// The staff checklist forum: one thread per bot issue in a staff-only forum,
// mirroring the issue. The thread's record is one bot comment on the issue.
import { CHECKLIST_NAMES, planTags, sameTags } from '../src/core.js';
import { postGone } from '../src/discord.js';

const link = (guildId, threadId) => `https://discord.com/channels/${guildId}/${threadId}`;
const norm = (c) => String((c && c.body) || '').replace(/\r\n?/g, '\n');
const field = (body, name) => (new RegExp(`<!--\\s*discord-checklist-${name}:\\s*(.+?)\\s*-->`).exec(body) || [])[1] || null;

// The record. `state` is the thread's id, or `pending` (no thread yet) or
// `creating` (a create may have gone out). `forumId` is the forum the create
// was sent to, so a lost answer is searched for there; `since` is when that
// try began, `issueUrl` the issue's address then (a transfer changes it),
// and `archived` the key of the close the bot archived the thread for.
export function checklistBody({ state, guildId, forumId = '', since, issueUrl, archived = null }) {
  const thread = /^\d+$/.test(String(state));
  return [
    `Staff checklist thread: ${thread ? link(guildId, state) : 'opening'}`,
    '',
    `<!-- discord-checklist: ${state} guild: ${guildId || 'none'} -->`,
    ...(forumId ? [`<!-- discord-checklist-forum: ${forumId} -->`] : []),
    `<!-- discord-checklist-since: ${since} -->`,
    `<!-- discord-checklist-issue: ${issueUrl} -->`,
    ...(archived ? [`<!-- discord-checklist-archived: ${archived} -->`] : []),
  ].join('\n');
}

export function parseChecklist(c) {
  const body = norm(c);
  const m = /<!--\s*discord-checklist:\s*(\d+|pending|creating)\s+guild:\s*(\d+|none)\s*-->/.exec(body);
  if (!m) return null;
  const threadId = /^\d+$/.test(m[1]) ? m[1] : null;
  const guildId = m[2] === 'none' ? '' : m[2];
  return {
    id: c.id, url: c.html_url || '', state: m[1], threadId, guildId,
    // False for a thread id staff put in the marker by hand: the visible
    // line does not link it yet.
    linked: !!threadId && body.startsWith(`Staff checklist thread: ${link(guildId, threadId)}\n`),
    forumId: field(body, 'forum') || '', since: Number(field(body, 'since')) || 0, issueUrl: field(body, 'issue'), archived: field(body, 'archived'),
  };
}

// A Discord error's body can hold any text, a staff tag's name included, and
// the Actions log is public: an error leaving the runner keeps only each
// request and its status.
const brief = (e) => {
  const one = (x) => {
    const msg = String((x && x.message) || x || '');
    // The bot's own "not JSON" note is kept; a response body never is.
    return (/^Discord \S+ \S+ -> \d{3}(?: \(the answer was not JSON\))?/.exec(msg) || [msg])[0];
  };
  return one(e) + (e && e.rearchiveError ? `; the re-archive failed too: ${one(e.rearchiveError)}` : '')
    + (e && e.keyError ? `; clearing the archive key failed too: ${one(e.keyError)}` : '');
};
const scrubbed = (fn) => async (...args) => {
  try {
    return await fn(...args);
  } catch (e) {
    throw new Error(brief(e));
  }
};

// The checklist's writers. `wanted(n, proof)` reads GitHub without writing
// and gives the thread's status name, its Accepted state, its archive key,
// whether the close it is keyed on is the issue's current one, whether the
// bot still files the issue, and the issue's records; `proof` is a release
// run's own `{ fix, tag }` when the tag list may not show that tag yet.
// `records(n)` gives the records alone.
export function checklistRunner({ gh, discord, repo, forumId, wanted, records, botIssue, log, settleTries }) {
  const plan = (w) => (applied, available) => planTags(applied, available, w.name, { names: CHECKLIST_NAMES, accepted: w.accepted, dropOther: false });
  const commentPath = (rec) => `/repos/${repo}/issues/comments/${rec.id}`;
  const write = (rec, over) => gh.call('PATCH', commentPath(rec), { body: checklistBody({ ...rec, ...over }) });
  // The record as it is now, read just before an archive decision. It must
  // still link the thread this run writes: an id staff changed meanwhile
  // is left for the issue's next checklist job to check, never saved here.
  async function fresh(rec) {
    const r = parseChecklist(await gh.call('GET', commentPath(rec)));
    if (!r) throw new Error(`the staff checklist record lost its marker (${rec.url})`);
    if (r.threadId !== rec.threadId || !r.linked) throw new Error(`the staff checklist record changed during this run (${rec.url}); the issue's next event checks it`);
    return r;
  }

  // Bring the thread in step with GitHub. The tag write keeps the archive
  // state, or opens the thread when a reopen overtook the close it was
  // archived for; then a finished close's archive is made. Each Discord
  // write comes before its key write, so a failure leaves a key that
  // differs from GitHub's, which the sweep names.
  async function mirrorTags(n, rec, proof = null) {
    const id = rec.threadId;
    const onThread = async (fn) => {
      try {
        return await fn();
      } catch (e) {
        if (postGone(e, id)) throw new Error(`staff checklist thread is gone (${rec.url})`);
        throw e;
      }
    };
    for (let i = 0; i < settleTries; i++) {
      const w = await wanted(n, proof);
      if (!w.eligible) {
        log(`#${n}: no longer an issue the bot filed; its checklist thread is left as it is`);
        return;
      }
      if (!w.closeKnown) throw new Error('the issue is closed but its close event is not readable yet');
      let cur = await fresh(rec);
      const reopen = !w.key && !!cur.archived;
      let r;
      try {
        r = await onThread(() => discord.setTags(id, forumId, plan(w), { open: reopen }));
      } catch (e) {
        // A finished thread the write may have left open owes its archive
        // again. The re-archive may have landed with its answer lost, so the
        // thread is read first: one shown archived keeps its key, and a later
        // staff reply is never archived over for it.
        // Only the thread's own channel is read: its archived flag is all
        // this needs.
        if (e.rearchive && w.key && cur.archived === w.key) {
          const seen = await discord.call('GET', `/channels/${id}`).catch(() => null);
          const archived = !!(seen && seen.thread_metadata && seen.thread_metadata.archived);
          if (!archived) await write(cur, { archived: null }).catch((k) => Object.assign(e, { keyError: k }));
        }
        throw e;
      }
      if (reopen) {
        cur = { ...cur, archived: null };
        await write(cur, {});
      }
      // The same key on an open thread means staff reopened it.
      if (w.key && cur.archived !== w.key) {
        if (!r.archived) await onThread(() => discord.archive(id));
        await write(cur, { archived: w.key });
      }
      if (r.missing) throw new Error(`checklist forum has no "${w.name}" tag`);
      // Settled when a write now would change nothing and GitHub still wants
      // the same; the slot and tag notes come from that same read.
      const shown = await onThread(() => discord.threadState(id));
      const back = plan(w)(shown.applied, shown.available);
      if (back.missing) throw new Error(`checklist forum has no "${w.name}" tag`);
      const again = await wanted(n, proof);
      if (sameTags(back.tags, shown.applied) && again.eligible && again.closeKnown && again.name === w.name && again.accepted === w.accepted && again.key === w.key) {
        if (back.full) log(`#${n}: no free tag slot for "${w.name}" on the checklist thread`);
        if (back.noRoom) log(`#${n}: no free tag slot for Accepted on the checklist thread`);
        if (w.accepted && back.noAccepted) log(`#${n}: the checklist forum has no Accepted tag`);
        return;
      }
    }
    throw new Error(`staff checklist thread did not settle after ${settleTries} tries`);
  }

  // PR and release runs and the sweep keep a thread that exists in step;
  // none is ever opened here, and an issue with none costs one read. A
  // thread id staff entered by hand is left for the issue's next checklist
  // job, which checks it first.
  async function mirror(n, proof = null) {
    const rec = (await records(n)).checklist;
    if (rec && rec.threadId && rec.linked) await mirrorTags(n, rec, proof);
  }

  async function open(n) {
    if (!(await botIssue(n))) return;
    const rec = (await records(n)).checklist;
    if (rec && rec.threadId) await mirrorTags(n, rec);
    else log(`#${n}: no staff checklist thread yet`);
  }

  return { open: scrubbed(open), mirror: scrubbed(mirror) };
}
