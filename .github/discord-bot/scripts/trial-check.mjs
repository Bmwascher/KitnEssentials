// Read-only look at test-server posts and channels, for live trials: a post's
// name, forum, tags, archived and locked state and its last messages, or a
// text channel's last messages, or a forum's posts.
//   node scripts/trial-check.mjs <post or channel id>... [--limit N]
//   node scripts/trial-check.mjs --forum <forum id>
// Use a separate bot invited with only View Channels and Read Message
// History, with the Message Content intent on, on a test server only (it
// also gets whatever @everyone may do there). The token comes from
// TRIAL_READER_TOKEN, else the file ~/.discord-trial-reader/token. It is
// never printed.
import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { discordClient } from '../src/discord.js';

const FORUM_TYPE = 15;

// A token with a character a header cannot hold would make fetch quote the
// whole Authorization header in its error.
function readToken() {
  let token = process.env.TRIAL_READER_TOKEN;
  if (!token) {
    try {
      token = readFileSync(join(homedir(), '.discord-trial-reader', 'token'), 'utf8');
    } catch {
      return null;
    }
  }
  token = token.trim();
  return /^[!-~]+$/.test(token) ? token : null;
}

const tagNames = (ids, forum) => (ids || [])
  .map((id) => forum.available_tags.find((t) => t.id === id)?.name || `?${id}`);

// Whole, never cut: a cut could split the token and hide it from main's mask.
const oneLine = (s) => s.replace(/\s+/g, ' ').trim();

function messageLines(m) {
  const who = `${m.author.username}${m.author.bot ? ' [bot]' : ''}`;
  const out = [`  ${m.timestamp.slice(0, 19).replace('T', ' ')} ${who}${m.edited_timestamp ? ' (edited)' : ''}: ${oneLine(m.content)}`];
  for (const e of m.embeds) {
    out.push(`    embed: ${oneLine([e.title, e.description].filter(Boolean).join(' / '))}`);
  }
  const buttons = (m.components || []).flatMap((row) => row.components || [])
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
  const page = await api.call('GET', `/channels/${forumId}/threads/archived/public?limit=50`);
  const out = [`Forum ${forum.name} (${forum.id}): ${active.length} open, ${page.threads.length} newest archived`];
  for (const t of [...active, ...page.threads]) {
    out.push(`  ${t.id} "${t.name}" [${tagNames(t.applied_tags, forum).join(', ') || 'no tags'}]${t.thread_metadata.archived ? ' archived' : ''}`);
  }
  if (page.has_more) out.push('  older archived posts are not listed');
  return out.join('\n');
}

const USAGE = 'Usage: node scripts/trial-check.mjs <id>... [--limit 1-100] | --forum <forum id>';
const isId = (a) => /^\d+$/.test(a || '');

// Every argument must be an id or an option with its value, so a typo is an
// error instead of a request for the wrong channel.
export function parseArgs(argv) {
  const out = { ids: [], limit: 10, forum: null };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--limit' && isId(argv[i + 1]) && +argv[i + 1] >= 1 && +argv[i + 1] <= 100) out.limit = +argv[++i];
    else if (a === '--forum' && !out.forum && isId(argv[i + 1])) out.forum = argv[++i];
    else if (isId(a)) out.ids.push(a);
    else return null;
  }
  return out.forum || out.ids.length ? out : null;
}

async function main(argv) {
  const args = parseArgs(argv);
  if (!args) {
    console.error(USAGE);
    process.exit(1);
  }
  const token = readToken();
  if (!token) {
    console.error('No usable token: set TRIAL_READER_TOKEN or save the token alone, on one line, in ~/.discord-trial-reader/token');
    process.exit(1);
  }
  // A message on the server can quote the token itself.
  const hide = (text) => text.split(token).join('<reader token>');
  const api = discordClient(token);
  try {
    if (args.forum) console.log(hide(await listForum(api, args.forum)));
    for (const id of args.ids) console.log(hide(`${await describe(api, id, args.limit)}\n`));
  } catch (e) {
    console.error(hide(e.message));
    process.exit(1);
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] || '').href) main(process.argv.slice(2));
