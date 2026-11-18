import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, createVerify } from 'node:crypto';
import { handle, COMMAND_NAME } from '../src/worker.js';
import { importAppKey, appJwt } from '../src/github.js';
import { MESSAGES } from '../src/core.js';
import { fakeFetch, fakeKv, FORUM, stall } from './fake-fetch.mjs';

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
  assert.match(created.body, /^\| Reporter \| \[Pat\]\(https:\/\/discord\.com\/users\/42\) \|\n/);
  assert.match(created.body, /\n\| Filed by \| \[moddy\]\(https:\/\/discord\.com\/users\/5\) \(`moddy`\) \|\n/);
  assert.match(created.body, /\n\| Discord post \| \[Open the post\]\(https:\/\/discord\.com\/channels\/1\/700\) \|\n/);
  assert.match(created.body, /\n<!-- discord-message: 800 -->\n<!-- discord-thread: 700 reporter: 42 -->$/);
  assert.deepEqual(created.labels, ['from-discord', 'type: bug', 'client: retail']);

  assert.deepEqual(f.find('PATCH', /\/channels\/700$/)[0].body, { applied_tags: ['t-retail', 't-bug', 's-tri'] });
  const msg = f.find('POST', /\/channels\/700\/messages$/)[0].body;
  assert.match(msg.content, /tracked as ONE #17/);
  assert.deepEqual(msg.message_reference, { message_id: '800', fail_if_not_exists: false });
  assert.deepEqual(msg.allowed_mentions, { parse: [], users: [], replied_user: true });
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

test('the issue names the reporter and the moderator by server name, profile link and username', async () => {
  const KIRA = { id: '42', username: 'kira_99', global_name: 'Kira Display' };
  const NICKED = { ...MOD, nick: 'Bite', user: { id: '5', username: 'moddy', global_name: 'Mod Display' } };
  for (const [why, message, member, reporterRow] of [
    ['the member read gives the nickname', { author: KIRA }, () => ({ nick: 'Kira Nick', user: KIRA }), '| Reporter | [Kira Nick](https://discord.com/users/42) (`kira_99`) |'],
    ['the member read is refused: the display name', { author: KIRA }, () => new Response('{"message":"Unknown Member"}', { status: 404 }), '| Reporter | [Kira Display](https://discord.com/users/42) (`kira_99`) |'],
    ['a webhook author: the name alone, and no member read', { author: { id: '99', username: 'Hook' }, webhook_id: '99' }, () => ({ nick: 'never' }), '| Reporter | Hook |'],
  ]) {
    let created;
    const f = fakeFetch(discordRoutes(githubRoutes([], [
      ['GET', /\/channels\/700\/messages\/800$/, () => ({ id: '800', content: 'hi', attachments: [], ...message })],
      ['GET', /\/guilds\/1\/members\/(42|99)$/, member],
      ['POST', /api\.github\.com\/repos\/me\/test-one\/issues$/, (b) => { created = b; return { number: 17, html_url: 'u' }; }],
    ])));
    const ctx = ctxFor();
    await handle(await signed({ ...submit(), member: NICKED }), env, ctx, { fetch: f, installationToken: async () => 'inst' });
    const [res] = await Promise.all(ctx.jobs);
    assert.equal(res.created, 17, why);
    const lines = created.body.split('\n');
    assert.equal(lines[0], reporterRow, why);
    assert.equal(lines[2], '| Filed by | [Bite](https://discord.com/users/5) (`moddy`) |', why);
    assert.equal(f.find('GET', /\/guilds\/1\/members\/99$/).length, 0, why);
  }
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
  // The look comes after the lock, so it sees the issue the other send left.
  const f = fakeFetch(discordRoutes(githubRoutes([], [
    ['GET', /issues\?state=all.*labels=from-discord/, () => [{ number: 17, html_url: 'u', body: '<!-- discord-thread: 700 reporter: 42 -->' }]],
  ])));
  const ctx = ctxFor();
  await handle(await signed(submit()), env, ctx, { fetch: f, installationToken: async () => 'inst' });
  assert.deepEqual(await Promise.all(ctx.jobs), [{ duplicate: 17 }]);
  assert.equal(f.find('POST', /\/issues$/).length, 0);
  const order = f.calls.filter((c) => /labels(\/discord-lock-700)?$|issues\?state=all/.test(c.url)).map((c) => c.method);
  assert.deepEqual(order, ['POST', 'GET', 'DELETE'], 'lock, one look, release');
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
  let aborted = 0;
  const hangList = (url, init = {}) => (/issues\?state=all/.test(url)
    ? stall(init, () => { aborted++; })
    : base(url, init));
  const ctx = ctxFor();
  const t0 = Date.now();
  await handle(await signed(submit()), env, ctx, { fetch: hangList, installationToken: async () => 'inst', log: () => {}, callMs: 50 });
  const [res] = await Promise.all(ctx.jobs);
  assert.equal(aborted, 1, 'the stalled list call was ended by its time limit');
  assert.match(res.error, /aborted|timeout/i, 'reported as the time-limit error');
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
    ? stall(init)
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
    ['GET', /issues\?state=all.*labels=from-discord/, () => (++looks <= 1 ? [] : [{ number: 17, html_url: 'u/17', body: '<!-- discord-thread: 700 reporter: 42 -->' }])],
  ])));
  const hang = (url, init = {}) => (init.method === 'POST' && /\/issues$/.test(url)
    ? stall(init)
    : base(url, init));
  const ctx = ctxFor();
  await handle(await signed(submit()), env, ctx, { fetch: hang, installationToken: async () => 'inst', log: () => {}, callMs: 50 });
  const [res] = await Promise.all(ctx.jobs);
  assert.equal(res.created, 17);
  assert.match(base.find('PATCH', /\/webhooks\//)[0].body.content, /^Created ONE #17/);
  assert.equal(base.find('DELETE', /labels\/discord-lock-700$/).length, 1);
});

test('a server error on create is an unknown outcome too', async () => {
  const f = fakeFetch(discordRoutes(githubRoutes([], [
    ['POST', /\/issues$/, () => new Response('bad gateway', { status: 502 })],
  ])));
  const ctx = ctxFor();
  await handle(await signed(submit()), env, ctx, { fetch: f, installationToken: async () => 'inst', log: () => {} });
  const [res] = await Promise.all(ctx.jobs);
  assert.equal(res.uncertain, true);
  assert.match(f.find('PATCH', /\/webhooks\//)[0].body.content, /may have been created/);
  assert.equal(f.find('DELETE', /labels\/discord-lock-700$/).length, 0, 'the lock stays');
});

test('a lock claim with no answer is reported with the label to clear', async () => {
  const base = fakeFetch(discordRoutes(githubRoutes()));
  const hang = (url, init = {}) => (init.method === 'POST' && /\/labels$/.test(url)
    ? stall(init)
    : base(url, init));
  const ctx = ctxFor();
  await handle(await signed(submit()), env, ctx, { fetch: hang, installationToken: async () => 'inst', log: () => {}, callMs: 50 });
  const [res] = await Promise.all(ctx.jobs);
  assert.equal(res.uncertain, 'lock');
  assert.equal(base.find('POST', /\/issues$/).length, 0);
  assert.match(base.find('PATCH', /\/webhooks\//)[0].body.content, /discord-lock-700/);
});

// Moves the clock forward from the moment `at` is called, to stand in for a
// filing whose calls used most of Workers' 30 s.
function shiftClock() {
  const real = Date.now;
  let by = 0;
  Date.now = () => real() + by;
  return { at: (ms) => { by = ms; }, restore: () => { Date.now = real; } };
}

test('each closing phase has its own end: a late re-check is skipped but the report still goes', async () => {
  const clock = shiftClock();
  try {
    const base = fakeFetch(discordRoutes(githubRoutes()));
    const hang = (url, init = {}) => (init.method === 'POST' && /\/issues$/.test(url)
      ? stall(init, () => clock.at(21000))
      : base(url, init));
    const ctx = ctxFor();
    await handle(await signed(submit()), env, ctx, { fetch: hang, installationToken: async () => 'inst', log: () => {}, callMs: 50 });
    const [res] = await Promise.all(ctx.jobs);
    assert.equal(res.uncertain, true);
    const looks = base.find('GET', /issues\?state=all.*labels=from-discord/).length;
    assert.equal(looks, 1, 'no re-check after 20 s');
    assert.match(base.find('PATCH', /\/webhooks\//)[0].body.content, /may have been created/);
  } finally { clock.restore(); }
});

test('each closing phase has its own end: past the report, the lock is still released', async () => {
  const clock = shiftClock();
  try {
    const base = fakeFetch(discordRoutes(githubRoutes()));
    const hang = (url, init = {}) => (/\/messages\/800$/.test(url)
      ? stall(init, () => clock.at(26000))
      : base(url, init));
    const ctx = ctxFor();
    await handle(await signed(submit()), env, ctx, { fetch: hang, installationToken: async () => 'inst', log: () => {}, callMs: 50 });
    await Promise.all(ctx.jobs);
    assert.equal(base.find('PATCH', /\/webhooks\//).length, 0, 'no report after 25 s');
    assert.equal(base.find('DELETE', /labels\/discord-lock-700$/).length, 1, 'released before 29 s');
  } finally { clock.restore(); }
});

test('a create that succeeded with a cut-off answer is not reported as nothing created', async () => {
  const f = fakeFetch(discordRoutes(githubRoutes([], [
    ['POST', /\/issues$/, () => new Response('{"number": 1', { status: 201 })],
  ])));
  const ctx = ctxFor();
  await handle(await signed(submit()), env, ctx, { fetch: f, installationToken: async () => 'inst', log: () => {} });
  const [res] = await Promise.all(ctx.jobs);
  assert.equal(res.uncertain, true);
  assert.doesNotMatch(f.find('PATCH', /\/webhooks\//)[0].body.content, /Nothing was created/);
  assert.equal(f.find('DELETE', /labels\/discord-lock-700$/).length, 0, 'the lock stays');
});

test('a lost connection on create (a plain Error on Workers) keeps the lock; a 4xx refusal does not', async () => {
  const lost = fakeFetch(discordRoutes(githubRoutes([], [
    ['POST', /\/issues$/, () => { throw new Error('Network connection lost.'); }],
  ])));
  let ctx = ctxFor();
  await handle(await signed(submit()), env, ctx, { fetch: lost, installationToken: async () => 'inst', log: () => {} });
  let [res] = await Promise.all(ctx.jobs);
  assert.equal(res.uncertain, true);
  assert.match(lost.find('PATCH', /\/webhooks\//)[0].body.content, /may have been created/);
  assert.equal(lost.find('DELETE', /labels\/discord-lock-700$/).length, 0);

  const refused = fakeFetch(discordRoutes(githubRoutes([], [
    ['POST', /\/issues$/, () => new Response('{"message":"Validation Failed"}', { status: 422 })],
  ])));
  ctx = ctxFor();
  await handle(await signed(submit()), env, ctx, { fetch: refused, installationToken: async () => 'inst', log: () => {} });
  [res] = await Promise.all(ctx.jobs);
  assert.equal(res.uncertain, undefined);
  assert.match(refused.find('PATCH', /\/webhooks\//)[0].body.content, /^Nothing was created/);
  assert.equal(refused.find('DELETE', /labels\/discord-lock-700$/).length, 1);
});

// ---- The thread button (P3) ---------------------------------------------------

const P3 = { ...env, FORUM_CHANNEL_IDS: '', FORUMS: '{"900":{"client":"Forever","type":"Feature"}}', APPROVED_ROLE_IDS: '77' };
const HELPER = { permissions: '0', roles: ['77'], user: { id: '8', username: 'helper' } };
const press = (member) => ({ type: 3, member, channel_id: '700', message: { id: '950' }, data: { custom_id: 'send:700', component_type: 2 } });
// A press checks every configured repo for the post before the form opens:
// here neither holds it.
const searched = (extra = []) => fakeFetch(discordRoutes([
  ...extra,
  ['GET', /api\.github\.com\/repos\/me\/test-(one|two)\/issues\?state=all.*labels=from-discord/, () => []],
]));
const INST = { installationToken: async () => 'inst' };

test('an approved role presses the button and gets the form, pre-filled from the forum', async () => {
  const f = searched();
  const j = await (await handle(await signed(press(HELPER)), P3, ctxFor(), { fetch: f, ...INST })).json();
  assert.equal(j.type, 9);
  assert.equal(j.data.custom_id, 'gh:700:700:950', 'thread, its first message, the button message');
  const val = Object.fromEntries(j.data.components.map((row) => [row.components[0].custom_id, row.components[0].value]));
  assert.deepEqual([val.client, val.type], ['Forever', 'Feature'], 'the forum map wins over the post tags');
});

test('the button refuses anyone without an approved role, and with no roles set it says so', async () => {
  let j = await (await handle(await signed(press(PLAYER)), P3, ctxFor(), { fetch: fakeFetch(discordRoutes()) })).json();
  assert.equal(j.type, 4);
  assert.match(j.data.content, /Only moderators and approved roles/);
  j = await (await handle(await signed(press(HELPER)), { ...P3, APPROVED_ROLE_IDS: '' }, ctxFor(), { fetch: fakeFetch(discordRoutes()) })).json();
  assert.match(j.data.content, /APPROVED_ROLE_IDS is empty.*right-click/);
});

test('a moderator can still press the button with no roles set', async () => {
  const j = await (await handle(await signed(press(MOD)), { ...P3, APPROVED_ROLE_IDS: '' }, ctxFor(), { fetch: searched(), ...INST })).json();
  assert.equal(j.type, 9);
});

const buttonSubmit = (member = HELPER) => ({ ...submit(), member, data: { ...submit().data, custom_id: 'gh:700:800:950' } });

// ---- The queue card, the press check and the tracked reply ------------------------

const QUEUE = { ...P3, QUEUE_CHANNEL_ID: '556' };
// A press on the post's card in the queue channel, outside the post.
const CARD = { id: '96', content: '**New post in <#900>:** Bags\nby Kira (`kira_99`) · Bug · Retail' };
const cardPress = (member) => ({ ...press(member), guild_id: '1', channel_id: '556', message: CARD });
const STARTER = ['GET', /\/channels\/700\/messages\/700$/, () => ({ id: '700', content: 'first', author: { id: '42', username: 'op' }, attachments: [] })];
const WITH_BUTTON = { id: '950', content: 'old', components: [{ type: 1, components: [{ type: 2, custom_id: 'send:700' }] }] };
const RECEIPT = { id: '950', content: 'Thanks! This is now tracked as ONE #9.', components: [] };
const refusal = () => new Response('{"message":"Missing Permissions"}', { status: 403 });
const at = (f, method, re) => f.calls.findIndex((c) => c.method === method && re.test(c.url));

test('a card press with no filing opens the form with the card id fourth; an old in-post button carries its greeting id', async () => {
  for (const [why, req, id] of [
    ['a queue card', cardPress(HELPER), 'gh:700:700:0:96'],
    ['an old greeting in the post', press(HELPER), 'gh:700:700:950'],
  ]) {
    const j = await (await handle(await signed(req), QUEUE, ctxFor(), { fetch: searched(), ...INST })).json();
    assert.equal(j.data.custom_id, id, why);
  }
  const j = await (await handle(await signed(cardPress(PLAYER)), QUEUE, ctxFor(), { fetch: searched(), ...INST })).json();
  assert.match(j.data.content, /Only moderators and approved roles/);
});

test('a card press on a post that cannot be read says why, never that the forum is wrong', async () => {
  for (const [why, answer, want] of [
    ['the post was deleted', () => new Response('{"message":"Unknown Channel"}', { status: 404 }), /^This post no longer exists\.$/],
    ['a passing failure', () => new Response('{}', { status: 500 }), /^Could not read the post just now\. Press the button again\.$/],
  ]) {
    const f = searched([['GET', /\/channels\/700$/, answer]]);
    const j = await (await handle(await signed(cardPress(HELPER)), QUEUE, ctxFor(), { fetch: f, ...INST })).json();
    assert.match(j.data.content, want, why);
  }
});

test('a press on a filed post answers Already tracked, opens no form, and the pressed message stops offering the button', async () => {
  const issue = (over = {}) => () => ({ number: 3, html_url: 'https://github.com/me/test-one/issues/3', ...over });
  const status = (s) => () => new Response('{"message":"x"}', { status: s });
  const record = { 'issue:700': JSON.stringify({ repo: 'me/test-one', number: 3, key: 'ONE', by: 'Bite' }) };
  const struck = '~~**New post in <#900>:** Bags~~';
  const marked = [{ number: 9, html_url: 'https://github.com/me/test-two/issues/9', repository_url: 'https://api.github.com/repos/me/test-two', body: '<!-- discord-thread: 700 reporter: 42 -->' }];
  const inst = async () => 'inst';
  // `one` and `two` answer the configured repos' issue lists, searched when no
  // record names a live issue.
  for (const [why, entries, read, req, want, edit, two = [], token = inst, one = []] of [
    ['no record and no marker anywhere: the form opens', {}, issue(), cardPress(HELPER), null, null],
    ['no record, but a configured repo holds the post\'s marker', {}, issue(), cardPress(HELPER), /^Already tracked as TWO #9: https:\/\/github\.com\/me\/test-two\/issues\/9$/,
      ['556', '96', { content: `${struck}\n**Filed as TWO #9**` }], marked],
    ['a live issue', record, issue(), cardPress(HELPER), /^Already tracked as ONE #3: https:\/\/github\.com\/me\/test-one\/issues\/3$/,
      ['556', '96', { content: `${struck}\n**Filed as ONE #3** by Bite` }]],
    ['a transferred issue: named where it is now', record,
      issue({ number: 31, html_url: 'https://github.com/me/test-three/issues/31', repository_url: 'https://api.github.com/repos/me/test-three' }), cardPress(HELPER),
      /^Already tracked as me\/test-three #31: https:\/\/github\.com\/me\/test-three\/issues\/31$/, ['556', '96', { content: `${struck}\n**Filed as me/test-three #31** by Bite` }]],
    ['an older record: no filer named', { 'thread:700': JSON.stringify({ greeting: '951', issue: { repo: 'me/test-one', number: 3 } }) }, issue(), cardPress(HELPER),
      /^Already tracked as ONE #3: /, ['556', '96', { content: `${struck}\n**Filed as ONE #3**` }]],
    // A 404 is also what an issue the app can no longer see answers.
    ['the saved issue answers 404: refused, naming it', record, status(404), cardPress(HELPER),
      /^Could not check ONE #3 in me\/test-one \(404\): it may be gone, or the app may have lost access there\. Nothing was opened\. If it is gone, a bot admin can clear this post's filing record \(the KV key issue:700, or the "issue" field of thread:700 for a post filed before this version\), and the post can then be sent again\.$/, null],
    ['the saved issue was deleted (410) and no marker is found: the form opens', record, status(410), cardPress(HELPER), null, null],
    // A match found by the search after the saved issue was deleted is another filing: the record's filer is not its filer.
    ['the saved issue was deleted (410) and another in its repo holds the marker: no filer named', record, status(410), cardPress(HELPER),
      /^Already tracked as ONE #5: /, ['556', '96', { content: `${struck}\n**Filed as ONE #5**` }], [], inst,
      [{ number: 5, html_url: 'https://github.com/me/test-one/issues/5', repository_url: 'https://api.github.com/repos/me/test-one', body: '<!-- discord-thread: 700 reporter: 42 -->' }]],
    ['GitHub fails: press again', record, status(500), cardPress(HELPER), /^Could not check whether this post is already on GitHub\. Press the button again\.$/, null],
    // A failed token says nothing about the issue.
    ['the token request answers 410: press again', record, issue(), cardPress(HELPER), /^Could not check whether this post is already on GitHub\./, null, [],
      async () => { throw new Error('GitHub GET /repos/me/test-one/installation -> 410 {}'); }],
    ['a configured repo cannot be searched: press again', {}, issue(), cardPress(HELPER), /^Could not check whether this post is already on GitHub\./, null, status(500)],
    ['a damaged record', { 'issue:700': '{"repo"' }, issue(), cardPress(HELPER), /^This post's saved record is damaged \(issue:700\)\. Nothing was opened\. A bot admin can delete that KV key; then press again\.$/, null],
    ['an empty record', { 'issue:700': '' }, issue(), cardPress(HELPER), /^This post's saved record is damaged \(issue:700\)/, null],
    ['an old in-post button', record, issue(), press(HELPER), /^Already tracked as ONE #3: /, ['700', '950', { components: [] }]],
  ]) {
    const f = fakeFetch(discordRoutes([
      ['GET', /api\.github\.com\/repos\/me\/test-one\/issues\/3$/, read],
      ['GET', /api\.github\.com\/repos\/me\/test-one\/issues\?state=all.*labels=from-discord/, () => one],
      ['GET', /api\.github\.com\/repos\/me\/test-two\/issues\?state=all.*labels=from-discord/, typeof two === 'function' ? two : () => two],
      ['PATCH', /\/channels\/(556|700)\/messages\/(96|950)$/, () => ({})],
    ]));
    const ctx = ctxFor();
    const j = await (await handle(await signed(req), { ...QUEUE, STATE: fakeKv(entries) }, ctx, { fetch: f, installationToken: token, log: () => {} })).json();
    await Promise.all(ctx.jobs);
    if (want) {
      assert.deepEqual([j.type, j.data.flags], [4, 64], `${why}: a private reply`);
      assert.match(j.data.content, want, why);
    } else assert.equal(j.type, 9, `${why}: the form`);
    const edits = f.find('PATCH', /\/messages\/(96|950)$/);
    assert.equal(edits.length, edit ? 1 : 0, why);
    if (edit) {
      assert.match(edits[0].url, new RegExp(`/channels/${edit[0]}/messages/${edit[1]}$`), why);
      for (const [k, v] of Object.entries(edit[2])) assert.deepEqual(edits[0].body[k], v, why);
    }
    assert.equal(f.find('POST', /\/channels\/700\/messages$/).length, 0, `${why}: no player message`);
  }
});

test('a press check that cannot finish asks for another press', async () => {
  const record = fakeKv({ 'issue:700': JSON.stringify({ repo: 'me/test-one', number: 3, key: 'ONE', by: 'Bite' }) });
  for (const [why, kv, fetchOf] of [
    ['the record read fails', { get: async () => { throw new Error('KV down'); } }, (f) => f],
    ['the record read never answers', { get: () => new Promise(() => {}) }, (f) => f],
    ['GitHub stalls past the deadline', record, (f) => (url, init = {}) => (/issues\/3$/.test(url) ? stall(init) : f(url, init))],
    ['the marker search stalls past the deadline', fakeKv(), (f) => (url, init = {}) => (/issues\?state=all/.test(url) ? stall(init) : f(url, init))],
  ]) {
    const f = fakeFetch(discordRoutes());
    const j = await (await handle(await signed(cardPress(HELPER)), { ...QUEUE, STATE: kv }, ctxFor(),
      { fetch: fetchOf(f), installationToken: async () => 'inst', log: () => {}, pressMs: 50 })).json();
    assert.match(j.data.content, /^Could not check whether this post is already on GitHub\. Press the button again\.$/, why);
  }
});

test('filing replies to the filed message with a ping, leaves the greeting alone, records the filing and marks the card last', async () => {
  for (const [why, req, messageId, by] of [
    ['from the queue card', { ...submit(), member: HELPER, channel_id: '556', data: { ...submit().data, custom_id: 'gh:700:700:0:96' } }, '700', 'helper'],
    ['by right-click on a later message, the card from the record', submit(), '800', 'moddy'],
  ]) {
    const kv = fakeKv({ 'thread:700': JSON.stringify({ greeting: '951', buttonless: true, card: '96' }) });
    const f = fakeFetch(discordRoutes(githubRoutes([], [
      STARTER,
      ['POST', /api\.github\.com\/repos\/me\/test-one\/issues$/, () => ({ number: 17, html_url: 'u/17' })],
      ['PATCH', /\/channels\/556\/messages\/96$/, () => ({})],
    ])));
    const ctx = ctxFor();
    await handle(await signed(req), { ...QUEUE, STATE: kv }, ctx, { fetch: f, installationToken: async () => 'inst' });
    const [res] = await Promise.all(ctx.jobs);
    assert.deepEqual(res, { created: 17, notes: [] }, why);
    const [sent, ...more] = f.find('POST', /\/channels\/700\/messages$/);
    assert.deepEqual(more, [], why);
    assert.equal(sent.body.content, MESSAGES.tracked('ONE', 17), why);
    assert.deepEqual(sent.body.message_reference, { message_id: messageId, fail_if_not_exists: false }, why);
    assert.deepEqual(sent.body.allowed_mentions, { parse: [], users: [], replied_user: true }, why);
    assert.equal(f.calls.filter((c) => /\/messages\/951$/.test(c.url)).length, 0, `${why}: the greeting is left alone`);
    const card = f.find('PATCH', /\/channels\/556\/messages\/96$/)[0].body;
    assert.match(card.content, new RegExp(`^~~.*~~\\n\\*\\*Filed as ONE #17\\*\\* by ${by}$`), why);
    const marked = at(f, 'PATCH', /\/channels\/556\/messages\/96$/);
    assert.ok(at(f, 'POST', /\/channels\/700\/messages$/) < marked, `${why}: the player's reply first`);
    assert.ok(at(f, 'PATCH', /\/webhooks\//) < marked, `${why}: the moderator's result first`);
    assert.ok(at(f, 'DELETE', /labels\/discord-lock-700$/) < marked, `${why}: the card waits for the lock's release, never the other way round`);
    assert.deepEqual(JSON.parse(kv.m.get('thread:700')), { greeting: '951', buttonless: true, card: '96' }, `${why}: the scan's record is untouched`);
    assert.deepEqual(JSON.parse(kv.m.get('issue:700')), { repo: 'me/test-one', number: 17, key: 'ONE', by }, why);
  }
});

test('an old button greeting is retired once the reply exists, and becomes the note only when the reply was refused', async () => {
  for (const [why, greeting, over, deleted, edit, notes] of [
    ['the delete works', WITH_BUTTON, [], 1, null, []],
    ['the delete is refused: the button is stripped', WITH_BUTTON, [['DELETE', /\/messages\/950$/, refusal]], 1, { components: [] }, []],
    ['the delete and the strip are refused', WITH_BUTTON, [['DELETE', /\/messages\/950$/, refusal], ['PATCH', /\/messages\/950$/, refusal]], 1, { components: [] }, [/^the old button was not removed: .*403/]],
    ['an earlier receipt shows no button: left alone', RECEIPT, [], 0, null, []],
    ['the reply is refused: the greeting becomes the note', WITH_BUTTON, [['POST', /\/channels\/700\/messages$/, refusal]], 0,
      { content: MESSAGES.tracked('ONE', 17), components: [], allowed_mentions: { parse: [] } }, []],
    // The reply may exist: a second receipt would repeat it.
    ['the reply has an unknown outcome: nothing is edited', WITH_BUTTON, [['POST', /\/channels\/700\/messages$/, () => new Response('{}', { status: 500 })]], 0,
      null, [/^note in the post may not have been sent: .*500/]],
  ]) {
    const kv = fakeKv({ 'thread:700': JSON.stringify({ greeting: '950' }) });
    const f = fakeFetch(discordRoutes(githubRoutes([], [
      ...over,
      ['GET', /\/channels\/700\/messages\/950$/, () => greeting],
      ['DELETE', /\/channels\/700\/messages\/950$/, () => null],
      ['PATCH', /\/channels\/700\/messages\/950$/, () => ({})],
      ['POST', /api\.github\.com\/repos\/me\/test-one\/issues$/, () => ({ number: 17, html_url: 'u/17' })],
    ])));
    const ctx = ctxFor();
    await handle(await signed(submit()), { ...env, STATE: kv }, ctx, { fetch: f, installationToken: async () => 'inst' });
    const [res] = await Promise.all(ctx.jobs);
    assert.equal(res.created, 17, why);
    assert.equal(f.find('DELETE', /\/messages\/950$/).length, deleted, why);
    assert.deepEqual(f.find('PATCH', /\/messages\/950$/).map((c) => c.body).at(-1) ?? null, edit, why);
    assert.equal(res.notes.length, notes.length, `${why}: ${res.notes}`);
    notes.forEach((re, i) => assert.match(res.notes[i], re, why));
  }
});

test('already tracked on submit: no reply, an old button greeting only loses its button, the filing is recorded, and the card says Filed as', async () => {
  for (const [why, greeting, stripped] of [['an old greeting with its button', WITH_BUTTON, [{ components: [] }]], ['an earlier receipt', RECEIPT, []]]) {
    const kv = fakeKv({ 'thread:700': JSON.stringify({ greeting: '950', card: '96' }) });
    const f = fakeFetch(discordRoutes(githubRoutes([{ number: 17, html_url: 'u/17', body: '<!-- discord-thread: 700 reporter: 42 -->' }], [
      ['GET', /\/channels\/700\/messages\/950$/, () => greeting],
      ['PATCH', /\/channels\/700\/messages\/950$/, () => ({})],
      ['PATCH', /\/channels\/556\/messages\/96$/, () => ({})],
    ])));
    const ctx = ctxFor();
    await handle(await signed(submit()), { ...QUEUE, STATE: kv }, ctx, { fetch: f, installationToken: async () => 'inst' });
    assert.deepEqual(await Promise.all(ctx.jobs), [{ duplicate: 17 }], why);
    assert.equal(f.find('POST', /\/channels\/700\/messages$/).length, 0, `${why}: no reply`);
    assert.equal(f.find('DELETE', /\/messages\/950$/).length, 0, `${why}: never deleted`);
    assert.deepEqual(f.find('PATCH', /\/messages\/950$/).map((c) => c.body), stripped, why);
    assert.match(f.find('PATCH', /\/channels\/556\/messages\/96$/)[0].body.content, /\n\*\*Filed as ONE #17\*\*$/, why);
    assert.ok(at(f, 'PATCH', /\/webhooks\//) < at(f, 'PATCH', /\/channels\/556\/messages\/96$/), `${why}: the moderator hears first`);
    assert.deepEqual(JSON.parse(kv.m.get('issue:700')), { repo: 'me/test-one', number: 17, key: 'ONE', by: null }, `${why}: found by the search and saved`);
    assert.equal(f.find('PATCH', /\/webhooks\//)[0].body.content, 'Already tracked: ONE #17 u/17', why);
  }
});

test('filing leaves a status the post shows, also one a workflow set just before the write', async () => {
  // The post is read when the filing starts, then by the tag write, then again just before it writes.
  for (const [why, reads] of [
    ['In progress from the start', [['t-retail', 's-prog']]],
    ['In progress set between the tag write\'s two reads', [['t-retail'], ['t-retail'], ['t-retail', 's-prog']]],
  ]) {
    const queue = [...reads];
    const f = fakeFetch(discordRoutes(githubRoutes([], [
      ['GET', /\/channels\/700$/, () => ({ id: '700', parent_id: '900', name: 'x', applied_tags: queue.length > 1 ? queue.shift() : queue[0] })],
      ['POST', /api\.github\.com\/repos\/me\/test-one\/issues$/, () => ({ number: 17, html_url: 'u/17' })],
    ])));
    const ctx = ctxFor();
    await handle(await signed(submit()), env, ctx, { fetch: f, installationToken: async () => 'inst' });
    const [res] = await Promise.all(ctx.jobs);
    assert.deepEqual([res.created, res.notes], [17, []], why);
    assert.equal(f.find('PATCH', /\/channels\/700$/).length, 0, `${why}: In progress stays`);
  }
});

test('a slow tag write cannot use up the player\'s receipt: each has its own end', async () => {
  const clock = shiftClock();
  try {
    let reads = 0;
    const base = fakeFetch(discordRoutes(githubRoutes([], [
      ['POST', /api\.github\.com\/repos\/me\/test-one\/issues$/, () => ({ number: 17, html_url: 'u/17' })],
    ])));
    // The post's second read is the tag write's: it stalls, and the clock
    // stands at 20.5 s when it ends.
    const hang = (url, init = {}) => ((init.method || 'GET') === 'GET' && /\/channels\/700$/.test(url) && ++reads === 2
      ? stall(init, () => clock.at(20500))
      : base(url, init));
    const ctx = ctxFor();
    await handle(await signed(submit()), env, ctx, { fetch: hang, installationToken: async () => 'inst', log: () => {}, callMs: 50 });
    const [res] = await Promise.all(ctx.jobs);
    assert.equal(res.created, 17);
    assert.ok(res.notes.some((n) => /^tag not set: /.test(n)), res.notes.join('; '));
    assert.equal(base.find('POST', /\/channels\/700\/messages$/).length, 1, 'the receipt went out');
    assert.match(base.find('PATCH', /\/webhooks\//)[0].body.content, /^Created ONE #17/);
  } finally { clock.restore(); }
});

test('an approved role can submit the form; a player cannot', async () => {
  const f = fakeFetch(discordRoutes(githubRoutes([], [['POST', /api\.github\.com\/repos\/me\/test-one\/issues$/, () => ({ number: 17, html_url: 'u' })]])));
  let ctx = ctxFor();
  const r = await handle(await signed(buttonSubmit(PLAYER)), P3, ctx, { fetch: f });
  assert.match((await r.json()).data.content, /Only moderators and approved roles/);
  assert.equal(ctx.jobs.length, 0);
  ctx = ctxFor();
  await handle(await signed(buttonSubmit(HELPER)), P3, ctx, { fetch: f, installationToken: async () => 'inst' });
  assert.equal((await Promise.all(ctx.jobs))[0].created, 17);
});

test('the template check is noted in the issue and told to the moderator, never the player', async () => {
  let created;
  const post = '```\nAddon version:\n1.2\n\nUI version:\n(from your addon manager, or "not sure")\n\nUpdated with the game closed:\nyes\n\nWhat happened:\nbags overlap\n\nWhat you expected:\nno overlap\n\nHow to make it happen again:\n(what you did, in order)\n\nScreenshots:\n(attach full-screen screenshots, or write "none")\n```';
  const f = fakeFetch(discordRoutes(githubRoutes([], [
    ['GET', /\/channels\/700\/messages\/800$/, () => ({ id: '800', content: post, author: { id: '42', username: 'pat' }, attachments: [] })],
    ['POST', /api\.github\.com\/repos\/me\/test-one\/issues$/, (b) => { created = b; return { number: 17, html_url: 'u' }; }],
  ])));
  const ctx = ctxFor();
  await handle(await signed(submit()), env, ctx, { fetch: f, installationToken: async () => 'inst' });
  await Promise.all(ctx.jobs);
  assert.match(created.body, /Template check \(advisory\): UI version missing · How to make it happen again missing · Screenshots missing$/m);
  assert.match(f.find('PATCH', /\/webhooks\//)[0].body.content, /Template: UI version missing, How to make it happen again missing, Screenshots missing\./);
  assert.doesNotMatch(f.find('POST', /\/channels\/700\/messages$/)[0].body.content, /Template/);
});

test('a post the bot already filed is found from its record without reading the issue list', async () => {
  const kv = fakeKv({ 'thread:700': JSON.stringify({ greeting: '950', issue: { repo: 'me/test-one', number: 17 } }) });
  const f = fakeFetch(discordRoutes(githubRoutes([], [
    ['GET', /api\.github\.com\/repos\/me\/test-one\/issues\/17$/, () => ({ number: 17, html_url: 'u/17', body: '<!-- discord-thread: 700 reporter: 42 -->' })],
  ])));
  const ctx = ctxFor();
  await handle(await signed(buttonSubmit()), { ...P3, STATE: kv }, ctx, { fetch: f, installationToken: async () => 'inst' });
  assert.deepEqual(await Promise.all(ctx.jobs), [{ duplicate: 17 }]);
  assert.equal(f.find('GET', /issues\?state=all/).length, 0);
  assert.match(f.find('PATCH', /\/webhooks\//)[0].body.content, /Already tracked: ONE #17/);
});

test('a button or form whose ids are not all digits is refused before any call', async () => {
  for (const req of [
    { ...press(HELPER), data: { custom_id: 'send:700/../x', component_type: 2 } },
    { ...submit(), data: { ...submit().data, custom_id: 'gh:700:800x' } },
    { ...submit(), data: { ...submit().data, custom_id: 'gh:700' } },
  ]) {
    const f = fakeFetch(discordRoutes());
    const ctx = ctxFor();
    const j = await (await handle(await signed(req), P3, ctx, { fetch: f })).json();
    assert.match(j.data.content, /not valid/, req.data.custom_id);
    assert.equal(f.calls.length, 0, req.data.custom_id);
    assert.equal(ctx.jobs.length, 0, req.data.custom_id);
  }
});

test('the template check reads the forum\'s pinned template, and falls back to the defaults with a note', async () => {
  const LINK = 'https://discord.com/channels/1/960/961';
  const pinned = '```\nWhat happened:\n(what went wrong)\n\nScreenshots:\n(attach)\n```';
  const post = 'What happened:\nbags overlap\n\nScreenshots:\n';
  for (const [link, answer, body, told, raw] of [
    [LINK, () => ({ id: '961', content: pinned }), /Template check \(advisory\): Screenshots missing$/m, /^Created ONE #17: u Template: Screenshots missing\.$/, null],
    // An optional field left blank is no gap, in the issue or the reply.
    [LINK, () => ({ id: '961', content: pinned.replace('Screenshots:', 'Screenshots (optional):') }), /Template check \(advisory\): every field present$/m, /^Created ONE #17: u$/, null],
    [LINK, () => new Response('{"message":"Missing Access"}', { status: 403 }), /Template check \(advisory\): Addon version unsure/, /\(the bot may not read the template message; check its access to that post, so the default fields were checked\)/, /template read failed: .*403.*Missing Access/],
    [LINK, () => ({ id: '961', content: 'Welcome! Read the rules first.' }), /Template check \(advisory\): Addon version unsure/, /the forum's pinned template has no labels, so the default fields were checked/, null],
    // A post's link pasted instead of the message's: nothing is read.
    ['https://discord.com/channels/1/960', () => { throw new Error('read'); }, /Template check \(advisory\): Addon version unsure/, /the forum's template link is not a message link, so the default fields were checked/, null],
  ]) {
    const PIN = { ...env, FORUM_CHANNEL_IDS: '', FORUMS: JSON.stringify({ 900: { client: 'Retail', type: 'Bug', template: link } }) };
    let created;
    const f = fakeFetch(discordRoutes(githubRoutes([], [
      ['GET', /\/channels\/960\/messages\/961$/, answer],
      ['GET', /\/channels\/700\/messages\/800$/, () => ({ id: '800', content: post, author: { id: '42', username: 'pat' }, attachments: [] })],
      ['POST', /api\.github\.com\/repos\/me\/test-one\/issues$/, (b) => { created = b; return { number: 17, html_url: 'u' }; }],
    ])));
    const ctx = ctxFor();
    const logged = [];
    await handle(await signed(submit()), PIN, ctx, { fetch: f, installationToken: async () => 'inst', log: (s) => logged.push(s) });
    await Promise.all(ctx.jobs);
    assert.match(created.body, body);
    const reply = f.find('PATCH', /\/webhooks\//)[0].body.content;
    assert.match(reply, told);
    assert.doesNotMatch(reply, /Discord GET|Missing Access/);
    if (raw) assert.ok(logged.some((l) => raw.test(l)), `the raw error is logged: ${logged}`);
    else assert.deepEqual(logged, []);
  }
});

test('a stalled pinned-template read near the deadline still leaves the create its full call time', async () => {
  const PIN = { ...env, FORUM_CHANNEL_IDS: '', FORUMS: '{"900":{"client":"Retail","type":"Bug","template":"https://discord.com/channels/1/960/961"}}' };
  const base = fakeFetch(discordRoutes(githubRoutes([], [
    ['POST', /api\.github\.com\/repos\/me\/test-one\/issues$/, () => ({ number: 17, html_url: 'u' })],
  ])));
  const hang = (url, init = {}) => (/\/channels\/960\/messages\/961$/.test(url) ? stall(init) : base(url, init));
  const ctx = ctxFor();
  await handle(await signed(submit()), PIN, ctx, { fetch: hang, installationToken: async () => 'inst', log: () => {}, callMs: 100, budgetMs: 300 });
  const [res] = await Promise.all(ctx.jobs);
  assert.equal(res.created, 17, JSON.stringify(res));
  assert.match(base.find('PATCH', /\/webhooks\//)[0].body.content, /the template message could not be read just now, so the default fields were checked/);
});
