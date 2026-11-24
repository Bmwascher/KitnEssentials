// The setup world: a server, an app and repos where every setup check passes.
import { fakeFetch } from './fake-fetch.mjs';
import { PERMS, STATUS_NAMES, CHECKLIST_NAMES, LABEL_DEFS } from '../src/core.js';

// A GitHub App key, made once, so the setup check signs its token requests
// with the real code and nothing stands in for it.
const APP_KEY = await (async () => {
  const k = await crypto.subtle.generateKey({ name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']);
  const der = Buffer.from(await crypto.subtle.exportKey('pkcs8', k.privateKey)).toString('base64');
  return `-----BEGIN PRIVATE KEY-----\n${der.match(/.{1,64}/g).join('\n')}\n-----END PRIVATE KEY-----\n`;
})();

// `edit(s)` breaks one part before the routes are built. `s.alone` answers a
// channel read on its own, by id (a channel missing there answers 404).
// Every repo under `me/` has the same labels, one page per entry of
// `s.labelPages`. `s.installs` answers a repo's installation read (default
// `{ id: 1 }`), and `s.tokens` an installation's token request (default
// `s.token`). `publicKey` is the app's key, in the env and in the
// application's answer alike.
export function setupWorld(edit = () => {}, publicKey = 'a'.repeat(64)) {
  const allowed = String(PERMS.viewChannel | PERMS.sendMessages | PERMS.readMessageHistory | PERMS.manageThreads | PERMS.sendMessagesInThreads | PERMS.manageWebhooks);
  const tags = (names) => names.map((name, i) => ({ id: String(700 + i), name }));
  const view = String(PERMS.viewChannel);
  const s = {
    env: {},
    app: { flags: 1 << 19 },
    member: { roles: ['11'] },
    roles: [{ id: '1', permissions: allowed }, { id: '11', permissions: '0' }],
    rolesAnswer: null,
    channels: [
      { id: '900', type: 15, guild_id: '1', available_tags: tags([...STATUS_NAMES, 'Accepted', 'Answered']), permission_overwrites: [] },
      { id: '556', type: 0, guild_id: '1', permission_overwrites: [] },
      // Staff-only: hidden from @everyone, shown to the bot's role.
      { id: '555', type: 0, guild_id: '1', permission_overwrites: [{ id: '1', type: 0, deny: view, allow: '0' }, { id: '11', type: 0, deny: '0', allow: view }] },
      { id: '950', type: 15, guild_id: '1', available_tags: tags([...CHECKLIST_NAMES, 'Accepted']), permission_overwrites: [] },
    ],
    alone: {},
    template: null,
    installs: {},
    token: { token: 't', permissions: { issues: 'write' } },
    tokens: {},
    labelPages: [LABEL_DEFS.map(([name]) => ({ name }))],
    channelsAnswer: null,
    modPost: null,
  };
  edit(s);
  const page = (url) => Number((/[?&]page=(\d+)/.exec(url) || [0, 1])[1]);
  const f = fakeFetch([
    ['GET', /\/users\/@me$/, () => ({ id: '42' })],
    ['GET', /\/applications\/@me$/, () => (s.app instanceof Response ? s.app : { verify_key: publicKey, ...s.app })],
    ['GET', /\/guilds\/1\/members\/42$/, () => s.member],
    ['GET', /\/guilds\/1\/roles$/, () => s.rolesAnswer || s.roles],
    ['GET', /\/guilds\/1\/channels$/, () => s.channelsAnswer || s.channels],
    ['GET', /\/channels\/\d+\/messages\/\d+$/, () => s.template || { id: '555', content: 'Addon version:' }],
    ['GET', /\/channels\/(\d+)$/, (b, url) => s.alone[/channels\/(\d+)$/.exec(url)[1]] || new Response('{"message":"Unknown Channel"}', { status: 404 })],
    ['POST', /\/channels\/555\/messages$/, () => (typeof s.modPost === 'function' ? s.modPost() : s.modPost || { id: 'm1' })],
    ['PATCH', /\/webhooks\//, () => ({})],
    ['GET', /api\.github\.com\/repos\/([^/]+\/[^/]+)\/installation$/, (b, url) => s.installs[/repos\/([^/]+\/[^/]+)\/installation$/.exec(url)[1]] || { id: 1 }],
    ['POST', /api\.github\.com\/app\/installations\/(\d+)\/access_tokens$/, (b, url) => s.tokens[/installations\/(\d+)\//.exec(url)[1]] || s.token],
    ['GET', /api\.github\.com\/repos\/me\/[^/]+\/labels/, (b, url) => s.labelPages[page(url) - 1] || []],
  ]);
  const env = {
    DISCORD_BOT_TOKEN: 'bot', DISCORD_PUBLIC_KEY: publicKey, GITHUB_APP_ID: '7', GITHUB_APP_PRIVATE_KEY: APP_KEY,
    GUILD_ID: '1', REPOS: '{"ONE":"me/one"}',
    FORUMS: '{"900":{"template":"https://discord.com/channels/1/444/555"}}',
    QUEUE_CHANNEL_ID: '556', MOD_CHANNEL_ID: '555', CHECKLIST_FORUM_ID: '950',
    STATE: { get: async () => null, put: async () => {} }, ...s.env,
  };
  return { env, deps: { fetch: f }, f, s };
}
