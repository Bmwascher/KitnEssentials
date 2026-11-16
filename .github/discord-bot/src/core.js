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

const CLIENTS = { retail: 'Retail', forever: 'Forever', all: 'All' };
const TYPES = { bug: 'Bug', feature: 'Feature', feedback: 'Feature', request: 'Feature' };

// Free text from the form -> canonical value, or null when unrecognised.
export function normClient(s) {
  const k = String(s || '').trim().toLowerCase();
  return CLIENTS[k] || null;
}
export function normType(s) {
  const k = String(s || '').trim().toLowerCase().split(/[\s/]+/)[0];
  return TYPES[k] || null;
}
export function normRepoKey(s, repos) {
  const k = String(s || '').trim().toUpperCase();
  return Object.prototype.hasOwnProperty.call(repos, k) ? k : null;
}

// "[AES][Retail][Bags] Bank tab icons overlap" -- the shape already used by hand.
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

function quote(text) {
  const t = String(text || '').trim() || '(no text, see the Discord post)';
  return t.split('\n').map((l) => `> ${l}`).join('\n');
}

export function marker({ threadId, reporterId }) {
  return `<!-- discord-thread: ${threadId} reporter: ${reporterId || 'unknown'} -->`;
}

export function parseMarker(body) {
  const m = /<!--\s*discord-thread:\s*(\d+)(?:\s+reporter:\s*(\d+|unknown))?\s*-->/.exec(String(body || ''));
  if (!m) return null;
  return { threadId: m[1], reporterId: m[2] && m[2] !== 'unknown' ? m[2] : null };
}

export function buildBody({ content, reporterName, threadUrl, client, attachments, threadId, reporterId, sentBy }) {
  const lines = ['## Report', '', quote(content), ''];
  lines.push(`Reported by **${reporterName}** in [the Discord post](${threadUrl}) · client ${client}`);
  if (attachments && attachments.length) {
    lines.push('', `${attachments.length} attachment(s) on the Discord post (open the post to see them; Discord image links expire).`);
  }
  if (sentBy) lines.push('', `_Sent from Discord by ${sentBy}._`);
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

export function repoDisplay(repoKey, tag) {
  const name = repoKey === 'AUI' ? 'atrocityUI' : 'atrocityEssentials';
  const v = /^v/i.test(tag) ? tag : `v${tag}`;
  return `${name} ${v}`;
}

export const MESSAGES = {
  tracked: (key, n) => `Thanks! This is now tracked as ${key} #${n}. We'll post here when a fix is being tested and when it ships.`,
  inProgress: () => 'A fix is up and being tested.',
  fixed: () => 'The fix is merged and will be in the next update.',
  shipped: (key, tag) => `The fix landed in ${repoDisplay(key, tag)}. Update the addon to get it, and reply here if it still happens.`,
  closed: (reason) => reason === 'duplicate'
    ? 'Closed as a duplicate of another report.'
    : 'Closed without a change for now.',
  needsInfo: (uid) => `${uid ? `<@${uid}> ` : ''}Could you add a bit more detail? A screenshot, your addon version and the steps to make it happen help a lot.`,
};

// Repo key ("AES"/"AUI") for a full repo name, from the configured map.
export function keyForRepo(fullName, repos) {
  const want = String(fullName).toLowerCase();
  return Object.keys(repos).find((k) => repos[k].toLowerCase() === want) || null;
}
