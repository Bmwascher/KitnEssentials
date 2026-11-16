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
// and no @mentions that would notify GitHub users.
export function neutralize(text) {
  return String(text || '').replace(/</g, '&lt;').replace(/@/g, '@​');
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

export function buildBody({ content, reporterName, threadUrl, client, attachments, threadId, reporterId, sentBy }) {
  const lines = ['## Report', '', quote(content), ''];
  lines.push(`Reported by **${neutralize(reporterName)}** in [the Discord post](${threadUrl}) · client ${client}`);
  if (attachments && attachments.length) {
    lines.push('', `${attachments.length} attachment(s) on the Discord post (open the post to see them; Discord image links expire).`);
  }
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

// Issue numbers a PR says it closes ("Fixes #12", "closes #3, resolves #4").
export function closingIssues(text) {
  const out = new Set();
  const re = /\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s*:?\s+#(\d+)/gi;
  let m;
  while ((m = re.exec(String(text || '')))) out.add(Number(m[1]));
  return [...out];
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

// "owner/SomeAddon" + "v5.0.120" -> "SomeAddon v5.0.120"; a tag that does not
// start with a version number is shown as it is.
export function repoDisplay(repoFullName, tag) {
  const name = String(repoFullName).split('/').pop();
  const v = /^\d/.test(tag) ? `v${tag}` : tag;
  return `${name} ${v}`;
}

export const MESSAGES = {
  tracked: (key, n) => `Thanks! This is now tracked as ${key} #${n}. We'll post here when a fix is being tested and when it ships.`,
  inProgress: () => 'A fix is up and being tested.',
  fixed: () => 'The fix is merged and will be in the next update.',
  shipped: (repoFullName, tag) => `The fix landed in ${repoDisplay(repoFullName, tag)}. Update the addon to get it, and reply here if it still happens.`,
  closed: (reason) => reason === 'duplicate'
    ? 'Closed as a duplicate of another report.'
    : 'Closed without a change for now.',
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
