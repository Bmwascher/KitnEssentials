import test from 'node:test';
import assert from 'node:assert/strict';
import * as C from '../src/core.js';
import { discordClient, answeredStatus } from '../src/discord.js';
import { stall, fakeFetch } from './fake-fetch.mjs';

test('title follows [KEY] [Client] [Type] [Module] Title, each module word capitalized', () => {
  for (const [repoKey, client, type, module, title, want] of [
    ['ONE', 'Retail', 'Bug', 'Bags', ' Icons overlap ', '[ONE] [Retail] [Bug] [Bags] Icons overlap'],
    ['TWO', 'All', 'Feature', '', 'x', '[TWO] [All] [Feature] [General] x'],
    ['ONE', 'Forever', 'Bug', 'damage meter', 'x', '[ONE] [Forever] [Bug] [Damage Meter] x'],
    ['ONE', 'Retail', 'Bug', 'UI', 'x', '[ONE] [Retail] [Bug] [UI] x'],
    ['ONE', 'Retail', 'Bug', 'bAGS', 'x', '[ONE] [Retail] [Bug] [BAGS] x'],
    // A letter outside the Basic Multilingual Plane is one character.
    ['ONE', 'Retail', 'Bug', '\u{10428}bc', 'x', '[ONE] [Retail] [Bug] [\u{10400}bc] x'],
    // A capital that is not one letter would lengthen the module.
    ['ONE', 'Retail', 'Bug', '\uFB03x \u00DFx', 'x', '[ONE] [Retail] [Bug] [\uFB03x \u00DFx] x'],
    ['ONE', 'Retail', 'Bug', '[bags] beta', 'x', '[ONE] [Retail] [Bug] [Bags Beta] x'],
    ['ONE', 'Retail', 'Bug', '  ', 'x', '[ONE] [Retail] [Bug] [General] x'],
    // The form pre-fills the title from the post's name: a direction mark there cannot reorder the issue's title.
    ['ONE', 'Retail', 'Bug', 'ba\u202Egs', 'free \u202Efix\u2066 now', '[ONE] [Retail] [Bug] [Bags] free fix now'],
  ]) assert.equal(C.buildTitle({ repoKey, client, type, module, title }), want, module);
});

test('the issue gets the whole title; the post name is cut to 100 characters inside the title, never splitting a surrogate pair', () => {
  const issueTitle = (title) => C.buildTitle({ repoKey: 'ONE', client: 'Retail', type: 'Bug', module: 'Bags', title });
  const prefix = '[ONE] [Retail] [Bug] [Bags] ';
  assert.equal(C.fitName(issueTitle('short')), `${prefix}short`);
  const long = 'y'.repeat(200);
  assert.equal(issueTitle(long), `${prefix}${long}`);
  assert.equal(C.fitName(issueTitle(long)), `${prefix}${'y'.repeat(100 - prefix.length)}`);
  // An emoji whose first half is the 100th unit is left out whole.
  const ys = 'y'.repeat(99 - prefix.length);
  assert.equal(C.fitName(issueTitle(`${ys}\u{1F600}z`)), `${prefix}${ys}`);
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

test('post title loses typed [..] prefixes, and a renamed post the bot\'s prefix', () => {
  assert.equal(C.cleanPostTitle('[ONE] [Retail] [Bug] [Damage Meter] Bags broken'), 'Bags broken');
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
  assert.deepEqual(C.parseFiledMessage(body), { id: '800', copy: false });
  assert.equal(C.parseMarker('no marker'), null);
  // Only the bot's footer line, just before the thread marker, counts: an
  // older issue may quote such a line in its report.
  for (const older of ['<!-- discord-thread: 2 reporter: 42 -->', '> <!-- discord-message: 9 -->\n<!-- discord-thread: 2 reporter: 42 -->',
    '<!-- discord-message: 9 -->\n\ntext\n\n<!-- discord-thread: 2 reporter: 42 -->']) {
    assert.equal(C.parseFiledMessage(older), null, older);
  }
});

test('a hostile name stays one row of text: no Markdown, mention or reordering', () => {
  const row = (body) => body.split('\n')[0];
  for (const [name, want] of [
    ['a|b', 'a\\|b'], ['x]y', 'x\\]y'], ['**x**', '\\*\\*x\\*\\*'], ['_b_', '\\_b\\_'],
    ['@org/team', '@\u200Borg/team'], ['<!--', '&lt;!--'],
    ['a\u202Eb', 'ab'], ['two\nlines', 'two lines'], ['[x](https://e.example)', '\\[x\\](https://e.example)'],
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

test('REPOS is required, and each key is letters and digits only', () => {
  for (const raw of [undefined, '', '{}', '[]', 'not json']) assert.throws(() => C.parseRepos(raw), /REPOS is not set/);
  assert.deepEqual(C.parseRepos('{"ONE":"me/a","v2":"me/b"}'), { ONE: 'me/a', v2: 'me/b' });
  // The key starts the issue's title and the post's name, where the form finds it again.
  for (const key of ['', 'A B', 'U]I', 'K-E', `U${String.fromCharCode(0x202e)}I`]) {
    assert.throws(() => C.parseRepos(JSON.stringify({ ONE: 'me/a', [key]: 'me/b' })), (e) => JSON.stringify(e.badKeys) === JSON.stringify([key]), JSON.stringify(key));
  }
  // Every bad key is named, not only the first.
  assert.throws(() => C.parseRepos('{"AB CD":"me/a","ONE":"me/b","K-E":"me/c"}'), (e) => JSON.stringify(e.badKeys) === '["AB CD","K-E"]');
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
  assert.equal(C.buildBody({ content: 'hi', reporter: { name: '&#64;mod' }, threadUrl: 'u', threadId: '1' }).includes('| Reporter | &amp;#64;mod |'), true);
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
  assert.deepEqual(C.parseCustomId('move:700'), { kind: 'move', threadId: '700' });
  assert.deepEqual(C.parseCustomId('mv:700'), { kind: 'moveForm', threadId: '700', cardId: '' });
  assert.deepEqual(C.parseCustomId('mv:700:96'), { kind: 'moveForm', threadId: '700', cardId: '96' });
  assert.deepEqual(C.parseCustomId('add:700'), { kind: 'add', threadId: '700' });
  // The add form carries the card id third; a 0 card part means none.
  for (const [id, messageId, cardId] of [['ai:700:800:96', '800', '96'], ['ai:700:700:0', '700', '']]) {
    assert.deepEqual(C.parseCustomId(id), { kind: 'addForm', threadId: '700', messageId, cardId }, id);
  }
  // The form carries the repo key and the client it pre-selected; a 0 card part means none.
  for (const [id, cardId, shownKey, shownClient] of [
    ['mv:700:96:KE:All', '96', 'KE', 'All'], ['mv:700:0:KE:Retail', '', 'KE', 'Retail'], ['mv:700:96::Forever', '96', '', 'Forever'], ['mv:700:96:KE:', '96', 'KE', ''],
  ]) assert.deepEqual(C.parseCustomId(id), { kind: 'moveForm', threadId: '700', cardId, shownKey, shownClient }, id);
  for (const bad of ['send:7a', 'send:', 'gh:700', 'gh:700:800:950:1:2', 'gh:700:800:0:96x', 'gh:7/0:800', 'xx:700:800', '', undefined,
    'move:7a', 'move:', 'mv:', 'mv:700:', 'mv:700:96:1', 'mv:7/0', 'add:7a', 'ai:700:800', 'ai:700:8x0:0']) {
    assert.equal(C.parseCustomId(bad), null, String(bad));
  }
});

test('a queue card names the post and its poster by Discord mention, pinging no one and showing no preview; once filed it strikes its own first line', () => {
  const post = { guildId: '1', forumId: '900', postId: '700' };
  // The post is Discord's own mention of it, so no text a player chose is in the first line; the poster's mention opens their profile.
  const card = C.queueCard({ ...post, author: { name: 'Kira_x', username: 'kira_99', id: '42' }, client: 'Retail', type: 'Bug' });
  assert.equal(card.content, '**New post in <#900>:** <#700>\nby <@42> (`kira_99`) · Bug · Retail');
  assert.deepEqual([card.allowed_mentions, card.flags], [{ parse: [] }, 4], 'no ping and no link preview');
  assert.deepEqual(card.components[0].components.map((b) => [b.label, b.custom_id, b.url]), [
    ['Send to GitHub', 'send:700', undefined], ['Add to issue', 'add:700', undefined], ['Move', 'move:700', undefined], ['Open post', undefined, 'https://discord.com/channels/1/700'],
  ]);
  // A poster with no user id (a webhook) is named as text: it cannot format, mention, link, invite, preview, or reorder or break its line.
  for (const [name, want] of [
    ['**Bags** ||spoiler|| @everyone <@5>', '\\*\\*Bags\\*\\* \\|\\|spoiler\\|\\| @everyone \\<@5\\>'],
    ['free fix https://evil.example', 'free fix https:\u200B//evil.example'],
    ['see www.evil.example', 'see www\u200B.evil.example'],
    ['join discord.gg/abc', 'join discord\u200B.gg/abc'],
    ['a\u202Eb\u2066c', 'abc'],
    ['two\nlines', 'two lines'],
  ]) {
    const named = C.queueCard({ ...post, author: { name } });
    assert.equal(named.content, `**New post in <#900>:** <#700>\nby ${want}`, JSON.stringify(name));
  }
  // An id that is not digits names no user: never a mention.
  assert.equal(C.queueCard({ ...post, author: { name: 'k', username: 'kira', id: '<@&1>' } }).content, '**New post in <#900>:** <#700>\nby k (`kira`)');
  assert.equal(C.queueCard(post).content, '**New post in <#900>:** <#700>', 'unknown parts are left out');
  // A post whose first message is gone cannot be filed from a button: the card says how to file it instead.
  const gone = C.queueCard({ ...post, starterGone: true });
  assert.equal(gone.content, '**New post in <#900>:** <#700>\nIts first message was deleted: a moderator can open the post and right-click a message › Apps › Send to GitHub.');
  assert.deepEqual(gone.components[0].components.map((b) => [b.label, b.custom_id, b.url]), [['Open post', undefined, 'https://discord.com/channels/1/700']]);
  // Filed, the card strikes its first line with the post's mention still in it.
  const head = C.cardHead('900', '700');
  for (const [by, line] of [['Bite', '**Filed as ONE #10** by Bite'], [undefined, '**Filed as ONE #10**']]) {
    const filed = C.filedCard({ guildId: '1', postId: '700', head, key: 'ONE', number: 10, by });
    assert.equal(filed.content, `~~**New post in <#900>:** <#700>~~\n${line}`, line);
    assert.deepEqual([filed.allowed_mentions, filed.flags], [{ parse: [] }, 4], line);
    assert.deepEqual(filed.components[0].components.map((b) => [b.label, b.custom_id, b.url]), [['Move', 'move:700', undefined], ['Open post', undefined, 'https://discord.com/channels/1/700']], line);
  }
  // Added to an issue, the card offers only the post.
  const added = C.filedCard({ guildId: '1', postId: '700', head, key: 'ONE', number: 12, by: '<@5>', added: true });
  assert.equal(added.content, '~~**New post in <#900>:** <#700>~~\n**Added to ONE #12** by <@5>');
  assert.deepEqual(added.components[0].components.map((b) => [b.label, b.url]), [['Open post', 'https://discord.com/channels/1/700']]);
  // A username shows in its code span on one line, with no direction mark.
  assert.equal(C.queueCard({ ...post, author: { name: 'k', username: 'ki\u202Era`', id: '42' } }).content, '**New post in <#900>:** <#700>\nby <@42> (`kira`)');
  // An older card names the post as escaped text and may show a live link or a direction mark: struck, it is not escaped again and shows neither.
  const older = C.filedCard({ guildId: '1', postId: '700', head: '**New post in <#900>:** a\\_b free https://evil.example \u202Ewww.evil.example', key: 'ONE', number: 10 });
  assert.equal(older.content, '~~**New post in <#900>:** a\\_b free https:\u200B//evil.example www\u200B.evil.example~~\n**Filed as ONE #10**');
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
    ['a server error whose answer quotes " -> 400 " is thrown, with no second send', [[500, 'upstream said -> 400 x']], { replyTo: '800' }, [reply], 'thrown'],
  ]) {
    const queue = [...answers];
    const f = fakeFetch([['POST', /\/channels\/700\/messages$/, () => {
      const [status, text = '{"message":"x"}'] = [].concat(queue.shift());
      return status === 200 ? { id: '1' } : new Response(text, { status });
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
});

test('a tag staff add while the forum is read is kept: the post is read again, just before the write', async () => {
  const tags = [{ id: 'a', name: 'A' }, { id: 'b', name: 'B' }, { id: 'c', name: 'C' }, { id: 'd', name: 'D' }, { id: 'x', name: 'Staff note' }, { id: 't', name: 'Triaged' }];
  const post = { id: '700', parent_id: '900', applied_tags: ['a', 'b', 'c', 'd'] };
  let forumReads = 0;
  const f = fakeFetch([
    ['GET', /\/channels\/700$/, () => ({ ...post, applied_tags: [...post.applied_tags] })],
    // Staff add a fifth tag of their own while the bot reads the forum.
    ['GET', /\/channels\/900$/, () => { if (++forumReads === 1) post.applied_tags.push('x'); return { id: '900', available_tags: tags }; }],
    ['PATCH', /\/channels\/700$/, () => ({})],
  ]);
  const r = await discordClient('t', f).setStatus('700', 'Triaged', undefined, { dropOther: false });
  assert.deepEqual(f.find('PATCH', /\/channels\/700$/), [], 'no staff tag is dropped');
  assert.match(r.skipped, /no free tag slot/);
});

test('CT1: tag planning: the status takes its slot, Accepted only a free one, and a staff tag is dropped only when asked', () => {
  const avail = [{ id: 'a', name: 'A' }, { id: 'b', name: 'B' }, { id: 'c', name: 'C' }, { id: 'd', name: 'D' }, { id: 'e', name: 'E' },
    { id: 'tri', name: 'Triaged' }, { id: 'wf', name: "Won't fix" }, { id: 'acc', name: 'Accepted' }];
  const names = C.CHECKLIST_NAMES;
  const keep = { names, accepted: false, dropOther: false };
  for (const [why, current, status, opts, want] of [
    ['the status replaces the old one and keeps other tags', ['a', 'wf'], 'Triaged', keep, { tags: ['a', 'tri'] }],
    ['the forum lacks the status tag: the tags stay as they are', ['a', 'acc'], 'Done', keep, { tags: ['a', 'acc'], missing: true }],
    ['five other tags and no status: nothing is dropped', ['a', 'b', 'c', 'd', 'e'], 'Triaged', keep, { tags: ['a', 'b', 'c', 'd', 'e'], full: true }],
    ['five other tags with dropOther: the fifth makes room, as today', ['a', 'b', 'c', 'd', 'e'], 'Triaged', { names, accepted: false }, { tags: ['a', 'b', 'c', 'd', 'tri'] }],
    ['Accepted goes into a free slot', ['a', 'tri'], 'Triaged', { ...keep, accepted: true }, { tags: ['a', 'tri', 'acc'] }],
    ['no free slot for Accepted: nothing is dropped', ['a', 'b', 'c', 'd', 'tri'], 'Triaged', { ...keep, accepted: true }, { tags: ['a', 'b', 'c', 'd', 'tri'], noRoom: true }],
    ['Accepted and four other tags with a status to place: the four stay, Accepted waits', ['acc', 'a', 'b', 'c', 'd'], 'Triaged', { ...keep, accepted: true }, { tags: ['a', 'b', 'c', 'd', 'tri'], noRoom: true }],
    ['Accepted is taken off when not wanted', ['a', 'acc', 'tri'], 'Triaged', keep, { tags: ['a', 'tri'] }],
  ]) {
    const r = C.planTags(current, avail, status, opts);
    assert.deepEqual(r.tags, want.tags, why);
    for (const k of ['missing', 'full', 'noRoom']) assert.equal(r[k], !!want[k], `${why}: ${k}`);
  }
  const noAccepted = avail.filter((t) => t.id !== 'acc');
  assert.equal(C.planTags(['a'], noAccepted, 'Triaged', { ...keep, accepted: true }).noAccepted, true, 'a forum with no Accepted tag');
  // A second tag named Accepted in another letter case is the bot's too.
  const twice = [...avail, { id: 'acc2', name: 'ACCEPTED' }];
  assert.deepEqual(C.planTags(['a', 'acc2', 'tri'], twice, 'Triaged', keep).tags, ['a', 'tri'], 'every Accepted tag is taken off');
  assert.deepEqual(C.planTags(['a', 'acc2', 'tri'], twice, 'Triaged', { ...keep, accepted: true }).tags, ['a', 'tri', 'acc'], 'and one is set');
});

test('CT2: a public status and close reason map to a checklist status, and only a finished one with a close has an archive key', () => {
  for (const [status, reason, want] of [
    ['Triaged', null, 'Triaged'], ['In progress', null, 'In progress'], ['Fixed, next update', 'completed', 'Fixed'],
    ['Shipped', 'completed', 'Shipped'], ['Closed', 'completed', 'Done'], ['Closed', 'not_planned', "Won't fix"], ['Closed', 'duplicate', 'Duplicate'],
  ]) assert.equal(C.checklistStatus(status, reason), want, `${status}, ${reason}`);
  const close = { id: 77 };
  for (const [name, c, want] of [
    ['Shipped', close, 'Shipped:77'], ["Won't fix", close, "Won't fix:77"], ['Duplicate', close, 'Duplicate:77'],
    ['Fixed', close, null], ['Triaged', null, null], ['Done', null, null],
  ]) assert.equal(C.checklistKey(name, c), want, name);
});

test('CT3: a checklist thread name is cut to 100 characters, never between the halves of a surrogate pair', () => {
  for (const [why, title, want] of [
    ['short', 'Bank tab icons overlap', '#12 Bank tab icons overlap'],
    ['long', 'x'.repeat(120), `#12 ${'x'.repeat(96)}`],
    ['a surrogate pair across the cut', `${'x'.repeat(95)}\u{1F600}y`, `#12 ${'x'.repeat(95)}`],
    ['control characters and a line break', 'a\u0007b\nc', '#12 ab c'],
  ]) assert.equal(C.threadName(12, title), want, why);
});

test('CT4: the staff checklist forum is never a player forum, even when FORUMS lists it', () => {
  assert.deepEqual(Object.keys(C.parseForums({ FORUMS: JSON.stringify({ 900: {}, 950: {} }), CHECKLIST_FORUM_ID: '950' })), ['900']);
  assert.deepEqual(Object.keys(C.parseForums({ FORUM_CHANNEL_IDS: '900, 950', CHECKLIST_FORUM_ID: '950' })), ['900']);
});

test('CT5: a checklist tag write reads the forum, then the thread, and keeps the archive state unless told to open', async () => {
  const forum = { id: '950', available_tags: [{ id: 'tri', name: 'Triaged' }, { id: 'prog', name: 'In progress' }, { id: 'acc', name: 'Accepted' }] };
  const thread = (tags, archived, parent = '950') => ({ id: '960', parent_id: parent, applied_tags: tags, thread_metadata: { archived } });
  const plan = (status, accepted) => (applied, available) => C.planTags(applied, available, status, { names: C.CHECKLIST_NAMES, accepted, dropOther: false });
  const both = [{ applied_tags: ['prog'], archived: false }, { archived: true }];
  for (const [why, t, p, open, patches, fails = {}, outcome = null] of [
    ['an open thread: one write', thread(['tri'], false), plan('In progress', false), false, [{ applied_tags: ['prog'] }]],
    ['an archived thread: opened in the write, archived again next', thread(['tri'], true), plan('In progress', true), false,
      [{ applied_tags: ['prog', 'acc'], archived: false }, { archived: true }]],
    ['tags already right: no write', thread(['tri'], true), plan('Triaged', false), false, []],
    ['the forum lacks the status tag: no write, even for Accepted', thread(['tri'], true), plan('Done', true), false, []],
    ['told to open: the write opens it and leaves it open', thread(['tri'], true), plan('In progress', false), true, [{ applied_tags: ['prog'], archived: false }]],
    ['told to open, tags right: it is only opened', thread(['tri'], true), plan('Triaged', false), true, [{ archived: false }]],
    ['told to open, the status tag missing: opened, no tags written', thread(['tri'], true), plan('Done', false), true, [{ archived: false }]],
    ['the re-archive fails: thrown', thread(['tri'], true), plan('In progress', false), false, both, { 2: 500 }, 'thrown'],
    ['the opening write fails: nothing more sent, thrown', thread(['tri'], true), plan('In progress', false), false,
      [{ applied_tags: ['prog'], archived: false }], { 1: 500 }, 'thrown'],
    ['a thread in another forum: no write', thread(['tri'], false, '900'), plan('In progress', false), false, [], {}, 'forum'],
  ]) {
    let patchNo = 0;
    const f = fakeFetch([
      ['GET', /\/channels\/950$/, () => forum],
      ['GET', /\/channels\/960$/, () => t],
      ['PATCH', /\/channels\/960$/, () => {
        const status = fails[++patchNo];
        return status ? new Response('{"message":"x"}', { status }) : {};
      }],
    ]);
    const write = discordClient('t', f).setTags('960', '950', p, { open });
    if (outcome === 'forum') await assert.rejects(write, /not the checklist forum/, why);
    else if (outcome) await assert.rejects(write, /-> 500/, why);
    else await write;
    assert.deepEqual(f.calls.slice(0, 2).map((c) => `${c.method} ${c.url.replace(/^.*\/channels\//, '')}`), ['GET 950', 'GET 960'], `${why}: the thread is read last`);
    assert.deepEqual(f.find('PATCH', /\/channels\/960$/).map((c) => c.body), patches, why);
  }
});

test('CT7: a Discord error\'s status is read only from its own request\'s prefix, never from the body after it', () => {
  for (const [why, msg, want] of [
    ['its own refusal', 'Discord POST /channels/950/threads -> 400 {"message":"x"}', 400],
    ['a server error whose body holds " -> 404 "', 'Discord POST /channels/950/threads -> 500 upstream said -> 404 x', 500],
    ['another request', 'Discord GET /channels/950 -> 403 {"message":"x"}', null],
    ['no answer at all', 'socket hang up', null],
  ]) assert.equal(answeredStatus(new Error(msg), 'POST', '/channels/950/threads'), want, why);
});

test('CT8: a Discord answer that is not JSON is reported by its request and status only, never its text', async () => {
  const f = fakeFetch([['GET', /\/channels\/950$/, () => new Response('<html>Needs QA</html>', { status: 200 })]]);
  await assert.rejects(discordClient('t', f).call('GET', '/channels/950'), (e) => e.message === 'Discord GET /channels/950 -> 200 (the answer was not JSON)');
});

// ---- The Accepted tag on the player's post -----------------------------------------

test('AT1: a post\'s status tags are listed in tag order, and the status it shows still prefers the wanted one', () => {
  const avail = [{ id: 'r', name: 'Retail' }, { id: 't', name: 'Triaged' }, { id: 'p', name: 'In progress' },
    { id: 'z', name: 'Closed' }, { id: 'acc', name: 'Accepted' }, { id: 'wf', name: "Won't fix" }];
  for (const [why, applied, want] of [
    ['Triaged alone, beside other tags', ['r', 'acc', 't'], ['Triaged']],
    ['two status tags, in tag order', ['z', 'r', 't'], ['Closed', 'Triaged']],
    ['no status tag', ['r', 'acc'], []],
    ['a checklist-only status tag is not a player status', ['wf', 't'], ['Triaged']],
  ]) assert.deepEqual(C.shownStatuses(applied, avail), want, why);
  assert.equal(C.currentStatus(['z', 't'], avail, 'Triaged'), 'Triaged', 'the wanted status shows wherever it sits');
});

test('AT4: only status tags that are Triaged and nothing else count as Triaged alone', () => {
  for (const [statuses, want] of [
    [['Triaged'], true], [['Triaged', 'Closed'], false], [['Closed', 'Triaged'], false], [['In progress'], false], [[], false],
  ]) assert.equal(C.triagedAlone(statuses), want, statuses.join(', ') || '(none)');
});

test('AT2: a status move with `accepted` places or removes Accepted in its one write, in a free slot only; the Worker\'s move plans as before', async () => {
  const forum = { id: '900', available_tags: [{ id: 'r', name: 'Retail' }, { id: 'x', name: 'Staff note' }, { id: 'a', name: 'A' },
    { id: 'b2', name: 'B' }, { id: 't', name: 'Triaged' }, { id: 'p', name: 'In progress' }, { id: 'acc', name: 'Accepted' }] };
  const noAccepted = { ...forum, available_tags: forum.available_tags.filter((t) => t.id !== 'acc') };
  const post = (tags, archived = false) => ({ id: '700', parent_id: '900', applied_tags: tags, thread_metadata: { archived } });
  const move = (status, accepted) => (d) => d.setStatus('700', status, undefined, { accepted });
  for (const [why, reads, write, patches, out, forumNow = forum] of [
    ['a move places Accepted', [post(['r', 't'])], move('In progress', true), [{ applied_tags: ['r', 'p', 'acc'] }], { noRoom: false }],
    ['an archived post\'s move reopens it with Accepted in that write', [post(['r', 't'], true)], move('In progress', true),
      [{ applied_tags: ['r', 'p', 'acc'], archived: false }], {}],
    ['a move removes Accepted', [post(['acc', 'r', 't'])], move('In progress', false), [{ applied_tags: ['r', 'p'] }], {}],
    ['no free slot: the status moves, Accepted waits, nothing is dropped', [post(['r', 'x', 'a', 'b2', 't'])], move('In progress', true),
      [{ applied_tags: ['r', 'x', 'a', 'b2', 'p'] }], { noRoom: true }],
    ['the status already shows, no Accepted tag and Accepted wanted: no write', [post(['r', 't'])], move('Triaged', true), [], {}],
    ['the same on an archived post', [post(['r', 't'], true)], move('Triaged', true), [], {}],
    ['the status already shows, an Accepted tag and Accepted not wanted: no write', [post(['r', 't', 'acc'])], move('Triaged', false), [], {}],
    ['the same on an archived post', [post(['r', 't', 'acc'], true)], move('Triaged', false), [], {}],
    ['a tag added between the reads is kept beside Accepted', [post(['r', 't']), post(['r', 'x', 't'])], move('In progress', true),
      [{ applied_tags: ['r', 'x', 'p', 'acc'] }], {}],
    ['the forum lacks the status tag: no write', [post(['r', 't'])], move('Shipped', true), [], { skipped: true }],
    ['no Accepted tag in the forum, Accepted wanted: the status moves and noAccepted is reported', [post(['r', 't'])], move('In progress', true),
      [{ applied_tags: ['r', 'p'] }], { noAccepted: true }, noAccepted],
    ['no Accepted tag in the forum, Accepted not wanted: the status moves and nothing is reported', [post(['r', 't'])], move('In progress', false),
      [{ applied_tags: ['r', 'p'] }], { noAccepted: false }, noAccepted],
    ['the Worker\'s move (no `accepted`): Accepted is one more tag, and the status goes last', [post(['acc', 'r'])],
      (d) => d.setStatus('700', 'Triaged'), [{ applied_tags: ['acc', 'r', 't'] }], {}],
  ]) {
    const queue = [...reads];
    const f = fakeFetch([
      ['GET', /\/channels\/700$/, () => (queue.length > 1 ? queue.shift() : queue[0])],
      ['GET', /\/channels\/900$/, () => forumNow],
      ['PATCH', /\/channels\/700$/, () => ({})],
    ]);
    const r = await write(discordClient('t', f));
    assert.deepEqual(f.find('PATCH', /\/channels\/700$/).map((c) => c.body), patches, why);
    for (const [k, v] of Object.entries(out)) assert.equal(!!r[k], v, `${why}: ${k}`);
  }
});

test('AT3: the Accepted-only write changes only Accepted, and only on an active post showing Triaged alone at both reads', async () => {
  const forum = { id: '900', available_tags: [{ id: 'r', name: 'Retail' }, { id: 'x', name: 'Staff note' }, { id: 'a', name: 'A' },
    { id: 'b2', name: 'B' }, { id: 't', name: 'Triaged' }, { id: 'p', name: 'In progress' }, { id: 'z', name: 'Closed' }, { id: 'acc', name: 'Accepted' }] };
  const noAccepted = { ...forum, available_tags: forum.available_tags.filter((t) => t.id !== 'acc') };
  const twice = { ...forum, available_tags: [...forum.available_tags, { id: 'acc2', name: 'ACCEPTED' }] };
  const post = (tags, archived = false) => ({ id: '700', parent_id: '900', applied_tags: tags, thread_metadata: { archived } });
  for (const [why, reads, want, patches, out, forumNow = forum] of [
    ['a second, differently cased Accepted tag already shows: no write', [post(['r', 't', 'acc2'])], true, [], { wrote: false }, twice],
    ['Triaged alone: Accepted added, nothing else changed', [post(['r', 't'])], true, [{ applied_tags: ['r', 't', 'acc'] }], { wrote: true }],
    ['not wanted: Accepted removed', [post(['r', 'acc', 't'])], false, [{ applied_tags: ['r', 't'] }], { wrote: true }],
    ['a tag added between the reads is kept', [post(['r', 't']), post(['r', 'x', 't'])], true, [{ applied_tags: ['r', 'x', 't', 'acc'] }], { wrote: true }],
    ['In progress: refused', [post(['r', 'p'])], true, [], { refused: true }],
    ['Triaged beside Closed: refused', [post(['r', 't', 'z'])], true, [], { refused: true }],
    ['Closed beside Triaged: refused', [post(['z', 'r', 't'])], true, [], { refused: true }],
    ['no status tag: refused', [post(['r'])], true, [], { refused: true }],
    ['Triaged at the first read, In progress at the fresh read: no write', [post(['r', 't']), post(['r', 'p'])], true, [], { raced: true }],
    ['Triaged alone at the first read, Triaged beside Closed at the fresh read: no write', [post(['r', 't']), post(['r', 't', 'z'])], true, [], { raced: true }],
    ['archived at the first read', [post(['r', 't'], true)], true, [], { archived: true }],
    ['archived at the fresh read', [post(['r', 't']), post(['r', 't'], true)], true, [], { archived: true }],
    ['five tags: no room', [post(['r', 'x', 'a', 'b2', 't'])], true, [], { noRoom: true, wrote: false }],
    ['no Accepted tag in the forum', [post(['r', 't'])], true, [], { noAccepted: true, wrote: false }, noAccepted],
  ]) {
    const queue = [...reads];
    const f = fakeFetch([
      ['GET', /\/channels\/700$/, () => (queue.length > 1 ? queue.shift() : queue[0])],
      ['GET', /\/channels\/900$/, () => forumNow],
      ['PATCH', /\/channels\/700$/, () => ({})],
    ]);
    const r = await discordClient('t', f).fixAccepted('700', want);
    assert.deepEqual(f.find('PATCH', /\/channels\/700$/).map((c) => c.body), patches, why);
    for (const [k, v] of Object.entries(out)) assert.equal(r[k], v, `${why}: ${k}`);
  }
});

test('a failed call\'s status is the one its client kept, never one its answer quotes', () => {
  const kept = (side, status) => Object.assign(new Error(`X GET /x -> ${status} upstream said -> 404 x`), { [side]: { method: 'GET', path: '/x', status } });
  assert.equal(C.statusOf(kept('discord', 500)), 500);
  assert.equal(C.statusOf(kept('github', 502)), 502);
  assert.equal(C.statusOf(new Error('out of time before GET https://x/ -> 404 ')), undefined);
});

test('a message read takes only its own 404 for a deleted message', async () => {
  for (const [why, answer, deleted] of [
    ['the message was deleted', () => new Response('{"message":"Unknown Message"}', { status: 404 }), true],
    ['a server error whose answer quotes " -> 404 "', () => new Response('upstream said -> 404 x', { status: 500 }), false],
  ]) {
    const f = fakeFetch([['GET', /\/channels\/700\/messages\/800$/, answer], ['GET', /\/channels\/700$/, () => ({ id: '700' })]]);
    const read = discordClient('t', f).readMessage('700', '800');
    if (deleted) assert.deepEqual(await read, { message: null, channel: { id: '700' } }, why);
    else await assert.rejects(read, { message: /^Discord GET \/channels\/700\/messages\/800 -> 500 / }, why);
  }
});

test('REPO_TAGS reads as tag name to key in any letter case, and a post\'s tags give a key only when they give one', () => {
  const tags = C.parseRepoTags('{"UI":"UI","Kitn":" ke ","Core":"KE"}');
  assert.deepEqual(tags, { ui: 'UI', kitn: 'KE', core: 'KE' }, 'keys read as normRepoKey reads them: trimmed, in upper case');
  assert.deepEqual(C.parseRepoTags('{"Triaged":"UI","accepted":"UI","UI":"UI"}'), { ui: 'UI' }, 'a status or Accepted tag is never a repo tag');
  for (const [why, names, want] of [
    ['one repo tag', ['Bug', 'ui'], 'UI'],
    ['two tags naming one key', ['KITN', 'core'], 'KE'],
    ['two tags naming two keys', ['UI', 'Kitn'], null],
    ['no repo tag', ['Bug'], null],
  ]) assert.equal(C.repoFromTags(names, tags), want, why);
  assert.deepEqual(C.plainTags(['Bug', 'UI', 'kitn', 'Retail'], tags), ['Bug', 'Retail'], 'repo tags left out in any letter case');
  assert.deepEqual(C.parseRepoTags('{"UI":"ONE","ui":"TWO","Kitn":"KE"}'), { kitn: 'KE' }, 'one name in two letter cases for two keys gives neither');
  for (const raw of ['', '  ', '{"UI":', '["UI"]', '{"UI":1}', 'null', undefined]) assert.deepEqual(C.parseRepoTags(raw), {}, String(typeof raw));
});

test('a webhook name drops discord and clyde until none is left, keeps other marks, and cuts at 80 units without splitting a character', () => {
  for (const [why, name, username, want] of [
    ['discord removed', 'Discord Fan', 'u', 'Fan'],
    ['Clyde removed, so the username stands in', 'Clyde', 'pat', 'pat'],
    ['a removal that joins the word again', 'Xdisdiscordcord', 'u', 'X'],
    ['the other word joined again', 'Ydiscclydeord', 'u', 'Y'],
    ['@, # and : kept', '@pat #1: hi', 'u', '@pat #1: hi'],
    ['81 units cut to 80', 'a'.repeat(81), 'u', 'a'.repeat(80)],
    ['an emoji across unit 80 not split', `${'a'.repeat(79)}\u{1F600}`, 'u', 'a'.repeat(79)],
    ['one line', 'two\nlines', 'u', 'two lines'],
    ['nothing left anywhere', 'discord', 'clyde', 'Player'],
  ]) assert.equal(C.webhookName(name, username), want, why);
});

test('an avatar address is the server avatar, else the user avatar, else the default by id or old discriminator', () => {
  const id = String((2n ** 40n + 5n) << 22n);
  for (const [why, user, member, want] of [
    ['a server avatar', { id: '42', avatar: 'u1', discriminator: '0' }, { avatar: 'm1' }, 'https://cdn.discordapp.com/guilds/1/users/42/avatars/m1.png'],
    ['a user avatar', { id: '42', avatar: 'u1', discriminator: '0' }, null, 'https://cdn.discordapp.com/avatars/42/u1.png'],
    // A 32-bit shift of this id gives index 5.
    ['the default for an id past 2^53', { id, avatar: null, discriminator: '0' }, {}, 'https://cdn.discordapp.com/embed/avatars/3.png'],
    ['the default for an old discriminator', { id, avatar: null, discriminator: '1234' }, null, 'https://cdn.discordapp.com/embed/avatars/4.png'],
  ]) assert.equal(C.avatarUrl({ guildId: '1', user, member }), want, why);
});

test('an issue filed from a moved post\'s copy ends with the copy footer, which every footer reader reads', () => {
  const filed = C.buildBody({ content: 'hi', reporter: { name: 'Pat', id: '42' }, sender: null, threadUrl: 'u', threadId: '990', messageId: '990', copied: true });
  assert.match(filed, /\n\n<!-- discord-copy -->\n<!-- discord-message: 990 -->\n<!-- discord-thread: 990 reporter: 42 -->$/);
  assert.deepEqual(C.parseMarker(filed), { threadId: '990', reporterId: '42' });
  assert.deepEqual(C.parseFiledMessage(filed), { id: '990', copy: true });
});

test('a filed move rewrites only the bot\'s footer and adds a Moved to line where it stood', () => {
  const MOD = { name: 'moddy', username: 'moddy', id: '5' };
  const MOVE = 'Moved to [the new post](https://discord.com/channels/1/990) by [moddy](https://discord.com/users/5) (`moddy`).';
  const FOOT = ['<!-- discord-copy -->', '<!-- discord-message: 990 -->'];
  const moved = (body, over = {}) => C.movedBody(body, { guildId: '1', newId: '990', mover: MOD, ...over });
  const filed = C.buildBody({ content: 'see https://discord.com/channels/1/700', reporter: { name: 'Pat', id: '42' }, sender: MOD,
    threadUrl: 'https://discord.com/channels/1/700', attachments: [{}], threadId: '700', messageId: '700' });
  const above = filed.split('\n').slice(0, -2);
  const once = moved(filed);
  assert.equal(once, [...above, MOVE, ...FOOT, '<!-- discord-thread: 990 reporter: 42 -->'].join('\n'), 'every line above the footer kept, the old links included');
  assert.deepEqual(C.parseMarker(once), { threadId: '990', reporterId: '42' });
  assert.deepEqual(C.parseFiledMessage(once), { id: '990', copy: true });
  const MOVE2 = MOVE.replace('990', '991');
  assert.equal(moved(once, { newId: '991' }), [...above, MOVE, '', MOVE2, '<!-- discord-copy -->', '<!-- discord-message: 991 -->', '<!-- discord-thread: 991 reporter: 42 -->'].join('\n'),
    'a second move: the first line stays, the copy footer is replaced');
  const footer = (id, rep) => [`<!-- discord-message: ${id} -->`, `<!-- discord-thread: ${id} reporter: ${rep} -->`].join('\n');
  const newFooter = (rep) => [...FOOT, `<!-- discord-thread: 990 reporter: ${rep} -->`].join('\n');
  for (const [why, below] of [
    ['a maintainer note', 'Note from staff.'],
    ['an open fence left unclosed', '```\nstack trace'],
    ['a fence opened two spaces in, closed at column one', '  ```\ncode\n```'],
    ['an HTML comment left unclosed', '<!-- staff note'],
  ]) {
    const body = `> report\n\n${footer('800', 'unknown')}\n${below}`;
    assert.equal(moved(body), `> report\n\n${MOVE}\n${newFooter('unknown')}\n${below}`, why);
  }
  assert.equal(moved(`> report\r\n\r\n${footer('800', '42').replace(/\n/g, '\r\n')}\r\nNote\r\nline two`),
    moved(`> report\n\n${footer('800', '42')}\nNote\nline two`), 'a CRLF body reads as its LF form');
  assert.equal(moved('> report\n<!-- discord-thread: 700 reporter: 42 -->'), `> report\n\n${MOVE}\n${newFooter('42')}`, 'an older footer, the marker alone');
  assert.equal(moved('Hand-written body'), `Hand-written body\n\n${MOVE}\n${newFooter('unknown')}`, 'no marker: the footer added at the end');
});

test('the filed message is read from the last marker\'s footer, wherever it stands', () => {
  assert.deepEqual(C.parseFiledMessage('> r\n\n<!-- discord-message: 800 -->\n<!-- discord-thread: 700 reporter: 42 -->\nA note below.'), { id: '800', copy: false });
  const moved = C.movedBody('> r\n\n<!-- discord-message: 800 -->\n<!-- discord-thread: 700 reporter: 42 -->\nA note below.', { guildId: '1', newId: '990', mover: { name: 'm' } });
  assert.deepEqual(C.parseFiledMessage(moved), { id: '990', copy: true });
  // A report that copies bot lines above its own footer.
  const quote = 'Copied from an older report:\n<!-- discord-message: 111 -->\n<!-- discord-thread: 222 reporter: 9 -->\n\n';
  const quoted = `${quote}<!-- discord-message: 800 -->\n<!-- discord-thread: 700 reporter: 42 -->`;
  assert.deepEqual(C.parseFiledMessage(quoted), { id: '800', copy: false });
  assert.ok(C.movedBody(quoted, { guildId: '1', newId: '990', mover: { name: 'm' } }).startsWith(quote), 'the quoted lines stay as written');
});

test('a moved issue\'s title gets the new key, client and type, and keeps its module and text as written', () => {
  const t = '[KE] [Retail] [Bug] [iOS] Bags overlap';
  for (const [why, title, parts, want] of [
    ['the three prefix groups', t, { repoKey: 'UI', client: 'All', type: 'Feature' }, '[UI] [All] [Feature] [iOS] Bags overlap'],
    ['a null type keeps the title\'s', t, { repoKey: 'UI', client: 'All', type: null }, '[UI] [All] [Bug] [iOS] Bags overlap'],
    ['a hand title', 'Bags overlap', { repoKey: 'UI', client: 'All', type: 'Bug' }, null],
  ]) assert.equal(C.movedTitle(title, parts), want, why);
  assert.deepEqual(C.splitTitle(t), { repoKey: 'KE', client: 'Retail', type: 'Bug', rest: '[iOS] Bags overlap' });
});

test('a moved post keeps the tags the new forum has and gets its client tags, five at most in order', () => {
  const FROM = [
    { id: 'f-retail', name: 'Retail' }, { id: 'f-bug', name: 'Bug' }, { id: 'f-tri', name: 'Triaged' }, { id: 'f-acc', name: 'Accepted' },
    { id: 'f-mage', name: 'Mage' }, { id: 'f-one', name: 'ONE' }, { id: 'f-staff', name: 'Staff note' }, { id: 'f-extra', name: 'Extra' },
    { id: 'f-retail2', name: 'Retail UI' }, { id: 'f-prog', name: 'In progress' }, { id: 'f-fixed', name: 'Fixed, next update' },
  ];
  const TO = [
    { id: 't-retail', name: 'retail' }, { id: 't-forever', name: 'Forever' }, { id: 't-bug', name: 'Bug' }, { id: 't-tri', name: 'TRIAGED' },
    { id: 't-acc', name: 'Accepted' }, { id: 't-staff', name: 'Staff note' }, { id: 't-extra', name: 'Extra' }, { id: 't-one', name: 'ONE' }, { id: 't-two', name: 'TWO' },
    { id: 't-two2', name: 'Two alias' }, { id: 't-retail2', name: 'Retail UI' }, { id: 't-prog', name: 'In progress' }, { id: 't-fixed', name: 'Fixed, next update' },
  ];
  const base = { from: FROM, to: TO, client: 'Retail', fixedClient: 'Retail', fixedType: null, repoTags: C.parseRepoTags('{"ONE":"ONE","TWO":"TWO"}') };
  const BOTH_FROM = [...FROM, { id: 'f-both', name: 'Retail Forever' }];
  const BOTH_TO = [...TO, { id: 't-both', name: 'Retail Forever' }];
  for (const [why, applied, over, want] of [
    ['a name kept in any letter case', ['f-tri', 'f-staff'], {}, ['t-tri', 't-staff']],
    ['a name the new forum lacks dropped', ['f-mage', 'f-staff'], {}, ['t-staff']],
    ['no client of its own: its Retail tag added', ['f-staff'], { fixedClient: null }, ['t-retail', 't-staff']],
    ['no client of its own: Forever, the Retail tag dropped', ['f-retail'], { fixedClient: null, client: 'Forever' }, ['t-forever']],
    ['no client of its own: All gives both', [], { fixedClient: null, client: 'All' }, ['t-retail', 't-forever']],
    ['a client of its own: an agreeing client tag kept', ['f-retail'], {}, ['t-retail']],
    ['a client of its own: a disagreeing client tag dropped', ['f-retail', 'f-staff'], { client: 'Forever', fixedClient: 'Forever' }, ['t-staff']],
    ['a type of its own: a disagreeing type tag dropped', ['f-bug', 'f-staff'], { fixedType: 'Feature' }, ['t-staff']],
    ['no type of its own: the type tag kept', ['f-bug'], {}, ['t-bug']],
    ['a repo tag the new forum has is kept, by name like any tag', ['f-one', 'f-staff'], {}, ['t-one', 't-staff']],
    ['six cut to five: status, repo, client, Accepted, then the post\'s order', ['f-staff', 'f-extra', 'f-acc', 'f-tri', 'f-one'], { fixedClient: null },
      ['t-tri', 't-one', 't-retail', 't-acc', 't-staff']],
    ['a status tag named in REPO_TAGS stays a status tag', ['f-tri', 'f-one'], { repoTags: C.parseRepoTags('{"Triaged":"TWO","ONE":"ONE"}') }, ['t-tri', 't-one']],
    ['All: a second Retail alias ranks with the rest, so Forever stays', ['f-retail', 'f-retail2', 'f-staff', 'f-acc', 'f-tri'], { fixedClient: null, client: 'All' },
      ['t-tri', 't-retail', 't-forever', 't-acc', 't-retail2']],
    ['three status tags: the first ranks first, the others with the rest, so both clients, the repo and Accepted stay',
      ['f-tri', 'f-prog', 'f-fixed', 'f-acc', 'f-one'], { fixedClient: null, client: 'All' },
      ['t-tri', 't-one', 't-retail', 't-forever', 't-acc']],
    ['a client-named tag that REPO_TAGS maps is not the client tag', [], {
      to: [{ id: 'x-ui', name: 'Retail UI' }, { id: 'x-retail', name: 'Retail' }],
      fixedClient: null, repoTags: C.parseRepoTags('{"Retail UI":"ONE"}'),
    }, ['x-retail']],
    ['a client tag that also names a type the forum refuses is not added', [], {
      to: [{ id: 'x-rbug', name: 'Retail Bug' }, { id: 'x-retail', name: 'Retail' }], fixedClient: null, fixedType: 'Feature',
    }, ['x-retail']],
    // With no type of the forum's own, the post's type is the one its kept
    // tags name, and an added client tag names that type or none.
    ['no type of its own: a Feature post gets Retail, not the Retail Bug listed first', ['f-feat'], {
      from: [...FROM, { id: 'f-feat', name: 'Feature' }],
      to: [{ id: 'u-feat', name: 'Feature' }, { id: 'u-rbug', name: 'Retail Bug' }, { id: 'u-retail', name: 'Retail' }], fixedClient: null,
    }, ['u-retail', 'u-feat']],
    ['no type known: a client tag that names one is not added', ['f-staff'], {
      to: [{ id: 's-rbug', name: 'Retail Bug' }, { id: 's-staff', name: 'Staff note' }], fixedClient: null,
    }, ['s-staff']],
    ['All: a combined tag that names another type is not added, the single ones are', ['f-feat'], {
      from: [...FROM, { id: 'f-feat', name: 'Feature' }],
      to: [{ id: 'q-feat', name: 'Feature' }, { id: 'q-both', name: 'Retail Forever Bug' }, { id: 'q-retail', name: 'Retail' }, { id: 'q-forever', name: 'Forever' }],
      fixedClient: null, client: 'All',
    }, ['q-retail', 'q-forever', 'q-feat']],
    ['All: a combined client tag covers both clients, so Accepted stays', ['f-tri', 'f-one', 'f-both', 'f-acc', 'f-staff'], { from: BOTH_FROM, to: BOTH_TO, fixedClient: null, client: 'All' },
      ['t-tri', 't-one', 't-both', 't-acc', 't-staff']],
    ['All: the combined tag added when the forum has it', [], {
      to: [{ id: 'y-both', name: 'Retail Forever' }, { id: 'y-staff', name: 'Staff note' }], fixedClient: null, client: 'All',
    }, ['y-both']],
    ['a post read with no tag list keeps none', undefined, { fixedClient: null }, ['t-retail']],
    ['All: one client kept, the other only in a combined tag: that tag added', ['f-retail'], {
      to: [{ id: 'z-retail', name: 'Retail' }, { id: 'z-both', name: 'Retail Forever' }], fixedClient: null, client: 'All',
    }, ['z-both', 'z-retail']],
    // The combined tag counts first, so the kept Retail ranks with the rest
    // and Accepted keeps its place in the five.
    ['All: a kept Retail tag and an added combined one: Accepted stays', ['f-tri', 'f-one', 'f-two', 'f-retail', 'f-acc'], {
      from: [...FROM, { id: 'f-two', name: 'TWO' }],
      to: [{ id: 'w-tri', name: 'Triaged' }, { id: 'w-one', name: 'ONE' }, { id: 'w-two', name: 'TWO' }, { id: 'w-retail', name: 'Retail' }, { id: 'w-acc', name: 'Accepted' }, { id: 'w-both', name: 'Retail Forever' }],
      fixedClient: null, client: 'All',
    }, ['w-tri', 'w-one', 'w-two', 'w-both', 'w-acc']],
    // A forum with both a Forever tag and a combined one: the combined tag is
    // added, so the status, three repos and both clients fit in five.
    ['All: the combined tag is preferred to a single one', ['f-tri', 'f-one', 'f-two', 'f-three', 'f-retail'], {
      from: [...FROM, { id: 'f-two', name: 'TWO' }, { id: 'f-three', name: 'THREE' }],
      to: [{ id: 'v-tri', name: 'Triaged' }, { id: 'v-one', name: 'ONE' }, { id: 'v-two', name: 'TWO' }, { id: 'v-three', name: 'THREE' },
        { id: 'v-retail', name: 'Retail' }, { id: 'v-forever', name: 'Forever' }, { id: 'v-both', name: 'Retail Forever' }],
      fixedClient: null, client: 'All', repoTags: C.parseRepoTags('{"ONE":"ONE","TWO":"TWO","THREE":"THREE"}'),
    }, ['v-tri', 'v-one', 'v-two', 'v-three', 'v-both']],
    ['Retail: a combined tag is not added for one client', [], {
      to: [{ id: 'v-both', name: 'Retail Forever' }, { id: 'v-staff', name: 'Staff note' }], fixedClient: null, client: 'Retail',
    }, []],
    ['a repo tag whose name reads as a type is kept in a forum of another type', ['f-rbug'], {
      from: [...FROM, { id: 'f-rbug', name: 'Retail UI Bug' }], to: [{ id: 'x-rbug', name: 'Retail UI Bug' }], fixedType: 'Feature', repoTags: C.parseRepoTags('{"Retail UI Bug":"ONE"}'),
    }, ['x-rbug']],
    ['three tags of one repo: only the first ranks as the repo, so both clients and Accepted stay', ['f-tri', 'f-one', 'f-one2', 'f-one3', 'f-acc'], {
      from: [...FROM, { id: 'f-one2', name: 'One alias' }, { id: 'f-one3', name: 'One third' }],
      to: [...TO, { id: 't-one2', name: 'One alias' }, { id: 't-one3', name: 'One third' }],
      fixedClient: null, client: 'All', repoTags: C.parseRepoTags('{"ONE":"ONE","One alias":"ONE","One third":"ONE"}'),
    }, ['t-tri', 't-one', 't-retail', 't-forever', 't-acc']],
    // A filed move passes the issue's key: its repo tag follows the issue.
    ['with repoKey, a repo tag of another key dropped, the key tag added', ['f-one', 'f-staff'], { repoKey: 'TWO' }, ['t-two', 't-staff']],
    ['with repoKey, the key tag kept, not doubled', ['f-one', 'f-staff'], { repoKey: 'ONE' }, ['t-one', 't-staff']],
    ['with repoKey, no tag for the key adds none', ['f-one', 'f-staff'], { repoKey: 'THREE' }, ['t-staff']],
  ]) assert.deepEqual(C.movedTags({ ...base, ...over, applied }), want, why);
});

test('a moved post\'s card mentions the mover, and the moved messages link both posts and ping only the reporter', () => {
  const post = { guildId: '1', forumId: '900', postId: '700' };
  assert.equal(C.queueCard({ ...post, author: { name: 'k', username: 'kira', id: '42' }, moved: '<@8>' }).content, '**New post in <#900>:** <#700>\nby <@42> (`kira`)\nMoved by <@8>');
  assert.equal(C.MESSAGES.movedHere({ from: 'https://discord.com/channels/1/700', by: '<@8>', reporter: { name: 'Pat', id: '42' } }),
    'Moved here from https://discord.com/channels/1/700 by <@8>. First posted by <@42>.');
  assert.equal(C.MESSAGES.movedHere({ from: 'L', by: '<@8>', reporter: { name: 'Pat', id: '42' }, tracked: { key: 'KE', number: 12 } }),
    'Moved here from L by <@8>. First posted by <@42>. Tracked as KE #12.');
  assert.equal(C.MESSAGES.movedHere({ from: 'L', by: '<@8>', reporter: { name: '**Hook**' }, left: 2, cut: true }),
    'Moved here from L by <@8>. First posted by \\*\\*Hook\\*\\*. 2 file(s) could not be copied (too large, or not downloaded); they are on the original post. The first message was too long to copy whole; the full text is on the original post.');
  assert.equal(C.MESSAGES.movedTo({ to: 'https://discord.com/channels/1/990', by: '<@8>' }), 'This post moved to https://discord.com/channels/1/990 (moved by <@8>).');
});

test('a staff member shows as their mention; a name an older record saved stays text', () => {
  assert.equal(C.staffRef({ id: '5', username: 'moddy' }), '<@5>');
  for (const [why, by, want] of [
    ['a mention', '<@5>', '<@5>'],
    ['an older record\'s name', 'Mod_x', 'Mod\\_x'],
    ['a name that only starts like a mention', '<@5> hi', '\\<@5\\> hi'],
  ]) assert.equal(C.shownStaff(by), want, why);
  const card = C.filedCard({ guildId: '1', postId: '700', head: 'h', key: 'KE', number: 3, by: '<@5>' });
  assert.equal(card.content, '~~h~~\n**Filed as KE #3** by <@5>');
  assert.deepEqual(card.allowed_mentions, { parse: [] }, 'shown, never pinged');
});

test('a forum\'s webhook is the bot\'s own when listed, else a new one named Post mover', async () => {
  for (const [why, list, made] of [
    ['its own, after another app\'s and a non-incoming one', [{ id: '60', type: 1, application_id: 'other', token: 'x' }, { id: '61', type: 2, application_id: 'app' }, { id: '62', type: 1, application_id: 'app', token: 't' }], false],
    ['none of its own', [{ id: '60', type: 1, application_id: 'other', token: 'x' }], true],
  ]) {
    const f = fakeFetch([['GET', /\/channels\/901\/webhooks$/, () => list], ['POST', /\/channels\/901\/webhooks$/, () => ({ id: '63', token: 'n' })]]);
    const hook = await discordClient('bot', f).forumWebhook('901', 'app');
    assert.equal(hook.id, made ? '63' : '62', why);
    assert.deepEqual(f.find('POST', /webhooks$/).map((c) => c.body), made ? [{ name: 'Post mover' }] : [], why);
  }
});

test('a webhook post is multipart with no bot token, and its errors never show the webhook token', async () => {
  const seen = [];
  const ok = async (url, init) => { seen.push({ url, init }); return new Response(JSON.stringify({ id: '990', channel_id: '990' }), { status: 200 }); };
  const files = [{ name: 'a.png', blob: new Blob(['x']) }];
  const msg = await discordClient('bot', ok).executeWebhook({ id: '61', token: 'secret-token' }, { content: 'hi' }, files);
  assert.equal(msg.channel_id, '990');
  assert.equal(seen[0].url, 'https://discord.com/api/v10/webhooks/61/secret-token?wait=true');
  assert.equal(seen[0].init.headers.Authorization, undefined);
  assert.deepEqual(JSON.parse(seen[0].init.body.get('payload_json')), { content: 'hi' });
  assert.equal(seen[0].init.body.get('files[0]').name, 'a.png');
  // The recording fake reads the same body.
  const f = fakeFetch([['POST', /\/webhooks\/61\/wtok\?wait=true$/, () => ({ id: '990', channel_id: '990' })]]);
  await discordClient('bot', f).executeWebhook({ id: '61', token: 'wtok' }, { content: 'hi' }, files);
  assert.deepEqual(f.calls[0].body, { payload: { content: 'hi' }, files: ['a.png'] });
  for (const [why, fetchImpl, said] of [
    ['a refusal that echoes the address', async () => new Response('{"message":"no","url":"https://discord.com/api/v10/webhooks/61/secret-token"}', { status: 400 }),
      /^Discord POST \/webhooks\/61\/<token> -> 400 .*webhooks\/61\/<token>/],
    ['out of time before the call', C.timedFetch(ok, 1, Date.now() - 1), /^out of time before POST https:\/\/discord\.com\/api\/v10\/webhooks\/61\/<token>\?wait=true$/],
    ['a 2xx whose body cannot be read', async () => new Response('{"id":', { status: 200 }), /^Discord POST \/webhooks\/61\/<token> answered 200 with a body that could not be read$/],
  ]) {
    const e = await discordClient('bot', fetchImpl).executeWebhook({ id: '61', token: 'secret-token' }, {}, []).then(() => null, (x) => x);
    assert.ok(e, why);
    assert.match(e.message, said, why);
    assert.ok(!e.message.includes('secret-token'), why);
  }
});

test('isBotCopy: only a message the bot\'s own webhook posted', () => {
  for (const [why, m, want] of [
    ['the bot\'s copy', { webhook_id: '61', application_id: 'app' }, true],
    ['another app\'s webhook', { webhook_id: '61', application_id: 'other' }, false],
    ['a server\'s own webhook, owned by no app', { webhook_id: '61' }, false],
    ['a player\'s message', { author: { id: '42' } }, false],
    ['a deleted message', null, false],
  ]) assert.equal(C.isBotCopy(m, 'app'), want, why);
});
test('setStatus and fixAccepted report their forum read to onForum, as that read answered, before anything after it can fail, and only a forum', async () => {
  const base = [{ id: 'r', name: 'Retail' }, { id: 't', name: 'Triaged' }, { id: 'p', name: 'In progress' }];
  const first = () => ({ id: '900', type: 15, available_tags: base });
  const post = () => ({ id: '700', parent_id: '900', applied_tags: ['r', 't'] });
  const answer = (status) => () => new Response('{"message":"x","code":0}', { status });
  // fixAccepted writes only into a forum that has Accepted.
  const withAcc = (f) => () => ({ ...f(), available_tags: [...f().available_tags, { id: 'a', name: 'Accepted' }] });
  const setStatus = (status) => (d, onForum) => d.setStatus('700', status, undefined, { accepted: true, onForum });
  const fixAccepted = (d, onForum) => d.fixAccepted('700', true, { onForum });
  for (const [why, call, posts, forums, patch, seenWant, fails] of [
    ['setStatus: the post already shows the status', setStatus('Triaged'), [post], [first], () => ({}), [3], false],
    ['setStatus: a move', setStatus('In progress'), [post, post], [first], () => ({}), [3], false],
    ['setStatus: the post read again answers 404', setStatus('In progress'), [post, answer(404)], [first], () => ({}), [3], true],
    ['setStatus: the write is refused', setStatus('In progress'), [post, post], [first], answer(403), [3], true],
    ['fixAccepted: the Accepted write', fixAccepted, [post, post], [withAcc(first)], () => ({}), [4], false],
    ['fixAccepted: the post read again answers 404', fixAccepted, [post, answer(404)], [withAcc(first)], () => ({}), [4], true],
    // A channel that is no forum has no tags to name; a forum with none, or
    // whose answer leaves its list out, is reported with an empty list.
    ['setStatus: a parent that is no forum is not reported', setStatus('In progress'), [post], [() => ({ id: '900', type: 0 })], () => ({}), [], false],
    ['setStatus: a forum with no tags is reported', setStatus('In progress'), [post], [() => ({ id: '900', type: 15, available_tags: [] })], () => ({}), [0], false],
    ['setStatus: a forum answer with no tag list is reported as one with none', setStatus('In progress'), [post], [() => ({ id: '900', type: 15 })], () => ({}), [0], false],
  ]) {
    let postReads = 0;
    let forumReads = 0;
    const f = fakeFetch([
      ['GET', /\/channels\/700$/, () => posts[postReads++]()],
      ['GET', /\/channels\/900$/, () => forums[forumReads++]()],
      ['PATCH', /\/channels\/700$/, patch],
    ]);
    const seen = [];
    const run = call(discordClient('t', f), (id, tags) => seen.push([id, tags.length]));
    if (fails) await assert.rejects(run, why);
    else await run;
    assert.deepEqual(seen, seenWant.map((n) => ['900', n]), why);
  }
});

import { inlineCode } from '../src/core.js';

test('inlineCode shows its text as written: no backtick inside ends the span, and spaces at both ends stay', () => {
  for (const [s, out] of [['fix', '`fix`'], ['a`b', '``a`b``'], ['`a', '`` `a ``'], [' fix ', '`  fix  `'], [' fix', '` fix`']]) {
    assert.equal(inlineCode(s), out, JSON.stringify(s));
  }
});

test("a report comment round-trips its post and player, and only the issue author's count", () => {
  const body = C.reportComment({ number: 4, guildId: '1', postId: '701', player: { name: 'P@t *x*', username: 'pat', id: '42' }, by: { name: 'moddy', username: 'moddy', id: '5' } });
  assert.equal(body, 'Report 4 of this problem: [the Discord post](https://discord.com/channels/1/701), from [P@​t \\*x\\*](https://discord.com/users/42) (`pat`), added by [moddy](https://discord.com/users/5) (`moddy`).\n\n<!-- discord-report: 701 player: 42 -->');
  assert.deepEqual(C.parseReport(body), { postId: '701', playerId: '42' });
  const hook = C.reportComment({ number: 2, guildId: '1', postId: '702', player: { name: 'Hook' }, by: { name: 'm', id: '5' } });
  assert.deepEqual(C.parseReport(hook), { postId: '702', playerId: null });
  assert.equal(C.parseReport('no line here'), null);
  const issue = { user: { login: 'app[bot]' } };
  const comments = [
    { user: { login: 'app[bot]' }, body },
    { user: { login: 'someone' }, body: C.reportComment({ number: 3, guildId: '1', postId: '703', player: { id: '9' }, by: { id: '5' } }) },
    { user: { login: 'app[bot]' }, body: 'a note with no hidden line' },
    { body: hook },
  ];
  assert.deepEqual(C.ownReports(issue, comments), [{ postId: '701', playerId: '42' }]);
});
