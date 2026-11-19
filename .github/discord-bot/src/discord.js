// Minimal Discord REST client. `fetchImpl` is injectable so tests never hit the network.
import { nextAppliedTags, currentStatus, otherTags } from './core.js';

const API = 'https://discord.com/api/v10';

// A post is gone only when a request for the post itself (its read or its
// tag write) answers 404; a 404 from its forum, or from GitHub, says nothing
// about the post.
export const postGone = (err, threadId) => new RegExp(`^Discord (?:GET|PATCH) /channels/${threadId} -> 404 `)
  .test(String((err && err.message) || ''));

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
    if (!res.ok) {
      const text = await res.text().catch(() => '');
      throw new Error(`Discord ${method} ${path} -> ${res.status} ${text.slice(0, 300)}`);
    }
    return res.status === 204 ? null : res.json();
  }

  async function threadAndForum(threadId) {
    const thread = await call('GET', `/channels/${threadId}`);
    const forum = await call('GET', `/channels/${thread.parent_id}`);
    return { thread, forum };
  }
  const archivedOf = (t) => !!(t.thread_metadata && t.thread_metadata.archived);

  return {
    call,
    getChannel: (id) => call('GET', `/channels/${id}`),
    getMessage: (channelId, messageId) => call('GET', `/channels/${channelId}/messages/${messageId}`),
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
    async setStatus(threadId, statusName, beforeMove, { dropOther = true } = {}) {
      const { thread, forum } = await threadAndForum(threadId);
      const from = currentStatus(thread.applied_tags, forum.available_tags, statusName);
      if (from === statusName) return { from, tags: thread.applied_tags || [] };
      if (beforeMove) await beforeMove(from);
      const plan = (t, avail) => {
        const applied = t.applied_tags || [];
        const tags = nextAppliedTags(applied, avail, statusName);
        if (!tags) return { skipped: `forum has no "${statusName}" tag` };
        if (!dropOther && otherTags(applied, avail).length >= 5) return { skipped: `no free tag slot for "${statusName}"` };
        return { tags };
      };
      let p = plan(thread, forum.available_tags);
      if (p.skipped) return { from, skipped: p.skipped };
      const freshForum = await call('GET', `/channels/${thread.parent_id}`);
      const fresh = await call('GET', `/channels/${threadId}`);
      // A post moved to another forum meanwhile is decided again from there.
      if (fresh.parent_id !== thread.parent_id
        || currentStatus(fresh.applied_tags, freshForum.available_tags, statusName) !== from) return { from, raced: true };
      p = plan(fresh, freshForum.available_tags);
      if (p.skipped) return { from, skipped: p.skipped };
      const patch = { applied_tags: p.tags };
      if (archivedOf(fresh)) patch.archived = false;
      await call('PATCH', `/channels/${threadId}`, patch);
      return { from, tags: p.tags };
    },
    // With `prefer`, a post carrying that status tag shows it, wherever it sits.
    async statusOf(threadId, prefer = null) {
      const { thread, forum } = await threadAndForum(threadId);
      return currentStatus(thread.applied_tags, forum.available_tags, prefer);
    },
    async unarchive(threadId) {
      const thread = await call('GET', `/channels/${threadId}`);
      if (thread.thread_metadata && thread.thread_metadata.archived) {
        await call('PATCH', `/channels/${threadId}`, { archived: false });
      }
    },
  };
}
