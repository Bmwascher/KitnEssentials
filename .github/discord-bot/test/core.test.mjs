import test from 'node:test';
import assert from 'node:assert/strict';
import * as C from '../src/core.js';

test('title follows [AES][Client][Module] Title', () => {
  assert.equal(C.buildTitle({ repoKey: 'AES', client: 'Retail', module: 'Bags', title: ' Icons overlap ' }),
    '[AES][Retail][Bags] Icons overlap');
  assert.equal(C.buildTitle({ repoKey: 'AUI', client: 'All', module: '', title: 'x' }), '[AUI][All][General] x');
});

test('form values normalize, junk is refused', () => {
  assert.equal(C.normClient('forever'), 'Forever');
  assert.equal(C.normClient('classic'), null);
  assert.equal(C.normType('Feedback/Request'), 'Feature');
  assert.equal(C.normType('bug'), 'Bug');
  assert.equal(C.normType('question'), null);
  assert.equal(C.normRepoKey('aui', { AES: 'a', AUI: 'b' }), 'AUI');
  assert.equal(C.normRepoKey('kitn', { AES: 'a' }), null);
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

test('closing keywords find linked issues', () => {
  assert.deepEqual(C.closingIssues('Fixes #12, closes #3 and resolved: #4. See #9'), [12, 3, 4]);
  assert.deepEqual(C.closingIssues('fix #5\nFIXED #5'), [5]);
  assert.deepEqual(C.closingIssues('related to #8'), []);
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

test('shipped message names the release', () => {
  assert.match(C.MESSAGES.shipped('AES', 'v5.0.120'), /atrocityEssentials v5\.0\.120/);
  assert.match(C.MESSAGES.shipped('AUI', '30.8'), /atrocityUI v30\.8/);
  assert.equal(C.keyForRepo('AtrocityZero/atrocityUI', { AES: 'atrocityzero/atrocityEssentials', AUI: 'atrocityzero/atrocityUI' }), 'AUI');
});
