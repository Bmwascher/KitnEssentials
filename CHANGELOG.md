# [Changelog](https://github.com/Bmwascher/KitnEssentials/blob/main/CHANGELOG.md)

## Unreleased

**Aura Debuffs** and **Aura Externals** have been rebuilt on top of the
game's own aura display system. That rebuild is the actual fix for the patch
12.1 crashes that led to the earlier advice to switch both modules off —
**if you disabled either one, turn it back on.**

### Aura Debuffs
- Rebuilt on the game's own aura display system, fixing the patch 12.1
  crashes. Turn this module back on if you had switched it off
- The movable frame's internal name changed from `KE_AuraDebuffs` to
  `KE_AuraDebuffsAnchor`. If anything else was anchored directly to the old
  name, it will no longer follow this display and will fall back to its own
  default position — re-anchor it to the new name
- The custom Blocklist can now only block spells the game itself lets addons
  identify by name. The settings card already warned this could happen; it
  is now the actual behaviour rather than a caveat

### Aura Externals
- Rebuilt on the game's own aura display system, fixing the patch 12.1
  crashes. Turn this module back on if you had switched it off
- The movable frame's internal name changed from `KE_AuraExternals` to
  `KE_AuraExternalsAnchor`. If anything else was anchored directly to the old
  name, it will no longer follow this display and will fall back to its own
  default position — re-anchor it to the new name

---

## v4.0.5

Two more patch 12.1 crash fixes, both reported from live play.

### Raid Notifications
- Fixed a flood of errors during raid pulls. The **Reset Boss** alert read the
  game's buff-change message, and patch 12.1 hides that information in raids
  and dungeons, so every buff change threw an error. It now checks before it
  reads, and the alert still rebuilds itself once combat ends, as before

### Automation
- Fixed **Hide Helptips** stopping the game with "script ran too long". The
  one-off scan that hides Blizzard tutorial buttons checked every frame in the
  game in a single pass, which with a large addon collection takes longer than
  the game allows. It now works through the list in small batches
- The same scan no longer repeats on every zone and dungeon load, and no longer
  gives up for the rest of the session if one frame refuses to be checked

---

## v4.0.4

More patch 12.1 fixes, both in code that reads buffs.

### Automation
- Fixed a flood of errors from **Hide Transforms** in dungeons and raids. The
  check meant to hold the sweep back asked the game a question patch 12.1 no
  longer answers, so it never held anything back. It now asks the supported
  way and skips the sweep while the game hides buff information

### Maintenance Tracker
- Stopped the group scan from erroring in the same places. The tracker keeps
  its last reading there and carries on counting it down, instead of reading
  as though nobody is buffed

---

## v4.0.3

Another patch 12.1 fix.

### Skinning
- Fixed a skin error on the Recruit A Friend rewards list. Patch 12.1 moved
  the month label into a wrapper, so the skin was colouring something that no
  longer accepted a colour

---

## v4.0.2

One more patch 12.1 fix, following on from 4.0.1.

### Skinning
- Fixed a flood of errors coming from skinned windows. Where the game now
  hides a window's size from addons, the border around it tried to do maths
  with that size and failed, repeatedly. The border skips that step on those
  windows now and looks exactly the same

---

## v4.0.1

Compatibility fixes for patch 12.1. Nothing new here — this release removes
the errors the patch introduced.

### Character Panel
- Fixed an error when opening the character panel. The patch removed the
  function the missing-enchant warning used to check your level, so the
  **No Enchant** warning is back
- Inspecting a player outside your group no longer risks an error from the
  gear overlays. Slots the game will not let us read are skipped instead

### Tooltips
- Fixed an error when mousing over units the game now hides information
  about. Player tooltips keep their class colors
- The rebuilt level line now steps aside on those hidden units instead of
  erroring, so they show the standard Blizzard line

### Totem Tracker
- Fixed an error when clicking **Create Macro**. The patch moved the macro
  limit the button checks against

---

## v4.0.0

The largest release so far. Skinning has been rebuilt around one engine
instead of a dozen separate modules, Edit Mode has been through four rounds of
work, and there is a new batch of quality of life tools. Several settings pages
have moved or merged, so it is worth a look through the sidebar after updating.

### Edit Mode
- **NEW:** boxes now snap to each other. Drag a frame near another and it locks
  to that frame's left, centre or right edge, and to its bottom, middle or top,
  with a line showing where the lock happened. The two directions decide
  separately, so a frame can line up horizontally with one neighbour and
  vertically with another
- **NEW:** hold **Alt** while dragging to turn snapping off for as long as you
  hold it. Works on both the grid and the new element snapping
- **NEW:** centre guides and a coarse grid, both toggleable, so you can see what
  a drag is aiming at
- **NEW:** right-click a box for its settings, add Shift to hide that box for
  the session, or Ctrl to put the frame back where it started
- **NEW:** arrow keys and the mouse wheel nudge the selected frame a pixel at a
  time, or ten with Ctrl held
- **NEW:** a category selector narrows the screen to one area at a time, so a
  busy layout stops being a wall of overlapping boxes
- The nudge tool was redesigned around a single column with the set-once
  preferences moved behind a chevron, and it is a good deal shorter than it was
- Selection boxes now cover text you have dragged off its icon. Timer and stack
  text parked outside an icon used to be text you could neither grab nor see
  highlighted
- Frames now land on exactly the position that gets saved, rather than up to
  half a pixel away from it

### Skinning
- **NEW:** a single skinning engine replaces the previous per-area modules.
  Around fifty Blizzard windows are covered — character, spellbook, talents,
  professions, auction house, bags, mail, guild, collections, weekly rewards,
  the settings panel and many more
- **NEW:** loot frame, loot roll and loot roll bar skins
- **NEW:** skins for several external addons, so a mixed UI stops looking
  assembled from parts
- **NEW:** global font control, including a slug renderer toggle for sharper
  text at small sizes
- **NEW:** UI widget skinning covers the top-of-screen widget sets, and the
  tooltip status bar is themed with everything else
- Action bars, auras, the micro menu, the raid manager, Battle.net, the Details
  backdrop and the general clean-up options are now tabs and cards inside the
  skinning pages rather than separate sidebar entries

### Quality of Life
- **NEW: Move Frames** — a temporary mover for Blizzard windows that do not
  normally remember where you put them
- **NEW: Copy Anything** — copy text out of tooltips, chat and most UI text
- **NEW: Color Picker** — RGB and alpha entry added to Blizzard's picker, so a
  colour can be typed rather than hunted for
- **NEW: Raid Control** — a compact raid utility panel
- **NEW: Group Sort** — keeps party and raid frames in a consistent order
- **NEW: Merchant Pages** — wider vendor windows with fewer pages to click
  through
- **NEW: Map Scale** — an adjustable size for the minimised world map
- **NEW: Alert Frames** — moves Blizzard's achievement and loot alerts somewhere
  less intrusive
- The Quality of Life page now gathers several small modules that used to have
  their own sidebar entries

### Dungeons and Mythic+
- **NEW: Group Finder Panel** — a reworked group finder with the information
  that matters on one screen
- **NEW: LFG Quick Create** — make a listing in a couple of clicks
- **NEW: LFG Reminder** — a nudge when you have a group listed and have stopped
  paying attention to it
- **NEW:** Dungeon Timers is now one tabbed page with season and dungeon
  dropdowns, instead of a long flat list
- Dungeon trash tracking gained aura-based detection for casts that previously
  went unnoticed

### Combat
- **NEW: Aura Headers** — control over the player buff and debuff rows, with
  both handled by one settings page
- Castbar and target castbar settings merged into a single page
- Dispel Glow and Dispel on Cursor merged into one Healer Tools page

### Damage Meter
- **NEW:** segment history is kept per character, so a key you ran yesterday is
  still there to look at

### Interface
- **NEW:** settings pages that carry a lot of options are now tabbed, which
  makes the long ones navigable
- **NEW:** a shared colours card, so the colour controls behave the same way on
  every page that has them
- **NEW:** conflict detection warns when another addon is doing the same job as
  a module you have enabled
- Dropdowns with long lists are now searchable
- The sidebar search matches on keywords as well as page titles

### Removed
- **Custom Nicknames** is hidden. The unit frame tags are gone and the settings
  page with them. Nicknames already saved still appear on Damage Meter bars,
  death notifications and healer mana, and nothing has been deleted — the
  feature can come back if the integration it depended on ever does
- **Position Controller** and the standalone **World Map** page are gone; their
  jobs are covered by Edit Mode and by Map Scale
- The soft outline font renderer has been retired. Text set to it now renders
  as a normal outline

### Under the hood
- Interface version raised for the 12.1 patch
- A great deal of secret-value hardening across combat, dungeon and unit code,
  which is the 12.0 rule set that makes the game refuse to hand addons certain
  information during encounters
- The headless test suite is now over 1900 checks

---

## v3.4.2

### Mythic+ Timer
- **Fixed:** count objectives like Pit of Saron's "Quarry Camps" (6/6) showed an absurd delta against your best time — often +19:00 or worse. The objective's clear time was already correct; the stored personal best was not. Older builds recorded that best at the moment the *first* camp was tagged (around 80 seconds), and because a best time is only ever overwritten by a faster one, a real ~21-minute completion could never replace it. Those poisoned records are now cleared the next time you run the dungeon, and the following completion sets an honest baseline
- **Fixed:** the moment a count objective completes is now recorded exactly. It was stamped from a clock that only refreshes once per second, so every 6/6 time came in up to a second early — and since that time becomes your personal best, the error was baked into every delta after it. Boss kill times carried a smaller version of the same lag through their back-dating math and now read the live clock too
- **Fixed:** reloading mid-run no longer re-times an already-completed count objective to the moment of the reload — it keeps the time it actually finished at
- Personal bests are better protected from bad data: disabling the module mid-key, or switching profiles mid-run, could previously let a different run's clear times be written over your records. In-flight run data is now also stamped per character, so one character's run can never adopt another's

### Totem Tracker
- **Fixed:** an Augmentation Evoker's dupes are totems, and only two of them ever showed no matter how many were up. The tracker mirrored Blizzard's totem frame, which loses them — it now reads the totem slots itself, so all four dupes appear, each with its own countdown
- **NEW:** the module is no longer Shaman-only. Evokers get the bar, its preview, and its position settings, all of which were previously locked out
- **NEW:** "Show Decimals Below (sec)" — under the threshold you set (default 5), the countdown switches to tenths of a second, so four staggered dupe timers stay readable at a glance
- Icon order no longer shuffles between refreshes
- The destroy-all-totems macro now covers every totem slot; its fifth click previously pointed at a button that was never created

### Profiles
- **Fixed:** switching profiles now applies everything live — modules turn on and off to match the new profile immediately, no `/reload` required. The one exception is Skinning modules, whose changes can't be unwound in place: if a switch changes one of those, you get a single reload prompt (and only then)
- **Fixed:** renaming your active profile no longer leaves the addon pointing at the old name
- **Fixed:** switching from the Profiles page back to a profile you'd just left silently did nothing until the page was reopened — it works in place now
- Profile copies, renames, and resets used to refresh every module several times over; each operation now applies exactly once
- Toggling a module off and on while its settings page is open brings its preview back immediately, instead of waiting for you to visit another section and return

### Skinned Action Bars
- **Fixed:** changing mouseover fade settings while hovering a bar now takes effect on the spot, instead of holding the old behavior until the mouse left
- **Fixed:** repeatedly disabling and re-enabling the bag-bar mouseover fade stacked up stale fade behavior behind the scenes — teardown is clean now
- All mouseover bars now share one lightweight cursor watcher instead of each running their own

### Skyriding UI
- **Fixed:** the settings preview's demo speed ("420%") could stick on the real HUD after closing settings, lingering until your first glide — it's cleared the moment the preview ends
- **Fixed:** disabling the module while its preview was showing could leave a speed updater running in the background

### Dungeon Casts
- **Fixed:** the "Show Raid Target Icon" toggle now applies to bars on the spot — the preview previously ignored the flip entirely

### World Marker Cycler
- **Fixed:** disabling the module now releases its place/clear keybinds immediately. They previously stayed bound until a `/reload` — and a disable during combat left them bound even after that combat ended

### General
- Settings changes that touch protected frames — action-bar skinning, the Skyriding UI, Recuperate's button, world-marker keybinds — made during combat now apply the moment combat ends, instead of being silently dropped
- **Fixed:** the mana percent unit-frame tag could error during combat in Midnight
- **Fixed:** the TalkingHead auto-hide kept working only until you toggled Automation off and on
- All chat output now uses the standard "KitnEssentials:" prefix (a few messages said "Kitn:")

---

## v3.4.1

### Dungeon Timers
- Better out-of-the-box defaults for the trash tracker's nameplate cooldown icons: they now anchor to the right side of the plate, at icon size 30 with a 1px gap

---

## v3.4.0

### Dungeon Timers
- **NEW:** Dungeon Trash Tracker — countdown timers for dangerous trash-pack casts, covering 8 dungeons: Pit of Saron, Skyreach, Seat of the Triumvirate, Algeth'ar Academy, Windrunner Spire, Magisters' Terrace, Maisara Caverns, and Nexus-Point Xenas. With the combat log gone in Midnight, the tracker identifies each mob and predicts its next cast purely from what nameplates expose — curated cast data matched against live observation of the pull. On by default
- Trash alerts render on the same bar and text stacks as the boss timers — same position, same styling, continuing the stack below any boss rows, so there's no separate trash anchor to manage
- Alerts are per-mob: two mobs winding up the same spell show two timers, each tied to its own caster
- **NEW:** on-nameplate cooldown icons — each enemy's upcoming casts show as countdown icons attached to its nameplate, configured on the new Nameplates settings tab (icon size, timer text size, anchor side, gap, offsets, strata) with a live preview. Works with the default nameplates and Plater; other nameplate addons best-effort
- Every tracked ability is editable from its dungeon's spell list: per-ability enable, tank/healer/DPS role filters, custom label, bar color, reveal-at lead time, decimal countdown threshold, a per-ability nameplate icon toggle, and reset-to-default
- Three sound slots per ability, each with a Test button — when the alert appears, when it expires, and when the cast actually starts. The cast-start sound names the right spell when two abilities share a timer, and stays silent rather than guess
- **NEW:** default cast-start voices — 44 hand-picked abilities across the 8 dungeons ship a fitting voice line ("AoE", "Frontal", "Feet", "Interrupt", ...) that calls out the moment the real cast begins; override or mute any of them per ability, and abilities with a sound show an "S" badge in the spell list
- Timers follow the pull as it happens: kicks, cast completions, cast-into-channel transitions, and deaths re-anchor the next prediction, and timers survive nameplate flicker instead of resetting
- Trash timers stand down during boss encounters whose adds could be mistaken for trash (Pit of Saron's Ick & Krick)
- A one-time warning popup appears if a tank in your group has Lindormi's Guidance active — the keystone NPC's assist changes enemy cast behavior and breaks the trash timers

### Damage Meter
- **Fixed:** with "Behind Bars Only" the backdrop's 1px top border was hidden under the first bar row — it now caps the bars with the same inset as the other sides
- The gap between docked meter windows is tighter (4px → 1px)

---

## v3.3.0

### Interrupt Tracker
- **NEW:** Rebuilt for 12.0.5 — the module works again. Detection now keys off the interrupt events Midnight still exposes; the old cast-correlation approach the API changes killed is gone
- Your own interrupt keeps its live per-spec cooldown bar, as before
- **NEW:** Kick Sync — teammates running KitnEssentials or a compatible interrupt addon get real, live cooldown bars: kicks broadcast to the party, and presence is announced on zone-in so synced bars are there from the first pull. Toggle: "Sync Kicks with Party Addon Users" (on by default)
- Teammates without a sync-capable addon can't expose exact cooldowns in 12.0.5 — their kicks show as temporary class-colored record bars ("> Name") that drain out and disappear; the new "Teammate Kick Duration" slider (5-30s) controls how long they linger
- Roster bars are verified-only: a bar appears once a teammate's kick data is confirmed, so the list never shows dead bars that can't update

### Character Panel
- **Fixed:** socketed gems could show as empty on your character sheet at the first login after a game patch, correcting only after a `/reload` or zone change — the panel now loads gem data during login and fills the icons in as they resolve
- **NEW:** Shift-click a gem in the Gem Socket Helper to replace every equipped socket holding that same gem in one action; your unique (meta) gem is left untouched. The slots that will change glow, and a footer shows the count while you hold Shift
- Opening the character panel and inspecting other players is a little lighter — each gear slot is now read once per refresh instead of several times

### Mythic+ Timer
- **Fixed:** count objectives like Pit of Saron's "Quarry Camps Liberated" (6/6) showed the wrong completion time — the moment the first camp was tagged rather than when the sixth finished, because the game never advances that objective's timer past its first tick. The row now records the true completion time

### Damage Meter
- **Fixed:** a boss's segment row could stay uncolored — missing its green (kill) or red (wipe) tint — when the boss was pulled while already in combat; the fight's outcome now tags reliably regardless of when the game created its combat session
- **NEW:** "Theme Color Header" toggle (Font settings) — tint the meter window's title with your KitnUI theme accent instead of white
- **NEW:** "Behind Bars Only" toggle (Backdrop settings) — wrap the backdrop around just the bar rows, leaving the header title floating above it

---

## v3.2.1

### Targeted Spells
- **Fixed:** casts shorter than 2 seconds showed their icons but no countdown — the cooldown widget's built-in 2-second minimum countdown duration is now zeroed
- **Fixed:** rebuilding an entry mid-cast (retargets, replace-by-unit) could drop its countdown or release a live entry — pooled cooldown lifecycle hardened
- Targeted Spells is now ON by default, with a one-time fixup so profiles saved under v3.2.0's default-off setting pick it up too; disabling it afterward sticks
- Default anchor recentered on the screen

### Damage Meter
- **Fixed:** cross-realm group members now resolve their spec icons (names matched without the realm suffix)
- **Fixed:** a boss pull chained immediately after the previous fight ended could steal that fight's kill/wipe tagging in segment history
- **Fixed:** death recap times in long fights could render abbreviated ("1Ks") — now always plain seconds
- The dock self-repairs after profile switch, copy, or reset operations

### Mythic+ Timer
- Clearing your splits now also clears the forces personal best
- Dungeon-name title-casing now applies only on English clients

### General
- **NEW:** `/kes help` (or any unrecognized command) lists every subcommand in chat
- Prompt dialogs no longer touch combat-protected keyboard APIs when opened in combat
- The one-time redundant-addon warning can no longer mark itself as shown without actually displaying

---

## v3.2.0

### Targeted Spells
- **NEW:** Targeted Spells module (Dungeons) — enemy casts aimed at YOU shown as mirrored icon + countdown + icon entries, driven by nameplates and fully 12.0 secret-safe. Entries stack under a repositionable anchor, compact as casts end, and cap at a configurable Max Entries
- Important spells get a pixel glow on both icons (toggleable)
- Interrupted casts linger for a second before dropping: both icons desaturate and the countdown swaps to a red outlined X
- Countdown styling: font face, size, and outline, a text color picker, a decimal precision slider (0-2), and a Text Spacing slider for the icon-to-timer gap
- Show In filters per content type — Dungeons and Delves on by default; Raids, Open World, and Arenas/Battlegrounds opt-in
- Casts longer than 60 seconds (broken multi-day NPC channels) are hidden automatically
- Off-screen casters only produce nameplates with the `nameplateShowOffscreen` CVar — a one-time prompt offers to enable it
- Edit Mode support and a live looping GUI preview

### Dungeon Casts
- Enemy casts longer than 60 seconds (broken multi-day NPC channels) no longer render

### Focus & Target Castbars
- Enemy casts longer than 60 seconds no longer render on the Target and Focus castbars

### General
- Fixed a taint chain where confirming a talent or spec change could break Blizzard's casting bar ("table cannot be accessed while tainted" errors attributed to KitnEssentials)

---

## v3.1.0

### Damage Meter
- **NEW:** Nicknames on the meter — names you've set in Custom Nicknames now display on the meter bars, hover tooltips, and the out-of-combat breakdown rows in place of real character names. Display-only: chat reports still post real names. Your own bar always shows its nickname; other players' nicknames hold through a fight once they've been seen. Toggle with "Use Nicknames" (on by default)
- **NEW:** Combat clock — an optional bracketed fight timer ("[2:41]") on window 1's header that ticks while you fight and freezes, dimmed, at the final time when combat ends. It shares the corner with the header action buttons: mousing over the header swaps the buttons in, and the clock returns when the mouse leaves. Off by default
- Segment menu overhaul — Current and Overall now sit in a fixed footer below the fight list so a long history can't scroll them away, the menu matches its window's width, and it opens pre-scrolled to the newest fights
- Bar layout — the rank number moved between the spec icon and the name (icon first, then "1. Name") and hugs the name, and the value column now reserves a fixed width so growing numbers no longer squeeze names mid-fight
- "Always Show Self" is now role-aware — damage views pin your row as a DPS or tank, healing views pin it as a healer, and the remaining views (Damage Taken, Interrupts, Dispels, ...) no longer force a zero row in
- The dock now clamps to the screen, so the meter can't be dragged or end up positioned off-screen
- **Fixed:** Interrupts and Dispels hover tooltips showed a meaningless DPS column — count views now read Amount and share % only
- **Fixed:** The segment menu's kill/wipe coloring skipped a final boss whose kill completed the key — the run's "+NN" history entry took the green instead. Both the boss row and the run row now tint

### Mythic+ Timer
- **NEW:** "Text Line" threshold mode — swaps the timer bar and its tick labels for a single collapsing timer line ("+2 Chest (26:24): 5:31") that always shows the next reward still in reach: the countdown runs teal while you're ahead, flips to a red +overshoot when a cutoff falls, drops to the next tier, and locks green or red at the finish. The final tier timer bare completion and reads "Timed"
- **NEW:** "Below Bar" threshold label position — keeps every cutoff visible: live cutoffs count down under their ticks, and passed cutoffs grey out to their absolute times as permanent pacing marks
- **NEW:** Thresholds font card — the +3/+2/+1 labels and the race line get their own font face, size, and outline, independent of the global HUD font
- **NEW:** "Live Sub-Seconds" timer option (replaces the old milliseconds toggle) — the running timer ticks a smooth tenths-of-a-second digit ten times per second, driven by a precise clock so it never drifts or jitters. The frozen completion time always shows full milliseconds regardless of the toggle
- **NEW:** Show Forces Bar toggle — hide the bar and the forces text becomes a stacked HUD row for an all-text look; plus a new forces format that appends an "Enemy Forces" label to the percent
- **NEW:** Row Spacing slider — tune the vertical gap between HUD rows and boss rows
- **NEW:** Optional dungeon name on the key row, which is restyled to "+12 Kings Rest" with dot-separated affixes ("Fortified · Peril · Tyrannical")
- Completion colors refreshed: the timer lands green on a timed finish (was gold), completed forces recolor the percent text instead of the bar fill, PB targets read grey-white, and the key row reads white; boss clear times drop their brackets
- Threshold labels in the Above and Below positions right-align to their tick marks, so labels near the end of the bar no longer collide or clip the frame edge
- The PB readout beside the timer sits in a fixed slot against the timer's reserved width, so it no longer shifts as the timer digits change
- Left-edge boss-row times (Time Position "Start") read time-first with the PB delta beside them, mirroring the right-edge order
- The deaths hover log backdrop now matches the Damage Meter panels (solid dark fill, black border)
- **Fixed:** The enemy overlay showed the raw progress fraction as the forces percent ("0.02%" instead of "2.47%") on nameplates and the tooltip Count line — both now display the game's pre-formatted percent
- **Fixed:** Walking out of a live key and re-entering could blank the timer HUD and permanently lose the run's boss splits and death log — run state now survives the walk-out and restores on re-entry
- Config page polish: bar color controls grey out while their bar is hidden, Count Brackets enables only for count-bearing formats, and the tooltip toggle now leads the Overlay tab

### Keystone Helper
- **NEW:** Keystone Helper module — three Mythic+ keystone QoL reminders in one Dungeon & Party Utilities page
- **NEW:** Instance Reset Announcer — posts a configurable message to party/raid chat whenever you reset instances (the announcer that disappeared with the old WarpDeplete Forces module, back as a standalone feature)
- **NEW:** Reroll Key Reminder — after you time a key at or above your own keystone's level, a keystone icon pops up glowing "REROLL KEY?" for 5 minutes and flips to "NEW KEY" once you've rerolled
- **NEW:** "Your Key?" Reminder — walking into a Mythic 0 dungeon that matches your owned keystone shows a "Your Key?" prompt so you remember to slot it, and clears the moment the key goes in
- Both reminders share one appearance and screen position (icon size, font with soft-outline support, text colors), each with its own glow color; a key line under the icon shows your keystone as "(dungeon icon) Dungeon Name - level"

### GUI
- The combined Macro Builders page split into standalone pages — Power Infusion Macro now lives under Class Utilities ("Priest: PI Macro") and Focus Marker under Dungeon & Party Utilities. Settings carry over unchanged

---

## v3.0.3

### Damage Meter
- **Fixed:** "Always Show Self" no longer pins your row into the Deaths view — your death could be forced out of chronological order. The Deaths log now always reads in time order
- **Fixed:** Player names now display without their realm suffix, so cross-realm and raid bars are no longer cluttered with "-Realm"
- **Fixed:** Spec icons now resolve for pug and cross-realm players whose spec the game client doesn't report directly (looked up via LibSpecialization), and fall back to the class icon when the spec still can't be determined instead of showing nothing

### Player Absorbs
- **NEW:** Player Absorbs module — an on-screen readout of your own damage-absorb shield (`UnitGetTotalAbsorbs`) and heal-absorb (`UnitGetTotalHealAbsorbs`), shown as text with optional spell icons and anchored to your player frame by default (auto-detects ElvUI and other supported unit frames, falls back to the Blizzard frame) or repositioned anywhere via `/kes edit`
- **NEW:** Two number modes — abbreviated (1.2M-style) that fades a configurable duration after the last change, or full numbers that stay while a shield is up and clear instantly at zero
- **NEW:** Layout options — grow the shield and heal-absorb readouts down, up, side-by-side (left/right), or split to opposite flanks with an adjustable gap; plus icon side, icon/row spacing, and auto-centering when only one is active
- **NEW:** Themable — LSM font with soft-outline support, separate shield and heal-absorb colors, icon size, and fade duration, all on a dedicated config page
- Built secret-value-safe for 12.0 — absorb amounts are Secret Values in 12.0, so the readout formats them only through tainted-safe paths (`AbbreviateNumbers` / `C_StringUtil`) with no tainting arithmetic, and registers its unit events filtered to the player so no other unit's data is ever read

---

## v3.0.2

### Damage Meter
- **NEW:** Detects when Details! is running alongside the KitnEssentials meter and posts a one-time chat reminder that you only need one. While the KitnEssentials meter is active it also turns off the now-redundant KitnEssentials "Details Backdrop" skin automatically

### Mythic+ Timer
- **NEW:** Detects when the external WarpDeplete addon is running alongside the Mythic+ Timer and posts a one-time chat reminder that you only need one

---

## v3.0.1

### Damage Meter
- **Fixed:** The default 3-window layout shipped squished into half its intended width on fresh installs. New installs now render at full width, and any profile already created on v3.0.0 is corrected automatically on update

---

## v3.0.0

### Damage Meter
- **NEW:** Damage Meter module — a standalone damage/healing meter built entirely on the 12.0 `C_DamageMeter` API (no external meter addon required). Replaces Blizzard's built-in meter and renders into a multi-window dock wrapped by one shared, auto-sizing backdrop
- **NEW:** Proportional multi-window dock — arrange windows into columns and stacked rows, resize panes by dragging the gaps, and rearrange them by dragging boxes on a live layout map in the GUI
- **NEW:** Per-content auto-swap — each window stores a separate layout per context (Default / Dungeon / Mythic+ / Raid / Arena / Battleground / Scenario) and switches automatically as you change content, inheriting from Default until overridden
- **NEW:** Meter types — Damage Done, Healing Done, Damage Taken, Enemy Damage Taken, Avoidable Damage Taken, Deaths, Interrupts, and Dispels, switchable per window via a right-click view selector or the GUI
- **NEW:** Out-of-combat detail views — click a bar for a per-spell breakdown, a death-recap timeline (`C_DeathRecap`), and a Targets list of the top enemies a player hit; plus a hover quick-peek tooltip
- **NEW:** Segment history — pick Current, Overall, or a recent fight from a per-window picker; the Deaths view shows a M:SS death time
- **NEW:** Report to chat — a header button (and `/kes dm report`) posts a window's totals, DPS, and share % to a chosen channel (Say / Party / Raid / Instance / Guild / Officer)
- **NEW:** Class-colored bars with icon, name, and total | per-second; configurable visible-bar count, Always-Show-Self, realm-name display, decimals, and rank numbers
- Built secret-value-safe for 12.0 — combat amounts feed native status-bar interpolation and `AbbreviateNumbers` with no tainting arithmetic, and the meter ticks only in combat (fully detaches when idle)

### Mythic+ Timer
- **NEW:** Mythic+ Timer module — a self-contained keystone timer HUD (no external WarpDeplete needed). Count-up timer with +3/+2/+1 threshold marks and remaining-time labels, aggregate forces bar, per-boss objective list with clear times and personal-best deltas, and an authoritative deaths line with a class-colored, timestamped hover log
- **NEW:** Personal bests — stores your best time per dungeon and key level, shows live per-boss and overall splits during the run, and previews PB targets during the starting countdown
- **NEW:** Challenger's Peril aware — recomputes the +3/+2/+1 cutoffs when the affix is active
- **NEW:** Enemy overlay — optional per-mob forces count on enemy tooltips and a per-pull % on nameplates (folds in and replaces the standalone WarpDeplete+ overlay; decoupled from the external addon)
- **NEW:** Quality of life — auto-inserts your keystone at the font of power, hides Blizzard's objective tracker during a key (combat-safe), and can post each boss split time to party chat
- **NEW:** Fully themable — LSM font and bar texture, configurable colors with accent/custom toggles, six-tab config page (`/kes mt`), `/kes edit` repositioning, and a Rookery +12 live preview
- Built secret-value-safe for 12.0 — aggregate forces and death count read non-secret APIs with plain math; enemy GUIDs and per-unit tooltip forces are guarded; the timer ticks only during a run and fully detaches when idle

### Advanced Debuffs
- **NEW:** Advanced Debuffs module — bar-based dispellable-debuff display with built-in cooldown swipe, native countdown text, per-dispel-type border color, and a per-type atlas overlay (Magic / Curse / Poison / Disease / Enrage / Bleed). Subsumes the older Boss Debuffs module; existing settings migrate automatically on first load
- **NEW:** Encounter-aura support — works on boss debuffs that ship as Secret Values in 12.0+. Built taint-safely via `C_UnitAuras.GetAuraDispelTypeColor` curves + `LuaDurationObject`, so dispel type and countdown render correctly even when raw aura fields are masked
- **NEW:** Border Color Mode toggle — pick between dispel-type-driven border (Magic = blue, Curse = purple, Poison = green, Disease = orange, etc.) or a fixed user color
- **NEW:** Filtering — Show My Debuffs Only (PLAYER filter) and per-type include/exclude. Blocklist by spell ID for unhelpful one-offs (e.g. Curse-of-Tongues spam)
- **NEW:** Element Positions card — adjust timer text and stack count placement independently of the icon
- Icon size slider headroom raised so larger icon configurations behave correctly at the upper end of the range

### External and Defensive Buffs
- **NEW:** External and Defensive Buffs module — displays external defensive cooldowns cast onto you (Pain Suppression, Ironbark, Blessing of Sacrifice, etc.) with built-in cooldown swipe, native countdown text, configurable glow per cast, and an optional Test sound when an external lands. Curated list of common externals + an Include Defensives toggle for your own ones
- **NEW:** BigWigs glow integration — when BigWigs flags an incoming raid hit, the matching defensive aura on your bar lights up
- **NEW:** Sound Test button — auditions the currently-selected Test sound from the GUI without waiting for a real cast

### Character Panel
- **NEW:** Character Panel module — replaces and expands the older Missing Enchants/Gems module. Adds per-slot item level, enchant labels, gem icons, item-track letters (M/H/C/V/A), an interactive Gem Socket Helper, a decimal character-pane item level, race text + faction icon on the name line, and an inspect-frame overlay that mirrors all of it onto other players. Module renamed from `MissingEnchants` to `CharacterPanel`; the saved DB section was renamed too — settings you previously customized under the old key will fall back to defaults
- **NEW:** Per-slot item level on every equipped slot (player and inspect). On the player's own panel the value reads via `ItemLocation`, so heirlooms and level-scaled gear match the tooltip exactly (no more templated readings like 371 on an item that's actually 71)
- **NEW:** Decimal item level — the character-stats item level shows two decimals (e.g. `642.38`). Optional, lives on the Display card
- **NEW:** Per-slot enchant labels — short stat nicknames (e.g. `Crit%+`, `Mast`, `Speed`). Crafted enchants strip their trailing quality-atlas markup. Missing enchants render as a single red "No Enchant" line on the same slot anchor
- **NEW:** Missing-gem cue — empty gem sockets render as a red socket icon inline with the gem strip, replacing the older "No Gem" text line so the cue sits naturally beside any filled gems
- **NEW:** Item-track indicators — single-letter overlays on each slot for the gear track (`M` Myth / `H` Hero / `C` Champion / `V` Veteran / `A` Adventurer)
- **NEW:** Gem Socket Helper (player only) — hovering an empty socket pops a list of compatible gems from your bags; clicking a gem sockets it directly. Multi-socketed items now target the correct socket position (the prior implementation could send the click to the wrong socket on items with mixed filled/empty rows)
- **NEW:** Inspect frame support — same-zone inspects render the same overlays on Blizzard's Inspect frame, including a 2-decimal **inspect** average item level (Blizzard's Inspect frame shows none natively). The render is bound to inspect-open and driven by a per-item async load queue, so gemmed sockets resolve without you having to hover the slot, and idle inspect frames don't accumulate background work
- **NEW:** Auto-disable for `BetterCharacterPanel` — if BCP is loaded on enable, KitnEssentials disables it for the current character and chat-prompts a `/reload`. The two would double-render every overlay otherwise; BCP's feature set is now covered here and then some
- All overlays are on by default on a fresh install with tuned font sizes, so the panel works without opening the GUI first

### Totem Tracker
- **NEW:** Totem Tracker (Shaman-only) — bar-based active-totem display with per-totem name, remaining-time text, and a per-button destroy button. Configurable row height, button spacing, and timer-text visibility; EditMode-integrated for repositioning; preview hooks into the standard `PREVIEW_MODULES` flow so the GUI preview button works like the other tracker modules. Silent no-op for non-Shaman characters; combat-safe — destroy buttons hide in lockdown rather than erroring

### WindTools Game Bar
- **NEW:** WindTools Game Bar hider — opt-in toggle to hide WindTools' Game Bar without unloading WindTools

### Focus & Target Castbar
- **Fixed:** Kick-ready highlight uses the cast-type (interruptable) color instead of falling back to a generic state
- **Fixed:** Mid-cast `notInterruptible` flips (boss / immunity windows) now correctly re-route through the kick indicator so the bar reflects the new state
- Kick cooldown indicator now tracks the interrupt's actual cooldown via `SPELL_UPDATE_COOLDOWN` with a lightweight 10Hz finishing ticker — eliminates per-frame polling and stays accurate across spec/talent changes
- Bar color refreshes at the end of `ApplySettings` so theme/colour edits in the GUI take effect immediately
- **NEW:** Important-spell glow (Focus) — the focus castbar can glow on casts Blizzard flags as important (lethal-if-not-interrupted). Pick the glow style (Pixel or Autocast) and tune color, line/particle count, frequency, length, thickness, scale, and border. Off by default
- **NEW:** Out-of-range dimming (Focus) — optionally fade the focus castbar when your interrupt is out of range of the focus, so a glance tells you whether you can kick. Range is measured against your spec's real interrupt spell. Off by default
- **NEW:** Ignore Friendly Focus — optionally hide the focus castbar entirely for a focus you can't attack

### Death Notifications
- **NEW:** Focus-death voice reminder — when your focus dies while you're in combat, an optional Text-to-Speech line plays (default "Focus Dead") so you know to retarget without watching the frame. Off by default; toggle and edit the spoken text on the Death Notifications page

### WarpDeplete+
- **Fixed:** A Hunter's Feign Death is no longer counted as a death by the death tracker (your own or a party member's)
- The standalone WarpDeplete+ overlay module has been retired; its forces tracking and enemy-overlay features are now built into the Mythic+ Timer module above

### Raid Notifications
- **Fixed:** "BONUS ROLLS MISSING" no longer reappears after a mid-key `/reload` inside an active keystone, and the Reset Boss reminder no longer briefly fires during combat

### Position Controller
- **NEW:** SkironCooldownManager support — Player and Target frames auto-anchor beside whichever cooldown manager is loaded (SkironCooldownManager or Ayije_CDM), no manual configuration needed
- **NEW:** ElvUI mover write-through — positions are written through ElvUI's mover system instead of via raw `SetPoint`, so placements survive `/reload` and zone changes without ElvUI reverting them
- Position Controller GUI rebuilt: Player/Target cards collapsed to Enable + X/Y offset (active CDM resolves the parent), Focus/Pet keep the full anchor picker, Ignore Healer Specs lifted into the master card

### Spell Alerts
- **NEW:** Per-spec toggles for every class — opt individual specs in or out of the proc-flash overlay via a 4-column class/spec grid. Keyed by global spec ID so selections survive talent/class swaps
- Opacity slider moved above the spec grid for quicker access

### Pixel-Perfect Rendering
- **Fixed:** X/Y offset sliders now move every positioned frame by exactly one physical pixel per click at perfect UI scale (1440p / 1080p / 720p). The prior snap math used the wrong divisor, producing a buggy grid where some integer slider clicks visibly didn't move the frame
- Pixel snapping is now always-on for every frame positioned through the KE framework — the per-module "Snap to Pixel Grid" toggle has been removed from every position card. At perfect UI scale the snap is a no-op for integer offsets; off-grid frames (e.g. anchored to ElvUI panels at fractional positions) are corrected automatically
- 1px icon and frame borders now stay crisp through UI-scale changes — the border textures resnap when the screen size or scale changes

### Healer Utilities
- **NEW:** Healer Utilities — a dedicated sidebar section gathering healer-specific tools. Healer Mana moved here, and Dispel on Cursor is now reachable from this section too (same settings as the Cursor Effects page)

### Innervate Tracker
- **NEW:** Innervate Tracker — shows an icon + countdown while Innervate is active on you, with a configurable label ("FREE" by default), glow, and alert sound. Because Innervate is hidden from the aura API in 12.0, it's detected by watching your spec's heal spells drop to zero mana cost. Healer-capable classes only (Druid, Paladin, Priest, Shaman, Monk, Evoker); position via Edit Mode

### Maintenance Tracker
- **NEW:** Maintenance Tracker — one icon per key maintenance buff showing how many group members currently have it and the lowest remaining duration across them, color-coded by urgency (green → amber → red as it runs low). Spec-aware: Atonement (Discipline Priest), Renewing + Enveloping Mist (Mistweaver Monk), Rejuvenation incl. Germination (Restoration Druid), Riptide (Restoration Shaman), Echo (Preservation Evoker). Multi-spell specs render side-by-side with a configurable growth direction. Adjustable urgency thresholds/colors, font, and count size; editable position with a GUI preview

### Dispel Glow
- **NEW:** Dispel Glow — highlights ElvUI party/raid/tank frames with a colored border + top fade whenever a dispellable debuff is present, including private auras (dungeon-mechanic debuffs the normal aura API can't see). Border color follows your dispel-type palette; border thickness is adjustable. Requires ElvUI
- The Dispel Type Colors palette is now shared between Advanced Debuffs and Dispel Glow — edit it from either page and both update

### Healer Mana
- **Fixed:** Delve companion NPCs (Valeera Sanguinar and similar) were being tracked as healers — they report role `HEALER` but have a max=1 sentinel mana pool, so the bar rendered at a meaningless percent. Non-player units now must have a real mana pool (max ≥ 100) to be picked up; player healers pass through across disconnects, and legitimate mana-using NPC followers (e.g. Cylestia in follower dungeons) still track normally
- **Fixed:** Mana percentage failed to render inside delves. Blizzard restricts party-member power queries there, so `UnitPowerPercent` comes back as a secret token; the percent text is now forwarded straight to `SetFormattedText` (a display call, not arithmetic — no taint propagates back into addon Lua) so the underlying value renders correctly

### Dungeon Timers
- Text-mode entries now show the spell icon inline as a prefix on the label
- Phase-bar audio: cleaned up sound-cue triggering on phase transitions so cues don't stack on rapid threshold crossings

### Font Outlines
- **NEW:** Slug and Outline Slug outline picks added to every module's Font Outline dropdown. Both engage Blizzard's vector glyph renderer (mathematically pixel-stable text), eliminating sub-pixel rasterization variance that bitmap rendering otherwise produces. Outline Slug is the recommended pick if you want crisp text at every screen position
- Soft outline rendering improved — text rendered with the "Soft" pick now uses the vector glyph renderer internally on both the main FontString and all 8 shadow copies, reducing the halo-edge variance that was visible at certain frame X positions
- Internal: outline options consolidated into a single `KE:GetFontOutlineOptions` factory so future outline modes only need one edit

### Automation
- **NEW:** Auto-accept resurrection — automatically accepts incoming resurrection requests when you're out of combat. Sender guard hardened to ignore requests with no resurrector identity
- Auction House Filter folded into the Automation tab — its three toggles (expansion filter, search auto-focus, craft orders filter) now live alongside the other auto-accept / auto-turn-in / auto-resurrection options

### Ready Check Consumables
- Smarter flask picker — when you have multiple flask buffs active, ready-check icons now resolve to the highest-tier one rather than the first match

### Focus Marker
- **NEW:** No Overwrite option — uses the Patch 12.0.7 `~` marker syntax in the generated macro (`/tm ~8`) so your marker only lands on an unmarked target instead of overwriting another player's icon. On by default; the macro's anti-toggle clear line is skipped in this mode so it can't wipe an existing marker first

### Tags
- **NEW:** `kes:mana:percent` tag — shows the unit's mana % below 100, hidden at full mana

### Sidebar
- Section labels relabelled for clarity: "Combat Utilities", "General Utilities", "Dungeon & Party Utilities". Module entries renamed too: Aura Debuffs → "Advanced Debuffs", Aura Externals → "External and Defensive Buffs"
- Auction House Filter sidebar entry removed (its toggles now live in the Automation tab)

### System Optimization
- Recommended graphics preset reworked to a "high world, low raid" profile — the open world now stays at high quality and only **raids & battlegrounds** drop to performance settings, instead of lowering quality everywhere
- **NEW:** Raid & BG Graphics card — a separate recommended profile (shadows, SSAO, particles, depth/compute effects, view distance, etc.) that applies only inside raids and battlegrounds via Blizzard's separate-raid-settings toggle
- **NEW:** CVars card — extra recommended tweaks: camera FOV (90°), max camera zoom, nameplate stacking & overlap, minimum world-text size, and disabling auto-push-spells-to-actionbar
- **NEW:** Expanded FPS limits (max FPS, loading-screen FPS cap, higher background FPS) and cosmetic toggles (screen-flash override, camera & UI shake)
- View Distance & Detail rows merged into the Base Graphics Quality card; Spell Queue Window (180 ms) retained
- If you'd optimized previously, the panel will flag the new recommendations — click *Optimize All* again to adopt them (your original values stay restorable via Revert)

### Recuperate
- Reduced idle CPU — dropped a redundant `[dead]` clause from the button's secure visibility driver, which was being re-evaluated on every player health change; the button still hides while you're dead via its existing health-based alpha

### Shared Media
- Added the "Details! Slash" status bar texture and a "Gun1" alert sound to the shared media options (selectable anywhere KitnEssentials offers a bar texture or sound dropdown)

### Removed
- Removed the Bloodlust Tracker module
- Removed the Hide ActionBars module

---

## v2.0.1

### Automation
- **NEW:** Auto Voidcores: Gold — automatically accepts and completes the weekly *Nebulous Voidcores: Gold* quest from Decimus end-to-end, even when general auto-accept/turn-in is off. Honors the same Pause-modifier (Shift/Ctrl/Alt/None) as the other quest automation toggles

### Ready Check Consumables
- Added Impossible Royal Roast / Royal Roast (`1294727`) to the food buff detection table — the non-Hearty variants were missing, so eating them registered as no-food on the ready-check icons

### Home Page
- Active Profile row moved into the top greeting card alongside Version/Author/Credit; the standalone Profile card and its redundant Character/Realm line have been removed. Slimmer top-of-page layout without losing the profile-name display

---

## v2.0.0

### Dungeon Timers
- **NEW:** Curated dungeon ability timer system — every mechanic across all 8 supported dungeons is hand-tuned with deliberate cast and channel durations, displayed as a bar or text alert with a clear role tag (tank / heal / mechanic / kick / move / other). No per-trigger upkeep, no import/export workflow — install and play
- **NEW:** Phase tracker — countdown text for HP%-driven boss transitions (Gemellus 50%, Crawth 75% / 45%, Commander Kroluk 66% / 33%). Shows lead-in countdown ("80% → 75%") in the seconds before a phase swap, then flashes "Phase Transitioned" briefly when the threshold is crossed. Built fully 12.0-secret-value-safe — drives bar value, text, and alpha via AllowedWhenTainted APIs (StatusBar:SetValue, Region:SetAlpha, AbbreviateNumbers) without ever extracting the hostile-unit HP integer
- **NEW:** Role-based filtering — every curated spell is tagged with which player role(s) should see it (tank / heal / mechanic / kick / move / other). Configurable via per-spell role overrides in the dungeon page. Driven by `LibSpecialization` for passive spec/role detection; degrades to always-DAMAGER if the library is absent
- **NEW:** Boss absorb shield bars — for encounters with curated `shieldBar` entries (e.g. Vordaza Necrotic Convergence), spawns a dedicated bar that tracks the absorb's remaining percentage. Scales the max value by Mythic+ keystone level using the standard EXDB level multiplier table
- **NEW:** Post-cast bars (`postCastBar`) — for abilities where the dangerous window is *after* the cast (e.g. ground effects, dispatched adds), the bar continues for a configurable duration after the cast finishes instead of vanishing on completion
- **NEW:** Spawn-on-message bars — for abilities that BigWigs reports as a Message rather than a Timer (no native countdown), the curated entry can opt into spawning on the message fire instead, with a curator-supplied duration
- **NEW:** Phantom follow-up bars (`phantomFollowupOf`) — for abilities where one cast triggers a delayed secondary effect, a second bar spawns automatically when the parent's cast resolves
- **NEW:** Per-spell display overrides — switch any spell between bar and text mode, adjust show-at-seconds, time offset, decimal threshold, color, on-show / on-hide sound, custom display label, all independently from the module-wide defaults
- **NEW:** Curated `displayText` preset chips — 15 hand-picked label/color combinations (ADD, AMP, AOE, CLEAR, DANCE, DODGE, FEET, FRONTAL, HIDE, MOVE, PULL, SOAK, SPREAD, STACK, TANK HIT) plus a hidden VULN preset, all selectable from a 3x5 chip grid in the spell detail pane. Color-only aliases (`ADDS`, `AIM BEAMS`, `BEAM`, etc.) inherit color from the canonical preset without overwriting the curator's text
- **NEW:** Reset Overrides card — per-dungeon Reset rows (with dungeon icon + red-text button) plus a "Reset All Dungeons" master that wipes every user-customized spell/phase override back to curated defaults in one click
- **NEW:** Boss death "hold" behavior — when a boss is killed mid-cast, in-progress bars are held at their current value rather than abruptly snapped to zero. Uses BigWigs's `originalEnd` vs current time to distinguish natural expiry from premature death
- Bundled sound cues — 33 mechanic-matched voice cues ("Drop", "Spread", "Stack", "Intermission", etc.) pre-assigned to every curated spell and phase; per-spell + per-phase dropdowns offer the full LibSharedMedia library plus a master mute toggle and sound channel dropdown on the General page
- The pre-2.0 BigWigs-trigger-based editor has been retired; its config is silently cleaned up on first load. Module config now lives at `KitnEssentialsDB.profile.DungeonTimers`

### Soft Outline
- **Fixed:** Bars / overlays using SOFTOUTLINE FontStrings could leave "ghost shadow" silhouettes visible on hidden elements. The `SetTextColor` hook now checks both the text-color alpha *and* the frame alpha when deciding whether to show or hide the 8 shadow FontStrings — previously a 3-argument `SetTextColor(r,g,b)` with no alpha would un-hide shadows even on alpha-zero frames

### Ready Check Consumables
- **Fixed:** Distinct food buff IDs for the recently-deduplicated Blooming Feast (1232087), Hearty Blooming Feast (1232078), and Champion's Bento (1284617). Blizzard finally split the buff IDs across these consumables so the food detection now correctly identifies which feast each player ate
- Fixed a "Blooing" typo in the Blooming Feast comment block

### Internals
- Drag handlers on the main GUI frame and edit-mode handles now use the lambda-wrapped form (`function(d) d:StartMoving(true) end`) with the 12.0 `alwaysStartFromMouse=true` argument so drag-initiation tracks the mouse from the click point instead of snapping to the frame's anchor
- Type annotations: `KE:ResolveColor` and `KE:GetAccentColor` now use separate `---@return number r / g / b / a` lines (multi-return was being parsed as a single value before)
- `KE.LDS` (LibDualSpec) is now typed as nullable to reflect `LibStub(..., true)` behavior

---

## v1.22.0

### Raid Notifications
- **NEW:** Bonus Rolls Missing — shows "BONUS ROLLS MISSING" while inside one of the 8 seasonal Mythic+ dungeons or 3 seasonal raids and your Nebulous Voidcore is below the seasonal cap. Hides automatically during combat, when an M+ keystone activates, when you cap, and when you leave the seasonal zones. Per-alert toggle in the GUI (default on); skips characters who haven't yet engaged with the currency system

### Class Status Texts
- **NEW:** Wrong Pet warning — Demonology Warlock only. Shows "WRONG PET" in orange when a pet other than the Felguard is summoned (Imp, Voidwalker, Felhunter, Sayaad). Priority above the existing Dead and Passive warnings — fixing the wrong pet supersedes reviving it. Configurable text and color in the Pet Status sub-tab
- No Movement Alert: Warlock Demonic Circle: Teleport label changed from "CIRCLE" to "PORT" for clarity (the alert fires on the teleport, not the circle placement)

### Automation
- **NEW:** Auto-Confirm Loot Roll Popup — auto-dismisses the Need / Greed / Disenchant confirmation dialog so a single Roll click commits the action
- **NEW:** Housing Item Auto-Roll — auto-passes (or auto-needs, configurable) on housing items detected via item class. Dismisses any resulting confirm popup automatically
- **NEW:** Confirm Bonus Rolls — adds a confirmation dialog before the M+ end-of-dungeon and raid bonus roll commits, preventing accidental clicks. The popup shows your active loot spec inline (icon + class-colored name) so you can verify before committing

### Ready Check Consumables
- **NEW:** Warlock Soulstone slot pulses a yellow pixel-glow when the spell is off cooldown but no group member currently has a Soulstone — a visible "go cast it" nudge. Stops once Soulstone is applied (slot enters cooldown / ready state)
- **NEW:** Warlock Healthstone slot is now clickable — left-click out of combat casts Create Soulwell (spell ID `29893`). Non-Warlocks see no clickable behavior

### Time Spiral Tracker
- Countdown text always shows 1 decimal place. Previously switched to whole-second mode under 10 seconds, which produced awkward "10.5 → 10" jumps during the first half-second of the 10.5s buff

---

## v1.21.0

### Ready Check Consumables
- **NEW:** Warlock Soulstone slot now auto-targets a healer. Click priority: your current target (if friendly) > the healer who currently has your Soulstone aura > the first living healer in your group > mouseover/target/self fallback chain
- Once you Soulstone a specific healer, the slot remembers them and re-targets them on every subsequent click — even after the buff is consumed on death — until they leave the group or you manually pick someone else
- To switch healers manually: click on the new healer to make them your target, then click the Soulstone icon. The cast goes to your manual pick and the sticky cache updates so the new healer auto-receives every cast going forward

### Focus Castbar
- **NEW:** Raid Marker — shows the focus target's raid marker icon (Skull, Cross, etc.) next to the cast bar when they're casting. Configurable anchor (Left/Center/Right), size, and X/Y offsets in a new "Raid Marker" card. Per-card "Show Raid Marker" toggle (default on) — disables the marker without affecting the rest of the focus bar

### Raid Notifications
- **NEW:** Bench Alert — shows "BENCHED" with a hearthstone icon when sitting in subgroup 7 or 8 of a Mythic raid (the conventional bench groups). Per-alert toggle in the GUI (default on); hides automatically when you're moved off the bench, the raid leader switches difficulty off Mythic, you leave the raid group, or you zone out of the instance

### Healer Mana Tracker
- **NEW:** OFFLINE display state — when the party healer disconnects, the row stays visible with greyed text reading "OFFLINE" and a dimmed icon, instead of vanishing entirely. Reconnect restores the live mana % automatically on the next 1-second tick
- Cross-realm Discipline vs Holy priest icons now resolve correctly. Previously defaulted to Disc icon for any cross-realm priest healer because the legacy inspect path didn't return spec data without a manual inspect

### Castbar (Focus / Target)
- "Interrupted by `<name>`" text now resolves correctly for warlock pet kicks (Felhunter Spell Lock, Felguard Axe Toss) and any non-player interrupter. Previously degraded to bare "Interrupted" with no name attribution. Works in non-restricted contexts (open world / quest mobs); in M+ / raids / rated PvP, Blizzard secures the interrupter GUID server-side and the bar falls back to "Interrupted"

### Cursor Circle
- **Fixed:** GCD ring color no longer briefly flashes uncolored when the texture refreshes — the texture and color are now applied in a single call (matches the 12.0 `SetSwipeTexture` API signature)

### Hide Bars
- **Fixed:** disabling Hide Bars no longer wipes your saved keybind. Toggle off → toggle on → your hotkey still works without re-entering it in the GUI

### Dragon Riding
- **Fixed:** toggling Dragon Riding off then on used to stack a duplicate set of frame hooks each cycle. After 3 toggles, every mount-up was running speed/vigor/secondWind work 4× per change with 4 concurrent timers competing. Hooks now install exactly once per session

### Missing Enchants
- **Fixed:** equipment-change updates no longer die after toggling Missing Enchants off then on. The slot warning text now refreshes on gear swap as expected without needing a `/reload`

### Dispel Cursor
- **Fixed:** toggling Dispel Cursor off then on no longer leaves the cursor text frame visible-but-frozen with no cursor-follow or cooldown numbers. Full functionality now restores on re-enable without a `/reload`

### Automation
- **Fixed:** the master Enable toggle now actually disables every behavior. Previously, flipping it off only unsubscribed from CVAR_UPDATE while every other behavior (hide toasts, hide zone text, auto-sell, auto-repair, auto-quest, auto-decline duels, skip cinematics, etc.) silently kept firing until `/reload`
- Auto Role Check and Auto Fill DELETE sub-toggles now respect runtime changes — flipping them off mid-session immediately suppresses the behavior, where previously they were only checked at install time

### Position Controller
- Disabling the master "Enable Position Controller" toggle now prompts for a reload. Behavior is suppressed immediately on disable, but the underlying frame hooks remain installed until `/reload` (re-enabling does not prompt — it's a clean path)

### Hunter's Mark Warning
- Edit Mode label renamed from "Hunter's Mark" to "Hunter's Mark Warning" — clearer when browsing modules in the Edit Mode panel

### Dungeon Timers
- **Restored:** Quick Preset card on every trigger's Display tab — pick from 14 color-coded labels (ADD, AMP, AOE, DODGE, FEET, FRONTAL, HIDE, KICK, PULL, SOAK, SPREAD, STACK, TANK HIT) and the dropdown stamps a consistent label and color onto the trigger so styling stays uniform across dungeons. Detected automatically on render — if the trigger already matches a preset, the dropdown shows it; otherwise it shows "None (Custom)" and edits stay non-destructive. (Lost during the v1.19.0 GUI layout port; restored from the original v1.12.1 implementation.)
- **NEW:** Hover-tooltip FAQ on the Message Filter input and Match dropdown — explains the three Match modes (Contains, Exact Match, Pattern) with examples, plus the recipe for filtering out BigWigs `<Cast: ...>` in-progress wrappers when a spell has both a countdown bar and a cast-duration bar that share the same Spell ID

### Interrupt Tracker
- Replaced the inspect-throttle / queue plumbing (~75 lines) with passive spec discovery via addon comms. Party member specs now populate automatically without an explicit inspect, and there's no inspect-API contention with other addons (Details, inspect tools, etc.)

### Libraries
- **NEW:** Embedded LibSpecialization (BigWigs upstream) for passive group spec/role tracking via addon comms. Powers the Healer Mana Tracker priest icon fix and the Interrupt Tracker spec lookup

---

## v1.20.0

### Dungeon Timers
- **NEW:** Spell browser updates results live as you type — no more clicking through pages to find what you typed
- **NEW:** "No Timer Selected" placeholder card now shown on every sub-tab (Trigger / Display / Load / Actions) when nothing is selected, instead of a blank panel
- General page dungeon list now sorted alphabetically to match the sidebar order
- Master Enable toggle now prompts for a reload when toggled and grays out all sections + sub-tab buttons immediately so you don't accidentally edit while the module is off
- Sub-tab clicks (Trigger / Display / Load / Actions) are now properly disabled when the module is off — was just visually grayed before
- Trigger Enable toggle now applies immediately (no need to click another timer to see the preview update)
- Switching trigger types in the dropdown no longer flashes a stale bar before the new type renders
- Disabled triggers in the timer list are now visibly grayed instead of looking the same as enabled ones
- Trigger note grammar tightened — "Trigger" tab said "Click +" instead of "Click New" with an inconsistent comma vs. the other three tabs
- Switching between dungeons no longer leaves the previous dungeon's preview bars ticking in the background — sharp drop in CPU when navigating across dungeon panels
- Bar fill animation no longer redraws every frame when the change wouldn't move the bar by even one pixel — same smoothness, less CPU
- BigWigs encounter timers no longer overwrite a still-extending in-progress bar from the same trigger; the new bar defers until the extension naturally expires
- Bar / Texts settings sliders no longer fire a stray callback when their min/max values are reconfigured

### Ready Check Consumables
- **Fixed:** with two 1H weapons, applying oil to the off-hand no longer lit up the main-hand slot too. The detection logic was tripping a Lua ternary gotcha that made the main-hand slot mirror the off-hand state when the main-hand was unenchanted

### Interrupt Tracker
- Cooling preview bars now skip per-frame redraws when the bar wouldn't visibly move
- OnUpdate detaches entirely when no bars are active — zero per-frame dispatch cost when idle

### Combat Timer
- OnUpdate detaches when not running — zero per-frame cost out of combat with no preview

### Cursor Circle / Dispel Cursor
- Per-frame position work skips when the cursor is stationary — these were the largest single source of idle CPU usage

### Time Spiral / Range Display
- Timer text and range text skip the redraw when the displayed string is identical to the prior tick

### Castbar (Focus / Target) and Dungeon Casts
- Throttled from 10 Hz to 30 FPS so every decimal tick in the 0.9 → 0.1 final-second window is visible

### Soft Outline (font rendering)
- Shadows on wide left/right-justified text no longer ghost in the opposite corner when the FontString is in a stretched container
- Fade-in/out animations no longer break when multiple soft-outlined FontStrings are on screen at once
- Eliminates the rare "stack overflow" crash from rapid fade transitions on soft-outline text

### Raid Notifications
- Clears its preview state on disable so re-enabling doesn't show a stale preview

### GUI
- Theme switching now properly refreshes pool-reused cards and widgets (some cached cards previously kept the old palette until /reload)
- Resize-grip on the GUI window no longer spazzes when clicked rapidly

### Profiler (`/kes profiler`)
- **NEW:** In-game CPU + memory profiler with named snapshots, top-function deltas, and per-walk diffing. Useful for diagnosing performance regressions
- Migrated to the 12.0 `GetFrameCPUUsage` + `C_AddOnProfiler` APIs for accurate measurements

### Under the hood
- New shared frame-pool primitive used by GUI cards across the addon — switching between module pages reuses widget frames instead of creating fresh ones, dropping rebuild cost dramatically
- Detail-pane card pooling on Dungeon Timers cuts ~20% memory and ~9% CPU per timer-click
- Module-preview Show/Hide calls are now skipped when the state hasn't actually changed, so cross-section navigation doesn't redundantly re-fire previews on every module
- Many small widget polish items — slider clamp silence, dropdown / colorpicker / editbox / toggle row callback hookups for pool reuse

---

## v1.19.0

### GUI
- **NEW:** Refreshed settings panel — bigger default window, full-width tabs across the top, and a sidebar that no longer squishes when you open a Dungeon Timer page
- **NEW:** Snap to Pixel Grid toggle now sits inline next to the Strata dropdown in every Position card with a short "ON for crisper text / OFF for precise positioning" hint
- Card 1 across modules trimmed to Enable + a one-line Note. Format/Display options moved into a dedicated card between Position and Font (Battle Res, Combat Timer, etc.)
- Several module pages reorganized for breathing room — notably Boss Debuffs, Combat Cross, Prescience Tracker, Ready Check Consumables, CVars Nameplates, and Great Vault Alert

### Dungeon Timers
- Settings now split into three sub-pages — Bars / Texts / General — instead of one tall scroll

### Skyriding UI
- The bars and Whirling Surge icon now center as a single visual unit — previously, setting Position XOffset = 0 centered just the bars while the icon hung off to one side

### Missing Enchants/Gems
- **NEW:** Master Enable toggle on Card 1, with the existing per-feature toggles (gem sockets, enchants, BetterCharacterPanel skip) moved into a General Settings card so individual checks can be turned off without disabling the whole module

### WarpDeplete+
- The standalone Instance Reset Announcer module is now folded into WarpDeplete+'s settings — same toggle and editable message, one less sidebar entry. Existing settings migrate automatically on first reload

### Profile resilience
- Switching profiles via the Profiles tab no longer leaves modules in a broken state — modules with active previews, partial color edits, or new-since-last-version settings all survive the switch cleanly
- Profiles auto-repair on load: saved font names that no longer resolve (e.g. an LSM-providing addon was uninstalled) reset to the project default, and settings added in newer versions get filled in for older saved profiles

### Under the hood
- Most module pages were touched as part of the GUI layout port — shared widgets for Font / Glow / Sound / Spell Browser / Text Format settings now replace the ad-hoc card layouts each page used to roll its own, so the look stays consistent across modules and adding a new module is a smaller diff going forward

---

## v1.18.0

### Position Controller (new module — replaces Racials Anchor)
- **NEW:** Anchors ElvUI Player / Target / Focus / Pet frames to other frames (the Essential Cooldown Viewer by default), with a per-frame chooser for the parent target and per-frame anchor + offset overrides. Includes a Focus frame option that the upstream reference doesn't ship
- **NEW:** Live status indicator on the top card — green when ElvUI is loaded, yellow when the standalone ElvUI_Anchor addon is detected (we yield to it to avoid two layers competing), red when ElvUI is missing
- **NEW:** Ignore Healer Specs toggle (default on) — anchoring no-ops on healer specs so ElvUI's profile positions take back over for healing layouts
- **NEW:** CDM Racials Anchor section consolidated into this module, fully independent of the master toggle. Live pet-status indicator (green when a pet bar is visible, red when not). Supports both ElvUI's `ElvUF_Pet` and UUF's `UUF_Pet`
- One-time migration carries the previous Racials Anchor settings (anchor points, offsets, pet bar offset) into the new CDM Racials section on first login

### Spell Alert Opacity (new module)
- **NEW:** Per-spec toggle for Blizzard's spell activation overlay (proc flashes), with each spec's icon rendered inline before its name. Useful for silencing proc flashes on tank/healer specs that don't need them
- **NEW:** Opacity slider for `spellActivationOverlayOpacity` so the flashes can be dimmed without hiding them entirely

### Missing Enchants/Gems
- Equipment-change updates now collapse rapid swaps into a single 0.1s debounced update, instead of running a full re-scan per `PLAYER_EQUIPMENT_CHANGED` event. Drops the duplicate `UNIT_INVENTORY_CHANGED` handler that fired alongside it
- Disabling the module now restores the Blizzard character-panel background textures it hid, instead of leaving the model scene blank until reload

### World Map
- Map scale callbacks (`WorldMapMinimized` / `WorldMapMaximized`) now properly unregister when the module is disabled or the Scale toggle is turned off, instead of staying registered as no-op closures

### Combat Resurrection
- Frame width is now sized correctly on first apply — the timer and charge text used to render too narrow until something forced a re-size (e.g. opening Edit Mode twice)

### Skyriding UI
- Speed text now centers over the visible bars + surge icon extent, not just the bars — when the icon is on the left or right of the bar block, the text shifts so it stays visually centered over the whole module

### GUI
- New reusable sub-tab widget — Castbars, Evoker Suite, Macro Builders, and Class Status Texts now share a single tab implementation. Tabs span the full content width on each page (matching the upstream layout), and an end-of-frame click debounce prevents the rapid-click render race that previously affected Evoker Suite
- Copy Anything module removed — the QoL sidebar was getting long and the feature wasn't widely used

---

## v1.17.0

### Death Notifications (new module)
- **NEW:** On-screen alerts when party/raid members or your focus target dies. Lives under the Dungeons section in the sidebar, active in 5-man dungeons by default with an opt-in toggle for raids
- **NEW:** Party/raid death messages render the dying player's name in their class color with a high-resolution circular class portrait next to it (Custom Nicknames apply automatically — a nicknamed party member shows their nickname instead of character name). Configurable text format with `%name` placeholder
- **NEW:** Focus death gets its own configurable text + color (defaults to `FOCUS DIED` in red)
- **NEW:** Soft-outline 8-shadow rendering, smooth alpha fade-out at end of duration, throttled to 4 party deaths per 10s so a wipe doesn't spam the screen
- Standard KE config surface — Behavior toggles (per-context activation, class color, class icon, format), Font Settings, Display (duration / spacing / grow direction), Position card with Snap to Pixel Grid

### Skyriding UI
- **NEW:** Reworked pill rendering — each charge has a 1px outset border that overlaps cleanly with adjacent pills for sharp shared dividers; pill background is a darkened version of the bar color so empty/recharging pills read as "dark <color>" instead of translucent black over the world
- **NEW:** Whirling Surge converted from a third bar row to a square icon with cooldown sweep and countdown text — sits to the side of the bars (configurable left/right), auto-sizes to match the bar block height or accepts a manual 16-64px override
- **NEW:** Behavior card with six toggles — Hide When Grounded, Hide When Full, Use Thrill Color, Show Second Wind, Flip Bar Order, Show Speed Text
- Recharging vigor pill no longer uses a special "lighter" color — partial fill against the dark bg reads as the recharging state naturally
- Colors card collapsed to a 1×3 layout; orphan `WhirlingSurge`, `WhirlingSurgeCD`, and `SecondWindCD` entries removed
- Card order updated: Enable → Behavior → Size → Colors → Surge Icon → Position
- Default colors changed: pink Vigor (`#FF008C`) and light cyan Second Wind (`#90F3F3`); default Bar Height bumped to 16; Thrill color override defaults off

### Pixel-Perfect Rendering
- **NEW:** Per-module *Snap to Pixel Grid* checkbox in the Position card — fixes soft-outline halos when frames anchor to ElvUI panels at sub-pixel screen positions (e.g. LeftChatPanel sits at 0.6/0.6 sub-pixel). Default OFF preserves precise integer-offset slider behavior; flip ON once positioned. Available on Combat Timer, Battle Res, Combat Texts, Range Display, Combat Potion Ready, Class Status Texts (Stance / Pet Status), Raid Notifications, Enemy Counter, and Healer Mana
- New pixel-snap helpers (`KE:GetPixelSize`, `KE:PixelSnap`, `KE:PixelSnapEven`) replace ad-hoc `math.ceil`/`math.floor` width math. Right-anchored frame edges (Combat Timer's right bracket at non-zero X offsets, Range Display, Enemy Counter, Action Bars column positioning) now land on exact integer pixels, eliminating residual halos at non-1.0 UI scales
- 1px borders across the skinning suite (Action Bars, Micro Menu, Auras, Battle.net, Tooltips, Details Backdrop) and standalone modules (Dungeon Timers, Dungeon Casts, Vantus Rune, World Map search box, Disintegrate tick width, Ebon Might Tracker border, Skyriding UI pills) all route through `KE:GetPixelSize()` for crisp edges at any UI scale

### Range Display
- Now shows `28+` (or whatever cap your class has) instead of just `28` when the target is beyond LibRangeCheck-3.0's longest available checker — typically opposite-faction players or hostile NPCs where hostile spell ranges cap at ~25-40y depending on class/spec. The `+` indicates the value is a lower bound, not an exact distance

### Combat Timer
- Brackets split into edge-pinned FontStrings — eliminates the right-bracket "shifting" that occurred when digit width changed (9 → 10, 99 → 100) due to the previous shared-FontString layout
- Soft-outline ghost shadows now properly clear when switching the outline style to "None" instead of lingering until reload

### Time Spiral Tracker
- Spec-keyed priority list with alt-talent fallbacks — picks the right movement spell for your current spec/talent automatically; handles spec changes (`PLAYER_SPECIALIZATION_CHANGED`) and talent reconfiguration (`TRAIT_CONFIG_UPDATED`) live without reload
- Multi-spell proc handler preserves the spec-detected spell pick when several procs fire in quick succession

### Raid Notifications
- Gateway Usable Reminder now suppresses itself when there's no Warlock in the group — wires `GROUP_ROSTER_UPDATE` to recheck on roster changes

### Healer Mana
- Settings edits now refresh existing frames in place instead of requiring a `/reload`

### Vantus Rune
- Fixed the confirmation popup's withdrawal bar overhanging the popup's right edge — bar borders now sit cleanly within the popup background

### Edit Mode / GUI
- Position Card row heights tightened (~16px overall) — dropdown/slider rows reduced from 40 → 36, snap row at 44; snap toggle reordered between offsets and strata since it directly affects offset behavior

---

## v1.16.3

### Ebon Might Tracker
- **NEW:** Pandemic Highlight — glow overlay during the last 4s of an Ebon Might buff, with 4 selectable glow styles (pixel, autocast, button, proc) and a configurable color. Forces the frame visible during the refresh window even when *Only Show on Crit* is enabled, so pandemic windows are never missed
- **NEW:** Main Stat card with an *Update from Current Stat* button — saves your primary stat as the first-cast bootstrap baseline. Auto-saves on combat exit and login; the button is a manual fallback for mid-fight gear/stat changes. Arcane Intellect is factored out automatically
- Rewrote crit detection — replaced the persisted baseline classifier with a 30s rolling cast-history window (single 1.25× threshold against the rolling minimum). Crit is now locked at cast time so mid-buff stat shifts (trinket procs, AI drop, gear swaps) no longer flip the border color partway through a buff
- Dupe detection switched to a live signal driven by the duplicate totem state (`PLAYER_TOTEM_UPDATE` + totem poll) — flips the dupe color the moment the duplicate spawns or expires during an active buff, instead of inferring from aura magnitude
- Added Pandemic Color picker — Colors card now lays out as a 2×2 grid (Base / Crit / Dupe / Pandemic)
- Logic adapted from EMTracker v1.2.0 by Baumritter

### Kick Tracker
- Removed Spell ID `132409` from the interrupt list — Blizzard removed this ability from Warlocks in 12.0.5
- Module is currently non-functional in 12.0.5 due to API changes — investigating alternative detection methods for a future release

---

## v1.16.2

### Dungeon Casts
- Fixed enemy cast bars silently dropping for every player-targeted hostile cast in 12.0 — `UnitSpellTargetName` returns the target's name directly (not a unit token), but the code was passing it to `UnitName` which rejects secret strings. Target names now render correctly for all casts
- Target names for player targets display with their class color
- Long target names truncate cleanly at the region edge instead of overlapping the spell name or time column
- Fixed the time text occasionally truncating to `...` at larger font sizes — width reservation now measures your configured font + size + outline once per settings change and caches it, so any font combination fits without manual tuning

### Focus Castbar / Target Castbar
- Fixed party member name highlighting that was silently broken in 12.0. Previously only your own name would ever light up because `UnitIsSpellTarget(caster, partyUnit)` no longer returns true for teammates. The castbar now shows a single target name string (player, party member, or NPC) with class color for player targets — more informative than the old highlight-one-of-five behavior

### Dungeon Timers
- Fixed stale text warnings firing after a boss died — bars with a Timer Offset were being held through `BigWigs_OnBossDisable` even when their countdown still had several seconds left. The HOLD guard now only keeps bars alive when they're inside the extension tail (the BigWigs bar has already naturally elapsed), not when the fight ended mid-countdown

---

## v1.16.1

### Packaging
- Declared `markup-type: markdown` on the manual-changelog in `.pkgmeta` so the CurseForge changelog tab renders headers, bullets, bold, and inline code properly. Wago was already auto-detecting markdown from the `.md` extension — no regression there

### CHANGELOG
- Rewrote every release entry from the old `Additions` / `Fixes` / `Changes` sub-header format to module-name sub-headers matching v1.15.0 / v1.16.0 style. No version history changed — purely a presentation pass

---

## v1.16.0

### World Map
- **NEW:** City Map Icons for Silvermoon, Stormwind, and Orgrimmar — trainers, innkeepers, portals, vendors, and class-hall teleports. Click an icon to set a waypoint
- **NEW:** Icon Style selector (Regular item icons / Small minimap-style with glow backdrop)
- **NEW:** "Only Show Trainers for Learned Professions" filter
- Renamed module from "World Map Scaler" → "World Map"

### WarpDeplete+
- **NEW:** Per-mob nameplate % overlay with configurable font, color mode (theme/custom), and anchor
- **NEW:** Death log persists across /reload within the same M+ key
- Rewrote forces tracking to use `C_ScenarioInfo.GetUnitCriteriaProgressValues` (added 12.0.5)
- Live pull-forces overlay removed — 12.0.5 blocks SecretValue arithmetic in tainted context. Tooltip and nameplate % still work
- Fixed death tooltip and class-color path for 12.0.5 localized CLEU

### Ebon Might Tracker
- Fixed 12.0.5 crit/dupe detection — `UnitStat` returns a secret value mid-encounter, breaking the old ratio math. Replaced with a baseline classifier that learns the clean EM average per target count and persists it across /reload
- **NEW:** Chronowarden apex Dupe proc detection (spellId 1259175)
- **NEW:** Recomputes on `UNIT_FLAGS` so death/charm/afk state changes feed the classifier

### Bloodlust Tracker
- Fixed repeated sound triggers in heavy raid combat — sound plays once by default instead of looping until the bar ends (matches upstream HighOnHaste v0.5.4)
- Added `numFrames` guard preventing divide-by-zero when sprite-sheet dimensions are degenerate

### Disintegrate Ticks
- Fixed 12.0.5 tick spacing — `UnitSpellHaste` returns a secret value in encounters; haste is now back-solved from the channel's actual duration

---

## v1.15.0

### Healer Mana (new module)
- **NEW:** Shows the party healer's name, mana %, and spec or class icon — configurable font, position, color, icon size, and icon type
- **NEW:** "Hide when my spec is a healer" toggle for self-healers
- Custom Nicknames apply automatically to the display
- Preview defers to the real healer when one's in your party

### Instance Reset (new module)
- **NEW:** Announces to party/raid chat when you reset instances — configurable message

### Dungeon Timers
- **NEW:** "Load KES Presets" button — imports curated preset triggers for the selected dungeon scope (dedup on repeat clicks)
- Reset button now scope-aware — "Reset All Dungeons" or "Reset [Dungeon Name]" based on the Dungeon dropdown
- Fixed Export/Import silently dropping triggers after a deleted entry (sparse-table iteration bug in `ipairs`/`#`)

### Combat
- Protection Paladin Avenger's Shield announce + fade-out restored, with `notInterruptible` nil-guard
- Balance Druid Solar Beam announce via Combat Texts

### CreatePrompt (shared widget)
- Fixed single-edit-box dialogs clipping their label (adaptive height, mirroring the v1.13.0 confirmation-prompt fix)

### Misc
- 12.0.5 interface support
- Sidebar sections default to collapsed (except Settings)
- Dungeons sidebar alphabetical

---

## v1.14.3

### Combat Castbars
- Fixed green kick-ready tick marker wiggling between pixels during enemy casts — now stays rock-steady for the life of each cast

---

## v1.14.2

### Combat Castbars (Warlock)
- Fixed Focus/Target castbar sound not muting and bar staying in "kick not ready" color after casting Axe Toss on Demonology Warlock with Felguard out

---

## v1.14.1

### Ready Check Consumables
- Fixed `ADDON_ACTION_BLOCKED` error when a ready check started or finished during combat — the consumable row now hides cleanly once combat ends

### Combat Castbars (Warlock)
- Fixed castbars showing "kick not ready" color and playing the interrupt sound even when a pet kick was available

### Internal
- Combat folder restructure — shared Focus/Target castbar logic extracted, interrupt spell data centralized, per-frame API polls moved to event-driven updates. Smoother feel, no user-visible behavior changes

---

## v1.14.0

### Ready Check Consumables (new module)
- **NEW:** Clickable consumable icon row attached to the ready check popup — tracks food, flask, main-hand & off-hand weapon enhancements (oils/stones/ammo), augment rune, healthstone, and Warlock Soulstone
- **NEW:** Click-to-use via SecureActionButton with `/stopmacro [combat]`-gated macros so clicks are combat-safe
- **NEW:** Context-aware slot visibility — off-hand enhancement hides when no OH weapon equipped, healthstone hides when no Warlock in group, class slot Warlock-only
- **NEW:** Dual-mode positioning — auto-anchor to the ready check popup for non-starters, fallback UIParent anchor for the starter (Blizzard skips the popup for whoever initiates), plus a full custom-anchor mode
- **NEW:** Close button for the ready check starter so the icon row can be dismissed without waiting for the timeout
- **NEW:** Compatibility toggles — *Use flasks only from raid cauldron* (Fleeting variants only) and *Use only unlimited augment rune* (DF/TWW unlimited only, with LibCustomGlow pixel-glow prompt when the rune is in bags but not applied)
- **NEW:** GUI configuration panel under **Utilities** → *Ready Check Consumables* with Enable / General / Visible Consumables / Position / Font / Colors cards plus a mock ready check preview popup for settings preview
- Ported from MRT's `RaidCheck.lua` and trimmed to Midnight 12.0 consumables only

### Combat Potion Ready
- Display Text moved out of the Enable card into a new *Display & Visibility* card; three visibility toggles flattened into a single 3-column row

---

## v1.13.1

### Custom Nicknames
- **NEW:** Unhalted Unit Frames support via the `[kes:nickname]` tag family
- **NEW:** Class color variants `[kes:nickname:color]` and `[kes:nickname:color:N]` (N = 1-30) for UUF
- **NEW:** `:color:short` / `:color:medium` / `:color:long` named width variants for UUF
- Available Tags card split into shared block + UUF-only subsection
- UUF path placeholder added to the Note section

### ProfileManager
- Fixed nil-call crash on profile create / switch / copy / rename / reset (root cause of "my profile disappeared" reports)

---

## v1.13.0

### Custom Nicknames (new module)
- **NEW:** Map characters (`Name-Realm`) to personal nicknames on ElvUI unit frames via a new tag family: `[kes:nickname]`, `[kes:nickname:N]` (1-30), and named variants `:short` (6), `:medium` (10), `:long` (20). Falls back to `UnitName` when no nickname is set
- **NEW:** GUI with Add/Update form (Use Current Target helper + realm auto-append), saved list grouped by nickname with click-to-edit rows
- **NEW:** Import/Export via `!KEN1!`-prefixed AceSerializer + LibDeflate payload (same pipeline as Dungeon Timers), Replace-mode toggle paired with Import, Clear All danger-zone button
- **NEW:** Live search box with filter-aware count (`N of M`), row flash on save/import, disabled Export/Clear All when empty, popup-based error surfacing for import failures

### CreatePrompt (shared widget)
- Fixed confirmation popups clipping text under the button row when the message wrapped past the default 120px dialog height — affects Dungeon Timers' *Reset All Triggers* and every other prompt with `\n\n`-separated body text. Dialog now measures the rendered FontString height and expands only when needed

---

## v1.12.3

### Bloodlust Tracker
- Fixed sound stutter during heavy raid combat — dropped poll rate 0.10s → 0.50s and added a 1.5s minimum between restarts so the loop no longer spams `PlaySoundFile` when the sound channel saturates

### Dungeon Timers
- Fixed extendTimer overwrite race — a new `BigWigs_Timer` arriving mid-extension now defers instead of silently hiding the visible extension
- Fixed extended bars getting killed by `BigWigs_StopBars` / `BigWigs_OnBossDisable` — new `StopAllBarsRespectExtend` path rides extensions through BigWigs cleanup events
- Added persistent `DEBUG_DT` flag for tracing BigWigs event flow, bar lifecycle, and extendTimer guard branches

### Cursor Circle
- Removed 3 non-functional crosshair/heart textures (Crosshair 1, Crosshair 2, Heart) from the texture dropdown

---

## v1.12.2

### Dungeon Timers
- Fixed bar previews invisible when the bar group was anchored to a non-UIParent frame (e.g. ElvUI unit frames)
- Unified anchor pattern across Dungeon Timers / Dungeon Casts / Interrupt Tracker — identical X/Y offsets now produce identical positions across the three modules

### Dungeon Casts / Interrupt Tracker
- Edit mode overlay now wraps just the anchor bar instead of the full stack — fixes misalignment with CENTER-based anchor points

---

## v1.12.1

### Dungeon Timers
- **NEW:** 14 color-coded display presets (AOE, DODGE, SOAK, FRONTAL, KICK, TANK HIT, etc.) — one-click label + color for common warning types
- **NEW:** Full anchor system for bar/text groups — anchor frame type, parent frame selection, and strata
- Fixed `BigWigs_StopBar` killing timers that still have extended time remaining
- Fixed pull/break countdown triggering unrelated timers with empty spell ID filters
- Fixed position changes not applying until /reload
- Fixed bar/text previews ignoring anchor frame setting

### Dungeon Casts
- Fixed cast bar group shifting position when bar count changed — switched to 1x1 anchor pattern matching Interrupt Tracker

---

## v1.12.0

### Dungeon Casts (new module)
- **NEW:** Enemy cast bars for M+ nameplates with icon, target text, raid icons, bar stacking, and interruptible/shielded status colors. Only active in 5-player dungeons

### Dungeon Timers (new module)
- **NEW:** BigWigs-integrated per-dungeon timer system with trigger editor, bar/text display groups, role-based load conditions, and spell browser
- **NEW:** Per-trigger display overrides
- **NEW:** Import/Export system — share timer configurations per-dungeon or all-at-once via AceSerializer + LibDeflate. Reset all triggers with confirmation prompt

### GUI
- **NEW:** Section-based previews — opening the GUI only previews modules in the active sidebar section (edit mode still shows all)
- **NEW:** Panel builder system (`RegisterPanel`, `RegisterWidePanel`) for full content-area takeover on dungeon trigger editor pages
- **NEW:** Sidebar `disabledCheck` and `alwaysEnabled` support for the Dungeon Timers section

### Combat Cross / Combat Texts / Core
- Fixed C stack overflow caused by `UIFrameFadeIn` / `UIFrameFadeOut` on frames with soft outline children (also fixed in `CreateMessagePopup`)

### Boss Debuffs
- Fixed `blacklistBox` nil upvalue error when the edit box loses focus
- Moved from Encounter Tools to Combat. Encounter Tools section removed

### Interrupt Tracker
- Moved from Combat to Dungeons section
- GUI restructured into Frame Settings and Bar Appearance cards matching the Dungeon Casts pattern

### Theme
- Fixed missing `OnThemeChanged` handler in Potion Ready, Enemy Counter, Raid Notifications, No Movement Alert, and Stasis Tracker — theme color changes now update these modules immediately

### Target Castbar
- Added to the preview system (was missing)

---

## v1.11.0

### Core
- **NEW:** Centralized secret value API (`Secret.lua`) — `KE:IsSecretValue()`, `KE:IsSafeValue()`, `KE:IsFullyRestricted()`, `KE:DeferUntilUnrestricted()` and restriction state tracking for combat, M+, encounters, and PvP
- **NEW:** Protected function violation listener for debugging
- **NEW:** `KE:AddBorders()` — enhanced border helper with optional `borderParent` for frame level control and a `SetBorderColor` method

### Combat Texts
- **NEW:** "No Target" warning — persistent text displayed when in combat with no target selected. Generation-based debounce prevents flicker during rapid target changes. Disabled by default, configurable text and color
- GUI: "No Target Warning" card with enable toggle, color picker, and text input

### Time Spiral
- **NEW:** Countdown timer text overlay on the icon showing remaining proc duration with dynamic decimal formatting via `C_DurationUtil`. Configurable font, size, outline, and color
- **NEW:** Infernal Strike (1234796) added for Demon Hunter
- Improved talent detection with multi-method `IsTalentKnown` (IsPlayerSpell + IsSpellKnown + C_Spell)
- GUI: Merged "Text Settings" and "Font Settings" into a single "Label Text" card. Added "Timer Settings" card for countdown display

### Automation
- **NEW:** Hide all tutorial/helptip popups at load time
- **NEW:** Hold Shift when opening a vendor to bypass auto-sell junk
- Replaced manual bag iteration for junk selling with `C_MerchantFrame.SellAllJunkItems()`

### Hunter's Mark
- Replaced `InCombatLockdown()` gate with the new restriction state system — nameplate tracking now works during combat instead of being completely blocked
- Added `issecretvalue` guards on aura scanning (`spellId`, `sourceUnit`) to prevent false "missing mark" warnings from secret values
- Added `ENCOUNTER_START` / `ENCOUNTER_END` events for better state management

### Auras Skinning
- Fixed buff icons not being re-styled when buffs are gained or lost — added missing `BuffFrame:UpdateAuraButtons` hook
- Added `SpaceRows` call for live row layout
- Added `ExternalDefensivesFrame:UpdateAuraButtons` hook for live restyling of defensive auras

---

## v1.10.5

### Enemy Counter
- Fixed inaccurate mob count — added `UnitIsDead` filter so dead mobs with lingering nameplates are no longer counted, plus `UnitCanAttack` filter so friendly NPC nameplates are excluded. Added persistent `DEBUG_EC` flag for future diagnostics

---

## v1.10.4

### WarpDeplete+
- Fixed duplicate death entries — `UNIT_DIED` fires for every mob death and time-window dedup failed as the M+ timer advanced past the death penalty jump. Replaced with state-based per-player dedup that clears when a player is alive again (battle-rez safe). Added `UNIT_DIED` debounce so the roster scan runs at most once per 150ms
- Fixed death names not class-colored — WarpDeplete's CLEU path ships a localized class string (e.g. `"Druid"`) instead of the classFilename token (`"DRUID"`) that `GetClassColor` expects. Now always prefers a roster-based `UnitClass(unit)` lookup
- Fixed death header count not matching the tooltip list — hooked `SetDeathCount` to use `max(gameCount, listCount)`. Per-death time penalty is learned dynamically from `C_ChallengeMode.GetDeathCount()` (5s below +12, 15s with Xal'atath's Guile)
- Fixed pull-forces overlay disappearing when re-entering combat within 0.5s of a drop — the delayed `PushToWarpDeplete(0)` callback from `PLAYER_REGEN_ENABLED` now checks `UnitAffectingCombat("player")`

### Ebon Might Tracker
- GUI reorganized — Mode dropdown and toggles (Only Show on Crit, Combat Only) moved from the Enable card into a separate Display Settings card. Color pickers (Base, Crit, Dupe) consolidated to a single horizontal row

---

## v1.10.3

### Ebon Might Tracker (new module)
- **NEW:** Augmentation Evoker tracker — shows active Ebon Might duration with crit and duped cast detection via mainStat ratio math against ally aura values
- **NEW:** Two display modes — Icon + Countdown (spell icon with centered timer) and Border + State Label (iconless border with "CRIT"/"DUPE" label above)
- **NEW:** Border dynamically recolors and thickens on crit/dupe (transparent → magenta/orange, 1px → 2px)
- **NEW:** Only Show on Crit toggle
- Class-gated to Evoker. Ported from EMTracker by Baumritter

### Bloodlust Tracker
- Simplified to two modes (Pedro animated overlay + Static Icon with countdown). Removed chipi/ninemm/erm presets, haste-approximation detection, sound-only mode, and DisplayMode concept. Removed ~1.8MB of unused media
- **NEW:** Combat Only toggle
- Fixed multi-trigger sound bug — edge-triggered detection now uses `updateInfo.addedAuras` instead of re-scanning
- Unified anchor behavior across both modes via `SetScale(1)` + computed size

### Prescience Tracker
- **Renamed:** "Aug Buffs Tracker" → "Prescience Tracker". Module only tracks Prescience and Shifting Sands — the narrower name fits and frees the "aug" namespace for the new Ebon Might Tracker. DB key `AugBuffsTracker` renamed to `PrescienceTracker` (existing profiles reset this module's settings to defaults)
- Fixed role icon drawing behind the main buff icon — reparented to iconFrame with correct sublevel, matching the `timer` FontString pattern
- Fixed Class Color Names toggle leaking widget state across GUI page rebuilds

### Evoker Suite
- Tab order and labels updated — Disintegrate / Stasis / Ebon Might / Prescience. The Ebon Might tab now hosts the Extension Helper (sound alert) and the new Tracker (visual display) in a shared card stack
- Fixed tab bar corrupting when rapidly switching away from the Disintegrate tab — tab clicks are now debounced via `C_Timer.After(0, ...)`, collapsing multiple rapid clicks into a single `RefreshContent`

### GUI
- Fixed latent zero-width-parent race for tabbed pages — `scrollChild` is now sized synchronously at creation instead of via a deferred timer

---

## v1.10.2

### WarpDeplete+
- **Renamed:** from "WarpDeplete Forces" to reflect expanded scope (forces + death fixes + tooltip)
- Fixed pull-forces overlay double-counting with WarpDeplete's own killed tracker — now only counts alive mobs
- Fixed death tooltip showing "No Recorded Player Deaths" in M+ (GUID is secret; bypassed with a roster scan)
- Fixed death names not class-colored (was using localized className instead of classFilename token)

---

## v1.10.1

### Enemy Counter (new module)
- **NEW:** Displays the number of enemies currently in combat via nameplate scanning. Editable prefix with toggle, combat-only visibility option, standard font/color

### WarpDeplete Forces
- Unhidden sidebar entry for the Dungeons section

---

## v1.10.0

### Battle.net Toast (new module)
- **NEW:** Dark theme skinning for BNet notification toasts with custom anchor positioning and EditMode support. Ported from NorskenUI

### WarpDeplete Forces (new module)
- **NEW:** Restores live pull forces tracking to WarpDeplete using fingerprint-based mob identification to bypass 12.0 Secret Values
- **NEW:** Tooltip shows per-mob forces in M+. All 8 Midnight Season 1 dungeons covered

### ElvUI Tags
- **NEW:** `[kes:group]` — shows "Group: X" only while in a raid group

### GUI
- **NEW:** Dungeons sidebar section (hidden pending further testing)

### Internal
- `.luacheckrc`: added missing WoW API globals (Mixin, UnitClassification, UnitSex, UnitPowerType, C_ScenarioInfo, GetRaidRosterInfo, WarpDeplete)

---

## v1.9.2

### Internal
- Code standards pass — Unicode box headers, 81-dash section dividers, and `-- Local references` cleanup across all 138+ Lua files. Removed 8 stub files (CDMGlow, CDMOverlay, Chat, Minimap). Suppressed unused `self` warnings in `.luacheckrc`

---

## v1.9.1

### Battle Res / Combat Timer / No Movement Alert
- Fixed crash when opening GUI post-encounter — all three modules now guard against secret values from `GetStringWidth()` after combat

---

## v1.9.0

### Boss Debuffs (new module)
- **NEW:** Shows icons for external debuffs applied to you during boss encounters. 1-5 icons with growth direction, cooldown spiral, duration text, mouseover tooltip, encounter blacklist with hover reference
- **NEW:** Visibility modes — Boss Encounters, Instance Combat, Always in Combat

### Racials Anchor (new module)
- **NEW:** Repositions the Ayije CDM racials bar with custom X/Y offsets and automatic pet bar offset for pet classes. Supports ElvUI and UUF pet frames

### Core
- **NEW:** Icon Standard — centralized `KE:ApplyIconZoom()` and `KE:AddIconBorders()` in `Core/Widgets.lua`. All icon modules now use consistent 0.3 zoom + 1px pixel-perfect borders

### GUI Sidebar
- **NEW:** Encounter Tools section for encounter-specific modules
- Alphabetical ordering for Combat, Utilities, and QoL sections
- Renames: Combat Res → Battle Res, Combat Cross → Player Crosshair, Dragon Riding UI → Skyriding UI

### Custom Buffs
- **Removed:** Section and all 4 modules (Buff Icons, Buff Bars, Externals/Defensives, Movement Buffs) — deprecated

### Misc
- Fixed 1px or oversized edit mode borders on Battle Res / Combat Timer / No Movement Alert — frames now size dynamically from content instead of backdrop/hardcoded values
- Fixed `/wa` slash command not respecting addon forks or disabled WeakAuras — now checks `WeakAuras` global instead of `IsAddOnLoaded`
- Fixed "Font not set" error during profile switch in Raid Notifications — settings now applied before showing preview alerts
- Fixed AugBuffsTracker creating frames on non-Evoker characters — added class check in OnEnable
- Migrated BloodlustTracker / StasisTracker / AugBuffsTracker / RaidNotifications / TimeSpiral / Recuperate / HuntersMark to the centralized icon helpers

---

## v1.8.6

### Preview / Edit Mode
- Class-restricted modules (Evoker Suite, Hunter's Mark) no longer show previews on non-matching classes. Any module can declare `classRestriction` to opt in

---

## v1.8.5

### Combat Potion Ready (new module)
- **NEW:** Displays "Potion Ready" text when a combat potion is in bags and off cooldown. 22 potions tracked (regular + fleeting)
- **NEW:** Visibility toggles — Instance Only, Combat Only, Hide for Healer Specs
- Standard color mode (class/custom/theme), SOFTOUTLINE default, anchored to `UtilityCooldownViewer`

---

## v1.8.4

### Battle Res
- Fixed module not respecting disabled state on login/profile switch — added missing `db.Enabled` gate in OnEnable

### Missing Enchants/Gems
- Fixed double text overlays when BetterCharacterPanel is loaded — silently skips if BCP is present
- Fixed event frame not unregistering events on module disable

### Packaging
- Fixed `<Include>` tags on `.lua` files in `Libs/Init.xml` (should have been `<Script>`). Standardized all paths to forward slashes
- Expanded `.pkgmeta` ignore list. Split Ace3 bulk external into individual library externals. Added LibCustomGlow, LibDBIcon, LibDataBroker, LibRangeCheck as externals. Added `.gitattributes` for line ending normalization

---

## v1.8.3

### Missing Enchants/Gems (new module)
- **NEW:** Red warnings on the character panel for missing enchants and empty gem sockets
- **NEW:** Expansion-aware enchant slots, tooltip-based gem socket detection ("Prismatic Socket"), combined text display ("No Enchant / No Gem")
- **NEW:** Configurable font, size, and outline. Hide Character Panel Background toggle

### World Map Scaler (new module)
- **NEW:** Adjustable minimized world map scale (1.0–2.0x)
- **NEW:** Coordinate waypoint search bar with live preview. Accepts multiple input formats (`/way`, comma-separated, spaces). Super-tracks waypoints automatically

### ElvUI Tags
- **NEW:** `[kes:name-classcolor]` — unit name with class/reaction color
- **NEW:** `[kes:target:separator]` — white » only when target exists
- **NEW:** `[kes:target:name-classcolor]` — target name with class/reaction color
- Tags only load when ElvUI is present

### Home Page
- **NEW:** General Settings card with "Show Minimap Button" and "Show Command in Chat on Login" toggles

---

## v1.8.2

### Combat Texts
- **NEW:** Interrupt Text — displays interrupted spell name and icon on a successful kick. Spec-aware detection using zzal reference pattern (`UNIT_SPELLCAST_SUCCEEDED` flag + `UNIT_SPELLCAST_INTERRUPTED`). Works in dungeons via `C_Spell.GetSpellInfo` AllowedWhenTainted. Configurable text, color, fade
- **Renamed:** "Interrupt Announce" → "Interrupt Text"
- Combat Enter/Exit combined into a single "Combat Messages" card with one enable toggle
- Per-type fade durations — Combat Messages and Interrupt Text each have their own slider (shared Fade Duration removed)
- Updated defaults — enabled, MEDIUM strata, Y offset 125, spacing 0, gray enter/exit colors, blue interrupt
- Tighter message stacking — frame height matches font size instead of hardcoded 30px

---

## v1.8.1

### Focus Castbar
- **NEW:** Mute sound when kick on CD — suppresses the cast alert sound while your interrupt is on cooldown. Uses spec-aware, event-based cooldown tracking (no secret value APIs)
- Fixed interrupt spell ID not caching at login — added `SPELLS_CHANGED` event to `CacheInterruptId`. Previously the kick tick and mute feature required a zone change before working
- Rewrote interrupt data from class-keyed to spec-keyed table (matching KickTracker). Fixes stale cooldown values (DK 15→12s, Mage 24→20s, Priest 45→30s) and per-spec CD differences (Evoker 20/18s, Shaman 12/30s, Warlock 24/30s)
- Updated defaults — enabled, 350x30, blue casting/channeling, red not-interruptible, green hold/tick, hide non-interruptible casts, sound on (Interrupt, Master)

### Interrupt Tracker
- Fixed ~1-in-5-8 CC false-positive in channel kick detection — replaced UNIT_AURA-based CC detection with `interruptedBy` GUID validation (ExWind v26.4.2 port). Removed the UNIT_AURA event handler entirely

### CVars
- **NEW:** "Always Compare Items" toggle — disable to show item comparison tooltips only while holding Shift

### Internal
- Comprehensive WoW API globals whitelist in `.luacheckrc` — zero "undefined variable" warnings across the codebase. Added `References/` exclusion

---

## v1.8.0

### Great Vault Spec Alert (new module)
- **NEW:** Shows your loot specialization with class color and spec icon on opening the Great Vault. Configurable sound, chat message, alert duration, font, and position

### Vantus Rune Withdrawer (new module)
- **NEW:** Guild Bank button to withdraw one Vantus Rune by priority (Radiant Gold > Radiant Silver)
- **NEW:** Pre-flight checks (existing rune, bag space, withdrawal limits), confirmation popup with countdown, cross-realm failure detection

---

## v1.7.3

### GUI
- Fixed mousewheel scrolling jumping top-to-bottom — content area (40px/tick) and sidebar (30px/tick) now scroll incrementally. Added `EnableMouseWheel` + `OnMouseWheel` handlers matching the dropdown widget pattern

### Aug Buffs Tracker
- Fixed edit mode overlay misaligned with entry bounds — now uses KickTracker's edge-anchor resize pattern

---

## v1.7.2

### Aug Buffs Tracker
- **NEW:** Name truncation — "Max Characters" slider (0 = full name) to shorten long player names
- Fixed all entries disappearing simultaneously in combat — `GROUP_ROSTER_UPDATE` was doing a destructive wipe + API re-scan that fails in combat. Now additive re-scan out of combat, skips in combat
- Replaced Stack Direction + Growth Direction with a single Growth Direction dropdown (Down/Up/Right/Left)

### Stance Texts
- Fixed Evoker attunements not detecting in combat — detection moved from buff scan to shapeshift form (like Warrior)

---

## v1.7.1

### Aug Buffs Tracker
- **NEW:** Growth Direction setting — entries grow Down, Up, Left, or Right from the anchor. Chain-anchor layout prevents frame resize from shifting entries
- Fixed entries randomly disappearing in combat — `removedAuraInstanceIDs` now checks both instance ID and unit token (aura instance IDs are per-unit; cross-unit ID collisions caused false removals in raids)
- Additive re-scan in the combat ticker (no wipe). Secret value guards restored on `expirationTime` and `aura.points` in `AddTrackedBuff`

### Raid Notifications
- **Removed:** Loot Boss save detection (unreliable encounter ID mapping)

---

## v1.7.0

### GUI
- **NEW:** Sidebar Search — real-time search bar at the top of the sidebar. Filters modules by name as you type, hides non-matching sections, force-expands matching sections, shows "No results found" for empty queries. Clear button (X) and ESC to reset. Clears automatically on GUI close. Theme-aware

---

## v1.6.9

### Aug Buffs Tracker (new module)
- **NEW:** Tracks Prescience and Shifting Sands on party/raid members for Augmentation Evoker. Buff icon, countdown timer, role badge, and player name per tracked target
- **NEW:** Horizontal/vertical stacking, icon size, separate name/timer fonts, class-colored names, crit color for Prescience
- Added as the 4th tab in Evoker Suite
- Combat-safe aura handling — processes `addedAuras` event payload directly (non-secret), guards `isFullUpdate` and `updatedAuraInstanceIDs` against tainted API returns in combat, `issecretvalue` guards on `expirationTime` and `points`

### Raid Notifications
- **NEW:** Loot Boss save detection — uses `C_EncounterJournal.IsEncounterComplete` to suppress "LOOT BOSS" when already saved to the boss (pre-cached on zone-in, compared on encounter end)

---

## v1.6.8

### Evoker Suite
- **NEW:** Stasis Tracker — Preservation Evoker module displaying stored spell icons and a 30-second countdown bar during Stasis. Configurable icon size, spacing, growth direction (horizontal/vertical), bar side, bar color mode, and font
- **NEW:** Ebon Might Helper — Augmentation module that plays a warning sound when casting an extender spell (Eruption, Fire Breath, Upheaval) that won't refresh Ebon Might. Smart polling handles mid-cast haste changes. Configurable sound and channel
- Combined Disintegrate Ticks, Stasis Tracker, and Ebon Might Helper into a single tabbed GUI page under Utilities

---

## v1.6.7

### Interrupt Tracker
- **NEW:** Healer position override — auto-swaps to a separate position/anchor when playing a healer spec. Core-level `KE:ApplyActivePosition` system available for future module opt-in. Enabled by default

### Focus Castbar / Target Castbar
- Fixed `notInterruptible` secret boolean handling — separated casting/channeling checks to avoid `or` on secret values. Added nil guard for `HideNotInterruptible` alpha toggle

### Internal
- Removed `GetSpellCooldown` debug print spam from No Movement Alert
- Removed secret-value debug prints from Bloodlust Tracker, Battle Res, Cursor Circle, Disintegrate Ticks, and Dispel Cursor

---

## v1.6.6

### Raid Notifications
- Fixed Reset Boss and Loot Boss alerts triggering in dungeons and M+ — now restricted to Normal/Heroic/Mythic raids only (difficulty 14-16). Matches NorthernSkyRaidTools reference via `GetInstanceInfo()`

---

## v1.6.5

### GUI Sidebar
- **Tab mergers** to reduce clutter:
  - Focus & Target Castbar — combined with tab switcher (Combat)
  - Class Status Texts — Pet Status, Class Stance, No Movement Alert, and Dispel CD on Cursor combined into one 4-tab page (Utilities)
  - Macro Builders — Focus Marker and Power Infusion combined (Utilities)
- Sidebar item count: Combat 10→8, Utilities 12→8. All module backends unchanged
- Added kick indicator note on both castbar GUI pages explaining bar color override behavior

### Defaults
- Updated defaults — PetStatusText (enabled, medium strata, size 26, accent passive color), NoMovementAlert (enabled, theme color, size 16, "NO %n - %t" format), DispelCursor (enabled, cyan text #3BECFF, offset 3)

### No Movement Alert
- **Removed:** Demon Hunter Shift from spell list (3-charge spells incompatible with 12.0.5 secret value cooldown checks)

---

## v1.6.4

### No Movement Alert (new module)
- **NEW:** Shows remaining cooldown when your movement ability is unavailable. Auto-detects class spell (highest priority known)
- **NEW:** Configurable display format with spell name and timer placeholders
- **NEW:** Max Cooldown threshold (default 30s) — only shows the alert when remaining cooldown drops below the threshold, hiding long-CD spells like Dash until they're nearly ready

### Internal
- KickTracker: merged player/pet kick handlers, simplified pool pop, reusable temp tables for layout, removed redundant `ApplyBarColor` from OnUpdate tick
- FocusCastbar: single cooldown fetch per frame shared between kick indicator and tick position
- RaidNotifications: cached aura API at load time, skip alerts when player is dead. Updated defaults (enabled, accent color, larger font)
- GUI text cleanup: gray `|cff888888` helper labels on settings hints, standard Note block on module descriptions

---

## v1.6.2

### Raid Notifications (replaces Gateway Alert)
- Gateway usability alert joined by **Reset Boss** (lust debuff reminder between pulls) and **Loot Boss** (reminder to loot after a boss kill). Per-alert toggles, shared font/color/position, configurable alert duration. Existing Gateway Alert settings migrate automatically

---

## v1.6.1

### Raid Notifications (replaces Gateway Alert)
- Gateway usability alert joined by **Reset Boss** and **Loot Boss** alerts. Per-alert toggles, shared font/color/position, configurable duration. Existing Gateway Alert settings migrate automatically

---

## v1.6.0

### Interrupt Tracker (new module)
- **NEW:** Tracks party interrupt cooldowns in real-time via status bars. Event-correlation detection (no protected API calls)
- **NEW:** Class/dark color modes with drain/fill animations, channel kick detection, icon desaturation on CD, Warlock pet kick support, role-based sorting

### Bloodlust Tracker (new module)
- **NEW:** Animated sprite overlay + sound on Bloodlust/Heroism/Time Warp. Presets — Pedro, Chipi Chipi, 9MM Bang (sound only), Sarah Gamer Word (sound only)
- **NEW:** Basic icon + countdown mode, sated debuff detection with optional haste-approximation fallback, Instance Only toggle

### Focus Castbar
- **NEW:** Sound alert on focus target cast start — LSM sound picker and channel selection

### Gateway Alert
- **NEW:** Gateway shard icons flanking the alert text (toggleable)
- **NEW:** Color mode selector (Class/Custom/Theme)

### Focus Marker
- Ready check announce now silently skips for specs without an interrupt ability

---

## v1.5.1

### Pet Status Texts
- Fixed preview not showing on non-pet classes until a GUI change — frame now applies position and font on first preview open

---

## v1.5.0

### Class Stance Texts (new module)
- **NEW:** Displays customizable text labels for your current Warrior stance, Paladin aura, or Evoker attunement with per-stance colors

### Missing Buffs
- **Removed:** Buff/food/flask/enchant/poison tracking replaced by the BuffReminders addon. Stance text feature extracted into the new Class Stance Texts module

---

## v1.4.3

### Disintegrate Ticks
- Fixed chain-cast tick placement firing too early — first tick now uses modulo of remaining time by previous hasted tick interval, matching upstream v2.0.1

---

## v1.4.2

### Minimap Button
- Tooltip styled with gold-colored click keywords and grey "Essentials" text for better visual hierarchy

---

## v1.4.1

### Minimap Button (new module)
- **NEW:** KitnUI cat icon on the minimap. Left-click opens settings, right-click toggles edit mode, middle-click reloads UI

### Automation
- **NEW:** Auto Confirm Queue toggle — auto-clicks Sign Up on LFG application dialogs (Ctrl bypass)
- **NEW:** Auto Slot Keystone toggle — auto-slots your keystone when opening the M+ UI
- **NEW:** Hide Event Toasts and Hide Zone Text toggles in the Cinematics & Dialogs card

### Combat Logger
- **NEW:** Quiet Mode toggle — suppresses chat messages when logging starts/stops

### GUI
- Hamburger menu dropdown delay bumped from 0.1s → 0.3s for easier mouse navigation

### PI Macro Builder
- Restored `SetPITarget()` global for backward compatibility with existing `/run` macros

### Internal
- `/simplify` pass — `KE:Print()` usage cleanup, removed dead code in FocusMarker and WorldMarkerCycler GUI

---

## v1.4.0

### Auction House Filter (new module)
- **NEW:** Auto-applies Current Expansion filter and focuses the search bar for the Blizzard AH and Craft Orders. Replaces the old single toggle from Automation

### Combat Logger (new module)
- **NEW:** Automatic combat logging for raids, dungeons, M+, PvP, arenas, and scenarios
- **NEW:** Per-content-type toggles, 30-second delayed stop for Warcraft Recorder compatibility, ACL prompt on login

### Power Infusion Macro Builder (new module)
- **NEW:** Auto-creates and manages a PI macro with trinkets, Vampiric Embrace, racial, potion/fleeting potion, and custom `/use` line. Extracted from Slash Commands into its own module with full GUI
- Now auto-creates the macro (no longer requires a pre-existing "PI" macro)

### Disintegrate Ticks
- Synced to upstream v2.0.0 — haste-aware tick placement, channel chaining support, Hover mid-Disintegrate deduplication, spellId filter on channel stop

### GUI
- Title bar font bumped to large (16px)
- Fixed intermittent resize-grip drag conflict with frame movement

### Internal
- Focus Marker / World Marker Cycler — replaced hardcoded `print()` with `KE:Print()`, clear `lastMacroName` on disable, removed dead `MARKER_NAMES` and `dragState.ghostTex` references
- Replaced hardcoded PREFIX constants with `KE:Print()` across new modules. Removed `_G.SetPITarget` global pollution from PIMacroBuilder
- Removed AH filter toggle from Automation page (replaced by new module). Removed PI Macro Builder card from Slash Commands page (replaced by new module)

---

## v1.3.1

### GUI
- **NEW:** Utilities sidebar section between Combat and Quality of Life. Moved Gateway Alert, Pet Status Texts, Time Spiral Tracker, Recuperate Button, Dispel CD on Cursor, Disintegrate Castbar Ticks, World Marker Cycler, and Focus Marker Macro Builder into Utilities
- Skinning section auto-collapses when ElvUI is detected
- Skinning sidebar reordered — General UI Clean Up and Buffs/Debuffs pinned at top, rest alphabetized
- **Renamed:** Range Checker Text → Range Display

### GUI Pages
- Color pickers paired side-by-side where previously stacked (Combat Timer, Range Display)
- Automation page — all toggle pairs now side-by-side (Cinematics, Merchant, Quest, Social, Convenience)
- Combat Cross — Range Warning checkboxes paired side-by-side
- Recuperate — Load conditions and Button Size merged into "General Settings" card. Added full anchor frame controls
- Disintegrate Ticks — Note text split into two clear lines

### Target / Focus Castbar
- **NEW:** Target Names card on Target Castbar with enable toggle, anchor, font size, and offset controls
- **NEW:** Target Names enable toggle on Focus Castbar

---

## v1.3.0

### Focus Marker Macro Builder (new module)
- **NEW:** Auto-creates and manages a focus target + raid marker macro. Marker icon grid selector, mark-only mode, no-raid marking, no-toggle, ready check announce, custom macro name/icon/conditionals

### Target Castbar
- Fixed target names using hardcoded positioning with no GUI controls

### Focus Marker
- Fixed NoToggle setting inversion causing marker spam on repeated clicks

---

## v1.2.0

### Disintegrate Castbar Ticks (new module)
- **NEW:** Evoker-only (Devastation/Preservation). Displays tick marks on your cast bar during Disintegrate channels with a configurable "DON'T CLIP" warning for Mass Disintegrate. Supports UUF, BCDM, Ayije CDM, and Blizzard cast bars

### World Marker Cycler (new module)
- **NEW:** Cycles through world markers at cursor position with customizable keybinds and drag-to-reorder marker priority. Interactive keybind capture with modifier support

### GUI Sidebar
- **Renames:** "Dispel on Cursor" → "Dispel CD on Cursor", "Time Spiral" → "Time Spiral Tracker"
- Time Spiral Tracker — added note clarifying it works for all classes
- Standardized note prefixes with accent-colored dash across all pages
- CVars "enabled" text color changed from accent to green for better visibility

---

## v1.1.5

### ActionBars
- Removed pcall wrappers from cooldown text styling and `SetUserPlaced` calls to reduce taint spreading to Blizzard's ZoneAbility system. Note — modifying cooldown regions inherently taints them (known Blizzard-side issue shared with NorskenUI)

---

## v1.1.4

### Battle Res
- Removed pcall wrappers around `C_Spell.GetSpellCharges` to prevent taint spreading to Blizzard's ZoneAbility system (was causing `CastSpellByID` forbidden errors)

---

## v1.1.3

### Battle Res
- Fixed tracker only showing on Druids during encounters — added `SPELL_UPDATE_CHARGES` and `PLAYER_REGEN_DISABLED` event-driven updates

### Tooltips
- Fixed `IsShown`/`SetAlpha` errors on embedded widget tooltips — removed `EmbeddedItemTooltip` from the skin list

---

## v1.1.1

### Sidebar / GUI Theme
- Hover and selection gradient overlays now update dynamically with theme changes
- Fixed CreateButton callback format for Copy/Reset buttons

---

## v1.1.0

### Addon Theme (new system)
- **NEW:** 8 WoW-themed color presets (KitnUI, Nighthold, Firelands, Icecrown, Dreamsurge, Twilight, Sunwell, Torghast), class color mode, and full custom color mode
- **NEW:** Paint icon button in the header bar for quick theme access
- **NEW:** Hamburger menu in the header bar with Reload UI, Blizzard Edit Mode, Kitn Edit Mode, and Cooldown Manager shortcuts

### GUI
- Merged Profiles and Theme into a unified "Settings" sidebar section
- Moved Cursor Circle from Quality of Life to Combat section
- **Removed:** Personal Defensives and Personal Movement Buffs from the GUI sidebar (now handled by ACDM)

### Misc fixes
- GUI-Theme — added nil guards for `db.Custom` color picker access
- ActionBars — minimum size guard in proc glow hook to prevent errors on unsized buttons
- DispelCursor — 60fps throttle on OnUpdate, proper event cleanup in OnDisable
- AddonTheme — recursion guard on `RefreshTheme` to prevent infinite loops
- CustomOutline — secret value guards now cover all text/alpha comparisons
- Sidebar — accent bar and selection highlight now update with theme changes
- CursorCircle / CombatCross — `OnThemeChanged` handlers for live theme color updates

---

## v1.0.9

### Dispel on Cursor (new module)
- **NEW:** Shows your dispel cooldown timer following your cursor. Auto-detects class dispel spell

### Cursor Circle
- **NEW:** Crosshair and heart texture options. Texture selector now supports a multi-row grid layout

---

## v1.0.8

### CustomOutline
- Fixed errors on focus castbar and other secure frames — added secret/tainted value guards to all text and alpha comparisons

### Tooltips
- Reverted to manual textures (bypassing `Backdrop.lua` entirely) — NorskenUI's BackdropTemplate approach still triggered taint errors

---

## v1.0.7

### Combat Cross
- **NEW:** Range warning — cross changes color when target is out of range (melee/ranged/healer spec support)

### Recuperate
- **NEW:** Configurable Load in Raid/Party toggles
- **NEW:** Health alpha curve (visible when missing health, hidden at full). Dead/ghost handling

### Missing Buffs
- Replaced `AuraUtil.ForEachAura` with direct `C_UnitAuras` API calls for better secret-value handling

### ActionBars
- Proc glow (SpellActivationAlert) size now matches button size dynamically

---

## v1.0.6

### Tooltips
- Replaced BackdropTemplate with manual textures for tooltip skinning to avoid Blizzard `Backdrop.lua` taint errors on protected tooltips (world map POIs, quest tooltips, etc.)

---

## v1.0.5

### Missing Buffs
- **NEW:** Food buff tracking (Well Fed, Sated, etc.)
- **NEW:** Rogue Stealth tracking with icon display
- **NEW:** "Hide When Mounted" option for stance & spec buffs
- **NEW:** Druid Forms "Only Show in Combat" option

---

## v1.0.4

### Tooltips
- Fixed secretvalue error when skinning the tooltip

---

## v1.0.3

### Packaging
- Removed `.png` from the ignore list

---

## v1.0.2

### Misc
- Minor tweaks

---

## v1.0.1

### Core
- Fixed KitnEssentials import error

## v1.0.0 — Initial Release

---
### Combat
- Combat Timer, Combat Cross, Combat Res, Combat Texts, Pet Status Texts, Gateway Alert, Target Castbar, Focus Castbar, Range Checker, TimeSpiral, Cursor Circle, Recuperate

### Custom Buffs
- Buff Icons, Buff Bars, Personal Defensives, Personal Movement Buffs

### Quality of Life
- Automation, Copy Anything, Dragon Riding UI, Missing Buffs, Hunters Mark Missing, Hide ActionBars, CDM Racials Anchor

### Skinning
- Action Bars, Auras, Tooltips, Micro Menu, Blizzard Messages, Blizzard Mouseover, Blizzard Raid Manager, Details Backdrop, UI Cleanup

### GUI
- Full GUI with theme support, edit mode, and profile management
