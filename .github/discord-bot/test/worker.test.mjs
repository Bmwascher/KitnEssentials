import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, createVerify } from 'node:crypto';
import { handle, COMMAND_NAME, CHECK_COMMAND, scheduled, privateText } from '../src/worker.js';
import { CRONS } from '../src/scan.js';
import { importAppKey, appJwt } from '../src/github.js';
import { MESSAGES } from '../src/core.js';
import { fakeFetch, fakeKv, FORUM, stall } from './fake-fetch.mjs';
import { setupWorld } from './setup-world.mjs';

const keys = await crypto.subtle.generateKey({ name: 'Ed25519' }, true, ['sign', 'verify']);
const pubHex = Buffer.from(await crypto.subtle.exportKey('raw', keys.publicKey)).toString('hex');
const env = {
  DISCORD_PUBLIC_KEY: pubHex, DISCORD_BOT_TOKEN: 'bot-token',
  GITHUB_APP_ID: '1', GITHUB_APP_PRIVATE_KEY: 'unused',
  REPOS: '{"ONE":"me/test-one","TWO":"me/test-two"}', LOCK_REPO: 'me/test-one', FORUM_CHANNEL_IDS: '900',
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
    ['GET', /api\.github\.com\/repos\/me\/test-two\/issues\?state=all.*labels=from-discord/, () => []],
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
  const order = f.calls.filter((c) => /labels(\/discord-lock-700)?$|test-one\/issues\?state=all/.test(c.url)).map((c) => c.method);
  assert.deepEqual(order, ['POST', 'GET', 'DELETE'], 'lock, one look in the chosen repo, release');
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
  const hangList = (url, init = {}) => (/test-one\/issues\?state=all/.test(url)
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
  // The lock stays, and the advice frees it only after an hour, given as a margin, not a guarantee.
  assert.match(told, /The lock discord-lock-700 in me\/test-one stays, so this post cannot be filed twice meanwhile\. If no issue for this post appears in me\/test-one, delete the label discord-lock-700 in me\/test-one, but only if the time in its description is more than an hour ago or it shows no time\. A send ends within 30 seconds and GitHub times out a request after 10 seconds, so the hour is a wide margin past both\. Then send the post again\.$/);
  assert.equal(base.find('DELETE', /labels\/discord-lock-700$/).length, 0, 'the lock stays until the outcome is known');
});

test('a create that answered late is found again: the player gets the reply, the moderator the result, and the card is marked last', async () => {
  let looks = 0;
  // Two searches before the create find nothing; the re-check after it finds the issue.
  const base = fakeFetch(discordRoutes(githubRoutes([], [
    ['GET', /test-one\/issues\?state=all.*labels=from-discord/, () => (++looks <= 2 ? [] : [{ number: 17, html_url: 'u/17', body: '<!-- discord-thread: 700 reporter: 42 -->' }])],
    ['PATCH', /\/channels\/556\/messages\/96$/, () => ({})],
  ])));
  const hang = (url, init = {}) => (init.method === 'POST' && /\/issues$/.test(url)
    ? stall(init)
    : base(url, init));
  const ctx = ctxFor();
  const kv = fakeKv({ 'thread:700': JSON.stringify({ card: '96' }) });
  await handle(await signed(submit()), { ...env, QUEUE_CHANNEL_ID: '556', STATE: kv }, ctx, { fetch: hang, installationToken: async () => 'inst', log: () => {}, callMs: 50 });
  const [res] = await Promise.all(ctx.jobs);
  assert.equal(res.created, 17);
  // The template result goes with a late create too.
  assert.equal(base.find('PATCH', /\/webhooks\//)[0].body.content, 'Created ONE #17: u/17 (GitHub answered late; the post\'s status tag comes from the issue\'s first workflow run) Template: Addon version unsure, UI version unsure, Updated with the game closed unsure, What happened unsure, What you expected unsure, How to make it happen again unsure.');
  assert.deepEqual(JSON.parse(kv.m.get('issue:700')), { repo: 'me/test-one', number: 17, key: 'ONE', by: 'moddy' }, 'the filing is recorded');
  const [receipt, ...more] = base.find('POST', /\/channels\/700\/messages$/);
  assert.deepEqual(more, [], 'one receipt');
  assert.equal(receipt.body.content, MESSAGES.tracked('ONE', 17), 'the player is told');
  assert.deepEqual(receipt.body.message_reference, { message_id: '800', fail_if_not_exists: false });
  assert.equal(base.find('PATCH', /\/channels\/556\/messages\/96$/)[0].body.content, '~~**New post in <#900>:** <#700>~~\n**Filed as ONE #17** by moddy', 'the card is marked filed, its first line the post\'s mention');
  const pos = (method, re) => at(base, method, re);
  const marked = pos('PATCH', /\/channels\/556\/messages\/96$/);
  assert.ok(pos('PATCH', /\/webhooks\//) < marked && pos('POST', /\/channels\/700\/messages$/) < marked, 'the card last');
  assert.equal(base.find('DELETE', /labels\/discord-lock-700$/).length, 1);
});

test('a late create whose record save never answers still reports in time', async () => {
  let looks = 0;
  const base = fakeFetch(discordRoutes(githubRoutes([], [
    ['GET', /test-one\/issues\?state=all.*labels=from-discord/, () => (++looks <= 2 ? [] : [{ number: 17, html_url: 'u/17', body: '<!-- discord-thread: 700 reporter: 42 -->' }])],
  ])));
  const hang = (url, init = {}) => (init.method === 'POST' && /\/issues$/.test(url) ? stall(init) : base(url, init));
  const kv = { get: async () => null, put: () => new Promise(() => {}) };
  const ctx = ctxFor();
  await handle(await signed(submit()), { ...env, STATE: kv }, ctx, { fetch: hang, installationToken: async () => 'inst', log: () => {}, callMs: 50, kvMs: 50 });
  const [res] = await Promise.all(ctx.jobs);
  assert.equal(res.created, 17);
  assert.match(base.find('PATCH', /\/webhooks\//)[0].body.content, /^Created ONE #17: u\/17 \(GitHub answered late; .*post record not saved: no answer in 50 ms\) Template: .*\.$/);
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
  const told = base.find('PATCH', /\/webhooks\//)[0].body.content;
  assert.match(told, /discord-lock-700/);
  // This send cannot know whose label it is, so it never advises deleting it.
  assert.doesNotMatch(told, /delete/);
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
    const looks = base.find('GET', /test-one\/issues\?state=all.*labels=from-discord/).length;
    assert.equal(looks, 2, 'the two searches before the create, and no re-check after 20 s');
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
  assert.equal(j.data.content, 'The button is not set up yet: APPROVED_ROLE_IDS is empty. A moderator can open the post and right-click a message › Apps › Send to GitHub.');
});

test('a moderator can still press the button with no roles set', async () => {
  const j = await (await handle(await signed(press(MOD)), { ...P3, APPROVED_ROLE_IDS: '' }, ctxFor(), { fetch: searched(), ...INST })).json();
  assert.equal(j.type, 9);
});

const buttonSubmit = (member = HELPER) => ({ ...submit(), member, data: { ...submit().data, custom_id: 'gh:700:800:950' } });

// ---- The queue card, the press check and the tracked reply ------------------------

const QUEUE = { ...P3, QUEUE_CHANNEL_ID: '556' };
// A press on the post's card in the queue channel, outside the post. It is an
// older card, the post's name as text: a press strikes its own first line as it is.
const CARD = { id: '96', content: '**New post in <#900>:** Bags\nby Kira (`kira_99`) · Bug · Retail' };
const cardPress = (member) => ({ ...press(member), guild_id: '1', channel_id: '556', message: CARD });
const STARTER = ['GET', /\/channels\/700\/messages\/700$/, () => ({ id: '700', content: 'first', author: { id: '42', username: 'op' }, attachments: [] })];
const WITH_BUTTON = { id: '950', content: 'old', components: [{ type: 1, components: [{ type: 2, custom_id: 'send:700' }] }] };
const RECEIPT = { id: '950', content: 'Thanks! This is now tracked as ONE #9.', components: [] };
const refusal = () => new Response('{"message":"Missing Permissions"}', { status: 403 });
// The position of a call, which must have been made: an order check never
// passes on a call that is missing.
const at = (f, method, re) => {
  const i = f.calls.findIndex((c) => c.method === method && re.test(c.url));
  assert.ok(i >= 0, `no ${method} ${re}`);
  return i;
};

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
    ['a record that names no issue', { 'issue:700': '{}' }, issue(), cardPress(HELPER), /^This post's saved record is damaged \(issue:700\)/, null],
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
    // The struck first line is the post's mention, never its name.
    assert.equal(card.content, `~~**New post in <#900>:** <#700>~~\n**Filed as ONE #17** by ${by}`, why);
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
    // An edit whose answer was lost may have made the greeting the note.
    ['the reply is refused and the edit has an unknown outcome', WITH_BUTTON, [['POST', /\/channels\/700\/messages$/, refusal], ['PATCH', /\/messages\/950$/, () => new Response('{}', { status: 500 })]], 0,
      { content: MESSAGES.tracked('ONE', 17), components: [], allowed_mentions: { parse: [] } }, [/^note in the post may not have been sent: .*500/]],
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
    assert.equal(f.find('PATCH', /\/channels\/556\/messages\/96$/)[0].body.content, '~~**New post in <#900>:** <#700>~~\n**Filed as ONE #17**', why);
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

test('a stalled pinned-template read ends a full call\'s time before the deadline, and the last read and the create still run', async () => {
  const PIN = { ...env, FORUM_CHANNEL_IDS: '', FORUMS: '{"900":{"client":"Retail","type":"Bug","template":"https://discord.com/channels/1/960/961"}}' };
  const base = fakeFetch(discordRoutes(githubRoutes([], [
    ['POST', /api\.github\.com\/repos\/me\/test-one\/issues$/, () => ({ number: 17, html_url: 'u' })],
  ])));
  let aborted = 0;
  const hang = (url, init = {}) => (/\/channels\/960\/messages\/961$/.test(url) ? stall(init, () => { aborted++; }) : base(url, init));
  const ctx = ctxFor();
  await handle(await signed(submit()), PIN, ctx, { fetch: hang, installationToken: async () => 'inst', log: () => {}, callMs: 100, budgetMs: 300 });
  const [res] = await Promise.all(ctx.jobs);
  assert.equal(aborted, 1, 'the template read started and was ended by its time limit');
  assert.equal(res.created, 17, JSON.stringify(res));
  assert.match(base.find('PATCH', /\/webhooks\//)[0].body.content, /the template message could not be read just now, so the default fields were checked/);
});

test('one post, one issue: the saved record, then every configured repo, is checked before filing', async () => {
  const live = () => ({ number: 9, html_url: 'https://github.com/me/test-two/issues/9' });
  const moved = () => ({ number: 31, html_url: 'https://github.com/me/test-three/issues/31', repository_url: 'https://api.github.com/repos/me/test-three' });
  const status = (s) => () => new Response('{"message":"x"}', { status: s });
  const list = (items) => () => items;
  const marked = { number: 9, html_url: 'https://github.com/me/test-two/issues/9', repository_url: 'https://api.github.com/repos/me/test-two', body: '<!-- discord-thread: 700 reporter: 42 -->' };
  const inst = async () => 'inst';
  const tokenFails = (s, bad = 'me/test-two') => async ({ repo }) => {
    if (repo === bad) throw new Error(`GitHub GET /repos/${bad}/installation -> ${s} {"message":"x"}`);
    return 'inst';
  };
  const movedIn = () => ({ number: 40, html_url: 'https://github.com/me/test-one/issues/40', repository_url: 'https://api.github.com/repos/me/test-one' });
  // GitHub names the repo in its own casing, which REPOS need not match.
  const caseIn = () => ({ number: 40, html_url: 'https://github.com/Me/Test-One/issues/40', repository_url: 'https://api.github.com/repos/Me/Test-One' });
  // A list that misses the post's issue the first time and holds it the
  // second, as when the issue shifted between two pages while it was read.
  const secondTime = (items) => { let n = 0; return () => (++n <= 1 ? [] : items); };
  const inOne = { number: 17, html_url: 'https://github.com/me/test-one/issues/17', repository_url: 'https://api.github.com/repos/me/test-one', body: '<!-- discord-thread: 700 reporter: 42 -->' };
  // A record from before the filing record kept the issue beside the greeting.
  const legacy = (repo, number) => ({ 'thread:700': JSON.stringify({ issue: { repo, number } }) });
  const elsewhere = legacy('me/test-two', 9);
  const brokenKv = { get: async () => { throw new Error('KV down'); }, put: async () => {} };
  const silentKv = { get: () => new Promise(() => {}), put: async () => {} };
  const made = { repo: 'me/test-one', number: 17, key: 'ONE', by: 'moddy' };
  const movedTo = { repo: 'me/test-three', number: 31, key: 'me/test-three', by: null };
  const way = 'If it is gone, a bot admin can clear this post\'s filing record \\(the KV key issue:700, or the "issue" field of thread:700 for a post filed before this version\\), and the post can then be sent again\\.$';
  // `two` and `one` answer the configured repos' issue lists; `saved` is the
  // issue:700 record afterward, repo and number together; a legacy record
  // that already names the issue where it is gets none.
  for (const [why, entries, read, token, two, want, told, saved, one = list([])] of [
    ['a live issue in the other repo', elsewhere, live, inst, list([]), { duplicate: 9, repo: 'me/test-two' },
      /^Already tracked as TWO #9: https:\/\/github\.com\/me\/test-two\/issues\/9\. Nothing was created in me\/test-one; to move the report, transfer the issue on GitHub\.$/, null],
    ['moved on from the other repo: named and recorded where it is now', elsewhere, moved, inst, list([]), { duplicate: 31, repo: 'me/test-three' },
      /^Already tracked as me\/test-three #31: https:\/\/github\.com\/me\/test-three\/issues\/31\. Nothing was created/, movedTo],
    // The filer stays known when the issue moved.
    ['moved on, with the filer on record', { 'issue:700': JSON.stringify({ repo: 'me/test-two', number: 9, key: 'TWO', by: 'Bite' }) }, moved, inst, list([]),
      { duplicate: 31, repo: 'me/test-three' }, /^Already tracked as me\/test-three #31: /, { ...movedTo, by: 'Bite' }],
    ['deleted there (410)', elsewhere, status(410), inst, list([]), { created: 17, notes: [] }, /^Created ONE #17/, made],
    ['not found there (404)', elsewhere, status(404), inst, list([]), { refused: 'saved-issue' },
      new RegExp(`^Could not check TWO #9 in me/test-two \\(404\\): it may be gone, or the app may have lost access there\\. Nothing was created\\. ${way}`), null],
    // A transfer can leave the record naming a repo the form does not offer.
    ['not found in a repo the form does not offer', legacy('me/test-three', 31), status(404), inst, list([]), { refused: 'saved-issue' },
      new RegExp(`^Could not check me/test-three #31 \\(404\\): it may be gone, or the app may have lost access there\\. Nothing was created\\. ${way}`), null],
    // The app files in its own repo, but a 404 there too may be an issue moved out of its reach.
    ['not found in the chosen repo (404)', legacy('me/test-one', 17), status(404), inst, list([]), { refused: 'saved-issue' },
      new RegExp(`^Could not check ONE #17 in me/test-one \\(404\\): .*Nothing was created\\. ${way}`), null],
    ['no token for the other repo', elsewhere, live, tokenFails(404), list([]), { refused: 'saved-issue' }, /^Could not check TWO #9 in me\/test-two \(no access: 404\)/, null],
    // Only the issue's own 410 means deleted, never the token's.
    ['the token request answers 410', elsewhere, live, tokenFails(410), list([]), { refused: 'saved-issue' }, /^Could not check TWO #9 in me\/test-two \(no access: 410\)/, null],
    ['no record and no marker anywhere: filed', {}, live, inst, list([]), { created: 17, notes: [] }, /^Created ONE #17/, made],
    ['no record, but the other repo holds the post\'s marker', {}, live, inst, list([marked]), { duplicate: 9 },
      /^Already tracked: TWO #9 https:\/\/github\.com\/me\/test-two\/issues\/9\. Nothing was created in me\/test-one\.$/, { repo: 'me/test-two', number: 9, key: 'TWO', by: null }],
    ['the other repo cannot be listed', {}, live, inst, status(500), 'error', /^Nothing was created: could not check me\/test-two for this post \(.*500.*\)\. Try again\.$/, null],
    ['the chosen repo cannot be listed', {}, live, inst, list([]), 'error', /^Nothing was created: could not check me\/test-one for this post \(.*500.*\)\. Try again\.$/, null, status(500)],
    ['the record read fails', 'unreadable', live, inst, list([]), { refused: 'record' }, /^Nothing was created: could not read this post's saved record just now\. Try again\.$/, undefined],
    ['the record read never answers', 'silent', live, inst, list([]), { refused: 'record' }, /^Nothing was created: could not read this post's saved record just now\. Try again\.$/, undefined],
    ['the filing record is not JSON', { 'issue:700': '{"repo": "me/test-tw' }, live, inst, list([]), { refused: 'record' },
      /^Nothing was created: this post's saved record is damaged \(issue:700\)\. A bot admin can delete that KV key; then send the post again\.$/, undefined],
    ['the scan\'s record is an empty string', { 'thread:700': '' }, live, inst, list([]), { refused: 'record' }, /^Nothing was created: this post's saved record is damaged \(thread:700\)/, undefined],
    // JSON the bot could not have written is damaged too, never "no record".
    ['the filing record is JSON null', { 'issue:700': 'null' }, live, inst, list([]), { refused: 'record' }, /^Nothing was created: this post's saved record is damaged \(issue:700\)/, undefined],
    ['the filing record names no issue', { 'issue:700': '{}' }, live, inst, list([]), { refused: 'record' }, /^Nothing was created: this post's saved record is damaged \(issue:700\)/, undefined],
    ['the scan\'s record is not a record', { 'thread:700': '[]' }, live, inst, list([]), { refused: 'record' }, /^Nothing was created: this post's saved record is damaged \(thread:700\)/, undefined],
    ['the filing record\'s repo is not owner/name', { 'issue:700': JSON.stringify({ repo: '/', number: 3 }) }, live, inst, list([]), { refused: 'record' }, /^Nothing was created: this post's saved record is damaged \(issue:700\)/, undefined],
    ['the same repo, deleted (410): the search runs and files', legacy('me/test-one', 17), status(410), inst, list([]), { created: 17, notes: [] }, /^Created ONE #17/, made],
    // Where the issue is now decides the advice, not where the record saw it.
    ['moved out of the chosen repo: the transfer advice', legacy('me/test-one', 17), moved, inst, list([]), { duplicate: 31, repo: 'me/test-three' },
      /^Already tracked as me\/test-three #31: .*Nothing was created in me\/test-one; to move the report, transfer the issue on GitHub\.$/, movedTo],
    ['moved into the chosen repo: no transfer advice', elsewhere, movedIn, inst, list([]), { duplicate: 40 },
      /^Already tracked: ONE #40 https:\/\/github\.com\/me\/test-one\/issues\/40$/, { repo: 'me/test-one', number: 40, key: 'ONE', by: null }],
    ['in the chosen repo, named by GitHub in another case: no transfer advice', elsewhere, caseIn, inst, list([]), { duplicate: 40 },
      /^Already tracked: ONE #40 https:\/\/github\.com\/Me\/Test-One\/issues\/40$/, { repo: 'Me/Test-One', number: 40, key: 'ONE', by: null }],
    ['no token for the chosen repo', {}, live, tokenFails(500, 'me/test-one'), list([]), 'error',
      /^Nothing was created: could not get access to me\/test-one \(.*500.*\)\. Try again\.$/, null],
    ['the second search finds what the first missed: no create', {}, live, inst, list([]), { duplicate: 17 },
      /^Already tracked: ONE #17 https:\/\/github\.com\/me\/test-one\/issues\/17$/, { repo: 'me/test-one', number: 17, key: 'ONE', by: null }, secondTime([inOne])],
  ]) {
    const kv = entries === 'unreadable' ? brokenKv : entries === 'silent' ? silentKv : fakeKv(entries);
    const f = fakeFetch(discordRoutes(githubRoutes([], [
      ['GET', /api\.github\.com\/repos\/me\/test-(one|two|three)\/issues\/(9|17|31)$/, read],
      ['GET', /api\.github\.com\/repos\/me\/test-one\/issues\?state=all.*labels=from-discord/, one],
      ['GET', /api\.github\.com\/repos\/me\/test-two\/issues\?state=all.*labels=from-discord/, two],
      ['POST', /api\.github\.com\/repos\/me\/test-one\/issues$/, () => ({ number: 17, html_url: 'u/17' })],
    ])));
    const ctx = ctxFor();
    await handle(await signed(submit()), { ...env, STATE: kv }, ctx, { fetch: f, installationToken: token, log: () => {}, kvMs: 50 });
    const [res] = await Promise.all(ctx.jobs);
    if (want === 'error') assert.ok(res.error, why);
    else assert.deepEqual(res, want, why);
    assert.equal(f.find('POST', /\/issues$/).length, want.created ? 1 : 0, why);
    assert.match(f.find('PATCH', /\/webhooks\//)[0].body.content, told, why);
    if (saved !== undefined) {
      assert.deepEqual(kv.m.has('issue:700') ? JSON.parse(kv.m.get('issue:700')) : null, saved, `${why}: the filing record`);
    }
  }
});

test('with several repos and no LOCK_REPO set, nothing is filed and the moderator is told why', async () => {
  const f = fakeFetch(discordRoutes(githubRoutes()));
  const ctx = ctxFor();
  await handle(await signed(submit()), { ...env, LOCK_REPO: '' }, ctx, { fetch: f, installationToken: async () => 'inst' });
  assert.deepEqual(await Promise.all(ctx.jobs), [{ refused: 'setup' }]);
  assert.equal(f.find('POST', /\/labels$|\/issues$/).length, 0);
  assert.equal(f.find('PATCH', /\/webhooks\//)[0].body.content, 'Nothing was created: the bot is not set up yet. REPOS names more than one repo, so LOCK_REPO must name the repo that holds every filing\'s lock.');
});

test('one lock per post: a filing into the second repo takes its lock in LOCK_REPO, and a lock held there stops it', async () => {
  for (const [why, held, want, repos = env.REPOS] of [
    ['free', false, { created: 21, notes: [] }],
    ['held by another send', true, { busy: true }],
    // The lock repo is named, not taken from the order of REPOS.
    ['REPOS listed the other way round', false, { created: 21, notes: [] }, '{"TWO":"me/test-two","ONE":"me/test-one"}'],
    ['held, with REPOS listed the other way round', true, { busy: true }, '{"TWO":"me/test-two","ONE":"me/test-one"}'],
  ]) {
    const f = fakeFetch(discordRoutes(githubRoutes([], [
      ['POST', /api\.github\.com\/repos\/me\/test-one\/labels$/, () => (held
        ? new Response('{"message":"Validation Failed","errors":[{"resource":"Label","code":"already_exists","field":"name"}]}', { status: 422 })
        : new Response('{}', { status: 201 }))],
      ['POST', /api\.github\.com\/repos\/me\/test-two\/issues$/, () => ({ number: 21, html_url: 'u/21' })],
    ])));
    const ctx = ctxFor();
    await handle(await signed(submit({ repo: 'two' })), { ...env, REPOS: repos }, ctx, { fetch: f, installationToken: async () => 'inst' });
    assert.deepEqual(await Promise.all(ctx.jobs), [want], why);
    assert.equal(f.find('POST', /test-two\/labels$/).length, 0, `${why}: no lock in the chosen repo`);
    assert.match(f.find('POST', /test-one\/labels$/)[0].body.description, /^Send to GitHub since \d{4}-\d\d-\d\d \d\d:\d\d:\d\d UTC$/, `${why}: the lock says when it was taken`);
    assert.equal(f.find('DELETE', /test-one\/labels\/discord-lock-700$/).length, held ? 0 : 1, `${why}: released where it was taken`);
    assert.equal(f.find('POST', /\/issues$/).length, held ? 0 : 1, why);
    // A filing that holds the lock may be between its last search and its create, or GitHub may still apply its create: the advice frees only a lock an hour old.
    if (held) {
      assert.match(f.find('PATCH', /\/webhooks\//)[0].body.content,
        /another send of this post is running, or one stopped partway\. Wait a few minutes, then send it again\. If it still says this and no issue for this post appears in any repo the bot files into, delete the label discord-lock-700 in me\/test-one, but only if the time in its description is more than an hour ago or it shows no time\. A send ends within 30 seconds and GitHub times out a request after 10 seconds, so the hour is a wide margin past both\. Then send the post again\.$/, why);
    }
  }
});

test('a reply Discord refuses goes out plain, and the Worker log says so', async () => {
  let posts = 0;
  const f = fakeFetch(discordRoutes(githubRoutes([], [
    ['POST', /\/channels\/700\/messages$/, () => (++posts === 1 ? new Response('{"message":"Cannot reply to a system message"}', { status: 400 }) : { id: '2' })],
    ['POST', /api\.github\.com\/repos\/me\/test-one\/issues$/, () => ({ number: 17, html_url: 'u/17' })],
  ])));
  const ctx = ctxFor();
  const logged = [];
  await handle(await signed(submit()), env, ctx, { fetch: f, installationToken: async () => 'inst', log: (s) => logged.push(s) });
  const [res] = await Promise.all(ctx.jobs);
  assert.deepEqual([res.created, res.notes], [17, []]);
  const [reply, plain] = f.find('POST', /\/channels\/700\/messages$/).map((c) => c.body);
  assert.deepEqual([reply.message_reference.message_id, plain.message_reference], ['800', undefined]);
  assert.ok(logged.some((l) => /^post 700: Discord refused the reply; the note went out plain, with no ping$/.test(l)), logged.join('\n'));
});

test('a long template result never costs the moderator the issue\'s link', async () => {
  // A valid pinned template of sixty long labels, none answered.
  const labels = Array.from({ length: 60 }, (_, i) => `Field ${String(i).padStart(2, '0')} with quite a long label name`);
  const PIN = { ...env, FORUM_CHANNEL_IDS: '', FORUMS: '{"900":{"client":"Retail","type":"Bug","template":"https://discord.com/channels/1/960/961"}}' };
  const f = fakeFetch(discordRoutes(githubRoutes([], [
    ['GET', /\/channels\/960\/messages\/961$/, () => ({ id: '961', content: labels.map((l) => `${l}:`).join('\n') })],
    ['POST', /api\.github\.com\/repos\/me\/test-one\/issues$/, () => ({ number: 17, html_url: 'u' })],
  ])));
  const ctx = ctxFor();
  await handle(await signed(submit()), PIN, ctx, { fetch: f, installationToken: async () => 'inst' });
  await Promise.all(ctx.jobs);
  const told = f.find('PATCH', /\/webhooks\//)[0].body.content;
  assert.ok(told.length <= 2000, `${told.length} characters`);
  assert.match(told, /^Created ONE #17: u Template: Field 00 with quite a long label name unsure, /);
});

test('the card lookup after the lock\'s release keeps to the release\'s end', async () => {
  const clock = shiftClock();
  try {
    let gets = 0;
    // The record reads under the lock answer; the lookup after the release would never answer.
    const kv = { get: () => (++gets <= 2 ? Promise.resolve(null) : new Promise(() => {})), put: async () => {} };
    const f = fakeFetch(discordRoutes(githubRoutes([], [
      ['POST', /api\.github\.com\/repos\/me\/test-one\/issues$/, () => ({ number: 17, html_url: 'u/17' })],
      // The release ends past 29 s.
      ['DELETE', /api\.github\.com\/repos\/me\/test-one\/labels\/discord-lock-700$/, () => { clock.at(29500); return null; }],
    ])));
    const ctx = ctxFor();
    await handle(await signed(submit()), { ...QUEUE, STATE: kv }, ctx, { fetch: f, installationToken: async () => 'inst', log: () => {} });
    const [res] = await Promise.all(ctx.jobs);
    assert.equal(res.created, 17);
    assert.equal(gets, 2, 'no lookup starts past the release\'s end');
  } finally { clock.restore(); }
});

test('a card lookup after the release that fails is logged, and the record read under the lock is used', async () => {
  let gets = 0;
  // The record read under the lock names card 96; the lookup after the release fails.
  const kv = { get: async (k) => { if (++gets > 2) throw new Error('KV down'); return k === 'thread:700' ? JSON.stringify({ card: '96' }) : null; }, put: async () => {} };
  const f = fakeFetch(discordRoutes(githubRoutes([], [
    ['POST', /api\.github\.com\/repos\/me\/test-one\/issues$/, () => ({ number: 17, html_url: 'u/17' })],
    ['PATCH', /\/channels\/556\/messages\/96$/, () => ({})],
  ])));
  const ctx = ctxFor();
  const logged = [];
  await handle(await signed(submit()), { ...QUEUE, STATE: kv }, ctx, { fetch: f, installationToken: async () => 'inst', log: (s) => logged.push(s) });
  const [res] = await Promise.all(ctx.jobs);
  assert.equal(res.created, 17);
  assert.ok(logged.some((l) => /^card lookup failed, so the record read earlier is used: KV down$/.test(l)), logged.join('\n'));
  assert.equal(f.find('PATCH', /\/channels\/556\/messages\/96$/).length, 1, 'the card the earlier read named is marked filed');
});

test('a message deleted before its filing files nothing and says how to file the post', async () => {
  const f = fakeFetch(discordRoutes(githubRoutes([], [
    ['GET', /\/channels\/700\/messages\/800$/, () => new Response('{"message":"Unknown Message"}', { status: 404 })],
  ])));
  const ctx = ctxFor();
  await handle(await signed(submit()), env, ctx, { fetch: f, installationToken: async () => 'inst', log: () => {} });
  assert.deepEqual(await Promise.all(ctx.jobs), [{ refused: 'message' }]);
  assert.equal(f.find('POST', /\/issues$/).length, 0);
  assert.equal(f.find('PATCH', /\/webhooks\//)[0].body.content, 'Nothing was created: the message to file was deleted; a moderator can open the post and right-click a message › Apps › Send to GitHub.');
  assert.equal(f.find('DELETE', /labels\/discord-lock-700$/).length, 1, 'the lock is released');
});

test('a message deleted while the member or the template is read files nothing', async () => {
  const PIN = { ...env, FORUM_CHANNEL_IDS: '', FORUMS: '{"900":{"client":"Retail","type":"Bug","template":"https://discord.com/channels/1/960/961"}}' };
  for (const [why, during] of [
    ['deleted while the reporter\'s member record is read', /\/guilds\/1\/members\/42$/],
    ['deleted while the pinned template is read', /\/channels\/960\/messages\/961$/],
  ]) {
    let gone = false;
    const f = fakeFetch(discordRoutes(githubRoutes([], [
      ['GET', /\/channels\/700\/messages\/800$/, () => (gone
        ? new Response('{"message":"Unknown Message"}', { status: 404 })
        : { id: '800', content: 'My bags overlap', author: { id: '42', username: 'pat' }, attachments: [] })],
      ['GET', during, () => { gone = true; return new Response('{"message":"x"}', { status: 404 }); }],
      ['POST', /api\.github\.com\/repos\/me\/test-one\/issues$/, () => ({ number: 17, html_url: 'u/17' })],
    ])));
    const ctx = ctxFor();
    await handle(await signed(submit()), PIN, ctx, { fetch: f, installationToken: async () => 'inst', log: () => {} });
    assert.deepEqual(await Promise.all(ctx.jobs), [{ refused: 'message' }], why);
    assert.equal(f.find('POST', /\/issues$/).length, 0, `${why}: nothing is created`);
    assert.match(f.find('PATCH', /\/webhooks\//)[0].body.content, /^Nothing was created: the message to file was deleted; a moderator can open the post/, why);
    assert.equal(f.find('DELETE', /labels\/discord-lock-700$/).length, 1, `${why}: the lock is released`);
  }
});

test('a filing whose post was deleted says the post was deleted, never the message', async () => {
  let reads = 0;
  const f = fakeFetch(discordRoutes(githubRoutes([], [
    ['GET', /\/channels\/700$/, () => (++reads === 1
      ? { id: '700', parent_id: '900', name: 'x', applied_tags: [] }
      : new Response('{"message":"Unknown Channel"}', { status: 404 }))],
    ['GET', /\/channels\/700\/messages\/800$/, () => new Response('{"message":"Unknown Channel"}', { status: 404 })],
  ])));
  const ctx = ctxFor();
  await handle(await signed(submit()), env, ctx, { fetch: f, installationToken: async () => 'inst', log: () => {} });
  assert.deepEqual(await Promise.all(ctx.jobs), [{ refused: 'post' }]);
  assert.equal(f.find('POST', /\/issues$/).length, 0);
  assert.equal(f.find('PATCH', /\/webhooks\//)[0].body.content, 'Nothing was created: the post was deleted.');
});

test('a filing whose searches end late still reads its message last and creates the issue', async () => {
  const clock = shiftClock();
  try {
    const base = fakeFetch(discordRoutes(githubRoutes([], [
      ['POST', /api\.github\.com\/repos\/me\/test-one\/issues$/, () => ({ number: 17, html_url: 'u/17' })],
    ])));
    // The searches and the first read of the message end at second eight of fifteen.
    let shifted = false;
    const late = (url, init = {}) => {
      const res = base(url, init);
      if (!shifted && /\/channels\/700\/messages\/800$/.test(url)) { shifted = true; clock.at(8000); }
      return res;
    };
    const ctx = ctxFor();
    await handle(await signed(submit()), env, ctx, { fetch: late, installationToken: async () => 'inst', log: () => {} });
    const [res] = await Promise.all(ctx.jobs);
    assert.equal(res.created, 17, JSON.stringify(res));
    assert.equal(base.find('GET', /\/channels\/700\/messages\/800$/).length, 2, 'the message is read again just before the create');
    assert.equal(base.find('GET', /\/guilds\/1\/members\//).length, 0, 'the optional member read is skipped');
  } finally { clock.restore(); }
});

test('a title of direction marks alone is empty, as the issue would get it', async () => {
  const ctx = ctxFor();
  const r = await handle(await signed(submit({ title: '\u200f\u202e' })), env, ctx, { fetch: fakeFetch([]) });
  assert.match((await r.json()).data.content, /Title is empty\./);
  assert.equal(ctx.jobs.length, 0);
});

// A setup failing in many ways at once: 30 forums that do not exist (more
// reads than the Discord share), 200 roles that do not (more lines than five
// messages hold), and eight healthy repos (24 GitHub calls, more than the
// GitHub share).
const BIG = {
  FORUMS: JSON.stringify(Object.fromEntries(Array.from({ length: 30 }, (_, i) => [String(1000 + i), {}]))),
  APPROVED_ROLE_IDS: Array.from({ length: 200 }, (_, i) => String(5000 + i)).join(','),
  REPOS: JSON.stringify(Object.fromEntries(['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'].map((k) => [k, `me/${k.toLowerCase()}`]))),
  LOCK_REPO: 'me/a',
};
// The same line 30 times: two messages whose lines are equal.
const SAME = { APPROVED_ROLE_IDS: Array(30).fill('777').join(',') };
const quiet = (deps) => ({ ...deps, log: () => {} });
// Every setting the Worker reads, written here, not taken from the code.
const ALL_SETTINGS = ['REPOS', 'LOCK_REPO', 'FORUMS', 'FORUM_CHANNEL_IDS', 'GUILD_ID', 'TEMPLATES', 'APPROVED_ROLE_IDS', 'MOD_CHANNEL_ID',
  'QUEUE_CHANNEL_ID', 'CHECKLIST_FORUM_ID', 'STALE_DAYS', 'DISCORD_PUBLIC_KEY', 'DISCORD_BOT_TOKEN', 'GITHUB_APP_ID', 'GITHUB_APP_PRIVATE_KEY'];
const NO_TEXT = { toString: null };
// Every value the entry points must stop on: each setting with no text form,
// and the two keys read with string methods bound to null.
const UNREADABLE = [...ALL_SETTINGS.map((k) => [k, NO_TEXT]), ['DISCORD_PUBLIC_KEY', null], ['GITHUB_APP_PRIVATE_KEY', null]];
const checkCmd = (member, over = {}) => ({ type: 2, member, channel_id: '555', guild_id: '1', application_id: 'app', token: 'tok', data: { name: CHECK_COMMAND }, ...over });

test('WT1: /bot-check is for moderators of this server, answers privately at once, and posts only to a verified moderator channel', async () => {
  for (const [why, member, envOver, guild, said] of [
    ['a player', PLAYER, {}, '1', /^Only moderators and admins can check the bot setup\.$/],
    ['a moderator of another server', MOD, {}, '2', /^This command checks only the server the bot is set up for\.$/],
    ['a moderator with GUILD_ID unset', MOD, { GUILD_ID: '' }, '1', /^The bot's GUILD_ID is not set to a server id, so it can check nothing\./],
    ['a moderator with GUILD_ID malformed', MOD, { GUILD_ID: '1x' }, '1', /^The bot's GUILD_ID is not set to a server id, so it can check nothing\./],
    ['a moderator with a GUILD_ID of no text form', MOD, { GUILD_ID: { toString: null } }, '1', /^The bot's GUILD_ID is not set to a server id, so it can check nothing\./],
  ]) {
    const { env: e, deps } = setupWorld(undefined, pubHex);
    const j = await (await handle(await signed(checkCmd(member, { guild_id: guild })), { ...e, ...envOver }, ctxFor(), quiet(deps))).json();
    assert.match(j.data.content, said, why);
    assert.equal(deps.fetch.calls.length, 0, `${why}: no calls`);
  }
  let n = 0;
  for (const [why, edit, posted, said] of [
    ['posted', () => {}, 1, /^Posted in <#555>: 0 problem\(s\)\.$/],
    ['channel unset', (s) => { s.env = { MOD_CHANNEL_ID: '' }; }, 0, /^Not posted in the moderator channel: MOD_CHANNEL_ID is not set\.\n\n\*\*Bot setup check\*\* \(run by <@5>\): 1 problem\(s\)/],
    ['channel set to a post', (s) => { s.env = { MOD_CHANNEL_ID: '777' }; s.alone['777'] = { id: '777', guild_id: '1', type: 11 }; }, 0,
      /^Not posted in the moderator channel: <#777> is not verified \(it is a post, not a channel\)\./],
    ['a listed channel of another server', (s) => { s.channels[2].guild_id = '2'; }, 0,
      /^Not posted in the moderator channel: <#555> is not verified \(it is not a channel of this server\)\./],
    ['a post taken with an answer that is not JSON', (s) => { s.modPost = new Response('<html>', { status: 200 }); }, 1, /^Posted in <#555>: 0 problem\(s\)\.$/],
    ['channel without Send Messages', (s) => { s.channels[2].permission_overwrites = [{ id: '11', type: 0, deny: String(1n << 11n), allow: '0' }]; }, 0,
      /^Not posted in the moderator channel: the bot lacks Send Messages in <#555>\./],
    ['post refused', (s) => { s.modPost = new Response('{"message":"Missing Permissions"}', { status: 403 }); }, 1,
      /^Not posted in the moderator channel: the moderator channel refused the post \(403\)\.\n\n\*\*Bot setup check\*\* \(run by <@5>\): 1 problem\(s\), \d+ checks passed\.\n- Moderator channel <#555>: the bot's post was refused \(403\)/],
    // The reason comes first, however long the rest: a failure with no answer.
    ['the post failing with no answer', (s) => { s.modPost = () => { throw new TypeError('network down'); }; }, 1,
      /^Not posted in the moderator channel: the post could not be sent \(network down\)\./],
    // A busy Discord is a retry, never a channel fault.
    ['the post answered 503', (s) => { s.modPost = new Response('{"message":"busy"}', { status: 503 }); }, 1,
      /^Not posted in the moderator channel: Discord could not take the post just now \(503\)\.\n[\s\S]*\n- Moderator channel <#555>: Discord could not take the post just now \(503\)\. Run \/bot-check again in a minute\./],
    // Two messages of equal lines, the first taken and the second refused:
    // the refused lines are named although their text was taken once.
    ['first message taken, the second refused', (s) => { s.env = SAME; n = 0; s.modPost = () => (++n === 1 ? { id: 'm1' } : new Response('{"message":"no"}', { status: 403 })); }, 2,
      /^Posted in part in <#555>: 1 of 2 messages; the moderator channel refused the post \(403\)\. The rest:\n\n- APPROVED_ROLE_IDS: the role <@&777> does not exist in this server\.\n/],
  ]) {
    const { env: e, deps } = setupWorld(edit, pubHex);
    const ctx = ctxFor();
    const r = await (await handle(await signed(checkCmd(MOD)), e, ctx, quiet(deps))).json();
    assert.deepEqual(r, { type: 5, data: { flags: 64 } }, why);
    await Promise.all(ctx.jobs);
    const count = deps.fetch.find('POST', /\/channels\/555\/messages$/).length;
    assert.equal(count, posted, why);
    assert.deepEqual(deps.fetch.find('POST', /\/channels\/777\/messages$/), [], `${why}: never into a post`);
    const reply = deps.fetch.find('PATCH', /\/webhooks\/app\/tok\/messages\/@original$/)[0].body;
    assert.match(reply.content, said, why);
    // The private reply names who ran the check, and pings no one.
    assert.deepEqual(reply.allowed_mentions, { parse: [] }, `${why}: the private reply pings no one`);
    // What the moderators read: the command's own result, naming who ran it
    // as a mention that pings no one.
    if (why === 'posted') {
      const post = deps.fetch.find('POST', /\/channels\/555\/messages$/)[0].body;
      assert.match(post.content, /^\*\*Bot setup check\*\* \(run by <@5>\): every check passed \(\d+ checks\)\.$/, `${why}: the posted result`);
      assert.deepEqual(post.allowed_mentions, { parse: [] }, `${why}: the posted result pings no one`);
    }
  }
  for (const [why, over, channel] of [
    ['in a forum post: its forum', { channel_id: '777', channel: { id: '777', type: 11, parent_id: '900' } }, '900'],
    ['in a text channel: that channel', { channel: { id: '555', type: 0, parent_id: '42' } }, '555'],
  ]) {
    const { env: e, deps } = setupWorld(undefined, pubHex);
    const out = [];
    const ctx = ctxFor();
    await handle(await signed(checkCmd(MOD, over)), e, ctx, { ...deps, log: (s) => out.push(s) });
    await Promise.all(ctx.jobs);
    assert.ok(out.some((l) => new RegExp(`^setup check: needed permissions computed \\d+, app_permissions not given, in channel ${channel}: different$`).test(l)), `${why}: ${out.join(' | ')}`);
  }
  const { env: e, deps } = setupWorld((s) => { s.env = BIG; }, pubHex);
  const ctx = ctxFor();
  await handle(await signed(checkCmd(MOD)), e, ctx, quiet(deps));
  await Promise.all(ctx.jobs);
  const calls = deps.fetch.calls;
  const github = calls.filter((c) => /api\.github\.com/.test(c.url)).length;
  const discordReads = calls.filter((c) => /discord\.com/.test(c.url) && c.method === 'GET').length;
  assert.equal(github, 15, `GitHub's share is used to its end and no further: ${github}`);
  assert.equal(discordReads, 28, `Discord's share is used to its end and no further: ${discordReads}`);
  assert.ok(calls.length <= 49, `the run stays within 49 requests: ${calls.length}`);
  assert.ok(calls.every((c) => c.redirect === 'manual'), 'no call may follow a redirect');
  const posts = deps.fetch.find('POST', /\/channels\/555\/messages$/);
  assert.ok(posts.length === 5 && posts.every((c) => c.body.content.length <= 2000), `${posts.length} posts`);
  assert.match(posts[4].body.content, /\n- and \d+ more \(see the Worker log\)$/, 'the fit names what it left out');
  assert.match(deps.fetch.find('PATCH', /\/webhooks\//)[0].body.content, /^Posted in <#555>: \d+ problem\(s\)\.$/);
});

test('WT2: the daily setup check posts problems every day, the weekly line on a passing Monday, and nothing on another passing day', async () => {
  const MON = Date.UTC(2026, 10, 23, 15, 30);
  const TUE = MON + 24 * 60 * 60 * 1000;
  for (const [why, edit, now, re] of [
    ['a problem on a Tuesday', (s) => { s.app = { flags: 0 }; }, TUE, /^\*\*Daily bot setup check:\*\* 1 problem\(s\):\n- The Message Content setting is off/],
    ['all pass on a Monday', () => {}, MON,
      /^\*\*Weekly bot setup check:\*\* every check passes today \(\d+ checks\)\. This line comes each Monday that every check passes\. A Monday with neither this line nor a problem list means the daily setup check is not running or cannot post\.$/],
    ['all pass on a Tuesday', () => {}, TUE, null],
    ['a moderator channel that is a post', (s) => { s.env = { MOD_CHANNEL_ID: '777' }; s.alone['777'] = { id: '777', guild_id: '1', type: 11 }; }, TUE, null],
    ['the large failing setup', (s) => { s.env = BIG; }, TUE, /^\*\*Daily bot setup check:\*\* \d+ problem\(s\):/],
  ]) {
    const { env: e, deps } = setupWorld(edit);
    const kv = fakeKv();
    const out = [];
    await scheduled({ cron: CRONS.setup }, { ...e, STATE: kv }, {}, { ...deps, now: () => now, log: (s) => out.push(s) });
    const posts = deps.fetch.find('POST', /\/channels\/\d+\/messages$/).map((c) => c.body.content);
    if (re) assert.match(posts[0] || '', re, why);
    else assert.deepEqual(posts, [], why);
    if (why === 'a moderator channel that is a post') assert.match(out.join('\n'), /Moderator channel <#777>: it is a post, not a channel/, `${why}: logged`);
    if (why === 'all pass on a Tuesday') assert.match(out.join('\n'), /^daily setup check: every check passed \(\d+ checks\)$/m, `${why}: the log says it ran`);
    assert.ok(deps.fetch.calls.length <= 48, `${why}: ${deps.fetch.calls.length} calls`);
    assert.ok(deps.fetch.calls.every((c) => c.redirect === 'manual'), `${why}: no call follows a redirect`);
    assert.equal(kv.m.size, 0, `${why}: no KV write`);
  }
});

test("WT4: the not-set-up reply names the first broken setting only to a caller who may send, in the bot's server, after the caller check", async () => {
  // A role the player lacks and the helper has, so a player reaches the
  // caller check's refusal and not the empty-role advice.
  const G = { GUILD_ID: '1', APPROVED_ROLE_IDS: '77' };
  const press = (member, guild = '1') => ({ type: 3, member, guild_id: guild, channel_id: '556', application_id: 'app', token: 'ptok', message: { id: '9' }, data: { custom_id: 'send:700' } });
  const rightClick = (member, guild = '1') => ({ type: 2, member, guild_id: guild, channel_id: '700', application_id: 'app', token: 'rtok', data: { name: COMMAND_NAME, target_id: '700' } });
  const sub = (member, guild = '1') => ({ ...submit(), member, guild_id: guild });
  const ADMINS = 'Only moderators and admins can send posts to GitHub.';
  const ROLES = 'Only moderators and approved roles can send posts to GitHub.';
  const ELSEWHERE = 'This only works on posts in the forums the bot is set up for.';
  const GUILD_LINE = "The bot is not set up yet: GUILD_ID is not set to the server's id (digits only, no spaces).";
  const FORUMS_LINE = 'The bot is not set up yet: FORUMS is not valid JSON: set it to JSON keyed by forum channel id, like {"111":{}}.';
  const REPOS_LINE = 'The bot is not set up yet: REPOS is not set or not valid JSON: set it to JSON like {"KE":"owner/repo"}.';
  const TEXTLESS_LINE = 'The bot is not set up yet: FORUMS entry 900: "client", "type" and "template" must each be text, like "template":"https://discord.com/channels/...".';
  const badForums = { FORUM_CHANNEL_IDS: '', FORUMS: '{not json' };
  const badRepos = { ...badForums, REPOS: '' };
  const textless = { FORUM_CHANNEL_IDS: '', FORUMS: '{"900":{"template":{"toString":null}}}' };
  for (const [why, broken, interaction, want] of [
    ['a moderator right-click, broken FORUMS', badForums, rightClick(MOD), FORUMS_LINE],
    ['a moderator submit, broken FORUMS', badForums, sub(MOD), FORUMS_LINE],
    ['an approved role submit, broken FORUMS', badForums, sub(HELPER), FORUMS_LINE],
    ['a player right-click, broken FORUMS', badForums, rightClick(PLAYER), ADMINS],
    ['a player submit, broken FORUMS', badForums, sub(PLAYER), ROLES],
    ['a moderator right-click, broken REPOS', badRepos, rightClick(MOD), REPOS_LINE],
    ['a moderator submit, broken REPOS', badRepos, sub(MOD), REPOS_LINE],
    ['a moderator press, broken REPOS', badRepos, press(MOD), REPOS_LINE],
    ['an approved role press, broken REPOS', badRepos, press(HELPER), REPOS_LINE],
    ['a player press, broken REPOS', badRepos, press(PLAYER), ROLES],
    ['a player submit, broken REPOS', badRepos, sub(PLAYER), ROLES],
    ['a moderator submit, a FORUMS value with no text form', textless, sub(MOD), TEXTLESS_LINE],
    ['a moderator right-click, no forums and a STALE_DAYS of no text form', { FORUMS: '', FORUM_CHANNEL_IDS: '', STALE_DAYS: { toString: null } }, rightClick(MOD),
      'The bot is not set up yet: STALE_DAYS is not text: set it as text. The checks below read it as unset.'],
    ['an approved role press, broken REPOS and an APPROVED_ROLE_IDS of no text form', { ...badRepos, APPROVED_ROLE_IDS: { toString: null } }, press(HELPER), ROLES],
    ['a moderator submit, a GUILD_ID of no text form', { ...badRepos, GUILD_ID: { toString: null } }, sub(MOD), GUILD_LINE],
    ['a moderator of another server, right-click', badRepos, rightClick(MOD, '2'), ELSEWHERE],
    ['a moderator of another server, press', badRepos, press(MOD, '2'), ELSEWHERE],
    ['a moderator of another server, submit', badForums, sub(MOD, '2'), ELSEWHERE],
    // With GUILD_ID not an id the caller's server cannot be told, so the
    // reply names GUILD_ID alone, never the broken REPOS behind it.
    ['GUILD_ID unset, a moderator of another server, press', { ...badRepos, GUILD_ID: '' }, press(MOD, '2'), GUILD_LINE],
    ['GUILD_ID malformed, a moderator of another server, right-click', { ...badRepos, GUILD_ID: '1x' }, rightClick(MOD, '2'), GUILD_LINE],
    ['GUILD_ID malformed, a moderator of another server, submit', { ...badRepos, GUILD_ID: '1x' }, sub(MOD, '2'), GUILD_LINE],
    ['GUILD_ID unset, a moderator in the server, submit', { ...badRepos, GUILD_ID: '' }, sub(MOD), GUILD_LINE],
  ]) {
    const f = fakeFetch([]);
    const j = await (await handle(await signed(interaction), { ...env, ...G, ...broken }, ctxFor(), { fetch: f })).json();
    assert.equal(j.data.content, want, why);
    assert.equal(f.calls.length, 0, `${why}: no calls`);
  }
  {
    // With REPOS readable, a press keeps its order: the search for a
    // filing comes first, so a filed post answers Already tracked and its
    // card is marked, broken FORUMS or not.
    const f = fakeFetch(discordRoutes([
      ['GET', /api\.github\.com\/repos\/me\/test-one\/issues\/3$/, () => ({ number: 3, html_url: 'https://github.com/me/test-one/issues/3' })],
      ['PATCH', /\/channels\/556\/messages\/96$/, () => ({})],
    ]));
    const kv = fakeKv({ 'issue:700': JSON.stringify({ repo: 'me/test-one', number: 3, key: 'ONE', by: 'Bite' }) });
    const ctx = ctxFor();
    const j = await (await handle(await signed(cardPress(HELPER)), { ...QUEUE, ...badForums, GUILD_ID: '1', STATE: kv }, ctx, { fetch: f, ...INST, log: () => {} })).json();
    await Promise.all(ctx.jobs);
    assert.match(j.data.content, /^Already tracked as ONE #3: /, 'a filed post still answers Already tracked');
    assert.equal(f.find('PATCH', /\/channels\/556\/messages\/96$/).length, 1, 'and its card is marked');
  }
});

test('WT5: with a setting no reader can read, the scan and the daily list do nothing, and the daily setup check names it', async () => {
  const T = Date.UTC(2026, 10, 24, 15, 30);
  const AGO = T - 3 * 60 * 60 * 1000;
  // Made an hour ago: after the scan's start and past every marker.
  const POST = String(BigInt(T - 60 * 60 * 1000 - 1420070400000) << 22n);
  const activeWith = (deps, sent) => (url, init) => {
    sent.push(url);
    return /\/threads\/active$/.test(url) ? new Response(JSON.stringify({ threads: [{ id: POST, parent_id: '900' }] })) : deps.fetch(url, init);
  };
  {
    // With every setting readable, the same scan reads the post, so the
    // runs below have a post to skip.
    const { env: e, deps } = setupWorld((s) => { s.alone['555'] = { ...s.channels[2] }; }, pubHex);
    const kv = fakeKv({ 'scan:since': String(AGO), 'scan:state': JSON.stringify({ last: AGO }) });
    const sent = [];
    await scheduled({ cron: CRONS.scan }, { ...e, STATE: kv }, {}, { fetch: activeWith(deps, sent), now: () => T, log: () => {} }).catch(() => {});
    assert.ok(sent.some((u) => u.includes(POST)), `with every setting readable, the scan reads the waiting post: ${sent.join(' | ')}`);
  }
  for (const [k, v] of UNREADABLE) {
    for (const cron of [CRONS.scan, CRONS.daily, CRONS.setup]) {
      const { env: e, deps } = setupWorld((s) => { s.alone['555'] = { ...s.channels[2] }; }, pubHex);
      const kv = fakeKv({ 'scan:since': String(AGO), 'scan:state': JSON.stringify({ last: AGO }) });
      const before = kv.m.get('scan:state');
      const sent = [];
      const out = [];
      await scheduled({ cron }, { ...e, STATE: kv, [k]: v }, {}, { fetch: activeWith(deps, sent), now: () => T, log: (s) => out.push(s) });
      if (cron !== CRONS.setup) {
        const job = cron === CRONS.scan ? 'scan' : 'daily list';
        assert.deepEqual(out, [`${k} is not text: the ${job} did not run.`], `${k}, the ${job}: one log line`);
        assert.deepEqual(sent, [], `${k}, the ${job}: no call`);
        assert.equal(kv.m.get('scan:state'), before, `${k}, the ${job}: no marker moves`);
        continue;
      }
      const named = `- ${k} is not text: set it as text. The checks below read it as unset.`;
      const posts = deps.fetch.find('POST', /\/channels\/555\/messages$/).map((c) => c.body.content);
      if (['MOD_CHANNEL_ID', 'GUILD_ID', 'DISCORD_BOT_TOKEN'].includes(k)) {
        assert.ok(!posts.length && out.some((l) => l.split('\n').includes(named)), `${k}, the setup check: logged, never posted: ${out.join(' | ')}`);
      } else {
        assert.ok(posts.some((p) => p.split('\n').includes(named)), `${k}, the setup check: named in the moderator channel: ${posts.join(' | ')}`);
      }
    }
  }
});

test('WT6: with a setting no reader can read, a request never starts filing; a caller who may send is told which', async () => {
  const rightClick = (member) => ({ type: 2, member, guild_id: '1', channel_id: '700', application_id: 'app', token: 'rtok', data: { name: COMMAND_NAME, target_id: '700' } });
  const press = (member) => ({ type: 3, member, guild_id: '1', channel_id: '556', application_id: 'app', token: 'ptok', message: { id: '9' }, data: { custom_id: 'send:700' } });
  // A readable forum list and an approved role the player lacks.
  const G = { GUILD_ID: '1', FORUMS: '{"900":{}}', APPROVED_ROLE_IDS: '77' };
  for (const [k, v] of UNREADABLE) {
    for (const [who, interaction, may] of [['a moderator right-click', rightClick(MOD), true], ['a player press', press(PLAYER), false],
      ['a moderator form submit', submit(), true], ['a moderator /bot-check', checkCmd(MOD), true]]) {
      const f = fakeFetch([]);
      const res = await handle(await signed(interaction), { ...env, ...G, [k]: v }, ctxFor(), { fetch: f });
      if (k === 'DISCORD_PUBLIC_KEY') {
        assert.equal(res.status, 401, `${k}, ${who}: refused, as main refuses a key it cannot read`);
        continue;
      }
      const want = !may ? 'Only moderators and approved roles can send posts to GitHub.'
        : k === 'GUILD_ID' && interaction.data.name === CHECK_COMMAND ? "The bot's GUILD_ID is not set to a server id, so it can check nothing. Fix it in the Worker's settings."
        : k === 'GUILD_ID' ? "The bot is not set up yet: GUILD_ID is not set to the server's id (digits only, no spaces)."
          : `The bot is not set up yet: ${k} is not text: set it as text. The checks below read it as unset.`;
      assert.equal((await res.json()).data.content, want, `${k}, ${who}`);
      assert.equal(f.calls.length, 0, `${k}, ${who}: no calls, and no filing`);
    }
  }
});

test('WT7: the private reply keeps a last line that fits, and names what it leaves out', () => {
  const head = 'Not posted in the moderator channel: x.';
  const last = `- ${'y'.repeat(1950 - head.length - 4)}`;
  assert.equal(privateText(head, [last]), `${head}\n\n${last}`, 'a last line within 2,000 characters is kept whole');
  assert.equal(privateText(head, [last, '- z']), `${head}\n\n${last}\n- z`, 'a reply of 1,954 characters is sent whole, both lines kept');
  const cut = privateText(head, [last, `- ${'z'.repeat(60)}`]);
  assert.ok(cut.length <= 2000 && cut.endsWith('…and 2 more line(s): fix these, then run /bot-check again.'), `lines past the limit are counted: ${cut.slice(-90)}`);
  // 1,930 characters kept and the 59-character notice for one more line: 1,989.
  const a = `- ${'a'.repeat(1880 - head.length - 4)}`;
  const b = `- ${'b'.repeat(47)}`;
  assert.equal(privateText(head, [a, b, `- ${'c'.repeat(100)}`]), `${head}\n\n${a}\n${b}\n…and 1 more line(s): fix these, then run /bot-check again.`,
    'a line that fits beside the notice is kept');
});
