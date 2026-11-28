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
//                 "gaveUp": [{"at", "post", "what": "greeting", "queue card",
//                             "greeting refused by the post (403)", "queue
//                             card refused by the post (403)"}], each kept
//                             two days for the daily alert}
//   thread:<id>  the scan's record of a post: {"greeting": message id,
//                 "buttonless": true for the greeting without a button,
//                 "card": queue card id, "cardSkipped": why no card goes out,
//                 "skipped": why no greeting goes out, "tracked": the bot's
//                 "now tracked" reply found in the post, "tries": failed
//                 passes, the greeting's and the card's together};
//                 one from before the filing record may hold "issue"
//   issue:<id>   the Worker's record once the post is filed: {"repo",
//                 "number", "key", "by": the filer's mention, or an older
//                 version's name}
//   movedfrom:<id>  the Worker's record of a post a move made: {"from": the
//                 old post's id, "reporter": {"name", "id", "username",
//                 "avatar"}, "card": the old post's queue card id}; the
//                 reporter's id, username and avatar and the card optional
//   movedto:<id>  the Worker's record of a post moved away: {"to": the new
//                 post's id}
//   daily:named  the posts of the give-ups a daily check has named
// Each key has one writer: the scan writes thread: and scan:, the Worker
// issue:, movedfrom: and movedto:, the daily check daily:named.
import { parseForums, snowflakeMs, timedFetch, currentStatus, SEND_BUTTON, queueCard, personName, MESSAGES, discordText, postLines, taken, oneHop, isDiscordId, TEXT_TYPES, statusOf, isBotCopy } from './core.js';
import { discordClient } from './discord.js';

export { SEND_BUTTON };
// Workers' free plan allows 50 outgoing calls per run. A greeting costs two
// (a look at the post's last messages, then the send) and a queue card three
// (the post as it is now, its own look, made just before it, then the card;
// a post busier than 100 messages takes one more, for its first message,
// and one more again when that read answers 404, to tell a deleted post;
// a card waits when the card share is spent).
// Greetings, cards and the scan's own reads (the active posts, the bot's id,
// its application's id, the queue channel) each have their own client, so
// cards can never use up what the greetings need. The daily check's forum
// reads keep their own share.
const MAX_GREET = 8;
const MAX_CARDS = 8;
const READ_BUDGET = 4;
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

// A record as stored, or null when there is none (or no namespace is bound,
// as before the scan is set up). A failed read, or a value that is not JSON,
// throws: neither is "no record", nor a filing.
export async function readStrict(kv, key) {
  if (!kv) return null;
  const raw = await kv.get(key);
  if (raw === null || raw === undefined) return null;
  return JSON.parse(raw);
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

// A fetch that refuses calls past its share of the run's budget. `left()`
// says how many it has left, so work that would only be refused is not
// started.
export class BudgetSpent extends Error {}
export function countedFetch(f, budget) {
  let left = budget;
  const counted = (url, init) => {
    if (left <= 0) throw new BudgetSpent('call budget for this run is spent');
    left--;
    return f(url, init);
  };
  counted.left = () => left;
  return counted;
}
function budgetClient(env, deps, budget) {
  return discordClient(env.DISCORD_BOT_TOKEN, countedFetch(timedFetch(oneHop(deps.fetch || fetch), CALL_MS), budget));
}

const refused = (err) => [403, 404].includes(statusOf(err));

const buttons = (m) => (m.components || []).flatMap((row) => row.components || []);
// An old button greeting, or a queue card, holding the post's send button.
export const hasButton = (m, postId) => buttons(m).some((c) => c.custom_id === `${SEND_BUTTON}:${postId}`);
// The bot's own queue card for the post: its send button, or its Open post
// link to exactly this post. Another app's message never counts.
const isCardFor = (m, postId, me, guildId) => !!m.author && m.author.id === me
  && (hasButton(m, postId) || buttons(m).some((c) => c.url === `https://discord.com/channels/${guildId}/${postId}`));

// How the Worker's "now tracked" reply and its reply to a post added to an
// issue start, and its moved message in a post a move made.
const TRACKED_START = MESSAGES.tracked('\u0000', 0).split('\u0000')[0];
const ADDED_START = MESSAGES.added({ key: '\u0000' }).split('\u0000')[0];
const MOVED_START = MESSAGES.movedHere({ from: '\u0000', by: '', reporter: { name: '' } }).split('\u0000')[0];
// The skip a post the bot moved here is saved with; the Worker refuses to
// file a reply in a post whose record says it.
export const MOVED_HERE = 'a post the bot moved here';
// The text of the Worker's "now tracked" or added reply, whoever wrote it. On
// a moved post's copy it starts with the reporter's mention.
export const isReceipt = (m) => {
  const s = String(m.content || '').replace(/^<@\d+> /, '');
  return s.startsWith(TRACKED_START) || s.startsWith(ADDED_START);
};

// The bot's own messages among the post's last 100: its greeting (the
// buttonless one, or an old one still showing its button), and its "now
// tracked" reply, which means the post was filed even when its filing record
// is missing or not yet visible here. The post's first message, which has
// the post's own id, is among them unless the post is busier than that.
async function lookIn(discord, threadId, myId) {
  const recent = (await discord.call('GET', `/channels/${threadId}/messages?limit=100`)) || [];
  const me = recent.length ? await myId() : null;
  const mine = recent.filter((m) => !!m.author && m.author.id === me);
  const receipt = mine.find(isReceipt);
  return {
    receipt: receipt ? receipt.id : null,
    // The move's own message: the post is a copy the bot made, even when its
    // first message is gone or past these 100.
    moved: mine.some((m) => String(m.content || '').startsWith(MOVED_START)),
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
  const state = (await readStrict(kv, 'scan:state')) || {};
  const through = { ...state.through };
  const greetedTo = { ...through, ...state.greeted };
  const greeted = [];
  const gaveUpNow = [];
  // The give-ups the state still holds. A post is named once.
  const kept = (state.gaveUp || []).filter((g) => now - g.at < GAVE_UP_KEPT_MS);
  const named = new Set(kept.map((g) => g.post));
  const name = (post, what) => {
    if (named.has(post)) return;
    named.add(post);
    gaveUpNow.push({ at: now, post, what });
  };
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
    // The bot's application id, which its webhook's messages carry: read
    // once a run, and only for a new post whose first message is an
    // application's webhook message. A failed read is no fault of the post:
    // it is thrown without the request's status, so it counts as a try and
    // is never read as the post's refusal.
    let app = null;
    const myAppId = () => (app = app || discord.call('GET', '/applications/@me').then((a) => a.id, (e) => {
      throw new Error(`the bot's application could not be read (${e.discord ? `status ${e.discord.status}` : e.name})`);
    }));
    // The queue channel's last 100 messages, read once a run and only when a
    // card is due, to find a card whose id was never saved.
    let queued = null;
    // A failure at the queue channel itself is marked, so a refusal there (a
    // channel the bot was never let into) is reported, not just skipped.
    const atQueue = (p) => p.catch((err) => { throw Object.assign(err, { queue: true }); });
    const queueRead = () => (queued = queued || atQueue(discord.call('GET', `/channels/${queue}/messages?limit=100`)).then((m) => m || []));
    // The post's queue card. The active list was read at the start of the
    // run, so the card reads again: the queue channel (once a run), the post
    // as it is now, then its own look at the post's last 100 messages, made
    // now even when the greeting looked earlier in this pass. The look comes
    // last, so a first message deleted while the others were read is seen.
    // The bot's "now tracked" reply there means the post was filed, so it
    // gets no card, whatever the queue channel answered. A post deleted since
    // (a 404, a refusal), archived, locked or moved out of the configured
    // forums gets no card, and the bot's own card already in the queue
    // channel is kept. A busier post's first message is read on its own, as
    // the last read; a post whose first message is gone gets a card with no
    // send button, since the form files that message.
    const cardFor = async (t) => {
      const mine = await myId();
      let queueErr = null;
      const msgs = await queueRead().catch((err) => { queueErr = err; return []; });
      const post = await carder.getChannel(t.id);
      const look = await lookIn(carder, t.id, myId);
      if (look.receipt) return { tracked: look.receipt };
      if (queueErr) throw queueErr;
      const had = msgs.find((m) => isCardFor(m, t.id, mine, env.GUILD_ID));
      if (had) return { card: had.id };
      // A busier post's first message is read on its own, last. When it was
      // deleted, that read reads the post too, and the post as read then
      // decides, not the read before the look.
      let starter = look.starter;
      let latest = post;
      if (!starter && look.full) {
        const read = await carder.readMessage(t.id, t.id);
        starter = read.message;
        latest = read.channel || post;
      }
      const meta = latest.thread_metadata || {};
      if (meta.archived || meta.locked) return { cardSkipped: `the post was ${meta.archived ? 'archived' : 'locked'} before its card went out` };
      if (!forums[latest.parent_id]) return { cardSkipped: 'the post is no longer in a configured forum' };
      const author = starter && starter.author;
      const info = forums[latest.parent_id];
      // A webhook's author id names no user, so it is never a mention.
      return { card: (await atQueue(carder.call('POST', `/channels/${queue}/messages`, queueCard({
        guildId: env.GUILD_ID, forumId: latest.parent_id, postId: t.id,
        author: author ? { name: personName(author), username: author.username, id: starter.webhook_id ? null : author.id } : null,
        client: info.client, type: info.type, starterGone: !starter,
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
    // Both of a post's records are read strictly: a read that fails, or text
    // that is not JSON, is never taken for "no record".
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
    // A failed pass. Out of this run's calls or reads, or with its record
    // unread, the post waits, spends no try, and nothing overwrites its
    // record. Any other failure raises the post's one tries count; at
    // MAX_TRIES or on a refusal the post is given up on, and once its
    // greeting is out only its card. A named give-up is named only once its
    // record says so.
    const failed = async (t, rec, err) => {
      const greetedNow = !!(rec && rec.greeting);
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
      const giveUp = refused(err) || tries >= MAX_TRIES;
      // A refusal by the post itself ends that post. A 404 (deleted) is named
      // to no one; a 403 (the bot may not read or message it) is a setup
      // problem and is named, as are a queue-channel refusal (every later
      // post shares it) and 30 tries. The status comes from
      // the request the client kept, never the response body, and only a
      // request on the post itself names it: a 403 from a shared endpoint
      // (the bot's own user) is no fault of the post.
      const own = !!err.discord && !err.queue && new RegExp(`^/channels/${t.id}(/|$)`).test(err.discord.path);
      const denied = own && err.discord.status === 403;
      const told = giveUp && (!refused(err) || !!err.queue || denied);
      log(`${what} ${giveUp ? 'skipped' : 'left for the next run'}: ${err.message}`);
      if (!giveUp) {
        errors.push(what);
        left++;
      } else if (told && !denied) {
        errors.push(`${what} (${refused(err) ? 'the queue channel refused the bot' : `gave up after ${tries} tries`})`);
      }
      const kind = greetedNow ? 'queue card' : 'greeting';
      const label = denied ? `${kind} refused by the post (403)` : kind;
      try {
        await putRecord(t.id, giveUp
          ? { ...rec, [greetedNow ? 'cardSkipped' : 'skipped']: err.message.slice(0, 200) }
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
        if (finished(rec, queue)) return { greeted: true, finished: true };
        // A post filed before this pass (by right-click, or from its card
        // after the greeting) gets no greeting and no card.
        if (await read(`issue:${t.id}`)) return { greeted: true, finished: true };
        // Nor does a post a move took away, though the move could leave
        // neither its note nor its lock there (a run past its steps' phase).
        if (await read(`movedto:${t.id}`)) return { greeted: true, finished: true };
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
          // The bot's copy of a moved post (the move's message is there, or
          // its first message came from the bot's webhook) gets no greeting
          // or card: the move's message and the old post's card stand in.
          // Discord shows these before KV shows the move's records. The
          // application is read only for a message that could be its copy.
          const isCopy = async (m) => !!(m && m.webhook_id && m.application_id) && isBotCopy(m, await myAppId());
          if (seen.moved || await isCopy(seen.starter)) {
            rec = { ...rec, skipped: MOVED_HERE };
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
    // New posts' greetings first; then older posts' card retries; then the
    // new posts' cards, with what is left of the card share. An older post
    // past the card share or the reads waits unread.
    const outcome = new Map();
    const owed = [];
    const older = fresh.filter((x) => !isNew.has(x.id));
    for (const t of fresh.filter((x) => isNew.has(x.id))) {
      // Once the greeting share is spent, a later new post could only wait:
      // it waits unread.
      if (reads >= MAX_KV_READS || tried >= MAX_GREET) { left++; continue; }
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
    const next = { last: now, through, greeted: greetedTo, ...(state.error ? { error: state.error } : {}) };
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
  // Only a text or announcement channel of this server takes the bot's
  // messages: the channel is read once, before the forum reads can spend
  // their share, on a client of its own.
  const checker = discordClient(env.DISCORD_BOT_TOKEN, countedFetch(timedFetch(oneHop(deps.fetch || fetch), CALL_MS), 1));
  let wrongChannel = null;
  const id = isDiscordId(env.MOD_CHANNEL_ID) ? String(env.MOD_CHANNEL_ID) : null;
  const checkChannel = async () => {
    if (wrongChannel === null) {
      wrongChannel = !id ? 'MOD_CHANNEL_ID is not a channel id' : await checker.getChannel(id).then(
        (c) => (TEXT_TYPES.includes(c.type) && String(c.guild_id) === String(env.GUILD_ID) ? '' : `MOD_CHANNEL_ID ${id} is not a text channel of this server`),
        (err) => `MOD_CHANNEL_ID ${id} could not be checked (Discord ${(err.discord && err.discord.status) || 'gave no answer'})`,
      );
    }
    return wrongChannel;
  };
  if (env.MOD_CHANNEL_ID) await checkChannel();
  // True when the text reached the channel, or the log by design (no
  // channel set, or past the run's posting share); false when the channel
  // failed it, so what it names is named again another day.
  const post = async (text) => {
    text = text.slice(0, 1900);
    if (!env.MOD_CHANNEL_ID) { log(text); return true; }
    const wrong = await checkChannel();
    if (wrong) {
      log(`not posted to the moderator channel: ${wrong}\n${text}`);
      return false;
    }
    try {
      await poster.send(env.MOD_CHANNEL_ID, text);
      posted = true;
      return true;
    } catch (err) {
      if (taken(err)) { posted = true; return true; }
      log(`could not post to the moderator channel: ${err.message}\n${text}`);
      return err instanceof BudgetSpent;
    }
  };

  const kv = env.STATE;
  let alerted = false;
  // Once the scan has started.
  if (kv && (await kv.get('scan:since')) !== null) {
    const state = (await readStrict(kv, 'scan:state')) || {};
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
    // Every give-up no daily check has named yet: one the minute's scan
    // saved just after the last check read the state is named by this one.
    // Only a line the channel took (or the log, by design) counts as named,
    // so one the channel refused is named again by the next check.
    const all = state.gaveUp || [];
    const shown = new Set((await readStrict(kv, 'daily:named')) || []);
    const gaveUp = all.filter((g) => !shown.has(g.post));
    const lineOf = (g) => `- ${g.what}: https://discord.com/channels/${env.GUILD_ID}/${g.post}`;
    const at = new Map();
    if (gaveUp.length) {
      alert.push(`The post scan gave up on these posts: after ${MAX_TRIES} tries; at once when the queue channel or the post refused the bot; or because a saved record could not be read. For a refusal, check the bot's permissions: in the queue channel, View Channel, Send Messages and Read Message History; in the post's forum, View Channel, Send Messages in Threads and Read Message History. A moderator can file each by right-click once access is fixed.`);
      for (const g of gaveUp) {
        at.set(g, alert.length);
        alert.push(lineOf(g));
      }
    }
    // Past the run's posting share, the rest goes to the log (`post`).
    const tookAt = new Set(alert.length ? await postLines(post, alert) : []);
    const named = (g) => at.has(g) && tookAt.has(at.get(g));
    if (alert.length) alerted = true;
    if (gaveUp.some(named)) {
      await kv.put('daily:named', JSON.stringify(all.filter((g) => shown.has(g.post) || named(g)).map((g) => g.post)));
    }
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
      const arch = await discord.archivedThreads(id, now - DAILY_ARCHIVED_MS, DAILY_ARCHIVE_PAGES);
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

  if (lines.length) await postLines(post, lines);
  return { waiting: waiting.length, alerted, unread, posted };
}

// Which job a cron expression runs (wrangler.toml [triggers]).
export const CRONS = { scan: '* * * * *', daily: '0 15 * * *', setup: '30 15 * * *' };
