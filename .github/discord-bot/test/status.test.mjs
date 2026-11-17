import test from 'node:test';
import assert from 'node:assert/strict';
import { run } from '../status/status.mjs';
import { world, shippedIn } from './fake-world.mjs';

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
  assert.deepEqual(w.said('717'), ["Good news: a fix for this is being worked on and tested. We'll post here when it's done."]);
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

test('an issue closed by a commit is pending-release and the post says Fixed, once', async () => {
  const w = world();
  w.issue(17);
  w.close(17, 'completed', 'aaaaaaa1');
  await closed(w, 17);
  assert.deepEqual(labels(w, 17), ['pending-release']);
  assert.equal(w.tagOf('717'), 'Fixed, next update');
  assert.deepEqual(w.said('717'), ["This is fixed! The fix will be in the next update. We'll post here when that update is out."]);
  assert.match(w.issues.get(17).comments[0].body, /<!-- discord-told: fixed-aaaaaaa1 -->/);
  assert.match(w.issues.get(17).comments[0].body, /^Delivery confirmed: This is fixed!/);
});

test('an issue closed by merging a PR, whose closed event carries no commit, is Fixed by the merge commit', async () => {
  const w = world();
  w.issue(17);
  w.close(17, 'completed', null, { pr: 'ccccccc3' });
  await closed(w, 17);
  assert.deepEqual(labels(w, 17), ['pending-release']);
  assert.equal(w.tagOf('717'), 'Fixed, next update');
  w.tags = [{ name: 'v5.0.1', commit: { sha: 'c-v5.0.1' } }];
  w.contains.set('ccccccc3...c-v5.0.1', 'ahead');
  await tag(w, 'v5.0.1');
  assert.equal(w.tagOf('717'), 'Shipped');
});

test('a closer that is an unmerged PR is no fix; a closer that is a commit here is', async () => {
  const w = world();
  w.issue(17);
  w.close(17, 'completed', null, { pr: 'eeeeeee5', merged: false });
  await closed(w, 17);
  assert.deepEqual(labels(w, 17), []);
  assert.equal(w.tagOf('717'), 'Closed');
  const w2 = world();
  w2.issue(17);
  w2.close(17, 'completed', null, { commit: 'fffffff6' });
  await closed(w2, 17);
  assert.deepEqual(labels(w2, 17), ['pending-release']);
  assert.equal(w2.tagOf('717'), 'Fixed, next update');
});

test('a PR merged in another repository is not this repo\'s fix', async () => {
  const w = world();
  w.issue(17);
  w.close(17, 'completed', null, { pr: 'ddddddd4', repo: 'someone/else' });
  await closed(w, 17);
  assert.deepEqual(labels(w, 17), []);
  assert.equal(w.tagOf('717'), 'Closed');
});

test('a duplicate links the other report\'s Discord post', async () => {
  const w = world();
  w.issue(17);
  w.issue(18);
  w.close(17, 'duplicate', null, null, 18);
  await closed(w, 17);
  assert.deepEqual(w.said('717'), ["This is the same problem as another report (https://discord.com/channels/800/718), so we'll follow it there and close this one. Thanks for reporting it!"]);
});

test('a duplicate of an issue with no Discord post, not filed by the bot, or in another repo, goes out without a link', async () => {
  const marked = '<!-- discord-thread: 718 reporter: 42 -->';
  for (const dup of [
    { body: 'filed on GitHub', labels: ['from-discord'] },
    { body: marked, labels: [] },
    { body: marked, labels: ['from-discord'], repo: 'someone/else' },
  ]) {
    const w = world();
    w.issue(17);
    w.thread('718');
    w.close(17, 'duplicate', null, null, dup);
    await closed(w, 17);
    assert.match(w.said('717')[0], /same problem as another report, so/, JSON.stringify(dup));
  }
});

test('a duplicate or not-planned close is told even while GitHub GraphQL is down', async () => {
  for (const [reason, said] of [['duplicate', /same problem as another report, so/], ['not_planned', /decided not to change this/]]) {
    const w = world();
    w.issue(17);
    w.issue(18);
    w.close(17, reason, null, null, reason === 'duplicate' ? 18 : null);
    w.fail.push(['POST', /graphql$/, new Response('{}', { status: 502 }), 99]);
    await closed(w, 17);
    assert.equal(w.tagOf('717'), 'Closed', reason);
    assert.match(w.said('717')[0] || '', said, reason);
  }
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
  assert.deepEqual(w.said('717'), ["A moderator has closed this. If it's still happening for you, reply here and we'll take another look."]);
});

test('closing as not planned or duplicate tells the player', async () => {
  for (const [reason, said] of [['not_planned', /decided not to change this/], ['duplicate', /same problem as another report,/]]) {
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
  assert.deepEqual(labels(w, 17), ['pending-release']);
  assert.equal(w.tagOf('717'), 'Fixed, next update');
  Object.assign(w.issues.get(17), { state: 'open', state_reason: 'reopened' });
  await go(w, 'issues', { action: 'reopened', issue: { number: 17 } });
  assert.deepEqual(labels(w, 17), []);
  assert.equal(w.tagOf('717'), 'Triaged');
  assert.equal(w.said('717').length, 1, 'reopening tells no one');
});

// ---- Shipped ---------------------------------------------------------------

test('a release tag holding the fix ships the issue and names the version, once', async () => {
  const w = world();
  w.issue(17);
  w.close(17, 'completed', 'aaaaaaa1');
  await closed(w, 17);
  w.contains.set('aaaaaaa1...c-v5.0.2', 'ahead');
  await tag(w, 'v5.0.2');
  await tag(w, 'v5.0.2');
  assert.deepEqual(labels(w, 17), ['shipped']);
  assert.equal(w.tagOf('717'), 'Shipped');
  const bodies = w.issues.get(17).comments.map((c) => c.body);
  assert.equal(bodies.filter((b) => /<!-- discord-shipped-in: v5\.0\.2 fixes: aaaaaaa1 -->/.test(b)).length, 1, 'one ship record');
  assert.equal(bodies.length, 3, 'told Fixed, the ship record, told Shipped');
  assert.match(w.said('717').at(-1), /out in one v5\.0\.2/);
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

test('a tag that does not hold the fix leaves the issue pending', async () => {
  const w = world();
  w.issue(17);
  w.close(17, 'completed', 'bbbbbbb2');
  await closed(w, 17);
  w.contains.set('bbbbbbb2...c-v5.0.2', 'behind');
  await tag(w, 'v5.0.2');
  assert.deepEqual(labels(w, 17), ['pending-release']);
  assert.equal(w.tagOf('717'), 'Fixed, next update');
  assert.equal(w.said('717').length, 1);
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
  await tag(w, 'v5.1.0-beta.1');
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
  w.record(17, shippedIn('v9.9.9', ['aaaaaaa1']), 'outsider');
  w.record(17, '<!-- discord-told: fixed-aaaaaaa1 -->', 'outsider');
  w.close(17, 'completed', 'aaaaaaa1');
  await closed(w, 17);
  assert.deepEqual(labels(w, 17), ['pending-release'], 'the outsider\'s ship record is ignored');
  assert.equal(w.said('717').length, 1, 'the outsider\'s told record does not silence the bot');
  w.contains.set('aaaaaaa1...c-v5.0.2', 'ahead');
  await tag(w, 'v5.0.2');
  assert.deepEqual(labels(w, 17), ['shipped']);
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
  assert.equal(w.said('717').filter((m) => /out in /.test(m)).length, 0, 'no Shipped message for the old fix');
});

test('a ship of an old fix, then a reopen and a new fix before the tag run settles, sends no Shipped message', async () => {
  const w = world();
  w.issue(17);
  w.close(17, 'completed', 'aaaaaaa1');
  await closed(w, 17);
  w.contains.set('aaaaaaa1...c-v5.0.2', 'ahead');
  w.contains.set('bbbbbbb2...c-v5.0.2', 'behind');
  let raced = false;
  w.hooks.push(['POST', /issues\/17\/comments$/, async (call) => {
    if (raced || !/shipped-in: v5\.0\.2/.test(call.body.body)) return;
    raced = true;
    // The fix did not hold: reopened, then closed by a new commit.
    Object.assign(w.issues.get(17), { state: 'open', state_reason: 'reopened' });
    await go(w, 'issues', { action: 'reopened', issue: { number: 17 } });
    w.close(17, 'completed', 'bbbbbbb2');
    await closed(w, 17);
  }]);
  await tag(w, 'v5.0.2');
  assert.ok(raced);
  assert.deepEqual(labels(w, 17), ['pending-release'], 'bbbbbbb2 is not in v5.0.2');
  assert.equal(w.tagOf('717'), 'Fixed, next update');
  assert.equal(w.said('717').filter((m) => /out in /.test(m)).length, 0);
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
  assert.equal(w.said('717').filter((m) => /worked on/.test(m)).length, 0, 'the stale In progress is not sent');
  assert.equal(w.said('717').filter((m) => /out in /.test(m)).length, 1);
});

// ---- Sweep -----------------------------------------------------------------

test('the daily sweep in report mode lists what is wrong and changes nothing', async () => {
  const w = world();
  w.issue(17);
  w.close(17, 'completed', 'aaaaaaa1');
  const out = [];
  await run({ eventName: 'schedule', payload: { schedule: '17 9 * * *' }, env: { ...env, SWEEP_MODE: 'report', GITHUB_REPOSITORY: 'me/one' }, fetchImpl: w.fetch, log: (s) => out.push(s) });
  assert.deepEqual(labels(w, 17), []);
  assert.equal(w.tagOf('717'), 'Triaged');
  assert.ok(out.some((s) => /#17: labels \(none\) -> pending-release; post Triaged -> Fixed, next update/.test(s)), out.join('\n'));
});

test('the daily sweep in fix mode repairs labels and posts without telling anyone', async () => {
  const w = world();
  w.issue(17, { labels: ['from-discord', 'shipped', 'pending-release'] });
  w.close(17, 'completed', 'aaaaaaa1');
  await run({ eventName: 'schedule', payload: { schedule: '17 9 * * *' }, env: { ...env, SWEEP_MODE: 'fix', GITHUB_REPOSITORY: 'me/one' }, fetchImpl: w.fetch, log: quiet });
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
  await run({ eventName: 'schedule', payload: { schedule: '17 9 * * *' }, env: { ...env, SWEEP_MODE: 'fix', GITHUB_REPOSITORY: 'me/one' }, fetchImpl: w.fetch, log: quiet });
  assert.deepEqual(labels(w, 17), ['pending-release']);
});

// ---- needs-info --------------------------------------------------------------

test('needs-info reopens an archived post, then pings only the reporter', async () => {
  const w = world();
  const i = w.issue(17);
  i.labels.add('needs-info');
  await go(w, 'issues', { action: 'labeled', label: { name: 'needs-info' }, issue: { number: 17, body: i.body, labels: [{ name: 'from-discord' }] } });
  assert.equal(w.threads.get('717').archived, false);
  const m = w.threads.get('717').messages[0];
  assert.match(m.content, /^<@42> /);
  assert.deepEqual(m.allowed_mentions, { parse: [], users: ['42'] });
});

// ---- Message ownership, closing commits, missing tags -----------------------------

test('a merged PR and the close it causes, in either order, tell the player once: Fixed', async () => {
  for (const prFirst of [true, false]) {
    const w = world();
    w.issue(17);
    w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [17] });
    await prEvent(w, 5);
    w.prs.get(5).state = 'MERGED';
    w.close(17, 'completed', 'aaaaaaa1');
    if (prFirst) { await prEvent(w, 5, 'closed'); await closed(w, 17); } else { await closed(w, 17); await prEvent(w, 5, 'closed'); }
    assert.deepEqual(w.said('717'), ["Good news: a fix for this is being worked on and tested. We'll post here when it's done.", "This is fixed! The fix will be in the next update. We'll post here when that update is out."], `prFirst=${prFirst}`);
    assert.equal(w.tagOf('717'), 'Fixed, next update');
  }
});

test('two close runs at once send the Fixed message once', async () => {
  const w = world();
  w.issue(17);
  w.close(17, 'completed', 'aaaaaaa1');
  let raced = false;
  w.hooks.push(['PATCH', /channels\/717$/, async () => {
    if (raced) return;
    raced = true;
    await closed(w, 17);
  }]);
  await closed(w, 17);
  assert.ok(raced);
  assert.equal(w.said('717').filter((m) => /next update/.test(m)).length, 1);
});

test('an issue reopened after shipping, then closed by hand, is Closed and says so, not Shipped again', async () => {
  const w = world();
  w.issue(17);
  w.close(17, 'completed', 'aaaaaaa1');
  await closed(w, 17);
  w.contains.set('aaaaaaa1...c-v5.0.2', 'ahead');
  await tag(w, 'v5.0.2');
  Object.assign(w.issues.get(17), { state: 'open', state_reason: 'reopened' });
  await go(w, 'issues', { action: 'reopened', issue: { number: 17 } });
  w.close(17, 'completed', null);
  await closed(w, 17);
  assert.deepEqual(labels(w, 17), []);
  assert.equal(w.tagOf('717'), 'Closed');
  assert.equal(w.said('717').at(-1), "A moderator has closed this. If it's still happening for you, reply here and we'll take another look.");
  assert.equal(w.said('717').filter((m) => /out in /.test(m)).length, 1);
});

test('a commit in another repo that closed the issue is not taken as its fix', async () => {
  const w = world();
  w.issue(17);
  w.close(17, 'completed', 'ddddddd4');
  w.issues.get(17).events.at(-1).commit_url = 'https://api.github.com/repos/me/other/commits/ddddddd4';
  await closed(w, 17);
  assert.deepEqual(labels(w, 17), []);
  assert.equal(w.tagOf('717'), 'Closed');
  assert.deepEqual(w.said('717'), ["A moderator has closed this. If it's still happening for you, reply here and we'll take another look."]);
});

test('a forum missing a status tag does not repeat the message on every sync', async () => {
  const w = world();
  w.issue(17);
  w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [17] });
  const noProg = w.fetch;
  w.fetch = async (url, init) => {
    const r = await noProg(url, init);
    if (/channels\/900$/.test(url)) {
      const forum = await r.json();
      forum.available_tags = forum.available_tags.filter((t) => t.name !== 'In progress');
      return new Response(JSON.stringify(forum));
    }
    return r;
  };
  await prEvent(w, 5);
  await prEvent(w, 5, 'reopened');
  assert.deepEqual(w.said('717'), []);
  assert.equal(w.tagOf('717'), 'Triaged');
});

// ---- Recovery ------------------------------------------------------------------

test('a tag run ships a just-closed issue the close run has not labeled yet', async () => {
  const w = world();
  w.issue(17);
  w.close(17, 'completed', 'aaaaaaa1');
  w.contains.set('aaaaaaa1...c-v5.0.2', 'ahead');
  await tag(w, 'v5.0.2');
  assert.deepEqual(labels(w, 17), ['shipped']);
  assert.match(w.said('717').at(-1), /v5\.0\.2/);
});

test('a shipped issue with no ship record (shipped before records existed) stays shipped, from a close run or the sweep', async () => {
  for (const via of ['close run', 'sweep']) {
    const w = world();
    w.issue(17, { labels: ['from-discord', 'shipped'] });
    w.close(17, 'completed', 'aaaaaaa1');
    w.thread('717', { applied_tags: ['t-retail', 's-ship'] });
    w.tags = [{ name: 'nightly', commit: { sha: 'n1' } }, { name: 'v5.0.1', commit: { sha: 'c-v5.0.1' } }];
    w.contains.set('aaaaaaa1...c-v5.0.1', 'ahead');
    w.contains.set('aaaaaaa1...n1', 'ahead');
    if (via === 'close run') await closed(w, 17);
    else await run({ eventName: 'schedule', payload: {}, env: { ...env, SWEEP_MODE: 'fix', GITHUB_REPOSITORY: 'me/one' }, fetchImpl: w.fetch, log: quiet });
    assert.deepEqual(labels(w, 17), ['shipped'], via);
    assert.equal(w.tagOf('717'), 'Shipped', via);
    assert.ok(w.issues.get(17).comments.some((c) => /discord-shipped-in: v5\.0\.1 fixes: aaaaaaa1/.test(c.body)), `${via}: the record is rebuilt from the release tag, not the nightly`);
    assert.deepEqual(w.said('717'), [], via);
  }
});

test('the sweep reports a post with no status tag, and a missing ship record, into the job summary', async () => {
  const { mkdtempSync, readFileSync } = await import('node:fs');
  const { join } = await import('node:path');
  const { tmpdir } = await import('node:os');
  const summary = join(mkdtempSync(join(tmpdir(), 'sweep-')), 'summary.md');
  const w = world();
  w.issue(17);
  w.thread('717', { applied_tags: ['t-retail'] });
  w.issue(18, { labels: ['from-discord', 'shipped'] });
  w.close(18, 'completed', 'bbbbbbb2');
  w.thread('718', { applied_tags: ['s-fix'] });
  w.issue(19, { labels: ['from-discord', 'pending-release'] });
  w.close(19, 'completed', 'ccccccc3');
  w.thread('719', { applied_tags: ['s-fix'] });
  w.tags = [{ name: 'v5.0.1', commit: { sha: 'c-v5.0.1' } }];
  w.contains.set('bbbbbbb2...c-v5.0.1', 'ahead');
  await run({ eventName: 'schedule', payload: {}, env: { ...env, GITHUB_REPOSITORY: 'me/one', GITHUB_STEP_SUMMARY: summary }, fetchImpl: w.fetch, log: quiet });
  const text = readFileSync(summary, 'utf8');
  assert.match(text, /2 of 3 issue\(s\) out of step/);
  assert.match(text, /#17: post \(no status\) -> Triaged/);
  assert.match(text, /#18: ship record missing \(v5\.0\.1 holds the fix\); post Fixed, next update -> Shipped/);
  assert.equal(w.issues.get(18).comments.length, 0, 'report mode writes nothing');
  assert.equal(w.find('GET', /compare\/ccccccc3/).length, 1, 'a pending fix is checked against the newest release only');
});

test('the close run and a tag run that holds the fix, interleaved, tell the player once', async () => {
  for (const tagFirst of [true, false]) {
    const w = world();
    w.issue(17);
    w.close(17, 'completed', 'aaaaaaa1');
    w.contains.set('aaaaaaa1...c-v5.0.2', 'ahead');
    let raced = false;
    // The other run moves the post before this one reads it.
    w.hooks.push(['GET', /channels\/717$/, async () => {
      if (raced) return;
      raced = true;
      if (tagFirst) await closed(w, 17); else await tag(w, 'v5.0.2');
    }]);
    if (tagFirst) await tag(w, 'v5.0.2'); else await closed(w, 17);
    assert.ok(raced);
    assert.equal(w.tagOf('717'), 'Shipped', `tagFirst=${tagFirst}`);
    assert.equal(w.said('717').filter((m) => /out in /.test(m)).length, 1, `tagFirst=${tagFirst}: Shipped once`);
    assert.ok(w.said('717').length >= 1);
  }
});

test('a member PR on a reopened issue says In progress, and a second PR says nothing new', async () => {
  const w = world();
  w.issue(17);
  w.close(17, 'completed', 'aaaaaaa1');
  await closed(w, 17);
  Object.assign(w.issues.get(17), { state: 'open', state_reason: 'reopened' });
  w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [17] });
  await go(w, 'issues', { action: 'reopened', issue: { number: 17 } });
  assert.equal(w.tagOf('717'), 'In progress');
  w.prs.set(6, { author_association: 'MEMBER', state: 'OPEN', closes: [17] });
  await prEvent(w, 6);
  assert.equal(w.said('717').filter((m) => /worked on/.test(m)).length, 1);
});

test('a PR that closes an issue in another repo leaves this repo\'s issue of that number alone', async () => {
  const w = world();
  w.issue(17);
  w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [{ number: 17, repository: { nameWithOwner: 'me/other' } }] });
  await prEvent(w, 5);
  assert.equal(w.tagOf('717'), 'Triaged');
  assert.deepEqual(w.said('717'), []);
});

// ---- Stale and failed messages, paging, re-checks --------------------------------

test('a rerun of the needs-info event pings the reporter once', async () => {
  const w = world();
  const i = w.issue(17);
  i.labels.add('needs-info');
  const ev = { action: 'labeled', label: { name: 'needs-info' }, issue: { number: 17, body: i.body, updated_at: '2026-11-16T12:00:00Z' } };
  await go(w, 'issues', ev);
  await go(w, 'issues', ev);
  assert.equal(w.said('717').length, 1);
});

test('a Shipped message that went stale before sending is dropped, not sent', async () => {
  const w = world();
  w.issue(17);
  w.close(17, 'completed', 'aaaaaaa1');
  await closed(w, 17);
  w.contains.set('aaaaaaa1...c-v5.0.2', 'ahead');
  w.contains.set('bbbbbbb2...c-v5.0.2', 'behind');
  let raced = false;
  w.hooks.push(['POST', /issues\/17\/comments$/, async (call) => {
    if (raced || !/discord-told: shipped-/.test(call.body.body)) return;
    raced = true;
    Object.assign(w.issues.get(17), { state: 'open', state_reason: 'reopened' });
    await go(w, 'issues', { action: 'reopened', issue: { number: 17 } });
    w.close(17, 'completed', 'bbbbbbb2');
    await closed(w, 17);
  }]);
  await tag(w, 'v5.0.2');
  assert.ok(raced);
  assert.equal(w.said('717').filter((m) => /out in /.test(m)).length, 0);
  assert.ok(w.issues.get(17).comments.some((c) => /discord-told: shipped-[\s\S]*discord-dropped/.test(c.body)));
  assert.ok(w.issues.get(17).comments.some((c) => /^Dropped \(no longer true\): The fix is out/.test(c.body)));
});

test('a message whose send failed is listed by the sweep, which sends nothing', async () => {
  const w = world();
  w.issue(17);
  w.close(17, 'completed', 'aaaaaaa1');
  w.fail.push(['POST', /channels\/717\/messages$/, new Response('{}', { status: 500 }), 1]);
  await assert.rejects(closed(w, 17), /#17/);
  w.clock += 60 * 60 * 1000;
  const out = [];
  await run({ eventName: 'schedule', payload: {}, env: { ...env, SWEEP_MODE: 'fix', GITHUB_REPOSITORY: 'me/one' }, fetchImpl: w.fetch, log: (s) => out.push(s), now: () => w.clock });
  assert.deepEqual(w.said('717'), []);
  assert.match(out.join('\n'), /#17: message "This is fixed! The fix will be in the next update\. We.ll post here when that update is out\." may not have reached the player \(https:\/\/github\.com\/me\/one\/issues\/17#issuecomment-\d+\)/);
  assert.ok(w.issues.get(17).comments.some((c) => /^Unconfirmed \(the send failed; the player may not have it\): This is fixed!/.test(c.body)));
});

test('a Shipped message for an old release is dropped when the issue has shipped again in a newer one', async () => {
  const w = world();
  w.issue(17);
  w.close(17, 'completed', 'aaaaaaa1');
  await closed(w, 17);
  w.contains.set('aaaaaaa1...c-v5.0.2', 'ahead');
  w.contains.set('bbbbbbb2...c-v5.0.3', 'ahead');
  let raced = false;
  w.hooks.push(['POST', /issues\/17\/comments$/, async (call) => {
    if (raced || !/discord-told: shipped-v5\.0\.2/.test(call.body.body)) return;
    raced = true;
    // Before the v5.0.2 message goes out: reopened, fixed again, shipped in v5.0.3.
    Object.assign(w.issues.get(17), { state: 'open', state_reason: 'reopened' });
    await go(w, 'issues', { action: 'reopened', issue: { number: 17 } });
    w.close(17, 'completed', 'bbbbbbb2');
    await closed(w, 17);
    await tag(w, 'v5.0.3');
  }]);
  await tag(w, 'v5.0.2');
  assert.ok(raced);
  assert.equal(w.said('717').filter((m) => /v5\.0\.2/.test(m)).length, 0, 'no stale v5.0.2 message');
  assert.equal(w.said('717').filter((m) => /v5\.0\.3/.test(m)).length, 1);
});

test('a tag run re-checks a new fix that closed the issue while it ran', async () => {
  const w = world();
  w.issue(17);
  w.close(17, 'completed', 'aaaaaaa1');
  await closed(w, 17);
  w.contains.set('aaaaaaa1...c-v5.0.2', 'ahead');
  w.contains.set('bbbbbbb2...c-v5.0.2', 'ahead');
  let raced = false;
  w.hooks.push(['POST', /issues\/17\/comments$/, async (call) => {
    if (raced || !/shipped-in: v5\.0\.2 fixes: aaaaaaa1/.test(call.body.body)) return;
    raced = true;
    w.close(17, 'completed', 'bbbbbbb2');
  }]);
  await tag(w, 'v5.0.2');
  assert.ok(raced);
  assert.deepEqual(labels(w, 17), ['shipped']);
  assert.equal(w.tagOf('717'), 'Shipped');
});

test('lists are followed past their first page: recent issues, tags and linked PRs', async () => {
  const w = world();
  for (let n = 100; n < 205; n++) { w.issue(n); w.close(n, 'not_planned', null); }
  w.issue(17);
  w.close(17, 'completed', 'aaaaaaa1');
  w.contains.set('aaaaaaa1...c-v5.0.2', 'ahead');
  await tag(w, 'v5.0.2');
  assert.equal(w.tagOf('717'), 'Shipped', 'an issue on the second page of recent closes ships');

  const w2 = world();
  w2.issue(17, { labels: ['from-discord', 'shipped'] });
  w2.close(17, 'completed', 'aaaaaaa1');
  w2.tags = Array.from({ length: 150 }, (_, i) => ({ name: `other-${i}`, commit: { sha: `o${i}` } }));
  w2.tags.push({ name: 'v5.0.1', commit: { sha: 'c-v5.0.1' } });
  w2.contains.set('aaaaaaa1...c-v5.0.1', 'ahead');
  await run({ eventName: 'schedule', payload: {}, env: { ...env, SWEEP_MODE: 'fix', GITHUB_REPOSITORY: 'me/one' }, fetchImpl: w2.fetch, log: quiet });
  assert.deepEqual(labels(w2, 17), ['shipped'], 'a release tag on the second page is found');

  const w3 = world();
  w3.pageSize = 1;
  w3.issue(17);
  w3.issue(18);
  w3.prs.set(4, { author_association: 'NONE', state: 'OPEN', closes: [17] });
  w3.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [18, 17] });
  await prEvent(w3, 5);
  assert.equal(w3.tagOf('717'), 'In progress', 'the member PR on the second page counts');
  assert.equal(w3.tagOf('718'), 'In progress');
});

test('more release tags than the pages hold fail the sweep rather than unship the issue', async () => {
  const w = world();
  w.issue(17, { labels: ['from-discord', 'shipped'] });
  w.close(17, 'completed', 'aaaaaaa1');
  w.tags = Array.from({ length: 1000 }, (_, i) => ({ name: `other-${i}`, commit: { sha: `o${i}` } }));
  w.tags.push({ name: 'v5.0.1', commit: { sha: 'c-v5.0.1' } });
  await assert.rejects(run({ eventName: 'schedule', payload: {}, env: { ...env, SWEEP_MODE: 'fix', GITHUB_REPOSITORY: 'me/one' }, fetchImpl: w.fetch, log: quiet }));
  assert.deepEqual(labels(w, 17), ['shipped']);
});

test('a needs-info event that runs after the label was taken off pings no one', async () => {
  const w = world();
  const i = w.issue(17);
  await go(w, 'issues', { action: 'labeled', label: { name: 'needs-info' }, issue: { number: 17, body: i.body, updated_at: '2026-11-16T12:00:00Z' } });
  assert.deepEqual(w.said('717'), []);
  i.labels.add('needs-info');
  await go(w, 'issues', { action: 'labeled', label: { name: 'needs-info' }, issue: { number: 17, body: i.body, updated_at: '2026-11-16T12:05:00Z' } });
  assert.equal(w.said('717').length, 1);
});

test('a needs-info label taken off while the run claims its ping sends nothing', async () => {
  const w = world();
  const i = w.issue(17);
  i.labels.add('needs-info');
  w.hooks.push(['POST', /issues\/17\/comments$/, async (call) => {
    if (/discord-told: needs-info/.test(call.body.body)) i.labels.delete('needs-info');
  }]);
  await go(w, 'issues', { action: 'labeled', label: { name: 'needs-info' }, issue: { number: 17, body: i.body, updated_at: '2026-11-16T12:00:00Z' } });
  assert.deepEqual(w.said('717'), []);
  assert.ok(i.comments.some((c) => /discord-dropped/.test(c.body)));
});

// ---- A fix a release already holds -------------------------------------------------

const RELEASES = [
  { name: 'v5.0.3', commit: { sha: 'c-v5.0.3' }, annotated: true },
  { name: 'v5.0.2', commit: { sha: 'c-v5.0.2' } },
  { name: 'v5.0.1', commit: { sha: 'c-v5.0.1' } },
];

test('a fix whose close comes after its release tag run is announced as Shipped, not Fixed', async () => {
  const w = world();
  w.issue(17);
  w.tags = [{ name: 'v5.0.2', commit: { sha: 'c-v5.0.2' } }, { name: 'v5.0.1', commit: { sha: 'c-v5.0.1' } }];
  w.contains.set('aaaaaaa1...c-v5.0.2', 'ahead');
  await tag(w, 'v5.0.2');
  w.close(17, 'completed', 'aaaaaaa1');
  await closed(w, 17);
  assert.deepEqual(labels(w, 17), ['shipped']);
  assert.equal(w.tagOf('717'), 'Shipped');
  assert.deepEqual(w.said('717'), ['The fix is out in one v5.0.2. Update your addons, and let us know here if you still see the problem.']);
});

test('the release named is the oldest of the newest tags that hold the fix, an annotated tag checked at its commit', async () => {
  const w = world();
  w.issue(17);
  w.tags = RELEASES;
  w.contains.set('aaaaaaa1...c-v5.0.3', 'ahead');
  w.contains.set('aaaaaaa1...c-v5.0.2', 'ahead');
  w.close(17, 'completed', 'aaaaaaa1');
  await closed(w, 17);
  assert.match(w.said('717')[0], /out in one v5\.0\.2\./);
});

test('a fix in no release costs one compare and is Fixed', async () => {
  const w = world();
  w.issue(17);
  w.tags = RELEASES;
  w.close(17, 'completed', 'bbbbbbb2');
  await closed(w, 17);
  assert.equal(w.find('GET', /compare\/bbbbbbb2/).length, 1);
  assert.equal(w.tagOf('717'), 'Fixed, next update');
});

test('a release check that cannot be read fails the run instead of announcing Fixed', async () => {
  const w = world();
  w.issue(17);
  w.close(17, 'completed', 'aaaaaaa1');
  w.fail.push(['POST', /graphql$/, new Response('{}', { status: 502 }), 99]);
  await assert.rejects(closed(w, 17), /#17/);
  assert.deepEqual(w.said('717'), []);
});

test('a tag run names the oldest release holding an unrecorded fix, as the close run and the sweep do', async () => {
  const w = world();
  w.issue(17);
  w.tags = RELEASES;
  w.contains.set('aaaaaaa1...c-v5.0.3', 'ahead');
  w.contains.set('aaaaaaa1...c-v5.0.2', 'ahead');
  w.close(17, 'completed', 'aaaaaaa1');
  await tag(w, 'v5.0.3');
  assert.ok(w.issues.get(17).comments.some((c) => /discord-shipped-in: v5\.0\.2 fixes: aaaaaaa1/.test(c.body)));
  assert.match(w.said('717').at(-1), /out in one v5\.0\.2\./);
});

// ---- Notes and owed messages --------------------------------------------------------

const RUN = { GITHUB_RUN_ID: '555' };
const closeRun = (w, over) => go(w, 'issues', { action: 'closed', issue: { number: 17 } }, over);
const sweepFix = (w, out) => run({ eventName: 'schedule', payload: {}, env: { ...env, SWEEP_MODE: 'fix', GITHUB_REPOSITORY: 'me/one' }, fetchImpl: w.fetch, log: (s) => out.push(s), now: () => w.clock });
const fixedNotes = (w) => w.issues.get(17).comments.filter((c) => /discord-told: fixed-/.test(c.body));
const refuseTagWrite = (w) => w.fail.push(['PATCH', /channels\/717$/, new Response('{"message":"Missing Permissions"}', { status: 403 }), 1]);
// The forum has no Fixed tag while `gone()` says so.
const withoutFixedTag = (w, gone) => {
  const real = w.fetch;
  w.fetch = async (url, init) => {
    const r = await real(url, init);
    if (!gone() || !/channels\/900$/.test(url)) return r;
    const forum = await r.json();
    forum.available_tags = forum.available_tags.filter((t) => t.name !== 'Fixed, next update');
    return new Response(JSON.stringify(forum));
  };
};

test('of two runs that write a note for one message at once, the later drops its own note', async () => {
  const w = world();
  w.issue(17);
  w.close(17, 'completed', 'aaaaaaa1');
  let raced = false;
  w.hooks.push(['POST', /issues\/17\/comments$/, async (call) => {
    if (raced || !/discord-told: fixed-/.test(call.body.body)) return;
    raced = true;
    await closed(w, 17);
  }]);
  await closed(w, 17);
  assert.ok(raced);
  assert.equal(w.said('717').length, 1);
  assert.deepEqual(fixedNotes(w).map((c) => c.body.split(':')[0]), ['Delivery confirmed', 'Dropped (another run claimed it)']);
});

test('a message stopped by a setup problem stays owed: the sweep leaves the post, and a re-run of that run sends it', async () => {
  for (const problem of ['tag write refused', 'forum has no tag']) {
    const w = world();
    w.issue(17);
    w.close(17, 'completed', 'aaaaaaa1');
    let broken = true;
    if (problem === 'tag write refused') {
      refuseTagWrite(w);
      await assert.rejects(closeRun(w, RUN), /#17/);
    } else {
      withoutFixedTag(w, () => broken);
      await closeRun(w, RUN);
    }
    assert.equal(w.tagOf('717'), 'Triaged', problem);
    assert.deepEqual(w.said('717'), [], problem);
    assert.match(fixedNotes(w)[0].body, /^Notification attempted: This is fixed!/, problem);

    broken = false;
    // A sweep right after the failure leaves the post too.
    await sweepFix(w, []);
    assert.equal(w.tagOf('717'), 'Triaged', `${problem}: an immediate sweep leaves the post`);
    w.clock += 60 * 60 * 1000;
    const out = [];
    await sweepFix(w, out);
    assert.match(out.join('\n'), /#17: .*owed message "This is fixed!.*re-run https:\/\/github\.com\/me\/one\/actions\/runs\/555/, problem);
    assert.equal(w.tagOf('717'), 'Triaged', `${problem}: the sweep leaves the post`);
    assert.deepEqual(labels(w, 17), ['pending-release'], problem);

    await closeRun(w, RUN);
    assert.equal(w.tagOf('717'), 'Fixed, next update', problem);
    assert.equal(w.said('717').length, 1, problem);
    assert.equal(fixedNotes(w).length, 1, `${problem}: the re-run sends the owed note and writes no new one`);
    assert.match(fixedNotes(w)[0].body, /^Delivery confirmed: This is fixed!/, problem);
  }
});

test('an owed message is sent by a re-run of its run even after another run or a sweep moved the post', async () => {
  for (const mover of ['another run', 'a sweep at its tag write']) {
    const w = world();
    w.issue(17);
    w.close(17, 'completed', 'aaaaaaa1');
    refuseTagWrite(w);
    if (mover === 'another run') {
      await assert.rejects(closeRun(w, RUN), /#17/);
      await closeRun(w, { GITHUB_RUN_ID: '556' });
    } else {
      // The close run writes its note and its tag write is refused just
      // before the sweep's own tag write, which then succeeds.
      let raced = false;
      w.hooks.push(['PATCH', /channels\/717$/, async () => {
        if (raced) return;
        raced = true;
        await assert.rejects(closeRun(w, RUN), /#17/);
      }]);
      await sweepFix(w, []);
      assert.ok(raced, mover);
    }
    assert.equal(w.tagOf('717'), 'Fixed, next update', mover);
    assert.deepEqual(w.said('717'), [], `${mover} sends nothing`);
    assert.equal(fixedNotes(w).length, 1, mover);
    await closeRun(w, RUN);
    assert.equal(w.said('717').length, 1, `${mover}: the re-run sends the owed message`);
    assert.match(fixedNotes(w)[0].body, /^Delivery confirmed: This is fixed!/, mover);
    await closeRun(w, RUN);
    assert.equal(w.said('717').length, 1, `${mover}: a second re-run sends nothing more`);
  }
});

test('a message that went out before its note was marked sent is never sent again', async () => {
  const w = world();
  w.issue(17);
  w.close(17, 'completed', 'aaaaaaa1');
  // The send succeeds, and the edit that marks the note sent fails.
  w.hooks.push(['POST', /channels\/717\/messages$/, async () => {
    w.fail.push(['PATCH', /issues\/comments\/\d+$/, new Response('{"message":"Server Error"}', { status: 500 }), 1]);
  }]);
  await assert.rejects(closeRun(w, RUN), /#17/);
  assert.equal(w.said('717').length, 1);
  await closeRun(w, RUN);
  assert.equal(w.said('717').length, 1, 'the re-run does not take over a note marked as sending');
  w.clock += 60 * 60 * 1000;
  const out = [];
  await sweepFix(w, out);
  assert.match(out.join('\n'), /message "This is fixed!.*" may not have reached the player \(https:/);
});

test('a re-run of a tag run days later still finds the issue it owes a message, and sends it once', async () => {
  const w = world();
  w.issue(17, { labels: ['from-discord', 'pending-release'] });
  w.close(17, 'completed', 'aaaaaaa1');
  w.tags = [{ name: 'v5.0.3', commit: { sha: 'c-v5.0.3' } }];
  w.contains.set('aaaaaaa1...c-v5.0.3', 'ahead');
  refuseTagWrite(w);
  const tagRun = (over) => run({
    eventName: 'push',
    payload: { repository, ref: 'refs/tags/v5.0.3', created: true, after: 'obj-v5.0.3', head_commit: { id: 'c-v5.0.3' } },
    env: { ...env, ...RUN, ...over }, fetchImpl: w.fetch, log: quiet, now: () => w.clock,
  });
  await assert.rejects(tagRun({ GITHUB_RUN_ATTEMPT: '1' }), /#17/);
  assert.deepEqual(labels(w, 17), ['shipped']);
  assert.deepEqual(w.said('717'), []);
  // Three days on, the issue is neither pending nor recently closed.
  w.clock += 3 * 24 * 60 * 60 * 1000;
  await tagRun({ GITHUB_RUN_ATTEMPT: '2' });
  assert.equal(w.tagOf('717'), 'Shipped');
  assert.equal(w.said('717').length, 1);
  await tagRun({ GITHUB_RUN_ATTEMPT: '3' });
  assert.equal(w.said('717').length, 1, 'a later attempt sends nothing more');
});

test('a re-run of a needs-info run whose ping never went out pings once', async () => {
  const w = world();
  const i = w.issue(17);
  i.labels.add('needs-info');
  const ev = { action: 'labeled', label: { name: 'needs-info' }, issue: { number: 17, body: i.body, updated_at: '2026-11-16T12:00:00Z' } };
  refuseTagWrite(w); // the post's reopen is refused once
  await assert.rejects(go(w, 'issues', ev, RUN), /-> 403/);
  assert.deepEqual(w.said('717'), []);
  await go(w, 'issues', ev, RUN);
  await go(w, 'issues', ev, RUN);
  assert.equal(w.said('717').length, 1);
});

test('an old Told the player status note lists as possibly unsent, and is never held, dropped or resent', async () => {
  for (const reopened of [false, true]) {
    const w = world();
    w.issue(17);
    w.close(17, 'completed', 'aaaaaaa1');
    if (reopened) Object.assign(w.issues.get(17), { state: 'open', state_reason: 'reopened' });
    // The older `Told the player` note: no run, no outcome mark.
    const legacy = 'Told the player: This is fixed!\n\n<!-- discord-told: fixed-aaaaaaa1 -->\n<!-- discord-told-status: Fixed, next update -->';
    const note = w.record(17, legacy);
    w.clock += 60 * 60 * 1000;
    const out = [];
    await sweepFix(w, out);
    assert.match(out.join('\n'), /message "This is fixed!" may not have been sent \(https:[^;]*$/m, `reopened: ${reopened}`);
    assert.doesNotMatch(out.join('\n'), /owed message/);
    assert.equal(note.body, legacy, `reopened: ${reopened}: the note is left as it is`);
    assert.equal(w.tagOf('717'), reopened ? 'Triaged' : 'Fixed, next update', 'the fix-mode sweep repairs the post');
    assert.deepEqual(w.said('717'), []);
  }
});

test('a note whose run GitHub no longer lets re-run holds nothing, however new the note', async () => {
  const DAY = 24 * 60 * 60 * 1000;
  const run = (w, over) => w.runs.set('555', { id: 555, status: 'completed', run_attempt: 1, created_at: new Date(w.start).toISOString(), ...over });
  for (const [why, setup] of [
    // The note comes from a late attempt; the run's first attempt was 31 days ago.
    ['30 days since the first attempt', (w) => run(w, { run_attempt: 2, created_at: new Date(w.clock - 31 * DAY).toISOString() })],
    ['50 re-runs used', (w) => run(w, { run_attempt: 51 })],
    ['run deleted', (w) => w.fail.push(['GET', /actions\/runs\/555$/, new Response('{"message":"Not Found"}', { status: 404 }), 1])],
  ]) {
    const w = world();
    w.issue(17);
    w.close(17, 'completed', 'aaaaaaa1');
    refuseTagWrite(w);
    await assert.rejects(closeRun(w, RUN), /#17/);
    setup(w);
    const out = [];
    await sweepFix(w, out);
    assert.match(out.join('\n'), /message "This is fixed!.*" was not sent .*can no longer be re-run/, why);
    assert.equal(w.tagOf('717'), 'Fixed, next update', `${why}: the sweep repairs the post`);
    assert.deepEqual(w.said('717'), [], why);
  }
});

test('a note whose run is still queued or running is neither listed nor dropped, and its post is held', async () => {
  for (const [status, reopened] of [['queued', false], ['in_progress', false], ['in_progress', true]]) {
    const why = `${status}${reopened ? ', issue reopened' : ''}`;
    const w = world();
    w.issue(17);
    w.close(17, 'completed', 'aaaaaaa1');
    refuseTagWrite(w);
    await assert.rejects(closeRun(w, RUN), /#17/);
    w.runs.set('555', { id: 555, status, run_attempt: 1, created_at: new Date(w.start).toISOString() });
    if (reopened) Object.assign(w.issues.get(17), { state: 'open', state_reason: 'reopened' });
    // Well past ten minutes: the run's state decides, not the note's age.
    w.clock += 60 * 60 * 1000;
    const out = [];
    await sweepFix(w, out);
    assert.doesNotMatch(out.join('\n'), /This is fixed!/, why);
    assert.match(fixedNotes(w)[0].body, /^Notification attempted: /, `${why}: the note is left for its run`);
    assert.equal(w.tagOf('717'), 'Triaged', `${why}: the post is left as it is`);
    assert.deepEqual(w.said('717'), [], why);
  }
});

test('the sweep reads old "Told the player" notes, a moderator\'s mark clears a note, and a losing duplicate is ignored', async () => {
  const w = world();
  w.issue(17);
  w.close(17, 'completed', 'aaaaaaa1');
  await closeRun(w, RUN);
  const UNC = 'Unconfirmed (the send failed; the player may not have it)';
  for (const [head, key, marks] of [
    ['Told the player', 'legacy-sent', '\n<!-- discord-sent -->'],
    ['Told the player', 'legacy-open', ''],
    [UNC, 'cleared', '\n<!-- discord-unconfirmed -->\n<!-- discord-sent -->'],
    [UNC, 'listed', '\n<!-- discord-unconfirmed -->'],
  ]) w.record(17, `${head}: News ${key}\n\n<!-- discord-told: ${key} -->${marks}`);
  // A losing run's later note for the confirmed message, whose Dropped edit
  // failed: only the first note of a message counts.
  w.record(17, 'Notification attempted: This is fixed!\n\n<!-- discord-told: fixed-aaaaaaa1 -->\n<!-- discord-told-status: Fixed, next update -->\n<!-- discord-told-run: 556 -->');
  w.clock += 60 * 60 * 1000;
  const out = [];
  await sweepFix(w, out);
  const said = out.join('\n');
  assert.doesNotMatch(said, /News legacy-sent|News cleared|This is fixed/);
  assert.match(said, /message "News legacy-open" may not have been sent \(https:/);
  assert.match(said, /message "News listed" may not have reached the player \(https:/);
});

test('an owed message no re-run could send is dropped by the fix-mode sweep, which then syncs quietly', async () => {
  const reopen = (w) => Object.assign(w.issues.get(17), { state: 'open', state_reason: 'reopened' });
  for (const [why, after, line, reason, wantLabels] of [
    ['reopened', reopen, /is no longer true/, 'no longer true', []],
    // Same status, another fix: a re-run of the first run could never adopt it.
    ['closed again by another fix', async (w) => {
      reopen(w);
      w.close(17, 'completed', 'bbbbbbb2');
      await closeRun(w, { GITHUB_RUN_ID: '556' });
    }, /is no longer true/, 'no longer true', ['pending-release']],
    ['post deleted', (w) => w.threads.delete('717'), /cannot be sent: the Discord post is gone/, 'the Discord post is gone', ['pending-release']],
  ]) {
    const w = world();
    w.issue(17);
    w.close(17, 'completed', 'aaaaaaa1');
    const thread = w.threads.get('717');
    refuseTagWrite(w);
    await assert.rejects(closeRun(w, RUN), /#17/);
    await after(w);
    const sent = thread.messages.length;
    w.clock += 60 * 60 * 1000;
    const out = [];
    await sweepFix(w, out);
    assert.match(out.join('\n'), new RegExp(`owed message "This is fixed!.*" ${line.source}`), why);
    assert.equal(fixedNotes(w)[0].body.split(':')[0], `Dropped (${reason})`, why);
    assert.deepEqual(labels(w, 17), wantLabels, why);
    assert.equal(thread.messages.length, sent, `${why}: the sweep sends nothing`);
  }
});

test('a note edited in the browser, with CRLF line ends, keeps its key and message when the bot rewrites it', async () => {
  const w = world();
  w.issue(17);
  w.close(17, 'completed', 'aaaaaaa1');
  refuseTagWrite(w);
  await assert.rejects(closeRun(w, RUN), /#17/);
  const note = fixedNotes(w)[0];
  note.body = note.body.replace(/\n/g, '\r\n');
  Object.assign(w.issues.get(17), { state: 'open', state_reason: 'reopened' });
  w.clock += 60 * 60 * 1000;
  await sweepFix(w, []);
  assert.equal(fixedNotes(w).length, 1, 'the note keeps its key');
  assert.match(fixedNotes(w)[0].body, /^Dropped \(no longer true\): This is fixed!/);
});

test('a needs-info ping whose label was taken off is dropped by the fix-mode sweep', async () => {
  const w = world();
  const i = w.issue(17);
  i.labels.add('needs-info');
  const ev = { action: 'labeled', label: { name: 'needs-info' }, issue: { number: 17, body: i.body, updated_at: '2026-11-16T12:00:00Z' } };
  refuseTagWrite(w); // the post's reopen is refused once
  await assert.rejects(go(w, 'issues', ev, RUN), /-> 403/);
  i.labels.delete('needs-info');
  w.clock += 60 * 60 * 1000;
  const out = [];
  await sweepFix(w, out);
  assert.match(out.join('\n'), /owed message "[\s\S]*" is no longer true/);
  assert.ok(i.comments.some((c) => /^Dropped \(no longer true\): /.test(c.body)));
  assert.deepEqual(w.said('717'), []);
});

test('a post with no status tag, overtaken while it settles, still gets its message once', async () => {
  const w = world();
  w.issue(17);
  w.thread('717', { applied_tags: ['t-retail'] });
  w.close(17, 'completed', 'aaaaaaa1');
  let patches = 0;
  w.hooks.push(['PATCH', /channels\/717$/, async () => {
    patches++;
    if (patches === 1) Object.assign(w.issues.get(17), { state: 'open', state_reason: 'reopened' });
    if (patches === 2) w.close(17, 'completed', 'aaaaaaa1');
  }]);
  // With a run id, the last settle adopts the first settle's note: it must still go out once.
  await closeRun(w, RUN);
  assert.equal(patches, 3);
  assert.equal(w.tagOf('717'), 'Fixed, next update');
  assert.deepEqual(w.said('717'), ["This is fixed! The fix will be in the next update. We'll post here when that update is out."]);
});

test('a needs-info ping to a deleted post drops its note', async () => {
  const w = world();
  const i = w.issue(17);
  i.labels.add('needs-info');
  w.threads.delete('717');
  await go(w, 'issues', { action: 'labeled', label: { name: 'needs-info' }, issue: { number: 17, body: i.body, updated_at: '2026-11-16T12:00:00Z' } });
  assert.ok(i.comments.some((c) => /^Dropped \(the Discord post is gone\): /.test(c.body)));
});
