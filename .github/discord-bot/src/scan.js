// The Worker's scheduled jobs. Every few minutes `scan` puts one message with
// a "Send to GitHub" button into each new post in the configured forums. Once
// a day `daily` lists posts that have waited too long with no status, and
// warns the moderators if the scan has stopped running.
//
// State lives in the Workers KV namespace bound as STATE:
//   scan:since   epoch ms; posts made before it are never messaged
//   scan:last    epoch ms of the last scan that finished
//   thread:<id>  {"greeting": message id, "issue": {"repo", "number"}}
import { parseForums, snowflakeMs, timedFetch, currentStatus } from './core.js';
import { discordClient } from './discord.js';

export const SEND_BUTTON = 'send';
// Workers' free plan allows 50 outgoing calls per run: greet a few posts per
// run and leave the rest for the next.
const MAX_GREET = 8;
const CALL_MS = 5000;
// Threads archive after an hour at the shortest; a gap longer than this also
// reads each forum's recently archived posts so none is missed.
const CATCH_UP_MS = 50 * 60 * 1000;
const STALE_SCAN_MS = 60 * 60 * 1000;
const ANSWERED = 'answered';

export const GREETING = 'Thanks for posting! A moderator will look at this soon. Moderators: the button below sends this post to GitHub.';

export function greetingMessage(threadId) {
  return {
    content: GREETING,
    allowed_mentions: { parse: [] },
    components: [{ type: 1, components: [{ type: 2, style: 1, label: 'Send to GitHub', custom_id: `${SEND_BUTTON}:${threadId}` }] }],
  };
}

const readJson = async (kv, key) => {
  const raw = await kv.get(key);
  if (!raw) return null;
  try { return JSON.parse(raw); } catch { return null; }
};

export async function threadRecord(kv, threadId) {
  return kv ? readJson(kv, `thread:${threadId}`) : null;
}

export async function saveThreadRecord(kv, threadId, patch) {
  if (!kv) return;
  const rec = (await threadRecord(kv, threadId)) || {};
  await kv.put(`thread:${threadId}`, JSON.stringify({ ...rec, ...patch }));
}

// Posts in the configured forums: the guild's active threads, plus each
// forum's recently archived ones when asked.
async function forumThreads(discord, guildId, forumIds, withArchived) {
  const out = new Map();
  const active = await discord.call('GET', `/guilds/${guildId}/threads/active`);
  for (const t of active.threads || []) if (forumIds.includes(t.parent_id)) out.set(t.id, t);
  if (withArchived) {
    for (const forumId of forumIds) {
      const arch = await discord.call('GET', `/channels/${forumId}/threads/archived/public?limit=50`);
      for (const t of arch.threads || []) out.set(t.id, t);
    }
  }
  return [...out.values()];
}

// Fails closed: with no forums, no guild or no KV it does nothing at all.
export async function scan(env, deps = {}) {
  const log = deps.log || console.log;
  const now = (deps.now || Date.now)();
  const forumIds = Object.keys(parseForums(env));
  const kv = env.STATE;
  if (!forumIds.length || !env.GUILD_ID || !kv) {
    log('scan skipped: FORUMS, GUILD_ID and the STATE namespace must all be set');
    return { skipped: true };
  }
  const since = Number(await kv.get('scan:since'));
  if (!since) {
    // First run: start from now, so posts made before the bot never get a message.
    await kv.put('scan:since', String(now));
    await kv.put('scan:last', String(now));
    return { started: now };
  }
  const last = Number(await kv.get('scan:last')) || 0;
  const discord = discordClient(env.DISCORD_BOT_TOKEN, timedFetch(deps.fetch || fetch, CALL_MS));
  const threads = await forumThreads(discord, env.GUILD_ID, forumIds, now - last > CATCH_UP_MS);
  const fresh = threads.filter((t) => snowflakeMs(t.id) >= since).sort((a, b) => (BigInt(a.id) < BigInt(b.id) ? -1 : 1));
  const greeted = [];
  let left = 0;
  for (const t of fresh) {
    if (await threadRecord(kv, t.id)) continue;
    if (greeted.length >= MAX_GREET) { left++; continue; }
    const m = await discord.call('POST', `/channels/${t.id}/messages`, greetingMessage(t.id));
    await saveThreadRecord(kv, t.id, { greeting: m.id });
    greeted.push(t.id);
  }
  await kv.put('scan:last', String(now));
  if (left) log(`scan: ${left} post(s) left for the next run`);
  return { greeted, left };
}

// E4 and the scan alert, posted to MOD_CHANNEL_ID (logged when it is unset).
export async function daily(env, deps = {}) {
  const log = deps.log || console.log;
  const now = (deps.now || Date.now)();
  const forumIds = Object.keys(parseForums(env));
  if (!forumIds.length || !env.GUILD_ID) {
    log('daily skipped: FORUMS and GUILD_ID must be set');
    return { skipped: true };
  }
  const staleMs = (Number(env.STALE_DAYS) || 3) * 24 * 60 * 60 * 1000;
  const discord = discordClient(env.DISCORD_BOT_TOKEN, timedFetch(deps.fetch || fetch, CALL_MS));
  const lines = [];

  const kv = env.STATE;
  if (kv && Number(await kv.get('scan:since'))) {
    const last = Number(await kv.get('scan:last')) || 0;
    if (now - last > STALE_SCAN_MS) {
      lines.push(`The post scan has not run for ${Math.round((now - last) / 60000)} minutes: new posts are not getting their button. Check the Worker's cron trigger.`);
    }
  }

  const tagsByForum = new Map();
  for (const id of forumIds) tagsByForum.set(id, (await discord.getChannel(id)).available_tags || []);
  const waiting = (await forumThreads(discord, env.GUILD_ID, forumIds, true)).filter((t) => {
    if (now - snowflakeMs(t.id) < staleMs) return false;
    if (t.thread_metadata && t.thread_metadata.locked) return false;
    const tags = tagsByForum.get(t.parent_id) || [];
    if (currentStatus(t.applied_tags, tags)) return false;
    const answered = tags.find((x) => x.name.toLowerCase() === ANSWERED);
    return !(answered && (t.applied_tags || []).includes(answered.id));
  });
  if (waiting.length) {
    lines.push(`${waiting.length} post(s) older than ${Math.round(staleMs / 86400000)} days with no status or "Answered" tag:`);
    for (const t of waiting.slice(0, 20)) lines.push(`- ${t.name || t.id}: https://discord.com/channels/${env.GUILD_ID}/${t.id}`);
    if (waiting.length > 20) lines.push(`- and ${waiting.length - 20} more`);
  }

  if (!lines.length) return { waiting: 0 };
  const text = lines.join('\n').slice(0, 1900);
  if (env.MOD_CHANNEL_ID) await discord.send(env.MOD_CHANNEL_ID, text);
  else log(text);
  return { waiting: waiting.length, posted: !!env.MOD_CHANNEL_ID };
}

// Which job a cron expression runs (wrangler.toml [triggers]).
export const CRONS = { scan: '*/5 * * * *', daily: '0 15 * * *' };
