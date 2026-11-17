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
// and no @mentions that would notify GitHub users. A fenced code block keeps
// what the player typed, since Markdown shows it literally; only `<!--` is
// broken there, so no marker comment can form. The bot writes both fence lines
// itself, with more backticks than any run inside the block, so GitHub can
// end the block only where the bot does, whatever the player typed. All else
// is text: each backtick, and each run of three or more tildes, is
// backslashed, so GitHub shows it as typed and opens no code or fence there.
// A $ is left alone: GitHub draws $a$ as math even when escaped, and keeps
// what is inside escaped, so it costs only looks.
// Discord's no-preview link forms, [text](<url>), [text](<url> "title") and
// <url>, become explicit Markdown links. An explicit destination keeps every
// character (a bare URL would lose trailing punctuation): Markdown takes a
// backslashed punctuation mark literally, so every one is backslashed, which
// leaves the URL itself unchanged. Only @ is percent-encoded, since a mention
// escape would change it. A bare URL's link text gets the same backslashes,
// so a backtick or bracket in it cannot break the link. One pass handles
// each piece once, so a title or a link's text is never rewritten again.
const BRACKETED_URL = /<(https?:\/\/[^\s<>]+)>/;
// A link title in any of its three forms, with backslash escapes.
const TITLE = /"((?:[^"\\\n]|\\.)*)"|'((?:[^'\\\n]|\\.)*)'|\(((?:[^()\\\n]|\\.)*)\)/;
// A no-preview link's destination, with an optional title.
const NO_PREVIEW = new RegExp(`\\]\\(${BRACKETED_URL.source}(?:[ \\t]+(?:${TITLE.source}))?[ \\t]*\\)`);
// One pass over text: a no-preview link, a bracketed URL, a run of backticks
// or of three or more tildes with the backslashes before it, or a < or @.
const PROSE = new RegExp([NO_PREVIEW.source, BRACKETED_URL.source, '(\\\\*)(`+|~{3,})', '[<@]'].join('|'), 'g');
const PUNCT = /[!-/:-?[-`{-~]/g;
// A zero-width space, written by code point so the source shows it.
const ZWSP = String.fromCharCode(0x200b);
const linkDest = (url) => url.replace(/@/g, '%40').replace(PUNCT, '\\$&');
const plain = (s) => s.replace(/</g, '&lt;').replace(/@/g, `@${ZWSP}`);
const escapeEach = (s) => s.replace(/[\s\S]/g, '\\$&');
// A title keeps its text: the player's escapes are read, then its quote
// marks, backslashes and backticks are escaped, and its < and @ as anywhere
// else (a title shows the &lt; entity as <).
const linkTitle = (t) => plain(t.replace(/\\([!-/:-@[-`{-~])/g, '$1').replace(/[\\"`]/g, '\\$&'));

function neutralizeProse(text) {
  return text.replace(PROSE, (m, url, t1, t2, t3, bare, slashes, marks) => {
    if (url) {
      const title = t1 ?? t2 ?? t3;
      return title === undefined ? `](${linkDest(url)})` : `](${linkDest(url)} "${linkTitle(title)}")`;
    }
    if (bare) return `[${plain(bare.replace(PUNCT, '\\$&'))}](${linkDest(bare)})`;
    // A mark the player escaped stays as it is; the rest are escaped.
    if (marks) return slashes + (slashes.length % 2 ? marks[0] + escapeEach(marks.slice(1)) : escapeEach(marks));
    return plain(m);
  });
}

// CR and CRLF are line endings to GitHub too; one form keeps lines aligned.
const lf = (text) => String(text || '').replace(/\r\n?/g, '\n');

// A fence the bot accepts: a line that starts, with no indent, with three or
// more backticks or tildes, then at most one plain language word. Any other
// fence-like line is text, its marks escaped, so GitHub opens nothing there.
const FENCE_OPEN = /^(`{3,}|~{3,})[ \t]*([A-Za-z0-9+#.-]*)[ \t]*$/;
// Language words GitHub draws as a diagram, formula or map instead of
// showing the code; the block keeps its code and loses the word.
const DRAWN = new Set(['mermaid', 'math', 'geojson', 'topojson', 'stl']);
// GitHub reads at most this many backticks of a fence line, so a block that
// holds a run this long cannot be outrun and stays text.
const MAX_FENCE = 255;
const longestRun = (lines) => Math.max(0, ...lines.flatMap((l) => (l.match(/`+/g) || []).map((r) => r.length)));

export function neutralize(text) {
  const lines = lf(text).split('\n');
  const out = [];
  let prose = [];
  const flush = () => {
    if (prose.length) out.push(neutralizeProse(prose.join('\n')));
    prose = [];
  };
  for (let i = 0; i < lines.length; i++) {
    const open = FENCE_OPEN.exec(lines[i]);
    if (!open) {
      prose.push(lines[i]);
      continue;
    }
    // The block ends at a line of up to three spaces, then the same mark at
    // least as long, then only spaces or tabs (CommonMark), or at the end of
    // the text. Where it ends here only decides how much shows as code: the
    // fence lines written below leave GitHub no other place to end it.
    const close = new RegExp('^ {0,3}' + open[1][0] + '{' + open[1].length + ',}[ \\t]*$');
    let end = i + 1;
    while (end < lines.length && !close.test(lines[end])) end++;
    const body = lines.slice(i + 1, end);
    const longest = longestRun(body);
    if (longest >= MAX_FENCE) {
      prose.push(...lines.slice(i, end + 1));
    } else {
      flush();
      const fence = '`'.repeat(Math.max(3, longest + 1));
      const word = DRAWN.has(open[2].toLowerCase()) ? '' : open[2];
      out.push([fence + word, ...body.map((l) => l.replace(/<!--/g, `<${ZWSP}!--`)), fence].join('\n'));
    }
    i = end;
  }
  flush();
  return out.join('\n');
}

// A name sits inside a line of the bot's own, where no code block can form,
// so all of it is text.
const neutralizeInline = (text) => neutralizeProse(lf(text));

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
  lines.push(`Reported by **${neutralizeInline(reporterName)}** in [the Discord post](${threadUrl}) · client ${client}`);
  if (attachments && attachments.length) {
    lines.push('', `${attachments.length} attachment(s) on the Discord post (open the post to see them; Discord image links expire).`);
  }
  if (templateLine) lines.push('', `Template check (advisory): ${templateLine}`);
  if (sentBy) lines.push('', `_Sent from Discord by ${neutralizeInline(sentBy)}._`);
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

// Which tags count as releases. Each repo sets its own pattern
// (RELEASE_TAG_PATTERN); the default takes plain version numbers, with or
// without a v. A pre-release word never counts, whatever the pattern says.
export const DEFAULT_RELEASE_PATTERN = '^v?\\d+(\\.\\d+)*$';
const PRERELEASE = /(^|[^a-z])(alpha|beta|rc|pre)([^a-z]|$)/i;
export function isRelease(name, pattern) {
  return pattern.test(name) && !PRERELEASE.test(name);
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

// The custom id of the thread button ("send:<post>") and of the form
// ("gh:<post>:<message>[:<button message>]"). Their parts go into API paths,
// so they are taken only when every part is digits.
export const SEND_BUTTON = 'send';
export function parseCustomId(id) {
  const s = String(id || '');
  let m = new RegExp(`^${SEND_BUTTON}:(\\d+)$`).exec(s);
  if (m) return { kind: 'send', threadId: m[1] };
  m = /^gh:(\d+):(\d+)(?::(\d+))?$/.exec(s);
  if (m) return { kind: 'form', threadId: m[1], messageId: m[2], greetingId: m[3] || '' };
  return null;
}

// A Discord id's creation time in epoch ms.
export function snowflakeMs(id) {
  return Number(BigInt(id) >> 22n) + 1420070400000;
}

// The template fields each kind of post should fill, as the published help
// templates label them. TEMPLATES (JSON, same shape) replaces these.
export const DEFAULT_TEMPLATES = {
  Bug: ['Addon version', 'UI version', 'Updated with the game closed', 'What happened', 'What you expected', 'How to make it happen again', 'Screenshots'],
  Feature: ['Area', 'My idea or feedback', 'Why it matters', 'Screenshots'],
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
// Not an answer: a hint in ( ), a bare list number, or code-block marks (a
// template pasted with its ``` lines).
const isHint = (s) => /^\*?\s*\(.*\)\s*\*?$/.test(s) || /^\d+\.\s*$/.test(s) || /^`+\w*$/.test(s);

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
