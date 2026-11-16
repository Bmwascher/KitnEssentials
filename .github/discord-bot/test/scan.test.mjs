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

function discord({ active = [], archived = [] } = {}) {
  let n = 0;
  return fakeFetch([
    ['GET', /\/guilds\/1\/threads\/active$/, () => ({ threads: active })],
    ['GET', /\/channels\/900\/threads\/archived\/public/, () => ({ threads: archived })],
    ['GET', /\/channels\/900$/, () => ({ ...FORUM, available_tags: [...FORUM.available_tags, { id: 's-ans', name: 'Answered' }] })],
    ['POST', /\/channels\/\d+\/messages$/, () => ({ id: `m${++n}` })],
  ]);
}

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
  const archived = { id: idAt(T0 + 1000), parent_id: '900', thread_metadata: { archived: true } };
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
