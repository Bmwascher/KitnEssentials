// Cloudflare Worker that answers Discord interactions over HTTP (no gateway,
// no always-on server). Two ways in, one form: the "Send to GitHub" button on
// a post's card in the staff queue channel (approved roles), or right-click a
// post > Apps > "Send to GitHub" (moderators). A press on a post already
// filed answers "Already tracked" instead of opening the form. Submitting the
// form files the issue and replies to the filed message in the post.
import {
  STATUS, MESSAGES, PERMS, packGroups, postLines, taken, oneHop, isDiscordId, THREAD_TYPES, buildTitle, fitName, buildBody, labelsFor, cleanPostTitle, personName, staffRef, titleText, statusOf,
  guessFromTags, normClient, normType, normRepoKey, parseRepos, timedFetch,
  parseForums, parseRoleIds, parseTemplates, templateCheck, templateGaps,
  templateNote, parseCustomId, templateLabels, filedCard, cardHead, BY_RIGHT_CLICK,
  parseRepoTags, repoFromTags, plainTags, usableRepoKeys,
  MOVE_BUTTON, CLIENT_NAMES, cutUnits,
  queueCard, movedTags, webhookName, avatarUrl, SELECT_MAX, isBotCopy,
} from './core.js';
import { discordClient, postGone, archivedOf } from './discord.js';
import { githubClient, installationToken, lockLabel } from './github.js';
import { scan, daily, CRONS, SEND_BUTTON, readStrict, saveIssueRecord, hasButton, countedFetch, AWAY_START, MOVED_HERE, isReceipt } from './scan.js';
import { setupCheck, setupLines, fitLines, NEEDED_BITS, configProblems } from './setup.js';

export const COMMAND_NAME = 'Send to GitHub';
export const CHECK_COMMAND = 'bot-check';
export const MOVE_COMMAND = 'Move post';
// The setup check ends by 20 s from the request's arrival and its posts by
// 22 s, leaving the private reply its own time before REPORT_BY_MS. The
// posts have their own share of calls, so a run stays within 50 requests.
const CHECK_BY_MS = 20000;
const CHECK_POSTS_BY_MS = 22000;
const POST_SHARE = 5;
const EPHEMERAL = 64;
// Discord refuses a message longer than this.
const MAX_REPLY = 2000;
// Discord wants the first answer within 3 s, counted from the moment the
// request arrives: a press's check for an existing filing (KV reads
// included) ends by 1.5 s, and the form's lookups by 2.6 s; a lookup gets at
// most 1.5 s.
const FORM_LOOKUP_MS = 1500;
const PRESS_BY_MS = 1500;
const FORM_BY_MS = 2600;
// Workers cancel waitUntil work about 30 s after the response, so every phase
// has a hard end, counted from the start: the filing's calls by 15 s, a
// re-check of an unknown create by 20 s, the report to the moderator by 25 s,
// the lock's release by 29 s.
const FILE_BUDGET_MS = 15000;
const RECHECK_BY_MS = 20000;
const REPORT_BY_MS = 25000;
const RELEASE_BY_MS = 29000;
const CALL_MS = 8000;
const TAIL_MS = 5000;
// Every KV wait has an end: a read or write is waited on for at most 1.5 s,
// so a slow one cannot hold the filing, its lock, the player's receipt or
// the moderator's result. After a create, the Triaged tag ends by 18 s and
// the player's receipt has its own end at 23 s, so a slow tag write cannot
// use up the receipt's time. The queue card is marked after the lock's
// release, by the release's own end.
const KV_MS = 1500;
const TAG_BY_MS = 18000;
const TRACKED_BY_MS = 23000;
// The forum's pinned template is advice only: its read gets at most 2 s, and
// fileIssue ends it a full call's time before the filing's deadline.
const TEMPLATE_MS = 2000;
// A move's phases, counted from the request's arrival: every call before the
// new post ends by 12 s (one still running then is stopped), the new post's
// create by 18 s, and each step after it by 23 s; the reply and the lock's
// release keep the filing's ends.
const MOVE_PREP_BY_MS = 12000;
const MOVE_CREATE_BY_MS = 18000;
const MOVE_REST_BY_MS = 23000;
// The downloads end this long before the prep phase: the re-read's time.
const MOVE_REREAD_MS = 2000;
// Discord takes 20 MiB per file and 25 MiB per request; 1 MiB of the request
// is left for the message and the multipart framing.
const COPY_FILE_MAX = 20 * 1024 * 1024;
const COPY_MAX_BYTES = 24 * 1024 * 1024;
const NOTHING_TO_COPY = '(The first message had nothing the bot can copy.)';
// Signed requests older than this are refused (a captured one cannot be replayed later).
const MAX_AGE_S = 300;

const json = (obj, status = 200) => new Response(JSON.stringify(obj), {
  status, headers: { 'Content-Type': 'application/json' },
});
const reply = (content) => json({ type: 4, data: { content, flags: EPHEMERAL } });
// The bot works nowhere until its config holds: the reply names the first
// problem. Every caller has checked the server first (`elsewhere`, or
// /bot-check's own check) and then the caller, so only staff of this server
// see it.
const notSetUp = (env) => reply(`The bot is not set up yet: ${configProblems(env, { bindings: false })[0]}`);
// The config, or null when it cannot be read (a broken REPOS throws), so
// every entry point answers with the problem instead of failing.
const configOr = (env) => {
  try { return config(env); } catch { return null; }
};

function hexToBytes(hex) {
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.substr(i * 2, 2), 16);
  return out;
}

export async function verifyDiscord(publicKeyHex, signatureHex, timestamp, body, nowS = Math.floor(Date.now() / 1000)) {
  if (!signatureHex || !timestamp) return false;
  if (!(Math.abs(nowS - Number(timestamp)) <= MAX_AGE_S)) return false;
  try {
    const key = await crypto.subtle.importKey('raw', hexToBytes(publicKeyHex), { name: 'Ed25519' }, false, ['verify']);
    return await crypto.subtle.verify('Ed25519', key, hexToBytes(signatureHex), new TextEncoder().encode(timestamp + body));
  } catch {
    return false;
  }
}

// Fails closed: with no forum ids set the command works nowhere, so a bot that
// ends up in another server cannot file into these repos.
export function config(env) {
  const repos = parseRepos(env.REPOS);
  const forumInfo = parseForums(env);
  return {
    repos, forums: Object.keys(forumInfo), forumInfo,
    roles: parseRoleIds(env.APPROVED_ROLE_IDS), templates: parseTemplates(env.TEMPLATES),
    queue: env.QUEUE_CHANNEL_ID || '',
    rename: String(env.RENAME_POSTS ?? '').trim() !== '0',
    // A mapping to a key REPOS no longer holds names no repo: its tag is read
    // as a plain tag again, for the client, the type and the move, and setup
    // names the mapping.
    repoTags: Object.fromEntries(Object.entries(parseRepoTags(env.REPO_TAGS)).filter(([, k]) => Object.hasOwn(repos, k))),
    // Every filing of a post takes its lock in this one repo, whichever repo
    // it goes to. It is named, never taken from the order of REPOS, so
    // reordering REPOS cannot move it; with one repo it is that repo.
    lockRepo: env.LOCK_REPO || (Object.keys(repos).length === 1 ? Object.values(repos)[0] : ''),
  };
}

// A write whose result is unknown: anything but a definite refusal (GitHub
// answered 4xx) or a call that was never sent (out of time before it). A lost
// connection on Workers is a plain Error, a timeout an AbortError or
// TimeoutError, a cut-off success a SyntaxError; GitHub's 5xx can come after
// the write was applied.
export function unknownOutcome(e) {
  const msg = String((e && e.message) || '');
  return !/^GitHub \S+ \S+ -> 4\d\d /.test(msg) && !/^out of time before /.test(msg);
}

function canUse(member) {
  if (!member || member.permissions === undefined) return false;
  const p = BigInt(member.permissions);
  return (p & PERMS.administrator) !== 0n || (p & PERMS.manageThreads) !== 0n;
}

const hasRole = (member, roles) => !!member && (member.roles || []).some((r) => roles.includes(r));
// Moderators (right-click) or an approved role (the button) may send.
const allowed = (member, cfg) => canUse(member) || hasRole(member, cfg.roles);
const NOT_ALLOWED = 'Only moderators and approved roles can send posts to GitHub.';
const BAD_IDS = 'Nothing was created: this button or form is not valid. Press the button or right-click the post to try again.';
const NOT_ALLOWED_MOVE = 'Only moderators and approved roles can move posts.';
const BAD_MOVE_IDS = 'Nothing was moved: this button or form is not valid. Press the button or right-click the post to try again.';
// A card button pressed by a member who is not a moderator while no role is
// approved: the right-click command `cmd` is for moderators.
const noRoles = (cmd) => `The button is not set up yet: APPROVED_ROLE_IDS is empty. A moderator can open the post and right-click a message › Apps › ${cmd}.`;
// A forum's tags from the server's channel list. FORUMS is outside data: a
// forum it names may be gone, or not be a forum.
const tagsIn = (channels, id) => (channels.find((c) => c.id === id) || {}).available_tags || [];
// The forums of FORUMS a post in `from` can move to: those this server's
// channel list has as forums. FORUMS may name a channel of another server,
// where a copy would publish the player's post, or one that is not a forum.
const moveTargets = (cfg, channels, from) => cfg.forums.filter((id) => id !== from && channels.some((c) => c.id === id && c.type === 15));

// A modal field: a Label (type 18) holding a text input or a select.
const label = (text, component, description) => ({ type: 18, label: text, ...(description ? { description } : {}), component });
const input = (id, text, value, opts = {}) => label(text, {
  type: 4, custom_id: id, style: opts.paragraph ? 2 : 1,
  required: opts.required !== false, max_length: opts.max || 100,
  value: value || undefined, placeholder: opts.placeholder,
});
// A select of [value, label] choices, `chosen` pre-selected when it is one.
const select = (id, text, choices, chosen, { required = true, description } = {}) => label(text, {
  type: 3, custom_id: id, required,
  options: choices.map(([value, name]) => ({ value, label: name, ...(value === chosen ? { default: true } : {}) })),
}, description);

// A modal's answers by field id: a Label's text input (`value`) or select
// (its first value, none when left empty), or an Action Row's text input, as
// a form opened before this version sends it.
function modalValues(data) {
  const out = {};
  for (const row of data.components || []) {
    for (const c of row.component ? [row.component] : row.components || []) out[c.custom_id] = c.values ? c.values[0] : c.value;
  }
  return out;
}

// The repo Send to GitHub's form pre-selects: the one key the post's repo
// tags give, else the only repo. None otherwise, so staff must pick.
// A tag's key the dropdown does not offer pre-selects nothing.
function repoChoice(keys, cfg, tagNames) {
  const tagged = normRepoKey(repoFromTags(tagNames, cfg.repoTags), cfg.repos);
  return keys.includes(tagged) ? tagged : keys.length === 1 ? keys[0] : null;
}

// The post a form is for: the interaction's own channel when it is the post
// with its parent and tags, else read. A card press brings no post with it,
// so a failed read there says why the form cannot open.
async function formPost(interaction, discord, threadId) {
  let ch = interaction.channel && interaction.channel.id === threadId ? interaction.channel : {};
  if (!ch.parent_id || !ch.applied_tags) {
    try {
      ch = await discord.getChannel(threadId);
    } catch (e) {
      if (!ch.parent_id) {
        return { answer: reply(statusOf(e) === 404 ? 'This post no longer exists.' : 'Could not read the post just now. Press the button again.') };
      }
    }
  }
  return { ch };
}

// The Move form, answered within FORM_BY_MS as openForm is. The forums it
// offers, and their names, come from the server's channel list, so its
// failure opens no form. It reads no record: the move's job does, and
// refuses a post already filed or moved. `cfg` is the config its route
// read, naming at least one player forum.
async function openMoveForm(interaction, env, deps, cfg, { threadId, cardId = '', deadline }) {
  const discord = discordClient(env.DISCORD_BOT_TOKEN, timedFetch(deps.fetch, FORM_LOOKUP_MS, deadline));
  const post = await formPost(interaction, discord, threadId);
  if (post.answer) return post.answer;
  const { ch } = post;
  if (!cfg.forums.includes(ch.parent_id)) return reply('This only works on posts in the forums the bot is set up for.');
  const channels = await discord.call('GET', `/guilds/${interaction.guild_id}/channels`).catch(() => null);
  if (!channels) return reply('Could not read the forums just now. Try again.');
  const others = moveTargets(cfg, channels, ch.parent_id);
  if (!others.length) return reply('There is no other forum to move this post to.');
  const label = (id) => cutUnits(`#${channels.find((c) => c.id === id).name}`, 100);
  // Two forums can share a name, or two long names their first 100
  // characters: such a label carries the forum's id, so staff can tell
  // which forum they pick.
  const shown = (id) => (others.filter((o) => label(o) === label(id)).length > 1 ? `${cutUnits(label(id), 100 - id.length - 3)} (${id})` : label(id));
  // A post read from the interaction alone may carry no tag list.
  const tagIds = ch.applied_tags || [];
  const tagNames = tagsIn(channels, ch.parent_id).filter((t) => tagIds.includes(t.id)).map((t) => t.name);
  return json({
    type: 9,
    data: {
      custom_id: `mv:${threadId}${cardId ? `:${cardId}` : ''}`,
      title: 'Move post',
      components: [
        select('forum', 'Move to', others.map((id) => [id, shown(id)]), others.length === 1 ? others[0] : null),
        select('client', 'Client', CLIENT_NAMES.map((c) => [c, c]), cfg.forumInfo[ch.parent_id].client || guessFromTags(plainTags(tagNames, cfg.repoTags)).client,
          { required: false, description: 'Used for a forum with no client of its own' }),
      ],
    },
  });
}

async function openForm(interaction, env, deps, { threadId, messageId, greetingId = '', cardId = '', deadline = Date.now() + FORM_LOOKUP_MS }) {
  const cfg = configOr(env);
  if (!cfg || !cfg.forums.length) return notSetUp(env);
  const discord = discordClient(env.DISCORD_BOT_TOKEN, timedFetch(deps.fetch, FORM_LOOKUP_MS, deadline));
  const post = await formPost(interaction, discord, threadId);
  if (post.answer) return post.answer;
  const { ch } = post;
  if (!cfg.forums.includes(ch.parent_id)) {
    return reply('This only works on posts in the forums the bot is set up for.');
  }

  // Pre-fill client and type from the forum's own settings, else from the
  // post's tags, and the repo from its repo tag; a slow or failed lookup
  // just leaves those fields blank.
  let guess = { ...cfg.forumInfo[ch.parent_id] };
  let tagNames = [];
  const keys = usableRepoKeys(cfg.repos);
  if (!guess.client || !guess.type || (keys.length > 1 && Object.keys(cfg.repoTags).length)) {
    try {
      const forum = await discord.getChannel(ch.parent_id);
      tagNames = (forum.available_tags || []).filter((t) => (ch.applied_tags || []).includes(t.id)).map((t) => t.name);
      const fromTags = guessFromTags(plainTags(tagNames, cfg.repoTags));
      guess = { client: guess.client || fromTags.client, type: guess.type || fromTags.type };
    } catch { /* keep the blanks */ }
  }

  return json({
    type: 9,
    data: {
      custom_id: `gh:${threadId}:${messageId}${greetingId || cardId ? `:${greetingId || '0'}` : ''}${cardId ? `:${cardId}` : ''}`,
      title: 'Send to GitHub',
      components: [
        select('repo', 'Repo', keys.map((k) => [k, k]), repoChoice(keys, cfg, tagNames)),
        input('client', 'Client (Retail, Forever or All)', guess.client || '', { max: 10 }),
        input('type', 'Type (Bug or Feature)', guess.type || '', { max: 10 }),
        input('module', 'Module (e.g. Bags, Damage Meter, Installer)', '', { max: 40 }),
        input('title', 'Issue title', cleanPostTitle(ch.name), { max: 100 }),
      ],
    },
  });
}

// The fields to check a post against: the labels of its forum's pinned
// template message when FORUMS names one and it can be read, else the
// TEMPLATES setting or the defaults for the post's type. Read at each filing
// (a few a day) and never stored, so an edited template counts at once and no
// KV write is spent. `note` tells the moderator why the fallback was used.
async function templateFields(cfg, forumId, type, env, deps, deadline, log) {
  const fallback = { fields: cfg.templates[type] || [], optional: [] };
  const info = cfg.forumInfo[forumId] || {};
  if (info.badTemplate) return { ...fallback, note: "the forum's template link is not a message link, so the default fields were checked" };
  const link = info.template;
  if (!link) return { ...fallback, note: '' };
  try {
    const discord = discordClient(env.DISCORD_BOT_TOKEN, timedFetch(deps.fetch, TEMPLATE_MS, deadline));
    const msg = await discord.call('GET', `/channels/${link.channelId}/messages/${link.messageId}`);
    const labels = templateLabels(msg && msg.content);
    if (labels.length) {
      return { fields: labels.map((l) => l.name), optional: labels.filter((l) => l.optional).map((l) => l.name), note: '' };
    }
    return { ...fallback, note: "the forum's pinned template has no labels, so the default fields were checked" };
  } catch (e) {
    log(`template read failed: ${e.message}`);
    return { ...fallback, note: templateNote(e) };
  }
}

// Where an issue is now: reading a transferred issue follows GitHub's
// redirect, so its repo comes from the answer.
function whereIs(issue, fallbackRepo) {
  const m = /\/repos\/([^/]+\/[^/]+)$/.exec(String(issue.repository_url || ''));
  return { repo: m ? m[1] : fallbackRepo, number: issue.number };
}
// Repo names compare without case: GitHub answers in its own casing, which a
// REPOS entry may not match.
const sameRepo = (a, b) => String(a).toLowerCase() === String(b).toLowerCase();
const keyOf = (cfg, repo) => Object.keys(cfg.repos).find((k) => sameRepo(cfg.repos[k], repo)) || repo;
// The status the client kept; an error no call answered with a status (a
// 2xx body that is not JSON, whose parser error quotes it, or out of time)
// shows its own text, never a status read from it.
const httpStatus = (e) => (statusOf(e) ? String(statusOf(e)) : e.message.slice(0, 120));
// A call Discord or GitHub refused (4xx), so it was never applied.
const refusal4xx = (e) => statusOf(e) >= 400 && statusOf(e) < 500;

// The one rule for a post's saved issue, shared by the press and the filing.
// It is read with a token for its own repo, the token and the read failing
// apart: `issue` when live; `gone` only on the issue read's own 410
// (deleted); anything else is `unclear`, with why, since a 404 is also what
// an issue the app can no longer see answers, and a failed token says
// nothing about the issue.
async function readSaved(saved, tokenFor, f) {
  let gh;
  try {
    gh = githubClient(await tokenFor(saved.repo), f);
  } catch (e) {
    return { unclear: `no access: ${httpStatus(e)}` };
  }
  try {
    return { issue: await gh.getIssue(saved.repo, saved.number) };
  } catch (e) {
    if (statusOf(e) === 410) return { gone: true };
    return { unclear: httpStatus(e), notFound: statusOf(e) === 404 };
  }
}

// The post's marker searched in every given repo at once, so the wait is the
// slowest repo's, not their sum. The first match in the given order wins; a
// failure in any repo throws, naming it.
async function searchRepos(repos, postId, tokenFor, f) {
  const found = await Promise.all(repos.map(async (r) => {
    try {
      return await githubClient(await tokenFor(r), f).findByThread(r, postId);
    } catch (e) {
      throw new Error(`could not check ${r} for this post (${e.message.slice(0, 200)}). Try again.`);
    }
  }));
  const at = found.findIndex(Boolean);
  return at < 0 ? null : { issue: found[at], repo: repos[at] };
}

// A write waited on for at most `ms`; past that it is reported as not
// confirmed, and what follows goes on.
function within(ms, p) {
  let timer;
  return Promise.race([p, new Promise((_, no) => { timer = setTimeout(() => no(new Error(`no answer in ${ms} ms`)), ms); })])
    .finally(() => clearTimeout(timer));
}

// An old greeting still showing the post's send button: deleted once a new
// reply replaces it, else (or when the delete fails) only its button goes. One
// that no longer shows it, such as an earlier filing's receipt, is left alone.
async function retireButton(discord, threadId, id, replaced) {
  let msg;
  try {
    msg = await discord.getMessage(threadId, id);
  } catch (e) {
    return / -> 404 /.test(e.message) ? [] : [`the old button was not removed: ${e.message.slice(0, 200)}`];
  }
  if (!hasButton(msg, threadId)) return [];
  if (replaced) {
    try {
      await discord.call('DELETE', `/channels/${threadId}/messages/${id}`);
      return [];
    } catch { /* strip the button instead */ }
  }
  try {
    await discord.call('PATCH', `/channels/${threadId}/messages/${id}`, { components: [] });
    return [];
  } catch (e) {
    return [`the old button was not removed: ${e.message.slice(0, 200)}`];
  }
}

// "Now tracked" as a reply to the filed message, which pings its author. A
// reply Discord refuses as a reply goes once more plain (`send`), and the
// log says so. Only a refusal (4xx) means no message was posted: then the
// greeting becomes the note. After any other failure the reply may exist,
// and a second receipt would repeat it; the same holds for that edit. A
// buttonless greeting is never deleted, and never edited when the reply
// works. A moved post's copy was posted by the bot's webhook, so a reply to
// it pings no one: its reporter (`ping`) is mentioned and pinged, and a plain
// message still pings them.
async function tellTracked(discord, log, { threadId, messageId, text, old, greeting, ping = null }) {
  try {
    const sent = await discord.send(threadId, ping ? `<@${ping}> ${text}` : text, ping ? [ping] : [], { replyTo: messageId });
    if (sent && sent.replyRefused) log(`post ${threadId}: Discord refused the reply; the note went out plain, ${ping ? 'its mention still pinging the reporter' : 'with no ping'}`);
  } catch (e) {
    if (!refusal4xx(e)) return [`note in the post may not have been sent: ${e.message.slice(0, 300)}`];
    if (!greeting) return [`note in the post not sent: ${e.message.slice(0, 300)}`];
    try {
      await discord.call('PATCH', `/channels/${threadId}/messages/${greeting}`, { content: text, components: [], allowed_mentions: { parse: [] } });
      return [];
    } catch (e2) {
      return [`note in the post ${refusal4xx(e2) ? 'not sent' : 'may not have been sent'}: ${e2.message.slice(0, 300)}`];
    }
  }
  return old ? retireButton(discord, threadId, old, true) : [];
}

// The post's queue card once the post is filed: struck through, "Filed as",
// only the Open post link. It goes after the lock's release; a failed edit
// is logged, and a press on the card later answers "Already tracked" and
// marks it.
async function markCard(discord, cfg, log, { cardId, guildId, postId, head, key, number, by }) {
  if (!cardId || !cfg.queue) return;
  await discord.call('PATCH', `/channels/${cfg.queue}/messages/${cardId}`, filedCard({ guildId, postId, head, key, number, by }))
    .catch((e) => log(`queue card ${cardId} not updated: ${e.message.slice(0, 200)}`));
}

// The post named as its issue, last, beside the card: a failure is logged,
// since the moderator's reply has already been tried. The post is read just before the
// write, so a name changed during the filing is seen. Discord changes no
// name on an archived thread unless the same request opens it. A write
// Discord answered 2xx is done, even when its body could not be read.
async function renamePost(discord, log, threadId, name) {
  try {
    const post = await discord.getChannel(threadId);
    if (post.name !== name) {
      await discord.call('PATCH', `/channels/${threadId}`, archivedOf(post) ? { name, archived: false } : { name })
        .catch((e) => { if (!taken(e)) throw e; });
    }
  } catch (e) {
    log(`post ${threadId} rename failed: ${e.message.slice(0, 200)}`);
  }
}

// A send ends within 30 s, and GitHub times out a request after 10 s. GitHub
// does not say whether a create it timed out can still be applied later, so
// the hour is a wide margin past both, not a proof. A newer lock may belong
// to a running send, so the advice never frees it.
const clearAdvice = (threadId, lockRepo, again = 'send') => `delete the label ${lockLabel(threadId)} in ${lockRepo}, but only if the time in its description is more than an hour ago or it shows no time. A send ends within 30 seconds and GitHub times out a request after 10 seconds, so the hour is a wide margin past both. Then ${again} the post again.`;

// A saved issue that answers 404 cannot be told from one the app can no
// longer see (a transfer out of reach, lost access), so nothing goes ahead.
// The way out clears only the post's filing association: its greeting and
// card ids stay.
function couldNotCheck(cfg, saved, postId, why, done) {
  const key = keyOf(cfg, saved.repo);
  const what = key !== saved.repo ? `${key} #${saved.number} in ${saved.repo}` : `${saved.repo} #${saved.number}`;
  return `Could not check ${what} (${why}): it may be gone, or the app may have lost access there. ${done} If it is gone, a bot admin can clear this post's filing record (the KV key issue:${postId}, or the "issue" field of thread:${postId} for a post filed before this version), and the post can then be sent again.`;
}

// A post's four records, read side by side and waited on for at most `ms`:
// the scan's, the filing's, and the two a move writes. `saved` is the issue
// the post was filed as: the Worker's record, or an older scan record that
// kept it beside the greeting.
async function postRecords(kv, id, ms) {
  const [thread, issue, movedFrom, movedTo] = await within(ms, Promise.all(['thread', 'issue', 'movedfrom', 'movedto'].map((p) => readStrict(kv, `${p}:${id}`))));
  return { thread, saved: issue || (thread && thread.issue) || null, movedFrom, movedTo };
}

// This bot's own messages among a post's last 100 that say what became of
// it: `away`, the new post's link in its move note, and, with `receipts`,
// `receipt`, its "now tracked" reply; each null when absent. The bot's user
// is read only when a message starts as one asked for: the filing asks for
// the note alone, so a player's message with the reply's text adds no call
// that could fail it. The move posts its note before it locks the post, so
// the note holds while KV does not show the movedto: record (not yet, or
// never, when its save failed); the reply says the post was filed when
// neither its filing record nor the from-discord label finds its issue.
// Another bot's text proves nothing.
async function ownNotes(discord, threadId, { receipts = false } = {}) {
  const isAway = (m) => String(m.content || '').startsWith(AWAY_START);
  const said = (await discord.call('GET', `/channels/${threadId}/messages?limit=100`))
    .filter((m) => isAway(m) || (receipts && isReceipt(m)));
  const me = said.length ? (await discord.me()).id : null;
  const mine = said.filter((m) => m.author.id === me);
  const note = mine.find(isAway);
  return { away: note ? note.content.slice(AWAY_START.length).split(' ')[0] : null, receipt: mine.find(isReceipt) || null };
}

// A press on a post already filed answers "Already tracked" at once, and the
// pressed message stops offering the button: a queue card becomes its filed
// form, an old greeting loses its button. The saved record names the issue;
// with none, or when its issue was deleted, every configured repo is
// searched for the post's marker, since a filing's record can be missing
// while its issue exists. Discord wants an answer within 3 s, so every wait
// here, KV included, ends by PRESS_BY_MS from the request's arrival; the
// form opens only after a check that finished and found nothing, and any
// other end asks for another press. Returns the reply, or null to open the form.
async function pressCheck(interaction, env, deps, cfg, postId, t0, ctx) {
  const log = deps.log || console.error;
  const { pressMs = PRESS_BY_MS } = deps; // tests shorten it
  const end = t0 + pressMs;
  const f = timedFetch(deps.fetch, pressMs, end);
  const wait = (p) => within(Math.max(0, end - Date.now()), p);
  const tokenFor = (repo) => (deps.installationToken || installationToken)({ appId: env.GITHUB_APP_ID, privateKey: env.GITHUB_APP_PRIVATE_KEY, repo }, f);
  const again = reply('Could not check whether this post is already on GitHub. Press the button again.');
  let saved;
  try {
    const filed = await wait(readStrict(env.STATE, `issue:${postId}`));
    const rec = filed ? null : await wait(readStrict(env.STATE, `thread:${postId}`));
    saved = filed || (rec && rec.issue) || null;
  } catch (e) {
    log(`press check failed after ${Date.now() - t0} ms: ${e.message.slice(0, 200)}`);
    return again;
  }
  let issue = null;
  let foundIn = null;
  let fromSaved = false;
  // Getting a token signs a key, so it waits under the same deadline.
  const timedToken = (repo) => wait(tokenFor(repo));
  try {
    if (saved) {
      const r = await readSaved(saved, timedToken, f);
      if (r.issue) {
        issue = r.issue;
        foundIn = saved.repo;
        fromSaved = true;
      } else if (r.notFound) {
        return reply(couldNotCheck(cfg, saved, postId, '404', 'Nothing was opened.'));
      } else if (!r.gone) {
        log(`press check failed after ${Date.now() - t0} ms: ${r.unclear}`);
        return again;
      }
    }
    if (!issue) {
      const hit = await searchRepos(Object.values(cfg.repos), postId, timedToken, f);
      if (hit) ({ issue, repo: foundIn } = hit);
    }
  } catch (e) {
    log(`press check failed after ${Date.now() - t0} ms: ${e.message.slice(0, 200)}`);
    return again;
  }
  if (!issue) return null;
  const where = whereIs(issue, foundIn);
  const key = keyOf(cfg, where.repo);
  // The filer is the record's only for the issue the record names: a search
  // match after that issue was deleted is another filing.
  const by = fromSaved ? saved.by || null : null;
  const pressed = interaction.message || {};
  const edit = interaction.channel_id === postId
    ? { components: [] }
    : filedCard({ guildId: interaction.guild_id, postId, head: String(pressed.content || '').split('\n')[0], key, number: where.number, by });
  const discord = discordClient(env.DISCORD_BOT_TOKEN, timedFetch(deps.fetch, CALL_MS));
  ctx.waitUntil(discord.call('PATCH', `/channels/${interaction.channel_id}/messages/${pressed.id}`, edit)
    .catch((e) => log(`pressed message not updated: ${e.message.slice(0, 200)}`)));
  return reply(`Already tracked as ${key} #${where.number}: ${issue.html_url}`);
}

// The private reply that replaces Discord's "thinking...": cut to Discord's
// length, and ended by REPORT_BY_MS from the request's arrival.
const followupFor = (interaction, deps, log, t0) => async (text) => {
  const content = text.length > MAX_REPLY ? `${text.slice(0, MAX_REPLY - 1)}…` : text;
  try {
    const res = await timedFetch(deps.fetch, TAIL_MS, t0 + REPORT_BY_MS)(
      `https://discord.com/api/v10/webhooks/${interaction.application_id}/${interaction.token}/messages/@original`,
      { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ content, allowed_mentions: { parse: [] } }) },
    );
    // The request's URL holds the interaction's token, and an answer may
    // echo it, so only the status and the failure's kind are logged.
    if (!res.ok) log(`followup failed: ${res.status}`);
  } catch (e) {
    log(`followup failed: ${/^out of time /.test(String(e.message)) ? 'out of time' : e.name}`);
  }
};

// A post to the moderator channel that says whether it was taken (`taken`).
const modPost = (discord, mod, onFail) => async (text) => {
  try {
    await discord.call('POST', `/channels/${mod}/messages`, { content: text, allowed_mentions: { parse: [] } });
    return true;
  } catch (e) {
    if (taken(e)) return true;
    onFail(e, text);
    return false;
  }
};

// The private result: its head first, then as many whole lines as fit
// Discord's length, the last saying how many more there are.
export function privateText(head, lines) {
  const whole = lines.length ? `${head}\n\n${lines.join('\n')}` : head;
  if (whole.length <= MAX_REPLY) return whole;
  // It does not fit: a line is kept only if the notice for the lines after
  // it still fits beside it.
  const notice = (n) => `\n…and ${n} more line(s): fix these, then run /bot-check again.`;
  let text = head;
  for (let i = 0; i < lines.length; i++) {
    const next = `${text}${i ? '\n' : '\n\n'}${lines[i]}`;
    if (next.length + notice(lines.length - i - 1).length > MAX_REPLY) return `${text}${notice(lines.length - i)}`;
    text = next;
  }
  return text;
}

// Discord's own permissions for the bot in that channel, masked to the ones
// the checks need, or null when it gave none.
const givenBits = (raw) => (raw === undefined || raw === null ? null : String(BigInt(raw) & NEEDED_BITS));

// /bot-check: the result goes to the moderator channel when the check found
// it fit to post to; whatever it did not take goes to the moderator's
// private reply, with the reason first.
export async function runCheck(interaction, env, deps, t0 = Date.now()) {
  const log = deps.log || console.error;
  const followup = followupFor(interaction, { ...deps, fetch: oneHop(deps.fetch) }, log, t0);
  const by = interaction.member.user.id;
  // A post's permissions are its forum's; any other channel is its own.
  const ch = interaction.channel || {};
  const probe = THREAD_TYPES.includes(ch.type) && ch.parent_id ? String(ch.parent_id) : String(interaction.channel_id || '');
  let result;
  try {
    result = await setupCheck(env, deps, { deadline: t0 + CHECK_BY_MS, probe });
  } catch (e) {
    // Each group catches its own failures; this is the last guard, so the
    // moderator is never left with "thinking...".
    log(`setup check stopped: ${String(e && e.message).slice(0, 200)}`);
    await followup('The setup check stopped on an error before it finished. The Worker log has it; run /bot-check again.');
    return null;
  }
  if (result.probe) {
    const given = givenBits(interaction.app_permissions);
    log(`setup check: needed permissions computed ${result.probe.bits}, app_permissions ${given ?? 'not given'}, in channel ${result.probe.id}: ${given === result.probe.bits ? 'same' : 'different'}`);
  }
  if (result.mod !== 'ok') {
    await followup(privateText(`Not posted in the moderator channel: ${result.mod}.`, setupLines({ ...result, kind: 'command', by })));
    return result;
  }
  const mod = String(env.MOD_CHANNEL_ID);
  const { lines, rest } = fitLines(setupLines({ ...result, kind: 'command', by }), POST_SHARE);
  if (rest.length) log(`check result lines past the posting share:\n${rest.join('\n')}`);
  let failure = null;
  const discord = discordClient(env.DISCORD_BOT_TOKEN, countedFetch(timedFetch(oneHop(deps.fetch), TAIL_MS, t0 + CHECK_POSTS_BY_MS), POST_SHARE));
  const took = new Set(await postLines(modPost(discord, mod, (e) => {
    failure = failure || e;
    log(`check result not posted: ${String(e.message).slice(0, 200)}`);
  }), lines));
  const missed = lines.filter((_, i) => !took.has(i));
  if (!missed.length) {
    await followup(`Posted in <#${mod}>: ${result.problems.length} problem(s).`);
    return result;
  }
  const status = failure && failure.discord ? failure.discord.status : null;
  const cause = failure ? String(failure.message).replace(/\s+/g, ' ').slice(0, 120) : 'no answer';
  // Too many requests, or Discord's own failure: a retry is the fix, not the
  // channel's settings.
  const busy = status === 429 || status >= 500;
  const line = !status ? `Moderator channel <#${mod}>: the result could not be posted (${cause}). Run /bot-check again.`
    : busy ? `Moderator channel <#${mod}>: Discord could not take the post just now (${status}). Run /bot-check again in a minute.`
      : `Moderator channel <#${mod}>: the bot's post was refused (${status}), though its permissions there look right. Check the channel's settings, then run /bot-check again.`;
  result.problems.push(line);
  // The reason goes in the head, which the length limit never cuts.
  const why = !status ? `the post could not be sent (${cause})`
    : busy ? `Discord could not take the post just now (${status})` : `the moderator channel refused the post (${status})`;
  if (took.size) {
    const groups = packGroups(lines);
    const whole = groups.filter((g) => g.every((i) => took.has(i))).length;
    await followup(privateText(`Posted in part in <#${mod}>: ${whole} of ${groups.length} messages; ${why}. The rest:`, [...missed, `- ${line}`]));
  } else {
    await followup(privateText(`Not posted in the moderator channel: ${why}.`, setupLines({ ...result, kind: 'command', by })));
  }
  return result;
}

// The daily setup check: problems go to the moderator channel every day they
// last, a passing Monday (UTC) posts the weekly line, and any other passing
// day only logs. A moderator channel the check did not find fit gets
// nothing: the lines are logged with the reason. It writes no KV.
export async function setupDaily(env, deps) {
  const log = deps.log || console.log;
  const today = new Date((deps.now || Date.now)());
  let result;
  try {
    result = await setupCheck(env, deps, { deadline: Date.now() + CHECK_BY_MS });
  } catch (e) {
    // The last guard: each group catches its own failures.
    log(`daily setup check stopped: ${String(e && e.message).slice(0, 200)}`);
    return;
  }
  if (!result.problems.length && today.getUTCDay() !== 1) {
    log(`daily setup check: every check passed (${result.passed} checks)`);
    return;
  }
  const all = setupLines({ ...result, kind: result.problems.length ? 'daily' : 'weekly' });
  if (result.mod !== 'ok') {
    log(`daily setup check not posted (${result.mod}):\n${all.join('\n')}`);
    return;
  }
  const { lines, rest } = fitLines(all, POST_SHARE);
  if (rest.length) log(`daily setup check lines past the posting share:\n${rest.join('\n')}`);
  const discord = discordClient(env.DISCORD_BOT_TOKEN, countedFetch(timedFetch(oneHop(deps.fetch), CALL_MS), POST_SHARE));
  // A message the channel did not take is logged with its lines (modPost).
  await postLines(modPost(discord, String(env.MOD_CHANNEL_ID), (e, text) => log(`could not post to the moderator channel: ${e.message}\n${text}`)), lines);
}

// One installation token per repo a run touches, each asked for once.
// `access(repo)` is a token the run cannot start without: its failure names
// the repo to try again for.
function githubAccess(env, deps, f) {
  const tokens = new Map();
  const tokenFor = (r) => {
    if (!tokens.has(r)) tokens.set(r, (deps.installationToken || installationToken)({ appId: env.GITHUB_APP_ID, privateKey: env.GITHUB_APP_PRIVATE_KEY, repo: r }, f));
    return tokens.get(r);
  };
  const access = async (r) => {
    try {
      return await tokenFor(r);
    } catch (e) {
      throw new Error(`could not get access to ${r} (${e.message.slice(0, 200)}). Try again.`);
    }
  };
  return { tokenFor, access };
}

// Runs after Discord already has its "thinking..." answer. Every call is timed,
// and every outcome, partial ones included, is reported back to the moderator.
// `t0` is the moment the request arrived; every phase's end counts from it.
export async function fileIssue(interaction, env, deps, t0 = Date.now()) {
  const cfg = config(env);
  const { threadId, messageId, greetingId, cardId } = parseCustomId(interaction.data.custom_id);
  // The moderator who sent the form, as the card and the filing record mention them.
  const filer = interaction.member && interaction.member.user ? staffRef(interaction.member.user) : null;
  const v = modalValues(interaction.data);
  const repoKey = normRepoKey(v.repo, cfg.repos);
  const client = normClient(v.client);
  const type = normType(v.type);
  const log = deps.log || console.error;
  const { callMs = CALL_MS, budgetMs = FILE_BUDGET_MS, kvMs = KV_MS } = deps; // tests shorten these
  const f = timedFetch(deps.fetch, callMs, t0 + budgetMs);
  const discord = discordClient(env.DISCORD_BOT_TOKEN, f);
  // The issue's link comes first, so a long template result is what Discord's
  // length cuts.
  const followup = followupFor(interaction, deps, log, t0);

  const repo = cfg.repos[repoKey];
  let gh;
  let ghRecheck; // the re-check of an unknown create, after the filing's budget
  let ghRelease; // the lock's release, last
  let locked = false;
  let keepLock = false;
  let creating = false;
  let issueTitle = '';
  let thread = null;
  let rec = null;
  let saved = null;
  let movedFrom = null;
  let copyId = null;
  let oldGreeting = '';
  let lockGh;
  const { tokenFor, access } = githubAccess(env, deps, f);
  // The post's queue card: the form's, else the scan's record of the post,
  // else, for a moved post, the old post's card the move recorded.
  const cardOf = (r) => cardId || (r && r.card) || (movedFrom && movedFrom.card) || '';
  // The card to mark Filed as, once the lock is released: optional work
  // never holds the lock.
  let cardAfter = null;
  let renameAfter = false;
  // The template check's result, for the moderator on either create path.
  let gaps = [];
  let tmplNote = '';
  const gapText = () => (gaps.length ? ` Template: ${gaps.join(', ')}.` : '');
  try {
    if (!cfg.lockRepo) {
      await followup("Nothing was created: the bot is not set up yet. REPOS names more than one repo, so LOCK_REPO must name the repo that holds every filing's lock.");
      return { refused: 'setup' };
    }
    const ghToken = await access(repo);
    gh = githubClient(ghToken, f);
    ghRecheck = githubClient(ghToken, timedFetch(deps.fetch, TAIL_MS, t0 + RECHECK_BY_MS));
    // One lock per post, in LOCK_REPO whichever repo the form chose: GitHub
    // makes a label once, so of two filings of one post, into the same repo
    // or different ones, only one holds it.
    const lockToken = await access(cfg.lockRepo);
    lockGh = githubClient(lockToken, f);
    ghRelease = githubClient(lockToken, timedFetch(deps.fetch, TAIL_MS, t0 + RELEASE_BY_MS));

    // The form may have been opened before the forum list changed: check again.
    thread = await discord.getChannel(threadId);
    if (!cfg.forums.includes(thread.parent_id)) {
      await followup('Nothing was created: this post is not in a forum the bot is set up for.');
      return { refused: 'forum' };
    }

    // Lock, then look once: any send that finished before the lock was
    // granted has left its issue to be found. The post's KV record, when it
    // names the issue, saves reading the whole issue list.
    const kv = env.STATE;
    // Every configured repo, the chosen one first, is searched for the
    // post's marker, so a post filed anywhere is never filed again. The issue
    // list is consistent at once, unlike search; a list that fails, in any
    // repo, stops the filing. The saved issue was checked before this.
    const already = () => searchRepos([repo, ...Object.values(cfg.repos).filter((x) => x !== repo)], threadId, tokenFor, f);
    const head = cardHead(thread.parent_id, threadId);
    // Already tracked: the record learns where the issue is now, an old
    // greeting only loses its button (no new reply replaces it), the
    // moderator is told, and then, after the lock's release, the card says
    // Filed as.
    const tracked = async (where, say, by) => {
      const key = keyOf(cfg, where.repo);
      const notes = [];
      if (!(saved && sameRepo(saved.repo, where.repo) && saved.number === where.number)) {
        try {
          await within(kvMs, saveIssueRecord(kv, threadId, { repo: where.repo, number: where.number, key, by }));
        } catch (e) { notes.push(`post record not saved: ${e.message.slice(0, 200)}`); }
      }
      if (oldGreeting) notes.push(...await retireButton(discord, threadId, oldGreeting, false));
      await followup(`${say(key)}${notes.length ? ` (${notes.join('; ')})` : ''}`);
      cardAfter = { cardId: cardOf(rec), head, key, number: where.number, by };
      return { duplicate: where.number };
    };
    try {
      locked = await lockGh.claimThread(cfg.lockRepo, threadId);
    } catch (e) {
      // The lock label may exist even though the answer was lost, and this
      // send cannot tell whose it is, so it advises no deletion: a later
      // send's busy reply gives the one safe advice.
      if (!unknownOutcome(e)) throw e;
      await followup(`Nothing was created: GitHub did not confirm the lock ${lockLabel(threadId)} in ${cfg.lockRepo} (${e.message.slice(0, 200)}). Wait a few minutes, then send the post again; if that says another send is running, follow its advice.`);
      return { error: e.message, uncertain: 'lock' };
    }
    if (!locked) {
      // The holder may be between its last search and its create, so no
      // issue shows yet: only a lock older than any send may be deleted.
      await followup(`Nothing was created: another send or move of this post is running, or one stopped partway. Wait a few minutes, then send it again. If it still says this and no issue for this post appears in any repo the bot files into, ${clearAdvice(threadId, cfg.lockRepo)}`);
      return { busy: true };
    }
    // The post's records, read under the lock side by side within KV_MS
    // (`kvMs`). One that cannot be read is not "none": it may name an issue the
    // search cannot see (one moved to a repo the bot does not file in), so
    // nothing is filed.
    let movedTo = null;
    try {
      ({ thread: rec, saved, movedFrom, movedTo } = await postRecords(kv, threadId, kvMs));
    } catch (e) {
      await followup("Nothing was created: could not read this post's saved record just now. Try again.");
      return { refused: 'record' };
    }
    // A post moved away: its record, else, on a locked post, the move's note.
    // While STATE is bound only a locked post is read, so other filings cost
    // nothing more; with none bound no record can show a move, and someone
    // may have unlocked the old post, so every post is read. The lock is read
    // as archivedOf reads the archive flag.
    const movedAway = movedTo ? `https://discord.com/channels/${interaction.guild_id}/${movedTo.to}`
      : !kv || (thread.thread_metadata && thread.thread_metadata.locked) ? (await ownNotes(discord, threadId)).away : null;
    if (movedAway) {
      await followup(`Nothing was created: this post was moved to ${movedAway}; send that one.`);
      return { refused: 'moved' };
    }
    // An old greeting: the one pressed in the post, or the record's when it
    // was written before greetings lost their button.
    oldGreeting = greetingId || (rec && rec.greeting && !rec.buttonless ? rec.greeting : '');
    // One post, one issue: the saved issue is read first, in whichever repo
    // it is. A live one refuses the filing, named where it is now, with the
    // filer kept. Only that issue's own 410 (deleted) lets the filing go on:
    // a 404 is also what an issue the app can no longer see answers (moved
    // out of reach, or lost access), in the chosen repo as anywhere, and a
    // failed token says nothing about the issue.
    if (saved) {
      const found = await readSaved(saved, tokenFor, f);
      if (found.issue) {
        // Where the issue is now decides the advice: one already in the
        // chosen repo needs no transfer, wherever the record saw it.
        const where = whereIs(found.issue, saved.repo);
        if (sameRepo(where.repo, repo)) {
          return await tracked(where, (key) => `Already tracked: ${key} #${where.number} ${found.issue.html_url}`, saved.by || null);
        }
        const said = await tracked(where, (key) => `Already tracked as ${key} #${where.number}: ${found.issue.html_url}. Nothing was created in ${repo}; to move the report, transfer the issue on GitHub.`, saved.by || null);
        return { ...said, repo: where.repo };
      }
      if (!found.gone) {
        await followup(couldNotCheck(cfg, saved, threadId, found.unclear, 'Nothing was created.'));
        return { refused: 'saved-issue' };
      }
    }
    // A search that finds nothing runs once more before the create: an issue
    // that shifted between two pages of a list while it was read is found
    // the second time.
    const existing = (await already()) || (await already());
    if (existing) {
      const where = whereIs(existing.issue, existing.repo);
      const elsewhere = sameRepo(where.repo, repo) ? '' : `. Nothing was created in ${repo}.`;
      return await tracked(where, (key) => `Already tracked: ${key} #${where.number} ${existing.issue.html_url}${elsewhere}`, null);
    }

    // The filed message may be gone since the form opened: a card cannot
    // follow its post's first message, since the scan never edits a card. It
    // is read for its author, then read again directly before the create,
    // whose body takes that last read, so a message deleted while the member
    // and the template are read files nothing. A deleted post is told apart
    // from a deleted message.
    const readFiled = async (client) => {
      try {
        const { message: found } = await client.readMessage(threadId, messageId);
        if (found) return { message: found };
        await followup(`Nothing was created: the message to file was deleted; ${BY_RIGHT_CLICK}`);
        return { refused: 'message' };
      } catch (e) {
        if (!postGone(e, threadId)) throw e;
        await followup('Nothing was created: the post was deleted.');
        return { refused: 'post' };
      }
    };
    const first = await readFiled(discord);
    if (first.refused) return { refused: first.refused };
    const author = first.message.author || {};
    // The bot's own copy with no readable move record (KV shows a write
    // elsewhere within a minute, or the save failed or never ran): filing it
    // would name the webhook as the player, or tie an issue to a copy no
    // record links. The first message tells it, and for a reply the scan's
    // record; with no STATE bound a reply's filing reads the first message
    // (none when deleted).
    const botCopy = messageId === threadId ? isBotCopy(first.message, interaction.application_id)
      : kv ? !!rec && rec.skipped === MOVED_HERE
        : isBotCopy((await discord.readMessage(threadId, threadId)).message, interaction.application_id);
    if (!movedFrom && botCopy) {
      await followup(kv
        ? `Nothing was created: this post is a copy the bot moved here, and its record movedfrom:${threadId} is not readable yet. Wait a minute, then send it again.`
        : `Nothing was created: this post is a copy the bot moved here, and its record movedfrom:${threadId} cannot be read: no STATE namespace is bound (/bot-check names it).`);
      return { refused: 'copy-record' };
    }
    // A moved post's first message is the bot's copy: the move's record
    // names its player. Otherwise a webhook's author id names no user, and
    // the issue shows its name alone.
    const copy = movedFrom && messageId === threadId ? movedFrom.reporter : null;
    copyId = copy && copy.id ? copy.id : null;
    const reporterId = copy ? copyId : first.message.webhook_id ? null : author.id;
    // The member and template reads are optional, so they end a full call's
    // time before the filing's deadline. The last read of the message and
    // the create must both run: they share what is left, in that order.
    const lookupsBy = t0 + budgetMs - callMs;
    // The server nickname is a nicety: any failure files with the display
    // name. A 404 is a member who left; any other failure is logged.
    const member = reporterId && !copy
      ? await discordClient(env.DISCORD_BOT_TOKEN, timedFetch(deps.fetch, FORM_LOOKUP_MS, lookupsBy))
        .call('GET', `/guilds/${interaction.guild_id}/members/${reporterId}`)
        .catch((e) => { if (statusOf(e) !== 404) log(`member read failed: ${e.message.slice(0, 200)}`); return null; })
      : null;
    const by = interaction.member && interaction.member.user;
    const template = await templateFields(cfg, thread.parent_id, type, env, deps, lookupsBy, log);
    const last = await readFiled(discordClient(env.DISCORD_BOT_TOKEN, timedFetch(deps.fetch, FORM_LOOKUP_MS, t0 + budgetMs)));
    if (last.refused) return { refused: last.refused };
    const { message } = last;
    const check = template.fields.length ? templateCheck(message.content, template.fields, (message.attachments || []).length) : [];
    gaps = templateGaps(check, template.optional);
    tmplNote = template.note;
    issueTitle = buildTitle({ repoKey, client, type, module: v.module, title: v.title });
    creating = true;
    const issue = await gh.createIssue(repo, {
      title: issueTitle,
      body: buildBody({
        content: message.content,
        reporter: copy ? { name: copy.name, username: copy.username, id: copyId } : { name: personName(author, member), username: author.username, id: reporterId },
        sender: by ? { name: personName(by, interaction.member), username: by.username, id: by.id } : null,
        threadId,
        messageId,
        threadUrl: `https://discord.com/channels/${interaction.guild_id}/${threadId}`,
        attachments: message.attachments,
        templateLine: check.length ? gaps.join(' · ') || 'every field present' : null,
        copied: !!copy,
      }),
      labels: labelsFor({ type, client }),
    });
    creating = false;

    // The issue exists from here on: report it whatever else fails. The tag
    // write and the player's receipt each have their own end, after the
    // filing's, so a slow create cannot starve them and a slow tag write
    // cannot use up the receipt's time.
    const tagger = discordClient(env.DISCORD_BOT_TOKEN, timedFetch(deps.fetch, callMs, t0 + TAG_BY_MS));
    const teller = discordClient(env.DISCORD_BOT_TOKEN, timedFetch(deps.fetch, callMs, t0 + TRACKED_BY_MS));
    const notes = [];
    if (template.note) notes.push(template.note);
    // Triaged goes only on a post with no status, as the post shows it just
    // before the write: the issue's own `opened` run, and any later run, set
    // the status GitHub calls for, and this write must not take it back.
    const shown = new Error('the post already shows a status');
    try {
      const status = await tagger.setStatus(threadId, STATUS.triaged, (from) => { if (from) throw shown; });
      if (status.skipped) notes.push(`tag not set: ${status.skipped}`);
    } catch (e) { if (e !== shown) notes.push(`tag not set: ${e.message.slice(0, 300)}`); }
    try {
      await within(kvMs, saveIssueRecord(kv, threadId, { repo, number: issue.number, key: repoKey, by: filer }));
    } catch (e) { notes.push(`post record not saved: ${e.message.slice(0, 200)}`); }
    notes.push(...await tellTracked(teller, log, {
      threadId, messageId, text: MESSAGES.tracked(repoKey, issue.number), old: oldGreeting, greeting: greetingId || (rec && rec.greeting), ping: copyId,
    }));
    await followup(`Created ${repoKey} #${issue.number}: ${issue.html_url}${notes.length ? ` (${notes.join('; ')})` : ''}${gapText()}`);
    cardAfter = { cardId, head, key: repoKey, number: issue.number, by: filer };
    renameAfter = cfg.rename;
    return { created: issue.number, notes };
  } catch (e) {
    // A create that got no answer may still have happened on GitHub's side:
    // look once more, and if it is not there yet keep the lock, so a retry
    // cannot file a second issue while the first may still appear.
    if (creating && unknownOutcome(e)) {
      const found = await ghRecheck.findByThread(repo, threadId).catch(() => null);
      if (found) {
        // Each step has its own end, so none can starve the next: the
        // record, the player's receipt (the issue's own run assumes the
        // Worker sent it), the moderator's report, and, after the lock's
        // release, the card.
        const late = tmplNote ? [tmplNote] : [];
        await within(kvMs, saveIssueRecord(env.STATE, threadId, { repo, number: found.number, key: repoKey, by: filer }))
          .catch((err) => late.push(`post record not saved: ${err.message.slice(0, 200)}`));
        const tail = discordClient(env.DISCORD_BOT_TOKEN, timedFetch(deps.fetch, TAIL_MS, t0 + TRACKED_BY_MS));
        late.push(...await tellTracked(tail, log, {
          threadId, messageId, text: MESSAGES.tracked(repoKey, found.number), old: oldGreeting, greeting: greetingId || (rec && rec.greeting), ping: copyId,
        }));
        await followup(`Created ${repoKey} #${found.number}: ${found.html_url} (GitHub answered late; the post's status tag comes from the issue's first workflow run${late.length ? `; ${late.join('; ')}` : ''})${gapText()}`);
        cardAfter = { cardId, head: thread ? cardHead(thread.parent_id, threadId) : '', key: repoKey, number: found.number, by: filer };
        renameAfter = cfg.rename;
        return { created: found.number, late: true };
      }
      keepLock = true;
      await followup(`The issue may have been created: GitHub did not answer in time, and may still make it. The lock ${lockLabel(threadId)} in ${cfg.lockRepo} stays, so this post cannot be filed twice meanwhile. If no issue for this post appears in ${repo}, ${clearAdvice(threadId, cfg.lockRepo)}`);
      return { error: e.message, uncertain: true };
    }
    await followup(`Nothing was created: ${e.message.slice(0, 1500)}`);
    return { error: e.message };
  } finally {
    if (locked && !keepLock) {
      try { await ghRelease.releaseThread(cfg.lockRepo, threadId); } catch (e) { log(`lock ${lockLabel(threadId)} not released: ${e.message}`); }
    }
    // Last, and after the release, the card and the post's rename, side by
    // side, on one client whose every call ends by the release's end. With
    // no card id from the form, the scan's record is read again: a scan may
    // have posted the card while this filing ran.
    const marking = cardAfter && cfg.queue;
    if (marking || renameAfter) {
      const closing = discordClient(env.DISCORD_BOT_TOKEN, timedFetch(deps.fetch, TAIL_MS, t0 + RELEASE_BY_MS));
      const card = async () => {
        const kvLeft = Math.min(kvMs, t0 + RELEASE_BY_MS - Date.now());
        const latest = cardAfter.cardId ? null
          : kvLeft > 0 ? await within(kvLeft, readStrict(env.STATE, `thread:${threadId}`))
            .catch((e) => { log(`card lookup failed, so the record read earlier is used: ${e.message.slice(0, 200)}`); return rec; }) : rec;
        await markCard(closing, cfg, log, {
          ...cardAfter, cardId: cardAfter.cardId || cardOf(latest), guildId: interaction.guild_id, postId: threadId,
        });
      };
      await Promise.all([
        marking ? card() : null,
        renameAfter ? renamePost(closing, log, threadId, fitName(issueTitle)) : null,
      ]);
    }
  }
}

// The issue a post was filed as, for a move: the saved one when it is live,
// else every configured repo searched. A search that finds nothing runs once
// more, as the filing's does: an issue that shifted between two pages of a
// list while it was read is found the second time. A saved issue that
// cannot be checked is `unclear`, with why. `key` is the one the saved
// issue was filed under while REPOS still maps it to the issue's repo, else
// the repo's first key.
async function findIssue(cfg, saved, postId, tokenFor, f) {
  // The saved key names only the saved issue: one a search finds after the
  // saved issue is gone is another filing.
  const found = (issue, from, own = false) => {
    const { repo } = whereIs(issue, from);
    const key = own && sameRepo(cfg.repos[saved.key], repo) ? saved.key : keyOf(cfg, repo);
    return { issue, key };
  };
  if (saved) {
    const r = await readSaved(saved, tokenFor, f);
    if (r.issue) return found(r.issue, saved.repo, true);
    if (!r.gone) return { unclear: r.unclear };
  }
  const search = () => searchRepos(Object.values(cfg.repos), postId, tokenFor, f);
  const hit = (await search()) || (await search());
  return hit ? found(hit.issue, hit.repo) : {};
}

// The Move form's job, after Discord has its "thinking..." answer, under the
// post's filing lock. It moves a post not yet filed; a filed one is refused
// with no change. Before the new post exists nothing a player sees changes,
// so every failure there moves nothing and moving again finishes the job.
// After it exists, every step runs and the reply names each one not done,
// with both posts' links: the old post is locked, so a second move cannot
// redo it.
export async function movePost(interaction, env, deps, t0 = Date.now()) {
  const cfg = config(env);
  const { threadId: oldId, cardId } = parseCustomId(interaction.data.custom_id);
  const v = modalValues(interaction.data);
  const targetId = v.forum;
  const target = cfg.forumInfo[targetId];
  const client = target.client || normClient(v.client);
  const guildId = interaction.guild_id;
  const link = (id) => `https://discord.com/channels/${guildId}/${id}`;
  const mover = staffRef(interaction.member.user);
  const log = deps.log || console.error;
  const { callMs = CALL_MS, kvMs = KV_MS } = deps; // tests shorten these
  const until = (by) => timedFetch(deps.fetch, callMs, t0 + by);
  const prep = until(MOVE_PREP_BY_MS);
  const discord = discordClient(env.DISCORD_BOT_TOKEN, prep);
  const { tokenFor, access } = githubAccess(env, deps, prep);
  const followup = followupFor(interaction, deps, log, t0);
  const kv = env.STATE;
  const notes = [];
  const refuse = async (why, kind) => {
    await followup(`Nothing was moved: ${why}.`);
    return { refused: kind };
  };
  let lockToken = '';
  let locked = false;
  let keepLock = false;
  try {
    if (!cfg.lockRepo) return await refuse("the bot is not set up yet. REPOS names more than one repo, so LOCK_REPO must name the repo that holds every filing's lock", 'setup');
    lockToken = await access(cfg.lockRepo);
    try {
      locked = await githubClient(lockToken, prep).claimThread(cfg.lockRepo, oldId);
    } catch (e) {
      if (!unknownOutcome(e)) throw e;
      await followup(`Nothing was moved: GitHub did not confirm the lock ${lockLabel(oldId)} in ${cfg.lockRepo} (${e.message.slice(0, 200)}). Wait a few minutes, then move the post again; if that says another send or move is running, follow its advice.`);
      return { uncertain: 'lock' };
    }
    if (!locked) {
      await followup(`Nothing was moved: another send or move of this post is running, or one stopped partway. Wait a few minutes, then move it again. If it still says this, ${clearAdvice(oldId, cfg.lockRepo, 'move')}`);
      return { busy: true };
    }

    let old;
    try {
      old = await discord.getChannel(oldId);
    } catch (e) {
      if (!postGone(e, oldId)) throw e;
      return await refuse('the post was deleted', 'post');
    }
    if (!cfg.forums.includes(old.parent_id)) return await refuse('this post is not in a forum the bot is set up for', 'forum');

    let records;
    try {
      records = await postRecords(kv, oldId, kvMs);
    } catch (e) {
      return await refuse("could not read this post's saved record just now. Try again", 'record');
    }
    if (records.movedTo) return await refuse(`this post was already moved to ${link(records.movedTo.to)}`, 'moved');
    // The bot's move locks the old post, and Discord shows a lock at once,
    // unlike KV's records: a move repeated within KV's minute stops here. The
    // bot's note there says where it went when its record was not saved. An
    // unlocked post's note refuses nothing: someone unlocked it to move it.
    const own = await ownNotes(discord, oldId, { receipts: true });
    if (old.thread_metadata.locked && own.away) return await refuse(`this post was already moved to ${own.away}`, 'moved');
    // A filed post is refused before a locked one's advice: unlocking it
    // would not let it move.
    const found = await findIssue(cfg, records.saved, oldId, tokenFor, prep);
    if (found.unclear) {
      await followup(couldNotCheck(cfg, records.saved, oldId, found.unclear, 'Nothing was moved.'));
      return { refused: 'saved-issue' };
    }
    if (found.issue) {
      await followup(`This post is already tracked as ${found.key} #${found.issue.number} (${found.issue.html_url}); moving filed posts comes in a later update.`);
      return { refused: 'filed' };
    }
    // Filed, though neither search finds its issue: a filing record never
    // saved or deleted, and the issue's label removed or the issue moved
    // outside REPOS. Moving it would leave that issue on the locked post.
    if (own.receipt) {
      return await refuse(`the bot's "now tracked" reply in this post (${link(oldId)}/${own.receipt.id}) says it was sent to GitHub, though its issue was not found by its filing record or the from-discord label; moving filed posts comes in a later update. If that issue was deleted, delete that reply, then move the post again`, 'filed');
    }
    if (old.thread_metadata.locked) return await refuse('the post is locked: a moderator can unlock it, then move it', 'locked');

    let channels;
    try {
      channels = await discord.call('GET', `/guilds/${guildId}/channels`);
    } catch (e) {
      return await refuse(`could not read the forums just now (${e.message.slice(0, 200)}). Try again`, 'forums');
    }
    // The form offered only this server's forums, and the submit checks
    // FORUMS alone: a forum deleted since the form opened is no longer in
    // the channel list.
    if (!moveTargets(cfg, channels, old.parent_id).includes(targetId)) {
      return await refuse(`<#${targetId}> is not a forum of this server, so nothing is posted there. /bot-check names the FORUMS entry to fix`, 'forum');
    }

    let read;
    try {
      read = await discord.readMessage(oldId, oldId);
    } catch (e) {
      if (!postGone(e, oldId)) throw e;
      return await refuse('the post was deleted', 'post');
    }
    const first = read.message;
    if (!first) return await refuse("the post's first message was deleted, so there is nothing to copy", 'message');
    // The bot's own copy whose move record is not readable yet (KV shows a
    // write elsewhere within a minute) or was not saved: copying it would
    // name the webhook as the player.
    if (!records.movedFrom && isBotCopy(first, interaction.application_id)) {
      return await refuse(`this post is a copy the bot moved here, and its record movedfrom:${oldId} is not readable yet. Wait a minute, then move it again`, 'copy-record');
    }
    let reporter;
    if (records.movedFrom) {
      // The old post is itself a moved copy: its record names the player.
      reporter = records.movedFrom.reporter;
    } else if (first.webhook_id) {
      // A webhook's author id names no user: its name alone, as filing names it.
      reporter = { name: personName(first.author, null) };
    } else {
      // The server name and avatar are niceties: a member who left (404), or
      // any failed read, gives the user's own. The read has its own short
      // call that ends a call's time before the prep phase (by 4 s with the
      // 8 s call), so one that stalls cannot take the time of the webhook
      // lookup after it, which keeps a whole call, of the downloads (to 10 s)
      // or of the re-read (to 12 s).
      const member = await discordClient(env.DISCORD_BOT_TOKEN, timedFetch(deps.fetch, FORM_LOOKUP_MS, t0 + MOVE_PREP_BY_MS - callMs))
        .call('GET', `/guilds/${guildId}/members/${first.author.id}`)
        .catch((e) => { if (statusOf(e) !== 404) log(`member read failed: ${e.message.slice(0, 200)}`); return null; });
      reporter = { name: personName(first.author, member), id: first.author.id, username: first.author.username, avatar: avatarUrl({ guildId, user: first.author, member }) };
    }

    let hook;
    try {
      hook = await discord.forumWebhook(targetId, interaction.application_id);
    } catch (e) {
      if (statusOf(e) === 403) return await refuse(`the bot lacks Manage Webhooks in <#${targetId}>`, 'webhook');
      throw e;
    }

    // Each file in order that fits Discord's limits is downloaded; the rest,
    // and any whose download fails, is stopped or cannot start in time, stay
    // on the old post. The downloads end MOVE_REREAD_MS before the prep
    // phase, so a slow file cannot take the time of the first message's read
    // below, which the create needs.
    const download = timedFetch(deps.fetch, callMs, t0 + MOVE_PREP_BY_MS - MOVE_REREAD_MS);
    const files = [];
    let room = COPY_MAX_BYTES;
    for (const a of first.attachments) {
      if (a.size > COPY_FILE_MAX || a.size > room) continue;
      try {
        const res = await download(a.url);
        if (!res.ok) throw new Error(`answered ${res.status}`);
        files.push({ id: a.id, name: a.filename, description: a.description, blob: await res.blob() });
        room -= a.size;
      } catch (e) {
        log(`file ${a.filename} of post ${oldId} not copied: ${e.message.slice(0, 200)}`);
      }
    }

    // The first message is read again just before the create, as a filing
    // reads its message: one deleted while the move prepared (its reads and
    // the file downloads) is not posted again.
    let last;
    try {
      last = (await discord.readMessage(oldId, oldId)).message;
    } catch (e) {
      if (!postGone(e, oldId)) throw e;
      return await refuse('the post was deleted', 'post');
    }
    if (!last) return await refuse("the post's first message was deleted, so there is nothing to copy", 'message');
    // The copy takes the downloaded files this read still lists, so a file
    // the player removed meanwhile is not posted; every other file it lists,
    // one added meanwhile included, is counted as left on the old post.
    const copied = files.filter((x) => last.attachments.some((a) => a.id === x.id));
    const left = last.attachments.length - copied.length;

    const type = target.type;
    const text = last.content;
    const cut = text.length > MAX_REPLY;
    // Built before the create, so the catch below sees only the create's own
    // failure. A thread read may carry no tag list (movedTags' default).
    const payload = {
      thread_name: old.name,
      applied_tags: movedTags({ applied: old.applied_tags, from: tagsIn(channels, old.parent_id), to: tagsIn(channels, targetId), client, fixedClient: target.client, fixedType: target.type, repoTags: cfg.repoTags }),
      content: cut ? `${cutUnits(text, MAX_REPLY - 1)}…` : text || (copied.length ? '' : NOTHING_TO_COPY),
      username: webhookName(reporter.name, reporter.username),
      // A webhook's reporter has no avatar.
      ...(reporter.avatar ? { avatar_url: reporter.avatar } : {}),
      allowed_mentions: { parse: [] },
      attachments: copied.map((x, i) => ({ id: i, filename: x.name, ...(x.description ? { description: x.description } : {}) })),
    };
    let made;
    try {
      made = await discordClient(env.DISCORD_BOT_TOKEN, until(MOVE_CREATE_BY_MS)).executeWebhook(hook, payload, copied);
    } catch (e) {
      if (refusal4xx(e)) return await refuse(`Discord refused the new post (${e.message.slice(0, 300)})`, 'create');
      if (/^out of time before /.test(e.message)) throw e;
      // Discord may still make it: the lock stays, so nothing moves or sends
      // this post meanwhile, as a filing keeps its lock after an unknown
      // create.
      log(`move of post ${oldId}: create not confirmed: ${e.message.slice(0, 200)}`);
      keepLock = true;
      await followup(`Nothing confirmed: Discord did not answer the new post's create in <#${targetId}>, so a copy of ${link(oldId)} may exist there. The old post was not changed; its lock ${lockLabel(oldId)} in ${cfg.lockRepo} stays.`);
      return { uncertain: 'create' };
    }

    // The new post exists from here on: every step runs, and the reply names
    // each one not done. Nothing is retried or repaired.
    const newId = made.channel_id;
    const newUrl = link(newId);
    const later = discordClient(env.DISCORD_BOT_TOKEN, until(MOVE_REST_BY_MS));
    const step = async (name, fn) => {
      try {
        await fn();
        return true;
      } catch (e) {
        // A write answered 2xx is done, even when its body could not be read.
        if (taken(e)) return true;
        log(`move of post ${oldId} to ${newId}: ${name} not done: ${e.message.slice(0, 200)}`);
        notes.push(name);
        return false;
      }
    };
    // Each record's wait ends with the steps' phase, so a slow KV cannot use
    // up the reply's or the release's time.
    const put = (key, value) => step(`record ${key}`, () => {
      const ms = Math.min(kvMs, t0 + MOVE_REST_BY_MS - Date.now());
      if (ms <= 0) throw new Error(`out of time before KV ${key}`);
      return within(ms, kv.put(key, JSON.stringify(value)));
    });
    // The old post's record comes first: it refuses a later send or move of
    // the old post and keeps the scan off it.
    await put(`movedto:${oldId}`, { to: newId });
    // The queue card shows the new post, edited before movedfrom: so the
    // record names the card. With no card, or one Discord refuses to edit
    // (deleted), a new card is posted: the card is how an approved role, who
    // has no right-click command, reaches the post.
    let card = cfg.queue ? cardId || (records.thread && records.thread.card) || (records.movedFrom && records.movedFrom.card) || '' : '';
    if (cfg.queue) {
      const body = queueCard({ guildId, forumId: targetId, postId: newId, author: reporter, client, type, moved: mover });
      await step('queue card for the new post', async () => {
        if (card) {
          try {
            await later.call('PATCH', `/channels/${cfg.queue}/messages/${card}`, body);
            return;
          } catch (e) {
            if (!refusal4xx(e)) throw e;
            card = '';
          }
        }
        card = (await later.call('POST', `/channels/${cfg.queue}/messages`, body)).id;
      });
    }
    await put(`movedfrom:${newId}`, { from: oldId, reporter, ...(card ? { card } : {}) });
    const here = MESSAGES.movedHere({ from: link(oldId), by: mover, reporter, left, cut });
    await step('moved message in the new post', () => later.send(newId, here, reporter.id ? [reporter.id] : []));
    await step('note in the old post', () => later.send(oldId, MESSAGES.movedTo({ to: newUrl, by: mover })));
    // An old post left open keeps its lock label, so nothing moves or sends
    // it again until the busy reply's hour has passed.
    if (!await step('lock on the old post', () => later.call('PATCH', `/channels/${oldId}`, { locked: true, archived: true }))) keepLock = true;
    // At most six short lines: the reply never nears Discord's length.
    await followup(notes.length
      ? `The move stopped partway: ${newUrl} was made from ${link(oldId)}. Not done:\n${notes.map((n) => `- ${n}`).join('\n')}`
      : `Moved to ${newUrl} from ${link(oldId)}.`);
    return { moved: newId, notes };
  } catch (e) {
    await followup(`Nothing was moved: ${e.message.slice(0, 1500)}`);
    return { error: e.message };
  } finally {
    // A lock kept stays; a release that fails is logged. The next send's or
    // move's busy reply says how to clear either, as after a filing.
    if (locked && !keepLock) {
      await githubClient(lockToken, timedFetch(deps.fetch, TAIL_MS, t0 + RELEASE_BY_MS))
        .releaseThread(cfg.lockRepo, oldId).catch((e) => log(`lock ${lockLabel(oldId)} not released: ${e.message}`));
    }
  }
}

// The bot serves the one server GUILD_ID names. Its commands are registered
// for every server it is in, and FORUMS or QUEUE_CHANNEL_ID can name another
// server's channel, so each entry point refuses any other server, or a
// GUILD_ID that names none, before it reads anything else. A setup problem
// is shown to staff only (`staff`); anyone else gets the entry point's own
// refusal (`no`). /bot-check says the same in its own words.
function elsewhere(env, interaction, staff, no) {
  const home = String(env.GUILD_ID ?? '');
  if (!isDiscordId(home)) return staff() ? reply("The bot is not set up yet: GUILD_ID is not set to the server's id (digits only, no spaces).") : reply(no);
  return String(interaction.guild_id ?? '') === home ? null : reply('This only works on posts in the forums the bot is set up for.');
}

// The checks a button press or form submit makes first, in order: the
// server, the ids, a config that reads, and the caller.
// `noRoles` is the reply to a member who is not a moderator while no role is
// approved; with `forums`, a config naming no player forum is not set up.
// Returns the reply, or the config and the custom id's parts.
function gate(interaction, env, { no, badIds = BAD_IDS, noRoles: none = '', forums = false }) {
  const away = elsewhere(env, interaction, () => allowed(interaction.member, { roles: parseRoleIds(env.APPROVED_ROLE_IDS) }), no);
  if (away) return { answer: away };
  const ids = parseCustomId(interaction.data.custom_id);
  if (!ids) return { answer: reply(badIds) };
  const cfg = configOr(env);
  if (!cfg) return { answer: allowed(interaction.member, { roles: parseRoleIds(env.APPROVED_ROLE_IDS) }) ? notSetUp(env) : reply(no) };
  if (none && !cfg.roles.length && !canUse(interaction.member)) return { answer: reply(none) };
  if (!allowed(interaction.member, cfg)) return { answer: reply(no) };
  if (forums && !cfg.forums.length) return { answer: notSetUp(env) };
  return { cfg, ids };
}

export async function handle(request, env, ctx, deps = { fetch: (...a) => fetch(...a) }) {
  // Discord's 3 s for the first answer runs from here: reading the body and
  // checking the signature count against it. Every path's deadlines count
  // from this moment: the press, the right-click form and the filing.
  const t0 = Date.now();
  if (request.method !== 'POST') return new Response('ok');
  const body = await request.text();
  const ok = await verifyDiscord(env.DISCORD_PUBLIC_KEY,
    request.headers.get('X-Signature-Ed25519'), request.headers.get('X-Signature-Timestamp'), body);
  if (!ok) return new Response('bad signature', { status: 401 });

  const interaction = JSON.parse(body);
  if (interaction.type === 1) return json({ type: 1 });

  if (interaction.type === 2 && interaction.data.name === COMMAND_NAME) {
    const away = elsewhere(env, interaction, () => canUse(interaction.member), 'Only moderators and admins can send posts to GitHub.');
    if (away) return away;
    if (!canUse(interaction.member)) return reply('Only moderators and admins can send posts to GitHub.');
    return openForm(interaction, env, deps, { threadId: interaction.channel_id, messageId: interaction.data.target_id, deadline: t0 + FORM_BY_MS });
  }

  if (interaction.type === 2 && interaction.data.name === MOVE_COMMAND) {
    const away = elsewhere(env, interaction, () => canUse(interaction.member), 'Only moderators and admins can move posts.');
    if (away) return away;
    if (!canUse(interaction.member)) return reply('Only moderators and admins can move posts.');
    const cfg = configOr(env);
    if (!cfg || !cfg.forums.length) return notSetUp(env);
    return openMoveForm(interaction, env, deps, cfg, { threadId: interaction.channel_id, deadline: t0 + FORM_BY_MS });
  }

  if (interaction.type === 2 && interaction.data.name === CHECK_COMMAND) {
    if (!canUse(interaction.member)) return reply('Only moderators and admins can check the bot setup.');
    // Fails closed: a moderator of another server the bot is in neither
    // posts here nor reads this setup, also when GUILD_ID is broken.
    const guild = String(env.GUILD_ID ?? '');
    if (!isDiscordId(guild)) return reply("The bot's GUILD_ID is not set to a server id, so it can check nothing. Fix it in the Worker's settings.");
    if (String(interaction.guild_id) !== guild) return reply('This command checks only the server the bot is set up for.');
    ctx.waitUntil(runCheck(interaction, env, deps, t0));
    return json({ type: 5, data: { flags: EPHEMERAL } });
  }

  if (interaction.type === 3 && String(interaction.data.custom_id).startsWith(`${SEND_BUTTON}:`)) {
    const { answer, cfg, ids } = gate(interaction, env, { no: NOT_ALLOWED, noRoles: noRoles(COMMAND_NAME) });
    if (answer) return answer;
    // A press on a post already filed answers at once and opens no form.
    const answered = await pressCheck(interaction, env, deps, cfg, ids.threadId, t0, ctx);
    if (answered) return answered;
    // A forum post's first message has the post's own id. A press on a queue
    // card, outside the post, carries the card's id; one on an old greeting
    // in the post carries the greeting's.
    const pressed = (interaction.message && interaction.message.id) || '';
    const fromCard = interaction.channel_id !== ids.threadId;
    return openForm(interaction, env, deps, {
      threadId: ids.threadId, messageId: ids.threadId, greetingId: fromCard ? '' : pressed, cardId: fromCard ? pressed : '', deadline: t0 + FORM_BY_MS,
    });
  }

  if (interaction.type === 3 && String(interaction.data.custom_id).startsWith(`${MOVE_BUTTON}:`)) {
    const { answer, cfg, ids } = gate(interaction, env, { no: NOT_ALLOWED_MOVE, badIds: BAD_MOVE_IDS, noRoles: noRoles(MOVE_COMMAND), forums: true });
    if (answer) return answer;
    // The Move button is on queue cards only, so the press carries its card.
    return openMoveForm(interaction, env, deps, cfg, { threadId: ids.threadId, cardId: interaction.message.id, deadline: t0 + FORM_BY_MS });
  }

  if (interaction.type === 5 && String(interaction.data.custom_id).startsWith('gh:')) {
    const { answer, cfg } = gate(interaction, env, { no: NOT_ALLOWED, forums: true });
    if (answer) return answer;
    const v = modalValues(interaction.data);
    const problems = [];
    if (!usableRepoKeys(cfg.repos).includes(normRepoKey(v.repo, cfg.repos))) problems.push('The repo chosen is no longer in REPOS: pick it again.');
    if (!normClient(v.client)) problems.push('Client must be Retail, Forever or All.');
    if (!normType(v.type)) problems.push('Type must be Bug or Feature.');
    if (!titleText(v.title)) problems.push('Title is empty.');
    if (problems.length) return reply(`Nothing was created. ${problems.join(' ')} Press the button or right-click the post to try again.`);

    ctx.waitUntil(fileIssue(interaction, env, deps, t0));
    return json({ type: 5, data: { flags: EPHEMERAL } });
  }

  if (interaction.type === 5 && String(interaction.data.custom_id).startsWith('mv:')) {
    const { answer, cfg } = gate(interaction, env, { no: NOT_ALLOWED_MOVE, badIds: BAD_MOVE_IDS, forums: true });
    if (answer) return answer;
    // A filing works with no namespace bound, but a move's records are what
    // link the two posts: without them nothing refuses the old one.
    if (!env.STATE) return reply('Nothing was moved: the STATE KV namespace is not bound, so the move could not be recorded. Bind it (README, Stage 2 step 5), then move the post.');
    const v = modalValues(interaction.data);
    const problems = [];
    // The forum is read against FORUMS as it is now, not as the form saw it.
    const known = cfg.forums.includes(v.forum);
    if (!known) problems.push('Pick a forum the bot is set up for.');
    // The client dropdown offers only CLIENT_NAMES, which normClient reads:
    // a client chosen is always valid, and only its absence is checked.
    if (!v.client && known && !cfg.forumInfo[v.forum].client) problems.push(`Pick a client: <#${v.forum}> has no client of its own.`);
    if (problems.length) return reply(`Nothing was moved. ${problems.join(' ')}`);
    ctx.waitUntil(movePost(interaction, env, deps, t0));
    return json({ type: 5, data: { flags: EPHEMERAL } });
  }

  return reply('Unknown command.');
}

export async function scheduled(controller, env, ctx, deps = { fetch: (...a) => fetch(...a) }) {
  if (controller.cron === CRONS.setup) return setupDaily(env, deps);
  if (controller.cron === CRONS.daily) return daily(env, deps);
  return scan(env, deps);
}

export default {
  fetch: (request, env, ctx) => handle(request, env, ctx),
  scheduled: (controller, env, ctx) => ctx.waitUntil(scheduled(controller, env, ctx)),
};
