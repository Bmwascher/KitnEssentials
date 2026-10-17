-- ╔══════════════════════════════════════════════════════════╗
-- ║  EncounterData.lua                                       ║
-- ║  Purpose: Curated cast-duration table for the Dungeon    ║
-- ║           Timers module, keyed by encounter ID then      ║
-- ║           spell ID.                                      ║
-- ╚══════════════════════════════════════════════════════════╝

-- Schema:
--   KE.EncounterData[encounterID] = {
--       name    = "Boss display name",
--       shortName = "Optional settings heading",
--       dungeon = "DungeonKey",
--       spells  = {
--           [spellID] = {
--               name            = "Spell display name",
--               castType        = "begincast"|"cast"|
--                                 "channel",
--               castDuration    = <seconds>,  -- optional
--               channelDuration = <seconds>,  -- optional
--               role            = "tank"|"heal"|
--                                 "mechanic"|"other"|
--                                 "kick"|"move",
--                                 -- kick = TANK + DPS
--                                 --   (interrupt duty)
--                                 -- move = HEAL + DPS
--                                 --   (spread/movement;
--                                 --    tank anchored)
--               display         = "bar"|"text",
--               displayText     = "DODGE"|...,
--                                 -- short curated label
--                                 -- shown instead of the
--                                 -- BigWigs spell name.
--                                 -- e.g. "TANK HIT",
--                                 -- "INTERRUPT",
--                                 -- "SPREAD". Fall back
--                                 -- to BigWigs name when
--                                 -- absent.
--               castDisplayText = "AOE"|...,
--                                 -- optional cast-phase
--                                 -- label/color swap.
--                                 -- When set, the bar
--                                 -- swaps to this text +
--                                 -- preset color when
--                                 -- the cast actually
--                                 -- starts. Lets a spell
--                                 -- show two cues — e.g.
--                                 -- "CC ADDS" during the
--                                 -- countdown then "AOE"
--                                 -- during the cast.
--               extendByChannel = true,
--                                 -- opt-in: extend the
--                                 -- bar by channelDuration
--                                 -- on top of castDuration
--                                 -- so the bar hits 0 at
--                                 -- end-of-channel. Use
--                                 -- for spells whose
--                                 -- effect lands at the
--                                 -- END of the channel
--                                 -- (e.g. adds spawn
--                                 -- after a 4s channel
--                                 -- finishes), NOT the
--                                 -- start. Default off —
--                                 -- channels normally
--                                 -- damage at zero.
--               disabled        = true,
--                                 -- curator-default
--                                 -- hard-disable. The
--                                 -- bar never renders
--                                 -- unless the user
--                                 -- explicitly enables
--                                 -- via the GUI (which
--                                 -- stores false in
--                                 -- db.SpellDisabled).
--                                 -- Use for spammable
--                                 -- abilities (kicks,
--                                 -- DoT-tick spells)
--                                 -- that would clutter
--                                 -- the screen by
--                                 -- default.
--               showAtSeconds   = <seconds>,
--                                 -- per-spell visibility
--                                 -- override. Hides the
--                                 -- bar until last N sec
--                                 -- of total lifetime.
--                                 -- Wins over the group
--                                 -- ShowAtSeconds slider.
--                                 -- 0 = force always
--                                 -- visible even when
--                                 -- group hides. Omit
--                                 -- to inherit group.
--               color           = { r, g, b },
--                                 -- curator-default RGB
--                                 -- color. Overrides the
--                                 -- displayText preset
--                                 -- color. Use for bars
--                                 -- that need a specific
--                                 -- hue not covered by
--                                 -- the preset palette.
--                                 -- User color override
--                                 -- still wins over this.
--               shieldColor     = { r, g, b }, -- shield-only default
--               sortAtEnd      = true,
--                                 -- push this entry to
--                                 -- the end of the spell
--                                 -- list in the GUI
--                                 -- (before phase rules).
--                                 -- Used for vulnerability
--                                 -- phase entries that
--                                 -- belong with phases
--                                 -- conceptually rather
--                                 -- than mixed in with
--                                 -- regular cast warnings
--               iconOverride   = <textureID|path>,
--                                 -- replace BigWigs's
--                                 -- supplied icon. Useful
--                                 -- when the spell's
--                                 -- default icon is
--                                 -- ambiguous (e.g.
--                                 -- a generic shadow
--                                 -- texture) and a more
--                                 -- recognizable icon
--                                 -- aids identification.
--                                 -- Accepts a texture
--                                 -- file ID or path.
--               forceDuration  = <seconds>,
--                                 -- override the BigWigs
--                                 -- duration with a
--                                 -- known-correct value.
--                                 -- Used for "amp" /
--                                 -- vulnerability bars
--                                 -- where LittleWigs's
--                                 -- hardcoded duration
--                                 -- doesn't match the
--                                 -- actual buff lifetime
--                                 -- (e.g. Backlash 20s
--                                 -- vs LW's 12.5s). Bar
--                                 -- self-drains over
--                                 -- forceDuration; we
--                                 -- ignore BigWigs's
--                                 -- StopBar so its early
--                                 -- end doesn't kill us.
--               postCastBar    = {
--                                   duration    = <s>,
--                                   display     = "bar"|
--                                                 "text",
--                                   displayText = ...,
--                                   iconOverride= <tex>,
--                                 },
--                                 -- follow-up bar that
--                                 -- spawns at a parent
--                                 -- bar's natural end.
--                                 -- Two trigger paths:
--                                 --  (a) parent has
--                                 --   castDuration → fires
--                                 --   when cast phase
--                                 --   ends (Nysarra Flare
--                                 --   → 17s BEAM).
--                                 --  (b) parent has no
--                                 --   castDuration →
--                                 --   fires on BigWigs's
--                                 --   StopBar at natural
--                                 --   countdown end (L'ura
--                                 --   Backlash → 19.5s
--                                 --   VULNERABILITY).
--                                 -- Use for buff/window
--                                 -- bars that follow a
--                                 -- cast when SPELL_AURA_
--                                 -- APPLIED is unreliable
--                                 -- (most boss-applied
--                                 -- auras in 12.0).
--                                 -- iconOverride wins
--                                 -- over the parent's
--                                 -- inherited icon when
--                                 -- set; useful when the
--                                 -- follow-up represents
--                                 -- a different visual
--                                 -- cue. Always shown to
--                                 -- everyone (no role).
--               phantomFollowupOf =
--                                 <parentSpellId>,
--               duration       = <s>,
--                                 -- top-level GUI entry
--                                 -- that opts out of the
--                                 -- BigWigs_Timer path
--                                 -- and instead spawns
--                                 -- when the parent's
--                                 -- BigWigs_StopBar fires
--                                 -- naturally (cast
--                                 -- finished = buff
--                                 -- applied). Use when
--                                 -- you want a follow-up
--                                 -- bar to have its own
--                                 -- configurable row in
--                                 -- the GUI (vs nesting
--                                 -- as the parent's
--                                 -- postCastBar which
--                                 -- hides under one row).
--                                 -- L'ura's 247816
--                                 -- (VULNERABILITY)
--                                 -- follows 1266001
--                                 -- (Backlash KNOCK).
--                                 -- Pairs naturally with
--                                 -- iconOverride/color/
--                                 -- displayText for the
--                                 -- follow-up's visuals.
--               spawnOnMessage = true,
--               duration       = <s>,
--               leadDelay      = <s>,  -- optional
--                                 -- BigWigs_Message-
--                                 -- driven spawn. Used
--                                 -- for vulnerability
--                                 -- bars whose trigger
--                                 -- is a non-cast event
--                                 -- (widget update,
--                                 -- boss emote) that
--                                 -- LittleWigs surfaces
--                                 -- via self:Message(
--                                 -- spellId, ...). When
--                                 -- BigWigs_Message
--                                 -- fires with this
--                                 -- spellId, we spawn a
--                                 -- bar of `duration`
--                                 -- seconds (optionally
--                                 -- after `leadDelay`
--                                 -- seconds, a prepare
--                                 -- phase before the
--                                 -- active window).
--                                 -- Use this when
--                                 -- SPELL_AURA_APPLIED
--                                 -- doesn't fire in 12.0
--                                 -- (most boss-applied
--                                 -- auras). Entry skips
--                                 -- BigWigs_Timer path.
--               shieldBar      = {
--                                   baseAmount = <number>,
--                                   displayText = ...,
--                                 },
--                                 -- opt-in absorb-tracker
--                                 -- bar for boss shield
--                                 -- channels (e.g.
--                                 -- Vordaza's Necrotic
--                                 -- Convergence). Shows
--                                 -- on a boss channel
--                                 -- start inside the
--                                 -- parent's watch window
--                                 -- and drains as the boss
--                                 -- takes damage. Max =
--                                 -- baseAmount × M+
--                                 -- multiplier. Uses the
--                                 -- parent's icon, font
--                                 -- and enable/role gate;
--                                 -- shieldColor defaults
--                                 -- to green. The user's
--                                 -- color override wins.
--                                 -- displayText is the
--                                 -- shield bar's label
--                                 -- (separate from the
--                                 -- parent's countdown
--                                 -- bar). Secret-safe —
--                                 -- absorb is read with
--                                 -- UnitGetTotalAbsorbs
--                                 -- (secret on hostile)
--                                 -- and passed only to
--                                 -- allowed-when-tainted
--                                 -- formatters.
--                                 -- Ends on the same
--                                 -- boss's channel stop
--                                 -- or interruptible
--                                 -- signal; its cleanup
--                                 -- cap is the row's
--                                 -- channelDuration, else
--                                 -- castDuration, else
--                                 -- 60, plus 2 s.
--               secondary       = {
--                                   role = ...,
--                                   display = ...,
--                                   displayText = ...,
--                                   color = { r, g, b },
--                                 },
--                                 -- optional second bar
--                                 -- spawned alongside
--                                 -- the primary on each
--                                 -- Timer event. Has its
--                                 -- own role gate, mode,
--                                 -- text, and color. Use
--                                 -- for spells that need
--                                 -- a tank-only bar AND
--                                 -- an everyone-text
--                                 -- (e.g. Orebreaker:
--                                 -- "TANK HIT" bar +
--                                 -- "FEET" text).
--               sound          = "<LSM sound key>",
--                                 -- curator-default
--                                 -- on-show audio cue.
--                                 -- LSM key for any
--                                 -- registered sound —
--                                 -- KitnEssentials's
--                                 -- bundled presets live
--                                 -- in Media\Sounds\ and
--                                 -- are registered in
--                                 -- Core\Globals.lua.
--                                 -- User override wins:
--                                 -- nil in db = play
--                                 -- this curated
--                                 -- default; "None" in
--                                 -- db = explicit mute;
--                                 -- other LSM key = user
--                                 -- pick. soundOnHide is
--                                 -- the analogous on-
--                                 -- hide field (rarely
--                                 -- used; on-show is the
--                                 -- primary cue).
--           },
--           ...
--       },
--       phases  = {
--           {
--               unit      = "boss1",  -- default boss1
--               threshold = 75,       -- HP% phase fires
--               lead      = 5,        -- alert window
--                                      --   (HP between
--                                      --   threshold and
--                                      --   threshold+lead
--                                      --   shows alert)
--               sound       = "...",  -- curator on-show
--               soundOnHide = "...",  -- curator on-hide
--                                      --   LSM keys; same
--                                      --   override rules
--                                      --   as spell.sound
--               endsAtStage = 2,      -- optional: hidden
--                                      --   once the
--                                      --   encounter's stage
--                                      --   (stageCue) reaches
--                                      --   this stage
--           },
--           ...
--       },
--               -- optional: HP%-driven "Phase Transition
--               -- X%" text bar.
--               -- Fires while unit HP is in
--               -- (threshold, threshold + lead]. Always
--               -- shown to everyone (no role filter).
--   }
--
-- Lookup at BigWigs_Timer time: O(1) by encounterID +
-- spellID. The BigWigs spellId we receive is the EVENT
-- spellId, NOT the hostile-cast spellId — they differ in
-- some cases (Barrage 1260643 vs. 1260648 cast).
--
-- Optional `bossOrder` field on an encounter overrides
-- the default encounterID-ascending sort. Use when an
-- older dungeon's encounterIDs don't reflect in-dungeon
-- boss order (e.g. Pit of Saron: 1999/2001/2000 sorts to
-- Garfrost/Tyrannus/Ick&Krick but actual order is
-- Garfrost/Ick&Krick/Tyrannus).
--
-- timerPolicy = "explicit" (optional, encounter-level):
-- switches this encounter to explicit-only Timer bindings
-- — a row binds only when its timerSource contract
-- validates; every other row in the encounter binds
-- nothing. Absent timerPolicy keeps the legacy per-row
-- logic above.
--
-- timerSource = { kind="Timer", isCooldown=true,
-- policy="estimated-impact", spanMode="remaining-only",
-- stopTolerance=<seconds > 0>,
-- collisionPolicy="refuse-unresolved-label" } (row-level,
-- required under timerPolicy="explicit"): requires a
-- finite castDuration >= 0 (an explicit 0 is required
-- curation whose cue ends at the provider deadline, not a
-- missing value) and forbids channelDuration,
-- forceDuration, postCastBar, phantomFollowupOf,
-- spawnOnMessage, shieldBar, secondary, castDisplayText,
-- and extendByChannel=true.
--
-- timerSource = { kind="Sequel", parent=<spellId>,
-- after=<seconds >= 0> } (row-level, explicit only): a
-- cue with its own settings row, scheduled once from the
-- parent row's timeline-finished anchor and ending
-- after + castDuration seconds past it. The parent must
-- anchor without castConfirm, and one parent takes one
-- child. Never a publisher key; the forbidden fields
-- above apply.
--
-- timerSource.pausedStop = "retire" (row-level, optional,
-- requires anchor = "timeline-finished"): a provider stop
-- whose correlated timeline event reads Paused retires the
-- cue at any elapsed time before its anchor. For a provider
-- that stops a bar on pause and never resumes it.
--
-- timerSource.canceledStop = { stage=<n > 0>, within=<s in
-- (0, 1]> } (row-level, optional, requires anchor =
-- "timeline-finished", no castConfirm, pausedStop or
-- queueAfter): a correlated Canceled stop with more than 0
-- and at most `within` seconds left, on an occurrence
-- published and stopped while the boss module's GetStage()
-- returns `stage`, keeps the cue silently to its original
-- estimated end. It never anchors; later stops, pauses and
-- resumes are ignored. The row may not own its expiry,
-- parent a shield or end a cue.
--
-- timerSource.pullReceipt = true (row-level, optional, no
-- anchor): a receipt published by the provider's own
-- start handler before KE's encounter start is held and
-- replayed by that start, as for a phase cue below.
--
-- timerSource.castMatch = { spells = { <cast spell ID>, ... },
-- within = <seconds in (0, 5]> } (row-level, optional; needs
-- castDuration > 0 and none of castConfirm, pausedStop,
-- queueAfter, canceledStop, retainEarlyFinished,
-- suppressConcurrentRestart, holdOverlapping, replacement,
-- pullReceipt or waitAfter): from its forecast zero, or from
-- its qualified anchor, the occurrence is re-timed from the
-- start of one boss-unit cast of a listed spell, seen as a
-- readable START that the same unit's current cast confirms
-- (same spell, same cast bar, readable times); the extension,
-- with any user offset, runs from that start. A provider stop
-- whose exact timeline event is not Active or Finished closes
-- the occurrence to casts. `within` needs anchor =
-- "timeline-finished" and is otherwise forbidden: at the
-- anchor, Soon replaces the countdown for up to `within`
-- seconds when each listed spell reads as not secret on some
-- boss unit, and an unmatched wait ends silently. The row may
-- not parent, end or be gated.
-- castMatch.endpoint = "cast-end" (unanchored rows only): a
-- matched occurrence ends at that cast's readable end plus the
-- user offset instead of the curated extension. A pushback of
-- the same cast on the same unit and cast bar moves the end; an
-- interrupt, failure or early stop of it ends the occurrence
-- silently.
--
-- timerSource.waitAfter = <seconds in (0, 5]> (row-level,
-- optional, no anchor, castConfirm or queueAfter): past forecast zero the
-- occurrence shows Soon until the provider stops its label or
-- the wait ends silently.
--
-- timerSource.soonOnHold = true (row-level, optional, needs
-- anchor = "timeline-finished", no holdOverlapping): the
-- queue hold shows Soon instead of a blank countdown.
--
-- windMap = { wind = <spellID>, spit = <spellID> } (encounter-
-- level, optional): the two anchored explicit Timer rows the
-- optional wind map shows as cards, its wind sides from the
-- first. The wind row's spell is also the boss1 cast the map
-- confirms: its side moves one step only once that cast
-- succeeds. During that encounter the map also reads
-- boss1-boss5 for presence and death: any readable boss death
-- or lost boss token drops the held wind and its step for the
-- rest of the encounter, leaving only live published winds.
--
-- stageCue = { spellID = <spellID>, duration = <seconds>,
-- stage = <n> } (encounter-level, optional): the encounter
-- starts in stage 1, and a provider Timer receipt for that
-- explicit Timer row, whose duration rounds to `duration` at
-- one decimal, starts `stage`. The stage only moves forward
-- and resets with the encounter; it ends a phase rule's
-- endsAtStage and sets the wind map's placement phase.
--
-- phaseCues = { <name> = { ... } } (encounter-level,
-- explicit only): a window with its own settings row, keyed
-- "cue:<encounterId>:<name>" (name: lowercase letters,
-- digits, underscores). Requires name, iconOverride and one
-- source:
--   { kind="Message", key=<id> }   each provider Message;
--     requires duration, optional leadDelay, maxPerPull
--     (admitted Messages per pull that may start one) and
--     prepareText (needs a positive leadDelay).
--     ordinals=<whole 2..9> (optional): the label is
--     followed by the n whose provider count text for n
--     of that total equals the Message; refused with
--     leadDelay, maxPerPull, prepareText, hidesForecasts,
--     endedText or messageCount.
--     ordinalSounds={...} optionally supplies one sound per
--     ordinal; sound remains the default outside a delivery.
--     messageCount=<whole 1..9> (optional): only the
--     Message equal to the provider's count text for that
--     number starts the cue; any other is refused before
--     the cap.
--     pullReceipt=true (optional): a Message published by
--     the provider's own start handler before KE's
--     encounter start is held, dropped if its module stops
--     all bars or disables first, and replayed in arrival
--     order by that encounter's start within half a second.
--   { kind="Timer", key=<id>, isCooldown=false }   each
--     provider non-cooldown Timer; the published time is
--     the window, so no duration.
--   { kind="Sequel", parent=<spellId>, after=<s >= 0> }
--     from the parent row's timeline-finished anchor;
--     requires duration.
-- endedText + endedDuration (Message or Timer source, both
-- or neither): text shown after the window's natural end.
-- endedColor = { r, g, b } (needs endedText): the ended
-- text's color, ahead of any user color for the cue.
-- endsOnAnchor = <spellId> (Sequel only): that explicit
-- anchored row's qualified anchor ends the cue silently;
-- the cue is not planned while the row's own Sequel cue
-- window is live, and drawing that window ends it.
-- role, display, displayText, color, sound, soundOnHide,
-- showAtSeconds and disabled mean what they mean on a row.
-- Any other field refuses the cue; one source may be named
-- by one cue only. A cue has no time offset.
--
-- auraSounds = { { spellID=<aura id>, trigger="added" |
-- "removed" | "increased", unit="player" | "boss",
-- name=<row name>, sound=<sound name>, disabled=<bool,
-- optional> }, ... } (encounter-level): sounds the client
-- plays when the aura lands on the unit, leaves it, or
-- ("increased") gains a stack on it. Registered for the whole
-- dungeon while inside it; the encounter is the settings
-- page grouping only. "boss" registers boss1 to boss5.
-- Row key "aura:<encounterId>:<spellID>:<trigger>".
--
-- shields = { { parent=<spellId>, baseAmount=<number > 0>,
-- timeout=<seconds > 0>, displayText=<string, optional> } }
-- (encounter-level, explicit only): a boss absorb bar shown on
-- a boss channel start inside the parent's windows: from 1 s
-- before the parent row's forecast for 5 s, and for 2 s after
-- its qualified timeline-finished anchor; the parent must be an
-- accepted
-- Timer row with anchor = "timeline-finished" and no
-- castConfirm. The total is baseAmount times the keystone
-- multiplier, an estimate the text marks with "~". The bar
-- ends on that boss's channel stop or interruptible signal;
-- timeout is a cleanup cap, not a channel length. Any other
-- field refuses the entry, and two entries naming one parent
-- install neither.

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

KE.EncounterData = KE.EncounterData or {}

-- ╔══════════════════════════════════════════════════════════╗
-- ║  AlgetharAcademy                                         ║
-- ╚══════════════════════════════════════════════════════════╝

KE.EncounterData[2562] = {
    name = "Vexamus",
    dungeon = "AlgetharAcademy",
    spells = {
        -- Orbs take ~4s to start spawning after the cast ends — castDuration=4 extends the bar
        -- into a 4s "cast phase" tail so the SOAK cue stays visible until the soak moment.
        [386544] = { name = "Arcane Orbs",       castType = "cast",      castDuration = 4,                   role = "other",                     displayText = "SOAK",     sound = "Soaks" },
        [385958] = { name = "Arcane Expulsion",  castType = "begincast", castDuration = 4,                   role = "tank",     display = "bar", displayText = "TANK HIT" },
        [386173] = { name = "Mana Bombs",        castType = "begincast", castDuration = 2.5,                 role = "other",                     displayText = "DROPS",    sound = "Drop" },
        [388537] = { name = "Arcane Fissure",    castType = "begincast", castDuration = 3,                   role = "mechanic",                  displayText = "AOE + FEET", sound = "Aoe And Dance" },
    },
}

KE.EncounterData[2563] = {
    name = "Overgrown Ancient",
    dungeon = "AlgetharAcademy",
    spells = {
        [388544] = { name = "Barkbreaker",  castType = "begincast", castDuration = 1,                      role = "tank",     display = "bar", displayText = "TANK HIT" },
        [388796] = { name = "Germinate",    castType = "cast",                       channelDuration = 4,  role = "other",                     displayText = "STACK",    sound = "Stack" },
        [388623] = { name = "Branch Out",   castType = "begincast", castDuration = 2.5,                    role = "other",                     displayText = "ADD",      sound = "Add" },
        [388923] = { name = "Burst Forth",  castType = "begincast", castDuration = 3,                      role = "other",                     displayText = "AOE",      sound = "AoE" },
    },
}

KE.EncounterData[2564] = {
    name = "Crawth",
    dungeon = "AlgetharAcademy",
    spells = {
        [376997] = { name = "Savage Peck",       castType = "begincast", castDuration = 3,                   role = "tank",     display = "bar", displayText = "TANK HIT" },
        [377004] = { name = "Deafening Screech", castType = "begincast", castDuration = 2.5,                 role = "other",                     displayText = "AOE",      sound = "Stop Casting" },
        [377034] = { name = "Overpowering Gust", castType = "begincast", castDuration = 3,                   role = "other",                     displayText = "FRONTAL"  },
        -- LittleWigs's SPELL_AURA_APPLIED handler for aura 376781 doesn't fire in 12.0 (same root cause
        -- as L'ura's Backlash). Instead we spawn off LittleWigs's reliable widget-driven Message(376448),
        -- which fires from the UPDATE_UI_WIDGET handler when goal-tracker widget 4183 reaches barValue=3.
        -- A 2s lead-in precedes the 12s active phase.
        [376448] = { name = "Vulnerability Phase", spawnOnMessage = true, duration = 12, leadDelay = 2,      role = "other",    display = "bar",  displayText = "VULNERABILITY", iconOverride = 135821, showAtSeconds = 0, sortAtEnd = true, sound = "Dmg Amp" },
    },
    -- HP-threshold phase bars are visual-only, no audio cue.
    -- 12.0's secret-value system prevents an
    -- addon-observable HP crossing trigger, so the show sound on bar
    -- creation fired at engage (HP=100%) rather than at the threshold —
    -- text-only sidesteps that without per-encounter event proxies.
    phases = {
        { unit = "boss1", threshold = 75, lead = 5 },
        { unit = "boss1", threshold = 45, lead = 5 },
    },
}

KE.EncounterData[2565] = {
    name = "Echo of Doragosa",
    dungeon = "AlgetharAcademy",
    spells = {
        -- Disabled by default: random single-target hit, fires frequently — opt-in via GUI
        [373326]  = { name = "Arcane Missiles", castType = "cast",                                           role = "other",                                       disabled = true },
        [1282251] = { name = "Astral Blast",    castType = "begincast", castDuration = 3,                    role = "tank",     display = "bar", displayText = "TANK HIT" },
        -- castDuration=1.5 assumed — live verification still pending (role=heal so filtered for DAMAGER logs, can't see in this run).
        [374343]  = { name = "Energy Bomb",     castType = "begincast", castDuration = 1.5,                  role = "heal",                      displayText = "DISPEL",   sound = "Dispel" },
        -- The pull effect fires AT the end of BigWigs's predictive countdown (= start of the boss
        -- cast). No castDuration extension because the pull is instantaneous from the player's POV
        -- — we don't want the bar lingering past the moment of effect. No showAtSeconds either:
        -- visibility is left to the user's group "Reveal at" slider, since there's no mechanical
        -- reason this specific bar should override the user's global preference.
        [388822]  = { name = "Power Vacuum",    castType = "begincast",                                      role = "other",                     displayText = "PULL",     sound = "Pull" },
    },
}

-- ╔══════════════════════════════════════════════════════════╗
-- ║  MagistersTerrace                                        ║
-- ╚══════════════════════════════════════════════════════════╝

KE.EncounterData[3071] = {
    name = "Arcanotron Custos",
    dungeon = "MagistersTerrace",
    spells = {
        [474496]  = { name = "Repulsing Slam",     castType = "begincast", castDuration = 2.5,                     role = "tank",     display = "bar", displayText = "TANK HIT" },
        [1214081] = { name = "Arcane Expulsion",   castType = "begincast", castDuration = 3,                       role = "other",                displayText = "AOE",      sound = "Knockback" },
        [1214032] = { name = "Ethereal Shackles",  castType = "cast",                                              role = "heal",                 displayText = "DISPEL",   sound = "Dispel" },
        [474345]  = { name = "Refueling Protocol", castType = "begincast", castDuration = 3,   channelDuration = 20, role = "other",                displayText = "AMP",      sound = "Dmg Amp" },
    },
}

KE.EncounterData[3072] = {
    name = "Seranel Sunlash",
    dungeon = "MagistersTerrace",
    spells = {
        [1225787] = { name = "Runic Mark",         castType = "begincast", castDuration = 3,                       role = "other",                     displayText = "MARKS",    sound = "Spread" },
        [1224903] = { name = "Suppression Zone",   castType = "begincast", castDuration = 3,                       role = "mechanic",                  displayText = "CLEAR",    sound = "Clear" },
        [1248689] = { name = "Hastening Ward",     castType = "cast",                                              role = "tank",     display = "bar", displayText = "BOSS BUFFED" },
        [1225193] = { name = "Wave of Silence",    castType = "begincast", castDuration = 5,                       role = "other",                     displayText = "HIDE",     sound = "Hide" },
    },
}

KE.EncounterData[3073] = {
    name = "Gemellus",
    dungeon = "MagistersTerrace",
    spells = {
        [1223847] = { name = "Triplicate",         castType = "begincast", castDuration = 2.5,                     role = "other",    displayText = "SPLIT" },
        [1284954] = { name = "Cosmic Sting",       castType = "begincast", castDuration = 4,                       role = "other",    displayText = "DROPS", sound = "Drop" },
        [1253709] = { name = "Neural Link",        castType = "begincast", castDuration = 2,                       role = "other",    displayText = "CLEAR", sound = "Clear" },
        [1224299] = { name = "Astral Grasp",       castType = "begincast", castDuration = 4,   channelDuration = 8, role = "other",    displayText = "PULL",  sound = "Pull" },
    },
    -- HP-threshold phase bar is visual-only — see Crawth note above for why.
    phases = {
        { unit = "boss1", threshold = 50, lead = 5 },
    },
}

KE.EncounterData[3074] = {
    name = "Degentrius",
    dungeon = "MagistersTerrace",
    spells = {
        [1280113] = { name = "Hulking Fragment",      castType = "begincast", castDuration = 3,                    role = "tank",     display = "bar", displayText = "TANK HIT" },
        [1215897] = { name = "Devouring Entropy",     castType = "cast",                                           role = "other",                     displayText = "SPREAD",   sound = "Spread" },
        [1215087] = { name = "Unstable Void Essence", castType = "begincast", castDuration = 2.5,                  role = "other",                     displayText = "SOAK",     sound = "Soak" },
    },
}

-- ╔══════════════════════════════════════════════════════════╗
-- ║  MaisaraCaverns                                          ║
-- ╚══════════════════════════════════════════════════════════╝

KE.EncounterData[3212] = {
    name = "Muro'jin and Nekraxx",
    dungeon = "MaisaraCaverns",
    spells = {
        [1266480] = { name = "Flanking Spear",   castType = "begincast", castDuration = 2.5, role = "tank",     display = "bar", displayText = "TANK HIT" },
        [1243900] = { name = "Fetid Quillstorm", castType = "begincast", castDuration = 3,   role = "other",                     displayText = "FEET",    sound = "Feet" },
        [1260731] = { name = "Freezing Trap",    castType = "begincast", castDuration = 2,   role = "mechanic",                  displayText = "FEET",    sound = "Feet" },
        [1260643] = { name = "Barrage",          castType = "cast",      channelDuration = 5, role = "move",                  displayText = "FRONTAL", sound = "Frontal" },
        [1246666] = { name = "Infected Pinions", castType = "begincast", castDuration = 1.5,  role = "other",                 displayText = "AOE"     },
        [1249479] = { name = "Carrion Swoop",    castType = "begincast", castDuration = 4.5,  role = "mechanic",              displayText = "DODGE",   sound = "Dodge" },
    },
}

KE.EncounterData[3213] = {
    name = "Vordaza",
    dungeon = "MaisaraCaverns",
    spells = {
        [1251554] = { name = "Drain Soul",           castType = "begincast", castDuration = 1,   channelDuration = 4,   role = "tank",     display = "bar", displayText = "TANK HIT"     },
        [1252054] = { name = "Unmake",               castType = "begincast", castDuration = 2.5, channelDuration = 4.5, role = "other",                     displayText = "FRONTAL",      sound = "Frontal" },
        [1251204] = { name = "Wrest Phantoms",       castType = "cast",                          channelDuration = 4,   role = "mechanic", extendByChannel = true, displayText = "ADDS",  sound = "Adds" },
        -- Necrotic Convergence is a 60s intermission channel where the boss
        -- casts an absorb shield (UnitGetTotalAbsorbs, secret on hostile units).
        -- Two bars surface for one mechanic: the BigWigs-driven INTERMISSION
        -- countdown (channelDuration=60) and an opt-in absorb-tracking shieldBar
        -- that drains as the team breaks the shield. M+ scaling on baseAmount
        -- is applied automatically by DungeonTimers.
        [1250708] = { name = "Necrotic Convergence", castType = "channel",                       channelDuration = 60,  role = "other",                     displayText = "INTERMISSION", sound = "Intermission",
                      shieldBar = { baseAmount = 1160814, displayText = "SHIELD" } },
    },
}

KE.EncounterData[3214] = {
    name = "Rak'tul, Vessel of Souls",
    dungeon = "MaisaraCaverns",
    spells = {
        [1251023] = { name = "Spiritbreaker",      castType = "channel",                       channelDuration = 4.5, role = "tank",     display = "bar", displayText = "TANK HIT"     },
        [1252676] = { name = "Crush Souls",        castType = "begincast", castDuration = 4.5,                        role = "mechanic", displayText = "TOTEMS",       sound = "Totem" },
        [1253788] = { name = "Soulrending Roar",   castType = "begincast", castDuration = 3,                          role = "mechanic", displayText = "INTERMISSION", sound = "Intermission" },
    },
}

-- ╔══════════════════════════════════════════════════════════╗
-- ║  NexusPointXenas                                         ║
-- ╚══════════════════════════════════════════════════════════╝

KE.EncounterData[3328] = {
    name = "Chief Corewright Kasreth",
    dungeon = "NexusPointXenas",
    spells = {
        [1251579] = { name = "Leyline Array",          castType = "cast",      castDuration = 6,                   role = "other",  display = "bar",   displayText = "Lines Spawning", color = { 0.302, 0.800, 1.0 } }, -- #4dccff
        [1251772] = { name = "Reflux Charge",          castType = "begincast", castDuration = 2.1,                 role = "other",  display = "bar",   displayText = "Clear Lines",   color = { 1.0, 0.302, 0.800 } }, -- #ff4dcc
        [1264048] = { name = "Flux Collapse",          castType = "cast",      castDuration = 3,                   role = "other",                     displayText = "FEET",          sound = "Feet" },
        -- Disabled by default: opt-in heal-only AOE warning
        [1257509] = { name = "Corespark Detonation",   castType = "begincast", castDuration = 5,                   role = "heal",                      displayText = "AOE",            disabled = true },
    },
}

KE.EncounterData[3332] = {
    name = "Corewarden Nysarra",
    dungeon = "NexusPointXenas",
    spells = {
        [1247937] = { name = "Umbral Lash",           castType = "begincast", castDuration = 0.8,                       role = "tank",     display = "bar", displayText = "TANK HIT" },
        [1249014] = { name = "Eclipsing Step",        castType = "begincast", castDuration = 2.5, channelDuration = 2,  role = "move",                      displayText = "SPREAD",   sound = "Spread" },
        [1252703] = { name = "Null Vanguard",         castType = "cast",      castDuration = 6,                         role = "other",                     displayText = "ADDS",     sound = "Adds" },
        -- castDuration=10 is rough — Lightscar Flare timing varies in-game; adjust per future logs.
        -- postCastBar: 17s damage-amp window after the cast finishes — boss channels a beam that buffs
        -- player damage for everyone standing in it. Synthesized bar (no separate BigWigs Timer fires
        -- for the channel) — spawns at cast-phase end, doesn't fire on cast interrupts. Bundled into
        -- Flare's entry rather than split as a `phantomFollowupOf` row because the beam channel has
        -- no clean spellID — detected by watching for a level-92 mob's
        -- UNIT_SPELLCAST_CHANNEL_START, not a curated ID we could surface in the GUI list.
        [1264439] = { name = "Lightscar Flare",       castType = "cast",      castDuration = 10,                        role = "other",                     displayText = "AMP",      sound = "Dmg Amp",
            postCastBar = { duration = 17, display = "bar", displayText = "BEAM", iconOverride = 612098 } },
        -- Disabled by default: BigWigs fires Timer but the spell may not actually exist in-game.
        [1271684] = { name = "Devour the Unworthy",   castType = "begincast", castDuration = 3.4, channelDuration = 5,  role = "other",                     displayText = "AOE",     disabled = true },
    },
}

KE.EncounterData[3333] = {
    name = "Lothraxion",
    dungeon = "NexusPointXenas",
    spells = {
        [1253950] = { name = "Searing Rend",         castType = "begincast", castDuration = 3,                     role = "tank",     display = "bar", displayText = "TANK HIT" },
        [1253855] = { name = "Brilliant Dispersion", castType = "begincast", castDuration = 4,                     role = "other",                     displayText = "DROPS",    sound = "Drop" },
        [1255531] = { name = "Flicker",              castType = "cast",                                            role = "other",                     displayText = "DODGE",    sound = "Dodge" },
        [1257595] = { name = "Divine Guile",         castType = "begincast", castDuration = 7,                     role = "other",                     displayText = "Minigame", sound = "Intermission" },
    },
}

-- ╔══════════════════════════════════════════════════════════╗
-- ║  PitOfSaron                                              ║
-- ╚══════════════════════════════════════════════════════════╝

KE.EncounterData[1999] = {
    name = "Forgemaster Garfrost",
    dungeon = "PitOfSaron",
    bossOrder = 1,
    spells = {
        [1261299] = { name = "Throw Saronite",   castType = "begincast", castDuration = 2,   channelDuration = 6,   role = "other",  display = "bar", displayText = "Drop Ore",   sound = "Drop", color = { 0.7725, 0.4980, 0.1176 } }, -- #c57f1e
        -- Primary "FEET" (everyone, text) so the GUI preview shows the broadly-relevant cue.
        -- Secondary "TANK HIT" (tank-only, bar) renders alongside in-game for the tank.
        [1261546] = { name = "Orebreaker",       castType = "begincast", castDuration = 4.5,                        role = "other",                   displayText = "FEET",       sound = "Feet",
                                                  secondary = { role = "tank", display = "bar", displayText = "TANK HIT" } },
        [1262029] = { name = "Glacial Overload", castType = "begincast", castDuration = 5,   channelDuration = 3.5, role = "other",                   displayText = "HIDE",       sound = "Hide" },
        [1261847] = { name = "Cryostomp",        castType = "begincast", castDuration = 2.5,                        role = "other",                   displayText = "AOE + FEET", sound = "Aoe And Dance" },
    },
}

KE.EncounterData[2001] = {
    name = "Ick & Krick",
    dungeon = "PitOfSaron",
    bossOrder = 2,
    spells = {
        [1264287] = { name = "Blight Smash",     castType = "begincast", castDuration = 4,                          role = "tank",     display = "bar", displayText = "TANK HIT" },
        [1264336] = { name = "Plague Expulsion", castType = "begincast", castDuration = 2.5,                        role = "move",                      displayText = "AOE + FEET", sound = "Aoe And Dance" },
        [1264027] = { name = "Shade Shift",      castType = "begincast", castDuration = 4,                          role = "other",                     displayText = "ADDS",       sound = "Adds" },
        [1264363] = { name = "Get 'Em, Ick!",    castType = "begincast", castDuration = 4,                          role = "move",                      displayText = "FIXATES",    sound = "Fixate Incoming" },
    },
}

KE.EncounterData[2000] = {
    name = "Scourgelord Tyrannus",
    dungeon = "PitOfSaron",
    bossOrder = 3,
    spells = {
        [1262745] = { name = "Rime Blast",          castType = "begincast", castDuration = 6,                         role = "move",                      displayText = "CLEAR",   sound = "Clear" },
        [1262582] = { name = "Scourgelord's Brand", castType = "begincast", castDuration = 2.5,                       role = "tank",     display = "bar", displayText = "TANK HIT" },
        [1263756] = { name = "Death's Grasp",       castType = "cast",                          channelDuration = 6,  role = "other",                     displayText = "FEET",    sound = "Feet" },
        [1263406] = { name = "Army of the Dead",    castType = "begincast", castDuration = 5,                         role = "other",                     displayText = "ADDS",    sound = "Adds" },
        [1276948] = { name = "Ice Barrage",         castType = "cast",                          channelDuration = 4.5, role = "other",                     displayText = "FEET",    sound = "Feet" },
        [1276648] = { name = "Bone Infusion",       castType = "begincast", castDuration = 3,                         role = "other",                     displayText = "AOE",     sound = "AoE" },
    },
}

-- ╔══════════════════════════════════════════════════════════╗
-- ║  SeatOfTriumvirate                                       ║
-- ╚══════════════════════════════════════════════════════════╝

KE.EncounterData[2065] = {
    name = "Zuraal",
    dungeon = "SeatOfTriumvirate",
    spells = {
        [1263440] = { name = "Void Slash",     castType = "cast",                        channelDuration = 1.5, role = "tank",     display = "bar", displayText = "TANK HIT"  },
        [1263282] = { name = "Decimate",       castType = "begincast", castDuration = 5,                        role = "other",    display = "bar", displayText = "DROP POOL", sound = "Drop", color = { 0.365, 0.082, 0.773 } }, -- #5d15c5
        [1268916] = { name = "Null Palm",      castType = "begincast", castDuration = 2.5,                      role = "other",                     displayText = "FRONTAL",   sound = "Frontal" },
        [1263399] = { name = "Oozing Slam",    castType = "begincast", castDuration = 3,                        role = "other",                     displayText = "AOE",       sound = "AoE" },
        [1263297] = { name = "Crashing Void",  castType = "begincast", castDuration = 4,                        role = "other",                     displayText = "CC ADDS",   sound = "CC", castDisplayText = "AOE" },
    },
}

KE.EncounterData[2066] = {
    name = "Saprish",
    dungeon = "SeatOfTriumvirate",
    spells = {
        [245742]  = { name = "Shadow Pounce",  castType = "cast",                                          role = "other",    display = "bar", displayText = "Cat Jumping", color = { 0.769, 0.169, 0.169 } }, -- #c42b2b
        [1248219] = { name = "Void Bomb",      castType = "cast",                                          role = "other",                     displayText = "FEET",        sound = "Feet" },
        [1280065] = { name = "Phase Dash",     castType = "cast",                                          role = "mechanic",                  displayText = "CLEAR",       sound = "Clear" },
        [1263523] = { name = "Overload",       castType = "begincast", castDuration = 4,                   role = "other",                     displayText = "AOE",         sound = "AoE" },
    },
}

KE.EncounterData[2067] = {
    name = "Viceroy Nezhar",
    dungeon = "SeatOfTriumvirate",
    spells = {
        -- Disabled by default: spammable kick target (24 fires per ~3 min). Opt-in via GUI.
        [244750]  = { name = "Mind Blast",          castType = "begincast", castDuration = 2,                   role = "kick",                      displayText = "KICK",         sound = "Kick", disabled = true },
        [1277358] = { name = "Gates of the Abyss",  castType = "cast",                                          role = "other",  display = "bar",   displayText = "ORB SPAWNING",  color = { 1.0, 0.302, 0.800 } }, -- #ff4dcc
        [1263542] = { name = "Mass Void Infusion",  castType = "begincast", castDuration = 2, channelDuration = 5, role = "other",                  displayText = "SUCC",         sound = "Defensive" },
        [1263538] = { name = "Umbral Tentacles",    castType = "begincast", castDuration = 3,                   role = "other",                     displayText = "ADDS",         sound = "Adds" },
        [1263528] = { name = "Repulse",             castType = "begincast", castDuration = 2,                   role = "other",                     displayText = "KNOCK",        sound = "Knockback" },
    },
}

KE.EncounterData[2068] = {
    name = "L'ura",
    dungeon = "SeatOfTriumvirate",
    spells = {
        [1265421] = { name = "Dirge of Despair",            castType = "begincast", castDuration = 4,                   role = "other",                  displayText = "AOE",       sound = "AoE" },
        [1264196] = { name = "Disintegrate",                castType = "begincast", castDuration = 3, channelDuration = 5, role = "other",               displayText = "DANCE",     sound = "Dance" },
        [1265463] = { name = "Discordant Beam",             castType = "begincast", castDuration = 7,                   role = "other",                  displayText = "AIM BEAMS", sound = "Clear" },
        [1265689] = { name = "Grim Chorus",                 castType = "begincast", castDuration = 5.5,                 role = "other",                  displayText = "FEET",      sound = "Feet" },
        -- Symphony of the Eternal Night is the intermission/phase-transition.
        [1266003] = { name = "Symphony of the Eternal Night", castType = "begincast", castDuration = 10,                role = "other",                  displayText = "AMP",       sound = "Intermission" },
        [1266001] = { name = "Backlash", castType = "cast", role = "other", displayText = "KNOCK", sound = "Knockback" },
        -- LittleWigs's SPELL_AURA_APPLIED handler for aura 247816 doesn't fire in 12.0
        -- (confirmed via in-game log — Bar message never arrived). Instead this entry
        -- spawns when 1266001's BigWigs_StopBar fires naturally (cast finished = buff
        -- applied). LittleWigs drives that StopBar via ENCOUNTER_TIMELINE_EVENT_*,
        -- a reliable Blizzard API. The active phase measures ~19.5s -- second-hand,
        -- not re-timed in game here -- rounded up to the 20s duration below.
        [247816]  = { name = "Vulnerability Phase", phantomFollowupOf = 1266001, duration = 20, role = "other", display = "bar", displayText = "VULNERABILITY", iconOverride = 4914666, showAtSeconds = 0, sortAtEnd = true, sound = "Dmg Amp" },
    },
}

-- ╔══════════════════════════════════════════════════════════╗
-- ║  Skyreach                                                ║
-- ╚══════════════════════════════════════════════════════════╝

KE.EncounterData[1698] = {
    name = "Ranjit",
    dungeon = "Skyreach",
    spells = {
        [1252690] = { name = "Gale Surge",     castType = "begincast", castDuration = 3,                       role = "other",    displayText = "DROPS",   sound = "Drop" },
        [153757]  = { name = "Fan of Blades",  castType = "begincast", castDuration = 2,                       role = "mechanic", displayText = "AOE",     sound = "AoE" },
        [1258152] = { name = "Wind Chakram",   castType = "begincast", castDuration = 3,                       role = "other",    displayText = "FRONTAL", sound = "Frontal" },
        [156793]  = { name = "Chakram Vortex", castType = "begincast", castDuration = 3,                       role = "mechanic", displayText = "DODGE",   sound = "Dodge" },
    },
}

KE.EncounterData[1699] = {
    name = "Araknath",
    dungeon = "Skyreach",
    spells = {
        [154110] = { name = "Fiery Smash", castType = "begincast", castDuration = 3,                   role = "tank",     display = "bar", displayText = "TANK HIT" },
        -- Energize cast finishes ~7s before the soakable line actually spawns; extend the bar
        -- so it hits zero at line-spawn moment (the actionable cue), not at cast-end.
        [154162] = { name = "Energize",    castType = "cast",      castDuration = 7,                   role = "mechanic",                  displayText = "SOAK",    sound = "Soaks" },
        [154135] = { name = "Supernova",   castType = "begincast", castDuration = 4,                   role = "other",                     displayText = "AOE",     sound = "AoE" },
    },
}

KE.EncounterData[1700] = {
    name = "Rukhran",
    dungeon = "Skyreach",
    spells = {
        [1253519] = { name = "Burning Claws",   castType = "begincast", castDuration = 3,                       role = "tank",     display = "bar", displayText = "TANK HIT" },
        [1253510] = { name = "Sunbreak",        castType = "begincast", castDuration = 3,                       role = "mechanic",                  displayText = "ADD",     sound = "Add" },
        [159382]  = { name = "Searing Quills",  castType = "begincast", castDuration = 5,   channelDuration = 3, role = "mechanic",                  displayText = "HIDE",    sound = "Hide" },
    },
}

KE.EncounterData[1701] = {
    name = "High Sage Viryx",
    dungeon = "Skyreach",
    spells = {
        [1253538] = { name = "Scorching Ray",  castType = "cast",                                              role = "heal",                     displayText = "AOE",  sound = "AoE" },
        -- Disabled by default: spammable interrupt, opt-in via GUI.
        [154396]  = { name = "Solar Blast",    castType = "begincast", castDuration = 3,                       role = "other",    disabled = true, displayText = "KICK", sound = "Kick" },
        [153954]  = { name = "Cast Down",      castType = "cast",                                              role = "mechanic",                  displayText = "ADD",  sound = "Add" },
        [1253840] = { name = "Lens Flare",     castType = "begincast", castDuration = 3,                       role = "mechanic",                  displayText = "FEET", sound = "Feet" },
    },
}

-- ╔══════════════════════════════════════════════════════════╗
-- ║  Windrunner Spire                                        ║
-- ╚══════════════════════════════════════════════════════════╝

KE.EncounterData[3056] = {
    name = "Emberdawn",
    dungeon = "WindrunnerSpire",
    spells = {
        [466556] = { name = "Flaming Updraft", castType = "begincast", castDuration = 1.5,                       role = "mechanic",               displayText = "DROPS",   sound = "Drop" },
        [466064] = { name = "Searing Beak",    castType = "begincast", castDuration = 3,                         role = "tank",  display = "bar", displayText = "TANK HIT" },
        [465904] = { name = "Burning Gale",    castType = "begincast", castDuration = 3,   channelDuration = 18, role = "other",                  displayText = "DANCE",   sound = "Dance" },
    },
}

KE.EncounterData[3057] = {
    name = "Derelict Duo",
    dungeon = "WindrunnerSpire",
    spells = {
        [472745] = { name = "Splattering Spew",    castType = "begincast", castDuration = 4,                      role = "other",                  displayText = "SPREAD",  sound = "Spread" },
        [472888] = { name = "Bone Hack",           castType = "begincast", castDuration = 2,  channelDuration = 3, role = "tank",  display = "bar", displayText = "TANK HIT" },
        [474105] = { name = "Curse of Darkness",   castType = "begincast", castDuration = 4,                      role = "other",                  displayText = "ADDS",    sound = "Dispel" },
        -- castDuration=7 covers the follow-on Heaving Yank (BigWigs only fires Timer for Shriek).
        [472736] = { name = "Debilitating Shriek", castType = "begincast", castDuration = 7,                      role = "other",                  displayText = "HOOK",    showAtSeconds = 10 },
    },
}

KE.EncounterData[3058] = {
    name = "Commander Kroluk",
    dungeon = "WindrunnerSpire",
    spells = {
        [467620]  = { name = "Rampage",            castType = "begincast", castDuration = 2,   channelDuration = 5, role = "tank",     display = "bar", displayText = "TANK HIT" },
        -- 472081 vs 472053 — LittleWigs ID wins (BigWigs Timer key); cast data assumed same as 472053
        [472081]  = { name = "Reckless Leap",      castType = "begincast", castDuration = 3,                        role = "other",                    displayText = "FEET",     sound = "Feet" },
        [1253272] = { name = "Intimidating Shout", castType = "begincast", castDuration = 5,                        role = "mechanic",                 displayText = "STACK",    sound = "Stack" },
        -- 470963 vs 1271676 — LittleWigs ID wins (BigWigs Timer key); cast data adjusted to 2s based on live log late values
        [470963]  = { name = "Bladestorm",         castType = "begincast", castDuration = 2,                        role = "other",                    displayText = "DODGE"    },
    },
    -- HP-threshold phase bars are visual-only — see Crawth note above for why.
    phases = {
        { unit = "boss1", threshold = 66, lead = 5 },
        { unit = "boss1", threshold = 33, lead = 5 },
    },
}

KE.EncounterData[3059] = {
    name = "Restless Heart",
    dungeon = "WindrunnerSpire",
    spells = {
        [472556]  = { name = "Arrow Rain",         castType = "channel",                          channelDuration = 2.5, role = "other",    extendByChannel = true, displayText = "FEET",    sound = "Feet" },
        [472662]  = { name = "Tempest Slash",      castType = "begincast", castDuration = 2.5,                           role = "tank",     display = "bar",        displayText = "TANK HIT" },
        [1253986] = { name = "Gust Shot",          castType = "cast",                                                    role = "mechanic",                         displayText = "CLEARS",  sound = "Clear" },
        [468429]  = { name = "Bullseye Windblast", castType = "cast",                                                    role = "mechanic",                         displayText = "LEAP",    sound = "Leap" },
        [474528]  = { name = "Bolt Gale",          castType = "begincast", castDuration = 4,      channelDuration = 5,   role = "mechanic",                         displayText = "FRONTAL", sound = "Frontal" },
    },
}

-- ╔══════════════════════════════════════════════════════════╗
-- ║  AltarOfFangs                                            ║
-- ╚══════════════════════════════════════════════════════════╝

KE.EncounterData[3456] = {
    name = "Rav'i",
    dungeon = "AltarOfFangs",
    bossOrder = 1,
    timerPolicy = "explicit",
    spells = {
        [1296220] = { name = "Triple Shot", castType = "begincast", castDuration = 2, role = "other", displayText = "DOTS + SPREAD", color = { 1.0, 0.6, 0.0 }, sound = "Spread",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1296216] = { name = "Ssscavenging", castType = "cast", castDuration = 0, role = "mechanic", displayText = "SHIELD INC", soundOnHide = "Boss Shielded",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1296050] = { name = "Regurgitate", castType = "begincast", castDuration = 3, role = "other", displayText = "FRONTAL", sound = "Frontal",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1307894] = { name = "Ravenous Stomp", castType = "begincast", castDuration = 3, role = "mechanic", displayText = "AOE + FEET", color = { 1.0, 1.0, 0.2 }, sound = "Aoe And Dance",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        -- No timeline event publishes this estimate; its provider stop follows the encounter warning.
        -- The pull publication can precede KE's encounter start.
        [1307703] = { name = "Fresh Meat", castType = "cast", castDuration = 0, role = "tank", displayText = "FRESH MEAT", color = { 0.855, 0.357, 1.0 }, soundOnHide = "Boss Buffed",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", pullReceipt = true, waitAfter = 5 } },
    },
    phaseCues = {
        -- The pull Stomp has no forecast; later Stomps are the timed row and carry a later count.
        pull_stomp = { name = "Ravenous Stomp on pull", iconOverride = 1307894, role = "mechanic",
            source = { kind = "Message", key = 1307894 }, duration = 3, messageCount = 1, maxPerPull = 1, pullReceipt = true,
            display = "text", displayText = "AOE + FEET", color = { 1.0, 1.0, 0.2 }, sound = "Aoe And Dance", showAtSeconds = 0 },
    },
    -- The total is an estimate scaled by keystone level; the timeout only caps cleanup.
    shields = {
        { parent = 1296216, baseAmount = 1311783.429, timeout = 60, displayText = "SHIELD" },
    },
    auraSounds = {
        { spellID = 1296069, trigger = "added", unit = "player", name = "Regurgitate under you", sound = "Move" },
        { spellID = 1297876, trigger = "added", unit = "player", name = "Triple Shot on you",    sound = "Gun1" },
    },
}

KE.EncounterData[3457] = {
    name = "The Writhing Coil",
    dungeon = "AltarOfFangs",
    bossOrder = 2,
    timerPolicy = "explicit",
    spells = {
        [1299154] = { name = "Synchronized Venom", castType = "begincast", castDuration = 2, role = "other", displayText = "AOE", sound = "AoE",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1298949] = { name = "Tail Scythe", castType = "begincast", castDuration = 3, role = "tank", display = "bar", displayText = "TANK HIT", sound = "Blade",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1310357] = { name = "Preparing Toxin", castType = "begincast", castDuration = 0, role = "kick", displayText = "KICKS INC", color = { 1.0, 0.15, 0.15 }, sound = "Kicks Inc",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        -- Charge and Jet have separate cues.
        [1299940] = { name = "Vindictive Onslaught", castType = "begincast", castDuration = 0, role = "other", displayText = "BAIT", color = { 0.3, 0.9, 1.0 }, sound = "Bait",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1299053] = { name = "Death Rattle", castType = "begincast", castDuration = 5, role = "mechanic", displayText = "BREAK TETHER", color = { 0.855, 0.357, 1.0 }, sound = "Gun1",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1310547] = { name = "Toxic Atrophy", castType = "begincast", castDuration = 4, role = "other", displayText = "CC ADDS", sound = "CC",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1300686] = { name = "Assimilation", castType = "begincast", castDuration = 2, role = "mechanic", displayText = "PHASE CHANGE", color = { 1.0, 1.0, 1.0 }, sound = "Phasing",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
    },
    phaseCues = {
        toxic_atrophy_kicks = { name = "Toxic Atrophy interrupts", iconOverride = 1310358, role = "kick",
            source = { kind = "Message", key = 1310358 }, duration = 4, ordinals = 3,
            ordinalSounds = { "Kick 1", "Kick 2", "Kick 3" },
            interruptResult = { ordinal = 3, unit = "boss1", displayText = "DONE", duration = 2.0, color = { 0.2, 1.0, 0.2 } },
            display = "text", displayText = "KICK", color = { 1.0, 0.15, 0.15 }, sound = "Kick", showAtSeconds = 0 },
        burrowing_charge = { name = "Burrowing Charge", iconOverride = 1299130, role = "other",
            source = { kind = "Message", key = 1299130 }, duration = 3,
            display = "text", displayText = "CHARGE", color = { 0.855, 0.357, 1.0 }, sound = "Move", showAtSeconds = 0 },
        venom_jet = { name = "Venom Jet", iconOverride = 1300044, role = "other",
            source = { kind = "Message", key = 1300044 }, duration = 4,
            display = "text", displayText = "FRONTAL", sound = "Frontal", showAtSeconds = 0 },
    },
    auraSounds = {
        { spellID = 1310974, trigger = "added", unit = "player", name = "Toxic Atrophy on you", sound = "Gun1" },
        { spellID = 1300503, trigger = "added", unit = "player", name = "Spiteful Hunt on you", sound = "Fixate Incoming", disabled = true },
    },
}

KE.EncounterData[3458] = {
    name = "Zul'jan",
    dungeon = "AltarOfFangs",
    bossOrder = 3,
    timerPolicy = "explicit",
    spells = {
        -- The short replacement may arrive before the long forecast's canceled stop.
        [1300876] = { name = "Ritual of the Fang", castType = "begincast", castDuration = 5, role = "mechanic", displayText = "SOAK LINES", color = { 0.2, 1.0, 0.4 }, sound = "Soak",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished", replacement = { from = 65, duration = 3 } } },
        [1301111] = { name = "Axegrinder", castType = "begincast", castDuration = 3, role = "mechanic", displayText = "FRONTALS", color = { 0.77, 0.17, 0.17 }, sound = "Frontals",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1301350] = { name = "Chop Down", castType = "begincast", castDuration = 1.5, role = "tank", display = "bar", displayText = "TANK HIT", sound = "Blade",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1301413] = { name = "Boneslicer", castType = "begincast", castDuration = 5, role = "other", displayText = "CLEAR DEBUFF", color = { 0.95, 0.95, 0.95 }, sound = "Clear",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
    },
    phaseCues = {
        axegrinder_channel = { name = "Axegrinder (Channel)", iconOverride = 1301111, role = "mechanic",
            source = { kind = "Message", key = 1301111 }, leadDelay = 3, duration = 6,
            display = "text", displayText = "FRONTALS", color = { 0.77, 0.17, 0.17 }, showAtSeconds = 0, disabled = true },
        ritual_channel = { name = "Ritual of the Fang (Channel)", iconOverride = 1300876, role = "mechanic",
            source = { kind = "Message", key = 1300876 }, leadDelay = 5, duration = 8,
            display = "text", displayText = "SOAK LINES", color = { 0.2, 1.0, 0.4 }, showAtSeconds = 0, disabled = true },
    },
    auraSounds = {
        { spellID = 1300894, trigger = "removed", unit = "player", name = "Ritual Venom ended", sound = "Clear" },
    },
}

-- ╔══════════════════════════════════════════════════════════╗
-- ║  DenOfNalorakk                                           ║
-- ╚══════════════════════════════════════════════════════════╝

KE.EncounterData[3207] = {
    name = "The Hoardmonger",
    dungeon = "DenOfNalorakk",
    bossOrder = 1,
    timerPolicy = "explicit",
    spells = {
        [1234233] = { name = "Spoiled Supplies", castType = "cast", castDuration = 2.3, role = "other", displayText = "SOAKS", sound = "Soaks",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1253268] = { name = "Earthshatter Slam", castType = "begincast", castDuration = 4, role = "other", displayText = "FRONTAL", sound = "Frontal",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished", castConfirm = "boss-cast-start" } },
        [1235118] = { name = "Ravenous Bellow", castType = "begincast", castDuration = 3, role = "mechanic", displayText = "AOE", sound = "Aoe And Knockback",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
    },
}

KE.EncounterData[3208] = {
    name = "Sentinel of Winter",
    dungeon = "DenOfNalorakk",
    bossOrder = 2,
    timerPolicy = "explicit",
    spells = {
        [1235548] = { name = "Glacial Torment",       castType = "begincast", castDuration = 1, role = "heal",     displayText = "DISPEL", sound = "Dispel",
                      timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label" } },
        [1235623] = { name = "Raging Squall",         castType = "begincast", castDuration = 0, role = "other",    displayText = "STACK",  sound = "Stack",
                      timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label" } },
        [1235783] = { name = "Shattering Frostspike", castType = "begincast", castDuration = 3, role = "mechanic", displayText = "ADDS",   sound = "Adds",
                      timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label" } },
    },
}

KE.EncounterData[3209] = {
    name = "Nalorakk",
    dungeon = "DenOfNalorakk",
    bossOrder = 3,
    timerPolicy = "explicit",
    spells = {
        [1242860] = { name = "Echoing Maul",           castType = "begincast", castDuration = 4, role = "other",    displayText = "DROPS", sound = "Drops",
                      timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label" } },
        [1243011] = { name = "Fury of the War God",    castType = "cast",      castDuration = 0, role = "mechanic", displayText = "PROTECT", sound = "Protect",
                      timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label" } },
        [1243569] = { name = "Overwhelming Onslaught", castType = "begincast", castDuration = 7, role = "mechanic", displayText = "HIDE",  sound = "Hide",
                      timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1297797] = { name = "Forceful Slam",          castType = "begincast", castDuration = 5, role = "tank",     displayText = "TANK SOAK", sound = "Soak",
                      timerSource = { kind = "Sequel", parent = 1243569, after = 10 } },
    },
}

-- ╔══════════════════════════════════════════════════════════╗
-- ║  KingsRest                                               ║
-- ╚══════════════════════════════════════════════════════════╝

KE.EncounterData[2139] = {
    name = "The Golden Serpent",
    dungeon = "KingsRest",
    bossOrder = 1,
    timerPolicy = "explicit",
    spells = {
        [265773] = { name = "Spit Gold", castType = "begincast", castDuration = 2, role = "other", displayText = "DROPS", sound = "Drops",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [265910] = { name = "Tail Thrash", castType = "begincast", castDuration = 1.5, role = "tank", display = "bar", displayText = "TANK HIT", sound = "Blade",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [265781] = { name = "Serpentine Gust", castType = "begincast", castDuration = 2, role = "other", displayText = "AOE", sound = "AoE",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [265923] = { name = "Lucre's Call", castType = "begincast", castDuration = 2, role = "mechanic", displayText = "ADDS", sound = "Adds",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
    },
    auraSounds = {
        { spellID = 265914, trigger = "added", unit = "player", name = "Molten Gold under you", sound = "Move" },
    },
}

KE.EncounterData[2142] = {
    name = "Mchimba the Embalmer",
    dungeon = "KingsRest",
    bossOrder = 2,
    timerPolicy = "explicit",
    spells = {
        [267618] = { name = "Drain Fluids", castType = "begincast", castDuration = 2, role = "other", displayText = "FEET", sound = "Feet",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1311956] = { name = "Burn Corruption", castType = "begincast", castDuration = 4, role = "other", displayText = "DODGE", sound = "Dodge",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1312146] = { name = "Awakening Slam", castType = "begincast", castDuration = 3, role = "other", displayText = "ADDS", sound = "Adds",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [267702] = { name = "Entomb", castType = "begincast", castDuration = 3, role = "mechanic", displayText = "RESCUE", color = { 0.855, 0.357, 1.0 }, sound = "Rescue",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
    },
    auraSounds = {
        { spellID = 267618, trigger = "added", unit = "player", name = "Drain Fluids on you",      sound = "Gun1" },
        { spellID = 267874, trigger = "added", unit = "player", name = "Burning Ground under you", sound = "Move" },
    },
}

KE.EncounterData[2140] = {
    name = "The Council of Tribes",
    dungeon = "KingsRest",
    bossOrder = 3,
    timerPolicy = "explicit",
    spells = {
        [266206] = { name = "Whirling Axes", castType = "begincast", castDuration = 2.8, role = "other", displayText = "DODGE", sound = "Dodge",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [266231] = { name = "Severing Axe", castType = "begincast", castDuration = 1.5, role = "other", displayText = "BLEED", color = { 0.77, 0.17, 0.17 }, sound = "Bleed",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [267494] = { name = "Barrel Through", castType = "begincast", castDuration = 6, role = "mechanic", displayText = "STACK + SOAK", color = { 0.2, 1.0, 0.4 }, sound = "Soak",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [266237] = { name = "Debilitating Backhand", castType = "begincast", castDuration = 2, role = "tank", display = "bar", displayText = "TANK KITE", color = { 0.77, 0.17, 0.17 }, sound = "Blade",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        -- No sound: a cooldown timer cannot say who is targeted.
        [1305810] = { name = "Arc Lightning", castType = "begincast", castDuration = 1, role = "other", displayText = "ARC LIGHTNING", color = { 1.0, 0.231, 0.188 }, disabled = true,
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [267273] = { name = "Poison Nova", castType = "begincast", castDuration = 0, role = "mechanic", displayText = "KICK BOSS", color = { 1.0, 0.15, 0.15 }, sound = "Interrupt",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [267060] = { name = "Call of the Elements", castType = "begincast", castDuration = 2.5, role = "mechanic", displayText = "TOTEMS", sound = "Totems",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
    },
}

KE.EncounterData[2143] = {
    name = "Dazar, The First King",
    dungeon = "KingsRest",
    bossOrder = 4,
    timerPolicy = "explicit",
    spells = {
        -- Timeline Finished can arrive late; retain the estimate unless a readable cast confirms its end.
        [269230] = { name = "Hunting Leap", castType = "begincast", castDuration = 2, role = "other", displayText = "ADD FRONTAL", color = { 0.77, 0.17, 0.17 }, sound = "Add Frontal",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", castMatch = { spells = { 269232 }, endpoint = "cast-end" } } },
        [269369] = { name = "Deathly Roar", castType = "begincast", castDuration = 0, role = "other", displayText = "KICK ADD", color = { 1.0, 0.15, 0.15 }, sound = "Kick Add",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        -- Unanchored: the timeline finish arrives late, so the cue ends on its estimate.
        [1303115] = { name = "Aerial Smash", castType = "begincast", castDuration = 4, role = "other", displayText = "SPREAD", sound = "Spread",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label" } },
        [268586] = { name = "Blade Combo", castType = "begincast", castDuration = 1.5, role = "tank", display = "bar", displayText = "TANK HIT", sound = "Blade",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1303267] = { name = "Gilded Destruction", castType = "begincast", castDuration = 6, role = "mechanic", displayText = "AOE + FRONTAL", color = { 1.0, 1.0, 0.2 }, sound = "AoE",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        -- Unanchored: the timeline finish arrives late; the cue ends at the forecast deadline.
        [1303327] = { name = "Quaking Leap", castType = "cast", castDuration = 0, role = "other", displayText = "SPREAD", color = { 1.0, 0.6, 0.0 }, sound = "Spread",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label" } },
        [1303488] = { name = "Savage Maul", castType = "begincast", castDuration = 2, role = "tank", display = "bar", displayText = "TANK HIT", sound = "Blade",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
    },
    phases = {
        { unit = "boss1", threshold = 80, lead = 5 },
    },
}

-- ╔══════════════════════════════════════════════════════════╗
-- ║  MurderRow                                               ║
-- ╚══════════════════════════════════════════════════════════╝

KE.EncounterData[3101] = {
    name = "Kystia Manaheart",
    dungeon = "MurderRow",
    bossOrder = 1,
    timerPolicy = "explicit",
    spells = {
        [1253811] = { name = "Fel Spray", castType = "begincast", castDuration = 3.5, role = "other", displayText = "FRONTAL", sound = "Frontal",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [474240] = { name = "Fel Nova", castType = "begincast", castDuration = 3.5, role = "other", displayText = "DODGE", sound = "Dodge",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1264095] = { name = "Mirror Images", castType = "cast", castDuration = 0, role = "mechanic", displayText = "CC ADDS", sound = "CC",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
    },
    phaseCues = {
        -- The figure in the label is fixed text; nothing is measured.
        light_infusion = { name = "Light Infusion", iconOverride = 1230304, role = "other",
            source = { kind = "Message", key = 1230304 }, leadDelay = 1.7, duration = 20, maxPerPull = 4,
            -- A Fel Nova forecast is hidden for this window; an actual Nova cast still shows.
            hidesForecasts = { 474240 },
            prepareText = "VULNERABILITY SOON", endedText = "VULNERABILITY ENDED", endedDuration = 2,
            display = "bar", displayText = "VULNERABILITY 100%", color = { 0.4, 1.0, 0.3 },
            soundOnHide = "Dmg Amp Over", showAtSeconds = 0 },
    },
    phases = {
        { unit = "boss2", threshold = 20, lead = 5 },
    },
    auraSounds = {
        -- Off by default: the Light Infusion cue already announces this moment.
        { spellID = 1217464, trigger = "removed", unit = "boss",   name = "Vulnerability buff removed", sound = "Dmg Amp", disabled = true },
        { spellID = 1217989, trigger = "removed", unit = "boss",   name = "Shield removed",             sound = "Gun1" },
        { spellID = 1228198, trigger = "added",   unit = "player", name = "Corroding Spittle on you",   sound = "Dispel" },
        { spellID = 1253813, trigger = "added",   unit = "player", name = "Fel Spray on you",           sound = "Gun1" },
    },
}

KE.EncounterData[3102] = {
    name = "Zaen Bladesorrow",
    dungeon = "MurderRow",
    bossOrder = 2,
    timerPolicy = "explicit",
    spells = {
        [474478] = { name = "Killing Spree", castType = "cast", castDuration = 0, role = "other", displayText = "AOE", sound = "AoE",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label" } },
        [474765] = { name = "Same-Day Delivery", castType = "cast", castDuration = 2, role = "other", displayText = "FEET", sound = "Feet",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1214357] = { name = "Fire Bomb", castType = "cast", castDuration = 0, role = "other", displayText = "CLEAR", sound = "Clear",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label" } },
        [1222795] = { name = "Envenom", castType = "begincast", castDuration = 3, role = "tank", display = "bar", displayText = "TANK HIT", sound = "Blade",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1218347] = { name = "Murder in a Row", castType = "cast", castDuration = 0, role = "mechanic", displayText = "HIDE", sound = "Hide",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
    },
    auraSounds = {
        { spellID = 1214352, trigger = "added",   unit = "player", name = "Fire Bomb on you",             sound = "Move" },
        { spellID = 474515,  trigger = "added",   unit = "player", name = "Heartstop Poison on you",      sound = "Dispel" },
        { spellID = 474545,  trigger = "removed", unit = "player", name = "Murder in a Row ended",        sound = "Feet" },
        { spellID = 474740,  trigger = "added",   unit = "player", name = "Murder in a Row bleed on you", sound = "Gun1" },
        { spellID = 1218465, trigger = "added",   unit = "player", name = "Waiter assignment",            sound = "Whisper" },
        { spellID = 1218466, trigger = "added",   unit = "player", name = "Cleaner assignment",           sound = "Whisper" },
        { spellID = 1218467, trigger = "added",   unit = "player", name = "Entertainer assignment",       sound = "Whisper" },
        { spellID = 1218468, trigger = "added",   unit = "player", name = "Bouncer assignment",           sound = "Whisper" },
    },
}

-- This boss's provider module stops a bar when its event pauses and never
-- resumes it, so every row here opts into the paused-stop refusal.
KE.EncounterData[3103] = {
    name = "Xathuux the Annihilator",
    dungeon = "MurderRow",
    bossOrder = 3,
    timerPolicy = "explicit",
    spells = {
        [473898] = { name = "Legion Strike", castType = "begincast", castDuration = 3, role = "tank", display = "bar", displayText = "TANK HIT", sound = "Blade",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished", pausedStop = "retire" } },
        [1214637] = { name = "Axe Toss", castType = "begincast", castDuration = 3, role = "other", displayText = "ADD", sound = "Add",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished", pausedStop = "retire" } },
        -- An estimate: queued behind Legion Strike, Crush starts about 0.6 s after its 3 s cast.
        [1295453] = { name = "Infernal Crush", castType = "begincast", castDuration = 3, role = "other", displayText = "SPREAD", sound = "Spread",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished", pausedStop = "retire",
                queueAfter = { parent = 473898, delay = 3.6 } } },
        [474197] = { name = "Demonic Rage", castType = "begincast", castDuration = 4, role = "mechanic", displayText = "VULN + AOE", sound = "AoE",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished", pausedStop = "retire" } },
    },
    phaseCues = {
        -- The provider's own phase timer is the window. The figure is fixed text.
        rage_phase = { name = "Demonic Rage phase", iconOverride = 474197, role = "other",
            source = { kind = "Timer", key = 474197, isCooldown = false },
            endedText = "VULNERABILITY ENDED", endedDuration = 2,
            display = "bar", displayText = "VULNERABILITY 30%", color = { 0.4, 1.0, 0.3 },
            sound = "Dmg Amp", showAtSeconds = 0 },
    },
    auraSounds = {
        { spellID = 1214637, trigger = "added",   unit = "player", name = "Axe Toss on you",      sound = "Move" },
        { spellID = 473898,  trigger = "removed", unit = "player", name = "Legion Strike ended",  sound = "Clear" },
        { spellID = 474234,  trigger = "added",   unit = "player", name = "Burning Steps on you", sound = "Gun1" },
    },
}

KE.EncounterData[3105] = {
    name = "Lithiel Cinderfury",
    dungeon = "MurderRow",
    bossOrder = 4,
    timerPolicy = "explicit",
    spells = {
        [474408] = { name = "Summon Vilefiend", castType = "begincast", castDuration = 2, role = "mechanic", displayText = "ADD", sound = "Add",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1218203] = { name = "Fingers of Gul'dan", castType = "begincast", castDuration = 5, role = "other", displayText = "ADDS", sound = "Adds",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        -- Hidden by default: its forecast reaches zero after the leap. Its
        -- anchor still starts the lockout cue and ends the leap estimate.
        [1224478] = { name = "Malefic Wave", castType = "begincast", castDuration = 0, role = "mechanic", sound = "Phasing", disabled = true,
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
    },
    phaseCues = {
        -- An estimate: the leap follows the Fingers cast start by about 8.1 seconds.
        leap = { name = "Boss leap estimate", iconOverride = 1224478, role = "mechanic",
            source = { kind = "Sequel", parent = 1218203, after = 0 }, duration = 8.1, endsOnAnchor = 1224478,
            display = "text", displayText = "BOSS LEAP", color = { 0.7, 0.4, 1.0 }, sound = "Phasing", showAtSeconds = 3 },
        no_portal = { name = "Malefic Wave lockout", iconOverride = 1224478, role = "mechanic",
            source = { kind = "Sequel", parent = 1224478, after = 0 }, duration = 10,
            endedText = "GATEWAY SAFE", endedDuration = 2, endedColor = { 0.2, 1.0, 0.4 },
            display = "text", displayText = "DON'T GATE", color = { 1.0, 0.2, 0.2 }, soundOnHide = "Take Gateway", showAtSeconds = 0 },
    },
    auraSounds = {
        { spellID = 1217384, trigger = "added", unit = "player", name = "Malefic Wave on you", sound = "Gun1" },
    },
}

-- ╔══════════════════════════════════════════════════════════╗
-- ║  RubyLifePools                                           ║
-- ╚══════════════════════════════════════════════════════════╝

KE.EncounterData[2609] = {
    name = "Melidrussa Chillworn",
    dungeon = "RubyLifePools",
    bossOrder = 1,
    timerPolicy = "explicit",
    spells = {
        [1307297] = { name = "Hailburst", castType = "begincast", castDuration = 3, role = "other", displayText = "DROPS", sound = "Drops",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1307308] = { name = "Chillstorm", castType = "begincast", castDuration = 4.5, role = "other", displayText = "SUCC", sound = "Pull",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        -- Mythic only: no Frost Overload timer is published on other difficulties.
        [373686] = { name = "Frost Overload", castType = "cast", castDuration = 0, role = "mechanic", displayText = "SHIELD INC", soundOnHide = "Boss Shielded", shieldColor = { 0.37, 0.82, 1.0 },
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
    },
    phaseCues = {
        -- Published with the Mythic shield forecast at each health transition.
        awaken_whelps = { name = "Awaken Whelps", iconOverride = 373046, role = "mechanic",
            source = { kind = "Message", key = 373046 }, duration = 4, maxPerPull = 2,
            display = "text", displayText = "ADDS", sound = "Adds", showAtSeconds = 0 },
    },
    phases = {
        { unit = "boss1", threshold = 66, lead = 5 },
        { unit = "boss1", threshold = 33, lead = 5 },
    },
    shields = {
        { parent = 373686, baseAmount = 2490819.8, timeout = 60, displayText = "SHIELD" },
    },
    auraSounds = {
        { spellID = 372963, trigger = "added", unit = "player", name = "Storm's Eye on you", sound = "Move" },
        { spellID = 384024, trigger = "added", unit = "player", name = "Hailbombs on you",   sound = "Gun1" },
    },
}

KE.EncounterData[2606] = {
    name = "Kokia Blazehoof",
    dungeon = "RubyLifePools",
    bossOrder = 2,
    timerPolicy = "explicit",
    spells = {
        [372864] = { name = "Ritual of Blazebinding", castType = "begincast", castDuration = 5, role = "mechanic", displayText = "ADD", sound = "Add",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [372110] = { name = "Molten Boulder", castType = "begincast", castDuration = 0, role = "mechanic", displayText = "BAIT", sound = "Bait",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [372858] = { name = "Searing Blows", castType = "cast", castDuration = 0, role = "tank", display = "bar", displayText = "TANK HIT", sound = "Blade",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
    },
    auraSounds = {
        { spellID = 372820, trigger = "added", unit = "player", name = "Scorched Earth on you", sound = "Move" },
    },
}

KE.EncounterData[2623] = {
    name = "Kyrakka and Erkhart Stormvein",
    shortName = "Kyrakka & Erkhart",
    dungeon = "RubyLifePools",
    bossOrder = 3,
    timerPolicy = "explicit",
    spells = {
        -- The cast can start well after the timeline finishes; its confirmed start re-times the cue.
        [381525] = { name = "Roaring Firebreath", castType = "begincast", castDuration = 4, role = "other", displayText = "FRONTAL", sound = "Frontal",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished", castMatch = { spells = { 381525 }, within = 5 }, soonOnHold = true } },
        [381512] = { name = "Stormslam", castType = "begincast", castDuration = 2.5, role = "tank", display = "bar", displayText = "TANK HIT", sound = "Blade",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [381517] = { name = "Winds of Change", castType = "begincast", castDuration = 1.5, role = "mechanic", displayText = "WINDS - CHECK MAP", sound = "Check Map",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        -- The key names the debuff; the casts are the flying and grounded spits.
        [381862] = { name = "Inferno Spit", castType = "begincast", castDuration = 2, role = "other", displayText = "DROPS", sound = "Drops",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished", castMatch = { spells = { 381602, 381605 }, within = 5 }, soonOnHold = true } },
        [381516] = { name = "Interrupting Cloudburst", castType = "begincast", castDuration = 5, role = "mechanic", displayText = "STOP CASTING", color = { 1.0, 0.15, 0.15 }, sound = "Stop Casting",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
    },
    windMap = { wind = 381517, spit = 381862 },
    -- Either boss reaching 40% lands Kyrakka; Erkhart, on boss1, triggers
    -- nearly every landing. The reminder ends at the landing.
    phases = {
        { unit = "boss1", threshold = 40, lead = 5, endsAtStage = 2 },
    },
    -- The 5 s Roaring Firebreath forecast marks the landing.
    stageCue = { spellID = 381525, duration = 5, stage = 2 },
    auraSounds = {
        { spellID = 381526, trigger = "added", unit = "player", name = "Roaring Firebreath on you", sound = "Gun1" },
        { spellID = 384773, trigger = "added", unit = "player", name = "Flaming Embers on you",     sound = "Move" },
    },
}

-- ╔══════════════════════════════════════════════════════════╗
-- ║  TempleOfSethraliss                                      ║
-- ╚══════════════════════════════════════════════════════════╝

KE.EncounterData[2124] = {
    name = "Adderis and Aspix",
    dungeon = "TempleOfSethraliss",
    bossOrder = 1,
    timerPolicy = "explicit",
    spells = {
        [1288049] = { name = "Thunder and Lightning", castType = "begincast", castDuration = 4.5, role = "other", displayText = "STACK + SOAK", color = { 0.2, 1.0, 0.4 }, sound = "Soak",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1311804] = { name = "Overload", castType = "begincast", castDuration = 3, role = "tank", display = "bar", displayText = "TANK HIT", sound = "Blade",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1311805] = { name = "Tempest Winds", castType = "begincast", castDuration = 3, role = "other", displayText = "DROPS", color = { 1.0, 0.6, 0.0 }, sound = "Drops",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1289059] = { name = "Gale Force", castType = "begincast", castDuration = 3.5, role = "other", displayText = "KNOCK", color = { 1.0, 1.0, 0.2 }, sound = "Knockback",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished", holdOverlapping = true } },
    },
    phases = {
        { unit = "boss1", threshold = 66, lead = 5 },
        { unit = "boss1", threshold = 35, lead = 5 },
        { unit = "boss2", threshold = 66, lead = 5 },
        { unit = "boss2", threshold = 35, lead = 5 },
    },
    auraSounds = {
        { spellID = 1288885, trigger = "added", unit = "player", name = "Tempest Winds silence on you", sound = "Move" },
    },
}

KE.EncounterData[2125] = {
    name = "Merektha",
    dungeon = "TempleOfSethraliss",
    bossOrder = 2,
    timerPolicy = "explicit",
    spells = {
        [264172] = { name = "Burrow", castType = "begincast", castDuration = 3, role = "other", displayText = "INTERMISSION", color = { 1.0, 1.0, 1.0 }, soundOnHide = "Intermission",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1290029] = { name = "A Knot of Snakes", castType = "begincast", castDuration = 3, role = "other", displayText = "STACK + CC", color = { 0.2, 1.0, 0.4 }, sound = "CC",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        -- An estimate: the channel length is unpublished, so the cue ends 3 s after its anchor.
        [1289109] = { name = "Thunder Spit", castType = "begincast", castDuration = 3, role = "other", displayText = "FEET", sound = "Feet",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1289205] = { name = "Hatch", castType = "begincast", castDuration = 3, role = "mechanic", displayText = "BIG ADD", color = { 1.0, 0.3, 0.8 }, sound = "Adds",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1290797] = { name = "Lightning Bite", castType = "begincast", castDuration = 3, role = "tank", display = "bar", displayText = "TANK HIT", sound = "Blade",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1293048] = { name = "Serpentstorm", castType = "begincast", castDuration = 4, role = "other", displayText = "AOE + DANCE", color = { 1.0, 1.0, 0.2 }, sound = "Aoe And Dance",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
    },
    phaseCues = {
        burrow_window = { name = "Burrow window", iconOverride = 264172, role = "other",
            source = { kind = "Timer", key = 264172, isCooldown = false },
            display = "bar", displayText = "BURROWED", color = { 1.0, 1.0, 1.0 }, showAtSeconds = 0 },
    },
    auraSounds = {
        { spellID = 1289109, trigger = "added", unit = "player", name = "Thunder Spit on you",          sound = "Gun1" },
        { spellID = 1289588, trigger = "added", unit = "player", name = "Thunder Spit hit on you",      sound = "Move" },
        { spellID = 1289589, trigger = "added", unit = "player", name = "Lingering Storm under you",    sound = "Move" },
        { spellID = 1290030, trigger = "added", unit = "player", name = "A Knot of Snakes on you",      sound = "Move" },
        { spellID = 1297034, trigger = "added", unit = "player", name = "Electrified Ground under you", sound = "Move" },
    },
}

KE.EncounterData[2126] = {
    name = "Galvazzt",
    dungeon = "TempleOfSethraliss",
    bossOrder = 3,
    timerPolicy = "explicit",
    spells = {
        [1309525] = { name = "Induction", castType = "begincast", castDuration = 3, role = "other", displayText = "AOE", sound = "AoE",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        -- The extension estimates spire availability after the provider endpoint.
        [1291618] = { name = "Lightning Spire", castType = "cast", castDuration = 3.5, role = "mechanic", displayText = "BLOCK LINE", color = { 0.855, 0.357, 1.0 }, sound = "Block Line",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished", soonOnHold = true } },
    },
    auraSounds = {
        { spellID = 1291815, trigger = "added", unit = "player", name = "Induction Field under you", sound = "Move" },
    },
}

KE.EncounterData[2127] = {
    name = "Avatar of Sethraliss",
    dungeon = "TempleOfSethraliss",
    bossOrder = 4,
    timerPolicy = "explicit",
    spells = {
        [1301202] = { name = "Defiling Taint", castType = "cast", castDuration = 0, role = "other", displayText = "BOSS IMMUNE", color = { 1.0, 1.0, 1.0 }, sound = "Boss Immune",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished", soonOnHold = true } },
        [1273408] = { name = "Stage One", castType = "cast", castDuration = 0, role = "other", displayText = "STAGE ONE", color = { 1.0, 1.0, 1.0 }, sound = "Phase Ending",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
    },
    auraSounds = {
        { spellID = 1302826, trigger = "removed", unit = "player", name = "Corruption Burst ended", sound = "Clear" },
    },
}

-- ╔══════════════════════════════════════════════════════════╗
-- ║  TheBlindingVale                                         ║
-- ╚══════════════════════════════════════════════════════════╝

KE.EncounterData[3199] = {
    name = "Lightblossom Trinity",
    dungeon = "TheBlindingVale",
    bossOrder = 1,
    timerPolicy = "explicit",
    spells = {
        [1234753] = { name = "Bedrock Slam", castType = "begincast", castDuration = 3, role = "tank", display = "bar", displayText = "TANK HIT", sound = "Blade",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1234850] = { name = "Lightsower Dash", castType = "begincast", castDuration = 2.5, role = "mechanic", displayText = "CHARGE", color = { 0.855, 0.357, 1.0 }, sound = "Dodge",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1235640] = { name = "Thornblade", castType = "begincast", castDuration = 3, role = "other", displayText = "MOVE OUT", color = { 0.77, 0.17, 0.17 }, sound = "Move Out",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished", retainEarlyFinished = true } },
        -- The cue ends with the cast; the beam that follows is not shown.
        [1235564] = { name = "Lightblossom Beam", castType = "begincast", castDuration = 3, role = "mechanic", displayText = "BLOCK LINE", color = { 0.855, 0.357, 1.0 }, sound = "Block Line",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
    },
    auraSounds = {
        { spellID = 1234802, trigger = "added", unit = "player", name = "Fertile Loam under you",         sound = "Move" },
        { spellID = 1235828, trigger = "added", unit = "player", name = "Light-Scorched Earth under you", sound = "Move" },
        { spellID = 1261276, trigger = "added", unit = "player", name = "Thornblade on you",              sound = "Gun1" },
    },
}

KE.EncounterData[3200] = {
    name = "Ikuzz the Light Hunter",
    dungeon = "TheBlindingVale",
    bossOrder = 2,
    timerPolicy = "explicit",
    spells = {
        [1236746] = { name = "Verdant Stomp", castType = "begincast", castDuration = 3, role = "other", displayText = "AOE", sound = "Knockback",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished", suppressConcurrentRestart = { from = 29, duration = 6 } } },
        [1236709] = { name = "Thorncaller Roar", castType = "begincast", castDuration = 2, role = "other", displayText = "AOE + FEET", sound = "Aoe And Dance",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1237090] = { name = "Bloodthirsty Gaze", castType = "begincast", castDuration = 4, role = "mechanic", displayText = "FIXATE", color = { 0.855, 0.357, 1.0 }, sound = "Fixate Incoming",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
    },
    auraSounds = {
        { spellID = 1237267, trigger = "added", unit = "player", name = "Incise on you",   sound = "Gun1" },
        { spellID = 1272290, trigger = "added", unit = "player", name = "Crunched on you", sound = "Gun1" },
    },
}

KE.EncounterData[3201] = {
    name = "Lightwarden Ruia",
    dungeon = "TheBlindingVale",
    bossOrder = 3,
    timerPolicy = "explicit",
    spells = {
        -- Off by default: its forecast ends at the pull.
        [1239882] = { name = "Moonkin Form", castType = "begincast", castDuration = 2, role = "mechanic", displayText = "PHASE 1", color = { 1.0, 1.0, 1.0 }, disabled = true,
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        -- Stage-three forecasts cancel near their deadlines instead of finishing.
        [1239824] = { name = "Lightfire", castType = "begincast", castDuration = 2, role = "mechanic", displayText = "SPREAD", color = { 1.0, 0.6, 0.0 }, sound = "Spread",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished", canceledStop = { stage = 3, within = 1 } } },
        [1240098] = { name = "Lightfall", castType = "cast", castDuration = 0, role = "other", displayText = "FEET", color = { 1.0, 0.6, 0.0 }, sound = "Feet",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished", canceledStop = { stage = 3, within = 1 } } },
        [1240210] = { name = "Pulverizing Strikes", castType = "begincast", castDuration = 2.5, role = "other", displayText = "MARKED FRONTALS", color = { 0.77, 0.17, 0.17 }, sound = "Frontal",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished", canceledStop = { stage = 3, within = 1 } } },
        [1241058] = { name = "Grievous Thrash", castType = "begincast", castDuration = 2, role = "other", displayText = "BLEEDS", sound = "Bleeds",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished", canceledStop = { stage = 3, within = 1 } } },
    },
    phaseCues = {
        bear_form = { name = "Bear Form", iconOverride = 1239885, role = "other",
            source = { kind = "Message", key = 1239885 }, duration = 2, maxPerPull = 1,
            display = "text", displayText = "PHASE 2", color = { 1.0, 1.0, 1.0 }, sound = "Phasing", showAtSeconds = 0 },
        haranir_form = { name = "Haranir Form", iconOverride = 1239883, role = "other",
            source = { kind = "Message", key = 1239883 }, duration = 2, maxPerPull = 1,
            display = "text", displayText = "PHASE 3", color = { 1.0, 1.0, 1.0 }, sound = "Phasing", showAtSeconds = 0 },
    },
    phases = {
        { unit = "boss1", threshold = 70, lead = 5 },
        { unit = "boss1", threshold = 40, lead = 5 },
    },
}

KE.EncounterData[3202] = {
    name = "Ziekket",
    dungeon = "TheBlindingVale",
    bossOrder = 4,
    timerPolicy = "explicit",
    spells = {
        [1246372] = { name = "Awaken the Lightbloom", castType = "begincast", castDuration = 3, role = "mechanic", displayText = "ADDS", sound = "Adds",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1247685] = { name = "Thornspike", castType = "begincast", castDuration = 3, role = "tank", display = "bar", displayText = "TANK HIT", sound = "Blade",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1246607] = { name = "Concentrated Lightbeam", castType = "begincast", castDuration = 5, role = "other", displayText = "AIM AT ADDS", color = { 1.0, 0.231, 0.188 }, sound = "Frontal",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        -- Mythic only: no other difficulty publishes this timer.
        [1246858] = { name = "Lightbloom's Essence", castType = "begincast", castDuration = 2, role = "other", displayText = "SOAK ORBS", color = { 0.2, 1.0, 0.4 }, sound = "Soaks",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
    },
    auraSounds = {
        { spellID = 1246753, trigger = "added",     unit = "player", name = "Lightsap under you",               sound = "Move" },
        { spellID = 1247052, trigger = "added",     unit = "player", name = "Lightbloom's Might: initial gain", sound = "Whisper" },
        { spellID = 1247052, trigger = "increased", unit = "player", name = "Lightbloom's Might: extra stack",  sound = "Whisper" },
        { spellID = 1247746, trigger = "added",     unit = "player", name = "Thornspike bleed on you",          sound = "Gun1" },
    },
}

-- ╔══════════════════════════════════════════════════════════╗
-- ║  VoidscarArena                                           ║
-- ╚══════════════════════════════════════════════════════════╝

KE.EncounterData[3285] = {
    name = "Taz'Rah",
    dungeon = "VoidscarArena",
    bossOrder = 1,
    timerPolicy = "explicit",
    spells = {
        -- Unanchored: this event's timeline finish is not reliably reported.
        [1222098] = { name = "Nether Dash", castType = "cast", castDuration = 0, role = "mechanic", displayText = "LINES", sound = "Spread",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label" } },
        [1296963] = { name = "Umbral Rupture", castType = "begincast", castDuration = 4, role = "other", displayText = "FEET", sound = "Feet",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1297017] = { name = "Void Blast", castType = "begincast", castDuration = 2, role = "tank", display = "bar", displayText = "TANK HIT", sound = "Blade",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1300259] = { name = "Dark Bloom", castType = "begincast", castDuration = 4, role = "other", displayText = "AOE + DODGE", sound = "Dodge",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
    },
    auraSounds = {
        { spellID = 1296967, trigger = "added", unit = "player", name = "Void Fissure on you", sound = "Move" },
    },
}

KE.EncounterData[3286] = {
    name = "Atroxus",
    dungeon = "VoidscarArena",
    bossOrder = 2,
    timerPolicy = "explicit",
    spells = {
        [1222371] = { name = "Provoke Creeper", castType = "cast", castDuration = 0, role = "mechanic", displayText = "ADD", sound = "Add",
            timerSource = { kind = "Sequel", parent = 1262497, after = 7 } },
        [1222642] = { name = "Hulking Claw", castType = "begincast", castDuration = 2, role = "tank", display = "bar", displayText = "TANK HIT", sound = "Blade",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1222721] = { name = "Noxious Breath", castType = "begincast", castDuration = 4, role = "other", displayText = "FRONTAL", sound = "Frontal",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1226120] = { name = "Poison Splash", castType = "cast", castDuration = 0, role = "other", displayText = "FEET", sound = "Feet",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1262497] = { name = "Monstrous Roar", castType = "begincast", castDuration = 3, role = "other", displayText = "AOE", sound = "AoE",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
    },
    auraSounds = {
        { spellID = 1222484, trigger = "added", unit = "player", name = "Poison Pool on you",         sound = "Move" },
        { spellID = 1263971, trigger = "added", unit = "player", name = "Mind-Numbing Poison on you", sound = "Dispel" },
        { spellID = 1282892, trigger = "added", unit = "player", name = "Sickening Bite on you",      sound = "Gun1" },
    },
}

KE.EncounterData[3287] = {
    name = "Charonus",
    dungeon = "VoidscarArena",
    bossOrder = 3,
    timerPolicy = "explicit",
    spells = {
        [1222755] = { name = "Void Cascade", castType = "begincast", castDuration = 6, role = "other", displayText = "FRONTAL", sound = "Frontal",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1227264] = { name = "Cosmic Crash", castType = "begincast", castDuration = 4.8, role = "other", displayText = "AOE + SPREAD", sound = "Spread",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1263982] = { name = "Gravitic Orbs", castType = "begincast", castDuration = 0, role = "mechanic", displayText = "BAIT ORBS", sound = "Bait",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1282770] = { name = "Unstable Singularity", castType = "begincast", castDuration = 6, role = "mechanic", displayText = "MOVE IN", color = { 1.0, 0.6, 0.0 }, sound = "Move",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
        [1311923] = { name = "Dark Waves", castType = "begincast", castDuration = 5, role = "tank", display = "bar", displayText = "TANK HIT", sound = "Blade",
            timerSource = { kind = "Timer", isCooldown = true, policy = "estimated-impact", spanMode = "remaining-only", stopTolerance = 0.15, collisionPolicy = "refuse-unresolved-label", anchor = "timeline-finished" } },
    },
    phaseCues = {
        tank_frontal = {
            name = "Dark Waves: Tank Frontal", iconOverride = 1311923, role = "move",
            source = { kind = "Sequel", parent = 1311923, after = 0 },
            duration = 5, display = "text", displayText = "TANK FRONTAL",
            sound = "Frontal", showAtSeconds = 5,
        },
    },
    auraSounds = {
        { spellID = 1227247, trigger = "added", unit = "player", name = "Void Cascade on you", sound = "Gun1" },
        { spellID = 1310026, trigger = "added", unit = "player", name = "Atomized on you",     sound = "Gun1" },
    },
}
