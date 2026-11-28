# Discord bot: forum posts to GitHub issues

Every new, open post in the configured forums gets a short greeting from the
bot, "Thanks for posting! A moderator will take a look soon, and we'll post
updates here." (a post closed before the bot saw it gets none). With
`QUEUE_CHANNEL_ID` set, the bot also puts a card for the post in that staff
channel: Discord's own link to the post (it shows the post's current name),
the poster's name tag (it opens their profile) with their username beside it,
and what kind of post it is, with a **Send to GitHub** button and an **Open
post** link. The card pings no one. A poster with no user id (a webhook) is
named as plain text, and a poster who has left the server shows as
"@unknown-user" beside their username. Someone with an approved role (or a
moderator) presses the button, checks a short form, and the bot files the
issue in the repo the form names. The bot then replies to the filed message
with "tracked as KE #17", which pings its author, tags the post **Triaged**
when it shows no status yet, renames the post to the issue's title (see The
issue), and changes the card to "Filed as KE #17 by @moderator" (a mention
that pings no one). Moderators can still right-click any post or message > **Apps > Send
to GitHub** for the same form; the reply then goes to that message, and the
post's card is marked filed too. A greeting from an earlier version that still
shows its own button keeps working; once the reply exists, the bot deletes it,
or removes its button if it may not delete it. The card also has a **Move**
button, and moderators can right-click > **Apps > Move post**, to move a post
to another player forum (see Moving a post). Its **Add to issue** button (an
approved role or a moderator) and the right-click **Apps > Add to issue**
(moderators) add a repeat report to an issue the bot already filed, in place
of a second issue (see Adding a repeat report). For a bug, "now tracked" also
asks the player to paste the text of the addon's in-game Report a Problem
window in the post; the bot does not copy it to GitHub.

The greeting and the card go out in the same scan: new posts are greeted
first, then cards still owed by older posts go out, then the new posts'
cards. A post filed before the scan reaches it (by right-click, say) gets
neither, also when its filing record was not saved: the bot finds its own
"now tracked" reply in the post, and it looks again just before each card,
so a post filed after its greeting gets no card either. If the card cannot go
out yet, the scan tries again each minute while the post is open, without
sending the greeting again. A card goes out only to a post still open just
before it is sent, and its last look at the post's messages comes directly
before the card, so a first message deleted meanwhile is seen. A post whose
first message was deleted gets a card without the button, which says a
moderator can open the post and right-click a message in it: the form files
the first message, and the right-click command is for moderators only.

A card can still offer **Send to GitHub** after its post is filed (see Known
limits). Pressing a card of a post already filed is safe: the bot first
checks whether the post is on GitHub (its saved filing record, else every
repo in `REPOS`), answers you privately "Already tracked as KE #17" with the
link, and marks that card filed; no form opens and no one is pinged. The form
opens only after that check finished and found nothing. If the check cannot
finish, you are asked to press again; if that keeps happening, a moderator
can right-click the post instead (the form's submission checks too). A
message or post deleted before the submission reads it files nothing and
says so.

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
| `accepted` label on an open issue | Accepted, beside the status (see The Accepted tag) | none |

On a post the bot moved (see Moving a post), "now tracked" and every status
message also start with an @mention of the reporter, who is pinged: the
copied message was posted by the bot's webhook, so a reply to it pings no one.
After a filed post moves, its status messages reply to the copy in the new
post and @mention the reporter the issue names. An issue whose reporter is
unknown (a report a webhook posted) pings no one, as before the move. The
needs-info message is not a reply, as always: it mentions the reporter in
the new post.

On an issue with repeat reports added (see Adding a repeat report), every
message in the original post ends with one line, "Also reported by @A @B.",
naming each added player whose report comment that run had read and whom the
message does not already @mention; each of them is pinged. With no one left
to name, the message has no such line.

"Now tracked" and every status message are replies to the reporter's message,
the one the issue was filed from, so Discord pings the reporter even when
their notifications are set to only @mentions. An issue filed before this
version replies to the post's first message, with a ping, only when that
message is the reporter's; otherwise the message goes out with no reply and no
ping, beyond the added players its last line names. If Discord refuses the reply, the message goes out once as a plain
message, which loses the reply's ping only (every @mention in it, the
reporter's and the added players', still pings), and the log says so: the
workflow run's for a status message, the Worker's for "now tracked" and the
Add reply. If Discord refuses "now tracked" or the Add reply
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
is unfinished, write `Refs #N`, and editing it to `Fixes #N` makes the PR
count toward In progress for an open issue, once the PR is ready for review
and its author has a repo role (the table above). An edit of the title alone
starts nothing. GitHub does not read the description again when only a PR's
base branch changes, so after changing the base, edit and save the
description once. A PR into a branch other than the default branch lists no
closing issues, so it moves nothing.

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
from moving, its message stays owed, and the run ends red with the fix in its
job summary (Checking the setup, Red status runs). The sweep leaves that post as it is
and lists the owed message with a link to the run. Fix the setup, then re-run
that run (Re-run failed jobs, or Re-run all jobs for a run that passed), and
the message goes out, even if another run has moved the post in the meantime.
A message is never sent twice by the bot, except in the rare race under Known
limits. GitHub allows re-runs for 30 days from the
run's first attempt. Once the note is ten minutes old, an owed message that no re-run
could send (its post is gone, or what it says is no longer true) is listed,
and a fix-mode sweep marks it `Dropped`. A message the bot dropped was never
sent, so if the same news comes true again (a PR back from draft), the bot
writes a new note and sends it. A note a moderator marked by hand (below)
closes its message for good.

Four times a day (03:17, 09:17, 15:17 and 21:17 UTC) a sweep lists anything
still out of step in the job summary, a post with no status tag, an
unconfirmed message and an Accepted tag out of step on a post that is not
archived included (and, with `SWEEP_MODE=fix`, repairs the labels and tags:
a status repair sets the Accepted tag in its own write, and a post whose
only gap is Accepted is repaired only when it is not archived and shows
Triaged alone). The sweep never messages
anyone. To clear a listed message (sent by hand, or not needed), open the
comment the sweep line links to and add `<!-- discord-sent -->` (or
`<!-- discord-dropped -->`) at its end.

Every day the Worker also lists posts older than `STALE_DAYS` that have no
status tag and no `Answered` tag (open posts, and posts archived in the last
30 days) in `MOD_CHANNEL_ID`, and warns there first if the post scan has
stopped, or hit a problem with some post or forum in the last day. A post
that refuses the bot (Discord's 403: a missing permission) is given up on at
once and named in the next alert as "refused by the post (403)", with the
permissions to check; a deleted post is skipped without a word (unless an
earlier try failed for another reason: Known limits). The alert,
like every bot message to `MOD_CHANNEL_ID`, goes only to a text channel of
the server; otherwise it goes to the Worker log. A post
that fails 30 runs in a row (about 30 minutes) is given up on, and so is one
whose saved record still cannot be read an hour after the post was made. The
alert names each post given up on that no earlier alert named; one the
moderator channel refused to show is named again the next day.

Two halves, no always-on server:

- `src/` is a **Cloudflare Worker** (free plan, or Workers Paid for repos
  with thousands of bot issues, see Known limits): it answers the button, the
  right-click command and the form, and runs the post scan and the daily check
  on cron triggers.
- `status/status.mjs` runs in **GitHub Actions** (`.github/workflows/discord-status.yml`),
  and `status/merge-plan.mjs` beside it, in its own job after it, for pull requests.
  Without the `DISCORD_BOT_TOKEN` secret both do nothing while the repo has no
  issue the bot filed, so they are safe to merge early; once it has one, the
  status job fails until the secret is added, and the merge plan still skips.
  A status run whose issues could not be listed to check fails too, saying
  so; re-run it.

None of this ships to players: `.github` is excluded from sync and builds.

## Pull requests: the merge plan

A pull request that closes an issue the bot filed, says `Refs #N` for one,
links one's Discord post, or closes a Discord report in another repo gets one
comment from the workflow, the merge plan. For each open issue the PR will
close, it quotes the bot's current message for each step: the PR ready for
review (In progress), merged (Fixed) and a release that holds it (Shipped).
That is the wording a new message gets; when a message goes out, and when it
does not, is described at the top of this README, and a message owed from an
older run keeps the words it was written with. The comment reads no Discord
post. Below that, a Heads-up list says when merging will not do what the
author expects: the PR targets a branch other than the default one, GitHub
does not list an issue the description closes (the PR was opened into another
branch and then moved to the default one, the description not saved since),
it is a draft, its author has no role on the repo, an issue is already
closed, it closes a Discord report in another repo, it links a report's post
without closing its issue, or it says `Refs #N`. The comment links the issue
and copies none of the report. It reads the description and the PR's links,
not commit messages.

The comment is rebuilt at each PR event (opened, description or base edited,
ready for review, converted to draft, reopened, closed) by its own job, which
runs after the status job, and edited in place; it is never deleted. Keep
its hidden first line: without it the bot no longer finds the comment and
posts a new one. A PR that merges with no merge plan yet (one opened before
the bot was set up, say) gets the merged one then, if GitHub lists an issue
the bot filed here as one it closes. The merged comment names those issues
and says GitHub closes each one still open; it does not tell apart one
closed before the merge, and leaves what the bot then does to this README.
The merge-plan job never delays its own run's status job. It shares two
things with every other status run (Known limits): the GitHub allowance,
whose exhaustion can make a status job fail, and the account's hosted
runners, whose being full can make another run's status job wait. A comment
it cannot write is named in its log, never as a failed run.
The job takes about a minute and ends its own calls within 60 seconds; its
5-minute limit is reached only when GitHub stalls its setup (Known limits).

- **One line does it.** Put `Fixes #N` on its own line in the description
  (`Closes #N` and `Resolves #N` work the same), with the default branch as
  the base. N is the number the post's "tracked as" reply names.
- **`Refs #N` while unfinished, `Fixes #N` when ready.** With `Refs #N` the
  PR does not close the issue, unless a commit message or a link in the PR's
  Development sidebar does. Editing it to `Fixes #N` makes the PR count
  toward In progress once it is ready for review and its author has a role
  on the repo.
  Write one Refs per issue. Any wording with fix, close or resolve right
  before the number closes the issue on merge, in the description or in a
  commit message, "partly fixes #12" included.
- **Never `Fixes` across repos.** That repo's status workflow, if it runs,
  cannot see a fix or a release made here, so it treats the issue as closed
  by hand and never moves its post to Fixed or Shipped. Transfer the issue
  to the repo that holds the fix first.
- **A thread link alone moves nothing.** Linking the Discord post is fine,
  but only a closing keyword (`Fixes #N`, `Closes #N` or `Resolves #N`) in
  the description or in a commit message, or a link in the PR's
  Development sidebar, closes the issue. To keep an unfinished PR from
  closing it, change the description's word to `Refs`, remove the sidebar
  link, and keep those words out of commit messages.
- **A fix reverted before its release:** reopen its issue the same day.
  Reopening drops the fix; otherwise the release announces the fix as out.
- **A fix merged without `Fixes #N`:** put `Fixes #N` in the message of the
  next commit on the default branch, before the release tag. Do not close
  the issue by hand: the bot treats a hand close as Closed, not Fixed, and
  never as shipped.

## Checking the setup

The Worker checks its own setup in three places: `/bot-check`, the daily
setup check, and its replies to a moderator while a setting is broken. The
status workflow checks the GitHub side in its own runs (Red status runs,
below).

- **`/bot-check`.** A moderator (Manage Threads) runs it in the server the
  bot is set up for; in any other server, or while `GUILD_ID` is not set, it
  is refused. It checks:
  - the Worker's settings, as the bot reads them, `REPO_TAGS` included;
  - the bot's permissions in each player forum (Manage Webhooks among them,
    for moves), the queue channel, the moderator channel and the checklist
    forum;
  - each forum's tags and template message;
  - the Message Content setting and the approved roles;
  - that the moderator channel is hidden from `@everyone`;
  - that the four secrets are set and of the right form (never their values),
    and that `DISCORD_PUBLIC_KEY` and `DISCORD_BOT_TOKEN` belong to the same
    app;
  - for each repo in `REPOS` and `LOCK_REPO`, once in any letter case, the
    GitHub App's install, its Issues permission and, for a filing repo, the
    bot's labels; when `REPOS` names two or more repos, also each filing
    repo's Contents: Read and write, which moving a filed post to another
    repo needs.

  The result goes to `MOD_CHANNEL_ID`, one line per problem with its fix,
  but only when the check found that channel to be a text channel of this
  server where the bot can post. Otherwise, or when the channel refuses the
  post, it comes back to you privately, the reason first; if only part of it
  was posted, the private reply holds the rest. A check that could not run
  counts as a problem. The checks run in groups (the server's channels,
  tags and roles; the bot's application; the template messages; GitHub),
  so one failure hides only the rest of its own group, and the result then
  holds a line that says which checks did not run: fix that problem, then
  run the check again.
- **The daily setup check.** At 15:30 UTC the Worker runs the same checks.
  Problems are posted in the moderator channel every day they last. A
  passing day posts nothing, except Mondays: "every check passes today". A
  Monday with neither that line nor a problem list means the daily setup
  check is not running or cannot post.
- **The Worker's replies.** While the Worker cannot read its settings (a
  broken `REPOS`, for one) or they name no player forum, a moderator who
  right-clicks a post, and a moderator or a member of an approved role who
  presses a queue card's button or submits the form, in this server, is
  told "The bot is not set up yet:" and the first broken setting. Anyone
  else gets the usual "Only moderators ..." refusal first, and a moderator
  of another server gets "This only works on posts in the forums the bot is
  set up for."; neither sees the setup line. While the Worker can read its
  settings, a press on a post already filed still answers "Already tracked"
  first.
- **Filing** into a forum without the `Triaged` tag still files the issue.
  When the bot tries to set `Triaged` on a post with no status and cannot,
  the moderator's reply includes "tag not set" with the reason, among its
  other notes. The setup checks name a missing status tag of every forum
  every day.
- **Red status runs.** A status run or a sweep that meets a setup problem (a
  forum missing a status tag, or the Accepted tag an accepted issue needs,
  the staff checklist forum included;
  Discord refusing the bot; a bad `RELEASE_TAG_PATTERN` or `SWEEP_MODE`; a
  `CHECKLIST_FORUM_ID` that is not a plain channel id, digits only, which
  also stops all staff checklist work in that run; no
  `DISCORD_BOT_TOKEN` in a repo with issues the bot filed, or whose issues
  could not be listed to check) finishes every
  other issue, then fails (a needs-info event stops at its first failure,
  as it always has), with each problem and its fix under "Discord
  status: setup problems" in the job summary, for example
  `forum 900 has no "Fixed, next update" tag: add it, spelled as the README lists it`.
  Each problem is also in the run's log, where it was met. A refusal is
  named by the channel Discord refused, so a forum the bot cannot see gives
  a line for each of its posts that run read, all with the same fix. A
  transferred issue's opened run does nothing, as before, so it names no
  bad `CHECKLIST_FORUM_ID`; the next run does. The checklist job
  fails the same way on a bad pattern, a bad `CHECKLIST_FORUM_ID` or a
  missing token; a checklist thread it cannot settle fails it as before,
  with no setup line. The sweep is red in report mode too. Fix the problem,
  then re-run that same run: it sends the messages it still owes. Nothing
  is posted in Discord for it. A forum setting that names a channel that is
  no forum gets no tag line: the daily setup check names a player forum of
  the wrong kind, and a checklist forum set in the Worker too; a checklist
  forum set only for Actions fails a status run's checklist work as before,
  unless it is a media channel holding the threads and their tags, which
  works as before.
  GitHub emails a failed run to the person whose action started it, and a
  failed scheduled sweep to the workflow's creator, or whoever later changed
  its schedule line or re-enabled it; each only when their notification
  settings ask for failed Actions runs. GitHub's docs do not say who, if
  anyone, is told of a run the bot's GitHub App started (an issue's opened
  run). The sweep is scheduled four times a day, and a sweep checks the
  forum of each post it reads, so a player forum problem is normally named
  within about six hours. A sweep that fails before it reads the posts (its
  issue list unreadable), or that its ten-minute job limit stops, names only
  what it reached; checklist threads it has no time for (its checklist work
  stops at two minutes) wait for a later sweep. Only event runs see a
  refused message send or message read; the daily setup check names those
  permissions in the moderator channel.

Neither of the Worker's checks can see its cron triggers. After every deploy, read
Wrangler's output (step 5 of the setup).

## The issue

The issue opens with a small table: the reporter and the moderator who filed
it, each as their server name linked to their Discord profile, with their
username (a webhook's post shows its name alone), and a link to the post. The
quoted report follows, then the attachment count and the template check. The
issue keeps those names, usernames and Discord ids as they were at filing; a
maintainer removes them by editing the issue. Two hidden lines after the
report name the filed message and the post; leave them in place. They stand
together where the bot wrote them: at the end, unless a maintainer added a
note below them, which then follows them. An issue filed from a moved post's
copy has three: the first marks the copy, so status messages @mention the
reporter (see Moving a post). Each move of a filed post adds a visible line
directly above the hidden lines, "Moved to (the new post) by (moderator).",
oldest first, each linking the post that move made, and rewrites the hidden
lines to name the new post.

Each new issue gets the labels `from-discord`, its `type:` and `client:`
labels, and `player-report` (came from a player, not reproduced yet). The
bot adds `player-report` once, at filing, and never again; a maintainer
removes it once the problem is reproduced. Each repeat report added to the
issue is a comment of the bot's, "Report N of this problem", with a hidden
line naming the post and the player; leave those comments as they are.

The issue's title is built from the form: `[KE] [Retail] [Bug] [Bags] Bank tab
icons overlap`. That is the repo key, the client, the type, the module, and
then the title. Each word of the module gets an upper-case first letter
(`General` when nothing is left of it once direction marks and control
characters are removed), and brackets typed in the module are dropped. A
letter whose capital is more than one letter, such as ß, stays as typed.
Each key in `REPOS` must be made of letters and digits only: A to Z, a to
z and 0 to 9. With any other key the bot files nothing and answers that it
is not set up, naming the first problem it finds: the key, unless an
earlier one comes first, such as a `GUILD_ID` that is unset or not a server
id. The setup check writes a line for every such key, within its usual
display limits.

When a new issue is created, the bot renames the post to the same text, cut
to Discord's 100 characters, normally inside the title (a module of many
emoji can make the cut fall in the prefix). The rename comes last, once the
reply to the moderator and the lock's release have been tried, beside the
queue card's update, so it never delays or stops the filing. A reply or a
release that fails is logged and the rename still runs, so a renamed post
does not prove the moderator got the reply or the lock was cleared. It reads
the post just before the rename: a post that already has that name is not
written, and an archived one whose name changes is opened by the same
request (one that already has the name stays as it is). A rename that fails
goes to the Worker log as `post <post id> rename failed:` with Discord's
answer or the timeout; the moderator's reply does not mention it.

A post found already tracked is not renamed, and a later change to the
issue's title does not rename the post. Opening the form again on a renamed
post pre-fills the title without the bot's prefix, as it drops any leading
bracket groups from a post's name. When the cut fell inside the module, the
rest of the module is pre-filled instead, and the moderator types the title
again. Set `RENAME_POSTS` to `0` to leave post names alone; the issue's
title keeps this shape.

One post gets one issue, across every repo in `REPOS`. Before filing, the bot
reads the issue the post's saved filing record names, then searches every
configured repo once for the post's hidden line; a match anywhere answers
"Already tracked" and files nothing, and a check that fails, or a token the
bot cannot get, files nothing and names the repo to try again for. A saved issue that answers "not found" (404) also files
nothing: GitHub answers the same for an issue the app can no longer see, so
the bot names it and says how to clear the record (below). Two filings of one
post at the same moment, into any repos, make one issue: each takes a lock
label, `discord-lock-<post id>`, in `LOCK_REPO`, whose description says when
it was taken ("Send to GitHub since 2026-11-18 18:40:05 UTC"). Delete a lock
label only when that time is more than an hour ago, or it shows none (an
older version's label). A newer one may belong to a filing between its last
search and its create, or to a create GitHub never confirmed and may still
apply, and deleting it can let a second filing make a second issue. A filing
ends within 30 seconds and GitHub times out a request after 10 seconds, so
the hour is a wide margin past both, not a guarantee (see Known limits).
Every reply that advises deleting a lock gives this rule; the reply to a lock
GitHub never confirmed names the label and advises no deletion.

An issue moved in from another repo arrives as a new issue: its `opened`
event does nothing (no message, no tag change, no checklist thread). Its
post is settled by its next status event (a close, a reopen, a PR or a
release) or the sweep, and its checklist thread by its next checklist event.
When the bot's own move transferred it, the move has already relinked the
post and rewritten the checklist thread's first message.

## Moving a post

A post in the wrong player forum can be moved to another one in `FORUMS`: a
bug report to the feedback forum and back, or a Retail post to the Forever
forum. Whoever can file can move: a member of an approved role (or a
moderator) presses **Move** on the post's queue card, and a moderator can
right-click any message in the post > **Apps > Move post**. A player gets
"Only moderators and admins can move posts.". A forum outside `FORUMS`, the
checklist forum included, is never a source or a target, and a `FORUMS`
entry that is not a forum of this server is never a target (`/bot-check`
names it).
Every forum in `FORUMS` must be open to the same players: a move into a
forum a player cannot see archives the post they can read and leaves them
a link and a mention they cannot open. The bot cannot tell who can see a
forum, so it does not check this.

Queue cards posted before this version have no Move button: a member of
an approved role asks a moderator, who right-clicks the post. Cards posted
before the Add to issue version have no Add to issue button either: a
moderator right-clicks the message.

A filed post moves too, and its issue follows it (below). A post that holds
the bot's "now tracked" reply among its last 100 messages is refused when
the bot cannot find its issue (its filing record was never saved or was
deleted, and the issue lost its `from-discord` label or left `REPOS`), so
the bot cannot move it; the answer links that reply. If that issue was
deleted, delete the reply, then move the post again.

The form has these dropdowns:

- **Move to**: the other forums in `FORUMS` that are forums of this server,
  chosen already when there is only one.
- **Repo**: only when `REPOS` has two or more keys the dropdowns can offer,
  and used only for a post already on GitHub. It is pre-filled from the
  post's filing record: the key the post was filed under while it still
  names that repo, else the repo's first key. Leaving it as shown keeps the
  issue where it is, even when the record names a repo the issue has since
  left. Another key for the same repo changes only the key. Another repo
  moves the issue there (a transfer on GitHub), unless the issue is closed:
  a closed issue keeps its repo, and moving its post to another repo is
  refused. On a post not yet filed the field is ignored, and Send to GitHub
  on the new post picks the repo, its dropdown pre-filled from the post's
  one repo tag (`REPO_TAGS`).
- **Client**: optional, read only for a forum with no client of its own.
  Moving into such a forum with no client chosen answers "Nothing was moved.
  Pick a client: ..." and changes nothing. On a post named as its issue's
  title (the filing renames it), it shows the issue's client; left as shown,
  a filed post keeps its issue's client, and another choice changes it.

**A filed post.** A repo change without a forum change is not a move: transfer
the issue on GitHub. A filed move changes on the issue:

- the title's prefix: the key, the client and the type, the module and the
  title's text kept as written. A title not of the bot's shape is kept, and
  the new post takes the old post's name;
- its `client:` and `type:` labels, never `from-discord`. A forum with no
  type of its own keeps the issue's type, from its `type:` label;
- its hidden lines, now naming the new post, so status messages go there,
  and one "Moved to (the new post) by (moderator)." line above them. The
  rest of the body stays as written, so its links still open the old post,
  which says where the post went;
- the post's filing record (`issue:<new post id>`);
- the first message of its staff checklist thread, to name the new post,
  the issue's title and address and its labels. The thread is opened to
  edit it and left open.

The new post's tags carry the repo tag of the issue's key (a tag of another
key is dropped), the moved message adds "Tracked as KEY #n.", and the queue
card shows "Filed as KEY #n" with **Move** and **Open post**. The reply is
"Moved to <new post> from <old post>. KEY #n: <issue link>", with
"(transferred from OLDKEY #m)" after a transfer.

**The transfer** comes before the new post is made, the last write before
it. GitHub moves issues only between repos of one owner, never from a
private repo to a public one; it keeps a milestone only when the target has
one of the same name and due date, and the bot makes in the target any label
it lacks. GitHub copies the labels a few seconds after it answers, so
before it removes a client or type label the bot reads the issue again,
up to six times a second apart, until the old labels are there. The
GitHub App needs Contents: Read and write as well as Issues on both repos
(Checking the setup). After the bot found the issue, every reply
that moved nothing ends by saying where it is, "The issue is KEY #n in
owner/repo (link)."; a refusal before that, such as a busy post, names no
issue. A transfer GitHub refused (an HTTP 4xx, or its missing-permission
answer) leaves the issue in its repo and names the permission. A transfer
GitHub did not confirm (no answer, a 5xx, a stop at its deadline, an answer
the bot cannot read, or another GitHub error) says instead where the issue
was last known and that it may now be in the target repo.

Discord cannot move a thread, so the bot makes a new post in the chosen
forum through a webhook it makes there, named `Post mover`, and reuses
after; one someone deletes is made again at the next move. The player sees:

- the new post, with the old post's name (a filed post's is rebuilt from
  its issue's new title while renaming is on), its first message's text and
  files, under their server name and avatar with Discord's APP badge. Only
  the first message is copied, not the conversation;
- the bot's message in it, "Moved here from <old post> by @mover. First
  posted by @player.", which pings them;
- the old post: "This post moved to <new post> (moved by @mover).", then
  locked and archived. It stays readable.

The new post gets no greeting. The old post's queue card is edited to show
the new post, with its buttons and "Moved by @mover" (a filed post's shows
"Filed as KEY #n" instead); a post with no card
yet, or whose card Discord will not edit, gets a new card for the new post.

**Tags.** The new post keeps every tag of the old post whose name, in any
letter case, the new forum has, a repo tag included; none is added for a
repo, except a filed post's (above). A client tag that disagrees with the post's client is dropped, and a
forum with no client of its own gets its tags for that client (All gives
both, or one tag naming both when the forum has it). A tag added so names
no type, or the post's own: the forum's, else the one its kept tags name.
A Feature post gets "Retail", never "Retail Bug", which Send to GitHub
would read as a bug; with no type known, only a tag naming none is added.
A type tag that disagrees with the forum's own type is dropped. Discord
takes five: the
status tag, the repo tags, the client tags and Accepted come first, in that
order, so a post with a status and four repo tags keeps no client tag; the
queue card still names the client.

**Refusals.** Each answers "Nothing was moved: ..." and changes nothing: a
post already moved (its record says where), or locked; a closed issue moved
to another repo; a transfer GitHub refused, or whose target repo the bot
cannot reach or read; an issue whose comments cannot be read; a move into a forum
`FORUMS` no longer lists, or into one deleted since the form opened; a post, or its first message, that was deleted; a post being filed or moved (the lock); a saved
record that cannot be read; a saved issue that cannot be checked; a forum list that cannot
be read; the bot lacking Manage Webhooks in the target forum; no `STATE`
namespace bound; a copy the bot made whose move record is not readable yet
(wait a minute and move again). Send to GitHub on an old post whose record
KV shows answers
"Nothing was created: this post was moved to <link>; send that one.", and
on such a copy it asks to wait a minute too. Every button and command, Send
to GitHub's included, answers only in the server `GUILD_ID` names: anywhere
else, or while `GUILD_ID` is unset, it is refused before anything is read.

**Before the new post exists**, every failure answers "Nothing was moved",
or "Nothing confirmed" when GitHub or Discord did not answer a write (then
the lock stays), and leaves the old post as it was; after a create Discord
did not answer, a copy may exist in the target forum. The forum's `Post mover` webhook may
have been made; the next move uses it. A transfer may have gone through
first: the reply then says where the issue now is, and the next form's Repo
field, left as shown, keeps it there.

### When a move stops partway

A move makes the new post, then does six things: saves the old post's
record, moves the queue card, saves the new post's record, posts the moved
message, posts the note in the old post, and locks the old post. A filed
post's move does four more: it saves the filing record and edits the issue
right after the old post's record, and sets the labels and edits the
checklist thread after the old post's lock. While
`QUEUE_CHANNEL_ID` is unset, the card step is skipped with no line and no
card is touched. The reply is "Moved to <new post> from <old post>." when
every step it ran is done. Otherwise
it is "The move stopped partway: <new post> was made from <old post>. Not
done:", then one line for each that failed, and the Worker log says why.
A step whose write GitHub or Discord did not answer is listed too, though
it may have gone through; a later step reads the state as it last knew it.
The bot does not retry them, and there is no repair procedure: each state
below is known and accepted. What you see in each:

- **The old post's record** (`record movedto:<old post id>`). The old post
  can be sent again at once, and moved again once someone unlocks it, and the scan
  may greet it if its lock also failed. Leave it locked; if it is unlocked,
  close it again.
- **The queue card** (`queue card for the new post`). The card still shows
  the old post; its buttons answer that the post moved. Right-click the
  new post to send or move it.
- **The new post's record** (`record movedfrom:<new post id>`). Sending or
  moving the new post by its first message answers that its record is not
  readable yet, for good, and so does sending a reply in it once the scan
  has saved the post as the bot's copy. The new post stays a readable copy.
- **The moved message** (`moved message in the new post`). The new post has
  no link back, and the player was not pinged.
- **The note in the old post** (`note in the old post`). The old post does
  not say where it went; the new post's moved message still links back.
- **The old post's lock** (`lock on the old post`). It stays open, and its
  lock label stays, so it can be neither sent nor moved until the busy
  reply's hour has passed.
- **No answer to the create** ("Nothing confirmed: Discord did not answer
  the new post's create in <forum>, so a copy of <old post> may exist
  there."). A copy may or may not appear in that forum. The old post was
  not changed and its lock stays; after an hour the busy reply's advice
  applies. A copy that appears is refused for sending and moving by its
  first message, and for sending by a reply once the scan has seen it, and
  is not greeted. Do not delete a post in that forum on
  the strength of this message alone: another post can share the title and
  the player's name.
- **The filing record** (`record issue:<new post id>`). Send to GitHub on
  the new post still answers "Already tracked", finding the issue by its
  hidden lines, once the issue link step was done.
- **The issue link** (`issue link to the new post`). The issue's body and
  title still name the old post, so status messages go there. With the
  filing record also not done, Send to GitHub on the new post files a
  second issue; close it by hand.
- **The labels** (`issue labels`). The client or type labels named stay,
  or are missing.
- **The checklist thread** (`staff checklist thread`). Its first message
  still names the old post and address. The thread stays linked to the
  issue, and its tags keep following it.
- **A transfer refused** (an HTTP 4xx, or GitHub's missing-permission
  answer): nothing moved, the issue stays in its repo, and the lock is
  released.
- **A transfer not confirmed** ("Nothing confirmed: GitHub did not confirm
  the transfer of ..."): the issue may be in either repo, and the old
  post's lock label stays until someone deletes it as the busy reply says.
  The move after that reads where the issue is.
- **A move stopped after a transfer** (the new post refused, or not
  answered): the issue is in the new repo and the old post was not
  changed, though an unanswered create may have left a copy; its
  checklist thread stays linked, since its record comment moved with it.
- **No reply at all** (the Worker was stopped, or the reply failed): any of
  the states above may hold. Look at both posts before acting.

**Files** are copied up to 20 MiB each and 24 MiB in all, Discord's limits
less room for the message. The rest and any that fail to download stay on
the old post, and the moved message says how many; a file the player adds
after the bot reads the first message stays there too, uncounted. A first message over
Discord's 2,000 characters is cut, and the moved message says the full text
is on the original.

**Send to GitHub on a moved post** files the copy as the player's report:
the issue names the player and links their profile, and "now tracked"
starts with an @mention of them.

**Calls.** Workers' free plan allows 50 `fetch` calls a run; KV calls are
not counted here. A move with one repo, which `LOCK_REPO` also names, the
webhook already made, a queue card to edit and a first message a player
posted makes 17 (the GitHub token takes two, its search for an issue runs
once, as a filing's does, and the post's last 100 messages are read for
the bot's "now tracked" reply). A `LOCK_REPO` of another repo adds two,
for its own token; moving a moved copy saves one, the member read. It adds one per file it
tries to download, whether or not the download works; one the first time a
forum's webhook is made; one when Discord refuses the card's edit and a new
card is posted (a post with no card posts one instead of the edit, at no
extra cost); and one when the post's messages hold one that starts as the
bot's "now tracked" reply, to read the bot's own id. Each further repo
searched costs three (its token's two and its search), plus one for each
further 100 `from-discord` issues updated there since the post was made.
With ten files and two repos, 20 calls are left: about 2,000 such issues
past the first 100 in each repo, in the two repos together (about 1,000 in
each); past that,
the last steps fail and are reported. If KV calls
count too, the figure grows by six (four reads, two writes). The live bot
runs on the paid plan. These figures are for a post not yet filed. A filed
post's move skips the "now tracked" read and makes up to 17 more: with a
transfer, the issue's comments (one more for each full page of 100), the
target's token (two) and repo, the transfer, up to six reads of the moved
issue's labels, the issue edit, up to three label calls and the checklist
thread's two; and one more KV write.

## Adding a repeat report

A post about a problem that already has an issue the bot filed is added to
that issue instead of being filed again. Whoever can file can add: a member
of an approved role (or a moderator) presses **Add to issue** on the post's
queue card, which adds the post's first message, and a moderator can
right-click any message in the post > **Apps > Add to issue**, which adds
that message. A player gets the Send button's refusal. The form asks for the
issue number ("12" or "#12"), and for the repo when `REPOS` has two or more
keys.

The issue must be one the bot filed from a Discord post, in the repo picked,
and open, or closed with its fix waiting for a release (the `pending-release`
label, the "Fixed, next update" state), so its added players get the "Out
now" message too. Each other answer adds nothing and says why: an issue not
found in that repo; one now in another repo ("pick that repo and number");
one the bot did not file from a Discord post (a hand-made issue or a pull
request); any other closed issue ("If the problem is back, send this post on
its own": reopening an issue drops its fix, so no "Out now" would go out). A
post already added, already filed (by its record, or by its issue's hidden
line when it has none), moved away, being sent, moved or added, or whose
message was deleted since the form opened is refused too.

An add makes, in order:

- one comment on the issue, "Report N of this problem: (the post), from
  (player), added by (moderator).", where the issue's own post is report 1
  and N counts the bot's earlier report comments. Only comments by the
  account that filed the issue count, since anyone can comment on a public
  issue. The issue's title, body and labels do not change;
- the post's record (`issue:<post id>`, marked `added`);
- the post's Closed tag;
- one reply to the player's message: "This is the same problem as KE #12,
  first reported in (the original post). We've added your report to it, and
  we'll ping you in that post with each update.", with the Report a Problem
  request for a bug. On a moved post's copy it starts with the player's
  mention;
- the moderator's reply, "Added to KE #12 as report N" with the issue's
  address, naming any step above not done;
- then, as after a filing, the lock's release and the queue card, "Added to
  KE #12", with only Open post. A failed release or card edit goes to the
  Worker log.

When GitHub refuses the comment, or the add runs out of time before it, the
post is not changed. When GitHub does not confirm it (no answer, a 5xx), the
reply says it may be there: if this post's report comment is on the issue,
a maintainer deletes it, then the same message is added to the same issue
again.

The added post gets no status messages of its own. Its player is named in
every later message of the original post (see the top of this README), a
player whose post a webhook made excepted. Send to GitHub on an added post
answers "this post was added to KE #12 as a repeat report", and Move refuses
it ("so it stays here").

A post already sent to GitHub as its own issue cannot be added. Close its
issue on GitHub as a duplicate of the other one: its post gets the
Duplicate message, which links the other report when that issue is in the
same repo and its post can be read. Its player gets no later pings from the
other issue. If that matters once live, the follow-up is to let Add take a
filed post whose own issue is closed as a duplicate.

To undo an add to the wrong issue, by hand: a maintainer deletes the post's
report comment, a bot admin deletes `issue:<post id>` (as in Clearing a
filing record), and a moderator deletes the bot's reply; the post can then
be added again. A post whose saved issue was deleted on GitHub, which Add
answers as already filed, is freed the same way, by clearing its record.

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

The bot's KV records are written by the bot alone and read as it wrote
them (Known limits). Deleting `thread:<post id>` loses the card's id, so a
later filing by right-click leaves that card live; press it once to mark it
filed. A move writes two more records, both the Worker's:
`movedfrom:<new post id>` (the old post, the player and the queue card) and
`movedto:<old post id>` (the new post); without `movedfrom:` the new post is
refused for sending and moving for good, and without `movedto:` the old
post can be sent again, and moved again once someone unlocks it (as in When
a move stops partway).

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
   - If it does not, and you are not sure, keep it in force with the
     description `Send to GitHub since <the current UTC time> UTC`, so the
     hour before it may be deleted counts from now: when the label is already
     in the new `LOCK_REPO`, edit its description; otherwise make a label of
     the same name with that description in the new `LOCK_REPO` (once, when
     old repos hold the same name), then delete the old one.
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

## The Accepted tag

Add the `accepted` label to an open issue to show the player that staff plan
to act on it: its post gets an `Accepted` tag beside the status tag. It tells
no one. The tag shows only while the issue is open, so a close that moves
the post's status removes it.

- **When it changes.** The label itself changes nothing at once, and no
  `status` job runs for it. The post's next status change adds or removes
  Accepted in the same write, as GitHub stood when that run read the issue:
  a label changed after that read waits like any other. On a post that is
  not archived and shows Triaged and no other status tag, a sweep with
  `SWEEP_MODE=fix` also does it, so within about six hours; in report mode
  the sweep only lists it. A post showing any other status waits for its
  next status change, and the sweep lists it meanwhile. An archived post
  (Discord archives an idle post on its own) waits too, and the sweep does
  not list it (Archived posts, below).
- **A free slot only.** A post keeps at most five tags. Accepted goes in only
  when one is free: no tag of yours, and not the status, is moved for it. A
  status that needs the slot takes it, and Accepted waits.
- **Archived posts.** An archived post keeps the Accepted tag it had when it
  was archived, or its absence: nothing writes Accepted to it. A status change
  that reopens the post sets Accepted in that same write. A fix-mode sweep's
  status repair that reopens an out-of-step post (Stage 3) is such a change.
- **The bot owns the tag.** A hand-added `Accepted` tag goes at the post's
  next status change unless the label is on, so add or remove the label, not
  the tag. A forum without an `Accepted` tag sees no change. If a forum
  already has a tag named `Accepted` that means something else, rename it
  before deploying this version.

Setup: give each player forum an `Accepted` tag, and make the `accepted`
label with this command (Stage 2 step 8 runs the same one):

`GITHUB_TOKEN=<a token with repo access> npm run labels <owner>/<repo>`

## Staff checklist

With the repository variable `CHECKLIST_FORUM_ID` set, every issue the bot
filed gets one thread in a staff-only Discord forum, a mirror of the issue.
Its first message names the issue, the player's post, and the issue's type
and client labels.

Setup:

1. Make a staff-only forum in the same server as the player forums, with the
   tags `Triaged`, `In progress`, `Fixed`, `Shipped`, `Done`, `Won't fix`,
   `Duplicate` and `Accepted`. The bot treats any tag with one of these
   names, in any letter case, as its own, so give staff tags other names.
   "Require people to select tags when posting" may be on.
2. Give the bot View Channel, Send Messages, Send Messages in Threads, Manage
   Threads and Read Message History there.
3. Keep the forum out of `FORUMS`, and set `CHECKLIST_FORUM_ID` in
   `wrangler.toml` to its id, so the Worker never treats it as a player forum
   even if `FORUMS` lists it.
4. Make the `accepted` label:
   `GITHUB_TOKEN=<a token with repo access> npm run labels <owner>/<repo>`
5. Set the repository variable `CHECKLIST_FORUM_ID` to the forum's id. Until
   then nothing here runs. Every repo in `REPOS` that runs the workflow sets
   it to the same forum as the Worker's `CHECKLIST_FORUM_ID`: an issue that
   moves between repos keeps its one thread. A repo with another forum fails
   its checklist job on a transferred issue's thread, naming the thread, and
   a repo with the variable unset keeps no thread in step. The bot cannot
   read a repository variable, so it cannot check this.

**Tags.** The bot owns those eight tags; every other tag is staff's. The
status tag follows the issue: Triaged, In progress (a member's PR will close
it), Fixed (closed by a commit or a merged PR), Shipped (a release holds the
fix), Done (closed by hand), Won't fix (closed as not planned) and Duplicate.
An open issue with the `accepted` label also shows Accepted; a label change
tells no one. A thread keeps at most five tags, and the bot never drops a
staff tag: a status or Accepted tag with no free slot waits, the run logs it,
and the sweep lists it. If the forum lacks the status tag an issue needs,
the bot changes no tag on its thread and the run fails naming the tag; if it
lacks only the Accepted tag, the status still moves, and the run logs it and
the sweep lists it. A status run (a PR or a release) and a sweep also name
either missing tag as a setup problem and end red (Checking the setup); the
checklist job logs a missing Accepted tag and stays green, as before.
The sweep names only the bot's tags in the Actions log,
and counts staff tags.

**Who opens.** Only the issue's own events open its thread: opened, closed,
reopened, and the `accepted` label added or removed. The workflow's
`checklist` job runs them, one at a time per issue, and each job brings the
whole thread in step with GitHub. PR and release runs and the sweep
update a thread that exists, but never open one. An issue filed before this
version, or one whose open failed, gets its thread at its next such event, or
when its failed checklist job is re-run. If Discord may have made a thread
but its answer was lost, the bot never makes a second thread for the
issue's "Staff checklist thread" comment: it leaves it "not confirmed" for
staff (see the sweep).

**Archiving.** A thread is archived when its issue is finished (Shipped,
Done, Won't fix, Duplicate), once per close: the issue's "Staff checklist
thread" comment notes which close it was archived for. A staff reply reopens
an archived thread, and the bot leaves it open until the issue closes again.
A reopened issue's thread is opened again. A tag change by the bot keeps a
thread's archive state, so a thread Discord archived for inactivity stays
archived. A move of the issue's post does not: it opens the thread to edit
its first message and leaves it open (Known limits).

**The sweep** lists each checklist problem with the thread's link and what to
do: an open issue with no thread, a thread not opened or not confirmed, an
archive owed or one made for a close that no longer holds, a deleted thread,
a thread outside the checklist forum, a missing tag in the forum, and tags
out of step. With `SWEEP_MODE=fix` it repairs tags and archive state; it
never opens a thread. For a thread not confirmed after a lost create answer,
the sweep links the forum the create went to and the issue's addresses.
With more than one bot thread whose first message names the issue, keep the
oldest and delete the rest. Put the thread's id in place of "creating" in
the issue's "Staff checklist thread" comment, and the next event takes it.
If there is none, delete that comment only once you are sure no
thread in the forum is this issue's: one whose first message was deleted
can be, and its name started "#<issue number> " unless someone renamed it.
The issue's next event then opens a new thread. If you are not sure, leave
the comment; the sweep keeps listing it.
For a thread outside the checklist forum, set `CHECKLIST_FORUM_ID` back if
it changed by mistake; if it changed on purpose, archive or delete the old
thread, then delete that comment, and the next event opens a new thread.

A checklist problem never stops a player message: the checklist job is
separate, and a PR or release run updates threads after all its messages and
fails at its end. A later run for the same PR, or for the next release tag,
may wait while one finishes its checklist work; other runs, and the
checklist job, run alongside.

## Known limits

Accepted on purpose; each line says how you would notice it.

- The bot trusts its own KV records (`thread:`, `issue:`, `movedfrom:`,
  `movedto:`, `scan:` and `daily:named`) to hold what it wrote. A record
  edited by hand into another shape can make the scan, a filing or a move
  fail with an error in the Worker log; delete or rewrite it as the bot
  wrote it (Clearing a filing record). The one exception is `scan:since`:
  one that is not a time in milliseconds makes the scan greet nothing, with
  no error (an empty one or `0` reads as 1970, so the scan takes up every
  open post past its saved progress, however old), and deleting it restarts the scan
  from now, passing over every waiting post. Rewrite it with a time, never delete it.
- A setting saved as a JSON value with no text form, or a
  `DISCORD_PUBLIC_KEY` or `GITHUB_APP_PRIVATE_KEY` that is not text, is not
  checked for: requests fail with an error in the Worker log. Save each
  setting as plain text.
- The bot needs its `STATE` KV namespace bound; without it a filing cannot
  tell a moved post from its records, so an old post or a reply in the
  bot's copy can be filed, and an add saves no record, says nothing of it,
  and the post can be sent or added again. `/bot-check` names a missing
  binding.
- A filing knows a post was moved away only from its `movedto:` record. In
  about the minute before KV shows that record, or when its save failed,
  Send to GitHub on the old post files it, and Add to issue adds it; close
  the extra issue, or delete the extra report comment, by hand.
- A send or move form left open across a deploy of a new version is
  submitted as the new version reads it; send or move again if it answers
  oddly.
- A move copies the first message's text and files only: a sticker, a poll
  or an embed is not copied, and a file over 20 MiB, or past 24 MiB in all,
  stays on the old post.
- A first message over Discord's 2,000 characters is cut in the copy, and so
  in a later filing of the copy.
- Two first moves into one forum at the same moment make two webhooks; both
  work, and later moves use the first listed.
- Two actions on one post within about a minute. A move can overlap a
  filing, a scan, or a filing's late card edit or rename, and KV takes up to
  a minute to show a move's records everywhere. The locks stop a second send
  or move of the same post, but not these:
  - A send of the old post already running when the move finished: an issue
    for the old post. Close it, then send the new post.
  - A scan that listed a post just before a move locked it, or that ran
    before KV showed the move's record: a greeting or a queue card in or for
    the old post. Delete the greeting; the card's buttons answer that the
    post moved.
  - The bot's copy whose first message and moved message the scan cannot
    see (the moved message failed or the player deleted the first message,
    or both are past the post's last 100 messages): a greeting and a second
    card on the copy. Delete both.
  - A filing's card edit or rename that lands after a move of the same post:
    the card points back at the old post, or the old post is reopened.
    Right-click the new post; archive the old post again.
  - A status run on a filed post's issue during its move: its message goes
    to the old post.
  - A maintainer's edit to the issue's title, body or labels in the seconds
    between the move's read and its write: the move's write can undo it.
  - A reply sent in the new post before its filing record is saved: Send to
    GitHub on it can file a second issue. Close it by hand.
- On the free plan a move counts `fetch` calls only toward the 50 a run
  allows (see Moving a post); if KV calls count too, the figure there grows
  by six.
- A moved post's wait for the daily list of waiting posts starts again at
  the move: the list counts from the post's creation, the new post is new,
  and the locked old post is not listed. A move is a staff touch.
- A filed post's repo cannot change while it stays in its forum: transfer
  the issue on GitHub.
- A checklist thread keeps its name (`#<old number> ...`) after its issue
  is transferred.
- A move of a filed post opens its checklist thread to edit it and leaves it
  open, an archived one included, so a finished issue's thread shows in the
  active list until Discord archives it again for inactivity.
- A moved copy whose filing record was not saved or was deleted, and whose
  issue then lost `from-discord` or left `REPOS`, moves as a post not yet
  filed, as a send of it files it again.
- The bot expects every `REPOS` value in `owner/repo` form, which
  `/bot-check` reports; another value can stop the Move form or a move
  before anything changes. The issue's hidden bot lines (the
  `discord-copy`, `discord-message` and `discord-thread` lines, which stand
  together below the last "Moved to" line, or below the bot's own text
  before any move, and above any note a maintainer added below them) must
  not be edited, removed or copied: a body with no `discord-thread` line
  gets the bot's lines back on a move, which brings the issue back into the
  status and checklist jobs.
- Rare cases of a filed move, each left as it is:
  - A Move form left open while a deploy changes `REPOS`: a Repo field left
    as shown still keeps the repo, but a picked key is read under the new
    `REPOS`, so a remapped key transfers the issue to its new repo, and a
    removed key keeps the issue in its repo with that key's name in its
    title, record, card and reply.
  - A status message a workflow run still owes (its note written, its send
    failed) cannot be sent by re-running that run once the issue is in
    another repo: send it by hand and mark the note (top of this README).
  - An issue in a repo no `REPOS` key names (transferred there by hand)
    keeps that repo on a move, with the repo's name in place of a key in the
    title, record, card and replies.
  - A repo with two keys: a later Send to GitHub names its issue by the
    repo's first key, and a saved key `/bot-check` names as not usable is
    not pre-selected but is kept when the repo is kept.
  - Two keys for a repo's former and current names count as two repos:
    picking the other name's key tries a transfer (refused for a closed
    issue), and the setup checks ask for Contents write. `/bot-check`
    already names a moved repo.
  - An issue with two type labels keeps the first one's type on a move, and
    the other label is removed.
  - A checklist record that does not parse is not relinked, and the move's
    reply does not name it. One whose thread id staff changed by hand has
    that thread's first message rewritten when the bot wrote it, and gives
    the `staff checklist thread` line otherwise.
  - More than 25 usable `REPOS` keys: the Move form does not open, since
    Discord takes at most 25 options in a dropdown; the setup checks warn
    about that many keys.
  - A title a maintainer rewrote out of the bot's shape: the move cannot
    read the issue's client from it, so the form's client applies.
  - With `RENAME_POSTS` at `0`, a filed post with no client tag, in a forum
    with no client of its own, shows Client blank on the Move form; moved
    to another such forum, it asks staff to pick the client, and a client
    other than the issue's changes it.
  - A transfer slow enough to use most of the move's 12-second preparation
    leaves more files on the old post.
  - A transfer whose labels GitHub has not copied by the sixth read: the
    move changes the labels anyway, and a client or type label it removed
    can come back with the copy; remove it by hand.
  - The staff checklist thread keeps the name it was made with: after a
    move, or a retitle on GitHub, its name shows the old issue number or
    title, while its first message shows the current ones.
  - A title a maintainer lengthened to near GitHub's 256 characters can make
    the issue edit fail after a move; the reply names "issue link to the new
    post", and status messages keep going to the old post.
  - Markup a maintainer opened above the bot's hidden lines and closed below
    them, such as a `<pre>` block, also encloses the "Moved to" line, which
    then shows as plain text.

- A message whose send failed is never sent again automatically: the sweep
  lists it as unconfirmed, and a person decides.
- A post the scan fails to greet in 30 runs in a row (server errors included),
  about 30 minutes at one scan a minute, is given up on; the daily alert names
  it.
- A post the scan gave up on can be named again by the scan's saved problem
  paragraph in the next daily alert, a deleted post included when an earlier
  try failed for another reason, and one whose give-up the scan could not
  save in its state is not named at all.
- A closed issue whose close GitHub's events list does not show yet is
  judged from an earlier close, or from none, until the next run.
- When a ship record cannot be written and GitHub's tag list lags, the
  staff checklist can show the issue's status from before the release until
  the next run.
- A move while the Message Content setting is off copies a post with no
  text or files as the "nothing the bot can copy" placeholder, then locks
  and archives the old post: `/bot-check` names the setting; unlock the old
  post and delete the copy.
- A player's edit, file removal or deleted first message in the seconds a
  move runs can be copied as it was before; a moderator can delete or edit
  the copy.
- If Discord's setup reads stall long enough, the daily setup report can
  go to the Worker log instead of the moderator channel; the next day's
  check runs again.
- A "Staff checklist thread" comment whose hidden lines staff broke reads
  as no record, so the next job can open a second record and thread; delete
  the broken comment or mend it as the bot wrote it.
- A Discord link in a PR to a post whose issue carries the label in another
  letter case (`From-Discord`) gets a merge-plan line too.
- A post can rarely get two greetings when two scans overlap (a scan that runs
  longer than a minute).
- A queue card can stay live on a filed post, or a post can get two cards:
  two overlapping scans, a card send whose answer was lost and that has since
  scrolled past the queue channel's last 100 messages, a card posted while
  its post was being filed, a post archived, locked or deleted in the moment
  between the scan's read of it and its card, or a failed card edit. Nothing
  lists such
  cards. Once the post is filed, pressing one answers "Already tracked" and
  marks that card filed, and a form it opened earlier files nothing. While
  the post is not yet filed, both cards offer the form; filing from one marks
  only that one, and the other is marked when someone presses it.
- A queue card for a post that never needs an issue stays in the queue
  channel until someone deletes it.
- Discord allows the bot only a few renames of one post in a short time
  (reported as about two in ten minutes), and does not document the limit.
  A filing soon after other renames of its post still creates the issue and
  answers the moderator, but its rename can be refused. The post then keeps
  its name, and the Worker log line `post <post id> rename failed:` shows
  Discord's 429. Rename the post by hand later.
- A card whose post was deleted shows "# unknown" in place of the post's
  name, so the card no longer says which post it was.
- If presses keep answering "press again" (GitHub slow or failing), a
  moderator can right-click the post instead: it opens the form with no
  check, and the form's submission checks.
- A post scanned while the queue channel refuses the bot (it was not let into
  the channel yet) gets no card, even after the permission is fixed. The next
  daily alert names each such post, and moderators file it by right-click.
- A post archived or locked before its card went out gets no card, and nothing
  names the missing card. This includes a post archived or locked while a
  broken setting stopped the scan. The daily waiting list covers it only in part: it
  lists posts older than `STALE_DAYS` (3 by default) with no status or
  `Answered` tag, leaves out locked posts, reads archived posts from the last
  30 days only (up to 300 per forum), and names about 20 posts at most.
  A moderator's right-click filing always works.
- A post whose greeting and card keep failing for 30 tries in all is given up
  on: before the greeting is out, it gets neither; after, it keeps its
  greeting and gets no card. The next daily alert names every post given up
  on since the last one, with its link, and moderators file it by
  right-click. The alert and the day's list of waiting posts share the daily
  check's four messages, each split between whole lines; what does not fit
  goes to the Worker's log, the list's last part first, then the alert's.
- If the bot's greeting went out but its id was not saved, the next scan looks
  for it among the post's last 100 messages; a post busier than that can get
  a second greeting. The same look finds the bot's "now tracked" reply, so a
  post filed without a saved record gets no greeting after it, unless the
  filing lands in the moment between that look and the greeting's send, or
  the reply is further back than those 100 messages.
- The sweep reads every bot issue ever filed, so it grows with the issue count;
  it fails loudly when it runs out of API calls.
- The workflow reads each issue's closing event in two near-identical queries.
- A few early commits mix two changes; merged history is not rewritten.
- A link made only in a PR's Development sidebar, or a `Fixes #N` removed from
  a description, moves nothing until the issue's next event or a fix-mode
  sweep.
- A Discord link in a PR to a post whose issue is in another repo, or that
  was never filed, makes no merge-plan comment: the workflow knows only its
  own repo's issues. A `Refs #N`, or a closing keyword GitHub does not list,
  whose issue has since been transferred to another repo is named as if it
  were still here.
- The merge plan reads `#N` and `owner/repo#N` after a keyword, the forms
  GitHub documents, not an issue's URL: a `Refs` or closing keyword followed
  by a URL gets no line of its own. GitHub's own list of closing issues still
  counts, whatever form GitHub read.
- The merge plan sees a Discord link only when it stands alone: at the start
  of a line or after a space, and ending at a space or the end of a line. A
  link that something touches (`[post](...)`, `<...>`, another URL holding
  it, or a sentence's period) gets no thread-link warning. A link inside
  Markdown may or may not count: a reference definition or a link with
  spaces inside its parentheses stands alone, so it counts. An unused reference
  definition is not shown on the PR page but still counts. A link that counts
  always names the post its URL names.
- The merge plan's GitHub reads share the workflow token's hourly allowance
  with the status job. A status job that GitHub refuses for the limit fails
  like any failed run, and re-running it recovers what any re-run recovers
  (above).
- The merge-plan job also takes a hosted runner for about a minute per PR
  event. When the account's runners are all busy (GitHub's per-account
  concurrent-job limit), GitHub queues new jobs, so another run's status job
  can wait for one. Its In progress message then goes out late, or is
  skipped if the PR turns draft first, as whenever GitHub is slow to start
  a job: the status job reads the PR as it is when it runs.
- The merge plan's cross-repo warning needs the other repo's issue to be
  readable with the workflow's token. A closing reference the token cannot
  read can stop the merge plan of that PR; the merge-plan job's log says why.
- The merge plan follows the PR's own events: a Development sidebar link, or
  an issue closed or relabeled, shows at the PR's next event. A closing
  keyword in a commit message is not shown, and neither is a post's status.
- The merge plan of a PR with more than 100 closing references reads only
  the first 100 GitHub lists; a reference past those is named only when the
  PR's description holds its closing keyword.
- A merge-plan comment write that times out may still be applied by GitHub
  after the job has moved on, and a job stopped partway (an error, or its time
  limit) may have edited one copy and not another. The PR can then show an
  older plan, or two copies, until a later event's job edits them; after the
  PR's last event they stay until someone edits or deletes the extra comment.
- A fix-mode sweep that runs while a PR's merge-plan job is queued (behind
  that PR's previous merge-plan job, or for a free runner) or running, after
  that PR's status job failed to move a post and the PR went back to draft,
  keeps that run's In progress message owed. The PR's next ready event then
  sends nothing; the sweep lists the message, and re-running the failed run
  sends it.
- A merge-plan job whose checkout or Node setup GitHub stalls past its
  5-minute limit is canceled, and that shows the Discord status run as canceled
  rather than green or red, whatever the status job did. Open that run and
  use Re-run all jobs, whether its status job passed or failed. Its status
  job then does what any re-run does (above: a message still owed and still
  true goes out; a failed send stays listed by the sweep for a person). The
  re-run also rebuilds the comment, which matters when the run was the PR's
  last event (a merge, or a close).
- A run also shows as canceled when GitHub drops its waiting merge-plan job:
  each PR keeps one merge-plan job running and one waiting, so a third PR
  event in quick succession drops the one that waits. Nothing is lost, since
  the newest run rebuilds the comment. Re-run that run only if its status job
  failed, as for any failed run.
- An owed message goes out only when someone re-runs the run that owes it, even
  if another run has moved the post since; until then the sweep lists it with
  that run's link. GitHub allows re-runs for 30 days from the run's first
  attempt; the sweep counts from the note, so a note from a late attempt can
  be held past that window, and after 50 re-runs the sweep still points to
  the run. Once the note is 30 days old the sweep says so, and a person sends
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
  be read as formatting. A diagram word such as `mermaid` is kept, so GitHub
  draws that block. Code
  indented by four spaces is escaped like text, so `<` shows as `&lt;` there.
- Text between two dollar signs with no space inside them, such as `$a$`, can
  show as a math formula. What is inside stays escaped text.
- Discord takes only a whole tag list, so a tag someone adds to a post in the
  moment between the bot's last read of its tags and its write can be lost,
  and one someone removes in that moment can come back. The bot reads the
  tags again just before each write, so that moment is one request long.
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
  sent again. A move of such a post is refused while the bot's "now
  tracked" reply is among the post's last 100 messages; a send is not.
- With no saved filing record, the bot searches every configured repo once
  before filing. An issue moved between two configured repos while it
  searches can be missed, and a second issue made. So can one in a repo
  with more than 100 issues labeled `from-discord`, when labels change during
  the search and its place in GitHub's issue list shifts between two pages.
  The search takes a second or two.
- On Workers' free plan a run may make 50 outgoing calls. A filing whose
  repos together hold more than about 3,200 `from-discord` issues updated
  since the post was made (about 3,400 with `RENAME_POSTS` at `0`) can use
  them all. The post's rename and the card update come last and go unmade
  first; with more issues the filing can run out before it answers the
  moderator and releases its lock: the moderator may see no result, and
  until the lock label is cleared the post's next send says another send
  is running. Repos that large need Workers Paid.
- A queue card still owed looks for the bot's "now tracked" reply among the
  post's last 100 messages. A post filed after its greeting, whose filing
  record was not saved (or not yet seen) and whose reply is further back
  than that, can still get a card; pressing it answers "Already tracked" and
  marks it filed.
- If the daily alert went out but saving which posts it named then fails,
  the next daily alert names those posts again.
- A post the scan keeps failing on holds back its progress for up to 30 runs
  (an hour, for a record that cannot be read). Meanwhile the scan reads every
  finished post after it again each run; with more than about 40 of them,
  the newest posts wait for their greeting until it gives up.
- GitHub cannot delete a label only if it is unchanged. If two people each
  read the same old lock's time and both delete it, one after the other, the
  second can delete a new lock a filing took in the seconds between, and two
  filings can then make two issues.
- The daily alert's count of give-ups is not exact. A give-up saved just
  after a daily check, whose first alert the moderator channel refuses, can
  expire (after two days) before the check that would name it again. An
  alert Discord took but whose answer was lost is sent again the next day. A
  post whose greeting went out but whose record could not be saved on its
  30th try, with a queue channel set, is named as a given-up queue card
  though no card was tried. If `daily:named` cannot be read, that day's
  alert, scan warning and list of waiting posts are not sent.
- A run of new posts can spend the scan's KV reads before older posts'
  card retries, so those cards wait a run. Cards already in the
  queue channel whose record writes keep failing take the scan's card slots
  every run until a write works, and newer posts' cards wait meanwhile.
- Do not rename, swap or add the bot's tags (the status tags and `Accepted`,
  in a player forum or the staff checklist forum) while the bot may be
  writing: a post being filed; an issue opened, closed or reopened; its
  `accepted` label added or removed (the checklist job); a PR opened,
  edited, reopened, closed, marked ready or converted to draft; a release
  tag pushed; or a sweep (03:17, 09:17, 15:17 and 21:17 UTC). Each bot
  write first reads the forum's tag names; a tag renamed, swapped or added
  from that read until the write lands is written under its old meaning.
  To change the tags of a post or checklist thread, the bot reads the forum,
  then the post or thread, then writes, so the gap is about two requests.
  A new checklist thread's names are read before the bot checks the issue
  and saves its record on GitHub, and the thread is created after that, so
  its gap can last a few seconds. The post can then show the wrong tag: a
  post that wrongly shows `Closed` gets no message at the issue's next
  close, one that wrongly shows In progress gets none at a reopen, and a
  staff tag can be dropped or come back. After a rename, check the posts and
  checklist threads the bot touched in those minutes and fix their tags by
  hand.
- If a player deletes the message being filed in the moment its issue is
  created, the issue still quotes it; close or edit it by hand. If the first
  message is deleted in the moment its card is posted, the card still offers
  **Send to GitHub**. Pressing it still opens the form; sending the form
  files nothing and says the message was deleted.
- GitHub times out a request after 10 seconds, but its docs do not say
  whether a create it timed out can still be applied later. The hour before
  a lock may be deleted is a wide margin, not a guarantee: if GitHub applied
  such a create more than an hour late, after the lock was deleted and the
  post's next send had searched, the post would get two issues.
- A failed write right after a Discord write, or two bot runs writing one
  checklist thread at once, can leave that thread's tags or archive state
  wrong; the sweep names the thread and what to check. Player
  messages, public tags, queue cards and staff tags are never affected;
  anything else is a bug to report.
- Two bot runs that cross on one checklist thread, or a run after a record
  write that failed, can archive again a thread staff reopened; and a close
  run's late archive whose record write failed can leave an open issue's
  thread archived. Nothing lists either: you notice a thread you replied in
  that is archived again, or an open issue's thread that is archived. A
  staff reply reopens the thread for good.
- If the bot's re-archive of a finished checklist thread fails after a tag
  change, or the job is stopped between the tag change and the re-archive,
  or a tag change times out (the bot then sends no re-archive), the thread
  may stay open and nothing lists it; the run is red in Actions. One click
  archives it.
- If the bot's re-archive fails after it changed the tags of an open issue's
  thread that Discord had archived for inactivity, the thread stays open and
  nothing lists it; the run is red in Actions, and Discord archives it again
  after the forum's inactivity time.
- A staff reply in the moment between the bot's last read of an archived
  checklist thread and its tag write, or between that write and the
  re-archive, can be archived over, as a tag can be lost in that moment. The
  moment is one request long; another reply reopens the thread for good.
- A tag someone adds to a checklist thread in the moment between the bot's
  last read of its tags and its write can be lost, and one removed in that
  moment can come back, as on a post. That moment is one request long.
- When GitHub drops a waiting checklist job for a newer one, the thread jumps
  to the newest state: you see its status tag skip a step (Triaged straight
  to Done, say). Nothing is lost.
- A closed issue filed before this version gets no checklist thread and is
  not listed; a reopen or an `accepted` label change opens one.
- A checklist thread whose create answer was lost stays "not confirmed",
  with its job red, until staff put its id in the record comment. The bot
  never creates again for it; the sweep lists it and says what staff do
  (see Staff checklist).
- The bot trusts the thread id in a "Staff checklist thread" comment as
  written. An id staff put in by hand, or a comment copied from another
  issue, is taken without a check: the bot then writes tags to that thread.
  Never copy that comment between issues, and check an id before you put
  it in.
- Adding or removing the `accepted` label changes nothing at once. The post
  gets the change at its next status change, or at a fix-mode sweep while it
  is not archived and shows Triaged alone. The same holds for a post whose
  status run read the issue just before the label changed, for two status
  runs on one issue that cross (the older can write Accepted back), and for
  a slot freed after a status change. A post showing another status, or two
  status tags, waits for its next status change; the sweep lists it
  meanwhile.
- An `Accepted` tag on a closed issue's post is listed by the sweep while
  the post is not archived, and the sweep's Accepted repair never removes
  it; nor does a close whose post already shows that close's status. A
  fix-mode status repair removes it when the post's status is out of step
  too, as after a put-back (below); otherwise remove it by hand.
- A status change that lands while a fix-mode sweep writes Accepted on a
  Triaged post (from Discord serving the sweep's last read of the post to its
  write taking effect) is put back to Triaged, with the Accepted tag as the
  sweep wrote it, even on an issue that was just closed. The player still
  gets that change's message once. The post shows Triaged until the next run
  that settles its status (an `accepted` label change runs none) or the next
  fix-mode sweep.
- If a status run was part-way through when such a change was put back, it
  can write its own older status afterward, and a later run that wants that
  status then finds it shown and sends nothing: the player can miss one
  later message. Two cases are known. A PR run under way, a close inside the
  sweep's one write, then a reopen with the PR still open: no In progress
  message for the reopened issue, though the post shows In progress. A close
  run under way, a reopen whose In progress write lands inside the sweep's
  one write, then a close as not planned: no "Not planned." message, though
  the post shows Closed.
- If an issue is closed while a fix-mode sweep writes Accepted on its post,
  and the forum has no tag for that close or the close's own tag write fails
  or is refused, the post can show Triaged and Accepted on the closed issue.
  The sweep lists it with the owed close message; fixing the cause (adding
  the tag, or nothing for a passing failure) and re-running that run sends
  the message and removes Accepted. Once that run can no longer be re-run,
  the sweep stops holding the post. If the close's tag exists by then, a
  fix-mode sweep moves the post and removes Accepted without the message,
  and the sweep's line says to send it by hand if it is still needed. The
  post keeps Triaged and Accepted while the close's tag is still missing:
  the sweep lists it and skips the move until the tag is added.
- If an issue is reopened and closed again while another bot run (a fix-mode
  sweep or a PR run) is opening its checklist thread for the reopen, the
  finished thread can stay open with nothing listing it: you see a finished
  issue whose thread is open, and one click archives it.
- If an issue is reopened and closed again before GitHub lists either
  event, or closed again for another reason while the bot reads
  it, the thread can be keyed on the wrong close: it stays open until the
  sweep lists "checklist archive owed", or a staff reply made after the
  bot's archive is archived over once; reply again to reopen it for good.
- If `from-discord` is taken off an issue in the seconds its checklist thread
  is being made, the thread can still be made and nothing lists it, as the
  sweep skips that issue: you see a thread for an issue the bot no longer
  files; keep or delete it.
- If the "Staff checklist thread" comment is deleted or replaced in the
  seconds the bot is making the thread, the thread is made but not recorded,
  the job is red, and the issue's next event can make a second one: you see
  two threads for one issue; keep the one that comment links and delete the
  other.
- If an issue closes as the bot reads the checklist forum just before making
  its thread, and GitHub does not show the close yet, the thread is made
  open; the issue's next event or a fix-mode sweep archives it.
- An edit to the "Staff checklist thread" comment saved in the moment the bot
  rewrites it can be lost: you see your edit gone; make it again.
- `/bot-check` and the daily setup check cannot see the Actions settings; a
  status run or the sweep names a bad one as a red run.
- GitHub shows no job summary at all for a step whose summary passes 1 MiB.
  A sweep's report quotes each note it lists in full, so a very long report
  can pass it; its setup problems are then only in the run's log, where
  each was met.
- A Discord refusal met during a sweep's checklist repair is named inside
  the two minutes that work may take, so a sweep right at that limit can
  leave the next issue's checklist thread for a later sweep.
- An issue that gets the accepted label after a sweep read its staff
  checklist thread, in a checklist forum with no Accepted tag, is not named
  by that sweep; a fix-mode repair of the thread that settles logs the
  missing tag, and the next sweep names it as a setup problem.
- A Discord refusal still in flight when a run's time limit stops it is not
  named by that run. A refused message send is not tried again (its note is
  listed by the sweep as maybe not delivered), so its fix comes from the
  daily setup check, which names the forum's missing permission.
- The setup check computes the bot's permissions from the server's roles and
  each channel's overrides, in Discord's documented order; a rule outside
  that order can make a line wrong.
- A repo with 300 or more labels can leave some of the bot's labels
  unchecked; the check says which.
- With `MOD_CHANNEL_ID` empty, the scan's alert goes to the Worker log and
  counts as delivered, so setting the channel later does not repeat it;
  the setup check names the empty setting every day, but only in the
  Worker log, so run `/bot-check` after setting up.
- The Worker cannot see its own cron triggers. Without the setup check's
  schedule, no Monday line arrives; without the daily list's schedule,
  nothing says so. Wrangler's output after each deploy is the check.
- The setup check compares `DISCORD_PUBLIC_KEY` with the public key of the
  app the bot token belongs to. A mismatch says the two belong to different
  apps, not which one is wrong; and a token and key that both belong to the
  wrong app agree.
- The moderator channel check sees only `@everyone`: a role that players
  hold and that is allowed into the channel is not found.
- The checks trust the fields Discord and GitHub document as always
  present. Some settings `/bot-check` flags are no longer checked again
  when used: more than 25 forums or repos for a form's choices, or no
  usable `REPOS` key, can make the form fail to open with Discord's generic
  failure, and a `QUEUE_CHANNEL_ID` outside this server gets a moved post's
  card wherever the bot can write. A failed read is "could
  not check", never a pass.
- A player name that looks like `#12`, `GH-12`, a commit hash or a URL can
  show as a link in the issue's Reporter row.
- A `FORUMS` entry's `client` or `type` that is misspelled or written as a
  JSON object instead of text reads as unset, and `/bot-check` does not name
  it: the form guesses from the post's tags instead, and a move goes by the
  post's own tags.
  Write each as plain text, like `"type":"Feature"`.
- Repeat reports (Adding a repeat report), each left as it is:
  - A send or a second add of a post before KV shows its add's record can
    file the added post or add it twice, since an add writes no hidden line
    in an issue's body for the search to find: close the extra issue, or
    delete the extra report comment. An add after a send is caught by the
    search for the issue's hidden line.
  - Two adds to one issue at the same moment can get the same N.
  - A report comment GitHub did not confirm, and applied only after staff
    checked and added the post again, leaves two report comments for one
    post: N counts one too many, and the player is mentioned once when both
    name the same player (a retry from another author's message names a
    second player, who is mentioned too). A maintainer deletes the extra
    comment.
  - A status message whose run read the issue's comments before an add
    wrote its report comment goes out without that player; the next message
    names them.
  - A report comment deleted on GitHub lowers later numbers, and its player
    is no longer mentioned once it was their last one on the issue.
  - With more than about 80 added players on one issue, a status message
    passes Discord's 2,000 characters: Discord refuses it, its note is
    marked Unconfirmed and the run fails.
  - An added post's record keeps the key and number of the add, so after the
    original post moves the issue to another repo, Send on the added post
    names the old ones.
  - An added post whose record was not saved ("post record not saved") can
    be sent or added again.
  - An issue closed in the seconds between the add's read of it and its
    comment still gets the comment, and the add reports success: the check
    uses the issue as the add read it.
  - For about a minute after a fix commit closes an issue, until that
    close's status run sets `pending-release`, or after a close run that
    failed, Add refuses it as having no fix waiting; add the post again in a
    minute, or once the run is fixed and re-run.
  - An added post's card whose edit failed (the Worker log has `queue card
    ... not updated`) still offers its buttons: Send answers that the post
    was added, and Add that it was already added.
  - A moved copy added within a minute of its move, before its move record
    is readable, is credited to the webhook's name and its player is not
    mentioned.

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
   `In progress`, `Fixed, next update`, `Shipped`, `Closed`, an `Accepted`
   tag and an `Answered` tag. Make a staff-only queue channel. Copy each
   forum's and the channel's id and the server's id (Developer Mode on,
   right-click > Copy ID).
2. **Discord app.** At discord.com/developers/applications: New Application >
   Bot > Reset Token (keep it). Under Privileged Gateway Intents switch on
   **Message Content** (the bot reads the post it is pointed at; it never listens
   to the server). Under Installation set **Install Link** to None first
   (Discord will not save the next step while a default install link exists),
   then under Bot switch **Public Bot** off so only you can invite it.
   Note the Application ID and Public Key from General Information.
3. **Invite it** with OAuth2 > URL Generator: scopes `bot` + `applications.commands`,
   permissions View Channels, Read Message History, Send Messages, Send
   Messages in Threads, Manage Threads, Manage Webhooks. Then check each
   channel's own permissions, since a channel can override the invite's:
   - each player forum: View Channel, Send Messages in Threads, Manage
     Threads, Read Message History (without it every queue card says the
     first message was deleted) and Manage Webhooks (a move posts its copy
     through the bot's webhook there);
   - the queue channel: View Channel, Send Messages and Read Message History.
     Let the bot into it before you set `QUEUE_CHANNEL_ID`: a post scanned
     while the channel refuses the bot gets no card;
   - the moderator channel, a staff-only text channel of the server (View
     Channel denied to `@everyone`): View Channel and Send Messages. The
     bot's setup results and alerts there name its settings.
   `/bot-check` (step 10) checks all of these.
4. **GitHub App.** github.com/settings/apps > New GitHub App: no webhook,
   Repository permissions **Issues: Read and write**, Metadata: Read, and,
   when `REPOS` will name more than one repo, **Contents: Read and write**
   (moving a filed post to another repo transfers its issue). Create,
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
   Wrangler then lists the schedules it deployed: there must be three,
   `* * * * *` (the post scan), `0 15 * * *` (the daily list) and
   `30 15 * * *` (the daily setup check). If any of the three is missing or
   different, copy the `[triggers]` block of the committed `wrangler.toml`,
   its `crons = [...]` line included, into yours, compare the three
   expressions, and deploy again; the Worker cannot see its own triggers, so
   no check names a missing one. Then run `/bot-check`
   after every deploy (step 10).
6. **Point Discord at it.** Developer portal > General Information >
   Interactions Endpoint URL = that URL. Discord checks it on save.
7. **Register the commands** (the right-click Send to GitHub, Add to issue
   and Move post, and `/bot-check`) on the test server only, and again after
   updating to a version that adds one (the register command sends all four):
   `DISCORD_APP_ID=... DISCORD_BOT_TOKEN=... DISCORD_GUILD_ID=<test server id> npm run register`
8. **Labels:** `GITHUB_TOKEN=<a token with repo access> npm run labels <you>/<test-repo>`
9. **Status workflow in the test repo:** copy `.github/discord-bot/` and
   `.github/workflows/discord-status.yml` into it and add the repo secret
   `DISCORD_BOT_TOKEN`.
10. **Check the setup:** in the test server, run `/bot-check`. Its result
    goes to the moderator channel; fix each line it names, then run it again
    until every check passes.

Then walk one fake report through: post in a test forum and wait up to a
minute for the greeting and the queue card, press **Send to GitHub** on the
card with the test role, submit the form, and a minute later check that the
post's name is now the issue's title (cut at 100 characters when the title
is longer; the rename comes last, after the reply),
open a PR with `Fixes #N` into the default branch (from an account with a
role on the repo), merge it, and push a tag. **In this KitnEssentials test
copy, use a `discord-test-1` style tag: its own `v*` tags publish real
releases to CurseForge and Wago.** Each step should change the tag and post
its message. (The workflow here already defaults to that tag pattern; set the
repo variable `RELEASE_TAG_PATTERN` to change it.) Run the `Discord status`
workflow by hand once to see the sweep's report.

**Reading the results without looking.** `node scripts/trial-check.mjs <id>...`
prints each post's name, forum, tags, archived and locked state and last
messages (a text channel id prints its last messages; `--limit N`, default
10); `--forum <id>` lists a forum's open posts and its 50 newest archived
ones with their tags. It only reads.
Give it its own bot, never the trial bot: a new application whose bot has
the **Message Content** intent on and is invited with View Channels and Read
Message History only. It also gets whatever `@everyone` may do in each
channel, so use it on a test server only. Its token goes in
`TRIAL_READER_TOKEN` or in the file `~/.discord-trial-reader/token`, alone on
one line, outside every repo.

## Stage 3: live

Same steps against the real server and repos, with `FORUMS` set to the real
forums and the command at first registered without `DISCORD_GUILD_ID`
(global). Narrow who sees the right-click command under Server Settings >
Integrations > the bot > Send to GitHub (Mod and Admin roles); the button
checks `APPROVED_ROLE_IDS` itself. Leave `SWEEP_MODE` unset (report only)
and read one or two sweep summaries (run the `Discord status` workflow by
hand, or wait for the scheduled ones). If a line names a post or thread you
do not expect the bot to change, ask before going further; otherwise set
`SWEEP_MODE` to `fix`. This look is a sanity check, not a guarantee of what
fix mode will change: a run going at the same time, or two entries on one
line, can make fix mode do more or less than the summary suggests.

Fix mode turns on, for every bot issue: quiet status repairs, which also
reopen an out-of-step archived post and set its Accepted tag; release
labels; missing ship records; dropping notes whose message no longer holds;
the Accepted repair on posts that are not archived and show Triaged alone;
and, with `CHECKLIST_FORUM_ID` set, the staff checklist threads' tag and
archive repairs, which can retag, archive or reopen a thread and update its
record.
It also makes five known limits possible (Known limits): a status tag
shown without its message; a message the player may get twice; and, from
the Accepted repair, a status change put back to Triaged, one later
message lost when a status run was part-way through such a put-back, and a
closed issue's post left showing Triaged and Accepted.
Each repo's copy has its own variable and its own soak.

The workflow checks out the repository's default branch, and scheduled runs
use the default branch's workflow file, so the bot's code runs from the
default branch only. A copy whose code lives on another branch must make
that branch the repository's default.

Each repo the bot files into needs its own copy of `discord-status.yml` and
this folder, and the GitHub App installed, with Contents: Read and write
when `REPOS` names more than one repo (Stage 2 step 4). When updating, give
every such repo this version's folder on its default branch before the
Worker is deployed: the workflow runs its own repo's default branch, and an
older copy reads the issue's hidden lines only at the body's end, so after
a move of an issue with a maintainer's note below them it would find no
footer and post the message plainly in the new post, with no ping. For this repo that is the merge; for
each other repo, a copy. An older copy also leaves added players out of
status messages. For the Add to issue version, also run `npm run register`
again, and `npm run labels` for each repo in `REPOS` before the deploy, so
`player-report` exists. With more than one repo in
`REPOS`, set `LOCK_REPO` to the repo that holds every filing's lock label,
whichever repo it files into; until it is set, nothing is filed. Before
changing it, follow "Changing the lock repo" above. Set its push trigger to that repo's release tags, and the repo
variable `RELEASE_TAG_PATTERN` to an anchored pattern that matches only them:
for tags like `v5.0.120`, `tags: ['v*']` and `^v\d+\.\d+\.\d+$`; for tags like
`30.8` or `31`, `tags: ['*']` and `^\d+(\.\d+)*$`. A tag whose name holds alpha,
beta, rc or pre, not inside a longer word, never counts, whatever the pattern
says. The guard misses `preview` and `1.0b1`, so a looser pattern must refuse
those itself.

