import test from 'node:test';
import assert from 'node:assert/strict';
import * as C from '../src/core.js';
import { discordClient } from '../src/discord.js';
import { stall, fakeFetch } from './fake-fetch.mjs';

test('title follows [ONE][Client][Module] Title', () => {
  assert.equal(C.buildTitle({ repoKey: 'ONE', client: 'Retail', module: 'Bags', title: ' Icons overlap ' }),
    '[ONE][Retail][Bags] Icons overlap');
  assert.equal(C.buildTitle({ repoKey: 'TWO', client: 'All', module: '', title: 'x' }), '[TWO][All][General] x');
  // The form pre-fills the title from the post's name: a direction mark there cannot reorder the issue's title.
  assert.equal(C.buildTitle({ repoKey: 'ONE', client: 'Retail', module: 'Ba\u202Egs', title: 'free \u202Efix\u2066 now' }), '[ONE][Retail][Bags] free fix now');
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
  assert.equal(C.cleanPostTitle('[Bug] Bags \u202Ebroken'), 'Bags broken');
});

test('body: a table names both people, then the quoted report, with the hidden lines last', () => {
  const body = C.buildBody({ content: 'line one\nline two', reporter: { name: 'Kira', username: 'kira_99', id: '42' },
    sender: { name: 'Bite', username: 'bite.mod', id: '5' }, threadUrl: 'https://discord.com/channels/1/2', attachments: [{}],
    threadId: '2', messageId: '800', templateLine: 'Area missing' });
  assert.equal(body, [
    '| Reporter | [Kira](https://discord.com/users/42) (`kira_99`) |', '| --- | --- |',
    '| Filed by | [Bite](https://discord.com/users/5) (`bite.mod`) |',
    '| Discord post | [Open the post](https://discord.com/channels/1/2) |',
    '', '## Report', '', '> line one', '> line two',
    '', '1 attachment(s) on the Discord post (open the post to see them; Discord image links expire).',
    '', 'Template check (advisory): Area missing',
    '', '<!-- discord-message: 800 -->', '<!-- discord-thread: 2 reporter: 42 -->',
  ].join('\n'));
  assert.deepEqual(C.parseMarker(body), { threadId: '2', reporterId: '42' });
  assert.equal(C.parseFiledMessage(body), '800');
  assert.equal(C.parseMarker('no marker'), null);
  // Only the bot's footer line, just before the thread marker, counts: an
  // older issue may quote such a line in its report.
  for (const older of ['<!-- discord-thread: 2 reporter: 42 -->', '> <!-- discord-message: 9 -->\n<!-- discord-thread: 2 reporter: 42 -->',
    '<!-- discord-message: 9 -->\n\ntext\n\n<!-- discord-thread: 2 reporter: 42 -->']) {
    assert.equal(C.parseFiledMessage(older), null, older);
  }
});

test('a hostile name stays one row of text: no link, mention, cross-reference or reordering', () => {
  const row = (body) => body.split('\n')[0];
  for (const [name, want] of [
    ['a|b', 'a\\|b'], ['x]y', 'x\\]y'], ['**x**', '\\*\\*x\\*\\*'], ['_b_', '\\_b\\_'],
    ['#12', '#\u200B12'], ['@org/team', '@\u200Borg/team'], ['<!--', '&lt;!--'],
    ['a\u202Eb', 'ab'], ['two\nlines', 'two lines'], ['[x](https://e.example)', '\\[x\\](https:\u200B//e.example)'],
    ['https://evil.example', 'https:\u200B//evil.example'], ['www.evil.example', 'www\u200B.evil.example'],
    // GitHub links GH-<n> to an issue, and seven or more hex digits to a commit.
    ['GH-12', 'GH-\u200B12'], ['gh-12', 'gh-\u200B12'], ['a5c3785ed8d6', 'a5c378\u200B5ed8d6'],
  ]) {
    const body = C.buildBody({ content: 'x', reporter: { name, username: 'u', id: '42' }, threadUrl: 'u', threadId: '2' });
    assert.equal(row(body), `| Reporter | [${want}](https://discord.com/users/42) (\`u\`) |`, JSON.stringify(name));
    assert.doesNotMatch(body, /<@/, JSON.stringify(name));
  }
  // A username shows exactly as typed, in a code span a backtick cannot end.
  for (const [username, want] of [['kira_99', '`kira_99`'], ['a`b|c', '``a`b\\|c``'], ['`x', '`` `x ``']]) {
    const body = C.buildBody({ content: 'x', reporter: { name: 'K', username, id: '42' }, threadUrl: 'u', threadId: '2' });
    assert.equal(row(body), `| Reporter | [K](https://discord.com/users/42) (${want}) |`, username);
  }
  // With no id there is no profile to link: the name alone.
  const noId = C.buildBody({ content: 'x', reporter: { name: 'Hook', username: 'Hook' }, threadUrl: 'u', threadId: '2' });
  assert.equal(row(noId), '| Reporter | Hook |');
  assert.match(noId, /<!-- discord-thread: 2 reporter: unknown -->$/);
});


test('a status swap keeps the other tags; a post shows a wanted status wherever its tag sits', () => {
  const avail = [{ id: 'r', name: 'Retail' }, { id: 'b', name: 'Bug' }, { id: 't', name: 'Triaged' }, { id: 'p', name: 'In progress' }];
  const five = ['a', 'b2', 'c', 'd', 'e'].map((id) => ({ id, name: id }));
  const all = [...five, ...avail];
  for (const [why, args, want] of [
    ['the status replaces the old one and keeps the rest', [['r', 'b', 't'], avail, 'In progress'], ['r', 'b', 'p']],
    ['five other tags: the status takes the fifth slot', [five.map((t) => t.id), all, 'Triaged'], ['a', 'b2', 'c', 'd', 't']],
    ['the forum has no such tag', [['r'], avail, 'Shipped'], null],
  ]) assert.deepEqual(C.nextAppliedTags(...args), want, why);
  for (const [why, applied, prefer, want] of [
    ['the first status tag', ['p', 't', 'r'], undefined, 'In progress'],
    ['the wanted status second: shown all the same', ['p', 't', 'r'], 'Triaged', 'Triaged'],
    ['the wanted status absent: the first status tag', ['p', 'r'], 'Triaged', 'In progress'],
    ['no status tag', ['r'], 'Triaged', null],
  ]) assert.equal(C.currentStatus(applied, avail, prefer), want, why);
  assert.deepEqual(C.otherTags(['a', 't', 'b2', 'p'], all), ['a', 'b2'], 'every tag but the status tags');
});

test('shipped message names the repo and the release', () => {
  assert.match(C.MESSAGES.shipped('me/SomeAddon', 'v5.0.120'), /^\*\*Out now in SomeAddon v5\.0\.120\.\*\* /);
  assert.match(C.MESSAGES.shipped('me/OtherUI', '30.8'), /^\*\*Out now in OtherUI v30\.8\.\*\* /);
  assert.match(C.MESSAGES.shipped('me/OtherAddon', 'discord-test-1'), /^\*\*Out now in OtherAddon discord-test-1\.\*\* /);
});

test('player text cannot plant a marker or mention anyone', () => {
  const planted = 'it broke\n<!-- discord-thread: 123 reporter: 456 -->\ncc @maintainer';
  const body = C.buildBody({ content: planted, reporter: { name: '<!--discord-thread:9-->', id: '77' }, threadUrl: 'u',
    threadId: '2', sender: { name: '@mod' } });
  assert.deepEqual(C.parseMarker(body), { threadId: '2', reporterId: '77' });
  assert.equal([...body.matchAll(/<!--/g)].length, 1, 'only the bot marker is a comment');
  assert.doesNotMatch(body, /@maintainer|@mod/);
  // An older body with a stray marker before the real one still reads the last.
  assert.equal(C.parseMarker('<!-- discord-thread: 1 --> x <!-- discord-thread: 2 -->').threadId, '2');
  // A direction mark in the report cannot reorder its lines in the issue.
  const marked = C.buildBody({ content: 'see \u202Etxt.exe\u2066 now', reporter: { name: 'P', id: '77' }, threadUrl: 'u', threadId: '2' });
  assert.match(marked, /\n> see txt\.exe now\n/);
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
  // A typed entity shows as typed: it never becomes an @ or a <.
  assert.equal(C.neutralize('&#64;a &commat;b &#x40;c &lt;!-- x &amp; y'), '&amp;#64;a &amp;commat;b &amp;#x40;c &amp;lt;!-- x &amp;amp; y');
  // An & that starts no entity is left alone, so a URL keeps its address.
  assert.equal(C.neutralize('a & b https://e.com/?b=1&c=2'), 'a & b https://e.com/?b=1&c=2');
  assert.equal(C.neutralize('<https://e.com/?b=1&c=2>'), `[${dest('https://e.com/?b=1&c=2')}](${dest('https://e.com/?b=1&c=2')})`);
  assert.equal(C.buildBody({ content: 'hi', reporter: { name: '&#64;mod' }, threadUrl: 'u', threadId: '1' }).includes('| Reporter | &#\u200B64;mod |'), true);
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
  const body = C.buildBody({ content: 'x', reporter: { name: '```@x <b>' }, threadUrl: 'u', threadId: '2' });
  assert.ok(body.includes('| Reporter | \\`\\`\\`@\u200Bx &lt;b> |'), body);
});

test('a marker comment planted inside code is broken, and only the bot marker parses', () => {
  const content = '`<!-- discord-thread: 9 reporter: 9 -->`\n```\n<!-- discord-thread: 8 -->\n```';
  const body = C.buildBody({ content, reporter: { name: 'Pat', id: '77' }, threadUrl: 'u', threadId: '2' });
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
    // A bold label's hint left as it is, inside the bold marks, is no answer.
    ['**AES Version: (Found in your addon management client)**', ['AES Version'], 0, ['missing']],
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
  // A card's form carries the card id fourth; a 0 greeting part means none.
  for (const [id, greetingId, cardId] of [
    ['gh:700:800', '', ''], ['gh:700:800:950', '950', ''], ['gh:700:800:950:96', '950', '96'], ['gh:700:800:0:96', '', '96'],
  ]) assert.deepEqual(C.parseCustomId(id), { kind: 'form', threadId: '700', messageId: '800', greetingId, cardId }, id);
  for (const bad of ['send:7a', 'send:', 'gh:700', 'gh:700:800:950:1:2', 'gh:700:800:0:96x', 'gh:7/0:800', 'xx:700:800', '', undefined]) {
    assert.equal(C.parseCustomId(bad), null, String(bad));
  }
});

test('a queue card links the post and shows names as text, with no preview; once filed it strikes its own first line', () => {
  const post = { guildId: '1', forumId: '900', postId: '700', postName: '**Bags** ||spoiler|| @everyone <@5>' };
  const card = C.queueCard({ ...post, author: { name: 'Kira_x', username: 'kira_99' }, client: 'Retail', type: 'Bug' });
  assert.equal(card.content, '**New post in <#900>:** \\*\\*Bags\\*\\* \\|\\|spoiler\\|\\| @everyone \\<@5\\>\nby Kira\\_x (`kira_99`) · Bug · Retail');
  assert.deepEqual([card.allowed_mentions, card.flags], [{ parse: [] }, 4], 'no ping and no link preview');
  assert.deepEqual(card.components[0].components.map((b) => [b.label, b.custom_id, b.url]), [
    ['Send to GitHub', 'send:700', undefined], ['Open post', undefined, 'https://discord.com/channels/1/700'],
  ]);
  // A post or author name makes no link, invite or preview, and cannot reorder or break its line.
  for (const [name, want] of [
    ['free fix https://evil.example', 'free fix https:\u200B//evil.example'],
    ['see www.evil.example', 'see www\u200B.evil.example'],
    ['join discord.gg/abc', 'join discord\u200B.gg/abc'],
    ['a\u202Eb\u2066c', 'abc'],
    ['two\nlines', 'two lines'],
  ]) {
    const named = C.queueCard({ ...post, postName: name, author: { name } });
    assert.equal(named.content, `**New post in <#900>:** ${want}\nby ${want}`, JSON.stringify(name));
  }
  assert.equal(C.queueCard({ ...post, postName: 'x' }).content, '**New post in <#900>:** x', 'unknown parts are left out');
  // A post whose first message is gone cannot be filed from a button: the card says how to file it instead.
  const gone = C.queueCard({ ...post, postName: 'x', starterGone: true });
  assert.equal(gone.content, '**New post in <#900>:** x\nIts first message was deleted: a moderator can open the post and right-click a message › Apps › Send to GitHub.');
  assert.deepEqual(gone.components[0].components.map((b) => [b.label, b.custom_id, b.url]), [['Open post', undefined, 'https://discord.com/channels/1/700']]);
  // The head is the card's first line as shown, already escaped: it is not escaped again.
  const head = C.cardHead('900', 'a_b');
  for (const [by, line] of [['Bite', '**Filed as ONE #10** by Bite'], [undefined, '**Filed as ONE #10**']]) {
    const filed = C.filedCard({ guildId: '1', postId: '700', head, key: 'ONE', number: 10, by });
    assert.equal(filed.content, `~~**New post in <#900>:** a\\_b~~\n${line}`, line);
    assert.deepEqual([filed.allowed_mentions, filed.flags], [{ parse: [] }, 4], line);
    assert.deepEqual(filed.components[0].components.map((b) => [b.label, b.url]), [['Open post', 'https://discord.com/channels/1/700']], line);
  }
  // A username shows in its code span on one line, with no direction mark.
  assert.equal(C.queueCard({ ...post, postName: 'x', author: { name: 'k', username: 'ki\u202Era`' } }).content, '**New post in <#900>:** x\nby k (`kira`)');
  // A card an older version sent may show a live link or a direction mark in its first line: struck, it shows neither.
  const older = C.filedCard({ guildId: '1', postId: '700', head: '**New post in <#900>:** free https://evil.example \u202Ewww.evil.example', key: 'ONE', number: 10 });
  assert.equal(older.content, '~~**New post in <#900>:** free https:\u200B//evil.example www\u200B.evil.example~~\n**Filed as ONE #10**');
});

// A help-post template as forums pin it: bold labels, italic hints, a list.
const PINNED = ['**Addon Version:** *(Found in your addon management client)*', '**UI Version:** *(Found in your addon management client)*',
  '**Updated addons outside of game? (Yes/No):**', '', '**Issue Details:**', '', '**Steps to Reproduce:**', '1.', '2.', '3.', '',
  '**Supporting Screenshots:**', '*(Please attach uncropped, full-screen screenshots below showing both the issue and your entire UI)*'].join('\n');

test('a template message gives the label lines of its code block, or of the whole message', () => {
  const req = (...names) => names.map((name) => ({ name, optional: false }));
  for (const [content, want] of [
    ['Search this forum first.\nCopy the box below:\n```\nArea:\n(which part)\n\n**My idea or feedback:**\n(what works)\n```', req('Area', 'My idea or feedback')],
    ['Area:\n(x)\nWhy it matters:\n(y)', req('Area', 'Why it matters')],
    ['Welcome! Read the rules first.', []],
    // Text on the opening line is the block's first line unless it is one plain language word.
    ['```UI Version:\nArea:\n```', req('UI Version', 'Area')],
    ['```Version:\nArea:\n```', req('Version', 'Area')],
    ['```yaml\nArea:\n```', req('Area')],
    ['```c++\nArea:\n```', req('Area')],
    ['```\nUI Version: (Found in your addon management client)\n```', req('UI Version')],
    ['```\nUpdated addons outside of game? (Yes/No): \n```', req('Updated addons outside of game')],
    ['```\nArea:\nScreenshots (optional):\n```', [...req('Area'), { name: 'Screenshots', optional: true }]],
    // Only the word "optional" marks a label optional.
    ['```\nScreenshots (nonoptional):\n```', req('Screenshots')],
    ['```\nNote: only in raids\n```', []],
    [PINNED, req('Addon Version', 'UI Version', 'Updated addons outside of game', 'Issue Details', 'Steps to Reproduce', 'Supporting Screenshots')],
  ]) assert.deepEqual(C.templateLabels(content), want, content);
});

test('template gaps leave out present fields and optional ones', () => {
  const check = (states) => Object.entries(states).map(([field, state]) => ({ field, state }));
  for (const [why, states, optional, want] of [
    ['an optional field left blank', { Area: 'present', Screenshots: 'missing' }, ['Screenshots'], []],
    ['an optional field filled', { Area: 'present', Screenshots: 'present' }, ['Screenshots'], []],
    ['a required field missing and one unsure', { Area: 'missing', 'Why it matters': 'unsure', Screenshots: 'present' }, [], ['Area missing', 'Why it matters unsure']],
    ['every field present', { Area: 'present' }, [], []],
  ]) assert.deepEqual(C.templateGaps(check(states), optional), want, why);
});

test('a failed template read gives the moderator a plain note', () => {
  for (const [err, want] of [
    [new Error('Discord GET /channels/1/messages/2 -> 404 {"message": "Unknown Message", "code": 10008}'), /^the template message was not found; check the forum's template link, so the default fields were checked$/],
    [new Error('Discord GET /channels/1/messages/2 -> 403 {"message": "Missing Access"}'), /^the bot may not read the template message; check its access to that post, so the default fields were checked$/],
    [Object.assign(new Error('The operation was aborted due to timeout'), { name: 'TimeoutError' }), /^the template message could not be read just now, so the default fields were checked$/],
  ]) assert.match(C.templateNote(err), want, err.message);
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

test('a reply pings its target; a refused reply goes once more plain, and any other error is thrown', async () => {
  const plainBody = { content: 'hi', allowed_mentions: { parse: [], users: [] } };
  const reply = { content: 'hi', allowed_mentions: { parse: [], users: [], replied_user: true }, message_reference: { message_id: '800', fail_if_not_exists: false } };
  for (const [why, answers, opts, sent, outcome] of [
    ['a pinged reply', [200], { replyTo: '800' }, [reply], 'sent'],
    ['a refused reply goes once more, plain', [400, 200], { replyTo: '800' }, [reply, plainBody], 'refused'],
    ['a server error is thrown, with no second send', [500], { replyTo: '800' }, [reply], 'thrown'],
  ]) {
    const queue = [...answers];
    const f = fakeFetch([['POST', /\/channels\/700\/messages$/, () => {
      const status = queue.shift();
      return status === 200 ? { id: '1' } : new Response('{"message":"x"}', { status });
    }]]);
    const send = discordClient('t', f).send('700', 'hi', [], opts);
    if (outcome === 'thrown') await assert.rejects(send, / -> 500 /, why);
    else assert.equal((await send).replyRefused, outcome === 'refused' ? true : undefined, why);
    assert.deepEqual(f.calls.map((c) => c.body), sent, why);
  }
});

test('status writes read the post again first, never reopen a post already showing its status, and drop a staff tag only when asked', async () => {
  const forum = { id: '900', available_tags: [{ id: 'r', name: 'Retail' }, { id: 'x', name: 'Staff note' }, { id: 'a', name: 'A' },
    { id: 'b2', name: 'B' }, { id: 'c', name: 'C' }, { id: 't', name: 'Triaged' }, { id: 'p', name: 'In progress' }] };
  const post = (tags, archived = false) => ({ id: '700', parent_id: '900', applied_tags: tags, thread_metadata: { archived } });
  const five = ['r', 'x', 'a', 'b2', 'c'];
  for (const [why, reads, write, patches, out] of [
    ['a status another writer set between the reads: no write', [post(['r']), post(['r', 'p'])],
      (d) => d.setStatus('700', 'Triaged'), [], { raced: true }],
    ['a tag added between the reads is kept', [post(['r']), post(['r', 'x'])],
      (d) => d.setStatus('700', 'Triaged'), [{ applied_tags: ['r', 'x', 't'] }], { raced: false }],
    // A second status tag is no reason to reopen an archived post, in either order.
    ['an archived post showing its status first, beside a second status tag', [post(['t', 'p', 'r'], true)],
      (d) => d.setStatus('700', 'Triaged'), [], { from: 'Triaged' }],
    ['an archived post showing its status second', [post(['p', 't', 'r'], true)],
      (d) => d.setStatus('700', 'Triaged'), [], { from: 'Triaged' }],
    ['an archived post whose status moves: reopened in the same write', [post(['r', 't'], true)],
      (d) => d.setStatus('700', 'In progress'), [{ applied_tags: ['r', 'p'], archived: false }], { from: 'Triaged' }],
    // A status run never drops a staff tag to show Triaged.
    ['no status and five other tags, nothing to drop: no write', [post(five)],
      (d) => d.setStatus('700', 'Triaged', undefined, { dropOther: false }), [], { skipped: true }],
    ['the same at filing, as today: the fifth tag makes room', [post(five), post(five)],
      (d) => d.setStatus('700', 'Triaged'), [{ applied_tags: ['r', 'x', 'a', 'b2', 't'] }], { skipped: false }],
  ]) {
    const queue = [...reads];
    const f = fakeFetch([
      ['GET', /\/channels\/700$/, () => (queue.length > 1 ? queue.shift() : queue[0])],
      ['GET', /\/channels\/900$/, () => forum],
      ['PATCH', /\/channels\/700$/, () => ({})],
    ]);
    const r = await write(discordClient('t', f));
    assert.deepEqual(f.find('PATCH', /\/channels\/700$/).map((c) => c.body), patches, why);
    for (const [k, v] of Object.entries(out)) assert.equal(typeof v === 'boolean' ? !!r[k] : r[k], v, `${why}: ${k}`);
  }
  const f = fakeFetch([['GET', /\/channels\/700$/, () => post(['p', 't'])], ['GET', /\/channels\/900$/, () => forum]]);
  assert.equal(await discordClient('t', f).statusOf('700', 'Triaged'), 'Triaged', 'statusOf reads the wanted status wherever it sits');
});

test('a status tag renamed to a staff tag between the reads is read with the forum as it is now', async () => {
  const tags = [{ id: 'a', name: 'A' }, { id: 'b2', name: 'B' }, { id: 'c', name: 'C' }, { id: 'x', name: 'Staff note' }, { id: 'z', name: 'Closed' }, { id: 't', name: 'Triaged' }];
  // Staff rename the post's Closed tag to a name of their own while the bot reads.
  const forums = [{ id: '900', available_tags: tags }, { id: '900', available_tags: tags.map((t) => (t.id === 'z' ? { ...t, name: 'Needs review' } : t)) }];
  const f = fakeFetch([
    ['GET', /\/channels\/700$/, () => ({ id: '700', parent_id: '900', applied_tags: ['a', 'b2', 'c', 'x', 'z'] })],
    ['GET', /\/channels\/900$/, () => (forums.length > 1 ? forums.shift() : forums[0])],
    ['PATCH', /\/channels\/700$/, () => ({})],
  ]);
  const r = await discordClient('t', f).setStatus('700', 'Triaged', undefined, { dropOther: false });
  assert.deepEqual(f.find('PATCH', /\/channels\/700$/), [], 'no staff tag is dropped');
  assert.equal(r.raced, true, 'the caller decides again from the post as it is now');
});

test('a tag staff add while the forum is read again is kept: the post is read last, just before the write', async () => {
  const tags = [{ id: 'a', name: 'A' }, { id: 'b', name: 'B' }, { id: 'c', name: 'C' }, { id: 'd', name: 'D' }, { id: 'x', name: 'Staff note' }, { id: 't', name: 'Triaged' }];
  const post = { id: '700', parent_id: '900', applied_tags: ['a', 'b', 'c', 'd'] };
  let forumReads = 0;
  const f = fakeFetch([
    ['GET', /\/channels\/700$/, () => ({ ...post, applied_tags: [...post.applied_tags] })],
    // Staff add a fifth tag of their own while the bot reads the forum the second time.
    ['GET', /\/channels\/900$/, () => { if (++forumReads === 2) post.applied_tags.push('x'); return { id: '900', available_tags: tags }; }],
    ['PATCH', /\/channels\/700$/, () => ({})],
  ]);
  const r = await discordClient('t', f).setStatus('700', 'Triaged', undefined, { dropOther: false });
  assert.deepEqual(f.find('PATCH', /\/channels\/700$/), [], 'no staff tag is dropped');
  assert.match(r.skipped, /no free tag slot/);
});
