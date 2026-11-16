// Cloudflare Worker that answers Discord interactions over HTTP (no gateway,
// no always-on server). One command: right-click a forum post > Apps >
// "Send to GitHub" opens a form; submitting it files the issue.
import {
  STATUS, MESSAGES, buildTitle, buildBody, labelsFor, cleanPostTitle,
  guessFromTags, normClient, normType, normRepoKey,
} from './core.js';
import { discordClient } from './discord.js';
import { githubClient, installationToken } from './github.js';

export const COMMAND_NAME = 'Send to GitHub';
const ADMINISTRATOR = 1n << 3n;
const MANAGE_THREADS = 1n << 34n;
const EPHEMERAL = 64;

const json = (obj, status = 200) => new Response(JSON.stringify(obj), {
  status, headers: { 'Content-Type': 'application/json' },
});
const reply = (content) => json({ type: 4, data: { content, flags: EPHEMERAL } });

function hexToBytes(hex) {
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.substr(i * 2, 2), 16);
  return out;
}

export async function verifyDiscord(publicKeyHex, signatureHex, timestamp, body) {
  if (!signatureHex || !timestamp) return false;
  try {
    const key = await crypto.subtle.importKey('raw', hexToBytes(publicKeyHex), { name: 'Ed25519' }, false, ['verify']);
    return await crypto.subtle.verify('Ed25519', key, hexToBytes(signatureHex), new TextEncoder().encode(timestamp + body));
  } catch {
    return false;
  }
}

export function config(env) {
  const repos = JSON.parse(env.REPOS || '{"AES":"atrocityzero/atrocityEssentials","AUI":"atrocityzero/atrocityUI"}');
  const forums = String(env.FORUM_CHANNEL_IDS || '').split(',').map((s) => s.trim()).filter(Boolean);
  return { repos, forums };
}

function canUse(member) {
  if (!member || member.permissions === undefined) return false;
  const p = BigInt(member.permissions);
  return (p & ADMINISTRATOR) !== 0n || (p & MANAGE_THREADS) !== 0n;
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
  const threadId = interaction.channel_id;
  const messageId = interaction.data.target_id;
  const discord = discordClient(env.DISCORD_BOT_TOKEN, deps.fetch);
  let ch = interaction.channel || {};
  if (!ch.parent_id || !ch.applied_tags) {
    ch = await discord.getChannel(threadId).catch(() => ch);
  }
  if (cfg.forums.length && !cfg.forums.includes(ch.parent_id)) {
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

// Runs after Discord already has its "thinking..." answer, so it may take a while.
export async function fileIssue(interaction, env, deps) {
  const cfg = config(env);
  const [, threadId, messageId] = interaction.data.custom_id.split(':');
  const v = modalValues(interaction.data);
  const repoKey = normRepoKey(v.repo, cfg.repos);
  const client = normClient(v.client);
  const type = normType(v.type);
  const discord = discordClient(env.DISCORD_BOT_TOKEN, deps.fetch);
  const followup = (content) => deps.fetch(
    `https://discord.com/api/v10/webhooks/${interaction.application_id}/${interaction.token}/messages/@original`,
    { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ content }) },
  );

  try {
    const repo = cfg.repos[repoKey];
    const ghToken = await (deps.installationToken || installationToken)(
      { appId: env.GITHUB_APP_ID, privateKey: env.GITHUB_APP_PRIVATE_KEY, repo }, deps.fetch);
    const gh = githubClient(ghToken, deps.fetch);

    const existing = await gh.findByThread(repo, threadId).catch(() => null);
    if (existing) {
      await followup(`Already tracked: ${repoKey} #${existing.number} ${existing.html_url}`);
      return { duplicate: existing.number };
    }

    const message = await discord.call('GET', `/channels/${threadId}/messages/${messageId}`);
    const author = message.author || {};
    const by = interaction.member && interaction.member.user;
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

    const status = await discord.setStatus(threadId, STATUS.triaged).catch((e) => ({ error: e.message }));
    await discord.send(threadId, MESSAGES.tracked(repoKey, issue.number));
    await followup(`Created ${repoKey} #${issue.number}: ${issue.html_url}${status.skipped ? ` (tag not set: ${status.skipped})` : ''}`);
    return { created: issue.number };
  } catch (e) {
    await followup(`Could not create the issue: ${e.message.slice(0, 1500)}`);
    return { error: e.message };
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
