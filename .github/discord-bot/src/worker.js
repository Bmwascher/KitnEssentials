// Cloudflare Worker that answers Discord interactions over HTTP (no gateway,
// no always-on server). Two ways in, one form: the "Send to GitHub" button
// the scheduled scan puts in each new post (approved roles), or right-click
// a post > Apps > "Send to GitHub" (moderators). Submitting the form files
// the issue.
import {
  STATUS, MESSAGES, PERMS, buildTitle, buildBody, labelsFor, cleanPostTitle,
  guessFromTags, normClient, normType, normRepoKey, parseRepos, timedFetch,
  parseForums, parseRoleIds, parseTemplates, templateCheck, templateGaps,
  templateNote, parseCustomId, templateLabels,
} from './core.js';
import { discordClient } from './discord.js';
import { githubClient, installationToken, lockLabel } from './github.js';
import { scan, daily, CRONS, SEND_BUTTON, threadRecord, saveThreadRecord } from './scan.js';

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

async function openForm(interaction, env, deps, { threadId, messageId, greetingId = '' }) {
  const cfg = config(env);
  if (!cfg.forums.length) return reply('The bot is not set up yet: FORUMS is empty.');
  const discord = discordClient(env.DISCORD_BOT_TOKEN, timedFetch(deps.fetch, FORM_LOOKUP_MS, Date.now() + FORM_LOOKUP_MS));
  let ch = interaction.channel && interaction.channel.id === threadId ? interaction.channel : {};
  if (!ch.parent_id || !ch.applied_tags) {
    ch = await discord.getChannel(threadId).catch(() => ch);
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
      custom_id: `gh:${threadId}:${messageId}${greetingId ? `:${greetingId}` : ''}`,
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

// Runs after Discord already has its "thinking..." answer. Every call is timed,
// and every outcome, partial ones included, is reported back to the moderator.
export async function fileIssue(interaction, env, deps) {
  const cfg = config(env);
  const { threadId, messageId, greetingId } = parseCustomId(interaction.data.custom_id);
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

    // Lock, then look once: any send that finished before the lock was
    // granted has left its issue to be found. The post's KV record, when it
    // names the issue, saves reading the whole issue list.
    const kv = env.STATE;
    const rec = await threadRecord(kv, threadId).catch(() => null);
    const already = async () => {
      let existing = null;
      if (rec && rec.issue && rec.issue.repo === repo) {
        existing = await gh.getIssue(repo, rec.issue.number).catch((e) => { if (/-> 404 /.test(e.message)) return null; throw e; });
      }
      if (!existing) existing = await gh.findByThread(repo, threadId);
      if (existing) await followup(`Already tracked: ${repoKey} #${existing.number} ${existing.html_url}`);
      return existing;
    };
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
    const existing = await already();
    if (existing) return { duplicate: existing.number };

    const message = await discord.call('GET', `/channels/${threadId}/messages/${messageId}`);
    const author = message.author || {};
    const by = interaction.member && interaction.member.user;
    // The template read ends a full call's time before the filing's deadline,
    // so the create can always start.
    const template = await templateFields(cfg, thread.parent_id, type, env, deps, t0 + budgetMs - callMs, log);
    const check = template.fields.length ? templateCheck(message.content, template.fields, (message.attachments || []).length) : [];
    const gaps = templateGaps(check, template.optional);
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
        templateLine: check.length ? gaps.join(' · ') || 'every field present' : null,
      }),
      labels: labelsFor({ type, client }),
    });
    creating = false;

    // The issue exists from here on: report it whatever else fails.
    const notes = [];
    if (template.note) notes.push(template.note);
    try {
      const status = await discord.setStatus(threadId, STATUS.triaged);
      if (status.skipped) notes.push(`tag not set: ${status.skipped}`);
    } catch (e) { notes.push(`tag not set: ${e.message.slice(0, 300)}`); }
    try {
      await saveThreadRecord(kv, threadId, { issue: { repo, number: issue.number } });
    } catch (e) { notes.push(`post record not saved: ${e.message.slice(0, 200)}`); }
    // One bot message per post: the button's message becomes the note.
    const greeting = greetingId || (rec && rec.greeting);
    try {
      if (greeting) {
        await discord.call('PATCH', `/channels/${threadId}/messages/${greeting}`, {
          content: MESSAGES.tracked(repoKey, issue.number), components: [], allowed_mentions: { parse: [] },
        });
      } else {
        await discord.send(threadId, MESSAGES.tracked(repoKey, issue.number));
      }
    } catch (e) { notes.push(`note in the post not sent: ${e.message.slice(0, 300)}`); }
    const tmpl = gaps.length ? ` Template: ${gaps.join(', ')}.` : '';
    await followup(`Created ${repoKey} #${issue.number}: ${issue.html_url}${notes.length ? ` (${notes.join('; ')})` : ''}${tmpl}`);
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
    if (!canUse(interaction.member)) return reply('Only moderators and admins can send posts to GitHub.');
    return openForm(interaction, env, deps, { threadId: interaction.channel_id, messageId: interaction.data.target_id });
  }

  if (interaction.type === 3 && String(interaction.data.custom_id).startsWith(`${SEND_BUTTON}:`)) {
    const ids = parseCustomId(interaction.data.custom_id);
    if (!ids) return reply(BAD_IDS);
    const cfg = config(env);
    if (!cfg.roles.length && !canUse(interaction.member)) {
      return reply('The button is not set up yet: APPROVED_ROLE_IDS is empty. A moderator can right-click the post > Apps > Send to GitHub.');
    }
    if (!allowed(interaction.member, cfg)) return reply(NOT_ALLOWED);
    // A forum post's first message has the post's own id.
    return openForm(interaction, env, deps, { threadId: ids.threadId, messageId: ids.threadId, greetingId: interaction.message && interaction.message.id });
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
    if (!String(v.title || '').trim()) problems.push('Title is empty.');
    if (problems.length) return reply(`Nothing was created. ${problems.join(' ')} Press the button or right-click the post to try again.`);

    ctx.waitUntil(fileIssue(interaction, env, deps));
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
