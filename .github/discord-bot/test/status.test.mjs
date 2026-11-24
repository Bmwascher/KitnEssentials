import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import { run } from '../status/status.mjs';
import { world, shippedIn } from './fake-world.mjs';
import { FORUM } from './fake-fetch.mjs';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const env = { GITHUB_TOKEN: 'gh', DISCORD_BOT_TOKEN: 'bot', RELEASE_TAG_PATTERN: '^v\\d' };
const repository = { full_name: 'me/one', default_branch: 'dev' };
const quiet = () => {};
const PR = 'pull_request_target';
const labels = (w, n) => [...w.issues.get(n).labels].filter((l) => l !== 'from-discord').sort();

const go = (w, eventName, payload, over = {}) => run({ eventName, payload: { repository, ...payload }, env: { ...env, ...over }, fetchImpl: w.fetch, log: quiet });
const prEvent = (w, number, action = 'opened') => go(w, PR, { action, pull_request: { number } });
const closed = (w, n) => go(w, 'issues', { action: 'closed', issue: { number: n } });
const tag = (w, name, extra = {}) => go(w, 'push', { ref: `refs/tags/${name}`, created: true, after: `obj-${name}`, head_commit: { id: `c-${name}` }, ...extra });

// Forum 900 answers without the named tags until the returned restore runs;
// a failed answer passes through as it is.
const dropTag = (w, ...names) => {
  const real = w.fetch;
  w.fetch = async (url, init = {}) => {
    const r = await real(url, init);
    if (!r.ok || !/discord\.com\/api\/v10\/channels\/900$/.test(url) || (init.method || 'GET') !== 'GET') return r;
    const forum = await r.json();
    forum.available_tags = forum.available_tags.filter((t) => !names.includes(t.name));
    return new Response(JSON.stringify(forum));
  };
  return () => { w.fetch = real; };
};
// Every job summary of this file's cases sits in one folder, removed at the end.
const SUMMARIES = mkdtempSync(join(tmpdir(), 'status-summary-'));
after(() => rmSync(SUMMARIES, { recursive: true }));
let summaries = 0;
const tmpSummary = () => {
  const p = join(SUMMARIES, `${++summaries}.md`);
  writeFileSync(p, '');
  return p;
};
// The setup section's problem lines, as the summary shows them. The section
// appears at most once, runs to the next heading (a sweep's report) or the
// end, and holds its bullets and the whole advice once.
const setupBullets = (path) => {
  const sections = readFileSync(path, 'utf8').split('### Discord status: setup problems\n').slice(1);
  if (!sections.length) return [];
  assert.equal(sections.length, 1, 'one setup section');
  const paragraphs = sections[0].slice(1).split(/\n(?=### )/)[0].replace(/\n$/, '').split('\n\n');
  assert.equal(paragraphs.length, 2, 'the bullets, then the advice, and nothing else');
  assert.equal(paragraphs[1], 'After fixing them, re-run this run. A run that owes a player a message sends it then; '
    + 'a message marked Unconfirmed is never sent again, and the sweep lists it.');
  return paragraphs[0].split('\n');
};

// ---- In progress -----------------------------------------------------------

test('a member PR that will close the issue moves the post to In progress and says so once', async () => {
  const w = world();
  w.issue(17);
  w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [17] });
  await prEvent(w, 5);
  await prEvent(w, 5, 'reopened');
  assert.equal(w.tagOf('717'), 'In progress');
  assert.deepEqual(w.said('717'), ["**In progress.** A fix for this is being worked on and tested. We'll post here when it's done."]);
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
  assert.deepEqual(w.said('717'), ["**Fixed!** The fix will be in the next update. We'll post here when that update is out."]);
  assert.match(w.issues.get(17).comments[0].body, /<!-- discord-told: fixed-aaaaaaa1 -->/);
  assert.match(w.issues.get(17).comments[0].body, /^Delivery confirmed: \*\*Fixed!\*\*/);
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
  assert.deepEqual(w.said('717'), ["**Duplicate.** This is the same problem as another report (https://discord.com/channels/800/718), so we'll follow it there and close this one. Thanks for reporting it!"]);
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
  assert.deepEqual(w.said('717'), ["**Closed.** A moderator has closed this. If it's still happening for you, reply here and we'll take another look."]);
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
  assert.match(w.said('717').at(-1), /Out now in one v5\.0\.2/);
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
  assert.equal(w.said('717').filter((m) => /Out now in /.test(m)).length, 0, 'no Shipped message for the old fix');
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
  assert.equal(w.said('717').filter((m) => /Out now in /.test(m)).length, 0);
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
  assert.equal(w.said('717').filter((m) => /Out now in /.test(m)).length, 1);
});

// ---- Sweep -----------------------------------------------------------------

test('the sweep in report mode lists what is wrong and changes nothing', async () => {
  const w = world();
  w.issue(17);
  w.close(17, 'completed', 'aaaaaaa1');
  const out = [];
  await run({ eventName: 'schedule', payload: { schedule: '17 9 * * *' }, env: { ...env, SWEEP_MODE: 'report', GITHUB_REPOSITORY: 'me/one' }, fetchImpl: w.fetch, log: (s) => out.push(s) });
  assert.deepEqual(labels(w, 17), []);
  assert.equal(w.tagOf('717'), 'Triaged');
  assert.ok(out.some((s) => /#17: labels \(none\) -> pending-release; post Triaged -> Fixed, next update/.test(s)), out.join('\n'));
});

test('the sweep in fix mode repairs labels and posts without telling anyone', async () => {
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
  assert.equal(m.message_reference, undefined, 'a mention, not a reply');
});

test('each status message replies to the filed message with a ping; an older issue only when its first message is the reporter\'s', async () => {
  const filedBody = '## Report\n\n> hi\n\n<!-- discord-message: 333 -->\n<!-- discord-thread: 717 reporter: 42 -->';
  const steps = [
    ['In progress', (w) => { w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [17] }); return prEvent(w, 5); }],
    ['Fixed', (w) => { w.close(17, 'completed', 'aaaaaaa1'); return closed(w, 17); }],
    ['Closed by hand', (w) => { w.close(17, 'completed', null); return closed(w, 17); }],
    ['Shipped', (w) => { w.close(17, 'completed', 'aaaaaaa1'); w.contains.set('aaaaaaa1...c-v5.0.2', 'ahead'); return tag(w, 'v5.0.2'); }],
  ];
  for (const [why, over, starter, target] of [
    ['filed with its message id', { body: filedBody }, null, '333'],
    ['older, its first message by the reporter', {}, { author: { id: '42' } }, '717'],
    ['older, its first message by someone else', {}, { author: { id: '43' } }, null],
    ['older, its first message unreadable', {}, null, null],
  ]) {
    for (const [status, step] of steps) {
      const w = world();
      w.issue(17, over);
      if (starter) w.threads.get('717').starter = starter;
      await step(w);
      const sent = w.threads.get('717').messages;
      const at = `${why}, ${status}`;
      assert.equal(sent.length, 1, at);
      if (target) {
        assert.deepEqual(sent[0].message_reference, { message_id: target, fail_if_not_exists: false }, at);
        assert.deepEqual(sent[0].allowed_mentions, { parse: [], users: [], replied_user: true }, at);
      } else {
        assert.equal(sent[0].message_reference, undefined, at);
        assert.deepEqual(sent[0].allowed_mentions, { parse: [], users: [] }, at);
      }
    }
  }
});

test('a re-run sends an older note in its own words, so the player and the note agree', async () => {
  const w = world();
  w.issue(17);
  w.close(17, 'completed', 'aaaaaaa1');
  w.record(17, 'Notification attempted: This is fixed! Old words.\n\n<!-- discord-told: fixed-aaaaaaa1 -->\n<!-- discord-told-status: Fixed, next update -->\n<!-- discord-told-run: 555 -->');
  await go(w, 'issues', { action: 'closed', issue: { number: 17 } }, { GITHUB_RUN_ID: '555', GITHUB_RUN_ATTEMPT: '2' });
  assert.deepEqual(w.said('717'), ['This is fixed! Old words.']);
  assert.match(w.issues.get(17).comments[0].body, /^Delivery confirmed: This is fixed! Old words\.\n/);
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
    assert.deepEqual(w.said('717'), ["**In progress.** A fix for this is being worked on and tested. We'll post here when it's done.", "**Fixed!** The fix will be in the next update. We'll post here when that update is out."], `prFirst=${prFirst}`);
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
  assert.equal(w.said('717').at(-1), "**Closed.** A moderator has closed this. If it's still happening for you, reply here and we'll take another look.");
  assert.equal(w.said('717').filter((m) => /Out now in /.test(m)).length, 1);
});

test('a commit in another repo that closed the issue is not taken as its fix', async () => {
  const w = world();
  w.issue(17);
  w.close(17, 'completed', 'ddddddd4');
  w.issues.get(17).events.at(-1).commit_url = 'https://api.github.com/repos/me/other/commits/ddddddd4';
  await closed(w, 17);
  assert.deepEqual(labels(w, 17), []);
  assert.equal(w.tagOf('717'), 'Closed');
  assert.deepEqual(w.said('717'), ["**Closed.** A moderator has closed this. If it's still happening for you, reply here and we'll take another look."]);
});

test('a forum missing a status tag does not repeat the message on every sync', async () => {
  const w = world();
  w.issue(17);
  w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [17] });
  dropTag(w, 'In progress');
  await assert.rejects(prEvent(w, 5), /forum 900 has no "In progress" tag: add it, spelled as the README lists it/);
  await assert.rejects(prEvent(w, 5, 'reopened'), /forum 900 has no "In progress" tag/);
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
  const summary = tmpSummary();
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
    assert.equal(w.said('717').filter((m) => /Out now in /.test(m)).length, 1, `tagFirst=${tagFirst}: Shipped once`);
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
  assert.equal(w.said('717').filter((m) => /Out now in /.test(m)).length, 0);
  assert.ok(w.issues.get(17).comments.some((c) => /discord-told: shipped-[\s\S]*discord-dropped/.test(c.body)));
  assert.ok(w.issues.get(17).comments.some((c) => /^Dropped \(no longer true\): \*\*Out now in/.test(c.body)));
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
  assert.match(out.join('\n'), /#17: message "\*\*Fixed!\*\* The fix will be in the next update\. We.ll post here when that update is out\." may not have reached the player \(https:\/\/github\.com\/me\/one\/issues\/17#issuecomment-\d+\)/);
  assert.ok(w.issues.get(17).comments.some((c) => /^Unconfirmed \(the send failed; the player may not have it\): \*\*Fixed!\*\*/.test(c.body)));
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
  // Posts 1100 to 1204: the fake's default 700 + n would reach the forum's id (900) and the server's (800).
  for (let n = 100; n < 205; n++) { w.issue(n, { thread: String(1000 + n) }); w.close(n, 'not_planned', null); }
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
  assert.deepEqual(w.said('717'), ['**Out now in one v5.0.2.** Update your addons, and let us know here if you still see the problem.']);
});

test('the release named is the oldest of the newest tags that hold the fix, an annotated tag checked at its commit', async () => {
  const w = world();
  w.issue(17);
  w.tags = RELEASES;
  w.contains.set('aaaaaaa1...c-v5.0.3', 'ahead');
  w.contains.set('aaaaaaa1...c-v5.0.2', 'ahead');
  w.close(17, 'completed', 'aaaaaaa1');
  await closed(w, 17);
  assert.match(w.said('717')[0], /Out now in one v5\.0\.2\./);
});

test('a fix in no release costs one compare per release check, a few checks per run, and is Fixed', async () => {
  const w = world();
  w.issue(17);
  w.tags = RELEASES;
  w.close(17, 'completed', 'bbbbbbb2');
  await closed(w, 17);
  // Each read of the issue checks the releases afresh: labels, post, message.
  const compares = w.find('GET', /compare\/bbbbbbb2/).length;
  const walks = w.find('POST', /graphql$/).filter((c) => /refs\(refPrefix/.test(c.body.query)).length;
  assert.equal(compares, walks);
  assert.ok(compares >= 1 && compares <= 6, `${compares} compares`);
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
  assert.match(w.said('717').at(-1), /Out now in one v5\.0\.2\./);
});

// ---- Notes and owed messages --------------------------------------------------------

const RUN = { GITHUB_RUN_ID: '555' };
const closeRun = (w, over) => go(w, 'issues', { action: 'closed', issue: { number: 17 } }, over);
const sweepFix = (w, out) => run({ eventName: 'schedule', payload: {}, env: { ...env, SWEEP_MODE: 'fix', GITHUB_REPOSITORY: 'me/one' }, fetchImpl: w.fetch, log: (s) => out.push(s), now: () => w.clock });
const fixedNotes = (w) => w.issues.get(17).comments.filter((c) => /discord-told: fixed-/.test(c.body));
const refuseTagWrite = (w) => w.fail.push(['PATCH', /channels\/717$/, new Response('{"message":"Missing Permissions"}', { status: 403 }), 1]);

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
    let restore = () => {};
    if (problem === 'tag write refused') {
      refuseTagWrite(w);
      await assert.rejects(closeRun(w, RUN), /#17/);
    } else {
      restore = dropTag(w, 'Fixed, next update');
      await assert.rejects(closeRun(w, RUN), /forum 900 has no "Fixed, next update" tag/);
    }
    assert.equal(w.tagOf('717'), 'Triaged', problem);
    assert.deepEqual(w.said('717'), [], problem);
    assert.match(fixedNotes(w)[0].body, /^Notification attempted: \*\*Fixed!\*\*/, problem);

    restore();
    // A sweep right after the failure leaves the post too.
    await sweepFix(w, []);
    assert.equal(w.tagOf('717'), 'Triaged', `${problem}: an immediate sweep leaves the post`);
    w.clock += 60 * 60 * 1000;
    const out = [];
    await sweepFix(w, out);
    assert.match(out.join('\n'), /#17: .*owed message "\*\*Fixed!\*\*.*re-run https:\/\/github\.com\/me\/one\/actions\/runs\/555/, problem);
    assert.equal(w.tagOf('717'), 'Triaged', `${problem}: the sweep leaves the post`);
    assert.deepEqual(labels(w, 17), ['pending-release'], problem);

    await closeRun(w, RUN);
    assert.equal(w.tagOf('717'), 'Fixed, next update', problem);
    assert.equal(w.said('717').length, 1, problem);
    assert.equal(fixedNotes(w).length, 1, `${problem}: the re-run sends the owed note and writes no new one`);
    assert.match(fixedNotes(w)[0].body, /^Delivery confirmed: \*\*Fixed!\*\*/, problem);
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
    assert.match(fixedNotes(w)[0].body, /^Delivery confirmed: \*\*Fixed!\*\*/, mover);
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
  assert.match(out.join('\n'), /message "\*\*Fixed!\*\*.*" may not have reached the player \(https:/);
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
    assert.match(out.join('\n'), /message "\*\*Fixed!\*\*.*" was not sent .*can no longer be re-run/, why);
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
    assert.doesNotMatch(out.join('\n'), /\*\*Fixed!\*\*/, why);
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
  assert.doesNotMatch(said, /News legacy-sent|News cleared|Fixed!|This is fixed/);
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
    assert.match(out.join('\n'), new RegExp(`owed message "\\*\\*Fixed!\\*\\*.*" ${line.source}`), why);
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
  assert.match(fixedNotes(w)[0].body, /^Dropped \(no longer true\): \*\*Fixed!\*\*/);
});

test('a sweep drop does not overwrite a note a re-run marked after the sweep read it', async () => {
  const w = world();
  w.issue(17);
  w.close(17, 'completed', 'aaaaaaa1');
  refuseTagWrite(w);
  await assert.rejects(closeRun(w, RUN), /#17/);
  Object.assign(w.issues.get(17), { state: 'open', state_reason: 'reopened' });
  w.clock += 60 * 60 * 1000;
  // The run's re-run marks the note while the sweep is judging it.
  w.hooks.push(['GET', /actions\/runs\/555$/, async () => {
    const note = fixedNotes(w)[0];
    note.body = `${note.body}\n<!-- discord-sending -->\n<!-- discord-unconfirmed -->`;
  }]);
  await sweepFix(w, []);
  assert.equal(fixedNotes(w).length, 1);
  assert.match(fixedNotes(w)[0].body, /<!-- discord-unconfirmed -->$/);
  assert.doesNotMatch(fixedNotes(w)[0].body, /^Dropped/);
});

test('two issues one fix closes, the second closing after a release, while one PR run settles both: the second is Shipped', async () => {
  const w = world();
  w.issue(17);
  w.issue(18);
  w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [17, 18] });
  const steps = [
    () => w.close(17, 'completed', 'aaaaaaa1'),
    () => {
      w.tags = [{ name: 'v5.0.2', commit: { sha: 'c-v5.0.2' } }];
      w.contains.set('aaaaaaa1...c-v5.0.2', 'ahead');
      w.close(18, 'completed', 'aaaaaaa1');
    },
  ];
  for (const [thread, step] of [['717', steps[0]], ['718', steps[1]]]) {
    let raced = false;
    w.hooks.push(['PATCH', new RegExp(`channels/${thread}$`), async () => {
      if (raced) return;
      raced = true;
      step();
    }]);
  }
  await prEvent(w, 5);
  assert.equal(w.tagOf('717'), 'Fixed, next update');
  assert.equal(w.tagOf('718'), 'Shipped');
  assert.deepEqual(w.said('718').filter((m) => /next update|This is fixed/.test(m)), []);
});

test('a release tagged while a close run writes its labels is announced as Shipped, with the shipped label', async () => {
  const w = world();
  w.issue(17);
  w.tags = RELEASES;
  w.close(17, 'completed', 'aaaaaaa1');
  let raced = false;
  // The tag run for this release finds nothing to do: the issue is not yet labeled.
  w.hooks.push(['POST', /issues\/17\/labels$/, async () => {
    if (raced) return;
    raced = true;
    w.tags = [{ name: 'v5.0.4', commit: { sha: 'c-v5.0.4' } }, ...RELEASES];
    w.contains.set('aaaaaaa1...c-v5.0.4', 'ahead');
  }]);
  await closed(w, 17);
  assert.ok(raced);
  assert.deepEqual(labels(w, 17), ['shipped']);
  assert.equal(w.tagOf('717'), 'Shipped');
  assert.deepEqual(w.said('717'), ['**Out now in one v5.0.4.** Update your addons, and let us know here if you still see the problem.']);
});

test('a re-run of a PR run sends the Shipped message it owes for an issue that closed while it ran', async () => {
  const w = world();
  w.issue(17);
  w.tags = [{ name: 'v5.0.2', commit: { sha: 'c-v5.0.2' } }];
  w.contains.set('aaaaaaa1...c-v5.0.2', 'ahead');
  w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [17] });
  let moves = 0;
  // The first move closes the issue; the Shipped move is then refused once.
  w.hooks.push(['PATCH', /channels\/717$/, async () => {
    moves++;
    if (moves === 1) w.close(17, 'completed', 'aaaaaaa1');
    if (moves === 2) refuseTagWrite(w);
  }]);
  const pr = (over) => go(w, PR, { action: 'opened', pull_request: { number: 5 } }, over);
  await assert.rejects(pr(RUN), /#17/);
  assert.equal(w.said('717').filter((m) => /Out now in/.test(m)).length, 0);
  await pr({ ...RUN, GITHUB_RUN_ATTEMPT: '2' });
  assert.equal(w.tagOf('717'), 'Shipped');
  assert.equal(w.said('717').filter((m) => /Out now in/.test(m)).length, 1);
});

test('a note a moderator marked dropped keeps its message closed, even after the sweep dropped it', async () => {
  for (const sweptFirst of [false, true]) {
    const w = world();
    w.issue(17);
    w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [17] });
    const pr = (over) => go(w, PR, { action: 'ready_for_review', pull_request: { number: 5 } }, over);
    refuseTagWrite(w);
    await assert.rejects(pr(RUN), /#17/);
    w.prs.get(5).draft = true;
    if (sweptFirst) {
      w.clock += 60 * 60 * 1000;
      await sweepFix(w, []);
    }
    // The moderator sends it by hand, or decides it is not needed, and marks the note.
    const note = w.issues.get(17).comments.find((c) => /discord-told: in-progress-/.test(c.body));
    note.body = `${note.body}\n<!-- discord-dropped -->`;
    w.prs.get(5).draft = false;
    await pr({ GITHUB_RUN_ID: '556' });
    assert.equal(w.tagOf('717'), 'In progress', `sweptFirst=${sweptFirst}`);
    assert.deepEqual(w.said('717'), [], `sweptFirst=${sweptFirst}: nothing sent`);
  }
});

test('an In progress note the sweep dropped does not stop the message when a PR is ready again', async () => {
  const w = world();
  w.issue(17);
  w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [17] });
  const pr = (over) => go(w, PR, { action: 'ready_for_review', pull_request: { number: 5 } }, over);
  refuseTagWrite(w);
  await assert.rejects(pr(RUN), /#17/);
  w.prs.get(5).draft = true;
  w.clock += 60 * 60 * 1000;
  await sweepFix(w, []);
  assert.ok(w.issues.get(17).comments.some((c) => /^Dropped \(no longer true\): /.test(c.body)));
  w.prs.get(5).draft = false;
  await pr({ GITHUB_RUN_ID: '556' });
  assert.equal(w.tagOf('717'), 'In progress');
  assert.deepEqual(w.said('717'), ["**In progress.** A fix for this is being worked on and tested. We'll post here when it's done."]);
});

test('a re-run does not send a note a moderator marked sent after the re-run took it over', async () => {
  const w = world();
  w.issue(17);
  w.close(17, 'completed', 'aaaaaaa1');
  refuseTagWrite(w);
  await assert.rejects(closeRun(w, RUN), /#17/);
  // The moderator sends it by hand and marks the note while the re-run moves the post.
  let marked = false;
  w.hooks.push(['PATCH', /channels\/717$/, async () => {
    if (marked) return;
    marked = true;
    const note = fixedNotes(w)[0];
    note.body = `${note.body}\n<!-- discord-sent -->`;
  }]);
  await closeRun(w, { ...RUN, GITHUB_RUN_ATTEMPT: '2' });
  assert.ok(marked);
  assert.equal(w.tagOf('717'), 'Fixed, next update');
  assert.deepEqual(w.said('717'), []);
  assert.match(fixedNotes(w)[0].body, /<!-- discord-sent -->$/);
});

test('an issue closed while a PR run settles its post, by a fix already released, is announced as Shipped', async () => {
  const w = world();
  w.issue(17);
  w.tags = [{ name: 'v5.0.2', commit: { sha: 'c-v5.0.2' } }];
  w.contains.set('aaaaaaa1...c-v5.0.2', 'ahead');
  w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [17] });
  let raced = false;
  w.hooks.push(['PATCH', /channels\/717$/, async () => {
    if (raced) return;
    raced = true;
    w.close(17, 'completed', 'aaaaaaa1');
  }]);
  await prEvent(w, 5);
  assert.ok(raced);
  assert.equal(w.tagOf('717'), 'Shipped');
  assert.deepEqual(w.said('717'), ['**Out now in one v5.0.2.** Update your addons, and let us know here if you still see the problem.']);
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
  assert.deepEqual(w.said('717'), ["**Fixed!** The fix will be in the next update. We'll post here when that update is out."]);
});

test('a needs-info ping to a deleted post drops its note', async () => {
  const w = world();
  const i = w.issue(17);
  i.labels.add('needs-info');
  w.threads.delete('717');
  await go(w, 'issues', { action: 'labeled', label: { name: 'needs-info' }, issue: { number: 17, body: i.body, updated_at: '2026-11-16T12:00:00Z' } });
  assert.ok(i.comments.some((c) => /^Dropped \(the Discord post is gone\): /.test(c.body)));
});

// ---- The opened run and the sweep --------------------------------------------------

const tagsOf = (w, id) => w.threads.get(id).applied_tags;
const sweepRun = (w, mode, out = [], over = {}) => run({
  eventName: 'schedule', payload: { schedule: '17 9 * * *' },
  env: { ...env, SWEEP_MODE: mode, GITHUB_REPOSITORY: 'me/one', ...over }, fetchImpl: w.fetch, log: (s) => out.push(s),
});
// A Fixed note another run (555) wrote and still owes.
const OWED = 'Notification attempted: x\n\n<!-- discord-told: fixed-aaaaaaa1 -->\n<!-- discord-told-status: Fixed, next update -->\n<!-- discord-told-run: 555 -->';

test('the sweep lists a post it cannot read, judges none of its notes, and fails at its end', async () => {
  for (const [why, read, status] of [
    ['the post read is refused', /discord\.com\/api\/v10\/channels\/717$/, 403],
    // A 404 from the post's forum says nothing about the post.
    ['the forum read answers 404', /discord\.com\/api\/v10\/channels\/900$/, 404],
  ]) {
    const w = world();
    w.issue(17);
    w.close(17, 'completed', 'aaaaaaa1');
    w.record(17, OWED);
    w.fail.push(['GET', read, new Response('{"message":"x"}', { status }), 1]);
    const out = [];
    await assert.rejects(sweepRun(w, 'fix', out), /#17/, why);
    assert.match(out.join('\n'), /#17: .*Discord post not read \(see the log\)/, why);
    assert.match(w.issues.get(17).comments[0].body, /^Notification attempted:/, `${why}: the owed note is not dropped`);
  }
});

test('a GitHub 404 while a status write claims its note fails the issue, and never reads as a deleted post', async () => {
  const w = world();
  w.issue(17);
  w.close(17, 'completed', 'aaaaaaa1');
  w.fail.push(['POST', /api\.github\.com\/repos\/me\/one\/issues\/17\/comments$/, new Response('{"message":"Not Found"}', { status: 404 }), 1]);
  const out = [];
  await assert.rejects(run({ eventName: 'issues', payload: { repository, action: 'closed', issue: { number: 17 } }, env, fetchImpl: w.fetch, log: (s) => out.push(s) }), /#17/);
  assert.doesNotMatch(out.join('\n'), /Discord post is gone/);
  assert.deepEqual(w.said('717'), []);
});

test('the issue\'s opened run sets the status GitHub calls for on a post that shows none, and tells no one', async () => {
  const w = world();
  w.issue(17);
  w.threads.get('717').applied_tags = ['t-retail'];
  await go(w, 'issues', { action: 'opened', issue: { number: 17 } });
  assert.equal(w.tagOf('717'), 'Triaged');
  assert.deepEqual(w.said('717'), []);
});

test('an opened run never drops a staff tag to show Triaged', async () => {
  const w = world();
  w.issue(17);
  // A late create left the post with no status and five tags of its own.
  const five = ['t-retail', 't-forever', 't-bug', 't-feedback', 't-staff'];
  w.threads.get('717').applied_tags = [...five];
  const out = [];
  await run({ eventName: 'issues', payload: { repository, action: 'opened', issue: { number: 17 } }, env, fetchImpl: w.fetch, log: (s) => out.push(s) });
  assert.deepEqual(tagsOf(w, '717'), five);
  assert.match(out.join('\n'), /#17: no free tag slot for "Triaged"/);
});

test('an opened run that starts after a fix PR opened tells In progress itself, and the PR\'s own run adds nothing', async () => {
  const w = world();
  w.issue(17);
  w.threads.get('717').applied_tags = ['t-retail'];
  w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [17] });
  const told = () => w.said('717').filter((m) => /worked on/.test(m)).length;
  const notes = () => w.issues.get(17).comments.filter((c) => /discord-told-status: In progress/.test(c.body)).length;
  await go(w, 'issues', { action: 'opened', issue: { number: 17 } });
  assert.equal(w.tagOf('717'), 'In progress', 'set by the opened run');
  assert.deepEqual([told(), notes()], [1, 1], 'told, with its note, by the opened run');
  await prEvent(w, 5);
  assert.equal(w.tagOf('717'), 'In progress');
  assert.deepEqual([told(), notes()], [1, 1], 'the PR\'s run adds neither');
});

// ---- Transfers -------------------------------------------------------------------

test('SS1: an opened event from a transfer is skipped by the status job and the checklist job', async () => {
  const changes = { old_issue: { html_url: 'https://github.com/me/two/issues/3' }, old_repository: { full_name: 'me/two' } };
  for (const over of [{}, { CHECKLIST_ONLY: '1', CHECKLIST_FORUM_ID: '950' }]) {
    const w = world();
    w.issue(17, { state: 'closed', state_reason: 'completed' });
    w.threads.get('717').applied_tags = ['t-retail'];
    const out = [];
    await run({ eventName: 'issues', payload: { repository, action: 'opened', issue: { number: 17 }, changes }, env: { ...env, ...over }, fetchImpl: w.fetch, log: (s) => out.push(s) });
    assert.deepEqual(w.calls, [], JSON.stringify(over));
    assert.match(out.join('\n'), /#17: opened by a transfer from https:\/\/github\.com\/me\/two\/issues\/3; nothing to do/, JSON.stringify(over));
  }
  const w = world();
  w.issue(17);
  w.threads.get('717').applied_tags = ['t-retail'];
  await go(w, 'issues', { action: 'opened', issue: { number: 17 } });
  assert.equal(w.tagOf('717'), 'Triaged', 'an opened event with no transfer runs as before');
});

// ---- The Accepted tag on the player's post -----------------------------------------

// Every tag name a post shows, in tag order.
const tagNames = (w, id) => w.threads.get(id).applied_tags.map((t) => FORUM.available_tags.find((x) => x.id === t).name);
const withLabel = (w, n) => w.issue(n, { labels: ['from-discord', 'accepted'] });
const closeByHand = async (w, n = 17) => {
  w.close(n, 'completed');
  await closed(w, n);
};
const reopen = async (w, n = 17) => {
  Object.assign(w.issues.get(n), { state: 'open', state_reason: 'reopened' });
  await go(w, 'issues', { action: 'reopened', issue: { number: n } });
};

test('AT5: a status move places or removes Accepted in its own write, and Accepted says nothing', async () => {
  {
    const w = world();
    withLabel(w, 17);
    await closeByHand(w);
    assert.deepEqual(tagNames(w, '717'), ['Retail', 'Bug', 'Closed'], 'a closed issue shows no Accepted');
    const before = w.find('PATCH', /channels\/717$/).length;
    await reopen(w);
    assert.equal(w.find('PATCH', /channels\/717$/).length - before, 1, 'the reopen writes once');
    assert.deepEqual(tagNames(w, '717'), ['Retail', 'Bug', 'Triaged', 'Accepted'], 'and places Accepted in that write');
    assert.equal(w.tagOf('717'), 'Triaged', 'the status reader passes over Accepted');
    assert.equal(w.said('717').length, 1, 'only the close spoke');
  }
  {
    const w = world();
    withLabel(w, 17);
    w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [17] });
    await prEvent(w, 5);
    assert.deepEqual(tagNames(w, '717'), ['Retail', 'Bug', 'In progress', 'Accepted']);
    assert.deepEqual(w.said('717'), ["**In progress.** A fix for this is being worked on and tested. We'll post here when it's done."]);
    w.prs.get(5).state = 'MERGED';
    w.close(17, 'completed', 'aaaaaaa1');
    const before = w.find('PATCH', /channels\/717$/).length;
    await closed(w, 17);
    assert.deepEqual(w.find('PATCH', /channels\/717$/).slice(before).map((c) => c.body.applied_tags), [['t-retail', 't-bug', 's-fix']],
      'the close removes Accepted in its one write');
    assert.deepEqual(tagNames(w, '717'), ['Retail', 'Bug', 'Fixed, next update']);
    assert.equal(w.said('717').length, 2, 'the Fixed message once');
    assert.match(w.said('717')[1], /^\*\*Fixed!\*\*/, 'and it is the Fixed message');
  }
  {
    const w = world();
    withLabel(w, 17);
    await go(w, 'issues', { action: 'opened', issue: { number: 17 } });
    assert.deepEqual(w.find('PATCH', /channels\/717$/), [], 'Triaged already shows: no write, so Accepted waits for the sweep');
  }
});

test('AT6: an accepted label added or removed starts nothing', async () => {
  for (const action of ['labeled', 'unlabeled']) {
    const w = world();
    withLabel(w, 17);
    w.threads.get('717').archived = false;
    await go(w, 'issues', { action, label: { name: 'accepted' }, issue: { number: 17 } });
    assert.deepEqual(w.calls.filter((c) => /discord\.com/.test(c.url)), [], `${action}: no Discord call`);
    assert.deepEqual(w.find('POST', /\/comments$/), [], `${action}: no comment`);
  }
});

test('AT7: the sweep lists each Accepted gap on an active post, and none on an archived or unread one', async () => {
  const inProgress = (w) => {
    w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [17] });
    w.threads.get('717').applied_tags = ['t-retail', 's-prog'];
  };
  for (const [why, setup, line] of [
    ['missing on a Triaged post', (w) => withLabel(w, 17), /^#17: post Accepted missing -> shown$/],
    ['shown on a Triaged post with the label off', (w) => { w.issue(17); w.threads.get('717').applied_tags = ['t-retail', 't-acc', 's-tri']; },
      /^#17: post Accepted shown -> removed$/],
    ['missing on an In progress post', (w) => { withLabel(w, 17); inProgress(w); },
      /^#17: post Accepted missing -> shown \(waits for the post's next status change\)$/],
    ['missing on a post showing Triaged beside Closed', (w) => { withLabel(w, 17); w.threads.get('717').applied_tags = ['t-retail', 's-tri', 's-closed']; },
      /^#17: post Accepted missing -> shown \(waits for the post's next status change\)$/],
    ['no free slot', (w) => { withLabel(w, 17); w.threads.get('717').applied_tags = ['t-retail', 't-bug', 't-forever', 't-staff', 's-tri']; },
      /^#17: no free tag slot for Accepted on the post$/],
  ]) {
    const w = world();
    setup(w);
    w.threads.get('717').archived = false;
    const out = [];
    await sweepRun(w, 'report', out);
    assert.match(out.find((l) => l.startsWith('#17: ')) || '', line, why);
    assert.deepEqual(w.find('PATCH', /channels\/717$/), [], `${why}: report mode writes nothing`);
  }
  const saved = FORUM.available_tags;
  FORUM.available_tags = saved.filter((t) => t.id !== 't-acc');
  try {
    const w = world();
    withLabel(w, 17);
    w.threads.get('717').archived = false;
    const out = [];
    await sweepRun(w, 'report', out);
    assert.match(out.find((l) => l.startsWith('#17: ')) || '', /^#17: the forum has no Accepted tag$/);
  } finally {
    FORUM.available_tags = saved;
  }
  {
    const w = world();
    withLabel(w, 17);
    const out = [];
    await sweepRun(w, 'report', out);
    assert.ok(!out.some((l) => /Accepted/.test(l)), 'an archived post is not listed for Accepted');
  }
  {
    const w = world();
    withLabel(w, 17);
    w.threads.get('717').archived = false;
    w.fail.push(['GET', /discord\.com\/api\/v10\/channels\/717$/, new Response('{"message":"x"}', { status: 403 }), 1]);
    const out = [];
    await assert.rejects(sweepRun(w, 'report', out), /#17/);
    assert.match(out.join('\n'), /#17: Discord post not read \(see the log\)/);
    assert.ok(!out.some((l) => /Accepted/.test(l)), 'an unread post gets no Accepted line');
  }
  {
    // A second, differently cased Accepted tag shows Accepted to the player.
    FORUM.available_tags = [...saved, { id: 't-acc2', name: 'ACCEPTED' }];
    try {
      for (const mode of ['report', 'fix']) {
        const w = world();
        withLabel(w, 17);
        w.threads.get('717').applied_tags = ['t-retail', 's-tri', 't-acc2'];
        w.threads.get('717').archived = false;
        const out = [];
        await sweepRun(w, mode, out);
        assert.ok(!out.some((l) => /Accepted/.test(l)), `${mode}: a post showing a second Accepted tag is in step`);
        assert.deepEqual(w.find('PATCH', /channels\/717$/), [], `${mode}: no write`);
      }
    } finally {
      FORUM.available_tags = saved;
    }
  }
});

test('AT8: a fix-mode sweep repairs Accepted only on a post showing Triaged alone, and an Accepted line alone moves no status', async () => {
  // Runs `fn` at the `at`-th read of the help forum: the sweep's read is the
  // first, the repair's two reads the second and third.
  const atForumRead = (w, at, fn) => {
    let k = 0;
    w.hooks.push(['GET', /discord\.com\/api\/v10\/channels\/900$/, async () => { if (++k === at) await fn(); }]);
  };
  const owing = (w) => w.runs.set('555', { id: 555, status: 'in_progress', run_attempt: 1, created_at: new Date(w.start).toISOString() });
  for (const [why, setup, patches, line] of [
    ['a Triaged post gets Accepted', (w) => withLabel(w, 17),
      [{ applied_tags: ['t-retail', 't-bug', 's-tri', 't-acc'] }], /^#17: post Accepted missing -> shown$/],
    ['the label off on an open Triaged issue: removed', (w) => { w.issue(17); w.threads.get('717').applied_tags = ['t-retail', 't-acc', 's-tri']; },
      [{ applied_tags: ['t-retail', 's-tri'] }], /^#17: post Accepted shown -> removed$/],
    ['an In progress post with only an Accepted gap: listed, not written',
      (w) => { withLabel(w, 17); w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [17] }); w.threads.get('717').applied_tags = ['t-retail', 's-prog']; },
      [], /^#17: post Accepted missing -> shown \(waits for the post's next status change\)$/],
    ['a post an owed note holds is left whole, Accepted included',
      (w) => { w.issue(17); w.close(17, 'completed', 'aaaaaaa1'); w.record(17, OWED); owing(w); w.threads.get('717').applied_tags = ['t-retail', 't-acc', 's-tri']; },
      [], /post Accepted shown -> removed \(waits for the post's next status change\)$/],
    ['a closed issue\'s stale Accepted: listed, left', (w) => { w.issue(17); w.close(17, 'completed'); w.threads.get('717').applied_tags = ['t-retail', 't-acc', 's-closed']; },
      [], /^#17: post Accepted shown -> removed \(waits for the post's next status change\)$/],
    ['a status line beside it: the status move places Accepted, and the repair adds nothing', (w) => { withLabel(w, 17); w.threads.get('717').applied_tags = ['t-retail', 't-bug']; },
      [{ applied_tags: ['t-retail', 't-bug', 's-tri', 't-acc'] }], /^#17: post \(no status\) -> Triaged; post Accepted missing -> shown \(waits/],
    ['a staff tag added between the repair\'s reads stays', (w) => { withLabel(w, 17); atForumRead(w, 3, () => w.threads.get('717').applied_tags.push('t-staff')); },
      [{ applied_tags: ['t-retail', 't-bug', 's-tri', 't-staff', 't-acc'] }], /^#17: post Accepted missing -> shown$/],
    ['a status change between the repair\'s reads: no write', (w) => { withLabel(w, 17); atForumRead(w, 3, () => { w.threads.get('717').applied_tags = ['t-retail', 't-bug', 's-prog']; }); },
      [], /^#17: post Accepted missing -> shown$/],
  ]) {
    const w = world();
    setup(w);
    w.threads.get('717').archived = false;
    // A held note dropped, rewritten or deleted would cost its run the message.
    const comments = structuredClone(w.issues.get(17).comments);
    const out = [];
    await sweepRun(w, 'fix', out);
    assert.match(out.find((l) => l.startsWith('#17: ')) || '', line, why);
    assert.deepEqual(w.find('PATCH', /channels\/717$/).map((c) => c.body), patches, why);
    assert.deepEqual(w.said('717'), [], `${why}: no message`);
    assert.deepEqual(w.issues.get(17).comments, comments, `${why}: no comment written, changed or dropped`);
  }
  {
    // A PR is opened after the sweep read the post. The Accepted repair finds
    // GitHub no longer wants Triaged and writes nothing, so the PR's own run
    // moves the post and tells it. A quiet status move here would leave that
    // run nothing to tell.
    const w = world();
    withLabel(w, 17);
    w.threads.get('717').archived = false;
    atForumRead(w, 1, () => w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [17] }));
    const out = [];
    await sweepRun(w, 'fix', out);
    assert.match(out.find((l) => l.startsWith('#17: ')) || '', /^#17: post Accepted missing -> shown$/);
    assert.deepEqual(w.find('PATCH', /channels\/717$/), [], 'no post write');
    assert.deepEqual(w.find('POST', /issues\/17\/labels$/), [], 'no label write');
    assert.deepEqual(w.issues.get(17).comments, [], 'no note');
    await prEvent(w, 5);
    assert.deepEqual(tagNames(w, '717'), ['Retail', 'Bug', 'In progress', 'Accepted']);
    assert.equal(w.said('717').length, 1, 'the PR run tells it once');
    assert.match(w.said('717')[0], /^\*\*In progress\.\*\*/);
  }
});

test('AT9: a status move landing inside the repair\'s write is put back to Triaged alone, and an In progress post is never written', async () => {
  const words = (w) => w.said('717').map((m) => /^\*\*([^*]+)\*\*/.exec(m)[1]);
  const confirmed = (w, word) => w.issues.get(17).comments.filter((c) => c.body.startsWith(`Delivery confirmed: **${word}**`)).length;
  // Closes the issue by hand inside the first post write made while armed,
  // before that write applies. The test disarms it when the sweep ends.
  const closeInWrite = (w) => {
    const hook = { armed: true, fired: false };
    w.hooks.push(['PATCH', /discord\.com\/api\/v10\/channels\/717$/, async () => {
      if (!hook.armed) return;
      hook.armed = false;
      hook.fired = true;
      await closeByHand(w);
    }]);
    return hook;
  };
  {
    // The repair writes a Triaged post, and a close lands inside that write.
    const w = world();
    withLabel(w, 17);
    w.threads.get('717').archived = false;
    const hook = closeInWrite(w);
    await sweepRun(w, 'fix');
    hook.armed = false;
    assert.ok(hook.fired, 'the repair wrote');
    assert.deepEqual(tagNames(w, '717'), ['Retail', 'Bug', 'Triaged', 'Accepted'], 'the close is put back to Triaged, with Accepted as the repair wrote it');
    await reopen(w);
    await closeByHand(w);
    assert.deepEqual(words(w), ['Closed.', 'Closed.'], 'each close told once; the reopen says nothing');
    assert.equal(confirmed(w, 'Closed.'), 2, 'both notes confirmed');
  }
  {
    // An In progress post. Were it written, the close inside the write would
    // be put back to In progress, and the reopen would find In progress shown
    // and tell nothing.
    const w = world();
    withLabel(w, 17);
    w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [17] });
    w.threads.get('717').applied_tags = ['t-retail', 's-prog'];
    w.threads.get('717').archived = false;
    const hook = closeInWrite(w);
    await sweepRun(w, 'fix');
    hook.armed = false;
    if (!hook.fired) await closeByHand(w);
    await reopen(w);
    assert.deepEqual(words(w), ['Closed.', 'In progress.'], 'the reopened issue is told In progress');
    assert.equal(confirmed(w, 'In progress.'), 1, 'its note confirmed');
    assert.equal(hook.fired, false, 'the repair sent no write');
  }
  {
    const w = world();
    withLabel(w, 17);
    w.threads.get('717').applied_tags = ['t-retail', 's-tri', 's-closed'];
    w.threads.get('717').archived = false;
    let hit = false;
    w.hooks.push(['PATCH', /discord\.com\/api\/v10\/channels\/717$/, async () => { hit = true; }]);
    await sweepRun(w, 'fix');
    assert.equal(hit, false, 'Triaged beside Closed: the repair sends no write, so nothing can be put back');
  }
});

test('AT11: the Accepted repair logs each outcome on its own line', async () => {
  // Runs `fn` before the `k`-th matching request is served: the sweep's own
  // read of the post and its forum is the first, the repair's first read the
  // second, and its fresh read the third.
  const at = (w, re, k, fn) => {
    let i = 0;
    w.hooks.push(['GET', re, async () => { if (++i === k) await fn(); }]);
  };
  const POST = /discord\.com\/api\/v10\/channels\/717$/;
  const HELP = /discord\.com\/api\/v10\/channels\/900$/;
  const saved = FORUM.available_tags;
  for (const [why, setup, logged] of [
    ['shown', (w) => withLabel(w, 17), /^#17: Accepted shown on the post$/],
    ['removed', (w) => { w.issue(17); w.threads.get('717').applied_tags = ['t-retail', 't-acc', 's-tri']; }, /^#17: Accepted removed on the post$/],
    ['archived at the first read', (w) => { withLabel(w, 17); at(w, POST, 2, () => { w.threads.get('717').archived = true; }); },
      /^#17: the post is archived; its Accepted tag is left as it is$/],
    ['not Triaged alone at the first read', (w) => { withLabel(w, 17); at(w, POST, 2, () => { w.threads.get('717').applied_tags = ['t-retail', 's-prog']; }); },
      /^#17: Accepted left: the post does not show Triaged alone$/],
    ['moved at the fresh read', (w) => { withLabel(w, 17); at(w, POST, 3, () => { w.threads.get('717').applied_tags = ['t-retail', 's-prog']; }); },
      /^#17: Accepted left: the post changed during the repair; the next sweep tries again$/],
    ['no free slot at the first read', (w) => { withLabel(w, 17); at(w, POST, 2, () => { w.threads.get('717').applied_tags = ['t-retail', 't-bug', 't-forever', 't-staff', 's-tri']; }); },
      /^#17: no free tag slot for Accepted on the post$/],
    ['the forum loses its Accepted tag', (w) => { withLabel(w, 17); at(w, HELP, 2, () => { FORUM.available_tags = saved.filter((t) => t.id !== 't-acc'); }); },
      /^#17: the forum has no Accepted tag$/],
    ['already in step at the first read', (w) => { withLabel(w, 17); at(w, POST, 2, () => { w.threads.get('717').applied_tags.push('t-acc'); }); },
      /^#17: Accepted already in step on the post$/],
    ['GitHub no longer wants Triaged', (w) => { withLabel(w, 17); at(w, HELP, 1, () => { w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [17] }); }); },
      /^#17: Accepted left for the post's next status change$/],
  ]) {
    try {
      const w = world();
      setup(w);
      w.threads.get('717').archived = false;
      const out = [];
      await sweepRun(w, 'fix', out);
      assert.ok(out.some((l) => logged.test(l)), `${why}: ${out.filter((l) => l.startsWith('#17: ')).join(' | ')}`);
    } finally {
      FORUM.available_tags = saved;
    }
  }
});

test('AT12: a failed status repair stops the Accepted repair on that post', async () => {
  const w = world();
  w.issue(17, { labels: ['from-discord', 'accepted', 'pending-release'] });
  w.threads.get('717').archived = false;
  w.fail.push(['DELETE', /issues\/17\/labels\/pending-release$/, new Response('{"message":"x"}', { status: 500 }), 99]);
  const out = [];
  await assert.rejects(sweepRun(w, 'fix', out), /#17/);
  assert.match(out.find((l) => l.startsWith('#17: ')) || '', /^#17: labels pending-release -> \(none\); post Accepted missing -> shown$/);
  assert.deepEqual(w.find('PATCH', /channels\/717$/), [], 'no post write after the failed status repair');
});

// ---- Setup problems -----------------------------------------------------------------

test('PT5: a forum missing a status tag fails the run once, after every other issue, with its fix in the summary; a re-run sends what it owes', async () => {
  const w = world();
  w.issue(17);
  w.issue(18);
  w.issue(19);
  w.threads.get('718').parent_id = '901';
  w.extraForums.set('901', { ...structuredClone(FORUM), id: '901' });
  w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [17, 18, 19] });
  // Shipped, which this PR run does not need, goes too: an event run names
  // only the tag it needs.
  const restore = dropTag(w, 'In progress', 'Shipped');
  const summary = tmpSummary();
  const out = [];
  const pr = (over, log = quiet) => run({
    eventName: PR, payload: { repository, action: 'opened', pull_request: { number: 5 } },
    env: { ...env, GITHUB_RUN_ID: '77', ...over }, fetchImpl: w.fetch, log,
  });
  await assert.rejects(pr({ GITHUB_STEP_SUMMARY: summary }, (s) => out.push(s)),
    /^Error: setup problems: forum 900 has no "In progress" tag: add it, spelled as the README lists it$/);
  assert.deepEqual(setupBullets(summary), ['- forum 900 has no "In progress" tag: add it, spelled as the README lists it'], 'one line for the two issues in that forum');
  assert.deepEqual(out.filter((l) => l.startsWith('setup problem: ')), ['setup problem: forum 900 has no "In progress" tag: add it, spelled as the README lists it'],
    'logged once, when first met');
  assert.equal(w.said('718').length, 1, "the healthy forum's player was told in that run");
  assert.deepEqual([w.said('717'), w.said('719')], [[], []], "the broken forum's players were not");
  restore();
  await pr({ GITHUB_RUN_ATTEMPT: '2', GITHUB_STEP_SUMMARY: tmpSummary() });
  assert.deepEqual([w.said('717').length, w.said('718').length, w.said('719').length], [1, 1, 1], 'the re-run sends the owed messages and nothing more');
});

test('PT5: a forum without the Accepted tag an accepted issue needs fails the run, whether the status moves, already shows, has no slot, its write fails, or the post goes before the write', async () => {
  const fiveOthers = ['t-retail', 't-forever', 't-bug', 't-feedback', 't-staff'];
  const fixPr = (w) => w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [17] });
  const alone = /^Error: setup problems: forum 900 has no "Accepted" tag, which issues with the accepted label need: add it, spelled as the README lists it$/;
  for (const [why, setup, event, line, shown, told] of [
    ['the status moves', fixPr, (w) => prEvent(w, 5), alone, 'In progress', 1],
    ['the post already shows the status', (w) => { fixPr(w); w.threads.get('717').applied_tags = ['t-retail', 's-prog']; }, (w) => prEvent(w, 5), alone, 'In progress', 0],
    ['five other tags leave Triaged no slot', (w) => { w.threads.get('717').applied_tags = [...fiveOthers]; },
      (w) => go(w, 'issues', { action: 'reopened', issue: { number: 17 } }), alone, null, 0],
    ['the status write fails', (w) => { fixPr(w); refuseTagWrite(w); },
      (w) => prEvent(w, 5), /^Error: could not update issue\(s\) #17; see above; setup problems: forum 900 has no "Accepted" tag, which issues with the accepted label need/, 'Triaged', 0],
    // The post's read just before the write answers 404, so the run takes the
    // post as gone and has no other failure.
    ['the post goes before the write', (w) => {
      fixPr(w);
      let once = false;
      w.hooks.push(['GET', /discord\.com\/api\/v10\/channels\/900$/, async () => {
        if (once) return;
        once = true;
        w.fail.push(['GET', /discord\.com\/api\/v10\/channels\/717$/, new Response('{"message":"Unknown Channel","code":10003}', { status: 404 }), 1]);
      }]);
    }, (w) => prEvent(w, 5), alone, 'Triaged', 0],
  ]) {
    const w = world();
    w.issue(17, { labels: ['from-discord', 'accepted'] });
    setup(w);
    dropTag(w, 'Accepted');
    await assert.rejects(event(w), line, why);
    assert.equal(w.tagOf('717') || null, shown, why);
    assert.equal(w.said('717').length, told, `${why}: the player messages are as before`);
  }
});

test('PT5: an invalid RELEASE_TAG_PATTERN fails the run before any call, its error shown as written on one summary line', async () => {
  for (const [why, pattern] of [['an unclosed group', '('], ['a pattern holding a line break', 'v\\d\n(']]) {
    const w = world();
    w.issue(17);
    w.close(17, 'completed', 'aaaaaaa1');
    const summary = tmpSummary();
    await assert.rejects(closeRun(w, { RELEASE_TAG_PATTERN: pattern, GITHUB_STEP_SUMMARY: summary }), /^Error: setup problems: RELEASE_TAG_PATTERN is not a valid pattern \(/, why);
    assert.deepEqual(w.calls, [], `${why}: no call`);
    const lines = setupBullets(summary);
    assert.equal(lines.length, 1, why);
    assert.match(lines[0], /^- RELEASE_TAG_PATTERN is not a valid pattern \(`Invalid regular expression: [^\n`]*`\): fix the repository variable$/, why);
  }
});

test('PT5: a re-run whose owed-note scan fails reports the setup problems it met, throws its own error when it met none, and a clean run writes no setup section', async () => {
  for (const [why, broken, over, line, bullets] of [
    ['a setup problem met', true, {}, /^Error: the re-run's owed-note scan failed \(.*\); setup problems: forum 900 has no "Fixed, next update" tag/,
      ['- forum 900 has no "Fixed, next update" tag: add it, spelled as the README lists it']],
    // Named only at the end, so the scan's failure is kept for it.
    ['a bad CHECKLIST_FORUM_ID due', false, { CHECKLIST_FORUM_ID: './950' }, /^Error: the re-run's owed-note scan failed \(.*\); setup problems: CHECKLIST_FORUM_ID is `\.\/950`/,
      ["- CHECKLIST_FORUM_ID is `./950`, which is not a Discord channel id: set the repository variable to the staff checklist forum's id, digits only (this run did no staff checklist work)"]],
    ['none met: the scan error itself', false, {}, /^Error: GitHub GET \/repos\/me\/one\/issues\?/, []],
  ]) {
    const w = world();
    w.issue(17);
    w.close(17, 'completed', 'aaaaaaa1');
    if (broken) dropTag(w, 'Fixed, next update');
    w.fail.push(['GET', /\/repos\/me\/one\/issues\?/, new Response('{}', { status: 500 }), 1]);
    const summary = tmpSummary();
    await assert.rejects(closeRun(w, { ...RUN, GITHUB_RUN_ATTEMPT: '2', GITHUB_STEP_SUMMARY: summary, ...over }), line, why);
    assert.deepEqual(setupBullets(summary), bullets, why);
  }
  {
    const w = world();
    w.issue(17);
    w.close(17, 'completed', 'aaaaaaa1');
    const summary = tmpSummary();
    await closeRun(w, { GITHUB_STEP_SUMMARY: summary });
    assert.equal(readFileSync(summary, 'utf8'), '');
  }
});

test('PT5: a Discord refusal is named by what it refused, and the run still finishes its other work first', async () => {
  const refused = (status) => new Response('{"message":"Missing Access"}', { status });
  const channel = (id) => `Discord refused the bot on channel ${id} (403), a post or its forum: give the bot View Channel, Manage Threads and Send Messages in Threads in that forum`;
  const named = (id) => new RegExp(`setup problems: ${channel(id).replace(/[()]/g, '\\$&')}`);
  const needsInfo = (w) => {
    const i = w.issues.get(17);
    i.labels.add('needs-info');
    return go(w, 'issues', { action: 'labeled', label: { name: 'needs-info' }, issue: { number: 17, body: i.body, updated_at: '2026-11-16T12:00:00Z' } }, { ...RUN, GITHUB_STEP_SUMMARY: w.summary });
  };
  for (const [why, setup, event, line, after = () => {}] of [
    ['a refused post, then a healthy one', (w) => {
      w.issue(18);
      w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [17, 18] });
      w.fail.push(['GET', /discord\.com\/api\/v10\/channels\/717$/, refused(403), 99]);
    }, (w) => go(w, PR, { action: 'opened', pull_request: { number: 5 } }, { GITHUB_STEP_SUMMARY: w.summary }),
    /^Error: could not update issue\(s\) #17; see above; setup problems: Discord refused the bot on channel 717 \(403\)/,
    (w) => {
      assert.equal(w.said('718').length, 1, 'the healthy issue after it is still told');
      assert.deepEqual(setupBullets(w.summary), [`- ${channel(717)}`]);
    }],
    ['the send', (w) => { w.close(17, 'completed', 'aaaaaaa1'); w.fail.push(['POST', /discord\.com\/api\/v10\/channels\/717\/messages$/, refused(403), 99]); },
      (w) => closed(w, 17),
      /setup problems: Discord refused the bot's message in post 717 \(403\): give the bot View Channel, Send Messages in Threads and Read Message History \(a reply needs it\) in that post's forum/],
    ['the token', (w) => { w.close(17, 'completed', 'aaaaaaa1'); w.fail.push(['GET', /discord\.com\/api\/v10\//, refused(401), 99]); },
      (w) => closed(w, 17), /setup problems: Discord refused the bot token \(401\): set the repository secret DISCORD_BOT_TOKEN to the bot's current token/],
    ["the reporter's first message", (w) => {
      w.close(17, 'completed', 'aaaaaaa1');
      // The starter is the reporter's, so a readable one would make the message a reply.
      w.threads.get('717').starter = { author: { id: '42' }, content: 'hi' };
      w.fail.push(['GET', /discord\.com\/api\/v10\/channels\/717\/messages\/717$/, refused(403), 99]);
    }, (w) => closed(w, 17),
    /^Error: setup problems: Discord refused the bot reading messages in post 717 \(403\): give the bot View Channel and Read Message History in that post's forum$/,
    (w) => {
      const [sent] = w.threads.get('717').messages;
      assert.equal(w.threads.get('717').messages.length, 1, 'the message still went out');
      assert.deepEqual([sent.message_reference, sent.allowed_mentions.replied_user], [undefined, undefined], 'plain: no reply, no ping');
    }],
    ["the duplicate's post", (w) => { w.issue(18); w.close(17, 'duplicate', null, null, 18); w.fail.push(['GET', /discord\.com\/api\/v10\/channels\/718$/, refused(403), 99]); },
      (w) => closed(w, 17), named(718),
      (w) => {
        assert.equal(w.said('717').length, 1, 'the message still went out');
        assert.doesNotMatch(w.said('717')[0], /718/, 'without the link');
      }],
    ['the needs-info reopen: the event stops at once, as before, with its line in the summary', (w) => refuseTagWrite(w), needsInfo,
      /^Error: Discord PATCH \/channels\/717 -> 403 /, (w) => assert.deepEqual(setupBullets(w.summary), [`- ${channel(717)}`])],
    ["the sweep's post read", (w) => w.fail.push(['GET', /discord\.com\/api\/v10\/channels\/717$/, refused(403), 99]), (w) => sweepRun(w, 'report'), named(717)],
    ["a fix-mode sweep's status repair", (w) => { w.close(17, 'completed', 'aaaaaaa1'); refuseTagWrite(w); }, (w) => sweepRun(w, 'fix'), named(717)],
    ["a fix-mode sweep's Accepted repair", (w) => { w.issues.get(17).labels.add('accepted'); w.threads.get('717').archived = false; refuseTagWrite(w); },
      (w) => sweepRun(w, 'fix'), named(717)],
  ]) {
    const w = world();
    w.issue(17);
    w.summary = tmpSummary();
    setup(w);
    await assert.rejects(event(w), line, why);
    after(w);
  }
});

test('PT5: a refused send is logged as a setup problem before its note is marked Unconfirmed, so a run stopped there still shows it', async () => {
  const w = world();
  w.issue(17);
  w.close(17, 'completed', 'aaaaaaa1');
  w.fail.push(['POST', /discord\.com\/api\/v10\/channels\/717\/messages$/, new Response('{"message":"Missing Access"}', { status: 403 }), 99]);
  const out = [];
  let atMark = null;
  w.hooks.push(['PATCH', /\/issues\/comments\/\d+$/, async (call) => {
    if (atMark === null && /discord-unconfirmed/.test(call.body.body)) atMark = out.filter((l) => l.startsWith('setup problem: '));
  }]);
  await assert.rejects(run({ eventName: 'issues', payload: { repository, action: 'closed', issue: { number: 17 } }, env, fetchImpl: w.fetch, log: (s) => out.push(s) }),
    /setup problems: Discord refused the bot's message in post 717 \(403\)/);
  assert.deepEqual(atMark, ["setup problem: Discord refused the bot's message in post 717 (403): give the bot View Channel, Send Messages in Threads and Read Message History (a reply needs it) in that post's forum"]);
});

test('PT5: a needs-info re-run whose issue read fails stops there, so no other step moves the post or tells the player', async () => {
  const w = world();
  const i = w.issue(17);
  i.labels.add('needs-info');
  const ev = { action: 'labeled', label: { name: 'needs-info' }, issue: { number: 17, body: i.body, updated_at: '2026-11-16T12:00:00Z' } };
  refuseTagWrite(w);
  await assert.rejects(go(w, 'issues', ev, RUN), /-> 403/);
  w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [17] });
  w.fail.push(['GET', /\/repos\/me\/one\/issues\/17$/, new Response('{}', { status: 500 }), 1]);
  await assert.rejects(go(w, 'issues', ev, { ...RUN, GITHUB_RUN_ATTEMPT: '2' }), /^Error: GitHub GET \/repos\/me\/one\/issues\/17 -> 500/);
  assert.deepEqual(w.said('717'), [], 'no message');
  assert.equal(w.tagOf('717'), 'Triaged', 'no move');
});
