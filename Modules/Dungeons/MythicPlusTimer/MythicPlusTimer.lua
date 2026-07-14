-- ╔══════════════════════════════════════════════════════════╗
-- ║  MythicPlusTimer.lua                                     ║
-- ║  Module: Mythic+ Timer                                   ║
-- ║  Purpose: Self-contained keystone timer HUD with an      ║
-- ║           edge-straddling bar layout and an event-driven ║
-- ║           tick architecture. Bootstrap, DB defaults, run ║
-- ║           lifecycle/state, event wiring, tick, deaths.   ║
-- ║  Backend split: _HUD (render), _Splits (PB), _Overlay    ║
-- ║           (folded nameplate/tooltip forces overlay).     ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local MPT = KitnEssentials:NewModule("MythicPlusTimer", "AceEvent-3.0", "AceHook-3.0")

-- Local references
local floor, max, abs = math.floor, math.max, math.abs
local format = string.format
local pairs = pairs
local wipe = wipe  -- WoW global
local C_ChallengeMode = C_ChallengeMode
local C_ScenarioInfo = C_ScenarioInfo
local C_Scenario = C_Scenario
local C_Container = C_Container
local C_Item = C_Item
local GetWorldElapsedTime = GetWorldElapsedTime
local GetTimePreciseSec = GetTimePreciseSec
local hooksecurefunc = hooksecurefunc
local issecretvalue = issecretvalue or function() return false end
-- Current chat API. The bare global SendChatMessage is deprecated in 12.0, so capture
-- the namespaced form once at load under a non-colliding local name (a local literally
-- named SendChatMessage still trips the deprecation lint). C_ChatInfo is a core
-- namespace present before module files run. Mirror: Modules/DamageMeter/Core.lua:46.
local SendChat = C_ChatInfo and C_ChatInfo.SendChatMessage

-- Returns the appropriate group chat channel for boss-split output, or nil when
-- the player is alone (solo run — no channel to post to). INSTANCE_CHAT preferred
-- (cross-realm instance groups), then RAID, then PARTY.
local function ResolveGroupChannel()
    if GetNumGroupMembers(LE_PARTY_CATEGORY_INSTANCE) > 0 then
        return "INSTANCE_CHAT"
    elseif IsInRaid() then
        return "RAID"
    elseif IsInGroup() then
        return "PARTY"
    end
    return nil
end

-- Constants
local PLUS_TWO_RATIO   = 0.8   -- +2 cutoff (80% of timer)
local PLUS_THREE_RATIO = 0.6   -- +3 cutoff (60% of timer)
local CHALLENGERS_PERIL_AFFIX_ID = 152  -- adds +90s; thresholds computed on (maxTime-90)

-- Module debug flag. Flip to true + /reload for lifecycle/event tracing.
-- Leave false in shipping builds.
local DEBUG_MPT = false

-- CLEU-free death attribution. Midnight removed COMBAT_LOG_EVENT_UNFILTERED,
-- so new deaths are detected by diffing GetDeathCount and scanning the party
-- for who newly went dead/ghost. Party GUIDs are non-secret (contract).
local _prevDeathCount = 0
local _partyAlive = {}  -- [name] = true while alive

-- In-flight split cache: the objective clear times of the run currently being
-- played, so a /reload can back-stamp them instead of re-timing them (a count
-- objective cannot be re-timed — it has no back-date source). Identity-stamped
-- "mapID:level"; see MPT.CacheBelongsToRun.
--
-- Lives in db.GLOBAL, deliberately. It is transient RUN state, not user config,
-- and it used to sit on MPT.db (= KE.db.profile.MythicPlusTimer) — where an
-- AceDB profile switch mid-run rebinds it wholesale (ProfileManager:
-- RefreshAllModules -> UpdateDB), handing the live run a stale cache from
-- ANOTHER profile's earlier run. Those splits PREDATE the current run clock, so
-- they read as entirely plausible and no downstream sanity check can catch them;
-- CommitSplits would then persist one as a personal best, and improve-only makes
-- a too-low value immortal — the exact poison this module was just fixed to
-- remove. Global storage is not rebound by a profile switch, so the vector is
-- closed at the source rather than guarded against.
local function GetRunSplitCache()
    return KE.db and KE.db.global and KE.db.global.MPTActiveRunSplits or nil
end

local function SetRunSplitCache(cache)
    if KE.db and KE.db.global then KE.db.global.MPTActiveRunSplits = cache end
end

-- Single shared run state (the contract's MPT.run). Reset by MPT:ResetRun(),
-- which wipes the array tables in place (affixIDs/affixNames/objectives/deathLog);
-- thresholds is re-assigned (tiny flat table, once per run).
MPT.run = {
    active = false, completed = false,
    mapID = nil, level = 0, affixIDs = {}, affixNames = {}, affixFileIDs = {},
    affixNamesStr = nil,
    mapName = nil,        -- localized dungeon name (ShowDungeonName key row)
    msBase = nil,         -- live-ms clock anchor: re-glued each flip by OnTimerTick (HUD driver nil-inits pre-first-flip)
    maxTime = 0, thresholds = { plus1 = 0, plus2 = 0, plus3 = 0 },
    elapsed = 0, lastTickedSec = -1,
    deaths = 0, deathTimeLost = 0, deathLog = {},
    forces = { total = 0, current = 0, percent = 0, completed = false },
    objectives = {},
    bestOverall = nil,
}

-- Frame handles (created once in MPT:BuildHUD, lives in _HUD file).
MPT.frames = MPT.frames or {}

---------------------------------------------------------------------------------
-- Pure helpers (busted-testable — no frame or WoW API access)
---------------------------------------------------------------------------------

-- Pure: seconds -> "MM:SS" or "MM:SS.mmm". Busted-testable.
function MPT.FormatTime(sec, withMs)
    if not sec or sec < 0 then sec = 0 end
    local whole = floor(sec)
    local m = floor(whole / 60)
    local s = floor(whole % 60)
    if withMs then
        local ms = floor(((sec - whole) * 1000) + 0.5)
        if ms >= 1000 then
            whole = whole + 1
            m = floor(whole / 60)
            s = floor(whole % 60)
            ms = 0
        end
        return format("%02d:%02d.%03d", m, s, ms)
    end
    return format("%02d:%02d", m, s)
end

-- Pure: seconds -> "MM:SS.d" — one truncated decisecond digit, the live ms
-- driver's 10 Hz form (the frozen completion time keeps FormatTime's full
-- .mmm). Truncation, not rounding: the digit must never carry into the
-- seconds field. Busted-testable.
function MPT.FormatTimeDeci(sec)
    if not sec or sec < 0 then sec = 0 end
    local whole = floor(sec)
    local d = floor((sec - whole) * 10)
    return format("%02d:%02d.%d", floor(whole / 60), floor(whole % 60), d)
end

-- Pure: peril-aware +3/+2/+1 cutoff seconds. hasPeril => recompute on (maxTime-90).
-- plus1 = full limit, plus2 = 80%, plus3 = 60%. Busted-testable.
-- Allocates a new table per call — callers cache the result (compute once per run).
function MPT.ComputeThresholds(maxTime, hasPeril)
    maxTime = maxTime or 0
    if maxTime <= 0 then
        return { plus1 = 0, plus2 = 0, plus3 = 0 }
    end
    local plus2 = maxTime * PLUS_TWO_RATIO
    local plus3 = maxTime * PLUS_THREE_RATIO
    if hasPeril then
        local base = maxTime - 90
        if base > 0 then
            plus2 = base * PLUS_TWO_RATIO + 90
            plus3 = base * PLUS_THREE_RATIO + 90
        end
    end
    return { plus1 = maxTime, plus2 = plus2, plus3 = plus3 }
end

-- Pure: remaining seconds until a cutoff (never negative). Busted-testable.
function MPT.ThresholdRemaining(elapsed, cutoff)
    return max(0, (cutoff or 0) - (elapsed or 0))
end

-- Pure: the LINES-mode race line — which chest tier is being raced and how
-- it's going. Returns (tier, cutoff, value, state):
--   tier   3|2|1 (1 only while plusOneRace races the depletion deadline)
--   cutoff that tier's cutoff in seconds
--   value  seconds remaining (RACING/LOCKED_MADE) or overshoot (OVER/LOCKED_MISSED)
--   state  "RACING" | "OVER" | "LOCKED_MADE" | "LOCKED_MISSED"
-- plusOneRace (elapsed-bearing timer formats): after +2 falls, race the +1
-- deadline live — the count-up big timer never shows time-remaining, so the
-- line carries it. REMAINING formats pass false (their big timer IS the +1
-- countdown) and keep the +2 overshoot. Completion in the missed-+2 window
-- ALWAYS locks the +2 delta (user direction 2026-07-02), so the lock is
-- identical with the flag on or off.
-- completed=true picks the locked state — CompleteRun freezes run.elapsed,
-- so the "lock" is the caller re-rendering the frozen value.
-- nil while thresholds are unusable (maxTime-0 reload-repair window).
-- Busted-testable (dev/spec/mpt_raceline_spec.lua).
function MPT.ResolveRaceLine(elapsed, thresholds, completed, plusOneRace)
    if not thresholds or (thresholds.plus2 or 0) <= 0 then return nil end
    elapsed = elapsed or 0
    local t3, t2, t1 = thresholds.plus3, thresholds.plus2, thresholds.plus1
    if elapsed <= t3 then
        return 3, t3, t3 - elapsed, completed and "LOCKED_MADE" or "RACING"
    elseif elapsed <= t2 then
        return 2, t2, t2 - elapsed, completed and "LOCKED_MADE" or "RACING"
    end
    if completed then
        return 2, t2, elapsed - t2, "LOCKED_MISSED"
    end
    if plusOneRace and t1 and t1 > 0 then
        if elapsed <= t1 then
            return 1, t1, t1 - elapsed, "RACING"
        end
        return 1, t1, elapsed - t1, "OVER"
    end
    return 2, t2, elapsed - t2, "OVER"
end

-- Pure: worst-case timer-row string per TimerFormat, for the PB tuck's
-- width reservation ("8" as the widest-digit assumption). showMs reserves
-- the millisecond form of the elapsed part — pass true when the live
-- toggle is on OR the run is completed (the frozen completion time always
-- shows ms); REMAINING modes never display ms. Returns (template, sepGaps):
-- split-FontString rows (changing | "/" | total) carry their side gaps as
-- anchor offsets, so the template is SPACE-FREE and sepGaps tells the
-- caller how many TIMER_SEP_GAP gaps to add to the measured width.
-- Minutes render %02d uncapped — a >99-minute string would exceed the
-- reservation; irrelevant for M+ (max ~44 min), documented deliberately.
-- Busted-testable (dev/spec/mpt_raceline_spec.lua).
function MPT.BuildTimerTemplate(mode, showMs)
    local ela = showMs and "88:88.888" or "88:88"
    if mode == "REMAINING" then return "88:88", 0 end
    if mode == "REMAINING_TOTAL" then return "88:88/88:88", 2 end
    if mode == "ELAPSED" then return ela, 0 end
    if mode == "ELAPSED_DETAIL" then return ela .. " (88:88 / 88:88)", 0 end
    return ela .. "/88:88", 2   -- ELAPSED_TOTAL (default)
end

-- Pure: live-milliseconds display clock. GetWorldElapsedTime only carries
-- whole seconds (its fraction is always 0), so the HUD's ms driver runs a
-- GetTimePreciseSec-based clock glued to the authoritative one. OnTimerTick
-- re-anchors run.msBase at every whole-second flip (phase error = flip
-- detection latency), so between corrections this is pure pass-through:
--   * pass the precise clock through untouched (smooth)
--   * snap FORWARD when the authoritative clock is ahead (stale first
--     anchor before the first flip, or a death-penalty leap landing
--     between driver frames)
--   * never snap backward — when the authoritative feed stalls, the
--     precise clock free-runs ahead; yanking it back to a stale tick
--     re-created the per-second sawtooth this replaced (2026-07-02)
-- Returns (displaySeconds, newMsBase). Busted-testable
-- (dev/spec/mpt_raceline_spec.lua).
function MPT.LiveMsElapsed(now, msBase, elapsed)
    elapsed = elapsed or 0
    if not msBase then msBase = now - elapsed end
    local p = now - msBase
    if p < elapsed then
        msBase = now - elapsed
        p = elapsed
    end
    return p, msBase
end

-- Posts a one-line boss-kill split to the group channel (INSTANCE_CHAT / RAID /
-- PARTY). Called from the fresh-stamp arm of UpdateObjectives ONLY — the
-- restoration arm (reload mid-run) must never re-post. Guard: ChatOutputSplits
-- DB toggle, objective must be completed, not InCombatLockdown (avoids mid-pull
-- spam noise; SendChatMessage itself is fine in combat), and a channel must exist
-- (solo runs are silently dropped). Appends a "+/- vs PB" delta when pbTime is
-- available. Uses MPT.FormatTime (pure helper) for time formatting.
function MPT:ChatOutputBossSplit(objective)
    if not SendChat then return end
    if not self.db.ChatOutputSplits then return end
    if not objective or not objective.completed then return end
    if InCombatLockdown() then return end  -- skip mid-pull spam noise

    local channel = ResolveGroupChannel()
    if not channel then return end

    local clearStr = MPT.FormatTime(objective.clearTime or 0, false)
    local msg = format("%s: %s", objective.name or "Boss", clearStr)

    -- Append PB delta when we have a per-boss PB to compare against.
    if objective.pbTime then
        local delta = (objective.clearTime or 0) - objective.pbTime
        local sign = delta <= 0 and "-" or "+"
        msg = msg .. format(" (%s%s vs PB)", sign, MPT.FormatTime(abs(delta), false))
    end

    SendChat(msg, channel)
end

-- Canonical flat defaults (seeded into KE.db.profile.MythicPlusTimer
-- by MPT:UpdateDB). Flat keys only — no nesting (KE convention). Colors are
-- {r,g,b} arrays resolved via KE:ResolveColor at render time.
local MPT_DEFAULTS = {
    Enabled = true,

    -- Position (consumed by KE:ApplyFramePosition / CreatePositionCard).
    -- ParentFrame deliberately unseeded (position card writes it on demand).
    -- anchorFrameType is intentionally camelCase — the position card reads that literal key.
    SelfPoint = "RIGHT", AnchorPoint = "RIGHT", anchorFrameType = "SCREEN",
    XOffset = 0, YOffset = 198, Strata = "MEDIUM", Scale = 1.0,

    -- Timer
    TimerFormat = "ELAPSED_TOTAL",  -- ELAPSED_TOTAL|REMAINING|REMAINING_TOTAL|ELAPSED|ELAPSED_DETAIL
    ShowMilliseconds = false,
    TimerColor = {1, 1, 1},
    TimerSuccessColor = {0, 1, 0.14},
    TimerExpiredColor = {1, 0.16, 0.18},

    -- Timer bar + thresholds
    BarTexture = "KitnUI",
    BarWidth = 275, BarHeight = 14,
    RowSpacing = 2,   -- vertical gap between stacked HUD rows AND boss rows
    BarColor = {0.56, 0.56, 0.56},
    BarBackgroundColor = {0.031, 0.031, 0.031},  -- empty-track tint, both bars (#080808; fixed 0.8 alpha)
    StateColorFill = false,
    TickColor = {1, 1, 1},
    ShowThresholdLabels = true,
    -- EDGE (default): half-in/half-out on the bar's top edge (the edge-straddling look)
    -- ABOVE: centered over the tick, fully above | INSIDE: fully on the bar
    ThresholdPlacement = "EDGE",

    -- Forces
    ShowForces = true,
    ShowForcesBar = true,   -- bar-only visibility; text stays (all-text HUD)
    ForcesFormat = "PERCENT",   -- PERCENT|COUNT|COUNT_PERCENT|REMAINING|CUSTOM
    -- EDGE (default): half-in/half-out on the bar's bottom-right corner
    -- (the edge-straddling look) | CORNER: fully below | CENTER | BESIDE
    ForcesPlacement = "EDGE",
    ForcesColor = {0.73, 0.62, 0.13},
    ForcesCompleteColor = {0, 1, 0.14},  -- % TEXT color once forces cap (the bar fill no longer recolors)
    ForcesTextColor = {1, 1, 1},  -- percent/count text — independent of the bar fill
    ForcesCustomFormat = ":count:/:totalcount: :percent:",
    ForcesBracketStyle = "NONE",  -- NONE|SQUARE|ROUND (wraps the count portion)
    ForcesBandedColors = false,
    -- 5-band quintile palette (0-19 / 20-39 / 40-59 / 60-79 / 80-99 %) plus a
    -- distinct 100% color, used by RenderForces when ForcesBandedColors is on
    -- (at completion the bar keeps its Full band; ForcesCompleteColor moves
    -- to the % text instead).
    ForcesBandPalette = {
        {1, 0.459, 0.502},        -- 0-19%
        {1, 0.510, 0.282},        -- 20-39%
        {1, 0.773, 0.404},        -- 40-59%
        {1, 0.976, 0.588},        -- 60-79%
        {0.408, 0.804, 1},        -- 80-99%
        Full = {0.804, 1, 0.655}, -- 100%
    },
    -- Hidden/disabled pull-preview overlay (dead on 12.0 — per-unit forces are
    -- secret; see memory project_warpdeplete_forces_preview_blocked). No data
    -- feed; GUI exposes nothing.
    ShowPullOverlay = false,

    -- Objectives / boss list
    ShowObjectives = true,
    ShowObjectiveTimes = true,  -- the clear time on completed rows
    ShowPBDelta = true,         -- the (+/-) delta beside a clear time
    -- Visibility of the "PB m:ss" TARGET (pending boss rows + the live
    -- timer/forces PB), gated by MPT:ShouldShowRecords: ALWAYS keeps it up for
    -- the whole run; COUNTDOWN (default) shows it only before the timer starts
    -- ticking and hides it for the live run so the HUD stays clean; NEVER hides
    -- it entirely. The completed-row (+/-) deltas are independent (ShowPBDelta).
    SplitsShowMode = "COUNTDOWN",   -- ALWAYS|COUNTDOWN|NEVER
    -- Which side of a boss row the clear time / PB target sits on, for KE's
    -- right-aligned HUD: END (default) clusters it at the right edge beside the
    -- name; START pins it at the row's left edge with the name right-justified.
    ObjectiveTimePosition = "END",  -- END|START
    -- No-exact-record PB fallback when no record matches the exact key level:
    -- CLOSEST|CLOSEST_LOWER|CLOSEST_HIGHER|HIGHEST|LOWEST|OFF
    PBFallbackMode = "CLOSEST",
    ObjectiveColor = {0.85, 0.85, 0.85},
    ObjectiveDoneColor = {0, 1, 0.14},
    SplitAheadColor = {0.25, 0.88, 0.82},
    SplitBehindColor = {1, 0.34, 0.34},
    PBColor = {0.81, 0.81, 0.81},
    PBOpacity = 1.0,

    -- Deaths
    ShowDeaths = true,
    ShowDeathTooltip = true,
    DeathsColor = {0.85, 0.85, 0.85},
    DeathPenaltyColor = {1, 0.42, 0.42},

    -- Affixes / key
    ShowAffixes = true,
    AffixMode = "TEXT",         -- TEXT|ICON
    AffixColor = {0.69, 0.69, 0.69},
    ShowKeyLevel = true,
    KeyColor = {1, 1, 1},
    -- Appends the dungeon name to the key bracket ("+12 Nexus-Point Xenas").
    ShowDungeonName = false,

    -- Enemy overlay (folded from the retired forces-overlay module).
    -- Nameplate per-mob forces % + enemy-tooltip count via
    -- C_ScenarioInfo.GetUnitCriteriaProgressValues (12.0.5 API). Full key set
    -- lives here (canonical).
    -- OverlayNameplateEnabled defaults the nameplate percent off.
    OverlayNameplateEnabled = false,
    OverlayTooltipEnabled = true,
    OverlayFormat = "%s%%", -- a string.format spec (NOT an enum) applied to the
                            -- pre-formatted percentValueString (API return #3 —
                            -- "0.87", NO percent sign; live-confirmed 2026-07-02)
    OverlayCombatOnly = true,
    OverlayFontFace = "Expressway",
    OverlayFontSize = 12,
    OverlayFontOutline = "OUTLINE",
    OverlayColorMode = "theme",
    OverlayColor = {1, 1, 1},
    OverlayAnchor = "TOPRIGHT",
    OverlayXOffset = -20,
    OverlayYOffset = 2,

    -- QoL
    AutoInsertKeystone = true,
    HideBlizzardTracker = true,
    ChatOutputSplits = false,

    -- Backdrop
    BackdropEnabled = false,
    BackdropColor = {0, 0, 0},
    BackdropOpacity = 0.6,

    -- Fonts (global default + per-element overrides resolved at render)
    FontFace = "Expressway", FontSize = 15, FontOutline = "OUTLINE",
    TimerFontFace = "Expressway", TimerFontSize = 32, TimerFontOutline = "OUTLINE",
    ForcesFontFace = "Expressway", ForcesFontSize = 16, ForcesFontOutline = "OUTLINE",
    ObjectiveFontFace = "Expressway", ObjectiveFontSize = 16, ObjectiveFontOutline = "OUTLINE",
    DeathsFontFace = "Expressway", DeathsFontSize = 15, DeathsFontOutline = "OUTLINE",
}

-- Recursive deep-copy so the profile section never shares table identity with
-- MPT_DEFAULTS (a profile reset must regenerate independent tables).
local function DeepCopy(src)
    if type(src) ~= "table" then return src end
    local dst = {}
    for k, v in pairs(src) do dst[k] = DeepCopy(v) end
    return dst
end

-- Aggregate enemy forces from the weighted criterion. Plain math: GetCriteriaInfo
-- quantity/quantityString/totalQuantity are proven non-secret (Task 1.1 dry-run);
-- per the contract's "DO NOT GUARD" set, no issecretvalue here.
function MPT:UpdateForces()
    local run = self.run
    local f = run.forces
    local numCriteria = select(3, C_Scenario.GetStepInfo()) or 0
    -- Scenario step absent (pre-pull countdown) or torn down (key just
    -- completed): GetStepInfo reports 0 criteria. Preserve the last-known
    -- forces instead of zeroing it — otherwise the frozen completion summary
    -- loses its 100% forces bar. StartRun already seeds forces to 0 for the
    -- countdown, so the empty-step case there is unchanged.
    if numCriteria == 0 then return end
    for i = 1, numCriteria do
        local info = C_ScenarioInfo.GetCriteriaInfo(i)
        if info and info.isWeightedProgress then
            -- quantityString carries the absolute count with a stray '%'. Locale-safe
            -- parse: strip '%', treat a comma with no dot as a decimal separator
            -- (DE/FR clients), then tonumber. Cached on the raw string —
            -- criteria events fire far more often than the count actually changes.
            local qs = info.quantityString
            local current
            if qs == f._lastQS then
                current = f._lastQSParsed or 0
            else
                current = 0
                if qs and qs ~= "" then
                    local normalized = qs:gsub("%%", "")
                    if normalized:find(",") and not normalized:find("%.") then
                        normalized = normalized:gsub(",", ".")
                    end
                    current = tonumber(normalized) or 0
                end
                f._lastQS, f._lastQSParsed = qs, current
            end
            local total = info.totalQuantity or 0
            -- Monotonic count (never decreases): the weighted criterion reports a
            -- current of 0 in the scenario teardown window right before
            -- CHALLENGE_MODE_COMPLETED. Accept only increases so that transitional
            -- 0 can never empty a near-100% forces bar.
            -- (Forces never legitimately decrease in M+ — you can't un-tag.)
            if current > (f.current or 0) then f.current = current end
            f.total = total
            if total > 0 then
                f.percent = (f.current / total) * 100
            else
                f.percent = 0
            end
            -- Sticky completion: once forces read 100% it stays complete — the
            -- teardown read must not un-complete it. clearTime captured once,
            -- back-dated via info.elapsed (reload-safe: the false->true transition
            -- re-derives the cap moment without a persisted cache).
            local wasCompleted = f.completed
            if info.completed or (total > 0 and f.current >= total) then
                f.completed = true
                if not wasCompleted then
                    f.clearTime = (run.elapsed or 0) - (info.elapsed or 0)
                end
            end
            return
        end
    end
    -- No weighted criterion this step (e.g. countdown before the scenario
    -- populates, or the teardown window where it drops out of the step list).
    -- Don't clobber an already-completed forces bar — only zero one that never
    -- started (StartRun seeds 0 for the countdown, so that case is unaffected).
    if not f.completed then
        f.current, f.total, f.percent = 0, 0, 0
    end
end

-- Boss/objective rows from non-weighted criteria. Names stored raw; the HUD
-- truncates via SetWidth+SetWordWrap(false) (engine-side, no Lua string read).
-- pbTime is left nil here — MPT:ResolvePB (Splits phase) fills it per run.
-- Plain reads: GetCriteriaInfo description/completed/elapsed and
-- GetStepInfo are non-secret (contract "DO NOT GUARD" set).
-- (GetWorldElapsedTime removed from this path; info.elapsed back-dates instead.)
-- Reload-safe: clearTime is back-stamped via _activeRunSplits so a /reload
-- mid-run restores prior kill times without re-triggering chat output (Task 5.3).
function MPT:UpdateObjectives()
    local run = MPT.run
    local numCriteria = select(3, C_Scenario.GetStepInfo()) or 0  -- non-secret loop bound
    local elapsed = run.elapsed or 0
    local objIdx = 0

    -- ONE live clock for this pass. run.elapsed is refreshed only by OnTimerTick
    -- (deduped to once per whole second), so it lags a criteria event by up to
    -- ~1s. The count-objective stamp and the cache provenance bound below MUST
    -- share the same clock: stamping from the live clock while bounding against
    -- the cached one makes a legitimately-stamped split read as "in the future"
    -- (saved 101 vs elapsed 100) and get thrown away.
    --
    -- Only while the run is live. In CompleteRun's backfill pass run.elapsed is
    -- the authoritative final time (GetChallengeCompletionInfo — the world clock
    -- goes stale post-depletion, the "99:99" class), so there it wins.
    local liveElapsed = elapsed
    if not run.completed then
        local _, live = GetWorldElapsedTime(1)
        if live and live >= 0 then liveElapsed = live end
    end

    for i = 1, numCriteria do
        local info = C_ScenarioInfo.GetCriteriaInfo(i)
        if info and not info.isWeightedProgress then
            objIdx = objIdx + 1
            local obj = run.objectives[objIdx]
            if not obj then
                obj = { name = "", completed = false, clearTime = nil, pbTime = nil,
                        quantity = 0, totalQuantity = 1, criteriaIndex = i }
                run.objectives[objIdx] = obj
            end
            obj.criteriaIndex = i

            -- Count-based objectives (e.g. Pit of Saron "Quarry Camps" 0/6).
            -- quantity/totalQuantity are aggregate GetCriteriaInfo fields
            -- (contract DO-NOT-GUARD set, read raw). Plain boss criteria report
            -- totalQuantity 0/1 — normalize to 0-or-1 / 1 so the HUD's
            -- `totalQuantity > 1` prefix gate skips them.
            obj.quantity = info.quantity or 0
            obj.totalQuantity = info.totalQuantity or 0
            if obj.totalQuantity == 0 then
                obj.quantity = (info.completed and 1) or 0
                obj.totalQuantity = 1
            end

            -- Strip Blizzard's leading checkmark (U+2713 = 0xE2 0x9C 0x93) + dash.
            -- Gated on the raw string — this fires per SCENARIO_CRITERIA_UPDATE,
            -- and names are stable after CHALLENGE_MODE_START; skip the gsub churn.
            local rawName = info.description or ("Objective " .. i)
            if rawName ~= obj._rawName then
                obj._rawName = rawName
                local name = rawName:gsub("^\226\156\147%s*", ""):gsub("^%-%s*", "")
                -- Drop Blizzard's "defeated" suffix from boss criteria, then trim.
                name = name:gsub("[Dd]efeated", "")
                obj.name = name:match("^%s*(.-)%s*$") or name
            end

            -- Sticky completion (write-once): once a boss criterion reads complete
            -- it STAYS complete with its captured clear time. At key completion the
            -- scenario teardown momentarily re-reports finished criteria as
            -- incomplete (elapsed 0); without this a single transitional read grays
            -- the row and nils its clear time in the frozen summary.
            -- Reversion is never legitimate for an M+ boss/count criterion.
            local wasCompleted = obj.completed
            if info.completed and not wasCompleted then
                obj.completed = true
                -- Reload survival: reuse the persisted split only when it
                -- belongs to THIS run (identity-stamped "mapID:level"). A
                -- stale cache from another key must never back-stamp — see
                -- CHALLENGE_MODE_START's staleness wipe for the
                -- cross-session leak path.
                local cache = GetRunSplitCache()
                local runKey = MPT.BuildSplitKey(run.mapID, run.level)
                -- Tolerates the reload-recovery level-0 window, where an exact
                -- key compare misses and a count objective would otherwise be
                -- re-stamped at the reload time (see MPT.CacheBelongsToRun).
                local cacheOK = MPT.CacheBelongsToRun(cache, run.mapID, run.level)
                local saved = cacheOK and cache[objIdx]
                -- Provenance backstop: a split can never postdate the run clock,
                -- because elapsed only advances within a run. Bounded against
                -- liveElapsed, NOT the cached run.elapsed — a count split is
                -- stamped from the live clock, so bounding it against the lagging
                -- cached value rejects legitimate data (saved 101 vs elapsed 100).
                --
                -- This is a backstop only. It catches a foreign cache whose
                -- splits postdate this run, but NOT one whose splits predate it
                -- (an older run's 60s split looks fine against a 300s clock) —
                -- and that direction is the dangerous one, since a too-LOW value
                -- committed as a PB is exactly the immortal poison this branch
                -- exists to remove. Cross-run adoption is prevented at the
                -- source, by wiping the cache in OnDisable (see there).
                if saved and liveElapsed > 0 and saved > liveElapsed then
                    cacheOK, saved = false, nil
                end
                -- Count/progress criteria (Quarry Camps 6/6) leave info.elapsed
                -- pinned to the FIRST increment (1/6) — it never advances to the
                -- 6/6 moment — so back-dating (elapsed - info.elapsed) yields the
                -- time the first camp was tagged, not the completion. (Confirmed
                -- against the MPlusTimer + EllesmereUIMythicTimer references, which
                -- both stamp the live world clock at the completion transition for
                -- this case rather than trusting the criterion's elapsed.) Boss
                -- criteria report elapsed as time-since-completed, so they still
                -- back-date correctly. totalQuantity > 1 marks the count case
                -- (same gate the HUD uses for the "6/6" name prefix).
                local isCountObjective = (obj.totalQuantity or 1) > 1
                if saved and saved > 0 then
                    obj.clearTime = saved
                else
                    if isCountObjective then
                        -- SCENARIO_CRITERIA_UPDATE fires at the completing
                        -- increment, so the run clock IS the 6/6 moment — but it
                        -- has to be read LIVE. The `elapsed` upvalue is
                        -- run.elapsed, which only OnTimerTick refreshes, and that
                        -- dedupes to once per whole second (lastTickedSec). Using
                        -- it here stamps the previous tick, up to ~1s early — and
                        -- since this time becomes the stored PB, that optimism
                        -- would be baked into every future delta.
                        --
                        -- ONLY while the run is live. CompleteRun sets
                        -- run.completed, then resolves the authoritative final
                        -- time (GetChallengeCompletionInfo, precisely because
                        -- GetWorldElapsedTime goes stale post-depletion — the
                        -- "99:99" class), and only then calls UpdateObjectives to
                        -- backfill. Re-reading the world clock in THAT pass would
                        -- override the authoritative value with a stale one, and
                        -- CommitSplits would persist it as a PB — improve-only,
                        -- so a stale-low value would poison the record exactly
                        -- like the bug this all fixes. There, run.elapsed wins.
                        --
                        -- Boss criteria need none of this: they back-date off
                        -- info.elapsed, which is exact.
                        obj.clearTime = liveElapsed
                    else
                        -- Back-dated to the actual kill moment:
                        -- info.elapsed is the time since this criterion completed.
                        obj.clearTime = elapsed - (info.elapsed or 0)
                    end
                    -- Create-or-rekey: also displaces a legacy keyless table.
                    -- Gate on cacheOK, NOT on an exact key compare: during the
                    -- level-0 window the key differs but the cache is ours, and
                    -- rekeying would throw away the very splits it is holding.
                    if not cacheOK then
                        cache = { key = runKey }
                        SetRunSplitCache(cache)
                    end
                    cache[objIdx] = obj.clearTime
                    -- Fresh-stamp arm ONLY (never the restoration arm above), AND
                    -- only near-real-time completions: a reload-recovery pass can
                    -- re-walk old kills through this arm when the persisted cache
                    -- was discarded (identity mismatch on a level-0 API race) —
                    -- their back-dated clearTime keeps chat silent (Task 5.3).
                    -- The chat line is a boss-kill announcement; count objectives
                    -- (which now stamp elapsed, so delta is always 0) are excluded.
                    if not isCountObjective and (elapsed - obj.clearTime) <= 5 then
                        self:ChatOutputBossSplit(obj)
                    end
                end
            end
        end
    end

    -- Trim stale rows beyond the live criteria count — but ONLY while the
    -- scenario still reports criteria. At key completion GetStepInfo flips to
    -- 0; an unconditional trim would wipe the whole boss list out of the frozen
    -- summary AND leave CommitSplits nothing to persist (the root cause of
    -- per-boss PB splits never accumulating). Preserve the rows in that case.
    if numCriteria > 0 then
        for i = objIdx + 1, #run.objectives do
            run.objectives[i] = nil
        end
    end

    -- Resolve PB targets/deltas for each objective (Splits, Task 3.6).
    MPT:UpdateSplits()
end

-- Seed KE.db.profile.MythicPlusTimer from MPT_DEFAULTS for any key
-- the saved profile is missing (mirrors KE:FillProfileDefaults' deep-fill
-- intent, scoped to this module), then bind MPT.db. Also guarantee the global
-- splits store. Splits keyed "mapID:level" -> { total=sec, objectives={...} }.
-- NAME IS LOAD-BEARING: ProfileManager:RefreshAllModules
-- (Core/ProfileManager.lua:417-419) duck-types `module.UpdateDB` and re-runs
-- this on every profile switch/copy/reset — re-seeding the new profile's
-- section and re-binding self.db. Do not rename.
function MPT:UpdateDB()
    local profile = KE.db.profile
    if type(profile.MythicPlusTimer) ~= "table" then
        profile.MythicPlusTimer = {}
    end
    local saved = profile.MythicPlusTimer
    for k, v in pairs(MPT_DEFAULTS) do
        if saved[k] == nil then
            saved[k] = DeepCopy(v)
        end
    end
    self.db = saved

    -- Persisted-value repairs: early dev builds saved the retired enum value
    -- "PERCENT"; builds through 2026-07 saved the numeric spec "%.2f%%" for
    -- what is now Blizzard's pre-formatted percent STRING (the overlay binds
    -- GetUnitCriteriaProgressValues return #3 — %.2f on it would error), then
    -- briefly the bare "%s" passthrough, which dropped the % sign the string
    -- doesn't carry (live-confirmed 2026-07-02). Normalize all three to "%s%%".
    -- OverlayFormat has no GUI control, so no user-customized value exists.
    if self.db.OverlayFormat == "PERCENT" or self.db.OverlayFormat == "%.2f%%"
        or self.db.OverlayFormat == "%s" then
        self.db.OverlayFormat = "%s%%"
    end

    -- MigrateLegacyOverlayDB lives in MythicPlusTimer_Overlay.lua, which is
    -- loaded later in the XML manifest — but all files are parsed before any
    -- AceAddon OnInitialize fires (ADDON_LOADED triggers after the parse phase),
    -- so the method is guaranteed to exist by the time UpdateDB first runs.
    -- No existence guard needed.
    self:MigrateLegacyOverlayDB()

    if type(KE.db.global.MythicPlusTimerSplits) ~= "table" then
        KE.db.global.MythicPlusTimerSplits = {}
    end
end

-- Wipe this module's persisted profile section and regenerate every key from
-- MPT_DEFAULTS, then re-apply to the live HUD. Backs the GUI "Reset to Defaults"
-- button. Everything in the section returns to default (position, colors, fonts,
-- sizes, toggles); the on/off state is preserved (a settings reset shouldn't
-- silently enable/disable the module), and the global PB-splits store
-- (KE.db.global, not this section) is left intact — reset settings, keep records.
function MPT:ResetToDefaults()
    local profile = KE.db.profile
    local wasEnabled = self.db and self.db.Enabled
    local wasMigrated = self.db and self.db.OverlayMigrated
    if type(profile.MythicPlusTimer) == "table" then
        wipe(profile.MythicPlusTimer)   -- in place: keep table identity for any held refs
        -- Re-plant the migration stamp BEFORE UpdateDB: MigrateLegacyOverlayDB runs
        -- inside UpdateDB and would otherwise re-import the retired (deliberately
        -- orphaned) profile.Dungeons.WarpDepleteForces keys over the fresh defaults.
        if wasMigrated then profile.MythicPlusTimer.OverlayMigrated = true end
    end
    self:UpdateDB()                     -- re-seed all defaults + re-bind self.db
    if wasEnabled ~= nil then self.db.Enabled = wasEnabled end
    self:ApplySettings()                -- busts caches, re-applies layout/colors to the live HUD
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------

function MPT:OnInitialize()
    self:UpdateDB()
    -- Default-disable: the addon-level OnEnable loop (Core/Main.lua:154-163)
    -- owns the enable decision via db.Enabled (sibling pattern).
    self:SetEnabledState(false)
end

function MPT:OnEnable()
    if not self.db.Enabled then return end
    self:InstallTickHook()
    -- Always-on (low-frequency) tier — enough to detect a key starting.
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("CHALLENGE_MODE_START")
    self:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    self:RegisterEvent("CHALLENGE_MODE_RESET")
    self:RegisterEvent("WORLD_STATE_TIMER_START")
    self:RegisterEvent("WORLD_STATE_TIMER_STOP")
    self:RegisterEvent("CHALLENGE_MODE_DEATH_COUNT_UPDATED")
    self:RegisterEvent("UPDATE_INSTANCE_INFO")
    self:RegisterEvent("CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN")
    -- Wire the enemy overlay (tooltip post-call + optional nameplate events).
    -- InitOverlay is defined in MythicPlusTimer_Overlay.lua, loaded after this
    -- file in Dungeons.xml — guaranteed to exist at runtime (same guarantee as
    -- MigrateLegacyOverlayDB which is called from UpdateDB without a guard).
    self:InitOverlay()
    -- Build the HUD if its file is loaded (Task 2.1 defines BuildHUD). Guard is
    -- MANDATORY in Phase 1 — the HUD file does not exist yet; mirrors the
    -- PurgeStaleSplits guard idiom below.
    if self.BuildHUD then self:BuildHUD() end
    self:RegWithEditMode()
    -- Restore HUD if we /reload'd mid-key.
    self:CheckForActiveRun()
    -- WarpDeplete is a competing keystone timer — recommend running only one.
    KE:WarnRedundantAddon("WarpDeplete", "WarpDeplete", "Mythic+ Timer", "/kes mt", self.db, "_warpDepleteWarned")
    -- Season-based purge of stale split records (deferred; API not ready at login).
    C_Timer.After(2, function()
        if not self:IsEnabled() then return end  -- module disabled inside the window
        self:PurgeStaleSplits()
    end)
end

function MPT:OnDisable()
    -- Preview teardown FIRST (GUI Enable-off while the page preview shows).
    -- HidePreview clears isPreview BEFORE the tracker restore below — the
    -- permanent Show-hook's ShouldHideTracker would otherwise see isPreview,
    -- synchronously re-hide the tracker on otf:Show(), and steal _keHidTracker
    -- ownership (tracker stuck hidden until /reload) — the same hook trap
    -- documented for run.active below. It also hides the preview HUD and
    -- restores self.run from _savedRun so the run-state clears below act on
    -- the REAL run table. (PreviewManager won't re-show: ShowSectionPreviews
    -- gates on db.Enabled; sibling Enable-toggle-kills-preview pattern.)
    if self.isPreview then self:HidePreview() end
    -- Pending refresh timer must not render on a disabled module; ticker must detach.
    self:StopTimerLoop()
    self._refreshQueued = nil
    self._salvagePending = nil  -- pending salvage timer fires inert (run cleared below)
    -- Overlay teardown: UnregisterAllEvents below kills the plate events, but the
    -- 0.5s nameplate ticker and any attached plate texts survive without this.
    self:SetOverlayActive(false)
    -- Close the permanent tick hook's gate: run.active is the documented
    -- disable safeguard (the hooksecurefunc is never removed), so a disabled
    -- module would otherwise keep running the full per-second pipeline —
    -- including chat boss splits. It also lets ShouldHideTracker fall through
    -- for the restore below: otf:Show() synchronously fires the permanent
    -- Show-hook, which would re-hide the tracker and steal _keHidTracker
    -- ownership while run.active still read true (tracker stuck hidden until
    -- /reload). Re-enable mid-key rebuilds via CheckForActiveRun -> StartRun,
    -- the same path a /reload uses (clear times restore from _activeRunSplits).
    self.run.active = false
    self.run.completed = false
    -- Restore a tracker WE hid (mid-key disable would otherwise leave it hidden
    -- until /reload). Direct Show — the frame is not protected (see the
    -- ApplyTrackerVisibility comment), so no combat defer is needed.
    if self._keHidTracker then
        local otf = _G.ObjectiveTrackerFrame
        if otf and not otf:IsShown() then otf:Show() end
        self._keHidTracker = nil
        if DEBUG_MPT then KE:Print("[MPT] OnDisable: tracker restored") end
    end
    -- Drop the in-flight split cache. Every other clear (CHALLENGE_MODE_START,
    -- CompleteRun, ResetRun) is event-driven, and the UnregisterAllEvents below
    -- blinds us — so a cache kept across a disable has unknown provenance: a key
    -- can start and finish while we are dark. A later run of the same map would
    -- then adopt another run's clear times, and CommitSplits would persist them.
    -- A stale split that PREDATES the new run reads as perfectly plausible
    -- against its clock, so no sanity check downstream can catch it; the only
    -- sound move is to not carry the cache across the blind window at all.
    --
    -- Cost is bounded: disabling and re-enabling mid-run re-stamps that run's
    -- count objectives at the re-enable moment (bosses still back-date exactly
    -- off info.elapsed). A /reload does NOT come through here — Ace3 tears the
    -- Lua state down without OnDisable — so the reload-survival path the cache
    -- exists for is untouched.
    SetRunSplitCache(nil)

    self:UnregisterAllEvents()
    self:UnhookAll()
end

---------------------------------------------------------------------------------
-- Tick driver: debounced refresh (Task 1.6)
---------------------------------------------------------------------------------

-- Hidden frame that hosts the 1 Hz fallback OnUpdate (attached only during a run).
local tickerFrame = CreateFrame("Frame")
tickerFrame:Hide()

-- Append one death to the log. Reconciled against GetDeathCount so the log
-- never drifts (the headline is authoritative; this is the hover detail).
-- guid path: guarded (enemy GUIDs are secret). unit/name path: party-scan,
-- non-secret. Either way we only ever resolve party members.
function MPT:RecordDeath(guid, knownName, knownUnit)
    local run = MPT.run
    local name, class
    if knownUnit then
        name = knownName or UnitName(knownUnit)
        class = select(2, UnitClass(knownUnit))
    elseif guid then
        if issecretvalue(guid) then return end          -- enemy GUID -> bail
        name = knownName or UnitNameFromGUID(guid)
        -- select(2): class FILE token ("WARRIOR") for RAID_CLASS_COLORS keys —
        -- first return is the localized name (and ConditionalSecret).
        class = select(2, UnitClassFromGUID(guid))
        if name and not UnitInParty(name) and name ~= UnitName("player") then
            return                                       -- non-party death, ignore
        end
        -- Mutual exclusion with the GetDeathCount party-scan: both paths fire
        -- for the same death (UNIT_DIED + count diff), and the front-trim
        -- reconcile in OnDeathCountUpdated would then delete an older VALID
        -- entry (log corrupts from death #2 on). Record only while the member
        -- is still marked alive, and prune the snapshot so the later scan
        -- can't append a duplicate (mirrors CheckForNewDeaths' prune).
        -- Cross-realm caveat: UnitNameFromGUID can return "Name-Realm" while
        -- the snapshot is keyed by UnitName's short form — the guid path is
        -- then muted for that member and the count-scan records the death
        -- instead (single entry either way; the scan is authoritative).
        if not name or not _partyAlive[name] then return end
        _partyAlive[name] = nil
    else
        return
    end
    if not name then return end
    run.deathLog[#run.deathLog + 1] = {
        t = run.elapsed or 0,
        name = name,
        class = class,
    }
    -- Reload/DC survival: persist the log write-through (same lifecycle as
    -- _activeRunSplits — cleared by CHALLENGE_MODE_START's staleness wipe,
    -- CHALLENGE_MODE_RESET, and CompleteRun; a mid-key walk-out SPARES it so
    -- re-entry restores). mapID-only identity is sufficient: any genuinely
    -- new same-dungeon run passes through the START wipe first, so only a
    -- recovery StartRun (reload, DC, or walk-back-in) sees the cache alive —
    -- and the restore is reconcile-trimmed against GetDeathCount right after.
    -- (No composite level key — unlike splits there is no level-keyed
    -- store to poison, and the level-0 API race would drop the restore.)
    -- cache.log shares table identity with run.deathLog, so later appends and
    -- the OnDeathCountUpdated reconcile-trim persist for free.
    local cache = MPT.db._activeRunDeaths
    if not cache or cache.mapID ~= run.mapID then
        cache = { mapID = run.mapID }
        MPT.db._activeRunDeaths = cache
    end
    cache.log = run.deathLog
end

-- Rebuilds the alive snapshot from the current party state. Called after
-- CheckForNewDeaths so the next diff starts from an up-to-date baseline.
local function ScanPartyAlive()
    wipe(_partyAlive)
    local prefix = IsInRaid() and "raid" or "party"
    local count = GetNumGroupMembers()
    for i = 1, count do
        local unit = (prefix == "party" and i == count) and "player" or (prefix .. i)
        local name = UnitName(unit)
        if name and not UnitIsDeadOrGhost(unit) then
            _partyAlive[name] = true
        end
    end
    -- Solo safety net: with GetNumGroupMembers() == 0 the loop never runs, so
    -- snapshot the player directly. In a real party the loop's i == count arm
    -- already covered "player" and this is an idempotent duplicate write.
    if prefix == "party" then
        local name = UnitName("player")
        if name and not UnitIsDeadOrGhost("player") then
            _partyAlive[name] = true
        end
    end
end

-- Diffs the new death count against the prior snapshot to find who newly died.
-- Calls MPT:RecordDeath (Task 3.4 stub for now) for each newly-dead member.
local function CheckForNewDeaths(newDeathCount)
    if newDeathCount <= _prevDeathCount then
        _prevDeathCount = newDeathCount
        return
    end
    -- Death count went up — find who is now dead that was alive last tick.
    local prefix = IsInRaid() and "raid" or "party"
    local count = GetNumGroupMembers()
    for i = 1, count do
        local unit = (prefix == "party" and i == count) and "player" or (prefix .. i)
        local name = UnitName(unit)
        if name and _partyAlive[name] and UnitIsDeadOrGhost(unit) then
            MPT:RecordDeath(nil, name, unit)
            _partyAlive[name] = nil
        end
    end
    -- Trailing solo-player block: only reached when GetNumGroupMembers()==0.
    -- The loop's (i == count) branch already maps to "player" inside any party,
    -- so this fires only for a solo run with no group members iterated above.
    if prefix == "party" then
        local name = UnitName("player")
        if name and _partyAlive[name] and UnitIsDeadOrGhost("player") then
            MPT:RecordDeath(nil, name, "player")
            _partyAlive[name] = nil
        end
    end
    _prevDeathCount = newDeathCount
end

function MPT:OnDeathCountUpdated()
    local run = MPT.run
    local count, timeLost = C_ChallengeMode.GetDeathCount()
    -- Dirty-gate the trace: only log when count actually changes.
    if DEBUG_MPT and (count or 0) ~= run.deaths then
        KE:Print(format("[MPT] OnDeathCountUpdated: count=%d timeLost=%d", count or 0, timeLost or 0))
    end
    run.deaths = count or 0
    run.deathTimeLost = timeLost or 0
    CheckForNewDeaths(run.deaths)   -- attribute the delta to party members
    ScanPartyAlive()                -- refresh snapshot for the next diff
    -- Reconcile log: authoritative count caps the log; if UNIT_DIED and the
    -- party-scan both recorded the same death, drop oldest surplus entries.
    while #MPT.run.deathLog > MPT.run.deaths do
        table.remove(MPT.run.deathLog, 1)
    end
    MPT:NotifyRefresh()
end

-- Both drivers (Blizzard hook + fallback) funnel here. Early-returns unless the
-- whole-second floor advanced -> the whole pipeline runs <=1 Hz.
function MPT:OnTimerTick()
    local run = self.run
    if not run.active then return end
    local _, elapsed = GetWorldElapsedTime(1)
    if not (elapsed and elapsed >= 0) then return end
    local sec = floor(elapsed)
    -- The hook and the 1 Hz fallback run on independent clocks; lastTickedSec floor-dedup is the only coordination.
    if sec == run.lastTickedSec then return end
    run.lastTickedSec = sec
    run.elapsed = elapsed
    -- Late keystone-info repair: two number compares per tick, fires at most
    -- once per run (see RepairRunInfo).
    if run.level == 0 or run.maxTime == 0 then self:RepairRunInfo() end
    -- API-independent clock anchor: world elapsed is authoritative here (it
    -- includes death penalties), so anchor once on the first good tick;
    -- CompleteRun uses it as the last-resort completion fallback when the
    -- world clock goes stale post-depletion.
    if not run.preciseBase and GetTimePreciseSec then
        run.preciseBase = GetTimePreciseSec() - elapsed
    end
    -- Re-glue the live-ms driver's clock at every whole-second flip: the
    -- flip is the only moment the true fraction is known (~0, within flip
    -- detection latency). A one-shot anchor bakes a stale fraction into
    -- every later second — the 2026-07-02 "spazzing" sawtooth.
    if GetTimePreciseSec then
        run.msBase = GetTimePreciseSec() - elapsed
    end
    self:OnDeathCountUpdated()
    self:UpdateForces()
    self:UpdateObjectives()
    self:NotifyRefresh()
end

-- 1 Hz OnUpdate fallback (fires even when the Blizzard hook is silenced by
-- QuestTracker reparenting the ObjectiveTrackerFrame to a hidden container).
local onUpdateAccum = 0
local function OnUpdateFallback(_, dt)
    onUpdateAccum = onUpdateAccum + dt
    if onUpdateAccum < 1 then return end
    onUpdateAccum = 0
    MPT:OnTimerTick()
end

function MPT:StartTimerLoop()
    onUpdateAccum = 0
    tickerFrame:SetScript("OnUpdate", OnUpdateFallback)
    tickerFrame:Show()
end

function MPT:StopTimerLoop()
    tickerFrame:SetScript("OnUpdate", nil)
    tickerFrame:Hide()
    onUpdateAccum = 0  -- defensive: discard any partial accumulation from the detached ticker
end

-- Primary driver: Blizzard pushes UpdateTime ~1/sec during M+ (free outside it).
-- Idempotent: guard prevents double-hooking if OnEnable is called more than once.
local primaryHookInstalled = false
function MPT:InstallTickHook()
    if primaryHookInstalled then return end
    -- ScenarioObjectiveTracker.ChallengeModeBlock is the 12.0 home of the M+
    -- timer block. (The legacy ScenarioBlocksFrame global no longer exists in
    -- 12.0.5 — verified against wow-ui-source; the old fallback was dead code.)
    local block = ScenarioObjectiveTracker and ScenarioObjectiveTracker.ChallengeModeBlock
    if block and block.UpdateTime then
        primaryHookInstalled = true
        -- INTENTIONALLY PERMANENT for the session: raw hooksecurefunc is NOT managed
        -- by AceHook's UnhookAll. The run.active gate in OnTimerTick is the disable
        -- safeguard — the hook itself is never removed.
        hooksecurefunc(block, "UpdateTime", function() MPT:OnTimerTick() end)
    else
        if DEBUG_MPT then KE:Print("[MPT] tick hook target missing - fallback ticker only") end
    end
end

-- Pre-declared callback eliminates per-call closure allocation in NotifyRefresh.
-- Flag cleared BEFORE Render so a Render-triggered NotifyRefresh can re-arm.
local function _NotifyRefreshFire()
    MPT._refreshQueued = nil
    MPT:Render()
end

-- Coalesces burst calls (SCENARIO_CRITERIA_UPDATE fires per-criterion) into a
-- single Render at most every 50 ms. Flag cleared BEFORE calling Render so a
-- Render-triggered NotifyRefresh can re-arm without being swallowed.
-- NOTE: a handle-based guard would be inert here (C_Timer.After returns nil,
-- not a cancellable handle); KE uses the boolean-pending pattern instead.
function MPT:NotifyRefresh()
    if self._refreshQueued then return end
    self._refreshQueued = true
    C_Timer.After(0.05, _NotifyRefreshFire)
end

---------------------------------------------------------------------------------
-- Post-completion lifecycle helpers
---------------------------------------------------------------------------------

-- True while still physically inside a Mythic Keystone instance. Needed for
-- the post-completion fanfare window: GetActiveChallengeMapID() and
-- IsChallengeModeActive() both flip false at completion while the player is
-- still standing in the dungeon, so fall back to the instance type/difficulty.
local function InChallengeInstance()
    local _, instanceType, difficulty = GetInstanceInfo()
    return instanceType == "party" and difficulty == 8
end

-- True when every tracked criterion is done (forces + all objectives), read
-- from the module's own cached state (API-free). Used to salvage a completion
-- when CHALLENGE_MODE_COMPLETED itself was never processed.
local function RunLooksComplete(run)
    if not (run.forces and run.forces.completed) then return false end
    local objs = run.objectives
    if #objs == 0 then return false end
    for i = 1, #objs do
        if not objs[i].completed then return false end
    end
    return true
end

-- Deferred salvage callback (pre-declared: no closure per arm). The
-- authoritative CHALLENGE_MODE_COMPLETED wins the 2s race — CompleteRun's
-- run.completed guard makes the late salvage a no-op.
local function _CompleteSalvageFire()
    MPT._salvagePending = nil
    local run = MPT.run
    if run.active and not run.completed and RunLooksComplete(run) then
        if DEBUG_MPT then KE:Print("[MPT] salvage: completing run (CHALLENGE_MODE_COMPLETED never arrived)") end
        MPT:CompleteRun()
    end
end

---------------------------------------------------------------------------------
-- Two-tier event registration (Task 1.8)
---------------------------------------------------------------------------------

-- Registered only during an active run (high-frequency; would wake on every
-- quest/scenario update outside a key). Per the contract's run-only tier.
local RUN_EVENTS = { "SCENARIO_CRITERIA_UPDATE", "SCENARIO_POI_UPDATE", "ZONE_CHANGED_NEW_AREA", "UNIT_DIED" }

function MPT:RegisterRunEvents()
    if DEBUG_MPT then KE:Print("[MPT] run events registered") end
    for _, ev in ipairs(RUN_EVENTS) do self:RegisterEvent(ev) end
end

function MPT:UnregisterRunEvents()
    if DEBUG_MPT then KE:Print("[MPT] run events unregistered") end
    for _, ev in ipairs(RUN_EVENTS) do self:UnregisterEvent(ev) end
end

-- One-shot deferred re-check (pre-declared: no closure per PEW): challenge-mode
-- APIs aren't reliably populated at PLAYER_ENTERING_WORLD, so a /reload-mid-key
-- recovery can miss. The 10s retry exists for exactly this.
local function _DelayedRunCheck()
    if not MPT:IsEnabled() then return end
    if MPT.run.active or MPT.run.completed then return end
    MPT:CheckForActiveRun()
end

-- Always-on event handlers (registered in OnEnable; low-frequency).
function MPT:PLAYER_ENTERING_WORLD()
    self:CheckForActiveRun()
    C_Timer.After(10, _DelayedRunCheck)
end

function MPT:CHALLENGE_MODE_START()
    -- New-key staleness boundary: this event NEVER fires for a reload or
    -- mid-key re-entry (those recover through CheckForActiveRun), so it owns
    -- the wipe of the run-recovery caches that the location-gated ResetRun
    -- paths deliberately spare (a mid-key walk-out keeps them so re-entry can
    -- restore splits + death log). Also covers the logout-outside-mid-key
    -- cross-session leak the old ResetRun hoisted clear used to catch.
    SetRunSplitCache(nil)
    self.db._activeRunDeaths = nil
    -- A genuinely new key replaces any lingering completed summary (completed
    -- state otherwise survives until the player leaves the instance).
    if self.run.completed then self:ResetRun() end
    self:StartRun()
end

function MPT:CHALLENGE_MODE_COMPLETED()
    self:CompleteRun()
end

function MPT:CHALLENGE_MODE_RESET()
    self:ResetRun()
end

-- Run-only criteria/POI updates: re-read forces+objectives, then debounce render.
function MPT:SCENARIO_CRITERIA_UPDATE()
    if not self.run.active then return end
    self:UpdateForces()
    self:UpdateObjectives()
    -- Completion salvage net (deferred): if everything just finished but
    -- CHALLENGE_MODE_COMPLETED never arrives, complete from cached state 2s
    -- later. The real event wins the race and carries the authoritative ms
    -- completion time.
    if not self._salvagePending and not self.run.completed and RunLooksComplete(self.run) then
        self._salvagePending = true
        C_Timer.After(2, _CompleteSalvageFire)
    end
    self:NotifyRefresh()
end

-- SCENARIO_POI_UPDATE shares the same handler as SCENARIO_CRITERIA_UPDATE.
MPT.SCENARIO_POI_UPDATE = MPT.SCENARIO_CRITERIA_UPDATE

function MPT:ZONE_CHANGED_NEW_AREA()
    if not self.run.active then return end  -- run-only event; belt-and-suspenders
    self:NotifyRefresh()
end

-- Alternate death capture path: catches deaths the party-scan diff may miss
-- (e.g. rapid multi-death bursts between GetDeathCount ticks). Enemy mob deaths
-- also fire this event — guard against their GUIDs being secret.
function MPT:UNIT_DIED(_, guid)
    if not guid or issecretvalue(guid) then return end
    MPT:RecordDeath(guid)
end

-- Authoritative death count changed (always-on tier).
-- NotifyRefresh is called inside OnDeathCountUpdated — no separate call needed.
function MPT:CHALLENGE_MODE_DEATH_COUNT_UPDATED()
    self:OnDeathCountUpdated()
end

-- WORLD_STATE_TIMER_START/STOP and instance-info events resolve to a re-check.
function MPT:WORLD_STATE_TIMER_START() self:CheckForActiveRun() end
function MPT:UPDATE_INSTANCE_INFO() if not self.run.active then self:CheckForActiveRun() end end

function MPT:WORLD_STATE_TIMER_STOP()
    -- Completed gate: the M+ world timer stops AT completion — without it
    -- this wipes the frozen summary + fanfare tracker suppression seconds
    -- after every finish (ResetRun's guard deliberately admits completed runs).
    -- keepCaches: at a mid-key walk-out this event can trail the PEW reset
    -- (run already inert) — it must not wipe the recovery caches that path
    -- spared. Cache staleness is owned by CHALLENGE_MODE_START / _RESET /
    -- CompleteRun.
    if not self.run.active and not self.run.completed then self:ResetRun(true) end
end

-- Auto-insert keystone when the font of power receptacle opens (Task 5.1).
-- Scans bags for the first keystone item and uses it automatically.
-- Gated on difficulty 8 (Mythic) or 23 (Mythic 5-man) so it never fires in
-- non-keystone instances. C_Item.IsItemKeystoneByID is the modern check;
-- hardcoded item IDs are stale.
function MPT:CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN()
    if not self.db.AutoInsertKeystone then return end

    -- Only auto-insert in a Mythic Keystone instance (8 = Mythic, 23 = Mythic 5-man).
    local difficulty = select(3, GetInstanceInfo())
    if difficulty ~= 8 and difficulty ~= 23 then return end

    local found
    for bagIndex = 0, NUM_BAG_SLOTS do
        local numSlots = C_Container.GetContainerNumSlots(bagIndex)
        for invIndex = 1, numSlots do
            local itemID = C_Container.GetContainerItemID(bagIndex, invIndex)
            if itemID and C_Item.IsItemKeystoneByID(itemID) then
                found = { bagIndex = bagIndex, invIndex = invIndex }
                break
            end
        end
        if found then break end
    end

    if found then
        C_Container.UseContainerItem(found.bagIndex, found.invIndex)
    end
end

---------------------------------------------------------------------------------
-- Run lifecycle (Task 1.7)
---------------------------------------------------------------------------------

-- Returns true if the affixIDs list contains Challenger's Peril (ID 152).
-- Called once per run start to determine peril-aware threshold calculation.
local function HasPerilAffix(affixIDs)
    if not affixIDs then return false end
    for _, id in ipairs(affixIDs) do
        if id == CHALLENGERS_PERIL_AFFIX_ID then return true end
    end
    return false
end

-- Trims the possessive prefix off the wordy Midnight affixes so the key line
-- stays compact: "Xal'atath's Guile" -> "Guile", "Challenger's Peril" -> "Peril".
-- Matched on the first word's stem ("Xal"/"Challenger") so the apostrophe glyph
-- (ASCII ' vs the Unicode right-quote WoW sometimes uses) never matters; every
-- other affix passes through untouched, and a single-word name is a no-op.
---@param name string?
local function ShortenAffix(name)
    if not name then return name end
    if name:find("^Xal") or name:find("^Challenger") then
        return name:match("(%S+)%s*$") or name
    end
    return name
end

-- Caches keystone level + affix names/fileIDs + peril-aware thresholds onto
-- the run. Split out of StartRun so RepairRunInfo can re-run it when
-- GetActiveKeystoneInfo wasn't populated at StartRun time (reload-recovery
-- race — a level-0 run otherwise locks wrong, un-peril'd +3/+2 cutoffs in
-- for the whole restored run). GetAffixInfo returns (name, description,
-- filedataid); all cached ONCE — never change mid-run.
function MPT:CacheKeystoneInfo(level, affixIDs)
    local run = self.run
    run.level = level or 0
    wipe(run.affixIDs)
    if affixIDs then
        for i = 1, #affixIDs do run.affixIDs[i] = affixIDs[i] end
    end
    wipe(run.affixNames)
    wipe(run.affixFileIDs)
    if affixIDs then
        for i, id in ipairs(affixIDs) do
            local name, _, fileID = C_ChallengeMode.GetAffixInfo(id)
            run.affixNames[i]   = ShortenAffix(name) or ""
            run.affixFileIDs[i] = fileID
        end
    end
    run.affixNamesStr = table.concat(run.affixNames, " · ")
    -- Dungeon name for the optional "+12 Name" key row (ShowDungeonName).
    -- GetMapUIInfo's first return is the localized name — non-secret map
    -- metadata (same call RepairRunInfo already uses for timeLimit).
    run.mapName = (run.mapID and C_ChallengeMode.GetMapUIInfo(run.mapID)) or nil
    run.thresholds = MPT.ComputeThresholds(run.maxTime, HasPerilAffix(run.affixIDs))
end

-- Late run-info repair, called from OnTimerTick while level/maxTime are still
-- 0 (cheap number gates). A reload-recovery StartRun can race API population;
-- each branch repairs at most once per run.
function MPT:RepairRunInfo()
    local run = self.run
    if run.maxTime == 0 and run.mapID then
        local _, _, timeLimit = C_ChallengeMode.GetMapUIInfo(run.mapID)
        if timeLimit and timeLimit > 0 then
            run.maxTime = timeLimit
            run.thresholds = MPT.ComputeThresholds(run.maxTime, HasPerilAffix(run.affixIDs))
            if DEBUG_MPT then KE:Print(format("[MPT] RepairRunInfo: maxTime=%d", timeLimit)) end
        end
    end
    if run.level == 0 then
        local level, affixIDs = C_ChallengeMode.GetActiveKeystoneInfo()
        if level and level > 0 then
            self:CacheKeystoneInfo(level, affixIDs)
            -- PB store is level-keyed: re-resolve pbRec + reseed bestOverall.
            self:LoadSplits()
            -- Re-stamp the in-flight split cache with the now-known level, so
            -- identity goes back to EXACT matching instead of staying on the
            -- level-0 window's relaxed map-only rule (MPT.CacheBelongsToRun).
            local cache = GetRunSplitCache()
            if MPT.CacheBelongsToRun(cache, run.mapID, 0) then
                cache.key = MPT.BuildSplitKey(run.mapID, run.level)
            end
            if DEBUG_MPT then KE:Print(format("[MPT] RepairRunInfo: level=%d", level)) end
        end
    end
end

function MPT:StartRun()
    -- preview teardown (ShowPreview/HidePreview: Task 2.6); isPreview is nil until then, so this is inert in Phase 1
    if self.isPreview then self:HidePreview() end
    local run = self.run
    if run.active then
        if DEBUG_MPT then KE:Print("[MPT] StartRun: already active, ignoring") end
        return
    end
    -- Fresh run: the reservation returns to the live-toggle width (the
    -- completed-run measurement included ms).
    local rootF = self.frames and self.frames.root
    if rootF then rootF._keConfigDone = nil end
    local mapID = C_ChallengeMode.GetActiveChallengeMapID()
    if not mapID then
        if DEBUG_MPT then KE:Print("[MPT] StartRun: no active map ID, ignoring") end
        return
    end

    local _, _, timeLimit = C_ChallengeMode.GetMapUIInfo(mapID)
    local level, affixIDs = C_ChallengeMode.GetActiveKeystoneInfo()
    if DEBUG_MPT then KE:Print(format("[MPT] StartRun: mapID=%d level=%d maxTime=%d", mapID, level or 0, timeLimit or 0)) end

    run.active = true
    run.completed = false
    run.mapID = mapID
    run.maxTime = timeLimit or 0
    run.elapsed = 0
    run.lastTickedSec = -1
    run.preciseBase = nil  -- re-anchored by OnTimerTick's first good tick
    run.msBase = nil       -- re-anchored by OnTimerTick at each whole-second flip
    self:CacheKeystoneInfo(level, affixIDs)
    wipe(run.objectives)
    run.forces.current, run.forces.total, run.forces.percent, run.forces.completed = 0, 0, 0, false
    run.forces._lastQS, run.forces._lastQSParsed = nil, nil
    run.forces.clearTime, run.forces.pbTime = nil, nil
    wipe(run.deathLog); _prevDeathCount = 0; wipe(_partyAlive); ScanPartyAlive()
    -- Reload/DC survival for the hover death log: restore the persisted log
    -- when it belongs to THIS dungeon. A genuinely new run never sees a live
    -- cache (CHALLENGE_MODE_START wipes both caches before its StartRun);
    -- recovery paths — reload, DC, and mid-key walk-back-in — restore here.
    -- Defensive shape checks because the table round-trips SavedVariables.
    local dCache = self.db._activeRunDeaths
    if dCache and dCache.mapID == mapID and type(dCache.log) == "table" then
        for i = 1, #dCache.log do
            local e = dCache.log[i]
            if type(e) == "table" and e.name then
                run.deathLog[#run.deathLog + 1] = { t = e.t or 0, name = e.name, class = e.class }
            end
        end
        dCache.log = run.deathLog  -- re-bind shared identity for future writes
        if DEBUG_MPT then KE:Print(format("[MPT] StartRun: restored %d death-log entries", #run.deathLog)) end
    end
    self:OnDeathCountUpdated()

    self:LoadSplits()
    self:RegisterRunEvents()
    self:StartTimerLoop()
    self:OnTimerTick()                    -- prime the display immediately
    self:ApplyTrackerVisibility()         -- QoL hide (combat-guarded, Step 5)
    self:SetOverlayActive(true)           -- activate nameplate % overlay for this run
    self:NotifyRefresh()
end

function MPT:CompleteRun()
    -- preview teardown (ShowPreview/HidePreview: Task 2.6); isPreview is nil until then, so this is inert in Phase 1
    if self.isPreview then self:HidePreview() end
    local run = self.run
    if run.completed then
        if DEBUG_MPT then KE:Print("[MPT] CompleteRun: already completed, ignoring") end
        return
    end
    if DEBUG_MPT then KE:Print("[MPT] CompleteRun: completing run") end
    run.completed = true
    run.active = false
    -- The frozen completion time always shows ms — bust the config gate so
    -- ApplyLayout re-measures the PB tuck reservation for the wider string
    -- (one-time state change; the EditMode drag path uses the same bust).
    local rootF = self.frames and self.frames.root
    if rootF then rootF._keConfigDone = nil end
    self:StopTimerLoop()
    self:UnregisterRunEvents()
    -- Authoritative final time (ms). GetWorldElapsedTime can go secret/stale ("99:99")
    -- after depletion, so always prefer GetChallengeCompletionInfo here.
    local info = C_ChallengeMode.GetChallengeCompletionInfo and C_ChallengeMode.GetChallengeCompletionInfo()
    if info and info.time and info.time > 0 then
        if DEBUG_MPT then KE:Print(format("[MPT] CompleteRun: elapsed source=completion-info time=%.1f", info.time / 1000)) end
        run.elapsed = info.time / 1000
    else
        local _, e = GetWorldElapsedTime(1)
        -- GetWorldElapsedTime can go stale after depletion (the "99:99" class
        -- of values). Sanity-gate before freezing it into the final display
        -- and the improve-only overall-PB commit; fall back to the precise-
        -- clock anchor, else keep the last good ticked value.
        local cap = (run.maxTime > 0) and (run.maxTime + 3600) or math.huge
        if e and e > 0 and e < cap then
            if DEBUG_MPT then KE:Print(format("[MPT] CompleteRun: elapsed source=world-elapsed fallback time=%.1f", e)) end
            run.elapsed = e
        elseif run.preciseBase and GetTimePreciseSec then
            -- Slightly under-counts penalties accrued after a mid-run /reload
            -- (the anchor restarts); far better than freezing a stale clock.
            run.elapsed = max(0, GetTimePreciseSec() - run.preciseBase)
            if DEBUG_MPT then KE:Print(format("[MPT] CompleteRun: elapsed source=precise-clock fallback time=%.1f", run.elapsed)) end
        end
    end
    self:UpdateObjectives()  -- backfill final clear times (tail-calls UpdateSplits; pre-run record still in run.bestOverall)
    -- Force-complete the frozen summary: a completed key has every boss dead
    -- and 100% forces by definition, but the final criterion update can arrive
    -- AFTER this event or be lost to the scenario teardown. Pin any objective
    -- still missing a clear time to the final elapsed and force the forces bar
    -- to 100%, so the summary can never freeze with a gray boss row or an empty
    -- forces bar. Runs BEFORE CommitSplits so the pinned times persist; the
    -- sticky/monotonic capture in UpdateObjectives/UpdateForces means real
    -- mid-run times are already in place for everything but a last-instant kill.
    local finalElapsed = run.elapsed or 0
    for i = 1, #run.objectives do
        local obj = run.objectives[i]
        obj.completed = true
        -- Count objectives (e.g. "2/6") read full at completion.
        if obj.totalQuantity and obj.totalQuantity > 1 then obj.quantity = obj.totalQuantity end
        if not (obj.clearTime and obj.clearTime > 0) then obj.clearTime = finalElapsed end
    end
    local fo = run.forces
    if fo then
        if fo.total and fo.total > 0 then fo.current = fo.total end
        fo.percent = 100
        if not fo.completed then
            fo.completed = true
            if not (fo.clearTime and fo.clearTime > 0) then fo.clearTime = finalElapsed end
        end
    end
    SetRunSplitCache(nil)  -- run over; in-progress split cache no longer needed
    MPT.db._activeRunDeaths = nil  -- ditto for the reload-survival death log
    self:CommitSplits()   -- persist improved per-boss + overall times to the global store
    self:SetOverlayActive(false)          -- release nameplate texts; run is over
    self:NotifyRefresh()
end

function MPT:ResetRun(keepCaches)
    -- preview teardown (ShowPreview/HidePreview: Task 2.6); isPreview is nil until then, so this is inert in Phase 1
    if self.isPreview then self:HidePreview() end
    -- Recovery-cache lifecycle: the default (keepCaches falsy — the
    -- CHALLENGE_MODE_RESET path) wipes both persisted caches BEFORE the
    -- early-return below, hoisted because they are independent of in-memory
    -- run state. keepCaches=true is passed by the LOCATION-gated paths
    -- (mid-key walk-out in CheckForActiveRun, a trailing
    -- WORLD_STATE_TIMER_STOP): the key is still live server-side, so re-entry
    -- restores splits + death log through the same path a /reload uses.
    -- Staleness is safe: CHALLENGE_MODE_START wipes both caches for every
    -- genuinely new key (including the logout-outside-mid-key cross-session
    -- leak), _activeRunSplits self-guards via its "mapID:level" identity
    -- stamp, and a restored death log is immediately reconcile-trimmed
    -- against the authoritative GetDeathCount.
    if not keepCaches then
        SetRunSplitCache(nil)
        MPT.db._activeRunDeaths = nil
    end
    -- Hoist rationale also applies to the salvage flag: a pending 2s salvage timer
    -- must not leave the flag armed into a chained new run (the
    -- not-_salvagePending guard would suppress that run's salvage net). The
    -- fire callback's run-state guards make any stale timer inert.
    self._salvagePending = nil
    local run = self.run
    if not run.active and not run.completed and run.mapID == nil then
        if DEBUG_MPT then KE:Print("[MPT] ResetRun: nothing to reset, ignoring") end
        return
    end
    if DEBUG_MPT then KE:Print("[MPT] ResetRun: resetting run state") end
    run.active = false
    run.completed = false
    run.mapID = nil
    run.level = 0
    run.maxTime = 0
    run.elapsed = 0
    run.lastTickedSec = -1
    run.preciseBase = nil
    run.msBase = nil
    run.deaths = 0
    run.deathTimeLost = 0
    wipe(run.deathLog); _prevDeathCount = 0; wipe(_partyAlive)
    wipe(run.affixIDs)
    wipe(run.affixNames)
    wipe(run.affixFileIDs)
    run.affixNamesStr = nil
    run.mapName = nil
    wipe(run.objectives)
    run.thresholds = { plus1 = 0, plus2 = 0, plus3 = 0 }
    run.forces.current, run.forces.total, run.forces.percent, run.forces.completed = 0, 0, 0, false
    run.forces._lastQS, run.forces._lastQSParsed = nil, nil
    run.forces.clearTime, run.forces.pbTime = nil, nil
    run.bestOverall = nil
    run.pbRec = nil
    run.pbSourceLevel = nil
    self:UnregisterRunEvents()
    self:StopTimerLoop()
    self:ApplyTrackerVisibility()
    self:SetOverlayActive(false)          -- release nameplate texts; run cancelled/reset
    self:NotifyRefresh()
end

function MPT:CheckForActiveRun()
    local mapID = C_ChallengeMode.GetActiveChallengeMapID()
    if mapID then
        -- Completed gate: GetActiveChallengeMapID can stay non-nil
        -- on the completion screen — without this, UPDATE_INSTANCE_INFO
        -- restarts a zombie run that re-posts every chat split and resolves
        -- PB against the record the real run just committed. The completed
        -- state is cleared by ResetRun once the player actually leaves (or by
        -- CHALLENGE_MODE_START when a genuinely new key begins).
        if not self.run.completed then
            self:StartRun()
        end
    else
        if self.run.active and RunLooksComplete(self.run) then
            -- Salvage: everything finished but the completion
            -- event was never processed — commit the run instead of wiping it.
            self:CompleteRun()
        elseif (self.run.active or self.run.completed) and not InChallengeInstance() then
            -- Reset ONLY once the player is genuinely OUTSIDE the keystone
            -- instance (upstream parity — the 2026-07-03 walk-out/in bug):
            -- GetActiveChallengeMapID reads nil in the PLAYER_ENTERING_WORLD
            -- window even while standing inside a live key, and resetting an
            -- ACTIVE run on that flap wiped the freshly rebuilt run right
            -- after re-entry. For completed runs this is the fanfare window:
            -- the map ID flips nil at completion while still inside — the
            -- frozen summary + tracker suppression stay up until the player
            -- actually leaves (ShouldHideTracker's completed arm uses the
            -- same predicate, so suppression ends at the door too).
            -- keepCaches: a walked-out key is still live server-side —
            -- re-entry restores splits + death log via the /reload path.
            self:ResetRun(true)
        end
    end
    -- Re-apply tracker visibility after any reload recovery: StartRun/ResetRun
    -- each call ApplyTrackerVisibility, but their early-return guards can skip it
    -- when run state is already consistent. This direct call guarantees a
    -- /reload mid-key re-hides the tracker (Task 5.2 wiring).
    self:ApplyTrackerVisibility()
end

---------------------------------------------------------------------------------
-- Tracker suppression system (Task 1.7 Step 5 / Task 5.2 Steps 1-2 early)
---------------------------------------------------------------------------------

local _trackerHookInstalled = false

-- True while the tracker should stay hidden: during the active challenge AND
-- after it completes but before the player leaves the dungeon instance.
-- Blizzard's end-of-run fanfare flips IsChallengeModeActive() back to false
-- while the user is still inside -- without the completed + party gate the
-- tracker pops back up for the last seconds before zone-out.
function MPT:ShouldHideTracker()
    -- GUI preview: always suppress, independent of the HideBlizzardTracker
    -- toggle — the fake-run HUD occupies the tracker's screen area. Hide/Show
    -- routes through ApplyTrackerVisibility from ShowPreview/HidePreview, so
    -- the _keHidTracker show-ownership gate applies as usual.
    if self.isPreview then return true end
    if not (self.db and self.db.HideBlizzardTracker) then return false end
    if self.run and self.run.active then return true end
    if self.run and self.run.completed then
        -- Same predicate as CheckForActiveRun's fanfare window: require the
        -- keystone difficulty too, or a lingering completed flag could keep
        -- the tracker suppressed in a non-keystone 5-man entered without a
        -- reset in between.
        return InChallengeInstance()
    end
    return false
end

function MPT:InstallTrackerHook()
    if _trackerHookInstalled then return end
    local otf = _G.ObjectiveTrackerFrame
    if not otf then return end
    _trackerHookInstalled = true
    -- Re-hide on every Blizzard Show attempt while ShouldHideTracker holds. No
    -- SetParent (avoids tainting the secure scenario tree). The re-hide is
    -- immediate even in combat — see the ApplyTrackerVisibility comment.
    hooksecurefunc(otf, "Show", function()
        if not MPT:ShouldHideTracker() then return end
        MPT:ApplyTrackerVisibility()
    end)
end

function MPT:ApplyTrackerVisibility()
    self:InstallTrackerHook()
    local otf = _G.ObjectiveTrackerFrame
    if not otf then return end

    local wantHide = self:ShouldHideTracker()

    -- No combat defer. ObjectiveTrackerFrame is NOT protected (verified against
    -- 12.0.5 wow-ui-source: no protected flag anywhere in its template chain —
    -- ObjectiveTrackerContainerTemplate, UIParentRightManagedFrameTemplate,
    -- EditModeObjectiveTrackerSystemTemplate), so Hide/Show in combat is legal
    -- and carries the same taint exposure as the out-of-combat path. A regen
    -- defer here is exactly how the Blizzard tracker "randomly came back"
    -- mid-key: ObjectiveTrackerContainerMixin:Update() ends in self:Show()
    -- whenever any module has content, and its MarkDirty schedules via
    -- RunNextFrame even while hidden — so the first enemy-forces/quest update
    -- of a pull re-showed it and the deferred hide left it up for the rest of
    -- that fight. Hiding unconditionally avoids that for the same reason.

    -- Show-ownership gate: only re-Show a tracker WE hid (_keHidTracker),
    -- never one another addon hid (e.g. KalielsTracker) — Show() unconditionally
    -- would fight other tracker addons on every lifecycle pass.
    if wantHide then
        if DEBUG_MPT then KE:Print("[MPT] ApplyTrackerVisibility: hiding tracker") end
        if otf:IsShown() then otf:Hide() end
        self._keHidTracker = true
    elseif self._keHidTracker then
        if DEBUG_MPT then KE:Print("[MPT] ApplyTrackerVisibility: showing tracker") end
        if not otf:IsShown() then otf:Show() end
        self._keHidTracker = nil
    end
end

---------------------------------------------------------------------------------
-- Slash command: /kes mt <...>
--
-- Routed from Core/Globals.lua's /kes dispatcher (HandleSlash-first; its
-- GUI-open fallback is superseded by the default arm below). Subcommands:
-- clearsplits (two-step wipe of the global PB store — the recovery path for
-- a bad improve-only record); anything else — including bare "/kes mt" —
-- opens the Mythic+ Timer GUI page (the dispatcher's previous behavior).
-- Mirrors DM:HandleSlash in Modules/DamageMeter/Core.lua.
---------------------------------------------------------------------------------

function MPT:HandleSlash(input)
    local arg, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    arg = (arg or ""):lower()
    if arg == "clearsplits" then
        local store = KE.db and KE.db.global and KE.db.global.MythicPlusTimerSplits
        local n = 0
        if store then
            for _ in pairs(store) do n = n + 1 end
        end
        if (rest or ""):lower() == "confirm" then
            if store then wipe(store) end
            -- Drop the live run's cached resolution so a key in progress
            -- stops rendering targets from the wiped store (false = resolved,
            -- nothing found — UpdateSplits' re-resolve sentinel is nil).
            self.run.pbRec = false
            self.run.pbSourceLevel = nil
            self.run.bestOverall = nil
            for i = 1, #self.run.objectives do
                self.run.objectives[i].pbTime = nil
            end
            if self.run.forces then self.run.forces.pbTime = nil end
            self:NotifyRefresh()
            KE:Print(format("Mythic+ Timer: cleared %d stored PB record(s).", n))
        elseif n == 0 then
            KE:Print("Mythic+ Timer: no stored PB records.")
        else
            KE:Print(format(
                "Mythic+ Timer: %d stored PB record(s). Type '/kes mt clearsplits confirm' to permanently delete them.",
                n))
        end
        return
    end
    -- Default: open the GUI page (matches the dispatcher's old fallback).
    if KE.GUIFrame and KE.GUIFrame.OpenPage then
        KE.GUIFrame:OpenPage("MythicPlusTimer", "dungeons_section")
    end
end

---------------------------------------------------------------------------------
-- EditMode registration (Task 5.11)
-- Registers frames.root with KE's standalone overlay system so /kes edit
-- shows a draggable overlay over the HUD and persists position writes to
-- SelfPoint/AnchorPoint/XOffset/YOffset (flat DB keys, Task 0.2 canonical).
-- Idempotent: self.editModeRegistered guard prevents double-registration.
-- Mirrors KickTracker:RegWithEditMode() (KickTracker.lua:1236-1268).
---------------------------------------------------------------------------------

function MPT:RegWithEditMode()
    if not (KE.EditMode and self.frames and self.frames.root) then return end
    if self.editModeRegistered then return end
    KE.EditMode:RegisterElement({
        key = "MythicPlusTimer",
        displayName = "Mythic+ Timer",
        frame = self.frames.root,
        getPosition = function()
            return {
                AnchorFrom = self.db.SelfPoint or "RIGHT",
                AnchorTo   = self.db.AnchorPoint or "RIGHT",
                XOffset    = self.db.XOffset or -20,
                YOffset    = self.db.YOffset or 0,
            }
        end,
        setPosition = function(pos)
            self.db.SelfPoint  = pos.AnchorFrom
            self.db.AnchorPoint = pos.AnchorTo
            self.db.XOffset    = pos.XOffset
            self.db.YOffset    = pos.YOffset
            -- Bust the config-skip gate: KE:ApplyFramePosition lives in
            -- ApplyLayout's `not _keConfigDone` block, which has already run
            -- by drag time. Without this the drag persists to DB but the
            -- anchor-relative position is never re-applied (frame would jump
            -- on next /reload).
            local f = self.frames and self.frames.root
            if f then f._keConfigDone = nil end
            self:ApplyLayout()  -- re-applies KE:ApplyFramePosition on frames.root
        end,
        getParentFrame = function()
            return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame)
        end,
        guiPath = "MythicPlusTimer",
    })
    self.editModeRegistered = true
end
