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
// everything both wrote. The sweep repairs what a failed call left.
import { readFileSync, appendFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { STATUS, LABELS, MESSAGES, parseMarker, parseFiledMessage, timedFetch, isRelease, DEFAULT_RELEASE_PATTERN, checklistStatus, checklistKey, statusOf,
  shownStatuses, preferStatus, triagedAlone, withAccepted, showsAccepted, ACCEPTED, inlineCode, hasTag, tagLine, acceptedLine, isDiscordId, STATUS_NAMES } from '../src/core.js';
import { discordClient, postGone } from '../src/discord.js';
import { githubClient } from '../src/github.js';
import { checklistRunner, parseChecklist } from './checklist.mjs';

const hasLabel = (issue, name) => (issue.labels || []).some((l) => (l.name || l) === name);
// The bot's own issues: the label and the marker it writes last.
export const eligible = (issue) => hasLabel(issue, LABELS.fromDiscord) && parseMarker(issue.body) !== null;
const NO_ACCEPTED_SLOT = 'no free tag slot for Accepted on the post';
const NO_ACCEPTED_TAG = 'the forum has no Accepted tag';
// Only PRs from people with a role on the repo move a post to In progress.
export const TRUSTED = new Set(['OWNER', 'MEMBER', 'COLLABORATOR']);
const PR_EVENTS = new Set(['pull_request', 'pull_request_target']);
const CALL_MS = 15000;
const SETTLE_TRIES = 3;
// A tag run also looks at bot issues closed this recently, in case a close
// run has not labeled them yet.
const RECENT_MS = 24 * 60 * 60 * 1000;
// The account this workflow comments as (GITHUB_TOKEN). Only its records
// count: anyone can comment on a public issue.
export const BOT_LOGIN = 'github-actions[bot]';
const RELEASE = [LABELS.pendingRelease, LABELS.shipped];
// Lists are followed this many pages (100 each) at most.
const MAX_PAGES = 10;
// A note is judged once it is this old: its status job has ended by then.
const OWED_MS = 10 * 60 * 1000;
// GitHub allows a run to be re-run for this long after its first attempt.
const RERUN_MS = 30 * 24 * 60 * 60 * 1000;
// The sweep's own checklist calls stop once they have taken this long in a
// run, so slow checklist reads never keep later issues' player repairs from
// the job's time limit; the issues left are named, and the next sweep
// checks them.
const CHECKLIST_SWEEP_MS = 2 * 60 * 1000;
// With the checklist on, each day's sweep starts one issue further on, so
// issues that time leaves are reached first on a later day.
const DAY_MS = 24 * 60 * 60 * 1000;

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

const SETUP_HEAD = '### Discord status: setup problems';
const RERUN_ADVICE = 'After fixing them, re-run this run. A run that owes a player a message sends it then; a message marked Unconfirmed is never sent again, and the sweep lists it.';
// A value from outside the code, shown as written: a line break would split
// its summary line, and Markdown in it (a comment, a <br>) would change what
// the summary shows.
// Cut by whole characters, so an emoji at the cut is never split.
const quoted = (v, max = 80) => inlineCode(Array.from(String(v).replace(/\s+/g, ' ')).slice(0, max).join(''));
const noTagLine = (forumId, name) => tagLine(`forum ${forumId}`, name);
const noAcceptedLine = (forumId) => acceptedLine(`forum ${forumId}`);

// Outside Actions there is no summary file.
function writeSetup(path, lines) {
  if (!path) return;
  appendFileSync(path, [SETUP_HEAD, '', ...lines.map((l) => `- ${l}`), '', RERUN_ADVICE, ''].join('\n'));
}

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

// A scheduled run's payload names no repository; Actions sets GITHUB_REPOSITORY.
const repoOf = (payload, env) => (payload.repository && payload.repository.full_name) || env.GITHUB_REPOSITORY;

export async function run({ eventName, payload, env, fetchImpl = fetch, log = console.log, now = Date.now }) {
  const repo = repoOf(payload, env);
  const [owner, name] = repo.split('/');
  // Every run needs the pattern, and a repository variable can hold anything:
  // one that does not compile is a setup problem, reported before any call.
  let pattern;
  try {
    pattern = new RegExp(env.RELEASE_TAG_PATTERN || DEFAULT_RELEASE_PATTERN);
  } catch (e) {
    const line = `RELEASE_TAG_PATTERN is not a valid pattern (${quoted(e.message)}): fix the repository variable`;
    writeSetup(env.GITHUB_STEP_SUMMARY, [line]);
    throw new Error(`setup problems: ${line}`);
  }
  // A setting pasted with a space around the id is still that id, as the
  // Worker reads it. Only a plain id is used: any other set value, spaces
  // alone included (the workflow starts the checklist job for it), would go
  // into request paths as typed, so the run does no checklist work and names
  // it at its end, beside its other setup lines.
  const checklistSetting = String(env.CHECKLIST_FORUM_ID || '');
  const checklistForum = isDiscordId(checklistSetting.trim()) ? checklistSetting.trim() : '';
  const badChecklistLine = checklistSetting && !checklistForum
    ? `CHECKLIST_FORUM_ID is ${quoted(checklistSetting)}, which is not a Discord channel id: set the repository variable to the staff checklist forum's id, digits only (this run did no staff checklist work)`
    : null;
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
  // Setup problems, one line each with its fix, kept apart so the run
  // finishes every other issue and then fails once. A line holds ids, tag
  // names and setting names only, so one problem met twice is one line.
  const setup = [];
  const setupProblem = (line) => {
    if (setup.includes(line)) return;
    setup.push(line);
    // Logged when met, so a run the job's time limit stops still shows it.
    log(`setup problem: ${line}`);
  };
  // A bad CHECKLIST_FORUM_ID is named with the report, wherever the run
  // writes one; a failure before any issue work writes none.
  const reportSetup = () => {
    if (badChecklistLine) setupProblem(badChecklistLine);
    if (setup.length) writeSetup(env.GITHUB_STEP_SUMMARY, setup);
  };
  // The sweep names every status tag a forum lacks, from every forum read it
  // makes, its repairs' included; an event run names the one it needs.
  const sweeping = eventName === 'schedule' || eventName === 'workflow_dispatch';
  const checkStatusTags = (forumId, tags, names) => {
    for (const s of names) if (!hasTag(tags, s)) setupProblem(noTagLine(forumId, s));
  };
  // The sweep's report, written after the setup section at the run's end.
  let sweepSummary = null;
  // A Discord refusal of the bot, named by the request it refused, which the
  // client keeps apart from the answer's text.
  const noteRefusal = (e) => {
    const d = e.discord;
    if (!d) return;
    if (d.status === 401) {
      setupProblem("Discord refused the bot token (401): set the repository secret DISCORD_BOT_TOKEN to the bot's current token");
      return;
    }
    if (d.status !== 403) return;
    // A path's ids are a marker's digits, a plain CHECKLIST_FORUM_ID, or
    // ones Discord gave: a post's `parent_id` can be null (a marker naming
    // a channel with no parent), which puts no id in the forum read's path.
    // Such a refusal names nothing and still fails the run.
    const [, ch, rest = ''] = /^\/channels\/(\d+)(\/.*)?$/.exec(d.path) || [];
    if (!ch) return;
    if (d.method === 'POST' && rest === '/messages') {
      setupProblem(`Discord refused the bot's message in post ${ch} (403): give the bot View Channel, Send Messages in Threads and Read Message History (a reply needs it) in that post's forum`);
    } else if (rest.startsWith('/messages/')) {
      setupProblem(`Discord refused the bot reading messages in post ${ch} (403): give the bot View Channel and Read Message History in that post's forum`);
    } else {
      setupProblem(`Discord refused the bot on channel ${ch} (403), a post or its forum: give the bot View Channel, Manage Threads and Send Messages in Threads in that forum`);
    }
  };
  if (runId) log(`workflow run ${runId}, attempt ${attempt}`);
  // An issue moved in from another repo arrives as `opened`. Its post and
  // its thread already follow it, and a commit-closed one would be told
  // "Closed." here. Each job's next event for it settles its own part.
  if (eventName === 'issues' && payload.action === 'opened' && payload.changes && payload.changes.old_issue) {
    log(`#${payload.issue.number}: opened by a transfer from ${payload.changes.old_issue.html_url || 'another repo'}; nothing to do`);
    return done;
  }

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
    // The staff checklist record, one per issue.
    const ckRecords = [];
    for (let page = 1; ; page++) {
      const batch = await gh.call('GET', `/repos/${repo}/issues/${n}/comments?per_page=100&page=${page}`);
      for (const c of batch) {
        if (!c.user || c.user.login !== BOT_LOGIN) continue;
        // A body edited in the browser comes back with CRLF line ends.
        const body = (c.body || '').replace(/\r\n?/g, '\n');
        if (checklistForum) {
          const ck = parseChecklist(c);
          if (ck) ckRecords.push(ck);
        }
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
      if (batch.length < 100) {
        const checklist = ckRecords.find((r) => r.threadId) || ckRecords[0] || null;
        return { shipped, told, checklist };
      }
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

  // GitHub label names match in any letter case, as the workflow's `if` does.
  const acceptedLabel = (name) => String(name || '').toLowerCase() === LABELS.accepted;
  // Accepted shows only while the issue is open; once closed, the status tag
  // says what happened. The post and its checklist thread read the label alike.
  const wantedAccepted = (issue) => issue.state === 'open' && (issue.labels || []).some((l) => acceptedLabel(l.name || l));

  // The issue's state as releasedState gives it, read only: a fix a release
  // already holds is taken as shipped, and no ship record is written.
  async function peekState(n) {
    const st = await stateOf(n);
    if (!st.fix || st.shippedIn) return st;
    const held = await releaseHolding(n, st.fix, false);
    return held ? { ...st, shippedIn: held } : st;
  }

  // What the issue's checklist thread should show, from its state and its
  // public status, and whether the bot still files the issue.
  function wantFrom(st, status) {
    const name = checklistStatus(status, st.issue.state_reason);
    const marker = parseMarker(st.issue.body);
    return {
      st, issue: st.issue, name, key: checklistKey(name, st.close), eligible: eligible(st.issue),
      accepted: wantedAccepted(st.issue),
      postId: marker ? marker.threadId : null,
    };
  }

  async function wanted(n) {
    const st = await peekState(n);
    return wantFrom(st, wantedStatus(st, st.issue.state === 'open' ? await prsFor(n) : []));
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
      if (statusOf(e) === 404) return null;
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
      const sent = await discord.send(threadId, reply.mention ? `<@${reply.mention}> ${text}` : text, reply.mention ? [...ping, reply.mention] : ping, reply);
      // A plain message still pings the reporter it mentions.
      if (sent && sent.replyRefused) log(`#${n}: Discord refused the reply; the message went out plain, ${reply.mention ? 'its mention still pinging the reporter' : 'with no ping'}`);
    } catch (e) {
      if (statusOf(e) === 404) {
        log(`#${n}: Discord post is gone; message dropped`);
        await settleNote(note, 'dropped', 'the Discord post is gone');
        return;
      }
      noteRefusal(e);
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
        // Each forum read is checked as it lands, so a failure after it, or a
        // post gone before the write, never hides a tag the forum lacks. A
        // post with no free slot is staff's choice and stays a log line.
        const accepted = wantedAccepted(st.issue);
        r = await discord.setStatus(threadId, want, beforeMove, {
          dropOther: want !== STATUS.triaged,
          accepted,
          onForum: (forumId, tags) => {
            checkStatusTags(forumId, tags, sweeping ? STATUS_NAMES : [want]);
            if (accepted && !hasTag(tags, ACCEPTED)) setupProblem(noAcceptedLine(forumId));
          },
        });
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
      if (r.noRoom) log(`#${n}: ${NO_ACCEPTED_SLOT}`);
      if (r.noAccepted) log(`#${n}: ${NO_ACCEPTED_TAG}`);
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
    // A moved post's copy was posted by the bot's webhook, so a reply to it
    // pings no one: the reporter is mentioned instead.
    if (filed) return filed.copy ? { replyTo: filed.id, mention: parseMarker(issue.body).reporterId } : { replyTo: filed.id };
    // A body edited during the run may have lost its marker.
    const { reporterId } = parseMarker(issue.body) || {};
    if (!reporterId) return {};
    try {
      const first = await discord.getMessage(threadId, threadId);
      return first && first.author && first.author.id === reporterId ? { replyTo: threadId } : {};
    } catch (e) {
      noteRefusal(e);
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

  // The sweep's Accepted-only repair, on an open issue GitHub wants at
  // Triaged only. It reads no records, claims no note and moves no status.
  async function repairAccepted(n) {
    const issue = await gh.getIssue(repo, n);
    if (!eligible(issue)) return;
    if (issue.state !== 'open' || wantedStatus({ issue }, await prsFor(n)) !== STATUS.triaged) {
      log(`#${n}: Accepted left for the post's next status change`);
      return;
    }
    const threadId = parseMarker(issue.body).threadId;
    const want = wantedAccepted(issue);
    let r;
    try {
      r = await discord.fixAccepted(threadId, want, { onForum: (forumId, tags) => checkStatusTags(forumId, tags, STATUS_NAMES) });
    } catch (e) {
      if (!postGone(e, threadId)) throw e;
      log(`#${n}: Discord post is gone (${e.message.slice(0, 120)})`);
      return;
    }
    if (r.wrote) log(`#${n}: Accepted ${want ? 'shown' : 'removed'} on the post`);
    else if (r.archived) log(`#${n}: the post is archived; its Accepted tag is left as it is`);
    else if (r.refused) log(`#${n}: Accepted left: the post does not show Triaged alone`);
    else if (r.raced) log(`#${n}: Accepted left: the post changed during the repair; the next sweep tries again`);
    else if (r.noAccepted) log(`#${n}: ${NO_ACCEPTED_TAG}`);
    else if (r.noRoom) log(`#${n}: ${NO_ACCEPTED_SLOT}`);
    else log(`#${n}: Accepted already in step on the post`);
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
      noteRefusal(err);
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
  // The issues a PR or release run took up, also those whose ship record or
  // sync failed first: each still gets its checklist thread updated.
  const touched = new Set();

  // One issue's failure is logged and the rest still run; the job fails at the end.
  async function each(numbers, fn) {
    for (const n of numbers) {
      try {
        await fn(n);
      } catch (e) {
        log(`#${n}: ${e.message}`);
        failed.push(n);
        noteRefusal(e);
      }
    }
  }

  async function botIssue(n) {
    const issue = await gh.getIssue(repo, n);
    return eligible(issue) ? issue : null;
  }

  // The checklist job fails on its own error, as it always has; the other
  // runs also name what the runner meets as setup problems.
  const checklistOnly = !!env.CHECKLIST_ONLY;
  const checklist = checklistForum
    ? checklistRunner({
      gh, discord, repo, forumId: checklistForum, wanted, records: recordsOf, botIssue, log, now, settleTries: SETTLE_TRIES, owedMs: OWED_MS,
      noteRefusal: checklistOnly ? () => {} : noteRefusal,
      setupProblem: checklistOnly ? () => {} : setupProblem,
      sweeping,
    })
    : null;

  // The checklist job: the issue's own events, and only its checklist
  // thread. It sends no message, so it never runs the re-run owed scan.
  if (checklistOnly) {
    const n = payload.issue && payload.issue.number;
    const ours = eventName === 'issues' && (['opened', 'closed', 'reopened'].includes(payload.action)
      || (['labeled', 'unlabeled'].includes(payload.action) && payload.label && acceptedLabel(payload.label.name)));
    if (ours && badChecklistLine) {
      reportSetup();
      throw new Error(`setup problems: ${badChecklistLine}`);
    }
    if (!checklist || !ours) {
      log('not a checklist event, or CHECKLIST_FORUM_ID is not set: nothing to do');
      return done;
    }
    try {
      await checklist.open(n);
    } catch (e) {
      throw new Error(`checklist thread not updated for #${n}: ${e.message}`);
    }
    return done;
  }

  if (PR_EVENTS.has(eventName)) {
    // Closed issues belong to the close run (E2).
    const pr = payload.pull_request;
    const numbers = await issuesClosedBy(pr.number);
    await each(numbers, async (n) => {
      // Taken up before its first read, so a failed read or a closed issue
      // still gets its checklist thread updated.
      touched.add(n);
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
        touched.add(n);
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
      // A failure here ends the run at once, as it always has: caught by
      // `each`, a failed first read would leave the ping's note to the
      // owed-note scan, whose ordinary sync can move the post and tell its
      // player. Its setup problems are reported before the throw.
      try {
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
              if (statusOf(e) === 404) return true;
              throw e;
            });
            if (gone) await dropNote(note, 'the Discord post is gone');
            else await deliver(n, m.threadId, note, text, null, m.reporterId ? [m.reporterId] : []);
          }
        }
      } catch (e) {
        noteRefusal(e);
        reportSetup();
        throw e;
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
    // Unset reads as report, as before. Checked after the list, so a failed
    // list never holds a collected line.
    if (env.SWEEP_MODE && env.SWEEP_MODE !== 'report' && !fix) {
      setupProblem(`SWEEP_MODE is ${quoted(env.SWEEP_MODE)}, which is neither report nor fix: set the repository variable to one of them (this sweep ran in report mode)`);
    }
    // Every post read carries its forum's tags as read then, so each read is
    // checked, at no extra call: a tag renamed between two reads is still
    // named. Accepted counts for an issue that wants it, archived post or not.
    // A post in a channel that is no forum (`forumTags`) names nothing.
    const checkForum = (read, issue) => {
      if (!read.tags) return;
      checkStatusTags(read.parentId, read.tags, STATUS_NAMES);
      if (wantedAccepted(issue) && !hasTag(read.tags, ACCEPTED)) setupProblem(noAcceptedLine(read.parentId));
    };
    let wrong = 0;
    let ckSpent = 0;
    const ckLeft = [];
    const numbers = issues.map((i) => i.number);
    const start = checklist && numbers.length ? Math.floor(now() / DAY_MS) % numbers.length : 0;
    const ckTimed = async (fn) => {
      const t = now();
      try {
        return await fn();
      } finally {
        ckSpent += now() - t;
      }
    };
    await each([...numbers.slice(start), ...numbers.slice(0, start)], async (n) => {
      let st = await stateOf(n);
      const parts = [];
      // Every failure of this issue is kept and thrown together at its end,
      // so a failed write here still leaves its checklist thread judged and
      // repaired.
      const errors = [];
      // A player-side failure ends this issue's player repair. With the
      // checklist on it is kept instead of thrown, so the checklist lines and
      // repair still run.
      let playerStop = false;
      const playerFailed = (e, what) => {
        if (!checklist) throw e;
        playerStop = true;
        errors.push(`${what} (${e.message.slice(0, 200)})`);
      };
      // A failed note read alone ends the note judging: a failed ship record
      // stops only the repair, so every note is still listed.
      let noteStop = false;
      const playerRead = (fn, what) => fn().catch((e) => {
        playerFailed(e, what);
        noteStop = true;
        return null;
      });
      // A fix with no ship record may already be in a release; a fix in none
      // costs one compare.
      if (st.fix && !st.shippedIn) {
        const held = await releaseHolding(n, st.fix, false);
        if (held) {
          parts.push(`ship record missing (${held} holds the fix)`);
          let written = false;
          if (fix) {
            try {
              await gh.call('POST', `/repos/${repo}/issues/${n}/comments`, { body: shipRecord(held, st.fix) });
              written = true;
            } catch (e) {
              playerFailed(e, 'ship record not written');
            }
          }
          st = written ? await stateOf(n) : { ...st, shippedIn: held };
        }
      }
      const want = wantedLabels(st);
      const has = RELEASE.filter((l) => hasLabel(st.issue, l));
      const status = wantedStatus(st, st.issue.state === 'open' ? await prsFor(n) : []);
      const threadId = parseMarker(st.issue.body).threadId;
      let shown;
      let post = null;
      // A post read that fails for any reason but a 404 leaves the post
      // neither judged nor repaired, and its notes unjudged: it is not gone.
      let unread = null;
      try {
        // A post carrying the wanted status tag shows it, wherever it sits.
        const read = await discord.threadState(threadId);
        post = { ...read, statuses: shownStatuses(read.applied, read.available) };
        shown = preferStatus(post.statuses, status);
      } catch (e) {
        // The issue's failure line at the end of the sweep logs the error.
        // Only the post's own read answering 404 says it is gone.
        noteRefusal(e);
        if (!postGone(e, threadId)) {
          unread = e;
          parts.push('Discord post not read (see the log)');
        }
        shown = undefined; // the post is gone, or was not read
      }
      if (post) checkForum(post, st.issue);
      if (!(want.length === has.length && want.every((l) => has.includes(l)))) {
        parts.push(`labels ${has.join(', ') || '(none)'} -> ${want.join(', ') || '(none)'}`);
      }
      if (shown !== undefined && shown !== status) parts.push(`post ${shown || '(no status)'} -> ${status}`);
      // Accepted lines are kept apart from the post's other lines and judged
      // on the tags as read; a status repair in the same sweep can change the
      // answer. Only a post showing Triaged alone, on an issue GitHub wants
      // at Triaged, is repaired; any other waits for its next status change.
      const accParts = [];
      let accRepairable = false;
      if (post && !post.archived) {
        const acc = wantedAccepted(st.issue);
        const a = withAccepted(post.applied, post.available, acc);
        if (acc && a.noAccepted) accParts.push(NO_ACCEPTED_TAG);
        else if (a.noRoom) accParts.push(NO_ACCEPTED_SLOT);
        else if (!a.noAccepted && acc !== showsAccepted(post.applied, post.available)) {
          accRepairable = status === STATUS.triaged && triagedAlone(post.statuses);
          accParts.push(`post Accepted ${acc ? 'missing -> shown' : 'shown -> removed'}${accRepairable ? '' : " (waits for the post's next status change)"}`);
        }
      }
      // The first note of each message. The sweep never messages anyone.
      // - A note in the older `Told the player` form was marked sent
      //   only after its send, so an unmarked one may have gone out: it is
      //   listed, and never held, dropped or resent.
      // - A newer note still attempted was never sent: its send marks it
      //   first. Still true, and its run still re-runnable (judged by the
      //   note's age), it is owed: the post is left for that run from the
      //   moment the note exists, since a re-run sends it whether or not the
      //   post moved.
      //   One no re-run could send is dropped: its post is gone, or its
      //   message no longer holds (a status note, whatever the post shows; a
      //   needs-info ping once the label is off).
      // A note is judged once it is OWED_MS old.
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
        const done = now() - t.at > OWED_MS;
        const open = Boolean(t.run) && now() - t.at < RERUN_MS;
        // A note marked as sending may have gone out; nothing resends it.
        if (t.state === 'sending') {
          if (done) parts.push(`message "${t.text}" may not have reached the player (${t.url})`);
          continue;
        }
        const m = t.status && shown !== undefined && status === t.status ? await playerRead(() => messageFor(n, st, status), `message of ${t.url} not read`) : null;
        if (noteStop) break;
        const stillTrue = Boolean(m) && m.key === t.key;
        const dead = shown === undefined ? 'the Discord post is gone'
          : (t.status ? !stillTrue : t.key.startsWith('needs-info-') && !hasLabel(st.issue, LABELS.needsInfo)) ? 'no longer true'
            : '';
        if (stillTrue && open) {
          if (shown !== t.status) owed.push(t);
          if (done) parts.push(`owed message "${t.text}" (${t.url}): fix the setup if needed, then re-run ${runUrl(t.run)}; a post not showing it is left as it is until then`);
        } else if (dead) {
          if (done) {
            stale.push({ note: t, reason: dead });
            parts.push(`owed message "${t.text}" ${dead === 'no longer true' ? 'is no longer true' : 'cannot be sent: the Discord post is gone'} (${t.url})`);
          }
        } else if (done) {
          const how = !t.run ? '' : open ? `; re-run ${runUrl(t.run)} sends it while it is still true`
            : `; its run ${runUrl(t.run)} can no longer be re-run (30 days have passed), so send it by hand if it is still needed`;
          parts.push(`message "${t.text}" was not sent (${t.url})${how}`);
        }
      }
      // The checklist's lines are read in their own catch and kept apart, so
      // a checklist line alone never moves the post, and a post or thread
      // that cannot be read never stops the other's repair. Every failure is
      // kept and thrown together at the end.
      const postOwes = parts.length > 0;
      let ck = { parts: [], repair: false, unread: null };
      const ckOn = !!checklist && ckSpent < CHECKLIST_SWEEP_MS;
      if (checklist && !ckOn) ckLeft.push(n);
      if (ckOn) {
        try {
          ck = await ckTimed(() => checklist.lines(n, wantFrom(st, status)));
        } catch (e) {
          ck = { parts: [`staff checklist not read: ${e.message.slice(0, 200)}`], repair: false, unread: e };
        }
      }
      if (ck.unread) noteRefusal(ck.unread);
      if (ck.seen) checklist.checkSeen(ck.seen);
      // An Accepted line alone never starts the status repair: its quiet move
      // could leave a run that is about to tell the player nothing to send.
      const accFix = accRepairable && !owed.length;
      if (!postOwes && !accParts.length && !ck.parts.length) {
        if (errors.length) throw new Error(errors.join('; '));
        return;
      }
      wrong++;
      const line = `#${n}: ${[...parts, ...accParts, ...ck.parts].join('; ')}`;
      log(line);
      report.push(line);
      if (unread) errors.unshift(`#${n}: Discord post not read (${unread.message.slice(0, 200)})`);
      if (fix && postOwes && !unread && !playerStop) {
        try {
          for (const s of stale) await dropNote(s.note, s.reason);
          if (owed.length) await settleLabels(n);
          else await sync(n, false);
        } catch (e) {
          // A post whose status repair failed gets no Accepted write either.
          playerStop = true;
          errors.push(e.message);
          noteRefusal(e);
        }
      }
      if (fix && accFix && !unread && !playerStop) {
        try {
          await repairAccepted(n);
        } catch (e) {
          errors.push(e.message);
          noteRefusal(e);
        }
      }
      if (fix && ck.repair && ckSpent >= CHECKLIST_SWEEP_MS) ckLeft.push(n);
      else if (fix && ck.repair) {
        try {
          await ckTimed(() => checklist.mirror(n));
        } catch (e) {
          errors.push(`staff checklist: ${e.message}`);
          noteRefusal(e);
        }
      }
      if (ck.unread) errors.push(`staff checklist thread not read (${ck.unread.message.slice(0, 200)})`);
      if (errors.length) throw new Error(errors.join('; '));
    });
    if (ckLeft.length) {
      const left = `staff checklist not checked or not repaired for ${ckLeft.map((x) => `#${x}`).join(', ')}: this sweep's checklist work reached its ${CHECKLIST_SWEEP_MS / 60000} minutes, and a later sweep reaches them`;
      log(left);
      report.push(left);
    }
    const head = `sweep (${fix ? 'fix' : 'report'} mode): ${wrong} of ${issues.length} issue(s) out of step`;
    log(head);
    if (env.GITHUB_STEP_SUMMARY) {
      // A report line can quote text from outside the code (a note's message,
      // an error), which can hold Markdown or HTML. Each line stays one
      // bullet, and every backslash, backtick and `<` is shown as typed, so
      // no code span, comment, tag or heading can form, whatever the quoted
      // text holds.
      const asText = (l) => l.replace(/\s+/g, ' ').replace(/[\\`]/g, '\\$&').replace(/</g, '&lt;');
      sweepSummary = [`### Discord status ${head}`, '', ...report.map((l) => `- ${asText(l)}`), ''].join('\n');
    }
  }

  // A re-run also syncs every issue on which an earlier attempt of this run
  // left a note it never sent. The event may no longer lead to that issue: a
  // tag run's window of recent closes has moved on, or a PR no longer links
  // it. The sync then sends the note while it is still true.
  // With the checklist on, or a setup line met or due, a failed owed-note
  // scan is kept, so the checklist work and the setup report below still
  // run; otherwise it is thrown at once.
  let rerunFailed = null;
  if (runId && attempt > 1 && eventName !== 'schedule' && eventName !== 'workflow_dispatch') {
    try {
      const owing = [];
      for (const i of (await gh.issuesWithLabel(repo, LABELS.fromDiscord)).filter(eligible)) {
        if (handled.has(i.number)) continue;
        const { told } = await recordsOf(i.number);
        if (told.some((t) => t.run === runId && t.state === 'attempted')) owing.push(i.number);
      }
      await each(owing, (n) => sync(n));
    } catch (e) {
      if (!checklist && !setup.length && !badChecklistLine) throw e;
      rerunFailed = e;
      log(`re-run owed-note scan failed: ${e.message.slice(0, 200)}`);
    }
  }

  // PR and release runs keep each issue they took up in step on its
  // checklist thread, after every player message; a failure fails the run
  // at its end, beside any player failure.
  const ckFailed = [];
  if (checklist && (PR_EVENTS.has(eventName) || eventName === 'push')) {
    for (const n of new Set([...touched, ...handled])) {
      try {
        await checklist.mirror(n);
      } catch (e) {
        log(`#${n}: staff checklist: ${e.message}`);
        ckFailed.push(n);
        noteRefusal(e);
      }
    }
  }

  log(done.length ? `told ${done.length} Discord post(s)` : 'no Discord post told');
  const problems = [];
  if (rerunFailed) problems.push(`the re-run's owed-note scan failed (${rerunFailed.message.slice(0, 200)})`);
  if (failed.length) problems.push(`could not update issue(s) ${failed.map((n) => `#${n}`).join(', ')}; see above`);
  if (ckFailed.length) problems.push(`checklist thread(s) not updated for ${ckFailed.map((n) => `#${n}`).join(', ')}; see above`);
  reportSetup();
  if (sweepSummary) appendFileSync(env.GITHUB_STEP_SUMMARY, sweepSummary);
  if (setup.length) problems.push(`setup problems: ${setup.join('; ')}`);
  if (problems.length) throw new Error(problems.join('; '));
  return done;
}

// With no bot token, a repo with no issue the bot filed is skipped, so the
// workflow can be merged before the bot is set up; a labeled PR or a
// hand-labeled issue does not count. A repo with one fails, with the fix in
// the job summary.
export async function main({ eventName, payload, env, fetchImpl = fetch, log = console.log }) {
  if (env.DISCORD_BOT_TOKEN) return run({ eventName, payload, env, fetchImpl, log });
  let line = null;
  try {
    // issuesWithLabel leaves PRs out; `eligible` needs the bot's marker too.
    const labeled = await githubClient(env.GITHUB_TOKEN, timedFetch(fetchImpl, CALL_MS)).issuesWithLabel(repoOf(payload, env), LABELS.fromDiscord);
    if (labeled.some(eligible)) line = 'DISCORD_BOT_TOKEN is not set, but this repo has issues the bot filed: add the repository secret DISCORD_BOT_TOKEN';
  } catch (e) {
    line = `DISCORD_BOT_TOKEN is not set, and the bot's issues could not be checked (${quoted(e.message, 200)}): add the repository secret DISCORD_BOT_TOKEN, or re-run this run`;
  }
  if (!line) {
    log('DISCORD_BOT_TOKEN is not set: skipping Discord updates');
    return [];
  }
  writeSetup(env.GITHUB_STEP_SUMMARY, [line]);
  throw new Error(`setup problems: ${line}`);
}

if (import.meta.url === pathToFileURL(process.argv[1] || '').href) {
  const payload = JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'));
  main({ eventName: process.env.GITHUB_EVENT_NAME, payload, env: process.env }).catch((e) => {
    console.error(e);
    process.exit(1);
  });
}
