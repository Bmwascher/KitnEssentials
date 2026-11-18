// Minimal Discord REST client. `fetchImpl` is injectable so tests never hit the network.
import { nextAppliedTags, currentStatus } from './core.js';

const API = 'https://discord.com/api/v10';

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
    // that already shows it is left alone. `from` is the status it showed.
    // `beforeMove(from)`, when given, runs once the post is known not to show
    // the status, before anything is written, even when the forum lacks the tag.
    async setStatus(threadId, statusName, beforeMove) {
      const thread = await call('GET', `/channels/${threadId}`);
      const forum = await call('GET', `/channels/${thread.parent_id}`);
      const from = currentStatus(thread.applied_tags, forum.available_tags);
      const tags = nextAppliedTags(thread.applied_tags, forum.available_tags, statusName);
      if (from === statusName) return { from, tags };
      if (beforeMove) await beforeMove(from);
      if (!tags) return { from, skipped: `forum has no "${statusName}" tag` };
      const patch = { applied_tags: tags };
      if (thread.thread_metadata && thread.thread_metadata.archived) patch.archived = false;
      await call('PATCH', `/channels/${threadId}`, patch);
      return { from, tags };
    },
    async statusOf(threadId) {
      const thread = await call('GET', `/channels/${threadId}`);
      const forum = await call('GET', `/channels/${thread.parent_id}`);
      return currentStatus(thread.applied_tags, forum.available_tags);
    },
    async unarchive(threadId) {
      const thread = await call('GET', `/channels/${threadId}`);
      if (thread.thread_metadata && thread.thread_metadata.archived) {
        await call('PATCH', `/channels/${threadId}`, { archived: false });
      }
    },
  };
}
