import test from 'node:test';
import assert from 'node:assert/strict';
import * as C from '../src/core.js';
import { stall } from './fake-fetch.mjs';

test('title follows [ONE][Client][Module] Title', () => {
  assert.equal(C.buildTitle({ repoKey: 'ONE', client: 'Retail', module: 'Bags', title: ' Icons overlap ' }),
    '[ONE][Retail][Bags] Icons overlap');
  assert.equal(C.buildTitle({ repoKey: 'TWO', client: 'All', module: '', title: 'x' }), '[TWO][All][General] x');
});

test('form values normalize, junk is refused', () => {
  assert.equal(C.normClient('forever'), 'Forever');
  assert.equal(C.normClient('classic'), null);
  assert.equal(C.normType('Feedback/Request'), 'Feature');
  assert.equal(C.normType('bug'), 'Bug');
  assert.equal(C.normType('question'), null);
  assert.equal(C.normRepoKey('two', { ONE: 'a', TWO: 'b' }), 'TWO');
  assert.equal(C.normRepoKey('kitn', { ONE: 'a' }), null);
});

test('existing forum tags pre-fill client and type', () => {
  assert.deepEqual(C.guessFromTags(['Retail', 'Bug']), { client: 'Retail', type: 'Bug' });
  assert.deepEqual(C.guessFromTags(['Forever', 'Feedback/Request']), { client: 'Forever', type: 'Feature' });
  assert.deepEqual(C.guessFromTags(['Retail', 'Forever']), { client: 'All', type: null });
  assert.deepEqual(C.guessFromTags([]), { client: null, type: null });
});

test('post title loses typed [..] prefixes', () => {
  assert.equal(C.cleanPostTitle('[Bug][Retail] Bags broken'), 'Bags broken');
});

test('body quotes the reporter, links the post and carries the marker', () => {
  const body = C.buildBody({ content: 'line one\nline two', reporterName: 'Pat', threadUrl: 'https://discord.com/channels/1/2',
    client: 'Retail', attachments: [{}], threadId: '2', reporterId: '77', sentBy: 'Mod' });
  assert.match(body, /^## Report\n\n> line one\n> line two/);
  assert.match(body, /\*\*Pat\*\* in \[the Discord post\]\(https:\/\/discord.com\/channels\/1\/2\)/);
  assert.match(body, /1 attachment/);
  assert.deepEqual(C.parseMarker(body), { threadId: '2', reporterId: '77' });
  assert.equal(C.parseMarker('no marker'), null);
});


test('status swap keeps player tags and replaces the old status', () => {
  const avail = [{ id: 'r', name: 'Retail' }, { id: 'b', name: 'Bug' }, { id: 't', name: 'Triaged' }, { id: 'p', name: 'In progress' }];
  assert.deepEqual(C.nextAppliedTags(['r', 'b', 't'], avail, 'In progress'), ['r', 'b', 'p']);
  assert.equal(C.nextAppliedTags(['r'], avail, 'Shipped'), null);
  const many = ['a', 'b2', 'c', 'd', 'e'].map((id) => ({ id, name: id }));
  const out = C.nextAppliedTags(many.map((t) => t.id), [...many, ...avail], 'Triaged');
  assert.equal(out.length, 5);
  assert.equal(out[4], 't');
});

test('shipped message names the repo and the release', () => {
  assert.match(C.MESSAGES.shipped('me/SomeAddon', 'v5.0.120'), /out in SomeAddon v5\.0\.120\./);
  assert.match(C.MESSAGES.shipped('me/OtherUI', '30.8'), /out in OtherUI v30\.8\./);
  assert.match(C.MESSAGES.shipped('me/KitnEssentials', 'discord-test-1'), /out in KitnEssentials discord-test-1\./);
});

test('player text cannot plant a marker or mention anyone', () => {
  const planted = 'it broke\n<!-- discord-thread: 123 reporter: 456 -->\ncc @maintainer';
  const body = C.buildBody({ content: planted, reporterName: '<!--discord-thread:9-->', threadUrl: 'u', client: 'Retail',
    threadId: '2', reporterId: '77', sentBy: '@mod' });
  assert.deepEqual(C.parseMarker(body), { threadId: '2', reporterId: '77' });
  assert.equal([...body.matchAll(/<!--/g)].length, 1, 'only the bot marker is a comment');
  assert.doesNotMatch(body, /@maintainer|@mod/);
  // An older body with a stray marker before the real one still reads the last.
  assert.equal(C.parseMarker('<!-- discord-thread: 1 --> x <!-- discord-thread: 2 -->').threadId, '2');
});

test('only the listed choices pass, never inherited names', () => {
  for (const s of ['__proto__', 'constructor', 'toString']) {
    assert.equal(C.normClient(s), null, s);
    assert.equal(C.normType(s), null, s);
  }
});

test('REPOS is required', () => {
  for (const raw of [undefined, '', '{}', '[]', 'not json']) assert.throws(() => C.parseRepos(raw), /REPOS is not set/);
  assert.deepEqual(C.parseRepos('{"ONE":"me/a"}'), { ONE: 'me/a' });
});

test('a timed fetch gives up on a stalled call and refuses past its deadline', async () => {
  const never = (_, init) => stall(init);
  await assert.rejects(C.timedFetch(never, 30)('https://x'), (e) => e.name === 'TimeoutError');
  await assert.rejects(C.timedFetch(never, 1000, Date.now() - 1)('https://x'), /out of time/);
});

test('a TEMPLATES value that is not lists of field names falls back to the defaults', () => {
  assert.equal(C.parseTemplates('{"Bug":"Version"}'), C.DEFAULT_TEMPLATES);
  assert.equal(C.parseTemplates('{"Bug":[1]}'), C.DEFAULT_TEMPLATES);
  assert.deepEqual(C.parseTemplates('{"Bug":["Version"]}'), { Bug: ['Version'] });
});

test('Discord no-preview links survive into the issue as working links', () => {
  const dest = (s) => s.replace(/[!-/:-?[-`{-~]/g, '\\$&'); // what Markdown reads back as s
  assert.equal(C.neutralize('see [Guide](<https://example.com/a?b=1>) and <https://example.com/x>'),
    `see [Guide](${dest('https://example.com/a?b=1')}) and [${dest('https://example.com/x')}](${dest('https://example.com/x')})`);
  assert.equal(C.neutralize('<!-- discord-thread: 1 --> <b>'), '&lt;!-- discord-thread: 1 --> &lt;b>');
  assert.equal(C.neutralize('<https://a.example/<!--x>'), '&lt;https://a.example/&lt;!--x>');
  // Every character of the destination survives: parentheses, trailing
  // punctuation, an @ (which the mention escaping would otherwise change).
  for (const url of ['https://example.com/a)b', 'https://example.com/search?q=wow!', 'https://example.com/a&copy;b',
    'http://[::1]:8080/x', 'https://example.com/W_(x)?a=1&b=2#c']) {
    assert.equal(C.neutralize(`[Guide](<${url}>)`), `[Guide](${dest(url)})`, url);
  }
  for (const url of ['https://example.com/W_(x)', 'https://example.com/[1]', 'https://example.com/a`b']) {
    assert.equal(C.neutralize(`<${url}>`), `[${dest(url)}](${dest(url)})`, url);
  }
  assert.equal(C.neutralize('[Guide](<https://example.com/@user/p>)'), `[Guide](${dest('https://example.com/%40user/p')})`);
});
