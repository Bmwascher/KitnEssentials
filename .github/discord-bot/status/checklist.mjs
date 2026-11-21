// The staff checklist forum: one thread per bot issue in a staff-only forum,
// mirroring the issue. The thread's record is one bot comment on the issue.
import { CHECKLIST_NAMES, ACCEPTED, planTags, sameTags, threadName, discordText } from '../src/core.js';
import { postGone, answeredStatus } from '../src/discord.js';

// The search for a thread a lost create answer made: it reads threads made
// since a minute before the try, through two archived pages and 20 first
// messages at most.
const SEARCH_BACK_MS = 60 * 1000;
const SEARCH_PAGES = 2;
const MAX_CANDIDATES = 20;
// GitHub caps a title at 256 characters; with at most ten labels named, the
// first message stays far inside Discord's 2000.
const MAX_LABELS = 10;
// The bot's own tag names on a checklist thread, in any letter case.
const OWN = new Set([...CHECKLIST_NAMES, ACCEPTED].map((s) => s.toLowerCase()));
// One copy each, so a job's error and the sweep's line for the same case
// never drift apart.
const CLOSE_UNREAD = 'the issue is closed but its close event is not readable yet';
const noTag = (name) => `checklist forum has no "${name}" tag`;
const notOurs = (n) => `#${n}: no longer an issue the bot filed; its checklist thread is left as it is`;
// The first message's player post line, as `firstMessage` writes it.
const POST_LINE = /^Player post: https:\/\/discord\.com\/channels\/\d+\/(\d+)$/;

const link = (guildId, threadId) => `https://discord.com/channels/${guildId}/${threadId}`;
// A link needs the server's id; a record with none yet (an id put in a
// `pending` record by hand) is named by the bare id.
const place = (guildId, id) => (guildId ? link(guildId, id) : id);
const norm = (c) => String((c && c.body) || '').replace(/\r\n?/g, '\n');
const field = (body, name) => (new RegExp(`<!--\\s*discord-checklist-${name}:\\s*(.+?)\\s*-->`).exec(body) || [])[1] || null;

// The record. `state` is the thread's id, or `pending` (no thread yet) or
// `creating` (a create may have gone out). `forumId` is the forum the create
// was sent to, so a lost answer is searched for there; `since` is when that
// try began, `issueUrl` the issue's address then (a transfer changes it),
// and `archived` the key of the close the bot archived the thread for.
export function checklistBody({ id, state, guildId, forumId = '', since, issueUrl, archived = null }) {
  const thread = /^\d+$/.test(String(state));
  return [
    `Staff checklist thread: ${thread ? link(guildId, state) : 'opening'}`,
    '',
    `<!-- discord-checklist: ${state} guild: ${guildId || 'none'} -->`,
    // Written by the bot alone, for an id it made or checked, and bound to
    // this comment. Staff mending the marker or the visible line, or copying
    // a checked record into another issue's comment, never write it, so
    // their id is checked before any thread write.
    ...(thread ? [`<!-- discord-checklist-linked: ${state} comment: ${id} -->`] : []),
    ...(forumId ? [`<!-- discord-checklist-forum: ${forumId} -->`] : []),
    `<!-- discord-checklist-since: ${since} -->`,
    // A record with no saved address has no line. A record copied from
    // another issue names that issue's address, so a thread is taken only
    // when its first message also names this issue's player post.
    ...(issueUrl ? [`<!-- discord-checklist-issue: ${issueUrl} -->`] : []),
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
    // False for a thread id staff put in the marker by hand, a record
    // copied from another comment, or a comment a transfer renumbered.
    linked: !!threadId && field(body, 'linked') === `${threadId} comment: ${c.id}`,
    forumId: field(body, 'forum') || '', since: Number(field(body, 'since')) || 0, issueUrl: field(body, 'issue'), archived: field(body, 'archived'),
  };
}

// A Discord error's body can hold any text, a staff tag's name included, and
// the Actions log is public: an error leaving the runner keeps only each
// request and its status.
// The causes a writer keeps beside its first error, each named in the run's error.
const ALSO = [['rearchiveError', 'the re-archive failed too'], ['keyError', 'clearing the archive key failed too'], ['recordError', 'setting the record back to pending failed too']];
const brief = (e) => {
  // A Discord error is told from its request's fields, with the bot's own
  // "not JSON" note, never from its message; any other error's message is
  // the bot's own or GitHub's.
  const one = (x) => {
    const d = x && x.discord;
    if (d) return `Discord ${d.method} ${d.path} -> ${d.status}${d.notJson ? ' (the answer was not JSON)' : ''}`;
    return String((x && x.message) || x || '');
  };
  return one(e) + ALSO.map(([k, what]) => (e && e[k] ? `; ${what}: ${one(e[k])}` : '')).join('');
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
export function checklistRunner({ gh, discord, repo, forumId, wanted, records, botIssue, log, now, settleTries, owedMs }) {
  const plan = (w) => (applied, available) => planTags(applied, available, w.name, { names: CHECKLIST_NAMES, accepted: w.accepted, dropOther: false });
  const commentPath = (rec) => `/repos/${repo}/issues/comments/${rec.id}`;
  // The record as it is now, which must still be the one this run holds: a
  // record staff changed meanwhile is left for the issue's next checklist
  // job to check. GitHub has no compare-and-save, so it is read just before
  // every archive decision and every record write.
  async function current(rec) {
    const r = parseChecklist(await gh.call('GET', commentPath(rec)));
    if (!r) throw new Error(`the staff checklist record lost its marker (${rec.url})`);
    if (r.state !== rec.state || r.linked !== !!rec.linked) throw new Error(`the staff checklist record changed during this run (${rec.url}); the issue's next event checks it`);
    return r;
  }
  // `rec` is the record as this run last read or wrote it; `over` is the
  // change, or a function giving it from the record as just read. It is laid
  // on that read, so anything else staff changed in the record stays.
  async function write(rec, over) {
    const seen = await current(rec);
    const change = typeof over === 'function' ? over(seen) : over;
    await gh.call('PATCH', commentPath(rec), { body: checklistBody({ ...seen, ...change }) });
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
        log(notOurs(n));
        return;
      }
      if (!w.closeKnown) throw new Error(CLOSE_UNREAD);
      let cur = await current(rec);
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

  // The checklist job: a record and a thread when there is none yet, then
  // the whole thread settled from GitHub, whatever event started the job.
  async function open(n) {
    if (!(await botIssue(n))) return;
    const w = await wanted(n);
    if (!w.eligible) return;
    // Before any write: a thread opened or taken now could not be archived
    // for a close GitHub does not show yet.
    if (!w.closeKnown) throw new Error(CLOSE_UNREAD);
    // A record whose marker no longer parses is not "no record": a new one
    // could make a second thread. Nothing is written until staff mend it.
    if (!w.st.records.checklist && w.st.records.checklistDamaged) throw new Error(damagedLine(w.st.records.checklistDamaged));
    let rec = w.st.records.checklist;
    if (rec && rec.threadId && !rec.linked) {
      rec = await confirm(n, w, rec);
      if (!rec) return;
    }
    if (!rec) {
      const at = now();
      const body = checklistBody({ state: 'pending', guildId: '', since: at, issueUrl: w.issue.html_url });
      const c = await gh.call('POST', `/repos/${repo}/issues/${n}/comments`, { body });
      rec = { id: c.id, url: c.html_url || '', state: 'pending', threadId: null, guildId: '', forumId: '', since: at, issueUrl: w.issue.html_url, archived: null };
    }
    if (!rec.threadId) rec = rec.state === 'creating' ? await adopt(n, w, rec) : await create(n, rec);
    if (rec) await mirrorTags(n, rec);
  }

  // What the thread mirrors, and the line the search matches (`Issue: <url>`).
  const firstMessage = (w, guildId) => {
    const kinds = (w.issue.labels || []).map((l) => l.name || l).filter((l) => /^(type|client): /.test(l)).slice(0, MAX_LABELS);
    return [
      `**${discordText(w.issue.title)}**`,
      `Issue: ${w.issue.html_url}`,
      `Player post: https://discord.com/channels/${guildId}/${w.postId}`,
      ...(kinds.length ? [kinds.join(' · ')] : []),
      'The bot sets the status and Accepted tags from GitHub; every other tag is yours.',
    ].join('\n');
  };

  // `pending` makes the next job create at once, so it is offered only for
  // a record staff are sure has no thread; `creating` sends the job to look
  // for one first.
  // The marker is quoted as inline code: the job summary is Markdown, which
  // would hide it as an HTML comment.
  const damagedLine = (url) => `the staff checklist record (${url}) cannot be read: mend it so its hidden marker line reads \`<!-- discord-checklist: THREAD-ID guild: SERVER-ID -->\`, with the thread's id and its server's id. `
    + 'If you are not sure a thread was made for it, put "creating" in place of THREAD-ID, and the issue\'s next event looks for one. '
    + 'Put "pending" there, or delete the comment, only once you are sure no thread was made for it; the issue\'s next event then opens one';

  // Every opener write first reads GitHub again, after its Discord reads:
  // an issue that stopped being the bot's, or closed with its close event
  // not readable yet, gets no write, and its next event or the sweep
  // settles it. It gives that read, or null.
  async function stillOpenable(n) {
    const again = await wanted(n);
    if (!again.eligible) {
      log(notOurs(n));
      return null;
    }
    if (!again.closeKnown) throw new Error(CLOSE_UNREAD);
    return again;
  }

  // A `creating` record whose create was never sent, or was refused, goes
  // back to `pending`, so the next job opens at once. A failed set-back is
  // kept beside the cause, which may name the permission to fix.
  const setBack = (rec, e) => write(rec, { state: 'pending' }).catch((r) => {
    Object.assign(e, { recordError: r });
  });

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
    tagsFor(ready, forum);
    // Marked just before the create, with the forum it goes to, so a lost
    // answer is searched for there.
    const trying = { ...rec, state: 'creating', guildId, forumId, since: now(), issueUrl: ready.issue.html_url };
    await write(rec, trying);
    // The save is a request of its own, so GitHub is read once more, then
    // the forum, last, so a status tag renamed meanwhile is seen; the thread
    // is planned from both. No create has gone out yet: a stop here sets the
    // record back.
    let cur;
    let tags;
    try {
      cur = await stillOpenable(n);
      if (cur) tags = tagsFor(cur, await discord.getChannel(forumId));
    } catch (e) {
      await setBack(trying, e);
      throw e;
    }
    if (!cur) {
      await write(trying, { state: 'pending' });
      return null;
    }
    let made;
    try {
      made = await discord.createThread(forumId, { name: threadName(n, cur.issue.title), content: firstMessage(cur, guildId), tagIds: tags });
    } catch (e) {
      // A refusal made nothing: the next job opens at once, with no search.
      const status = answeredStatus(e, 'POST', `/channels/${forumId}/threads`) || 0;
      if (status >= 400 && status < 500) await setBack(trying, e);
      throw e;
    }
    // An answer with no thread id says nothing of what was made: the record
    // stays `creating`, so the next job looks for the thread.
    if (!made || !/^\d+$/.test(String(made.id))) throw new Error('the create was answered with no thread id; the issue\'s next event looks for the thread');
    await write(trying, { state: made.id });
    return { ...trying, state: made.id, threadId: made.id, linked: true };
  }

  // Whether a thread's first message is the bot's and names this issue: one
  // of its addresses (`issue.urls`) and the player post it was filed from.
  // The post comes from the issue's own body, so a transfer keeps it and a
  // record copied from another issue cannot change it. A thread whose first
  // message is gone names nothing.
  async function namesIssue(threadId, me, issue) {
    const first = await discord.getMessage(threadId, threadId).catch((e) => {
      if (answeredStatus(e, 'GET', `/channels/${threadId}/messages/${threadId}`) === 404) return null;
      throw e;
    });
    if (!first || !first.author || first.author.id !== me.id) return false;
    const said = String(first.content || '').split('\n');
    return said.some((l) => l.startsWith('Issue: ') && issue.urls.has(l.slice('Issue: '.length)))
      && said.some((l) => (POST_LINE.exec(l) || [])[1] === issue.postId);
  }
  // The issue's address now and the one its record saved at the try, and its post.
  const issueOf = (w, rec) => ({ urls: new Set([w.issue.html_url, rec.issueUrl].filter(Boolean)), postId: w.postId });
  // A record read with no saved address (a first `pending` post, or one staff
  // mended) takes the issue's address now, so a later transfer still finds
  // its thread.
  const address = (seen, w) => (seen.issueUrl ? {} : { issueUrl: w.issue.html_url });

  // A create whose answer was lost may have made a thread. It is found by
  // the bot's own first message naming the issue, never by name, which staff
  // can change. Every listed thread is read, or no match counts: an unread
  // one may be the match.
  async function search(rec, issue) {
    try {
      const list = await discord.threadsSince(rec.guildId, rec.forumId || forumId, rec.since - SEARCH_BACK_MS, SEARCH_PAGES);
      if (!list.complete) return { why: 'the archived listing stops short' };
      if (list.threads.length > MAX_CANDIDATES) return { why: `more than ${MAX_CANDIDATES} threads were made since` };
      const me = await discord.me();
      const matches = [];
      for (const t of list.threads) if (await namesIssue(t.id, me, issue)) matches.push(t.id);
      if (matches.length > 1) return { why: `${matches.length} bot threads name the issue` };
      return matches.length ? { id: matches[0] } : { why: 'no bot thread names the issue' };
    } catch (e) {
      return { why: brief(e) };
    }
  }

  // A thread id staff put in the record by hand passes the same check as an
  // adopted thread: it sits in the forum the create went to, its first
  // message is the bot's and names the issue, and GitHub still allows the
  // write. The record is then written in full, so its line links the thread.
  async function confirm(n, w, rec) {
    // Only a gone thread is a wrong id; any other failed read is thrown, so
    // a re-run can retry it and staff are not told to undo a right id.
    const ch = await discord.call('GET', `/channels/${rec.threadId}`).catch((e) => {
      if (postGone(e, rec.threadId)) return null;
      throw e;
    });
    const inForum = !!ch && String(ch.parent_id) === String(rec.forumId || forumId);
    if (!inForum || !(await namesIssue(rec.threadId, await discord.me(), issueOf(w, rec)))) {
      throw new Error(`the staff checklist record (${rec.url}) names thread ${rec.threadId}, which is not the bot's thread for this issue in the forum its create went to: put back the right id, or "creating"`);
    }
    if (!(await stillOpenable(n))) return null;
    // A `pending` record has no server or forum yet; the thread gives both,
    // so the saved link works.
    await write(rec, (seen) => ({ ...(seen.guildId ? {} : { guildId: String(ch.guild_id) }), ...(seen.forumId ? {} : { forumId }), ...address(seen, w) }));
    return { ...rec, linked: true };
  }

  // For a `creating` record. It never creates: only exactly one match is
  // taken, so the bot never makes a second thread for a record, and anything
  // else is left for staff through the sweep.
  async function adopt(n, w, rec) {
    const s = await search(rec, issueOf(w, rec));
    if (!s.id) throw new Error(`staff checklist thread not confirmed (${s.why}); see the sweep`);
    if (!(await stillOpenable(n))) return null;
    await write(rec, (seen) => ({ state: s.id, ...address(seen, w) }));
    return { ...rec, state: s.id, threadId: s.id, linked: true };
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
    // No checklist write is made until the close is readable, so nothing
    // else is judged; listed with or without a record, as a first open can
    // have failed on it.
    if (!w.closeKnown) {
      parts.push(`${CLOSE_UNREAD}: the checklist ${here ? `thread (${here})` : rec ? `record (${rec.url})` : 'thread'} is checked at the next sweep`);
      return { parts, repair: false, unread: null };
    }
    if (!rec) {
      if (w.st.records.checklistDamaged) parts.push(damagedLine(w.st.records.checklistDamaged));
      else if (w.issue.state === 'open') parts.push("no staff checklist thread (the issue's next event, a close, a reopen, or the accepted label added or removed, opens one)");
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
        parts.push(`staff checklist thread not confirmed (${rec.url}): the issue's next event, or a re-run of its failed checklist job, looks for it. `
          + `If this stays, look in the checklist forum ${place(rec.guildId, rec.forumId || forumId)} for the bot's threads whose first message names ${urls} and the player post ${place(rec.guildId, w.postId)}. `
          + 'With more than one, keep the oldest and delete the rest, and the next event takes it. '
          + 'If the job still fails (too many threads made since, or the listing stops short), put the thread\'s id in place of "creating" in that comment, and the next event checks it and takes it. '
          + `If there is none, delete that comment only once you are sure no thread there is this issue's: a thread whose first message was deleted can be, and its name started "#${named} " unless someone renamed it. `
          + 'Then the next event opens a new thread. If you are not sure, leave the comment, and this line stays');
      } else {
        parts.push(`staff checklist thread not opened (${rec.url}): the issue's next event opens it`);
      }
    }
    if (!rec.threadId) return { parts, repair, unread: null };
    if (!rec.linked) {
      parts.push(`staff checklist thread ${here} is not confirmed yet (${rec.url}): its id was put in by hand, or the record was copied or renumbered. The issue's next event checks that it is the bot's thread for this issue and takes it`);
      return { parts, repair: false, unread: null };
    }
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
      return { parts, repair: !!keyPart, unread: new Error(brief(e)) };
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
    return { parts, repair, unread: null };
  }

  return { open: scrubbed(open), mirror: scrubbed(mirror), lines: scrubbed(lines) };
}
