import test from 'node:test';
import assert from 'node:assert/strict';
import { run } from '../status/status.mjs';
import { fakeFetch, FORUM } from './fake-fetch.mjs';

const env = { GITHUB_TOKEN: 'gh', DISCORD_BOT_TOKEN: 'bot' };
const BOT = { login: 'github-actions[bot]' };
const repository = { full_name: 'me/one', default_branch: 'dev' };
const MARK = '<!-- discord-thread: 700 reporter: 42 -->';
const issue = (n, extra = {}) => ({ number: n, body: `## Report\n\n> hi\n\n${MARK}`, labels: [{ name: 'from-discord' }], ...extra });
const quiet = () => {};
// The event name GitHub really sends for this workflow's PR trigger.
const PR = 'pull_request_target';
const pr = (over = {}) => ({ title: 'Bags fix', body: 'Fixes #17', base: { ref: 'dev' }, draft: false, author_association: 'MEMBER', ...over });

function routes(issues, extra = []) {
  return [
    ...extra,
    ['GET', /api\.github\.com\/repos\/me\/one\/issues\/(\d+)$/, (_, url) => {
      const n = Number(/issues\/(\d+)$/.exec(url)[1]);
      return issues[n] || new Response('nf', { status: 404 });
    }],
    ['GET', /\/issues\/\d+\/comments/, () => []],
    ['POST', /\/issues\/\d+\/comments$/, () => ({})],
    ['POST', /\/issues\/\d+\/labels$/, () => []],
    ['DELETE', /\/issues\/\d+\/labels\//, () => null],
    ['GET', /discord\.com\/api\/v10\/channels\/700$/, () => ({ id: '700', parent_id: '900', applied_tags: ['t-retail', 't-bug', 's-tri'], thread_metadata: { archived: true } })],
    ['GET', /discord\.com\/api\/v10\/channels\/900$/, () => FORUM],
    ['PATCH', /discord\.com\/api\/v10\/channels\/700$/, () => ({})],
    ['POST', /discord\.com\/api\/v10\/channels\/700\/messages$/, () => ({})],
  ];
}

test('a member PR that says Fixes #17 moves the post to In progress', async () => {
  const f = fakeFetch(routes({ 17: issue(17) }));
  const done = await run({ eventName: PR, fetchImpl: f, env, log: quiet,
    payload: { action: 'opened', repository, pull_request: pr() } });
  assert.equal(done.length, 1);
  assert.deepEqual(f.find('PATCH', /channels\/700$/)[0].body, { applied_tags: ['t-retail', 't-bug', 's-prog'], archived: false });
  assert.match(f.find('POST', /channels\/700\/messages$/)[0].body.content, /being tested/);
});

test('a PR from an outside author, or a draft, moves nothing', async () => {
  for (const over of [{ author_association: 'NONE' }, { author_association: 'CONTRIBUTOR' }, { author_association: undefined }, { draft: true }]) {
    const f = fakeFetch(routes({ 17: issue(17) }));
    const done = await run({ eventName: PR, fetchImpl: f, env, log: quiet,
      payload: { action: 'opened', repository, pull_request: pr(over) } });
    assert.equal(done.length, 0, JSON.stringify(over));
    assert.equal(f.calls.filter((c) => /discord\.com/.test(c.url)).length, 0, JSON.stringify(over));
  }
});

test('a post already fixed or shipped does not go back to In progress', async () => {
  for (const name of ['pending-release', 'shipped']) {
    const f = fakeFetch(routes({ 17: issue(17, { labels: [{ name: 'from-discord' }, { name }] }) }));
    const done = await run({ eventName: PR, fetchImpl: f, env, log: quiet,
      payload: { action: 'reopened', repository, pull_request: pr() } });
    assert.equal(done.length, 0, name);
  }
});

test('issues not made by the bot are left alone', async () => {
  const f = fakeFetch(routes({ 3: { number: 3, body: 'filed by hand', labels: [] } }));
  const done = await run({ eventName: PR, fetchImpl: f, env, log: quiet,
    payload: { action: 'opened', repository, pull_request: pr({ title: 'x', body: 'Fixes #3' }) } });
  assert.equal(done.length, 0);
  assert.equal(f.calls.filter((c) => /discord\.com/.test(c.url)).length, 0);
});

test('merging into dev marks pending-release, records the fix commit and says fixed', async () => {
  const f = fakeFetch(routes({ 17: issue(17) }));
  await run({ eventName: PR, fetchImpl: f, env, log: quiet,
    payload: { action: 'closed', repository, pull_request: pr({ merged: true, merge_commit_sha: 'abc1234def', title: 'Fix bags (fixes #17)', body: '' }) } });
  assert.deepEqual(f.find('POST', /issues\/17\/labels$/)[0].body, { labels: ['pending-release'] });
  assert.match(f.find('POST', /issues\/17\/comments$/)[0].body.body, /<!-- discord-fixed-in: abc1234def -->/);
  const writes = f.calls.filter((c) => /issues\/17\/(comments|labels)$/.test(c.url)).map((c) => c.url.split('/').pop());
  assert.deepEqual(writes, ['comments', 'labels'], 'the commit is recorded before the issue is labeled pending');
  assert.deepEqual(f.find('PATCH', /channels\/700$/)[0].body.applied_tags, ['t-retail', 't-bug', 's-fix']);
  assert.match(f.find('POST', /channels\/700\/messages$/)[0].body.content, /next update/);
});

test('an issue fixed again after shipping is pending, not shipped', async () => {
  const f = fakeFetch(routes({ 17: issue(17, { labels: [{ name: 'from-discord' }, { name: 'shipped' }] }) }));
  await run({ eventName: PR, fetchImpl: f, env, log: quiet,
    payload: { action: 'closed', repository, pull_request: pr({ merged: true, merge_commit_sha: 'abc1234' }) } });
  const writes = f.calls.filter((c) => /issues\/17\/(comments|labels)/.test(c.url) && c.method !== 'GET')
    .map((c) => `${c.method} ${c.url.split('/issues/17/')[1]}`);
  assert.deepEqual(writes, ['DELETE labels/shipped', 'POST comments', 'POST labels'], 'shipped goes before the record is written');
});

test('rerunning a merge that stopped partway finishes it', async () => {
  const rec = [{ user: BOT, body: '<!-- discord-fixed-in: abc1234 -->' }];
  // The record was written, then adding the label failed.
  const f = fakeFetch(routes({ 17: issue(17) }, [['GET', /\/issues\/17\/comments/, () => rec]]));
  const done = await run({ eventName: PR, fetchImpl: f, env, log: quiet,
    payload: { action: 'closed', repository, pull_request: pr({ merged: true, merge_commit_sha: 'abc1234' }) } });
  assert.equal(f.find('POST', /issues\/17\/comments$/).length, 0, 'not recorded twice');
  assert.deepEqual(f.find('POST', /issues\/17\/labels$/)[0].body, { labels: ['pending-release'] });
  assert.equal(done.length, 1, 'the player is told');
});

test('a merged PR does not label a from-discord issue that has no marker', async () => {
  const f = fakeFetch(routes({ 17: issue(17, { body: 'marker removed by hand' }) }));
  const done = await run({ eventName: PR, fetchImpl: f, env, log: quiet,
    payload: { action: 'closed', repository, pull_request: pr({ merged: true }) } });
  assert.equal(done.length, 0);
  assert.equal(f.find('POST', /issues\/17\/labels$/).length, 0);
});

test('a PR closed without merging, or merged elsewhere, does nothing', async () => {
  for (const over of [{ merged: false }, { merged: true, base: { ref: 'main' } }]) {
    const f = fakeFetch(routes({ 17: issue(17) }));
    const done = await run({ eventName: PR, fetchImpl: f, env, log: quiet,
      payload: { action: 'closed', repository, pull_request: pr(over) } });
    assert.equal(done.length, 0);
  }
});

test('a release tag ships every pending issue and names the version', async () => {
  const f = fakeFetch(routes({}, [
    ['GET', /\/issues\?state=all.*labels=pending-release/, () => [issue(17), issue(18, { body: 'no marker', labels: [{ name: 'pending-release' }] })]],
  ]));
  const done = await run({ eventName: 'push', fetchImpl: f, env, log: quiet, payload: { ref: 'refs/tags/v5.0.120', repository } });
  assert.equal(done.length, 1);
  assert.match(done[0].message, /landed in one v5\.0\.120/);
  assert.deepEqual(f.find('PATCH', /channels\/700$/)[0].body.applied_tags, ['t-retail', 't-bug', 's-ship']);
  assert.equal(f.find('DELETE', /issues\/17\/labels\/pending-release/).length, 1);
  assert.deepEqual(f.find('POST', /issues\/17\/labels$/)[0].body, { labels: ['shipped'] });
  assert.equal(f.find('PATCH', /channels\/700$/)[0].body.locked, undefined, 'shipped posts stay open');
  assert.equal(f.calls.filter((c) => /issues\/18\//.test(c.url)).length, 0, 'an issue the bot did not make keeps its labels');
});

test('one broken post does not stop the rest of a release; a deleted post still ships', async () => {
  const at = (thread) => `## Report\n\n<!-- discord-thread: ${thread} reporter: 42 -->`;
  const f = fakeFetch(routes({}, [
    ['GET', /\/issues\?state=all.*labels=pending-release/, () => [issue(20, { body: at(701) }), issue(21, { body: at(702) }), issue(17)]],
    ['GET', /channels\/701$/, () => new Response('{"message":"Unknown Channel"}', { status: 404 })],
    ['GET', /channels\/702$/, () => new Response('{"message":"Missing Access"}', { status: 403 })],
  ]));
  const logs = [];
  await assert.rejects(run({ eventName: 'push', fetchImpl: f, env, log: (l) => logs.push(l), payload: { ref: 'refs/tags/v5.0.121', repository } }),
    /could not update issue\(s\) #21/);
  assert.equal(f.find('DELETE', /issues\/20\/labels\/pending-release/).length, 1, 'a deleted post is shipped anyway');
  assert.equal(f.find('DELETE', /issues\/21\/labels\/pending-release/).length, 0, 'a refused post stays pending for the next tag');
  assert.equal(f.find('DELETE', /issues\/17\/labels\/pending-release/).length, 1, 'issues after a failure still ship');
  assert.ok(logs.some((l) => /#21: .*403/.test(l)));
});

test('a tag ships only fixes it contains, so rerunning an older tag ships nothing new', async () => {
  const fixed = (sha) => [{ user: BOT, body: `Fixed in ${sha}.\n\n<!-- discord-fixed-in: ${sha} -->` }];
  const f = fakeFetch(routes({}, [
    ['GET', /\/issues\?state=all.*labels=pending-release/, () => [issue(17), issue(18)]],
    ['GET', /\/issues\/17\/comments/, () => fixed('aaaaaaa')],
    ['GET', /\/issues\/18\/comments/, () => fixed('bbbbbbb')],
    ['GET', /\/compare\/aaaaaaa\.\.\.discord-test-1$/, () => ({ status: 'ahead' })],
    ['GET', /\/compare\/bbbbbbb\.\.\.discord-test-1$/, () => ({ status: 'diverged' })],
  ]));
  const done = await run({ eventName: 'push', fetchImpl: f, env: { ...env, RELEASE_TAG_PATTERN: '^discord-test-' }, log: quiet,
    payload: { ref: 'refs/tags/discord-test-1', repository } });
  assert.deepEqual(done.map((d) => d.issue), [17]);
  assert.equal(f.find('DELETE', /issues\/18\/labels\/pending-release/).length, 0);
});

test('deleting a release tag ships nothing', async () => {
  const f = fakeFetch(routes({}, [['GET', /\/issues\?state=all/, () => [issue(17)]]]));
  const done = await run({ eventName: 'push', fetchImpl: f, env, log: quiet, payload: { ref: 'refs/tags/v5.0.120', deleted: true, repository } });
  assert.equal(done.length, 0);
  assert.equal(f.calls.length, 0);
});

test('a second repo names itself from its full name; other tags do nothing', async () => {
  const two = { full_name: 'me/two', default_branch: 'dev' };
  const f = fakeFetch([
    ['GET', /\/issues\?state=all/, () => [issue(4)]],
    ...routes({}),
  ]);
  const done = await run({ eventName: 'push', fetchImpl: f, env: { ...env, RELEASE_TAG_PATTERN: '^\\d+\\.\\d+' }, log: quiet,
    payload: { ref: 'refs/tags/30.8', repository: two } });
  assert.match(done[0].message, /two v30\.8/);
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

test('needs-info reopens an archived post, then pings only the reporter', async () => {
  const f = fakeFetch(routes({}));
  await run({ eventName: 'issues', fetchImpl: f, env, log: quiet,
    payload: { action: 'labeled', label: { name: 'needs-info' }, repository, issue: issue(17) } });
  assert.deepEqual(f.find('PATCH', /channels\/700$/).map((c) => c.body), [{ archived: false }], 'status tags untouched');
  const msg = f.find('POST', /channels\/700\/messages$/)[0].body;
  assert.match(msg.content, /^<@42> Could you add/);
  assert.deepEqual(msg.allowed_mentions, { parse: [], users: ['42'] });
  const order = f.calls.filter((c) => /channels\/700/.test(c.url) && c.method !== 'GET').map((c) => c.method);
  assert.deepEqual(order, ['PATCH', 'POST'], 'reopened before the message');
});

test('only the workflow\'s own fixed-in comments count, from every page, and the tag needs all of them', async () => {
  const marker = (sha, user) => ({ user, body: `<!-- discord-fixed-in: ${sha} -->` });
  const outsider = { login: 'someone' };
  const page1 = [marker('aaaaaaa', BOT), ...Array.from({ length: 99 }, () => ({ user: outsider, body: 'me too' }))];
  const f = fakeFetch(routes({}, [
    ['GET', /\/issues\?state=all.*labels=pending-release/, () => [issue(17)]],
    ['GET', /\/issues\/17\/comments\?per_page=100&page=1$/, () => page1],
    // A later page: a second fix, then an outsider's planted record.
    ['GET', /\/issues\/17\/comments\?per_page=100&page=2$/, () => [marker('bbbbbbb', BOT), marker('ccccccc', outsider)]],
    ['GET', /\/compare\/aaaaaaa\.\.\.v5\.0\.1$/, () => ({ status: 'ahead' })],
    ['GET', /\/compare\/bbbbbbb\.\.\.v5\.0\.1$/, () => ({ status: 'behind' })],
  ]));
  const done = await run({ eventName: 'push', fetchImpl: f, env, log: quiet, payload: { ref: 'refs/tags/v5.0.1', repository } });
  assert.equal(done.length, 0, 'held: the tag lacks the second fix');
});

test('an outsider\'s planted fix record can neither hold nor break a release', async () => {
  const f = fakeFetch(routes({}, [
    ['GET', /\/issues\?state=all.*labels=pending-release/, () => [issue(17)]],
    ['GET', /\/issues\/17\/comments/, () => [
      { user: BOT, body: '<!-- discord-fixed-in: aaaaaaa -->' },
      { user: { login: 'someone' }, body: '<!-- discord-fixed-in: ccccccc -->' },
    ]],
    ['GET', /\/compare\/aaaaaaa\.\.\.v5\.0\.1$/, () => ({ status: 'ahead' })],
    // Were the outsider's record read, this would hold the issue.
    ['GET', /\/compare\/ccccccc\.\.\.v5\.0\.1$/, () => ({ status: 'behind' })],
  ]));
  const done = await run({ eventName: 'push', fetchImpl: f, env, log: quiet, payload: { ref: 'refs/tags/v5.0.1', repository } });
  assert.deepEqual(done.map((d) => d.issue), [17]);
  assert.equal(f.find('GET', /compare\/ccccccc/).length, 0);
});

test('rerunning an old merge event changes nothing', async () => {
  const f = fakeFetch(routes({ 17: issue(17, { labels: [{ name: 'from-discord' }, { name: 'shipped' }] }) }, [
    ['GET', /\/issues\/17\/comments/, () => [{ user: BOT, body: '<!-- discord-fixed-in: abc1234 -->' }]],
  ]));
  const done = await run({ eventName: PR, fetchImpl: f, env, log: quiet,
    payload: { action: 'closed', repository, pull_request: pr({ merged: true, merge_commit_sha: 'abc1234' }) } });
  assert.equal(done.length, 0);
  assert.equal(f.calls.filter((c) => c.method !== 'GET').length, 0, 'no label, comment or Discord write');
});

test('a merge that lands while In progress is being written wins', async () => {
  let reads = 0;
  const f = fakeFetch(routes({}, [
    ['GET', /repos\/me\/one\/issues\/17$/, () => (++reads === 1 ? issue(17) : issue(17, { labels: [{ name: 'from-discord' }, { name: 'pending-release' }] }))],
  ]));
  const done = await run({ eventName: PR, fetchImpl: f, env, log: quiet, payload: { action: 'opened', repository, pull_request: pr() } });
  assert.equal(done.length, 0);
  assert.equal(f.calls.filter((c) => /discord\.com/.test(c.url)).length, 0);
});

test('a failed issue read on a PR fails the job instead of passing silently', async () => {
  const f = fakeFetch(routes({}, [['GET', /repos\/me\/one\/issues\/17$/, () => new Response('slow down', { status: 403 })]]));
  await assert.rejects(run({ eventName: PR, fetchImpl: f, env, log: quiet,
    payload: { action: 'closed', repository, pull_request: pr({ merged: true, merge_commit_sha: 'abc1234' }) } }), /#17/);
});

test('a moved release tag ships nothing', async () => {
  const f = fakeFetch(routes({}, [['GET', /\/issues\?state=all/, () => [issue(17)]]]));
  const done = await run({ eventName: 'push', fetchImpl: f, env, log: quiet, payload: { ref: 'refs/tags/v5.0.120', created: false, forced: true, repository } });
  assert.equal(done.length, 0);
  assert.equal(f.calls.length, 0);
});

test('both labels with a newer fix not in the tag: pending again, not dropped', async () => {
  const f = fakeFetch(routes({}, [
    ['GET', /\/issues\?state=all.*labels=pending-release/, () => [issue(17, { labels: [{ name: 'from-discord' }, { name: 'pending-release' }, { name: 'shipped' }] })]],
    ['GET', /\/issues\/17\/comments/, () => [{ user: BOT, body: '<!-- discord-fixed-in: def5678 -->' }]],
    ['GET', /\/compare\/def5678\.\.\.v5\.0\.4$/, () => ({ status: 'behind' })],
  ]));
  const done = await run({ eventName: 'push', fetchImpl: f, env, log: quiet, payload: { ref: 'refs/tags/v5.0.4', repository } });
  assert.equal(done.length, 0);
  assert.equal(f.find('DELETE', /issues\/17\/labels\/shipped$/).length, 1);
  assert.equal(f.find('DELETE', /issues\/17\/labels\/pending-release$/).length, 0);
});

test('a ship that stopped after telling the player is finished without telling again', async () => {
  const f = fakeFetch(routes({}, [
    ['GET', /\/issues\?state=all.*labels=pending-release/, () => [issue(17, { labels: [{ name: 'from-discord' }, { name: 'pending-release' }, { name: 'shipped' }] })]],
  ]));
  const done = await run({ eventName: 'push', fetchImpl: f, env, log: quiet, payload: { ref: 'refs/tags/v5.0.2', repository } });
  assert.equal(done.length, 0);
  assert.equal(f.find('DELETE', /issues\/17\/labels\/pending-release/).length, 1);
  assert.equal(f.find('POST', /discord\.com.*messages$/).length, 0, 'no second message');
  assert.equal(f.find('PATCH', /channels\/700$/).at(-1).body.applied_tags.at(-1), 's-ship', 'the post says Shipped');
});

test('shipping adds the shipped label before it removes pending-release', async () => {
  const f = fakeFetch(routes({}, [['GET', /\/issues\?state=all.*labels=pending-release/, () => [issue(17)]]]));
  await run({ eventName: 'push', fetchImpl: f, env, log: quiet, payload: { ref: 'refs/tags/v5.0.3', repository } });
  const labelOps = f.calls.filter((c) => /issues\/17\/labels/.test(c.url)).map((c) => c.method);
  assert.deepEqual(labelOps, ['POST', 'DELETE']);
});

test('a tag event is checked against the commit it pushed, not where the tag points now', async () => {
  const f = fakeFetch(routes({}, [
    ['GET', /\/issues\?state=all.*labels=pending-release/, () => [issue(17)]],
    ['GET', /\/issues\/17\/comments/, () => [{ user: BOT, body: '<!-- discord-fixed-in: bbbbbbb -->' }]],
    ['GET', /\/compare\/bbbbbbb\.\.\.aaaa111$/, () => ({ status: 'behind' })],
    ['GET', /\/compare\/bbbbbbb\.\.\.discord-test-1$/, () => ({ status: 'ahead' })],
  ]));
  const done = await run({ eventName: 'push', fetchImpl: f, env: { ...env, RELEASE_TAG_PATTERN: '^discord-test-' }, log: quiet,
    payload: { ref: 'refs/tags/discord-test-1', created: true, after: 'aaaa111', repository } });
  assert.equal(done.length, 0, 'the commit this event pushed lacks the fix');
  assert.equal(f.find('GET', /compare\/bbbbbbb\.\.\.discord-test-1$/).length, 0);
});

test('an earlier fix missing from the tag holds the issue even when a later one is in it', async () => {
  const f = fakeFetch(routes({}, [
    ['GET', /\/issues\?state=all.*labels=pending-release/, () => [issue(17)]],
    ['GET', /\/issues\/17\/comments/, () => [
      { user: BOT, body: '<!-- discord-fixed-in: aaaaaaa -->' },
      { user: BOT, body: '<!-- discord-fixed-in: bbbbbbb -->' },
    ]],
    ['GET', /\/compare\/aaaaaaa\.\.\.v5\.0\.5$/, () => ({ status: 'behind' })],
    ['GET', /\/compare\/bbbbbbb\.\.\.v5\.0\.5$/, () => ({ status: 'ahead' })],
  ]));
  const done = await run({ eventName: 'push', fetchImpl: f, env, log: quiet, payload: { ref: 'refs/tags/v5.0.5', repository } });
  assert.equal(done.length, 0);
});

test('In progress written while a merge landed is put back to Fixed', async () => {
  let reads = 0;
  const f = fakeFetch(routes({}, [
    ['GET', /repos\/me\/one\/issues\/17$/, () => (++reads <= 2 ? issue(17) : issue(17, { labels: [{ name: 'from-discord' }, { name: 'pending-release' }] }))],
  ]));
  await run({ eventName: PR, fetchImpl: f, env, log: quiet, payload: { action: 'opened', repository, pull_request: pr() } });
  const tags = f.find('PATCH', /channels\/700$/).map((c) => c.body.applied_tags.at(-1));
  assert.deepEqual(tags, ['s-prog', 's-fix']);
});

test('a fix merged while a ship runs is pending again, not left with neither label', async () => {
  let reads = 0;
  const f = fakeFetch(routes({}, [
    ['GET', /\/issues\?state=all.*labels=pending-release/, () => [issue(17)]],
    ['GET', /\/issues\/17\/comments/, () => (++reads === 1
      ? [{ user: BOT, body: '<!-- discord-fixed-in: aaaaaaa -->' }]
      : [{ user: BOT, body: '<!-- discord-fixed-in: aaaaaaa -->' }, { user: BOT, body: '<!-- discord-fixed-in: bbbbbbb -->' }])],
    ['GET', /\/compare\/aaaaaaa\.\.\.v5\.0\.6$/, () => ({ status: 'ahead' })],
    ['GET', /\/compare\/bbbbbbb\.\.\.v5\.0\.6$/, () => ({ status: 'behind' })],
  ]));
  await run({ eventName: 'push', fetchImpl: f, env, log: quiet, payload: { ref: 'refs/tags/v5.0.6', repository } });
  const ops = f.calls.filter((c) => /issues\/17\/labels/.test(c.url))
    .map((c) => `${c.method} ${c.method === 'POST' ? c.body.labels[0] : c.url.split('/').pop()}`);
  assert.deepEqual(ops, ['POST shipped', 'DELETE pending-release', 'POST pending-release', 'DELETE shipped']);
  assert.equal(f.find('PATCH', /channels\/700$/).at(-1).body.applied_tags.at(-1), 's-fix');
});

test('a merge adds pending-release even when the issue already showed it', async () => {
  // Read mid-ship: both labels, so a ship may be about to remove pending.
  const f = fakeFetch(routes({ 17: issue(17, { labels: [{ name: 'from-discord' }, { name: 'pending-release' }, { name: 'shipped' }] }) }));
  await run({ eventName: PR, fetchImpl: f, env, log: quiet,
    payload: { action: 'closed', repository, pull_request: pr({ merged: true, merge_commit_sha: 'ccc1234' }) } });
  assert.deepEqual(f.find('POST', /issues\/17\/labels$/)[0].body, { labels: ['pending-release'] });
});

test('an annotated tag is checked against the commit it points at', async () => {
  const f = fakeFetch(routes({}, [
    ['GET', /\/issues\?state=all.*labels=pending-release/, () => [issue(17)]],
    ['GET', /\/issues\/17\/comments/, () => [{ user: BOT, body: '<!-- discord-fixed-in: bbbbbbb -->' }]],
    ['GET', /\/compare\/bbbbbbb\.\.\.c0ffee1$/, () => ({ status: 'ahead' })],
  ]));
  const done = await run({ eventName: 'push', fetchImpl: f, env, log: quiet,
    payload: { ref: 'refs/tags/v5.0.7', created: true, after: '7a90b1e', head_commit: { id: 'c0ffee1' }, repository } });
  assert.equal(done.length, 1);
});
