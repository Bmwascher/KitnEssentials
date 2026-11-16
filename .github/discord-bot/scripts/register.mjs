// Registers the right-click "Send to GitHub" command. Run once per bot:
//   DISCORD_APP_ID=... DISCORD_BOT_TOKEN=... [DISCORD_GUILD_ID=...] node scripts/register.mjs
// With DISCORD_GUILD_ID it is registered on that server only (shows up instantly; use for testing).
import { COMMAND_NAME } from '../src/worker.js';
import { PERMS } from '../src/core.js';

const { DISCORD_APP_ID: app, DISCORD_BOT_TOKEN: token, DISCORD_GUILD_ID: guild } = process.env;
if (!app || !token) { console.error('Set DISCORD_APP_ID and DISCORD_BOT_TOKEN'); process.exit(1); }

const commands = [{
  name: COMMAND_NAME,
  type: 3, // message context menu
  default_member_permissions: PERMS.manageThreads.toString(), // mods and admins; narrow further in Server Settings > Integrations
  contexts: [0], // servers only
}];
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
