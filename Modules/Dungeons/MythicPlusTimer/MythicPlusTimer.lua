-- ╔══════════════════════════════════════════════════════════╗
-- ║  MythicPlusTimer.lua                                     ║
-- ║  Module: Mythic+ Timer                                   ║
-- ║  Purpose: Self-contained keystone timer HUD (WarpDeplete ║
-- ║           look, EllesmereUI event/tick architecture).    ║
-- ║           Bootstrap, DB defaults, run lifecycle/state,   ║
-- ║           event wiring, tick driver, deaths.             ║
-- ║  Backend split: _HUD (render), _Splits (PB), _Overlay   ║
-- ║           (folded ex-WarpDepleteForces nameplate/tip).  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local MPT = KitnEssentials:NewModule("MythicPlusTimer", "AceEvent-3.0", "AceHook-3.0")

-- Upvalues
local floor, max = math.floor, math.max
local format = string.format
local wipe = wipe
local C_ChallengeMode = C_ChallengeMode
local C_ScenarioInfo = C_ScenarioInfo
local C_Scenario = C_Scenario
local GetWorldElapsedTime = GetWorldElapsedTime
local hooksecurefunc = hooksecurefunc
local issecretvalue = issecretvalue or function() return false end

-- Constants
local PLUS_TWO_RATIO   = 0.8   -- +2 cutoff (80% of timer)
local PLUS_THREE_RATIO = 0.6   -- +3 cutoff (60% of timer)
local CHALLENGERS_PERIL_AFFIX_ID = 152  -- adds +90s; thresholds computed on (maxTime-90)

-- Shared run state (the currentRun table; reset by MPT:ResetRun).
MPT.run = MPT.run or {}

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
            m = floor(whole / 60); s = floor(whole % 60); ms = 0
        end
        return format("%02d:%02d.%03d", m, s, ms)
    end
    return format("%02d:%02d", m, s)
end

-- Pure: peril-aware +3/+2/+1 cutoff seconds. hasPeril => recompute on (maxTime-90).
-- plus1 = full limit, plus2 = 80%, plus3 = 60%. Busted-testable.
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
    OverlayColor = {1, 1, 1, 1},
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

    -- Task 4.2 appends `self:MigrateLegacyOverlayDB()` here (one-time
    -- WarpDepleteForces -> Overlay* key migration). Do not add it now — the
    -- method does not exist until Phase 4.

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
    -- Always-on event registration, HUD build, and active-run restore are wired
    -- in later phases (RegisterRunEvents / BuildHUD / CheckForActiveRun).
end

function MPT:OnDisable()
    self:UnregisterAllEvents()
    self:UnhookAll()
end
