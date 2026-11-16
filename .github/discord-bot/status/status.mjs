// GitHub -> Discord: keeps each bot-made issue's release labels and its forum
// post's status tag equal to what the issue says, and tells the player when
// the post moves. Driven by .github/workflows/discord-status.yml.
//
// Nothing here steps a status along. Every run reads the whole state again:
//   - the fix is the commit that closed the issue (its newest `closed`
//     event), while the issue is closed as completed; reopening drops it;
//   - whether that fix shipped is a record a release run wrote on the issue
//     (`discord-shipped-in`), rebuilt from the release tags when missing;
//   - an open issue is In progress while a member's non-draft PR will close it.
// Each run writes the labels and the tag that state gives, then reads again
// and rewrites until a read agrees, so runs that overlap end on the state of
// everything both wrote. The daily sweep repairs what a failed call left.
import { readFileSync, appendFileSync } from 'node:fs';
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
// A tag run also looks at bot issues closed this recently, in case a close
// run has not labeled them yet.
const RECENT_MS = 24 * 60 * 60 * 1000;
// The account this workflow comments as (GITHUB_TOKEN). Only its records
// count: anyone can comment on a public issue.
const BOT_LOGIN = 'github-actions[bot]';
const RELEASE = [LABELS.pendingRelease, LABELS.shipped];
// Lists are followed this many pages (100 each) at most.
const MAX_PAGES = 10;
// A message note older than this that was never marked sent is listed.
const OWED_MS = 10 * 60 * 1000;

const shipRecord = (tag, sha) => `Shipped in ${tag}.\n\n<!-- discord-shipped-in: ${tag} fixes: ${sha} -->`;
// Written just before a message to the player. Of two runs about to send
// the same message, only the one whose note came first sends it. The note is
// marked sent after the send, or dropped when the message went stale first;
// the sweep lists a note left neither.
const toldRecord = (key, text, status) => `Told the player: ${text}\n\n<!-- discord-told: ${key} -->`
  + (status ? `\n<!-- discord-told-status: ${status} -->` : '');

// The release labels an issue should carry.
export function wantedLabels(st) {
  if (!st.fix) return [];
  return [st.shippedIn ? LABELS.shipped : LABELS.pendingRelease];
}

// The status tag a post should show (E1).
export function wantedStatus(st, prs) {
  const { issue } = st;
  if (issue.state === 'closed') {
    if (issue.state_reason !== 'completed' || !st.fix) return STATUS.closed;
    return st.shippedIn ? STATUS.shipped : STATUS.fixed;
  }
  const working = prs.some((p) => p.state === 'OPEN' && !p.isDraft && TRUSTED.has(p.authorAssociation));
  return working ? STATUS.inProgress : STATUS.triaged;
}

export async function run({ eventName, payload, env, fetchImpl = fetch, log = console.log, now = Date.now }) {
  // A scheduled run's payload names no repository; Actions sets GITHUB_REPOSITORY.
  const repo = (payload.repository && payload.repository.full_name) || env.GITHUB_REPOSITORY;
  const [owner, name] = repo.split('/');
  const pattern = new RegExp(env.RELEASE_TAG_PATTERN || '^v\\d');
  const f = timedFetch(fetchImpl, CALL_MS);
  const gh = githubClient(env.GITHUB_TOKEN, f);
  const discord = discordClient(env.DISCORD_BOT_TOKEN, f);
  const done = [];
  const failed = [];
  const report = [];

  async function graphql(query, variables) {
    const r = await gh.call('POST', '/graphql', { query, variables });
    if (r.errors && r.errors.length) throw new Error(`GitHub GraphQL: ${r.errors[0].message}`);
    return r.data;
  }

  // Every node of a GraphQL connection, page by page.
  async function connection(query, variables, pick) {
    const out = [];
    let after = null;
    for (let i = 0; i < MAX_PAGES; i++) {
      const conn = pick(await graphql(query, { ...variables, after }));
      if (!conn) return out;
      out.push(...conn.nodes);
      if (!conn.pageInfo || !conn.pageInfo.hasNextPage) return out;
      after = conn.pageInfo.endCursor;
    }
    throw new Error(`more than ${MAX_PAGES * 100} linked items: too many to read`);
  }

  // Open PRs that will close the issue: closing keywords and the
  // Development sidebar link alike.
  async function prsFor(n) {
    return connection(`query($owner: String!, $name: String!, $number: Int!, $after: String) {
      repository(owner: $owner, name: $name) { issue(number: $number) {
        closedByPullRequestsReferences(first: 100, after: $after, includeClosedPrs: false) {
          pageInfo { hasNextPage endCursor } nodes { isDraft state authorAssociation } } } } }`,
    { owner, name, number: n }, (d) => d.repository.issue.closedByPullRequestsReferences);
  }

  // This repo's issues a PR will close.
  async function issuesClosedBy(prNumber) {
    const nodes = await connection(`query($owner: String!, $name: String!, $number: Int!, $after: String) {
      repository(owner: $owner, name: $name) { pullRequest(number: $number) {
        closingIssuesReferences(first: 100, after: $after) {
          pageInfo { hasNextPage endCursor } nodes { number repository { nameWithOwner } } } } } }`,
    { owner, name, number: prNumber }, (d) => d.repository.pullRequest && d.repository.pullRequest.closingIssuesReferences);
    return nodes
      .filter((x) => !x.repository || x.repository.nameWithOwner.toLowerCase() === repo.toLowerCase())
      .map((x) => x.number);
  }

  // Every item of a REST list, page by page, until `stop` finds one.
  async function listPages(path, stop = () => false) {
    const out = [];
    for (let page = 1; page <= MAX_PAGES; page++) {
      const batch = await gh.call('GET', `${path}${path.includes('?') ? '&' : '?'}per_page=100&page=${page}`);
      out.push(...batch);
      if (batch.length < 100 || batch.some(stop)) return out;
    }
    throw new Error(`${path}: more than ${MAX_PAGES * 100} items, too many to read`);
  }

  // The workflow's records on the issue, from every page: releases that
  // shipped a fix, and messages already told.
  async function recordsOf(n) {
    const shipped = [];
    const told = [];
    for (let page = 1; ; page++) {
      const batch = await gh.call('GET', `/repos/${repo}/issues/${n}/comments?per_page=100&page=${page}`);
      for (const c of batch) {
        if (!c.user || c.user.login !== BOT_LOGIN) continue;
        const sh = /<!--\s*discord-shipped-in:\s*(\S+)\s+fixes:\s*([0-9a-f,]*)\s*-->/.exec(c.body || '');
        if (sh) shipped.push({ tag: sh[1], fixes: sh[2].split(',').filter(Boolean) });
        const tl = /<!--\s*discord-told:\s*(\S+)\s*-->/.exec(c.body || '');
        if (tl) {
          const body = c.body || '';
          told.push({
            key: tl[1], id: c.id, body,
            text: (/^Told the player: ([\s\S]*?)\n\n<!--/.exec(body) || [])[1] || '',
            status: (/<!--\s*discord-told-status:\s*(.+?)\s*-->/.exec(body) || [])[1] || null,
            settled: /<!--\s*discord-(sent|dropped)\s*-->/.test(body),
            at: Date.parse(c.created_at) || 0,
          });
        }
      }
      if (batch.length < 100) return { shipped, told };
    }
  }

  // The issue's newest `closed` event: its id, and its commit when that
  // commit is in this repo (a commit elsewhere can close it, but cannot be
  // compared with this repo's tags). GitHub closes an issue from a commit
  // only when the commit reaches the default branch.
  async function lastClose(n) {
    let last = null;
    for (let page = 1; ; page++) {
      const batch = await gh.call('GET', `/repos/${repo}/issues/${n}/events?per_page=100&page=${page}`);
      for (const e of batch) if (e.event === 'closed') last = e;
      if (batch.length < 100) break;
    }
    if (!last) return null;
    const here = last.commit_id && (!last.commit_url || String(last.commit_url).includes(`/repos/${repo}/commits/`));
    return { id: last.id, sha: here ? last.commit_id : null };
  }

  async function stateOf(n) {
    const issue = await gh.getIssue(repo, n);
    const closedDone = issue.state === 'closed' && issue.state_reason === 'completed';
    const close = issue.state === 'closed' ? await lastClose(n) : null;
    const fix = closedDone && close && close.sha ? close.sha : null;
    const records = await recordsOf(n);
    const ship = fix ? records.shipped.find((s) => s.fixes.includes(fix)) : null;
    return { issue, close, fix, shippedIn: ship ? ship.tag : null, records };
  }

  async function tagContains(sha, target) {
    const r = await gh.call('GET', `/repos/${repo}/compare/${sha}...${encodeURIComponent(target)}`);
    return r.status === 'ahead' || r.status === 'identical';
  }

  // A fix whose ship record is missing (a write that failed, or an issue
  // shipped before these records existed): the first release tag on the
  // first page that holds it. Writes the record when `write` is set.
  async function recoverShip(n, sha, write) {
    for (let page = 1; page <= MAX_PAGES; page++) {
      const batch = await gh.call('GET', `/repos/${repo}/tags?per_page=100&page=${page}`);
      for (const t of batch.filter((x) => pattern.test(x.name))) {
        if (await tagContains(sha, t.commit && t.commit.sha ? t.commit.sha : t.name)) {
          if (write) await gh.call('POST', `/repos/${repo}/issues/${n}/comments`, { body: shipRecord(t.name, sha) });
          return t.name;
        }
      }
      if (batch.length < 100) return null;
    }
    // A release may sit further back: fail rather than take "not shipped" as the answer.
    throw new Error(`#${n}: more than ${MAX_PAGES * 100} tags, too many to read`);
  }

  // Write the release labels the state gives, then read again; repeat while
  // another run's write changed the answer in between.
  async function settleLabels(n) {
    for (let i = 0; i < SETTLE_TRIES; i++) {
      let st = await stateOf(n);
      // An issue labeled shipped with no record of it is checked against the
      // release tags before it is turned back to pending.
      if (st.fix && !st.shippedIn && hasLabel(st.issue, LABELS.shipped) && (await recoverShip(n, st.fix, true))) {
        st = await stateOf(n);
      }
      const want = wantedLabels(st);
      for (const l of want) if (!hasLabel(st.issue, l)) await gh.addLabels(repo, n, [l]);
      for (const l of RELEASE) if (!want.includes(l) && hasLabel(st.issue, l)) await gh.removeLabel(repo, n, l);
      const now = await stateOf(n);
      const again = wantedLabels(now);
      const has = RELEASE.filter((l) => hasLabel(now.issue, l));
      if (again.length === has.length && again.every((l) => has.includes(l))) return now;
    }
    throw new Error(`#${n}: release labels did not settle after ${SETTLE_TRIES} tries`);
  }

  // Set the post's tag to what the issue says, then read again; repeat while
  // the answer moved. Returns where the post started and ended.
  async function settlePost(n) {
    let from = null;
    for (let i = 0; i < SETTLE_TRIES; i++) {
      const st = await stateOf(n);
      if (!eligible(st.issue)) return null;
      const threadId = parseMarker(st.issue.body).threadId;
      const want = wantedStatus(st, st.issue.state === 'open' ? await prsFor(n) : []);
      let r;
      try {
        r = await discord.setStatus(threadId, want);
      } catch (e) {
        // A deleted post can never be told; its issue still moves.
        if (!/-> 404 /.test(e.message)) throw e;
        log(`#${n}: Discord post is gone (${e.message.slice(0, 120)})`);
        return null;
      }
      if (from === null) from = r.from;
      if (r.skipped) {
        // The forum has no such tag: the post did not move.
        log(`#${n}: ${r.skipped}`);
        return { n, threadId, from, to: from, st };
      }
      const after = await stateOf(n);
      const again = wantedStatus(after, after.issue.state === 'open' ? await prsFor(n) : []);
      if (again === want) return { n, threadId, from, to: want, st: after };
    }
    throw new Error(`#${n}: post status did not settle after ${SETTLE_TRIES} tries`);
  }

  async function sync(n) {
    await settleLabels(n);
    return settlePost(n);
  }

  // Write a message note and return it when this run's note is the first
  // with that key; otherwise another run owns the message.
  async function claim(n, key, text, status) {
    const body = toldRecord(key, text, status);
    const mine = await gh.call('POST', `/repos/${repo}/issues/${n}/comments`, { body });
    const first = (await recordsOf(n)).told.find((t) => t.key === key);
    if (first && mine && first.id !== mine.id) return null;
    return { id: mine && mine.id, body };
  }

  const settleNote = (note, how) => gh.call('PATCH', `/repos/${repo}/issues/comments/${note.id}`, { body: `${note.body}\n<!-- discord-${how} -->` });

  // Send a claimed message, then mark its note sent. A failed send leaves the
  // note open, for the sweep.
  async function deliver(n, threadId, note, text, status, ping = []) {
    try {
      await discord.send(threadId, text, ping);
    } catch (e) {
      if (!/-> 404 /.test(e.message)) throw e;
      log(`#${n}: Discord post is gone; message dropped`);
      await settleNote(note, 'dropped');
      return;
    }
    await settleNote(note, 'sent');
    done.push({ issue: n, thread: threadId, status, message: text });
  }

  // Tell the player, once, when the post ended on `status`. The key names
  // the change; a rerun or an overlapping run with the same key stays quiet.
  async function tell(moved, status, key, text) {
    if (!moved || moved.to !== status || moved.from === status) return;
    const note = await claim(moved.n, key, text, status);
    if (!note) return;
    // Another run may have moved the issue on since this one settled it; that
    // run tells its own news. The fact must still hold, not just the status.
    const st = await stateOf(moved.n);
    const nowStatus = wantedStatus(st, st.issue.state === 'open' ? await prsFor(moved.n) : []);
    const still = nowStatus === status && (await messageFor(moved.n, st, status));
    if (!still || still.key !== key) {
      await settleNote(note, 'dropped');
      return;
    }
    await deliver(moved.n, moved.threadId, note, text, status);
  }

  // The message for a post showing `status`, keyed by the fact it tells,
  // or null when that status has none.
  async function messageFor(n, st, status) {
    if (status === STATUS.fixed && st.fix) return { key: `fixed-${st.fix}`, text: MESSAGES.fixed() };
    if (status === STATUS.shipped && st.fix && st.shippedIn) {
      return { key: `shipped-${st.shippedIn.replace(/[^\w.-]/g, '')}-${st.fix}`, text: MESSAGES.shipped(repo, st.shippedIn) };
    }
    if (status === STATUS.closed && st.close) {
      const reason = st.issue.state_reason;
      return { key: `closed-${st.close.id}`, text: reason === 'completed' ? MESSAGES.done() : MESSAGES.closed(reason) };
    }
    if (status === STATUS.inProgress) {
      // Once per time the issue is open: a second PR, or a PR back from
      // draft, says nothing new.
      const close = await lastClose(n);
      return { key: `in-progress-after-${close ? close.id : 'none'}`, text: MESSAGES.inProgress() };
    }
    return null;
  }

  // Tell the player about the status a run moved the post to, whichever run
  // it is. Each key comes from the issue's state, so every run that sees the
  // same change claims the same note and only one sends.
  async function announce(moved) {
    if (!moved || moved.to === moved.from) return;
    const m = await messageFor(moved.n, moved.st, moved.to);
    if (m) await tell(moved, moved.to, m.key, m.text);
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
    // Closed issues belong to the close run (E2).
    const pr = payload.pull_request;
    const numbers = await issuesClosedBy(pr.number);
    await each(numbers, async (n) => {
      const issue = await botIssue(n);
      if (!issue || issue.state !== 'open') return;
      await announce(await sync(n));
    });
  } else if (eventName === 'push' && String(payload.ref).startsWith('refs/tags/')) {
    const tag = payload.ref.slice('refs/tags/'.length);
    // The tagged commit: for an annotated tag `after` is the tag object.
    const target = (payload.head_commit && payload.head_commit.id) || payload.after || tag;
    if (payload.deleted || payload.created === false) {
      log(`tag ${tag} was deleted or moved, not created: nothing to do`);
    } else if (!pattern.test(tag)) {
      log(`tag ${tag} is not a release tag, nothing to do`);
    } else {
      const since = new Date(now() - RECENT_MS).toISOString();
      const recent = await listPages(`/repos/${repo}/issues?state=closed&labels=${encodeURIComponent(LABELS.fromDiscord)}&since=${since}`);
      const pending = await gh.issuesWithLabel(repo, LABELS.pendingRelease);
      const numbers = [...new Set([...pending, ...recent].filter((i) => !i.pull_request && eligible(i)).map((i) => i.number))];
      await each(numbers, async (n) => {
        for (let i = 0; i < SETTLE_TRIES; i++) {
          const st = await stateOf(n);
          if (st.fix && !st.shippedIn) {
            if (await tagContains(st.fix, target)) {
              await gh.call('POST', `/repos/${repo}/issues/${n}/comments`, { body: shipRecord(tag, st.fix) });
            } else {
              log(`#${n}: fix ${st.fix.slice(0, 7)} is not in ${tag}, still pending`);
            }
          }
          const moved = await sync(n);
          await announce(moved);
          // A new fix that closed the issue meanwhile gets its own check.
          const after = moved ? moved.st : await stateOf(n);
          if (!after.fix || after.fix === st.fix || after.shippedIn) return;
        }
      });
    }
  } else if (eventName === 'issues') {
    const n = payload.issue.number;
    if (payload.action === 'labeled' && payload.label && payload.label.name === LABELS.needsInfo) {
      const issue = await botIssue(n);
      // A label taken off before this run started asks for nothing.
      const m = issue && hasLabel(issue, LABELS.needsInfo) && parseMarker(issue.body);
      if (m) {
        const text = MESSAGES.needsInfo(m.reporterId);
        // One ping per labeling: a rerun of the event finds the note.
        const note = await claim(n, `needs-info-${String(payload.issue.updated_at || 'once').replace(/\W/g, '')}`, text, null);
        if (note && !hasLabel(await gh.getIssue(repo, n), LABELS.needsInfo)) {
          await settleNote(note, 'dropped');
        } else if (note) {
          // A locked post does not unarchive on a new message; reopen it first.
          await discord.unarchive(m.threadId);
          await deliver(n, m.threadId, note, text, null, m.reporterId ? [m.reporterId] : []);
        }
      }
    } else if (['closed', 'reopened'].includes(payload.action)) {
      await each([n], async () => {
        if (!(await botIssue(n))) return;
        await announce(await sync(n));
      });
    }
  } else if (eventName === 'schedule' || eventName === 'workflow_dispatch') {
    // E3: the sweep. Report mode lists what is wrong; fix mode writes it,
    // and neither tells anyone.
    const fix = env.SWEEP_MODE === 'fix';
    const issues = (await gh.issuesWithLabel(repo, LABELS.fromDiscord)).filter(eligible);
    let wrong = 0;
    await each(issues.map((i) => i.number), async (n) => {
      let st = await stateOf(n);
      const parts = [];
      // Only an issue labeled shipped can have lost its record; a pending fix
      // waits for the next release tag.
      if (st.fix && !st.shippedIn && hasLabel(st.issue, LABELS.shipped)) {
        const held = await recoverShip(n, st.fix, fix);
        if (held) {
          parts.push(`ship record missing (${held} holds the fix)`);
          if (fix) st = await stateOf(n);
          else st = { ...st, shippedIn: held };
        }
      }
      const want = wantedLabels(st);
      const has = RELEASE.filter((l) => hasLabel(st.issue, l));
      const status = wantedStatus(st, st.issue.state === 'open' ? await prsFor(n) : []);
      const threadId = parseMarker(st.issue.body).threadId;
      let shown;
      try {
        shown = await discord.statusOf(threadId);
      } catch (e) {
        if (!/-> 404 /.test(e.message)) throw e;
        shown = undefined; // the post is gone
      }
      if (!(want.length === has.length && want.every((l) => has.includes(l)))) {
        parts.push(`labels ${has.join(', ') || '(none)'} -> ${want.join(', ') || '(none)'}`);
      }
      if (shown !== undefined && shown !== status) parts.push(`post ${shown || '(no status)'} -> ${status}`);
      // A claimed message never marked sent or dropped: its send failed.
      // Listed for a person to judge; the sweep never messages anyone.
      const seen = new Set();
      for (const t of st.records.told) {
        if (seen.has(t.key)) continue;
        seen.add(t.key);
        if (!t.settled && now() - t.at > OWED_MS) parts.push(`message "${t.text}" may not have been sent`);
      }
      if (!parts.length) return;
      wrong++;
      const line = `#${n}: ${parts.join('; ')}`;
      log(line);
      report.push(line);
      if (fix) await sync(n);
    });
    const head = `sweep (${fix ? 'fix' : 'report'} mode): ${wrong} of ${issues.length} issue(s) out of step`;
    log(head);
    if (env.GITHUB_STEP_SUMMARY) {
      appendFileSync(env.GITHUB_STEP_SUMMARY, [`### Discord status ${head}`, '', ...report.map((l) => `- ${l}`), ''].join('\n'));
    }
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
