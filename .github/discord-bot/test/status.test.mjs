import test from 'node:test';
import assert from 'node:assert/strict';
import { run } from '../status/status.mjs';
import { world, fixedIn, shippedIn } from './fake-world.mjs';

const env = { GITHUB_TOKEN: 'gh', DISCORD_BOT_TOKEN: 'bot', RELEASE_TAG_PATTERN: '^v\\d' };
const repository = { full_name: 'me/one', default_branch: 'dev' };
const quiet = () => {};
const PR = 'pull_request_target';
const labels = (w, n) => [...w.issues.get(n).labels].filter((l) => l !== 'from-discord').sort();

const go = (w, eventName, payload, over = {}) => run({ eventName, payload: { repository, ...payload }, env: { ...env, ...over }, fetchImpl: w.fetch, log: quiet });
const prEvent = (w, number, action = 'opened') => go(w, PR, { action, pull_request: { number } });
const closed = (w, n) => go(w, 'issues', { action: 'closed', issue: { number: n } });
const tag = (w, name, extra = {}) => go(w, 'push', { ref: `refs/tags/${name}`, created: true, after: `obj-${name}`, head_commit: { id: `c-${name}` }, ...extra });

// ---- In progress -----------------------------------------------------------

test('a member PR that will close the issue moves the post to In progress and says so once', async () => {
  const w = world();
  w.issue(17);
  w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [17] });
  await prEvent(w, 5);
  await prEvent(w, 5, 'reopened');
  assert.equal(w.tagOf('717'), 'In progress');
  assert.deepEqual(w.said('717'), ['A fix is up and being tested.']);
});

test('a PR from an outside author, or a draft, leaves the post where it is', async () => {
  for (const over of [{ author_association: 'NONE' }, { author_association: 'CONTRIBUTOR' }, { author_association: 'MEMBER', draft: true }]) {
    const w = world();
    w.issue(17);
    w.prs.set(5, { state: 'OPEN', closes: [17], ...over });
    await prEvent(w, 5);
    assert.equal(w.tagOf('717'), 'Triaged', JSON.stringify(over));
    assert.deepEqual(w.said('717'), [], JSON.stringify(over));
  }
});

test('a PR closed without merging puts the post back to Triaged, quietly', async () => {
  const w = world();
  w.issue(17);
  w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [17] });
  await prEvent(w, 5);
  w.prs.get(5).state = 'CLOSED';
  await prEvent(w, 5, 'closed');
  assert.equal(w.tagOf('717'), 'Triaged');
  assert.equal(w.said('717').length, 1);
});

test('issues the bot did not make are left alone', async () => {
  const w = world();
  w.issue(17, { labels: [] });
  w.issue(18, { body: 'no marker' });
  w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [17, 18] });
  await prEvent(w, 5);
  assert.equal(w.find('PATCH', /discord/).length, 0);
  assert.equal(w.find('POST', /discord/).length, 0);
});

// ---- Fixed: closed by a commit ----------------------------------------------

test('an issue closed by a commit records it, is pending-release and the post says Fixed', async () => {
  const w = world();
  w.issue(17);
  w.close(17, 'completed', 'aaaaaaa1');
  await closed(w, 17);
  assert.match(w.issues.get(17).comments[0].body, /<!-- discord-fixed-in: aaaaaaa1 -->/);
  assert.deepEqual(labels(w, 17), ['pending-release']);
  assert.equal(w.tagOf('717'), 'Fixed, next update');
  assert.deepEqual(w.said('717'), ['The fix is merged and will be in the next update.']);
});

test('rerunning the close records nothing twice and says nothing twice', async () => {
  const w = world();
  w.issue(17);
  w.close(17, 'completed', 'aaaaaaa1');
  await closed(w, 17);
  await closed(w, 17);
  assert.equal(w.issues.get(17).comments.length, 1);
  assert.equal(w.said('717').length, 1);
});

test('an issue closed by hand gets no release label and a neutral note', async () => {
  const w = world();
  w.issue(17);
  w.close(17, 'completed', null);
  await closed(w, 17);
  assert.deepEqual(labels(w, 17), []);
  assert.equal(w.tagOf('717'), 'Closed');
  assert.deepEqual(w.said('717'), ['Marked as done.']);
});

test('closing as not planned or duplicate tells the player', async () => {
  for (const [reason, said] of [['not_planned', /without a change/], ['duplicate', /duplicate/]]) {
    const w = world();
    w.issue(17);
    w.close(17, reason);
    await closed(w, 17);
    assert.equal(w.tagOf('717'), 'Closed', reason);
    assert.match(w.said('717')[0], said, reason);
  }
});

test('a reopened issue drops its release label and goes back to Triaged', async () => {
  const w = world();
  w.issue(17);
  w.close(17, 'completed', 'aaaaaaa1');
  await closed(w, 17);
  Object.assign(w.issues.get(17), { state: 'open', state_reason: 'reopened' });
  await go(w, 'issues', { action: 'reopened', issue: { number: 17 } });
  assert.deepEqual(labels(w, 17), []);
  assert.equal(w.tagOf('717'), 'Triaged');
});

// ---- Shipped ---------------------------------------------------------------

test('a release tag holding every fix ships the issue and names the version, once', async () => {
  const w = world();
  w.issue(17);
  w.close(17, 'completed', 'aaaaaaa1');
  await closed(w, 17);
  w.contains.set('aaaaaaa1...c-v5.0.2', 'ahead');
  await tag(w, 'v5.0.2');
  await tag(w, 'v5.0.2');
  assert.deepEqual(labels(w, 17), ['shipped']);
  assert.equal(w.tagOf('717'), 'Shipped');
  assert.match(w.issues.get(17).comments.at(-1).body, /<!-- discord-shipped-in: v5\.0\.2 fixes: aaaaaaa1 -->/);
  assert.equal(w.issues.get(17).comments.length, 2);
  assert.match(w.said('717').at(-1), /landed in one v5\.0\.2/);
  assert.equal(w.said('717').length, 2);
});

test('a tag is checked at the commit it points at, not its tag object or name', async () => {
  const w = world();
  w.issue(17);
  w.close(17, 'completed', 'aaaaaaa1');
  await closed(w, 17);
  w.contains.set('aaaaaaa1...obj-v5.0.2', 'ahead');
  w.contains.set('aaaaaaa1...v5.0.2', 'ahead');
  await tag(w, 'v5.0.2');
  assert.deepEqual(labels(w, 17), ['pending-release'], 'only the tagged commit counts');
});

test('a tag missing any recorded fix leaves the issue pending', async () => {
  const w = world();
  w.issue(17);
  w.record(17, fixedIn('aaaaaaa1'));
  w.record(17, fixedIn('bbbbbbb2'));
  w.close(17, 'completed', 'bbbbbbb2');
  await closed(w, 17);
  w.contains.set('bbbbbbb2...c-v5.0.2', 'ahead');
  await tag(w, 'v5.0.2');
  assert.deepEqual(labels(w, 17), ['pending-release']);
  assert.equal(w.tagOf('717'), 'Fixed, next update');
});

test('a fix after shipping is pending again, then ships with the next tag that holds it', async () => {
  const w = world();
  w.issue(17);
  w.close(17, 'completed', 'aaaaaaa1');
  await closed(w, 17);
  w.contains.set('aaaaaaa1...c-v5.0.2', 'ahead');
  await tag(w, 'v5.0.2');
  Object.assign(w.issues.get(17), { state: 'open', state_reason: 'reopened' });
  w.close(17, 'completed', 'bbbbbbb2');
  await closed(w, 17);
  assert.deepEqual(labels(w, 17), ['pending-release']);
  assert.equal(w.tagOf('717'), 'Fixed, next update');
  w.contains.set('aaaaaaa1...c-v5.0.3', 'ahead');
  w.contains.set('bbbbbbb2...c-v5.0.3', 'ahead');
  await tag(w, 'v5.0.3');
  assert.deepEqual(labels(w, 17), ['shipped']);
  assert.match(w.said('717').at(-1), /v5\.0\.3/);
});

test('deleted, moved and non-release tags do nothing', async () => {
  const w = world();
  w.issue(17);
  w.close(17, 'completed', 'aaaaaaa1');
  await closed(w, 17);
  const before = w.calls.length;
  await tag(w, 'v5.0.2', { deleted: true, created: false });
  await tag(w, 'v5.0.2', { created: false, forced: true });
  await tag(w, 'nightly-1');
  assert.equal(w.calls.length, before);
});

test('a deleted Discord post does not stop a release', async () => {
  const w = world();
  w.issue(17);
  w.issue(18);
  for (const n of [17, 18]) {
    w.close(n, 'completed', `aaaaaa${n}`);
    await closed(w, n);
    w.contains.set(`aaaaaa${n}...c-v5.0.2`, 'ahead');
  }
  w.threads.delete('717');
  await tag(w, 'v5.0.2');
  assert.deepEqual(labels(w, 17), ['shipped']);
  assert.deepEqual(labels(w, 18), ['shipped']);
  assert.equal(w.tagOf('718'), 'Shipped');
});

test('only the workflow\'s own records count, from every page', async () => {
  const w = world();
  w.issue(17);
  for (let i = 0; i < 120; i++) w.record(17, `chatter ${i}`, 'someone');
  w.record(17, fixedIn('aaaaaaa1'));
  w.record(17, fixedIn('ffffff99'), 'outsider');
  w.record(17, shippedIn('v9.9.9', ['aaaaaaa1']), 'outsider');
  w.close(17, 'completed', 'aaaaaaa1');
  await closed(w, 17);
  assert.deepEqual(labels(w, 17), ['pending-release'], 'the outsider\'s shipped record is ignored');
  w.contains.set('aaaaaaa1...c-v5.0.2', 'ahead');
  await tag(w, 'v5.0.2');
  assert.deepEqual(labels(w, 17), ['shipped'], 'the outsider\'s fix record does not hold it');
});

// ---- Races: two runs on one issue -------------------------------------------

test('a fix closed while a ship is writing labels ends pending, with the post at Fixed', async () => {
  const w = world();
  w.issue(17);
  w.close(17, 'completed', 'aaaaaaa1');
  await closed(w, 17);
  w.contains.set('aaaaaaa1...c-v5.0.2', 'ahead');
  let raced = false;
  w.hooks.push(['POST', /issues\/17\/labels$/, async (call) => {
    if (raced || !call.body.labels.includes('shipped')) return;
    raced = true;
    Object.assign(w.issues.get(17), { state: 'open' });
    w.close(17, 'completed', 'bbbbbbb2');
    await closed(w, 17);
  }]);
  await tag(w, 'v5.0.2');
  assert.ok(raced);
  assert.deepEqual(labels(w, 17), ['pending-release']);
  assert.equal(w.tagOf('717'), 'Fixed, next update');
});

test('a ship that lands while a fix run writes labels still ends with the right labels', async () => {
  const w = world();
  w.issue(17);
  w.record(17, fixedIn('aaaaaaa1'));
  w.issues.get(17).labels.add('pending-release');
  w.contains.set('aaaaaaa1...c-v5.0.2', 'ahead');
  w.contains.set('bbbbbbb2...c-v5.0.2', 'behind');
  let raced = false;
  w.hooks.push(['POST', /issues\/17\/comments$/, async (call) => {
    if (raced || !/fixed-in: bbbbbbb2/.test(call.body.body)) return;
    raced = true;
    await tag(w, 'v5.0.2');
  }]);
  w.close(17, 'completed', 'bbbbbbb2');
  await closed(w, 17);
  assert.ok(raced);
  assert.deepEqual(labels(w, 17), ['pending-release'], 'bbbbbbb2 is not in v5.0.2');
  assert.equal(w.tagOf('717'), 'Fixed, next update');
});

test('an In progress write that loses to a ship is put back to Shipped', async () => {
  const w = world();
  w.issue(17);
  w.close(17, 'completed', 'aaaaaaa1');
  await closed(w, 17);
  Object.assign(w.issues.get(17), { state: 'open' });
  w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [17] });
  let raced = false;
  w.hooks.push(['PATCH', /channels\/717$/, async () => {
    if (raced) return;
    raced = true;
    // The PR merges, closing the issue, and a release ships it.
    w.prs.get(5).state = 'MERGED';
    w.close(17, 'completed', 'ccccccc3');
    await closed(w, 17);
    w.contains.set('aaaaaaa1...c-v5.0.2', 'ahead');
    w.contains.set('ccccccc3...c-v5.0.2', 'ahead');
    await tag(w, 'v5.0.2');
  }]);
  await prEvent(w, 5);
  assert.ok(raced);
  assert.equal(w.tagOf('717'), 'Shipped');
});

// ---- Sweep -----------------------------------------------------------------

test('the daily sweep in report mode lists what is wrong and changes nothing', async () => {
  const w = world();
  w.issue(17);
  w.record(17, fixedIn('aaaaaaa1'));
  w.close(17, 'completed', 'aaaaaaa1');
  const out = [];
  await run({ eventName: 'schedule', payload: { repository }, env: { ...env, SWEEP_MODE: 'report' }, fetchImpl: w.fetch, log: (s) => out.push(s) });
  assert.deepEqual(labels(w, 17), []);
  assert.equal(w.tagOf('717'), 'Triaged');
  assert.ok(out.some((s) => /#17: labels \(none\) -> pending-release; post Triaged -> Fixed, next update/.test(s)), out.join('\n'));
});

test('the daily sweep in fix mode repairs labels and posts without telling anyone', async () => {
  const w = world();
  w.issue(17, { labels: ['from-discord', 'shipped', 'pending-release'] });
  w.record(17, fixedIn('aaaaaaa1'));
  w.close(17, 'completed', 'aaaaaaa1');
  await run({ eventName: 'schedule', payload: { repository }, env: { ...env, SWEEP_MODE: 'fix' }, fetchImpl: w.fetch, log: quiet });
  assert.deepEqual(labels(w, 17), ['pending-release']);
  assert.equal(w.tagOf('717'), 'Fixed, next update');
  assert.deepEqual(w.said('717'), []);
});

test('a failed write fails the job, and the next sweep repairs what it left', async () => {
  const w = world();
  w.issue(17);
  w.close(17, 'completed', 'aaaaaaa1');
  w.fail.push(['POST', /issues\/17\/labels$/, new Response('boom', { status: 502 }), 1]);
  await assert.rejects(closed(w, 17), /#17/);
  assert.deepEqual(labels(w, 17), []);
  await run({ eventName: 'schedule', payload: { repository }, env: { ...env, SWEEP_MODE: 'fix' }, fetchImpl: w.fetch, log: quiet });
  assert.deepEqual(labels(w, 17), ['pending-release']);
});

// ---- needs-info --------------------------------------------------------------

test('needs-info reopens an archived post, then pings only the reporter', async () => {
  const w = world();
  const i = w.issue(17);
  await go(w, 'issues', { action: 'labeled', label: { name: 'needs-info' }, issue: { number: 17, body: i.body, labels: [{ name: 'from-discord' }] } });
  assert.equal(w.threads.get('717').archived, false);
  const m = w.threads.get('717').messages[0];
  assert.match(m.content, /^<@42> /);
  assert.deepEqual(m.allowed_mentions, { parse: [], users: ['42'] });
});
