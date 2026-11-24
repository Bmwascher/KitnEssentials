import { test } from 'node:test';
import assert from 'node:assert/strict';
import { discordClient } from '../src/discord.js';
import { describe, listForum, parseArgs } from '../scripts/trial-check.mjs';
import { fakeFetch, FORUM } from './fake-fetch.mjs';

const FORUM_CH = { ...FORUM, name: 'bugs', type: 15, guild_id: '1' };
const POST = {
  id: '50', name: 'Bars vanish', parent_id: '900', applied_tags: ['t-bug', 's-tri'],
  thread_metadata: { archived: false, locked: true },
};
const MSGS = [
  {
    timestamp: '2026-11-23T10:05:00.000Z', author: { username: 'bot', bot: true }, content: 'Filed as #12',
    embeds: [{ title: 'Status' }], components: [{ components: [{ label: 'Send to GitHub', disabled: true }] }],
  },
  { timestamp: '2026-11-23T10:00:00.000Z', author: { username: 'player' }, content: 'Bars\nvanish', embeds: [] },
];

const world = () => fakeFetch([
  ['GET', /\/channels\/50\/messages\?limit=5$/, () => MSGS],
  ['GET', /\/channels\/50$/, () => POST],
  ['GET', /\/channels\/900$/, () => FORUM_CH],
  ['GET', /\/guilds\/1\/threads\/active$/, () => ({ threads: [POST, { ...POST, id: '51', parent_id: '901' }] })],
  ['GET', /\/channels\/900\/threads\/archived\/public/, () => ({ threads: [{ ...POST, id: '49', applied_tags: [], thread_metadata: { archived: true } }], has_more: true })],
]);

test('a post shows its name, forum, tag names, state and messages oldest first', async () => {
  const fetch = world();
  const text = await describe(discordClient('t', fetch), '50', 5);
  assert.equal(text, [
    'Post 50: "Bars vanish"',
    '  forum: bugs (900)',
    '  tags: Bug, Triaged',
    '  archived: no, locked: yes',
    '  last 2 messages, oldest first:',
    '  2026-11-23 10:00:00 player: Bars vanish',
    '  2026-11-23 10:05:00 bot [bot]: Filed as #12',
    '    embed: Status',
    '    buttons: Send to GitHub (disabled)',
  ].join('\n'));
  assert.ok(fetch.calls.every((c) => c.method === 'GET'));
});

test('a forum lists only its own open posts, then archived ones', async () => {
  const text = await listForum(discordClient('t', world()), '900');
  assert.equal(text, [
    'Forum bugs (900): 1 open, 1 newest archived',
    '  50 "Bars vanish" [Bug, Triaged]',
    '  49 "Bars vanish" [no tags] archived',
    '  older archived posts are not listed',
  ].join('\n'));
});

test('arguments are ids and options with their values, and anything else is refused', () => {
  assert.deepEqual(parseArgs(['50', '--limit', '3', '51']), { ids: ['50', '51'], limit: 3, forum: null });
  assert.deepEqual(parseArgs(['--forum', '900']), { ids: [], limit: 10, forum: '900' });
  for (const bad of [[], ['--limt', '5'], ['--forum'], ['--limit', '2.5', '50'], ['--limit', '0', '50'], ['--forum', 'abc'], ['--forum', '900', '--forum', '901']]) {
    assert.equal(parseArgs(bad), null, bad.join(' '));
  }
});
