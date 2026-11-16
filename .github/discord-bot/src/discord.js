// Minimal Discord REST client. `fetchImpl` is injectable so tests never hit the network.
import { nextAppliedTags } from './core.js';

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
    // Never pings anyone unless a user id is passed explicitly.
    send: (channelId, content, pingUserIds = []) => call('POST', `/channels/${channelId}/messages`, {
      content,
      allowed_mentions: { parse: [], users: pingUserIds },
    }),
    // Swap the status tag on a forum post, keeping every other tag.
    async setStatus(threadId, statusName) {
      const thread = await call('GET', `/channels/${threadId}`);
      const forum = await call('GET', `/channels/${thread.parent_id}`);
      const tags = nextAppliedTags(thread.applied_tags, forum.available_tags, statusName);
      if (!tags) return { skipped: `forum has no "${statusName}" tag` };
      const patch = { applied_tags: tags };
      if (thread.thread_metadata && thread.thread_metadata.archived) patch.archived = false;
      await call('PATCH', `/channels/${threadId}`, patch);
      return { tags };
    },
  };
}
