// Registers the bot's four commands: the right-click "Send to GitHub",
// "Add to issue" and "Move post", and the /bot-check setup check. Run once
// per bot, and again after any changes:
//   DISCORD_APP_ID=... DISCORD_BOT_TOKEN=... [DISCORD_GUILD_ID=...] node scripts/register.mjs
// With DISCORD_GUILD_ID they are registered on that server only (they show up
// instantly; use for testing). The PUT replaces every command of every type,
// so all four are always sent together.
import { COMMAND_NAME, CHECK_COMMAND, MOVE_COMMAND, ADD_COMMAND } from '../src/worker.js';
import { PERMS } from '../src/core.js';

const { DISCORD_APP_ID: app, DISCORD_BOT_TOKEN: token, DISCORD_GUILD_ID: guild } = process.env;
if (!app || !token) { console.error('Set DISCORD_APP_ID and DISCORD_BOT_TOKEN'); process.exit(1); }

// Mods and admins; narrow further in Server Settings > Integrations.
const mods = PERMS.manageThreads.toString();
const commands = [
  { name: COMMAND_NAME, type: 3, default_member_permissions: mods, contexts: [0] }, // message context menu
  { name: ADD_COMMAND, type: 3, default_member_permissions: mods, contexts: [0] },
  { name: MOVE_COMMAND, type: 3, default_member_permissions: mods, contexts: [0] },
  { name: CHECK_COMMAND, type: 1, description: "Check the bot's setup: config, permissions, tags and GitHub access", default_member_permissions: mods, contexts: [0] },
];
const url = guild
  ? `https://discord.com/api/v10/applications/${app}/guilds/${guild}/commands`
  : `https://discord.com/api/v10/applications/${app}/commands`;
const res = await fetch(url, {
  method: 'PUT',
  headers: { Authorization: `Bot ${token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify(commands),
});
console.log(res.status, await res.text());
if (!res.ok) process.exit(1);
