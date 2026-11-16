// GitHub -> Discord: moves a forum post's status tag and posts a short note,
// driven by the workflow in .github/workflows/discord-status.yml.
// Only issues labeled `from-discord` (made by the bot) are ever touched.
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { STATUS, LABELS, MESSAGES, parseMarker, closingIssues, timedFetch } from '../src/core.js';
import { discordClient } from '../src/discord.js';
import { githubClient } from '../src/github.js';

const hasLabel = (issue, name) => (issue.labels || []).some((l) => (l.name || l) === name);
// The bot's own issues: the label and the marker it writes last.
const eligible = (issue) => hasLabel(issue, LABELS.fromDiscord) && parseMarker(issue.body) !== null;
// Only people with a role on the repo can move a post with a PR.
const TRUSTED = new Set(['OWNER', 'MEMBER', 'COLLABORATOR']);
const PR_EVENTS = new Set(['pull_request', 'pull_request_target']);
const CALL_MS = 15000;
const fixedInMarker = (sha) => `<!-- discord-fixed-in: ${sha} -->`;
// The account this workflow comments as (GITHUB_TOKEN). Only its fixed-in
// comments count: anyone can comment on a public issue.
const BOT_LOGIN = 'github-actions[bot]';

export async function run({ eventName, payload, env, fetchImpl = fetch, log = console.log }) {
  const repo = payload.repository.full_name;
  const f = timedFetch(fetchImpl, CALL_MS);
  const gh = githubClient(env.GITHUB_TOKEN, f);
  const discord = discordClient(env.DISCORD_BOT_TOKEN, f);
  const done = [];
  const failed = [];

  async function notify(issue, status, message, ping = []) {
    const m = parseMarker(issue.body);
    if (!m || !eligible(issue)) return false;
    if (status) {
      const r = await discord.setStatus(m.threadId, status);
      if (r.skipped) log(`#${issue.number}: ${r.skipped}`);
    } else {
      // A locked post does not unarchive on a new message; reopen it first.
      await discord.unarchive(m.threadId);
    }
    if (message) await discord.send(m.threadId, message, ping);
    done.push({ issue: issue.number, thread: m.threadId, status, message });
    return m;
  }

  // One issue's failure is logged and the rest still run; the job fails at the end.
  async function each(issues, fn) {
    for (const issue of issues) {
      try {
        await fn(issue);
      } catch (e) {
        log(`#${issue.number}: ${e.message}`);
        failed.push(issue.number);
      }
    }
  }

  // The fix commit the merged-PR step recorded on the issue (the newest one),
  // read from every page and only from this workflow's own comments.
  async function fixedIn(issue) {
    let sha = null;
    for (let page = 1; ; page++) {
      const batch = await gh.call('GET', `/repos/${repo}/issues/${issue.number}/comments?per_page=100&page=${page}`);
      for (const c of batch) {
        if (!c.user || c.user.login !== BOT_LOGIN) continue;
        const m = /<!--\s*discord-fixed-in:\s*([0-9a-f]{7,40})\s*-->/.exec(c.body || '');
        if (m) sha = m[1];
      }
      if (batch.length < 100) return sha;
    }
  }

  async function tagContains(sha, tag) {
    const r = await gh.call('GET', `/repos/${repo}/compare/${sha}...${encodeURIComponent(tag)}`);
    return r.status === 'ahead' || r.status === 'identical';
  }

  async function linkedIssues(pr) {
    const nums = closingIssues(`${pr.title}\n${pr.body || ''}`);
    const out = [];
    for (const n of nums) {
      const issue = await gh.getIssue(repo, n).catch(() => null);
      if (issue && !issue.pull_request) out.push(issue);
    }
    return out;
  }

  if (PR_EVENTS.has(eventName)) {
    const pr = payload.pull_request;
    const action = payload.action;
    if (['opened', 'reopened', 'ready_for_review'].includes(action)) {
      if (pr.draft) {
        log('draft PR: nothing to do until it is ready for review');
      } else if (!TRUSTED.has(pr.author_association)) {
        log(`PR author is ${pr.author_association || 'unknown'}, not a repo member: nothing to do`);
      } else {
        // A post already Fixed or Shipped does not go back to In progress.
        const open = (await linkedIssues(pr)).filter((i) => !hasLabel(i, LABELS.pendingRelease) && !hasLabel(i, LABELS.shipped));
        await each(open, (issue) => notify(issue, STATUS.inProgress, MESSAGES.inProgress()));
      }
    } else if (action === 'closed' && pr.merged && pr.base.ref === payload.repository.default_branch) {
      const fixed = (await linkedIssues(pr)).filter(eligible);
      await each(fixed, async (issue) => {
        // The commit first, then the label: a pending issue always has the
        // commit a release tag is checked against.
        if (pr.merge_commit_sha) {
          await gh.call('POST', `/repos/${repo}/issues/${issue.number}/comments`, {
            body: `Fixed in ${pr.merge_commit_sha}; ships with the first release tag that contains it.\n\n${fixedInMarker(pr.merge_commit_sha)}`,
          });
        }
        await gh.addLabels(repo, issue.number, [LABELS.pendingRelease]);
        // Fixed again after an earlier ship: it is pending, not shipped.
        if (hasLabel(issue, LABELS.shipped)) await gh.removeLabel(repo, issue.number, LABELS.shipped);
        await notify(issue, STATUS.fixed, MESSAGES.fixed());
      });
    }
  } else if (eventName === 'push' && String(payload.ref).startsWith('refs/tags/')) {
    const tag = payload.ref.slice('refs/tags/'.length);
    const pattern = new RegExp(env.RELEASE_TAG_PATTERN || '^v\\d');
    if (payload.deleted) {
      log(`tag ${tag} was deleted, nothing to do`);
    } else if (!pattern.test(tag)) {
      log(`tag ${tag} is not a release tag, nothing to do`);
    } else {
      const pending = (await gh.issuesWithLabel(repo, LABELS.pendingRelease)).filter(eligible);
      await each(pending, async (issue) => {
        // Both labels: an earlier ship stopped after telling the player.
        if (hasLabel(issue, LABELS.shipped)) {
          await gh.removeLabel(repo, issue.number, LABELS.pendingRelease);
          return;
        }
        // Ship only a fix this tag contains, so a rerun of an older tag, or a
        // tag cut before the fix merged, leaves it pending.
        const sha = await fixedIn(issue);
        if (sha && !(await tagContains(sha, tag))) {
          log(`#${issue.number}: fix ${sha.slice(0, 7)} is not in ${tag}, still pending`);
          return;
        }
        if (!sha) log(`#${issue.number}: no recorded fix commit (labeled by hand); shipping with ${tag}`);
        try {
          await notify(issue, STATUS.shipped, MESSAGES.shipped(repo, tag));
        } catch (e) {
          // A deleted post can never be told; ship the issue anyway so it
          // does not block every later tag.
          if (!/-> 404 /.test(e.message)) throw e;
          log(`#${issue.number}: Discord post is gone (${e.message.slice(0, 120)}); marking shipped anyway`);
        }
        // Add before remove: a failure in between leaves both labels, never none.
        await gh.addLabels(repo, issue.number, [LABELS.shipped]);
        await gh.removeLabel(repo, issue.number, LABELS.pendingRelease);
      });
    }
  } else if (eventName === 'issues') {
    const issue = payload.issue;
    if (payload.action === 'closed' && ['not_planned', 'duplicate'].includes(issue.state_reason)) {
      await notify(issue, STATUS.closed, MESSAGES.closed(issue.state_reason));
    } else if (payload.action === 'labeled' && payload.label && payload.label.name === LABELS.needsInfo) {
      const m = parseMarker(issue.body);
      await notify(issue, null, MESSAGES.needsInfo(m && m.reporterId), m && m.reporterId ? [m.reporterId] : []);
    }
  }

  log(done.length ? `updated ${done.length} Discord post(s)` : 'no Discord post to update');
  if (failed.length) throw new Error(`could not update issue(s) ${failed.map((n) => `#${n}`).join(', ')}; see above`);
  return done;
}

if (import.meta.url === pathToFileURL(process.argv[1] || '').href) {
  const payload = JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'));
  if (!process.env.DISCORD_BOT_TOKEN) {
    console.log('DISCORD_BOT_TOKEN is not set: skipping Discord updates');
  } else {
    run({ eventName: process.env.GITHUB_EVENT_NAME, payload, env: process.env }).catch((e) => {
      console.error(e);
      process.exit(1);
    });
  }
}
