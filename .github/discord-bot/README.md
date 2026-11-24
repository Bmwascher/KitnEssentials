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
issue), and changes the card to "Filed as KE #17 by <name>". Moderators can
still right-click any post or message > **Apps > Send
to GitHub** for the same form; the reply then goes to that message, and the
post's card is marked filed too. A greeting from an earlier version that still
shows its own button keeps working; once the reply exists, the bot deletes it,
or removes its button if it may not delete it.

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
can right-click the post instead (the form's submission checks too). The
submission reads the message to file again just before it creates the
issue: a message deleted meanwhile files nothing and says so, and so does a
deleted post.

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
from moving, its message stays owed. The sweep leaves that post as it is
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
permissions to check; a deleted post is skipped without a word. The alert,
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
  Both do nothing until the `DISCORD_BOT_TOKEN` secret exists, so they are safe to merge early.

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
setup check, and its replies to a moderator while a setting is broken.

- **`/bot-check`.** A moderator (Manage Threads) runs it in the server the
  bot is set up for; in any other server, or while `GUILD_ID` is not set, it
  is refused. It checks:
  - the Worker's settings, as the bot reads them;
  - the bot's permissions in each player forum, the queue channel, the
    moderator channel and the checklist forum;
  - each forum's tags and template message;
  - the Message Content setting and the approved roles;
  - that the moderator channel is hidden from `@everyone`;
  - that the four secrets are set and of the right form (never their values),
    and that `DISCORD_PUBLIC_KEY` and `DISCORD_BOT_TOKEN` belong to the same
    app;
  - for each repo in `REPOS` and `LOCK_REPO`, once in any letter case, the
    GitHub App's install, its Issues permission and, for a filing repo, the
    bot's labels.

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
- **A setting the Worker cannot read** stops the bot until it is fixed: a
  setting saved as a JSON value with no text form, or a
  `DISCORD_PUBLIC_KEY` or `GITHUB_APP_PRIVATE_KEY` that is not text (a JSON
  `null` included). While it stands, new posts get no greeting and no queue
  card, the daily list of waiting posts is not posted, and nothing is filed:
  a moderator who right-clicks a post or runs `/bot-check`, and a moderator
  or a member of an approved role who presses a card or submits the form, is
  told privately "The bot is not set up yet:" and the setting's name.
  `/bot-check` runs no checks then. The daily setup check still runs
  and names it, in the moderator channel when it can post there, otherwise
  in the Worker's log. Once the setting is fixed, the scan greets and cards
  the open posts made meanwhile; a post archived or locked meanwhile gets no
  card (Known limits).
- **Filing** into a forum without the `Triaged` tag still files the issue.
  When the bot tries to set `Triaged` on a post with no status and cannot,
  the moderator's reply includes "tag not set" with the reason, among its
  other notes. The setup checks name a missing status tag of every forum
  every day.

Neither check can see the Worker's cron triggers. After every deploy, read
Wrangler's output (step 5 of the setup).

## The issue

The issue opens with a small table: the reporter and the moderator who filed
it, each as their server name linked to their Discord profile, with their
username (a webhook's post shows its name alone), and a link to the post. The
quoted report follows, then the attachment count and the template check. The
issue keeps those names, usernames and Discord ids as they were at filing; a
maintainer removes them by editing the issue. Two hidden lines at the end name
the filed message and the post; leave them in place.

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
id, or a setting with no text form. The setup check writes a line for every
such key, within its usual display limits; while a setting has no text
form, `/bot-check` names that setting instead, and the daily setup check
names the keys. A `DISCORD_PUBLIC_KEY` with no text form fails the
signature check of every request, so the bot answers nothing, `/bot-check`
included, and only the daily setup check names it and the keys.

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
configured repo twice for the post's hidden line; a match anywhere answers
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

A record the bot calls damaged is empty, not JSON, or not a record the bot
writes: a filing record whose repo is not `owner/name` or whose issue number
is not a positive whole number, or a scan record with a field of the wrong
kind (a `tries` written as text, a `tracked` that is not a message id). A
damaged `issue:<post id>` holds nothing to keep: delete it as in step 1. A
damaged `thread:<post id>` may still hold the greeting's and card's ids:
read it (step 2), and if it is JSON, write it back (step 3) with only its
`greeting`, `buttonless` and `card` fields, keeping each that looks right (a
`greeting` or `card` is a message id, `buttonless` is `true`); otherwise
delete it the same way as step 1. The post scan never writes over a damaged
record: it gives that post no greeting and no card, and the next daily
alert names it; a scan record that still cannot be read an hour after its
post was made is named the same way. Deleting `thread:<post id>` loses the
card's id, so a later filing by right-click leaves that card live; press it
once to mark it filed.

The scan's own keys are checked too. If `scan:since`, the time the bot
started, is damaged, the scan stops rather than start again from now, which
would pass over every waiting post, and the daily alert says so. Put back a
time in milliseconds since 1970 (`node -e "console.log(Date.now())"` prints
the current one) with
`npx wrangler@3 kv key put --binding=STATE "scan:since" "<time>"`: the
current time skips every post made before it, and an earlier one lets the
scan greet the open posts made since. A damaged `scan:state` is rebuilt by
the next scan, and the daily alert says so: posts the scan gave up on
before may be missing from it. A damaged `daily:named` makes the next daily
alert say that some posts it names may have been named before.

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
   then nothing here runs.

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
the sweep lists it. The sweep names only the bot's tags in the Actions log,
and counts staff tags.

**Who opens.** Only the issue's own events open its thread: opened, closed,
reopened, and the `accepted` label added or removed. The workflow's
`checklist` job runs them, one at a time per issue, and each job brings the
whole thread in step with GitHub. PR and release runs and the sweep
update a thread that exists, but never open one. An issue filed before this
version, or one whose open failed, gets its thread at its next such event, or
when its failed checklist job is re-run. If Discord made a thread but its
answer was lost, the next job looks for it in the forum the create went to,
by the bot's own first message naming the issue, and takes it when exactly
one bot thread matches. The bot never makes a second thread for the issue's
"Staff checklist thread" comment; anything else leaves it "not confirmed"
for staff (see the sweep).

**Archiving.** A thread is archived when its issue is finished (Shipped,
Done, Won't fix, Duplicate), once per close: the issue's "Staff checklist
thread" comment notes which close it was archived for. A staff reply reopens
an archived thread, and the bot leaves it open until the issue closes again.
A reopened issue's thread is opened again. A tag change by the bot keeps a
thread's archive state, so a thread Discord archived for inactivity stays
archived.

**The sweep** lists each checklist problem with the thread's link and what to
do: an open issue with no thread, a thread not opened or not confirmed, an
archive owed or one made for a close that no longer holds, a deleted thread,
a thread outside the checklist forum, a missing tag in the forum, and tags
out of step. With `SWEEP_MODE=fix` it repairs tags and archive state; it
never opens a thread. For a thread not confirmed after a lost create answer,
the sweep links the forum the create went to and the issue's addresses.
With more than one bot thread whose first message names the issue, keep the
oldest and delete the rest, and the next event takes it. If the job still
fails, put the thread's id in place of "creating" in the issue's "Staff
checklist thread" comment; the next event takes it only when the thread is
in the forum the create went to and its first message is the bot's for
that issue. If there is none, delete that comment only once you are sure no
thread in the forum is this issue's: one whose first message was deleted
can be, and its name started "#<issue number> " unless someone renamed it.
The issue's next event then opens a new thread. If you are not sure, leave
the comment; the sweep keeps listing it.
If the comment's hidden lines are edited so they no longer read, or deleted,
the bot writes nothing for that issue, and the sweep says how to mend it.
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

- A message whose send failed is never sent again automatically: the sweep
  lists it as unconfirmed, and a person decides.
- A post the scan fails to greet in 30 runs in a row (server errors included),
  about 30 minutes at one scan a minute, is given up on; the daily alert names
  it.
- If the scan cannot save its state in the run that gives up on a deleted
  post, the next daily alert can name that post once more.
- If the scan cannot save its state in the run that gives up on a post that
  refuses the bot (403), and the post is locked or archived before the next
  scan, the daily alert never names it.
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
  setting the Worker cannot read stopped the scan. The daily waiting list covers it only in part: it
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
  whose issue has since been transferred to another repo gets no line either.
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
- The merge plan of a PR with more than 100 closing references is not
  updated; the merge-plan job's log says why.
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
  sent again.
- With no saved filing record, the bot searches every configured repo twice
  before filing. An issue moved between two configured repos while it
  searches can still be missed, and a second issue made. So can one in a repo
  with more than 100 issues labeled `from-discord`, when labels change during
  both searches and its place in GitHub's issue list shifts between two pages
  each time. Each search takes a second or two.
- On Workers' free plan a run may make 50 outgoing calls. A filing whose
  repos together hold more than about 1,600 `from-discord` issues updated
  since the post was made (about 1,700 with `RENAME_POSTS` at `0`) can use
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
- If the scan gives up on a post and then fails to save its own state, it
  names that post again only when it next visits it. A post archived, locked
  or deleted in that minute is not visited, so the daily alert misses it; an
  archived one can still reach the daily list of waiting posts after
  `STALE_DAYS`, within that list's limits (above).
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
- Some saved values the bot could not have written still pass its checks: a
  scan record's `greeting`, `card` or `tracked` that is text but no message
  id (such a `tracked` counts the post as filed), a `daily:named` entry that
  is text but no post id, a filing record's `by` that is not text (a card can
  then read "by true"), a `scan:since` of `Infinity` (the scan then reads no
  post while it keeps running), or a scan error time far in the future (the
  daily check then stops before its alert). A damaged `daily:named` on a day
  with no give-ups is replaced without a word. Writing back a damaged scan
  record with only its `greeting`, `buttonless` and `card` (above) drops an
  older record's `issue`, so a later filing finds that issue only by its
  hidden line.
- The daily alert's count of give-ups is not exact. A give-up saved just
  after a daily check, whose first alert the moderator channel refuses, can
  expire (after two days) before the check that would name it again. An
  alert Discord took but whose answer was lost is sent again the next day. A
  post whose greeting went out but whose record could not be saved on its
  30th try, with a queue channel set, is named as a given-up queue card
  though no card was tried. If `daily:named` cannot be read, that day's
  alert, scan warning and list of waiting posts are not sent.
- A new post's visit can use one of the record reads the scan keeps for older
  posts' cards, so the eighth older card can wait a run. Cards already in the
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
  change, and the record write after it fails too, or the job is stopped
  between the tag change and the re-archive, or Discord applies a timed-out
  tag change after the re-archive, the thread may stay open and nothing
  lists it; the run is red in Actions. One click archives it.
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
- A checklist thread whose create answer was lost is taken only when the
  bot's search finds exactly one bot thread naming the issue. It stays "not
  confirmed", with its job red, when the search finds none or several, its
  reads fail, more than 20 threads were made since, or the archived listing
  stops short. The bot never creates again for it; the sweep lists it and
  says what staff do (see Staff checklist).
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
- If a second bot thread names the same issue and is reopened and archived
  again in the seconds the bot's search reads Discord's lists, the search
  can miss it and take the other; the missed thread is then listed nowhere.
  Delete it by hand.
- A second bot thread naming the same issue that was made more than a
  minute before the lost create is outside the search, so the search can
  take the newer one alone, and the older is listed nowhere. Only a
  "Staff checklist thread" comment deleted while its thread still existed
  leaves one. Delete it by hand.
- A staff reply in the moment between the bot's re-archive landing, with
  its answer lost, and the bot's read of the thread just after can be
  archived over by the next run. The moment is one request long; another
  reply reopens the thread for good.
- If an issue is reopened and closed again while another bot run (a fix-mode
  sweep or a PR run) is opening its checklist thread for the reopen, the
  finished thread can stay open with nothing listing it: you see a finished
  issue whose thread is open, and one click archives it.
- If an issue is reopened and closed again within a minute before GitHub
  lists either event, or closed again for another reason while the bot reads
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
  its thread, and GitHub does not show the close yet, the thread is made open
  and the job is red; the issue's next event or a fix-mode sweep archives it.
- An edit to the "Staff checklist thread" comment saved in the moment the bot
  rewrites it can be lost: you see your edit gone; make it again.
- Two issues filed from one post (only after its filing record was cleared
  and the post sent again) share that post, so if one issue's "Staff
  checklist thread" comment is copied into the other, the bot can take the
  first issue's thread for the second. Never copy that comment between
  issues; delete the copy, and the issue's next event opens its own thread.
- `/bot-check` and the daily setup check cannot see the Actions settings.
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
  present. A failed read, an empty answer or a missing optional field is
  "could not check", never a pass.

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
   Messages in Threads, Manage Threads. Then check each channel's own
   permissions, since a channel can override the invite's:
   - each player forum: View Channel, Send Messages in Threads, Manage
     Threads and Read Message History (without Read Message History every
     queue card says the first message was deleted);
   - the queue channel: View Channel, Send Messages and Read Message History.
     Let the bot into it before you set `QUEUE_CHANNEL_ID`: a post scanned
     while the channel refuses the bot gets no card;
   - the moderator channel, a staff-only text channel of the server (View
     Channel denied to `@everyone`): View Channel and Send Messages. The
     bot's setup results and alerts there name its settings.
   `/bot-check` (step 10) checks all of these.
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
7. **Register the commands** (the right-click Send to GitHub and `/bot-check`)
   on the test server only:
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
10); `--forum <id>` lists a forum's posts with their tags. It only reads.
Give it its own bot, never the trial bot: a new application whose bot has
the **Message Content** intent on and is invited with View Channels and Read
Message History only. Its token goes in `TRIAL_READER_TOKEN` or in the file
`~/.discord-trial-reader/token`, outside every repo.

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

