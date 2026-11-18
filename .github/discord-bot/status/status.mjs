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
import { STATUS, LABELS, MESSAGES, parseMarker, parseFiledMessage, timedFetch, isRelease, DEFAULT_RELEASE_PATTERN } from '../src/core.js';
import { discordClient, postGone } from '../src/discord.js';
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
// A note with no run to ask about (the older `Told the player` form, or one
// from a run without an id) is judged once it is this old.
const OWED_MS = 10 * 60 * 1000;
// GitHub allows a run to be re-run for this long after its first attempt,
// and this many times.
const RERUN_MS = 30 * 24 * 60 * 60 * 1000;
const MAX_RERUNS = 50;

const shipRecord = (tag, sha) => `Shipped in ${tag}.\n\n<!-- discord-shipped-in: ${tag} fixes: ${sha} -->`;
// A note for each message to the player, written before the post's tag
// moves, so a move that fails leaves the message owed. Of two runs about to
// send the same message, only the one whose note came first sends it. The
// first line says what became of the message; the hidden lines name it, the
// status it announces and the run that wrote it, so a re-run of that run can
// still send it.
const noteRecord = (key, text, status, runId) => `Notification attempted: ${text}\n\n<!-- discord-told: ${key} -->`
  + (status ? `\n<!-- discord-told-status: ${status} -->` : '')
  + (runId ? `\n<!-- discord-told-run: ${runId} -->` : '');
// A note's message, under any of its first lines (`Told the player` is the older form).
const NOTE_TEXT = /^(?:Told the player|Notification attempted|Delivery confirmed|Dropped \([^)\n]*\)|Unconfirmed \([^)\n]*\)): ([\s\S]*?)\n\n<!--/;
const UNCONFIRMED = 'Unconfirmed (the send failed; the player may not have it)';

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
  const pattern = new RegExp(env.RELEASE_TAG_PATTERN || DEFAULT_RELEASE_PATTERN);
  // A re-run of a workflow run keeps its id, so it can still send what the
  // run owes.
  const runId = env.GITHUB_RUN_ID || null;
  const attempt = Number(env.GITHUB_RUN_ATTEMPT) || 1;
  const runUrl = (id) => `${env.GITHUB_SERVER_URL || 'https://github.com'}/${repo}/actions/runs/${id}`;
  const f = timedFetch(fetchImpl, CALL_MS);
  const gh = githubClient(env.GITHUB_TOKEN, f);
  const discord = discordClient(env.DISCORD_BOT_TOKEN, f);
  const done = [];
  const failed = [];
  const report = [];
  if (runId) log(`workflow run ${runId}, attempt ${attempt}`);

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
  // shipped a fix, and the notes of messages to the player.
  async function recordsOf(n) {
    const shipped = [];
    const told = [];
    for (let page = 1; ; page++) {
      const batch = await gh.call('GET', `/repos/${repo}/issues/${n}/comments?per_page=100&page=${page}`);
      for (const c of batch) {
        if (!c.user || c.user.login !== BOT_LOGIN) continue;
        // A body edited in the browser comes back with CRLF line ends.
        const body = (c.body || '').replace(/\r\n?/g, '\n');
        const sh = /<!--\s*discord-shipped-in:\s*(\S+)\s+fixes:\s*([0-9a-f,]*)\s*-->/.exec(body);
        if (sh) shipped.push({ tag: sh[1], fixes: sh[2].split(',').filter(Boolean) });
        const tl = /<!--\s*discord-told:\s*(\S+)\s*-->/.exec(body);
        if (tl) {
          // The last outcome mark wins: a moderator may mark a listed note by hand.
          const marks = [...body.matchAll(/<!--\s*discord-(sent|dropped|unconfirmed|sending)\s*-->/g)];
          told.push({
            key: tl[1], id: c.id, url: c.html_url || '', body,
            text: (NOTE_TEXT.exec(body) || [])[1] || '',
            status: (/<!--\s*discord-told-status:\s*(.+?)\s*-->/.exec(body) || [])[1] || null,
            run: (/<!--\s*discord-told-run:\s*(\S+)\s*-->/.exec(body) || [])[1] || null,
            state: marks.length ? marks[marks.length - 1][1] : 'attempted',
            // The older `Told the player` form, marked sent only after its send.
            legacy: /^Told the player: /.test(body),
            // Dropped by the bot before any send, and marked by no one else:
            // its message was never sent and can be claimed again.
            released: /^Dropped \(/.test(body) && marks.length === 1 && marks[0][1] === 'dropped',
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
  // only when the commit reaches the default branch. `wantFix` is set only
  // for a close as completed, the one kind whose fix is used.
  async function lastClose(n, wantFix = false) {
    let last = null;
    for (let page = 1; ; page++) {
      const batch = await gh.call('GET', `/repos/${repo}/issues/${n}/events?per_page=100&page=${page}`);
      for (const e of batch) if (e.event === 'closed') last = e;
      if (batch.length < 100) break;
    }
    if (!last) return null;
    const here = last.commit_id && (!last.commit_url || String(last.commit_url).includes(`/repos/${repo}/commits/`));
    if (here) return { id: last.id, sha: last.commit_id };
    return { id: last.id, sha: wantFix && !last.commit_id ? await closerSha(n) : null };
  }

  // A merged PR closes its issues with a `closed` event that carries no
  // commit; GraphQL names the closer instead. The
  // newest ClosedEvent's closer: a merged PR's merge commit, or a commit,
  // when it belongs to this repo.
  async function closerSha(n) {
    const data = await graphql(`query($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) { issue(number: $number) {
        timelineItems(itemTypes: [CLOSED_EVENT], last: 1) { nodes { ... on ClosedEvent { closer {
          __typename
          ... on PullRequest { merged mergeCommit { oid } repository { nameWithOwner } }
          ... on Commit { oid repository { nameWithOwner } }
        } } } }
      } }
    }`, { owner, name, number: n });
    const issue = data && data.repository && data.repository.issue;
    const node = issue && issue.timelineItems && issue.timelineItems.nodes[0];
    const c = node && node.closer;
    if (!c || !c.repository || String(c.repository.nameWithOwner).toLowerCase() !== repo.toLowerCase()) return null;
    if (c.__typename === 'PullRequest') return c.merged && c.mergeCommit ? c.mergeCommit.oid : null;
    if (c.__typename === 'Commit') return c.oid || null;
    return null;
  }

  async function stateOf(n) {
    const issue = await gh.getIssue(repo, n);
    const closedDone = issue.state === 'closed' && issue.state_reason === 'completed';
    const close = issue.state === 'closed' ? await lastClose(n, issue.state_reason === 'completed') : null;
    const fix = closedDone && close && close.sha ? close.sha : null;
    const records = await recordsOf(n);
    const ship = fix ? records.shipped.find((s) => s.fixes.includes(fix)) : null;
    return { issue, close, fix, shippedIn: ship ? ship.tag : null, records };
  }

  async function tagContains(sha, target) {
    const r = await gh.call('GET', `/repos/${repo}/compare/${sha}...${encodeURIComponent(target)}`);
    return r.status === 'ahead' || r.status === 'identical';
  }

  // The release that first shipped a fix with no ship record (a close that
  // came after its release run read its lists, a record write that failed, an
  // issue shipped before these records existed). Release tags lie on one line
  // of history, so walking them newest first, by the tagged commit's date,
  // the first one that does not hold the fix ends the walk, and the oldest
  // that held it is the release. Writes the record when `write` is set.
  async function releaseHolding(n, sha, write) {
    let held = null;
    let after = null;
    const finish = async () => {
      if (held && write) await gh.call('POST', `/repos/${repo}/issues/${n}/comments`, { body: shipRecord(held, sha) });
      return held;
    };
    for (let page = 0; page < MAX_PAGES; page++) {
      const data = await graphql(`query($owner: String!, $name: String!, $after: String) {
        repository(owner: $owner, name: $name) {
          refs(refPrefix: "refs/tags/", first: 100, after: $after, orderBy: {field: TAG_COMMIT_DATE, direction: DESC}) {
            pageInfo { hasNextPage endCursor }
            nodes { name target { __typename oid ... on Tag { target { oid } } } } } } }`, { owner, name, after });
      const refs = data.repository.refs;
      for (const ref of refs.nodes) {
        if (!isRelease(ref.name, pattern)) continue;
        const commit = ref.target.__typename === 'Tag' ? ref.target.target.oid : ref.target.oid;
        if (!(await tagContains(sha, commit))) return finish();
        held = ref.name;
      }
      if (!refs.pageInfo || !refs.pageInfo.hasNextPage) return finish();
      after = refs.pageInfo.endCursor;
    }
    // A release may sit further back: fail rather than take "not shipped" as the answer.
    throw new Error(`#${n}: more than ${MAX_PAGES * 100} tags, too many to read`);
  }

  // The issue's state, after checking a fix with no ship record against the
  // releases: its close may have come after the release run read its lists,
  // a record write may have failed, or a release may have been tagged while
  // this run worked. Checked afresh on every read, so no earlier answer goes
  // stale.
  async function releasedState(n) {
    const st = await stateOf(n);
    if (!st.fix || st.shippedIn) return st;
    if (await releaseHolding(n, st.fix, true)) return stateOf(n);
    return st;
  }

  // Write the release labels the state gives, then read again; repeat while
  // another run's write changed the answer in between.
  async function settleLabels(n) {
    for (let i = 0; i < SETTLE_TRIES; i++) {
      const st = await releasedState(n);
      const want = wantedLabels(st);
      for (const l of want) if (!hasLabel(st.issue, l)) await gh.addLabels(repo, n, [l]);
      for (const l of RELEASE) if (!want.includes(l) && hasLabel(st.issue, l)) await gh.removeLabel(repo, n, l);
      // Checked against the releases again: one may have been tagged while
      // the labels were written.
      const now = await releasedState(n);
      const again = wantedLabels(now);
      const has = RELEASE.filter((l) => hasLabel(now.issue, l));
      if (again.length === has.length && again.every((l) => has.includes(l))) return now;
    }
    throw new Error(`#${n}: release labels did not settle after ${SETTLE_TRIES} tries`);
  }

  // Rewrite a note's first line to say what became of its message, and mark it.
  async function settleNote(note, outcome, reason) {
    const head = outcome === 'sent' ? 'Delivery confirmed' : outcome === 'unconfirmed' ? UNCONFIRMED : `Dropped (${reason})`;
    const hidden = note.body.slice(note.body.indexOf('\n\n<!--'));
    await gh.call('PATCH', `/repos/${repo}/issues/comments/${note.id}`, { body: `${head}: ${note.text}${hidden}\n<!-- discord-${outcome} -->` });
  }

  // A note's body as it is now, or null once anything marked it (a re-run, a
  // sweep, a moderator) or it was deleted. A note is read again just before it
  // is sent or dropped, so no write lands on a newer outcome.
  async function unmarked(note) {
    let cur;
    try {
      cur = await gh.call('GET', `/repos/${repo}/issues/comments/${note.id}`);
    } catch (e) {
      if (/-> 404 /.test(e.message)) return null;
      throw e;
    }
    const body = ((cur && cur.body) || '').replace(/\r\n?/g, '\n');
    return /<!--\s*discord-(sent|dropped|unconfirmed|sending)\s*-->/.test(body) ? null : body;
  }

  async function dropNote(note, reason) {
    const body = await unmarked(note);
    if (body === null) return;
    note.body = body;
    await settleNote(note, 'dropped', reason);
  }

  // The note that owns a message. A note the bot dropped before any send, and
  // no one marked since, gives it up: when the same news comes true again, a
  // new note is written for it. A note a moderator marked keeps it for good.
  const owningNote = (told, key) => told.find((t) => t.key === key && !t.released);

  // The note for a message. A note already made for this key owns it: this
  // run takes it over only with `adopt`, when it is this run's own note from
  // an earlier attempt and was never sent (a re-run). Otherwise this run
  // writes a note, and of two runs writing at once the later drops its own.
  async function claim(n, key, text, status, adopt = false) {
    const existing = owningNote((await recordsOf(n)).told, key);
    if (existing) return adopt && runId && existing.run === runId && existing.state === 'attempted' ? existing : null;
    const body = noteRecord(key, text, status, runId);
    const mine = await gh.call('POST', `/repos/${repo}/issues/${n}/comments`, { body });
    const note = { id: mine && mine.id, body, text };
    const first = owningNote((await recordsOf(n)).told, key);
    if (first && mine && first.id !== mine.id) {
      await settleNote(note, 'dropped', 'another run claimed it');
      return null;
    }
    return note;
  }

  // Send a claimed message, then mark its note sent. The note is marked as
  // sending first: a run never takes over a note so marked, so a send that
  // went out before its sent mark failed is never sent again. A failed send
  // marks it unconfirmed, for the sweep, and fails the run.
  async function deliver(n, threadId, note, text, status, ping = [], reply = {}) {
    const body = await unmarked(note);
    if (body === null) {
      log(`#${n}: the note for "${text.slice(0, 60)}" was marked meanwhile; not sent`);
      return;
    }
    note.body = `${body}\n<!-- discord-sending -->`;
    await gh.call('PATCH', `/repos/${repo}/issues/comments/${note.id}`, { body: note.body });
    try {
      const sent = await discord.send(threadId, text, ping, reply);
      if (sent && sent.replyRefused) log(`#${n}: Discord refused the reply; the message went out plain, with no ping`);
    } catch (e) {
      if (/-> 404 /.test(e.message)) {
        log(`#${n}: Discord post is gone; message dropped`);
        await settleNote(note, 'dropped', 'the Discord post is gone');
        return;
      }
      await settleNote(note, 'unconfirmed').catch((err) => log(`#${n}: could not mark the note unconfirmed: ${err.message}`));
      throw e;
    }
    await settleNote(note, 'sent');
    done.push({ issue: n, thread: threadId, status, message: text });
  }

  // Set the post's tag to what the issue says, then read again; repeat while
  // the answer moved. With `tell`, each move's message is claimed just before
  // the tag is written, so a move that fails leaves the message owed. Returns
  // the post and the notes claimed on the way.
  async function settlePost(n, tell) {
    const notes = [];
    for (let i = 0; i < SETTLE_TRIES; i++) {
      const st = await releasedState(n);
      if (!eligible(st.issue)) {
        for (const c of notes) await dropNote(c.note, 'no longer true');
        return null;
      }
      const threadId = parseMarker(st.issue.body).threadId;
      const want = wantedStatus(st, st.issue.state === 'open' ? await prsFor(n) : []);
      const beforeMove = tell ? async () => {
        const m = await messageFor(n, st, want);
        const note = m && (await claim(n, m.key, m.text, want, true));
        // A later settle can adopt this run's own note from an earlier one:
        // keep each note once, so it is sent once.
        // An adopted note keeps its own words, so what is sent is what the note says.
        if (note && !notes.some((c) => c.note.id === note.id)) notes.push({ note, key: m.key, text: note.text || m.text, status: want });
      } : undefined;
      let r;
      try {
        // Triaged says only that the issue is filed: it never costs a staff
        // tag. A status with news still takes the fifth slot, as at filing.
        r = await discord.setStatus(threadId, want, beforeMove, { dropOther: want !== STATUS.triaged });
      } catch (e) {
        // A deleted post can never be told; its issue still moves. Only the
        // post's own read or write answering 404 says it is gone.
        if (!postGone(e, threadId)) throw e;
        log(`#${n}: Discord post is gone (${e.message.slice(0, 120)})`);
        for (const c of notes) await dropNote(c.note, 'the Discord post is gone');
        return null;
      }
      // Another writer moved the status just before this write: decide again
      // from what the post shows now.
      if (r.raced) continue;
      if (r.skipped) {
        // The forum has no such tag, or no free slot for Triaged: the post did
        // not move, and this move's
        // message stays owed until a re-run once the tag exists.
        log(`#${n}: ${r.skipped}`);
        return { n, threadId, st, notes: notes.filter((c) => c.status !== want) };
      }
      if (tell && runId && r.from === want) {
        // The post already shows the status: another run or a sweep moved it
        // after an earlier attempt of this run wrote its note and stopped. A
        // re-run still sends that note, its own and never marked as sending.
        const m = await messageFor(n, st, want);
        const own = m && owningNote((await recordsOf(n)).told, m.key);
        if (own && own.run === runId && own.state === 'attempted' && !notes.some((c) => c.note.id === own.id)) {
          notes.push({ note: own, key: m.key, text: own.text || m.text, status: want });
        }
      }
      const after = await releasedState(n);
      const again = wantedStatus(after, after.issue.state === 'open' ? await prsFor(n) : []);
      if (again === want) return { n, threadId, st: after, notes };
    }
    throw new Error(`#${n}: post status did not settle after ${SETTLE_TRIES} tries`);
  }

  // What a status message replies to: the filed message, pinged. An issue
  // filed before that id was saved replies to the post's first message only
  // when its author is the saved reporter, since a right-click filing may
  // name someone else; otherwise, or when it cannot be read, it goes plain.
  async function replyTarget(issue, threadId) {
    const filed = parseFiledMessage(issue.body);
    if (filed) return { replyTo: filed };
    // A body edited during the run may have lost its marker.
    const { reporterId } = parseMarker(issue.body) || {};
    if (!reporterId) return {};
    try {
      const first = await discord.getMessage(threadId, threadId);
      return first && first.author && first.author.id === reporterId ? { replyTo: threadId } : {};
    } catch {
      return {};
    }
  }

  // Send a claimed message when the fact it tells still holds. Another run
  // may have moved the issue on since; that run tells its own news. The reply
  // target is read first, so no slow read sits between the last check and
  // the send.
  async function tellNote(moved, c) {
    const reply = await replyTarget(moved.st.issue, moved.threadId);
    const st = await releasedState(moved.n);
    const nowStatus = wantedStatus(st, st.issue.state === 'open' ? await prsFor(moved.n) : []);
    const still = nowStatus === c.status && (await messageFor(moved.n, st, c.status));
    if (!still || still.key !== c.key) {
      await dropNote(c.note, 'no longer true');
      return;
    }
    await deliver(moved.n, moved.threadId, c.note, c.text, c.status, [], reply);
  }

  // Labels, then the post, then the messages claimed on the way. The sweep
  // syncs with `tell` off: it never messages anyone.
  async function sync(n, tell = true) {
    handled.add(n);
    await settleLabels(n);
    const moved = await settlePost(n, tell);
    if (moved) for (const c of moved.notes) await tellNote(moved, c);
    return moved;
  }

  // The Discord post of the issue this one was closed as a duplicate of, when
  // that issue is in this repo and the bot filed it. Only a nicety: any
  // failure gives null and the message goes out without the link.
  async function duplicateLink(n) {
    try {
      const data = await graphql(`query($owner: String!, $name: String!, $number: Int!) {
        repository(owner: $owner, name: $name) { issue(number: $number) {
          timelineItems(itemTypes: [CLOSED_EVENT], last: 1) { nodes { ... on ClosedEvent {
            duplicateOf { ... on Issue { body labels(first: 100) { nodes { name } } repository { nameWithOwner } } }
          } } }
        } }
      }`, { owner, name, number: n });
      const issue = data && data.repository && data.repository.issue;
      const node = issue && issue.timelineItems && issue.timelineItems.nodes[0];
      const d = node && node.duplicateOf;
      if (!d || !d.repository || String(d.repository.nameWithOwner).toLowerCase() !== repo.toLowerCase()) return null;
      const filed = ((d.labels && d.labels.nodes) || []).some((l) => l.name === LABELS.fromDiscord);
      const m = filed && parseMarker(d.body);
      if (!m) return null;
      const ch = await discord.getChannel(m.threadId);
      return ch && ch.guild_id ? `https://discord.com/channels/${ch.guild_id}/${m.threadId}` : null;
    } catch (err) {
      log(`#${n}: could not find the duplicate's post: ${err.message}`);
      return null;
    }
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
      if (reason === 'completed') return { key: `closed-${st.close.id}`, text: MESSAGES.done() };
      const link = reason === 'duplicate' ? await duplicateLink(n) : null;
      return { key: `closed-${st.close.id}`, text: MESSAGES.closed(reason, link) };
    }
    if (status === STATUS.inProgress) {
      // Once per time the issue is open: a second PR, or a PR back from
      // draft, says nothing new.
      const close = await lastClose(n);
      return { key: `in-progress-after-${close ? close.id : 'none'}`, text: MESSAGES.inProgress() };
    }
    return null;
  }

  // The issues this run synced or pinged; a re-run's owed scan skips only
  // these, so an issue the event passed over is still scanned.
  const handled = new Set();

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

  // A workflow run's state, for the sweep: whether it is still going, and
  // whether GitHub still lets it be re-run (30 days from its first attempt,
  // 50 re-runs at most). A deleted run is neither.
  const runs = new Map();
  function runInfo(id) {
    if (!runs.has(id)) {
      runs.set(id, gh.call('GET', `/repos/${repo}/actions/runs/${id}`).then(
        (r) => ({
          active: r.status !== 'completed',
          open: now() - Date.parse(r.created_at) < RERUN_MS && (r.run_attempt || 1) <= MAX_RERUNS,
        }),
        (e) => {
          if (/-> 404 /.test(e.message)) return { active: false, open: false };
          throw e;
        },
      ));
    }
    return runs.get(id);
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
      await sync(n);
    });
  } else if (eventName === 'push' && String(payload.ref).startsWith('refs/tags/')) {
    const tag = payload.ref.slice('refs/tags/'.length);
    // The tagged commit: for an annotated tag `after` is the tag object.
    const target = (payload.head_commit && payload.head_commit.id) || payload.after || tag;
    if (payload.deleted || payload.created === false) {
      log(`tag ${tag} was deleted or moved, not created: nothing to do`);
    } else if (!isRelease(tag, pattern)) {
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
              // The oldest release holding the fix is named, as on every other
              // path; this tag when the tag list does not show it yet.
              const held = (await releaseHolding(n, st.fix, false)) || tag;
              await gh.call('POST', `/repos/${repo}/issues/${n}/comments`, { body: shipRecord(held, st.fix) });
            } else {
              log(`#${n}: fix ${st.fix.slice(0, 7)} is not in ${tag}, still pending`);
            }
          }
          const moved = await sync(n);
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
        // One ping per labeling: a rerun of the event finds the note, and a
        // re-run of this run takes over its own note only if it was never
        // marked as sending, so the ping goes out at most once.
        handled.add(n);
        const note = await claim(n, `needs-info-${String(payload.issue.updated_at || 'once').replace(/\W/g, '')}`, text, null, true);
        if (note && !hasLabel(await gh.getIssue(repo, n), LABELS.needsInfo)) {
          await dropNote(note, 'no longer true');
        } else if (note) {
          // A locked post does not unarchive on a new message; reopen it first.
          // A deleted post fails here, before the send, and drops the note.
          const gone = await discord.unarchive(m.threadId).then(() => false, (e) => {
            if (/-> 404 /.test(e.message)) return true;
            throw e;
          });
          if (gone) await dropNote(note, 'the Discord post is gone');
          else await deliver(n, m.threadId, note, text, null, m.reporterId ? [m.reporterId] : []);
        }
      }
    } else if (['opened', 'closed', 'reopened'].includes(payload.action)) {
      // At `opened` the Worker has tagged a post with no status Triaged and
      // said "now tracked" itself, or tagged nothing when GitHub answered it
      // late: this run puts the post's status in step with GitHub. Triaged
      // has no message; when GitHub already calls for one that has (a fix PR
      // opened, a close, before this run started), this run tells it, and
      // the note rules let only one run send it.
      await each([n], async () => {
        if (!(await botIssue(n))) return;
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
      let st = await stateOf(n);
      const parts = [];
      // A fix with no ship record may already be in a release; a fix in none
      // costs one compare.
      if (st.fix && !st.shippedIn) {
        const held = await releaseHolding(n, st.fix, fix);
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
      // A post read that fails for any reason but a 404 leaves the post
      // neither judged nor repaired, and its notes unjudged: it is not gone.
      let unread = null;
      try {
        // A post carrying the wanted status tag shows it, wherever it sits.
        shown = await discord.statusOf(threadId, status);
      } catch (e) {
        // The issue's failure line at the end of the sweep logs the error.
        // Only the post's own read answering 404 says it is gone.
        if (!postGone(e, threadId)) {
          unread = e;
          parts.push('Discord post not read (see the log)');
        }
        shown = undefined; // the post is gone, or was not read
      }
      if (!(want.length === has.length && want.every((l) => has.includes(l)))) {
        parts.push(`labels ${has.join(', ') || '(none)'} -> ${want.join(', ') || '(none)'}`);
      }
      if (shown !== undefined && shown !== status) parts.push(`post ${shown || '(no status)'} -> ${status}`);
      // The first note of each message. The sweep never messages anyone.
      // - A note in the older `Told the player` form was marked sent
      //   only after its send, so an unmarked one may have gone out: it is
      //   listed, and never held, dropped or resent.
      // - A newer note still attempted was never sent: its send marks it
      //   first. Still true, and its run still going or still re-runnable, it
      //   is owed: the post is left for that run from the moment the note
      //   exists, since a re-run sends it whether or not the post moved.
      //   One no re-run could send is dropped: its post is gone, or its
      //   message no longer holds (a status note, whatever the post shows; a
      //   needs-info ping once the label is off).
      // A note is judged once its run has ended (its run's state, or, with no
      // run, the note's age).
      const owed = [];
      const stale = [];
      const seen = new Set();
      for (const t of unread ? [] : st.records.told) {
        if (t.released || seen.has(t.key)) continue;
        seen.add(t.key);
        if (t.state === 'unconfirmed') {
          parts.push(`message "${t.text}" may not have reached the player (${t.url})`);
          continue;
        }
        if (t.state === 'attempted' && t.legacy) {
          if (now() - t.at > OWED_MS) parts.push(`message "${t.text}" may not have been sent (${t.url})`);
          continue;
        }
        if (t.state !== 'attempted' && t.state !== 'sending') continue;
        const r = t.run ? await runInfo(t.run) : null;
        const done = r ? !r.active : now() - t.at > OWED_MS;
        // A note marked as sending may have gone out; nothing resends it.
        if (t.state === 'sending') {
          if (done) parts.push(`message "${t.text}" may not have reached the player (${t.url})`);
          continue;
        }
        const m = t.status && shown !== undefined && status === t.status ? await messageFor(n, st, status) : null;
        const stillTrue = Boolean(m) && m.key === t.key;
        const dead = shown === undefined ? 'the Discord post is gone'
          : (t.status ? !stillTrue : t.key.startsWith('needs-info-') && !hasLabel(st.issue, LABELS.needsInfo)) ? 'no longer true'
            : '';
        if (stillTrue && r && (r.active || r.open)) {
          if (shown !== t.status) owed.push(t);
          if (done) parts.push(`owed message "${t.text}" (${t.url}): fix the setup if needed, then re-run ${runUrl(t.run)}; a post not showing it is left as it is until then`);
        } else if (dead) {
          if (done) {
            stale.push({ note: t, reason: dead });
            parts.push(`owed message "${t.text}" ${dead === 'no longer true' ? 'is no longer true' : 'cannot be sent: the Discord post is gone'} (${t.url})`);
          }
        } else if (done) {
          const how = !r ? '' : r.open ? `; re-run ${runUrl(t.run)} sends it while it is still true`
            : `; its run ${runUrl(t.run)} can no longer be re-run (30 days from its first attempt, or 50 re-runs, have passed, or it was deleted), so send it by hand if it is still needed`;
          parts.push(`message "${t.text}" was not sent (${t.url})${how}`);
        }
      }
      if (!parts.length) return;
      wrong++;
      const line = `#${n}: ${parts.join('; ')}`;
      log(line);
      report.push(line);
      if (unread) throw new Error(`#${n}: Discord post not read (${unread.message.slice(0, 200)})`);
      if (!fix) return;
      for (const s of stale) await dropNote(s.note, s.reason);
      if (owed.length) await settleLabels(n);
      else await sync(n, false);
    });
    const head = `sweep (${fix ? 'fix' : 'report'} mode): ${wrong} of ${issues.length} issue(s) out of step`;
    log(head);
    if (env.GITHUB_STEP_SUMMARY) {
      appendFileSync(env.GITHUB_STEP_SUMMARY, [`### Discord status ${head}`, '', ...report.map((l) => `- ${l}`), ''].join('\n'));
    }
  }

  // A re-run also syncs every issue on which an earlier attempt of this run
  // left a note it never sent. The event may no longer lead to that issue: a
  // tag run's window of recent closes has moved on, or a PR no longer links
  // it. The sync then sends the note while it is still true.
  if (runId && attempt > 1 && eventName !== 'schedule' && eventName !== 'workflow_dispatch') {
    const owing = [];
    for (const i of (await gh.issuesWithLabel(repo, LABELS.fromDiscord)).filter(eligible)) {
      if (handled.has(i.number)) continue;
      const { told } = await recordsOf(i.number);
      if (told.some((t) => t.run === runId && t.state === 'attempted')) owing.push(i.number);
    }
    await each(owing, (n) => sync(n));
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
