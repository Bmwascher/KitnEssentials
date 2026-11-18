import test from 'node:test';
import assert from 'node:assert/strict';
import { scan as runScan, daily, GREETING, CRONS } from '../src/scan.js';
import { MESSAGES } from '../src/core.js';

// A scan that does not really wait out KV's one write a second per key; the
// case that checks the spacing passes its own clock.
const scan = (env, deps = {}) => runScan(env, { sleep: async () => {}, ...deps });
import { scheduled } from '../src/worker.js';
import { fakeFetch, fakeKv, FORUM } from './fake-fetch.mjs';

const HOUR = 60 * 60 * 1000;
const T0 = Date.UTC(2026, 10, 16, 12);
// A Discord id made at a given time.
const idAt = (ms) => ((BigInt(ms) - 1420070400000n) << 22n).toString();

// A KV namespace for a bot that started at `t`.
const started = (t, state = {}) => fakeKv({ 'scan:since': String(t), 'scan:state': JSON.stringify({ last: t, ...state }) });
const stateOf = (kv) => JSON.parse(kv.m.get('scan:state'));
const baseEnv = (kv) => ({ DISCORD_BOT_TOKEN: 'bot', GUILD_ID: '1', FORUMS: '{"900":{"client":"Retail","type":"Bug"}}', STATE: kv });

// The archived list is served `pageSize` at a time; `refuse` maps a channel
// id to the status its message calls answer with, and `postRefuse` refuses
// only its sends; `said` holds a channel's messages, newest first. A post is
// read from the active and archived lists. The bot's own user id is 'b'.
function discord({ active = [], archived = [], pageSize = 50, refuse = {}, postRefuse = {}, said = {} } = {}) {
  let n = 0;
  const no = (status) => new Response(JSON.stringify({ message: 'no' }), { status });
  return fakeFetch([
    ['GET', /\/users\/@me$/, () => ({ id: 'b' })],
    ['GET', /\/guilds\/1\/threads\/active$/, () => ({ threads: active })],
    ['GET', /\/channels\/900\/threads\/archived\/public/, (b, url) => {
      const before = /before=([^&]+)/.exec(url);
      const rest = before ? archived.filter((t) => t.thread_metadata.archive_timestamp < decodeURIComponent(before[1])) : archived;
      return { threads: rest.slice(0, pageSize), has_more: rest.length > pageSize };
    }],
    ['GET', /\/channels\/900$/, () => ({ ...FORUM, available_tags: [...FORUM.available_tags, { id: 's-ans', name: 'Answered' }] })],
    ['GET', /\/channels\/\d+$/, (b, url) => [...active, ...archived].find((t) => url.endsWith(`/${t.id}`)) || no(404)],
    ['GET', /\/channels\/\d+\/messages\/\d+$/, (b, url) => {
      const [, ch, id] = /channels\/(\d+)\/messages\/(\d+)$/.exec(url);
      return (said[ch] || []).find((m) => m.id === id) || no(404);
    }],
    ['GET', /\/channels\/\d+\/messages\?/, (b, url) => {
      const id = /channels\/(\d+)\//.exec(url)[1];
      return refuse[id] ? no(refuse[id]) : (said[id] || []);
    }],
    ['POST', /\/channels\/\d+\/messages$/, (b, url) => {
      const id = /channels\/(\d+)\//.exec(url)[1];
      const status = refuse[id] || postRefuse[id];
      return status ? no(status) : { id: `m${++n}` };
    }],
  ]);
}
// An archived post made at `ms` and archived at `archivedMs`.
const archivedPost = (ms, archivedMs, over = {}) => ({
  id: idAt(ms), parent_id: '900', thread_metadata: { archived: true, auto_archive_duration: 60, archive_timestamp: new Date(archivedMs).toISOString(), ...over },
});

test('the first scan only starts the clock: posts made before the bot never get a message', async () => {
  const kv = fakeKv();
  const f = discord({ active: [{ id: idAt(T0 - HOUR), parent_id: '900' }] });
  await scan(baseEnv(kv), { fetch: f, now: () => T0, log: () => {} });
  assert.equal(kv.m.get('scan:since'), String(T0));
  assert.equal(f.calls.length, 0);
});

const withQueue = (kv) => ({ ...baseEnv(kv), QUEUE_CHANNEL_ID: '556' });

test('each new post gets the buttonless greeting and one queue card, once', async () => {
  const kv = started(T0);
  const post = idAt(T0 + 60000);
  const starter = { id: post, author: { id: '42', username: 'kira_99', global_name: 'Kira' } };
  const f = discord({ active: [{ id: post, parent_id: '900', name: 'Bag sort ignores reagent bag' }], said: { [post]: [starter] } });
  await scan(withQueue(kv), { fetch: f, now: () => T0 + 5 * 60000, log: () => {} });
  await scan(withQueue(kv), { fetch: f, now: () => T0 + 10 * 60000, log: () => {} });
  const [greeting, card, ...more] = f.find('POST', /\/messages$/);
  assert.deepEqual(more, [], 'once');
  assert.match(greeting.url, new RegExp(`/channels/${post}/messages$`));
  assert.deepEqual(greeting.body, { content: GREETING, allowed_mentions: { parse: [] } });
  assert.match(card.url, /\/channels\/556\/messages$/);
  assert.equal(card.body.content, '**New post in <#900>:** Bag sort ignores reagent bag\nby Kira (`kira_99`) · Bug · Retail');
  assert.deepEqual(card.body.components[0].components.map((b) => b.custom_id || b.url), [`send:${post}`, `https://discord.com/channels/1/${post}`]);
  assert.deepEqual(JSON.parse(kv.m.get(`thread:${post}`)), { greeting: 'm1', buttonless: true, card: 'm2' });
});

test('with no queue channel a new post gets the greeting only', async () => {
  const kv = started(T0);
  const a = idAt(T0 + 1000);
  const f = discord({ active: [{ id: a, parent_id: '900' }] });
  await scan(baseEnv(kv), { fetch: f, now: () => T0 + 5 * 60000, log: () => {} });
  assert.deepEqual(f.find('POST', /\/messages$/).map((c) => c.url.split('/').at(-2)), [a]);
  assert.deepEqual(JSON.parse(kv.m.get(`thread:${a}`)), { greeting: 'm1', buttonless: true });
  assert.equal(stateOf(kv).through['900'], a, 'with no queue, the greeting settles the post');
});

test('posts in other channels, and posts older than the start, are left alone', async () => {
  const kv = started(T0);
  const f = discord({ active: [{ id: idAt(T0 + 1000), parent_id: '999' }, { id: idAt(T0 - 1000), parent_id: '900' }] });
  await scan(baseEnv(kv), { fetch: f, now: () => T0 + 5 * 60000, log: () => {} });
  assert.equal(f.find('POST', /\/messages$/).length, 0);
});

test('with no forums, no guild or no KV namespace the scan does nothing at all', async () => {
  for (const over of [{ FORUMS: '' }, { FORUMS: 'not json' }, { GUILD_ID: '' }, { STATE: undefined }]) {
    const kv = fakeKv({ 'scan:since': String(T0) });
    const f = discord({ active: [{ id: idAt(T0 + 1000), parent_id: '900' }] });
    const r = await scan({ ...baseEnv(kv), ...over }, { fetch: f, now: () => T0 + 60000, log: () => {} });
    assert.equal(r.skipped, true, JSON.stringify(over));
    assert.equal(f.calls.length, 0, JSON.stringify(over));
  }
});

test('a busy run greets eight posts and leaves the rest for the next run', async () => {
  const kv = started(T0);
  const active = Array.from({ length: 11 }, (_, i) => ({ id: idAt(T0 + 1000 * (i + 1)), parent_id: '900' }));
  const f = discord({ active });
  const first = await scan(withQueue(kv), { fetch: f, now: () => T0 + 5 * 60000, log: () => {} });
  assert.deepEqual([first.greeted.length, first.left], [8, 3]);
  assert.deepEqual(first.greeted, active.slice(0, 8).map((t) => t.id), 'oldest first');
  assert.equal(f.find('POST', /\/channels\/556\/messages$/).length, 8, 'a card for each');
  assert.ok(f.calls.length <= 50, `within the call budget: ${f.calls.length} calls`);
  const second = await scan(withQueue(kv), { fetch: f, now: () => T0 + 10 * 60000, log: () => {} });
  assert.deepEqual([second.greeted.length, second.left], [3, 0]);
});


test('the daily check lists posts waiting too long with no status or Answered tag', async () => {
  const kv = started(T0, { last: T0 + 5 * 24 * HOUR - 60000 });
  const now = T0 + 5 * 24 * HOUR;
  let k = 0;
  const old = (tags) => ({ id: idAt(T0 + 1000 * ++k), parent_id: '900', name: 'post', applied_tags: tags });
  const waiting = old(['t-retail']);
  const f = discord({ active: [waiting, old(['s-tri']), old(['s-ans']), { id: idAt(now - HOUR), parent_id: '900', applied_tags: [] }] });
  const r = await daily({ ...baseEnv(kv), MOD_CHANNEL_ID: '555' }, { fetch: f, now: () => now, log: () => {} });
  assert.equal(r.waiting, 1);
  const msg = f.find('POST', /\/channels\/555\/messages$/)[0].body.content;
  assert.match(msg, /1 post\(s\) older than 3 days/);
  assert.match(msg, new RegExp(`discord.com/channels/1/${waiting.id}`));
  assert.doesNotMatch(msg, /scan has not run/);
});

test('the daily check warns when the scan has stopped, and logs when no channel is set', async () => {
  const kv = started(T0);
  const f = discord();
  const out = [];
  await daily(baseEnv(kv), { fetch: f, now: () => T0 + 3 * HOUR, log: (s) => out.push(s) });
  assert.match(out.join('\n'), /scan has not run for at least 165 minutes: new posts are not getting their greeting and queue card\./);
  assert.equal(f.find('POST', /\/messages$/).length, 0);
});

test('a saved scan time older than an hour by less than the heartbeat raises no alarm', async () => {
  const kv = started(T0);
  const out = [];
  await daily(baseEnv(kv), { fetch: discord(), now: () => T0 + 70 * 60 * 1000, log: (s) => out.push(s) });
  assert.doesNotMatch(out.join('\n'), /scan has not run/);
});

test('the Worker runs the daily check on its daily cron and the scan otherwise', async () => {
  const kv = fakeKv();
  const f = discord();
  await scheduled({ cron: CRONS.scan }, baseEnv(kv), {}, { fetch: f, log: () => {} });
  assert.ok(kv.m.get('scan:since'), 'the scan ran');
  const out = [];
  await scheduled({ cron: CRONS.daily }, { ...baseEnv(kv), MOD_CHANNEL_ID: '' }, {}, { fetch: f, log: (s) => out.push(s) });
  assert.equal(f.find('GET', /\/guilds\/1\/threads\/active$/).length, 1, 'the daily check read the posts');
});

// ---- Refused and failing posts, duplicates, budgets ----------------------------

const sends = (f) => f.find('POST', /\/channels\/\d+\/messages$/).map((c) => /channels\/(\d+)\//.exec(c.url)[1]);

test('a post the bot may not message is skipped, and later posts still get theirs', async () => {
  const kv = started(T0);
  const a = idAt(T0 + 1000);
  const b = idAt(T0 + 2000);
  const f = discord({ active: [{ id: a, parent_id: '900' }, { id: b, parent_id: '900' }], refuse: { [a]: 403 } });
  const r = await scan(baseEnv(kv), { fetch: f, now: () => T0 + 5 * 60000, log: () => {} });
  assert.deepEqual(r.greeted, [b]);
  assert.match(JSON.parse(kv.m.get(`thread:${a}`)).skipped, /403/);
  assert.equal(stateOf(kv).last, T0 + 5 * 60000);
  await scan(baseEnv(kv), { fetch: f, now: () => T0 + 10 * 60000, log: () => {} });
  assert.deepEqual(sends(f), [b], 'the refused post is not tried again');
});

test('a post that fails for another reason is tried again next run, and the daily check reports it', async () => {
  const kv = started(T0);
  const a = idAt(T0 + 1000);
  const refuse = { [a]: 500 };
  const f = discord({ active: [{ id: a, parent_id: '900' }], refuse });
  const r = await scan(baseEnv(kv), { fetch: f, now: () => T0 + 5 * 60000, log: () => {} });
  assert.deepEqual([r.greeted.length, r.left], [0, 1]);
  assert.equal(stateOf(kv).last, T0 + 5 * 60000, 'the run still counts as run');
  assert.match(stateOf(kv).error.text, new RegExp(`post ${a}`));
  const out = [];
  await daily(baseEnv(kv), { fetch: f, now: () => T0 + 6 * 60000, log: (s) => out.push(s) });
  assert.match(out.join('\n'), /scan hit a problem/);
  delete refuse[a];
  const again = await scan(baseEnv(kv), { fetch: f, now: () => T0 + 10 * 60000, log: () => {} });
  assert.deepEqual(again.greeted, [a]);
  const later = [];
  await daily(baseEnv(kv), { fetch: f, now: () => T0 + 26 * HOUR, log: (s) => later.push(s) });
  assert.doesNotMatch(later.join('\n'), /hit a problem/, 'a problem a day old is not reported again');
});

test('a locked post is never messaged', async () => {
  const kv = started(T0);
  const f = discord({ active: [{ id: idAt(T0 + 1000), parent_id: '900', thread_metadata: { locked: true } }] });
  await scan(baseEnv(kv), { fetch: f, now: () => T0 + 5 * 60000, log: () => {} });
  assert.deepEqual(sends(f), []);
});

test('a post that already shows the button (its record was lost) is not messaged again', async () => {
  const kv = started(T0);
  const a = idAt(T0 + 1000);
  const button = { id: 'old1', author: { id: 'b', bot: true }, components: [{ type: 1, components: [{ type: 2, custom_id: `send:${a}` }] }] };
  const f = discord({ active: [{ id: a, parent_id: '900' }], said: { [a]: [{ id: 'x' }, button] } });
  await scan(baseEnv(kv), { fetch: f, now: () => T0 + 5 * 60000, log: () => {} });
  assert.deepEqual(sends(f), []);
  assert.deepEqual(JSON.parse(kv.m.get(`thread:${a}`)), { greeting: 'old1' });
});

test('a greeting or card already there (its record was lost) is not posted again; another app\'s message is not taken for it', async () => {
  const cardBy = (author, a) => ({ id: 'c1', author: { id: author, bot: true }, components: [{ type: 1, components: [{ type: 2, style: 5, url: `https://discord.com/channels/1/${a}` }] }] });
  for (const [why, inQueue, want, card] of [
    ['both exist', 'b', [], 'c1'],
    ['only the greeting exists', null, ['556'], 'm1'],
    ['a card by another app links the post', 'x', ['556'], 'm1'],
  ]) {
    const kv = started(T0);
    const a = idAt(T0 + 1000);
    const greeting = { id: 'g1', content: GREETING, author: { id: 'b', bot: true } };
    const f = discord({ active: [{ id: a, parent_id: '900' }], said: { [a]: [greeting], 556: inQueue ? [cardBy(inQueue, a)] : [] } });
    await scan(withQueue(kv), { fetch: f, now: () => T0 + 5 * 60000, log: () => {} });
    assert.deepEqual(sends(f), want, why);
    assert.deepEqual(JSON.parse(kv.m.get(`thread:${a}`)), { greeting: 'g1', buttonless: true, card }, why);
  }
});

test('a queue read that fails keeps the greeting saved and the progress mark behind the post, and the next scan posts the card with no second greeting', async () => {
  const kv = started(T0);
  const a = idAt(T0 + 1000);
  const refuse = { 556: 500 };
  const f = discord({ active: [{ id: a, parent_id: '900' }], refuse });
  await scan(withQueue(kv), { fetch: f, now: () => T0 + 5 * 60000, log: () => {} });
  assert.deepEqual(sends(f), [a]);
  assert.deepEqual(JSON.parse(kv.m.get(`thread:${a}`)), { greeting: 'm1', buttonless: true, tries: 1 }, 'the greeting is saved before the card');
  assert.match(stateOf(kv).error.text, new RegExp(`queue card for post ${a}`));
  assert.equal(stateOf(kv).through['900'], undefined, 'the mark waits for the card');
  assert.equal(stateOf(kv).greeted['900'], a, 'the greeting mark passes the greeted post, so it is not new again');
  delete refuse[556];
  const before = f.calls.length;
  await scan(withQueue(kv), { fetch: f, now: () => T0 + 6 * 60000, log: () => {} });
  assert.deepEqual(f.calls.slice(before).filter((c) => c.url.includes(`/channels/${a}/messages?`)), [], 'a saved greeting is never looked for or sent again');
  assert.deepEqual(sends(f), [a, '556']);
  assert.deepEqual(JSON.parse(kv.m.get(`thread:${a}`)), { greeting: 'm1', buttonless: true, tries: 1, card: 'm2' });
  assert.equal(stateOf(kv).through['900'], a);
});

test('a refused queue skips the card and keeps the greeting', async () => {
  for (const [why, opts] of [['the queue read is refused', { refuse: { 556: 403 } }], ['the card is refused', { postRefuse: { 556: 403 } }]]) {
    const kv = started(T0);
    const a = idAt(T0 + 1000);
    const f = discord({ active: [{ id: a, parent_id: '900' }], ...opts });
    await scan(withQueue(kv), { fetch: f, now: () => T0 + 5 * 60000, log: () => {} });
    assert.equal(f.find('POST', new RegExp(`/channels/${a}/messages$`)).length, 1, why);
    const rec = JSON.parse(kv.m.get(`thread:${a}`));
    assert.deepEqual([rec.greeting, rec.buttonless, rec.card, rec.skipped], ['m1', true, undefined, undefined], why);
    assert.match(rec.cardSkipped, /403/, why);
    assert.equal(stateOf(kv).through['900'], a, why);
    // A channel the bot was never let into is a setup problem: named, not just skipped.
    assert.match(stateOf(kv).error.text, new RegExp(`queue card for post ${a} \\(the queue channel refused the bot\\)`), why);
    assert.deepEqual(stateOf(kv).gaveUp.map((g) => [g.post, g.what]), [[a, 'queue card']], why);
  }
});

test('cards owed by older posts never take the greetings\' share; a post over the card share waits and spends no try', async () => {
  const owed = Array.from({ length: 8 }, (_, i) => idAt(T0 + 1000 * (i + 1)));
  const kv = started(T0);
  for (const id of owed) await kv.put(`thread:${id}`, JSON.stringify({ greeting: 'g', buttonless: true, tries: 1 }));
  const fresh = Array.from({ length: 8 }, (_, i) => ({ id: idAt(T0 + 100000 + 1000 * i), parent_id: '900', name: 'x' }));
  const f = discord({ active: [...owed.map((id) => ({ id, parent_id: '900', name: 'x' })), ...fresh] });
  // The post a card is for, from its Open post link, which every card has.
  const carded = () => f.find('POST', /\/channels\/556\/messages$/).map((c) => c.body.components[0].components.at(-1).url.split('/').at(-1));
  const r = await scan(withQueue(kv), { fetch: f, now: () => T0 + 5 * 60000, log: () => {} });
  assert.deepEqual(r.greeted, fresh.map((t) => t.id), 'every new post is greeted');
  assert.deepEqual(carded(), owed, 'the older posts\' cards, oldest first, within the card share');
  assert.ok(f.calls.length <= 50, `within the call budget: ${f.calls.length} calls`);
  for (const t of fresh) assert.equal(JSON.parse(kv.m.get(`thread:${t.id}`)).tries, undefined, 'a post that waited for the card share spent no try');
  assert.equal(stateOf(kv).through['900'], owed.at(-1), 'the mark waits at the first post still owed a card');
  await scan(withQueue(kv), { fetch: f, now: () => T0 + 6 * 60000, log: () => {} });
  assert.deepEqual(carded(), [...owed, ...fresh.map((t) => t.id)]);
  assert.equal(stateOf(kv).through['900'], fresh.at(-1).id);
});

test('a post filed before the scan reaches it gets no greeting and no card, and holds back nothing', async () => {
  const a = idAt(T0 + 1000);
  const filed = JSON.stringify({ repo: 'me/one', number: 3, key: 'ONE', by: 'Bite' });
  for (const [why, entries] of [
    ['filed by right-click before the first scan', { [`issue:${a}`]: filed }],
    ['filed after its greeting, with its card still owed', { [`thread:${a}`]: JSON.stringify({ greeting: 'g', buttonless: true, tries: 2 }), [`issue:${a}`]: filed }],
    ['an older record names its issue', { [`thread:${a}`]: JSON.stringify({ greeting: 'g', issue: { repo: 'me/one', number: 3 } }) }],
  ]) {
    const kv = started(T0);
    for (const [k, v] of Object.entries(entries)) await kv.put(k, v);
    const f = discord({ active: [{ id: a, parent_id: '900' }] });
    await scan(withQueue(kv), { fetch: f, now: () => T0 + 5 * 60000, log: () => {} });
    assert.deepEqual(sends(f), [], why);
    assert.equal(stateOf(kv).through['900'], a, why);
  }
});

test('the greeting and the card share one tries count: giving up after the greeting skips only the card', async () => {
  const a = idAt(T0 + 1000);
  const kv = started(T0);
  await kv.put(`thread:${a}`, JSON.stringify({ tries: 29 }));
  const f = discord({ active: [{ id: a, parent_id: '900' }], refuse: { 556: 500 } });
  await scan(withQueue(kv), { fetch: f, now: () => T0 + 5 * 60000, log: () => {} });
  const rec = JSON.parse(kv.m.get(`thread:${a}`));
  assert.deepEqual([rec.greeting, rec.buttonless, rec.skipped], ['m1', true, undefined], 'the greeting stays');
  assert.match(rec.cardSkipped, /500/);
  assert.equal(stateOf(kv).through['900'], a);
  assert.match(stateOf(kv).error.text, new RegExp(`queue card for post ${a} \\(gave up after 30 tries\\)`));
});

test('a card goes out only to a post still open when it is sent; one whose first message is gone says how to file it', async () => {
  const a = idAt(T0 + 1000);
  const now = { id: a, parent_id: '900', name: 'x' };
  for (const [why, readNow, skipped, button] of [
    // The post is in this run's active list, then changed by the time its card is made.
    ['the post was deleted', () => new Response('{"message":"Unknown Channel"}', { status: 404 }), /404/, null],
    ['the post was archived', () => ({ ...now, thread_metadata: { archived: true } }), /archived/, null],
    ['the post was locked', () => ({ ...now, thread_metadata: { locked: true } }), /locked/, null],
    ['the post moved to a forum the bot is not set up for', () => ({ ...now, parent_id: '901' }), /forum/, null],
    ['only its first message was deleted', () => now, null, false],
    ['the post as it was', () => now, null, true],
  ]) {
    const kv = started(T0);
    await kv.put(`thread:${a}`, JSON.stringify({ greeting: 'g1', buttonless: true }));
    const said = button ? { [a]: [{ id: a, author: { id: '42', username: 'kira_99', global_name: 'Kira' } }] } : {};
    const base = discord({ active: [now], said });
    const fetch = (url, init = {}) => ((init.method || 'GET') === 'GET' && url.endsWith(`/channels/${a}`)
      ? Promise.resolve(readNow()).then((r) => (r instanceof Response ? r : new Response(JSON.stringify(r))))
      : base(url, init));
    await scan(withQueue(kv), { fetch, now: () => T0 + 5 * 60000, log: () => {} });
    const rec = JSON.parse(kv.m.get(`thread:${a}`));
    const [card] = base.find('POST', /\/channels\/556\/messages$/);
    if (skipped) {
      assert.equal(card, undefined, why);
      assert.match(rec.cardSkipped, skipped, why);
      continue;
    }
    assert.equal(rec.card, 'm1', why);
    assert.equal(card.body.components[0].components.some((b) => b.custom_id === `send:${a}`), button, `${why}: the send button`);
    if (!button) assert.match(card.body.content, /right-click a message › Apps › Send to GitHub\.$/, why);
  }
});

test('a record written twice in one pass waits out KV\'s one write a second, and a failed write stays with its post', async () => {
  const kv = started(T0);
  const [a, b] = [idAt(T0 + 1000), idAt(T0 + 2000)];
  let t = 0;
  const puts = [];
  const put = kv.put;
  kv.put = async (k, v) => {
    puts.push([k, t]);
    // The first post's card record, and the write after it, hit KV's limit.
    if (k === `thread:${a}` && puts.filter(([x]) => x === k).length > 1) throw new Error('KV PUT failed: 429 Too Many Requests');
    return put(k, v);
  };
  const f = discord({ active: [{ id: a, parent_id: '900', name: 'x' }, { id: b, parent_id: '900', name: 'y' }] });
  await scan(withQueue(kv), { fetch: f, now: () => T0 + 5 * 60000, log: () => {}, clock: () => t, sleep: async (ms) => { t += ms; } });
  for (const id of [a, b]) {
    const at = puts.filter(([k]) => k === `thread:${id}`).map(([, ms]) => ms);
    for (let i = 1; i < at.length; i++) assert.ok(at[i] - at[i - 1] >= 1000, `post ${id}: writes at ${at.join(', ')} ms`);
  }
  assert.deepEqual(sends(f), [a, '556', b, '556'], 'the first post\'s failed writes stop nothing');
  assert.deepEqual(JSON.parse(kv.m.get(`thread:${b}`)), { greeting: 'm3', buttonless: true, card: 'm4' });
  assert.match(stateOf(kv).error.text, new RegExp(`the record of queue card for post ${a}`));
});

test('new posts come first: older posts\' card retries and posts filed before the scan take neither the greetings nor the reads new posts need', async () => {
  // Thirty older posts, greeted and still owed their cards, would use every KV read.
  const older = Array.from({ length: 30 }, (_, i) => idAt(T0 + 1000 * (i + 1)));
  const kv = started(T0, { greeted: { 900: older.at(-1) } });
  for (const id of older) await kv.put(`thread:${id}`, JSON.stringify({ greeting: 'g', buttonless: true, tries: 1 }));
  // Eight new posts filed by right-click before the scan, then one new post.
  const filed = Array.from({ length: 8 }, (_, i) => idAt(T0 + 100000 + 1000 * i));
  for (const id of filed) await kv.put(`issue:${id}`, JSON.stringify({ repo: 'me/one', number: 3, key: 'ONE', by: 'Bite' }));
  const fresh = idAt(T0 + 200000);
  const f = discord({ active: [...older, ...filed, fresh].map((id) => ({ id, parent_id: '900', name: 'x' })) });
  let reads = 0;
  const get = kv.get;
  kv.get = async (k) => { if (k.startsWith('thread:') || k.startsWith('issue:')) reads++; return get(k); };
  const r = await scan(withQueue(kv), { fetch: f, now: () => T0 + 5 * 60000, log: () => {} });
  assert.deepEqual(r.greeted, [fresh], 'the new post is greeted');
  assert.ok(reads <= 60, `within the KV reads: ${reads}`);
  assert.ok(f.calls.length <= 50, `within the call budget: ${f.calls.length} calls`);
  assert.equal(f.find('POST', /\/channels\/556\/messages$/).length, 8, 'the card share goes on');
});

test('a post whose receipt is already there (its filing record missing) gets no greeting and no card', async () => {
  const kv = started(T0);
  const a = idAt(T0 + 1000);
  const receipt = { id: 'r1', author: { id: 'b', bot: true }, content: MESSAGES.tracked('ONE', 3) };
  const f = discord({ active: [{ id: a, parent_id: '900' }], said: { [a]: [receipt] } });
  await scan(withQueue(kv), { fetch: f, now: () => T0 + 5 * 60000, log: () => {} });
  assert.deepEqual(sends(f), []);
  assert.deepEqual(JSON.parse(kv.m.get(`thread:${a}`)), { tracked: 'r1' });
  assert.equal(stateOf(kv).through['900'], a);
});

test('every post given up on in the last day is named in the daily alert, whatever errors come after', async () => {
  const kv = started(T0);
  const posts = Array.from({ length: 8 }, (_, i) => idAt(T0 + 1000 * (i + 1)));
  for (const id of posts) await kv.put(`thread:${id}`, JSON.stringify({ greeting: 'g', buttonless: true, tries: 29 }));
  const later = idAt(T0 + 100000);
  const refuse = { 556: 500 };
  const f = discord({ active: posts.map((id) => ({ id, parent_id: '900', name: 'x' })), refuse });
  await scan(withQueue(kv), { fetch: f, now: () => T0 + 5 * 60000, log: () => {} });
  // A later run's own error replaces the error summary.
  const g = discord({ active: [{ id: later, parent_id: '900' }], refuse: { [later]: 500 } });
  await scan(withQueue(kv), { fetch: g, now: () => T0 + 6 * 60000, log: () => {} });
  assert.doesNotMatch(stateOf(kv).error.text, /queue card/);
  const out = [];
  await daily(withQueue(kv), { fetch: f, now: () => T0 + 7 * 60000, log: (s) => out.push(s) });
  for (const id of posts) assert.match(out.join('\n'), new RegExp(`- queue card: https://discord\\.com/channels/1/${id}`), id);
});



test('posts already handled are not read from KV again', async () => {
  const kv = started(T0);
  const active = Array.from({ length: 3 }, (_, i) => ({ id: idAt(T0 + 1000 * (i + 1)), parent_id: '900' }));
  const f = discord({ active });
  await scan(baseEnv(kv), { fetch: f, now: () => T0 + 5 * 60000, log: () => {} });
  assert.equal(stateOf(kv).through['900'], active[2].id);
  let reads = 0;
  const get = kv.get;
  kv.get = async (k) => { if (k.startsWith('thread:') || k.startsWith('issue:')) reads++; return get(k); };
  active.push({ id: idAt(T0 + 9000), parent_id: '900' });
  const r = await scan(baseEnv(kv), { fetch: f, now: () => T0 + 10 * 60000, log: () => {} });
  assert.deepEqual(r.greeted, [active[3].id]);
  assert.equal(reads, 2, 'only the new post is looked up (its record, then whether it was filed)');
});

test('a post made in the same millisecond the bot started is left alone', async () => {
  const kv = started(T0);
  const f = discord({ active: [{ id: idAt(T0), parent_id: '900' }] });
  await scan(baseEnv(kv), { fetch: f, now: () => T0 + 5 * 60000, log: () => {} });
  assert.deepEqual(sends(f), []);
});

test('the daily check posts the scan alert even when a forum cannot be read, and says which', async () => {
  const kv = started(T0);
  const f = discord();
  const env = { ...baseEnv(kv), FORUMS: '{"900":{},"901":{}}', MOD_CHANNEL_ID: '555' };
  await daily(env, { fetch: f, now: () => T0 + 3 * HOUR, log: () => {} });
  const posted = f.find('POST', /\/channels\/555\/messages$/).map((c) => c.body.content);
  assert.equal(posted.length, 2);
  assert.match(posted[0], /scan has not run for at least 165 minutes/);
  assert.match(posted[1], /Could not read forum 901/);
});

// ---- Progress marks, archived posts, the daily check -----------------------------

test('a post that keeps failing is given up on after 30 runs, and newer posts are never held back', async () => {
  const kv = started(T0);
  const bad = idAt(T0 + 1000);
  const active = [{ id: bad, parent_id: '900' }];
  for (let i = 0; i < 70; i++) active.push({ id: idAt(T0 + 2000 + i), parent_id: '900' });
  const f = discord({ active, refuse: { [bad]: 500 } });
  let t = T0;
  // 30 failing runs, then runs for the posts the KV read limit held back.
  for (let run = 0; run < 33; run++) await scan(baseEnv(kv), { fetch: f, now: () => (t += 5 * 60000), log: () => {} });
  assert.match(JSON.parse(kv.m.get(`thread:${bad}`)).skipped, /500/);
  assert.equal(new Set(sends(f).filter((id) => id !== bad)).size, 70, 'every other post got its button');
  assert.equal(stateOf(kv).through['900'], active.at(-1).id);
  const newest = { id: idAt(T0 + 9000), parent_id: '900' };
  active.push(newest);
  const r = await scan(baseEnv(kv), { fetch: f, now: () => (t += 5 * 60000), log: () => {} });
  assert.deepEqual(r.greeted, [newest.id]);
});




test('a scan writes its state only when something changed, or as a 15-minute heartbeat', async () => {
  const MIN = 60 * 1000;
  const a = idAt(T0 + 1000);
  const failing = `could not read or message post ${a}`;
  for (const [name, kv, opts, at, want] of [
    ['idle under 15 minutes', started(T0), {}, T0 + 14 * MIN, 0],
    ['idle at 15 minutes', started(T0), {}, T0 + 15 * MIN, 1],
    ['a greeted post', started(T0), { active: [{ id: a, parent_id: '900' }] }, T0 + MIN, 1],
    ['a new error', started(T0), { active: [{ id: a, parent_id: '900' }], refuse: { [a]: 500 } }, T0 + MIN, 1],
    ['the same error again', started(T0, { error: { at: T0, text: failing } }), { active: [{ id: a, parent_id: '900' }], refuse: { [a]: 500 } }, T0 + MIN, 0],
  ]) {
    let writes = 0;
    const put = kv.put;
    kv.put = async (k, v) => { if (k === 'scan:state') writes++; return put(k, v); };
    await scan(baseEnv(kv), { fetch: discord(opts), now: () => at, log: () => {} });
    assert.equal(writes, want, name);
  }
});

test('the daily check says nothing about archive pages when nothing is waiting', async () => {
  const kv = started(T0, { last: T0 + 30 * 24 * HOUR });
  const archived = Array.from({ length: 200 }, (_, i) => archivedPost(T0 + 1000 * (i + 1), T0 + 29 * 24 * HOUR - 60000 * i, { }));
  for (const a of archived) a.applied_tags = ['s-ans'];
  const f = discord({ archived });
  const out = [];
  await daily(baseEnv(kv), { fetch: f, now: () => T0 + 30 * 24 * HOUR, log: (s) => out.push(s) });
  assert.deepEqual(out, []);
});


test('the greeting limit counts tries, not successful sends', async () => {
  const kv = started(T0);
  const active = Array.from({ length: 12 }, (_, i) => ({ id: idAt(T0 + 1000 * (i + 1)), parent_id: '900' }));
  const refuse = Object.fromEntries(active.map((t) => [t.id, 500]));
  const f = discord({ active, refuse });
  await scan(baseEnv(kv), { fetch: f, now: () => T0 + 5 * 60000, log: () => {} });
  assert.equal(sends(f).length, 0);
  assert.equal(f.find('GET', /\/messages\?/).length, 8);
});

test('the daily check reports whether its message really went out', async () => {
  const kv = started(T0);
  const f = fakeFetch([
    ['GET', /\/guilds\/1\/threads\/active$/, () => ({ threads: [] })],
    ['GET', /\/channels\/900$/, () => FORUM],
    ['GET', /\/threads\/archived\/public/, () => ({ threads: [] })],
    ['POST', /\/channels\/555\/messages$/, () => new Response('{}', { status: 500 })],
  ]);
  const r = await daily({ ...baseEnv(kv), MOD_CHANNEL_ID: '555' }, { fetch: f, now: () => T0 + 3 * HOUR, log: () => {} });
  assert.equal(r.alerted, true);
  assert.equal(r.posted, false);
});

test('the daily check says when its archive read was cut short, even with nothing on its list', async () => {
  const kv = started(T0, { last: T0 + 30 * 24 * HOUR });
  const archived = Array.from({ length: 400 }, (_, i) => archivedPost(T0 + 1000 * (i + 1), T0 + 29 * 24 * HOUR - 60000 * i));
  for (const a of archived) a.applied_tags = ['s-ans'];
  const f = discord({ archived });
  const out = [];
  await daily(baseEnv(kv), { fetch: f, now: () => T0 + 30 * 24 * HOUR, log: (s) => out.push(s) });
  assert.match(out.join('\n'), /Only the most recently archived posts were checked \(300 per forum, from the last 30 days\)/);
});

test('the scan only ever messages open posts: archived ones are left alone, even after a gap', async () => {
  const kv = started(T0);
  const archived = archivedPost(T0 + 1000, T0 + 2 * HOUR);
  const f = discord({ active: [{ ...archived }], archived: [archived] });
  await scan(baseEnv(kv), { fetch: f, now: () => T0 + 3 * HOUR, log: () => {} });
  assert.deepEqual(sends(f), []);
  assert.equal(f.find('GET', /archived/).length, 0, 'the scan never reads archived lists');
});

test('a forum with many handled posts never holds back a new post in another forum', async () => {
  const kv = started(T0);
  const active = Array.from({ length: 70 }, (_, i) => ({ id: idAt(T0 + 1000 * (i + 1)), parent_id: '900' }));
  const f = discord({ active });
  const env = { ...baseEnv(kv), FORUMS: '{"900":{},"901":{}}' };
  let t = T0;
  for (let run = 0; run < 10; run++) await scan(env, { fetch: f, now: () => (t += 5 * 60000), log: () => {} });
  const other = { id: idAt(T0 + 500000), parent_id: '901' };
  active.push(other);
  const r = await scan(env, { fetch: f, now: () => (t += 5 * 60000), log: () => {} });
  assert.deepEqual(r.greeted, [other.id]);
});

test('the daily check keeps its warnings when a long list is cut to fit', async () => {
  const kv = started(T0, { last: T0 + 30 * 24 * HOUR });
  const archived = Array.from({ length: 400 }, (_, i) => archivedPost(T0 + 1000 * (i + 1), T0 + 29 * 24 * HOUR - 60000 * i));
  for (const a of archived) { a.applied_tags = []; a.name = 'a post with a long enough title to fill the message quickly '.repeat(2); }
  const f = discord({ archived });
  const out = [];
  await daily(baseEnv(kv), { fetch: f, now: () => T0 + 30 * 24 * HOUR, log: (s) => out.push(s) });
  assert.match(out.join('\n'), /Only the most recently archived posts were checked/);
});
