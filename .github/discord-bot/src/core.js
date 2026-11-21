// Pure helpers shared by the Discord worker and the GitHub status script.
// No network, no globals: everything here is covered by test/core.test.mjs.

export const STATUS = {
  triaged: 'Triaged',
  inProgress: 'In progress',
  fixed: 'Fixed, next update',
  shipped: 'Shipped',
  closed: 'Closed',
};
export const STATUS_NAMES = Object.values(STATUS);

// The staff checklist forum's status tags: finer close reasons than a
// player's post.
export const CHECKLIST = {
  triaged: 'Triaged',
  inProgress: 'In progress',
  fixed: 'Fixed',
  shipped: 'Shipped',
  done: 'Done',
  wontFix: "Won't fix",
  duplicate: 'Duplicate',
};
export const CHECKLIST_NAMES = Object.values(CHECKLIST);
const CHECKLIST_FINISHED = new Set([CHECKLIST.shipped, CHECKLIST.done, CHECKLIST.wontFix, CHECKLIST.duplicate]);
// The tag an `accepted` label sets on an open issue's thread.
export const ACCEPTED = 'Accepted';

// A public status and the issue's close reason, as a checklist status.
export function checklistStatus(status, stateReason) {
  if (status === STATUS.fixed) return CHECKLIST.fixed;
  if (status !== STATUS.closed) return status;
  if (stateReason === 'not_planned') return CHECKLIST.wontFix;
  if (stateReason === 'duplicate') return CHECKLIST.duplicate;
  return CHECKLIST.done;
}

// A finished checklist status's archive key, one per close, so a reopen and
// a new close are told apart. Null while nothing is finished.
export function checklistKey(name, close) {
  return CHECKLIST_FINISHED.has(name) && close ? `${name}:${close.id}` : null;
}

export const LABELS = {
  fromDiscord: 'from-discord',
  pendingRelease: 'pending-release',
  shipped: 'shipped',
  needsInfo: 'needs-info',
  accepted: 'accepted',
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
  [LABELS.accepted, '1d76db', 'Staff plan to do this (sets the Accepted tag)'],
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
// The form pre-fills the title from the post's name, which a player typed,
// so control and direction marks go, as in names.
export function buildTitle({ repoKey, client, module, title }) {
  const mod = oneLine(module).trim() || 'General';
  return `[${repoKey}][${client}][${mod}] ${titleText(title)}`;
}

// The title as the issue gets it. The form's check uses it too, so a title
// of direction marks alone is empty.
export const titleText = (title) => oneLine(title).trim();

// Forum post name minus any [..] prefixes a player typed, for pre-filling the form.
export function cleanPostTitle(name) {
  return oneLine(name).replace(/^(\s*\[[^\]]*\])+\s*/, '').trim().slice(0, 100);
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
// and no @mentions that would notify GitHub users; an & that starts an entity
// is escaped, so a typed &#64; shows as typed and never becomes an @, and a
// URL's & is left alone so its link still works. A fenced code block keeps
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
// or of three or more tildes with the backslashes before it, a < or @, or an
// & that starts an entity.
const PROSE = new RegExp([NO_PREVIEW.source, BRACKETED_URL.source, '(\\\\*)(`+|~{3,})', '[<@]|&(?=#?\\w+;)'].join('|'), 'g');
const PUNCT = /[!-/:-?[-`{-~]/g;
// A zero-width space, written by code point so the source shows it.
const ZWSP = String.fromCharCode(0x200b);
const linkDest = (url) => url.replace(/@/g, '%40').replace(PUNCT, '\\$&');
const plain = (s) => s.replace(/&(?=#?\w+;)/g, '&amp;').replace(/</g, '&lt;').replace(/@/g, `@${ZWSP}`);
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
    return m === '&' ? '&amp;' : plain(m);
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

// Direction marks, which could reorder a line of the bot's own or of a
// quoted report.
const BIDI = /[\u061c\u200e\u200f\u202a-\u202e\u2066-\u2069]/g;
// Control, bidirectional and line-separator characters, which could reorder
// or break a line of the bot's own; a line break becomes a space.
const CONTROLS = new RegExp(`[\\u0000-\\u001f\\u007f-\\u009f]|${BIDI.source}`, 'g');
const oneLine = (s) => String(s ?? '').replace(/\r\n?|[\n\u2028\u2029]/g, ' ').replace(CONTROLS, '');

// A name inside a table cell of the bot's own: all text. Markdown marks,
// pipes and brackets are backslashed. A # or GH- before a digit is broken so
// it links no issue, a run of hex digits every six so it links no commit,
// and a URL's :// and www. so GitHub links nothing; <, @ and & go as in
// player text.
const nameText = (s) => plain(oneLine(s).replace(/[\\`*_~|[\]]/g, '\\$&').replace(/#(?=\d)/g, `#${ZWSP}`)
  .replace(/\b(GH)-(?=\d)/gi, `$1-${ZWSP}`).replace(/[0-9a-f]{6}(?=[0-9a-f])/gi, `$&${ZWSP}`)
  .replace(/:\/\//g, `:${ZWSP}//`).replace(/\b(www)\./gi, `$1${ZWSP}.`));

// A username as typed: a code span longer than any backtick run in it, and
// \| for a pipe, which a table cell needs even inside code.
function codeSpan(s) {
  const t = oneLine(s).replace(/\|/g, '\\|');
  const fence = '`'.repeat(longestRun([t]) + 1);
  const pad = /^`|`$/.test(t) ? ' ' : '';
  return `${fence}${pad}${t}${pad}${fence}`;
}

// A person as the issue shows them: the name linked to the Discord profile,
// then the username. With no id (a webhook) there is no profile: the name
// alone. Never a <@id> mention.
function personCell(p) {
  const { name, username, id } = p || {};
  const text = nameText(name || username || 'unknown');
  if (!/^\d+$/.test(String(id || ''))) return text;
  const shown = `[${text}](https://discord.com/users/${id})`;
  return username ? `${shown} (${codeSpan(username)})` : shown;
}

// The name a server shows: the nickname, else the display name, else the username.
export function personName(user, member) {
  return (member && member.nick) || (user && (user.global_name || user.username)) || 'unknown';
}

function quote(text) {
  const t = neutralize(String(text || '').replace(BIDI, '')).trim() || '(no text, see the Discord post)';
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

// The id of the message the issue was filed from, or null for an issue filed
// before the bot wrote it. Only the bot's footer counts: the line directly
// before the thread marker that ends the body, since an older body may quote
// such a line in its report.
export function parseFiledMessage(body) {
  const m = /(?:^|\n)<!-- discord-message: (\d+) -->\n<!-- discord-thread: \d+ reporter: (?:\d+|unknown) -->\s*$/.exec(lf(body));
  return m ? m[1] : null;
}

// `reporter` and `sender` are { name, username, id }, any part missing.
export function buildBody({ content, reporter, sender, threadUrl, attachments, threadId, messageId, templateLine }) {
  const lines = [
    `| Reporter | ${personCell(reporter)} |`, '| --- | --- |',
    `| Filed by | ${personCell(sender)} |`,
    `| Discord post | [Open the post](${threadUrl}) |`,
    '', '## Report', '', quote(content),
  ];
  if (attachments && attachments.length) {
    lines.push('', `${attachments.length} attachment(s) on the Discord post (open the post to see them; Discord image links expire).`);
  }
  if (templateLine) lines.push('', `Template check (advisory): ${templateLine}`);
  lines.push('');
  if (messageId) lines.push(`<!-- discord-message: ${messageId} -->`);
  lines.push(marker({ threadId, reporterId: reporter && reporter.id }));
  return lines.join('\n');
}

export function labelsFor({ type, client }) {
  const out = [LABELS.fromDiscord];
  if (type) out.push(`type: ${type.toLowerCase()}`);
  if (client) out.push(`client: ${client.toLowerCase()}`);
  return out;
}

// A post's tags other than the bot's status tags (`names`, the forum's
// status names): staff and player tags.
export function otherTags(current, available, names = STATUS_NAMES) {
  const statusNames = new Set(names.map((s) => s.toLowerCase()));
  const byId = new Map((available || []).map((t) => [t.id, t]));
  return (current || []).filter((id) => {
    const t = byId.get(id);
    return !(t && statusNames.has(t.name.toLowerCase()));
  });
}

// New applied_tags for a forum post: keep every non-status tag, swap the status.
// Discord allows at most 5 applied tags; the status tag always wins a slot.
export function nextAppliedTags(current, available, statusName, names = STATUS_NAMES) {
  const keep = otherTags(current, available, names);
  const target = (available || []).find((t) => t.name.toLowerCase() === statusName.toLowerCase());
  if (!target) return null; // forum has no such tag: caller leaves tags alone
  return [...keep.slice(0, 4), target.id];
}

// The status a post shows now (a status tag's canonical name), or null. A
// post carrying the `prefer` status tag shows it, wherever the tag sits: a
// second status tag beside it is no reason to move, or reopen, the post.
export function currentStatus(applied, available, prefer = null) {
  const byLower = new Map(Object.values(STATUS).map((s) => [s.toLowerCase(), s]));
  const byId = new Map((available || []).map((t) => [t.id, t]));
  const shown = (applied || []).map((id) => byId.get(id)).filter((t) => t && byLower.has(t.name.toLowerCase()))
    .map((t) => byLower.get(t.name.toLowerCase()));
  return prefer && shown.includes(prefer) ? prefer : (shown[0] || null);
}

const tagNamed = (available, name) => (available || []).find((t) => t.name.toLowerCase() === name.toLowerCase());
// Every tag id the forum names Accepted, in any letter case: all are the bot's.
const acceptedIds = (available) => new Set((available || []).filter((t) => t.name.toLowerCase() === ACCEPTED.toLowerCase()).map((t) => t.id));

// Whether two tag lists hold the same ids, in any order.
export const sameTags = (a, b) => a.length === b.length && a.every((id) => b.includes(id));

// The Accepted tag added to `tags` when wanted and a slot is free, or taken
// off. Nobody's tag is removed to make room for it.
export function withAccepted(tags, available, want) {
  const t = tagNamed(available, ACCEPTED);
  const ids = acceptedIds(available);
  const rest = (tags || []).filter((id) => !ids.has(id));
  if (!t) return { tags: rest, noRoom: false, noAccepted: true };
  if (!want) return { tags: rest, noRoom: false, noAccepted: false };
  if (rest.length >= 5) return { tags: rest, noRoom: true, noAccepted: false };
  return { tags: [...rest, t.id], noRoom: false, noAccepted: false };
}

// A post's whole tag list: its status, from the forum's status `names`, and
// with `accepted` true or false the Accepted tag. An Accepted tag already
// there is set aside first, so it never costs another tag its slot; the
// status is placed, then Accepted takes a free slot or waits (`noRoom`).
// `missing`: the forum has no such status tag, so the list stays as it is.
// `full`: with `dropOther` false, five other tags leave the status no slot,
// and none is dropped.
export function planTags(current, available, statusName, { names = STATUS_NAMES, accepted = false, dropOther = true } = {}) {
  const acc = tagNamed(available, ACCEPTED);
  if (!tagNamed(available, statusName)) return { tags: [...(current || [])], missing: true, full: false, noRoom: false, noAccepted: !acc };
  const accIds = acceptedIds(available);
  const base = (current || []).filter((id) => !accIds.has(id));
  const full = !dropOther && otherTags(base, available, names).length >= 5;
  const placed = full ? base : nextAppliedTags(base, available, statusName, names);
  const a = withAccepted(placed, available, accepted);
  return { tags: a.tags, missing: false, full, noRoom: a.noRoom, noAccepted: a.noAccepted };
}

// A checklist thread's name, `#<n> <title>`, cut to Discord's 100
// characters, never between the two halves of a surrogate pair.
export function threadName(n, title) {
  const s = `#${n} ${titleText(title)}`;
  if (s.length <= 100) return s;
  const high = s.charCodeAt(99) >= 0xd800 && s.charCodeAt(99) <= 0xdbff;
  return s.slice(0, high ? 99 : 100);
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
  inProgress: () => "**In progress.** A fix for this is being worked on and tested. We'll post here when it's done.",
  fixed: () => "**Fixed!** The fix will be in the next update. We'll post here when that update is out.",
  shipped: (repoFullName, tag) => `**Out now in ${repoDisplay(repoFullName, tag)}.** Update your addons, and let us know here if you still see the problem.`,
  done: () => "**Closed.** A moderator has closed this. If it's still happening for you, reply here and we'll take another look.",
  // `link` is the other report's Discord post, when there is one.
  closed: (reason, link) => {
    if (reason !== 'duplicate') return "**Not planned.** We've decided not to change this for now, so we're closing this post. Thanks for the suggestion!";
    const other = link ? `another report (${link})` : 'another report';
    return `**Duplicate.** This is the same problem as ${other}, so we'll follow it there and close this one. Thanks for reporting it!`;
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

// A Discord message link (right-click the message > Copy Message Link) -> the
// channel and the message it names, or null.
function messageLink(raw) {
  const m = /^https:\/\/(?:(?:ptb|canary)\.)?discord(?:app)?\.com\/channels\/\d+\/(\d+)\/(\d+)\/?$/.exec(String(raw || '').trim());
  return m ? { channelId: m[1], messageId: m[2] } : null;
}

// FORUMS is JSON keyed by forum channel id; each value may name the client and
// type every post there has, and the link of the forum's pinned template
// message: {"123":{"client":"Retail","type":"Bug","template":"https://discord.com/channels/1/2/3"}}. A value
// of {} means "guess from the post's tags". The older FORUM_CHANNEL_IDS (a
// comma list) still works and guesses for every forum. Broken JSON gives no
// forums, so the bot works nowhere rather than everywhere.
function forumsOf(env) {
  const out = {};
  if (env.FORUMS && String(env.FORUMS).trim()) {
    let raw;
    try { raw = JSON.parse(String(env.FORUMS)); } catch { return out; }
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return out;
    for (const [id, v] of Object.entries(raw)) {
      if (!/^\d+$/.test(id)) continue;
      const o = v && typeof v === 'object' ? v : {};
      const template = messageLink(o.template);
      // A template value that is not a message link is flagged, not dropped
      // quietly, so the moderator's reply can say the defaults were checked.
      const badTemplate = !template && String(o.template ?? '').trim() !== '';
      out[id] = { client: normClient(o.client), type: normType(o.type), template, badTemplate };
    }
    return out;
  }
  for (const id of String(env.FORUM_CHANNEL_IDS || '').split(',').map((s) => s.trim()).filter(Boolean)) {
    out[id] = { client: null, type: null, template: null, badTemplate: false };
  }
  return out;
}

// The staff checklist forum is never a player forum, even when FORUMS lists
// it by mistake: its threads get no greeting, card or filing.
export function parseForums(env) {
  const out = forumsOf(env);
  if (env.CHECKLIST_FORUM_ID) delete out[String(env.CHECKLIST_FORUM_ID).trim()];
  return out;
}

// Role ids allowed to press the send button (comma list), besides
// moderators. Empty: moderators only.
export function parseRoleIds(raw) {
  return String(raw || '').split(',').map((s) => s.trim()).filter((s) => /^\d+$/.test(s));
}

// The custom id of the send button ("send:<post>") and of the form
// ("gh:<post>:<message>[:<button message or 0>[:<queue card>]]"). Their parts
// go into API paths, so they are taken only when every part is digits.
export const SEND_BUTTON = 'send';
export function parseCustomId(id) {
  const s = String(id || '');
  let m = new RegExp(`^${SEND_BUTTON}:(\\d+)$`).exec(s);
  if (m) return { kind: 'send', threadId: m[1] };
  m = /^gh:(\d+):(\d+)(?::(\d+)(?::(\d+))?)?$/.exec(s);
  if (m) return { kind: 'form', threadId: m[1], messageId: m[2], greetingId: m[3] && m[3] !== '0' ? m[3] : '', cardId: m[4] || '' };
  return null;
}

// A URL's :// and the dot after www or discord broken, so text makes no
// link, invite or preview.
const noLinks = (s) => s.replace(/:\/\//g, `:${ZWSP}//`).replace(/\b(www|discord(?:app)?)\./gi, `$1${ZWSP}.`);

// A post or person name inside a message of the bot's own, as text: one
// line with no control or direction marks, Discord's Markdown marks
// backslashed so it cannot format or mention, and no link.
export function discordText(s) {
  return noLinks(oneLine(s).replace(/[\\*_~|>`<[\]]/g, '\\$&'));
}

// The message flag that shows no link previews: a card stays text whatever a
// name holds.
const SUPPRESS_EMBEDS = 1 << 2;

const openPost = (guildId, postId) => ({ type: 2, style: 5, label: 'Open post', url: `https://discord.com/channels/${guildId}/${postId}` });
// The card's first line: the forum and the post as Discord's own mentions, so
// Discord shows the post's current name as a link to it, and no text a player
// chose is in the line.
export const cardHead = (forumId, postId) => `**New post in <#${forumId}>:** <#${postId}>`;

// How to file a post whose message to file is gone. The right-click command
// is for moderators only, so the advice says who can use it.
export const BY_RIGHT_CLICK = 'a moderator can open the post and right-click a message › Apps › Send to GitHub.';

// The queue channel's card for a post nobody has filed: the post, who posted
// it and what kind it is, with the send button and a link. The poster is a
// mention, which opens their profile and pings no one (allowed_mentions),
// beside their username; a poster with no user id (a webhook) is named as
// text. Unknown parts are left out. The form files the post's first message,
// so a post whose first message is gone gets no send button, only the way to
// file it by hand.
export function queueCard({ guildId, forumId, postId, author, client, type, starterGone = false }) {
  const who = author && (/^\d+$/.test(String(author.id ?? '')) ? `<@${author.id}>` : discordText(author.name));
  const by = author ? `by ${who}${author.username ? ` (\`${oneLine(author.username).replace(/`/g, '')}\`)` : ''}` : '';
  const second = [by, type, client].filter(Boolean).join(' · ');
  const lines = [cardHead(forumId, postId), second,
    starterGone ? `Its first message was deleted: ${BY_RIGHT_CLICK}` : ''].filter(Boolean);
  return {
    content: lines.join('\n'),
    allowed_mentions: { parse: [] },
    flags: SUPPRESS_EMBEDS,
    components: [{ type: 1, components: [
      ...(starterGone ? [] : [{ type: 2, style: 1, label: 'Send to GitHub', custom_id: `${SEND_BUTTON}:${postId}` }]),
      openPost(guildId, postId),
    ] }],
  };
}

// The card once its post is filed. `head` is the pressed card's own first
// line as its content holds it (already escaped, so never escaped again; an
// older card names the post as text there), or cardHead for the post. A card
// an older version sent may still show a live link or a direction mark
// there, so the head goes on one line with its links broken. `by`, the
// filer, is left out when unknown.
export function filedCard({ guildId, postId, head, key, number, by }) {
  return {
    content: `~~${noLinks(oneLine(head))}~~\n**Filed as ${key} #${number}**${by ? ` by ${discordText(by)}` : ''}`,
    allowed_mentions: { parse: [] },
    flags: SUPPRESS_EMBEDS,
    components: [{ type: 1, components: [openPost(guildId, postId)] }],
  };
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
// Not an answer: a hint in ( ), inside any * marks (a bold label's hint
// copied as it is), a bare list number, or code-block marks (a template
// pasted with its ``` lines).
const isHint = (s) => /^\**\s*\(.*\)\s*\**$/.test(s) || /^\d+\.\s*$/.test(s) || /^`+\w*$/.test(s);

// Advisory check of a post against its template: for each field, "present"
// (labeled and answered), "missing" (labeled, left empty) or "unsure" (no
// label found; the player may have answered in their own words). A field
// about screenshots counts as present when the post has an attachment.
export function templateCheck(content, fields, attachments = 0) {
  const text = String(content || '');
  const lines = text.split('\n');
  // A label may carry words before the field name ("Addon Version:").
  const labels = fields.map((f) => new RegExp(`^\\W*(?:[a-z][\\w ]*\\s)?${escapeRe(f)}[^:\\n]*:\\**`, 'i'));
  // A line that two fields match ("UI version:" for "Version" and "UI
  // version") belongs to the field with the longer name.
  const owner = (l) => {
    let best = -1;
    labels.forEach((re, j) => { if (re.test(l) && (best < 0 || fields[j].length > fields[best].length)) best = j; });
    return best;
  };
  return fields.map((field, k) => {
    if (/screenshot|image|visual/i.test(field) && attachments > 0) return { field, state: 'present' };
    const at = lines.findIndex((l) => owner(l.trim()) === k);
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

// A label line: one to eight words of letters, digits, _, ', / and -; then
// optionally a ? and a ( ) group; the colon; then at most one ( ) hint, which
// may be in * marks. * bold marks may wrap the name or the whole line. Any
// other text after the colon ("Note: only in raids") makes it no label.
const LABEL_LINE = /^\**\s*([A-Za-z0-9][\w'/-]*(?:\s+[\w'/-]+){0,7})\s*\??\s*(?:\(([^()]*)\))?\s*\**\s*:\s*\**\s*(?:\**\([^()]*\)\**)?\s*$/;

// The field labels of a template message: the label lines of its first code
// block, or of the whole message when it has none. Discord shows text on a
// block's opening line unless it is one plain language word (the word
// FENCE_OPEN takes), so that text is the block's first line. A label with
// the word "optional" in its ( ) before the colon is optional. An empty list
// means the message holds no template.
export function templateLabels(content) {
  const text = String(content || '');
  const block = /```([^\n]*)\n([\s\S]*?)```/.exec(text);
  const lines = (block ? block[2] : text).split('\n');
  if (block && !FENCE_OPEN.test('```' + block[1])) lines.unshift(block[1]);
  const labels = [];
  for (const line of lines) {
    const m = LABEL_LINE.exec(line.trim());
    if (!m) continue;
    const name = m[1].trim();
    if (labels.some((x) => x.name.toLowerCase() === name.toLowerCase())) continue;
    labels.push({ name, optional: /\boptional\b/i.test(m[2] || '') });
  }
  return labels;
}

// The fields a post did not answer, as "field state". The issue's template
// line and the moderator's note both come from it, so they agree. An
// optional field is never a gap.
export function templateGaps(check, optional = []) {
  const skip = new Set(optional.map((f) => f.toLowerCase()));
  return check.filter((c) => c.state !== 'present' && !skip.has(c.field.toLowerCase())).map((c) => `${c.field} ${c.state}`);
}

// The moderator's note when the template message could not be read; the raw
// error goes to the log.
export function templateNote(err) {
  const status = (/^Discord \S+ \S+ -> (\d{3}) /.exec(String((err && err.message) || '')) || [])[1];
  if (status === '404') return "the template message was not found; check the forum's template link, so the default fields were checked";
  if (status === '403') return 'the bot may not read the template message; check its access to that post, so the default fields were checked';
  return 'the template message could not be read just now, so the default fields were checked';
}
