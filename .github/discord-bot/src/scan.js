// The Worker's scheduled jobs. Every minute `scan` puts one message with
// a "Send to GitHub" button into each new, open post in the configured forums.
// A post that was closed or archived before a scan saw it gets none; the
// right-click command still works there. Once
// a day `daily` lists posts that have waited too long with no status, and
// warns the moderators if the scan has stopped running or keeps failing.
//
// State lives in the Workers KV namespace bound as STATE. KV's free plan
// allows 1,000 writes a day, so a scan writes its own state only when it
// changed, or HEARTBEAT_MS after the last write, which tells the daily check
// the scan is still running:
//   scan:since   epoch ms; posts made at or before it are never messaged
//   scan:state   {"last": epoch ms of the last state write,
//                 "through": {forum: the newest post id at or before which every
//                             post there is handled, so a run reads KV only after it},
//                 "error": {"at": epoch ms, "text": the last failure}}
//   thread:<id>  {"greeting": message id, "skipped": reason, "tries": failed sends,
//                 "issue": {"repo", "number"}}
import { parseForums, snowflakeMs, timedFetch, currentStatus, SEND_BUTTON } from './core.js';
import { discordClient } from './discord.js';

export { SEND_BUTTON };
// Workers' free plan allows 50 outgoing calls per run. Each greeting costs two
// (a look at the post's last messages, then the send) and has its own share,
// so reading the forums can never use up what the greetings need.
const MAX_GREET = 8;
const READ_BUDGET = 28;
const GREET_BUDGET = 2 * MAX_GREET;
const POST_BUDGET = 4;
const MAX_KV_READS = 60;
// A post that fails this many runs in a row (not a refusal) is given up on:
// about 30 minutes of errors at one scan a minute. Each failed try is one KV
// write, so the cost stays small.
const MAX_TRIES = 30;
const CALL_MS = 5000;
const STALE_SCAN_MS = 60 * 60 * 1000;
const HEARTBEAT_MS = 15 * 60 * 1000;
const ERROR_SHOWN_MS = 24 * 60 * 60 * 1000;
const DAILY_ARCHIVED_MS = 30 * 24 * 60 * 60 * 1000;
const DAILY_ARCHIVE_PAGES = 6;
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

// A record that only counts failed tries is not finished.
const finished = (rec) => !!rec && Object.keys(rec).some((k) => k !== 'tries');

// A Discord client that refuses calls past its share of the run's budget.
class BudgetSpent extends Error {}
function budgetClient(env, deps, budget) {
  const timed = timedFetch(deps.fetch || fetch, CALL_MS);
  let left = budget;
  const counted = (url, init) => {
    if (left <= 0) throw new BudgetSpent('call budget for this run is spent');
    left--;
    return timed(url, init);
  };
  return discordClient(env.DISCORD_BOT_TOKEN, counted);
}

const refused = (err) => / -> (403|404) /.test(String(err && err.message));

// One forum's archived posts, newest first, back to those archived at `since`
// (epoch ms), up to a few pages. `cut` is the archive time it stopped at when
// the page limit came first.
async function archivedPosts(discord, forumId, since, pages) {
  const out = [];
  let before = '';
  for (let page = 0; page < pages; page++) {
    const arch = await discord.call('GET', `/channels/${forumId}/threads/archived/public?limit=50${before}`);
    const threads = arch.threads || [];
    out.push(...threads);
    const oldest = threads.at(-1);
    const stamp = oldest && oldest.thread_metadata && oldest.thread_metadata.archive_timestamp;
    if (!arch.has_more || !stamp || Date.parse(stamp) < since) return { threads: out, cut: null };
    before = `&before=${encodeURIComponent(stamp)}`;
  }
  return { threads: out, cut: out.at(-1).thread_metadata.archive_timestamp };
}

// The bot's button already in the post's last messages, if any.
async function existingGreeting(discord, threadId) {
  const recent = await discord.call('GET', `/channels/${threadId}/messages?limit=100`);
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
  const state = (await readJson(kv, 'scan:state')) || {};
  const through = { ...state.through };
  if (!since) {
    // First run: start from now, so posts made before the bot never get a message.
    await kv.put('scan:since', String(now));
    await kv.put('scan:state', JSON.stringify({ last: now }));
    return { started: now };
  }
  const greeted = [];
  const errors = [];
  let left = 0;
  try {
    const discord = budgetClient(env, deps, READ_BUDGET);
    const greeter = budgetClient(env, deps, GREET_BUDGET);
    let active;
    try {
      active = (await discord.call('GET', `/guilds/${env.GUILD_ID}/threads/active`)).threads || [];
    } catch (err) {
      errors.push('the active posts');
      throw err;
    }
    const mark = (f) => BigInt(through[f] || 0);
    const fresh = active
      .filter((t) => forumIds.includes(t.parent_id))
      .filter((t) => snowflakeMs(t.id) > since && BigInt(t.id) > mark(t.parent_id))
      .filter((t) => !(t.thread_metadata && (t.thread_metadata.locked || t.thread_metadata.archived)))
      .sort((a, b) => (BigInt(a.id) < BigInt(b.id) ? -1 : 1));
    const unbroken = new Set(forumIds);
    let reads = 0;
    let tried = 0;
    for (const t of fresh) {
      const f = t.parent_id;
      if (tried >= MAX_GREET || reads >= MAX_KV_READS) { left++; unbroken.delete(f); continue; }
      reads++;
      const rec = await threadRecord(kv, t.id);
      let done = finished(rec);
      if (!done) {
        tried++;
        try {
          const had = await existingGreeting(greeter, t.id);
          if (had) await saveThreadRecord(kv, t.id, { greeting: had });
          else {
            const m = await greeter.call('POST', `/channels/${t.id}/messages`, greetingMessage(t.id));
            greeted.push(t.id);
            await saveThreadRecord(kv, t.id, { greeting: m.id });
          }
          done = true;
        } catch (err) {
          const tries = ((rec && rec.tries) || 0) + 1;
          if (refused(err) || tries >= MAX_TRIES) {
            log(`post ${t.id} skipped: ${err.message}`);
            await saveThreadRecord(kv, t.id, { skipped: err.message.slice(0, 200) });
            if (!refused(err)) errors.push(`post ${t.id} (gave up after ${tries} tries)`);
            done = true;
          } else {
            log(`post ${t.id} left for the next run: ${err.message}`);
            await saveThreadRecord(kv, t.id, { tries });
            errors.push(`post ${t.id}`);
            left++;
          }
        }
      }
      if (!done) unbroken.delete(f);
      if (unbroken.has(f)) through[f] = t.id;
    }
    if (left) log(`scan: ${left} post(s) left for the next run`);
  } catch (err) {
    if (!errors.length) errors.push(err.message);
    throw err;
  } finally {
    const next = { last: now, through, error: state.error };
    if (errors.length) next.error = { at: now, text: `could not read or message ${errors.slice(0, 5).join(', ')}` };
    const changed = JSON.stringify(through) !== JSON.stringify(state.through || {})
      || (next.error && next.error.text) !== (state.error && state.error.text)
      || now - (Number(state.last) || 0) >= HEARTBEAT_MS;
    if (changed) await kv.put('scan:state', JSON.stringify(next));
  }
  return { greeted, left };
}

// E4 and the scan alert, posted to MOD_CHANNEL_ID (logged when it is unset).
// The alert goes first, on its own, so a forum that cannot be read never
// holds it back. The daily check writes no state.
export async function daily(env, deps = {}) {
  const log = deps.log || console.log;
  const now = (deps.now || Date.now)();
  const forumIds = Object.keys(parseForums(env));
  if (!forumIds.length || !env.GUILD_ID) {
    log('daily skipped: FORUMS and GUILD_ID must be set');
    return { skipped: true };
  }
  const staleMs = (Number(env.STALE_DAYS) || 3) * 24 * 60 * 60 * 1000;
  const discord = budgetClient(env, deps, READ_BUDGET + GREET_BUDGET);
  const poster = budgetClient(env, deps, POST_BUDGET);
  let posted = false;
  const post = async (text) => {
    text = text.slice(0, 1900);
    if (!env.MOD_CHANNEL_ID) return log(text);
    try {
      await poster.send(env.MOD_CHANNEL_ID, text);
      posted = true;
    } catch (err) {
      log(`could not post to the moderator channel: ${err.message}\n${text}`);
    }
  };

  const kv = env.STATE;
  let alerted = false;
  if (kv && Number(await kv.get('scan:since'))) {
    const state = (await readJson(kv, 'scan:state')) || {};
    const last = Number(state.last) || 0;
    const alert = [];
    // An idle scan writes its state only every HEARTBEAT_MS, so the last run
    // may be up to that much newer than the saved time.
    if (now - last > STALE_SCAN_MS + HEARTBEAT_MS) {
      alert.push(`The post scan has not run for at least ${Math.round((now - last - HEARTBEAT_MS) / 60000)} minutes: new posts are not getting their button. Check the Worker's cron trigger.`);
    }
    if (state.error && now - state.error.at < ERROR_SHOWN_MS) {
      alert.push(`The post scan hit a problem at ${new Date(state.error.at).toISOString()}: ${state.error.text}. Check the bot's permissions in those channels.`);
    }
    if (alert.length) { await post(alert.join('\n')); alerted = true; }
  }

  const tagsByForum = new Map();
  for (const id of forumIds) {
    try { tagsByForum.set(id, (await discord.getChannel(id)).available_tags || []); } catch (err) { log(`could not read forum ${id}: ${err.message}`); }
  }
  const unread = forumIds.filter((id) => !tagsByForum.has(id)).map((id) => `forum ${id}`);
  const threads = new Map();
  try {
    const active = await discord.call('GET', `/guilds/${env.GUILD_ID}/threads/active`);
    for (const t of active.threads || []) threads.set(t.id, t);
  } catch (err) {
    log(`could not read the active posts: ${err.message}`);
    unread.push('the active posts');
  }
  let cut = false;
  for (const id of tagsByForum.keys()) {
    try {
      const arch = await archivedPosts(discord, id, now - DAILY_ARCHIVED_MS, DAILY_ARCHIVE_PAGES);
      for (const t of arch.threads) threads.set(t.id, t);
      cut = cut || !!arch.cut;
    } catch (err) {
      log(`could not read forum ${id}: ${err.message}`);
      unread.push(`forum ${id}`);
    }
  }
  const waiting = [...threads.values()].filter((t) => {
    if (!tagsByForum.has(t.parent_id)) return false;
    if (now - snowflakeMs(t.id) < staleMs) return false;
    if (t.thread_metadata && t.thread_metadata.locked) return false;
    const tags = tagsByForum.get(t.parent_id);
    if (currentStatus(t.applied_tags, tags)) return false;
    const answered = tags.find((x) => x.name.toLowerCase() === ANSWERED);
    return !(answered && (t.applied_tags || []).includes(answered.id));
  });
  // The warnings go first, so the length limit can only cut the list. An
  // incomplete search cannot say nothing is waiting, so they go out even with
  // an empty list.
  const lines = [];
  if (unread.length) lines.push(`Could not read ${[...new Set(unread)].join(', ')}, so this list may be short. Check the bot's access there.`);
  if (cut) lines.push(`Only the most recently archived posts were checked (${DAILY_ARCHIVE_PAGES * 50} per forum, from the last ${DAILY_ARCHIVED_MS / 86400000} days); older ones may also be waiting.`);
  if (waiting.length) {
    lines.push(`${waiting.length} post(s) older than ${Math.round(staleMs / 86400000)} days with no status or "Answered" tag (archived posts from the last ${DAILY_ARCHIVED_MS / 86400000} days):`);
    for (const t of waiting.slice(0, 20)) lines.push(`- ${t.name || t.id}: https://discord.com/channels/${env.GUILD_ID}/${t.id}`);
    if (waiting.length > 20) lines.push(`- and ${waiting.length - 20} more`);
  }

  if (lines.length) await post(lines.join('\n'));
  return { waiting: waiting.length, alerted, unread, posted };
}

// Which job a cron expression runs (wrangler.toml [triggers]).
export const CRONS = { scan: '* * * * *', daily: '0 15 * * *' };
