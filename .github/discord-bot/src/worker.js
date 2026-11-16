// Cloudflare Worker that answers Discord interactions over HTTP (no gateway,
// no always-on server). One command: right-click a forum post > Apps >
// "Send to GitHub" opens a form; submitting it files the issue.
import {
  STATUS, MESSAGES, PERMS, buildTitle, buildBody, labelsFor, cleanPostTitle,
  guessFromTags, normClient, normType, normRepoKey, parseRepos, timedFetch,
} from './core.js';
import { discordClient } from './discord.js';
import { githubClient, installationToken, lockLabel } from './github.js';

export const COMMAND_NAME = 'Send to GitHub';
const EPHEMERAL = 64;
// Discord wants the first answer within 3 s; the form's lookups get 1.5 s.
const FORM_LOOKUP_MS = 1500;
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
  const forums = String(env.FORUM_CHANNEL_IDS || '').split(',').map((s) => s.trim()).filter(Boolean);
  return { repos, forums };
}

// A write whose result is unknown: no answer (time limit, network failure) or
// a GitHub server error, which can come after the write was applied.
export function unknownOutcome(e) {
  return /TimeoutError|AbortError|TypeError/.test(e.name) || /-> 5\d\d /.test(e.message);
}

function canUse(member) {
  if (!member || member.permissions === undefined) return false;
  const p = BigInt(member.permissions);
  return (p & PERMS.administrator) !== 0n || (p & PERMS.manageThreads) !== 0n;
}

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

async function openForm(interaction, env, deps) {
  const cfg = config(env);
  if (!canUse(interaction.member)) return reply('Only moderators and admins can send posts to GitHub.');
  if (!cfg.forums.length) return reply('The bot is not set up yet: FORUM_CHANNEL_IDS is empty.');
  const threadId = interaction.channel_id;
  const messageId = interaction.data.target_id;
  const discord = discordClient(env.DISCORD_BOT_TOKEN, timedFetch(deps.fetch, FORM_LOOKUP_MS, Date.now() + FORM_LOOKUP_MS));
  let ch = interaction.channel || {};
  if (!ch.parent_id || !ch.applied_tags) {
    ch = await discord.getChannel(threadId).catch(() => ch);
  }
  if (!cfg.forums.includes(ch.parent_id)) {
    return reply('This only works on posts in the bug and feedback forum.');
  }

  // Pre-fill client and type from the post's own tags; a slow or failed lookup
  // just leaves those fields for the moderator to type.
  let guess = { client: null, type: null };
  try {
    const forum = await discord.getChannel(ch.parent_id);
    const names = (forum.available_tags || []).filter((t) => (ch.applied_tags || []).includes(t.id)).map((t) => t.name);
    guess = guessFromTags(names);
  } catch { /* keep the blanks */ }

  const keys = Object.keys(cfg.repos);
  return json({
    type: 9,
    data: {
      custom_id: `gh:${threadId}:${messageId}`,
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

// Runs after Discord already has its "thinking..." answer. Every call is timed,
// and every outcome, partial ones included, is reported back to the moderator.
export async function fileIssue(interaction, env, deps) {
  const cfg = config(env);
  const [, threadId, messageId] = interaction.data.custom_id.split(':');
  const v = modalValues(interaction.data);
  const repoKey = normRepoKey(v.repo, cfg.repos);
  const client = normClient(v.client);
  const type = normType(v.type);
  const log = deps.log || console.error;
  const { callMs = CALL_MS, budgetMs = FILE_BUDGET_MS } = deps; // tests shorten these
  const t0 = Date.now();
  const f = timedFetch(deps.fetch, callMs, t0 + budgetMs);
  const discord = discordClient(env.DISCORD_BOT_TOKEN, f);
  const followup = async (content) => {
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
  try {
    const ghToken = await (deps.installationToken || installationToken)(
      { appId: env.GITHUB_APP_ID, privateKey: env.GITHUB_APP_PRIVATE_KEY, repo }, f);
    gh = githubClient(ghToken, f);
    ghRecheck = githubClient(ghToken, timedFetch(deps.fetch, TAIL_MS, t0 + RECHECK_BY_MS));
    ghRelease = githubClient(ghToken, timedFetch(deps.fetch, TAIL_MS, t0 + RELEASE_BY_MS));

    // The form may have been opened before the forum list changed: check again.
    const thread = await discord.getChannel(threadId);
    if (!cfg.forums.includes(thread.parent_id)) {
      await followup('Nothing was created: this post is not in a forum the bot is set up for.');
      return { refused: 'forum' };
    }

    // Look, lock, then look again: a send that finished between the first look
    // and the lock has released its lock but left its issue.
    const already = async () => {
      const existing = await gh.findByThread(repo, threadId);
      if (existing) await followup(`Already tracked: ${repoKey} #${existing.number} ${existing.html_url}`);
      return existing;
    };
    let existing = await already();
    if (existing) return { duplicate: existing.number };
    try {
      locked = await gh.claimThread(repo, threadId);
    } catch (e) {
      // The lock label may exist even though the answer was lost.
      if (!unknownOutcome(e)) throw e;
      await followup(`Nothing was created: GitHub did not confirm the lock (${e.message.slice(0, 200)}). If a later send says another send is running, delete the label ${lockLabel(threadId)} in ${repo} and try again.`);
      return { error: e.message, uncertain: 'lock' };
    }
    if (!locked) {
      await followup(`Nothing was created: another send of this post is running, or one stopped partway. If no issue appears, delete the label ${lockLabel(threadId)} in ${repo} and try again.`);
      return { busy: true };
    }
    existing = await already();
    if (existing) return { duplicate: existing.number };

    const message = await discord.call('GET', `/channels/${threadId}/messages/${messageId}`);
    const author = message.author || {};
    const by = interaction.member && interaction.member.user;
    creating = true;
    const issue = await gh.createIssue(repo, {
      title: buildTitle({ repoKey, client, module: v.module, title: v.title }),
      body: buildBody({
        content: message.content,
        reporterName: author.global_name || author.username || 'unknown',
        reporterId: author.id,
        threadId,
        threadUrl: `https://discord.com/channels/${interaction.guild_id}/${threadId}`,
        client,
        attachments: message.attachments,
        sentBy: by ? (by.global_name || by.username) : null,
      }),
      labels: labelsFor({ type, client }),
    });
    creating = false;

    // The issue exists from here on: report it whatever else fails.
    const notes = [];
    try {
      const status = await discord.setStatus(threadId, STATUS.triaged);
      if (status.skipped) notes.push(`tag not set: ${status.skipped}`);
    } catch (e) { notes.push(`tag not set: ${e.message.slice(0, 300)}`); }
    try {
      await discord.send(threadId, MESSAGES.tracked(repoKey, issue.number));
    } catch (e) { notes.push(`note in the post not sent: ${e.message.slice(0, 300)}`); }
    await followup(`Created ${repoKey} #${issue.number}: ${issue.html_url}${notes.length ? ` (${notes.join('; ')})` : ''}`);
    return { created: issue.number, notes };
  } catch (e) {
    // A create that got no answer may still have happened on GitHub's side:
    // look once more, and if it is not there yet keep the lock, so a retry
    // cannot file a second issue while the first may still appear.
    if (creating && unknownOutcome(e)) {
      const found = await ghRecheck.findByThread(repo, threadId).catch(() => null);
      if (found) {
        await followup(`Created ${repoKey} #${found.number}: ${found.html_url} (GitHub answered late; the post's tag and note were not set)`);
        return { created: found.number, late: true };
      }
      keepLock = true;
      await followup(`The issue may have been created: GitHub did not answer in time. If none appears in ${repo} within a few minutes, delete the label ${lockLabel(threadId)} there and send the post again.`);
      return { error: e.message, uncertain: true };
    }
    await followup(`Nothing was created: ${e.message.slice(0, 1500)}`);
    return { error: e.message };
  } finally {
    if (locked && !keepLock) {
      try { await ghRelease.releaseThread(repo, threadId); } catch (e) { log(`lock ${lockLabel(threadId)} not released: ${e.message}`); }
    }
  }
}

export async function handle(request, env, ctx, deps = { fetch: (...a) => fetch(...a) }) {
  if (request.method !== 'POST') return new Response('ok');
  const body = await request.text();
  const ok = await verifyDiscord(env.DISCORD_PUBLIC_KEY,
    request.headers.get('X-Signature-Ed25519'), request.headers.get('X-Signature-Timestamp'), body);
  if (!ok) return new Response('bad signature', { status: 401 });

  const interaction = JSON.parse(body);
  if (interaction.type === 1) return json({ type: 1 });

  if (interaction.type === 2 && interaction.data.name === COMMAND_NAME) {
    return openForm(interaction, env, deps);
  }

  if (interaction.type === 5 && String(interaction.data.custom_id).startsWith('gh:')) {
    if (!canUse(interaction.member)) return reply('Only moderators and admins can send posts to GitHub.');
    const cfg = config(env);
    if (!cfg.forums.length) return reply('The bot is not set up yet: FORUM_CHANNEL_IDS is empty.');
    const v = modalValues(interaction.data);
    const problems = [];
    if (!normRepoKey(v.repo, cfg.repos)) problems.push(`Repo must be ${Object.keys(cfg.repos).join(' or ')}.`);
    if (!normClient(v.client)) problems.push('Client must be Retail, Forever or All.');
    if (!normType(v.type)) problems.push('Type must be Bug or Feature.');
    if (!String(v.title || '').trim()) problems.push('Title is empty.');
    if (problems.length) return reply(`Nothing was created. ${problems.join(' ')} Right-click the post to try again.`);

    ctx.waitUntil(fileIssue(interaction, env, deps));
    return json({ type: 5, data: { flags: EPHEMERAL } });
  }

  return reply('Unknown command.');
}

export default { fetch: (request, env, ctx) => handle(request, env, ctx) };
