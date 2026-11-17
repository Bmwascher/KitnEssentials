# Discord bot: forum posts to GitHub issues

Every new, open post in the configured forums gets one message from the bot
with a **Send to GitHub** button (a post closed before the bot saw it gets
none). Someone with an approved role (or a moderator)
presses it, checks a short form, and the bot files the issue in the repo the
form names. The button's message turns into "tracked as KE #17" and the post
is tagged **Triaged**. Moderators can still right-click any post > **Apps >
Send to GitHub** for the same form.

After that the `Discord status` workflow keeps the post in step with its
issue, working out the status from the issue each time rather than stepping
it along:

| The issue | Forum tag | Message in the post (once, when the tag changes) |
| --- | --- | --- |
| Filed | Triaged | "Thanks! This is now tracked as KE #17..." |
| Open, with a non-draft PR that will close it, from someone with a repo role | In progress | "Good news: a fix for this is being worked on and tested..." |
| Closed by a commit or a merged PR in this repo | Fixed, next update | "This is fixed! The fix will be in the next update..." |
| A release tag holds that commit | Shipped | "The fix is out in KitnEssentials v5.0.120..." (post stays open) |
| Closed by hand | Closed | "A moderator has closed this..." |
| Closed as not planned / duplicate | Closed | Short reason |
| `needs-info` label added | (unchanged) | Pings the reporter for details |

A PR that closes or goes back to draft puts the post back to Triaged, quietly.
The In progress message is said once while the issue stays open, however many PRs come
and go.

How the release state is kept: the fix is the commit that last closed the
issue (reopening drops it). When a release tag holds that commit, the workflow
writes a comment on the issue naming the release; if that comment is ever
missing, it is rebuilt from the release tags. The `pending-release` and
`shipped` labels always follow from these, so a release label added by hand is
taken off again. Runs that overlap on one issue each read again after writing
until the answer holds. Whichever run moves the post sends the message for
where it moved, once: the workflow leaves a short comment on the issue for it,
only the run whose note came first sends it, and a message that stopped being
true before its last check is dropped (one overtaken in the moment between
that check and the send still goes out; the next message corrects it). A
daily sweep lists anything still out of step in the job summary, a post with
no status tag and a message whose send failed included (and, with
`SWEEP_MODE=fix`, repairs the labels and tags). The sweep never messages
anyone. To clear a listed message (sent by hand, or not needed), edit that
comment and add `<!-- discord-sent -->` at its end.

Every day the Worker also lists posts older than `STALE_DAYS` that have no
status tag and no `Answered` tag (open posts, and posts archived in the last
30 days) in `MOD_CHANNEL_ID`, and warns there first if the post scan has
stopped, or hit a problem with some post or forum in the last day. A post the bot may not message (locked, or no permission) is skipped; one
that fails six runs in a row is given up on.

Two halves, no always-on server:

- `src/` is a **Cloudflare Worker** (free tier): it answers the button, the
  right-click command and the form, and runs the post scan and the daily check
  on cron triggers.
- `status/status.mjs` runs in **GitHub Actions** (`.github/workflows/discord-status.yml`).
  It does nothing until the `DISCORD_BOT_TOKEN` secret exists, so it is safe to merge early.

None of this ships to players: `.github` is excluded from sync and builds.

## Templates

When the form is sent, the bot checks the post against its template's fields
(a bug: version, details, steps, screenshots; a suggestion: category, summary,
description) and marks each present, missing or unsure. The result goes into
the issue and the moderator's reply only. It never asks the player anything:
check it against real posts first. Set `TEMPLATES` to change the fields.

## Tests

`npm test` (Node 20+, no installs). Every Discord and GitHub call is faked, so
the tests never touch a real server or repo. They also run on GitHub for any
change under this folder (`Discord bot tests` workflow).

## Stage 2: trial on a test server and test repo

Do this on a private Discord server and a throwaway repo (for example
KitnEssentials) before the real ones. Roughly 45 minutes.

1. **Test forums.** On the test server, make the forum channels you will use
   (for example one for Retail bugs, one for Forever bugs, one for
   suggestions), each with the five status tags spelled exactly: `Triaged`,
   `In progress`, `Fixed, next update`, `Shipped`, `Closed`, and an `Answered`
   tag. Copy each forum's id and the server's id (Developer Mode on,
   right-click > Copy ID).
2. **Discord app.** At discord.com/developers/applications: New Application >
   Bot > Reset Token (keep it). Under Privileged Gateway Intents switch on
   **Message Content** (the bot reads the post it is pointed at; it never listens
   to the server). Under Installation set **Install Link** to None first
   (Discord will not save the next step while a default install link exists),
   then under Bot switch **Public Bot** off so only you can invite it.
   Note the Application ID and Public Key from General Information.
3. **Invite it** with OAuth2 > URL Generator: scopes `bot` + `applications.commands`,
   permissions View Channels, Read Message History, Send Messages in Threads,
   Manage Threads.
4. **GitHub App.** github.com/settings/apps > New GitHub App: no webhook,
   Repository permissions **Issues: Read and write**, Metadata: Read. Create,
   generate a private key (a `.pem` downloads), note the App ID, then
   Install App on the test repo only.
5. **Worker.** In this folder: `npx wrangler@3 login`, then
   `npx wrangler@3 secret put` for `DISCORD_PUBLIC_KEY`, `DISCORD_BOT_TOKEN`,
   `GITHUB_APP_ID`, `GITHUB_APP_PRIVATE_KEY` (paste the whole `.pem`). Run
   `npx wrangler@3 kv namespace create STATE` and put its id into the
   commented `[[kv_namespaces]]` lines of `wrangler.toml`. In `wrangler.toml`
   set `REPOS` to `{"KE":"<you>/<test-repo>"}`, `FORUMS` to the forum map,
   `GUILD_ID`, `APPROVED_ROLE_IDS` (a test role) and `MOD_CHANNEL_ID`.
   `FORUMS` is required: while it is empty (and the older `FORUM_CHANNEL_IDS`
   is empty too) the bot does nothing anywhere.
   `npm run deploy` prints a URL. The first scan only starts its clock, so
   posts made before it never get a message.
6. **Point Discord at it.** Developer portal > General Information >
   Interactions Endpoint URL = that URL. Discord checks it on save.
7. **Register the command** on the test server only:
   `DISCORD_APP_ID=... DISCORD_BOT_TOKEN=... DISCORD_GUILD_ID=<test server id> npm run register`
8. **Labels:** `GITHUB_TOKEN=<a token with repo access> npm run labels <you>/<test-repo>`
9. **Status workflow in the test repo:** copy `.github/discord-bot/` and
   `.github/workflows/discord-status.yml` into it and add the repo secret
   `DISCORD_BOT_TOKEN`.

Then walk one fake report through: post in a test forum and wait up to five
minutes for the bot's message, press **Send to GitHub** with the test role,
open a PR with `Fixes #N` into the default branch (from an account with a
role on the repo), merge it, and push a tag. **In this KitnEssentials test
copy, use a `discord-test-1` style tag: its own `v*` tags publish real
releases to CurseForge and Wago.** Each step should change the tag and post
its message. (The workflow here already defaults to that tag pattern; set the
repo variable `RELEASE_TAG_PATTERN` to change it.) Run the `Discord status`
workflow by hand once to see the sweep's report.

## Stage 3: live

Same steps against the real server and repos, with `FORUMS` set to the real
forums and the command at first registered without `DISCORD_GUILD_ID`
(global). Narrow who sees the right-click command under Server Settings >
Integrations > the bot > Send to GitHub (Mod and Admin roles); the button
checks `APPROVED_ROLE_IDS` itself. Leave `SWEEP_MODE` unset (report only)
until a few daily reports look right, then set it to `fix`.

Each repo the bot files into needs its own copy of `discord-status.yml` and
this folder. Set its push trigger to that repo's release tags, and the repo
variable `RELEASE_TAG_PATTERN` to match them (for tags like `30.8`:
`tags: ['*']` and `^\d+\.\d+`).
