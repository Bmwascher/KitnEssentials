// The Worker's scheduled jobs. Every few minutes `scan` puts one message with
// a "Send to GitHub" button into each new post in the configured forums. Once
// a day `daily` lists posts that have waited too long with no status, and
// warns the moderators if the scan has stopped running.
//
// State lives in the Workers KV namespace bound as STATE:
//   scan:since   epoch ms; posts made at or before it are never messaged
//   scan:last    epoch ms of the last scan that ran, whatever it found
//   scan:caught  epoch ms up to which archived posts are known to be handled
//   scan:through the newest post id at or before which every post is handled,
//                so a run reads KV only for posts after it
//   scan:error   the last scan's failure, cleared by a clean run
//   thread:<id>  {"greeting": message id, "skipped": reason, "issue": {"repo", "number"}}
import { parseForums, snowflakeMs, timedFetch, currentStatus } from './core.js';
import { discordClient } from './discord.js';

export const SEND_BUTTON = 'send';
// Workers' free plan allows 50 outgoing calls per run. Each greeting costs two
// (a look at the post's last messages, then the send); the rest of the budget
// reads the forums.
const MAX_GREET = 8;
const CALL_BUDGET = 45;
const MAX_KV_READS = 60;
const ARCHIVE_PAGES = 3;
const CALL_MS = 5000;
// Posts archive after an hour at the shortest; when the archived posts were
// last fully handled longer ago than this, they are read too.
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

// A Discord client that refuses calls past the run's budget.
function budgetClient(env, deps) {
  const timed = timedFetch(deps.fetch || fetch, CALL_MS);
  let left = CALL_BUDGET;
  const counted = (url, init) => {
    if (left <= 0) throw new Error('call budget for this run is spent');
    left--;
    return timed(url, init);
  };
  return discordClient(env.DISCORD_BOT_TOKEN, counted);
}

const refused = (err) => / -> (403|404) /.test(String(err && err.message));

// Posts in the configured forums: the guild's active posts, plus, when asked,
// each forum's posts archived at or after `archivedSince`, newest first, up to
// a few pages. `complete` is false when anything could not be read.
async function forumThreads(discord, guildId, forumIds, archivedSince, log) {
  const out = new Map();
  const failed = [];
  let complete = true;
  try {
    const active = await discord.call('GET', `/guilds/${guildId}/threads/active`);
    for (const t of active.threads || []) if (forumIds.includes(t.parent_id)) out.set(t.id, t);
  } catch (err) {
    log(`could not read the active posts: ${err.message}`);
    failed.push('active posts');
    complete = false;
  }
  if (archivedSince !== null) {
    for (const forumId of forumIds) {
      try {
        let before = '';
        for (let page = 0; ; page++) {
          if (page === ARCHIVE_PAGES) { complete = false; break; }
          const arch = await discord.call('GET', `/channels/${forumId}/threads/archived/public?limit=50${before}`);
          const threads = arch.threads || [];
          for (const t of threads) out.set(t.id, t);
          const oldest = threads.at(-1);
          const stamp = oldest && oldest.thread_metadata && oldest.thread_metadata.archive_timestamp;
          if (!arch.has_more || !stamp || Date.parse(stamp) < archivedSince) break;
          before = `&before=${encodeURIComponent(stamp)}`;
        }
      } catch (err) {
        log(`could not read forum ${forumId}: ${err.message}`);
        failed.push(`forum ${forumId}`);
        complete = false;
      }
    }
  }
  return { threads: [...out.values()], complete, failed };
}

// The bot's button already in the post's last messages, if any.
async function existingGreeting(discord, threadId) {
  const recent = await discord.call('GET', `/channels/${threadId}/messages?limit=20`);
  const mine = `${SEND_BUTTON}:${threadId}`;
  const hit = (recent || []).find((m) => (m.components || []).some((row) => (row.components || []).some((c) => c.custom_id === mine)));
  return hit ? hit.id : null;
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
    await kv.put('scan:caught', String(now));
    return { started: now };
  }
  const greeted = [];
  const errors = [];
  let left = 0;
  try {
    const caught = Number(await kv.get('scan:caught')) || since;
    const catchUp = now - caught > CATCH_UP_MS;
    const discord = budgetClient(env, deps);
    const found = await forumThreads(discord, env.GUILD_ID, forumIds, catchUp ? caught : null, log);
    errors.push(...found.failed);
    const through = BigInt((await kv.get('scan:through')) || 0);
    const fresh = found.threads
      .filter((t) => snowflakeMs(t.id) > since && BigInt(t.id) > through && !(t.thread_metadata && t.thread_metadata.locked))
      .sort((a, b) => (BigInt(a.id) < BigInt(b.id) ? -1 : 1));
    let reads = 0;
    let handled = through;
    let unbroken = true;
    for (const t of fresh) {
      if (greeted.length >= MAX_GREET || reads >= MAX_KV_READS) { left++; unbroken = false; continue; }
      reads++;
      let done = true;
      if (!(await threadRecord(kv, t.id))) {
        try {
          const had = await existingGreeting(discord, t.id);
          if (had) await saveThreadRecord(kv, t.id, { greeting: had });
          else {
            const m = await discord.call('POST', `/channels/${t.id}/messages`, greetingMessage(t.id));
            greeted.push(t.id);
            await saveThreadRecord(kv, t.id, { greeting: m.id });
          }
        } catch (err) {
          if (refused(err)) {
            log(`post ${t.id} skipped: ${err.message}`);
            await saveThreadRecord(kv, t.id, { skipped: err.message.slice(0, 200) });
          } else {
            log(`post ${t.id} left for the next run: ${err.message}`);
            errors.push(`post ${t.id}`);
            left++;
            done = false;
          }
        }
      }
      unbroken = unbroken && done;
      if (unbroken) handled = BigInt(t.id);
    }
    if (found.complete && handled > through) await kv.put('scan:through', handled.toString());
    if (catchUp && found.complete && !left) await kv.put('scan:caught', String(now));
    if (left) log(`scan: ${left} post(s) left for the next run`);
  } catch (err) {
    errors.push(err.message);
    throw err;
  } finally {
    await kv.put('scan:last', String(now));
    if (errors.length) await kv.put('scan:error', `${new Date(now).toISOString()}: could not read or message ${errors.slice(0, 5).join(', ')}`);
    else await kv.put('scan:error', '');
  }
  return { greeted, left };
}

// E4 and the scan alert, posted to MOD_CHANNEL_ID (logged when it is unset).
// The alert goes first, on its own, so a forum that cannot be read never
// holds it back.
export async function daily(env, deps = {}) {
  const log = deps.log || console.log;
  const now = (deps.now || Date.now)();
  const forumIds = Object.keys(parseForums(env));
  if (!forumIds.length || !env.GUILD_ID) {
    log('daily skipped: FORUMS and GUILD_ID must be set');
    return { skipped: true };
  }
  const staleMs = (Number(env.STALE_DAYS) || 3) * 24 * 60 * 60 * 1000;
  const discord = budgetClient(env, deps);
  const post = async (text) => {
    text = text.slice(0, 1900);
    if (!env.MOD_CHANNEL_ID) return log(text);
    try { await discord.send(env.MOD_CHANNEL_ID, text); } catch (err) { log(`could not post to the moderator channel: ${err.message}\n${text}`); }
  };

  const kv = env.STATE;
  let alerted = false;
  if (kv && Number(await kv.get('scan:since'))) {
    const last = Number(await kv.get('scan:last')) || 0;
    const error = await kv.get('scan:error');
    const alert = [];
    if (now - last > STALE_SCAN_MS) {
      alert.push(`The post scan has not run for ${Math.round((now - last) / 60000)} minutes: new posts are not getting their button. Check the Worker's cron trigger.`);
    }
    if (error) alert.push(`The post scan is running but hit a problem: ${error}. Check the bot's permissions in those channels.`);
    if (alert.length) { await post(alert.join('\n')); alerted = true; }
  }

  const lines = [];
  const tagsByForum = new Map();
  for (const id of forumIds) {
    try { tagsByForum.set(id, (await discord.getChannel(id)).available_tags || []); } catch (err) { log(`could not read forum ${id}: ${err.message}`); }
  }
  const found = await forumThreads(discord, env.GUILD_ID, forumIds, 0, log);
  const unread = [...new Set([...forumIds.filter((id) => !tagsByForum.has(id)).map((id) => `forum ${id}`), ...found.failed])];
  const waiting = found.threads.filter((t) => {
    if (now - snowflakeMs(t.id) < staleMs) return false;
    if (t.thread_metadata && t.thread_metadata.locked) return false;
    if (!tagsByForum.has(t.parent_id)) return false;
    const tags = tagsByForum.get(t.parent_id);
    if (currentStatus(t.applied_tags, tags)) return false;
    const answered = tags.find((x) => x.name.toLowerCase() === ANSWERED);
    return !(answered && (t.applied_tags || []).includes(answered.id));
  });
  if (waiting.length) {
    lines.push(`${waiting.length} post(s) older than ${Math.round(staleMs / 86400000)} days with no status or "Answered" tag:`);
    for (const t of waiting.slice(0, 20)) lines.push(`- ${t.name || t.id}: https://discord.com/channels/${env.GUILD_ID}/${t.id}`);
    if (waiting.length > 20) lines.push(`- and ${waiting.length - 20} more`);
  }
  if (unread.length) lines.push(`Could not read ${unread.join(', ')}, so this list may be short. Check the bot's access there.`);
  else if (!found.complete) lines.push('Only the most recently archived posts were checked; older ones may also be waiting.');

  if (lines.length) await post(lines.join('\n'));
  return { waiting: waiting.length, alerted, unread, posted: !!env.MOD_CHANNEL_ID && (alerted || lines.length > 0) };
}

// Which job a cron expression runs (wrangler.toml [triggers]).
export const CRONS = { scan: '*/5 * * * *', daily: '0 15 * * *' };
