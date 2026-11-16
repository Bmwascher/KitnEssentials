import test from 'node:test';
import assert from 'node:assert/strict';
import { scan, daily, GREETING, CRONS } from '../src/scan.js';
import { scheduled } from '../src/worker.js';
import { fakeFetch, fakeKv, FORUM } from './fake-fetch.mjs';

const HOUR = 60 * 60 * 1000;
const T0 = Date.UTC(2026, 10, 16, 12);
// A Discord id made at a given time.
const idAt = (ms) => ((BigInt(ms) - 1420070400000n) << 22n).toString();

const baseEnv = (kv) => ({ DISCORD_BOT_TOKEN: 'bot', GUILD_ID: '1', FORUMS: '{"900":{"client":"Retail","type":"Bug"}}', STATE: kv });

// The archived list is served `pageSize` at a time; `refuse` maps a post id
// to the status its message calls answer with; `said` holds a post's messages.
function discord({ active = [], archived = [], pageSize = 50, refuse = {}, said = {} } = {}) {
  let n = 0;
  const no = (status) => new Response(JSON.stringify({ message: 'no' }), { status });
  return fakeFetch([
    ['GET', /\/guilds\/1\/threads\/active$/, () => ({ threads: active })],
    ['GET', /\/channels\/900\/threads\/archived\/public/, (b, url) => {
      const before = /before=([^&]+)/.exec(url);
      const rest = before ? archived.filter((t) => t.thread_metadata.archive_timestamp < decodeURIComponent(before[1])) : archived;
      return { threads: rest.slice(0, pageSize), has_more: rest.length > pageSize };
    }],
    ['GET', /\/channels\/900$/, () => ({ ...FORUM, available_tags: [...FORUM.available_tags, { id: 's-ans', name: 'Answered' }] })],
    ['GET', /\/channels\/\d+\/messages\?/, (b, url) => {
      const id = /channels\/(\d+)\//.exec(url)[1];
      return refuse[id] ? no(refuse[id]) : (said[id] || []);
    }],
    ['POST', /\/channels\/\d+\/messages$/, (b, url) => {
      const id = /channels\/(\d+)\//.exec(url)[1];
      return refuse[id] ? no(refuse[id]) : { id: `m${++n}` };
    }],
  ]);
}
// An archived post made at `ms` and archived at `archivedMs`.
const archivedPost = (ms, archivedMs, over = {}) => ({
  id: idAt(ms), parent_id: '900', thread_metadata: { archived: true, archive_timestamp: new Date(archivedMs).toISOString(), ...over },
});

test('the first scan only starts the clock: posts made before the bot never get a message', async () => {
  const kv = fakeKv();
  const f = discord({ active: [{ id: idAt(T0 - HOUR), parent_id: '900' }] });
  await scan(baseEnv(kv), { fetch: f, now: () => T0, log: () => {} });
  assert.equal(kv.m.get('scan:since'), String(T0));
  assert.equal(f.calls.length, 0);
});

test('each new post in a configured forum gets one message with the button, once', async () => {
  const kv = fakeKv({ 'scan:since': String(T0), 'scan:last': String(T0) });
  const post = idAt(T0 + 60000);
  const f = discord({ active: [{ id: post, parent_id: '900' }] });
  await scan(baseEnv(kv), { fetch: f, now: () => T0 + 5 * 60000, log: () => {} });
  await scan(baseEnv(kv), { fetch: f, now: () => T0 + 10 * 60000, log: () => {} });
  const sent = f.find('POST', /\/messages$/);
  assert.equal(sent.length, 1);
  assert.match(sent[0].url, new RegExp(`/channels/${post}/messages$`));
  assert.equal(sent[0].body.content, GREETING);
  assert.deepEqual(sent[0].body.allowed_mentions, { parse: [] });
  const button = sent[0].body.components[0].components[0];
  assert.deepEqual([button.type, button.label, button.custom_id], [2, 'Send to GitHub', `send:${post}`]);
  assert.deepEqual(JSON.parse(kv.m.get(`thread:${post}`)), { greeting: 'm1' });
});

test('posts in other channels, and posts older than the start, are left alone', async () => {
  const kv = fakeKv({ 'scan:since': String(T0), 'scan:last': String(T0) });
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
  const kv = fakeKv({ 'scan:since': String(T0), 'scan:last': String(T0) });
  const active = Array.from({ length: 11 }, (_, i) => ({ id: idAt(T0 + 1000 * (i + 1)), parent_id: '900' }));
  const f = discord({ active });
  const first = await scan(baseEnv(kv), { fetch: f, now: () => T0 + 5 * 60000, log: () => {} });
  assert.deepEqual([first.greeted.length, first.left], [8, 3]);
  assert.deepEqual(first.greeted, active.slice(0, 8).map((t) => t.id), 'oldest first');
  const second = await scan(baseEnv(kv), { fetch: f, now: () => T0 + 10 * 60000, log: () => {} });
  assert.deepEqual([second.greeted.length, second.left], [3, 0]);
});

test('after a gap in scanning, recently archived posts are caught up too', async () => {
  const kv = fakeKv({ 'scan:since': String(T0), 'scan:last': String(T0) });
  const archived = archivedPost(T0 + 1000, T0 + HOUR);
  const f = discord({ archived: [archived] });
  await scan(baseEnv(kv), { fetch: f, now: () => T0 + 10 * 60000, log: () => {} });
  assert.equal(f.find('GET', /archived/).length, 0, 'a normal interval reads active posts only');
  await scan(baseEnv(kv), { fetch: f, now: () => T0 + 3 * HOUR, log: () => {} });
  assert.equal(f.find('POST', new RegExp(`/channels/${archived.id}/messages$`)).length, 1);
});

test('the daily check lists posts waiting too long with no status or Answered tag', async () => {
  const kv = fakeKv({ 'scan:since': String(T0), 'scan:last': String(T0 + 5 * 24 * HOUR - 60000) });
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
  const kv = fakeKv({ 'scan:since': String(T0), 'scan:last': String(T0) });
  const f = discord();
  const out = [];
  await daily(baseEnv(kv), { fetch: f, now: () => T0 + 3 * HOUR, log: (s) => out.push(s) });
  assert.match(out.join('\n'), /scan has not run for 180 minutes/);
  assert.equal(f.find('POST', /\/messages$/).length, 0);
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

// ---- Round 1 review --------------------------------------------------------------

const sends = (f) => f.find('POST', /\/channels\/\d+\/messages$/).map((c) => /channels\/(\d+)\//.exec(c.url)[1]);

test('a post the bot may not message is skipped, and later posts still get theirs', async () => {
  const kv = fakeKv({ 'scan:since': String(T0), 'scan:last': String(T0) });
  const a = idAt(T0 + 1000);
  const b = idAt(T0 + 2000);
  const f = discord({ active: [{ id: a, parent_id: '900' }, { id: b, parent_id: '900' }], refuse: { [a]: 403 } });
  const r = await scan(baseEnv(kv), { fetch: f, now: () => T0 + 5 * 60000, log: () => {} });
  assert.deepEqual(r.greeted, [b]);
  assert.match(JSON.parse(kv.m.get(`thread:${a}`)).skipped, /403/);
  assert.equal(kv.m.get('scan:last'), String(T0 + 5 * 60000));
  await scan(baseEnv(kv), { fetch: f, now: () => T0 + 10 * 60000, log: () => {} });
  assert.deepEqual(sends(f), [b], 'the refused post is not tried again');
});

test('a post that fails for another reason is tried again next run, and the daily check reports it', async () => {
  const kv = fakeKv({ 'scan:since': String(T0), 'scan:last': String(T0) });
  const a = idAt(T0 + 1000);
  const refuse = { [a]: 500 };
  const f = discord({ active: [{ id: a, parent_id: '900' }], refuse });
  const r = await scan(baseEnv(kv), { fetch: f, now: () => T0 + 5 * 60000, log: () => {} });
  assert.deepEqual([r.greeted.length, r.left], [0, 1]);
  assert.equal(kv.m.get('scan:last'), String(T0 + 5 * 60000), 'the run still counts as run');
  assert.match(kv.m.get('scan:error'), new RegExp(`post ${a}`));
  const out = [];
  await daily(baseEnv(kv), { fetch: f, now: () => T0 + 6 * 60000, log: (s) => out.push(s) });
  assert.match(out.join('\n'), /scan is running but hit a problem/);
  delete refuse[a];
  const again = await scan(baseEnv(kv), { fetch: f, now: () => T0 + 10 * 60000, log: () => {} });
  assert.deepEqual(again.greeted, [a]);
  assert.equal(kv.m.get('scan:error'), '', 'a clean run clears the problem');
});

test('a locked post is never messaged', async () => {
  const kv = fakeKv({ 'scan:since': String(T0), 'scan:last': String(T0) });
  const f = discord({ active: [{ id: idAt(T0 + 1000), parent_id: '900', thread_metadata: { locked: true } }] });
  await scan(baseEnv(kv), { fetch: f, now: () => T0 + 5 * 60000, log: () => {} });
  assert.deepEqual(sends(f), []);
});

test('a post that already shows the button (its record was lost) is not messaged again', async () => {
  const kv = fakeKv({ 'scan:since': String(T0), 'scan:last': String(T0) });
  const a = idAt(T0 + 1000);
  const button = { id: 'old1', components: [{ type: 1, components: [{ type: 2, custom_id: `send:${a}` }] }] };
  const f = discord({ active: [{ id: a, parent_id: '900' }], said: { [a]: [{ id: 'x' }, button] } });
  await scan(baseEnv(kv), { fetch: f, now: () => T0 + 5 * 60000, log: () => {} });
  assert.deepEqual(sends(f), []);
  assert.deepEqual(JSON.parse(kv.m.get(`thread:${a}`)), { greeting: 'old1' });
});

test('catch-up keeps going until every archived post is handled', async () => {
  const kv = fakeKv({ 'scan:since': String(T0), 'scan:last': String(T0) });
  const archived = Array.from({ length: 9 }, (_, i) => archivedPost(T0 + 1000 * (i + 1), T0 + 2 * HOUR - 1000 * i));
  const f = discord({ archived });
  const first = await scan(baseEnv(kv), { fetch: f, now: () => T0 + 3 * HOUR, log: () => {} });
  assert.deepEqual([first.greeted.length, first.left], [8, 1]);
  assert.equal(kv.m.get('scan:caught'), undefined, 'not caught up yet');
  const second = await scan(baseEnv(kv), { fetch: f, now: () => T0 + 3 * HOUR + 5 * 60000, log: () => {} });
  assert.equal(second.greeted.length, 1);
  assert.equal(kv.m.get('scan:caught'), String(T0 + 3 * HOUR + 5 * 60000));
  await scan(baseEnv(kv), { fetch: f, now: () => T0 + 3 * HOUR + 10 * 60000, log: () => {} });
  assert.equal(f.find('GET', /archived/).length, 2, 'caught up: the next run reads active posts only');
});

test('catch-up follows the archived pages back to the last time it caught up', async () => {
  const kv = fakeKv({ 'scan:since': String(T0), 'scan:last': String(T0), 'scan:caught': String(T0) });
  const archived = Array.from({ length: 5 }, (_, i) => archivedPost(T0 + 1000 * (i + 1), T0 + 2 * HOUR - 60000 * i));
  const f = discord({ archived, pageSize: 2 });
  const r = await scan(baseEnv(kv), { fetch: f, now: () => T0 + 3 * HOUR, log: () => {} });
  assert.equal(r.greeted.length, 5);
  assert.equal(f.find('GET', /archived/).length, 3);
  assert.match(f.find('GET', /archived/)[1].url, /before=/);
});

test('posts already handled are not read from KV again', async () => {
  const kv = fakeKv({ 'scan:since': String(T0), 'scan:last': String(T0) });
  const active = Array.from({ length: 3 }, (_, i) => ({ id: idAt(T0 + 1000 * (i + 1)), parent_id: '900' }));
  const f = discord({ active });
  await scan(baseEnv(kv), { fetch: f, now: () => T0 + 5 * 60000, log: () => {} });
  assert.equal(kv.m.get('scan:through'), active[2].id);
  let reads = 0;
  const get = kv.get;
  kv.get = async (k) => { if (k.startsWith('thread:')) reads++; return get(k); };
  active.push({ id: idAt(T0 + 9000), parent_id: '900' });
  const r = await scan(baseEnv(kv), { fetch: f, now: () => T0 + 10 * 60000, log: () => {} });
  assert.deepEqual(r.greeted, [active[3].id]);
  assert.equal(reads, 2, 'only the new post is looked up (once to check, once to save)');
});

test('a post made in the same millisecond the bot started is left alone', async () => {
  const kv = fakeKv({ 'scan:since': String(T0), 'scan:last': String(T0) });
  const f = discord({ active: [{ id: idAt(T0), parent_id: '900' }] });
  await scan(baseEnv(kv), { fetch: f, now: () => T0 + 5 * 60000, log: () => {} });
  assert.deepEqual(sends(f), []);
});

test('the daily check posts the scan alert even when a forum cannot be read, and says which', async () => {
  const kv = fakeKv({ 'scan:since': String(T0), 'scan:last': String(T0) });
  const f = discord();
  const env = { ...baseEnv(kv), FORUMS: '{"900":{},"901":{}}', MOD_CHANNEL_ID: '555' };
  await daily(env, { fetch: f, now: () => T0 + 3 * HOUR, log: () => {} });
  const posted = f.find('POST', /\/channels\/555\/messages$/).map((c) => c.body.content);
  assert.equal(posted.length, 2);
  assert.match(posted[0], /scan has not run for 180 minutes/);
  assert.match(posted[1], /Could not read forum 901/);
});
