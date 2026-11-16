// GitHub -> Discord: moves a forum post's status tag and posts a short note,
// driven by the workflow in .github/workflows/discord-status.yml.
// Only issues labelled `from-discord` (made by the bot) are ever touched.
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { STATUS, LABELS, MESSAGES, parseMarker, closingIssues, keyForRepo } from '../src/core.js';
import { discordClient } from '../src/discord.js';
import { githubClient } from '../src/github.js';

const isFromDiscord = (issue) => (issue.labels || []).some((l) => (l.name || l) === LABELS.fromDiscord);

export async function run({ eventName, payload, env, fetchImpl = fetch, log = console.log }) {
  const repo = payload.repository.full_name;
  const repos = JSON.parse(env.REPOS || '{"AES":"atrocityzero/atrocityEssentials","AUI":"atrocityzero/atrocityUI"}');
  const repoKey = keyForRepo(repo, repos) || 'AES';
  const gh = githubClient(env.GITHUB_TOKEN, fetchImpl);
  const discord = discordClient(env.DISCORD_BOT_TOKEN, fetchImpl);
  const done = [];

  async function notify(issue, status, message, ping = []) {
    const m = parseMarker(issue.body);
    if (!m || !isFromDiscord(issue)) return false;
    if (status) {
      const r = await discord.setStatus(m.threadId, status);
      if (r.skipped) log(`#${issue.number}: ${r.skipped}`);
    }
    if (message) await discord.send(m.threadId, message, ping);
    done.push({ issue: issue.number, thread: m.threadId, status, message });
    return m;
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

  if (eventName === 'pull_request') {
    const pr = payload.pull_request;
    const action = payload.action;
    if (['opened', 'reopened', 'ready_for_review'].includes(action)) {
      for (const issue of await linkedIssues(pr)) await notify(issue, STATUS.inProgress, MESSAGES.inProgress());
    } else if (action === 'closed' && pr.merged && pr.base.ref === payload.repository.default_branch) {
      for (const issue of await linkedIssues(pr)) {
        if (!isFromDiscord(issue)) continue;
        await gh.addLabels(repo, issue.number, [LABELS.pendingRelease]);
        await notify(issue, STATUS.fixed, MESSAGES.fixed());
      }
    }
  } else if (eventName === 'push' && String(payload.ref).startsWith('refs/tags/')) {
    const tag = payload.ref.slice('refs/tags/'.length);
    const pattern = new RegExp(env.RELEASE_TAG_PATTERN || '^v\\d');
    if (!pattern.test(tag)) {
      log(`tag ${tag} is not a release tag, nothing to do`);
    } else {
      for (const issue of await gh.issuesWithLabel(repo, LABELS.pendingRelease)) {
        await notify(issue, STATUS.shipped, MESSAGES.shipped(repoKey, tag));
        await gh.removeLabel(repo, issue.number, LABELS.pendingRelease);
        await gh.addLabels(repo, issue.number, [LABELS.shipped]);
      }
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
