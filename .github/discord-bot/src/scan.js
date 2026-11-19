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
//                 "gaveUp": [{"at", "post", "what": "greeting", "queue card" or
//                             "damaged record <key>"}], each kept two days
//                             for the daily alert}
//   thread:<id>  the scan's record of a post: {"greeting": message id,
//                 "buttonless": true for the greeting without a button,
//                 "card": queue card id, "cardSkipped": why no card goes out,
//                 "skipped": why no greeting goes out, "tracked": the bot's
//                 "now tracked" reply found in the post, "tries": failed
//                 passes, the greeting's and the card's together, "gaveUp":
//                 {"at", "what"} once the scan gave up on it and names it};
//                 one from before the filing record may hold "issue"
//   issue:<id>   the Worker's record once the post is filed: {"repo",
//                 "number", "key", "by"}
//   daily:named  the posts of the give-ups a daily check has named
// Each key has one writer: the scan writes thread: and scan:, the Worker
// issue:, the daily check daily:named.
import { parseForums, snowflakeMs, timedFetch, currentStatus, SEND_BUTTON, queueCard, personName, MESSAGES, discordText } from './core.js';
import { discordClient } from './discord.js';

export { SEND_BUTTON };
// Workers' free plan allows 50 outgoing calls per run. A greeting costs two
// (a look at the post's last messages, then the send) and a queue card three
// (its own look, made just before it, the post as it is now, then the card;
// a post busier than 100 messages takes one more, for its first message,
// and waits when the card share is spent).
// Greetings, cards and the scan's own reads (the active posts, the bot's id,
// the queue channel) each have their own client, so cards can never use up
// what the greetings need. The daily check's forum reads keep their own share.
const MAX_GREET = 8;
const MAX_CARDS = 8;
const READ_BUDGET = 3;
const GREET_BUDGET = 2 * MAX_GREET;
const CARD_BUDGET = 3 * MAX_CARDS;
const FORUM_BUDGET = 44;
const POST_BUDGET = 4;
const MAX_KV_READS = 60;
// The reads older posts' card retries keep when any are owed: the new
// posts' visits never use them, so a run of new posts cannot starve them.
const OLDER_READS = 2 * MAX_CARDS;
// A post whose pass fails this many runs in a row (not a refusal) is given
// up on: about 30 minutes of errors at one scan a minute. Its greeting and
// its card share the count; once the greeting is out, giving up skips only
// the card. A post that waits for a share of this run's calls spends no try.
// Each failed try is one KV write, so the cost stays small.
const MAX_TRIES = 30;
// A post whose record still cannot be read an hour after the post was made
// is given up on and named, as 30 failed tries would be: a record that
// cannot be read cannot count its tries, and is never written over.
const UNREAD_GIVE_UP_MS = 60 * 60 * 1000;
// KV takes one write a second to a key, so a second write to a post's
// record in one pass waits this long after the first.
const KV_GAP_MS = 1100;
const CALL_MS = 5000;
const STALE_SCAN_MS = 60 * 60 * 1000;
const HEARTBEAT_MS = 15 * 60 * 1000;
const ERROR_SHOWN_MS = 24 * 60 * 60 * 1000;
// A give-up stays in the state two days, so one saved just after a daily
// check read the state is still there for the next.
const GAVE_UP_KEPT_MS = 2 * 24 * 60 * 60 * 1000;
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

// What the bot writes: a record is an object; an issue (a filing record, or
// an older record's "issue") names its repo as owner/name and a positive
// whole number; each field of the scan's record has the type the scan gives
// it, so a value the bot could not have written never reads as done, filed
// or a count. Other fields are left alone: older records are read too.
const isRecord = (v) => !!v && typeof v === 'object' && !Array.isArray(v);
const isText = (v) => typeof v === 'string' && v !== '';
const isIssue = (v) => isRecord(v) && typeof v.repo === 'string' && /^[\w.-]+\/[\w.-]+$/.test(v.repo)
  && Number.isInteger(v.number) && v.number > 0;
const SCAN_FIELDS = {
  greeting: isText, card: isText, tracked: isText, skipped: isText, cardSkipped: isText,
  buttonless: (v) => v === true,
  tries: (v) => Number.isInteger(v) && v > 0,
  gaveUp: (v) => isRecord(v) && Number.isFinite(v.at) && isText(v.what),
  issue: isIssue,
};
const isScanRecord = (v) => isRecord(v) && Object.entries(SCAN_FIELDS).every(([k, ok]) => v[k] === undefined || ok(v[k]));
// The scan's own state: marks that are post ids, and times and lists of the
// shapes it writes.
const isMarks = (v) => v === undefined || (isRecord(v) && Object.values(v).every((id) => /^\d+$/.test(String(id))));
const isState = (v) => isRecord(v) && isMarks(v.through) && isMarks(v.greeted)
  && (v.last === undefined || Number.isFinite(v.last))
  && (v.error === undefined || (isRecord(v.error) && Number.isFinite(v.error.at) && typeof v.error.text === 'string'))
  && (v.gaveUp === undefined || (Array.isArray(v.gaveUp)
    && v.gaveUp.every((g) => isRecord(g) && Number.isFinite(g.at) && isText(g.post) && isText(g.what))));

// The scan's and the daily check's own bookkeeping, read so that a damaged
// value is told apart from none: `damaged` is set, and the caller rebuilds
// the value and says so.
async function readOwn(kv, key, ok) {
  const raw = await kv.get(key);
  if (raw === null || raw === undefined) return { value: null };
  let v;
  try { v = JSON.parse(raw); } catch { return { value: null, damaged: true }; }
  return ok(v) ? { value: v } : { value: null, damaged: true };
}

// A record as stored, or null when there is none (or no namespace is bound,
// as before the scan is set up). A value the bot could not have written
// (empty, not JSON, or not shaped as above) throws with `damaged` set to its
// key, and a failed read throws as it is: neither is "no record", nor a
// filing.
export async function readStrict(kv, key) {
  if (!kv) return null;
  const raw = await kv.get(key);
  if (raw === null || raw === undefined) return null;
  let v = null;
  try { v = JSON.parse(raw); } catch { /* damaged, below */ }
  const ok = key.startsWith('issue:') ? isIssue(v) : isScanRecord(v);
  if (!ok) throw Object.assign(new Error(`the KV value at ${key} is damaged (not a record the bot wrote)`), { damaged: key });
  return v;
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
// is missing or not yet visible here. The post's first message, which has
// the post's own id, is among them unless the post is busier than that.
async function lookIn(discord, threadId, myId) {
  const recent = (await discord.call('GET', `/channels/${threadId}/messages?limit=100`)) || [];
  const me = recent.length ? await myId() : null;
  const mine = recent.filter((m) => !!m.author && m.author.id === me);
  const receipt = mine.find((m) => String(m.content || '').startsWith(TRACKED_START));
  return {
    receipt: receipt ? receipt.id : null,
    greeting: mine.find((m) => hasButton(m, threadId) || m.content === GREETING) || null,
    starter: recent.find((m) => m.id === threadId) || null,
    full: recent.length >= 100,
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
  const rawSince = await kv.get('scan:since');
  if (rawSince === null || rawSince === undefined) {
    // First run: start from now, so posts made before the bot never get a message.
    await kv.put('scan:since', String(now));
    await kv.put('scan:state', JSON.stringify({ last: now }));
    return { started: now };
  }
  const since = Number(rawSince);
  const errors = [];
  // A damaged state is rebuilt, and said so: each post's record still says
  // what it needs, and the marks only spare reads.
  const saved = await readOwn(kv, 'scan:state', isState);
  if (saved.damaged) errors.push('scan:state (its saved value was damaged and is rebuilt; give-ups named before may be missing from the daily alert)');
  const state = saved.value || {};
  const through = { ...state.through };
  const greetedTo = { ...through, ...state.greeted };
  const greeted = [];
  const gaveUpNow = [];
  // The give-ups the state still holds. A post is named once.
  const kept = (state.gaveUp || []).filter((g) => now - g.at < GAVE_UP_KEPT_MS);
  const named = new Set(kept.map((g) => g.post));
  const name = (post, what, at = now) => {
    if (named.has(post)) return;
    named.add(post);
    gaveUpNow.push({ at, post, what });
  };
  let left = 0;
  try {
    // A start time that is not a time is damaged, never a first run:
    // starting again from now would pass over every post still waiting.
    if (!(since > 0)) {
      errors.push('scan:since (its saved value is damaged; a bot admin must set it again, see the README)');
      throw new Error(`the KV value at scan:since is damaged: ${String(rawSince).slice(0, 40)}`);
    }
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
    // The post's queue card. Its own look at the post's last 100 messages
    // comes first, made now even when the greeting looked earlier in this
    // pass, since other posts' work runs between the two: the bot's "now
    // tracked" reply there means the post was filed, so it gets no card,
    // whatever the queue channel would answer, and the post's first message
    // is found there, or read on its own in a busier post. Then the bot's own
    // card already in the queue channel, else a new one. The post itself is
    // read last, just before the card goes out, since the active list was
    // read at the start of the run: one deleted since (a 404, a refusal),
    // archived, locked or moved out of the configured forums gets no card.
    // A post whose first message is gone gets a card with no send button,
    // since the form files that message.
    const cardFor = async (t) => {
      const look = await lookIn(carder, t.id, myId);
      if (look.receipt) return { tracked: look.receipt };
      const msgs = await queueRead();
      const mine = msgs.length ? await myId() : null;
      const had = msgs.find((m) => isCardFor(m, t.id, mine, env.GUILD_ID));
      if (had) return { card: had.id };
      let starter = look.starter;
      if (!starter && look.full) {
        try {
          starter = await carder.getMessage(t.id, t.id);
        } catch (err) {
          if (!/ -> 404 /.test(err.message)) throw err;
        }
      }
      const post = await carder.getChannel(t.id);
      const meta = post.thread_metadata || {};
      if (meta.archived || meta.locked) return { cardSkipped: `the post was ${meta.archived ? 'archived' : 'locked'} before its card went out` };
      if (!forums[post.parent_id]) return { cardSkipped: 'the post is no longer in a configured forum' };
      const author = starter && starter.author;
      const info = forums[post.parent_id];
      return { card: (await atQueue(carder.call('POST', `/channels/${queue}/messages`, queueCard({
        guildId: env.GUILD_ID, forumId: post.parent_id, postId: t.id, postName: post.name || t.name,
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
    // Posts past the greeting mark are new: their reads and greetings never
    // wait behind an older post's card retry.
    const isNew = new Set(fresh.filter((t) => BigInt(t.id) > mark(greetedTo, t.parent_id)).map((t) => t.id));
    let reads = 0;
    // Both of a post's records are read strictly: a value the bot could not
    // have written is never taken for "no record", so it is never written over.
    const read = async (key) => {
      if (reads >= MAX_KV_READS) throw new BudgetSpent('KV reads for this run are spent');
      reads++;
      return readStrict(kv, key);
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
    // A finished post whose record says the scan gave up on it, but which
    // the state does not name (its state write was lost, or an overlapping
    // scan wrote over it), is named again from its record.
    const restored = (t, rec) => {
      const g = rec.gaveUp;
      if (g && now - g.at < GAVE_UP_KEPT_MS) name(t.id, g.what, g.at);
      return { greeted: true, finished: true };
    };
    // A failed pass. Out of this run's calls or reads, or with its record
    // unread, the post waits, spends no try, and nothing overwrites its
    // record. A scan record the bot could not have written is never written
    // over either: the post is given up on at once, and named. Any other
    // failure raises the post's one tries count; at MAX_TRIES, on a refusal,
    // or over a damaged filing record, the post is given up on, and once its
    // greeting is out only its card. A named give-up is named only once its
    // record says so.
    const failed = async (t, rec, err) => {
      const greetedNow = !!(rec && rec.greeting);
      if (err.damaged && !rec) {
        log(`post ${t.id} skipped: ${err.message}`);
        errors.push(`post ${t.id} (its saved record ${err.damaged} is damaged)`);
        name(t.id, `damaged record ${err.damaged}`);
        return { greeted: true, finished: true };
      }
      if (!rec && !(err instanceof BudgetSpent) && now - snowflakeMs(t.id) >= UNREAD_GIVE_UP_MS) {
        log(`post ${t.id} skipped: its record could not be read: ${err.message}`);
        errors.push(`post ${t.id} (its saved record thread:${t.id} could not be read)`);
        name(t.id, `unreadable record thread:${t.id}`);
        return { greeted: true, finished: true };
      }
      if (err instanceof BudgetSpent || !rec) {
        if (!rec && !(err instanceof BudgetSpent)) {
          log(`post ${t.id} left for the next run: its record could not be read: ${err.message}`);
          errors.push(`the record of post ${t.id}`);
        }
        left++;
        return { greeted: greetedNow, finished: false };
      }
      const what = greetedNow ? `queue card for post ${t.id}` : `post ${t.id}`;
      // The work went out (a card, a receipt found, a greeting with no queue
      // channel) and only its record's write failed: nothing was given up,
      // no try is spent, and the next pass finds it again by its looks.
      if (finished(rec, queue)) {
        log(`${what}: its record was not saved: ${err.message}`);
        errors.push(`the record of ${what}`);
        left++;
        return { greeted: true, finished: false };
      }
      const tries = (rec.tries || 0) + 1;
      const giveUp = !!err.damaged || refused(err) || tries >= MAX_TRIES;
      // A refusal by the post itself (deleted, closed to the bot) is that
      // post's own end, as before; one by the queue channel is a setup
      // problem every later post shares, so it is named, as are 30 tries
      // and a damaged record.
      const told = giveUp && (!!err.damaged || !refused(err) || !!err.queue);
      log(`${what} ${giveUp ? 'skipped' : 'left for the next run'}: ${err.message}`);
      if (!giveUp) {
        errors.push(what);
        left++;
      } else if (told) {
        errors.push(`${what} (${err.damaged ? `its saved record ${err.damaged} is damaged` : refused(err) ? 'the queue channel refused the bot' : `gave up after ${tries} tries`})`);
      }
      const label = err.damaged ? `damaged record ${err.damaged}` : greetedNow ? 'queue card' : 'greeting';
      try {
        await putRecord(t.id, giveUp
          ? { ...rec, [greetedNow ? 'cardSkipped' : 'skipped']: err.message.slice(0, 200), ...(told ? { gaveUp: { at: now, what: label } } : {}) }
          : { ...rec, tries });
      } catch (e) {
        log(`${what}: its record was not saved: ${e.message}`);
        errors.push(`the record of ${what}`);
        return { greeted: greetedNow, finished: false };
      }
      if (told) name(t.id, label);
      return { greeted: giveUp || greetedNow, finished: giveUp };
    };
    // One post's greeting step. It never throws, so one post's failure stays
    // with it. `greeted`: the greeting is settled; `finished`: nothing is
    // left to do; `owes`: the card is still to try.
    const greet = async (t) => {
      let rec = null;
      let seen = null;
      try {
        rec = (await read(`thread:${t.id}`)) || {};
        if (finished(rec, queue)) return restored(t, rec);
        // A post filed before this pass (by right-click, or from its card
        // after the greeting) gets no greeting and no card.
        if (await read(`issue:${t.id}`)) return { greeted: true, finished: true };
        if (!rec.greeting) {
          // The greeting share counts only posts that try a greeting.
          if (tried >= MAX_GREET) { left++; return { greeted: false, finished: false }; }
          tried++;
          seen = await lookIn(greeter, t.id, myId);
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
        return { greeted: true, finished: false, owes: { t, rec } };
      } catch (err) {
        return failed(t, rec, err);
      }
    };
    // A post's card, once its greeting is settled, within this run's card
    // share. It never throws either.
    const card = async ({ t, rec }) => {
      if (carded >= MAX_CARDS) { left++; return { greeted: true, finished: false }; }
      carded++;
      try {
        rec = { ...rec, ...(await cardFor(t)) };
        await putRecord(t.id, rec);
        return { greeted: true, finished: true };
      } catch (err) {
        return failed(t, rec, err);
      }
    };
    // New posts' greetings first; then older posts' card retries, so a run
    // of new posts never starves them; then the new posts' cards, with what
    // is left of the card share. An older post past the card share waits
    // unread.
    const outcome = new Map();
    const owed = [];
    const older = fresh.filter((x) => !isNew.has(x.id));
    const newReads = MAX_KV_READS - (older.length ? OLDER_READS : 0);
    for (const t of fresh.filter((x) => isNew.has(x.id))) {
      // Once the greeting share is spent, a later new post could only wait:
      // it waits unread.
      if (reads >= newReads || tried >= MAX_GREET) { left++; continue; }
      const o = await greet(t);
      outcome.set(t.id, o);
      if (o.owes) owed.push(o.owes);
    }
    for (const t of older) {
      if (reads >= MAX_KV_READS || carded >= MAX_CARDS) { left++; continue; }
      const o = await greet(t);
      outcome.set(t.id, o.owes ? await card(o.owes) : o);
    }
    for (const o of owed) outcome.set(o.t.id, await card(o));
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
    // Every post given up on stays named for two days, whatever errors
    // follow, so the daily alert lists each one.
    const gaveUp = [...kept, ...gaveUpNow];
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
// holds it back. The daily check writes only which give-ups it named.
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
  // Once the scan has started; a damaged start time too, whose error the
  // scan records.
  if (kv && (await kv.get('scan:since')) !== null) {
    const saved = await readOwn(kv, 'scan:state', isState);
    const state = saved.value || {};
    const last = Number(state.last) || 0;
    const alert = [];
    // An idle scan writes its state only every HEARTBEAT_MS, so the last run
    // may be up to that much newer than the saved time. A damaged state says
    // nothing about when the scan last ran.
    if (saved.damaged) {
      alert.push("The post scan's saved state (scan:state) is damaged. The next scan rebuilds it; posts it gave up on before may be missing below.");
    } else if (now - last > STALE_SCAN_MS + HEARTBEAT_MS) {
      alert.push(`The post scan has not run for at least ${Math.round((now - last - HEARTBEAT_MS) / 60000)} minutes: new posts are not getting their greeting and queue card. Check the Worker's cron trigger.`);
    }
    if (state.error && now - state.error.at < ERROR_SHOWN_MS) {
      alert.push(`The post scan hit a problem at ${new Date(state.error.at).toISOString()}: ${state.error.text}. Check the bot's permissions in those channels.`);
    }
    // Every give-up no daily check has named yet: one the minute's scan
    // saved just after the last check read the state is named by this one,
    // and none twice.
    const all = state.gaveUp || [];
    const shown = new Set([].concat((await readJson(kv, 'daily:named')) || []));
    const gaveUp = all.filter((g) => !shown.has(g.post));
    if (gaveUp.length) {
      alert.push(`In the last day the post scan gave up on these, after ${MAX_TRIES} tries, because the queue channel refused the bot, or because a saved record is damaged; a moderator can file each post by right-click:`);
      for (const g of gaveUp) alert.push(`- ${g.what}: https://discord.com/channels/${env.GUILD_ID}/${g.post}`);
    }
    if (alert.length) { await postLines(alert); alerted = true; }
    if (gaveUp.length) await kv.put('daily:named', JSON.stringify(all.map((g) => g.post)));
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
    for (const t of waiting.slice(0, 20)) lines.push(`- ${t.name ? discordText(t.name) : t.id}: https://discord.com/channels/${env.GUILD_ID}/${t.id}`);
    if (waiting.length > 20) lines.push(`- and ${waiting.length - 20} more`);
  }

  if (lines.length) await post(lines.join('\n'));
  return { waiting: waiting.length, alerted, unread, posted };
}

// Which job a cron expression runs (wrangler.toml [triggers]).
export const CRONS = { scan: '* * * * *', daily: '0 15 * * *' };
