# Discord bot: #aui-help posts to GitHub issues

A moderator right-clicks a forum post, picks **Apps > Send to GitHub**, and fills
a short form. The bot files the issue in this repo (or atrocityUI), tags the
post **Triaged** and tells the player. After that, the `Discord status`
workflow moves the post along on its own:

| On GitHub | Forum tag | Message in the post |
| --- | --- | --- |
| Mod sends the post | Triaged | "Thanks! This is now tracked as AES #17..." |
| A PR saying `Fixes #17` opens | In progress | "A fix is up and being tested." |
| That PR is merged into `dev` | Fixed, next update | "The fix is merged and will be in the next update." |
| A release tag is pushed (`v5.0.120`) | Shipped | "The fix landed in atrocityEssentials v5.0.120..." (post stays open) |
| Issue closed as not planned / duplicate | Closed | Short reason |
| `needs-info` label added | (unchanged) | Pings the reporter for details |

Two halves, no always-on server:

- `src/` is a **Cloudflare Worker** (free tier) that answers the right-click
  command and the form.
- `status/status.mjs` runs in **GitHub Actions** (`.github/workflows/discord-status.yml`).
  It does nothing until the `DISCORD_BOT_TOKEN` secret exists, so it is safe to merge early.

None of this ships to players: `.github` is excluded from sync and builds.

## Tests

`npm test` (Node 20+, no installs). Every Discord and GitHub call is faked, so
the tests never touch a real server or repo. They also run on GitHub for any
change under this folder (`Discord bot tests` workflow).

## Stage 2: trial on a test server and test repo

Do this on a private Discord server and a throwaway repo (for example
KitnEssentials) before the real ones. Roughly 30 minutes.

1. **Test forum.** On the test server, make a forum channel with the same tags
   as #aui-help (Retail, Forever, Bug, Feedback/Request) plus the five status
   tags, spelled exactly: `Triaged`, `In progress`, `Fixed, next update`,
   `Shipped`, `Closed`. Copy the forum's channel id (Developer Mode on, right-click > Copy Channel ID).
2. **Discord app.** At discord.com/developers/applications: New Application >
   Bot > Reset Token (keep it). Under Privileged Gateway Intents switch on
   **Message Content** (the bot reads the post it is pointed at; it never listens
   to the server). Note the Application ID and Public Key from General Information.
3. **Invite it** with OAuth2 > URL Generator: scopes `bot` + `applications.commands`,
   permissions View Channels, Read Message History, Send Messages in Threads,
   Manage Threads.
4. **GitHub App.** github.com/settings/apps > New GitHub App: no webhook,
   Repository permissions **Issues: Read and write**, Metadata: Read. Create,
   generate a private key (a `.pem` downloads), note the App ID, then
   Install App on the test repo only.
5. **Worker.** In this folder: `npx wrangler@3 login`, then
   `npx wrangler@3 secret put` for `DISCORD_PUBLIC_KEY`, `DISCORD_BOT_TOKEN`,
   `GITHUB_APP_ID`, `GITHUB_APP_PRIVATE_KEY` (paste the whole `.pem`). In
   `wrangler.toml` set `REPOS` to `{"AES":"<you>/<test-repo>"}` and
   `FORUM_CHANNEL_IDS` to the test forum's id. `npm run deploy` prints a URL.
6. **Point Discord at it.** Developer portal > General Information >
   Interactions Endpoint URL = that URL. Discord checks it on save.
7. **Register the command** on the test server only:
   `DISCORD_APP_ID=... DISCORD_BOT_TOKEN=... DISCORD_GUILD_ID=<test server id> npm run register`
8. **Labels:** `GITHUB_TOKEN=<a token with repo access> npm run labels <you>/<test-repo>`
9. **Status workflow in the test repo:** copy `.github/discord-bot/` and
   `.github/workflows/discord-status.yml` into it, add the repo secret
   `DISCORD_BOT_TOKEN`, and the repo variable `DISCORD_BOT_REPOS` =
   `{"AES":"<you>/<test-repo>"}`.

Then walk one fake report through: post in the test forum, right-click > Send
to GitHub, open a PR with `Fixes #N` into the default branch, merge it, and
push a tag. **In this KitnEssentials test copy, use a `discord-test-1` style
tag: its own `v*` tags publish real releases to CurseForge and Wago.** Each
step should change the tag and post its message. (The workflow here already
defaults to this repo and that tag pattern, so step 9's variable is optional.)

## Stage 3: live

Same steps against the real server and repos, with the command at first
registered without `DISCORD_GUILD_ID` (global). Narrow who sees it under Server
Settings > Integrations > the bot > Send to GitHub (Mod and Admin roles).

atrocityUI needs its own copy of `discord-status.yml` and this folder, with
`tags: ['*']` in the trigger and the repo variable `RELEASE_TAG_PATTERN` =
`^\d+\.\d+` (its tags look like `30.8`).
