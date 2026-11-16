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

  // Every fix commit the merged-PR step recorded on the issue, read from every
  // page and only from this workflow's own comments.
  async function fixesOf(issue) {
    const shas = new Set();
    for (let page = 1; ; page++) {
      const batch = await gh.call('GET', `/repos/${repo}/issues/${issue.number}/comments?per_page=100&page=${page}`);
      for (const c of batch) {
        if (!c.user || c.user.login !== BOT_LOGIN) continue;
        const m = /<!--\s*discord-fixed-in:\s*([0-9a-f]{7,40})\s*-->/.exec(c.body || '');
        if (m) shas.add(m[1]);
      }
      if (batch.length < 100) return [...shas];
    }
  }

  // `target` is the commit the tag event pushed (its `after`), not the tag's
  // name: a rerun of an old event must not see where the tag points today.
  async function tagContains(sha, target) {
    const r = await gh.call('GET', `/repos/${repo}/compare/${sha}...${encodeURIComponent(target)}`);
    return r.status === 'ahead' || r.status === 'identical';
  }

  // Removes `pending-release` once a tag holds every fix in `shas`, then reads
  // the records again: a merge that recorded a new fix while this ran may
  // already have added its label, which this removal just took away.
  async function dropPending(issue, shas, target, tag) {
    await gh.removeLabel(repo, issue.number, LABELS.pendingRelease);
    for (const sha of (await fixesOf(issue)).filter((s) => !shas.includes(s))) {
      if (await tagContains(sha, target)) continue;
      log(`#${issue.number}: fix ${sha.slice(0, 7)} merged during the ship and is not in ${tag}: pending again`);
      await gh.addLabels(repo, issue.number, [LABELS.pendingRelease]);
      await gh.removeLabel(repo, issue.number, LABELS.shipped);
      const m = parseMarker(issue.body);
      await discord.setStatus(m.threadId, STATUS.fixed).catch((e) => { if (!/-> 404 /.test(e.message)) throw e; });
      return;
    }
  }

  // Issues a PR says it closes. A number that is not an issue (404) is
  // skipped; any other read error fails the job at the end.
  async function linkedIssues(pr) {
    const nums = closingIssues(`${pr.title}\n${pr.body || ''}`);
    const out = [];
    for (const n of nums) {
      try {
        const issue = await gh.getIssue(repo, n);
        if (!issue.pull_request) out.push(issue);
      } catch (e) {
        if (/-> 404 /.test(e.message)) continue;
        log(`#${n}: ${e.message}`);
        failed.push(n);
      }
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
        // A post already Fixed or Shipped does not go back to In progress. The
        // labels are read again just before the write, in case a merge landed.
        const done = (i) => hasLabel(i, LABELS.pendingRelease) || hasLabel(i, LABELS.shipped);
        const open = (await linkedIssues(pr)).filter((i) => !done(i));
        await each(open, async (issue) => {
          const now = await gh.getIssue(repo, issue.number);
          if (done(now)) return;
          const m = await notify(now, STATUS.inProgress, MESSAGES.inProgress());
          // A merge or ship from another run may have landed while this one
          // wrote: read once more and put the later status back.
          const after = m ? await gh.getIssue(repo, issue.number) : null;
          if (after && hasLabel(after, LABELS.shipped)) await discord.setStatus(m.threadId, STATUS.shipped);
          else if (after && hasLabel(after, LABELS.pendingRelease)) await discord.setStatus(m.threadId, STATUS.fixed);
        });
      }
    } else if (action === 'closed' && pr.merged && pr.base.ref === payload.repository.default_branch) {
      const fixed = (await linkedIssues(pr)).filter(eligible);
      await each(fixed, async (issue) => {
        // Order matters so a rerun of this event (after success or a failure
        // partway) can tell what is left: drop `shipped`, record the commit,
        // add `pending-release`, tell the player.
        const recorded = pr.merge_commit_sha && (await fixesOf(issue)).includes(pr.merge_commit_sha);
        if (recorded && hasLabel(issue, LABELS.shipped)) {
          // `shipped` is dropped before the record is written, so this fix shipped since.
          log(`#${issue.number}: ${pr.merge_commit_sha.slice(0, 7)} already shipped, nothing to do`);
          return;
        }
        if (!recorded) {
          if (hasLabel(issue, LABELS.shipped)) await gh.removeLabel(repo, issue.number, LABELS.shipped);
          if (pr.merge_commit_sha) {
            await gh.call('POST', `/repos/${repo}/issues/${issue.number}/comments`, {
              body: `Fixed in ${pr.merge_commit_sha}; ships with the first release tag that contains it.\n\n${fixedInMarker(pr.merge_commit_sha)}`,
            });
          }
        }
        // Always added, even when the read showed it: a ship running now may be
        // about to remove it (see dropPending).
        await gh.addLabels(repo, issue.number, [LABELS.pendingRelease]);
        await notify(issue, STATUS.fixed, MESSAGES.fixed());
      });
    }
  } else if (eventName === 'push' && String(payload.ref).startsWith('refs/tags/')) {
    const tag = payload.ref.slice('refs/tags/'.length);
    const pattern = new RegExp(env.RELEASE_TAG_PATTERN || '^v\\d');
    if (payload.deleted || payload.created === false) {
      log(`tag ${tag} was deleted or moved, not created: nothing to do`);
    } else if (!pattern.test(tag)) {
      log(`tag ${tag} is not a release tag, nothing to do`);
    } else {
      const target = payload.after || tag;
      const pending = (await gh.issuesWithLabel(repo, LABELS.pendingRelease)).filter(eligible);
      await each(pending, async (issue) => {
        // Ship only when this tag contains every recorded fix, so a rerun of an
        // older tag, or a tag cut before a fix merged, leaves it pending. With
        // no record (labeled by hand by someone with write access) it ships.
        const shas = await fixesOf(issue);
        let inTag = true;
        for (const sha of shas) {
          if (!(await tagContains(sha, target))) {
            log(`#${issue.number}: fix ${sha.slice(0, 7)} is not in ${tag}, still pending`);
            inTag = false;
            break;
          }
        }
        // Both labels: a ship that stopped after telling the player (finish it
        // quietly), or a newer fix that raced a ship (it is pending again).
        if (hasLabel(issue, LABELS.shipped)) {
          if (inTag) await dropPending(issue, shas, target, tag);
          else await gh.removeLabel(repo, issue.number, LABELS.shipped);
          return;
        }
        if (!inTag) return;
        if (!shas.length) log(`#${issue.number}: no recorded fix commit (labeled by hand); shipping with ${tag}`);
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
        await dropPending(issue, shas, target, tag);
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
