// The Worker's scheduled jobs. Every minute `scan` greets each new, open post
// in the configured forums (no button) and, when QUEUE_CHANNEL_ID is set,
// posts a card for it with a "Send to GitHub" button in that staff channel,
// in the same pass. A post filed before a scan reached it gets neither, and
// so does one closed or archived first; the right-click command still works
// there. Once a day `daily` lists posts that have waited too long with no
// status, and warns the moderators if the scan has stopped running or keeps
// failing.
//
// State lives in the Workers KV namespace bound as STATE. KV's free plan
// allows 1,000 writes a day, so a scan writes its own state only when it
// changed, or HEARTBEAT_MS after the last write, which tells the daily check
// the scan is still running:
//   scan:since   epoch ms; posts made at or before it are never messaged
//   scan:state   {"last": epoch ms of the last state write,
//                 "through": {forum: the newest post id at or before which every
//                             post there is handled, so a run reads KV only after it},
//                 "greeted": {forum: the same, for the greeting alone: posts past
//                             it are new, and go before any card retry},
//                 "error": {"at": epoch ms, "text": the last failure},
//                 "gaveUp": [{"at", "post", "what": "greeting" or "queue card"}],
//                             each kept a day for the daily alert}
//   thread:<id>  the scan's record of a post: {"greeting": message id,
//                 "buttonless": true for the greeting without a button,
//                 "card": queue card id, "cardSkipped": why no card goes out,
//                 "skipped": why no greeting goes out, "tracked": the bot's
//                 "now tracked" reply found in the post, "tries": failed
//                 passes, the greeting's and the card's together}; one from
//                 before the filing record may hold "issue"
//   issue:<id>   the Worker's record once the post is filed: {"repo",
//                 "number", "key", "by"}
// Each key has one writer: the scan writes thread:, the Worker issue:.
import { parseForums, snowflakeMs, timedFetch, currentStatus, SEND_BUTTON, queueCard, personName, MESSAGES } from './core.js';
import { discordClient } from './discord.js';

export { SEND_BUTTON };
// Workers' free plan allows 50 outgoing calls per run. A greeting costs two
// (a look at the post's last messages, then the send) and a queue card three
// (the post as it is now, its first message, then the card). Greetings,
// cards and the scan's own reads (the active posts, the bot's id, the queue
// channel) each have their own client, so cards can never use up what the
// greetings need. The daily check's forum reads keep their own share.
const MAX_GREET = 8;
const MAX_CARDS = 8;
const READ_BUDGET = 3;
const GREET_BUDGET = 2 * MAX_GREET;
const CARD_BUDGET = 3 * MAX_CARDS;
const FORUM_BUDGET = 44;
const POST_BUDGET = 4;
const MAX_KV_READS = 60;
// A post whose pass fails this many runs in a row (not a refusal) is given
// up on: about 30 minutes of errors at one scan a minute. Its greeting and
// its card share the count; once the greeting is out, giving up skips only
// the card. A post that waits for a share of this run's calls spends no try.
// Each failed try is one KV write, so the cost stays small.
const MAX_TRIES = 30;
// KV takes one write a second to a key, so a second write to a post's
// record in one pass waits this long after the first.
const KV_GAP_MS = 1100;
const CALL_MS = 5000;
const STALE_SCAN_MS = 60 * 60 * 1000;
const HEARTBEAT_MS = 15 * 60 * 1000;
const ERROR_SHOWN_MS = 24 * 60 * 60 * 1000;
const DAILY_ARCHIVED_MS = 30 * 24 * 60 * 60 * 1000;
const DAILY_ARCHIVE_PAGES = 6;
const ANSWERED = 'answered';

export const GREETING = "Thanks for posting! A moderator will take a look soon, and we'll post updates here.";

export function greetingMessage() {
  return { content: GREETING, allowed_mentions: { parse: [] } };
}

const readJson = async (kv, key) => {
  const raw = await kv.get(key);
  if (!raw) return null;
  try { return JSON.parse(raw); } catch { return null; }
};

// A record as stored, or null when there is none. A value that is empty or
// not JSON throws with `damaged` set to its key, and a failed read throws as
// it is: neither is "no record".
export async function readStrict(kv, key) {
  if (!kv) return null;
  const raw = await kv.get(key);
  if (raw === null || raw === undefined) return null;
  try {
    return JSON.parse(raw);
  } catch {
    throw Object.assign(new Error(`the KV value at ${key} is damaged (empty or not JSON)`), { damaged: key });
  }
}

export async function saveIssueRecord(kv, threadId, rec) {
  if (kv) await kv.put(`issue:${threadId}`, JSON.stringify(rec));
}

// A post's work is done once it was skipped or filed (its receipt found
// counts), or its greeting is out and its card is settled: posted, skipped,
// or no queue channel set. The same rule keeps the forum's progress mark
// behind a post with work left.
const finished = (rec, queue) => !!rec && (!!rec.skipped || !!rec.issue || !!rec.tracked
  || (!!rec.greeting && (!queue || !!rec.card || !!rec.cardSkipped)));

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

const buttons = (m) => (m.components || []).flatMap((row) => row.components || []);
// An old button greeting, or a queue card, holding the post's send button.
export const hasButton = (m, postId) => buttons(m).some((c) => c.custom_id === `${SEND_BUTTON}:${postId}`);
// The bot's own queue card for the post: its send button, or its Open post
// link to exactly this post. Another app's message never counts.
const isCardFor = (m, postId, me, guildId) => !!m.author && m.author.id === me
  && (hasButton(m, postId) || buttons(m).some((c) => c.url === `https://discord.com/channels/${guildId}/${postId}`));

// How the Worker's "now tracked" reply starts.
const TRACKED_START = MESSAGES.tracked('\u0000', 0).split('\u0000')[0];

// The bot's own messages among the post's last 100: its greeting (the
// buttonless one, or an old one still showing its button), and its "now
// tracked" reply, which means the post was filed even when its filing record
// is missing or not yet visible here.
async function lookIn(discord, threadId, myId) {
  const recent = (await discord.call('GET', `/channels/${threadId}/messages?limit=100`)) || [];
  const me = recent.length ? await myId() : null;
  const mine = recent.filter((m) => !!m.author && m.author.id === me);
  const receipt = mine.find((m) => String(m.content || '').startsWith(TRACKED_START));
  return {
    receipt: receipt ? receipt.id : null,
    greeting: mine.find((m) => hasButton(m, threadId) || m.content === GREETING) || null,
  };
}

// Fails closed: with no forums, no guild or no KV it does nothing at all.
export async function scan(env, deps = {}) {
  const log = deps.log || console.log;
  const now = (deps.now || Date.now)();
  const forums = parseForums(env);
  const forumIds = Object.keys(forums);
  const kv = env.STATE;
  if (!forumIds.length || !env.GUILD_ID || !kv) {
    log('scan skipped: FORUMS, GUILD_ID and the STATE namespace must all be set');
    return { skipped: true };
  }
  const since = Number(await kv.get('scan:since'));
  const state = (await readJson(kv, 'scan:state')) || {};
  const through = { ...state.through };
  const greetedTo = { ...through, ...state.greeted };
  if (!since) {
    // First run: start from now, so posts made before the bot never get a message.
    await kv.put('scan:since', String(now));
    await kv.put('scan:state', JSON.stringify({ last: now }));
    return { started: now };
  }
  const greeted = [];
  const errors = [];
  const gaveUpNow = [];
  let left = 0;
  try {
    const discord = budgetClient(env, deps, READ_BUDGET);
    const greeter = budgetClient(env, deps, GREET_BUDGET);
    const carder = budgetClient(env, deps, CARD_BUDGET);
    const queue = env.QUEUE_CHANNEL_ID || '';
    const clock = deps.clock || Date.now;
    const sleep = deps.sleep || ((ms) => new Promise((done) => setTimeout(done, ms)));
    let me = null;
    const myId = () => (me = me || discord.me().then((u) => u.id));
    // The queue channel's last 100 messages, read once a run and only when a
    // card is due, to find a card whose id was never saved.
    let queued = null;
    // A failure at the queue channel itself is marked, so a refusal there (a
    // channel the bot was never let into) is reported, not just skipped.
    const atQueue = (p) => p.catch((err) => { throw Object.assign(err, { queue: true }); });
    const queueRead = () => (queued = queued || atQueue(discord.call('GET', `/channels/${queue}/messages?limit=100`)).then((m) => m || []));
    // The post's queue card: the bot's own card already there, else a new
    // one, for a post still open now. The active list was read at the start
    // of the run, so the post is read again: one deleted since (a 404, a
    // refusal), archived, locked or moved out of the configured forums gets
    // no card. A post whose first message is gone gets a card with no send
    // button, since the form files that message.
    const cardFor = async (t) => {
      const msgs = await queueRead();
      const mine = msgs.length ? await myId() : null;
      const had = msgs.find((m) => isCardFor(m, t.id, mine, env.GUILD_ID));
      if (had) return { card: had.id };
      const now = await carder.getChannel(t.id);
      const meta = now.thread_metadata || {};
      if (meta.archived || meta.locked) return { cardSkipped: `the post was ${meta.archived ? 'archived' : 'locked'} before its card went out` };
      if (!forums[now.parent_id]) return { cardSkipped: 'the post is no longer in a configured forum' };
      let starter = null;
      try {
        starter = await carder.getMessage(t.id, t.id);
      } catch (err) {
        if (!/ -> 404 /.test(err.message)) throw err;
      }
      const author = starter && starter.author;
      const info = forums[now.parent_id] || {};
      return { card: (await atQueue(carder.call('POST', `/channels/${queue}/messages`, queueCard({
        guildId: env.GUILD_ID, forumId: now.parent_id, postId: t.id, postName: now.name || t.name,
        author: author ? { name: personName(author), username: author.username } : null, client: info.client, type: info.type,
        starterGone: !starter,
      })))).id };
    };
    let active;
    try {
      active = (await discord.call('GET', `/guilds/${env.GUILD_ID}/threads/active`)).threads || [];
    } catch (err) {
      errors.push('the active posts');
      throw err;
    }
    const mark = (m, f) => BigInt(m[f] || 0);
    const fresh = active
      .filter((t) => forumIds.includes(t.parent_id))
      .filter((t) => snowflakeMs(t.id) > since && BigInt(t.id) > mark(through, t.parent_id))
      .filter((t) => !(t.thread_metadata && (t.thread_metadata.locked || t.thread_metadata.archived)))
      .sort((a, b) => (BigInt(a.id) < BigInt(b.id) ? -1 : 1));
    // Posts past the greeting mark are new. They go first, so their reads
    // and greetings never wait behind an older post's card retry.
    const isNew = new Set(fresh.filter((t) => BigInt(t.id) > mark(greetedTo, t.parent_id)).map((t) => t.id));
    let reads = 0;
    const read = async (key, strict = false) => {
      if (reads >= MAX_KV_READS) throw new BudgetSpent('KV reads for this run are spent');
      reads++;
      return strict ? readStrict(kv, key) : readJson(kv, key);
    };
    let tried = 0;
    let carded = 0;
    const wroteAt = new Map();
    const putRecord = async (id, rec) => {
      const wait = (wroteAt.has(id) ? wroteAt.get(id) + KV_GAP_MS : 0) - clock();
      if (wait > 0) await sleep(wait);
      try {
        await kv.put(`thread:${id}`, JSON.stringify(rec));
      } finally {
        wroteAt.set(id, clock());
      }
    };
    // One post's pass: its greeting, then its card. It never throws, so one
    // post's failure stays with it. `greeted`: the greeting is settled;
    // `finished`: nothing is left to do.
    const visit = async (t) => {
      let rec = null;
      try {
        rec = (await read(`thread:${t.id}`)) || {};
        if (finished(rec, queue)) return { greeted: true, finished: true };
        // A post filed before this pass (by right-click, or from its card
        // after the greeting) gets no greeting and no card.
        if (await read(`issue:${t.id}`, true)) return { greeted: true, finished: true };
        if (!rec.greeting) {
          // The greeting share counts only posts that try a greeting.
          if (tried >= MAX_GREET) { left++; return { greeted: false, finished: false }; }
          tried++;
          const seen = await lookIn(greeter, t.id, myId);
          if (seen.receipt) {
            // Filed and told, though its filing record is missing or not yet
            // visible here: no greeting after the receipt, and no card.
            rec = { ...rec, tracked: seen.receipt };
            await putRecord(t.id, rec);
            return { greeted: true, finished: true };
          }
          let id = seen.greeting && seen.greeting.id;
          if (!id) {
            id = (await greeter.call('POST', `/channels/${t.id}/messages`, greetingMessage())).id;
            greeted.push(t.id);
          }
          // Saved on its own, before the card: a later pass that reads it
          // never looks for or sends the greeting again.
          rec = { ...rec, greeting: id, ...(seen.greeting && hasButton(seen.greeting, t.id) ? {} : { buttonless: true }) };
          await putRecord(t.id, rec);
        }
        if (finished(rec, queue)) return { greeted: true, finished: true };
        if (carded >= MAX_CARDS) { left++; return { greeted: true, finished: false }; }
        carded++;
        rec = { ...rec, ...(await cardFor(t)) };
        await putRecord(t.id, rec);
        return { greeted: true, finished: true };
      } catch (err) {
        const greetedNow = !!(rec && rec.greeting);
        // Out of this run's calls or reads, or the record itself unread: the
        // post waits, spends no try, and nothing overwrites its record.
        if (err instanceof BudgetSpent || !rec) {
          if (!rec && !(err instanceof BudgetSpent)) {
            log(`post ${t.id} left for the next run: its record could not be read: ${err.message}`);
            errors.push(`the record of post ${t.id}`);
          }
          left++;
          return { greeted: greetedNow, finished: false };
        }
        // One count for the post's pass, greeting and card together. Once
        // the greeting is out, giving up skips only the card.
        const what = greetedNow ? `queue card for post ${t.id}` : `post ${t.id}`;
        const tries = (rec.tries || 0) + 1;
        const giveUp = refused(err) || tries >= MAX_TRIES;
        log(`${what} ${giveUp ? 'skipped' : 'left for the next run'}: ${err.message}`);
        if (!giveUp) {
          errors.push(what);
          left++;
        } else if (!refused(err) || err.queue) {
          // A refusal by the post itself (deleted, closed to the bot) is that
          // post's own end, as before; one by the queue channel is a setup
          // problem every later post shares, so it is named too.
          errors.push(`${what} (${refused(err) ? 'the queue channel refused the bot' : `gave up after ${tries} tries`})`);
          gaveUpNow.push({ post: t.id, what: greetedNow ? 'queue card' : 'greeting' });
        }
        try {
          await putRecord(t.id, giveUp ? { ...rec, [greetedNow ? 'cardSkipped' : 'skipped']: err.message.slice(0, 200) } : { ...rec, tries });
        } catch (e) {
          log(`${what}: its record was not saved: ${e.message}`);
          errors.push(`the record of ${what}`);
          return { greeted: greetedNow, finished: false };
        }
        return { greeted: giveUp || greetedNow, finished: giveUp };
      }
    };
    const outcome = new Map();
    for (const t of [...fresh.filter((x) => isNew.has(x.id)), ...fresh.filter((x) => !isNew.has(x.id))]) {
      if (reads >= MAX_KV_READS) { left++; continue; }
      outcome.set(t.id, await visit(t));
    }
    // Each mark moves past a forum's posts, oldest first, up to the first
    // with work left: `through` past posts with nothing left to do,
    // `greetedTo` past new posts whose greeting is settled.
    for (const f of forumIds) {
      for (const t of fresh.filter((x) => x.parent_id === f)) {
        const o = outcome.get(t.id);
        if (!o || !o.finished) break;
        through[f] = t.id;
      }
      for (const t of fresh.filter((x) => x.parent_id === f && isNew.has(x.id))) {
        const o = outcome.get(t.id);
        if (!o || !o.greeted) break;
        greetedTo[f] = t.id;
      }
    }
    if (left) log(`scan: ${left} post(s) left for the next run`);
  } catch (err) {
    if (!errors.length) errors.push(err.message);
    throw err;
  } finally {
    const next = { last: now, through, greeted: greetedTo, error: state.error };
    if (errors.length) next.error = { at: now, text: `could not read or message ${errors.slice(0, 5).join(', ')}` };
    // Every post given up on stays named for a day, whatever errors follow,
    // so the daily alert lists each one.
    const gaveUp = [...(state.gaveUp || []).filter((g) => now - g.at < ERROR_SHOWN_MS), ...gaveUpNow.map((g) => ({ at: now, ...g }))];
    if (gaveUp.length) next.gaveUp = gaveUp;
    const changed = JSON.stringify(through) !== JSON.stringify(state.through || {})
      || JSON.stringify(greetedTo) !== JSON.stringify({ ...state.through, ...state.greeted })
      || JSON.stringify(gaveUp) !== JSON.stringify(state.gaveUp || [])
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
  const discord = budgetClient(env, deps, FORUM_BUDGET);
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
  // Lines in as few messages as fit, each under 1,900 characters and cut
  // only between lines. Past the run's posting share, the rest goes to the log.
  const postLines = async (lines) => {
    let msg = '';
    for (const line of lines) {
      if (msg && msg.length + 1 + line.length > 1900) { await post(msg); msg = ''; }
      msg = msg ? `${msg}\n${line}` : line;
    }
    if (msg) await post(msg);
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
      alert.push(`The post scan has not run for at least ${Math.round((now - last - HEARTBEAT_MS) / 60000)} minutes: new posts are not getting their greeting and queue card. Check the Worker's cron trigger.`);
    }
    if (state.error && now - state.error.at < ERROR_SHOWN_MS) {
      alert.push(`The post scan hit a problem at ${new Date(state.error.at).toISOString()}: ${state.error.text}. Check the bot's permissions in those channels.`);
    }
    const gaveUp = (state.gaveUp || []).filter((g) => now - g.at < ERROR_SHOWN_MS);
    if (gaveUp.length) {
      alert.push(`In the last day the post scan gave up on these, after ${MAX_TRIES} tries or because the queue channel refused the bot; a moderator can file each post by right-click:`);
      for (const g of gaveUp) alert.push(`- ${g.what}: https://discord.com/channels/${env.GUILD_ID}/${g.post}`);
    }
    if (alert.length) { await postLines(alert); alerted = true; }
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
