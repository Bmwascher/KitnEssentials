// Minimal Discord REST client. `fetchImpl` is injectable so tests never hit the network.
import { nextAppliedTags, currentStatus, otherTags, sameTags, snowflakeMs, planTags, withAccepted, shownStatuses, triagedAlone, showsAccepted, forumTags } from './core.js';

const API = 'https://discord.com/api/v10';

// A post is gone only when a request for the post itself (its read or its
// tag write) answers 404; a 404 from its forum, or from GitHub, says nothing
// about the post.
export const postGone = (err, threadId) => new RegExp(`^Discord (?:GET|PATCH) /channels/${threadId} -> 404 `)
  .test(String((err && err.message) || ''));

// The HTTP status a Discord request answered with, when `err` is the error
// of that request (`method` and `path`), else null. Only the prefix is read:
// the response body after it can hold any text.
export function answeredStatus(err, method, path) {
  const m = /^Discord (\S+) (\S+) -> (\d{3}) /.exec(String((err && err.message) || ''));
  return m && m[1] === method && m[2] === path ? Number(m[3]) : null;
}

export const archivedOf = (t) => !!(t.thread_metadata && t.thread_metadata.archived);

export function discordClient(token, fetchImpl = fetch) {
  async function call(method, path, body) {
    const res = await fetchImpl(`${API}${path}`, {
      method,
      headers: {
        Authorization: `Bot ${token}`,
        'Content-Type': 'application/json',
        'User-Agent': 'DiscordBot (https://github.com, 1.0)',
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    // Kept apart from the message, so a caller that must never log a
    // response body never has to parse one out.
    const request = { method, path, status: res.status };
    if (!res.ok) {
      const text = await res.text().catch(() => '');
      throw Object.assign(new Error(`Discord ${method} ${path} -> ${res.status} ${text.slice(0, 300)}`), { discord: request });
    }
    if (res.status === 204) return null;
    // The parser's own message can quote the body, which may hold a staff
    // tag's name; the request and its status say enough.
    return res.json().catch(() => {
      throw Object.assign(new Error(`Discord ${method} ${path} -> ${res.status} (the answer was not JSON)`), { discord: { ...request, notJson: true } });
    });
  }

  // `onForum(forumId, tags)` sees each read of a forum as it lands, so a
  // caller keeps what a read showed even when a later step fails.
  const seeForum = (onForum, id, channel) => {
    const tags = forumTags(channel);
    if (tags) onForum(id, tags);
  };

  async function threadAndForum(threadId) {
    const thread = await call('GET', `/channels/${threadId}`);
    const forum = await call('GET', `/channels/${thread.parent_id}`);
    return { thread, forum };
  }

  // One forum's archived threads, newest first, back to those archived at
  // `since` (epoch ms), up to a few pages. `cut` is the archive time it
  // stopped at when the page limit came first, or, with `ties`, true when
  // a page said more follow but gave no time to go on from. Discord's
  // `before` is exclusive, so a thread archived at the same time as a
  // page's last one can be skipped; the daily check accepts that for its count of posts.
  // With `ties`, for the search, which needs every thread more than many,
  // each next page starts a millisecond later, repeats are dropped by id,
  // and a page that brings nothing new ends the listing as cut short.
  async function archivedThreads(forumId, since, pages, { ties = false } = {}) {
    const out = [];
    const seen = ties ? new Set() : null;
    let before = '';
    for (let page = 0; page < pages; page++) {
      const arch = await call('GET', `/channels/${forumId}/threads/archived/public?limit=50${before}`);
      const threads = arch.threads || [];
      const fresh = ties ? threads.filter((t) => !seen.has(t.id)) : threads;
      if (ties) for (const t of fresh) seen.add(t.id);
      out.push(...fresh);
      const oldest = threads.at(-1);
      const stamp = oldest && oldest.thread_metadata && oldest.thread_metadata.archive_timestamp;
      if (ties && arch.has_more && !stamp) return { threads: out, cut: true };
      if (!arch.has_more || !stamp || Date.parse(stamp) < since) return { threads: out, cut: null };
      if (ties && !fresh.length) break;
      before = `&before=${encodeURIComponent(ties ? new Date(Date.parse(stamp) + 1).toISOString() : stamp)}`;
    }
    return { threads: out, cut: out.at(-1).thread_metadata.archive_timestamp };
  }

  return {
    call,
    getChannel: (id) => call('GET', `/channels/${id}`),
    getMessage: (channelId, messageId) => call('GET', `/channels/${channelId}/messages/${messageId}`),
    // `{ message }`, or `{ message: null, channel }` when it was deleted. A
    // deleted channel's messages answer 404 too, so the channel is read then:
    // its own 404 is thrown, so a deleted post is never taken for a deleted
    // message, and its answer is returned, so the caller decides from the
    // post as it is now.
    async readMessage(channelId, messageId) {
      try {
        return { message: await call('GET', `/channels/${channelId}/messages/${messageId}`) };
      } catch (e) {
        if (!/ -> 404 /.test(e.message)) throw e;
        return { message: null, channel: await call('GET', `/channels/${channelId}`) };
      }
    },
    // The bot's own user: only its messages count as its greeting or card.
    me: () => call('GET', '/users/@me'),
    // Never pings anyone unless a user id is passed, or it replies, which
    // pings the target's author. A reply Discord refuses (400: a system
    // message as the target) was never posted, so it goes once more as a
    // plain message, marked `replyRefused`.
    async send(channelId, content, pingUserIds = [], { replyTo = null } = {}) {
      const plainBody = { content, allowed_mentions: { parse: [], users: pingUserIds } };
      if (!replyTo) return call('POST', `/channels/${channelId}/messages`, plainBody);
      try {
        return await call('POST', `/channels/${channelId}/messages`, {
          content,
          allowed_mentions: { ...plainBody.allowed_mentions, replied_user: true },
          message_reference: { message_id: replyTo, fail_if_not_exists: false },
        });
      } catch (e) {
        if (!/ -> 400 /.test(e.message)) throw e;
        return { ...(await call('POST', `/channels/${channelId}/messages`, plainBody)), replyRefused: true };
      }
    },
    // Swap the status tag on a forum post, keeping every other tag. A post
    // that already shows the status, wherever its tag sits, is left alone,
    // archived or not. `from` is the status it showed. `beforeMove(from)`,
    // when given, runs once the post is known not to show the status, before
    // anything is written, even when nothing can be written.
    // Discord takes only a whole tag list, so the forum's tags and then the
    // post are read again just before the write, the post last so the write
    // follows its read at once: a tag added, or a status tag renamed,
    // meanwhile is seen, and a status another writer set meanwhile
    // stops the write (`raced`), so the caller decides again from what the
    // post shows. A move unarchives the post, as before. With `dropOther`
    // false, a post with no status and five other tags is left as it is
    // rather than lose one of them.
    async setStatus(threadId, statusName, beforeMove, { dropOther = true, accepted = null, onForum = () => {} } = {}) {
      const { thread, forum } = await threadAndForum(threadId);
      seeForum(onForum, String(thread.parent_id), forum);
      const from = currentStatus(thread.applied_tags, forum.available_tags, statusName);
      if (from === statusName) return { from, tags: thread.applied_tags || [] };
      if (beforeMove) await beforeMove(from);
      const plan = (t, avail) => {
        const applied = t.applied_tags || [];
        // With `accepted` true or false the move also adds the Accepted tag,
        // in a free slot only, or removes it; null (the Worker) plans as before.
        if (accepted !== null) {
          const p = planTags(applied, avail, statusName, { accepted, dropOther });
          if (p.missing) return { skipped: `forum has no "${statusName}" tag` };
          if (p.full) return { skipped: `no free tag slot for "${statusName}"` };
          return { tags: p.tags, noRoom: p.noRoom, noAccepted: accepted && p.noAccepted };
        }
        const tags = nextAppliedTags(applied, avail, statusName);
        if (!tags) return { skipped: `forum has no "${statusName}" tag` };
        if (!dropOther && otherTags(applied, avail).length >= 5) return { skipped: `no free tag slot for "${statusName}"` };
        return { tags };
      };
      let p = plan(thread, forum.available_tags);
      if (p.skipped) return { from, skipped: p.skipped };
      const freshForum = await call('GET', `/channels/${thread.parent_id}`);
      seeForum(onForum, String(thread.parent_id), freshForum);
      const fresh = await call('GET', `/channels/${threadId}`);
      // A post moved to another forum meanwhile is decided again from there.
      if (fresh.parent_id !== thread.parent_id
        || currentStatus(fresh.applied_tags, freshForum.available_tags, statusName) !== from) return { from, raced: true };
      p = plan(fresh, freshForum.available_tags);
      if (p.skipped) return { from, skipped: p.skipped };
      const patch = { applied_tags: p.tags };
      if (archivedOf(fresh)) patch.archived = false;
      await call('PATCH', `/channels/${threadId}`, patch);
      return { from, tags: p.tags, noRoom: !!p.noRoom, noAccepted: !!p.noAccepted };
    },
    // The sweep's Accepted-only write. It writes only on an active post that
    // shows Triaged and no other status tag, at its first read and again just
    // before the write, and changes only the Accepted tag, so a status move
    // that lands inside its last request is put back to Triaged alone, under
    // the tag names last read. It never sends `archived`.
    async fixAccepted(threadId, want, { onForum = () => {} } = {}) {
      const out = (r) => ({ wrote: false, noRoom: false, noAccepted: false, archived: false, refused: false, raced: false, ...r });
      const alone = (t, avail) => triagedAlone(shownStatuses(t.applied_tags, avail));
      const { thread, forum } = await threadAndForum(threadId);
      seeForum(onForum, String(thread.parent_id), forum);
      if (archivedOf(thread)) return out({ archived: true });
      if (!alone(thread, forum.available_tags)) return out({ refused: true });
      // Already as wanted: a post showing another Accepted tag shows it.
      const inStep = (t, avail, q) => want === showsAccepted(t.applied_tags, avail) || sameTags(q.tags, t.applied_tags || []);
      let p = withAccepted(thread.applied_tags || [], forum.available_tags, want);
      if (inStep(thread, forum.available_tags, p)) return out({ noRoom: p.noRoom, noAccepted: p.noAccepted });
      const freshForum = await call('GET', `/channels/${thread.parent_id}`);
      seeForum(onForum, String(thread.parent_id), freshForum);
      const fresh = await call('GET', `/channels/${threadId}`);
      if (fresh.parent_id !== thread.parent_id) return out({ raced: true });
      if (archivedOf(fresh)) return out({ archived: true });
      if (!alone(fresh, freshForum.available_tags)) return out({ raced: true });
      p = withAccepted(fresh.applied_tags || [], freshForum.available_tags, want);
      if (inStep(fresh, freshForum.available_tags, p)) return out({ noRoom: p.noRoom, noAccepted: p.noAccepted });
      await call('PATCH', `/channels/${threadId}`, { applied_tags: p.tags });
      return out({ wrote: true });
    },
    async unarchive(threadId) {
      const thread = await call('GET', `/channels/${threadId}`);
      if (thread.thread_metadata && thread.thread_metadata.archived) {
        await call('PATCH', `/channels/${threadId}`, { archived: false });
      }
    },
    archive: (threadId) => call('PATCH', `/channels/${threadId}`, { archived: true }),
    archivedThreads,
    // The checklist's only tag writer. Discord takes only a whole tag list,
    // so the forum and then the thread are read just before the write, the
    // thread last, and nothing runs between that read and the write: a tag
    // added meanwhile is kept. A thread outside `forumId` is never written,
    // and a plan whose status tag the forum lacks writes no tags. An
    // archived thread must be opened to change its tags; it is archived
    // again in the next request unless `open` asks to leave it open (a
    // reopen overtook the close it was archived for). A refused first write
    // changed nothing. Any other failure may have opened the thread before
    // its answer was lost, so the re-archive is still sent; when it cannot
    // be made, the error is thrown marked `rearchive`.
    // `onForum(forumId, tags)` sees the forum read once the thread is
    // confirmed in that forum, before any write can fail: a forum the thread
    // is not in has nothing to fix for it.
    async setTags(threadId, forumId, plan, { open = false, onForum = () => {} } = {}) {
      const path = `/channels/${threadId}`;
      const forum = await call('GET', `/channels/${forumId}`);
      const thread = await call('GET', path);
      if (String(thread.parent_id) !== String(forumId)) {
        throw new Error(`staff checklist thread is in channel ${thread.parent_id}, not the checklist forum`);
      }
      seeForum(onForum, String(forum.id), forum);
      const applied = thread.applied_tags || [];
      const p = plan(applied, forum.available_tags || []);
      const archived = archivedOf(thread);
      const retag = !p.missing && !sameTags(p.tags, applied);
      if (!retag && !(open && archived)) return { ...p, wrote: false, archived };
      const keep = archived && !open;
      const rearchive = () => call('PATCH', path, { archived: true });
      try {
        await call('PATCH', path, { ...(retag ? { applied_tags: p.tags } : {}), ...(archived ? { archived: false } : {}) });
      } catch (e) {
        const status = answeredStatus(e, 'PATCH', path) || 0;
        if (!keep || (status >= 400 && status < 500)) throw e;
        // Both causes are kept: the re-archive's may name the permission to fix.
        const again = await rearchive().then(() => null, (r) => r);
        throw again ? Object.assign(e, { rearchive: true, rearchiveError: again }) : e;
      }
      if (keep) {
        try {
          await rearchive();
        } catch (e) {
          throw Object.assign(e, { rearchive: true });
        }
      }
      return { ...p, wrote: true, archived };
    },
    // A thread's parent, its tags, its own forum's tags and its archive state.
    async threadState(threadId) {
      const { thread, forum } = await threadAndForum(threadId);
      return { parentId: String(thread.parent_id), applied: thread.applied_tags || [], available: forum.available_tags || [], tags: forumTags(forum), archived: archivedOf(thread) };
    },
    createThread: (forumId, { name, content, tagIds }) => call('POST', `/channels/${forumId}/threads`, {
      name, applied_tags: tagIds, message: { content, allowed_mentions: { parse: [] } },
    }),
    // A forum's threads made at or after `sinceMs`: the active list, the
    // archived list back to that time, then the active list again, merged. A
    // thread that moves once between the lists while they are read is in one
    // of them; one that moves twice can be missed. A thread archived before
    // `sinceMs` was made before it too. `complete` is false when the
    // archived pages ran out first.
    async threadsSince(guildId, forumId, sinceMs, pages) {
      const byId = new Map();
      const take = (list) => {
        for (const t of list || []) if (t.parent_id === forumId && snowflakeMs(t.id) >= sinceMs) byId.set(t.id, t);
      };
      take((await call('GET', `/guilds/${guildId}/threads/active`)).threads);
      const arch = await archivedThreads(forumId, sinceMs, pages, { ties: true });
      take(arch.threads);
      take((await call('GET', `/guilds/${guildId}/threads/active`)).threads);
      return { threads: [...byId.values()], complete: !arch.cut };
    },
  };
}
