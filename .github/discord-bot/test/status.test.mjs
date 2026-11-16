import test from 'node:test';
import assert from 'node:assert/strict';
import { run } from '../status/status.mjs';
import { fakeFetch, FORUM } from './fake-fetch.mjs';

const env = { GITHUB_TOKEN: 'gh', DISCORD_BOT_TOKEN: 'bot', REPOS: '{"AES":"me/aes","AUI":"me/aui"}' };
const repository = { full_name: 'me/aes', default_branch: 'dev' };
const MARK = '<!-- discord-thread: 700 reporter: 42 -->';
const issue = (n, extra = {}) => ({ number: n, body: `## Report\n\n> hi\n\n${MARK}`, labels: [{ name: 'from-discord' }], ...extra });
const quiet = () => {};

function routes(issues, extra = []) {
  return [
    ...extra,
    ['GET', /api\.github\.com\/repos\/me\/aes\/issues\/(\d+)$/, (_, url) => {
      const n = Number(/issues\/(\d+)$/.exec(url)[1]);
      return issues[n] || new Response('nf', { status: 404 });
    }],
    ['POST', /\/issues\/\d+\/labels$/, () => []],
    ['DELETE', /\/issues\/\d+\/labels\//, () => null],
    ['GET', /discord\.com\/api\/v10\/channels\/700$/, () => ({ id: '700', parent_id: '900', applied_tags: ['t-retail', 't-bug', 's-tri'], thread_metadata: { archived: true } })],
    ['GET', /discord\.com\/api\/v10\/channels\/900$/, () => FORUM],
    ['PATCH', /discord\.com\/api\/v10\/channels\/700$/, () => ({})],
    ['POST', /discord\.com\/api\/v10\/channels\/700\/messages$/, () => ({})],
  ];
}

test('a PR that says Fixes #17 moves the post to In progress', async () => {
  const f = fakeFetch(routes({ 17: issue(17) }));
  const done = await run({ eventName: 'pull_request', fetchImpl: f, env, log: quiet,
    payload: { action: 'opened', repository, pull_request: { title: 'Bags fix', body: 'Fixes #17', base: { ref: 'dev' } } } });
  assert.equal(done.length, 1);
  assert.deepEqual(f.find('PATCH', /channels\/700$/)[0].body, { applied_tags: ['t-retail', 't-bug', 's-prog'], archived: false });
  assert.match(f.find('POST', /channels\/700\/messages$/)[0].body.content, /being tested/);
});

test('issues not made by the bot are left alone', async () => {
  const f = fakeFetch(routes({ 3: { number: 3, body: 'filed by hand', labels: [] } }));
  const done = await run({ eventName: 'pull_request', fetchImpl: f, env, log: quiet,
    payload: { action: 'opened', repository, pull_request: { title: 'x', body: 'Fixes #3', base: { ref: 'dev' } } } });
  assert.equal(done.length, 0);
  assert.equal(f.calls.filter((c) => /discord\.com/.test(c.url)).length, 0);
});

test('merging into dev marks pending-release and says fixed', async () => {
  const f = fakeFetch(routes({ 17: issue(17) }));
  await run({ eventName: 'pull_request', fetchImpl: f, env, log: quiet,
    payload: { action: 'closed', repository, pull_request: { merged: true, title: 'Fix bags (fixes #17)', body: '', base: { ref: 'dev' } } } });
  assert.deepEqual(f.find('POST', /issues\/17\/labels$/)[0].body, { labels: ['pending-release'] });
  assert.deepEqual(f.find('PATCH', /channels\/700$/)[0].body.applied_tags, ['t-retail', 't-bug', 's-fix']);
  assert.match(f.find('POST', /channels\/700\/messages$/)[0].body.content, /next update/);
});

test('a PR closed without merging, or merged elsewhere, does nothing', async () => {
  for (const pr of [{ merged: false, base: { ref: 'dev' } }, { merged: true, base: { ref: 'main' } }]) {
    const f = fakeFetch(routes({ 17: issue(17) }));
    const done = await run({ eventName: 'pull_request', fetchImpl: f, env, log: quiet,
      payload: { action: 'closed', repository, pull_request: { title: '', body: 'Fixes #17', ...pr } } });
    assert.equal(done.length, 0);
  }
});

test('a release tag ships every pending issue and names the version', async () => {
  const f = fakeFetch(routes({}, [
    ['GET', /\/issues\?state=all.*labels=pending-release/, () => [issue(17), issue(18, { body: 'no marker', labels: [] })]],
  ]));
  const done = await run({ eventName: 'push', fetchImpl: f, env, log: quiet, payload: { ref: 'refs/tags/v5.0.120', repository } });
  assert.equal(done.length, 1);
  assert.match(done[0].message, /landed in atrocityEssentials v5\.0\.120/);
  assert.deepEqual(f.find('PATCH', /channels\/700$/)[0].body.applied_tags, ['t-retail', 't-bug', 's-ship']);
  assert.equal(f.find('DELETE', /issues\/17\/labels\/pending-release/).length, 1);
  assert.deepEqual(f.find('POST', /issues\/17\/labels$/)[0].body, { labels: ['shipped'] });
  assert.equal(f.find('PATCH', /channels\/700$/)[0].body.locked, undefined, 'shipped posts stay open');
});

test('atrocityUI tags like 30.8 count when the pattern says so; other tags do not', async () => {
  const aui = { full_name: 'me/aui', default_branch: 'dev' };
  const f = fakeFetch([
    ['GET', /\/issues\?state=all/, () => [issue(4)]],
    ...routes({}),
  ]);
  const done = await run({ eventName: 'push', fetchImpl: f, env: { ...env, RELEASE_TAG_PATTERN: '^\\d+\\.\\d+' }, log: quiet,
    payload: { ref: 'refs/tags/30.8', repository: aui } });
  assert.match(done[0].message, /atrocityUI v30\.8/);
  const none = await run({ eventName: 'push', fetchImpl: fakeFetch([]), env, log: quiet, payload: { ref: 'refs/tags/test-build', repository } });
  assert.equal(none.length, 0);
});

test('closing as not planned tells the player; closing as done stays quiet', async () => {
  const f = fakeFetch(routes({}));
  await run({ eventName: 'issues', fetchImpl: f, env, log: quiet,
    payload: { action: 'closed', repository, issue: issue(17, { state_reason: 'not_planned' }) } });
  assert.deepEqual(f.find('PATCH', /channels\/700$/)[0].body.applied_tags, ['t-retail', 't-bug', 's-closed']);
  const g = fakeFetch(routes({}));
  const done = await run({ eventName: 'issues', fetchImpl: g, env, log: quiet,
    payload: { action: 'closed', repository, issue: issue(17, { state_reason: 'completed' }) } });
  assert.equal(done.length, 0);
});

test('needs-info pings only the reporter', async () => {
  const f = fakeFetch(routes({}));
  await run({ eventName: 'issues', fetchImpl: f, env, log: quiet,
    payload: { action: 'labeled', label: { name: 'needs-info' }, repository, issue: issue(17) } });
  const msg = f.find('POST', /channels\/700\/messages$/)[0].body;
  assert.match(msg.content, /^<@42> Could you add/);
  assert.deepEqual(msg.allowed_mentions, { parse: [], users: ['42'] });
  assert.equal(f.find('PATCH', /channels\/700$/).length, 0);
});
