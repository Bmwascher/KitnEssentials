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
| Closed as not planned / duplicate | Closed | Short reason; a duplicate links the other report's post when it came from Discord |
| `needs-info` label added | (unchanged) | Pings the reporter for details |

A PR that closes or goes back to draft puts the post back to Triaged, quietly.
The In progress message is said once while the issue stays open, however many PRs come
and go.

A PR counts from the moment its description says `Fixes #N`: while the work
is unfinished, write `Refs #N`, and editing it to `Fixes #N` moves the post to
In progress. An edit of the title alone starts nothing.

How the release state is kept: the fix is the commit that last closed the
issue (reopening drops it). When a release tag holds that commit, the workflow
writes a comment on the issue naming the release. A fix with no such comment
is checked against the newest release tags, so a fix that a release tag
pushed moments before its close already holds is announced as shipped, not as
coming in the next update. A tag whose name holds alpha, beta, rc or pre, not
inside a longer word (`v2.0-beta`, `v2.0rc1`), never counts as a release. The `pending-release` and `shipped` labels always follow
from these, so a release label added by hand is taken off again. Runs that
overlap on one issue each read again after writing until the answer holds.

Each message to a player has a note on the issue, written before the post's
tag moves: `Notification attempted: ...`. It then becomes `Delivery confirmed`,
`Dropped (...)` (no longer true, the post is gone, or another run claimed it), or
`Unconfirmed (...)` when the send failed and the player may not have it. Of
two runs about to send the same message, only the one whose note came first
sends it. A message that stopped being true before its last check is dropped
(one overtaken in the moment between that check and the send still goes out;
the next message corrects it).

If a setup problem (a missing tag, a missing permission) stops the post's tag
from moving, its message stays owed. The daily sweep leaves that post as it is
and lists the owed message with a link to the run. Fix the setup, then re-run
that run (Re-run failed jobs, or Re-run all jobs for a run that passed), and
the message goes out, even if another run has moved the post in the meantime.
A message is never sent twice. GitHub allows re-runs for 30 days from the
run's first attempt. Once the run has ended, an owed message that no re-run
could send (its post is gone, or what it says is no longer true) is listed,
and a fix-mode sweep marks it `Dropped`. A message the bot dropped was never
sent, so if the same news comes true again (a PR back from draft), the bot
writes a new note and sends it. A note a moderator marked by hand (below)
closes its message for good.

A daily sweep lists anything still out of step in the job summary, a post with
no status tag and an unconfirmed message included (and, with
`SWEEP_MODE=fix`, repairs the labels and tags). The sweep never messages
anyone. To clear a listed message (sent by hand, or not needed), open the
comment the sweep line links to and add `<!-- discord-sent -->` (or
`<!-- discord-dropped -->`) at its end.

Every day the Worker also lists posts older than `STALE_DAYS` that have no
status tag and no `Answered` tag (open posts, and posts archived in the last
30 days) in `MOD_CHANNEL_ID`, and warns there first if the post scan has
stopped, or hit a problem with some post or forum in the last day. A post the bot may not message (locked, or no permission) is skipped; one
that fails 30 runs in a row (about 30 minutes) is given up on.

Two halves, no always-on server:

- `src/` is a **Cloudflare Worker** (free tier): it answers the button, the
  right-click command and the form, and runs the post scan and the daily check
  on cron triggers.
- `status/status.mjs` runs in **GitHub Actions** (`.github/workflows/discord-status.yml`).
  It does nothing until the `DISCORD_BOT_TOKEN` secret exists, so it is safe to merge early.

None of this ships to players: `.github` is excluded from sync and builds.

## Templates

When the form is sent, the bot checks the post against its template's fields
and marks each present, missing or unsure. The result goes into the issue and
the moderator's reply only; the player is never told.

The fields come from, in order:

1. The forum's pinned template message, when its `FORUMS` entry names one.
   Right-click the template message > Copy Message Link, and add it as
   `"template"`, for example
   `{"111":{"client":"Retail","type":"Bug","template":"https://discord.com/channels/1/222/333"}}`.
   The labels are the lines of the message's code block (or of the whole
   message, when it has none) that hold only one to eight words and a colon,
   with nothing after it. A label may use letters, digits, spaces, `'`, `/`,
   `-`, `_` and `*` marks (such as `**` bold); a line with any other mark, such as
   `Screenshots (optional):`, is not a label, so put each hint in ( ) on its
   own line under its label. Edit the pinned message and the next filing
   checks against the new labels, with no redeploy. The message is read at
   each filing and never stored.
2. Otherwise `TEMPLATES`, when it is set. List every label of the template
   there: a label left out reads as part of the answer above it.
3. Otherwise the published templates: a bug's Addon version, UI version,
   Updated with the game closed, What happened, What you expected, How to make
   it happen again and Screenshots; a suggestion's Area, My idea or feedback,
   Why it matters and Screenshots.

If the pinned message cannot be read, or holds no labels, or the `"template"`
value is not a message link (a post's link, say), the moderator's reply says
so and the check falls back to 2 or 3; the filing goes ahead.

## Known limits

Accepted on purpose; each line says how you would notice it.

- A message whose send failed is never sent again automatically: the sweep
  lists it as unconfirmed, and a person decides.
- A post the scan fails to greet in 30 runs in a row (server errors included),
  about 30 minutes at one scan a minute, is given up on; the daily alert names
  it.
- A post can rarely get two greetings when two scans overlap (a scan that runs
  longer than a minute); the second button answers "Already tracked".
- The sweep reads every bot issue ever filed, so it grows with the issue count;
  it fails loudly when it runs out of API calls.
- The workflow reads each issue's closing event in two near-identical queries.
- A few early commits mix two changes; merged history is not rewritten.
- A link made only in a PR's Development sidebar, or a `Fixes #N` removed from
  a description, moves nothing until the issue's next event or a fix-mode
  sweep.
- An owed message goes out only when someone re-runs the run that owes it, even
  if another run has moved the post since; until then the sweep lists it with
  that run's link. GitHub allows re-runs for 30 days from the run's first
  attempt, and 50 at most; after that the sweep says so, and a person sends
  the message by hand if it is still needed. A
  re-run reads the comments of every bot issue once, to find what it owes.
- A message whose send may have gone out but whose note could not then be
  marked is never sent again; the sweep lists it as possibly not reaching the
  player.
- A fix-mode sweep that moves a post in the seconds before the run for the
  same change first reads it leaves that run nothing to send: no note and no
  message, and nothing is listed. The player sees the new status tag without
  its message.
- A status note is changed by replacing its text, and GitHub cannot refuse a
  replace when the note changed since it was read. The bot reads a note again
  just before it sends or drops it; the window left is the time between that
  read and the replace taking effect (usually well under a second):
  - If a fix-mode sweep drops a note while a re-run marks its send failed,
    the note reads Dropped, and later sweeps no longer list the message as
    possibly not reaching the player.
  - If a moderator sends a message by hand while a re-run sends it, the player
    gets it twice.
- Two runs that write a note for the same message at once settle which one
  keeps it. If, while they do, the winner drops its note (a PR went to draft)
  and the PR is ready again before the loser finishes, the loser drops its own
  note too, and the post moves to In progress with no message and nothing
  listed.
- The release check walks release tags newest first and stops at the first
  one without the fix, so it assumes each release tag holds every earlier
  one (one line of history). A release tagged on an older branch with a newer
  commit date can make a shipped fix read "Fixed, next update", or put a
  shipped issue with no ship comment back to `pending-release`.
- An issue whose `from-discord` label, or the bot's marker in its body, is
  removed is no longer read: the sweep stops listing its notes, and a re-run
  no longer sends a message it owes there.
- A note written before this version (`Told the player: ...`) that was never
  marked stays listed as possibly unsent until a person marks it; the bot
  never resends or drops it.
- Only a code block whose fence line starts a line, with at most one plain
  language word, keeps its characters; the bot writes its fence lines. An
  indented fence, or one in a list or quote, shows as plain text, and so does
  inline code: its backticks show, and a `*` or a backslash inside can rarely
  be read as formatting. A diagram word such as `mermaid` is dropped. Code
  indented by four spaces is escaped like text, so `<` shows as `&lt;` there.
- Text between two dollar signs with no space inside them, such as `$a$`, can
  show as a math formula. What is inside stays escaped text.

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

Then walk one fake report through: post in a test forum and wait up to a
minute for the bot's message, press **Send to GitHub** with the test role,
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
variable `RELEASE_TAG_PATTERN` to an anchored pattern that matches only them:
for tags like `v5.0.120`, `tags: ['v*']` and `^v\d+\.\d+\.\d+$`; for tags like
`30.8` or `31`, `tags: ['*']` and `^\d+(\.\d+)*$`. A tag whose name holds alpha,
beta, rc or pre, not inside a longer word, never counts, whatever the pattern
says. The guard misses `preview` and `1.0b1`, so a looser pattern must refuse
those itself.
