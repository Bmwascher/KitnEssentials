-- ╔══════════════════════════════════════════════════════════╗
-- ║  MythicPlusTimer.lua                                     ║
-- ║  Module: Mythic+ Timer                                   ║
-- ║  Purpose: Self-contained keystone timer HUD (WarpDeplete ║
-- ║           look, EllesmereUI event/tick architecture).    ║
-- ║           Bootstrap, DB defaults, run lifecycle/state,   ║
-- ║           event wiring, tick driver, deaths.             ║
-- ║  Backend split: _HUD (render), _Splits (PB), _Overlay    ║
-- ║           (folded ex-WarpDepleteForces nameplate/tip).   ║
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
local hooksecurefunc = hooksecurefunc
local issecretvalue = issecretvalue or function() return false end
-- Current chat API. The bare global SendChatMessage is deprecated in 12.0, so capture
-- the namespaced form once at load under a non-colliding local name (a local literally
-- named SendChatMessage still trips the deprecation lint). C_ChatInfo is a core
-- namespace present before module files run. Mirror: Modules/DamageMeter/Core.lua:46.
local SendChat = C_ChatInfo and C_ChatInfo.SendChatMessage

-- Returns the appropriate group chat channel for boss-split output, or nil when
-- the player is alone (solo run — no channel to post to). INSTANCE_CHAT preferred
-- (cross-realm instance groups), then RAID, then PARTY. Mirror:
-- References/M+ Timer/MythicPlusTimer/timer.lua:29-32 (extended fallback chain).
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

-- Single shared run state (the contract's MPT.run). Reset by MPT:ResetRun(),
-- which wipes the array tables in place (affixIDs/affixNames/objectives/deathLog);
-- thresholds is re-assigned (tiny flat table, once per run).
MPT.run = {
    active = false, completed = false, countdown = false,
    mapID = nil, level = 0, affixIDs = {}, affixNames = {}, affixFileIDs = {},
    affixNamesStr = nil,
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
    XOffset = -20, YOffset = 0, Strata = "MEDIUM", Scale = 1.0,

    -- Timer
    TimerFormat = "ELAPSED_TOTAL",  -- ELAPSED_TOTAL|REMAINING|REMAINING_TOTAL|ELAPSED|ELAPSED_DETAIL
    ShowMilliseconds = false,
    TimerColor = {1, 1, 1},
    TimerSuccessColor = {1, 0.83, 0.22},
    TimerExpiredColor = {1, 0.16, 0.18},

    -- Timer bar + thresholds
    BarTexture = "KitnUI",
    BarWidth = 300, BarHeight = 14,
    BarColor = {0.56, 0.56, 0.56},
    StateColorFill = false,
    TickColor = {1, 1, 1},
    ShowThresholdLabels = true,

    -- Forces
    ShowForces = true,
    ForcesFormat = "PERCENT",   -- PERCENT|COUNT|COUNT_PERCENT|REMAINING|CUSTOM
    ForcesPlacement = "CORNER", -- CORNER|CENTER|BESIDE
    ForcesColor = {0.73, 0.62, 0.13},
    ForcesCompleteColor = {0.2, 0.82, 0.31},
    ForcesCustomFormat = ":count:/:totalcount: :percent:",
    ForcesBracketStyle = "NONE",  -- NONE|SQUARE|ROUND (wraps the count portion)
    ForcesBandedColors = false,
    -- 5-band quintile palette (0-19 / 20-39 / 40-59 / 60-79 / 80-99 %) plus a
    -- distinct 100% color, used by RenderForces when ForcesBandedColors is on
    -- (ForcesCompleteColor still wins at criterion completion). Values from the
    -- Reloe MPlusTimer ForcesBar defaults ("References/M+ Timer/MPlusTimer
    -- (Reloe)/Data.lua:463-470"; cf. References/M+ Timer/FEATURE-INVENTORY.md).
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
    -- feed; GUI exposes nothing in Phase 1.
    ShowPullOverlay = false,

    -- Objectives / boss list
    ShowObjectives = true,
    ShowObjectiveTimes = true,
    ShowPBDelta = true,
    ObjectiveColor = {0.85, 0.85, 0.85},
    ObjectiveDoneColor = {0.2, 0.82, 0.31},
    SplitAheadColor = {0.25, 0.88, 0.82},
    SplitBehindColor = {1, 0.42, 0.42},
    PBColor = {0.85, 0.79, 0.54},
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
    KeyColor = {0.69, 0.69, 0.69},

    -- Enemy overlay (folded from the retired WarpDepleteForces module).
    -- Nameplate per-mob forces % + enemy-tooltip count via
    -- C_ScenarioInfo.GetUnitCriteriaProgressValues (12.0.5 API). Full key set
    -- lives here (canonical) — Task 4.1 only verifies these values.
    -- OverlayNameplateEnabled honors the legacy WDF NameplatePercent = false
    -- default (Core/Defaults.lua:1256).
    OverlayNameplateEnabled = false,
    OverlayTooltipEnabled = true,
    OverlayFormat = "%.2f%%",   -- a string.format spec (NOT an enum)
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
    FontFace = "Expressway", FontSize = 13, FontOutline = "OUTLINE",
    TimerFontFace = "Expressway", TimerFontSize = 28, TimerFontOutline = "OUTLINE",
    ForcesFontFace = "Expressway", ForcesFontSize = 13, ForcesFontOutline = "OUTLINE",
    ObjectiveFontFace = "Expressway", ObjectiveFontSize = 12, ObjectiveFontOutline = "OUTLINE",
    DeathsFontFace = "Expressway", DeathsFontSize = 13, DeathsFontOutline = "OUTLINE",
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
    for i = 1, numCriteria do
        local info = C_ScenarioInfo.GetCriteriaInfo(i)
        if info and info.isWeightedProgress then
            -- quantityString carries the absolute count with a stray '%'. Locale-safe
            -- parse (EUI pattern): strip '%', treat a comma with no dot as a decimal
            -- separator (DE/FR clients), then tonumber. Cached on the raw string —
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
            f.current = current
            f.total = total
            if total > 0 then
                f.percent = (current / total) * 100
            else
                f.percent = 0
            end
            f.completed = info.completed or (total > 0 and current >= total) or false
            return
        end
    end
    -- No weighted criterion this step (e.g. countdown before the scenario populates).
    f.current, f.total, f.percent, f.completed = 0, 0, 0, false
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

    for i = 1, numCriteria do
        local info = C_ScenarioInfo.GetCriteriaInfo(i)
        if info and not info.isWeightedProgress then
            objIdx = objIdx + 1
            local obj = run.objectives[objIdx]
            if not obj then
                obj = { name = "", completed = false, clearTime = nil, pbTime = nil, criteriaIndex = i }
                run.objectives[objIdx] = obj
            end
            obj.criteriaIndex = i

            -- Strip Blizzard's leading checkmark (U+2713 = 0xE2 0x9C 0x93) + dash.
            -- Gated on the raw string — this fires per SCENARIO_CRITERIA_UPDATE,
            -- and names are stable after CHALLENGE_MODE_START; skip the gsub churn.
            local rawName = info.description or ("Objective " .. i)
            if rawName ~= obj._rawName then
                obj._rawName = rawName
                obj.name = rawName:gsub("^\226\156\147%s*", ""):gsub("^%-%s*", "")
            end

            local wasCompleted = obj.completed
            obj.completed = info.completed and true or false

            if obj.completed and not wasCompleted then
                -- Reload survival: reuse persisted split if present, else stamp now.
                local saved = MPT.db._activeRunSplits and MPT.db._activeRunSplits[objIdx]
                if saved and saved > 0 then
                    obj.clearTime = saved
                else
                    -- Back-dated to the actual kill moment (WarpDeplete semantic):
                    -- info.elapsed is the time since this criterion completed.
                    obj.clearTime = elapsed - (info.elapsed or 0)
                    if not MPT.db._activeRunSplits then MPT.db._activeRunSplits = {} end
                    MPT.db._activeRunSplits[objIdx] = obj.clearTime
                    -- Fresh-stamp arm ONLY (never the restoration arm above), so a
                    -- /reload mid-run cannot re-post a boss split to chat (Task 5.3).
                    self:ChatOutputBossSplit(obj)
                end
            elseif not obj.completed and obj.clearTime then
                obj.clearTime = nil  -- criterion reverted; guard skips the per-tick dead write
            end
        end
    end

    -- Trim stale rows beyond the live criteria count.
    for i = objIdx + 1, #run.objectives do
        run.objectives[i] = nil
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

    -- Persisted-value repair: a profile saved by an early dev build may hold
    -- the retired enum value "PERCENT" — OverlayFormat is a string.format spec.
    if self.db.OverlayFormat == "PERCENT" then
        self.db.OverlayFormat = "%.2f%%"
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

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------

function MPT:OnInitialize()
    self:UpdateDB()
    -- Default-disable: the addon-level OnEnable loop (Core/Main.lua:154-163)
    -- owns the enable decision via db.Enabled (sibling pattern, WDF:745-758).
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
    -- Season-based purge of stale split records (deferred; API not ready at login).
    C_Timer.After(2, function()
        if not self:IsEnabled() then return end  -- module disabled inside the window
        self:PurgeStaleSplits()
    end)
end

function MPT:OnDisable()
    -- Pending refresh timer must not render on a disabled module; ticker must detach.
    self:StopTimerLoop()
    self._refreshQueued = nil
    -- Overlay teardown: UnregisterAllEvents below kills the plate events, but the
    -- 0.5s nameplate ticker and any attached plate texts survive without this.
    self:SetOverlayActive(false)
    -- Stale combat-defer from an earlier in-combat hide attempt; the AceEvent
    -- registration it pairs with dies in UnregisterAllEvents below anyway.
    self._trackerPending = nil
    -- Restore a tracker WE hid (mid-key disable would otherwise leave it hidden
    -- until /reload). Cannot route through ApplyTrackerVisibility: run.active is
    -- still true so ShouldHideTracker() would re-hide, and its in-combat defer
    -- uses AceEvent, which AceAddon auto-unregisters on module disable.
    if self._keHidTracker then
        local otf = _G.ObjectiveTrackerFrame
        if otf and InCombatLockdown() then
            -- Protected frame: defer the Show via a dedicated event frame that
            -- survives AceEvent teardown. Created lazily once, reused after.
            if not self._trackerRestoreFrame then
                self._trackerRestoreFrame = CreateFrame("Frame")
                self._trackerRestoreFrame:SetScript("OnEvent", function(frame)
                    frame:UnregisterAllEvents()
                    -- Re-enable race guard: if the module was re-enabled before
                    -- combat ended, ApplyTrackerVisibility owns the tracker again
                    -- (it may have legitimately re-hidden it) — do nothing.
                    if MPT:IsEnabled() then return end
                    local tracker = _G.ObjectiveTrackerFrame
                    if tracker and not tracker:IsShown() then tracker:Show() end
                    MPT._keHidTracker = nil
                    if DEBUG_MPT then KE:Print("[MPT] OnDisable: deferred tracker restore fired") end
                end)
            end
            self._trackerRestoreFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            if DEBUG_MPT then KE:Print("[MPT] OnDisable: tracker restore deferred (in combat)") end
        else
            if otf and not otf:IsShown() then otf:Show() end
            self._keHidTracker = nil
            if DEBUG_MPT then KE:Print("[MPT] OnDisable: tracker restored") end
        end
    end
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
    else
        return
    end
    if not name then return end
    run.deathLog[#run.deathLog + 1] = {
        t = run.elapsed or 0,
        name = name,
        class = class,
    }
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
    local block = (ScenarioObjectiveTracker and ScenarioObjectiveTracker.ChallengeModeBlock)
        or (ScenarioBlocksFrame and ScenarioBlocksFrame.ChallengeModeBlock)
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
-- NOTE: EUI's handle-based guard is inert (C_Timer.After returns nil, not a
-- cancellable handle); KE uses the boolean-pending pattern instead.
-- Do NOT restore the upstream form on a future reference sync.
function MPT:NotifyRefresh()
    if self._refreshQueued then return end
    self._refreshQueued = true
    C_Timer.After(0.05, _NotifyRefreshFire)
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

-- Always-on event handlers (registered in OnEnable; low-frequency).
function MPT:PLAYER_ENTERING_WORLD()
    self:CheckForActiveRun()
end

function MPT:CHALLENGE_MODE_START()
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
function MPT:WORLD_STATE_TIMER_STOP() if not self.run.active then self:ResetRun() end end
function MPT:UPDATE_INSTANCE_INFO() if not self.run.active then self:CheckForActiveRun() end end

-- NOTE: PLAYER_REGEN_ENABLED is registered/unregistered on demand by
-- MPT:ApplyTrackerVisibility via OnTrackerRegenEnabled — do NOT add a static
-- default handler here (it would shadow the on-demand registration).

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

function MPT:StartRun()
    -- preview teardown (ShowPreview/HidePreview: Task 2.6); isPreview is nil until then, so this is inert in Phase 1
    if self.isPreview then self:HidePreview() end
    local run = self.run
    if run.active then
        if DEBUG_MPT then KE:Print("[MPT] StartRun: already active, ignoring") end
        return
    end
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
    run.countdown = true  -- cleared once the clock leaves 0:00 (HUD phase)
    run.mapID = mapID
    run.level = level or 0
    run.maxTime = timeLimit or 0
    run.elapsed = 0
    run.lastTickedSec = -1
    wipe(run.affixIDs)
    if affixIDs then
        for i = 1, #affixIDs do run.affixIDs[i] = affixIDs[i] end
    end
    -- Cache affix names and file IDs ONCE (never change mid-run; avoids per-render
    -- GetAffixInfo calls). GetAffixInfo returns (name, description, filedataid).
    wipe(run.affixNames)
    wipe(run.affixFileIDs)
    if affixIDs then
        for i, id in ipairs(affixIDs) do
            local name, _, fileID = C_ChallengeMode.GetAffixInfo(id)
            run.affixNames[i]   = name or ""
            run.affixFileIDs[i] = fileID
        end
    end
    run.affixNamesStr = table.concat(run.affixNames, " - ")
    run.thresholds = MPT.ComputeThresholds(run.maxTime, HasPerilAffix(run.affixIDs))
    wipe(run.objectives)
    run.forces.current, run.forces.total, run.forces.percent, run.forces.completed = 0, 0, 0, false
    run.forces._lastQS, run.forces._lastQSParsed = nil, nil
    wipe(run.deathLog); _prevDeathCount = 0; wipe(_partyAlive); ScanPartyAlive()
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
    run.countdown = false
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
        if DEBUG_MPT then KE:Print(format("[MPT] CompleteRun: elapsed source=world-elapsed fallback time=%.1f", e or 0)) end
        run.elapsed = e or run.elapsed
    end
    self:UpdateObjectives()  -- backfill any final clear times
    MPT.db._activeRunSplits = nil  -- run over; in-progress split cache no longer needed
    self:UpdateSplits()   -- refresh pbTime targets one final time (pre-run record still in run.bestOverall)
    self:CommitSplits()   -- persist improved per-boss + overall times to the global store
    -- Clear any stale combat-defer; ApplyTrackerVisibility re-arms it if still locked.
    self._trackerPending = nil
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    self:SetOverlayActive(false)          -- release nameplate texts; run is over
    self:NotifyRefresh()
end

function MPT:ResetRun()
    -- preview teardown (ShowPreview/HidePreview: Task 2.6); isPreview is nil until then, so this is inert in Phase 1
    if self.isPreview then self:HidePreview() end
    local run = self.run
    if not run.active and not run.completed and run.mapID == nil then
        if DEBUG_MPT then KE:Print("[MPT] ResetRun: nothing to reset, ignoring") end
        return
    end
    if DEBUG_MPT then KE:Print("[MPT] ResetRun: resetting run state") end
    run.active = false
    run.completed = false
    run.countdown = false
    run.mapID = nil
    run.level = 0
    run.maxTime = 0
    run.elapsed = 0
    run.lastTickedSec = -1
    run.deaths = 0
    run.deathTimeLost = 0
    wipe(run.deathLog); _prevDeathCount = 0; wipe(_partyAlive)
    wipe(run.affixIDs)
    wipe(run.affixNames)
    wipe(run.affixFileIDs)
    run.affixNamesStr = nil
    wipe(run.objectives)
    run.thresholds = { plus1 = 0, plus2 = 0, plus3 = 0 }
    run.forces.current, run.forces.total, run.forces.percent, run.forces.completed = 0, 0, 0, false
    run.forces._lastQS, run.forces._lastQSParsed = nil, nil
    run.bestOverall = nil
    run.pbRec = nil
    MPT.db._activeRunSplits = nil
    self:UnregisterRunEvents()
    self:StopTimerLoop()
    -- Clear any stale combat-defer; ApplyTrackerVisibility re-arms it if still locked.
    self._trackerPending = nil
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    self:ApplyTrackerVisibility()
    self:SetOverlayActive(false)          -- release nameplate texts; run cancelled/reset
    self:NotifyRefresh()
end

function MPT:CheckForActiveRun()
    local mapID = C_ChallengeMode.GetActiveChallengeMapID()
    if mapID then
        self:StartRun()
    else
        self:ResetRun()
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
-- tracker pops back up for the last seconds before zone-out
-- (References/M+ Timer/EllesmereUI/EllesmereUIMythicTimer/EllesmereUIMythicTimer.lua:548-559).
function MPT:ShouldHideTracker()
    if not (self.db and self.db.HideBlizzardTracker) then return false end
    if self.run and self.run.active then return true end
    if self.run and self.run.completed then
        local _, instanceType = GetInstanceInfo()
        return instanceType == "party"
    end
    return false
end

function MPT:InstallTrackerHook()
    if _trackerHookInstalled then return end
    local otf = _G.ObjectiveTrackerFrame
    if not otf then return end
    _trackerHookInstalled = true
    -- Re-hide on every Blizzard Show attempt while ShouldHideTracker holds. No
    -- SetParent (avoids tainting the secure scenario tree); combat-guarded via
    -- ApplyTrackerVisibility per spec section 8.
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

    -- ObjectiveTrackerFrame is protected: never Hide/Show during combat lockdown;
    -- defer to PLAYER_REGEN_ENABLED (spec section 8 tracker rule).
    if InCombatLockdown() then
        if DEBUG_MPT then KE:Print("[MPT] ApplyTrackerVisibility: tracker defer: in combat") end
        self._trackerPending = true
        self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnTrackerRegenEnabled")
        return
    end

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

function MPT:OnTrackerRegenEnabled()
    if not self._trackerPending then return end
    self._trackerPending = nil
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    self:ApplyTrackerVisibility()
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
