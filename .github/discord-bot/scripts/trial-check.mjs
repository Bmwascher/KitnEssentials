// Read-only look at test-server posts and channels, for live trials: a post's
// name, forum, tags, archived and locked state and its last messages, or a
// text channel's last messages, or a forum's posts.
//   node scripts/trial-check.mjs <post or channel id>... [--limit N]
//   node scripts/trial-check.mjs --forum <forum id>
// Use a separate bot that has only View Channels and Read Message History,
// with the Message Content intent on, so a leaked token cannot change
// anything. The token comes from TRIAL_READER_TOKEN, else the file
// ~/.discord-trial-reader/token. It is never printed.
import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { discordClient } from '../src/discord.js';

const FORUM_TYPE = 15;

function readToken() {
  if (process.env.TRIAL_READER_TOKEN) return process.env.TRIAL_READER_TOKEN.trim();
  const file = join(homedir(), '.discord-trial-reader', 'token');
  try {
    return readFileSync(file, 'utf8').trim();
  } catch {
    return null;
  }
}

const tagNames = (ids, forum) => (ids || [])
  .map((id) => forum.available_tags.find((t) => t.id === id)?.name || `?${id}`);

const oneLine = (s, max = 300) => {
  const t = String(s || '').replace(/\s+/g, ' ').trim();
  return t.length > max ? `${t.slice(0, max)}...` : t;
};

function messageLines(m) {
  const who = `${m.author.username}${m.author.bot ? ' [bot]' : ''}`;
  const out = [`  ${m.timestamp.slice(0, 19).replace('T', ' ')} ${who}${m.edited_timestamp ? ' (edited)' : ''}: ${oneLine(m.content)}`];
  for (const e of m.embeds || []) {
    out.push(`    embed: ${oneLine([e.title, e.description].filter(Boolean).join(' / '))}`);
  }
  const buttons = (m.components || []).flatMap((row) => row.components)
    .map((c) => `${c.label || c.custom_id || '?'}${c.disabled ? ' (disabled)' : ''}`);
  if (buttons.length) out.push(`    buttons: ${buttons.join(', ')}`);
  return out;
}

export async function describe(api, id, limit) {
  const ch = await api.getChannel(id);
  const out = [];
  if (ch.thread_metadata) {
    const forum = await api.getChannel(ch.parent_id);
    const md = ch.thread_metadata;
    out.push(`Post ${ch.id}: "${ch.name}"`);
    out.push(`  forum: ${forum.name} (${forum.id})`);
    out.push(`  tags: ${tagNames(ch.applied_tags, forum).join(', ') || '(none)'}`);
    out.push(`  archived: ${md.archived ? 'yes' : 'no'}, locked: ${md.locked ? 'yes' : 'no'}`);
  } else {
    out.push(`Channel ${ch.id}: #${ch.name}`);
  }
  const msgs = await api.call('GET', `/channels/${id}/messages?limit=${limit}`);
  out.push(`  last ${msgs.length} messages, oldest first:`);
  for (const m of [...msgs].reverse()) out.push(...messageLines(m));
  return out.join('\n');
}

export async function listForum(api, forumId) {
  const forum = await api.getChannel(forumId);
  if (forum.type !== FORUM_TYPE) throw new Error(`${forumId} is not a forum`);
  const active = (await api.call('GET', `/guilds/${forum.guild_id}/threads/active`)).threads
    .filter((t) => t.parent_id === forumId);
  const archived = (await api.call('GET', `/channels/${forumId}/threads/archived/public?limit=25`)).threads;
  const out = [`Forum ${forum.name} (${forum.id}): ${active.length} open, ${archived.length} recently archived`];
  for (const t of [...active, ...archived]) {
    out.push(`  ${t.id} "${t.name}" [${tagNames(t.applied_tags, forum).join(', ') || 'no tags'}]${t.thread_metadata.archived ? ' archived' : ''}`);
  }
  return out.join('\n');
}

async function main(argv) {
  const token = readToken();
  if (!token) {
    console.error('No token: set TRIAL_READER_TOKEN or write it to ~/.discord-trial-reader/token');
    process.exit(1);
  }
  const api = discordClient(token);
  const li = argv.indexOf('--limit');
  const limit = li >= 0 ? Math.min(100, Math.max(1, Number(argv[li + 1]) || 10)) : 10;
  const fi = argv.indexOf('--forum');
  const values = new Set([li, fi].filter((i) => i >= 0).map((i) => i + 1));
  const ids = argv.filter((a, i) => /^\d+$/.test(a) && !values.has(i));
  if (fi >= 0) console.log(await listForum(api, argv[fi + 1]));
  for (const id of ids) console.log(`${await describe(api, id, limit)}\n`);
  if (fi < 0 && !ids.length) console.error('Usage: node scripts/trial-check.mjs <id>... [--limit N] | --forum <forum id>');
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2)).catch((e) => {
    console.error(e.message);
    process.exit(1);
  });
}
