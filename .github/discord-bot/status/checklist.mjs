// The staff checklist forum: one thread per bot issue in a staff-only forum,
// mirroring the issue. The thread's record is one bot comment on the issue.
import { CHECKLIST_NAMES, ACCEPTED, planTags, sameTags, threadName, discordText, hasTag, tagLine, acceptedLine } from '../src/core.js';
import { postGone, answeredStatus } from '../src/discord.js';

// GitHub caps a title at 256 characters; with at most ten labels named, the
// first message stays far inside Discord's 2000.
const MAX_LABELS = 10;
// The bot's own tag names on a checklist thread, in any letter case.
const OWN = new Set([...CHECKLIST_NAMES, ACCEPTED].map((s) => s.toLowerCase()));
// One copy each, so a job's error and the sweep's line for the same case
// never drift apart.
const noTag = (name) => `checklist forum has no "${name}" tag`;
const notOurs = (n) => `#${n}: no longer an issue the bot filed; its checklist thread is left as it is`;

const link = (guildId, threadId) => `https://discord.com/channels/${guildId}/${threadId}`;
// A link needs the server's id; a record with none yet (an id put in a
// `pending` record by hand) is named by the bare id.
const place = (guildId, id) => (guildId ? link(guildId, id) : id);
const norm = (c) => String((c && c.body) || '').replace(/\r\n?/g, '\n');
const field = (body, name) => (new RegExp(`<!--\\s*discord-checklist-${name}:\\s*(.+?)\\s*-->`).exec(body) || [])[1] || null;

// The record. `state` is the thread's id, or `pending` (no thread yet) or
// `creating` (a create may have gone out). `forumId` is the forum the create
// was sent to, where staff look for a lost answer's thread; `since` is when
// that try began, `issueUrl` the issue's address then (a transfer changes it),
// and `archived` the key of the close the bot archived the thread for.
export function checklistBody({ state, guildId, forumId = '', since, issueUrl, archived = null }) {
  const thread = /^\d+$/.test(String(state));
  return [
    `Staff checklist thread: ${thread ? link(guildId, state) : 'opening'}`,
    '',
    `<!-- discord-checklist: ${state} guild: ${guildId || 'none'} -->`,
    ...(forumId ? [`<!-- discord-checklist-forum: ${forumId} -->`] : []),
    `<!-- discord-checklist-since: ${since} -->`,
    // A record with no saved address has no line.
    ...(issueUrl ? [`<!-- discord-checklist-issue: ${issueUrl} -->`] : []),
    ...(archived ? [`<!-- discord-checklist-archived: ${archived} -->`] : []),
  ].join('\n');
}

// A thread's first message: what it mirrors. A move rewrites it with the
// same text.
export function checklistFirst({ title, issueUrl, guildId, postId, labels }) {
  const kinds = (labels || []).map((l) => l.name || l).filter((l) => /^(type|client): /.test(l)).slice(0, MAX_LABELS);
  return [
    `**${discordText(title)}**`,
    `Issue: ${issueUrl}`,
    `Player post: https://discord.com/channels/${guildId}/${postId}`,
    ...(kinds.length ? [kinds.join(' · ')] : []),
    'The bot sets the status and Accepted tags from GitHub; every other tag is yours.',
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
    forumId: field(body, 'forum') || '', since: Number(field(body, 'since')) || 0, issueUrl: field(body, 'issue'), archived: field(body, 'archived'),
  };
}

// A Discord error's body can hold any text, a staff tag's name included, and
// the Actions log is public: an error leaving the runner keeps only each
// request and its status.
// A Discord error is told from its request's fields, with the bot's own
// "not JSON" note, never from its message; any other error's message is the
// bot's own or GitHub's.
const brief = (x) => {
  const d = x && x.discord;
  if (d) return `Discord ${d.method} ${d.path} -> ${d.status}${d.notJson ? ' (the answer was not JSON)' : ''}`;
  return String((x && x.message) || x || '');
};
// The request record (method, path, status) holds no answer body, so it is
// kept: the status script names a refusal from it.
const scrub = (e) => Object.assign(new Error(brief(e)), { discord: e.discord });
const scrubbed = (fn) => async (...args) => {
  try {
    return await fn(...args);
  } catch (e) {
    throw scrub(e);
  }
};

// The checklist's writers. `wanted(n)` reads GitHub without writing and
// gives the thread's status name, its Accepted state, its archive key,
// whether the bot still files the issue, and the issue's records.
// `records(n)` gives the records alone.
export function checklistRunner({ gh, discord, repo, forumId, wanted, records, botIssue, log, now, settleTries, owedMs, noteRefusal, setupProblem, sweeping }) {
  const plan = (w) => (applied, available) => planTags(applied, available, w.name, { names: CHECKLIST_NAMES, accepted: w.accepted, dropOther: false });
  // A tag the checklist forum lacks is a setup problem, named by the id the
  // forum read answered with. A sweep checks its own read (`checkSeen`)
  // outside its timed checklist work and its repair checks none, so the
  // repair takes no more of that time than before.
  const checkTags = (w, id, tags, names) => {
    for (const s of names) if (!hasTag(tags, s)) setupProblem(tagLine(`checklist forum ${id}`, s));
    if (w.accepted && !hasTag(tags, ACCEPTED)) setupProblem(acceptedLine(`checklist forum ${id}`));
  };
  const commentPath = (rec) => `/repos/${repo}/issues/comments/${rec.id}`;
  // The record as it is now, which must still be the one this run holds: a
  // record staff changed meanwhile is left for the issue's next checklist
  // job to settle. GitHub has no compare-and-save, so it is read just before
  // every archive decision and every record write.
  async function current(rec) {
    const r = parseChecklist(await gh.call('GET', commentPath(rec)));
    if (!r) throw new Error(`the staff checklist record lost its marker (${rec.url})`);
    if (r.state !== rec.state) throw new Error(`the staff checklist record changed during this run (${rec.url}); the issue's next event settles it`);
    return r;
  }
  // `rec` is the record as this run last read or wrote it; `change` is laid
  // on the record as just read, so anything else staff changed there stays.
  async function write(rec, change) {
    const seen = await current(rec);
    await gh.call('PATCH', commentPath(rec), { body: checklistBody({ ...seen, ...change }) });
  }

  // Bring the thread in step with GitHub. The tag write keeps the archive
  // state, or opens the thread when a reopen overtook the close it was
  // archived for; then a finished close's archive is made. Each Discord
  // write comes before its key write, so a failure leaves a key that
  // differs from GitHub's, which the sweep names.
  async function mirrorTags(n, rec) {
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
      const w = await wanted(n);
      if (!w.eligible) {
        log(notOurs(n));
        return;
      }
      let cur = await current(rec);
      const reopen = !w.key && !!cur.archived;
      let r;
      try {
        r = await onThread(() => discord.setTags(id, forumId, plan(w), { open: reopen, onForum: sweeping ? undefined : (fid, tags) => checkTags(w, fid, tags, [w.name]) }));
      } catch (e) {
        noteRefusal(scrub(e));
        throw e;
      }
      if (reopen) {
        await write(cur, { archived: null });
        cur = { ...cur, archived: null };
      }
      // The same key on an open thread means staff reopened it.
      if (w.key && cur.archived !== w.key) {
        if (!r.archived) await onThread(() => discord.archive(id));
        await write(cur, { archived: w.key });
      }
      if (r.missing) throw new Error(noTag(w.name));
      // Settled when a write now would change nothing and GitHub still wants
      // the same; the slot and tag notes come from that same read.
      const shown = await onThread(() => discord.threadState(id));
      const back = plan(w)(shown.applied, shown.available);
      if (back.missing) throw new Error(noTag(w.name));
      const again = await wanted(n);
      if (sameTags(back.tags, shown.applied) && again.eligible && again.name === w.name && again.accepted === w.accepted && again.key === w.key) {
        if (back.full) log(`#${n}: no free tag slot for "${w.name}" on the checklist thread`);
        if (back.noRoom) log(`#${n}: no free tag slot for Accepted on the checklist thread`);
        if (w.accepted && back.noAccepted) log(`#${n}: the checklist forum has no Accepted tag`);
        return;
      }
    }
    throw new Error(`staff checklist thread did not settle after ${settleTries} tries`);
  }

  // PR and release runs and the sweep keep a thread that exists in step;
  // none is ever opened here, and an issue with none costs one read.
  async function mirror(n) {
    const rec = (await records(n)).checklist;
    if (rec && rec.threadId) await mirrorTags(n, rec);
  }

  // The checklist job: a record and a thread when there is none yet, then
  // the whole thread settled from GitHub, whatever event started the job.
  async function open(n) {
    if (!(await botIssue(n))) return;
    const w = await wanted(n);
    if (!w.eligible) return;
    let rec = w.st.records.checklist;
    if (!rec) {
      const at = now();
      const body = checklistBody({ state: 'pending', guildId: '', since: at, issueUrl: w.issue.html_url });
      const c = await gh.call('POST', `/repos/${repo}/issues/${n}/comments`, { body });
      rec = { id: c.id, url: c.html_url || '', state: 'pending', threadId: null, guildId: '', forumId: '', since: at, issueUrl: w.issue.html_url, archived: null };
    }
    // A `creating` record may have a thread already, so the bot never
    // creates again for it: staff settle it from the sweep's line.
    if (rec.state === 'creating') throw new Error(`staff checklist thread not confirmed (${rec.url}); see the sweep`);
    if (!rec.threadId) rec = await create(n, rec);
    if (rec) await mirrorTags(n, rec);
  }

  const firstMessage = (w, guildId) => checklistFirst({ title: w.issue.title, issueUrl: w.issue.html_url, guildId, postId: w.postId, labels: w.issue.labels });

  // The opener's write first reads GitHub again, after its Discord read: an
  // issue that stopped being the bot's gets no write, and its next event or
  // the sweep settles it. It gives that read, or null.
  async function stillOpenable(n) {
    const again = await wanted(n);
    if (!again.eligible) {
      log(notOurs(n));
      return null;
    }
    return again;
  }

  // For a `pending` record only: no create can have reached Discord yet.
  async function create(n, rec) {
    const forum = await discord.getChannel(forumId);
    const guildId = String(forum.guild_id);
    const tagsFor = (cur, f) => {
      const p = plan(cur)([], f.available_tags || []);
      if (p.missing) throw new Error(noTag(cur.name));
      return p.tags;
    };
    const ready = await stillOpenable(n);
    if (!ready) return null;
    const tags = tagsFor(ready, forum);
    // Marked just before the create, with the forum it goes to, so staff
    // know where to look for a lost answer's thread.
    const trying = { ...rec, state: 'creating', guildId, forumId, since: now(), issueUrl: ready.issue.html_url };
    await write(rec, trying);
    let made;
    try {
      made = await discord.createThread(forumId, { name: threadName(n, ready.issue.title), content: firstMessage(ready, guildId), tagIds: tags });
    } catch (e) {
      // A refusal made nothing: back to `pending`, so the next job opens at
      // once.
      const status = answeredStatus(e, 'POST', `/channels/${forumId}/threads`) || 0;
      if (status >= 400 && status < 500) await write(trying, { state: 'pending' });
      throw e;
    }
    await write(trying, { state: made.id });
    return { ...trying, state: made.id, threadId: made.id };
  }

  // The sweep's checklist lines for one issue, each saying what staff
  // should check; `w` is what `wanted` gives, from the sweep's own read.
  // The lines GitHub alone gives come first and stay whatever the thread's
  // read does. The thread is judged with the writer's own plan, so the two
  // never disagree. `repair`: a key or tag line, which fix mode repairs
  // with `mirror`; `unread`: the thread read's error.
  async function lines(n, w) {
    const parts = [];
    let repair = false;
    const rec = w.st.records.checklist;
    const at = now();
    const here = rec && rec.threadId ? place(rec.guildId, rec.threadId) : null;
    if (!rec) {
      if (w.issue.state === 'open') parts.push("no staff checklist thread (the issue's next event, a close, a reopen, or the accepted label added or removed, opens one)");
      return { parts, repair, unread: null };
    }
    if (!rec.threadId && at - rec.since > owedMs) {
      if (rec.state === 'creating') {
        // Built from the record alone: the bot never creates again for it,
        // so this line is the whole recovery, in the forum the create went to.
        const urls = [...new Set([rec.issueUrl, w.issue.html_url].filter(Boolean))].join(' or ');
        // The thread was named for the issue's number at the try, which a
        // transfer changes.
        const named = (/\/issues\/(\d+)$/.exec(rec.issueUrl || '') || [])[1] || n;
        parts.push(`staff checklist thread not confirmed (${rec.url}): a create may have made one, and the bot never creates again for this record. `
          + `Look in the checklist forum ${place(rec.guildId, rec.forumId || forumId)} for the bot's threads whose first message names ${urls} and the player post ${place(rec.guildId, w.postId)}. `
          + 'With more than one, keep the oldest and delete the rest. '
          + 'Put the thread\'s id in place of "creating" in that comment, and the next event takes it. '
          + `If there is none, delete that comment only once you are sure no thread there is this issue's: a thread whose first message was deleted can be, and its name started "#${named} " unless someone renamed it. `
          + 'Then the next event opens a new thread. If you are not sure, leave the comment, and this line stays');
      } else {
        parts.push(`staff checklist thread not opened (${rec.url}): the issue's next event opens it`);
      }
    }
    if (!rec.threadId) return { parts, repair, unread: null };
    // The key against GitHub's, whatever Discord's archived flag says. It is
    // listed once the thread read shows a repair can reach the thread.
    let keyPart = null;
    if (w.key && rec.archived !== w.key) {
      keyPart = `checklist archive owed (${here}): the issue is ${w.name}; a fix-mode sweep or the issue's next run archives it. If staff want it open, reply in it after that`;
    } else if (!w.key && rec.archived) {
      keyPart = `checklist archived for a close that no longer holds (${here}): the issue is ${w.name} now; a fix-mode sweep or the issue's next run opens it again`;
    }
    let shown;
    try {
      shown = await discord.threadState(rec.threadId);
    } catch (e) {
      if (postGone(e, rec.threadId)) {
        parts.push(`staff checklist thread is gone (${rec.url}): if it was deleted by mistake, delete that record comment and the issue's next event opens a new one`);
        return { parts, repair: false, unread: null };
      }
      if (keyPart) parts.push(keyPart);
      parts.push(`staff checklist thread not read (${here}): ${brief(e)}`);
      return { parts, repair: !!keyPart, unread: scrub(e) };
    }
    if (shown.parentId !== forumId) {
      parts.push(`staff checklist thread ${here} is not in the checklist forum: if CHECKLIST_FORUM_ID changed by mistake, set it back. `
        + `If it changed on purpose, archive or delete that thread as staff prefer, then delete that record comment (${rec.url}), and the issue's next event opens a new thread in the forum set now`);
      return { parts, repair: false, unread: null };
    }
    if (keyPart) {
      parts.push(keyPart);
      repair = true;
    }
    const p = plan(w)(shown.applied, shown.available);
    // Staff tag names stay out of the public log and job summary: only the
    // bot's own tags are named, and staff tags are counted.
    const nameOf = (id) => (shown.available.find((t) => t.id === id) || { name: '' }).name;
    const botTags = (ids) => ids.filter((id) => OWN.has(nameOf(id).toLowerCase()));
    const listed = (ids) => botTags(ids).map(nameOf).join(', ') || '(none)';
    if (p.missing) parts.push(`${noTag(w.name)} (${here}): add it, spelled as the README lists it`);
    else if (!sameTags(p.tags, shown.applied)) {
      parts.push(`checklist tags ${listed(shown.applied)} -> ${listed(p.tags)}, keeping ${p.tags.length - botTags(p.tags).length} staff tag(s) (${here})`);
      repair = true;
    }
    if (p.full) parts.push(`no free tag slot for "${w.name}" on the checklist thread (${here})`);
    if (p.noRoom) parts.push(`no free tag slot for Accepted on the checklist thread (${here})`);
    if (w.accepted && p.noAccepted) parts.push(`checklist forum has no Accepted tag (${here})`);
    return { parts, repair, unread: null, seen: shown.tags && { w, id: shown.parentId, tags: shown.tags } };
  }

  return { open: scrubbed(open), mirror: scrubbed(mirror), lines: scrubbed(lines), checkSeen: ({ w, id, tags }) => checkTags(w, id, tags, CHECKLIST_NAMES) };
}
