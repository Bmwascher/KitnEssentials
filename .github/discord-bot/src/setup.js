// The bot's setup checks. The settings checks need no network access and
// come first; /bot-check, the daily setup check and the Worker's "not set up
// yet" replies use them.
import { parseRepos, parseForums, isTemplates, PERMS, packGroups, clipLine, MESSAGE_MAX, isDiscordId as digits } from './core.js';
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
