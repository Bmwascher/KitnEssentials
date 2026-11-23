import test from 'node:test';
import assert from 'node:assert/strict';
import { MARKER, closingKeywordRefs, refsKeywordRefs, threadLinks, renderPlan, planRun } from '../status/merge-plan.mjs';
import { run } from '../status/status.mjs';
import { world } from './fake-world.mjs';

const CLOSED17 = 'Merged into `dev`, naming #17 as closing. GitHub closes each of these issues that was still open; what the bot then does is in `.github/discord-bot/README.md`.';
const NONE = 'Merged into `dev`. It closed no Discord-filed issue of this repo through its description or links; closing keywords in commit messages are not read here.';
const REVERT = 'If this merge is reverted before a release, reopen each issue it closed the same day; otherwise the release announces the fix as out.';

test('MP1: the description parsers', () => {
  const repo = 'me/one';
  for (const [why, body, closing, refs] of [
    ['every closing keyword, any case, with or without a colon', 'Fixes #1\ncloses: #2\nRESOLVED #3\nfix #4\nClose #5\nresolves: #6\nclosed #7\nFIXED: #8\nresolve #9', [1, 2, 3, 4, 5, 6, 7, 8, 9], []],
    ['Refs and Ref, with or without a colon', 'Refs #10\nref: #11\nREFS #12', [], [10, 11, 12]],
    ['a bare number and a plain mention', '#13 and see #14', [], []],
    ['this repo by name and by URL', 'Fixes me/one#15 and refs https://github.com/me/one/issues/16', [15], [16]],
    ['another repo is not this repo', 'Fixes other/repo#17\nRefs other/repo#18', [], []],
    ['a repo whose name ends in this one', 'Fixes other-me/one#19', [], []],
    ['a number inside a word', 'Fixes abc#20 and Refs x/y#21', [], []],
    ['an issue URL ending a sentence, or with a fragment', 'Fixes https://github.com/me/one/issues/23.\nRefs https://github.com/me/one/issues/24#issuecomment-1', [23], [24]],
    ['an issue URL whose path goes on after the number', 'Fixes https://github.com/me/one/issues/25/../26\nRefs https://github.com/me/one/issues/27./../28\nFixes https://github.com/me/one/issues/29\\..\\30', [], []],
  ]) {
    assert.deepEqual(closingKeywordRefs(body, repo), closing, why);
    assert.deepEqual(refsKeywordRefs(body, repo), refs, why);
  }
  assert.deepEqual(
    threadLinks('https://discord.com/channels/1/22 b https://ptb.discord.com/channels/1/33/44 c\nhttps://canary.discordapp.com/channels/1/55\nd https://discord.com/channels/1/22'),
    ['22', '33', '55'],
    'standalone links at the start, after a space or a line break, ending at whitespace or the end; a message link; a repeat',
  );
  for (const [why, body] of [
    ['a word after the id', 'https://discord.com/channels/1/717extra'],
    ['a hyphen after the id', 'https://discord.com/channels/1/717-extra'],
    ['an underscore after the id', 'https://discord.com/channels/1/717_'],
    ['21 digits', 'https://discord.com/channels/1/123456789012345678901'],
    ['a Markdown link', '[post](https://discord.com/channels/1/66)'],
    ['an angle-bracket link', '<https://discord.com/channels/1/77>'],
    ['a link ending a sentence', 'See https://discord.com/channels/1/88.'],
    ['a titled Markdown link, a space after the id', '[post](https://discord.com/channels/1/717 "details")'],
    ['a link inside another URL, at the end', 'https://example.org/?next=https://discord.com/channels/1/717'],
    ['a link after a quote mark', 'see "https://discord.com/channels/1/717 here'],
  ]) assert.deepEqual(threadLinks(body), [], why);
  // Markdown whose URL still stands alone between spaces names that same post.
  assert.deepEqual(
    threadLinks('[a]: https://discord.com/channels/1/91\n[b]( https://discord.com/channels/1/92 "t")'),
    ['91', '92'],
    'a reference definition and a spaced Markdown link name the post their URL names',
  );
});

test('MP2: renderPlan shows each line only when its case holds', () => {
  const base = {
    repo: 'me/one', defaultBranch: 'dev', base: 'dev', draft: false, trusted: true, state: 'open',
    closing: [{ n: 17, open: true }], unlisted: [], refs: [], linked: [], crossRepo: [],
  };
  const plain = renderPlan(base);
  assert.ok(plain.startsWith(`${MARKER}\n`));
  assert.doesNotMatch(plain, /Heads-up/);
  assert.match(plain, /\*\*#17\*\* closes when this PR merges\. The bot's current message for each step:/);
  assert.equal([...plain.matchAll(/^ {2}> /gm)].length, 3, 'three previews');
  assert.match(plain, /Only part of the fix\? Change the closing word before #17 to `Refs`, remove any link to #17 in the Development sidebar, and keep fix, close and resolve before #17 out of commit messages\./);
  assert.match(plain, /When each message goes out, and when it does not, is in `\.github\/discord-bot\/README\.md`\._$/);
  for (const [why, over, line] of [
    ['a wrong base', { base: 'feature' }, /This PR targets `feature`, not `dev`: GitHub will not close #17 when it merges\. Change the base, then edit and save the description once\./],
    ['a draft', { draft: true }, /This PR is a draft: it counts toward In progress only once it is ready for review\./],
    ['an author with no role', { trusted: false }, /This PR's author has no role on this repo, so this PR never counts toward In progress\./],
    ['a closing issue already closed', { closing: [{ n: 17, open: false }] }, /^- #17 is already closed\.$/m],
    ['a cross-repo report', { crossRepo: [{ repo: 'me/two', n: 12, open: true }] },
      /This PR closes me\/two#12, a Discord report in another repo\. That repo's status workflow, if it runs, cannot see this repo's fix or its releases\. Transfer the issue/],
    ['a cross-repo report already closed', { crossRepo: [{ repo: 'me/two', n: 12, open: false }] }, /^- me\/two#12 is already closed\.$/m],
    ['a linked post not closed', { linked: [{ n: 18, open: true }] },
      /This PR links the Discord post tracked as #18 but does not close it, unless a commit message does\. Add `Fixes #18` on its own line/],
    ['a Refs issue', { refs: [{ n: 19, open: true }] },
      /#19 is referenced, not closed: merging this PR does not close it, unless a commit message does\. Change `Refs #19` to `Fixes #19` when the fix is ready\./],
    ['a Refs issue already closed', { refs: [{ n: 19, open: false }] }, /#19 is already closed/],
    ['a linked issue already closed', { linked: [{ n: 18, open: false }] }, /^- #18 is already closed\.$/m],
    ['a closing keyword GitHub does not list', { closing: [], unlisted: [{ n: 17, open: true }] },
      /The description says it closes #17, but GitHub does not list #17 as closing, so merging will not close it, unless a commit message does\. Edit and save the description once: a base change alone does not make GitHub read it again\./],
    ['a closing keyword GitHub does not list, already closed', { closing: [], unlisted: [{ n: 17, open: false }] }, /^- #17 is already closed\.$/m],
  ]) {
    assert.match(renderPlan({ ...base, ...over }), line, why);
    assert.doesNotMatch(plain, line, `${why}: not in the plain plan`);
  }
  const outsideDraft = renderPlan({ ...base, draft: true, trusted: false });
  assert.match(outsideDraft, /has no role on this repo/);
  assert.doesNotMatch(outsideDraft, /This PR is a draft/, "an outside author's draft gets the no-role line only");
  for (const over of [{ draft: true }, { trusted: false }]) {
    assert.doesNotMatch(renderPlan({ ...base, ...over, closing: [{ n: 17, open: false }] }), /This PR is a draft|has no role/, `no open closing issue: no line (${JSON.stringify(over)})`);
  }
  assert.doesNotMatch(renderPlan({ ...base, base: 'feature' }), /^ {2}> /m, 'a wrong base shows no previews');
  for (const over of [{ draft: true }, { trusted: false }]) {
    assert.doesNotMatch(renderPlan({ ...base, ...over, base: 'feature' }), /This PR is a draft|has no role/, `a wrong base: no draft or no-role line (${JSON.stringify(over)})`);
  }
  const two = renderPlan({ ...base, closing: [{ n: 17, open: true }, { n: 18, open: true }] });
  assert.deepEqual([...two.matchAll(/^\*\*#(\d+)\*\* closes when this PR merges\./gm)].map((m) => Number(m[1])), [17, 18], 'one section per issue, in order');
  assert.ok(renderPlan({ ...base, base: 'a`@b`c' }).includes('This PR targets ``a`@b`c``, not `dev`'), 'a backtick in a branch name never ends its code span');
  assert.ok(renderPlan({ ...base, base: '`edge' }).includes('This PR targets `` `edge ``, not `dev`'), 'a branch name that starts with a backtick is padded');
  assert.ok(renderPlan({ ...base, base: 'edge`' }).includes('This PR targets `` edge` ``, not `dev`'), 'a branch name that ends with a backtick is padded');
  const merged = (over) => renderPlan({ ...base, state: 'merged', ...over });
  const cross = [{ repo: 'me/two', n: 12, open: false }];
  for (const over of [{}, { closing: [{ n: 17, open: false }] }, { crossRepo: cross }]) {
    assert.equal(merged(over), `${MARKER}\n\n${CLOSED17}\n\n${REVERT}`, `named as closing, open or not, another repo's report aside (${JSON.stringify(over)})`);
  }
  for (const over of [{ closing: [] }, { closing: [], crossRepo: cross }]) {
    assert.equal(merged(over), `${MARKER}\n\n${NONE}`, `none named here (${JSON.stringify(over)})`);
  }
  assert.equal(renderPlan({ ...base, state: 'closedUnmerged' }), `${MARKER}\n\nClosed without merging, so this PR closes no issue.`);
  assert.equal(renderPlan({ ...base, closing: [] }), `${MARKER}\n\nThis PR no longer closes, references or links a Discord-filed issue.`);
});

// ---- The comment on a PR, in the fake world ----------------------------------

const env = { GITHUB_TOKEN: 'gh', DISCORD_BOT_TOKEN: 'bot' };
const repository = { full_name: 'me/one', default_branch: 'dev' };
const quiet = () => {};
// A run that logs a failure fails the test, unless the test reads the log.
const clean = (line) => assert.ok(!line.startsWith('merge plan comment not updated'), line);
const plan = (w, number, action = 'opened', over = {}, log = clean) => planRun({
  payload: { repository, action, pull_request: { number } }, env: { ...env, ...over }, fetchImpl: w.fetch, log,
});
// One PR event as the workflow runs it: the status job, then the merge-plan job.
const both = async (w, number, action = 'opened', over = {}) => {
  await run({ eventName: 'pull_request_target', payload: { repository, action, pull_request: { number } }, env: { ...env, ...over }, fetchImpl: w.fetch, log: quiet });
  await plan(w, number, action, over);
};
const plans = (w, n) => w.holder(n).comments.filter((c) => c.user.login === 'github-actions[bot]' && c.body.includes(MARKER));

test('MP3: one merge-plan comment per PR, found on any page, edited in place, never deleted; a marked comment by anyone else, and an unmarked bot comment, are ignored', async () => {
  const w = world();
  w.issue(17, { body: '## Report\n\n> zebra-sentinel\n\n<!-- discord-thread: 717 reporter: 42 -->' });
  w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [17], body: 'Fixes #17' });
  const spoof = w.record(5, `${MARKER}\nnot the bot`, 'someone');
  const ordinary = w.record(5, 'an ordinary bot comment');
  for (let i = 0; i < 98; i++) w.record(5, 'a comment', 'someone');
  await plan(w, 5);
  assert.equal(plans(w, 5).length, 1);
  const { id } = plans(w, 5)[0];
  assert.match(plans(w, 5)[0].body, /\*\*#17\*\* closes when this PR merges\./);
  assert.doesNotMatch(plans(w, 5)[0].body, /zebra-sentinel|\b42\b|\b717\b|discord\.com/, 'no report text, reporter id, post id or Discord link');
  const creates = () => w.find('POST', /issues\/5\/comments$/).length;
  const writes = () => w.find('PATCH', new RegExp(`issues/comments/${id}$`)).length + creates();
  const before = writes();
  await plan(w, 5, 'edited');
  assert.equal(writes(), before, 'nothing changed: no write, though the plan is on the second page');
  Object.assign(w.prs.get(5), { closes: [], body: 'Refs #17' });
  await plan(w, 5, 'edited');
  assert.equal(plans(w, 5)[0].id, id, 'the same comment');
  assert.match(plans(w, 5)[0].body, /#17 is referenced, not closed/);
  w.prs.get(5).body = 'nothing here';
  await plan(w, 5, 'edited');
  assert.match(plans(w, 5)[0].body, /no longer closes, references or links/);
  Object.assign(w.prs.get(5), { closes: [17], body: 'Fixes #17', state: 'MERGED' });
  await plan(w, 5, 'closed');
  const merged = `${MARKER}\n\n${CLOSED17}\n\n${REVERT}`;
  assert.equal(plans(w, 5)[0].body, merged);
  await plan(w, 5, 'opened');
  assert.equal(plans(w, 5)[0].body, merged, 'a re-run of the old opened event leaves the merged text');
  // A second marked copy on the first page, the plan on the second.
  const copy = w.record(5, `${MARKER}\nan older copy`);
  const list = w.holder(5).comments;
  list.unshift(list.pop());
  // The plan changes after both copies exist, so each page's copy must be edited.
  w.issue(18);
  w.prs.get(5).closes.push(18);
  await plan(w, 5, 'closed');
  const copies = plans(w, 5);
  assert.deepEqual(copies.map((c) => c.id).sort(), [copy.id, id].sort());
  for (const c of copies) assert.match(c.body, /naming #17, #18 as closing/, `copy ${c.id}, on either page, gets the new plan`);
  assert.equal(creates(), 1, 'no comment created twice');
  assert.deepEqual(w.find('DELETE', /issues\/comments/), [], 'no comment deleted');
  assert.equal(spoof.body, `${MARKER}\nnot the bot`, "the other account's comment is left alone");
  assert.equal(ordinary.body, 'an ordinary bot comment', 'a bot comment without the marker is left alone');
});

test('MP4: the previews are the messages a new note sends', async () => {
  const w = world();
  w.issue(17);
  w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [17], body: 'Fixes #17' });
  const over = { RELEASE_TAG_PATTERN: '^v?\\d' };
  await both(w, 5, 'opened', over);
  const quoted = [...plans(w, 5)[0].body.matchAll(/^ {2}> (.*)$/gm)].map((m) => m[1]);
  assert.equal(quoted.length, 3);
  w.prs.get(5).state = 'MERGED';
  w.close(17, 'completed', null, { pr: 'aaaaaaa1' });
  await run({ eventName: 'issues', payload: { repository, action: 'closed', issue: { number: 17 } }, env: { ...env, ...over }, fetchImpl: w.fetch, log: quiet });
  w.tags.unshift({ name: '1.3', commit: { sha: 'c-1.3' } });
  w.contains.set('aaaaaaa1...c-1.3', 'ahead');
  await run({
    eventName: 'push', payload: { repository, ref: 'refs/tags/1.3', created: true, after: 'obj-1.3', head_commit: { id: 'c-1.3' } },
    env: { ...env, ...over }, fetchImpl: w.fetch, log: quiet,
  });
  assert.deepEqual(w.said('717'), [quoted[0], quoted[1], quoted[2].replace('(release tag)', 'v1.3')], 'a tag that starts with a digit is shown with a v');
});

test('MP5: a merge-plan failure is logged, never thrown, and writes nothing', async () => {
  for (const [why, setup, reason] of [
    ['the comment write is refused', (w) => w.fail.push(['POST', /issues\/5\/comments$/, new Response('{"message":"Resource not accessible by integration"}', { status: 403 }), 1]),
      /-> 403 .*Resource not accessible by integration/],
    ['the plan query answers an error', (w) => w.fail.push(['POST', /graphql$/, new Response(JSON.stringify({ errors: [{ message: 'boom' }] })), 1]),
      /GitHub GraphQL: boom/],
    ['a Refs lookup is refused', (w) => {
      w.prs.get(5).body = 'Fixes #17\nRefs #18';
      w.fail.push(['GET', /\/repos\/me\/one\/issues\/18$/, new Response('{"message":"Forbidden"}', { status: 403 }), 1]);
    }, /issues\/18 -> 403/],
    ['more than one page of closing references', (w) => {
      w.pageSize = 1;
      w.issue(18);
      w.prs.get(5).closes.push(18);
    }, /more than 100 closing references: the merge plan is not updated/],
  ]) {
    const w = world();
    w.issue(17);
    w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [17], body: 'Fixes #17' });
    setup(w);
    const out = [];
    await plan(w, 5, 'opened', {}, (s) => out.push(s));
    assert.deepEqual(plans(w, 5), [], why);
    assert.ok(out.some((l) => l.startsWith('merge plan comment not updated: ') && reason.test(l)), `${why}: ${out.join(' | ')}`);
  }
  const w = world();
  w.issue(17);
  w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [17], body: 'Fixes #17' });
  const out = [];
  await plan(w, 5, 'opened', { DISCORD_BOT_TOKEN: '' }, (s) => out.push(s));
  assert.deepEqual(out, ['DISCORD_BOT_TOKEN is not set: skipping the merge plan']);
  assert.deepEqual(w.calls, [], 'no call without the bot token');
});

test('MP6: which PRs get a comment, and what it names', async () => {
  const other = (over = {}) => ({
    number: 12, state: 'OPEN', repository: { nameWithOwner: 'me/two' },
    labels: { nodes: [{ name: 'from-discord' }] }, body: '<!-- discord-thread: 912 reporter: 42 -->', ...over,
  });
  const open = (over) => (w) => w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [], ...over });
  const none = (w, why) => assert.deepEqual(plans(w, 5), [], why);
  const says = (re, not = []) => (w, why) => {
    assert.equal(plans(w, 5).length, 1, why);
    assert.match(plans(w, 5)[0].body, re, why);
    for (const n of not) assert.doesNotMatch(plans(w, 5)[0].body, n, why);
  };
  for (const [why, setup, check] of [
    ['a ready member PR closing #17', open({ closes: [17], body: 'Fixes #17' }),
      says(/\*\*#17\*\* closes when this PR merges\./, [/Heads-up/])],
    ['a draft closing #17', open({ closes: [17], body: 'Fixes #17', draft: true }),
      says(/This PR is a draft: it counts toward In progress only once it is ready for review\./, [/has no role/])],
    ['an author with no role closing #17', open({ closes: [17], body: 'Fixes #17', author_association: 'NONE' }),
      says(/This PR's author has no role on this repo/, [/This PR is a draft/])],
    ['a cross-repo report: the label and the marker', open({ closes: [other()], body: 'Fixes me/two#12' }),
      says(/This PR closes me\/two#12, a Discord report in another repo\. That repo's status workflow, if it runs, cannot see this repo's fix or its releases\./)],
    ['a cross-repo report already closed', open({ closes: [other({ state: 'CLOSED' })], body: 'Fixes me/two#12' }),
      says(/^- me\/two#12 is already closed\.$/m, [/Transfer the issue/])],
    ['a cross-repo issue with the label and no marker', open({ closes: [other({ body: 'no marker' })], body: 'Fixes me/two#12' }), none],
    ['a cross-repo issue without the label', open({ closes: [other({ labels: { nodes: [] } })], body: 'Fixes me/two#12' }), none],
    ['a link to the post of #17', open({ body: 'See https://discord.com/channels/800/717\nThanks.' }),
      says(/This PR links the Discord post tracked as #17 but does not close it, unless a commit message does\./)],
    ['a link to the post of #17, its label in another letter case', (w) => {
      const { labels } = w.issues.get(17);
      labels.delete('from-discord');
      labels.add('From-Discord');
      open({ body: 'See https://discord.com/channels/800/717' })(w);
    }, none],
    ['a link to a post with no issue', open({ body: 'See https://discord.com/channels/800/12345' }), none],
    ['Refs #17 after #17 moved to another repo', (w) => {
      // Reading a transferred issue follows GitHub's redirect to its new repo.
      w.issues.get(17).html_url = 'https://github.com/me/two/issues/9';
      open({ body: 'Refs #17' })(w);
    }, none],
    ['a plain mention', open({ body: 'See #17' }), none],
    ['Refs to a PR with the label and a copied marker', (w) => {
      w.issue(30, { pull_request: {} });
      open({ body: 'Refs #30' })(w);
    }, none],
    ['ten Refs to numbers that are no issue, one of them deleted (410), then Refs #17', (w) => {
      w.fail.push(['GET', /\/repos\/me\/one\/issues\/101$/, new Response('{"message":"This issue was deleted"}', { status: 410 }), 1]);
      open({ body: `${Array.from({ length: 10 }, (_, i) => `Refs #${101 + i}`).join('\n')}\nRefs #17` })(w);
    }, says(/#17 is referenced, not closed/)],
    ['Fixes #17 into another branch', open({ body: 'Fixes #17', base: 'feature' }),
      says(/This PR targets `feature`, not `dev`: GitHub will not close #17 when it merges/, [/^ {2}> /m])],
    ['Fixes #17 on the default base, which GitHub does not list (the base was changed)', open({ body: 'Fixes #17' }),
      says(/The description says it closes #17, but GitHub does not list #17 as closing/, [/^ {2}> /m])],
    ['Fixes, Refs and the link of #17', open({ closes: [17], body: 'Fixes #17\nRefs #17\nhttps://discord.com/channels/800/717' }),
      says(/\*\*#17\*\* closes when this PR merges\./, [/is referenced, not closed/, /links the Discord post/])],
    ['Refs and the link of #17, no close', open({ body: 'Refs #17\nhttps://discord.com/channels/800/717' }),
      says(/#17 is referenced, not closed/, [/links the Discord post/])],
    ['first seen at its merge, closing #17', (w) => w.prs.set(5, { author_association: 'MEMBER', state: 'MERGED', closes: [17], body: 'Fixes #17' }),
      says(/^<!-- discord-merge-plan -->\n\nMerged into `dev`, naming #17 as closing\./)],
    ['first seen at its merge, naming #17 that was closed before it', (w) => {
      w.close(17, 'completed', 'aaaaaaa1');
      w.prs.set(5, { author_association: 'MEMBER', state: 'MERGED', closes: [17], body: 'Fixes #17' });
    }, says(/^<!-- discord-merge-plan -->\n\nMerged into `dev`, naming #17 as closing\. GitHub closes each of these issues that was still open;/)],
    ['first seen at its close, unmerged', (w) => w.prs.set(5, { author_association: 'MEMBER', state: 'CLOSED', closes: [17], body: 'Fixes #17' }), none],
    ['first seen at its merge, closing no bot issue', (w) => w.prs.set(5, { author_association: 'MEMBER', state: 'MERGED', closes: [], body: 'Refs #17' }), none],
    ['first seen at its merge, closing only another repo\'s report', (w) => w.prs.set(5, { author_association: 'MEMBER', state: 'MERGED', closes: [other()], body: 'Fixes me/two#12' }), none],
    ['closed after its last closing reference went', async (w) => {
      open({ closes: [17], body: '' })(w);
      await plan(w, 5);
      Object.assign(w.prs.get(5), { closes: [], state: 'CLOSED' });
    }, says(/^<!-- discord-merge-plan -->\n\nClosed without merging, so this PR closes no issue\.$/)],
  ]) {
    const w = world();
    w.issue(17);
    await setup(w);
    await plan(w, 5);
    check(w, why);
  }
  const w = world();
  w.issue(17);
  // #50 is an ordinary issue of this repo that GitHub lists as closing.
  w.prs.set(5, { author_association: 'MEMBER', state: 'OPEN', closes: [other({ number: 50, repository: { nameWithOwner: 'me/one' }, labels: { nodes: [] } })], body: 'Fixes #50' });
  await plan(w, 5);
  assert.deepEqual(plans(w, 5), [], 'a PR closing only an ordinary issue gets no comment');
  assert.equal(w.find('POST', /graphql$/).length, 1, 'one GraphQL read');
  assert.equal(w.find('GET', /issues\/5\/comments/).length, 1, 'one comment-list page');
  assert.equal(w.calls.length, 2, 'no other call, and no write');
});
