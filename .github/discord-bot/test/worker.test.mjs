import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, createVerify } from 'node:crypto';
import { handle, COMMAND_NAME } from '../src/worker.js';
import { importAppKey, appJwt } from '../src/github.js';
import { fakeFetch, FORUM } from './fake-fetch.mjs';

const keys = await crypto.subtle.generateKey({ name: 'Ed25519' }, true, ['sign', 'verify']);
const pubHex = Buffer.from(await crypto.subtle.exportKey('raw', keys.publicKey)).toString('hex');
const env = {
  DISCORD_PUBLIC_KEY: pubHex, DISCORD_BOT_TOKEN: 'bot-token',
  GITHUB_APP_ID: '1', GITHUB_APP_PRIVATE_KEY: 'unused',
  REPOS: '{"AES":"me/test-aes","AUI":"me/test-aui"}', FORUM_CHANNEL_IDS: '900',
};
const MOD = { permissions: String(1n << 34n), user: { id: '5', username: 'moddy' } };
const PLAYER = { permissions: '0', user: { id: '6', username: 'pat' } };

async function signed(obj, { tamper = false } = {}) {
  const body = JSON.stringify(obj);
  const ts = '1700000000';
  const sig = Buffer.from(await crypto.subtle.sign('Ed25519', keys.privateKey, new TextEncoder().encode(ts + body))).toString('hex');
  return new Request('https://bot.example/', {
    method: 'POST', body: tamper ? body.replace('1', '2') : body,
    headers: { 'X-Signature-Ed25519': sig, 'X-Signature-Timestamp': ts },
  });
}
const ctxFor = () => { const jobs = []; return { jobs, waitUntil: (p) => jobs.push(p) }; };

function discordRoutes(extra = []) {
  return [
    ...extra,
    ['GET', /\/channels\/700$/, () => ({ id: '700', parent_id: '900', name: '[Bug] Bags overlap after resize', applied_tags: ['t-retail', 't-bug'] })],
    ['GET', /\/channels\/900$/, () => FORUM],
    ['GET', /\/channels\/700\/messages\/800$/, () => ({ id: '800', content: 'My bags overlap\nafter resize', author: { id: '42', global_name: 'Pat' }, attachments: [{ url: 'x' }] })],
    ['PATCH', /\/channels\/700$/, () => ({})],
    ['POST', /\/channels\/700\/messages$/, () => ({ id: '1' })],
    ['PATCH', /\/webhooks\//, () => ({})],
  ];
}

test('rejects a bad signature and answers Discord pings', async () => {
  const f = fakeFetch([]);
  assert.equal((await handle(await signed({ type: 1 }, { tamper: true }), env, ctxFor(), { fetch: f })).status, 401);
  const r = await handle(await signed({ type: 1 }), env, ctxFor(), { fetch: f });
  assert.deepEqual(await r.json(), { type: 1 });
});

test('players cannot use the command', async () => {
  const r = await handle(await signed({ type: 2, member: PLAYER, channel_id: '700', data: { name: COMMAND_NAME, target_id: '800' } }), env, ctxFor(), { fetch: fakeFetch([]) });
  const j = await r.json();
  assert.equal(j.type, 4);
  assert.match(j.data.content, /Only moderators/);
});

test('only works inside the configured forum', async () => {
  const f = fakeFetch([['GET', /\/channels\/701$/, () => ({ id: '701', parent_id: '999', applied_tags: [] })]]);
  const r = await handle(await signed({ type: 2, member: MOD, channel_id: '701', data: { name: COMMAND_NAME, target_id: '800' } }), env, ctxFor(), { fetch: f });
  assert.match((await r.json()).data.content, /only works on posts/);
});

test('mod right-click opens a form pre-filled from the post', async () => {
  const f = fakeFetch(discordRoutes());
  const r = await handle(await signed({ type: 2, member: MOD, channel_id: '700', data: { name: COMMAND_NAME, target_id: '800' } }), env, ctxFor(), { fetch: f });
  const j = await r.json();
  assert.equal(j.type, 9);
  assert.equal(j.data.custom_id, 'gh:700:800');
  const val = Object.fromEntries(j.data.components.map((row) => [row.components[0].custom_id, row.components[0].value]));
  assert.deepEqual(val, { repo: 'AES', client: 'Retail', type: 'Bug', module: undefined, title: 'Bags overlap after resize' });
});

const submit = (over = {}) => ({
  type: 5, member: MOD, guild_id: '1', channel_id: '700', application_id: 'app', token: 'itok',
  data: { custom_id: 'gh:700:800', components: Object.entries({ repo: 'aes', client: 'retail', type: 'bug', module: 'Bags', title: 'Bags overlap after resize', ...over })
    .map(([custom_id, value]) => ({ type: 1, components: [{ type: 4, custom_id, value }] })) },
});

test('a bad form value creates nothing and says why', async () => {
  const f = fakeFetch([]);
  const ctx = ctxFor();
  const r = await handle(await signed(submit({ client: 'classic', repo: 'kitn' })), env, ctx, { fetch: f });
  const j = await r.json();
  assert.match(j.data.content, /Nothing was created.*Repo must be AES or AUI.*Client must be/);
  assert.equal(ctx.jobs.length, 0);
  assert.equal(f.calls.length, 0);
});

test('submitting files the issue, tags the post Triaged and tells the player', async () => {
  let created;
  const f = fakeFetch(discordRoutes([
    ['GET', /api\.github\.com\/search\/issues/, () => ({ items: [] })],
    ['POST', /api\.github\.com\/repos\/me\/test-aes\/issues$/, (b) => { created = b; return { number: 17, html_url: 'https://github.com/me/test-aes/issues/17' }; }],
  ]));
  const ctx = ctxFor();
  const r = await handle(await signed(submit()), env, ctx, { fetch: f, installationToken: async () => 'inst' });
  assert.equal((await r.json()).type, 5);
  assert.deepEqual(await Promise.all(ctx.jobs), [{ created: 17 }]);

  assert.equal(created.title, '[AES][Retail][Bags] Bags overlap after resize');
  assert.match(created.body, /> My bags overlap\n> after resize/);
  assert.match(created.body, /\*\*Pat\*\* in \[the Discord post\]\(https:\/\/discord.com\/channels\/1\/700\)/);
  assert.match(created.body, /<!-- discord-thread: 700 reporter: 42 -->/);
  assert.deepEqual(created.labels, ['from-discord', 'type: bug', 'client: retail']);

  assert.deepEqual(f.find('PATCH', /\/channels\/700$/)[0].body, { applied_tags: ['t-retail', 't-bug', 's-tri'] });
  const msg = f.find('POST', /\/channels\/700\/messages$/)[0].body;
  assert.match(msg.content, /tracked as AES #17/);
  assert.deepEqual(msg.allowed_mentions, { parse: [], users: [] });
  assert.match(f.find('PATCH', /\/webhooks\/app\/itok/)[0].body.content, /Created AES #17/);
});

test('sending the same post twice points at the first issue', async () => {
  const f = fakeFetch(discordRoutes([
    ['GET', /api\.github\.com\/search\/issues/, () => ({ items: [{ number: 17, html_url: 'u' }] })],
  ]));
  const ctx = ctxFor();
  await handle(await signed(submit()), env, ctx, { fetch: f, installationToken: async () => 'inst' });
  assert.deepEqual(await Promise.all(ctx.jobs), [{ duplicate: 17 }]);
  assert.equal(f.find('POST', /\/issues$/).length, 0);
  assert.match(f.find('PATCH', /\/webhooks\//)[0].body.content, /Already tracked: AES #17/);
});

test('a GitHub failure is reported to the mod, not swallowed', async () => {
  const f = fakeFetch(discordRoutes([
    ['GET', /search\/issues/, () => ({ items: [] })],
    ['POST', /\/issues$/, () => new Response('boom', { status: 403 })],
  ]));
  const ctx = ctxFor();
  await handle(await signed(submit()), env, ctx, { fetch: f, installationToken: async () => 'inst' });
  const [res] = await Promise.all(ctx.jobs);
  assert.match(res.error, /403/);
  assert.match(f.find('PATCH', /\/webhooks\//)[0].body.content, /Could not create the issue/);
});

test('GitHub App key in the PKCS#1 format GitHub hands out signs a valid JWT', async () => {
  const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
  const pem = privateKey.export({ type: 'pkcs1', format: 'pem' });
  assert.match(pem, /BEGIN RSA PRIVATE KEY/);
  const jwt = await appJwt('123', await importAppKey(pem), 1700000000);
  const [h, p, s] = jwt.split('.');
  const v = createVerify('RSA-SHA256'); v.update(`${h}.${p}`);
  assert.ok(v.verify(publicKey, Buffer.from(s, 'base64url')));
  assert.deepEqual(JSON.parse(Buffer.from(p, 'base64url')), { iat: 1699999940, exp: 1700000540, iss: '123' });
});
