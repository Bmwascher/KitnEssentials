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

const fence = (n, word = '') => '`'.repeat(n) + word;

test('a fenced code block keeps what the player typed, between fence lines the bot writes', () => {
  const inner = 'in function <Interface/AddOns/X.lua:12> @user <https://x.example/a> `x` $y ~~~';
  for (const [text, want] of [
    [`${fence(3, 'lua')}\n${inner}\n${fence(3)}`, `${fence(3, 'lua')}\n${inner}\n${fence(3)}`],
    // A tilde fence, and an unclosed one, get backtick fence lines, closed.
    [`~~~\n${inner}\n~~~`, `${fence(3)}\n${inner}\n${fence(3)}`],
    [`${fence(3)}\n${inner}`, `${fence(3)}\n${inner}\n${fence(3)}`],
    // A closing line indented up to three spaces ends the block; what follows is text.
    [`${fence(3)}\nx\n  ${fence(4)}\n@y <b>`, `${fence(3)}\nx\n${fence(3)}\n@\u200By &lt;b>`],
    // A line the bot does not take as the end stays inside, and the bot's fence outruns it.
    [`${fence(3)}\nx\n\t${fence(3)}\n@y <b>`, `${fence(4)}\nx\n\t${fence(3)}\n@y <b>\n${fence(4)}`],
    // Windows and old Mac line endings are line endings.
    [`${fence(3)}\r\nx\r\n${fence(3)}\r\n@y <b>`, `${fence(3)}\nx\n${fence(3)}\n@\u200By &lt;b>`],
    [`${fence(3)}\rx\r${fence(3)}\r@y`, `${fence(3)}\nx\n${fence(3)}\n@\u200By`],
    // A language word GitHub draws instead of showing the code is dropped.
    [`${fence(3, 'mermaid')}\nx\n${fence(3)}`, `${fence(3)}\nx\n${fence(3)}`],
  ]) assert.equal(C.neutralize(text), want, text);
});

test('a fence-like line the bot does not accept is text, with its marks escaped', () => {
  const esc = (s) => s.replace(/[`~]/g, '\\$&');
  for (const [text, want] of [
    ['  ```\n<b>\n  ```', `${esc('  ```')}\n&lt;b>\n${esc('  ```')}`],
    ['- ```\n<b>', `${esc('- ```')}\n&lt;b>`],
    ['> ~~~\n> <b>', `> ${esc('~~~')}\n> &lt;b>`],
    ['```lua title\n<b>', `${esc('```lua title')}\n&lt;b>`],
    // GitHub reads at most 255 backticks of a fence line, so a block holding a run that long stays text.
    [`~~~\n${fence(255)}\n~~~\n<b>`, `${esc('~~~')}\n${esc(fence(255))}\n${esc('~~~')}\n&lt;b>`],
  ]) assert.equal(C.neutralize(text), want, text);
});

test('inline code is text: backticks and long tilde runs are escaped, dollar signs left as typed', () => {
  for (const [text, want] of [
    ['`<b> @x`', '\\`&lt;b> @\u200Bx\\`'],
    ['a ` <b>', 'a \\` &lt;b>'],
    ['``a ` b``', '\\`\\`a \\` b\\`\\`'],
    // A mark the player already escaped stays as it is.
    ['\\`a` and \\$5', '\\`a\\` and \\$5'],
    ['$x$ ~~~ ~~y~~', '$x$ \\~\\~\\~ ~~y~~'],
  ]) assert.equal(C.neutralize(text), want, text);
  // A name sits inside the bot's own line: all of it is text.
  const body = C.buildBody({ content: 'x', reporterName: '```@x <b>', threadUrl: 'u', client: 'Retail', threadId: '2', reporterId: '77' });
  assert.ok(body.includes('**\\`\\`\\`@\u200Bx &lt;b>**'), body);
});

test('a marker comment planted inside code is broken, and only the bot marker parses', () => {
  const content = '`<!-- discord-thread: 9 reporter: 9 -->`\n```\n<!-- discord-thread: 8 -->\n```';
  const body = C.buildBody({ content, reporterName: 'Pat', threadUrl: 'u', client: 'Retail', threadId: '2', reporterId: '77' });
  assert.equal([...body.matchAll(/<!--/g)].length, 1, 'only the bot marker is a comment');
  assert.deepEqual(C.parseMarker(body), { threadId: '2', reporterId: '77' });
  assert.match(body, /\n> <\u200B!-- discord-thread: 8 -->\n/);
  assert.ok(body.includes('> \\`&lt;!-- discord-thread: 9 reporter: 9 -->\\`'), body);
});

test('a titled no-preview link becomes one working link that keeps its title', () => {
  const dest = (s) => s.replace(/[!-/:-?[-`{-~]/g, '\\$&');
  const url = 'https://example.com/a?b=1';
  for (const title of ['"hover <b>"', "'hover <b>'", '(hover <b>)']) {
    assert.equal(C.neutralize(`[Guide](<${url}> ${title})`), `[Guide](${dest(url)} "hover &lt;b>")`, title);
  }
  // The title stays title text: a URL is not turned into a link, backticks
  // open no code, and the player's escaped quote stays a quote.
  const guide = (title) => C.neutralize(`[Guide](<https://example.com> ${title})`);
  const out = (title) => `[Guide](${dest('https://example.com')} ${title})`;
  assert.equal(guide('"See <https://docs.example> @x"'), out('"See &lt;https://docs.example> @\u200Bx"'));
  assert.equal(guide('"Use `config`"'), out('"Use \\`config\\`"'));
  assert.equal(guide('"say \\"hi\\""'), out('"say \\"hi\\""'));
});

test('an escaped backtick and a bracketed URL holding backticks are prose, not code', () => {
  const dest = (s) => s.replace(/[!-/:-?[-`{-~]/g, '\\$&');
  assert.equal(C.neutralize('\\`<b> @user`'), '\\`&lt;b> @\u200Buser\\`');
  const url = 'https://example.com/a`b`';
  assert.equal(C.neutralize(`<${url}>`), `[${dest(url)}](${dest(url)})`);
  const a = 'https://x.example/a`';
  const b = 'https://y.example/b`';
  assert.equal(C.neutralize(`<${a}> and <${b}>`), `[${dest(a)}](${dest(a)}) and [${dest(b)}](${dest(b)})`);
});

const BLANK = {
  Bug: ['Addon version:', '(from your addon manager, or "not sure")', '', 'UI version:', '(from your addon manager, or "not sure")', '',
    'Updated with the game closed:', '(yes, no, or not sure)', '', 'What happened:', '(what you were doing, and what went wrong)', '',
    'What you expected:', '(what should have happened instead)', '', 'How to make it happen again:',
    '(what you did, in order. If it only happened once, say so)', '', 'Screenshots:', '(attach full-screen screenshots, or write "none")'],
  Feature: ['Area:', '(which part of the addon or UI, or "not sure")', '', 'My idea or feedback:', '(what works well, feels awkward, or is missing)', '',
    'Why it matters:', '(what you are trying to do. An example helps)', '', 'Screenshots:', '(optional: attach one, or write "none")'],
};
const states = (content, fields, attachments = 0) => C.templateCheck(content, fields, attachments).map((c) => c.state);

test('a published template pasted with its code marks reads all missing blank and all present filled', () => {
  for (const kind of ['Bug', 'Feature']) {
    const fields = C.DEFAULT_TEMPLATES[kind];
    const blank = ['```', ...BLANK[kind], '```'].join('\n');
    assert.deepEqual(states(blank, fields), fields.map(() => 'missing'), `${kind} blank`);
    const filled = blank.replace(/^\(.*\)$/gm, 'an answer');
    assert.deepEqual(states(filled, fields), fields.map(() => 'present'), `${kind} filled`);
  }
});

test('a label whose name holds another field\'s name answers only its own field, in either order', () => {
  for (const fields of [['UI version', 'Version'], ['Version', 'UI version']]) {
    const want = fields.map((f) => (f === 'UI version' ? 'present' : 'missing'));
    assert.deepEqual(states('UI version:\n2.0\nVersion:\n(hint)', fields), want, fields.join(', '));
    assert.deepEqual(states('Version:\n(hint)\nUI version:\n2.0', fields), want, `${fields.join(', ')}, swapped lines`);
  }
});

test('the template check: an answer may open with a short line and a colon, a hint is no answer, attachments and absent labels', () => {
  for (const [content, fields, attachments, want] of [
    ['What happened:\nGot this error:\n```lua\nattempt to index a nil value\n```\n\nScreenshots:\nnone', ['What happened', 'Screenshots'], 0, ['present', 'present']],
    ['What happened:\nNote: only in raids', ['What happened'], 0, ['present']],
    ['What happened:\n(what you were doing)', ['What happened'], 0, ['missing']],
    ['Screenshots:\n', ['Screenshots'], 1, ['present']],
    ['it broke', ['Area'], 0, ['unsure']],
  ]) assert.deepEqual(states(content, fields, attachments), want, content);
});

test('release tags: plain version numbers by default, and never a pre-release whatever the pattern', () => {
  const def = new RegExp(C.DEFAULT_RELEASE_PATTERN);
  for (const t of ['v5.0.120', '30.1', '31']) assert.equal(C.isRelease(t, def), true, t);
  for (const t of ['v5.1.0-beta.1', '30.2-rc1', 'nightly']) assert.equal(C.isRelease(t, def), false, t);
  const loose = /^(v|discord-test-)/;
  for (const t of ['v5.1.0-beta.1', 'v1.0.0rc1', 'discord-test-1-beta.1', 'v2.0-ALPHA', 'v3-pre']) assert.equal(C.isRelease(t, loose), false, t);
  assert.equal(C.isRelease('discord-test-1', loose), true);
});

test('button and form ids parse only when every id part is digits', () => {
  assert.deepEqual(C.parseCustomId('send:700'), { kind: 'send', threadId: '700' });
  assert.deepEqual(C.parseCustomId('gh:700:800'), { kind: 'form', threadId: '700', messageId: '800', greetingId: '' });
  assert.deepEqual(C.parseCustomId('gh:700:800:950'), { kind: 'form', threadId: '700', messageId: '800', greetingId: '950' });
  for (const bad of ['send:7a', 'send:', 'gh:700', 'gh:700:800:950:1', 'gh:7/0:800', 'xx:700:800', '', undefined]) {
    assert.equal(C.parseCustomId(bad), null, String(bad));
  }
});

test('a template message gives the label lines of its code block, or of the whole message', () => {
  for (const [content, want] of [
    ['Search this forum first.\nCopy the box below:\n```\nArea:\n(which part)\n\n**My idea or feedback:**\n(what works)\n```', ['Area', 'My idea or feedback']],
    ['Area:\n(x)\nWhy it matters:\n(y)', ['Area', 'Why it matters']],
    ['Welcome! Read the rules first.', []],
    ['```\nArea:\nScreenshots (optional):\n```', ['Area']],
  ]) assert.deepEqual(C.templateLabels(content), want, content);
});

test('a forum can name its pinned template message by its link', () => {
  // Copy Message Link gives /channels/<server>/<post>/<message>; a post's starter
  // message has the post's own id, so the last two ids can be equal.
  const f = C.parseForums({ FORUMS: JSON.stringify({
    900: { type: 'Bug', template: 'https://discord.com/channels/1/950/951' },
    901: { template: 'https://discord.com/channels/1/960/960' },
    902: { template: 'not a link' },
  }) });
  assert.deepEqual(f['900'].template, { channelId: '950', messageId: '951' });
  assert.deepEqual(f['901'].template, { channelId: '960', messageId: '960' });
  assert.equal(f['902'].template, null);
  // A value that is not a message link is flagged, so the moderator is told.
  assert.deepEqual([f['900'].badTemplate, f['902'].badTemplate], [false, true]);
});
