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
  REPOS: '{"ONE":"me/test-one","TWO":"me/test-two"}', FORUM_CHANNEL_IDS: '900',
};
const MOD = { permissions: String(1n << 34n), user: { id: '5', username: 'moddy' } };
const PLAYER = { permissions: '0', user: { id: '6', username: 'pat' } };

async function signed(obj, { tamper = false, ts = String(Math.floor(Date.now() / 1000)) } = {}) {
  const body = JSON.stringify(obj);
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

// GitHub side of a send: the from-discord issue list and the per-post lock label.
function githubRoutes(existing = [], extra = []) {
  return [
    ...extra,
    ['GET', /api\.github\.com\/repos\/me\/test-one\/issues\?state=all.*labels=from-discord/, () => existing],
    ['POST', /api\.github\.com\/repos\/me\/test-one\/labels$/, () => new Response('{}', { status: 201 })],
    ['DELETE', /api\.github\.com\/repos\/me\/test-one\/labels\/discord-lock-700$/, () => null],
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
  assert.deepEqual(val, { repo: 'ONE', client: 'Retail', type: 'Bug', module: undefined, title: 'Bags overlap after resize' });
});

const submit = (over = {}) => ({
  type: 5, member: MOD, guild_id: '1', channel_id: '700', application_id: 'app', token: 'itok',
  data: { custom_id: 'gh:700:800', components: Object.entries({ repo: 'one', client: 'retail', type: 'bug', module: 'Bags', title: 'Bags overlap after resize', ...over })
    .map(([custom_id, value]) => ({ type: 1, components: [{ type: 4, custom_id, value }] })) },
});

test('a bad form value creates nothing and says why', async () => {
  const f = fakeFetch([]);
  const ctx = ctxFor();
  const r = await handle(await signed(submit({ client: 'classic', repo: 'kitn' })), env, ctx, { fetch: f });
  const j = await r.json();
  assert.match(j.data.content, /Nothing was created.*Repo must be ONE or TWO.*Client must be/);
  assert.equal(ctx.jobs.length, 0);
  assert.equal(f.calls.length, 0);
});

test('submitting files the issue, tags the post Triaged and tells the player', async () => {
  let created;
  const f = fakeFetch(discordRoutes(githubRoutes([], [
    ['POST', /api\.github\.com\/repos\/me\/test-one\/issues$/, (b) => { created = b; return { number: 17, html_url: 'https://github.com/me/test-one/issues/17' }; }],
  ])));
  const ctx = ctxFor();
  const r = await handle(await signed(submit()), env, ctx, { fetch: f, installationToken: async () => 'inst' });
  assert.equal((await r.json()).type, 5);
  assert.deepEqual(await Promise.all(ctx.jobs), [{ created: 17, notes: [] }]);
  assert.equal(f.find('DELETE', /labels\/discord-lock-700$/).length, 1, 'the lock is released');

  assert.equal(created.title, '[ONE][Retail][Bags] Bags overlap after resize');
  assert.match(created.body, /> My bags overlap\n> after resize/);
  assert.match(created.body, /\*\*Pat\*\* in \[the Discord post\]\(https:\/\/discord.com\/channels\/1\/700\)/);
  assert.match(created.body, /<!-- discord-thread: 700 reporter: 42 -->/);
  assert.deepEqual(created.labels, ['from-discord', 'type: bug', 'client: retail']);

  assert.deepEqual(f.find('PATCH', /\/channels\/700$/)[0].body, { applied_tags: ['t-retail', 't-bug', 's-tri'] });
  const msg = f.find('POST', /\/channels\/700\/messages$/)[0].body;
  assert.match(msg.content, /tracked as ONE #17/);
  assert.deepEqual(msg.allowed_mentions, { parse: [], users: [] });
  assert.match(f.find('PATCH', /\/webhooks\/app\/itok/)[0].body.content, /Created ONE #17/);
});

test('sending the same post twice points at the first issue', async () => {
  const f = fakeFetch(discordRoutes(githubRoutes([
    { number: 9, body: 'another post <!-- discord-thread: 701 reporter: 1 -->' },
    { number: 17, html_url: 'u', body: '<!-- discord-thread: 700 reporter: 42 -->' },
  ])));
  const ctx = ctxFor();
  await handle(await signed(submit()), env, ctx, { fetch: f, installationToken: async () => 'inst' });
  assert.deepEqual(await Promise.all(ctx.jobs), [{ duplicate: 17 }]);
  assert.equal(f.find('POST', /\/issues$/).length, 0);
  assert.match(f.find('PATCH', /\/webhooks\//)[0].body.content, /Already tracked: ONE #17/);
});

test('a GitHub failure is reported to the mod, not swallowed', async () => {
  const f = fakeFetch(discordRoutes(githubRoutes([], [
    ['POST', /\/issues$/, () => new Response('boom', { status: 403 })],
  ])));
  const ctx = ctxFor();
  await handle(await signed(submit()), env, ctx, { fetch: f, installationToken: async () => 'inst' });
  const [res] = await Promise.all(ctx.jobs);
  assert.match(res.error, /403/);
  assert.match(f.find('PATCH', /\/webhooks\//)[0].body.content, /Nothing was created: .*403/);
  assert.equal(f.find('DELETE', /labels\/discord-lock-700$/).length, 1, 'the lock is released on failure too');
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

// ---- gate-fix cases ----

test('with no forum configured the command works nowhere', async () => {
  const f = fakeFetch(discordRoutes());
  const r = await handle(await signed({ type: 2, member: MOD, channel_id: '700', data: { name: COMMAND_NAME, target_id: '800' } }),
    { ...env, FORUM_CHANNEL_IDS: '' }, ctxFor(), { fetch: f });
  const j = await r.json();
  assert.equal(j.type, 4);
  assert.match(j.data.content, /not set up/);
});

test('an hour-old signed request is refused', async () => {
  const old = String(Math.floor(Date.now() / 1000) - 3600);
  assert.equal((await handle(await signed({ type: 1 }, { ts: old }), env, ctxFor(), { fetch: fakeFetch([]) })).status, 401);
});

test('a failed duplicate lookup stops the send instead of filing blind', async () => {
  const f = fakeFetch(discordRoutes(githubRoutes([], [
    ['GET', /issues\?state=all.*labels=from-discord/, () => new Response('rate limited', { status: 403 })],
  ])));
  const ctx = ctxFor();
  await handle(await signed(submit()), env, ctx, { fetch: f, installationToken: async () => 'inst' });
  const [res] = await Promise.all(ctx.jobs);
  assert.match(res.error, /403/);
  assert.equal(f.find('POST', /\/issues$/).length, 0);
  assert.match(f.find('PATCH', /\/webhooks\//)[0].body.content, /Nothing was created/);
});

// A small GitHub with real state: labels are created once, issues are listed.
function sharedGitHub() {
  const labels = new Set();
  const issues = [];
  const tick = () => new Promise((r) => setTimeout(r, 5));
  return [
    ['GET', /issues\?state=all.*labels=from-discord/, async () => { await tick(); return [...issues]; }],
    ['POST', /test-one\/labels$/, async (b) => {
      await tick();
      if (labels.has(b.name)) return new Response('{"message":"Validation Failed","errors":[{"resource":"Label","code":"already_exists","field":"name"}]}', { status: 422 });
      labels.add(b.name);
      return new Response('{}', { status: 201 });
    }],
    ['DELETE', /test-one\/labels\/(.+)$/, async (_, url) => { await tick(); labels.delete(decodeURIComponent(url.split('/').pop())); return null; }],
    ['POST', /test-one\/issues$/, async (b) => {
      await tick();
      const n = issues.length + 17;
      issues.push({ number: n, html_url: `u/${n}`, body: b.body });
      return { number: n, html_url: `u/${n}` };
    }],
  ];
}

test('two sends of one post at the same moment file one issue', async () => {
  const f = fakeFetch(discordRoutes(sharedGitHub()));
  const ctx = ctxFor();
  await Promise.all([
    handle(await signed(submit()), env, ctx, { fetch: f, installationToken: async () => 'inst' }),
    handle(await signed(submit()), env, ctx, { fetch: f, installationToken: async () => 'inst' }),
  ]);
  const results = await Promise.all(ctx.jobs);
  assert.equal(f.find('POST', /\/issues$/).length, 1, 'one issue');
  assert.equal(results.filter((r) => r.created).length, 1);
  assert.ok(results.some((r) => r.busy || r.duplicate), JSON.stringify(results));
  assert.equal(f.find('DELETE', /labels\/discord-lock-700$/).length, 1, 'only the holder releases the lock');
});

test('a label refusal that is not "already exists" is an error, not a busy lock', async () => {
  const f = fakeFetch(discordRoutes(githubRoutes([], [
    ['POST', /\/labels$/, () => new Response('{"message":"You have exceeded a secondary rate limit"}', { status: 422 })],
  ])));
  const ctx = ctxFor();
  await handle(await signed(submit()), env, ctx, { fetch: f, installationToken: async () => 'inst' });
  const [res] = await Promise.all(ctx.jobs);
  assert.match(res.error, /422/);
  assert.doesNotMatch(f.find('PATCH', /\/webhooks\//)[0].body.content, /another send/);
});

test('a form submitted after its forum left the list files nothing', async () => {
  const f = fakeFetch(discordRoutes(githubRoutes()));
  const ctx = ctxFor();
  await handle(await signed(submit()), { ...env, FORUM_CHANNEL_IDS: '901' }, ctx, { fetch: f, installationToken: async () => 'inst' });
  assert.deepEqual(await Promise.all(ctx.jobs), [{ refused: 'forum' }]);
  assert.equal(f.find('POST', /\/issues$/).length, 0);
  const r = await handle(await signed(submit()), { ...env, FORUM_CHANNEL_IDS: '' }, ctxFor(), { fetch: f });
  assert.match((await r.json()).data.content, /not set up/);
});

test('a send that finished while this one waited for the lock is not filed again', async () => {
  let looks = 0;
  const f = fakeFetch(discordRoutes(githubRoutes([], [
    ['GET', /issues\?state=all.*labels=from-discord/, () => (++looks === 1 ? [] : [{ number: 17, html_url: 'u', body: '<!-- discord-thread: 700 reporter: 42 -->' }])],
  ])));
  const ctx = ctxFor();
  await handle(await signed(submit()), env, ctx, { fetch: f, installationToken: async () => 'inst' });
  assert.deepEqual(await Promise.all(ctx.jobs), [{ duplicate: 17 }]);
  assert.equal(f.find('POST', /\/issues$/).length, 0);
  assert.equal(f.find('DELETE', /labels\/discord-lock-700$/).length, 1);
});

test('once the issue exists, a failed tag or post note is reported, never as a failed create', async () => {
  const f = fakeFetch(discordRoutes(githubRoutes([], [
    ['POST', /\/issues$/, () => ({ number: 17, html_url: 'https://github.com/me/test-one/issues/17' })],
    ['PATCH', /\/channels\/700$/, () => new Response('{"message":"Missing Permissions"}', { status: 403 })],
    ['POST', /\/channels\/700\/messages$/, () => new Response('{"message":"Thread is locked"}', { status: 403 })],
  ])));
  const ctx = ctxFor();
  await handle(await signed(submit()), env, ctx, { fetch: f, installationToken: async () => 'inst' });
  const [res] = await Promise.all(ctx.jobs);
  assert.equal(res.created, 17);
  const told = f.find('PATCH', /\/webhooks\//)[0].body.content;
  assert.match(told, /^Created ONE #17: .*tag not set: .*403.*note in the post not sent: .*403/);
});

test('a stalled call ends the send with a report to the mod', async () => {
  const base = fakeFetch(discordRoutes(githubRoutes()));
  // The issue list never answers; only the call's own time limit ends it.
  const stall = (url, init = {}) => (/issues\?state=all/.test(url)
    ? new Promise((_, reject) => init.signal.addEventListener('abort', () => reject(init.signal.reason)))
    : base(url, init));
  const ctx = ctxFor();
  const t0 = Date.now();
  await handle(await signed(submit()), env, ctx, { fetch: stall, installationToken: async () => 'inst', log: () => {}, callMs: 50 });
  const [res] = await Promise.all(ctx.jobs);
  assert.ok(res.error, 'reported as an error');
  assert.ok(Date.now() - t0 < 2000, 'within the per-call limit');
  assert.match(base.find('PATCH', /\/webhooks\//)[0].body.content, /Nothing was created/);
});

test('the lock is released even after the filing ran out of time', async () => {
  const base = fakeFetch(discordRoutes(githubRoutes()));
  // Reading the post outlasts the whole budget, so no later call may start.
  const slow = async (url, init = {}) => {
    if (/\/messages\/800$/.test(url)) await new Promise((r) => setTimeout(r, 120));
    return base(url, init);
  };
  const ctx = ctxFor();
  await handle(await signed(submit()), env, ctx, { fetch: slow, installationToken: async () => 'inst', log: () => {}, budgetMs: 60 });
  const [res] = await Promise.all(ctx.jobs);
  assert.match(res.error, /out of time/);
  assert.equal(base.find('POST', /\/issues$/).length, 0);
  assert.equal(base.find('DELETE', /labels\/discord-lock-700$/).length, 1, 'released despite the spent budget');
});

test('a create that got no answer is reported as maybe created, not as nothing', async () => {
  const base = fakeFetch(discordRoutes(githubRoutes()));
  const hang = (url, init = {}) => (init.method === 'POST' && /\/issues$/.test(url)
    ? new Promise((_, reject) => init.signal.addEventListener('abort', () => reject(init.signal.reason)))
    : base(url, init));
  const ctx = ctxFor();
  await handle(await signed(submit()), env, ctx, { fetch: hang, installationToken: async () => 'inst', log: () => {}, callMs: 50 });
  await Promise.all(ctx.jobs);
  const told = base.find('PATCH', /\/webhooks\//)[0].body.content;
  assert.match(told, /may have been created/);
  assert.doesNotMatch(told, /Nothing was created/);
  assert.equal(base.find('DELETE', /labels\/discord-lock-700$/).length, 0, 'the lock stays until the outcome is known');
});

test('a create that answered late is found again and reported as created', async () => {
  let looks = 0;
  const base = fakeFetch(discordRoutes(githubRoutes([], [
    ['GET', /issues\?state=all.*labels=from-discord/, () => (++looks <= 2 ? [] : [{ number: 17, html_url: 'u/17', body: '<!-- discord-thread: 700 reporter: 42 -->' }])],
  ])));
  const hang = (url, init = {}) => (init.method === 'POST' && /\/issues$/.test(url)
    ? new Promise((_, reject) => init.signal.addEventListener('abort', () => reject(init.signal.reason)))
    : base(url, init));
  const ctx = ctxFor();
  await handle(await signed(submit()), env, ctx, { fetch: hang, installationToken: async () => 'inst', log: () => {}, callMs: 50 });
  const [res] = await Promise.all(ctx.jobs);
  assert.equal(res.created, 17);
  assert.match(base.find('PATCH', /\/webhooks\//)[0].body.content, /^Created ONE #17/);
  assert.equal(base.find('DELETE', /labels\/discord-lock-700$/).length, 1);
});
