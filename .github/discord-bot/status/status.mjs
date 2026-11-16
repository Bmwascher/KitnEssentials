// GitHub -> Discord: keeps each bot-made issue's release labels and its forum
// post's status tag equal to what the issue's state says, and tells the player
// when the post moves. Driven by .github/workflows/discord-status.yml.
//
// Nothing here steps a status along. Every run works out the whole state from
// the issue, its records and its open PRs, writes it, then reads again and
// rewrites until a read agrees: two runs racing on one issue end on the state
// of everything both wrote. The daily sweep repairs what a failed call left.
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { STATUS, LABELS, MESSAGES, parseMarker, timedFetch } from '../src/core.js';
import { discordClient } from '../src/discord.js';
import { githubClient } from '../src/github.js';

const hasLabel = (issue, name) => (issue.labels || []).some((l) => (l.name || l) === name);
// The bot's own issues: the label and the marker it writes last.
const eligible = (issue) => hasLabel(issue, LABELS.fromDiscord) && parseMarker(issue.body) !== null;
// Only PRs from people with a role on the repo move a post to In progress.
const TRUSTED = new Set(['OWNER', 'MEMBER', 'COLLABORATOR']);
const PR_EVENTS = new Set(['pull_request', 'pull_request_target']);
const CALL_MS = 15000;
const SETTLE_TRIES = 3;
// The account this workflow comments as (GITHUB_TOKEN). Only its records
// count: anyone can comment on a public issue.
const BOT_LOGIN = 'github-actions[bot]';
const RELEASE = [LABELS.pendingRelease, LABELS.shipped];

const fixedRecord = (sha) => `Fixed in ${sha}; ships with the first release tag that contains it.\n\n<!-- discord-fixed-in: ${sha} -->`;
const shippedRecord = (tag, shas) => `Shipped in ${tag}.\n\n<!-- discord-shipped-in: ${tag} fixes: ${shas.join(',')} -->`;

// The release state the records give: which fixes exist, which a release has
// covered, and the newest release that covered them.
export function releaseState(records) {
  const shipped = new Set();
  let lastTag = null;
  for (const s of records.shipped) {
    for (const sha of s.fixes) shipped.add(sha);
    lastTag = s.tag;
  }
  const waiting = records.fixes.filter((sha) => !shipped.has(sha));
  return { fixes: records.fixes, waiting, lastTag };
}

// The release labels an issue should carry.
export function wantedLabels(issue, records) {
  if (issue.state !== 'closed' || issue.state_reason !== 'completed') return [];
  const r = releaseState(records);
  if (!r.fixes.length) return [];
  return [r.waiting.length ? LABELS.pendingRelease : LABELS.shipped];
}

// The status tag a post should show (E1).
export function wantedStatus(issue, records, prs) {
  if (issue.state === 'closed') {
    if (issue.state_reason !== 'completed') return STATUS.closed;
    const r = releaseState(records);
    if (!r.fixes.length) return STATUS.closed;
    return r.waiting.length ? STATUS.fixed : STATUS.shipped;
  }
  const working = prs.some((p) => p.state === 'OPEN' && !p.isDraft && TRUSTED.has(p.authorAssociation));
  return working ? STATUS.inProgress : STATUS.triaged;
}

export async function run({ eventName, payload, env, fetchImpl = fetch, log = console.log }) {
  const repo = payload.repository.full_name;
  const [owner, name] = repo.split('/');
  const f = timedFetch(fetchImpl, CALL_MS);
  const gh = githubClient(env.GITHUB_TOKEN, f);
  const discord = discordClient(env.DISCORD_BOT_TOKEN, f);
  const done = [];
  const failed = [];

  async function graphql(query, variables) {
    const r = await gh.call('POST', '/graphql', { query, variables });
    if (r.errors && r.errors.length) throw new Error(`GitHub GraphQL: ${r.errors[0].message}`);
    return r.data;
  }

  // Open PRs that will close the issue: closing keywords and the
  // Development sidebar link alike.
  async function prsFor(n) {
    const d = await graphql(`query($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) { issue(number: $number) {
        closedByPullRequestsReferences(first: 25, includeClosedPrs: false) { nodes { isDraft state authorAssociation } } } } }`,
    { owner, name, number: n });
    return d.repository.issue.closedByPullRequestsReferences.nodes;
  }

  async function issuesClosedBy(prNumber) {
    const d = await graphql(`query($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) { pullRequest(number: $number) {
        closingIssuesReferences(first: 25) { nodes { number } } } } }`,
    { owner, name, number: prNumber });
    const pr = d.repository.pullRequest;
    return pr ? pr.closingIssuesReferences.nodes.map((n) => n.number) : [];
  }

  // Every record this workflow wrote on the issue, from every page.
  async function recordsOf(n) {
    const fixes = [];
    const shipped = [];
    for (let page = 1; ; page++) {
      const batch = await gh.call('GET', `/repos/${repo}/issues/${n}/comments?per_page=100&page=${page}`);
      for (const c of batch) {
        if (!c.user || c.user.login !== BOT_LOGIN) continue;
        const fx = /<!--\s*discord-fixed-in:\s*([0-9a-f]{7,40})\s*-->/.exec(c.body || '');
        if (fx && !fixes.includes(fx[1])) fixes.push(fx[1]);
        const sh = /<!--\s*discord-shipped-in:\s*(\S+)\s+fixes:\s*([0-9a-f,]*)\s*-->/.exec(c.body || '');
        if (sh) shipped.push({ tag: sh[1], fixes: sh[2].split(',').filter(Boolean) });
      }
      if (batch.length < 100) return { fixes, shipped };
    }
  }

  // The commit that closed the issue, from its newest `closed` event; null
  // when it was closed by hand.
  async function closingCommit(n) {
    let last = null;
    for (let page = 1; ; page++) {
      const batch = await gh.call('GET', `/repos/${repo}/issues/${n}/events?per_page=100&page=${page}`);
      for (const e of batch) if (e.event === 'closed') last = e;
      if (batch.length < 100) return last ? last.commit_id || null : null;
    }
  }

  async function tagContains(sha, target) {
    const r = await gh.call('GET', `/repos/${repo}/compare/${sha}...${encodeURIComponent(target)}`);
    return r.status === 'ahead' || r.status === 'identical';
  }

  // Write the release labels the records give, then read again; repeat while
  // another run's record changed the answer in between.
  async function settleLabels(n) {
    for (let i = 0; i < SETTLE_TRIES; i++) {
      const issue = await gh.getIssue(repo, n);
      const records = await recordsOf(n);
      const want = wantedLabels(issue, records);
      for (const l of want) if (!hasLabel(issue, l)) await gh.addLabels(repo, n, [l]);
      for (const l of RELEASE) if (!want.includes(l) && hasLabel(issue, l)) await gh.removeLabel(repo, n, l);
      const now = await gh.getIssue(repo, n);
      const again = wantedLabels(now, await recordsOf(n));
      const has = RELEASE.filter((l) => hasLabel(now, l));
      if (again.length === has.length && again.every((l) => has.includes(l))) return;
    }
    throw new Error(`#${n}: release labels did not settle after ${SETTLE_TRIES} tries`);
  }

  // Set the post's tag to what the issue says, then read again; repeat while
  // the answer moved. Returns the status it started from and ended on.
  async function settlePost(n) {
    let from = null;
    let to = null;
    let threadId = null;
    for (let i = 0; i < SETTLE_TRIES; i++) {
      const issue = await gh.getIssue(repo, n);
      if (!eligible(issue)) return null;
      threadId = parseMarker(issue.body).threadId;
      const want = wantedStatus(issue, await recordsOf(n), issue.state === 'open' ? await prsFor(n) : []);
      let r;
      try {
        r = await discord.setStatus(threadId, want);
      } catch (e) {
        // A deleted post can never be told; its issue still moves.
        if (!/-> 404 /.test(e.message)) throw e;
        log(`#${n}: Discord post is gone (${e.message.slice(0, 120)})`);
        return null;
      }
      if (r.skipped) log(`#${n}: ${r.skipped}`);
      if (from === null) from = r.from;
      to = want;
      const after = await gh.getIssue(repo, n);
      const again = wantedStatus(after, await recordsOf(n), after.state === 'open' ? await prsFor(n) : []);
      if (again === want) return { threadId, from, to, issue: after };
    }
    throw new Error(`#${n}: post status did not settle after ${SETTLE_TRIES} tries`);
  }

  // Tell the player when the post ended on a new status. Closed and Shipped
  // say why; Triaged (a PR went away) stays quiet.
  async function announce(n, moved) {
    if (!moved || moved.from === moved.to) return;
    let text = null;
    if (moved.to === STATUS.inProgress) text = MESSAGES.inProgress();
    else if (moved.to === STATUS.fixed) text = MESSAGES.fixed();
    else if (moved.to === STATUS.shipped) {
      const r = releaseState(await recordsOf(n));
      text = MESSAGES.shipped(repo, r.lastTag);
    } else if (moved.to === STATUS.closed) {
      text = moved.issue.state_reason === 'completed' ? MESSAGES.done() : MESSAGES.closed(moved.issue.state_reason);
    }
    if (!text) return;
    try {
      await discord.send(moved.threadId, text);
    } catch (e) {
      if (!/-> 404 /.test(e.message)) throw e;
    }
    done.push({ issue: n, thread: moved.threadId, status: moved.to, message: text });
  }

  async function sync(n) {
    await settleLabels(n);
    await announce(n, await settlePost(n));
  }

  // One issue's failure is logged and the rest still run; the job fails at the end.
  async function each(numbers, fn) {
    for (const n of numbers) {
      try {
        await fn(n);
      } catch (e) {
        log(`#${n}: ${e.message}`);
        failed.push(n);
      }
    }
  }

  async function botIssue(n) {
    const issue = await gh.getIssue(repo, n);
    return eligible(issue) ? issue : null;
  }

  if (PR_EVENTS.has(eventName)) {
    // Any change to a PR re-syncs the issues it will close. Whether the post
    // shows In progress depends on the PR's state and author (wantedStatus).
    const numbers = await issuesClosedBy(payload.pull_request.number);
    await each(numbers, async (n) => {
      if (await botIssue(n)) await sync(n);
    });
  } else if (eventName === 'push' && String(payload.ref).startsWith('refs/tags/')) {
    const tag = payload.ref.slice('refs/tags/'.length);
    const pattern = new RegExp(env.RELEASE_TAG_PATTERN || '^v\\d');
    // The tagged commit: for an annotated tag `after` is the tag object.
    const target = (payload.head_commit && payload.head_commit.id) || payload.after || tag;
    if (payload.deleted || payload.created === false) {
      log(`tag ${tag} was deleted or moved, not created: nothing to do`);
    } else if (!pattern.test(tag)) {
      log(`tag ${tag} is not a release tag, nothing to do`);
    } else {
      const pending = (await gh.issuesWithLabel(repo, LABELS.pendingRelease)).filter(eligible);
      await each(pending.map((i) => i.number), async (n) => {
        const records = await recordsOf(n);
        const r = releaseState(records);
        const already = records.shipped.some((s) => s.tag === tag);
        if (r.waiting.length && !already) {
          let all = true;
          for (const sha of r.fixes) {
            if (!(await tagContains(sha, target))) {
              log(`#${n}: fix ${sha.slice(0, 7)} is not in ${tag}, still pending`);
              all = false;
              break;
            }
          }
          if (all) {
            await gh.call('POST', `/repos/${repo}/issues/${n}/comments`, { body: shippedRecord(tag, r.fixes) });
          }
        }
        await sync(n);
      });
    }
  } else if (eventName === 'issues') {
    const n = payload.issue.number;
    if (payload.action === 'labeled' && payload.label && payload.label.name === LABELS.needsInfo) {
      const issue = await botIssue(n);
      const m = issue && parseMarker(issue.body);
      if (m) {
        // A locked post does not unarchive on a new message; reopen it first.
        await discord.unarchive(m.threadId);
        const text = MESSAGES.needsInfo(m.reporterId);
        await discord.send(m.threadId, text, m.reporterId ? [m.reporterId] : []);
        done.push({ issue: n, thread: m.threadId, message: text });
      }
    } else if (['closed', 'reopened'].includes(payload.action)) {
      await each([n], async () => {
        const issue = await botIssue(n);
        if (!issue) return;
        if (issue.state === 'closed' && issue.state_reason === 'completed') {
          // E2: a commit that closed the issue is its fix.
          const sha = await closingCommit(n);
          if (sha && !(await recordsOf(n)).fixes.includes(sha)) {
            await gh.call('POST', `/repos/${repo}/issues/${n}/comments`, { body: fixedRecord(sha) });
          }
        }
        await sync(n);
      });
    }
  } else if (eventName === 'schedule' || eventName === 'workflow_dispatch') {
    // E3: the sweep. Report mode lists what is wrong; fix mode writes it,
    // and neither tells anyone.
    const fix = env.SWEEP_MODE === 'fix';
    const issues = (await gh.issuesWithLabel(repo, LABELS.fromDiscord)).filter(eligible);
    let wrong = 0;
    await each(issues.map((i) => i.number), async (n) => {
      const issue = await gh.getIssue(repo, n);
      const records = await recordsOf(n);
      const want = wantedLabels(issue, records);
      const has = RELEASE.filter((l) => hasLabel(issue, l));
      const status = wantedStatus(issue, records, issue.state === 'open' ? await prsFor(n) : []);
      const threadId = parseMarker(issue.body).threadId;
      let shown = null;
      try {
        shown = await discord.statusOf(threadId);
      } catch (e) {
        if (!/-> 404 /.test(e.message)) throw e;
      }
      const labelsOk = want.length === has.length && want.every((l) => has.includes(l));
      const postOk = shown === null || shown === status;
      if (labelsOk && postOk) return;
      wrong++;
      const parts = [];
      if (!labelsOk) parts.push(`labels ${has.join(', ') || '(none)'} -> ${want.join(', ') || '(none)'}`);
      if (!postOk) parts.push(`post ${shown || '(no status)'} -> ${status}`);
      log(`#${n}: ${parts.join('; ')}`);
      if (fix) {
        await settleLabels(n);
        await settlePost(n);
      }
    });
    log(`sweep (${fix ? 'fix' : 'report'} mode): ${wrong} of ${issues.length} issue(s) out of step`);
  }

  log(done.length ? `told ${done.length} Discord post(s)` : 'no Discord post told');
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
