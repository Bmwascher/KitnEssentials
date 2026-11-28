import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, createVerify } from 'node:crypto';
import { handle, COMMAND_NAME, CHECK_COMMAND, scheduled, privateText } from '../src/worker.js';
import { CRONS, MOVED_HERE } from '../src/scan.js';
import { importAppKey, appJwt } from '../src/github.js';
import { MESSAGES } from '../src/core.js';
import { checklistBody, checklistFirst } from '../status/checklist.mjs';
import { fakeFetch, fakeKv, FORUM, stall } from './fake-fetch.mjs';
import { setupWorld } from './setup-world.mjs';

const keys = await crypto.subtle.generateKey({ name: 'Ed25519' }, true, ['sign', 'verify']);
const pubHex = Buffer.from(await crypto.subtle.exportKey('raw', keys.publicKey)).toString('hex');
const env = {
  DISCORD_PUBLIC_KEY: pubHex, DISCORD_BOT_TOKEN: 'bot-token',
  GITHUB_APP_ID: '1', GITHUB_APP_PRIVATE_KEY: 'unused',
  REPOS: '{"ONE":"me/test-one","TWO":"me/test-two"}', LOCK_REPO: 'me/test-one', FORUM_CHANNEL_IDS: '900', GUILD_ID: '1',
};
const MOD = { permissions: String(1n << 34n), user: { id: '5', username: 'moddy' } };
const PLAYER = { permissions: '0', user: { id: '6', username: 'pat' } };

// An interaction that names no server comes from the bot's own ('1').
async function signed(obj, { tamper = false, ts = String(Math.floor(Date.now() / 1000)) } = {}) {
  const body = JSON.stringify(obj.type === 1 || 'guild_id' in obj ? obj : { ...obj, guild_id: '1' });
  const sig = Buffer.from(await crypto.subtle.sign('Ed25519', keys.privateKey, new TextEncoder().encode(ts + body))).toString('hex');
  return new Request('https://bot.example/', {
    method: 'POST', body: tamper ? body.replace('1', '2') : body,
    headers: { 'X-Signature-Ed25519': sig, 'X-Signature-Timestamp': ts },
  });
}
const ctxFor = () => { const jobs = []; return { jobs, waitUntil: (p) => jobs.push(p) }; };
// A form's pre-filled values by field id: a text input's value, a select's
// default option.
const formValues = (j) => Object.fromEntries(j.data.components.map(({ component: c }) => [c.custom_id, c.options ? (c.options.find((o) => o.default) || {}).value : c.value]));

function discordRoutes(extra = []) {
  return [
    ...extra,
    ['GET', /\/channels\/700$/, () => ({ id: '700', parent_id: '900', name: '[Bug] Bags overlap after resize', applied_tags: ['t-retail', 't-bug'] })],
    ['GET', /\/channels\/900$/, () => FORUM],
    ['GET', /\/channels\/700\/messages\/800$/, () => ({ id: '800', content: 'My bags overlap\nafter resize', author: { id: '42', global_name: 'Pat' }, attachments: [{ url: 'x' }] })],
    ['PATCH', /\/channels\/700$/, () => ({})],
    ['POST', /\/channels\/700\/messages$/, () => ({ id: '1' })],
    ['PATCH', /\/webhooks\//, () => ({})],
    ['GET', /\/channels\/\d+\/messages\?limit=100$/, () => []],
    ['GET', /\/channels\/700\/messages\/700$/, () => ({ id: '700', content: 'My bags overlap', author: { id: '42', global_name: 'Pat' }, attachments: [] })],
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
  // Two repos and no repo tag: none is pre-selected, so staff must pick.
  assert.deepEqual(formValues(j), { repo: undefined, client: 'Retail', type: 'Bug', module: undefined, title: 'Bags overlap after resize' });
});

const submit = (over = {}) => ({
  type: 5, member: MOD, guild_id: '1', channel_id: '700', application_id: 'app', token: 'itok',
  data: { custom_id: 'gh:700:800', components: Object.entries({ repo: 'one', client: 'retail', type: 'bug', module: 'Bags', title: 'Bags overlap after resize', ...over })
    .map(([custom_id, value]) => ({ type: 18, component: custom_id === 'repo' ? { type: 3, custom_id, values: [value] } : { type: 4, custom_id, value } })) },
});

test('a bad form value creates nothing and says why', async () => {
  const f = fakeFetch([]);
  const ctx = ctxFor();
  const r = await handle(await signed(submit({ client: 'classic', repo: 'kitn' })), env, ctx, { fetch: f });
  const j = await r.json();
  assert.match(j.data.content, /Nothing was created\. The repo chosen is no longer in REPOS: pick it again\. Client must be/);
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

  assert.equal(created.title, '[ONE] [Retail] [Bug] [Bags] Bags overlap after resize');
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
  assert.equal(f.find('PATCH', /\/channels\/700$/).length, 0, 'a post already tracked is not renamed');
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
  const s = await handle(await signed(submit()), { ...env, FORUM_CHANNEL_IDS: '' }, ctxFor(), { fetch: f });
  assert.match((await s.json()).data.content, /not set up/);
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
  // Its 403 route refuses the rename too, which is logged.
  await handle(await signed(submit()), env, ctx, { fetch: f, installationToken: async () => 'inst', log: () => {} });
  const [res] = await Promise.all(ctx.jobs);
  assert.equal(res.created, 17);
  const told = f.find('PATCH', /\/webhooks\//)[0].body.content;
  assert.match(told, /^Created ONE #17: .*tag not set: .*403.*note in the post not sent: .*403/);
});

test('a new filing renames the post to the issue title after the report and the lock\'s release; a failure goes to the log, never the reply', async () => {
  const NAME = '[ONE] [Retail] [Bug] [Bags] Bags overlap after resize';
  const POST = { id: '700', parent_id: '900', name: '[Bug] Bags overlap after resize', applied_tags: ['t-retail', 't-bug'] };
  const ARCHIVED = { ...POST, thread_metadata: { archived: true } };
  const clock = shiftClock();
  // `read(late)` answers a read of the post; `late` is whether the lock's
  // release has run, so only the rename's read is late.
  try { for (const [why, read, envOver, write, renames, logged] of [
    ['renamed', () => POST, {}, null, [{ name: NAME }], []],
    ['archived when the rename reads it: the same write opens it', (late) => (late ? ARCHIVED : POST), {}, null, [{ name: NAME, archived: false }], []],
    ['already so named, and archived, when the rename reads it: not written, so it stays archived', (late) => ({ ...(late ? ARCHIVED : POST), name: NAME }), {}, null, [], []],
    ['so named when the filing began, renamed by hand since: written', (late) => ({ ...POST, name: late ? 'renamed by hand' : NAME }), {}, null, [{ name: NAME }], []],
    ['RENAME_POSTS is 0: the post is not read or written', () => POST, { RENAME_POSTS: ' 0 ' }, null, [], []],
    ['the rename\'s read is refused (404): nothing written', (late) => (late ? new Response('{"message":"Unknown Channel"}', { status: 404 }) : POST), {}, null, [],
      [/^post 700 rename failed: Discord GET \/channels\/700 -> 404 /]],
    // The release's end (29 s) passes during the read: the write is never sent.
    ['no time left for the write', (late) => { if (late) clock.at(29500); return POST; }, {}, null, [], [/^post 700 rename failed: out of time before PATCH /]],
    ['refused (403)', () => POST, {}, () => new Response('{"message":"Missing Permissions"}', { status: 403 }), [{ name: NAME }],
      [/^post 700 rename failed: Discord PATCH \/channels\/700 -> 403 /]],
    // Discord answered 200 and only its body could not be read: the post has its name.
    ['taken with an answer that is not JSON: no failure logged', () => POST, {}, () => new Response('<html>', { status: 200 }), [{ name: NAME }], []],
  ]) {
    clock.at(0);
    let created;
    // The release answers late: a call to the post while it is pending
    // would be a rename that did not wait for it.
    let releasing = false;
    let released = false;
    let early = false;
    const logs = [];
    const base = fakeFetch(discordRoutes(githubRoutes([], [
      ['DELETE', /labels\/discord-lock-700$/, async () => {
        releasing = true;
        await new Promise((r) => setTimeout(r, 20));
        released = true;
        return null;
      }],
      ['GET', /\/channels\/700$/, () => { if (releasing && !released) early = true; return read(released); }],
      ['PATCH', /\/channels\/700$/, (b) => { if (releasing && !released) early = true; return b.name && write ? write() : {}; }],
      ['POST', /api\.github\.com\/repos\/me\/test-one\/issues$/, (b) => { created = b; return { number: 17, html_url: 'u/17' }; }],
    ])));
    const ctx = ctxFor();
    await handle(await signed(submit()), { ...env, ...envOver }, ctx, { fetch: base, installationToken: async () => 'inst', log: (s) => logs.push(s) });
    const [res] = await Promise.all(ctx.jobs);
    assert.deepEqual(res, { created: 17, notes: [] }, why);
    assert.equal(created.title, NAME, `${why}: the issue's title`);
    const writes = base.find('PATCH', /\/channels\/700$/).map((c) => c.body);
    assert.deepEqual(writes.filter((b) => 'name' in b), renames, `${why}: the rename`);
    assert.equal(writes.filter((b) => 'applied_tags' in b).length, 1, `${why}: the tag write`);
    // The report, then the release, then the rename's own calls.
    const release = at(base, 'DELETE', /labels\/discord-lock-700$/);
    assert.ok(at(base, 'PATCH', /\/webhooks\//) < release, `${why}: the report before the release`);
    const after = base.calls.slice(release + 1).filter((c) => /\/channels\/700$/.test(c.url)).map((c) => c.method);
    assert.deepEqual(after, envOver.RENAME_POSTS ? [] : renames.length ? ['GET', 'PATCH'] : ['GET'], `${why}: the rename's calls`);
    assert.equal(early, false, `${why}: the rename waits for the release's answer`);
    assert.doesNotMatch(base.find('PATCH', /\/webhooks\//)[0].body.content, /renam/, `${why}: the reply says nothing of the rename`);
    const renameLogs = logs.filter((l) => /^post 700 rename/.test(l));
    assert.equal(renameLogs.length, logged.length, `${why}: ${renameLogs.join(' | ')}`);
    logged.forEach((re, i) => assert.match(renameLogs[i], re, why));
  } } finally { clock.restore(); }
});

test('after the lock\'s release, the card (its record lookup included) and the rename run side by side', async () => {
  const POST = { id: '700', parent_id: '900', name: '[Bug] Bags overlap after resize', applied_tags: ['t-retail', 't-bug'] };
  const slow = (ms) => new Promise((r) => setTimeout(r, ms));
  let released = false;
  let gets = 0;
  let looking = false;
  let renaming = false;
  // Whether the card's record lookup and the rename's read were pending at
  // the same time, in whichever order they start; and whether the card's
  // write started while the rename's read (the slower) was still pending.
  let overlap = false;
  let markedDuringRename = false;
  // A right-click filing: the card comes from the record, read under the
  // lock (the first four reads) and looked up again, slowly, after the release.
  const kv = {
    get: async (k) => {
      if (++gets > 4) {
        looking = true;
        overlap = overlap || renaming;
        await slow(30);
        looking = false;
      }
      return k === 'thread:700' ? JSON.stringify({ card: '96' }) : null;
    },
    put: async () => {},
  };
  const f = fakeFetch(discordRoutes(githubRoutes([], [
    ['DELETE', /labels\/discord-lock-700$/, () => { released = true; return null; }],
    ['GET', /\/channels\/700$/, async () => {
      if (!released) return POST;
      renaming = true;
      overlap = overlap || looking;
      await slow(90);
      renaming = false;
      return POST;
    }],
    ['PATCH', /\/channels\/556\/messages\/96$/, () => { markedDuringRename = renaming; return {}; }],
    ['POST', /api\.github\.com\/repos\/me\/test-one\/issues$/, () => ({ number: 17, html_url: 'u/17' })],
  ])));
  const ctx = ctxFor();
  await handle(await signed(submit()), { ...env, QUEUE_CHANNEL_ID: '556', STATE: kv }, ctx, { fetch: f, installationToken: async () => 'inst', log: () => {} });
  const [res] = await Promise.all(ctx.jobs);
  assert.equal(res.created, 17);
  assert.equal(f.find('PATCH', /\/channels\/556\/messages\/96$/).length, 1, 'the card is marked');
  assert.equal(f.find('PATCH', /\/channels\/700$/).filter((c) => 'name' in c.body).length, 1, 'the post is renamed');
  assert.ok(overlap, 'the rename did not wait for the card\'s lookup, nor the lookup for the rename');
  assert.ok(markedDuringRename, 'the card\'s write did not wait for the rename');
});

test('a long title: the issue gets it whole, the post its first 100 characters', async () => {
  const title = 'z'.repeat(100);
  const whole = `[ONE] [Retail] [Bug] [Bags] ${title}`;
  let created;
  const f = fakeFetch(discordRoutes(githubRoutes([], [
    ['POST', /api\.github\.com\/repos\/me\/test-one\/issues$/, (b) => { created = b; return { number: 17, html_url: 'u/17' }; }],
  ])));
  const ctx = ctxFor();
  await handle(await signed(submit({ title })), env, ctx, { fetch: f, installationToken: async () => 'inst' });
  await Promise.all(ctx.jobs);
  assert.equal(created.title, whole);
  assert.deepEqual(f.find('PATCH', /\/channels\/700$/).map((c) => c.body).filter((b) => 'name' in b), [{ name: whole.slice(0, 100) }]);
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
  // The search before the create finds nothing; the re-check after it finds the issue.
  const base = fakeFetch(discordRoutes(githubRoutes([], [
    ['GET', /test-one\/issues\?state=all.*labels=from-discord/, () => (++looks <= 1 ? [] : [{ number: 17, html_url: 'u/17', body: '<!-- discord-thread: 700 reporter: 42 -->' }])],
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
  assert.deepEqual(JSON.parse(kv.m.get('issue:700')), { repo: 'me/test-one', number: 17, key: 'ONE', by: '<@5>' }, 'the filing is recorded');
  const [receipt, ...more] = base.find('POST', /\/channels\/700\/messages$/);
  assert.deepEqual(more, [], 'one receipt');
  assert.equal(receipt.body.content, MESSAGES.tracked('ONE', 17), 'the player is told');
  assert.deepEqual(receipt.body.message_reference, { message_id: '800', fail_if_not_exists: false });
  assert.equal(base.find('PATCH', /\/channels\/556\/messages\/96$/)[0].body.content, '~~**New post in <#900>:** <#700>~~\n**Filed as ONE #17** by <@5>', 'the card is marked filed, its first line the post\'s mention');
  const pos = (method, re) => at(base, method, re);
  const marked = pos('PATCH', /\/channels\/556\/messages\/96$/);
  assert.ok(pos('PATCH', /\/webhooks\//) < marked && pos('POST', /\/channels\/700\/messages$/) < marked, 'the card last');
  assert.equal(base.find('DELETE', /labels\/discord-lock-700$/).length, 1);
  assert.deepEqual(base.find('PATCH', /\/channels\/700$/).map((c) => c.body), [{ name: '[ONE] [Retail] [Bug] [Bags] Bags overlap after resize' }], 'the post is renamed, and no tag is written');
  assert.ok(pos('DELETE', /labels\/discord-lock-700$/) < pos('PATCH', /\/channels\/700$/), 'the rename after the lock\'s release');
});

test('a late create whose record save never answers still reports in time', async () => {
  let looks = 0;
  const base = fakeFetch(discordRoutes(githubRoutes([], [
    ['GET', /test-one\/issues\?state=all.*labels=from-discord/, () => (++looks <= 1 ? [] : [{ number: 17, html_url: 'u/17', body: '<!-- discord-thread: 700 reporter: 42 -->' }])],
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
    assert.equal(looks, 1, 'the search before the create, and no re-check after 20 s');
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
  const val = formValues(j);
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
    ['a passing failure whose answer quotes " -> 404 "', () => new Response('upstream said -> 404 x', { status: 500 }), /^Could not read the post just now\. Press the button again\.$/],
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
    ['GitHub fails with a 500 whose answer quotes " -> 404 ": press again', record, () => new Response('upstream said -> 404 x', { status: 500 }), cardPress(HELPER),
      /^Could not check whether this post is already on GitHub\. Press the button again\.$/, null],
    ['GitHub fails with a 500 whose answer quotes " -> 410 ": press again', record, () => new Response('upstream said -> 410 x', { status: 500 }), cardPress(HELPER),
      /^Could not check whether this post is already on GitHub\. Press the button again\.$/, null],
    // A 2xx whose body is not JSON: the parser's error quotes a body under
    // 21 characters whole, and that quote is never read as a 404.
    ['GitHub answers 200 with a body that quotes " -> 404 ": press again', record, () => new Response('x -> 404 y', { status: 200 }), cardPress(HELPER),
      /^Could not check whether this post is already on GitHub\. Press the button again\.$/, null],
    // A failed token says nothing about the issue.
    ['the token request answers 410: press again', record, issue(), cardPress(HELPER), /^Could not check whether this post is already on GitHub\./, null, [],
      async () => { throw new Error('GitHub GET /repos/me/test-one/installation -> 410 {}'); }],
    ['a configured repo cannot be searched: press again', {}, issue(), cardPress(HELPER), /^Could not check whether this post is already on GitHub\./, null, status(500)],
    ['a record that is not JSON: press again', { 'issue:700': '{"repo"' }, issue(), cardPress(HELPER), /^Could not check whether this post is already on GitHub\. Press the button again\.$/, null],
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
    ['from the queue card', { ...submit(), member: HELPER, channel_id: '556', data: { ...submit().data, custom_id: 'gh:700:700:0:96' } }, '700', '<@8>'],
    ['by right-click on a later message, the card from the record', submit(), '800', '<@5>'],
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
    ['the reply fails with a 500 whose answer quotes " -> 403 ": nothing is edited', WITH_BUTTON, [['POST', /\/channels\/700\/messages$/, () => new Response('upstream said -> 403 x', { status: 500 })]], 0,
      null, [/^note in the post may not have been sent: .*500/]],
    ['the reply is refused and the edit fails with a 500 whose answer quotes " -> 403 "', WITH_BUTTON, [['POST', /\/channels\/700\/messages$/, refusal], ['PATCH', /\/messages\/950$/, () => new Response('upstream said -> 403 x', { status: 500 })]], 0,
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
    assert.deepEqual(f.find('PATCH', /\/channels\/700$/).map((c) => c.body), [{ name: '[ONE] [Retail] [Bug] [Bags] Bags overlap after resize' }], `${why}: In progress stays`);
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
    if (repo === bad) throw Object.assign(new Error(`GitHub GET /repos/${bad}/installation -> ${s} {"message":"x"}`), { github: { method: 'GET', path: `/repos/${bad}/installation`, status: s } });
    return 'inst';
  };
  const movedIn = () => ({ number: 40, html_url: 'https://github.com/me/test-one/issues/40', repository_url: 'https://api.github.com/repos/me/test-one' });
  // GitHub names the repo in its own casing, which REPOS need not match.
  const caseIn = () => ({ number: 40, html_url: 'https://github.com/Me/Test-One/issues/40', repository_url: 'https://api.github.com/repos/Me/Test-One' });
  // A record from before the filing record kept the issue beside the greeting.
  const legacy = (repo, number) => ({ 'thread:700': JSON.stringify({ issue: { repo, number } }) });
  const elsewhere = legacy('me/test-two', 9);
  const brokenKv = { get: async () => { throw new Error('KV down'); }, put: async () => {} };
  const silentKv = { get: () => new Promise(() => {}), put: async () => {} };
  const made = { repo: 'me/test-one', number: 17, key: 'ONE', by: '<@5>' };
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
    // The filing names the reason: the parser's message, never a quoted 404.
    ['answered 200 with a body that is not JSON and quotes " -> 404 "', elsewhere, () => new Response('x -> 404 y', { status: 200 }), inst, list([]), { refused: 'saved-issue' },
      /^Could not check TWO #9 in me\/test-two \(Unexpected token/, null],
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
      /^Nothing was created: could not read this post's saved record just now\. Try again\.$/, undefined],
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
        /another send or move of this post is running, or one stopped partway\. Wait a few minutes, then send it again\. If it still says this and no issue for this post appears in any repo the bot files into, delete the label discord-lock-700 in me\/test-one, but only if the time in its description is more than an hour ago or it shows no time\. A send ends within 30 seconds and GitHub times out a request after 10 seconds, so the hour is a wide margin past both\. Then send the post again\.$/, why);
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
    const kv = { get: () => (++gets <= 4 ? Promise.resolve(null) : new Promise(() => {})), put: async () => {} };
    const f = fakeFetch(discordRoutes(githubRoutes([], [
      ['POST', /api\.github\.com\/repos\/me\/test-one\/issues$/, () => ({ number: 17, html_url: 'u/17' })],
      // The release ends past 29 s.
      ['DELETE', /api\.github\.com\/repos\/me\/test-one\/labels\/discord-lock-700$/, () => { clock.at(29500); return null; }],
    ])));
    const ctx = ctxFor();
    await handle(await signed(submit()), { ...QUEUE, STATE: kv }, ctx, { fetch: f, installationToken: async () => 'inst', log: () => {} });
    const [res] = await Promise.all(ctx.jobs);
    assert.equal(res.created, 17);
    assert.equal(gets, 4, 'no lookup starts past the release\'s end');
  } finally { clock.restore(); }
});

test('a card lookup after the release that fails is logged, and the record read under the lock is used', async () => {
  let gets = 0;
  // The record read under the lock names card 96; the lookup after the release fails.
  const kv = { get: async (k) => { if (++gets > 4) throw new Error('KV down'); return k === 'thread:700' ? JSON.stringify({ card: '96' }) : null; }, put: async () => {} };
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

test('filing a moved post names its player, ends with the copy line and pings them; filing the old post is refused', async () => {
  let created;
  const kv = fakeKv({ 'movedfrom:700': JSON.stringify({ from: '690', reporter: { name: 'Pat', id: '42', username: 'pat' }, card: '96' }) });
  const f = fakeFetch(discordRoutes(githubRoutes([], [
    ['GET', /\/channels\/700\/messages\/700$/, () => ({ id: '700', content: 'My bags overlap', webhook_id: '61', author: { id: '61', username: 'Pat' }, attachments: [] })],
    ['POST', /api\.github\.com\/repos\/me\/test-one\/issues$/, (b) => { created = b; return { number: 17, html_url: 'u/17' }; }],
    ['PATCH', /\/channels\/556\/messages\/96$/, () => ({})],
  ])));
  const form = submit();
  form.data.custom_id = 'gh:700:700';
  const ctx = ctxFor();
  await handle(await signed(form), { ...QUEUE, STATE: kv }, ctx, { fetch: f, installationToken: async () => 'inst' });
  assert.deepEqual(await Promise.all(ctx.jobs), [{ created: 17, notes: [] }]);
  assert.match(created.body, /^\| Reporter \| \[Pat\]\(https:\/\/discord\.com\/users\/42\) \(`pat`\) \|\n/);
  assert.match(created.body, /\n<!-- discord-copy -->\n<!-- discord-message: 700 -->\n<!-- discord-thread: 700 reporter: 42 -->$/);
  assert.equal(f.find('GET', /\/guilds\/1\/members\//).length, 0, 'the record names the player: no member read');
  const receipt = f.find('POST', /\/channels\/700\/messages$/)[0].body;
  assert.match(receipt.content, /^<@42> Thanks! This is now tracked as ONE #17\./);
  assert.deepEqual(receipt.allowed_mentions, { parse: [], users: ['42'], replied_user: true });
  assert.deepEqual(receipt.message_reference, { message_id: '700', fail_if_not_exists: false });
  assert.equal(f.find('PATCH', /\/channels\/556\/messages\/96$/).length, 1, 'the card the move recorded is marked filed');

  const old = fakeFetch(discordRoutes(githubRoutes()));
  const oldCtx = ctxFor();
  await handle(await signed(submit()), { ...env, STATE: fakeKv({ 'movedto:700': '{"to":"990"}' }) }, oldCtx, { fetch: old, installationToken: async () => 'inst' });
  assert.deepEqual(await Promise.all(oldCtx.jobs), [{ refused: 'moved' }]);
  assert.equal(old.find('PATCH', /\/webhooks\//)[0].body.content, 'Nothing was created: this post was moved to https://discord.com/channels/1/990; send that one.');
  assert.equal(old.find('POST', /\/issues$/).length, 0);

  // The bot's copy whose record KV does not show yet: refused, not filed as the webhook.
  const early = fakeFetch(discordRoutes(githubRoutes([], [
    ['GET', /\/channels\/700\/messages\/700$/, () => ({ id: '700', content: 'My bags overlap', webhook_id: '61', application_id: 'app', author: { id: '61', username: 'Pat' }, attachments: [] })],
  ])));
  const earlyForm = submit();
  earlyForm.data.custom_id = 'gh:700:700';
  const earlyCtx = ctxFor();
  await handle(await signed(earlyForm), { ...env, STATE: fakeKv() }, earlyCtx, { fetch: early, installationToken: async () => 'inst' });
  assert.deepEqual(await Promise.all(earlyCtx.jobs), [{ refused: 'copy-record' }]);
  assert.match(early.find('PATCH', /\/webhooks\//)[0].body.content, /^Nothing was created: this post is a copy the bot moved here, and its record movedfrom:700 is not readable yet\./);
  assert.equal(early.find('POST', /\/issues$/).length, 0);

  // A reply in such a copy, which the scan marked: refused too, so no issue
  // names a copy staff may delete. A reply in any other post files as today.
  const orphan = fakeFetch(discordRoutes(githubRoutes()));
  const orphanCtx = ctxFor();
  await handle(await signed(submit()), { ...env, STATE: fakeKv({ 'thread:700': JSON.stringify({ skipped: MOVED_HERE }) }) }, orphanCtx, { fetch: orphan, installationToken: async () => 'inst' });
  assert.deepEqual(await Promise.all(orphanCtx.jobs), [{ refused: 'copy-record' }]);
  assert.equal(orphan.find('POST', /\/issues$/).length, 0);
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

test('a filing whose search ends late still creates the issue', async () => {
  const clock = shiftClock();
  try {
    const base = fakeFetch(discordRoutes(githubRoutes([], [
      ['POST', /api\.github\.com\/repos\/me\/test-one\/issues$/, () => ({ number: 17, html_url: 'u/17' })],
    ])));
    // The search and the read of the message end at second eight of fifteen.
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
const checkCmd = (member, over = {}) => ({ type: 2, member, channel_id: '555', guild_id: '1', application_id: 'app', token: 'tok', data: { name: CHECK_COMMAND }, ...over });

test('WT1: /bot-check is for moderators of this server, answers privately at once, and posts only to a verified moderator channel', async () => {
  for (const [why, member, envOver, guild, said] of [
    ['a player', PLAYER, {}, '1', /^Only moderators and admins can check the bot setup\.$/],
    ['a moderator of another server', MOD, {}, '2', /^This command checks only the server the bot is set up for\.$/],
    ['a moderator with GUILD_ID unset', MOD, { GUILD_ID: '' }, '1', /^The bot's GUILD_ID is not set to a server id, so it can check nothing\./],
    ['a moderator with GUILD_ID malformed', MOD, { GUILD_ID: '1x' }, '1', /^The bot's GUILD_ID is not set to a server id, so it can check nothing\./],
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
    // The private reply pings no one, whoever it names.
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
  const KEY_LINE = 'The bot is not set up yet: REPOS key "O NE" is not made of letters and digits: write each key in A to Z, a to z and 0 to 9 only, like KE.';
  const badForums = { FORUM_CHANNEL_IDS: '', FORUMS: '{not json' };
  const badRepos = { ...badForums, REPOS: '' };
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
    ['a moderator submit, a REPOS key that is not letters and digits', { REPOS: '{"O NE":"me/test-one"}' }, sub(MOD), KEY_LINE],
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

test('a failed member read at filing is logged, unless the member left (404)', async () => {
  for (const [why, answer, logged] of [
    ['the member left', () => new Response('{"message":"Unknown Member"}', { status: 404 }), false],
    ['a 500 whose answer quotes " -> 404 "', () => new Response('upstream said -> 404 x', { status: 500 }), true],
  ]) {
    const lines = [];
    const f = fakeFetch(discordRoutes(githubRoutes([], [
      ['GET', /\/guilds\/1\/members\/42$/, answer],
      ['POST', /api\.github\.com\/repos\/me\/test-one\/issues$/, () => ({ number: 17, html_url: 'u/17' })],
    ])));
    const ctx = ctxFor();
    await handle(await signed(submit()), env, ctx, { fetch: f, installationToken: async () => 'inst', log: (s) => lines.push(s) });
    const [res] = await Promise.all(ctx.jobs);
    assert.equal(res.created, 17, why);
    assert.equal(lines.some((s) => /^member read failed: /.test(s)), logged, `${why}: ${lines.join(' | ')}`);
  }
});

test('Send to GitHub pre-selects the repo from the post\'s repo tag, else the only repo, else none', async () => {
  const forum = { ...FORUM, available_tags: [...FORUM.available_tags, { id: 'r-one', name: 'ONE' }, { id: 'r-two', name: 'two' }] };
  const FIXED = { FORUM_CHANNEL_IDS: '', FORUMS: '{"900":{"client":"Forever","type":"Feature"}}' };
  for (const [why, tags, over, want] of [
    ['one repo tag', ['t-bug', 'r-two'], {}, 'TWO'],
    ['one repo tag, in a forum with its own client and type', ['r-two'], FIXED, 'TWO'],
    ['two repo tags that disagree', ['r-one', 'r-two'], {}, undefined],
    ['no repo tag', ['t-bug'], {}, undefined],
    ['one repo in REPOS', ['t-bug'], { REPOS: '{"ONE":"me/test-one"}' }, 'ONE'],
  ]) {
    const f = fakeFetch(discordRoutes([
      ['GET', /\/channels\/700$/, () => ({ id: '700', parent_id: '900', name: 'x', applied_tags: tags })],
      ['GET', /\/channels\/900$/, () => forum],
    ]));
    const e = { ...env, REPO_TAGS: '{"ONE":"ONE","Two":"two"}', ...over };
    const j = await (await handle(await signed({ type: 2, member: MOD, channel_id: '700', data: { name: COMMAND_NAME, target_id: '800' } }), e, ctxFor(), { fetch: f })).json();
    assert.equal(formValues(j).repo, want, why);
    assert.deepEqual(j.data.components[0].component.options.map((o) => o.value), Object.keys(JSON.parse(e.REPOS)), `${why}: every repo offered`);
  }
  // A repo tag names the repo only, never the client or the type.
  const ui = { ...FORUM, available_tags: [...FORUM.available_tags, { id: 'r-ui', name: 'Retail UI Bug' }] };
  const fu = fakeFetch(discordRoutes([
    ['GET', /\/channels\/700$/, () => ({ id: '700', parent_id: '900', name: 'x', applied_tags: ['r-ui'] })],
    ['GET', /\/channels\/900$/, () => ui],
  ]));
  const ju = await (await handle(await signed({ type: 2, member: MOD, channel_id: '700', data: { name: COMMAND_NAME, target_id: '800' } }), { ...env, REPO_TAGS: '{"Retail UI Bug":"ONE"}' }, ctxFor(), { fetch: fu })).json();
  // A blank text input carries no value.
  const vu = formValues(ju);
  assert.deepEqual([vu.repo, vu.client, vu.type], ['ONE', undefined, undefined]);
  // A mapping to a key REPOS no longer holds is no repo tag: the tag gives
  // the client and type again.
  const js = await (await handle(await signed({ type: 2, member: MOD, channel_id: '700', data: { name: COMMAND_NAME, target_id: '800' } }), { ...env, REPO_TAGS: '{"Retail UI Bug":"OLD"}' }, ctxFor(), { fetch: fu })).json();
  const vs = formValues(js);
  assert.deepEqual([vs.repo, vs.client, vs.type], [undefined, 'Retail', 'Bug']);
});

test('Send to GitHub offers only usable repo keys', async () => {
  const req = { type: 2, member: MOD, channel_id: '700', data: { name: COMMAND_NAME, target_id: '800' } };
  // "KE" beside "ke" and a 100-character key for other repos: only the key
  // the submit reads back as itself, short enough for a title, is offered.
  const both = await (await handle(await signed(req), { ...env, REPOS: JSON.stringify({ KE: 'me/test-one', ke: 'me/test-two', ['K'.repeat(100)]: 'me/test-two' }), LOCK_REPO: 'me/test-one' }, ctxFor(), { fetch: fakeFetch(discordRoutes()) })).json();
  assert.deepEqual(both.data.components[0].component.options.map((o) => o.value), ['KE']);
  // A typed or stale choice of a key the dropdown does not offer files nothing.
  const long = 'K'.repeat(100);
  const sub = await (await handle(await signed(submit({ repo: long })), { ...env, REPOS: JSON.stringify({ ONE: 'me/test-one', [long]: 'me/test-two' }) }, ctxFor(), { fetch: fakeFetch([]) })).json();
  assert.match(sub.data.content, /^Nothing was created\. The repo chosen is no longer in REPOS: pick it again\./);
});

// ---- Moving a post -------------------------------------------------------------

const MOVE_ENV = {
  ...env, FORUM_CHANNEL_IDS: '', GUILD_ID: '1', QUEUE_CHANNEL_ID: '556', APPROVED_ROLE_IDS: '77', CHECKLIST_FORUM_ID: '950',
  FORUMS: '{"900":{"client":"Retail","type":"Bug"},"901":{"type":"Feature"},"902":{"client":"Forever","type":"Bug"}}',
  REPO_TAGS: '{"ONE":"ONE","TWO":"TWO"}',
};
// The server's channel list: the queue channel, and the three player forums
// with their tags.
const CHANNELS = [
  { id: '556', type: 0, name: 'queue' },
  { id: '900', type: 15, name: 'retail-bugs', available_tags: FORUM.available_tags },
  { id: '901', type: 15, name: 'feedback', available_tags: [
    { id: 'f-retail', name: 'Retail' }, { id: 'f-forever', name: 'Forever' }, { id: 'f-feat', name: 'Feedback' }, { id: 'f-staff', name: 'Staff note' },
    { id: 'f-tri', name: 'Triaged' }, { id: 'f-acc', name: 'Accepted' }, { id: 'f-one', name: 'ONE' }, { id: 'f-two', name: 'TWO' },
  ] },
  { id: '902', type: 15, name: 'forever-bugs', available_tags: [{ id: 'v-bug', name: 'Bug' }, { id: 'v-tri', name: 'Triaged' }, { id: 'v-acc', name: 'Accepted' }, { id: 'v-two', name: 'TWO' }] },
];
const answerOf = (v) => (typeof v === 'function' ? v() : v);
// A move's world: post 700 in forum 900, filed nowhere, with the server's
// forums, the bot's webhook in each, and the lock repo. `edit(s)` changes any
// answer first; an answer may be a function, called at each request, and
// `s.extra` routes go before the rest.
function moveWorld(edit = () => {}) {
  const s = {
    post: { id: '700', parent_id: '900', name: 'Bags overlap', applied_tags: ['t-retail', 't-bug', 't-staff'], thread_metadata: { archived: false, locked: false } },
    first: { id: '700', content: 'My bags overlap', author: { id: '42', username: 'pat', global_name: 'Pat', avatar: 'abc', discriminator: '0' }, attachments: [] },
    said: [],
    member: { nick: 'Patty' },
    channels: CHANNELS,
    hooks: [{ id: '61', type: 1, application_id: 'app', token: 'wtok' }],
    one: [],
    two: [],
    files: {},
    made: { id: '990', channel_id: '990' },
    card: { id: '97' },
    lock: {},
    claim: () => new Response('{}', { status: 201 }),
    kv: {},
    putFails: '',
    putHangs: '',
    extra: [],
  };
  edit(s);
  const kv = fakeKv(s.kv);
  const put = kv.put;
  kv.put = async (k, v) => {
    if (k === s.putFails) throw new Error('KV down');
    if (k === s.putHangs) return new Promise(() => {});
    return put(k, v);
  };
  const f = fakeFetch([
    ...s.extra,
    ['GET', /\/channels\/700$/, () => answerOf(s.post)],
    ['GET', /\/channels\/700\/messages\/700$/, () => answerOf(s.first)],
    ['GET', /\/channels\/700\/messages\?limit=100$/, () => answerOf(s.said)],
    ['GET', /\/users\/@me$/, () => ({ id: 'b' })],
    ['GET', /\/guilds\/1\/channels$/, () => answerOf(s.channels)],
    ['GET', /\/guilds\/1\/members\/42$/, () => answerOf(s.member)],
    ['GET', /\/channels\/90\d\/webhooks$/, () => answerOf(s.hooks)],
    ['POST', /\/channels\/90\d\/webhooks$/, () => ({ id: '62', type: 1, application_id: 'app', token: 'new' })],
    ['GET', /^https:\/\/cdn\.example\//, (b, url) => answerOf(s.files[url])],
    ['POST', /\/webhooks\/\d+\/\w+\?wait=true$/, () => answerOf(s.made)],
    ['POST', /\/channels\/(700|990)\/messages$/, () => ({ id: 'm1' })],
    ['PATCH', /\/channels\/700$/, () => answerOf(s.lock)],
    ['PATCH', /\/channels\/556\/messages\/96$/, () => ({})],
    ['POST', /\/channels\/556\/messages$/, () => answerOf(s.card)],
    ['PATCH', /\/webhooks\/app\/itok/, () => ({})],
    ['GET', /api\.github\.com\/repos\/me\/test-one\/issues\?state=all.*labels=from-discord/, () => answerOf(s.one)],
    ['GET', /api\.github\.com\/repos\/me\/test-two\/issues\?state=all.*labels=from-discord/, () => answerOf(s.two)],
    ['POST', /api\.github\.com\/repos\/me\/test-one\/labels$/, () => answerOf(s.claim)],
    ['DELETE', /api\.github\.com\/repos\/me\/test-one\/labels\/discord-lock-700$/, () => null],
    // A filed post's issue (`s.issue`), its comments, the target repo, the
    // transfer, the issue's edits and its checklist thread 960.
    ['GET', /api\.github\.com\/repos\/me\/test-(one|two)\/issues\/\d+$/, () => (s.issue ? answerOf(s.issue) : new Response('{}', { status: 404 }))],
    ['GET', /api\.github\.com\/repos\/me\/test-(one|two)\/issues\/\d+\/comments\?/, () => answerOf(s.comments || [])],
    ['GET', /api\.github\.com\/repos\/me\/test-two$/, () => answerOf(s.repo || { node_id: 'R_2' })],
    ['POST', /api\.github\.com\/graphql$/, () => answerOf(s.gql)],
    ['PATCH', /api\.github\.com\/repos\/me\/test-(one|two)\/issues\/\d+$/, () => answerOf(s.patch || {})],
    ['POST', /api\.github\.com\/repos\/me\/test-(one|two)\/issues\/\d+\/labels$/, () => answerOf(s.addLabels || [])],
    ['DELETE', /api\.github\.com\/repos\/me\/test-(one|two)\/issues\/\d+\/labels\//, () => null],
    ['PATCH', /\/channels\/960$/, () => answerOf(s.open || {})],
    ['PATCH', /\/channels\/960\/messages\/960$/, () => answerOf(s.firstEdit || {})],
  ]);
  return { f, s, kv };
}
// A filed post: issue:700 names ONE #40, whose title, labels and footer are
// the bot's, with its checklist record naming thread 960. The post shows
// Triaged and Accepted.
const ISSUE_URL = 'https://github.com/me/test-one/issues/40';
const ISSUE_BODY = '| Reporter | Pat |\n\n## Report\n\n> My bags overlap\n\n<!-- discord-message: 700 -->\n<!-- discord-thread: 700 reporter: 42 -->';
const filedIssue = (over = {}) => ({
  number: 40, state: 'open', node_id: 'I_40', html_url: ISSUE_URL, repository_url: 'https://api.github.com/repos/me/test-one',
  title: '[ONE] [Retail] [Bug] [Bags] Bags overlap', body: ISSUE_BODY,
  labels: [{ name: 'from-discord' }, { name: 'type: bug' }, { name: 'client: retail' }], ...over,
});
const RECORD = { id: 3, user: { login: 'github-actions[bot]' }, body: checklistBody({ state: '960', guildId: '1', since: 1, issueUrl: ISSUE_URL }) };
function filedWorld(edit = () => {}, issue = {}) {
  return moveWorld((s) => {
    s.kv = { 'issue:700': JSON.stringify({ repo: 'me/test-one', number: 40, key: 'ONE', by: '<@5>' }) };
    s.issue = filedIssue(issue);
    s.comments = [RECORD];
    s.post.applied_tags = ['t-retail', 't-bug', 's-tri', 't-acc'];
    edit(s);
  });
}
const moveClick = (member = MOD) => ({ type: 2, member, guild_id: '1', channel_id: '700', data: { name: 'Move post', target_id: '800' } });
const movePress = (member = HELPER) => ({ type: 3, member, guild_id: '1', channel_id: '556', message: { id: '96' }, data: { custom_id: 'move:700', component_type: 2 } });

test('the Move form offers the other forums of this server, pre-selects what it can, and refuses where it cannot move', async () => {
  for (const [why, req, edit, envOver, want] of [
    ['a card press', movePress(), null, {}, { custom: 'mv:700:96::Retail', forum: undefined, client: 'Retail' }],
    ['a right-click', moveClick(), null, {}, { custom: 'mv:700:0::Retail', forum: undefined, client: 'Retail' }],
    ['one other forum: chosen', moveClick(), null, { FORUMS: '{"900":{"client":"Retail"},"901":{}}' }, { forum: '901' }],
    // FORUMS is outside data: an id there may be a channel of another
    // server, which this server's list lacks, or not be a forum.
    ['a FORUMS forum of another server is not offered', moveClick(), (s) => { s.channels = CHANNELS.filter((c) => c.id !== '902'); }, {}, { forum: '901' }],
    ['a FORUMS channel that is not a forum is not offered', moveClick(), (s) => { s.channels = CHANNELS.map((c) => (c.id === '902' ? { ...c, type: 0 } : c)); }, {}, { forum: '901' }],
    ['the client from the tags', moveClick(), (s) => { s.post.applied_tags = ['t-forever']; }, { FORUMS: '{"900":{},"901":{},"902":{}}' }, { client: 'Forever' }],
    ['a post outside FORUMS', moveClick(), (s) => { s.post.parent_id = '999'; }, {}, /^This only works on posts in the forums the bot is set up for\.$/],
    ['no other forum', moveClick(), null, { FORUMS: '{"900":{}}' }, /^There is no other forum to move this post to\.$/],
    ['no other forum in this server', moveClick(), (s) => { s.channels = CHANNELS.filter((c) => c.id === '900'); }, {}, /^There is no other forum to move this post to\.$/],
    ['a player right-click', moveClick(PLAYER), null, {}, /^Only moderators and admins can move posts\.$/],
    ['a player card press', movePress(PLAYER), null, {}, /^Only moderators and approved roles can move posts\.$/],
    ['the forum list fails', moveClick(), (s) => { s.channels = () => new Response('{}', { status: 500 }); }, {}, /^Could not read the forums just now\. Try again\.$/],
  ]) {
    const w = moveWorld(edit || (() => {}));
    const j = await (await handle(await signed(req), { ...MOVE_ENV, STATE: w.kv, ...envOver }, ctxFor(), { fetch: w.f, log: () => {} })).json();
    if (want instanceof RegExp) {
      assert.match(j.data.content, want, why);
      continue;
    }
    assert.equal(j.type, 9, why);
    if (want.custom) assert.equal(j.data.custom_id, want.custom, why);
    const v = formValues(j);
    for (const k of ['forum', 'client']) if (k in want) assert.equal(v[k], want[k], `${why}: ${k}`);
  }
  const w = moveWorld();
  const j = await (await handle(await signed(movePress()), { ...MOVE_ENV, STATE: w.kv }, ctxFor(), { fetch: w.f })).json();
  const field = (id) => j.data.components.find((c) => c.component.custom_id === id);
  assert.equal(j.data.title, 'Move post');
  assert.deepEqual(field('forum').component.options.map((o) => [o.value, o.label]), [['901', '#feedback'], ['902', '#forever-bugs']], 'the other forums, by name');
  assert.deepEqual([field('client').component.required, field('client').description], [false, 'Used for a forum with no client of its own']);
  // Two forums of one name: each label carries its forum's id.
  const twin = moveWorld((s) => { s.channels = CHANNELS.map((c) => (c.id === '901' || c.id === '902' ? { ...c, name: 'bugs' } : c)); });
  const t = await (await handle(await signed(movePress()), { ...MOVE_ENV, STATE: twin.kv }, ctxFor(), { fetch: twin.f })).json();
  assert.deepEqual(t.data.components[0].component.options.map((o) => o.label), ['#bugs (901)', '#bugs (902)']);
});

test('the Move form pre-selects the repo from the filing record and the client from the post\'s name, and carries both in its id', async () => {
  const TWO = JSON.stringify({ repo: 'me/test-two', number: 12, key: 'TWO' });
  const DUO_REPOS = '{"ONE":"me/test-one","TWO":"me/test-two","DUO":"me/test-two"}';
  for (const [why, kv, envOver, want, after = null] of [
    ['the record\'s key', { 'issue:700': TWO }, {}, { repo: 'TWO', custom: 'mv:700:0:TWO:Retail' }],
    ['an alias key that still names its repo', { 'issue:700': JSON.stringify({ repo: 'me/test-two', number: 12, key: 'DUO' }) }, { REPOS: DUO_REPOS }, { repo: 'DUO', custom: 'mv:700:0:DUO:Retail' }],
    ['the scan record\'s issue', { 'thread:700': JSON.stringify({ issue: JSON.parse(TWO) }) }, {}, { repo: 'TWO', custom: 'mv:700:0:TWO:Retail' }],
    ['no record', {}, {}, { repo: undefined, custom: 'mv:700:0::Retail' }],
    ['a record read that fails', {}, {}, { repo: undefined, custom: 'mv:700:0::Retail' }, (w) => { w.kv.get = async () => { throw new Error('KV down'); }; }],
    ['a record read slower than the form', {}, {}, { repo: undefined, custom: 'mv:700:0::Retail' }, (w) => { w.kv.get = () => new Promise(() => {}); }],
    ['a record whose repo no key names', { 'issue:700': JSON.stringify({ repo: 'owner/three', number: 9, key: 'THREE' }) }, {}, { repo: undefined, custom: 'mv:700:0::Retail' }],
    ['one usable key: no Repo field', { 'issue:700': TWO }, { REPOS: '{"ONE":"me/test-one"}' }, { fields: ['forum', 'client'], custom: 'mv:700:0::Retail' }],
    ['no usable key: no Repo field', {}, { REPOS: '{"old":"me/test-one"}' }, { fields: ['forum', 'client'], custom: 'mv:700:0::Retail' }],
    ['the field order with two keys', {}, {}, { fields: ['forum', 'repo', 'client'] }],
  ]) {
    const w = moveWorld((s) => { s.kv = kv; });
    if (after) after(w);
    const j = await (await handle(await signed(moveClick()), { ...MOVE_ENV, STATE: w.kv, ...envOver }, ctxFor(), { fetch: w.f, log: () => {} })).json();
    assert.equal(j.type, 9, why);
    if ('custom' in want) assert.equal(j.data.custom_id, want.custom, why);
    if ('repo' in want) assert.equal(formValues(j).repo, want.repo, why);
    if (want.fields) assert.deepEqual(j.data.components.map((c) => c.component.custom_id), want.fields, why);
  }
  const repo = (await (await handle(await signed(moveClick()), { ...MOVE_ENV, STATE: moveWorld().kv }, ctxFor(), { fetch: moveWorld().f })).json())
    .data.components.find((c) => c.component.custom_id === 'repo');
  assert.deepEqual([repo.label, repo.component.required, repo.description, repo.component.options.map((o) => o.value)],
    ['Repo', false, 'Used only for a post already on GitHub; another repo moves its issue there', ['ONE', 'TWO']]);
  // The client: a filed post named as its issue's title shows the issue's
  // client. A post with no filing record keeps phase 1's, whatever its name.
  for (const [why, name, kv, client] of [
    ['a filed post named as its issue', '[ONE] [All] [Bug] [UI] Title', { 'issue:700': TWO }, 'All'],
    ['an unfiled post with a name of that shape', '[ONE] [All] [Bug] [UI] Title', {}, 'Retail'],
    ['any other name', 'Bags overlap', { 'issue:700': TWO }, 'Retail'],
  ]) {
    const w = moveWorld((s) => { s.post.name = name; s.kv = kv; });
    const j = await (await handle(await signed(movePress()), { ...MOVE_ENV, STATE: w.kv }, ctxFor(), { fetch: w.f })).json();
    assert.equal(formValues(j).client, client, why);
    assert.equal(j.data.custom_id, `mv:700:96:${kv['issue:700'] ? 'TWO' : ''}:${client}`, why);
  }
});

test('every entry point refuses another server, or a GUILD_ID that names none, before reading anything', async () => {
  const sendPress = { type: 3, member: MOD, guild_id: '1', channel_id: '556', message: { id: '96' }, data: { custom_id: 'send:700', component_type: 2 } };
  const sendClick = { type: 2, member: MOD, guild_id: '1', channel_id: '700', data: { name: COMMAND_NAME, target_id: '800' } };
  for (const [why, guild, envOver, want] of [
    ['another server', '2', {}, 'This only works on posts in the forums the bot is set up for.'],
    ['GUILD_ID unset', '1', { GUILD_ID: '' }, "The bot is not set up yet: GUILD_ID is not set to the server's id (digits only, no spaces)."],
  ]) {
    for (const [entry, req] of [['right-click Send to GitHub', sendClick], ['a send button', sendPress], ['a Send to GitHub submit', submit()],
      ['right-click Move post', moveClick()], ['a Move button', movePress(MOD)]]) {
      const w = moveWorld();
      const j = await (await handle(await signed({ ...req, guild_id: guild }), { ...MOVE_ENV, STATE: w.kv, ...envOver }, ctxFor(), { fetch: w.f })).json();
      assert.equal(j.data.content, want, `${why}: ${entry}`);
      assert.equal(w.f.calls.length, 0, `${why}: ${entry}: nothing read`);
    }
  }
  // A setup problem is for staff: a player gets the entry point's own refusal,
  // as WT6 has it for GUILD_ID.
  const w = moveWorld();
  const j = await (await handle(await signed(movePress(PLAYER)), { ...MOVE_ENV, STATE: w.kv, GUILD_ID: '' }, ctxFor(), { fetch: w.f })).json();
  assert.equal(j.data.content, 'Only moderators and approved roles can move posts.');
  assert.equal(w.f.calls.length, 0);
});

const moveSubmit = (values = {}, { custom = 'mv:700:96', member = HELPER } = {}) => ({
  type: 5, member, guild_id: '1', channel_id: '556', application_id: 'app', token: 'itok',
  data: { custom_id: custom, components: Object.entries({ forum: '901', client: 'Retail', ...values })
    .map(([custom_id, value]) => ({ type: 18, component: { type: 3, custom_id, values: value === null ? [] : [value] } })) },
});
// Submits the Move form and waits for its job: the job's result, the KV, the
// first answer and the moderator's reply.
async function runMove(w, form = moveSubmit(), envOver = {}, depsOver = {}) {
  const ctx = ctxFor();
  const r = await handle(await signed(form), { ...MOVE_ENV, STATE: w.kv, ...envOver }, ctx, { fetch: w.f, installationToken: async () => 'inst', log: () => {}, ...depsOver });
  const [res] = await Promise.all(ctx.jobs);
  const told = w.f.find('PATCH', /\/webhooks\/app\/itok/)[0];
  return { res, kv: w.kv, answer: await r.json(), told: told && told.body.content };
}
// The move's replies for post 700 moved to 990: done, and stopped partway
// (each step not done follows on its own line).
const MOVED = 'Moved to https://discord.com/channels/1/990 from https://discord.com/channels/1/700.';
const PARTWAY = 'The move stopped partway: https://discord.com/channels/1/990 was made from https://discord.com/channels/1/700. Not done:';

test('a Move form with a forum or client the move cannot use, or from a player, or with no KV bound, moves nothing and calls nothing', async () => {
  for (const [why, form, want, envOver = {}] of [
    // FORUMS as it is now: a forum dropped while the form was open is refused here.
    ['a forum outside FORUMS', moveSubmit({ forum: '903' }), /^Nothing was moved\. Pick a forum the bot is set up for\.$/],
    ['no client for a forum with none of its own', moveSubmit({ client: null }), /^Nothing was moved\. Pick a client: <#901> has no client of its own\.$/],
    ['a player', moveSubmit({}, { member: PLAYER }), /^Only moderators and approved roles can move posts\.$/],
    ['another server', { ...moveSubmit(), guild_id: '2' }, /^This only works on posts in the forums the bot is set up for\.$/],
    ['GUILD_ID unset', moveSubmit(), /^The bot is not set up yet: GUILD_ID is not set to the server's id/, { GUILD_ID: '' }],
    ['no STATE namespace', moveSubmit(), /^Nothing was moved: the STATE KV namespace is not bound, so the move could not be recorded\. /, { STATE: undefined }],
  ]) {
    const w = moveWorld();
    const ctx = ctxFor();
    const j = await (await handle(await signed(form), { ...MOVE_ENV, STATE: w.kv, ...envOver }, ctx, { fetch: w.f })).json();
    assert.match(j.data.content, want, why);
    assert.equal(ctx.jobs.length, 0, why);
    assert.equal(w.f.calls.length, 0, why);
  }
});

test('an unfiled post moves: a webhook copy in the new forum, both records, the ping, the old post locked and the card moved', async () => {
  const w = moveWorld((s) => {
    s.first.attachments = [{ id: 'a1', filename: 'bags.png', description: 'the bags', size: 5, url: 'https://cdn.example/a1' }];
    s.files['https://cdn.example/a1'] = new Response('12345');
  });
  const { res, kv, answer, told } = await runMove(w);
  const f = w.f;
  assert.deepEqual(answer, { type: 5, data: { flags: 64 } });
  assert.deepEqual(res, { moved: '990', notes: [] });
  assert.ok(at(f, 'POST', /test-one\/labels$/) < at(f, 'GET', /\/channels\/700$/), 'the lock before any read of the post');
  assert.ok(at(f, 'POST', /\?wait=true$/) < at(f, 'POST', /\/channels\/700\/messages$/), 'the create before the old post\'s note');
  assert.ok(at(f, 'POST', /\?wait=true$/) < at(f, 'PATCH', /\/channels\/700$/), 'the create before the old post\'s lock');
  assert.deepEqual(f.find('POST', /test-one\/labels$/).map((c) => c.body.name), ['discord-lock-700'], 'one lock, the old post\'s');
  assert.ok(at(f, 'PATCH', /\/channels\/556\/messages\/96$/) < at(f, 'PATCH', /\/channels\/700$/), 'the card before the old post\'s lock');
  assert.equal(f.find('POST', /\/channels\/556\/messages$/).length, 0, 'the card edited, no second one');
  assert.ok(at(f, 'PATCH', /\/webhooks\/app\/itok/) < at(f, 'DELETE', /discord-lock-700$/), 'the reply before the release');
  const sent = f.find('POST', /\?wait=true$/)[0];
  assert.match(sent.url, /\/webhooks\/61\/wtok\?wait=true$/, 'the bot\'s own webhook');
  assert.deepEqual(sent.body, {
    payload: {
      thread_name: 'Bags overlap', applied_tags: ['f-retail', 'f-staff'], content: 'My bags overlap',
      username: 'Patty', avatar_url: 'https://cdn.discordapp.com/avatars/42/abc.png', allowed_mentions: { parse: [] },
      attachments: [{ id: 0, filename: 'bags.png', description: 'the bags' }],
    },
    files: ['bags.png'],
  });
  assert.deepEqual(JSON.parse(kv.m.get('movedfrom:990')), { from: '700', reporter: { name: 'Patty', id: '42', username: 'pat', avatar: 'https://cdn.discordapp.com/avatars/42/abc.png' }, card: '96' });
  assert.deepEqual(JSON.parse(kv.m.get('movedto:700')), { to: '990' });
  const here = f.find('POST', /\/channels\/990\/messages$/)[0].body;
  assert.equal(here.content, 'Moved here from https://discord.com/channels/1/700 by <@8>. First posted by <@42>.');
  assert.deepEqual(here.allowed_mentions, { parse: [], users: ['42'] });
  const note = f.find('POST', /\/channels\/700\/messages$/)[0].body;
  assert.equal(note.content, 'This post moved to https://discord.com/channels/1/990 (moved by <@8>).');
  assert.deepEqual(note.allowed_mentions, { parse: [], users: [] }, 'the mover\'s mention pings no one');
  assert.deepEqual(f.find('PATCH', /\/channels\/700$/)[0].body, { locked: true, archived: true });
  const card = f.find('PATCH', /\/channels\/556\/messages\/96$/)[0].body;
  assert.equal(card.content, '**New post in <#901>:** <#990>\nby <@42> (`pat`) · Feature · Retail\nMoved by <@8>');
  assert.deepEqual(card.components[0].components.map((b) => b.custom_id || b.url), ['send:990', 'move:990', 'https://discord.com/channels/1/990']);
  assert.equal(told, MOVED);
});

test('a move with no card to edit, or whose card is gone, posts a new queue card for the new post', async () => {
  for (const [why, form, edit, edits] of [
    // A right-click before the scan carded the post: there is no card.
    ['no card known', moveSubmit({}, { custom: 'mv:700', member: MOD }), null, 0],
    ['the card deleted', moveSubmit(), (s) => { s.extra = [['PATCH', /\/channels\/556\/messages\/96$/, () => new Response('{"message":"Unknown Message"}', { status: 404 })]]; }, 1],
  ]) {
    const w = moveWorld(edit || (() => {}));
    const { told, kv } = await runMove(w, form);
    assert.equal(told, MOVED, why);
    assert.equal(w.f.find('PATCH', /\/channels\/556\/messages\/96$/).length, edits, why);
    const posted = w.f.find('POST', /\/channels\/556\/messages$/);
    assert.equal(posted.length, 1, why);
    assert.deepEqual(posted[0].body.components[0].components.map((b) => b.custom_id || b.url), ['send:990', 'move:990', 'https://discord.com/channels/1/990'], why);
    assert.equal(JSON.parse(kv.m.get('movedfrom:990')).card, '97', `${why}: the new card is the copy's`);
  }
  // The edit and the new card both refused: the record names no card, not
  // the one Discord would not edit.
  const both = moveWorld((s) => { s.extra = [['PATCH', /\/channels\/556\/messages\/96$/, refusal], ['POST', /\/channels\/556\/messages$/, refusal]]; });
  const bothRun = await runMove(both);
  assert.equal(bothRun.told, `${PARTWAY}\n- queue card for the new post`);
  assert.equal('card' in JSON.parse(bothRun.kv.m.get('movedfrom:990')), false);
  // No queue channel set, though the form names the old post's card: the
  // card step is skipped with no line, no queue call is made, and the copy's
  // record names no card, so a later filing marks none.
  // A right-click carries no card: the old post's card comes from the scan's
  // record, else from the move record of a post moved before, and is edited.
  for (const [why, kv] of [
    ['the scan\'s record', { 'thread:700': JSON.stringify({ card: '96' }) }],
    ['the move record', { 'movedfrom:700': JSON.stringify({ from: '690', reporter: { name: 'Pat', id: '42', username: 'pat' }, card: '96' }) }],
  ]) {
    const w = moveWorld((s) => { s.kv = kv; });
    const { told } = await runMove(w, moveSubmit({}, { custom: 'mv:700', member: MOD }));
    assert.equal(told, MOVED, why);
    assert.equal(w.f.find('PATCH', /\/channels\/556\/messages\/96$/).length, 1, `${why}: that card edited`);
    assert.equal(w.f.find('POST', /\/channels\/556\/messages$/).length, 0, `${why}: no second card`);
  }
  const off = moveWorld();
  const offRun = await runMove(off, moveSubmit(), { QUEUE_CHANNEL_ID: '' });
  assert.equal(offRun.told, MOVED);
  assert.equal(off.f.calls.filter((c) => /\/channels\/556\//.test(c.url)).length, 0, 'no queue request');
  assert.equal('card' in JSON.parse(offRun.kv.m.get('movedfrom:990')), false);
});

test('the move uses the bot\'s own webhook, makes one when the forum has none, and says when it lacks Manage Webhooks', async () => {
  for (const [why, hooks, made, said, creates] of [
    ['its own, among others', [{ id: '60', type: 1, application_id: 'other', token: 'x' }, { id: '61', type: 1, application_id: 'app', token: 'wtok' }], 0, /^Moved to /, 1],
    ['none of its own', [{ id: '60', type: 1, application_id: 'other', token: 'x' }], 1, /^Moved to /, 1],
    ['no Manage Webhooks', () => new Response('{"message":"Missing Permissions"}', { status: 403 }), 0, /^Nothing was moved: the bot lacks Manage Webhooks in <#901>\.$/, 0],
  ]) {
    const w = moveWorld((s) => { s.hooks = hooks; });
    const { told } = await runMove(w);
    assert.match(told, said, why);
    assert.equal(w.f.find('POST', /\/channels\/901\/webhooks$/).length, made, why);
    assert.equal(w.f.find('POST', /\?wait=true$/).length, creates, why);
  }
});

test('files over 20 MiB, past the 24 MiB left, or that fail to download stay behind and are counted; long text is cut', async () => {
  const MiB = 1024 * 1024;
  const w = moveWorld((s) => {
    s.first.content = 'x'.repeat(2100);
    s.first.attachments = [
      { id: 'big', filename: 'big.zip', size: 21 * MiB, url: 'https://cdn.example/big' },
      { id: 'a', filename: 'a.png', size: 15 * MiB, url: 'https://cdn.example/a' },
      { id: 'b', filename: 'b.png', size: 10 * MiB, url: 'https://cdn.example/b' },
      { id: 'c', filename: 'c.png', size: 5, url: 'https://cdn.example/c' },
      { id: 'd', filename: 'd.png', size: 5, url: 'https://cdn.example/d' },
    ];
    s.files = { 'https://cdn.example/a': new Response('a'), 'https://cdn.example/c': new Response('c'), 'https://cdn.example/d': new Response('no', { status: 404 }) };
  });
  const { res } = await runMove(w);
  assert.equal(res.moved, '990');
  assert.deepEqual(w.f.find('GET', /cdn\.example\//).map((c) => c.url.split('/').pop()), ['a', 'c', 'd'], 'a file too large, or past what is left, is never downloaded');
  const sent = w.f.find('POST', /\?wait=true$/)[0].body;
  assert.deepEqual(sent.files, ['a.png', 'c.png']);
  assert.equal(sent.payload.content, `${'x'.repeat(1999)}…`);
  assert.equal(w.f.find('POST', /\/channels\/990\/messages$/)[0].body.content,
    'Moved here from https://discord.com/channels/1/700 by <@8>. First posted by <@42>. 3 file(s) could not be copied (too large, or not downloaded); they are on the original post. The first message was too long to copy whole; the full text is on the original post.');
  const empty = moveWorld((s) => { s.first.content = ''; s.first.attachments = [{ filename: 'big.zip', size: 21 * MiB, url: 'https://cdn.example/big' }]; });
  await runMove(empty);
  assert.equal(empty.f.find('POST', /\?wait=true$/)[0].body.payload.content, '(The first message had nothing the bot can copy.)');
  assert.equal(empty.f.find('GET', /\/applications\/@me$/).length, 0, 'a message with a file shows the bot can read it');
  // A sticker alone, with Message Content on: the placeholder is posted.
  const blank = moveWorld((s) => { s.first.content = ''; s.extra = [['GET', /\/applications\/@me$/, () => ({ flags: 1 << 19 })]]; });
  await runMove(blank);
  assert.equal(blank.f.find('POST', /\?wait=true$/)[0].body.payload.content, '(The first message had nothing the bot can copy.)');
});

test('with the default call time, a move whose reads before the files end at 4.1 s still copies them', async () => {
  const clock = shiftClock();
  try {
    clock.at(0);
    const w = moveWorld((s) => {
      s.first.attachments = [{ id: 'a1', filename: 'one.png', size: 5, url: 'https://cdn.example/a1' }];
      s.files['https://cdn.example/a1'] = new Response('1');
      s.hooks = () => { clock.at(4100); return [{ id: '61', type: 1, application_id: 'app', token: 'wtok' }]; };
    });
    const { told } = await runMove(w);
    assert.equal(told, MOVED);
    assert.deepEqual(w.f.find('POST', /\?wait=true$/)[0].body.files, ['one.png']);
  } finally { clock.restore(); }
});

test('a download still running when the downloads end is stopped, so the first message is read again and the post moves with the files done before it', async () => {
  const clock = shiftClock();
  try {
    clock.at(0);
    // The downloads end at 10 s. The first ends at 9.5 s; the second never
    // answers, so only its signal, at 10 s, ends it.
    const w = moveWorld((s) => {
      s.first.attachments = [
        { id: 'a1', filename: 'one.png', size: 5, url: 'https://cdn.example/a1' },
        { id: 'a2', filename: 'two.png', size: 5, url: 'https://cdn.example/a2' },
      ];
      s.files['https://cdn.example/a1'] = () => { clock.at(9500); return new Response('1'); };
    });
    let started = 0;
    let stopped = false;
    const fetch = (url, init = {}) => {
      if (!/cdn\.example\/a2$/.test(url)) return w.f(url, init);
      started++;
      return stall(init, () => { stopped = true; });
    };
    const { told } = await runMove(w, moveSubmit(), {}, { fetch });
    assert.equal(told, MOVED);
    assert.equal(started, 1, 'the second download is started');
    assert.ok(stopped, 'and stopped by its signal');
    assert.deepEqual(w.f.find('POST', /\?wait=true$/)[0].body.files, ['one.png']);
  } finally { clock.restore(); }
});

test('a member read that stalls does not hold the webhook lookup: the post moves under the user\'s own name', async () => {
  const clock = shiftClock();
  try {
    clock.at(0);
    // With a call's time of 2 s the member read ends at 10 s and is reached
    // at 10.1 s. On the prep phase's client it would stall to 12 s, the
    // clock set there when its signal ends it, and leave the webhook lookup
    // no time.
    const w = moveWorld((s) => {
      const first = s.first;
      s.first = () => { clock.at(10100); return first; };
    });
    const fetch = (url, init = {}) => (/\/guilds\/1\/members\/42$/.test(url)
      ? stall(init, () => clock.at(12000))
      : w.f(url, init));
    const { told } = await runMove(w, moveSubmit(), {}, { fetch, callMs: 2000 });
    assert.equal(told, MOVED);
    assert.equal(w.f.find('GET', /\/channels\/901\/webhooks$/).length, 1, 'the webhook is looked up');
    assert.equal(w.f.find('POST', /\?wait=true$/)[0].body.payload.username, 'Pat', 'the user\'s own name, not the server name');
  } finally { clock.restore(); }
});

test('a move refused before the new post changes nothing and says why', async () => {
  const RECEIPT = /^Nothing was moved: the bot's "now tracked" reply in this post \(https:\/\/discord\.com\/channels\/1\/700\/m8\) says it was sent to GitHub, though its issue was not found by its filing record or the from-discord label, so the bot cannot move it\. If that issue was deleted, delete that reply, then move the post again\.$/;
  for (const [why, edit, want, envOver = {}] of [
    ['a locked post', (s) => { s.post.thread_metadata.locked = true; }, /^Nothing was moved: the post is locked: a moderator can unlock it, then move it\.$/],
    ['a post already moved', (s) => { s.kv = { 'movedto:700': '{"to":"990"}' }; }, /^Nothing was moved: this post was already moved to https:\/\/discord\.com\/channels\/1\/990\.$/],
    ['a filing record that is not JSON', (s) => { s.kv = { 'issue:700': '{' }; }, /^Nothing was moved: could not read this post's saved record just now\. Try again\.$/],
    ['a post already moved, which the move locked', (s) => { s.kv = { 'movedto:700': '{"to":"990"}' }; s.post.thread_metadata.locked = true; },
      /^Nothing was moved: this post was already moved to https:\/\/discord\.com\/channels\/1\/990\.$/],
    // Filed with no record saved (no STATE bound then, or the save failed),
    // its issue's from-discord label removed since: neither search finds it,
    // and the bot's reply in the post still says it was filed.
    ['a filed post neither its record nor the label finds, told by the bot\'s reply', (s) => {
      s.said = [{ id: 'm8', content: MESSAGES.tracked('ONE', 40), author: { id: 'b' } }];
    }, RECEIPT],
    ['the bot\'s reply that starts with the player\'s mention, as on a moved copy', (s) => {
      s.said = [{ id: 'm8', content: `<@42> ${MESSAGES.tracked('ONE', 40)}`, author: { id: 'b' } }];
    }, RECEIPT],
    ['a locked post with the bot\'s reply (the filed refusal, not the unlock advice)', (s) => {
      s.post.thread_metadata.locked = true;
      s.said = [{ id: 'm8', content: MESSAGES.tracked('ONE', 40), author: { id: 'b' } }];
    }, RECEIPT],
    // The form offered 901; it was deleted before the submit, so the
    // server's channel list no longer holds it.
    ['the chosen forum deleted since the form opened', (s) => { s.channels = CHANNELS.filter((c) => c.id !== '901'); },
      /^Nothing was moved: <#901> is not a forum of this server, so nothing is posted there\. \/bot-check names the FORUMS entry to fix\.$/],
    ['a deleted post', (s) => { s.post = () => new Response('{"message":"Unknown Channel"}', { status: 404 }); }, /^Nothing was moved: the post was deleted\.$/],
    ['a send or move of the post running', (s) => { s.claim = () => new Response('{"errors":[{"code":"already_exists"}]}', { status: 422 }); },
      /^Nothing was moved: another send or move of this post is running, or one stopped partway\. .*Then move the post again\.$/],
    ['a lock GitHub did not confirm', (s) => { s.claim = () => { throw new Error('Network connection lost.'); }; },
      /^Nothing was moved: GitHub did not confirm the lock discord-lock-700 in me\/test-one \(Network connection lost\.\)\. Wait a few minutes, then move the post again; /],
    ['the first message deleted', (s) => { s.first = () => new Response('{"message":"Unknown Message"}', { status: 404 }); }, /^Nothing was moved: the post's first message was deleted, so there is nothing to copy\.$/],
    ['the bot\'s copy whose record is not readable yet', (s) => { s.first = { ...s.first, webhook_id: '61', application_id: 'app' }; },
      /^Nothing was moved: this post is a copy the bot moved here, and its record movedfrom:700 is not readable yet\. /],
    ['a saved issue that cannot be checked', (s) => {
      s.kv = { 'issue:700': JSON.stringify({ repo: 'me/test-one', number: 40, key: 'ONE' }) };
      s.extra = [['GET', /api\.github\.com\/repos\/me\/test-one\/issues\/40$/, () => new Response('{}', { status: 404 })]];
    }, /^Could not check ONE #40 in me\/test-one \(404\): .*Nothing was moved\./],
  ]) {
    const w = moveWorld(edit);
    const { told, kv } = await runMove(w, moveSubmit(), envOver);
    assert.match(told, want, why);
    assert.equal(w.f.find('POST', /\?wait=true$/).length, 0, `${why}: no new post`);
    assert.equal(w.f.find('PATCH', /\/channels\/700$/).length, 0, `${why}: the old post is left as it is`);
    assert.equal(kv.m.has('movedfrom:990'), false, `${why}: no record`);
  }
  // Another author's message with the reply's text proves nothing.
  const quoted = moveWorld((s) => { s.said = [{ id: 'm8', content: MESSAGES.tracked('ONE', 40), author: { id: '42' } }]; });
  assert.equal((await runMove(quoted)).told, MOVED);
});

test('a create with no answer says a copy may exist, keeps the lock, and writes no record and nothing to the old post', async () => {
  for (const [why, made] of [
    ['a lost connection', () => { throw new Error('Network connection lost.'); }],
    ['a 2xx whose body cannot be read', () => new Response('{"id":', { status: 200 })],
    // Only the status the client kept counts, never one the answer's text quotes.
    ['a 502 whose answer quotes a 4xx', () => new Response('upstream: POST /x -> 400 bad', { status: 502 })],
  ]) {
    const w = moveWorld((s) => { s.made = made; });
    const { res, told, kv } = await runMove(w);
    assert.deepEqual(res, { uncertain: 'create' }, why);
    assert.equal(told, 'Nothing confirmed: Discord did not answer the new post\'s create in <#901>, so a copy of https://discord.com/channels/1/700 may exist there. The old post was not changed; its lock discord-lock-700 in me/test-one stays.', why);
    assert.equal(kv.m.size, 0, why);
    assert.equal(w.f.find('POST', /\/channels\/700\/messages$/).length + w.f.find('PATCH', /\/channels\/700$/).length, 0, why);
    assert.equal(w.f.find('DELETE', /discord-lock-700$/).length, 0, `${why}: the lock stays`);
  }
});

test('a create Discord refuses moves nothing and releases the lock', async () => {
  const w = moveWorld((s) => { s.made = () => new Response('{"message":"Invalid Form Body"}', { status: 400 }); });
  const { res, told, kv } = await runMove(w);
  assert.deepEqual(res, { refused: 'create' });
  assert.match(told, /^Nothing was moved: Discord refused the new post \([^)]*-> 400 [^)]*\)\.$/);
  assert.equal(kv.m.size, 0);
  assert.equal(w.f.find('DELETE', /discord-lock-700$/).length, 1, 'the lock is released');
});

test('a move past its steps\' phase still answers and releases: a slow KV or a stalled step cannot use up the reply\'s time', async () => {
  const clock = shiftClock();
  try {
    // The card's edit stalls until its call's time ends, and the clock then
    // stands at 23.5 s, past the steps' phase.
    clock.at(0);
    const late = moveWorld();
    const stalled = (url, init = {}) => (init.method === 'PATCH' && /\/channels\/556\/messages\/96$/.test(url)
      ? stall(init, () => clock.at(23500))
      : late.f(url, init));
    const { res, told, kv } = await runMove(late, moveSubmit(), {}, { fetch: stalled, callMs: 50 });
    assert.equal(res.moved, '990');
    // The old post's record went first, so it is saved despite the stall.
    assert.deepEqual(JSON.parse(kv.m.get('movedto:700')), { to: '990' });
    assert.equal(told, `${PARTWAY}\n- queue card for the new post\n- record movedfrom:990\n- moved message in the new post\n- note in the old post\n- lock on the old post`);
    // The old post was not locked in Discord, so its lock label stays.
    assert.equal(late.f.find('DELETE', /discord-lock-700$/).length, 0, 'the old post\'s lock stays');

    // Every step in time, the last one (the old post's lock) ending at
    // 24.5 s: the reply still goes by 25 s, and the release after it.
    clock.at(0);
    const closing = moveWorld((s) => { s.lock = () => { clock.at(24500); return {}; }; });
    const end = await runMove(closing);
    assert.equal(end.told, MOVED);
    assert.equal(closing.f.find('DELETE', /discord-lock-700$/).length, 1, 'the lock is released');

    // A record write that starts with 0.3 s of the steps' phase left waits
    // those 0.3 s, not the whole `kvMs`.
    clock.at(0);
    const short = moveWorld((s) => {
      s.putHangs = 'movedto:700';
      s.made = () => { clock.at(22700); return { id: '990', channel_id: '990' }; };
    });
    const began = performance.now();
    const cut = await runMove(short, moveSubmit(), {}, { kvMs: 5000 });
    assert.ok(performance.now() - began < 2000, 'the write waits only what is left of the phase');
    assert.match(cut.told, / Not done:\n- record movedto:700(\n|$)/);
  } finally { clock.restore(); }
  // A record whose write never answers is named after `kvMs`, and the steps
  // after it still run.
  const hang = moveWorld((s) => { s.putHangs = 'movedto:700'; });
  const { told } = await runMove(hang, moveSubmit(), {}, { kvMs: 30 });
  assert.equal(told, `${PARTWAY}\n- record movedto:700`);
  assert.equal(hang.f.find('PATCH', /\/channels\/700$/).length, 1, 'the steps after it still run');
});

test('a step after the new post that fails is named, and the later steps still run', async () => {
  for (const [why, edit, line, kept = false] of [
    ['the old post\'s record not saved', (s) => { s.putFails = 'movedto:700'; }, 'record movedto:700'],
    ['the new post\'s record not saved', (s) => { s.putFails = 'movedfrom:990'; }, 'record movedfrom:990'],
    ['the moved message refused', (s) => { s.extra = [['POST', /\/channels\/990\/messages$/, refusal]]; }, 'moved message in the new post'],
    ['the old post\'s note refused', (s) => { s.extra = [['POST', /\/channels\/700\/messages$/, refusal]]; }, 'note in the old post'],
    // An old post left open keeps its lock label, so nothing sends or moves it.
    ['the old post\'s lock refused', (s) => { s.lock = refusal; }, 'lock on the old post', true],
  ]) {
    const w = moveWorld(edit);
    const { res, told } = await runMove(w);
    assert.equal(res.moved, '990', why);
    assert.equal(told, `${PARTWAY}\n- ${line}`, why);
    assert.equal(w.f.find('PATCH', /\/channels\/700$/).length, 1, `${why}: the lock is still tried`);
    assert.equal(w.f.find('PATCH', /\/channels\/556\/messages\/96$/).length, 1, `${why}: the card still moves`);
    assert.equal(w.f.find('DELETE', /discord-lock-700$/).length, kept ? 0 : 1, `${why}: the old post's lock label`);
  }
  // A 2xx whose body the client could not read is a write that was done.
  const odd = moveWorld((s) => { s.lock = () => new Response('not json', { status: 200 }); });
  assert.equal((await runMove(odd)).told, MOVED);
});

test('a moved post moved again is copied under the original player, whose record carries on', async () => {
  const reporter = { name: 'Pat', id: '42', username: 'pat', avatar: 'https://cdn.discordapp.com/avatars/42/abc.png' };
  const w = moveWorld((s) => {
    s.kv = { 'movedfrom:700': JSON.stringify({ from: '690', reporter, card: '95' }) };
    s.first = { id: '700', content: 'My bags overlap', webhook_id: '61', application_id: 'app', author: { id: '61', username: 'Pat' }, attachments: [] };
  });
  const { res, kv } = await runMove(w);
  assert.equal(res.moved, '990');
  const sent = w.f.find('POST', /\?wait=true$/)[0].body.payload;
  assert.deepEqual([sent.username, sent.avatar_url], ['Pat', reporter.avatar]);
  assert.deepEqual(w.f.find('POST', /\/channels\/990\/messages$/)[0].body.allowed_mentions, { parse: [], users: ['42'] });
  assert.deepEqual(JSON.parse(kv.m.get('movedfrom:990')), { from: '700', reporter, card: '96' });
  assert.equal(w.f.find('GET', /\/guilds\/1\/members\//).length, 0, 'no member read for a copy');
});

// ---- Moving a filed post ---------------------------------------------------------

// The Move form as the record pre-filled it: ONE, client Retail, from card 96.
const filedSubmit = (values = {}, { custom = 'mv:700:96:ONE:Retail', member = MOD } = {}) => moveSubmit(values, { custom, member });
const FILED_MOVED = `${MOVED} ONE #40: ${ISSUE_URL}`;
const FILED_PARTWAY = `The move stopped partway: https://discord.com/channels/1/990 was made from https://discord.com/channels/1/700 (ONE #40: ${ISSUE_URL}). Not done:`;
const WHERE = ` The issue is ONE #40 in me/test-one (${ISSUE_URL}).`;
const TWO_URL = 'https://github.com/me/test-two/issues/7';
const TRANSFERRED = { data: { transferIssue: { issue: { number: 7, url: TWO_URL } } } };
const DUO_REPOS = { REPOS: '{"ONE":"me/test-one","TWO":"me/test-two","DUO":"me/test-two"}' };
const reEscape = (s) => s.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&');
const labelCalls = (f) => [...f.find('DELETE', /\/issues\/\d+\/labels\//).map((c) => `-${decodeURIComponent(c.url.split('/labels/')[1])}`),
  ...f.find('POST', /\/issues\/\d+\/labels$/).flatMap((c) => c.body.labels.map((l) => `+${l}`))];

test('a filed post moves keeping its repo: the issue, its record, its card and its checklist thread follow the new post', async () => {
  const w = filedWorld();
  const { res, kv, told } = await runMove(w, filedSubmit());
  const f = w.f;
  assert.deepEqual(res, { moved: '990', notes: [] });
  assert.equal(told, FILED_MOVED);
  assert.equal(f.find('POST', /\/graphql$/).length, 0, 'no transfer');
  // Phase 1's steps, then the labels, then the checklist thread last.
  const order = [['POST', /\?wait=true$/], ['PATCH', /\/issues\/40$/], ['PATCH', /\/channels\/556\/messages\/96$/], ['POST', /\/channels\/990\/messages$/],
    ['POST', /\/channels\/700\/messages$/], ['PATCH', /\/channels\/700$/], ['DELETE', /\/issues\/40\/labels\//], ['PATCH', /\/channels\/960$/],
    ['PATCH', /\/channels\/960\/messages\/960$/], ['PATCH', /\/webhooks\/app\/itok/]].map(([m, re]) => at(f, m, re));
  assert.deepEqual(order, [...order].sort((a, b) => a - b), `in order: ${order}`);
  const sent = f.find('POST', /\?wait=true$/)[0].body.payload;
  assert.equal(sent.thread_name, '[ONE] [Retail] [Feature] [Bags] Bags overlap', 'the issue\'s rebuilt title');
  assert.deepEqual(sent.applied_tags, ['f-tri', 'f-one', 'f-retail', 'f-acc'], 'the status, the key\'s repo tag, the client and Accepted');
  const patch = f.find('PATCH', /\/issues\/40$/)[0].body;
  assert.equal(patch.title, '[ONE] [Retail] [Feature] [Bags] Bags overlap');
  assert.equal(patch.body, ISSUE_BODY.replace('<!-- discord-message: 700 -->\n<!-- discord-thread: 700 reporter: 42 -->', [
    'Moved to [the new post](https://discord.com/channels/1/990) by [moddy](https://discord.com/users/5) (`moddy`).',
    '<!-- discord-copy -->', '<!-- discord-message: 990 -->', '<!-- discord-thread: 990 reporter: 42 -->'].join('\n')), 'only the footer replaced, by the mover\'s line and the copy footer');
  assert.deepEqual(labelCalls(f), ['-type: bug', '+type: feature']);
  assert.deepEqual(JSON.parse(kv.m.get('issue:990')), { repo: 'me/test-one', number: 40, key: 'ONE', by: '<@5>' });
  assert.deepEqual(f.find('PATCH', /\/channels\/960$/)[0].body, { archived: false });
  const first = f.find('PATCH', /\/channels\/960\/messages\/960$/)[0].body;
  assert.equal(first.content, checklistFirst({ title: patch.title, issueUrl: ISSUE_URL, guildId: '1', postId: '990', labels: ['from-discord', 'client: retail', 'type: feature'] }));
  assert.match(first.content, /\nPlayer post: https:\/\/discord\.com\/channels\/1\/990\nclient: retail . type: feature\n/);
  assert.deepEqual(first.allowed_mentions, { parse: [] });
  assert.equal(f.find('PATCH', /\/channels\/960$/).length, 1, 'no archive after the edit');
  const card = f.find('PATCH', /\/channels\/556\/messages\/96$/)[0].body;
  assert.equal(card.content, '~~**New post in <#901>:** <#990>~~\n**Filed as ONE #40** by <@5>');
  assert.deepEqual(card.components[0].components.map((b) => b.custom_id || b.url), ['move:990', 'https://discord.com/channels/1/990']);
  assert.equal(f.find('POST', /\/channels\/990\/messages$/)[0].body.content,
    'Moved here from https://discord.com/channels/1/700 by <@5>. First posted by <@42>. Tracked as ONE #40.');
});

test('a filed post moved to another repo transfers its issue first, and everything after follows the new repo and number', async () => {
  const w = filedWorld((s) => { s.gql = TRANSFERRED; });
  const { kv, told } = await runMove(w, filedSubmit({ repo: 'TWO' }));
  const f = w.f;
  assert.equal(told, `${MOVED} TWO #7: ${TWO_URL} (transferred from ONE #40)`);
  assert.ok(at(f, 'POST', /\/graphql$/) < at(f, 'POST', /\?wait=true$/), 'the transfer before the create');
  assert.deepEqual(f.find('POST', /\/graphql$/)[0].body.variables, { issueId: 'I_40', repositoryId: 'R_2' });
  assert.deepEqual(f.find('POST', /\?wait=true$/)[0].body.payload.applied_tags, ['f-tri', 'f-two', 'f-retail', 'f-acc'], 'the target key\'s repo tag, not the source\'s');
  assert.equal(f.find('PATCH', /test-two\/issues\/7$/)[0].body.title, '[TWO] [Retail] [Feature] [Bags] Bags overlap');
  assert.deepEqual(labelCalls(f), ['-type: bug', '+type: feature']);
  assert.equal(f.find('DELETE', /test-two\/issues\/7\/labels\//).length, 1, 'labels on the moved issue');
  assert.deepEqual(JSON.parse(kv.m.get('issue:990')), { repo: 'me/test-two', number: 7, key: 'TWO', by: '<@5>' });
  assert.match(f.find('PATCH', /\/channels\/960\/messages\/960$/)[0].body.content, new RegExp(`\nIssue: ${reEscape(TWO_URL)}\n`));
  assert.match(f.find('PATCH', /\/channels\/556\/messages\/96$/)[0].body.content, /\*\*Filed as TWO #7\*\* by <@5>$/);
});

test('a filed post keeps its old name when the title is not the bot\'s, and the title still follows when renaming is off', async () => {
  const hand = filedWorld(() => {}, { title: 'Bags overlap after resize' });
  await runMove(hand, filedSubmit());
  assert.equal(hand.f.find('POST', /\?wait=true$/)[0].body.payload.thread_name, 'Bags overlap', 'a hand title: the old post\'s name');
  assert.equal('title' in hand.f.find('PATCH', /\/issues\/40$/)[0].body, false, 'and no title sent');
  const off = filedWorld();
  await runMove(off, filedSubmit(), { RENAME_POSTS: '0' });
  assert.equal(off.f.find('POST', /\?wait=true$/)[0].body.payload.thread_name, 'Bags overlap', 'renaming off: the old post\'s name');
  assert.equal(off.f.find('PATCH', /\/issues\/40$/)[0].body.title, '[ONE] [Retail] [Feature] [Bags] Bags overlap', 'and still the new title');
});

test('the repo the form showed keeps the issue where it is; only another repo transfers it', async () => {
  const elsewhere = { repository_url: 'https://api.github.com/repos/me/test-two', html_url: 'https://github.com/me/test-two/issues/40' };
  const inTwo = (s) => { s.kv = { 'issue:700': JSON.stringify({ repo: 'me/test-two', number: 40, key: 'TWO' }) }; };
  for (const [why, edit, form, envOver, issue, reply] of [
    ['the field left empty', () => {}, filedSubmit({ repo: null }), {}, {}, FILED_MOVED],
    ['the shown key, the issue moved by hand to another repo', () => {}, filedSubmit({ repo: 'ONE' }), {}, elsewhere, `${MOVED} TWO #40: https://github.com/me/test-two/issues/40`],
    ['another key for the same repo', inTwo, filedSubmit({ repo: 'DUO' }, { custom: 'mv:700:96:TWO:Retail' }), DUO_REPOS, elsewhere, `${MOVED} DUO #40: https://github.com/me/test-two/issues/40`],
    ['a closed issue with the shown key', () => {}, filedSubmit({ repo: 'ONE' }), {}, { state: 'closed' }, FILED_MOVED],
    ['a closed issue with another key for its repo', inTwo, filedSubmit({ repo: 'DUO' }, { custom: 'mv:700:96:TWO:Retail' }), DUO_REPOS, { ...elsewhere, state: 'closed' },
      `${MOVED} DUO #40: https://github.com/me/test-two/issues/40`],
    ['an unfiled post with a repo picked', (s) => { s.kv = {}; s.issue = null; s.comments = []; }, filedSubmit({ repo: 'TWO' }), {}, {}, MOVED],
  ]) {
    const w = filedWorld(edit, issue);
    const { told } = await runMove(w, form, envOver);
    assert.equal(told, reply, why);
    assert.equal(w.f.find('POST', /\/graphql$/).length, 0, `${why}: no transfer`);
  }
});

test('a target forum with no type keeps the issue\'s type, from its type label', async () => {
  const NO_TYPE = { FORUMS: '{"900":{"client":"Retail","type":"Bug"},"901":{},"902":{"client":"Forever","type":"Bug"}}' };
  const feedback = (s) => {
    s.channels = CHANNELS.map((c) => (c.id === '900' ? { ...c, available_tags: [...c.available_tags, { id: 't-fb', name: 'Feedback' }] } : c));
    s.post.applied_tags = [...s.post.applied_tags, 't-fb'];
  };
  const BUG = '[ONE] [Retail] [Bug] [Bags] Bags overlap';
  for (const [why, edit, issue, title] of [
    ['the type label sets it', () => {}, { labels: [{ name: 'from-discord' }, { name: 'type: feature' }, { name: 'client: retail' }] }, '[ONE] [Retail] [Feature] [Bags] Bags overlap'],
    ['a kept Feature tag on a bug is dropped', feedback, {}, BUG],
    ['no type label: the title keeps its type', () => {}, { labels: [{ name: 'from-discord' }, { name: 'client: retail' }] }, BUG],
  ]) {
    const w = filedWorld(edit, issue);
    await runMove(w, filedSubmit(), NO_TYPE);
    assert.deepEqual(labelCalls(w.f), [], `${why}: no label call`);
    const sent = w.f.find('POST', /\?wait=true$/)[0].body.payload;
    assert.equal(sent.thread_name, title, why);
    if (/dropped/.test(why)) assert.equal(sent.applied_tags.includes('f-feat'), false, `${why}: no Feature tag`);
  }
});

test('a target forum with no client keeps the issue\'s client when the form\'s was left as shown', async () => {
  const ALL = { title: '[ONE] [All] [Bug] [UI] Title', labels: [{ name: 'from-discord' }, { name: 'type: bug' }, { name: 'client: all' }] };
  const kept = filedWorld(() => {}, ALL);
  await runMove(kept, filedSubmit({ client: 'Retail' }, { custom: 'mv:700:96:ONE:Retail' }));
  assert.equal(kept.f.find('PATCH', /\/issues\/40$/)[0].body.title, '[ONE] [All] [Feature] [UI] Title');
  assert.deepEqual(labelCalls(kept.f), ['-type: bug', '+type: feature'], 'no client label call');
  assert.ok(kept.f.find('POST', /\?wait=true$/)[0].body.payload.applied_tags.includes('f-forever'), 'tags for client All');
  const picked = filedWorld(() => {}, ALL);
  await runMove(picked, filedSubmit({ client: 'Retail' }, { custom: 'mv:700:96:ONE:All' }));
  assert.equal(picked.f.find('PATCH', /\/issues\/40$/)[0].body.title, '[ONE] [Retail] [Feature] [UI] Title');
  assert.deepEqual(labelCalls(picked.f), ['-type: bug', '-client: all', '+client: retail', '+type: feature']);
});

test('a filed move with nothing to change in the title or labels writes neither, and never adds from-discord', async () => {
  const w = filedWorld(() => {}, { labels: [{ name: 'type: bug' }, { name: 'client: retail' }] });
  await runMove(w, filedSubmit(), { FORUMS: '{"900":{"client":"Retail","type":"Bug"},"901":{"client":"Retail","type":"Bug"},"902":{}}' });
  assert.equal('title' in w.f.find('PATCH', /\/issues\/40$/)[0].body, false);
  assert.deepEqual(labelCalls(w.f), []);
});

test('a filed post found another way moves with that issue, and a locked one says where the issue is', async () => {
  const thirteen = filedIssue({ number: 13, html_url: 'https://github.com/me/test-two/issues/13', repository_url: 'https://api.github.com/repos/me/test-two' });
  // The saved issue deleted, another found by its marker: another filing, so no filer.
  const gone = filedWorld((s) => {
    s.kv = { 'issue:700': JSON.stringify({ repo: 'me/test-two', number: 12, key: 'DUO', by: '<@5>' }) };
    s.issue = () => new Response('{}', { status: 410 });
    s.two = [thirteen];
  });
  const goneRun = await runMove(gone, filedSubmit({ repo: null }, { custom: 'mv:700:96:DUO:Retail' }), DUO_REPOS);
  assert.equal(goneRun.told, `${MOVED} TWO #13: https://github.com/me/test-two/issues/13`);
  assert.deepEqual(JSON.parse(goneRun.kv.m.get('issue:990')), { repo: 'me/test-two', number: 13, key: 'TWO', by: null });
  assert.equal(gone.f.find('PATCH', /\/channels\/556\/messages\/96$/)[0].body.content, '~~**New post in <#901>:** <#990>~~\n**Filed as TWO #13**');
  // No record: found by its marker, with no filer.
  const search = filedWorld((s) => { s.kv = {}; s.one = []; s.two = [thirteen]; });
  const searchRun = await runMove(search, filedSubmit({ repo: null }, { custom: 'mv:700:96::Retail' }));
  assert.equal(searchRun.told, `${MOVED} TWO #13: https://github.com/me/test-two/issues/13`);
  assert.equal(JSON.parse(searchRun.kv.m.get('issue:990')).by, null);
  // Filed under a second key of its repo: that key throughout.
  const duo = filedWorld((s) => { s.kv = { 'issue:700': JSON.stringify({ repo: 'me/test-two', number: 40, key: 'DUO', by: '<@5>' }) }; },
    { repository_url: 'https://api.github.com/repos/me/test-two', html_url: 'https://github.com/me/test-two/issues/40' });
  const duoRun = await runMove(duo, filedSubmit({ repo: 'DUO' }, { custom: 'mv:700:96:DUO:Retail' }), DUO_REPOS);
  assert.equal(duoRun.told, `${MOVED} DUO #40: https://github.com/me/test-two/issues/40`);
  assert.equal(JSON.parse(duoRun.kv.m.get('issue:990')).key, 'DUO');
  assert.match(duo.f.find('PATCH', /\/issues\/40$/)[0].body.title, /^\[DUO\] /);
  // A locked filed post: the locked refusal, then where the issue is.
  const locked = filedWorld((s) => { s.post.thread_metadata.locked = true; });
  const lockedRun = await runMove(locked, filedSubmit());
  assert.equal(lockedRun.told, `Nothing was moved: the post is locked: a moderator can unlock it, then move it.${WHERE}`);
  assert.equal(locked.f.find('POST', /\?wait=true$/).length, 0, 'locked: no new post');
  assert.equal(locked.f.find('PATCH', /\/channels\/700$/).length, 0, 'locked: the old post is left as it is');
  assert.equal(lockedRun.kv.m.has('movedfrom:990'), false, 'locked: no record');
});

test('a refusal after the issue is found ends by saying where it is, and nothing is transferred', async () => {
  for (const [why, edit, form, issue, want] of [
    ['a record naming another repo, and no Manage Webhooks', (s) => { s.hooks = refusal; }, filedSubmit(),
      { repository_url: 'https://api.github.com/repos/me/test-two', html_url: 'https://github.com/me/test-two/issues/40' },
      'Nothing was moved: the bot lacks Manage Webhooks in <#901>. The issue is TWO #40 in me/test-two (https://github.com/me/test-two/issues/40).'],
    ['a closed issue and another repo', () => {}, filedSubmit({ repo: 'TWO' }), { state: 'closed' },
      `Nothing was moved: ONE #40 is closed, so it stays in me/test-one; move the post again keeping its repo.${WHERE}`],
    ['the comments read failing', (s) => { s.comments = () => new Response('oops', { status: 500 }); }, filedSubmit(), {},
      `Nothing was moved: GitHub GET /repos/me/test-one/issues/40/comments?per_page=100&page=1 -> 500 oops.${WHERE}`],
  ]) {
    const w = filedWorld(edit, issue);
    const { told } = await runMove(w, form);
    assert.equal(told, want, why);
    assert.equal(w.f.find('POST', /\/graphql$/).length, 0, `${why}: no transfer`);
    assert.equal(w.f.find('POST', /\?wait=true$/).length, 0, `${why}: no new post`);
    assert.equal(w.f.find('DELETE', /discord-lock-700$/).length, 1, `${why}: the lock released`);
  }
});

test('a transfer refused or never sent leaves the issue in its repo and releases the lock; one not confirmed keeps it', async () => {
  const NEEDS = 'Moving an issue to another repo needs the GitHub App\'s Contents: Read and write and Issues: Read and write, on repos of one owner; /bot-check names a missing permission.';
  const unconfirmed = (msg) => `Nothing confirmed: GitHub did not confirm the transfer of ONE #40 to me/test-two (${msg}), so the issue may be there now. It was last known as ONE #40 in me/test-one (${ISSUE_URL}). The post was not moved; its lock discord-lock-700 in me/test-one stays.`;
  const noTarget = async ({ repo }) => {
    if (repo === 'me/test-two') throw Object.assign(new Error('GitHub GET /repos/me/test-two/installation -> 404 nf'), { github: { status: 404 } });
    return 'inst';
  };
  for (const [why, edit, want, kept, depsOver = {}] of [
    ['refused: no Contents write', (s) => { s.gql = { data: { transferIssue: null }, errors: [{ type: 'FORBIDDEN', message: 'Resource not accessible by integration' }] }; },
      `Nothing was moved: GitHub refused the transfer of ONE #40 to me/test-two (Resource not accessible by integration). ${NEEDS}${WHERE}`, false],
    ['refused: a 422', (s) => { s.gql = () => new Response('bad', { status: 422 }); },
      `Nothing was moved: GitHub refused the transfer of ONE #40 to me/test-two (GitHub POST /graphql -> 422 bad). ${NEEDS}${WHERE}`, false],
    ['the target token failing', () => {}, `Nothing was moved: could not get access to me/test-two (GitHub GET /repos/me/test-two/installation -> 404 nf). Try again.${WHERE}`, false, { installationToken: noTarget }],
    ['the target repo read answering 404', (s) => { s.repo = () => new Response('{}', { status: 404 }); }, `Nothing was moved: could not read me/test-two (404). Try again.${WHERE}`, false],
    ['the target repo read answering 500', (s) => { s.repo = () => new Response('{}', { status: 500 }); }, `Nothing was moved: could not read me/test-two (500). Try again.${WHERE}`, false],
    ['no answer', (s) => { s.gql = () => { throw new Error('Network connection lost.'); }; }, unconfirmed('Network connection lost.'), true],
    ['a 500', (s) => { s.gql = () => new Response('oops', { status: 500 }); }, unconfirmed('GitHub POST /graphql -> 500 oops'), true],
    ['an error of another type', (s) => { s.gql = { data: { transferIssue: null }, errors: [{ type: 'UNPROCESSABLE', message: 'Cannot transfer' }] }; }, unconfirmed('Cannot transfer'), true],
  ]) {
    const w = filedWorld(edit);
    const { told } = await runMove(w, filedSubmit({ repo: 'TWO' }), {}, depsOver);
    assert.equal(told, want, why);
    assert.equal(w.f.find('POST', /\?wait=true$/).length, 0, `${why}: nothing created`);
    assert.equal(w.f.find('DELETE', /discord-lock-700$/).length, kept ? 0 : 1, `${why}: the lock`);
    if (/token|repo read/.test(why)) assert.equal(w.f.find('POST', /\/graphql$/).length, 0, `${why}: no transfer sent`);
    if (/token/.test(why)) assert.equal(w.f.find('GET', /\/repos\/me\/test-two$/).length, 0, `${why}: no repo read`);
  }
  // No time left to send the mutation: never sent, so the lock is released.
  const clock = shiftClock();
  try {
    clock.at(0);
    const w = filedWorld((s) => { s.repo = () => { clock.at(12000); return { node_id: 'R_2' }; }; });
    const { told } = await runMove(w, filedSubmit({ repo: 'TWO' }));
    assert.equal(told, `Nothing was moved: out of time before POST https://api.github.com/graphql.${WHERE}`);
    assert.equal(w.f.find('POST', /\/graphql$/).length, 0);
    assert.equal(w.f.find('DELETE', /discord-lock-700$/).length, 1);
  } finally { clock.restore(); }
  // After a transfer, a create refused or not answered names the new repo.
  const NEW_WHERE = ` The issue is TWO #7 in me/test-two (${TWO_URL}).`;
  const refused = filedWorld((s) => { s.gql = TRANSFERRED; s.made = () => new Response('{"message":"Invalid Form Body"}', { status: 400 }); });
  assert.match((await runMove(refused, filedSubmit({ repo: 'TWO' }))).told, new RegExp(`^Nothing was moved: Discord refused the new post \\([^)]*-> 400 [^)]*\\)\\.${reEscape(NEW_WHERE)}$`));
  const lost = filedWorld((s) => { s.gql = TRANSFERRED; s.made = () => { throw new Error('Network connection lost.'); }; });
  assert.equal((await runMove(lost, filedSubmit({ repo: 'TWO' }))).told,
    `Nothing confirmed: Discord did not answer the new post's create in <#901>, so a copy of https://discord.com/channels/1/700 may exist there. The old post was not changed; its lock discord-lock-700 in me/test-one stays.${NEW_WHERE}`);
  assert.equal(lost.f.find('DELETE', /discord-lock-700$/).length, 0, 'the unanswered create keeps the lock');
});

test('after a transfer whose create was refused, moving again with the form\'s default transfers nothing and finishes', async () => {
  let runs = 0;
  let moved = false;
  const w = filedWorld((s) => {
    s.gql = () => { moved = true; return TRANSFERRED; };
    s.issue = () => (moved ? filedIssue({ number: 7, html_url: TWO_URL, repository_url: 'https://api.github.com/repos/me/test-two' }) : filedIssue());
    s.made = () => (runs === 1 ? new Response('{"message":"Invalid Form Body"}', { status: 400 }) : { id: '990', channel_id: '990' });
  });
  runs = 1;
  await runMove(w, filedSubmit({ repo: 'TWO' }));
  runs = 2;
  const before = w.f.calls.length;
  await runMove(w, filedSubmit({ repo: 'ONE' }));
  const second = w.f.calls.slice(before);
  assert.equal(second.filter((c) => /\/graphql$/.test(c.url)).length, 0, 'no transfer');
  assert.equal(second.filter((c) => /\?wait=true$/.test(c.url)).length, 1, 'the post created');
  assert.equal(w.f.find('PATCH', /\/webhooks\/app\/itok/).at(-1).body.content, `${MOVED} TWO #7: ${TWO_URL}`);
});

test('a filed move\'s step after the new post that fails is named, and the later steps still run', async () => {
  for (const [why, edit, line] of [
    ['the record not saved', (s) => { s.putFails = 'issue:990'; }, 'record issue:990'],
    ['the issue edit refused', (s) => { s.patch = refusal; }, 'issue link to the new post'],
    ['the issue edit answered 200 with a cut-off body', (s) => { s.patch = () => new Response('{"id":', { status: 200 }); }, null],
    ['the issue edit answered 200 and its body stream failed', (s) => {
      s.patch = () => new Response(new ReadableStream({ start(c) { c.error(new TypeError('terminated')); } }), { status: 200 });
    }, null],
    ['a label add refused', (s) => { s.addLabels = refusal; }, 'issue labels'],
    ['the checklist message edit refused', (s) => { s.firstEdit = refusal; }, 'staff checklist thread'],
    ['the checklist thread open answered 200 with a cut-off body', (s) => { s.open = () => new Response('{"id":', { status: 200 }); }, null],
  ]) {
    const w = filedWorld(edit);
    const { told } = await runMove(w, filedSubmit());
    assert.equal(told, line ? `${FILED_PARTWAY}\n- ${line}` : FILED_MOVED, why);
    // The checklist names the labels as the calls left them: the bug label
    // went, the feature label was refused.
    if (/label add/.test(why)) assert.match(w.f.find('PATCH', /\/channels\/960\/messages\/960$/)[0].body.content, /\nclient: retail\nThe bot/);
    assert.equal(w.f.find('PATCH', /\/channels\/960\/messages\/960$/).length, 1, `${why}: the checklist step still runs`);
    assert.equal(w.f.find('PATCH', /\/channels\/700$/).length, 1, `${why}: the old post still locked`);
  }
});

test('the checklist step edits only a thread the bot\'s record names', async () => {
  const gone = filedWorld((s) => { s.open = () => new Response('{"message":"Unknown Channel"}', { status: 404 }); });
  assert.equal((await runMove(gone, filedSubmit())).told, `${FILED_PARTWAY}\n- staff checklist thread`);
  assert.equal(gone.f.find('PATCH', /\/channels\/960\/messages\/960$/).length, 0, 'no message edit');
  for (const [why, comments] of [
    ['a record with no thread yet', [{ ...RECORD, body: checklistBody({ state: 'pending', guildId: '', since: 1, issueUrl: ISSUE_URL }) }]],
    ['no record', []],
    ['a record-shaped comment by someone else', [{ ...RECORD, user: { login: 'pat' } }]],
  ]) {
    const w = filedWorld((s) => { s.comments = comments; });
    assert.equal((await runMove(w, filedSubmit())).told, FILED_MOVED, why);
    assert.equal(w.f.calls.filter((c) => /\/channels\/960/.test(c.url)).length, 0, `${why}: no checklist call`);
  }
});

test('Send to GitHub on a moved filed post finds its issue by the move\'s record and writes the card the move wrote', async () => {
  const w = filedWorld();
  const { kv } = await runMove(w, filedSubmit());
  const card = w.f.find('PATCH', /\/channels\/556\/messages\/96$/)[0].body.content;
  const f = fakeFetch([
    ['GET', /\/channels\/990$/, () => ({ id: '990', parent_id: '901', name: 'x', applied_tags: [] })],
    ['GET', /\/repos\/me\/test-one\/issues\/40$/, () => filedIssue()],
    ['POST', /test-one\/labels$/, () => new Response('{}', { status: 201 })],
    ['DELETE', /discord-lock-990$/, () => null],
    ['PATCH', /\/channels\/556\/messages\/96$/, () => ({})],
    ['PATCH', /\/webhooks\//, () => ({})],
  ]);
  const form = { ...submit({ repo: 'ONE' }), channel_id: '990' };
  form.data = { ...form.data, custom_id: 'gh:990:990' };
  const ctx = ctxFor();
  await handle(await signed(form), { ...MOVE_ENV, STATE: kv }, ctx, { fetch: f, installationToken: async () => 'inst', log: () => {} });
  await Promise.all(ctx.jobs);
  assert.equal(f.find('PATCH', /\/webhooks\//)[0].body.content, `Already tracked: ONE #40 ${ISSUE_URL}`);
  assert.equal(f.find('PATCH', /\/channels\/556\/messages\/96$/)[0].body.content, card, 'the card the move wrote');
});
