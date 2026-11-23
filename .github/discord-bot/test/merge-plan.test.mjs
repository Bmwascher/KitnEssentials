import test from 'node:test';
import assert from 'node:assert/strict';
import { MARKER, closingKeywordRefs, refsKeywordRefs, threadLinks, renderPlan } from '../status/merge-plan.mjs';

// The merged texts, as a merge into `dev` naming #17 as closing, or naming
// none, writes them.
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
  );});

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
  assert.equal([...two.matchAll(/^\*\*#\d+\*\* closes when this PR merges\./gm)].length, 2, 'two sections');
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
