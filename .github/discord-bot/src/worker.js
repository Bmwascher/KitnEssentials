// Cloudflare Worker that answers Discord interactions over HTTP (no gateway,
// no always-on server). Two ways in, one form: the "Send to GitHub" button on
// a post's card in the staff queue channel (approved roles), or right-click a
// post > Apps > "Send to GitHub" (moderators). A press on a post already
// filed answers "Already tracked" instead of opening the form. Submitting the
// form files the issue and replies to the filed message in the post.
import {
  STATUS, MESSAGES, PERMS, buildTitle, buildBody, labelsFor, cleanPostTitle, personName, titleText,
  guessFromTags, normClient, normType, normRepoKey, parseRepos, timedFetch,
  parseForums, parseRoleIds, parseTemplates, templateCheck, templateGaps,
  templateNote, parseCustomId, templateLabels, filedCard, cardHead, BY_RIGHT_CLICK,
} from './core.js';
import { discordClient, postGone } from './discord.js';
import { githubClient, installationToken, lockLabel } from './github.js';
import { scan, daily, CRONS, SEND_BUTTON, readStrict, saveIssueRecord, hasButton } from './scan.js';

export const COMMAND_NAME = 'Send to GitHub';
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
// Signed requests older than this are refused (a captured one cannot be replayed later).
const MAX_AGE_S = 300;

const json = (obj, status = 200) => new Response(JSON.stringify(obj), {
  status, headers: { 'Content-Type': 'application/json' },
});
const reply = (content) => json({ type: 4, data: { content, flags: EPHEMERAL } });

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

const input = (id, label, value, opts = {}) => ({
  type: 1,
  components: [{
    type: 4, custom_id: id, label, style: opts.paragraph ? 2 : 1,
    required: opts.required !== false, max_length: opts.max || 100,
    value: value || undefined, placeholder: opts.placeholder,
  }],
});

function modalValues(data) {
  const out = {};
  for (const row of data.components || []) for (const c of row.components || []) out[c.custom_id] = c.value;
  return out;
}

async function openForm(interaction, env, deps, { threadId, messageId, greetingId = '', cardId = '', deadline = Date.now() + FORM_LOOKUP_MS }) {
  const cfg = config(env);
  if (!cfg.forums.length) return reply('The bot is not set up yet: FORUMS is empty.');
  const discord = discordClient(env.DISCORD_BOT_TOKEN, timedFetch(deps.fetch, FORM_LOOKUP_MS, deadline));
  let ch = interaction.channel && interaction.channel.id === threadId ? interaction.channel : {};
  if (!ch.parent_id || !ch.applied_tags) {
    try {
      ch = await discord.getChannel(threadId);
    } catch (e) {
      // A card press brings no post with it: say why the form cannot open.
      if (!ch.parent_id) {
        return reply(/ -> 404 /.test(e.message) ? 'This post no longer exists.' : 'Could not read the post just now. Press the button again.');
      }
    }
  }
  if (!cfg.forums.includes(ch.parent_id)) {
    return reply('This only works on posts in the forums the bot is set up for.');
  }

  // Pre-fill client and type from the forum's own settings, else from the
  // post's tags; a slow or failed lookup just leaves those fields blank.
  let guess = { ...cfg.forumInfo[ch.parent_id] };
  if (!guess.client || !guess.type) {
    try {
      const forum = await discord.getChannel(ch.parent_id);
      const names = (forum.available_tags || []).filter((t) => (ch.applied_tags || []).includes(t.id)).map((t) => t.name);
      const fromTags = guessFromTags(names);
      guess = { client: guess.client || fromTags.client, type: guess.type || fromTags.type };
    } catch { /* keep the blanks */ }
  }

  const keys = Object.keys(cfg.repos);
  return json({
    type: 9,
    data: {
      custom_id: `gh:${threadId}:${messageId}${greetingId || cardId ? `:${greetingId || '0'}` : ''}${cardId ? `:${cardId}` : ''}`,
      title: 'Send to GitHub',
      components: [
        input('repo', `Repo (${keys.join(' or ')})`, keys[0], { max: 10 }),
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
const httpStatus = (e) => (/-> (\d{3}) /.exec(e.message) || [])[1] || e.message.slice(0, 120);

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
    if (/-> 410 /.test(e.message)) return { gone: true };
    return { unclear: httpStatus(e), notFound: /-> 404 /.test(e.message) };
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
// works.
async function tellTracked(discord, log, { threadId, messageId, text, old, greeting }) {
  try {
    const sent = await discord.send(threadId, text, [], { replyTo: messageId });
    if (sent && sent.replyRefused) log(`post ${threadId}: Discord refused the reply; the note went out plain, with no ping`);
  } catch (e) {
    if (!/ -> 4\d\d /.test(e.message)) return [`note in the post may not have been sent: ${e.message.slice(0, 300)}`];
    if (!greeting) return [`note in the post not sent: ${e.message.slice(0, 300)}`];
    try {
      await discord.call('PATCH', `/channels/${threadId}/messages/${greeting}`, { content: text, components: [], allowed_mentions: { parse: [] } });
      return [];
    } catch (e2) {
      return [`note in the post ${/ -> 4\d\d /.test(e2.message) ? 'not sent' : 'may not have been sent'}: ${e2.message.slice(0, 300)}`];
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

// A send ends within 30 s and GitHub ends a request it has worked on for
// 10 s, so an hour after a lock was taken no send holds it and no create it
// sent can still land, even one whose answer was lost. A newer lock may, so
// the advice never frees it.
const clearAdvice = (threadId, lockRepo) => `delete the label ${lockLabel(threadId)} in ${lockRepo}, but only if the time in its description is more than an hour ago or it shows no time: a send ends within 30 seconds and GitHub finishes each request within seconds, so by then no send holds that lock and no issue it asked for can still appear. Then send the post again.`;

// A saved issue that answers 404 cannot be told from one the app can no
// longer see (a transfer out of reach, lost access), so nothing goes ahead.
// The way out clears only the post's filing association: its greeting and
// card ids stay.
function couldNotCheck(cfg, saved, postId, why, done) {
  const key = keyOf(cfg, saved.repo);
  const what = key !== saved.repo ? `${key} #${saved.number} in ${saved.repo}` : `${saved.repo} #${saved.number}`;
  return `Could not check ${what} (${why}): it may be gone, or the app may have lost access there. ${done} If it is gone, a bot admin can clear this post's filing record (the KV key issue:${postId}, or the "issue" field of thread:${postId} for a post filed before this version), and the post can then be sent again.`;
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
    if (e.damaged) return reply(`This post's saved record is damaged (${e.damaged}). Nothing was opened. A bot admin can delete that KV key; then press again.`);
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

// Runs after Discord already has its "thinking..." answer. Every call is timed,
// and every outcome, partial ones included, is reported back to the moderator.
// `t0` is the moment the request arrived; every phase's end counts from it.
export async function fileIssue(interaction, env, deps, t0 = Date.now()) {
  const cfg = config(env);
  const { threadId, messageId, greetingId, cardId } = parseCustomId(interaction.data.custom_id);
  // The moderator who sent the form, as the card and the filing record name them.
  const modName = interaction.member && interaction.member.user ? personName(interaction.member.user, interaction.member) : null;
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
  const followup = async (text) => {
    const content = text.length > MAX_REPLY ? `${text.slice(0, MAX_REPLY - 1)}…` : text;
    try {
      const res = await timedFetch(deps.fetch, TAIL_MS, t0 + REPORT_BY_MS)(
        `https://discord.com/api/v10/webhooks/${interaction.application_id}/${interaction.token}/messages/@original`,
        { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ content }) },
      );
      if (!res.ok) log(`followup failed: ${res.status} ${(await res.text().catch(() => '')).slice(0, 300)}`);
    } catch (e) {
      log(`followup failed: ${e.message}`);
    }
  };

  const repo = cfg.repos[repoKey];
  let gh;
  let ghRecheck; // the re-check of an unknown create, after the filing's budget
  let ghRelease; // the lock's release, last
  let locked = false;
  let keepLock = false;
  let creating = false;
  let thread = null;
  let rec = null;
  let saved = null;
  let oldGreeting = '';
  let lockGh;
  // One token per repo this filing touches.
  const tokens = new Map();
  const tokenFor = (r) => {
    if (!tokens.has(r)) tokens.set(r, (deps.installationToken || installationToken)({ appId: env.GITHUB_APP_ID, privateKey: env.GITHUB_APP_PRIVATE_KEY, repo: r }, f));
    return tokens.get(r);
  };
  // A token the filing cannot start without: its failure files nothing and
  // names the repo to try again for.
  const access = async (r) => {
    try {
      return await tokenFor(r);
    } catch (e) {
      throw new Error(`could not get access to ${r} (${e.message.slice(0, 200)}). Try again.`);
    }
  };
  // The post's queue card: the form's, else the scan's record of the post.
  const cardOf = (r) => cardId || (r && r.card) || '';
  // The card to mark Filed as, once the lock is released: optional work
  // never holds the lock.
  let cardAfter = null;
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
    const head = cardHead(thread.parent_id, thread.name);
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
      await followup(`Nothing was created: another send of this post is running, or one stopped partway. Wait a few minutes, then send it again. If it still says this and no issue for this post appears in any repo the bot files into, ${clearAdvice(threadId, cfg.lockRepo)}`);
      return { busy: true };
    }
    // The post's records, read under the lock, each waited on for at most
    // KV_MS (`kvMs`). One that cannot be read is not "none": it may name an issue the
    // search cannot see (one moved to a repo the bot does not file in), so
    // nothing is filed.
    try {
      rec = await within(kvMs, readStrict(kv, `thread:${threadId}`));
      const filed = await within(kvMs, readStrict(kv, `issue:${threadId}`));
      // The issue the post was filed as: the Worker's record, or an older
      // record that kept it beside the greeting.
      saved = filed || (rec && rec.issue) || null;
    } catch (e) {
      await followup(e.damaged
        ? `Nothing was created: this post's saved record is damaged (${e.damaged}). A bot admin can delete that KV key; then send the post again.`
        : "Nothing was created: could not read this post's saved record just now. Try again.");
      return { refused: 'record' };
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
    // A webhook's author id names no user: the issue shows its name alone.
    const reporterId = first.message.webhook_id ? null : author.id;
    // The member and template reads are optional, so they end a full call's
    // time before the filing's deadline. The last read of the message and
    // the create must both run: they share what is left, in that order.
    const lookupsBy = t0 + budgetMs - callMs;
    // The server nickname is a nicety: any failure files with the display
    // name. A 404 is a member who left; any other failure is logged.
    const member = reporterId
      ? await discordClient(env.DISCORD_BOT_TOKEN, timedFetch(deps.fetch, FORM_LOOKUP_MS, lookupsBy))
        .call('GET', `/guilds/${interaction.guild_id}/members/${reporterId}`)
        .catch((e) => { if (!/ -> 404 /.test(e.message)) log(`member read failed: ${e.message.slice(0, 200)}`); return null; })
      : null;
    const by = interaction.member && interaction.member.user;
    const template = await templateFields(cfg, thread.parent_id, type, env, deps, lookupsBy, log);
    const last = await readFiled(discordClient(env.DISCORD_BOT_TOKEN, timedFetch(deps.fetch, FORM_LOOKUP_MS, t0 + budgetMs)));
    if (last.refused) return { refused: last.refused };
    const { message } = last;
    const check = template.fields.length ? templateCheck(message.content, template.fields, (message.attachments || []).length) : [];
    gaps = templateGaps(check, template.optional);
    tmplNote = template.note;
    creating = true;
    const issue = await gh.createIssue(repo, {
      title: buildTitle({ repoKey, client, module: v.module, title: v.title }),
      body: buildBody({
        content: message.content,
        reporter: { name: personName(author, member), username: author.username, id: reporterId },
        sender: by ? { name: personName(by, interaction.member), username: by.username, id: by.id } : null,
        threadId,
        messageId,
        threadUrl: `https://discord.com/channels/${interaction.guild_id}/${threadId}`,
        attachments: message.attachments,
        templateLine: check.length ? gaps.join(' · ') || 'every field present' : null,
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
      await within(kvMs, saveIssueRecord(kv, threadId, { repo, number: issue.number, key: repoKey, by: modName }));
    } catch (e) { notes.push(`post record not saved: ${e.message.slice(0, 200)}`); }
    notes.push(...await tellTracked(teller, log, {
      threadId, messageId, text: MESSAGES.tracked(repoKey, issue.number), old: oldGreeting, greeting: greetingId || (rec && rec.greeting),
    }));
    await followup(`Created ${repoKey} #${issue.number}: ${issue.html_url}${notes.length ? ` (${notes.join('; ')})` : ''}${gapText()}`);
    cardAfter = { cardId, head, key: repoKey, number: issue.number, by: modName };
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
        await within(kvMs, saveIssueRecord(env.STATE, threadId, { repo, number: found.number, key: repoKey, by: modName }))
          .catch((err) => late.push(`post record not saved: ${err.message.slice(0, 200)}`));
        const tail = discordClient(env.DISCORD_BOT_TOKEN, timedFetch(deps.fetch, TAIL_MS, t0 + TRACKED_BY_MS));
        late.push(...await tellTracked(tail, log, {
          threadId, messageId, text: MESSAGES.tracked(repoKey, found.number), old: oldGreeting, greeting: greetingId || (rec && rec.greeting),
        }));
        await followup(`Created ${repoKey} #${found.number}: ${found.html_url} (GitHub answered late; the post's status tag comes from the issue's first workflow run${late.length ? `; ${late.join('; ')}` : ''})${gapText()}`);
        cardAfter = { cardId, head: thread ? cardHead(thread.parent_id, thread.name) : '', key: repoKey, number: found.number, by: modName };
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
    // Last, and after the release, the card. With no card id from the form,
    // the scan's record is read again: a scan may have posted the card while
    // this filing ran. The read and the edit both end by the release's end.
    if (cardAfter && cfg.queue) {
      const kvLeft = Math.min(kvMs, t0 + RELEASE_BY_MS - Date.now());
      const latest = cardAfter.cardId ? null
        : kvLeft > 0 ? await within(kvLeft, readStrict(env.STATE, `thread:${threadId}`))
          .catch((e) => { log(`card lookup failed, so the record read earlier is used: ${e.message.slice(0, 200)}`); return rec; }) : rec;
      await markCard(discordClient(env.DISCORD_BOT_TOKEN, timedFetch(deps.fetch, TAIL_MS, t0 + RELEASE_BY_MS)), cfg, log, {
        ...cardAfter, cardId: cardAfter.cardId || cardOf(latest), guildId: interaction.guild_id, postId: threadId,
      });
    }
  }
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
    if (!canUse(interaction.member)) return reply('Only moderators and admins can send posts to GitHub.');
    return openForm(interaction, env, deps, { threadId: interaction.channel_id, messageId: interaction.data.target_id, deadline: t0 + FORM_BY_MS });
  }

  if (interaction.type === 3 && String(interaction.data.custom_id).startsWith(`${SEND_BUTTON}:`)) {
    const ids = parseCustomId(interaction.data.custom_id);
    if (!ids) return reply(BAD_IDS);
    const cfg = config(env);
    if (!cfg.roles.length && !canUse(interaction.member)) {
      return reply('The button is not set up yet: APPROVED_ROLE_IDS is empty. A moderator can right-click the post > Apps > Send to GitHub.');
    }
    if (!allowed(interaction.member, cfg)) return reply(NOT_ALLOWED);
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

  if (interaction.type === 5 && String(interaction.data.custom_id).startsWith('gh:')) {
    if (!parseCustomId(interaction.data.custom_id)) return reply(BAD_IDS);
    const cfg = config(env);
    if (!allowed(interaction.member, cfg)) return reply(NOT_ALLOWED);
    if (!cfg.forums.length) return reply('The bot is not set up yet: FORUMS is empty.');
    const v = modalValues(interaction.data);
    const problems = [];
    if (!normRepoKey(v.repo, cfg.repos)) problems.push(`Repo must be ${Object.keys(cfg.repos).join(' or ')}.`);
    if (!normClient(v.client)) problems.push('Client must be Retail, Forever or All.');
    if (!normType(v.type)) problems.push('Type must be Bug or Feature.');
    if (!titleText(v.title)) problems.push('Title is empty.');
    if (problems.length) return reply(`Nothing was created. ${problems.join(' ')} Press the button or right-click the post to try again.`);

    ctx.waitUntil(fileIssue(interaction, env, deps, t0));
    return json({ type: 5, data: { flags: EPHEMERAL } });
  }

  return reply('Unknown command.');
}

export async function scheduled(controller, env, ctx, deps = { fetch: (...a) => fetch(...a) }) {
  if (controller.cron === CRONS.daily) return daily(env, deps);
  return scan(env, deps);
}

export default {
  fetch: (request, env, ctx) => handle(request, env, ctx),
  scheduled: (controller, env, ctx) => ctx.waitUntil(scheduled(controller, env, ctx)),
};
