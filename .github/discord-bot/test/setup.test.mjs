import test from 'node:test';
import assert from 'node:assert/strict';
import { configProblems, channelPermissions, fitLines } from '../src/setup.js';
import { PERMS, postLines, taken } from '../src/core.js';

// Discord's own message limit, which every message sent must fit.
const DISCORD_MAX = 2000;
const KV = { get: async () => null, put: async () => {} };
const CLEAN = { REPOS: '{"KE":"me/one"}', FORUMS: '{"900":{}}', GUILD_ID: '1', MOD_CHANNEL_ID: '555', STATE: KV };

test('ST1: configProblems names each broken setting as the code reads it, in one line, and nothing for a clean config', () => {
  assert.deepEqual(configProblems(CLEAN), []);
  assert.deepEqual(configProblems({ ...CLEAN, STATE: undefined }, { bindings: false }), [], 'bindings off skips STATE');
  assert.deepEqual(configProblems({ ...CLEAN, FORUMS: '', FORUM_CHANNEL_IDS: '900' }), [], 'the older FORUM_CHANNEL_IDS still counts');
  assert.deepEqual(configProblems({ ...CLEAN, STALE_DAYS: '  ', TEMPLATES: ' ', CHECKLIST_FORUM_ID: '  ' }), [], 'settings read as unset when blank stay unset');
  assert.deepEqual(configProblems({ ...CLEAN, CHECKLIST_FORUM_ID: ' 950 ' }), [], 'the checklist id is read trimmed, as the code reads it');
  assert.deepEqual(configProblems({ ...CLEAN, REPOS: '{"AB CD":"me/one"}' }), [], 'an inner space is a key the form can choose');
  for (const [why, over, re] of [
    ['no REPOS', { REPOS: '' }, /^REPOS is not set or not valid JSON/],
    ['a REPOS entry that is not owner/repo', { REPOS: '{"KE":"one"}' }, /^REPOS entry KE is not owner\/repo\.$/],
    ['a REPOS key the form can never choose', { REPOS: '{"ke":"me/one"}' }, /^REPOS key "ke" can never be chosen in the form/],
    ['a REPOS key longer than the form field', { REPOS: '{"ELEVENCHARS":"me/one"}' }, /^REPOS key "ELEVENCHARS" can never be chosen in the form/],
    ['a short upper-case REPOS key holding a line break, which a one-line field cannot hold', { REPOS: '{"K\\nE":"me/one"}' }, /^REPOS key "K\sE" can never be chosen in the form/],
    ['a FORUMS value with no text form, which the reader would throw on', { FORUMS: '{"900":{"template":{"toString":null}}}' }, /^FORUMS entry 900: "client", "type" and "template" must each be text/],
    ['a REPOS entry past GitHub name limits', { REPOS: `{"KE":"me/${'r'.repeat(101)}"}` }, /^REPOS entry KE is not owner\/repo\.$/],
    ['an id longer than any Discord id', { MOD_CHANNEL_ID: '1'.repeat(21) }, /^MOD_CHANNEL_ID is not a channel id/],
    ['a STATE that is not a KV namespace', { STATE: {} }, /^The STATE KV namespace is not bound/],
    ['two repos and no LOCK_REPO', { REPOS: '{"A":"me/one","B":"me/two"}' }, /^LOCK_REPO is empty/],
    ['a LOCK_REPO that is not owner/repo', { LOCK_REPO: 'me/one ' }, /^LOCK_REPO is not owner\/repo/],
    ['a LOCK_REPO of spaces, which the filing would use', { LOCK_REPO: '  ' }, /^LOCK_REPO is not owner\/repo/],
    ['no FORUMS', { FORUMS: '' }, /^FORUMS is empty/],
    ['broken FORUMS JSON', { FORUMS: '{"900":' }, /^FORUMS is not valid JSON/],
    ['a FORUMS key that is no id', { FORUMS: '{"help":{}}' }, /^FORUMS key help is not a channel id\.$/],
    ['a FORUM_CHANNEL_IDS entry that is no id', { FORUMS: '', FORUM_CHANNEL_IDS: '900,help' }, /^FORUM_CHANNEL_IDS entry help is not a channel id\.$/],
    ['a template that is no message link', { FORUMS: '{"900":{"template":"https://discord.com/channels/1/2"}}' }, /^FORUMS entry 900: its "template" is not a message link/],
    ['FORUMS naming only the checklist forum', { FORUMS: '{"950":{}}', CHECKLIST_FORUM_ID: '950' }, /^FORUMS names no player forum/],
    ['FORUM_CHANNEL_IDS holding only commas', { FORUMS: '', FORUM_CHANNEL_IDS: ' , ' }, /^FORUMS names no player forum/],
    ['no GUILD_ID', { GUILD_ID: '' }, /^GUILD_ID is not set/],
    ['a GUILD_ID of spaces', { GUILD_ID: '  ' }, /^GUILD_ID is not set/],
    ['a GUILD_ID with a space', { GUILD_ID: ' 1' }, /^GUILD_ID is not set/],
    ['bad TEMPLATES', { TEMPLATES: '{"Bug":"x"}' }, /^TEMPLATES is not valid/],
    ['a role id that is no id', { APPROVED_ROLE_IDS: '12,mods' }, /^APPROVED_ROLE_IDS entry mods is not a role id\.$/],
    ['no MOD_CHANNEL_ID', { MOD_CHANNEL_ID: '' }, /^MOD_CHANNEL_ID is empty/],
    ['a MOD_CHANNEL_ID of spaces, which the daily check would post to', { MOD_CHANNEL_ID: '   ' }, /^MOD_CHANNEL_ID is not a channel id/],
    ['a QUEUE_CHANNEL_ID that is no id', { QUEUE_CHANNEL_ID: '#queue' }, /^QUEUE_CHANNEL_ID is not a channel id/],
    ['a QUEUE_CHANNEL_ID of spaces, which the scan would use', { QUEUE_CHANNEL_ID: ' ' }, /^QUEUE_CHANNEL_ID is not a channel id/],
    ['a CHECKLIST_FORUM_ID that is no id', { CHECKLIST_FORUM_ID: 'ck' }, /^CHECKLIST_FORUM_ID is not a channel id/],
    ['a bad STALE_DAYS', { STALE_DAYS: 'three' }, /^STALE_DAYS is not a positive number\.$/],
    ['an endless STALE_DAYS', { STALE_DAYS: 'Infinity' }, /^STALE_DAYS is not a positive number\.$/],
    ['no STATE binding', { STATE: undefined }, /^The STATE KV namespace is not bound/],
  ]) {
    const lines = configProblems({ ...CLEAN, ...over });
    assert.ok(lines.some((l) => re.test(l)), `${why}: ${lines.join(' | ')}`);
  }
  for (const [why, over] of [
    ['a key with a line break', { REPOS: `{"a\\nb${'x'.repeat(200)}":"me/one"}` }],
    ['a forum key of 300 digits with a broken template', { FORUMS: `{"${'9'.repeat(300)}":{"template":"x"}}` }],
  ]) {
    const broken = configProblems({ ...CLEAN, ...over });
    assert.ok(broken.length && broken.every((l) => !l.includes('\n') && l.length < 300), `${why} gives short lines: ${broken.join(' | ')}`);
  }
});

test("ST2: channelPermissions applies Discord's order, all role denies before all role allows", () => {
  const V = PERMS.viewChannel;
  const S = PERMS.sendMessages;
  const R = PERMS.readMessageHistory;
  const roles = [{ id: '1', permissions: String(V | S | R) }, { id: 'ra', permissions: '0' }, { id: 'rb', permissions: '0' }, { id: 'adm', permissions: String(PERMS.administrator) }];
  const of = (botRoles, permission_overwrites) => channelPermissions({ guildId: '1', botId: 'b', botRoles, roles, channel: { permission_overwrites } });
  const o = (id, type, deny = 0n, allow = 0n) => ({ id, type, deny: String(deny), allow: String(allow) });
  for (const [why, got, want] of [
    ['administrator via a role', of(['adm'], [o('1', 0, V | S | R)]) & R, R],
    ['an @everyone deny with a role allow', of(['ra'], [o('1', 0, R), o('ra', 0, 0n, R)]) & R, R],
    ['a role deny with a member allow', of(['ra'], [o('ra', 0, R), o('b', 1, 0n, R)]) & R, R],
    ['a member deny over a role allow', of(['ra'], [o('ra', 0, 0n, R), o('b', 1, R)]) & R, 0n],
    ['no overwrites', of(['ra'], []) & (V | S | R), V | S | R],
    ['deny and allow on the same role', of(['ra'], [o('ra', 0, R, R)]) & R, R],
    ['one role denies and another allows: allowed', of(['ra', 'rb'], [o('ra', 0, R), o('rb', 0, 0n, R)]) & R, R],
    ['the same with the overwrites in the other order', of(['rb', 'ra'], [o('rb', 0, 0n, R), o('ra', 0, R)]) & R, R],
    ['an overwrite for a role the bot lacks changes nothing', of(['ra'], [o('rb', 0, R)]) & R, R],
  ]) assert.equal(got, want, why);
});

test('ST4: postLines sends whole lines in bounded messages and says which it sent by place; fitLines names what was left out', async () => {
  // What the real sender sends: each message, and whether it was taken.
  const sendAll = async (lines, answer = () => true) => {
    const sent = [];
    const took = await postLines(async (text) => { sent.push(text); return answer(sent.length); }, lines);
    return { sent, took };
  };
  const line = (i) => `- ${String(i).padStart(4, '0')} ${'x'.repeat(90)}`;
  const few = Array.from({ length: 5 }, (_, i) => line(i));
  assert.deepEqual(fitLines(few, 1), { lines: few, rest: [] });
  const many = Array.from({ length: 100 }, (_, i) => line(i));
  const { lines, rest } = fitLines(many, 2);
  assert.ok(rest.length > 0);
  assert.equal(lines.at(-1), `- and ${rest.length} more (see the Worker log)`);
  assert.deepEqual([...lines.slice(0, -1), ...rest], many, 'nothing lost or reordered');
  const two = await sendAll(lines);
  assert.ok(two.sent.length <= 2 && two.sent.every((m) => m.length <= DISCORD_MAX), "each message within Discord's limit");
  assert.deepEqual(two.sent.join('\n').split('\n'), lines, 'whole lines, in order');
  const huge = await sendAll([`- ${'y'.repeat(3000)}`]);
  assert.equal(huge.sent.length, 1);
  assert.ok(huge.sent[0].length <= DISCORD_MAX && huge.sent[0].endsWith('…'), 'an oversized line is cut to fit the message sent');
  const long = Array.from({ length: 2000 }, (_, i) => `- ${i}`);
  const fit = fitLines(long, 5);
  assert.equal(fit.lines.length - 1 + fit.rest.length, 2000);
  assert.ok((await sendAll(fit.lines)).sent.length <= 5);
  // Thirty equal lines fill two messages; the first is taken, the second not.
  const same = Array(30).fill(`- ${'z'.repeat(68)}`);
  const split = await sendAll(same, (n) => n === 1);
  const first = split.sent[0].split('\n').length;
  assert.equal(split.sent.length, 2);
  assert.deepEqual(split.took, Array.from({ length: first }, (_, i) => i), "only the first message's places, though the text of the rest was taken too");
  for (const [why, err, want] of [
    ['a 2xx answer that is not JSON', { discord: { status: 200, notJson: true } }, true],
    ['a refusal', { discord: { status: 403 } }, false],
    ['a refusal whose answer is not JSON either', { discord: { status: 403, notJson: true } }, false],
    ['a redirect whose answer is not JSON', { discord: { status: 302, notJson: true } }, false],
    ['a failure with no answer', new Error('network'), false],
    ['no error at all', undefined, false],
  ]) assert.equal(taken(err), want, why);
});
