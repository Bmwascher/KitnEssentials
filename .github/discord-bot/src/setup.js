// The bot's setup checks. The settings checks need no network access and
// come first; /bot-check, the daily setup check and the Worker's "not set up
// yet" replies use them.
import {
  parseRepos, parseForums, parseRoleIds, isTemplates, PERMS, packGroups, clipLine, MESSAGE_MAX, isDiscordId as digits, STATUS_NAMES, CHECKLIST_NAMES, ACCEPTED,
  LABELS, LABEL_DEFS, TEXT_TYPES, THREAD_TYPES, timedFetch, discordText, oneHop,
} from './core.js';
import { discordClient } from './discord.js';
import { installationAccess, githubClient } from './github.js';
import { BudgetSpent, countedFetch } from './scan.js';
// The code uses these settings whenever they are non-empty, spaces included,
// so that is when they are checked.
const present = (v) => v !== undefined && v !== null && String(v) !== '';
// These the code reads as unset when blank.
const blank = (v) => String(v ?? '').trim() === '';
// owner/repo within GitHub's name limits.
const REPO = /^[\w.-]{1,39}\/[\w.-]{1,100}$/;
// The form's repo field takes at most this many characters.
const REPO_KEY_MAX = 10;
// Every permission, which an administrator has.
const ALL = (1n << 64n) - 1n;

// A config value quoted in a problem line: one line, at most 80 characters,
// so the line stays one line wherever it is posted.
const shown = (v) => {
  const s = String(v).replace(/\s+/g, ' ');
  return s.length > 80 ? `${s.slice(0, 79)}…` : s;
};

// One line per broken setting, each naming the setting and its fix. With
// `bindings`, the STATE namespace must be bound too.
export function configProblems(env, { bindings = true } = {}) {
  const out = [];
  let repos = null;
  try {
    repos = parseRepos(env.REPOS);
  } catch {
    out.push('REPOS is not set or not valid JSON: set it to JSON like {"KE":"owner/repo"}.');
  }
  if (repos) {
    for (const [k, r] of Object.entries(repos)) {
      // The form's answer is read trimmed and in upper case.
      // The field is one line, so a key holding a line break cannot be typed.
      if (!k || k !== k.trim().toUpperCase() || k.length > REPO_KEY_MAX || /[\u0000-\u001f]/.test(k)) out.push(`REPOS key "${shown(k)}" can never be chosen in the form: write it in upper case, at most ${REPO_KEY_MAX} characters, on one line, with no space at either end.`);
      if (typeof r !== 'string' || !REPO.test(r)) out.push(`REPOS entry ${shown(k)} is not owner/repo.`);
    }
    if (Object.keys(repos).length > 1 && !present(env.LOCK_REPO)) out.push("LOCK_REPO is empty while REPOS names more than one repo: set it to the repo that holds every filing's lock.");
  }
  if (present(env.LOCK_REPO) && !REPO.test(String(env.LOCK_REPO))) out.push('LOCK_REPO is not owner/repo (no spaces).');
  let forumsRead = true;
  if (!blank(env.FORUMS)) {
    let raw = null;
    try { raw = JSON.parse(String(env.FORUMS)); } catch { /* named below */ }
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
      forumsRead = false;
      out.push('FORUMS is not valid JSON: set it to JSON keyed by forum channel id, like {"111":{}}.');
    } else {
      for (const id of Object.keys(raw)) if (!digits(id)) out.push(`FORUMS key ${shown(id)} is not a channel id.`);
      // The reader turns client, type and template into text, and an object
      // there can have no text form at all, so the reader is not run on it.
      const textless = Object.entries(raw).filter(([, v]) => v && typeof v === 'object'
        && ['client', 'type', 'template'].some((k) => v[k] !== null && typeof v[k] === 'object'));
      for (const [id] of textless) out.push(`FORUMS entry ${shown(id)}: "client", "type" and "template" must each be text, like "template":"https://discord.com/channels/...".`);
      if (textless.length) forumsRead = false;
      else {
        for (const [id, v] of Object.entries(parseForums(env))) {
          if (v.badTemplate) out.push(`FORUMS entry ${shown(id)}: its "template" is not a message link (right-click the template message > Copy Message Link).`);
        }
      }
    }
  } else if (!blank(env.FORUM_CHANNEL_IDS)) {
    for (const id of String(env.FORUM_CHANNEL_IDS).split(',').map((s) => s.trim()).filter(Boolean)) {
      if (!digits(id)) out.push(`FORUM_CHANNEL_IDS entry ${shown(id)} is not a channel id.`);
    }
  } else {
    forumsRead = false;
    out.push('FORUMS is empty: the bot does nothing anywhere until it names the player forums.');
  }
  // What the bot will use: the checklist forum is never a player forum.
  if (forumsRead && !Object.keys(parseForums(env)).length) out.push('FORUMS names no player forum (the checklist forum does not count).');
  if (!digits(env.GUILD_ID)) out.push("GUILD_ID is not set to the server's id (digits only, no spaces).");
  if (!blank(env.TEMPLATES)) {
    let t = null;
    try { t = JSON.parse(String(env.TEMPLATES)); } catch { /* named below */ }
    if (!isTemplates(t)) out.push('TEMPLATES is not valid: set it to JSON like {"Bug":["Addon version"]}, or leave it unset for the defaults.');
  }
  for (const r of String(env.APPROVED_ROLE_IDS ?? '').split(',').map((s) => s.trim()).filter(Boolean)) {
    if (!digits(r)) out.push(`APPROVED_ROLE_IDS entry ${shown(r)} is not a role id.`);
  }
  if (!present(env.MOD_CHANNEL_ID)) out.push("MOD_CHANNEL_ID is empty: the daily alert, the daily setup check and the weekly line reach only the Worker log. Set it to the moderator channel's id.");
  for (const k of ['MOD_CHANNEL_ID', 'QUEUE_CHANNEL_ID']) {
    if (present(env[k]) && !digits(env[k])) out.push(`${k} is not a channel id (digits only, no spaces).`);
  }
  // The checklist forum's id is read trimmed, so spaces alone are unset.
  if (!blank(env.CHECKLIST_FORUM_ID) && !digits(String(env.CHECKLIST_FORUM_ID).trim())) out.push('CHECKLIST_FORUM_ID is not a channel id (digits only).');
  if (!blank(env.STALE_DAYS) && !(Number.isFinite(Number(env.STALE_DAYS)) && Number(env.STALE_DAYS) > 0)) out.push('STALE_DAYS is not a positive number.');
  // The scan and the filing call get and put on it; nothing is written here.
  if (bindings && !(env.STATE && typeof env.STATE.get === 'function' && typeof env.STATE.put === 'function')) out.push('The STATE KV namespace is not bound: create it and uncomment the [[kv_namespaces]] lines in wrangler.toml (README, Stage 2 step 5).');
  return out;
}

// The bot's permissions in a channel, in Discord's documented order: the
// @everyone role and the bot's roles, administrator, then the channel's
// @everyone overwrite, then every role overwrite's denies together and then
// their allows together (so one role's allow beats another's deny), then the
// member overwrite. Every field it reads is one Discord's answer always
// carries; if one were missing it throws, and the caller's check reports
// "could not check" instead of a permission.
export function channelPermissions({ guildId, botId, botRoles, roles, channel }) {
  const byId = new Map(roles.map((r) => [String(r.id), BigInt(r.permissions)]));
  const mine = new Set(botRoles.map(String));
  let p = byId.get(String(guildId)) || 0n;
  for (const id of mine) p |= byId.get(id) || 0n;
  if ((p & PERMS.administrator) !== 0n) return ALL;
  const over = channel.permission_overwrites;
  const bits = (o, k) => BigInt(o[k]);
  const everyone = over.find((o) => o.type === 0 && String(o.id) === String(guildId));
  if (everyone) p = (p & ~bits(everyone, 'deny')) | bits(everyone, 'allow');
  let deny = 0n;
  let allow = 0n;
  for (const o of over) {
    if (o.type === 0 && String(o.id) !== String(guildId) && mine.has(String(o.id))) {
      deny |= bits(o, 'deny');
      allow |= bits(o, 'allow');
    }
  }
  p = (p & ~deny) | allow;
  const member = over.find((o) => o.type === 1 && String(o.id) === String(botId));
  if (member) p = (p & ~bits(member, 'deny')) | bits(member, 'allow');
  return p;
}

// The lines that fit in `max` messages; when some do not, the last kept line
// says how many were left out, and those are returned for the log.
export function fitLines(lines, max) {
  const cut = lines.map(clipLine);
  if (packGroups(cut).length <= max) return { lines: cut, rest: [] };
  // The longest start that fills `max` messages, in one pass.
  let keep = 0;
  let count = 0;
  let size = 0;
  for (; keep < cut.length; keep++) {
    const n = cut[keep].length;
    if (count && size + 1 + n <= MESSAGE_MAX) size += 1 + n;
    else if (count < max) { count++; size = n; } else break;
  }
  // Room for the closing line: a few kept lines at most give way to it.
  for (;;) {
    const kept = [...cut.slice(0, keep), `- and ${cut.length - keep} more (see the Worker log)`];
    if (keep === 0 || packGroups(kept).length <= max) return { lines: kept, rest: cut.slice(keep) };
    keep--;
  }
}

// Each check has its own share of the 50 requests a Workers run may make;
// the result's posts (5) and the private reply (1) use what is left.
const DISCORD_BUDGET = 28;
const GITHUB_BUDGET = 15;
const CALL_MS = 5000;
const LABEL_PAGES = 3;
const FORUM_TYPE = 15;
// The Message Content intent: the first bit for a bot in 100 or more
// servers, the second for one in fewer.
const MESSAGE_CONTENT = (1n << 18n) | (1n << 19n);
const NEEDS = {
  forum: {
    'View Channel': PERMS.viewChannel, 'Send Messages in Threads': PERMS.sendMessagesInThreads,
    'Manage Threads': PERMS.manageThreads, 'Read Message History': PERMS.readMessageHistory,
  },
  queue: { 'View Channel': PERMS.viewChannel, 'Send Messages': PERMS.sendMessages, 'Read Message History': PERMS.readMessageHistory },
  mod: { 'View Channel': PERMS.viewChannel, 'Send Messages': PERMS.sendMessages },
  checklist: {
    'View Channel': PERMS.viewChannel, 'Send Messages': PERMS.sendMessages, 'Send Messages in Threads': PERMS.sendMessagesInThreads,
    'Manage Threads': PERMS.manageThreads, 'Read Message History': PERMS.readMessageHistory,
  },
};
// Every permission some check needs, for comparing with Discord's own value:
// administrator sets every bit, Discord's value only the defined ones.
export const NEEDED_BITS = Object.values(NEEDS).flatMap((k) => Object.values(k)).reduce((a, b) => a | b, 0n);
const NO_HISTORY = ' Without it every queue card says the first message was deleted.';
// The tag staff put on a post answered without an issue; the daily list of
// waiting posts leaves such a post out.
const ANSWERED_TAG = 'Answered';
const stopped = (e) => e instanceof BudgetSpent || /^out of time /.test(String((e && e.message) || ''));
const short = (e) => (stopped(e) ? 'out of time or calls' : String((e && e.message) || e).replace(/\s+/g, ' ').slice(0, 160));
const them = (list) => (list.length > 1 ? 'them' : 'it');

// Discord's and GitHub's answers are read as documented: a required field
// is used as given, and only an optional one is tested for absence.
const unset = (v) => v === undefined || v === null;

const PEM = /-----BEGIN (RSA )?PRIVATE KEY-----/;
const HEX_KEY = /^[0-9a-fA-F]{64}$/;
// The token signer sends the App id as it is (`iss`), so any value without
// spaces is tried, and GitHub's own answer says whether it is right.
const appIdSet = (v) => /^\S+$/.test(String(v ?? ''));
const githubReady = (env) => appIdSet(env.GITHUB_APP_ID) && PEM.test(String(env.GITHUB_APP_PRIVATE_KEY ?? ''));
// The Worker's secrets, for their presence and form only: no line quotes a
// value. Whether the public key is this bot's is the application group's.
function secretProblems(env) {
  const out = [];
  const put = (k) => `Set it with npx wrangler@3 secret put ${k}.`;
  if (!HEX_KEY.test(String(env.DISCORD_PUBLIC_KEY ?? ''))) out.push(`DISCORD_PUBLIC_KEY is not the 64-character public key from the developer portal (General Information): Discord refuses every command until it is. ${put('DISCORD_PUBLIC_KEY')}`);
  if (blank(env.DISCORD_BOT_TOKEN)) out.push(`DISCORD_BOT_TOKEN is not set: the bot can read and post nothing. ${put('DISCORD_BOT_TOKEN')}`);
  if (!appIdSet(env.GITHUB_APP_ID)) out.push(`GITHUB_APP_ID is not set, or holds a space: set it to the App ID (the App's settings, About). ${put('GITHUB_APP_ID')}`);
  if (!PEM.test(String(env.GITHUB_APP_PRIVATE_KEY ?? ''))) out.push(`GITHUB_APP_PRIVATE_KEY is not the text of a private key file: paste the whole .pem. ${put('GITHUB_APP_PRIVATE_KEY')}`);
  return out;
}

// Every setup check, under a call budget and a deadline, in named groups,
// each in its own try, in this order: the server group's base reads, the
// channel list and the moderator channel; the application group; the rest
// of the server group (the other channels and the approved roles); the
// template group; the GitHub group. The application group comes before the
// long channel list, so channels that spend the calls never hide it. One
// group's failure never stops another; a group that cannot run says so in
// one line and asks for a second run. A check passes (counted) only when its
// answer says so; otherwise it gives one line, a fix or "could not check".
// `mod` is 'ok' only when the moderator channel is a text channel of this
// server where the bot can post; otherwise it says why.
export async function setupCheck(env, deps, { deadline, probe = null }) {
  const problems = [...configProblems(env), ...secretProblems(env)];
  let passed = 0;
  const ok = (cond, line) => {
    if (cond) passed++;
    else problems.push(line);
  };
  const mod = String(env.MOD_CHANNEL_ID ?? '');
  const guild = String(env.GUILD_ID ?? '');
  const token = !blank(env.DISCORD_BOT_TOKEN);
  let modState = mod === '' ? 'MOD_CHANNEL_ID is not set' : !digits(mod) ? 'MOD_CHANNEL_ID is not a channel id'
    : !digits(guild) ? 'the moderator channel could not be checked (GUILD_ID is not a server id)'
      : !token ? 'the moderator channel could not be checked (DISCORD_BOT_TOKEN is not set)' : 'the moderator channel could not be checked';
  let probed = null;
  let repos = null;
  try { repos = parseRepos(env.REPOS); } catch { /* named by configProblems */ }
  let forums = {};
  try { forums = Object.fromEntries(Object.entries(parseForums(env)).filter(([id]) => digits(id))); } catch { /* named by configProblems */ }
  // configProblems says why no player forum is left; this says what it hides.
  if (token && !Object.keys(forums).length) problems.push('The forum checks (permissions, tags and template messages) did not run: fix FORUMS above, then run the check again.');
  const timed = timedFetch(oneHop(deps.fetch || fetch), CALL_MS, deadline);
  // One Discord share for every read. The channel list ends one call's time
  // before the deadline, so a slow list never leaves the moderator channel's
  // own read without time.
  const shared = countedFetch(oneHop(deps.fetch || fetch), DISCORD_BUDGET);
  const discord = discordClient(env.DISCORD_BOT_TOKEN, timedFetch(shared, CALL_MS, deadline));
  const lister = discordClient(env.DISCORD_BOT_TOKEN, timedFetch(shared, CALL_MS, deadline - CALL_MS));
  // A 204 is an answer with no record.
  const need = (v, what) => {
    if (v === null || v === undefined) throw new Error(`Discord's answer had no ${what}`);
    return v;
  };

  // The server group: the bot, its member record and the server's roles are
  // what every permission rests on. The channel list only saves reads: when
  // it fails, each channel is read on its own.
  let base = null;
  let listed = new Map();
  if (!token) {
    problems.push('The Discord checks (channels, tags, roles, Message Content, the public key and the template messages) did not run: fix DISCORD_BOT_TOKEN above, then run the check again.');
  } else if (!digits(guild)) {
    problems.push('The channel, tag and role checks did not run: fix GUILD_ID above, then run the check again.');
  } else {
    try {
      const me = need(await discord.me(), 'user');
      const member = need(await discord.call('GET', `/guilds/${guild}/members/${me.id}`), 'member');
      const roles = need(await discord.call('GET', `/guilds/${guild}/roles`), 'role list');
      base = { me, member, roles };
    } catch (e) {
      problems.push(`Could not check the bot's access to the server (${short(e)}), so its channel, tag and role checks did not run: fix this, then run the check again.`);
      if (digits(mod)) modState = `the moderator channel could not be checked (${short(e)})`;
    }
    if (base) {
      try {
        listed = new Map(need(await lister.call('GET', `/guilds/${guild}/channels`), 'channel list').map((c) => [String(c.id), c]));
      } catch { /* each channel is read on its own */ }
    }
  }
  {
    // One line for a channel: its label, what was found, and the fix. The
    // reason alone is returned, for the moderator channel's state.
    const say = (label, why, fix = '') => {
      problems.push(`${label}: ${why}.${fix ? ` ${fix}` : ''}`);
      return { why };
    };
    // The channel as the list holds it, or as its own read gives it when the
    // list left it out (the list holds no thread and no channel the bot
    // cannot view). Only a 403 is read as missing access. A listed channel
    // meets the same rules as one read on its own.
    const find = async (label, id) => {
      let c = listed.get(String(id));
      if (!c) {
        try {
          c = await discord.call('GET', `/channels/${id}`);
        } catch (e) {
          const status = e.discord && e.discord.status;
          return status === 404 ? say(label, 'no such channel', 'Check the id.')
            : status === 403 ? say(label, 'the bot cannot see it', "Allow View Channel for the bot's role there.")
              : say(label, stopped(e) ? 'not checked (out of time or calls)' : `could not check it (${short(e)})`);
        }
      }
      // A 204 gives no channel; a channel's server id is optional.
      if (!c) return say(label, "could not check it (Discord's answer had no channel)");
      if (unset(c.guild_id)) return say(label, "could not check it (Discord's answer had no server id)");
      if (String(c.guild_id) !== guild) return say(label, 'it is not a channel of this server', 'Check the id.');
      if (THREAD_TYPES.includes(c.type)) return say(label, 'it is a post, not a channel', 'Check the id.');
      return { c };
    };
    const perms = (c) => channelPermissions({ guildId: guild, botId: base.me.id, botRoles: base.member.roles, roles: base.roles, channel: c });
    // Kind, permissions and tags, each only on the fields it needs. `lacking`
    // is what the bot lacks there, or null when its permissions were not
    // checked, `why` saying what stopped them.
    const check = async (label, id, kind, kinds, tags, extra = '') => {
      try {
        const found = await find(label, id);
        if (!found.c) return { lacking: null, why: found.why };
        const c = found.c;
        if (!kinds.includes(c.type)) {
          return { lacking: null, ...say(label, `it is the wrong kind of channel (${kinds.includes(FORUM_TYPE) ? 'a forum' : 'a text channel'} is needed)`, 'Check the id.') };
        }
        passed++;
        let out;
        // The overwrite and tag lists are optional fields of a channel.
        if (unset(c.permission_overwrites)) {
          out = { lacking: null, ...say(label, "could not check the bot's permissions (Discord's answer had no permission overwrites)") };
        } else {
          const has = perms(c);
          const lacking = Object.keys(NEEDS[kind]).filter((k) => (has & NEEDS[kind][k]) === 0n);
          ok(!lacking.length, `${label}: the bot lacks ${lacking.join(', ')}.${lacking.includes('Read Message History') ? extra : ''} Allow ${them(lacking)} for the bot's role in the channel's permissions.`);
          out = { lacking, why: '', c };
        }
        if (tags) {
          if (unset(c.available_tags)) {
            say(label, "could not check its tags (Discord's answer had no tag list)");
          } else {
            const names = new Set(c.available_tags.map((t) => t.name.toLowerCase()));
            const absent = tags.filter((t) => !names.has(t.toLowerCase()));
            ok(!absent.length, `${label} has no ${absent.map((t) => `"${t}"`).join(', ')} tag${absent.length > 1 ? 's' : ''}. Add ${them(absent)}, spelled as the README lists ${them(absent)}.`);
          }
        }
        return out;
      } catch (e) {
        return { lacking: null, ...say(label, stopped(e) ? 'not checked (out of time or calls)' : `could not check it (${short(e)})`) };
      }
    };

    if (base) {
      // The moderator channel before every read that could spend its time or
      // calls, so its state is known whatever else fails.
      if (digits(mod)) {
        const r = await check(`Moderator channel <#${mod}>`, mod, 'mod', TEXT_TYPES, null);
        modState = !r.lacking ? `<#${mod}> is not verified (${r.why})` : r.lacking.length ? `the bot lacks ${r.lacking.join(', ')} in <#${mod}>` : 'ok';
        // What @everyone may do there: a member with no role of its own.
        // Players can then read every result and alert. A warning, not a
        // gate: the channel still gets its posts.
        if (r.c) {
          const everyone = channelPermissions({ guildId: guild, botId: '', botRoles: [], roles: base.roles, channel: r.c });
          if ((everyone & PERMS.viewChannel) !== 0n) problems.push(`Moderator channel <#${mod}>: everyone in the server can see it, and the bot's setup results and alerts there name its settings. Deny View Channel for @everyone in it, and allow it for the staff roles.`);
        }
      }
      const here = probe ? listed.get(String(probe)) : null;
      if (here && !unset(here.permission_overwrites)) {
        try { probed = { id: String(probe), bits: String(perms(here) & NEEDED_BITS) }; } catch { /* the channel's own check says why */ }
      }
    }
    // The application group needs the bot token alone. Its public key must
    // be the one Discord signs this bot's commands with.
    if (token) {
      try {
        const app = await discord.call('GET', '/applications/@me');
        if (!app) {
          problems.push("Could not check the Message Content setting or the public key (Discord's answer had no application).");
        } else {
          const raw = app.flags_new ?? app.flags;
          if (unset(raw)) problems.push("Could not check the Message Content setting (Discord's answer had no flags).");
          else ok((BigInt(raw) & MESSAGE_CONTENT) !== 0n, 'The Message Content setting is off: filed issues would quote no text, and the bot would see no attachments. Turn it on in the developer portal, Bot, Privileged Gateway Intents.');
          // A mismatch shows the two secrets name different apps, not which
          // of them is wrong.
          if (HEX_KEY.test(String(env.DISCORD_PUBLIC_KEY ?? ''))) {
            ok(String(app.verify_key).toLowerCase() === String(env.DISCORD_PUBLIC_KEY).toLowerCase(), "DISCORD_PUBLIC_KEY and DISCORD_BOT_TOKEN belong to different Discord apps. In the developer portal, open the bot's app and set both from it: the public key (General Information) with npx wrangler@3 secret put DISCORD_PUBLIC_KEY, the token (Bot) with npx wrangler@3 secret put DISCORD_BOT_TOKEN.");
          }
        }
      } catch (e) {
        problems.push(`Could not check the Message Content setting or the public key (${short(e)}).`);
      }
    }

    if (base) {
      for (const id of Object.keys(forums)) await check(`Forum <#${id}>`, id, 'forum', [FORUM_TYPE], [...STATUS_NAMES, ACCEPTED, ANSWERED_TAG], NO_HISTORY);
      const queue = String(env.QUEUE_CHANNEL_ID ?? '');
      // The checklist forum's id is read trimmed, as the code reads it.
      const ck = String(env.CHECKLIST_FORUM_ID ?? '').trim();
      if (digits(queue)) await check(`Queue channel <#${queue}>`, queue, 'queue', TEXT_TYPES, null);
      if (digits(ck)) await check(`Checklist forum <#${ck}>`, ck, 'checklist', [FORUM_TYPE], [...CHECKLIST_NAMES, ACCEPTED]);
      const roleIds = new Set(base.roles.map((r) => String(r.id)));
      for (const r of parseRoleIds(env.APPROVED_ROLE_IDS).filter((x) => digits(x))) {
        // Every member has @everyone, but the filing check looks only at
        // the roles a member is given, so it never matches that one.
        if (r === guild) problems.push(`APPROVED_ROLE_IDS: <@&${r}> is the @everyone role, which the filing check never matches. Name a role members are given.`);
        else ok(roleIds.has(r), `APPROVED_ROLE_IDS: the role <@&${r}> does not exist in this server.`);
      }
    }
    // The template group needs the bot token alone. A template may sit in a
    // post, which the guild's list never holds, so it is read directly.
    for (const [id, info] of token ? Object.entries(forums) : []) {
      if (!info.template) continue;
      try {
        const m = await discord.call('GET', `/channels/${info.template.channelId}/messages/${info.template.messageId}`);
        ok(!!m, `Forum <#${id}>: could not check its template message (Discord's answer had no message).`);
      } catch (e) {
        // Only a refusal (403) or a missing message (404) is a link or
        // permission fault; any other failure says nothing about the setup.
        const status = e && e.discord && e.discord.status;
        problems.push(stopped(e) ? `Forum <#${id}>'s template message: not checked (out of time or calls).`
          : status === 403 || status === 404 ? `Forum <#${id}>: its template message cannot be read (${status}). Check the link, and the bot's Read Message History where it is.`
            : `Forum <#${id}>: could not check its template message (${short(e)}).`);
      }
    }
  }

  // The GitHub group rests on REPOS, LOCK_REPO and the App's secrets alone.
  // Repo names are matched in any letter case, as the filing matches them,
  // so each repo is checked once.
  const filing = new Map();
  for (const r of Object.values(repos || {})) {
    if (typeof r === 'string' && REPO.test(r) && !filing.has(r.toLowerCase())) filing.set(r.toLowerCase(), r);
  }
  const lock = String(env.LOCK_REPO ?? '');
  const all = [...filing.values(), ...(REPO.test(lock) && !filing.has(lock.toLowerCase()) ? [lock] : [])];
  const gf = countedFetch(timed, GITHUB_BUDGET);
  if (!githubReady(env) || !all.length) {
    const fix = [!githubReady(env) && 'GITHUB_APP_ID or GITHUB_APP_PRIVATE_KEY', !all.length && 'REPOS'].filter(Boolean).join(' and ');
    problems.push(`The GitHub checks (install, permissions and labels) did not run: fix ${fix} above, then run the check again.`);
  }
  for (const repo of githubReady(env) ? all : []) {
    const name = shown(repo);
    // A repo the share or the deadline cannot cover is not started: its key
    // import and signing would only be refused.
    if (gf.left() < 2 || Date.now() >= deadline) {
      problems.push(`${name}: not checked (out of time or calls).`);
      continue;
    }
    let a;
    try {
      a = await installationAccess({ appId: env.GITHUB_APP_ID, privateKey: env.GITHUB_APP_PRIVATE_KEY, repo }, gf);
    } catch (e) {
      // No redirect is followed, so a renamed or moved repo answers 3xx here,
      // while filing, which follows it, still works.
      const st = e.github && e.github.status;
      problems.push(e.notInstalled ? `${name}: the GitHub App is not installed there (404). Install it on that repo.`
        : st >= 300 && st < 400 ? `${name}: GitHub says the repo has moved (${st}). Set REPOS or LOCK_REPO to its new owner/repo.`
          : stopped(e) ? `${name}: not checked (out of time or calls).` : `Could not check ${name} (${short(e)}).`);
      continue;
    }
    // The token's permissions are optional in GitHub's answer; a permission
    // not granted is left out of them.
    if (unset(a.permissions)) problems.push(`${name}: could not check the GitHub App's permissions (GitHub's answer had none).`);
    else ok(a.permissions.issues === 'write', `${name}: the GitHub App lacks Issues: Read and write. Grant it in the App's settings, then accept the new permission on the installation.`);
    // A repo named only as LOCK_REPO holds nothing but the per-post lock labels.
    if (!filing.has(repo.toLowerCase())) continue;
    try {
      const gh = githubClient(a.token, gf);
      const wanted = LABEL_DEFS.map(([n]) => n);
      const lower = new Map();
      let full = false;
      for (let page = 1; page <= LABEL_PAGES; page++) {
        const batch = await gh.call('GET', `/repos/${repo}/labels?per_page=100&page=${page}`);
        for (const l of batch) lower.set(l.name.toLowerCase(), l.name);
        full = batch.length === 100;
        // A repo holds one label per name in any letter case, so once every
        // name is found no later page can change the result.
        if (!full || wanted.every((n) => lower.has(n.toLowerCase()))) break;
      }
      // The status script matches every label exactly but accepted, which
      // it matches in any letter case.
      const absent = [];
      const renamed = [];
      for (const n of wanted) {
        const got = lower.get(n.toLowerCase());
        if (got === undefined) absent.push(`"${n}"`);
        else if (got !== n && n !== LABELS.accepted) renamed.push(`"${shown(got)}" must be named "${n}"`);
      }
      if (absent.length && full) {
        problems.push(`${name}: could not check the labels ${absent.join(', ')}: the repo has at least ${LABEL_PAGES * 100} labels, and the bot read only the first ${LABEL_PAGES * 100}.`);
      } else {
        ok(!absent.length, `${name}: the label${absent.length > 1 ? 's' : ''} ${absent.join(', ')} ${absent.length > 1 ? 'are' : 'is'} missing. Run npm run labels ${repo}.`);
      }
      ok(!renamed.length, `${name}: the label ${renamed.join(', ')}, as the bot matches names exactly. Rename it on GitHub.`);
    } catch (e) {
      problems.push(stopped(e) ? `${name}'s labels: not checked (out of time or calls).` : `Could not check ${name}'s labels (${short(e)}).`);
    }
  }
  return { problems, passed, mod: modState, probe: probed };
}

// The message lines of a check's result: `command` names who ran it,
// `daily` lists the problems, `weekly` is the Monday line.
export function setupLines({ problems, passed, kind, by }) {
  if (kind === 'weekly') {
    return [`**Weekly bot setup check:** every check passes today (${passed} checks). This line comes each Monday that every check passes. A Monday with neither this line nor a problem list means the daily setup check is not running or cannot post.`];
  }
  if (kind === 'daily') return [`**Daily bot setup check:** ${problems.length} problem(s):`, ...problems.map((p) => `- ${p}`)];
  const head = `**Bot setup check**${by ? ` (run by ${discordText(by)})` : ''}`;
  if (!problems.length) return [`${head}: every check passed (${passed} checks).`];
  return [`${head}: ${problems.length} problem(s), ${passed} checks passed.`, ...problems.map((p) => `- ${p}`)];
}
