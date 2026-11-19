# Discord bot: forum posts to GitHub issues

Every new, open post in the configured forums gets a short greeting from the
bot, "Thanks for posting! A moderator will take a look soon, and we'll post
updates here." (a post closed before the bot saw it gets none). With
`QUEUE_CHANNEL_ID` set, the bot also puts a card for the post in that staff
channel: the post's name, who posted it and what kind it is, with a **Send to
GitHub** button and an **Open post** link. Someone with an approved role (or a
moderator) presses the button, checks a short form, and the bot files the
issue in the repo the form names. The bot then replies to the filed message
with "tracked as KE #17", which pings its author, tags the post **Triaged**
when it shows no status yet, and changes the card to "Filed as KE #17 by
<name>". Moderators can still right-click any post or message > **Apps > Send
to GitHub** for the same form; the reply then goes to that message, and the
post's card is marked filed too. A greeting from an earlier version that still
shows its own button keeps working; once the reply exists, the bot deletes it,
or removes its button if it may not delete it.

The greeting and the card go out in the same scan: new posts are greeted
first, then cards still owed by older posts go out, then the new posts'
cards. A post filed before the scan reaches it (by right-click, say) gets
neither, also when its filing record was not saved: the bot finds its own
"now tracked" reply in the post, and it looks again before each card, so a
post filed after its greeting gets no card either. If the card cannot go
out yet, the scan tries again each minute while the post is open, without
sending the greeting again. A card goes out only to a post still open when
it is sent. A post whose first message was deleted gets a card without the
button, which says to open the post and right-click a message in it, since
the form files the first message.

A card can still offer **Send to GitHub** after its post is filed (see Known
limits). Pressing a card of a post already filed is safe: the bot first
checks whether the post is on GitHub (its saved filing record, else every
repo in `REPOS`), answers you privately "Already tracked as KE #17" with the
link, and marks that card filed; no form opens and no one is pinged. The form
opens only after that check finished and found nothing. If the check cannot
finish, you are asked to press again; if that keeps happening, right-click the
post instead (the form's submission checks too).

After that the `Discord status` workflow keeps the post in step with its
issue, working out the status from the issue each time rather than stepping
it along:

| The issue | Forum tag | Message in the post (once, when the tag changes) |
| --- | --- | --- |
| Filed | Triaged | "Thanks! This is now tracked as KE #17..." |
| Open, with a non-draft PR that will close it, from someone with a repo role | In progress | "**In progress.** A fix for this is being worked on and tested..." |
| Closed by a commit or a merged PR in this repo | Fixed, next update | "**Fixed!** The fix will be in the next update..." |
| A release tag holds that commit | Shipped | "**Out now in SomeAddon v5.0.120.** Update your addons..." (post stays open) |
| Closed by hand | Closed | "**Closed.** A moderator has closed this..." |
| Closed as not planned / duplicate | Closed | "**Not planned.** ..." or "**Duplicate.** ..."; a duplicate links the other report's post when it came from Discord |
| `needs-info` label added | (unchanged) | Pings the reporter for details |

"Now tracked" and every status message are replies to the reporter's message,
the one the issue was filed from, so Discord pings the reporter even when
their notifications are set to only @mentions. An issue filed before this
version replies to the post's first message, with a ping, only when that
message is the reporter's; otherwise the message goes out with no reply and no
ping. If Discord refuses the reply, the message goes out once as a plain
message, with no ping, and the log says so: the workflow run's for a status
message, the Worker's for "now tracked". If Discord refuses "now tracked"
in any other way, the bot turns its greeting in the post into that note
instead, and the moderator's reply says when the note was not sent, or may
not have been. A message whose note was written before
this version goes out in that note's own words. The issue's first workflow
run, about a minute after filing, sets the status GitHub calls for when the
bot could not.

A PR that closes or goes back to draft puts the post back to Triaged, quietly.
The In progress message is said once while the issue stays open, however many PRs come
and go.

A PR counts from the moment its description says `Fixes #N`: while the work
is unfinished, write `Refs #N`, and editing it to `Fixes #N` moves the post to
In progress. An edit of the title alone starts nothing. GitHub does not read
the description again when only a PR's base branch changes, so after changing
the base, edit and save the description once. A PR into a branch other than
the default branch lists no closing issues, so it moves nothing.

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
A message is never sent twice by the bot, except in the rare race under Known
limits. GitHub allows re-runs for 30 days from the
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

- `src/` is a **Cloudflare Worker** (free plan, or Workers Paid for repos
  with thousands of bot issues, see Known limits): it answers the button, the
  right-click command and the form, and runs the post scan and the daily check
  on cron triggers.
- `status/status.mjs` runs in **GitHub Actions** (`.github/workflows/discord-status.yml`).
  It does nothing until the `DISCORD_BOT_TOKEN` secret exists, so it is safe to merge early.

None of this ships to players: `.github` is excluded from sync and builds.

## The issue

The issue opens with a small table: the reporter and the moderator who filed
it, each as their server name linked to their Discord profile, with their
username (a webhook's post shows its name alone), and a link to the post. The
quoted report follows, then the attachment count and the template check. The
issue keeps those names, usernames and Discord ids as they were at filing; a
maintainer removes them by editing the issue. Two hidden lines at the end name
the filed message and the post; leave them in place.

One post gets one issue, across every repo in `REPOS`. Before filing, the bot
reads the issue the post's saved filing record names, then searches every
configured repo twice for the post's hidden line; a match anywhere answers
"Already tracked" and files nothing, and a check that fails, or a token the
bot cannot get, files nothing and names the repo to try again for. A saved issue that answers "not found" (404) also files
nothing: GitHub answers the same for an issue the app can no longer see, so
the bot names it and says how to clear the record (below). Two filings of one
post at the same moment, into any repos, make one issue: each takes a lock
label, `discord-lock-<post id>`, in `LOCK_REPO`.

## Clearing a filing record

When the bot refuses a filing because the issue the post's saved record names
could not be checked, and that issue is really gone, clear the record in this
folder, then send the post again. This keeps the post's greeting and card
ids, so nothing is posted twice:

1. Delete the Worker's record:
   `npx wrangler@3 kv key delete --binding=STATE "issue:<post id>"`
2. Read the scan's record:
   `npx wrangler@3 kv key get --binding=STATE "thread:<post id>"`
3. If it holds an `"issue"` field (a post filed before this version), write it
   back without that field, keeping every other field as it was:
   `npx wrangler@3 kv key put --binding=STATE "thread:<post id>" '<the record without "issue">'`

A record the bot calls damaged (empty, not JSON, or not a record the bot
writes, such as a filing record with no repo or issue number) holds nothing
to keep: delete the key it names, `issue:<post id>` as in step 1 or
`thread:<post id>` the same way. The post scan never writes over a damaged
record: it gives that post no greeting and no card, and the next daily
alert names it. Deleting `thread:<post id>` loses the card's id, so a later
filing by right-click leaves that card live; press it once to mark it filed.

## Changing the lock repo

Every filing takes its lock in `LOCK_REPO` (with one repo in `REPOS`, empty
means that repo). A filing that stopped without knowing whether its issue was
made keeps its lock label, so the post cannot be filed again until someone
checks. Versions before this one took the lock in the repo the form chose, so
when you deploy this version, or change `LOCK_REPO`:

1. Ask everyone who can file (the approved roles and the moderators) to stop
   for a few minutes: no button presses, no right-clicks, and no sending a
   form that is already open; cancel it instead.
2. Wait two minutes. A filing ends within 30 seconds of its form being sent,
   so after two minutes no filing the old setup started is still running.
3. Deploy this version, or the new `LOCK_REPO` setting.
4. In every repo that held locks before (each repo in `REPOS` for an older
   version, the old `LOCK_REPO` otherwise), open Issues > Labels and search
   for `discord-lock-`.
5. For each label found, search every repo in `REPOS` for the post's issue
   (the post id is the label's number).
   - If the issue exists, delete the label.
   - If it does not, and you know that filing failed, delete the label.
   - If it does not, and you are not sure: when the label is already in the
     new `LOCK_REPO`, leave it as it is; otherwise make a label of the same
     name in the new `LOCK_REPO` (once, when old repos hold the same name),
     then delete the old one.
6. Tell everyone they can file again.

## Templates

When the form is sent, the bot checks the post against its template's fields.
The issue lists the fields that are missing or unsure ("every field present"
when none are), and the moderator's reply names the same gaps (nothing when
there are none); the player is never told.

The fields come from, in order:

1. The forum's pinned template message, when its `FORUMS` entry names one.
   Right-click the template message > Copy Message Link, and add it as
   `"template"`, for example
   `{"111":{"client":"Retail","type":"Bug","template":"https://discord.com/channels/1/222/333"}}`.
   The labels are the lines of the message's first code block (or of the
   whole message, when it has none) that hold one to eight words and a colon.
   A label may use letters, digits, spaces, `'`, `/`, `-`, `_` and `*` marks
   (such as `**` bold), and may carry a `?` or a ( ) part before its colon and
   one ( ) hint after it, which its name drops: `Updated addons outside of
   game? (Yes/No):` is the label "Updated addons outside of game". A label
   marked with the word `(optional)`, such as `Screenshots (optional):`, is
   never reported as a gap. Text on a code block's opening line, after the
   backticks, is a label line too, unless it is one plain language word such
   as `yaml`. A line with other text after its colon, such as `Note: only in
   raids`, is no label. Edit the pinned message and the next filing
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
so in a plain sentence (the message was not found, the bot may not read it, or
it could not be read just now; the Worker log keeps Discord's error) and the
check falls back to 2 or 3; the filing goes ahead.

## Known limits

Accepted on purpose; each line says how you would notice it.

- A message whose send failed is never sent again automatically: the sweep
  lists it as unconfirmed, and a person decides.
- A post the scan fails to greet in 30 runs in a row (server errors included),
  about 30 minutes at one scan a minute, is given up on; the daily alert names
  it.
- A post can rarely get two greetings when two scans overlap (a scan that runs
  longer than a minute).
- A queue card can stay live on a filed post, or a post can get two cards:
  two overlapping scans, a card send whose answer was lost and that has since
  scrolled past the queue channel's last 100 messages, a card posted while
  its post was being filed, a post archived in the moment between the scan's
  last read of it and its card, or a failed card edit. Nothing lists such
  cards. Once the post is filed, pressing one answers "Already tracked" and
  marks that card filed, and a form it opened earlier files nothing. While
  the post is not yet filed, both cards offer the form; filing from one marks
  only that one, and the other is marked when someone presses it.
- A queue card for a post that never needs an issue stays in the queue
  channel until someone deletes it.
- If presses keep answering "press again" (GitHub slow or failing), right-click
  the post instead: it opens the form with no check, and the form's submission
  checks.
- A post scanned while the queue channel refuses the bot (it was not let into
  the channel yet) gets no card, even after the permission is fixed. The next
  daily alert names each such post, and moderators file it by right-click.
- A post archived or locked before its card went out gets no card, and nothing
  names the missing card. The daily waiting list covers it only in part: it
  lists posts older than `STALE_DAYS` (3 by default) with no status or
  `Answered` tag, leaves out locked posts, reads archived posts from the last
  30 days only (up to 300 per forum), and names about 20 posts at most.
  Right-click filing always works.
- A post whose greeting and card keep failing for 30 tries in all is given up
  on: before the greeting is out, it gets neither; after, it keeps its
  greeting and gets no card. The next daily alert names every post given up
  on since the last one, with its link, and moderators file it by
  right-click. With more than about 65 of them, the alert fills the daily
  check's four messages, so that day's list of waiting posts goes to the
  Worker's log instead of the moderator channel; past about 85, so does the
  alert's last part.
- If the bot's greeting went out but its id was not saved, the next scan looks
  for it among the post's last 100 messages; a post busier than that can get
  a second greeting. The same look finds the bot's "now tracked" reply, so a
  post filed without a saved record gets no greeting after it, unless the
  filing lands in the moment between that look and the greeting's send.
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
    possibly not reaching the player. The bot then reads the message as never
    sent, so if the same news comes true again (a PR back from draft), it
    writes a new note and sends the message again; the player may get it
    twice.
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
- Discord takes only a whole tag list, so a tag someone adds to a post in the
  moment between the bot's last read of its tags and its write can be lost.
  The bot reads the tags again just before each write, so that moment is one
  request long.
- The status workflow never drops a tag of yours to show Triaged: a post with
  no status and five other tags shows no status until a slot is free or a
  status with news arrives (that one takes the fifth slot, as filing does),
  and the sweep lists it meanwhile.
- The Worker sets Triaged only on a post with no status. If the issue's first
  workflow runs set a status in the moment between the Worker's read and its
  write (one request long), the post can show Triaged until the issue's next
  event or a fix-mode sweep.
- An issue filed before this version is told without a ping when its post's
  first message is not the reporter's.
- If GitHub never confirms a create and the bot's re-check does not find the
  issue, the moderator is told the issue may exist, and the player gets no
  "now tracked" reply. A later send or card press that finds the issue
  answers "Already tracked" and sends none either.
- A post can be filed a second time when its filing record was never saved
  (the moderator was told "post record not saved") or was deleted, and its
  issue was then moved to a repo outside `REPOS` or lost its `from-discord`
  label: the bot's search sees neither. For about a minute after a filing,
  its saved record may not yet be seen everywhere, so the same holds when
  the issue loses its `from-discord` label in that minute and the post is
  sent again.
- With no saved filing record, the bot searches every configured repo twice
  before filing. An issue moved between two configured repos while it
  searches can still be missed, and a second issue made. So can one in a repo
  with more than 100 issues labeled `from-discord`, when labels change during
  both searches and its place in GitHub's issue list shifts between two pages
  each time. Each search takes a second or two.
- On Workers' free plan a run may make 50 outgoing calls. A filing whose
  repos together hold more than about 2,000 `from-discord` issues updated
  since the post was made can use them all before it answers the moderator
  and releases its lock: the moderator may see no result, and until the
  lock label is cleared the post's next send says another send is running.
  Repos that large need Workers Paid.
- A queue card still owed looks for the bot's "now tracked" reply among the
  post's last 100 messages. A post filed after its greeting, whose filing
  record was not saved (or not yet seen) and whose reply is further back
  than that, can still get a card; pressing it answers "Already tracked" and
  marks it filed.

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
   tag. Make a staff-only queue channel. Copy each forum's and the channel's
   id and the server's id (Developer Mode on, right-click > Copy ID).
2. **Discord app.** At discord.com/developers/applications: New Application >
   Bot > Reset Token (keep it). Under Privileged Gateway Intents switch on
   **Message Content** (the bot reads the post it is pointed at; it never listens
   to the server). Under Installation set **Install Link** to None first
   (Discord will not save the next step while a default install link exists),
   then under Bot switch **Public Bot** off so only you can invite it.
   Note the Application ID and Public Key from General Information.
3. **Invite it** with OAuth2 > URL Generator: scopes `bot` + `applications.commands`,
   permissions View Channels, Read Message History, Send Messages, Send
   Messages in Threads, Manage Threads. Send Messages lets it post queue
   cards; in the queue channel it needs View Channel, Send Messages and Read
   Message History. Let the bot into the staff-only queue channel before you
   set `QUEUE_CHANNEL_ID`: a post scanned while the channel refuses the bot
   gets no card.
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
   `GUILD_ID`, `APPROVED_ROLE_IDS` (a test role), `MOD_CHANNEL_ID` and
   `QUEUE_CHANNEL_ID`.
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
minute for the greeting and the queue card, press **Send to GitHub** on the
card with the test role,
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
this folder, and the GitHub App installed. With more than one repo in
`REPOS`, set `LOCK_REPO` to the repo that holds every filing's lock label,
whichever repo it files into; until it is set, nothing is filed. Before
changing it, follow "Changing the lock repo" above. Set its push trigger to that repo's release tags, and the repo
variable `RELEASE_TAG_PATTERN` to an anchored pattern that matches only them:
for tags like `v5.0.120`, `tags: ['v*']` and `^v\d+\.\d+\.\d+$`; for tags like
`30.8` or `31`, `tags: ['*']` and `^\d+(\.\d+)*$`. A tag whose name holds alpha,
beta, rc or pre, not inside a longer word, never counts, whatever the pattern
says. The guard misses `preview` and `1.0b1`, so a looser pattern must refuse
those itself.
