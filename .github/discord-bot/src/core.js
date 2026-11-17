// Pure helpers shared by the Discord worker and the GitHub status script.
// No network, no globals: everything here is covered by test/core.test.mjs.

export const STATUS = {
  triaged: 'Triaged',
  inProgress: 'In progress',
  fixed: 'Fixed, next update',
  shipped: 'Shipped',
  closed: 'Closed',
};

export const LABELS = {
  fromDiscord: 'from-discord',
  pendingRelease: 'pending-release',
  shipped: 'shipped',
  needsInfo: 'needs-info',
};

// Every label the bot or the status workflow sets: [name, color, description].
export const LABEL_DEFS = [
  [LABELS.fromDiscord, '2da44e', 'Filed from a Discord forum post'],
  ['type: bug', 'd73a4a', 'Something is broken'],
  ['type: feature', '0075ca', 'Feature request or feedback'],
  ['client: retail', 'bfbfbf', 'Retail client'],
  ['client: forever', 'bfbfbf', 'WoW: Forever client'],
  ['client: all', 'bfbfbf', 'Both clients'],
  [LABELS.needsInfo, 'fbca04', 'Waiting on the reporter for details'],
  [LABELS.pendingRelease, 'f9a03f', 'Fixed in dev, ships with the next release tag'],
  [LABELS.shipped, '0e8a16', 'Released'],
];

export const PERMS = { administrator: 1n << 3n, manageThreads: 1n << 34n };

const CLIENTS = { retail: 'Retail', forever: 'Forever', all: 'All' };
const TYPES = { bug: 'Bug', feature: 'Feature', feedback: 'Feature', request: 'Feature' };
const own = (obj, k) => (Object.prototype.hasOwnProperty.call(obj, k) ? obj[k] : null);

// REPOS is required config: {"KE":"owner/repo", ...}. A missing or broken value
// stops the bot instead of filing into a default repo.
export function parseRepos(raw) {
  let repos;
  try { repos = JSON.parse(String(raw || '')); } catch { repos = null; }
  if (!repos || typeof repos !== 'object' || Array.isArray(repos) || !Object.keys(repos).length) {
    throw new Error('REPOS is not set: expected JSON like {"KE":"owner/repo"}');
  }
  return repos;
}

// Free text from the form -> canonical value, or null when unrecognized.
export function normClient(s) {
  return own(CLIENTS, String(s || '').trim().toLowerCase());
}
export function normType(s) {
  return own(TYPES, String(s || '').trim().toLowerCase().split(/[\s/]+/)[0]);
}
export function normRepoKey(s, repos) {
  const k = String(s || '').trim().toUpperCase();
  return Object.prototype.hasOwnProperty.call(repos, k) ? k : null;
}

// "[KE][Retail][Bags] Bank tab icons overlap" -- the shape already used by hand.
export function buildTitle({ repoKey, client, module, title }) {
  const mod = String(module || '').trim() || 'General';
  return `[${repoKey}][${client}][${mod}] ${String(title).trim()}`;
}

// Forum post name minus any [..] prefixes a player typed, for pre-filling the form.
export function cleanPostTitle(name) {
  return String(name || '').replace(/^(\s*\[[^\]]*\])+\s*/, '').trim().slice(0, 100);
}

// Guess client and type from the forum post's existing tags (names, any case).
export function guessFromTags(tagNames) {
  const names = (tagNames || []).map((n) => String(n).toLowerCase());
  const has = (re) => names.some((n) => re.test(n));
  let client = null;
  if (has(/retail/) && has(/forever/)) client = 'All';
  else if (has(/forever/)) client = 'Forever';
  else if (has(/retail/)) client = 'Retail';
  let type = null;
  if (has(/bug/)) type = 'Bug';
  else if (has(/feedback|request|feature|suggest/)) type = 'Feature';
  return { client, type };
}

// Player text goes into the issue as data: no HTML (so no fake marker comment)
// and no @mentions that would notify GitHub users. Discord's no-preview link
// forms, [text](<url>) and <url>, become explicit Markdown links before the
// escaping, so it does not break them. An explicit destination keeps every
// character (a bare URL would lose trailing punctuation); the characters that
// would end it early or be escaped are percent-encoded.
const URL_IN_BRACKETS = /<(https?:\/\/[^\s<>]+)>/g;
const linkDest = (url) => url.replace(/[()[\]@]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`);

export function neutralize(text) {
  return String(text || '')
    .replace(/\]\(<(https?:\/\/[^\s<>]+)>\)/g, (m, url) => `](${linkDest(url)})`)
    .replace(URL_IN_BRACKETS, (m, url) => `[${url.replace(/[[\]]/g, '\\$&')}](${linkDest(url)})`)
    .replace(/</g, '&lt;').replace(/@/g, '@​');
}

function quote(text) {
  const t = neutralize(text).trim() || '(no text, see the Discord post)';
  return t.split('\n').map((l) => `> ${l}`).join('\n');
}

export function marker({ threadId, reporterId }) {
  return `<!-- discord-thread: ${threadId} reporter: ${reporterId || 'unknown'} -->`;
}

// The bot writes the marker last; player text cannot hold one (neutralize), and
// the last match wins in case an older body predates that.
export function parseMarker(body) {
  const all = [...String(body || '').matchAll(/<!--\s*discord-thread:\s*(\d+)(?:\s+reporter:\s*(\d+|unknown))?\s*-->/g)];
  const m = all[all.length - 1];
  if (!m) return null;
  return { threadId: m[1], reporterId: m[2] && m[2] !== 'unknown' ? m[2] : null };
}

export function buildBody({ content, reporterName, threadUrl, client, attachments, threadId, reporterId, sentBy, templateLine }) {
  const lines = ['## Report', '', quote(content), ''];
  lines.push(`Reported by **${neutralize(reporterName)}** in [the Discord post](${threadUrl}) · client ${client}`);
  if (attachments && attachments.length) {
    lines.push('', `${attachments.length} attachment(s) on the Discord post (open the post to see them; Discord image links expire).`);
  }
  if (templateLine) lines.push('', `Template check (advisory): ${templateLine}`);
  if (sentBy) lines.push('', `_Sent from Discord by ${neutralize(sentBy)}._`);
  lines.push('', marker({ threadId, reporterId }));
  return lines.join('\n');
}

export function labelsFor({ type, client }) {
  const out = [LABELS.fromDiscord];
  if (type) out.push(`type: ${type.toLowerCase()}`);
  if (client) out.push(`client: ${client.toLowerCase()}`);
  return out;
}

// New applied_tags for a forum post: keep every non-status tag, swap the status.
// Discord allows at most 5 applied tags; the status tag always wins a slot.
export function nextAppliedTags(current, available, statusName) {
  const statusNames = new Set(Object.values(STATUS).map((s) => s.toLowerCase()));
  const byId = new Map((available || []).map((t) => [t.id, t]));
  const keep = (current || []).filter((id) => {
    const t = byId.get(id);
    return !(t && statusNames.has(t.name.toLowerCase()));
  });
  const target = (available || []).find((t) => t.name.toLowerCase() === statusName.toLowerCase());
  if (!target) return null; // forum has no such tag: caller leaves tags alone
  return [...keep.slice(0, 4), target.id];
}

// The status a post shows now (a status tag's canonical name), or null.
export function currentStatus(applied, available) {
  const byLower = new Map(Object.values(STATUS).map((s) => [s.toLowerCase(), s]));
  const byId = new Map((available || []).map((t) => [t.id, t]));
  for (const id of applied || []) {
    const t = byId.get(id);
    if (t && byLower.has(t.name.toLowerCase())) return byLower.get(t.name.toLowerCase());
  }
  return null;
}

// "owner/SomeAddon" + "v5.0.120" -> "SomeAddon v5.0.120"; a tag that does not
// start with a version number is shown as it is.
export function repoDisplay(repoFullName, tag) {
  const name = String(repoFullName).split('/').pop();
  const v = /^\d/.test(tag) ? `v${tag}` : tag;
  return `${name} ${v}`;
}

export const MESSAGES = {
  tracked: (key, n) => `Thanks! This is now tracked as ${key} #${n}. We'll post here when a fix is being tested and when it ships.`,
  inProgress: () => "Good news: a fix for this is being worked on and tested. We'll post here when it's done.",
  fixed: () => "This is fixed! The fix will be in the next update. We'll post here when that update is out.",
  shipped: (repoFullName, tag) => `The fix is out in ${repoDisplay(repoFullName, tag)}. Update your addons, and let us know here if you still see the problem.`,
  done: () => "A moderator has closed this. If it's still happening for you, reply here and we'll take another look.",
  // `link` is the other report's Discord post, when there is one.
  closed: (reason, link) => {
    if (reason !== 'duplicate') return "We've decided not to change this for now, so we're closing this post. Thanks for the suggestion!";
    const other = link ? `another report (${link})` : 'another report';
    return `This is the same problem as ${other}, so we'll follow it there and close this one. Thanks for reporting it!`;
  },
  needsInfo: (uid) => `${uid ? `<@${uid}> ` : ''}Could you add a bit more detail? A screenshot, your addon version and the steps to make it happen help a lot.`,
};

// A fetch whose every call gives up after `ms`, and that refuses to start once
// `deadline` (epoch ms) has passed, so a stalled call fails instead of hanging.
export function timedFetch(fetchImpl, ms, deadline = Infinity) {
  return async (url, init = {}) => {
    const left = Math.min(ms, deadline - Date.now());
    if (left <= 0) throw new Error(`out of time before ${init.method || 'GET'} ${url}`);
    return fetchImpl(url, { ...init, signal: AbortSignal.timeout(left) });
  };
}

// FORUMS is JSON keyed by forum channel id; each value may name the client and
// type every post there has: {"123":{"client":"Retail","type":"Bug"}}. A value
// of {} means "guess from the post's tags". The older FORUM_CHANNEL_IDS (a
// comma list) still works and guesses for every forum. Broken JSON gives no
// forums, so the bot works nowhere rather than everywhere.
export function parseForums(env) {
  const out = {};
  if (env.FORUMS && String(env.FORUMS).trim()) {
    let raw;
    try { raw = JSON.parse(String(env.FORUMS)); } catch { return out; }
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return out;
    for (const [id, v] of Object.entries(raw)) {
      if (!/^\d+$/.test(id)) continue;
      const o = v && typeof v === 'object' ? v : {};
      out[id] = { client: normClient(o.client), type: normType(o.type) };
    }
    return out;
  }
  for (const id of String(env.FORUM_CHANNEL_IDS || '').split(',').map((s) => s.trim()).filter(Boolean)) {
    out[id] = { client: null, type: null };
  }
  return out;
}

// Role ids allowed to press the thread button (comma list), besides
// moderators. Empty: moderators only.
export function parseRoleIds(raw) {
  return String(raw || '').split(',').map((s) => s.trim()).filter((s) => /^\d+$/.test(s));
}

// A Discord id's creation time in epoch ms.
export function snowflakeMs(id) {
  return Number(BigInt(id) >> 22n) + 1420070400000;
}

// The template fields each kind of post should fill. TEMPLATES (JSON, same
// shape) replaces these.
export const DEFAULT_TEMPLATES = {
  Bug: ['Version', 'Issue Details', 'Steps to Reproduce', 'Supporting Screenshots'],
  Feature: ['Category', 'Summary', 'Detailed Description'],
};

export function parseTemplates(raw) {
  if (!raw || !String(raw).trim()) return DEFAULT_TEMPLATES;
  try {
    const t = JSON.parse(String(raw));
    const ok = t && typeof t === 'object' && !Array.isArray(t)
      && Object.values(t).every((v) => Array.isArray(v) && v.every((f) => typeof f === 'string'));
    if (ok) return t;
  } catch { /* fall through */ }
  return DEFAULT_TEMPLATES;
}

const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const isHint = (s) => /^\*?\s*\(.*\)\s*\*?$/.test(s) || /^\d+\.\s*$/.test(s);

// Advisory check of a post against its template: for each field, "present"
// (labeled and answered), "missing" (labeled, left empty) or "unsure" (no
// label found; the player may have answered in their own words). A field
// about screenshots counts as present when the post has an attachment.
export function templateCheck(content, fields, attachments = 0) {
  const text = String(content || '');
  const lines = text.split('\n');
  // A label may carry words before the field name ("Addon Version:").
  const labels = fields.map((f) => new RegExp(`^\\W*(?:[a-z][\\w ]*\\s)?${escapeRe(f)}[^:\\n]*:\\**`, 'i'));
  return fields.map((field, k) => {
    if (/screenshot|image|visual/i.test(field) && attachments > 0) return { field, state: 'present' };
    const at = lines.findIndex((l) => labels[k].test(l.trim()));
    if (at < 0) return { field, state: 'unsure' };
    const rest = [lines[at].trim().replace(labels[k], '').trim()];
    for (let i = at + 1; i < lines.length; i++) {
      const l = lines[i].trim();
      if (labels.some((re) => re.test(l))) break;
      rest.push(l);
    }
    const answer = rest.filter((l) => l && !isHint(l));
    return { field, state: answer.length ? 'present' : 'missing' };
  });
}

export function templateSummary(check) {
  return check.map((c) => `${c.field} ${c.state}`).join(' · ');
}
