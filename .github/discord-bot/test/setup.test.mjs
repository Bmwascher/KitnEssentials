import test from 'node:test';
import assert from 'node:assert/strict';
import { configProblems, channelPermissions, fitLines, setupCheck } from '../src/setup.js';
import { PERMS, postLines, taken, STATUS_NAMES, CHECKLIST_NAMES, LABEL_DEFS, LABELS } from '../src/core.js';
import { setupWorld } from './setup-world.mjs';
import { stall, stallBody } from './fake-fetch.mjs';

// Discord's own message limit, which every message sent must fit.
const DISCORD_MAX = 2000;
const KV = { get: async () => null, put: async () => {} };
const CLEAN = { REPOS: '{"KE":"me/one"}', FORUMS: '{"900":{}}', GUILD_ID: '1', MOD_CHANNEL_ID: '555', STATE: KV };

test('ST1: configProblems names each broken setting as the code reads it, in one line, and nothing for a clean config', () => {
  assert.deepEqual(configProblems(CLEAN), []);
  assert.deepEqual(configProblems({ ...CLEAN, STATE: undefined }, { bindings: false }), [], 'bindings off skips STATE');
  assert.deepEqual(configProblems({ ...CLEAN, FORUMS: '', FORUM_CHANNEL_IDS: '900' }), [], 'the older FORUM_CHANNEL_IDS still counts');
  assert.deepEqual(configProblems({ ...CLEAN, FORUMS: false, FORUM_CHANNEL_IDS: '900' }), [], 'a false FORUMS is unset, as the reader reads it');
  assert.deepEqual(configProblems({ ...CLEAN, STALE_DAYS: '  ', TEMPLATES: ' ', CHECKLIST_FORUM_ID: '  ' }), [], 'settings read as unset when blank stay unset');
  assert.deepEqual(configProblems({ ...CLEAN, CHECKLIST_FORUM_ID: ' 950 ' }), [], 'the checklist id is read trimmed, as the code reads it');
  for (const [why, over, re] of [
    ['no REPOS', { REPOS: '' }, /^REPOS is not set or not valid JSON/],
    ['a REPOS entry that is not owner/repo', { REPOS: '{"KE":"one"}' }, /^REPOS entry KE is not owner\/repo\.$/],
    ['a lower-case REPOS key', { REPOS: '{"ke":"me/one"}' }, /^REPOS key "ke" does not fit the form: write it in upper case, at most 10 characters\.$/],
    ['a REPOS key longer than the form field', { REPOS: '{"ELEVENCHARS":"me/one"}' }, /^REPOS key "ELEVENCHARS" does not fit the form/],
    // A key is letters and digits only: both names carry it.
    ['a REPOS key holding a line break', { REPOS: '{"K\\nE":"me/one"}' }, /^REPOS key "K E" is not made of letters and digits: write each key in A to Z, a to z and 0 to 9 only, like KE\.$/],
    ['a REPOS key holding a space', { REPOS: '{"AB CD":"me/one"}' }, /^REPOS key "AB CD" is not made of letters and digits/],
    ['a REPOS key holding a bracket', { REPOS: '{"U]I":"me/one"}' }, /^REPOS key "U\]I" is not made of letters and digits/],
    ['an empty REPOS key', { REPOS: '{"":"me/one"}' }, /^REPOS key "" is not made of letters and digits/],
    ['a FORUMS value with no text form, which the reader would throw on', { FORUMS: '{"900":{"template":{"toString":null}}}' }, /^FORUMS entry 900: "client", "type" and "template" must each be text/],
    ['a broken template beside a forum field that is an object the reader still reads', { FORUMS: '{"900":{"client":{}},"901":{"template":"typo"}}' }, /^FORUMS entry 901: its "template" is not a message link/],
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
    ['a template that is no message link', { FORUMS: '{"900":{"template":"https://discord.com/channels/1/2"}}' }, /^FORUMS entry 900: its "template" is not a message link \(right-click the template message › Copy Message Link\)\.$/],
    ['FORUMS naming only the checklist forum', { FORUMS: '{"950":{}}', CHECKLIST_FORUM_ID: '950' }, /^FORUMS names no player forum/],
    ['FORUM_CHANNEL_IDS holding only commas', { FORUMS: '', FORUM_CHANNEL_IDS: ' , ' }, /^FORUM_CHANNEL_IDS names no player forum/],
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
  // One call names every bad key and still checks the rest of the map.
  assert.deepEqual(configProblems({ ...CLEAN, REPOS: JSON.stringify({ 'a b': 'me/one', '||KE||': 'broken' }) }), [
    'REPOS key "a b" is not made of letters and digits: write each key in A to Z, a to z and 0 to 9 only, like KE.',
    'REPOS key "||KE||" is not made of letters and digits: write each key in A to Z, a to z and 0 to 9 only, like KE.',
    'REPOS entry ||KE|| is not owner/repo.',
    "LOCK_REPO is empty while REPOS names more than one repo: set it to the repo that holds every filing's lock.",
  ]);
  // A JSON variable with no text form throws wherever it is turned into
  // text. The list is written here, not taken from the checker.
  for (const k of ['REPOS', 'LOCK_REPO', 'FORUMS', 'FORUM_CHANNEL_IDS', 'GUILD_ID', 'TEMPLATES', 'APPROVED_ROLE_IDS', 'MOD_CHANNEL_ID', 'QUEUE_CHANNEL_ID', 'CHECKLIST_FORUM_ID', 'STALE_DAYS', 'RENAME_POSTS']) {
    const lines = configProblems({ ...CLEAN, [k]: { toString: null } });
    assert.ok(lines.includes(`${k} is not text: set it as text. The checks below read it as unset.`), `${k} with no text form: ${lines.join(' | ')}`);
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

const checkOf = async (edit) => {
  const { env, deps, f } = setupWorld(edit);
  return { ...(await setupCheck(env, deps, { deadline: Date.now() + 20000 })), f };
};
const deny = (id, bits) => ({ id, type: 0, deny: String(bits), allow: '0' });
const tagNames = (names) => names.map((name, i) => ({ id: String(800 + i), name }));
const refusal = (status) => new Response('{"message":"no"}', { status });
const others = (n, size = 100) => Array.from({ length: size }, (_, i) => ({ name: `other-${n}-${i}` }));
const allLabels = () => LABEL_DEFS.map(([name]) => ({ name }));

test('ST3: setupCheck names each problem in one line with its fix, passes only on the evidence it needs, and checks the moderator channel whatever else fails', async () => {
  const clean = await checkOf(() => {});
  assert.deepEqual(clean.problems, [], "all pass, the template in a post read directly (444 is not in the guild's list) included");
  assert.equal(clean.mod, 'ok');
  assert.ok(clean.passed > 0);
  for (const [why, edit, re] of [
    ['a listed channel naming another server', (s) => { s.channels[2].guild_id = '2'; }, /^Moderator channel <#555>: it is not a channel of this server\. Check the id\.$/],
    ['a listed channel without its server id (an optional field)', (s) => { delete s.channels[1].guild_id; }, /^Queue channel <#556>: could not check it \(Discord's answer had no server id\)\.$/],
    ['a token request refused (404), which is no missing install', (s) => { s.token = refusal(404); }, /^Could not check me\/one \(GitHub POST \/app\/installations\/1\/access_tokens -> 404/],
    ['an installation read failing (500) with " -> 404 " in its body', (s) => { s.installs['me/one'] = new Response('upstream said -> 404 x', { status: 500 }); },
      /^Could not check me\/one \(GitHub GET \/repos\/me\/one\/installation -> 500/],
    ['a missing public key', (s) => { s.env = { DISCORD_PUBLIC_KEY: '' }; }, /^DISCORD_PUBLIC_KEY is not the 64-character public key/],
    ['a public key of the wrong form', (s) => { s.env = { DISCORD_PUBLIC_KEY: 'z'.repeat(64) }; }, /^DISCORD_PUBLIC_KEY is not the 64-character public key/],
    ['a public key that is not a string, which the verifier cannot read', (s) => { s.env = { DISCORD_PUBLIC_KEY: ['a'.repeat(64)] }; }, /^DISCORD_PUBLIC_KEY is not text/],
    ['a private key bound to null, which the key reader cannot read', (s) => { s.env = { GITHUB_APP_PRIVATE_KEY: null }; }, /^GITHUB_APP_PRIVATE_KEY is not text/],
    ["a public key of another app than the token's", (s) => { s.app = { ...s.app, verify_key: 'b'.repeat(64) }; },
      /^DISCORD_PUBLIC_KEY and DISCORD_BOT_TOKEN belong to different Discord apps\. In the developer portal, open the bot's app and set both from it/],
    ['a broken GUILD_ID: the application group still runs', (s) => { s.env = { GUILD_ID: 'x' }; s.app = { flags: 0 }; }, /^The Message Content setting is off/],
    ['a broken GUILD_ID: the template group still runs', (s) => { s.env = { GUILD_ID: 'x' }; s.template = refusal(403); }, /^Forum <#900>: its template message cannot be read \(403\)\./],
    ['a broken GUILD_ID: the server group says it did not run', (s) => { s.env = { GUILD_ID: 'x' }; },
      /^The channel, tag and role checks did not run: fix GUILD_ID above, then run the check again\.$/],
    ['no bot token', (s) => { s.env = { DISCORD_BOT_TOKEN: '' }; }, /^DISCORD_BOT_TOKEN is not set/],
    ['no bot token: the Discord groups say they did not run', (s) => { s.env = { DISCORD_BOT_TOKEN: '' }; },
      /^The Discord checks \(channels, tags, roles, Message Content, the public key and the template messages\) did not run: fix DISCORD_BOT_TOKEN above, then run the check again\.$/],
    ['no bot token: the GitHub group still runs', (s) => { s.env = { DISCORD_BOT_TOKEN: '' }; s.installs['me/one'] = refusal(404); }, /^me\/one: the GitHub App is not installed there \(404\)\./],
    ['no App id', (s) => { s.env = { GITHUB_APP_ID: '' }; }, /^GITHUB_APP_ID is not set, or holds a space: set it to the App ID \(the App's settings › About\)\. /],
    ['an App id holding a space', (s) => { s.env = { GITHUB_APP_ID: '12 34' }; }, /^GITHUB_APP_ID is not set, or holds a space/],
    ['no App id: the GitHub group says it did not run', (s) => { s.env = { GITHUB_APP_ID: '' }; },
      /^The GitHub checks \(install, permissions and labels\) did not run: fix GITHUB_APP_ID or GITHUB_APP_PRIVATE_KEY above, then run the check again\.$/],
    ['no REPOS and no LOCK_REPO: the GitHub group says it did not run', (s) => { s.env = { REPOS: '' }; },
      /^The GitHub checks \(install, permissions and labels\) did not run: fix REPOS above, then run the check again\.$/],
    ['a FORUMS value with no text form: named, and every group still runs', (s) => { s.env = { FORUMS: '{"900":{"template":{"toString":null}}}' }; s.installs['me/one'] = refusal(404); },
      /^me\/one: the GitHub App is not installed there \(404\)\./],
    ['a FORUMS value with no text form: the forum checks say they did not run', (s) => { s.env = { FORUMS: '{"900":{"template":{"toString":null}}}' }; },
      /^The forum checks \(permissions, tags and template messages\) did not run: fix FORUMS above, then run the check again\.$/],
    ['a setting with no text form: named, and every group still runs', (s) => { s.env = { STALE_DAYS: { toString: null } }; s.installs['me/one'] = refusal(404); },
      /^me\/one: the GitHub App is not installed there \(404\)\./],
    ['an empty forum list: the forum checks say they did not run', (s) => { s.env = { FORUMS: '{}' }; },
      /^The forum checks \(permissions, tags and template messages\) did not run: fix FORUMS above, then run the check again\.$/],
    ['FORUM_CHANNEL_IDS naming no id: the forum checks name that setting', (s) => { s.env = { FORUMS: '', FORUM_CHANNEL_IDS: 'abc' }; },
      /^The forum checks \(permissions, tags and template messages\) did not run: fix FORUM_CHANNEL_IDS above, then run the check again\.$/],
    ['the roles read answered 204, with no role list', (s) => { s.rolesAnswer = new Response(null, { status: 204 }); },
      /^Could not check the bot's access to the server \(Discord's answer had no role list\), so its channel, tag and role checks did not run: fix this, then run the check again\.$/],
    ['the application read answered 204', (s) => { s.app = new Response(null, { status: 204 }); },
      /^Could not check the Message Content setting or the public key \(Discord's answer had no application\)\.$/],
    ['@everyone as an approved role', (s) => { s.env = { APPROVED_ROLE_IDS: '1' }; }, /^APPROVED_ROLE_IDS: <@&1> is the @everyone role, which the filing check never matches\./],
    ['a moderator channel everyone can see', (s) => { s.channels[2].permission_overwrites = []; }, /^Moderator channel <#555>: everyone in the server can see it/],
    ['a missing Answered tag', (s) => { s.channels[0].available_tags = tagNames([...STATUS_NAMES, 'Accepted']); }, /^Forum <#900> has no "Answered" tag\./],
    ['a private key that is no key file', (s) => { s.env = { GITHUB_APP_PRIVATE_KEY: 'secret' }; }, /^GITHUB_APP_PRIVATE_KEY is not the text of a private key file/],
    ['a broken GUILD_ID, the GitHub checks still run', (s) => { s.env = { GUILD_ID: 'x' }; s.installs['me/one'] = refusal(404); }, /^me\/one: the GitHub App is not installed there \(404\)\./],
    ['a broken REPOS, LOCK_REPO still checked', (s) => { s.env = { REPOS: '', LOCK_REPO: 'me/lock' }; s.installs['me/lock'] = refusal(404); }, /^me\/lock: the GitHub App is not installed there \(404\)\./],
    ['a REPOS key that is not letters and digits: its repo is still checked', (s) => { s.env = { REPOS: '{"O NE":"me/one"}' }; s.installs['me/one'] = refusal(404); }, /^me\/one: the GitHub App is not installed there \(404\)\./],
    ['a lock-only repo with read-only issue access', (s) => { s.env = { LOCK_REPO: 'me/lock' }; s.installs['me/lock'] = { id: 2 }; s.tokens['2'] = { token: 't2', permissions: { issues: 'read' } }; },
      /^me\/lock: the GitHub App lacks Issues: Read and write\./],
    ['a listed channel of the wrong kind', (s) => { s.channels[0].type = 0; }, /^Forum <#900>: it is the wrong kind of channel \(a forum is needed\)\. Check the id\.$/],
    ['missing from the list, its own read refused (403)', (s) => { s.channels.splice(1, 1); s.alone['556'] = refusal(403); }, /^Queue channel <#556>: the bot cannot see it\. Allow View Channel for the bot's role there\.$/],
    ['missing from the list, no such channel (404)', (s) => { s.channels.splice(1, 1); }, /^Queue channel <#556>: no such channel\. Check the id\.$/],
    ['missing from the list, its read failing (500)', (s) => { s.channels.splice(1, 1); s.alone['556'] = refusal(500); }, /^Queue channel <#556>: could not check it \(Discord GET \/channels\/556 -> 500/],
    ['missing from the list, in another server', (s) => { s.channels.splice(1, 1); s.alone['556'] = { id: '556', guild_id: '2', type: 0 }; }, /^Queue channel <#556>: it is not a channel of this server\. Check the id\.$/],
    ['missing from the list, a post', (s) => { s.channels.splice(1, 1); s.alone['556'] = { id: '556', guild_id: '1', type: 11 }; }, /^Queue channel <#556>: it is a post, not a channel\. Check the id\.$/],
    ['missing from the list, then checked from its own answer', (s) => { s.channels.splice(1, 1); s.alone['556'] = { id: '556', guild_id: '1', type: 0, permission_overwrites: [deny('11', PERMS.sendMessages)] }; },
      /^Queue channel <#556>: the bot lacks Send Messages\./],
    ['a missing status tag', (s) => { s.channels[0].available_tags = tagNames([...STATUS_NAMES.filter((n) => n !== 'Shipped'), 'Accepted', 'Answered']); }, /^Forum <#900> has no "Shipped" tag\. Add it, spelled as the README lists it\.$/],
    ['a missing Accepted tag', (s) => { s.channels[0].available_tags = tagNames([...STATUS_NAMES, 'Answered']); }, /^Forum <#900> has no "Accepted" tag\./],
    ['a missing checklist tag', (s) => { s.channels[3].available_tags = tagNames([...CHECKLIST_NAMES.filter((n) => n !== 'Done'), 'Accepted']); }, /^Checklist forum <#950> has no "Done" tag\./],
    ['Message Content off', (s) => { s.app = { flags: 0 }; }, /^The Message Content setting is off: filed issues would quote no text, and the bot would see no attachments\. Turn it on in the developer portal › Bot › Privileged Gateway Intents\.$/],
    ['an unreadable template', (s) => { s.template = refusal(403); }, /^Forum <#900>: its template message cannot be read \(403\)\./],
    ['a template read failing (500), which says nothing of the link', (s) => { s.template = refusal(500); }, /^Forum <#900>: could not check its template message \(Discord GET \/channels\/444\/messages\/555 -> 500/],
    ['a template read answered 204, with no message', (s) => { s.template = new Response(null, { status: 204 }); }, /^Forum <#900>: could not check its template message \(Discord's answer had no message\)\.$/],
    ['a missing role', (s) => { s.env = { APPROVED_ROLE_IDS: '777' }; }, /^APPROVED_ROLE_IDS: the role <@&777> does not exist in this server\.$/],
    ['no installation', (s) => { s.installs['me/one'] = refusal(404); }, /^me\/one: the GitHub App is not installed there \(404\)\. Install it on that repo\.$/],
    ['no installation, its answer body cut off', (s) => { s.installs['me/one'] = new Response(new ReadableStream({ start(c) { c.error(new TypeError('connection reset')); } }), { status: 404 }); },
      /^me\/one: the GitHub App is not installed there \(404\)\. Install it on that repo\.$/],
    ['a renamed repo (301 on the installation read)', (s) => { s.installs['me/one'] = new Response('', { status: 301, headers: { location: 'https://api.github.com/repositories/9/installation' } }); },
      /^me\/one: GitHub says the repo has moved \(301\)\. Set REPOS or LOCK_REPO to its new owner\/repo\.$/],
    ['issues not write', (s) => { s.token = { token: 't', permissions: { issues: 'read' } }; }, /^me\/one: the GitHub App lacks Issues: Read and write\./],
    ['a token answer with no permissions', (s) => { s.token = { token: 't' }; }, /^me\/one: could not check the GitHub App's permissions \(GitHub's answer had none\)\.$/],
    ['a missing label', (s) => { s.labelPages = [allLabels().filter((l) => l.name !== 'needs-info')]; }, /^me\/one: the label "needs-info" is missing\. Run npm run labels me\/one\.$/],
    ['a label in another letter case', (s) => { s.labelPages = [LABEL_DEFS.map(([name]) => ({ name: name === 'from-discord' ? 'From-Discord' : name }))]; },
      /^me\/one: the label "From-Discord" must be named "from-discord", as the bot matches names exactly\. Rename it on GitHub\.$/],
    ['exactly 300 labels, three full pages, the bot labels unseen', (s) => { s.labelPages = [others(1), others(2), others(3)]; },
      /^me\/one: could not check the labels "from-discord", .*: the repo has at least 300 labels, and the bot read only the first 300\.$/],
    ['a channel answer with no overwrite list', (s) => { delete s.channels[1].permission_overwrites; }, /^Queue channel <#556>: could not check the bot's permissions \(Discord's answer had no permission overwrites\)\.$/],
    ['a forum answer with no tag list', (s) => { delete s.channels[0].available_tags; }, /^Forum <#900>: could not check its tags \(Discord's answer had no tag list\)\.$/],
    ['an application answer with no flags (an optional field)', (s) => { s.app = {}; }, /^Could not check the Message Content setting \(Discord's answer had no flags\)\.$/],
    ['a failed read of the server group', (s) => { s.rolesAnswer = refusal(500); },
      /^Could not check the bot's access to the server \(Discord GET \/guilds\/1\/roles -> 500\), so its channel, tag and role checks did not run: fix this, then run the check again\.$/],
    ['a token request answered 301, which is no moved repo', (s) => { s.token = new Response('', { status: 301, headers: { location: 'https://api.github.com/x' } }); },
      /^Could not check me\/one \(GitHub POST \/app\/installations\/1\/access_tokens -> 301\)\.$/],
    ['a token request refused with a body: its why holds no body', (s) => { s.token = new Response('{"message":"some text"}', { status: 422 }); },
      /^Could not check me\/one \(GitHub POST \/app\/installations\/1\/access_tokens -> 422\)\.$/],
    ['a token answer that is not JSON', (s) => { s.token = new Response('token text, not JSON', { status: 201 }); }, /^Could not check me\/one \(GitHub's answer was not JSON\)\.$/],
    ['two labels in another letter case', (s) => { s.labelPages = [LABEL_DEFS.map(([name]) => ({ name: ['from-discord', 'needs-info'].includes(name) ? name.toUpperCase() : name }))]; },
      /^me\/one: the labels ".+" must be named ".+", ".+" must be named ".+", as the bot matches names exactly\. Rename them on GitHub\.$/],
    ['a spent call budget', (s) => { s.env = { FORUMS: JSON.stringify(Object.fromEntries(Array.from({ length: 30 }, (_, i) => [String(1000 + i), {}]))) }; }, /^Forum <#\d+>: not checked \(out of time or calls\)\.$/],
  ]) {
    const { problems } = await checkOf(edit);
    assert.ok(problems.some((l) => re.test(l)), `${why}: ${problems.join(' | ')}`);
    assert.ok(problems.every((l) => !l.includes('\n')), `${why}: one line each`);
    assert.ok(!problems.some((l) => /lacks|is missing|is off|is not installed/.test(l) && /optional field|no overwrite list|no tag list|no permissions|204|failing \(500\)|failed read/.test(why)), `${why}: never a fact without the evidence`);
    if (/^missing from the list/.test(why)) assert.equal(problems.filter((l) => l.includes('<#556>')).length, 1, `${why}: one line only`);
  }
  {
    // Without the token, the Discord checks' own line already says why.
    const r = await checkOf((s) => { s.env = { DISCORD_BOT_TOKEN: '', FORUMS: '{}' }; });
    assert.ok(!r.problems.some((l) => l.startsWith('The forum checks')), `no bot token: no forum line: ${r.problems.join(' | ')}`);
  }
  // The permissions each kind of channel needs, written out here and not
  // taken from the checker: each, denied alone, gives its line and one check
  // fewer passed.
  const V = ['View Channel', PERMS.viewChannel];
  const S = ['Send Messages', PERMS.sendMessages];
  const T = ['Send Messages in Threads', PERMS.sendMessagesInThreads];
  const M = ['Manage Threads', PERMS.manageThreads];
  const H = ['Read Message History', PERMS.readMessageHistory];
  for (const [label, at, needed] of [
    ['Forum <#900>', 0, [V, T, M, H]],
    ['Queue channel <#556>', 1, [V, S, H]],
    ['Moderator channel <#555>', 2, [V, S]],
    ['Checklist forum <#950>', 3, [V, S, T, M, H]],
  ]) {
    for (const [perm, bit] of needed) {
      const r = await checkOf((s) => { s.channels[at].permission_overwrites = [deny('11', bit)]; });
      assert.ok(r.problems.some((l) => l.startsWith(`${label}: the bot lacks ${perm}.`)), `${label}, ${perm}: ${r.problems.join(' | ')}`);
      assert.equal(r.passed, clean.passed - 1, `${label}, ${perm}: one check fewer passed`);
    }
  }
  // Each row names the calls its behavior makes: `calls` counts a pattern
  // in the fake's record, so a check skipped or repeated shows.
  const count = (f, method, re) => f.find(method, re).length;
  const full = [...allLabels(), ...others(0, 100 - LABEL_DEFS.length)];
  for (const [why, edit, gone, calls] of [
    ['the labels on a second page', (s) => { s.labelPages = [others(1), allLabels()]; }, /label/, [['GET', /\/repos\/me\/one\/labels/, 2]]],
    ['every label on a full first page: no second read', (s) => { s.labelPages = [full, others(2)]; }, /label/, [['GET', /\/repos\/me\/one\/labels/, 1]]],
    ['Accepted in another letter case, which the bot accepts', (s) => { s.labelPages = [LABEL_DEFS.map(([name]) => ({ name: name === LABELS.accepted ? 'Accepted' : name }))]; }, /label/, []],
    ['a lock-only repo: its access checked, its labels never read', (s) => { s.env = { LOCK_REPO: 'me/lock' }; }, /me\/lock/,
      [['GET', /\/repos\/me\/lock\/installation$/, 1], ['GET', /\/repos\/me\/lock\/labels/, 0]]],
    ['one repo under aliases and LOCK_REPO in other letter cases: checked once', (s) => { s.env = { REPOS: '{"A":"me/one","B":"Me/One"}', LOCK_REPO: 'ME/ONE' }; }, /one/i,
      [['GET', /\/installation$/, 1]]],
    ['Message Content on through 1 << 18', (s) => { s.app = { flags: 1 << 18 }; }, /Message Content/, []],
    ['Message Content on through flags_new alone', (s) => { s.app = { flags: 0, flags_new: String(1n << 19n) }; }, /Message Content/, []],
    ['missing from the list, a same-server channel that passes', (s) => { s.channels.splice(1, 1); s.alone['556'] = { ...setupWorld().s.channels[1] }; }, /556/,
      [['GET', /\/channels\/556$/, 1]]],
    ['a failed channel list, the moderator channel also the queue channel: read once', (s) => { s.env = { QUEUE_CHANNEL_ID: '555' }; s.channelsAnswer = refusal(500); s.alone['555'] = { ...setupWorld().s.channels[2] }; }, /^$/,
      [['GET', /\/channels\/555$/, 1]]],
  ]) {
    const { problems, f } = await checkOf(edit);
    assert.ok(!problems.some((l) => gone.test(l)), `${why}: ${problems.join(' | ')}`);
    for (const [method, re, n] of calls) assert.equal(count(f, method, re), n, `${why}: ${method} ${re}`);
  }
  {
    // Read on its own, the channel passes the checks it passes when listed.
    const r = await checkOf((s) => { s.channels.splice(1, 1); s.alone['556'] = { ...setupWorld().s.channels[1] }; });
    assert.equal(r.passed, clean.passed, `an unlisted channel that passes counts its checks: ${r.problems.join(' | ')}`);
  }
  {
    // Four calls a repo (two label pages): the fourth repo's first label
    // page is the share's 15th call, and its second page is never sent.
    const r = await checkOf((s) => { s.env = { REPOS: JSON.stringify({ A: 'me/a', B: 'me/b', C: 'me/c', D: 'me/d' }), LOCK_REPO: 'me/a' }; s.labelPages = [others(1), allLabels()]; });
    assert.equal(r.f.calls.filter((c) => /api\.github\.com/.test(c.url)).length, 15, `the GitHub share ends at its 15th call: ${r.problems.join(' | ')}`);
    assert.ok(r.problems.includes("me/d's labels: not checked (out of time or calls)."), `the fourth repo's second page: ${r.problems.join(' | ')}`);
  }
  {
    // The application read stalls until the run's deadline cuts it off.
    const { env, deps } = setupWorld();
    const fetch = (url, init) => (/\/applications\/@me$/.test(url) ? stall(init) : deps.fetch(url, init));
    const r = await setupCheck(env, { fetch }, { deadline: Date.now() + 300 });
    assert.ok(r.problems.includes('The Message Content setting and the public key: not checked (out of time or calls).'), `a read the deadline cuts off: ${r.problems.join(' | ')}`);
  }
  {
    // The headers come at once; the body stalls until the deadline.
    const { env, deps } = setupWorld();
    const fetch = (url, init) => (/\/applications\/@me$/.test(url) ? stallBody(init) : deps.fetch(url, init));
    const r = await setupCheck(env, { fetch }, { deadline: Date.now() + 300 });
    assert.ok(r.problems.includes('The Message Content setting and the public key: not checked (out of time or calls).'), `a body the deadline cuts off: ${r.problems.join(' | ')}`);
  }
  const unlisted = { ...setupWorld().s.channels[2] };
  // Each row breaks one thing; the moderator channel's state stays its own.
  for (const [why, edit, mod] of [
    ['a post as the moderator channel', (s) => { s.env = { MOD_CHANNEL_ID: '777' }; s.alone['777'] = { id: '777', guild_id: '1', type: 11 }; }, /^<#777> is not verified \(it is a post, not a channel\)$/],
    ['a listed moderator channel of another server', (s) => { s.channels[2].guild_id = '2'; }, /^<#555> is not verified \(it is not a channel of this server\)$/],
    ['a moderator channel without Send Messages', (s) => { s.channels[2].permission_overwrites = [deny('11', PERMS.sendMessages)]; }, /^the bot lacks Send Messages in <#555>$/],
    ['a roles read answered 204', (s) => { s.rolesAnswer = new Response(null, { status: 204 }); }, /^the moderator channel could not be checked \(Discord's answer had no role list\)$/],
    ['a failed channel list: the moderator channel read on its own', (s) => { s.channelsAnswer = refusal(500); s.alone['555'] = unlisted; }, /^ok$/],
    ['a broken REPOS', (s) => { s.env = { REPOS: '' }; }, /^ok$/],
    ['an empty forum list', (s) => { s.env = { FORUMS: '{}' }; }, /^ok$/],
    ['a failed application read', (s) => { s.app = refusal(500); }, /^ok$/],
  ]) {
    const r = await checkOf(edit);
    assert.match(r.mod, mod, `${why}: ${r.mod} | ${r.problems.join(' | ')}`);
    if (/\^ok/.test(String(mod))) assert.ok(r.problems.length > 0, `${why}: its own line is still there`);
  }
  // An early failure stops only its own group: each row also breaks one
  // check in every group that runs after it, and each of those lines must
  // still come.
  const later = {
    app: [(s) => { s.app = { ...s.app, flags: 0 }; }, /^The Message Content setting is off/],
    server: [(s) => { s.channels[0].available_tags = tagNames([...STATUS_NAMES.filter((n) => n !== 'Shipped'), 'Accepted', 'Answered']); }, /^Forum <#900> has no "Shipped" tag\./],
    template: [(s) => { s.template = refusal(403); }, /^Forum <#900>: its template message cannot be read \(403\)\./],
    github: [(s) => { s.installs['me/one'] = refusal(404); }, /^me\/one: the GitHub App is not installed there \(404\)\./],
  };
  for (const [why, edit, after] of [
    ['the roles read failing (500)', (s) => { s.rolesAnswer = refusal(500); }, ['app', 'template', 'github']],
    ['the roles read answered 204', (s) => { s.rolesAnswer = new Response(null, { status: 204 }); }, ['app', 'template', 'github']],
    ['the channel list answered 204', (s) => { s.channelsAnswer = new Response(null, { status: 204 }); }, ['app', 'template', 'github']],
    ['the application read answered 204', (s) => { s.app = new Response(null, { status: 204 }); }, ['server', 'template', 'github']],
    ['the application read failing (500)', (s) => { s.app = refusal(500); }, ['server', 'template', 'github']],
    ['the template read answered 204', (s) => { s.template = new Response(null, { status: 204 }); }, ['github']],
    ['the template read failing (500)', (s) => { s.template = refusal(500); }, ['github']],
    ['a STALE_DAYS with no text form', (s) => { s.env = { STALE_DAYS: { toString: null } }; }, ['server', 'app', 'template', 'github']],
  ]) {
    const r = await checkOf((s) => { edit(s); for (const k of after) later[k][0](s); });
    for (const k of after) assert.ok(r.problems.some((l) => later[k][1].test(l)), `${why}: the ${k} checks still run: ${r.problems.join(' | ')}`);
  }
});
