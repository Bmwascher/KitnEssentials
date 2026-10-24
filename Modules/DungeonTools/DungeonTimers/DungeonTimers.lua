-- ╔══════════════════════════════════════════════════════════╗
-- ║  DungeonTimers.lua                                       ║
-- ║  Module: Dungeon Timers (curated)                        ║
-- ║  Purpose: Layers curated castDuration data on top of     ║
-- ║           BigWigs_Timer events. Encounter data lives in  ║
-- ║           EncounterData.lua (hand-curated table keyed by ║
-- ║           encounterID/spellID).                          ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class DungeonTimers: AceModule, AceEvent-3.0, AceTimer-3.0
local DT = KitnEssentials:NewModule("DungeonTimers", "AceEvent-3.0", "AceTimer-3.0")

KE.EncounterData = KE.EncounterData or {}

local State = KE._DungeonTimerState
local Swap = KE._DungeonShieldSwapState
local Trace = KE._DungeonTimerTrace

local ipairs = ipairs
local pairs = pairs
local tostring = tostring
local tonumber = tonumber
local string_format = string.format
local math_min = math.min
local table_insert = table.insert
local table_remove = table.remove
local table_sort = table.sort
local CreateFrame = CreateFrame
local GetTime = GetTime
local UIParent = UIParent
local PlaySoundFile = PlaySoundFile
local UnitExists = UnitExists
local UnitGetTotalAbsorbs = UnitGetTotalAbsorbs
local UnitHealthPercent = UnitHealthPercent
local C_CurveUtil = C_CurveUtil
local Enum = Enum
local AbbreviateNumbers = AbbreviateNumbers
local pcall = pcall
local type = type
local issecretvalue = issecretvalue
local canaccesstable = canaccesstable

local DEBUG_DT2 = false

local BIGWIGS_EVENTS = {
    "BigWigs_StartBar",
    "BigWigs_Timer",
    "BigWigs_CastTimer",
    "BigWigs_PauseBar",
    "BigWigs_ResumeBar",
    "BigWigs_StopBar",
    "BigWigs_StopBars",
    "BigWigs_OnBossDisable",
    "BigWigs_Message",
}

-- Timeline values an anchored row acts on; any nil leaves the anchor path
-- inert and every stop on the heuristic rules.
local TIMELINE_SOURCE_ENCOUNTER = Enum and Enum.EncounterTimelineEventSource
    and Enum.EncounterTimelineEventSource.Encounter
local TIMELINE_STATE_FINISHED = Enum and Enum.EncounterTimelineEventState
    and Enum.EncounterTimelineEventState.Finished
local TIMELINE_STATE_CANCELED = Enum and Enum.EncounterTimelineEventState
    and Enum.EncounterTimelineEventState.Canceled
local TIMELINE_STATE_ACTIVE = Enum and Enum.EncounterTimelineEventState
    and Enum.EncounterTimelineEventState.Active
local TIMELINE_STATE_PAUSED = Enum and Enum.EncounterTimelineEventState
    and Enum.EncounterTimelineEventState.Paused

-- Wall-clock windows after a qualified Finished anchor: the Slam cast-start
-- confirm, and the DEBUG_DT2-only cast-start observation. Neither pauses.
local CONFIRM_WINDOW = 1.5
local OBSERVE_WINDOW = 3.0

local SOON_TEXT = "Soon"
local BOSS_UNITS = { "boss1", "boss2", "boss3", "boss4", "boss5" }

-- One AceEvent slot exists per event per module object, so each unit-cast
-- event has exactly one module handler and every feature dispatches from it.
local UNIT_CAST_HANDLERS = {
    UNIT_SPELLCAST_START = "OnUnitCastStart",
    UNIT_SPELLCAST_INTERRUPTED = "OnUnitCastInterrupted",
    UNIT_SPELLCAST_FAILED = "OnUnitCastFailed",
    UNIT_SPELLCAST_FAILED_QUIET = "OnUnitCastFailed",
    UNIT_SPELLCAST_CHANNEL_START = "OnUnitChannelStart",
    UNIT_SPELLCAST_CHANNEL_STOP = "OnUnitChannelStop",
    UNIT_SPELLCAST_DELAYED = "OnUnitCastDelayed",
    UNIT_SPELLCAST_STOP = "OnUnitCastStop",
}

local function AcceptBossUnit(unit)
    if issecretvalue and issecretvalue(unit) then return false end
    if type(unit) ~= "string" or not unit:match("^boss%d$") then return false end
    return true
end

-- Optional load — module degrades to "no role filter" if absent.
local LibSpec = LibStub("LibSpecialization", true)

-- Spell.role → which player roles see this bar. Untagged spells fail open.
local ROLE_ALLOW_LIST = {
    TANK    = { tank = true,             mechanic = true, other = true, kick = true              },
    HEALER  = {             heal = true, mechanic = true, other = true,             move = true },
    DAMAGER = {                          mechanic = true, other = true, kick = true, move = true },
}

-- Fallback sizes for very early init before DB resolves.
local FALLBACK_BAR_WIDTH = 250
local FALLBACK_BAR_HEIGHT = 22
local FALLBACK_TEXT_HEIGHT = 22

local STALE_GRACE = 1.5     -- seconds: bar at 0 self-destructs after this if StopBar never arrives (boss phased out etc.)

-- Synthetic key prefix for shield bars (boss absorb-tracker bars, e.g. Vordaza
-- Necrotic Convergence), independent of any BigWigs text key. A shield shows on
-- a boss channel start inside its parent's watch window.
local SHIELD_KEY_PREFIX = "__shield:"
local SHIELD_REFRESH_THROTTLE = 0.1  -- absorb-changed coalescing window
local function ShieldBarKey(spellId) return SHIELD_KEY_PREFIX .. tostring(spellId) end

-- M+ damage scaling for boss absorb shields.
-- shield max = baseAmount × LEVEL_MULTIPLIERS[keystoneLevel].
-- Levels above 35 clamp to [35]; level 0 (no keystone) uses 1.0.
local LEVEL_MULTIPLIERS = {
    [1]  =  1.00,
    [2]  =  1.07000005245,
    [3]  =  1.13999998569,
    [4]  =  1.23000001907,
    [5]  =  1.30999994278,
    [6]  =  1.39999997616,
    [7]  =  1.5,
    [8]  =  1.61000001431,
    [9]  =  1.72000002861,
    [10] =  1.84000003338,
    [11] =  2.01999998093,
    [12] =  2.22000002861,
    [13] =  2.45000004768,
    [14] =  2.69000005722,
    [15] =  2.96000003815,
    [16] =  3.25999999046,
    [17] =  3.57999992371,
    [18] =  3.94000005722,
    [19] =  4.32999992371,
    [20] =  4.76999998093,
    [21] =  5.25,
    [22] =  5.76999998093,
    [23] =  6.34999990463,
    [24] =  6.98000001907,
    [25] =  7.67999982834,
    [26] =  8.44999980927,
    [27] =  9.28999996185,
    [28] = 10.22000026703,
    [29] = 11.23999977112,
    [30] = 12.36999988556,
    [31] = 13.60999965668,
    [32] = 14.97000026703,
    [33] = 16.45999908447,
    [34] = 18.11000061035,
    [35] = 19.92000007629,
}

local function GetMythicLevel()
    if not (C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo) then return 0 end
    local ok, level = pcall(C_ChallengeMode.GetActiveKeystoneInfo)
    if not ok then return 0 end
    return tonumber(level) or 0
end

local function GetShieldLevelMultiplier()
    local level = GetMythicLevel()
    if level <= 0 then return 1 end
    if level > 35 then level = 35 end
    return LEVEL_MULTIPLIERS[level] or 1
end

-- Same style as FormatShieldTotal.
local SHIELD_REMAINING_OPTIONS = {
    breakpointData = {
        {
            breakpoint = 1e6, abbreviation = "M", significandDivisor = 1e4,
            fractionDivisor = 100, abbreviationIsGlobal = false,
        },
        {
            breakpoint = 1e3, abbreviation = "K", significandDivisor = 1e3,
            fractionDivisor = 1, abbreviationIsGlobal = false,
        },
        {
            breakpoint = 0, abbreviation = "", significandDivisor = 1,
            fractionDivisor = 1, abbreviationIsGlobal = false,
        },
    },
}

-- Percent of the estimated total: AbbreviateNumbers divides the absorb value by
-- 1% of the total, so no Lua arithmetic touches the secret value.
local function NewShieldPercentOptions(total)
    return {
        breakpointData = {
            {
                breakpoint = 0, abbreviation = "%", significandDivisor = total / 100,
                fractionDivisor = 1, abbreviationIsGlobal = false,
            },
        },
    }
end

-- The total is plain (baseAmount times the keystone multiplier).
local function FormatShieldTotal(total)
    if total >= 1e6 then return string.format("%.2fM", total / 1e6) end
    if total >= 1e3 then return string.format("%.0fK", total / 1e3) end
    return tostring(total)
end

-- The absorb value reaches only AbbreviateNumbers and SetFormattedText, which
-- both accept secret arguments.
local function WriteShieldText(fontString, absorbAmount, totalText, percentOptions)
    if type(AbbreviateNumbers) ~= "function" then
        fontString:SetText("")
        return
    end
    local okPercent, percentText = pcall(AbbreviateNumbers, absorbAmount, percentOptions)
    if not okPercent then
        fontString:SetText("")
        return
    end
    local okRemaining, remainingText = pcall(AbbreviateNumbers, absorbAmount, SHIELD_REMAINING_OPTIONS)
    if okRemaining then
        fontString:SetFormattedText("%s / %s (%s)", remainingText, totalText, percentText)
    else
        fontString:SetFormattedText("%s / %s", percentText, totalText)
    end
end

-- 30 = "always show decimals" for typical 0-30s bars. User-configured threshold of 1 would render "5 4 3 2 1 0.9 0.8".
local DECIMAL_THRESHOLD_DEFAULT = 30

local DEFAULT_BAR_COLOR = { 0.3, 0.5, 0.9 }
local SHIELD_FILL_COLOR = { 0.137, 0.325, 0.278 }
local DISPLAY_PRESETS = {
    ADD     = { label = "ADD",      color = { 1.0,  0.3,  0.8  } },
    AMP     = { label = "AMP",      color = { 0.9,  0.5,  1.0  } },
    AOE     = { label = "AOE",      color = { 1.0,  1.0,  0.2  } },
    CLEAR   = { label = "CLEAR",    color = { 0.95, 0.95, 0.95 } },
    DANCE   = { label = "DANCE",    color = { 0.7,  0.4,  1.0  } },
    DODGE   = { label = "DODGE",    color = { 1.0,  0.6,  0.0  } },
    FEET    = { label = "FEET",     color = { 1.0,  0.6,  0.0  } },
    FRONTAL = { label = "FRONTAL",  color = { 0.77, 0.17, 0.17 } },
    HIDE    = { label = "HIDE",     color = { 0.3,  0.9,  1.0  } },
    KICK    = { label = "KICK",     color = { 1.0,  0.15, 0.15 }, hidden = true },
    MOVE    = { label = "MOVE",     color = { 1.0,  0.6,  0.0  } },
    PULL    = { label = "PULL",     color = { 0.3,  0.9,  1.0  } },
    SOAK    = { label = "SOAK",     color = { 0.2,  1.0,  0.4  } },
    SPREAD  = { label = "SPREAD",   color = { 1.0,  0.6,  0.0  } },
    STACK   = { label = "STACK",    color = { 0.2,  1.0,  0.4  } },
    TANK    = { label = "TANK HIT", color = { 0.77, 0.17, 0.17 } },
    -- Hidden from the GUI chip grid (`hidden = true`) but still resolves
    -- via ResolveDisplayPreset for curators using `displayText = "VULN"`.
    -- Excluded so the visible preset grid stays at exactly 15 (3x5 layout).
    VULN    = { label = "VULN",     color = { 0.4,  1.0,  0.3  }, hidden = true },
}

-- Color-only aliases. The original text is preserved; only the color is borrowed from the aliased preset.
local DISPLAY_PRESET_ALIASES = {
    ["ADD GRIP"]  = "ADD",
    ADDS         = "ADD",
    ["AIM BEAMS"] = "CLEAR",
    ["AOE + BLEED"] = "AOE",
    ["AOE + DODGE"] = "DODGE",
    ["AOE + FEET"] = "FEET",
    ["AOE + SPREAD"] = "SPREAD",
    BAIT         = "PULL",
    ["BAIT ORBS"] = "PULL",
    BEAM         = "AMP",
    ["BIG HIT"]  = "TANK",
    BLEEDS       = "FRONTAL",
    ["CC ADDS"]  = "ADD",
    CHAINS       = "AOE",
    CLEARS       = "CLEAR",
    DISPEL       = "CLEAR",
    DROPS        = "SPREAD",
    FIXATES      = "FRONTAL",
    ["HEAL ABSORB"] = "CLEAR",
    HOOK         = "FRONTAL",
    INTERMISSION = "DANCE",
    KNOCK        = "PULL",
    LEAP         = "PULL",
    LEAPS        = "PULL",
    LINES        = "MOVE",
    MARKS        = "FRONTAL",
    MINIGAME     = "DANCE",
    ["ORB SPAWN"] = "ADD",
    PROTECT       = "SOAK",
    SHIELD       = "VULN",
    ["SHIELD INC"] = "VULN",
    SOAKS         = "SOAK",
    SPLIT        = "AMP",
    SUCC          = "AOE",
    ["TANK FRONTAL"] = "FRONTAL",
    ["TANK SOAK"] = "SOAK",
    TOTEMS        = "ADD",
    ["VULN + AOE"] = "AOE",
    VULNERABILITY = "VULN",
    ["WINDS - CHECK MAP"] = "MOVE",
}

-- Match by preset key first, then by label. Case-insensitive.
local function ResolvePresetByText(str)
    if not str then return nil end
    local upper = str:upper()
    local preset = DISPLAY_PRESETS[upper]
    if preset then return preset end
    for _, p in pairs(DISPLAY_PRESETS) do
        if p.label:upper() == upper then return p end
    end
    return nil
end

-- Returns (label, color). Preset/alias matches are case-insensitive but custom strings preserve user casing.
local function ResolveDisplayPreset(displayText)
    if not displayText then return nil, DEFAULT_BAR_COLOR end
    local preset = ResolvePresetByText(displayText)
    if preset then return preset.label, preset.color end
    local aliasKey = DISPLAY_PRESET_ALIASES[displayText:upper()]
    if aliasKey and DISPLAY_PRESETS[aliasKey] then
        return displayText, DISPLAY_PRESETS[aliasKey].color
    end
    return displayText, DEFAULT_BAR_COLOR
end

DT._ResolvePresetByText = ResolvePresetByText

-- Preset/alias color for arbitrary text, or nil when nothing matches. The
-- Dungeon Trash Tracker borrows the boss palette so a curated/overridden trash
-- label (SOAK, DODGE, FRONTAL…) colors its alert exactly like a boss timer;
-- an unmatched label (e.g. a raw spell name) returns nil so the caller can fall
-- back to its own default. Lives on KE so trash resolvers reach it without a
-- GetModule round-trip.
function KE.ResolveTrashPresetColor(text)
    if not text then return nil end
    local preset = ResolvePresetByText(text)
    if preset then return preset.color end
    local aliasKey = DISPLAY_PRESET_ALIASES[text:upper()]
    if aliasKey and DISPLAY_PRESETS[aliasKey] then return DISPLAY_PRESETS[aliasKey].color end
    return nil
end

-- Read-only by convention — mutating either would break the ResolveDisplayPreset closure.
DT.DISPLAY_PRESETS = DISPLAY_PRESETS
DT.DISPLAY_PRESET_ALIASES = DISPLAY_PRESET_ALIASES

-- Split text-mode layout, shared by the boss text timers and
-- the Dungeon Trash central alerts — one implementation so the two renderers,
-- which draw at the same shared TextGroup position, can never drift (they had:
-- 2/5px boss vs 4/4px trash gaps). Label is the static pivot; the icon hangs
-- off its LEFT and the timer extends off its RIGHT, so digit-width changes
-- never shift the label:
--   LEFT   → icon → label → timer, chained from anchor:LEFT
--   CENTER → label static at anchor:CENTER; icon off label:LEFT, timer off
--            label:RIGHT (block expands asymmetrically, LABEL+ICON stay put)
--   RIGHT  → timer pinned to anchor:RIGHT, label/icon to its left (timer
--            width changes shift them — CENTER/LEFT are the canonical cases)
-- Lives on KE so the trash renderer reaches it without a GetModule round-trip.
function KE.ApplySplitTextLayout(anchor, label, timerText, iconFrame, showIcon, align)
    label:SetJustifyH("CENTER")  -- single-token, justify within auto-width
    timerText:SetJustifyH("LEFT")
    label:ClearAllPoints()
    timerText:ClearAllPoints()
    if iconFrame then iconFrame:ClearAllPoints() end
    if align == "LEFT" then
        if showIcon then
            iconFrame:SetPoint("LEFT", anchor, "LEFT", 0, 0)
            label:SetPoint("LEFT", iconFrame, "RIGHT", 2, 0)
        else
            label:SetPoint("LEFT", anchor, "LEFT", 0, 0)
        end
        timerText:SetPoint("LEFT", label, "RIGHT", 5, 0)
    elseif align == "RIGHT" then
        timerText:SetPoint("RIGHT", anchor, "RIGHT", 0, 0)
        label:SetPoint("RIGHT", timerText, "LEFT", -5, 0)
        if showIcon then
            iconFrame:SetPoint("RIGHT", label, "LEFT", -2, 0)
        end
    else  -- CENTER
        label:SetPoint("CENTER", anchor, "CENTER", 0, 0)
        if showIcon then
            iconFrame:SetPoint("RIGHT", label, "LEFT", -2, 0)
        end
        timerText:SetPoint("LEFT", label, "RIGHT", 5, 0)
    end
end

DT.bars = {}
DT.barGroup = nil
DT.textGroup = nil
DT.spellLookup = nil

-- Phase tracker (HP%-driven). Bars live in self.bars
-- with internal "_phase_<n>" keys so LayoutBars handles them naturally.
DT.activeEncounterID = nil
DT.phaseTicker = nil
local PHASE_TICK_SECONDS = 0.5

local function dprint(msg)
    if DEBUG_DT2 then
        if DT._debugTrace and DT._debugTrace.active then
            DT._debugTrace:Decision(msg)
            return
        end
        KE:Print("[DT2] " .. tostring(msg))
    end
end
-- Exported so sibling files (WindMap.lua) use the same DEBUG_DT2 flag.
DT._dprint = dprint

local function PlayPresetSound(soundKey)
    if not soundKey then return end
    if DT.db and DT.db.MutePresetSounds then return end
    local LSM = KE.LSM
    if not LSM then return end
    local file = LSM:Fetch("sound", soundKey)
    if file then
        local channel = (DT.db and DT.db.SoundChannel) or "Master"
        PlaySoundFile(file, channel)
    end
end

-- Preview bars loop endlessly so they're gated out to prevent sound spam.
local function PlayBarSound(self, key)
    if self.isPreview then return end
    if not self.spellId then return end
    local record = self._dtPresentation
    if record and record.silent then return end
    local soundKey
    if key == "show" then
        soundKey = DT:GetEffectiveSpellSoundOnShow(self.spellId, record and record.ordinal)
    elseif key == "hide" then
        soundKey = DT:GetEffectiveSpellSoundOnHide(self.spellId)
    end
    PlayPresetSound(soundKey)
end

-- BigWigs appends " (N)" for repeating-cast uniqueness; keep it in self.bars keys but strip it from the rendered label.
local function StripBigWigsCounter(text)
    if not text then return text end
    return (text:gsub(" %(%d+%)$", ""))
end

function DT:BuildSpellLookup()
    local lookup = {}
    for encId, enc in pairs(KE.EncounterData or {}) do
        if enc.spells then
            for spellId, spellData in pairs(enc.spells) do
                lookup[spellId] = spellData
            end
        end
        if type(enc.phaseCues) == "table" then
            for name, cue in pairs(enc.phaseCues) do
                lookup[State.CueKey(encId, name)] = cue
            end
        end
        if type(enc.auraSounds) == "table" then
            for i = 1, #enc.auraSounds do
                local rule = enc.auraSounds[i]
                if DT.IsWellFormedAuraRule(rule) then
                    lookup[DT.MakeAuraKey(encId, rule.spellID, rule.trigger)] = rule
                end
            end
        end
    end
    self.spellLookup = lookup
    return lookup
end

function DT:GetSpellInfo(spellId)
    if not spellId then return nil end
    local lookup = self.spellLookup or self:BuildSpellLookup()
    return lookup[spellId]
end

function DT.IsCueKey(key)
    return type(key) == "string" and key:find("^cue:") ~= nil
end

function DT:GetEncounterPhases(encounterID)
    local enc = encounterID and KE.EncounterData and KE.EncounterData[encounterID]
    return enc and enc.phases
end

-- Phase rule key scheme: "phase:<encounterID>:<ruleIndex>". String-keyed so
-- saved-DB tables can hold both numeric spellIds and phase keys without collision.
function DT:MakePhaseRuleKey(encounterID, ruleIndex)
    if not (encounterID and ruleIndex) then return nil end
    return string_format("phase:%d:%d", encounterID, ruleIndex)
end

function DT:ParsePhaseRuleKey(key)
    if type(key) ~= "string" then return nil, nil end
    local encStr, idxStr = key:match("^phase:(%d+):(%d+)$")
    if not encStr then return nil, nil end
    return tonumber(encStr), tonumber(idxStr)
end

function DT:IsPhaseRuleKey(key)
    if type(key) ~= "string" then return false end
    return key:find("^phase:%d+:%d+$") ~= nil
end

function DT:GetPhaseRule(encounterID, ruleIndex)
    local phases = self:GetEncounterPhases(encounterID)
    return phases and phases[ruleIndex]
end

function DT:GetPhaseRuleByKey(key)
    local enc, idx = self:ParsePhaseRuleKey(key)
    if not enc then return nil end
    return self:GetPhaseRule(enc, idx), enc, idx
end

-- Presentation offset past the provider countdown. castDuration always extends and may
-- be zero for a row whose cue ends at the provider deadline; channelDuration only when
-- extendByChannel = true (effect lands at end-of-channel rather than the typical start).
-- User offset added on top, floored at 0.
function DT:GetSpellExtension(spellId)
    -- A cue's window is provider- or data-timed; a stored offset never moves it.
    if DT.IsCueKey(spellId) then return 0 end
    local data = self:GetSpellInfo(spellId)
    local curated = (data and data.castDuration) or 0
    if data and data.extendByChannel and data.channelDuration then
        curated = curated + data.channelDuration
    end
    local userOffset = self:GetSpellTimeOffset(spellId) or 0
    local result = curated + userOffset
    if result < 0 then result = 0 end
    return result
end

-- Curator's raw extension (no user offset). Used by the GUI to compute
-- the per-spell time-offset slider's lower bound — slider can drop to
-- -curated (so resulting extension reaches 0) but no further. Mirrors
-- GetSpellExtension's curated portion (castDuration + channelDuration
-- when extendByChannel) so the slider's negative travel correctly
-- accounts for the full bar lifetime.
function DT:GetSpellCuratorCastDuration(spellId)
    local data = self:GetSpellInfo(spellId)
    local curated = (data and data.castDuration) or 0
    if data and data.extendByChannel and data.channelDuration then
        curated = curated + data.channelDuration
    end
    return curated
end

function DT:GetSpellTimeOffset(spellId)
    if not (self.db and self.db.SpellTimeOffsets and spellId) then return nil end
    return self.db.SpellTimeOffsets[spellId]
end

-- Auto-prunes when value rounds to 0 so the modified indicator clears on revert.
function DT:SetSpellTimeOffset(spellId, value)
    if not (self.db and spellId) then return end
    self.db.SpellTimeOffsets = self.db.SpellTimeOffsets or {}
    local curated = self:GetSpellCuratorCastDuration(spellId)
    if value < -curated then value = -curated end
    if value == 0 then
        self.db.SpellTimeOffsets[spellId] = nil
    else
        self.db.SpellTimeOffsets[spellId] = value
    end
end

function DT:GetSpellDisplay(spellId)
    local override = self:GetSpellDisplayOverride(spellId)
    if override then return override end
    local data = self:GetSpellInfo(spellId)
    return (data and data.display) or "text"
end

function DT:GetSpellCuratorDisplay(spellId)
    local data = self:GetSpellInfo(spellId)
    return (data and data.display) or "text"
end

function DT:GetSpellDisplayOverride(spellId)
    if not (self.db and self.db.SpellDisplayOverrides and spellId) then return nil end
    return self.db.SpellDisplayOverrides[spellId]
end

function DT:SetSpellDisplayOverride(spellId, mode)
    if not (self.db and spellId) then return end
    if mode ~= "bar" and mode ~= "text" then return end
    self.db.SpellDisplayOverrides = self.db.SpellDisplayOverrides or {}
    local curated = self:GetSpellCuratorDisplay(spellId)
    if mode == curated then
        self.db.SpellDisplayOverrides[spellId] = nil
    else
        self.db.SpellDisplayOverrides[spellId] = mode
    end
end

function DT:GetSpellDisplayText(spellId)
    local override = self:GetSpellDisplayTextOverride(spellId)
    if override then return override end
    local data = self:GetSpellInfo(spellId)
    return data and data.displayText or nil
end

function DT:GetSpellCuratorDisplayText(spellId)
    local data = self:GetSpellInfo(spellId)
    return data and data.displayText or nil
end

function DT:GetSpellCastDisplayText(spellId)
    local data = self:GetSpellInfo(spellId)
    return data and data.castDisplayText or nil
end

function DT:GetSpellDisplayTextOverride(spellId)
    if not (self.db and self.db.SpellDisplayTextOverrides and spellId) then return nil end
    return self.db.SpellDisplayTextOverrides[spellId]
end

-- Empty input or curator-equivalent input prunes the entry.
function DT:SetSpellDisplayTextOverride(spellId, str)
    if not (self.db and spellId) then return end
    self.db.SpellDisplayTextOverrides = self.db.SpellDisplayTextOverrides or {}
    if str then str = str:match("^%s*(.-)%s*$") end
    if not str or str == "" then
        self.db.SpellDisplayTextOverrides[spellId] = nil
        return
    end
    local curated = self:GetSpellCuratorDisplayText(spellId)
    if curated then
        -- Equivalence prune: "dodge" vs "DODGE" both match preset, drop override.
        local userPreset = self._ResolvePresetByText(str)
        local curatorPreset = self._ResolvePresetByText(curated)
        if userPreset and userPreset == curatorPreset then
            self.db.SpellDisplayTextOverrides[spellId] = nil
            return
        end
        if not userPreset and not curatorPreset and str == curated then
            self.db.SpellDisplayTextOverrides[spellId] = nil
            return
        end
    end
    self.db.SpellDisplayTextOverrides[spellId] = str
end

-- Per-spell sound storage. Three distinguishable states:
--   nil      — user has never touched this; defer to EncounterData spell.sound.
--   "None"   — user explicitly muted (overrides any curated default).
--   "X"      — user picked LSM sound "X".
-- Raw getter returns the stored value as-is (Get*SpellSoundOn{Show,Hide}).
-- Effective getter resolves the three-state into "what should play" (Get
-- EffectiveSpellSoundOn{Show,Hide}) and is what audio playback consults.
function DT:GetSpellSoundOnShow(spellId)
    if not (self.db and self.db.SpellSoundsOnShow and spellId) then return nil end
    return self.db.SpellSoundsOnShow[spellId]
end

function DT:SetSpellSoundOnShow(spellId, soundKey)
    if not (self.db and spellId) then return end
    self.db.SpellSoundsOnShow = self.db.SpellSoundsOnShow or {}
    if soundKey == nil or soundKey == "" then
        self.db.SpellSoundsOnShow[spellId] = nil
    else
        self.db.SpellSoundsOnShow[spellId] = soundKey
    end
    if DT.IsAuraKey(spellId) then self:SyncAuraSounds() end
end

function DT:GetSpellSoundOnHide(spellId)
    if not (self.db and self.db.SpellSoundsOnHide and spellId) then return nil end
    return self.db.SpellSoundsOnHide[spellId]
end

function DT:SetSpellSoundOnHide(spellId, soundKey)
    if not (self.db and spellId) then return end
    self.db.SpellSoundsOnHide = self.db.SpellSoundsOnHide or {}
    if soundKey == nil or soundKey == "" then
        self.db.SpellSoundsOnHide[spellId] = nil
    else
        self.db.SpellSoundsOnHide[spellId] = soundKey
    end
end

-- Resolves the three-state storage into the LSM key audio playback should
-- consult. Returns nil for "play nothing" (either explicit "None" override
-- or no override + no curated default).
function DT:GetEffectiveSpellSoundOnShow(spellId, ordinal)
    if not spellId then return nil end
    local override = self:GetSpellSoundOnShow(spellId)
    if override == "None" then return nil end
    if override then return override end
    local spellData = self:GetSpellInfo(spellId)
    local sounds = spellData and spellData.ordinalSounds
    if type(ordinal) == "number" and type(sounds) == "table" and sounds[ordinal] then
        return sounds[ordinal]
    end
    return spellData and spellData.sound or nil
end

function DT:GetEffectiveSpellSoundOnHide(spellId)
    if not spellId then return nil end
    local override = self:GetSpellSoundOnHide(spellId)
    if override == "None" then return nil end
    if override then return override end
    local spellData = self:GetSpellInfo(spellId)
    return spellData and spellData.soundOnHide or nil
end

-- A "None" show override silences the result too; any other override
-- replaces only the kick voices, so the result keeps its own clip.
function DT:GetEffectiveCueResultSound(cueKey)
    if self:GetSpellSoundOnShow(cueKey) == "None" then return nil end
    local data = self:GetSpellInfo(cueKey)
    local result = data and data.interruptResult
    return result and result.sound or nil
end

-- "S" label visibility on the spell list. Checks the effective sound so a
-- curated default counts as "has sound" — the indicator means "will play",
-- not "user has stored an override". Override-only state lives in
-- HasSpellOverrides which reads raw db slots.
function DT:HasSpellSound(spellId)
    return self:GetEffectiveSpellSoundOnShow(spellId) ~= nil
        or self:GetEffectiveSpellSoundOnHide(spellId) ~= nil
end

function DT:GetSpellColorOverride(spellId)
    if not (self.db and self.db.SpellColorOverrides and spellId) then return nil end
    return self.db.SpellColorOverrides[spellId]
end

function DT:GetSpellCuratorColor(spellId)
    local data = self:GetSpellInfo(spellId)
    return data and data.color or nil
end

function DT:GetSpellSecondary(spellId)
    local data = self:GetSpellInfo(spellId)
    return data and data.secondary or nil
end

-- Optional follow-up bar config that spawns when the parent's cast phase ends
-- naturally (not on interrupt). Used for vulnerability/buff windows that
-- follow a cast — e.g. Nysarra Lightscar Flare's 17s damage-amp beam channel.
function DT:GetSpellPostCastBar(spellId)
    local data = self:GetSpellInfo(spellId)
    return data and data.postCastBar or nil
end

-- Validated shield binding for a parent in the active encounter, from a legacy
-- row's shieldBar or an explicit encounter's shields entry. See _ShowShieldBar
-- for the lifecycle.
function DT:GetSpellShieldBar(spellId)
    local encounterId = self._activeEncounterId
    local byEncounter = encounterId and self._bindings and self._bindings.shields[encounterId]
    return byEncounter and byEncounter[spellId] or nil
end

-- Phantom-followup entries: GUI-visible spell entries that don't fire from
-- their own BigWigs_Timer (their LittleWigs aura trigger is unreliable in
-- 12.0). Instead they spawn as an independent side effect of the *parent*
-- spell's accepted Timer, from the parent-to-phantom binding lookup. Allows
-- the VULN bar to have its own color/displayText/disabled/font row in the
-- GUI while staying chained to the parent's lifecycle.
function DT:GetSpellPhantomFollowupOf(spellId)
    local data = self:GetSpellInfo(spellId)
    return data and tonumber(data.phantomFollowupOf) or nil
end

-- Override BigWigs's reported duration with a known-correct value (e.g. for
-- Backlash where LittleWigs hardcodes 12.5s but the actual buff is 20s).
-- When set, the bar self-drains over forceDuration and ignores BigWigs StopBar.
function DT:GetSpellForceDuration(spellId)
    local data = self:GetSpellInfo(spellId)
    return data and tonumber(data.forceDuration) or nil
end

-- Replace BigWigs's supplied icon with a curated override. Accepts either a
-- texture file ID, a texture path, or a spell ID — numeric values are resolved
-- via C_Spell.GetSpellTexture first, then fall through to raw use if that misses.
function DT:GetSpellIconOverride(spellId)
    local data = self:GetSpellInfo(spellId)
    local override = data and data.iconOverride
    if not override then return nil end
    if type(override) == "number" and C_Spell and C_Spell.GetSpellTexture then
        local tex = C_Spell.GetSpellTexture(override)
        if tex then return tex end
    end
    return override
end

-- Centralized icon resolver: curator iconOverride wins over the spell's
-- default texture. Used by the in-game bar (via EventCallback), the preview
-- bar, the GUI list row, and the GUI detail-pane title icon so the four
-- representations stay in sync when iconOverride is set.
function DT:ResolveSpellIcon(spellId)
    local override = self:GetSpellIconOverride(spellId)
    if override then return override end
    if C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(spellId)
    end
    return nil
end

-- No auto-prune: float comparison on color components is unreliable, users click Reset to clear.
function DT:SetSpellColorOverride(spellId, color)
    if not (self.db and spellId) then return end
    self.db.SpellColorOverrides = self.db.SpellColorOverrides or {}
    if not color then
        self.db.SpellColorOverrides[spellId] = nil
        return
    end
    self.db.SpellColorOverrides[spellId] = { color[1], color[2], color[3] }
end

function DT:GetSpellDecimalThreshold(spellId)
    if not (self.db and self.db.SpellDecimalThresholds and spellId) then
        return DECIMAL_THRESHOLD_DEFAULT
    end
    local stored = self.db.SpellDecimalThresholds[spellId]
    return stored or DECIMAL_THRESHOLD_DEFAULT
end

function DT:SetSpellDecimalThreshold(spellId, value)
    if not (self.db and spellId) then return end
    self.db.SpellDecimalThresholds = self.db.SpellDecimalThresholds or {}
    if value == DECIMAL_THRESHOLD_DEFAULT then
        self.db.SpellDecimalThresholds[spellId] = nil
    else
        self.db.SpellDecimalThresholds[spellId] = value
    end
end

-- nil-checked explicitly: user override of 0 ("always visible") must beat the truthy-test fallback.
function DT:GetSpellShowAtSeconds(spellId)
    local userOverride = self:GetSpellShowAtOverride(spellId)
    if userOverride ~= nil then return userOverride end
    local data = self:GetSpellInfo(spellId)
    return data and data.showAtSeconds or nil
end

function DT:GetSpellCuratorShowAt(spellId)
    local data = self:GetSpellInfo(spellId)
    return data and data.showAtSeconds or nil
end

-- Validated explicit binding for a curated row; nil for a legacy row or a
-- row the builder refused, so the curated timerSource field alone never
-- admits anything. The preview and captions can run before the module
-- enables, so the table is built on first use and replaced at OnEnable.
function DT:GetSpellAdmittedBinding(spellId)
    if not self._bindings then
        self._bindings = State.BuildBindings(KE.EncounterData)
    end
    for _, byKey in pairs(self._bindings.timers) do
        local binding = byKey[spellId]
        if binding then
            if binding.policy == "estimated-impact" then return binding end
            return nil
        end
    end
    return nil
end

-- Rule-6 minimum reveal window for an admitted row: effective extension plus
-- the row's forecast lead and stop tolerance. nil for any row without an admitted binding. The
-- render path passes the instance's binding and the extension it already
-- computed; preview and GUI resolve both here.
function DT:GetSpellRevealFloor(spellId, binding, extension)
    binding = binding or self:GetSpellAdmittedBinding(spellId)
    if not (binding and binding.policy == "estimated-impact") then return nil end
    if extension == nil then extension = self:GetSpellExtension(spellId) end
    return extension + (binding.forecastLead or 0) + (binding.stopTolerance or 0)
end

-- Rule-6 reveal floor, shared by the renderer and the spell preview so they
-- cannot drift apart. A configured zero (always visible) is never floored.
function DT:GetSpellEffectiveShowAtSeconds(spellId, displayMode, binding, extension)
    local groupCfg = (displayMode == "bar") and (self.db and self.db.BarGroup)
                                            or (self.db and self.db.TextGroup)
    local configured = self:GetSpellShowAtSeconds(spellId) or (groupCfg and groupCfg.ShowAtSeconds) or 0
    if configured <= 0 then return configured end

    local floor = self:GetSpellRevealFloor(spellId, binding, extension)
    if floor and floor > configured then return floor end
    return configured
end

function DT:GetSpellShowAtOverride(spellId)
    if not (self.db and self.db.SpellShowAtOverrides and spellId) then return nil end
    return self.db.SpellShowAtOverrides[spellId]
end

function DT:SetSpellShowAtOverride(spellId, value)
    if not (self.db and spellId) then return end
    self.db.SpellShowAtOverrides = self.db.SpellShowAtOverrides or {}

    local effectiveDefault = self:GetSpellCuratorShowAt(spellId)
    if effectiveDefault == nil then
        local mode = self:GetSpellDisplay(spellId)
        local groupCfg = self.db[(mode == "bar") and "BarGroup" or "TextGroup"]
        effectiveDefault = (groupCfg and groupCfg.ShowAtSeconds) or 0
    end

    if value == effectiveDefault then
        self.db.SpellShowAtOverrides[spellId] = nil
    else
        self.db.SpellShowAtOverrides[spellId] = value
    end
end

function DT:GetSpellRole(spellId)
    local data = self:GetSpellInfo(spellId)
    return data and data.role or nil
end

-- Default DAMAGER so the allow-list never indexes nil before LibSpec resolves.
DT.playerRole = "DAMAGER"

function DT:OnLibSpecGroupUpdate(_, role, _, playerName)
    if not playerName or playerName ~= UnitName("player") then return end
    if role and role ~= self.playerRole then
        self.playerRole = role
        dprint("playerRole=" .. tostring(role))
    end
end

-- Override table only stores explicit deviations from curated; missing entry = fall through to ROLE_ALLOW_LIST.
function DT:IsSpellAllowedForRole(spellId, playerRoleToken)
    local overrides = self.db and self.db.SpellRoleOverrides
    local entry = overrides and spellId and overrides[spellId]
    if entry and entry[playerRoleToken] ~= nil then
        return entry[playerRoleToken] == true
    end
    local role = self:GetSpellRole(spellId)
    if not role then return true end
    local allow = ROLE_ALLOW_LIST[playerRoleToken]
    if not allow then return true end
    return allow[role] == true
end

-- The role filter ships enabled; db.RoleFilterEnabled=false or a per-spell
-- role override still lets a row through.
function DT:ShouldShowSpellRole(spellId)
    if not (self.db and self.db.RoleFilterEnabled) then return true end
    return self:IsSpellAllowedForRole(spellId, self.playerRole)
end

function DT:SetSpellRoleOverride(spellId, playerRoleToken, allowed)
    if not (self.db and spellId and playerRoleToken) then return end
    self.db.SpellRoleOverrides = self.db.SpellRoleOverrides or {}
    local overrides = self.db.SpellRoleOverrides
    overrides[spellId] = overrides[spellId] or {}
    overrides[spellId][playerRoleToken] = allowed and true or false

    -- Prune: walk every stored key and check if it matches the curated
    -- value. If all match, drop the entry entirely.
    local entry = overrides[spellId]
    local curatedRole = self:GetSpellRole(spellId)
    local allMatch = true
    for token, stored in pairs(entry) do
        local curatedAllow
        if curatedRole then
            local allow = ROLE_ALLOW_LIST[token]
            curatedAllow = allow and (allow[curatedRole] == true) or false
        else
            curatedAllow = true  -- uncurated → fail open default
        end
        if stored ~= curatedAllow then
            allMatch = false
            break
        end
    end
    if allMatch then
        overrides[spellId] = nil
    end
end

function DT:ResetSpellRoleOverride(spellId)
    if not (self.db and self.db.SpellRoleOverrides and spellId) then return end
    self.db.SpellRoleOverrides[spellId] = nil
end

function DT:ResetDungeonRoleOverrides(dungeonKey)
    if not (self.db and self.db.SpellRoleOverrides and dungeonKey) then return end
    for encId, enc in pairs(KE.EncounterData or {}) do
        if enc.dungeon == dungeonKey then
            for spellId in pairs(enc.spells or {}) do
                self.db.SpellRoleOverrides[spellId] = nil
            end
            if type(enc.phaseCues) == "table" then
                for name in pairs(enc.phaseCues) do
                    self.db.SpellRoleOverrides[State.CueKey(encId, name)] = nil
                end
            end
        end
    end
end

-- Tristate: nil = use curator default, true/false = explicit user override.
function DT:GetSpellCuratorDisabled(spellId)
    local data = self:GetSpellInfo(spellId)
    return (data and data.disabled) == true
end

function DT:IsSpellDisabled(spellId)
    if not spellId then return false end
    if self.db and self.db.SpellDisabled then
        local override = self.db.SpellDisabled[spellId]
        if override == true then return true end
        if override == false then return false end
    end
    return self:GetSpellCuratorDisabled(spellId)
end

function DT:SetSpellDisabled(spellId, disabled)
    if not (self.db and spellId) then return end
    self.db.SpellDisabled = self.db.SpellDisabled or {}
    local curated = self:GetSpellCuratorDisabled(spellId)
    if disabled == curated then
        self.db.SpellDisabled[spellId] = nil
    else
        self.db.SpellDisabled[spellId] = disabled
    end
    if DT.IsAuraKey(spellId) then self:SyncAuraSounds() end
    self:_OnProviderCueChanged(spellId)
end

function DT:ShouldShowSpell(spellId)
    if self:IsSpellDisabled(spellId) then return false end
    return self:ShouldShowSpellRole(spellId)
end

-- Drives the "modified" stripe in the spell list. Auto-pruned setters keep this from false-positiving.
function DT:HasSpellOverrides(spellId)
    if not (self.db and spellId) then return false end
    if self.db.SpellDisabled and self.db.SpellDisabled[spellId] ~= nil then
        return true
    end
    if self.db.SpellShowAtOverrides and self.db.SpellShowAtOverrides[spellId] ~= nil then
        return true
    end
    if self.db.SpellTimeOffsets and self.db.SpellTimeOffsets[spellId] ~= nil then
        return true
    end
    if self.db.SpellDisplayOverrides and self.db.SpellDisplayOverrides[spellId] ~= nil then
        return true
    end
    if self.db.SpellDisplayTextOverrides and self.db.SpellDisplayTextOverrides[spellId] ~= nil then
        return true
    end
    if self.db.SpellDecimalThresholds and self.db.SpellDecimalThresholds[spellId] ~= nil then
        return true
    end
    if self.db.SpellColorOverrides and self.db.SpellColorOverrides[spellId] ~= nil then
        return true
    end
    if self.db.SpellSoundsOnShow and self.db.SpellSoundsOnShow[spellId] ~= nil then
        return true
    end
    if self.db.SpellSoundsOnHide and self.db.SpellSoundsOnHide[spellId] ~= nil then
        return true
    end
    if self.db.SpellRoleOverrides then
        local entry = self.db.SpellRoleOverrides[spellId]
        if entry and next(entry) ~= nil then return true end
    end
    return false
end

function DT:ResetSpellOverrides(spellId)
    if not (self.db and spellId) then return end
    if self.db.SpellRoleOverrides then
        self.db.SpellRoleOverrides[spellId] = nil
    end
    if self.db.SpellDisabled then
        self.db.SpellDisabled[spellId] = nil
    end
    if self.db.SpellShowAtOverrides then
        self.db.SpellShowAtOverrides[spellId] = nil
    end
    if self.db.SpellTimeOffsets then
        self.db.SpellTimeOffsets[spellId] = nil
    end
    if self.db.SpellDisplayOverrides then
        self.db.SpellDisplayOverrides[spellId] = nil
    end
    if self.db.SpellDisplayTextOverrides then
        self.db.SpellDisplayTextOverrides[spellId] = nil
    end
    if self.db.SpellDecimalThresholds then
        self.db.SpellDecimalThresholds[spellId] = nil
    end
    if self.db.SpellColorOverrides then
        self.db.SpellColorOverrides[spellId] = nil
    end
    if self.db.SpellSoundsOnShow then
        self.db.SpellSoundsOnShow[spellId] = nil
    end
    if self.db.SpellSoundsOnHide then
        self.db.SpellSoundsOnHide[spellId] = nil
    end
    if DT.IsAuraKey(spellId) then self:SyncAuraSounds() end
    self:_OnProviderCueChanged(spellId)
end

-- ╔══════════════════════════════════════════════════════════╗
-- ║  Phase-rule overrides                                    ║
-- ║  Parallel to the spell-override helpers above. Operate   ║
-- ║  on phase rule keys produced by MakePhaseRuleKey.        ║
-- ╚══════════════════════════════════════════════════════════╝

function DT:IsPhaseDisabled(key)
    if not (key and self.db and self.db.PhaseDisabled) then return false end
    return self.db.PhaseDisabled[key] == true
end

function DT:SetPhaseDisabled(key, disabled)
    if not (self.db and key) then return end
    self.db.PhaseDisabled = self.db.PhaseDisabled or {}
    if disabled then
        self.db.PhaseDisabled[key] = true
    else
        self.db.PhaseDisabled[key] = nil
    end
end

function DT:GetPhaseDisplay(key)
    if not (key and self.db and self.db.PhaseDisplay) then return "text" end
    return self.db.PhaseDisplay[key] or "text"
end

function DT:GetPhaseCuratorDisplay(_)
    return "text"  -- phase rules default to text mode
end

function DT:SetPhaseDisplay(key, mode)
    if not (self.db and key) then return end
    if mode ~= "bar" and mode ~= "text" then return end
    self.db.PhaseDisplay = self.db.PhaseDisplay or {}
    if mode == "text" then
        self.db.PhaseDisplay[key] = nil  -- prune to default
    else
        self.db.PhaseDisplay[key] = mode
    end
end

function DT:GetPhaseLabelOverride(key)
    if not (key and self.db and self.db.PhaseLabels) then return nil end
    return self.db.PhaseLabels[key]
end

-- Trims whitespace; empty input prunes to default (no override).
function DT:SetPhaseLabelOverride(key, str)
    if not (self.db and key) then return end
    self.db.PhaseLabels = self.db.PhaseLabels or {}
    if str then str = str:match("^%s*(.-)%s*$") end
    if not str or str == "" then
        self.db.PhaseLabels[key] = nil
    else
        self.db.PhaseLabels[key] = str
    end
end

-- Effective label: user override → "Phase Transition" default.
function DT:GetPhaseEffectiveLabel(key)
    return self:GetPhaseLabelOverride(key) or "Phase Transition"
end

function DT:GetPhaseColorOverride(key)
    if not (key and self.db and self.db.PhaseColor) then return nil end
    return self.db.PhaseColor[key]
end

function DT:SetPhaseColorOverride(key, color)
    if not (self.db and key) then return end
    self.db.PhaseColor = self.db.PhaseColor or {}
    if not color then
        self.db.PhaseColor[key] = nil
        return
    end
    self.db.PhaseColor[key] = { color[1], color[2], color[3] }
end

-- Phase rule sound storage mirrors spell-sound semantics — nil = untouched
-- (defer to phaseData.sound/soundOnHide), "None" = explicit mute, anything
-- else = user pick. See DT:GetEffectivePhaseSoundOnShow below.
function DT:GetPhaseSoundOnShow(key)
    if not (key and self.db and self.db.PhaseSoundsOnShow) then return nil end
    return self.db.PhaseSoundsOnShow[key]
end

function DT:SetPhaseSoundOnShow(key, soundKey)
    if not (self.db and key) then return end
    self.db.PhaseSoundsOnShow = self.db.PhaseSoundsOnShow or {}
    if soundKey == nil or soundKey == "" then
        self.db.PhaseSoundsOnShow[key] = nil
    else
        self.db.PhaseSoundsOnShow[key] = soundKey
    end
end

function DT:GetPhaseSoundOnHide(key)
    if not (key and self.db and self.db.PhaseSoundsOnHide) then return nil end
    return self.db.PhaseSoundsOnHide[key]
end

function DT:SetPhaseSoundOnHide(key, soundKey)
    if not (self.db and key) then return end
    self.db.PhaseSoundsOnHide = self.db.PhaseSoundsOnHide or {}
    if soundKey == nil or soundKey == "" then
        self.db.PhaseSoundsOnHide[key] = nil
    else
        self.db.PhaseSoundsOnHide[key] = soundKey
    end
end

-- Resolves the three-state storage for phase rule sounds, falling back to
-- EncounterData[encounterID].phases[ruleIndex].sound (or .soundOnHide) when
-- the user hasn't stored an override. Returns nil for "play nothing".
local function ResolvePhaseRuleData(key)
    local encounterID, ruleIndex = DT:ParsePhaseRuleKey(key)
    if not encounterID or not ruleIndex then return nil end
    if not KE.EncounterData then return nil end
    local enc = KE.EncounterData[encounterID]
    if not enc or not enc.phases then return nil end
    return enc.phases[ruleIndex]
end

function DT:GetEffectivePhaseSoundOnShow(key)
    local override = self:GetPhaseSoundOnShow(key)
    if override == "None" then return nil end
    if override then return override end
    local rule = ResolvePhaseRuleData(key)
    return rule and rule.sound or nil
end

function DT:GetEffectivePhaseSoundOnHide(key)
    local override = self:GetPhaseSoundOnHide(key)
    if override == "None" then return nil end
    if override then return override end
    local rule = ResolvePhaseRuleData(key)
    return rule and rule.soundOnHide or nil
end

function DT:HasPhaseSound(key)
    return self:GetEffectivePhaseSoundOnShow(key) ~= nil
        or self:GetEffectivePhaseSoundOnHide(key) ~= nil
end

function DT:GetPhaseLeadOffset(key)
    if not (key and self.db and self.db.PhaseLeadOffsets) then return 0 end
    return self.db.PhaseLeadOffsets[key] or 0
end

function DT:SetPhaseLeadOffset(key, value)
    if not (self.db and key) then return end
    self.db.PhaseLeadOffsets = self.db.PhaseLeadOffsets or {}
    value = tonumber(value) or 0
    if value == 0 then
        self.db.PhaseLeadOffsets[key] = nil
    else
        self.db.PhaseLeadOffsets[key] = value
    end
end

-- Effective lead = curated lead + user offset, floored at 1.
function DT:GetPhaseEffectiveLead(key)
    local rule = self:GetPhaseRuleByKey(key)
    if not rule then return 0 end
    local curated = tonumber(rule.lead) or 0
    local effective = curated + self:GetPhaseLeadOffset(key)
    if effective < 1 then effective = 1 end
    return effective
end

function DT:HasPhaseOverrides(key)
    if not (self.db and key) then return false end
    if self.db.PhaseDisabled and self.db.PhaseDisabled[key] ~= nil then return true end
    if self.db.PhaseDisplay and self.db.PhaseDisplay[key] ~= nil then return true end
    if self.db.PhaseLabels and self.db.PhaseLabels[key] ~= nil then return true end
    if self.db.PhaseColor and self.db.PhaseColor[key] ~= nil then return true end
    if self.db.PhaseSoundsOnShow and self.db.PhaseSoundsOnShow[key] ~= nil then return true end
    if self.db.PhaseSoundsOnHide and self.db.PhaseSoundsOnHide[key] ~= nil then return true end
    if self.db.PhaseLeadOffsets and self.db.PhaseLeadOffsets[key] ~= nil then return true end
    return false
end

function DT:ResetPhaseOverrides(key)
    if not (self.db and key) then return end
    if self.db.PhaseDisabled       then self.db.PhaseDisabled[key]       = nil end
    if self.db.PhaseDisplay        then self.db.PhaseDisplay[key]        = nil end
    if self.db.PhaseLabels         then self.db.PhaseLabels[key]         = nil end
    if self.db.PhaseColor          then self.db.PhaseColor[key]          = nil end
    if self.db.PhaseSoundsOnShow   then self.db.PhaseSoundsOnShow[key]   = nil end
    if self.db.PhaseSoundsOnHide   then self.db.PhaseSoundsOnHide[key]   = nil end
    if self.db.PhaseLeadOffsets    then self.db.PhaseLeadOffsets[key]    = nil end
end

-- Migration: early schema nested anchor keys under group.Position; PositionCard needs them flat.
local function MigratePositionToFlat(group)
    if not group or type(group.Position) ~= "table" then return end
    local pos = group.Position
    if pos.AnchorFrom and not group.AnchorFrom then group.AnchorFrom = pos.AnchorFrom end
    if pos.AnchorTo and not group.AnchorTo then group.AnchorTo = pos.AnchorTo end
    if pos.XOffset ~= nil and group.XOffset == nil then group.XOffset = pos.XOffset end
    if pos.YOffset ~= nil and group.YOffset == nil then group.YOffset = pos.YOffset end
    group.Position = nil
end

-- Silent orphan cleanup. Two legacy slots can exist in saved profiles from
-- pre-1.23.0 versions of this addon — both now point at no live code:
--   * db.profile.Dungeons.DungeonTimers — the pre-1.23.0 BigWigs-trigger
--     module's slot (also the dungeontimers-rebuild branch's transitional
--     location for the new curated module before the top-level move).
--   * db.profile.Dungeons.BigWigsTimers — the same module under its short-
--     lived rename on the dungeontimers-rebuild branch.
-- The active module reads/writes db.profile.DungeonTimers, so these are
-- harmless but they bloat SavedVariables. Nil them out. Named-key-only,
-- existence-guarded, idempotent — re-running is a no-op.
local function MigrateLegacyDungeonTimers()
    if not (KE.db and KE.db.profile) then return end
    local dungeons = KE.db.profile.Dungeons
    if not dungeons then return end
    if dungeons.DungeonTimers ~= nil then dungeons.DungeonTimers = nil end
    if dungeons.BigWigsTimers ~= nil then dungeons.BigWigsTimers = nil end
end
KE._MigrateDungeonTimersDB = MigrateLegacyDungeonTimers

function DT:UpdateDB()
    if not (KE.db and KE.db.profile) then return end
    -- AceDB defaults don't deep-fill nested sub-tables when their parent already exists in saved data —
    -- backfill manually on first sight so DungeonTimers picks up its defaults.
    if not KE.db.profile.DungeonTimers then
        if KE.FillProfileDefaults then
            KE:FillProfileDefaults()
        end
    end
    self.db = KE.db.profile.DungeonTimers
    if self.db then
        MigratePositionToFlat(self.db.BarGroup)
        MigratePositionToFlat(self.db.TextGroup)
    end
end

function DT:GetGroupSettings(groupType)
    self:UpdateDB()
    if not self.db then return nil end
    return groupType == "bar" and self.db.BarGroup or self.db.TextGroup
end

---------------------------------------------------------------------------------
-- DB-driven settings resolvers (with fallbacks for early-init paths)
---------------------------------------------------------------------------------

local function GetBarDisplay()
    if DT.db and DT.db.BarDisplay then return DT.db.BarDisplay end
    return nil
end

local function GetTextDisplay()
    if DT.db and DT.db.TextDisplay then return DT.db.TextDisplay end
    return nil
end

local function GetBarHeight()
    local d = GetBarDisplay()
    return (d and d.barHeight) or FALLBACK_BAR_HEIGHT
end

local function GetTextHeight()
    local d = GetTextDisplay()
    -- 1.6× font size baseline; floored at FALLBACK to stay readable at tiny sizes.
    local fontSize = (d and d.fontSize) or 14
    local h = math.floor(fontSize * 1.6 + 0.5)
    if h < FALLBACK_TEXT_HEIGHT then h = FALLBACK_TEXT_HEIGHT end
    return h
end

local function ResolveFontPath(face)
    if KE.LSM and face then
        local path = KE.LSM:Fetch("font", face)
        if path then return path end
    end
    return KE.FONT or "Fonts\\FRIZQT__.TTF"
end

local function ResolveTexture(name)
    if KE.LSM and name then
        local path = KE.LSM:Fetch("statusbar", name)
        if path then return path end
    end
    return "Interface\\Buttons\\WHITE8x8"
end

-- 1px point anchor — bars stack outward from group corner so changing bar height doesn't shift the stack.
function DT:EnsureBarGroup()
    if self.barGroup then return self.barGroup end
    local f = CreateFrame("Frame", "KE_DungeonTimers_BarGroup", UIParent)
    f:SetSize(1, 1)
    self.barGroup = f
    self:UpdateBarGroupPosition()
    return f
end

function DT:EnsureTextGroup()
    if self.textGroup then return self.textGroup end
    local f = CreateFrame("Frame", "KE_DungeonTimers_TextGroup", UIParent)
    f:SetSize(1, 1)
    self.textGroup = f
    self:UpdateTextGroupPosition()
    return f
end

function DT:UpdateBarGroupPosition()
    if not self.barGroup then return end
    local settings = self:GetGroupSettings("bar")
    if not settings then return end
    -- Flat schema: settings holds both posConfig (AnchorFrom/To/XOffset/YOffset)
    -- and Config (Strata/anchorFrameType/ParentFrame) at the same level.
    KE:ApplyFramePosition(self.barGroup, settings, settings)
end

function DT:UpdateTextGroupPosition()
    if not self.textGroup then return end
    local settings = self:GetGroupSettings("text")
    if not settings then return end
    KE:ApplyFramePosition(self.textGroup, settings, settings)
end

function DT:UpdateGroupPositions()
    self:UpdateBarGroupPosition()
    self:UpdateTextGroupPosition()
end

-- Skip SetValue when delta < 1 pixel of bar width. Text mode has no fill, so SetValue is a no-op there.
local function GatedSetValue(frame, value)
    if frame.displayMode ~= "bar" or not frame.bar then return end
    local sb = frame.bar
    local minV, maxV = sb:GetMinMaxValues()
    -- 12.0: a pooled StatusBar that earlier served as a shield bar was fed a
    -- secret UnitGetTotalAbsorbs token via SetValue (see _RefreshShieldBar).
    -- That permanently secret-poisons the bar's getters, so GetMinMaxValues
    -- keeps returning a secret number even after CreateBar's plain
    -- SetMinMaxValues on reuse. Arithmetic on it (maxV - minV) would taint, so
    -- skip the pixel-gating math and write directly — SetValue is
    -- AllowedWhenTainted and `value` is a plain countdown/cast number here.
    if issecretvalue and (issecretvalue(minV) or issecretvalue(maxV)) then
        sb:SetValue(value)
        frame._lastValue = value
        return
    end
    local span = maxV - minV
    if span <= 0 then return end
    local widthPx = frame._cachedBarWidth or sb:GetWidth()
    if widthPx <= 0 then
        sb:SetValue(value)
        frame._lastValue = value
        return
    end
    local valuePerPixel = span / widthPx
    local lastV = frame._lastValue
    if not lastV or math.abs(value - lastV) >= valuePerPixel then
        sb:SetValue(value)
        frame._lastValue = value
    end
end

-- Safe here because BigWigs durations are plain numbers, not secret-value Unit*CastingDuration returns.
local function GatedSetText(textObj, holderBar, slot, str)
    if holderBar[slot] ~= str then
        textObj:SetText(str)
        holderBar[slot] = str
    end
end

local function SetCountdownText(self, timerStr)
    if self.staticLabel then return end
    if self.timerText then
        GatedSetText(self.timerText, self, "_lastTimerStr", timerStr)
    elseif self.label and self.baseText then
        GatedSetText(self.label, self, "_lastTimerStr",
            self.baseText .. " \194\187 " .. timerStr)
    end
end

-- Below threshold = "%.1f" decimals; at/above = ceil whole seconds ("5" means "5+ left").
local function UpdateTimeString(self, displayedTime)
    if self.staticLabel then return end
    local threshold = self.decimalThreshold or DECIMAL_THRESHOLD_DEFAULT
    local timerStr
    if displayedTime < threshold then
        timerStr = string_format("%.1f", displayedTime)
    else
        timerStr = string_format("%d", math.ceil(displayedTime))
    end
    SetCountdownText(self, timerStr)
end

-- Free-lists of retired CreateBar kits, keyed by displayMode ("bar" and
-- "text" kits have different child trees and never cross). WoW frames are
-- never garbage-collected — before this pool every bar teardown stranded a
-- 5-7-object kit permanently (~5-25 per boss pull). Mirrors the
-- DC:AcquireBar/DC:ReleaseBar free-list in DungeonCasts.lua.
---@type table<string, table[]>
local barFramePool = { bar = {}, text = {} }

-- Single teardown funnel for every bar lifecycle path. Callers stay
-- responsible for clearing their self.bars entry and re-running LayoutBars.
-- Frames without a _dtPoolKey tag (CreatePhaseBar kits — structurally
-- different children) get hide-only teardown and are not pooled.
local function ReleaseBar(bar)
    if not bar then return end
    if bar._dtPooled then return end
    bar:SetScript("OnUpdate", nil)
    bar:Hide()
    if not bar._dtPoolKey then return end
    bar:ClearAllPoints()
    -- Scrub every conditionally-set field so a reused kit can't inherit a
    -- previous life's state (CreateBar only assigns these when its inputs
    -- call for them). Boolean flags use false, not nil, so their inferred
    -- type stays boolean for the language server.
    bar.phase = "countdown"  -- mirrors CreateBar's init; don't rely on assignment order there
    bar.loop = false
    bar.isPreview = false
    bar.isShieldBar = false
    bar.staticLabel = false
    bar.shieldSpellId = nil
    bar.shieldUnit = nil
    bar.shieldMax = nil
    bar.showWindow = nil
    bar.sortIndex = nil
    bar.postCastBar = nil
    bar.castBaseText = nil
    bar.castColor = nil
    bar.fixedColor = nil
    bar.castStartTime = nil
    bar.castFromValue = nil
    bar.castDuration = nil
    bar._lastValue = nil
    bar._lastTimerStr = nil
    -- A reused kit that still carried these would drive BarOnUpdate's
    -- state branch off a retired record; the preview paths call CreateBar
    -- directly and leave OnUpdate live.
    bar._dtPresentation = nil
    bar._dtKey = nil
    bar._dtPooled = true
    table_insert(barFramePool[bar._dtPoolKey], bar)
end

-- self.phase/castStartTime belong to the preview path; cast visuals read the cast clock here.
local function BarOnUpdateInstance(self, record)
    local now = GetTime()
    local inst = record.instance
    local effectiveElapsed, _, remaining, phaseRemaining = State.Sample(inst, now)
    if effectiveElapsed == nil then
        DT:ReleaseInstancePresentations(inst, false)
        return
    end
    local outcome = State.ClassifyExpiry(inst, now)
    if outcome == "hold-eligible" then
        -- Resolved once per instance; the owned hold job, not this update,
        -- enforces the bound.
        outcome = DT:_BeginHold(inst, now) and "keep" or "retire"
    end
    if outcome == "keep" then
        if inst.castClock then
            local castElapsed = inst.binding.extension - phaseRemaining
            local visual = (self.castFromValue or 0) * (1 - castElapsed / inst.binding.extension)
            GatedSetValue(self, visual)
            UpdateTimeString(self, phaseRemaining)
        elseif State.ShowsSoon(inst) then
            -- A waiting occurrence has no deadline to draw.
            GatedSetValue(self, 0)
            SetCountdownText(self, SOON_TEXT)
        else
            local displayRemaining = State.AnchoredRemaining(inst, effectiveElapsed)
                or State.PredictedRemaining(inst, effectiveElapsed)
                or (remaining + inst.binding.extension + (inst.binding.forecastLead or 0))
            if displayRemaining < 0 then displayRemaining = 0 end
            GatedSetValue(self, displayRemaining)
            -- A held forecast has passed its deadline and has no corrected one yet.
            if inst.holdDeadline ~= nil then
                if self.timerText then GatedSetText(self.timerText, self, "_lastTimerStr", "") end
            else
                UpdateTimeString(self, displayRemaining)
            end
        end
    elseif outcome == "retire" then
        -- Create the ending text before release so the pool cannot reuse this frame.
        if inst.binding.cueKey then
            DT:_SpawnCueEnded(inst.owner, inst.binding.cueKey, now + remaining)
        end
        State.Retire(DT._state, inst)
        DT:ReleaseInstancePresentations(inst, true)
    elseif outcome == "legacy-followup-and-retire" then
        if State.TakeFollowup(DT._state, inst) then
            DT:_SpawnPostCastBar(inst, self)
        end
        State.Retire(DT._state, inst)
        DT:ReleaseInstancePresentations(inst, true)
    end
end

-- Clears this frame's own slot registration before release so a later
-- lookup under the same slot never finds an already-pooled or reused frame.
local function ClearSlotPresentation(frame, record)
    local byOwner = DT._slotPresentations[record.owner]
    local byKind = byOwner and byOwner[record.synthetic]
    if byKind and byKind[record.slotKey] == frame then
        byKind[record.slotKey] = nil
    end
end

-- Synthetic (phantom/postcast/message) presentations sample their own
-- independent clock and self-release on expiry or on a stale slot
-- generation — they never share the source instance's retirement.
local function BarOnUpdateSynthetic(self, record)
    local now = GetTime()
    if not State.IsSlotCurrent(DT._state, record.owner, record.synthetic, record.slotKey, record.generation) then
        ClearSlotPresentation(self, record)
        DT.bars[self._dtKey] = nil
        ReleaseBar(self)
        DT:LayoutBars()
        return
    end
    local effectiveElapsed, _, remaining = State.SampleClock(record.clock, now)
    if effectiveElapsed == nil or remaining <= 0 then
        if effectiveElapsed ~= nil then
            PlayBarSound(self, "hide")
            if record.endsCue then
                DT:_SpawnCueEnded(record.owner, record.endsCue, now + remaining)
            end
        end
        ClearSlotPresentation(self, record)
        DT.bars[self._dtKey] = nil
        ReleaseBar(self)
        DT:LayoutBars()
        return
    end
    GatedSetValue(self, remaining)
    UpdateTimeString(self, remaining)
end

local function BarOnUpdate(self)
    if self._dtPooled then return end
    local record = self._dtPresentation
    if record and record.instance then
        BarOnUpdateInstance(self, record)
        return
    elseif record and record.synthetic then
        BarOnUpdateSynthetic(self, record)
        return
    end

    -- Only previews reach here; boss and synthetic presentations returned above.
    if self.phase == "cast" then
        local castElapsed = GetTime() - self.castStartTime
        if castElapsed >= self.castDuration then
            -- Preview bars loop instead of destructing.
            if self.loop then
                self.phase = "countdown"
                self.startTime = GetTime()
                local c = self.barColor or DEFAULT_BAR_COLOR
                if self.displayMode == "bar" then
                    if self.bar then
                        self.bar:SetStatusBarColor(c[1], c[2], c[3])
                    end
                    if self.timerText then self.timerText:SetTextColor(1, 1, 1) end
                    if self.label then self.label:SetTextColor(1, 1, 1) end
                else
                    if self.label then self.label:SetTextColor(c[1], c[2], c[3]) end
                    if self.timerText then self.timerText:SetTextColor(c[1], c[2], c[3]) end
                end
                self._lastValue = nil
                self._lastTimerStr = nil
                return
            end
            -- Cast phase ended at impact — fire hide sound BEFORE Hide() so the cue lands.
            PlayBarSound(self, "hide")
            ReleaseBar(self)
            DT.bars[self.text] = nil
            DT:LayoutBars()
            return
        end
        local visual = self.castFromValue * (1 - castElapsed / self.castDuration)
        GatedSetValue(self, visual)
        UpdateTimeString(self, self.castDuration - castElapsed)
    else
        local remaining = self.totalDuration - (GetTime() - self.startTime)
        if remaining <= 0 then
            if self.loop then
                self.startTime = GetTime()
                remaining = self.totalDuration
                self._lastValue = nil
                self._lastTimerStr = nil
            elseif (self.extension or 0) <= 0 then
                -- No cast extension expected → self-destruct at zero crossing.
                PlayBarSound(self, "hide")
                ReleaseBar(self)
                DT.bars[self.text] = nil
                DT:LayoutBars()
                return
            elseif -remaining >= STALE_GRACE then
                -- StopBar never arrived (boss phased / interrupt) — self-destruct so we don't sit at 0 forever.
                dprint(string_format("BarOnUpdate %s → killed (stale grace, overdue=%.2f total=%.2f)",
                    self.text or "?", -remaining, self.totalDuration))
                PlayBarSound(self, "hide")
                ReleaseBar(self)
                DT.bars[self.text] = nil
                DT:LayoutBars()
                return
            else
                remaining = 0
            end
        end
        GatedSetValue(self, remaining)
        UpdateTimeString(self, remaining)
    end
end

-- Used by CreateBar (initial) and ApplySettings (live reapply). Visuals only — no state/timing.
local function ApplyVisualsToBar(frame)
    local isBar = (frame.displayMode == "bar")
    local barDisplay = GetBarDisplay()
    local textDisplay = GetTextDisplay()

    -- Per-spell knobs resolved first so the bar-color application below reads fresh values, not stale defaults.
    if frame.spellId then
        frame.decimalThreshold = DT:GetSpellDecimalThreshold(frame.spellId)
    else
        frame.decimalThreshold = DECIMAL_THRESHOLD_DEFAULT
    end
    local _, presetColor = ResolveDisplayPreset(frame.displayTextRaw)
    -- Phase bars don't have a spellId (encounter-level mechanics) — route their
    -- color override through phaseKey instead so the GUI Color picker applies.
    local userColor
    if frame.spellId then
        userColor = DT:GetSpellColorOverride(frame.spellId)
    elseif frame.phaseKey then
        userColor = DT:GetPhaseColorOverride(frame.phaseKey)
    end
    local curatorColor
    if frame.spellId then
        if frame.isShieldBar then
            local spell = DT:GetSpellInfo(frame.spellId)
            curatorColor = spell and spell.shieldColor or SHIELD_FILL_COLOR
        elseif frame.isSecondary then
            local secondary = DT:GetSpellSecondary(frame.spellId)
            curatorColor = secondary and secondary.color or nil
        else
            curatorColor = DT:GetSpellCuratorColor(frame.spellId)
        end
    end
    -- An ending leg's own color outranks the user's color for its cue.
    frame.barColor = frame.fixedColor or userColor or curatorColor or presetColor or DEFAULT_BAR_COLOR

    local w, h
    if isBar then
        w = (barDisplay and barDisplay.barWidth) or FALLBACK_BAR_WIDTH
        h = (barDisplay and barDisplay.barHeight) or FALLBACK_BAR_HEIGHT
    else
        w = (barDisplay and barDisplay.barWidth) or FALLBACK_BAR_WIDTH
        h = GetTextHeight()
    end
    frame:SetSize(w, h)

    if isBar then
        local iconEnabled = (barDisplay and barDisplay.iconEnabled ~= false)
        local iconSize = iconEnabled and h or 0

        if frame.iconFrame then
            if iconEnabled then
                frame.iconFrame:Show()
                frame.iconFrame:SetSize(iconSize, iconSize)
            else
                frame.iconFrame:Hide()
            end
        end

        if frame.barContainer then
            frame.barContainer:ClearAllPoints()
            frame.barContainer:SetPoint("TOPLEFT", frame, "TOPLEFT", iconSize, 0)
            frame.barContainer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        end

        if frame.bar and barDisplay then
            frame.bar:SetStatusBarTexture(ResolveTexture(barDisplay.barTexture))
            -- Don't stomp the cast-phase tint set elsewhere.
            if frame.phase ~= "cast" then
                local c = frame.barColor or DEFAULT_BAR_COLOR
                frame.bar:SetStatusBarColor(c[1], c[2], c[3])
            end
        end

        -- Cache fill width (frame - icon - 2px border) for pixel-aware SetValue gating.
        frame._cachedBarWidth = (w - iconSize) - 2
    else
        frame._cachedBarWidth = w

        -- Text-mode spell-icon (KE standard: zoom + border). Visibility from
        -- db.TextDisplay.ShowSpellIcon. Size is square at text-line height (h)
        -- so the icon's vertical extent matches the label. Texture is set
        -- live (frame.iconTex is stable from CreateBar but re-applied here in
        -- case ResolveSpellIcon's underlying data changed via the GUI).
        if frame.iconFrame then
            local showTextIcon = textDisplay and textDisplay.ShowSpellIcon and frame.iconTex
            if showTextIcon then
                local scale = tonumber(textDisplay.IconScale) or 0.8
                if scale < 0.25 then scale = 0.25 elseif scale > 2.0 then scale = 2.0 end
                local s = math.floor(h * scale + 0.5)
                if s < 1 then s = 1 end
                frame.iconFrame:SetSize(s, s)
                if frame.icon then frame.icon:SetTexture(frame.iconTex) end
                frame.iconFrame:Show()
            else
                frame.iconFrame:Hide()
            end
        end
    end

    -- Settings change always invalidates the gating caches so the next tick
    -- re-applies fonts/widths/strings unconditionally.
    frame._lastValue = nil
    frame._lastTimerStr = nil

    -- Font on label + timerText
    local face, size, outline
    if isBar then
        face = (barDisplay and barDisplay.fontFace) or KE:GetGlobalFont()
        size = (barDisplay and barDisplay.fontSize) or 12
        outline = (barDisplay and barDisplay.fontOutline) or "OUTLINE"
    else
        face = (textDisplay and textDisplay.fontFace) or KE:GetGlobalFont()
        size = (textDisplay and textDisplay.fontSize) or 14
        outline = (textDisplay and textDisplay.fontOutline) or "OUTLINE"
    end
    if frame.label and KE.ApplyFontToText then
        KE:ApplyFontToText(frame.label, face, size, outline)
    elseif frame.label then
        frame.label:SetFont(ResolveFontPath(face), size, KE.GetFontOutline and KE:GetFontOutline(outline) or outline)
    end
    if frame.timerText and KE.ApplyFontToText then
        KE:ApplyFontToText(frame.timerText, face, size, outline)
    elseif frame.timerText then
        frame.timerText:SetFont(ResolveFontPath(face), size, KE.GetFontOutline and KE:GetFontOutline(outline) or outline)
    end
    if frame.transitionText and KE.ApplyFontToText then
        KE:ApplyFontToText(frame.transitionText, face, size, outline)
    elseif frame.transitionText then
        frame.transitionText:SetFont(ResolveFontPath(face), size, KE.GetFontOutline and KE:GetFontOutline(outline) or outline)
    end

    -- Bar mode = white over colored fill. Text mode = label IS the colored cue.
    if frame.phase ~= "cast" then
        local c = frame.barColor or DEFAULT_BAR_COLOR
        if isBar then
            if frame.label then frame.label:SetTextColor(1, 1, 1) end
            if frame.timerText then frame.timerText:SetTextColor(1, 1, 1) end
            if frame.transitionText then frame.transitionText:SetTextColor(1, 1, 1) end
        else
            -- timerText now exists in text mode (split static-label / floating-timer
            -- layout) and shares the label's color so the block reads as one unit.
            if frame.label then frame.label:SetTextColor(c[1], c[2], c[3]) end
            if frame.timerText then frame.timerText:SetTextColor(c[1], c[2], c[3]) end
            if frame.transitionText then frame.transitionText:SetTextColor(c[1], c[2], c[3]) end
        end
    end

    if frame.label and frame.bar then
        frame.label:ClearAllPoints()
        if isBar then
            frame.label:SetPoint("LEFT", frame.bar, "LEFT", 4, 0)
            frame.label:SetPoint("RIGHT", frame.bar, "RIGHT", -4, 0)
            frame.label:SetJustifyH("LEFT")
            if frame.timerText then
                frame.timerText:ClearAllPoints()
                frame.timerText:SetPoint("LEFT", frame.bar, "LEFT", 4, 0)
                frame.timerText:SetPoint("RIGHT", frame.bar, "RIGHT", -4, 0)
                frame.timerText:SetJustifyH("RIGHT")
            end
            if frame.transitionText then
                -- Overlay the entire bar area so "Phase Transitioned" reads centered
                -- over the bar fill at the moment of transition.
                frame.transitionText:ClearAllPoints()
                frame.transitionText:SetPoint("LEFT", frame.bar, "LEFT", 4, 0)
                frame.transitionText:SetPoint("RIGHT", frame.bar, "RIGHT", -4, 0)
                frame.transitionText:SetJustifyH("CENTER")
            end
        else
            local align = (textDisplay and textDisplay.textAlign) or "CENTER"
            local showTextIcon = frame.iconFrame and frame.iconFrame:IsShown()

            if frame.timerText then
                -- Split-layout: the shared KE.ApplySplitTextLayout (defined
                -- with the preset tables above; also used by the Dungeon Trash
                -- alerts) — label/icon stay put, only the timerText extends.
                KE.ApplySplitTextLayout(frame.bar, frame.label, frame.timerText,
                    frame.iconFrame, showTextIcon, align)
            else
                -- Legacy single-label path (no timerText). Used by phase bars
                -- in text mode — they render via _ShowPhaseBar's direct SetText,
                -- not UpdateTimeString, so the static/floating split doesn't
                -- apply. Keep the span+justify layout.
                if showTextIcon then
                    frame.label:SetPoint("LEFT", frame.iconFrame, "RIGHT", 2, 0)
                else
                    frame.label:SetPoint("LEFT", frame.bar, "LEFT", 0, 0)
                end
                frame.label:SetPoint("RIGHT", frame.bar, "RIGHT", 0, 0)
                frame.label:SetJustifyH(align)
            end

            if frame.transitionText then
                frame.transitionText:ClearAllPoints()
                if showTextIcon then
                    frame.transitionText:SetPoint("LEFT", frame.iconFrame, "RIGHT", 2, 0)
                else
                    frame.transitionText:SetPoint("LEFT", frame.bar, "LEFT", 0, 0)
                end
                frame.transitionText:SetPoint("RIGHT", frame.bar, "RIGHT", 0, 0)
                frame.transitionText:SetJustifyH(align)
            end
        end
    end
end

function DT:CreateBar(text, baseDuration, extension, displayMode, displayText, spellId, castDisplayText, isSecondary, isSyntheticPostCast)
    displayMode = displayMode or "text"
    local isBar = (displayMode == "bar")
    local group = isBar and self:EnsureBarGroup() or self:EnsureTextGroup()

    -- 1 logical-unit = 1 physical pixel at any UI scale (literal 1 fuzzes at non-1x).
    local px = (KE.GetPixelSize and KE:GetPixelSize()) or 1

    -- Reuse a retired kit when one is available — frames are never GC'd, so
    -- building fresh per spawn permanently strands the old kit. The group
    -- parent is a create-once singleton, so pooled frames keep it.
    local frame = table_remove(barFramePool[displayMode])
    if frame then
        frame._dtPooled = false
        frame:Show()  -- ReleaseBar hides; new frames are shown by default
    else
        frame = CreateFrame("Frame", nil, group)
        frame._dtPoolKey = displayMode
    end
    frame.displayMode = displayMode
    -- Stash the spell's resolved icon for the text-mode `[icon] LABEL » time`
    -- prefix (GetTextIconPrefix). Resolved here at frame-create so toggle
    -- changes mid-fight pick up the icon without re-resolving every tick.
    -- ResolveSpellIcon honors data.iconOverride → falls back to the spell's
    -- default texture. Bar-mode icons are set separately via bar.icon below;
    -- this field is consumed only by the text-mode prefix path.
    frame.iconTex = spellId and self:ResolveSpellIcon(spellId) or nil

    -- Child kits are create-once per pooled frame. The px insets baked here
    -- go stale on a mid-session UI-scale change until /reload — accepted,
    -- same class as KE's other create-once kits.
    if isBar then
        if not frame.bar then
            frame.iconFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
            frame.iconFrame:SetPoint("LEFT", frame, "LEFT", 0, 0)
            frame.iconFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
            frame.iconFrame:SetBackdropColor(0, 0, 0, 0.8)
            if KE.AddIconBorders then
                KE:AddIconBorders(frame.iconFrame)
            end

            frame.icon = frame.iconFrame:CreateTexture(nil, "ARTWORK")
            frame.icon:SetPoint("TOPLEFT", px, -px)
            frame.icon:SetPoint("BOTTOMRIGHT", -px, px)
            if KE.ApplyIconZoom then KE:ApplyIconZoom(frame.icon) end

            frame.barContainer = CreateFrame("Frame", nil, frame, "BackdropTemplate")
            frame.barContainer:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = px,
            })
            frame.barContainer:SetBackdropColor(0, 0, 0, 0.8)
            frame.barContainer:SetBackdropBorderColor(0, 0, 0, 1)

            frame.bar = CreateFrame("StatusBar", nil, frame.barContainer)
            frame.bar:SetPoint("TOPLEFT", px, -px)
            frame.bar:SetPoint("BOTTOMRIGHT", -px, px)
        end
        -- Per-spawn: reset to the placeholder so a reused kit doesn't keep
        -- its previous spell's icon (the render entry point overwrites with iconID).
        frame.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    else
        if not frame.bar then
            -- Text mode: bar is a transparent FontString anchor.
            frame.bar = CreateFrame("StatusBar", nil, frame)
            frame.bar:SetAllPoints()

            -- Optional spell-icon prefix container, KE icon standard
            -- (KE:ApplyIconZoom + KE:AddIconBorders). Created unconditionally so
            -- toggling db.TextDisplay.ShowSpellIcon doesn't require bar rebuild —
            -- ApplyVisualsToBar Show/Hide's it and re-anchors the label. Sizing
            -- and texture are deferred to ApplyVisualsToBar since both depend on
            -- the current text height (h) and live frame.iconTex value.
            frame.iconFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
            frame.iconFrame:SetPoint("LEFT", frame, "LEFT", 0, 0)
            frame.iconFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
            frame.iconFrame:SetBackdropColor(0, 0, 0, 0.8)
            if KE.AddIconBorders then KE:AddIconBorders(frame.iconFrame) end

            frame.icon = frame.iconFrame:CreateTexture(nil, "ARTWORK")
            frame.icon:SetPoint("TOPLEFT", px, -px)
            frame.icon:SetPoint("BOTTOMRIGHT", -px, px)
            if KE.ApplyIconZoom then KE:ApplyIconZoom(frame.icon) end
        end
        if frame.iconTex then frame.icon:SetTexture(frame.iconTex) end
        frame.iconFrame:Hide()
    end

    local total = baseDuration + (extension or 0)
    frame.bar:SetMinMaxValues(0, total)
    frame.bar:SetValue(total)

    frame.startTime = GetTime()
    frame.duration = baseDuration
    frame.extension = extension or 0
    frame.totalDuration = total
    frame.phase = "countdown"
    frame.text = text
    frame.spellId = spellId
    frame.isSecondary = isSecondary

    -- Both modes get separate label + timerText FontStrings. Bar mode uses
    -- them as left/right pair inside the fill. Text mode uses them as a
    -- "static label » floating timer" split so the label (and the spell
    -- icon when shown) stays put while only the timer text width changes
    -- as the countdown shrinks.
    frame.label = frame.label or frame.bar:CreateFontString(nil, "OVERLAY")
    frame.timerText = frame.timerText or frame.bar:CreateFontString(nil, "OVERLAY")

    -- Stash raw displayText so ApplyVisualsToBar can re-resolve color on settings refresh.
    frame.displayTextRaw = displayText
    local resolvedLabel = ResolveDisplayPreset(displayText)

    -- Pre-resolved so StopBar's cast-phase swap is a cheap field assignment.
    frame.castDisplayTextRaw = castDisplayText
    if castDisplayText then
        local castLabel, castColor = ResolveDisplayPreset(castDisplayText)
        frame.castBaseText = castLabel or castDisplayText
        frame.castColor = castColor or DEFAULT_BAR_COLOR
    end

    -- Stash post-cast follow-up bar config (e.g. 17s VULN/BEAM after a cast).
    -- Only the primary carries it; synthetic and shield bars share the parent
    -- spellId and must not chain a postCastBar into themselves.
    local isSyntheticShield = text and text:sub(1, #SHIELD_KEY_PREFIX) == SHIELD_KEY_PREFIX
    if not isSecondary and not isSyntheticPostCast and not isSyntheticShield then
        frame.postCastBar = DT:GetSpellPostCastBar(spellId)
    end

    ApplyVisualsToBar(frame)
    -- frame.text keeps the raw label passed in; baseText is the rendered label.
    frame.baseText = resolvedLabel or StripBigWigsCounter(text)
    -- Initial label: bar mode shows just the name; text mode shows "name »"
    -- (with the separator baked into the static label) so the timer can
    -- hang off label:RIGHT without shifting the label as it counts down.
    if isBar then
        frame.label:SetText(frame.baseText)
    else
        frame.label:SetText(frame.baseText .. " \194\187")
    end
    -- Initial timer string. Threshold-aware decimal rendering avoids the
    -- "8.0" → "8" flash on the first tick. timerText is now populated in
    -- BOTH bar and text mode — BarOnUpdate's UpdateTimeString writes only
    -- to timerText (the `elseif self.label and self.baseText` fallback is
    -- now dead code for spell bars, retained for safety).
    local initialThreshold = frame.decimalThreshold or DECIMAL_THRESHOLD_DEFAULT
    local initialStr
    if total < initialThreshold then
        initialStr = string_format("%.1f", total)
    else
        initialStr = string_format("%d", math.ceil(total))
    end
    if frame.timerText then frame.timerText:SetText(initialStr) end

    frame:SetScript("OnUpdate", BarOnUpdate)
    return frame
end

function DT:LayoutBars()
    -- Read, never create: every bar's create path ensures its own group, so an
    -- absent group has nothing to place, and teardown of a module that never
    -- showed a bar allocates no frame.
    local barGroup = self.barGroup
    local textGroup = self.textGroup
    self:UpdateDB()

    local barCfg = self.db and self.db.BarGroup or nil
    local textCfg = self.db and self.db.TextGroup or nil
    local barSpacing = (barCfg and barCfg.Spacing) or 2
    local textSpacing = (textCfg and textCfg.Spacing) or 0
    local barGrowth = (barCfg and barCfg.GrowthDirection) or "DOWN"
    local textGrowth = (textCfg and textCfg.GrowthDirection) or "DOWN"

    -- Each bar anchors itself to the same corner the group uses (CENTER↔CENTER, TOPRIGHT↔TOPRIGHT).
    local barAnchorFrom = (barCfg and barCfg.AnchorFrom) or "CENTER"
    local textAnchorFrom = (textCfg and textCfg.AnchorFrom) or "CENTER"

    local barH = GetBarHeight()
    local textH = GetTextHeight()
    local barStride = barH + barSpacing
    local textStride = textH + textSpacing

    -- pairs() iterates hash order, which shuffled preview rows on reload — sort by sortIndex instead.
    local ordered = {}
    for _, bar in pairs(self.bars) do
        if bar:IsShown() then
            table_insert(ordered, bar)
        end
    end
    table_sort(ordered, function(a, b)
        -- Transparent phase rows must not displace ordinary countdowns.
        local aPhase, bPhase = a.isPhaseBar == true, b.isPhaseBar == true
        if aPhase ~= bPhase then return not aPhase end
        return (a.sortIndex or 0) < (b.sortIndex or 0)
    end)

    local barY, textY = 0, 0
    for _, bar in ipairs(ordered) do
        bar:ClearAllPoints()
        if bar.displayMode == "bar" then
            local offset = (barGrowth == "UP") and barY or -barY
            bar:SetPoint(barAnchorFrom, barGroup, barAnchorFrom, 0, offset)
            barY = barY + barStride
        else
            local offset = (textGrowth == "UP") and textY or -textY
            bar:SetPoint(textAnchorFrom, textGroup, textAnchorFrom, 0, offset)
            textY = textY + textStride
        end
    end

    -- Include transparent phase slots so merged trash cannot overlap them.
    self._stackExtents = self._stackExtents or {}
    if self._stackExtents.bar ~= barY or self._stackExtents.text ~= textY then
        self._stackExtents.bar = barY
        self._stackExtents.text = textY
        local DTrash = KitnEssentials:GetModule("DungeonTrash", true)
        if DTrash and DTrash.LayoutAlerts then
            DTrash:LayoutAlerts("bar")
            DTrash:LayoutAlerts("text")
        end
    end
end

-- Extent of all reserved boss rows (bar/text), refreshed by every LayoutBars —
-- the trash tracker's merged stack starts from it.
function DT:GetStackExtent(mode)
    local e = self._stackExtents
    return (e and e[mode]) or 0
end

function DT:ApplySettings()
    self:UpdateDB()
    self:UpdateGroupPositions()
    for _, bar in pairs(self.bars) do
        ApplyVisualsToBar(bar)
    end
    self:LayoutBars()
end

function DT:UpdateFrameVisuals()
    self:ApplySettings()
end

-- Real bars start at 1000 so they always lay out after the 1/2/3 previews.
DT._barSortCounter = 1000
DT._timerStateRevision = 74
-- Hidden occurrences the wind map observes, each with the job that ends it.
DT._observedRetireJobs = {}

-- Adapter-owned span normalization. Remaining-only contracts discard
-- any supplied maximum without inspecting it. Full-span contracts check
-- the maximum's secrecy after that return, then accept a nil maximum
-- (span = time) or an ordinary finite maximum >= time; anything else refuses.
function DT._NormalizeSpan(spanMode, time, maxTime)
    if type(time) ~= "number" or time ~= time or time == math.huge or time == -math.huge or time <= 0 then
        return nil, "invalid-time"
    end
    if spanMode ~= "full-span" then
        return time, time
    end
    if issecretvalue and issecretvalue(maxTime) then return nil, "invalid-span" end
    if maxTime == nil then return time, time end
    if type(maxTime) ~= "number" or maxTime ~= maxTime
        or maxTime == math.huge or maxTime == -math.huge or maxTime < time then
        return nil, "invalid-span"
    end
    return time, maxTime
end

-- A stale generation, retired scope/epoch or already-shown source record refuses.
function DT._IsPresentationCurrent(record)
    if not record then return false end
    if record.instance then
        if record.shown then return false end
        return State.IsCurrent(DT._state, record.instance, record.generation,
            record.instance.moduleEpoch, record.instance.encounterEpoch)
    end
    if record.synthetic then
        return State.IsSlotCurrent(DT._state, record.owner, record.synthetic, record.slotKey, record.generation)
    end
    return false
end

-- User time offset on top of the curated extension, cached per spell so
-- repeated Timers do not rebuild the copy.
function DT:_EffectiveBinding(binding, extension)
    if extension == binding.extension then return binding end
    self._effectiveBindings = self._effectiveBindings or {}
    local cached = self._effectiveBindings[binding]
    if not cached or cached.extension ~= extension then
        cached = {}
        for k, v in pairs(binding) do cached[k] = v end
        cached.extension = extension
        self._effectiveBindings[binding] = cached
    end
    return cached
end

-- Refuses inaccessible, secret or anonymous owners; no inference from name,
-- icon or duration. The cache is cleared at explicit boundaries.
function DT:_ResolveOwnerMeta(owner)
    if issecretvalue and issecretvalue(owner) then return nil, "secret-owner" end
    if type(owner) ~= "table" then return nil, "invalid-owner" end
    if canaccesstable and not canaccesstable(owner) then return nil, "inaccessible-owner" end
    local cached = self._ownerMeta[owner]
    if cached then return cached.encounterIds end
    local member = owner.GetEncounterID
    if issecretvalue and issecretvalue(member) then return nil, "secret-getencounterid" end
    if type(member) ~= "function" then return nil, "no-getencounterid" end
    local ids = { member(owner) }
    for i = 1, #ids do
        local id = ids[i]
        if (issecretvalue and issecretvalue(id)) or type(id) ~= "number" then
            return nil, "invalid-encounter-id"
        end
    end
    self._ownerMeta[owner] = { encounterIds = ids }
    return ids
end

-- CancelJob, RunJob and ScheduleJob touch self._jobs and self._ownedJobs per
-- job; RetireOrdinaryWork clears both tables outright.
local function CancelJob(self, job)
    if not job then return end
    if job.handle then self:CancelTimer(job.handle) end
    self._jobs[job] = nil
    local owned = self._ownedJobs[job.owner]
    if owned then owned[job] = nil end
end

-- A stale job (retired instance/generation, replaced slot) is dropped silently.
local function RunJob(job)
    local self = DT
    self._jobs[job] = nil
    local owned = self._ownedJobs[job.owner]
    if owned then owned[job] = nil end
    job.handle = nil
    local current
    if job.instance then
        current = State.IsCurrent(self._state, job.instance, job.instanceGeneration,
            job.instance.moduleEpoch, job.instance.encounterEpoch)
    elseif job.kind == "message" then
        local slots = self._slotJobs[job.owner]
        current = slots and slots["message"] and slots["message"][job.slotKey] == job
    else
        current = State.IsSlotCurrent(self._state, job.owner, job.kind, job.slotKey, job.generation)
    end
    if current then job.action(job) end
end

local function TrackJob(self, job)
    self._jobs[job] = true
    self._ownedJobs[job.owner] = self._ownedJobs[job.owner] or {}
    self._ownedJobs[job.owner][job] = true
end

-- A due delay runs the guarded action once synchronously; never a zero-delay continuation.
local function ScheduleJob(self, job, now)
    local delay, reason = State.JobRemaining(job.clockPolicy, job.deadline, job.clock, now)
    if not delay then
        dprint("job refused: " .. tostring(reason))
        return nil
    end
    TrackJob(self, job)
    if delay <= 0 then
        RunJob(job)
        return nil
    end
    job.handle = self:ScheduleTimer(RunJob, delay, job)
    return job
end

local function PauseJobHandle(self, job)
    if not job or not job.handle then return end
    self:CancelTimer(job.handle)
end

local function ResumeJobHandle(self, job, now)
    if not job then return end
    if not self._jobs[job] then return end
    if job.handle then
        self:CancelTimer(job.handle)
        job.handle = nil
    end
    local delay = State.JobRemaining(job.clockPolicy, job.deadline, job.clock, now)
    if not delay then
        self._jobs[job] = nil
        local owned = self._ownedJobs[job.owner]
        if owned then owned[job] = nil end
        return
    end
    if delay <= 0 then
        RunJob(job)
    else
        job.handle = self:ScheduleTimer(RunJob, delay, job)
    end
end

-- Hidden overlap rows need the same bounded expiry as a shown countdown.
local function KeepPresentationInstance(self, inst, now)
    local outcome = State.ClassifyExpiry(inst, now)
    if outcome == "hold-eligible" then outcome = self:_BeginHold(inst, now) and "keep" or "retire" end
    if outcome == "keep" then return true end
    State.Retire(self._state, inst)
    self:ReleaseInstancePresentations(inst, false)
    return false
end

local function PresentationRecord(inst)
    local presentations = DT._presentations[inst]
    local frame = presentations and presentations.primary
    return frame and frame._dtPresentation
end

local function IsShownPresentation(inst)
    local record = PresentationRecord(inst)
    return record and record.shown == true
end

local function IsWaitingPresentation(inst)
    local record = PresentationRecord(inst)
    return record and record.overlapHeld == true and inst.state ~= "paused"
end

-- `key` is the private storage identity in self.bars; CreateBar's text is the
-- source label or a synthetic identifier, never the key.
local function RenderPresentation(self, key, record, baseDur, extension, displayMode, iconID,
                                   displayText, spellId, castDisplayText, isSecondary)
    if not baseDur or baseDur <= 0 then return nil end
    local now = GetTime()
    local ctext
    if record.instance then
        ctext = record.instance.label
    else
        ctext = tostring(record.synthetic) .. ":" .. tostring(record.slotKey)
    end
    local isSyntheticPostCast = record.synthetic ~= nil

    local frame = self:CreateBar(ctext, baseDur, extension, displayMode, displayText, spellId,
        castDisplayText, isSecondary, isSyntheticPostCast)
    self._barSortCounter = self._barSortCounter + 1
    frame.sortIndex = self._barSortCounter
    frame._dtKey = key
    frame._dtPresentation = record
    self.bars[key] = frame

    if iconID and frame.icon then
        frame.icon:SetTexture(iconID)
    end

    self:UpdateDB()
    local total = baseDur + (extension or 0)

    if record.instance then
        local showWindow = self:GetSpellEffectiveShowAtSeconds(spellId, displayMode,
            record.instance.binding, extension or 0)
        local revealAt = showWindow > 0 and total - showWindow or 0
        local restart = record.instance.binding.suppressConcurrentRestart
        if restart and record.instance.sourceClock.remainingAtReceipt == restart.duration then
            -- Immediate reveals wait beyond the whole concurrent-anchor window.
            revealAt = math.max(revealAt, record.instance.binding.stopTolerance + 0.01)
        end
        if revealAt > 0 or record.instance.binding.holdOverlapping then
            frame:Hide()
            frame.showWindow = showWindow
            local inst = record.instance
            if inst.binding.holdOverlapping then
                -- Register before a synchronous expiry needs to find and release the frame.
                self._presentations[inst][record.role] = frame
            end
            local revealJob = {
                owner = inst.owner, scope = inst.scope, kind = "reveal",
                instance = inst, instanceGeneration = inst.generation,
                clockPolicy = "elapsed", deadline = revealAt, clock = inst.sourceClock,
            }
            revealJob.action = function()
                if not DT._IsPresentationCurrent(record) then return end
                if inst.binding.holdOverlapping then
                    if not KeepPresentationInstance(self, inst, GetTime()) then return end
                    local shown = State.PresentationHead(self._state, inst, IsShownPresentation)
                    if shown and shown ~= inst then
                        if not record.overlapHeld then dprint("presentation held text=" .. tostring(inst.label)) end
                        record.overlapHeld = true
                        -- Retirement or Resume wakes this job; no polling timer.
                        TrackJob(self, revealJob)
                        return
                    end
                    if record.overlapHeld then dprint("presentation released text=" .. tostring(inst.label)) end
                    record.overlapHeld = nil
                end
                record.revealJob = nil
                -- An overdue reveal must not show or sound an expired window.
                if inst.binding.cueKey and self:_ExpireTimerCue(inst, GetTime()) then return end
                frame:Show()
                if frame.bar and showWindow > 0 and showWindow < total then
                    frame.bar:SetMinMaxValues(0, showWindow)
                    frame.bar:SetValue(showWindow)
                    frame._lastValue = nil
                end
                -- Rule 7: a kept stop suppresses only this still-pending
                -- show sound, never the reveal itself.
                if not record.suppressShowSound then
                    PlayBarSound(frame, "show")
                end
                record.shown = true
                if inst.binding.holdOverlapping then BarOnUpdateInstance(frame, record) end
                self:LayoutBars()
            end
            record.revealJob = revealJob
            ScheduleJob(self, revealJob, now)
            if inst.state == "retired" then return nil end

            -- An owned instance's forecast end is decided by its expiry job; this
            -- job could run before a late reveal and retire it regardless.
            if not inst.binding.ownsExpiry then
                local retireJob = {
                    owner = inst.owner, scope = inst.scope, kind = "retire",
                    instance = inst, instanceGeneration = inst.generation,
                    clockPolicy = "elapsed", deadline = total, clock = inst.sourceClock,
                }
                retireJob.action = function()
                    record.retireJob = nil
                    if not record.shown then
                        if inst.binding.holdOverlapping then
                            local fireNow = GetTime()
                            if KeepPresentationInstance(self, inst, fireNow) then
                                if inst.holdDeadline ~= nil then
                                    -- Finished must be able to replace the hold with an anchored expiry.
                                    record.retireJob = retireJob
                                    TrackJob(self, retireJob)
                                else
                                    local elapsed, _, remaining = State.Sample(inst, fireNow)
                                    if elapsed == nil or remaining == nil then
                                        State.Retire(self._state, inst)
                                        self:ReleaseInstancePresentations(inst, false)
                                        return
                                    end
                                    local left = State.AnchoredRemaining(inst, elapsed)
                                        or remaining + inst.binding.extension + (inst.binding.forecastLead or 0)
                                    record.retireJob = retireJob
                                    retireJob.deadline = elapsed + left
                                    ScheduleJob(self, retireJob, fireNow)
                                end
                            end
                            return
                        end
                        -- A Timer cue whose reveal never ran still reached
                        -- its end; the ended text is timed from that end.
                        if inst.binding.cueKey then
                            local fireNow = GetTime()
                            local _, _, left = State.Sample(inst, fireNow)
                            if left then
                                self:_SpawnCueEnded(inst.owner, inst.binding.cueKey, fireNow + left)
                            end
                        end
                        State.Retire(self._state, inst)
                        self:ReleaseInstancePresentations(inst, false)
                    end
                end
                record.retireJob = retireJob
                ScheduleJob(self, retireJob, now)
                if inst.state == "retired" then return nil end
            end
        else
            if not record.suppressShowSound then
                PlayBarSound(frame, "show")
            end
            record.shown = true
        end
    else
        -- Synthetic presentations always show immediately.
        PlayBarSound(frame, "show")
    end

    self:LayoutBars()
    return frame
end

-- Frames and their reveal/retire jobs only; the table is emptied in place. The
-- instance's hold, owned expiry and cast work stay, so a forecast with no frame
-- keeps its own lifetime and a canceled reveal can never show a pooled frame.
local function ReleasePresentationFrames(self, presentations, playHide)
    local released = false
    for _, role in ipairs({ "primary", "secondary" }) do
        local frame = presentations[role]
        if frame then
            presentations[role] = nil
            local record = frame._dtPresentation
            if record then
                CancelJob(self, record.revealJob)
                CancelJob(self, record.retireJob)
                record.revealJob, record.retireJob = nil, nil
            end
            if playHide and frame:IsShown() then
                PlayBarSound(frame, "hide")
            end
            self.bars[frame._dtKey] = nil
            ReleaseBar(frame)
            released = true
        end
    end
    if released then self:LayoutBars() end
end

-- playHide follows the Stop-retire rule: only a shown presentation plays the hide sound.
-- The hold job, cast watch, observation window and linked shield watch are
-- resolved with the instance, on every retirement path.
-- fromCancel: a provider stop the timeline marks Canceled. A held overlap
-- successor it releases from behind a shown occurrence is the re-issue of an
-- announced cast, so it takes over without its show sound.
function DT:ReleaseInstancePresentations(inst, playHide, fromCancel)
    -- A canceled occurrence or an unconfirmed wait has nothing to announce.
    if inst.retainedEstimate == "canceled" or State.EndsSilently(inst) then playHide = false end
    self:_CancelHold(inst)
    self:_CloseCastWatch(inst, "retired")
    self:_CloseCastMatch(inst)
    self:_CloseCastFollow(inst)
    self:_CloseObservationWindow(inst, "retired")
    self:_ReleaseShieldWatchOf(inst)
    local observedRetire = self._observedRetireJobs[inst]
    if observedRetire then
        self._observedRetireJobs[inst] = nil
        CancelJob(self, observedRetire)
    end
    if inst.mapObserved then self:_WindMapRetired(inst) end
    self._gateSuppressed[inst] = nil
    local takeover = fromCancel == true and IsShownPresentation(inst)
    local presentations = self._presentations[inst]
    self._presentations[inst] = nil
    if presentations then ReleasePresentationFrames(self, presentations, playHide) end
    if inst.binding.holdOverlapping
        and not State.PresentationHead(self._state, inst, IsShownPresentation) then
        local head = State.PresentationHead(self._state, inst, IsWaitingPresentation)
        local record = head and PresentationRecord(head)
        if record then
            if takeover then record.suppressShowSound = true end
            ResumeJobHandle(self, record.revealJob, GetTime())
        end
    end
end

-- The reveal/retire jobs keep their original deadline; StopBar never moves them.
function DT:_ApplyCastPhaseVisual(inst, fill)
    local presentations = self._presentations[inst]
    if not presentations then return end
    for _, role in ipairs({ "primary", "secondary" }) do
        local frame = presentations[role]
        if frame then
            frame.castFromValue = fill
            if frame.castDisplayTextRaw then
                local cc = frame.castColor or DEFAULT_BAR_COLOR
                frame.baseText = frame.castBaseText or frame.baseText
                if frame.displayMode == "bar" then
                    if frame.bar then frame.bar:SetStatusBarColor(cc[1], cc[2], cc[3]) end
                    if frame.label then frame.label:SetText(frame.baseText) end
                else
                    if frame.label then frame.label:SetText(frame.baseText .. " \194\187") end
                    if frame.label then frame.label:SetTextColor(cc[1], cc[2], cc[3]) end
                    if frame.timerText then frame.timerText:SetTextColor(cc[1], cc[2], cc[3]) end
                end
            end
        end
    end
end

-- Rule 7's only effect on a kept stop: flag every presentation record so a
-- still-pending reveal shows silently. A gated instance has no record, so its
-- gate entry keeps the flag for the restore.
function DT:_SuppressPendingShowSound(inst)
    local gated = self._gateSuppressed[inst]
    if gated then gated.silent = true end
    local presentations = self._presentations[inst]
    if not presentations then return end
    for _, role in ipairs({ "primary", "secondary" }) do
        local frame = presentations[role]
        local record = frame and frame._dtPresentation
        if record then record.suppressShowSound = true end
    end
end

function DT:_OnSourcePauseChanged(inst, paused, now)
    local holdJob = self._holdJobs[inst]
    if holdJob then
        if paused then
            PauseJobHandle(self, holdJob)
        else
            ResumeJobHandle(self, holdJob, now)
        end
    end
    local observedRetire = self._observedRetireJobs[inst]
    if observedRetire then
        if paused then
            PauseJobHandle(self, observedRetire)
        else
            ResumeJobHandle(self, observedRetire, now)
        end
    end
    local presentations = self._presentations[inst]
    if not presentations then return end
    for _, role in ipairs({ "primary", "secondary" }) do
        local frame = presentations[role]
        local record = frame and frame._dtPresentation
        if record then
            if paused then
                PauseJobHandle(self, record.revealJob)
                PauseJobHandle(self, record.retireJob)
            else
                ResumeJobHandle(self, record.revealJob, now)
                ResumeJobHandle(self, record.retireJob, now)
            end
        end
    end
end

-- Moves the pending reveal/retire deadlines to an anchored or predicted total.
-- A prediction passes retireAt so the retire never passes its bound. A shown
-- presentation needs nothing: its OnUpdate reads the current remaining. A
-- hidden occurrence the wind map observes moves its own retire job instead.
function DT:_OnInstanceAnchored(inst, total, now, retireAt)
    if inst.mapObserved then
        if inst.trackOnly and inst.state ~= "retired" then
            self:_ArmObservedRetire(inst, retireAt or total, now)
        end
        self:_WindMapRetimed(inst, now)
    end
    local presentations = self._presentations[inst]
    if not presentations then return end
    for _, role in ipairs({ "primary", "secondary" }) do
        local frame = presentations[role]
        local record = frame and frame._dtPresentation
        if record then
            if record.revealJob then
                local showWindow = frame.showWindow or 0
                record.revealJob.deadline = showWindow > 0 and total - showWindow or 0
                ResumeJobHandle(self, record.revealJob, now)
            end
            if record.retireJob then
                record.retireJob.deadline = retireAt or total
                ResumeJobHandle(self, record.retireJob, now)
            end
        end
    end
end

-- Hold eligibility at forecast zero: the correlated event must still be
-- Active or Paused, or Finished for an owned parent with no extension, and
-- carry a usable queue allowance. Same refusal shape
-- as _ReadTimelineState; any nil retires the instance as before.
function DT:_ResolveHold(inst)
    if TIMELINE_STATE_ACTIVE == nil or TIMELINE_STATE_PAUSED == nil then return nil, nil, "no-enum" end
    if not (C_EncounterTimeline and C_EncounterTimeline.GetEventState) then return nil, nil, "no-api" end
    local eventId, maxQueue = State.ResolveTimelineEvent(self._state, inst)
    if not eventId then return nil, nil, maxQueue end
    if maxQueue == nil then return nil, eventId, "no-maxqueue" end
    local state = C_EncounterTimeline.GetEventState(eventId)
    if issecretvalue and issecretvalue(state) then return nil, eventId, "secret-state" end
    if state == nil then return nil, eventId, "gone" end
    -- Finished may precede the parent's stop callback; preserve its bounded anchor opportunity.
    local awaitsStop = inst.binding.ownsExpiry and not inst.binding.admitsLateFinished
        and (inst.binding.extension or 0) <= 0
        and TIMELINE_STATE_FINISHED ~= nil and state == TIMELINE_STATE_FINISHED
    if not awaitsStop and state ~= TIMELINE_STATE_ACTIVE and state ~= TIMELINE_STATE_PAUSED then
        return nil, eventId, "terminal"
    end
    return maxQueue, eventId
end

-- One owned job ends a hold or a wait at its bound. A job created on a paused
-- clock is registered without a timer so ResumeJobHandle arms it on Resume:
-- ScheduleJob would arm wall time from the frozen sample and
-- _OnSourcePauseChanged pauses only existing jobs.
local function ArmHoldJob(self, inst, deadline, now, onExpire)
    local job = {
        owner = inst.owner, scope = inst.scope, kind = "hold",
        instance = inst, instanceGeneration = inst.generation,
        clockPolicy = "elapsed", deadline = deadline, clock = inst.sourceClock,
    }
    job.action = function()
        self._holdJobs[inst] = nil
        onExpire()
    end
    self._holdJobs[inst] = job
    if inst.sourceClock.pausedAt ~= nil then
        TrackJob(self, job)
    else
        ScheduleJob(self, job, now)
    end
end

-- True once the instance is held; the owned hold job retires it at the
-- bound. A waitAfter row takes its own bounded wait instead.
function DT:_BeginHold(inst, now)
    if inst.binding.waitAfter then return self:_BeginForecastWait(inst, now) end
    local maxQueue, eventId, reason = self:_ResolveHold(inst)
    if not maxQueue then
        dprint(string_format("hold refused text=%s event=%s reason=%s",
            tostring(inst.label), tostring(eventId), tostring(reason)))
        return false
    end
    local deadline, holdReason = State.BeginHold(inst, maxQueue)
    if not deadline then
        dprint("hold refused: " .. tostring(holdReason))
        return false
    end
    ArmHoldJob(self, inst, deadline, now, function()
        dprint(string_format("hold expired text=%s elapsed=%.3f",
            tostring(inst.label), GetTime() - inst.sourceClock.receivedAt))
        State.Retire(self._state, inst)
        self:ReleaseInstancePresentations(inst, true)
    end)
    if DEBUG_DT2 then
        local blocked
        if C_EncounterTimeline.IsEventBlocked then blocked = C_EncounterTimeline.IsEventBlocked(eventId) end
        if issecretvalue and issecretvalue(blocked) then blocked = "secret" end
        dprint(string_format("hold text=%s event=%s maxQueue=%s deadline=%.3f blocked=%s at=%.3f",
            tostring(inst.label), tostring(eventId), tostring(maxQueue), deadline, tostring(blocked), now))
    end
    return inst.state ~= "retired"
end

-- A forecast confirmed only by its provider stop waits past zero for that
-- stop; the bound ends it silently.
function DT:_BeginForecastWait(inst, now)
    local deadline, reason = State.BeginForecastWait(inst)
    if not deadline then
        dprint("wait refused: " .. tostring(reason))
        return false
    end
    ArmHoldJob(self, inst, deadline, now, function()
        dprint("wait expired text=" .. tostring(inst.label))
        State.Retire(self._state, inst)
        self:ReleaseInstancePresentations(inst, true)
    end)
    dprint(string_format("wait text=%s deadline=%.3f at=%.3f", tostring(inst.label), deadline, now))
    return inst.state ~= "retired"
end

function DT:_CancelHold(inst)
    local job = self._holdJobs[inst]
    if not job then return end
    self._holdJobs[inst] = nil
    CancelJob(self, job)
end

-- One sequel slot per owner, counted parent label and child.
local function SequelSlotKey(label, childId)
    return tostring(label) .. ":" .. tostring(childId)
end

-- Forecast-zero decision of an ownsExpiry instance: one job on its own clock,
-- identical whether its cue is shown, hidden or never rendered. It takes the
-- existing hold, or retires the instance.
function DT:_ArmOwnedExpiry(inst, now)
    local job = {
        owner = inst.owner, scope = inst.scope, kind = "hold",
        instance = inst, instanceGeneration = inst.generation,
        clockPolicy = "elapsed",
        deadline = inst.sourceClock.remainingAtReceipt + inst.binding.extension + (inst.binding.forecastLead or 0),
        clock = inst.sourceClock,
    }
    job.action = function()
        self._holdJobs[inst] = nil
        local held = self:_BeginHold(inst, GetTime())
        dprint(string_format("expiry text=%s held=%s", tostring(inst.label), tostring(held)))
        if not held then
            State.Retire(self._state, inst)
            self:ReleaseInstancePresentations(inst, true)
        end
    end
    self._holdJobs[inst] = job
    ScheduleJob(self, job, now)
end

-- A filtered parent keeps dependent timing work under its owned expiry. A
-- filtered row the wind map observes also keeps its cast matching, unrendered.
-- A map-only occurrence the map refuses has no reason to exist and retires.
function DT:_StartTrackOnly(owner, label, binding, spellId, remaining, span, now, timelineIdentity, mapData,
                            mapOnly)
    local effectiveBinding = self:_EffectiveBinding(binding, self:GetSpellExtension(spellId))
    local inst, predecessor = State.Start(self._state, owner, label, effectiveBinding, remaining, span, now, false, true)
    if not inst then
        dprint("trackonly refused start: " .. tostring(predecessor))
        return
    end
    inst.timelineIdentity = timelineIdentity
    if predecessor then
        self:ReleaseInstancePresentations(predecessor, false)
    end
    self:_LinkShieldWatch(owner, label, spellId, inst)
    self:_ArmOwnedExpiry(inst, now)
    if mapData then
        inst.mapOnly = mapOnly
        self:_WindMapAttach(inst, mapData)
        if inst.mapObserved then
            if effectiveBinding.castMatch then self:_WatchCastMatch(inst) end
        elseif mapOnly then
            State.Retire(self._state, inst)
            self:ReleaseInstancePresentations(inst, false)
            return
        end
    end
    dprint(string_format("trackonly started text=%s deadline=%.3f", tostring(label),
        remaining + effectiveBinding.extension))
end

-- A hidden observed occurrence has no frame to end it, so one job retires it
-- at its anchored or estimated end. Every re-time re-arms it.
function DT:_ArmObservedRetire(inst, deadline, now)
    local previous = self._observedRetireJobs[inst]
    if previous then CancelJob(self, previous) end
    local job = {
        owner = inst.owner, scope = inst.scope, kind = "retire",
        instance = inst, instanceGeneration = inst.generation,
        clockPolicy = "elapsed", deadline = deadline, clock = inst.sourceClock,
    }
    job.action = function()
        self._observedRetireJobs[inst] = nil
        local fireNow = GetTime()
        if not KeepPresentationInstance(self, inst, fireNow) then return end
        local elapsed = State.Sample(inst, fireNow)
        local left = elapsed and State.AnchoredRemaining(inst, elapsed)
        if left and left > 0 then self:_ArmObservedRetire(inst, elapsed + left, fireNow) end
    end
    self._observedRetireJobs[inst] = job
    if inst.sourceClock.pausedAt ~= nil then
        TrackJob(self, job)
    else
        ScheduleJob(self, job, now)
    end
end

-- A curated parent's qualified Finished approximates its cast start; the one
-- target forecast still due before that cast and its gap end is moved later.
-- Display settings of either row take no part, and any refusal changes nothing.
function DT:_ApplyQueuedForecast(parent, now)
    local queues = self._bindings.queues[parent.binding.encounterId]
    local queue = queues and queues[parent.binding.curationId]
    if not queue then return end
    local target, selectReason = State.SelectQueuedTarget(self._state, parent.owner, queue.target, now, queue.delay)
    if not target then
        dprint("queue refused reason=" .. tostring(selectReason))
        return
    end
    local maxQueue, eventId, holdReason = self:_ResolveHold(target)
    if not maxQueue then
        dprint(string_format("queue refused text=%s event=%s reason=%s",
            tostring(target.label), tostring(eventId), tostring(holdReason)))
        return
    end
    local total, bound = State.Predict(target, now, queue.delay, maxQueue)
    if not total then
        dprint(string_format("queue refused text=%s reason=%s", tostring(target.label), tostring(bound)))
        return
    end
    self:_CancelHold(target)
    self:_OnInstanceAnchored(target, total, now, math_min(total, bound))
    dprint(string_format("queue text=%s parent=%s total=%.3f bound=%.3f at=%.3f",
        tostring(target.label), tostring(parent.label), total, bound, now))
end

-- One child cue per anchored parent occurrence. Timing and display mode are
-- read at the anchor, so the drawn mode matches the window it was planned
-- with; enabled, disabled and role state when the reveal job fires.
function DT:_ScheduleSequel(inst, now)
    local sequels = self._bindings.sequels[inst.binding.encounterId]
    local sequel = sequels and sequels[inst.binding.curationId]
    if not sequel then return end

    local child = sequel.key
    local display = self:GetSpellDisplay(child)
    local window = self:GetSpellEffectiveShowAtSeconds(child, display)
    if sequel.cueKey then
        -- Zero reveal covers the phase window, excluding the preceding gap.
        local cueRevealAt, cueEndAt = State.PlanSequel(now + sequel.after, 0, sequel.duration, window)
        if not cueRevealAt then
            dprint("sequel refused reason=" .. tostring(cueEndAt))
            return
        end
        self:_EndCue(inst.owner, sequel.cueKey)
        -- A cue never shows beside the window of the row whose anchor ends it.
        local ender = sequel.endsOnAnchor and sequels[sequel.endsOnAnchor]
        if ender and ender.cueKey and self:_IsCueWindowLive(inst.owner, ender.cueKey, now) then
            dprint("cue refused reason=ender-window cue=" .. sequel.cueKey)
            return
        end
        self:_ScheduleCueWindow(inst.owner, sequel.cueKey, display, cueRevealAt, cueEndAt, now)
        return
    end
    local revealAt, endAt = State.PlanSequel(now, sequel.after, self:GetSpellExtension(child), window)
    if not revealAt then
        dprint("sequel refused reason=" .. tostring(endAt))
        return
    end

    local owner = inst.owner
    local slotKey = SequelSlotKey(inst.label, child)
    local generation, slotReason = State.NextSlot(self._state, owner, "sequel", slotKey)
    if not generation then
        dprint("sequel refused reason=" .. tostring(slotReason))
        return
    end

    local job = {
        owner = owner, kind = "sequel", slotKey = slotKey, generation = generation,
        clockPolicy = "wall", deadline = revealAt,
    }
    job.action = function()
        if not (self.db and self.db.Enabled) then return end
        if self:IsSpellDisabled(child) then
            dprint("sequel suppressed reason=disabled label=" .. slotKey)
            return
        end
        if not self:ShouldShowSpellRole(child) then
            dprint("sequel suppressed reason=role label=" .. slotKey)
            return
        end
        local fireNow = GetTime()
        local duration = endAt - fireNow
        local frame = self:_SpawnSynthetic(owner, "sequel", slotKey, duration, display,
            self:ResolveSpellIcon(child), self:GetSpellDisplayText(child), child, fireNow)
        if frame then
            dprint(string_format("sequel fired label=%s duration=%.3f", slotKey, duration))
        else
            dprint("sequel suppressed reason=late label=" .. slotKey)
        end
    end
    dprint(string_format("sequel scheduled parent=%s label=%s child=%s reveal=%.3f end=%.3f",
        tostring(inst.binding.curationId), tostring(inst.label), tostring(child), revealAt, endAt))
    ScheduleJob(self, job, now)
end

local function CloseCueInterrupts(self, owner, cueKey, keep)
    for watch in pairs(self._cueInterrupts) do
        if watch ~= keep and (owner == nil or watch.owner == owner)
            and (cueKey == nil or watch.cueKey == cueKey) then
            self._cueInterrupts[watch] = nil
            CancelJob(self, watch.job)
        end
    end
    if next(self._cueInterrupts) == nil then
        self:_ReleaseUnitCastEvent("UNIT_SPELLCAST_INTERRUPTED", "cue")
        self:_ReleaseUnitCastEvent("UNIT_SPELLCAST_FAILED", "cue")
    end
end

-- Owned jobs and synthetic presentations only; the caller retires source instances.
local function ReleaseOwnerWork(self, owner)
    CloseCueInterrupts(self, owner)
    local jobs = self._ownedJobs[owner]
    if jobs then
        for job in pairs(jobs) do CancelJob(self, job) end
    end
    local slots = self._slotPresentations[owner]
    local released = false
    if slots then
        for _, byKey in pairs(slots) do
            for _, frame in pairs(byKey) do
                if frame._dtKey then self.bars[frame._dtKey] = nil end
                ReleaseBar(frame)
                released = true
            end
        end
        self._slotPresentations[owner] = nil
    end
    self._slotJobs[owner] = nil
    self._cueInstances[owner] = nil
    self._cueLabels[owner] = nil
    self._forecastGates[owner] = nil
    for inst in pairs(self._gateSuppressed) do
        if inst.owner == owner then self._gateSuppressed[inst] = nil end
    end
    if released then self:LayoutBars() end
end

-- The replacement frame is created before the predecessor is released so the
-- pool cannot hand the just-released kit back as the new presentation.
function DT:_SpawnSynthetic(owner, kind, slotKey, duration, displayMode, iconTex, displayText, spellId, now, opts)
    if not duration or duration <= 0 then return nil end
    local generation, reason = State.NextSlot(self._state, owner, kind, slotKey)
    if not generation then
        dprint("synthetic refused: " .. tostring(reason))
        return nil
    end

    local byOwner = self._slotPresentations[owner]
    local existing = byOwner and byOwner[kind] and byOwner[kind][slotKey]

    local record = {
        synthetic = kind, owner = owner, slotKey = slotKey, generation = generation,
        clock = State.NewClock(duration, duration, now),
    }
    if opts then
        record.silent = opts.silent
        record.endsCue = opts.endsCue
        record.ordinal = opts.ordinal
    end
    local frame = RenderPresentation(self, {}, record, duration, 0, displayMode, iconTex,
        displayText, spellId, nil, false)
    if not frame then return nil end

    if existing then
        if existing._dtKey then self.bars[existing._dtKey] = nil end
        ReleaseBar(existing)
    end

    self._slotPresentations[owner] = self._slotPresentations[owner] or {}
    self._slotPresentations[owner][kind] = self._slotPresentations[owner][kind] or {}
    self._slotPresentations[owner][kind][slotKey] = frame

    -- The predecessor's release happens after RenderPresentation's own
    -- layout pass, so that pass still counted it — re-run once the final
    -- registration set (predecessor gone, replacement in) is in place.
    if existing then
        self:LayoutBars()
    end

    return frame
end

local function ResolveIconOverride(value, fallback)
    if not value then return fallback end
    if type(value) == "number" and C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(value) or value
    end
    return value
end

-- Optional iconOverride on the postCastBar config takes precedence over the
-- parent's inherited icon; useful when the follow-up represents a different
-- visual cue (e.g. KNOCK icon → VULNERABILITY icon). Different counted
-- parent labels partition independent children via the slot key.
function DT:_SpawnPostCastBar(inst, parentFrame)
    local pcfg = self:GetSpellPostCastBar(inst.binding.curationId)
    if not pcfg then return end
    local parentIcon = parentFrame and parentFrame.icon and parentFrame.icon.GetTexture
        and parentFrame.icon:GetTexture() or nil
    local iconTex = ResolveIconOverride(pcfg.iconOverride, parentIcon)
    local slotKey = tostring(inst.label) .. ":" .. tostring(inst.binding.curationId)
    self:_SpawnSynthetic(inst.owner, "postcast", slotKey, tonumber(pcfg.duration) or 0,
        pcfg.display or "bar", iconTex, pcfg.displayText, inst.binding.curationId, GetTime())
end

-- Filtered by the phantom's own disabled/role state, never the parent's.
function DT:_SpawnPhantomFollowup(owner, phantomSpellId, parentIconTex, now)
    local data = self:GetSpellInfo(phantomSpellId)
    if not data then return end
    if self:IsSpellDisabled(phantomSpellId) then return end
    if not self:ShouldShowSpellRole(phantomSpellId) then return end
    local duration = tonumber(data.duration) or 0
    if duration <= 0 then return end
    local iconTex = ResolveIconOverride(data.iconOverride, parentIconTex)
    self:_SpawnPhantom(owner, phantomSpellId, duration, data.display or "bar", iconTex, data.displayText, now)
end

function DT:_SpawnPhantom(owner, phantomSpellId, duration, displayMode, iconTex, displayText, now)
    self:_SpawnSynthetic(owner, "phantom", phantomSpellId, duration, displayMode, iconTex,
        displayText, phantomSpellId, now)
end

-- Same-slot replacement cancels the pending job; admission is re-checked
-- when it fires. The pending job's identity is its own table stored under
-- self._slotJobs, not a slot generation — _SpawnSynthetic allocates the
-- generation for the rendered cue at fire time, so a second Message here
-- must not bump it and retire the still-visible previous cue early.
function DT:_SpawnMessageBar(owner, binding, key, now)
    local spellId = binding.curationId
    local data = self:GetSpellInfo(spellId)
    if not (data and data.spawnOnMessage) then return end
    if self:IsSpellDisabled(spellId) then return end
    if not self:ShouldShowSpellRole(spellId) then return end

    local slotKey = tostring(spellId) .. ":" .. tostring(key)

    self._slotJobs[owner] = self._slotJobs[owner] or {}
    self._slotJobs[owner]["message"] = self._slotJobs[owner]["message"] or {}
    local previous = self._slotJobs[owner]["message"][slotKey]
    if previous then CancelJob(self, previous) end

    local lead = tonumber(data.leadDelay) or 0
    local job = {
        owner = owner, kind = "message", slotKey = slotKey,
        clockPolicy = "wall", deadline = now + lead,
    }
    job.action = function()
        if not (self.db and self.db.Enabled) then return end
        self._slotJobs[owner]["message"][slotKey] = nil
        if self:IsSpellDisabled(spellId) then return end
        if not self:ShouldShowSpellRole(spellId) then return end
        local duration = tonumber(data.duration) or 0
        local iconTex = ResolveIconOverride(data.iconOverride, self:ResolveSpellIcon(spellId))
        self:_SpawnSynthetic(owner, "message", slotKey, duration, data.display or "bar",
            iconTex, data.displayText, spellId, GetTime())
    end
    self._slotJobs[owner]["message"][slotKey] = job
    ScheduleJob(self, job, now)
end

local CUE_LEG_SUFFIXES = { "#prepare", "", "#ended" }

-- Retire each leg silently; the caller controls any result text.
function DT:_EndCue(owner, cueKey, keepInterrupt)
    CloseCueInterrupts(self, owner, cueKey, keepInterrupt)
    local jobs = self._ownedJobs[owner]
    if jobs then
        for job in pairs(jobs) do
            if job.cueKey == cueKey and not (keepInterrupt and job == keepInterrupt.job) then
                CancelJob(self, job)
            end
        end
    end
    local byKey = self._slotPresentations[owner] and self._slotPresentations[owner]["cue"]
    local released = false
    if byKey then
        for i = 1, #CUE_LEG_SUFFIXES do
            local slotKey = cueKey .. CUE_LEG_SUFFIXES[i]
            local frame = byKey[slotKey]
            if frame then
                byKey[slotKey] = nil
                if frame._dtKey then self.bars[frame._dtKey] = nil end
                ReleaseBar(frame)
                released = true
            end
        end
    end
    local byCue = self._cueInstances[owner]
    local inst = byCue and byCue[cueKey]
    if inst then
        byCue[cueKey] = nil
        State.Retire(self._state, inst)
        self:ReleaseInstancePresentations(inst, false)
    end
    local labels = self._cueLabels[owner]
    if labels then labels[cueKey] = nil end
    if released then self:LayoutBars() end
end

-- A displaced label must not cancel the cue's newer occurrence.
function DT:_EndCueOccurrence(owner, cueKey, label)
    local labels = self._cueLabels[owner]
    if labels and labels[cueKey] == label then self:_EndCue(owner, cueKey) end
end

function DT:_EndCuesOnAnchor(inst)
    local enders = self._bindings.cueEnders[inst.binding.encounterId]
    local cueKeys = enders and enders[inst.binding.curationId]
    if not cueKeys then return end
    for i = 1, #cueKeys do
        self:_EndCue(inst.owner, cueKeys[i])
    end
end

-- Decided by the window's own end, not by leftover frames or jobs: a drawn
-- window counts while it has time left; a pending one only while admitted.
function DT:_IsCueWindowLive(owner, cueKey, now)
    local byKey = self._slotPresentations[owner] and self._slotPresentations[owner]["cue"]
    local frame = byKey and byKey[cueKey]
    local record = frame and frame._dtPresentation
    if record and record.clock then
        local _, _, remaining = State.SampleClock(record.clock, now)
        if remaining and remaining > 0 then return true end
    end
    if not self:ShouldShowSpell(cueKey) then return false end
    local jobs = self._ownedJobs[owner]
    if jobs then
        for job in pairs(jobs) do
            if job.cueKey == cueKey and job.endAt and now < job.endAt then return true end
        end
    end
    return false
end

-- Retire before a late reveal or pause can move the expired window's ending interval.
function DT:_ExpireTimerCue(inst, now)
    local _, _, left = State.Sample(inst, now)
    if not left or left > 0 then return false end
    self:_SpawnCueEnded(inst.owner, inst.binding.cueKey, now + left)
    State.Retire(self._state, inst)
    self:ReleaseInstancePresentations(inst, true)
    return true
end

function DT:_ScheduleCueWindow(owner, cueKey, display, revealAt, endAt, now, ordinal)
    local planKey = cueKey .. "#plan"
    local generation, slotReason = State.NextSlot(self._state, owner, "cue", planKey)
    if not generation then
        dprint("cue refused reason=" .. tostring(slotReason))
        return
    end
    local job = {
        owner = owner, kind = "cue", slotKey = planKey, generation = generation, cueKey = cueKey,
        clockPolicy = "wall", deadline = revealAt, endAt = endAt,
    }
    job.action = function()
        if not (self.db and self.db.Enabled) then return end
        if not self:ShouldShowSpell(cueKey) then
            dprint("cue suppressed reason=filtered cue=" .. cueKey)
            return
        end
        local data = self:GetSpellInfo(cueKey)
        if not data then return end
        local fireNow = GetTime()
        if fireNow >= endAt then
            self:_SpawnCueEnded(owner, cueKey, endAt)
            return
        end
        -- Covers a cue planned while this window's cue was disabled.
        local endedByWindow = self._bindings.cuesEndedByWindow[cueKey]
        if endedByWindow then
            for i = 1, #endedByWindow do self:_EndCue(owner, endedByWindow[i]) end
        end
        local endsCue
        if data.endedText then endsCue = cueKey end
        local label = self:GetSpellDisplayText(cueKey) or data.name
        if ordinal then label = label .. " " .. ordinal end
        self:_SpawnSynthetic(owner, "cue", cueKey, endAt - fireNow, display,
            self:ResolveSpellIcon(cueKey), label, cueKey, fireNow, { endsCue = endsCue, ordinal = ordinal })
    end
    dprint(string_format("cue scheduled cue=%s reveal=%.3f end=%.3f", cueKey, revealAt, endAt))
    ScheduleJob(self, job, now)
    return generation
end

local function ReadCueCastBarID(result)
    if not result or not UnitCastingInfo then return nil end
    local ok, castBarID = pcall(function() return select(10, UnitCastingInfo(result.unit)) end)
    if not ok or (issecretvalue and issecretvalue(castBarID)) then return nil end
    if not State.IsCastBarId(castBarID) then return nil end
    return castBarID
end

function DT:_ArmCueInterrupt(owner, cueKey, generation, result, castBarID, now, endAt, ordinal)
    if not generation or not castBarID or not self:ShouldShowSpell(cueKey) then return end
    local watch = {
        owner = owner, cueKey = cueKey, scope = self._state.scopes[owner],
        slotKey = cueKey .. "#plan", generation = generation, result = result,
        unit = result.unit, castBarID = castBarID, ordinal = ordinal, startedAt = now, endAt = endAt,
    }
    local job = {
        owner = owner, scope = watch.scope, kind = "cue", cueKey = cueKey,
        slotKey = watch.slotKey, generation = generation, clockPolicy = "wall", deadline = endAt,
    }
    job.action = function()
        if not self._cueInterrupts[watch] then return end
        CloseCueInterrupts(self, owner, cueKey)
    end
    watch.job = job
    self._cueInterrupts[watch] = true
    self:_AcquireUnitCastEvent("UNIT_SPELLCAST_INTERRUPTED", "cue")
    self:_AcquireUnitCastEvent("UNIT_SPELLCAST_FAILED", "cue")
    ScheduleJob(self, job, now)
    dprint("cue interrupt armed cue=" .. cueKey .. " ordinal=" .. tostring(ordinal) .. " castBarID=" .. tostring(castBarID))
end

function DT:OnUnitCastInterrupted(_, unit, _castGUID, _spellID, _interruptedBy, castBarID)
    self:_OnFollowedCastEnded(unit, castBarID, "interrupted")
    self:_OnCueCastEnded(unit, castBarID, "interrupted")
end

-- Cast-follow still takes the quiet failure; a kick ends only on a real one.
function DT:OnUnitCastFailed(event, unit, _castGUID, _spellID, castBarID)
    self:_OnFollowedCastEnded(unit, castBarID, "failed")
    if event == "UNIT_SPELLCAST_FAILED" then
        self:_OnCueCastEnded(unit, castBarID, "failed")
    end
end

local function SetStaticCueResult(frame, color)
    if not frame then return end
    frame.staticLabel = true
    if color then
        frame.fixedColor = color
        ApplyVisualsToBar(frame)
    end
    if frame.label then frame.label:SetText(frame.baseText) end
    if frame.timerText then frame.timerText:SetText("") end
end

function DT:_OnCueCastEnded(unit, castBarID, reason)
    if not (self.db and self.db.Enabled) or not AcceptBossUnit(unit) then return end
    if issecretvalue and issecretvalue(castBarID) then return end
    local now = GetTime()
    for watch in pairs(self._cueInterrupts) do
        if State.MatchCueInterrupt(self._state, watch, unit, castBarID, now) then
            -- Keep the consumed ID until its original deadline to refuse duplicate Messages.
            watch.completed = true
            self:_EndCue(watch.owner, watch.cueKey, watch)
            local result = watch.result
            local outcome = watch.ordinal == result.ordinal and "done" or "stopped"
            if outcome == "done" and self:ShouldShowSpell(watch.cueKey) then
                local frame = self:_SpawnSynthetic(watch.owner, "cue", watch.cueKey .. "#ended",
                    result.duration, "text", self:ResolveSpellIcon(watch.cueKey), result.displayText,
                    watch.cueKey, now, { silent = true })
                SetStaticCueResult(frame, result.color)
                -- The frame stays silent, so its show and hide sounds never play;
                -- the result's clip plays once here.
                if frame then PlayPresetSound(self:GetEffectiveCueResultSound(watch.cueKey)) end
            end
            dprint("cue interrupt " .. outcome .. " cue=" .. watch.cueKey .. " castBarID=" .. tostring(castBarID) .. " reason=" .. reason)
        end
    end
end

-- Assigned below, after the readable-value helpers it uses.
local ReadCountInputs

-- Compare the provider's localized count text instead of parsing the Message.
function DT:_MatchCueMessage(owner, binding, data, message)
    if not (data.ordinals or data.messageCount) then return true end
    local templateKey = data.ordinals and "count_amount" or "count"
    local template, renameOrReason = ReadCountInputs(owner, binding.key, templateKey)
    if not template then return nil, renameOrReason end
    local matched, reason
    if data.ordinals then
        matched, reason = State.MatchMessageOrdinal(message, template, renameOrReason, data.ordinals)
    else
        matched, reason = State.MatchMessageCount(message, template, renameOrReason, data.messageCount)
    end
    if not matched then return nil, reason end
    if data.ordinals then return true, matched end
    return true
end

-- Check the cap before replacing the current occurrence. A count or ordinal
-- is matched first, so a refused Message changes nothing and uses no cap.
function DT:_OnCueMessage(owner, binding, now, message)
    local cueKey = binding.cueKey
    local data = self:GetSpellInfo(cueKey)
    if not data then return end
    local matched, ordinalOrReason = self:_MatchCueMessage(owner, binding, data, message)
    if not matched then
        dprint("cue refused reason=" .. tostring(ordinalOrReason) .. " cue=" .. cueKey)
        return
    end
    local ordinal = ordinalOrReason
    -- A hidden cue reads no cast; its Message bookkeeping below still runs.
    local castBarID
    if data.interruptResult and self:ShouldShowSpell(cueKey) then
        castBarID = ReadCueCastBarID(data.interruptResult)
        for watch in pairs(self._cueInterrupts) do
            if watch.owner == owner and watch.cueKey == cueKey
                and State.IsCueMessageDuplicate(self._state, watch, ordinal, castBarID, now) then return end
        end
    end
    -- Phase knowledge precedes the cap and every display filter of the cue.
    self:_OpenForecastGate(owner, binding, data, now)
    local admitted, capReason = State.AdmitCue(self._state, binding.encounterId, cueKey, data.maxPerPull)
    if not admitted then
        dprint("cue refused reason=" .. tostring(capReason) .. " cue=" .. cueKey)
        return
    end
    self:_EndCue(owner, cueKey)

    local lead = data.leadDelay or 0
    local display = self:GetSpellDisplay(cueKey)
    local window = self:GetSpellEffectiveShowAtSeconds(cueKey, display)
    local revealAt, endAt = State.PlanSequel(now + lead, 0, data.duration, window)
    if not revealAt then
        dprint("cue refused reason=" .. tostring(endAt))
        return
    end
    if data.prepareText and self:ShouldShowSpell(cueKey) then
        self:_SpawnSynthetic(owner, "cue", cueKey .. "#prepare", lead, "text",
            self:ResolveSpellIcon(cueKey), data.prepareText, cueKey, now, { silent = true })
    end
    local generation = self:_ScheduleCueWindow(owner, cueKey, display, revealAt, endAt, now, ordinal)
    self:_ArmCueInterrupt(owner, cueKey, generation, data.interruptResult, castBarID, now, endAt, ordinal)
end

-- A covered forecast loses only its frames until the gate closes or its
-- Finished anchors it. An instance already suppressed keeps its first entry.
-- silent carries a played or suppressed show sound across every restored
-- record, so no later gate can sound it again.
function DT:_OpenForecastGate(owner, binding, data, now)
    local gates = self._bindings.forecastGates[binding.encounterId]
    local cueKey = binding.cueKey
    local spells = gates and gates[cueKey]
    if not spells then return end
    local slotKey = cueKey .. "#gate"
    local generation, slotReason = State.NextSlot(self._state, owner, "cue", slotKey)
    if not generation then
        dprint("gate refused reason=" .. tostring(slotReason))
        return
    end
    local endsAt = now + (data.leadDelay or 0) + data.duration
    self._forecastGates[owner] = self._forecastGates[owner] or {}
    self._forecastGates[owner][cueKey] = { endsAt = endsAt, spells = spells }
    -- No cueKey field: the cue's own replacement must not cancel the gate.
    local job = {
        owner = owner, kind = "cue", slotKey = slotKey, generation = generation,
        clockPolicy = "wall", deadline = endsAt,
    }
    job.action = function() self:_CloseForecastGate(owner, cueKey) end
    ScheduleJob(self, job, now)
    for inst, presentations in pairs(self._presentations) do
        if inst.owner == owner and spells[inst.binding.curationId] and inst.anchorElapsed == nil
            and not self._gateSuppressed[inst] then
            local primary = presentations.primary
            local record = primary and primary._dtPresentation
            self._gateSuppressed[inst] = {
                silent = record ~= nil and (record.shown == true or record.suppressShowSound == true),
            }
            ReleasePresentationFrames(self, presentations, false)
        end
    end
    dprint(string_format("gate opened cue=%s ends=%.3f", cueKey, endsAt))
end

function DT:_CloseForecastGate(owner, cueKey)
    local gates = self._forecastGates[owner]
    if gates then gates[cueKey] = nil end
    local now = GetTime()
    -- A restore clears entries, and a retiring one clears its entry again
    -- through ReleaseInstancePresentations, so restores run after the walk.
    local due = {}
    for inst in pairs(self._gateSuppressed) do
        if inst.owner == owner and not State.GateCovers(gates, inst.binding.curationId, now) then
            due[#due + 1] = inst
        end
    end
    for i = 1, #due do
        self:_RestoreGatedPresentation(due[i], now)
    end
    dprint("gate closed cue=" .. tostring(cueKey))
end

-- Set sound history before RenderPresentation, which may show synchronously.
-- A paused source leaves new jobs registered but unarmed until Resume.
function DT:_RestoreGatedPresentation(inst, now)
    local entry = self._gateSuppressed[inst]
    if not entry then return end
    self._gateSuppressed[inst] = nil
    if not State.IsCurrent(self._state, inst, inst.generation, inst.moduleEpoch, inst.encounterEpoch) then
        return
    end
    -- ClassifyExpiry answers "keep" for an unheld owned instance past forecast
    -- zero, leaving hold-or-retire to its expiry job. When that job is due, it
    -- runs first, so a retiring forecast is never drawn or sounded.
    local expiryJob = self._holdJobs[inst]
    if expiryJob and inst.binding.ownsExpiry and inst.anchorElapsed == nil and inst.holdDeadline == nil then
        local left = State.JobRemaining(expiryJob.clockPolicy, expiryJob.deadline, expiryJob.clock, now)
        if left and left <= 0 then
            CancelJob(self, expiryJob)
            RunJob(expiryJob)
            if inst.state == "retired" then return end
        end
    end
    local spellId = inst.binding.curationId
    if not (self.db and self.db.Enabled) or not self:ShouldShowSpell(spellId)
        or State.ClassifyExpiry(inst, now) ~= "keep" then
        State.Retire(self._state, inst)
        self:ReleaseInstancePresentations(inst, false)
        return
    end
    local presentations = self._presentations[inst]
    if not presentations then return end
    local record = { instance = inst, generation = inst.generation, role = "primary", shown = false,
        suppressShowSound = entry.silent }
    local frame = RenderPresentation(self, {}, record,
        inst.sourceClock.remainingAtReceipt + (inst.binding.forecastLead or 0),
        inst.binding.extension or 0, self:GetSpellDisplay(spellId), inst.receiptIcon,
        self:GetSpellDisplayText(spellId), spellId, self:GetSpellCastDisplayText(spellId), false)
    if not frame then return end
    presentations.primary = frame
    if inst.sourceClock.pausedAt ~= nil then
        PauseJobHandle(self, record.revealJob)
        PauseJobHandle(self, record.retireJob)
    end
end

-- Keep the ending interval tied to natural expiry, even when dispatch runs late.
function DT:_SpawnCueEnded(owner, cueKey, endedAt)
    local data = self:GetSpellInfo(cueKey)
    if not (data and data.endedText) then return end
    if not (self.db and self.db.Enabled) then return end
    if not self:ShouldShowSpell(cueKey) then return end
    local now = GetTime()
    local left = endedAt + data.endedDuration - now
    if left <= 0 then return end
    local frame = self:_SpawnSynthetic(owner, "cue", cueKey .. "#ended", left, "text",
        self:ResolveSpellIcon(cueKey), data.endedText, cueKey, now, { silent = true })
    SetStaticCueResult(frame, data.endedColor)
end

local CUE_PROVIDER_OPTIONS = {
    ["cue:2609:awaken_whelps"] = {
        moduleName = "Melidrussa Chillworn", encounterId = 2609, optionKey = 373046,
        label = "Awaken Whelps",
        manualPath = "Ruby Life Pools > Melidrussa Chillworn > Awaken Whelps > Advanced options > Messages",
        instanceID = 2521, dungeonName = "Ruby Life Pools", contentAddon = "LittleWigs_Dragonflight",
        mythicOnly = true,
    },
    ["cue:3101:light_infusion"] = {
        moduleName = "Kystia Manaheart", encounterId = 3101, optionKey = 1230304,
        label = "Light Infusion",
        manualPath = "Murder Row > Kystia Manaheart > Light Infusion > Advanced options > Messages",
        instanceID = 2813, dungeonName = "Murder Row", contentAddon = "LittleWigs",
    },
    ["cue:3201:bear_form"] = {
        moduleName = "Lightwarden Ruia", encounterId = 3201, optionKey = 1239885,
        label = "Bear Form",
        manualPath = "The Blinding Vale > Lightwarden Ruia > Shapeshift: Bear > Advanced options > Messages",
        instanceID = 2859, dungeonName = "The Blinding Vale", contentAddon = "LittleWigs",
    },
    ["cue:3201:haranir_form"] = {
        moduleName = "Lightwarden Ruia", encounterId = 3201, optionKey = 1239883,
        label = "Haranir Form",
        manualPath = "The Blinding Vale > Lightwarden Ruia > Shapeshift: Haranir > Advanced options > Messages",
        instanceID = 2859, dungeonName = "The Blinding Vale", contentAddon = "LittleWigs",
    },
    ["cue:3456:pull_stomp"] = {
        moduleName = "Rav'i", encounterId = 3456, optionKey = 1307894,
        label = "Ravenous Stomp",
        manualPath = "Altar of Fangs > Rav'i > Ravenous Stomp > Advanced options > Messages",
        instanceID = 2993, dungeonName = "Altar of Fangs", contentAddon = "LittleWigs",
    },
    ["cue:3457:toxic_atrophy_kicks"] = {
        moduleName = "The Writhing Coil", encounterId = 3457, optionKey = 1310358,
        label = "Toxic Atrophy (Stage 2)",
        manualPath = "Altar of Fangs > The Writhing Coil > Stage 2 > Toxic Atrophy > Advanced options > Messages",
        instanceID = 2993, dungeonName = "Altar of Fangs", contentAddon = "LittleWigs",
    },
    ["cue:3457:burrowing_charge"] = {
        moduleName = "The Writhing Coil", encounterId = 3457, optionKey = 1299130,
        label = "Burrowing Charge",
        manualPath = "Altar of Fangs > The Writhing Coil > Burrowing Charge > Advanced options > Messages",
        instanceID = 2993, dungeonName = "Altar of Fangs", contentAddon = "LittleWigs",
    },
    ["cue:3457:venom_jet"] = {
        moduleName = "The Writhing Coil", encounterId = 3457, optionKey = 1300044,
        label = "Venom Jet",
        manualPath = "Altar of Fangs > The Writhing Coil > Venom Jet > Advanced options > Messages",
        instanceID = 2993, dungeonName = "Altar of Fangs", contentAddon = "LittleWigs",
    },
    ["cue:3458:axegrinder_channel"] = {
        moduleName = "Zul'jan", encounterId = 3458, optionKey = 1301111,
        label = "Axegrinder (Channel)",
        manualPath = "Altar of Fangs > Zul'jan > Axegrinder > Advanced options > Messages",
        instanceID = 2993, dungeonName = "Altar of Fangs", contentAddon = "LittleWigs",
    },
    ["cue:3458:ritual_channel"] = {
        moduleName = "Zul'jan", encounterId = 3458, optionKey = 1300876,
        label = "Ritual of the Fang (Channel)",
        manualPath = "Altar of Fangs > Zul'jan > Ritual of the Fang > Advanced options > Messages",
        instanceID = 2993, dungeonName = "Altar of Fangs", contentAddon = "LittleWigs",
    },
    ["warn:2124:shield"] = {
        moduleName = "Adderis and Aspix", encounterId = 2124, optionKey = 1310311,
        label = "Storm Blessed (WRONG TARGET)",
        manualPath = "Temple of Sethraliss > Adderis and Aspix > Storm Blessed > Advanced options > Messages",
        instanceID = 1877, dungeonName = "Temple of Sethraliss", contentAddon = "LittleWigs_BattleForAzeroth",
        mythicOnly = true,
    },
}

local CUE_PROVIDER_ORDER = {
    "cue:3101:light_infusion", "cue:2609:awaken_whelps", "cue:3201:bear_form", "cue:3201:haranir_form",
    "cue:3456:pull_stomp", "cue:3457:toxic_atrophy_kicks", "cue:3457:burrowing_charge", "cue:3457:venom_jet",
    "cue:3458:axegrinder_channel", "cue:3458:ritual_channel", "warn:2124:shield",
}

local CUE_PROVIDER_PROMPT = "%s needs BigWigs Messages to show this alert. Enable Messages for %s"
    .. " in your current BigWigs profile? BigWigs may also show its own message."

local CUE_PROVIDER_REFUSALS = {
    combat = "you are in combat",
    ["module-disabled"] = "Dungeon Timers is disabled",
    ["cue-disabled"] = "this alert is disabled",
    ["profile-changed"] = "the BigWigs profile changed",
    ["not-applicable"] = "this alert requires Mythic or Mythic+ difficulty in this dungeon",
    unknown = "BigWigs could not be checked",
}

local function IsReadableTable(value)
    if issecretvalue and issecretvalue(value) then return false end
    if type(value) ~= "table" then return false end
    if canaccesstable and not canaccesstable(value) then return false end
    return true
end

local function IsPlainValue(value, typeName)
    if issecretvalue and issecretvalue(value) then return false end
    return type(value) == typeName
end

-- An unregistered locale reads as nil and a key without a rename raises; each refuses.
ReadCountInputs = function(owner, key, templateKey)
    local api = BigWigsAPI
    if not IsReadableTable(api) then return nil, "no-provider-api" end
    local getLocale = api.GetLocale
    if not IsPlainValue(getLocale, "function") then return nil, "no-provider-api" end
    local okLocale, locale = pcall(getLocale, api, "BigWigs: Common")
    if not okLocale or not IsReadableTable(locale) then return nil, "no-locale" end
    ---@cast locale table
    local template = rawget(locale, templateKey)
    if not IsPlainValue(template, "string") then return nil, "no-template" end
    local getRename = owner.GetRename
    if not IsPlainValue(getRename, "function") then return nil, "no-rename" end
    local okRename, rename = pcall(getRename, owner, key)
    if not okRename or not IsPlainValue(rename, "string") or rename == "" then return nil, "no-rename" end
    return template, rename
end

-- Indexing the profile lets a newly switched profile resolve its defaults.
function DT:_ReadCueProviderOption(cueKey)
    local entry = CUE_PROVIDER_OPTIONS[cueKey]
    if not entry then return nil end
    if not IsReadableTable(BigWigsLoader) then return "unknown", nil, entry, "no-provider" end
    local core = BigWigs
    if not IsReadableTable(core) then return "unknown", nil, entry, "not-loaded" end
    local constants, getModule = core.C, core.GetBossModule
    if not IsReadableTable(constants) or not IsPlainValue(getModule, "function") then
        return "unknown", nil, entry
    end
    local messageBit, emphasizeBit = constants.MESSAGE, constants.EMPHASIZE
    if not (IsPlainValue(messageBit, "number") and IsPlainValue(emphasizeBit, "number")) then
        return "unknown", nil, entry
    end

    local okModule, module = pcall(getModule, core, entry.moduleName, true)
    if not okModule then return "unknown", nil, entry, "unreadable" end
    if not IsReadableTable(module) then return "unknown", nil, entry, "not-loaded" end
    local getEncounterID = module.GetEncounterID
    if not IsPlainValue(getEncounterID, "function") then return "unknown", nil, entry end
    local ids = { pcall(getEncounterID, module) }
    local owns = false
    if ids[1] == true then
        for i = 2, #ids do
            if IsPlainValue(ids[i], "number") and ids[i] == entry.encounterId then owns = true end
        end
    end
    if not owns then return "unknown", nil, entry end

    -- toggleDefaults says the option exists; it is never the current setting.
    local defaults, db = module.toggleDefaults, module.db
    if not IsReadableTable(defaults) or not IsPlainValue(defaults[entry.optionKey], "number") then
        return "unknown", nil, entry
    end
    if not IsReadableTable(db) then return "unknown", nil, entry end
    local okProfile, profile = pcall(function() return db.profile end)
    if not okProfile or not IsReadableTable(profile) then return "unknown", nil, entry end
    ---@cast profile table
    local toggles = rawget(profile, "toggles")
    if not IsReadableTable(toggles) then return "unknown", nil, entry end
    local flags = rawget(toggles, entry.optionKey)
    if not IsPlainValue(flags, "number") then return "unknown", nil, entry end

    local status = State.ProviderMessageStatus(flags, messageBit, emphasizeBit)
    if status == "unknown" then return "unknown", nil, entry end
    return status, {
        profile = profile, toggles = toggles, flags = flags,
        messageBit = messageBit, emphasizeBit = emphasizeBit,
    }, entry
end

-- Resolve the current notice because the settings page may have been replaced.
local function NotifyCueProviderNotice(self, cueKey)
    local notice = self._cueProviderNotice
    if notice then notice(cueKey) end
    local headerNotice = self._providerSetupHeaderNotice
    if headerNotice then headerNotice(cueKey) end
end

-- No combat refusal: raised in combat it waits in the prompt queue.
function DT:_OpenCueProviderPrompt(cueKey, origin)
    if self:_ProviderSetupGate(cueKey, false) then
        self:_RetireProviderPrompt(cueKey)
        NotifyCueProviderNotice(self, cueKey)
        return
    end
    if origin == "auto" and self._cueProviderAccept then return end
    local status, context, entry = self:_ReadCueProviderOption(cueKey)
    if status ~= "missing" or not context then
        NotifyCueProviderNotice(self, cueKey)
        return
    end
    self:_RetireProviderPrompt()
    -- Asking again ends an earlier Later, so a refused accept can bring the prompt back.
    if origin ~= "auto" then self._providerSetupAnswered[cueKey] = nil end
    local openedProfile = context.profile
    local accept
    local function release()
        if self._cueProviderAccept ~= accept then return false end
        self._cueProviderAccept = nil
        self._cueProviderOrigin = nil
        self._cueProviderKey = nil
        return true
    end
    -- A refused acceptance must not count as Later.
    accept = function()
        if not release() then return end
        self:_AcceptCueProviderPrompt(cueKey, openedProfile)
        self:_RequestProviderSetupCheck()
    end
    local function decline()
        if release() then
            self:_NoteProviderPromptAnswered(cueKey)
            self:_RequestProviderSetupCheck()
        end
    end
    self._cueProviderAccept = accept
    self._cueProviderOrigin = origin or "explicit"
    self._cueProviderKey = cueKey
    KE:CreatePrompt(entry.label, string_format(CUE_PROVIDER_PROMPT, entry.label, entry.label),
        false, nil, true, self:_ResolveProviderIcon(cueKey) or 134400, 20, 20, nil, accept, decline,
        "Enable Messages", "Later", false, nil,
        { waitIfBusy = true, parkKey = "DungeonTimers.providerSetup" })
end

function DT:_AcceptCueProviderPrompt(cueKey, openedProfile)
    local refusal = self:_ProviderSetupGate(cueKey, InCombatLockdown() and true or false)
    if refusal then
        local gated = CUE_PROVIDER_OPTIONS[cueKey]
        if gated then
            KE:Print(string_format("BigWigs Messages for %s was not changed: %s.", gated.label,
                CUE_PROVIDER_REFUSALS[refusal] or CUE_PROVIDER_REFUSALS.unknown))
        end
        NotifyCueProviderNotice(self, cueKey)
        return
    end
    local status, context, entry = self:_ReadCueProviderOption(cueKey)
    if not status then return end
    local current = {
        inCombat = InCombatLockdown() and true or false,
        cueEnabled = self:_IsProviderCueEnabled(cueKey),
    }
    if context then
        current.profile, current.flags = context.profile, context.flags
        current.messageBit, current.emphasizeBit = context.messageBit, context.emphasizeBit
    end
    local decision, detail = State.PlanProviderMessageEnable({ profile = openedProfile }, current)
    if decision == "write" and context then
        context.toggles[entry.optionKey] = detail
        if self:_ReadCueProviderOption(cueKey) == "satisfied" then
            KE:Print(string_format("BigWigs Messages enabled for %s.", entry.label))
        else
            KE:Print(string_format("BigWigs Messages for %s could not be confirmed.", entry.label))
        end
    elseif decision == "satisfied" then
        KE:Print(string_format("BigWigs Messages or Emphasize is already on for %s.", entry.label))
    else
        KE:Print(string_format("BigWigs Messages for %s was not changed: %s.", entry.label,
            CUE_PROVIDER_REFUSALS[detail] or CUE_PROVIDER_REFUSALS.unknown))
    end
    NotifyCueProviderNotice(self, cueKey)
end

-- Zone exit and real profile boundaries. Leaves previews and phase bars to their
-- own cleanup; ApplySettings never calls this.
local function RetireOrdinaryWork(self)
    CloseCueInterrupts(self)
    self:_HideAllShieldBars()
    local retired = State.RetireAll(self._state)
    for i = 1, #retired do
        self:ReleaseInstancePresentations(retired[i], false)
    end
    self:_CloseAllCastWork("retired")
    for job in pairs(self._jobs) do
        if job.handle then self:CancelTimer(job.handle) end
    end
    self._jobs = {}
    self._ownedJobs = {}
    for _, byKind in pairs(self._slotPresentations) do
        for _, byKey in pairs(byKind) do
            for _, frame in pairs(byKey) do
                if frame._dtKey then self.bars[frame._dtKey] = nil end
                ReleaseBar(frame)
            end
        end
    end
    self._slotPresentations = {}
    self._slotJobs = {}
    self._cueInstances = {}
    self._cueLabels = {}
    self._forecastGates = {}
    self._gateSuppressed = {}
    self._ownerMeta = {}
    self._pullHold = {}
    self._presentations = {}
    self._effectiveBindings = {}
    self._holdJobs = {}
    self._castWatches = {}
    self._observeWindows = {}
    self._castMatches = {}
    self._castFollows = {}
    self._observedRetireJobs = {}
    self:_WindMapTeardown()
    self:LayoutBars()
end

-- ╔══════════════════════════════════════════════════════════╗
-- ║  Phase tracker (HP%-driven)                              ║
-- ║  While unit HP is in (threshold, threshold + lead], shows║
-- ║  a "Phase Transition X%" bar that updates as the boss    ║
-- ║  takes damage. Always shown to everyone (no role filter).║
-- ║                                                          ║
-- ║  Per-rule overrides (Disabled / Display / Color / Sounds ║
-- ║  / Lead) are stored on phase rule keys and resolved      ║
-- ║  through DT:GetPhase* helpers (see above).               ║
-- ╚══════════════════════════════════════════════════════════╝

local PHASE_BAR_ICON = 6013778  -- matches PHASE_ROW_ICON in the GUI list
local PHASE_TRANSITIONED_LABEL = "Phase Transitioned"  -- shown briefly after HP crosses threshold
-- HP percent below threshold during which the "Phase Transitioned" overlay stays
-- visible. Narrow band → brief flash. At typical M+
-- DPS, 1% HP burns through in ~1-3s. Wider (e.g. lead-mirroring 5%) would linger
-- for the entire post-phase damage window which the user found too long.
local PHASE_TRANSITIONED_BAND = 1

local function PlayPhaseSound(key, hookKey)
    if not (key and hookKey) then return end
    local soundKey
    if hookKey == "show" then
        soundKey = DT:GetEffectivePhaseSoundOnShow(key)
    elseif hookKey == "hide" then
        soundKey = DT:GetEffectivePhaseSoundOnHide(key)
    end
    PlayPresetSound(soundKey)
end

-- Per-key configuration, shared by fresh kits (CreatePhaseBar tail) and the
-- reused preview kits (ShowPhasePreview cache): identity fields, visual
-- resolution (ApplyVisualsToBar reads frame.phaseKey for the user color
-- override), and the white no-override default.
local function ConfigurePhaseBar(self, frame, key, sortIndex)
    frame.text = key
    frame.phaseKey = key
    frame.isPhaseBar = true
    frame.phase = "phase"  -- distinguishes from "countdown"/"cast"
    frame.sortIndex = sortIndex

    if frame.displayMode == "bar" and frame.bar then
        frame.bar:SetMinMaxValues(0, 1)
        frame.bar:SetValue(1)
    end
    if frame.transitionText then frame.transitionText:SetAlpha(0) end

    -- Color resolution: ApplyVisualsToBar reads frame.phaseKey for the user
    -- override. Phase bars without an override default to plain white (not
    -- the addon's blue DEFAULT_BAR_COLOR) — phase alerts read better neutral
    -- and let the user paint them via the GUI color picker if desired.
    frame.baseText = ""
    ApplyVisualsToBar(frame)
    -- Now the font is set; safe to assign the static overlay text.
    frame.transitionText:SetText(PHASE_TRANSITIONED_LABEL)
    if not self:GetPhaseColorOverride(key) then
        frame.barColor = { 1, 1, 1 }
        if frame.displayMode == "bar" then
            if frame.bar then frame.bar:SetStatusBarColor(1, 1, 1) end
        else
            if frame.label then frame.label:SetTextColor(1, 1, 1) end
            if frame.transitionText then frame.transitionText:SetTextColor(1, 1, 1) end
        end
    end
end

local function CreatePhaseBar(self, key, sortIndex)
    local mode = self:GetPhaseDisplay(key)
    local isBar = (mode == "bar")
    local group = isBar and self:EnsureBarGroup() or self:EnsureTextGroup()

    local px = (KE.GetPixelSize and KE:GetPixelSize()) or 1

    local frame = CreateFrame("Frame", nil, group)
    frame.displayMode = mode

    if isBar then
        frame.iconFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        frame.iconFrame:SetPoint("LEFT", frame, "LEFT", 0, 0)
        frame.iconFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        frame.iconFrame:SetBackdropColor(0, 0, 0, 0.8)
        if KE.AddIconBorders then KE:AddIconBorders(frame.iconFrame) end

        frame.icon = frame.iconFrame:CreateTexture(nil, "ARTWORK")
        frame.icon:SetPoint("TOPLEFT", px, -px)
        frame.icon:SetPoint("BOTTOMRIGHT", -px, px)
        if KE.ApplyIconZoom then KE:ApplyIconZoom(frame.icon) end
        frame.icon:SetTexture(PHASE_BAR_ICON)

        frame.barContainer = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        frame.barContainer:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = px,
        })
        frame.barContainer:SetBackdropColor(0, 0, 0, 0.8)
        frame.barContainer:SetBackdropBorderColor(0, 0, 0, 1)

        frame.bar = CreateFrame("StatusBar", nil, frame.barContainer)
        frame.bar:SetPoint("TOPLEFT", px, -px)
        frame.bar:SetPoint("BOTTOMRIGHT", -px, px)

        frame.label = frame.bar:CreateFontString(nil, "OVERLAY")
        frame.timerText = frame.bar:CreateFontString(nil, "OVERLAY")
    else
        frame.bar = CreateFrame("StatusBar", nil, frame)
        frame.bar:SetAllPoints()
        frame.label = frame.bar:CreateFontString(nil, "OVERLAY")
    end
    -- "Phase Transitioned" overlay: parented to the outer frame so its alpha is
    -- INDEPENDENT of bar.bar's alpha. Driven by the transitionedCurve so it appears
    -- only when HP is in the [threshold-lead, threshold] band — i.e., just AFTER
    -- the boss has phased, before fade-out. bar.bar's alpha hides the countdown
    -- bar/label/timerText at that moment; transitionText takes the visual.
    -- Font must be applied before SetText (FontString: "Font not set" otherwise),
    -- so SetText is deferred until after ApplyVisualsToBar runs.
    frame.transitionText = frame:CreateFontString(nil, "OVERLAY")
    frame.transitionText:SetAlpha(0)

    ConfigurePhaseBar(self, frame, key, sortIndex)

    return frame
end

-- Called every tick during the encounter with four secret HP-curve outputs:
--   secretValue        — bar fill / countdown integer (0..lead)
--   secretCountdown    — alpha for the countdown elements (bar.bar)
--   secretTransitioned — alpha for the "Phase Transitioned" overlay
--   secretFrameAlpha   — outer frame alpha (union of countdown + transitioned bands)
-- The bar is created lazily and kept in self.bars for the encounter's duration —
-- visibility is driven by SetAlpha because we can't read the secret value in addon
-- code to make a Show/Hide choice. Layout reserves its slot after ordinary
-- countdowns, including while the phase frame is transparent.
function DT:_ShowPhaseBar(key, secretValue, secretCountdown, secretTransitioned, secretFrameAlpha, lead)
    local bar = self.bars[key]
    local needLayout = false
    local justAppeared = false
    -- Rebuild if the user toggled display mode while a bar is alive.
    if bar and bar.displayMode ~= self:GetPhaseDisplay(key) then
        bar:Hide()
        self.bars[key] = nil
        bar = nil
    end
    if not bar then
        local _, _, ruleIdx = self:GetPhaseRuleByKey(key)
        local sortIdx = 50 + (ruleIdx or 1)
        bar = CreatePhaseBar(self, key, sortIdx)
        self.bars[key] = bar
        needLayout = true
        justAppeared = true
    elseif not bar:IsShown() then
        bar:Show()
        needLayout = true
        justAppeared = true
    end

    local baseLabel = self:GetPhaseEffectiveLabel(key)
    if bar.displayMode == "bar" then
        if bar.label and bar.label:GetText() ~= baseLabel then
            bar.label:SetText(baseLabel)
        end
        -- Text: AbbreviateNumbers takes secret + returns secret string;
        -- secret-string concat with a literal "%" is safe (per memory).
        if bar.timerText and AbbreviateNumbers then
            bar.timerText:SetText(AbbreviateNumbers(secretValue) .. "%")
        end
        -- Bar fill: SetValue is AllowedWhenTainted; passing a secret directly.
        if bar.bar and lead and lead > 0 then
            bar.bar:SetMinMaxValues(0, lead)
            bar.bar:SetValue(secretValue)
        end
    else
        if bar.label and AbbreviateNumbers then
            bar.label:SetText(baseLabel .. " " .. AbbreviateNumbers(secretValue) .. "%")
        end
    end

    -- Three nested alphas; all AllowedWhenTainted:
    --   frame    — fades the whole bar (union of countdown + transitioned bands)
    --   bar.bar  — fades just the countdown elements (label/timerText/fill)
    --   transitionText — fades the "Phase Transitioned" overlay independently
    -- transitionText is parented to `frame` (not bar.bar) so its alpha is NOT
    -- multiplied by bar.bar's alpha, letting it remain visible when bar.bar=0.
    bar:SetAlpha(secretFrameAlpha)
    if bar.bar then bar.bar:SetAlpha(secretCountdown) end
    if bar.transitionText then bar.transitionText:SetAlpha(secretTransitioned) end

    if needLayout then self:LayoutBars() end
    if justAppeared then PlayPhaseSound(key, "show") end
end

function DT:_HidePhaseBar(key)
    local bar = self.bars[key]
    if not bar or not bar:IsShown() then return end
    -- Keep the frame in self.bars across tick toggles so we don't churn frame creation
    -- when a boss bobs in and out of the lead window. Full teardown happens in StopPhaseTracking.
    bar:Hide()
    self:LayoutBars()
    PlayPhaseSound(key, "hide")
end

function DT:_HideAllPhaseBars()
    -- Preview bars belong to the editor, so encounter cleanup leaves them visible.
    local changed = false
    for key, bar in pairs(self.bars) do
        if bar.isPhaseBar and not bar.isPreview then
            bar:Hide()
            self.bars[key] = nil
            changed = true
        end
    end
    if changed then self:LayoutBars() end
end

-- Cache of phase curves keyed by "<threshold>:<lead>" so we build each curve
-- once per (threshold, lead) pair rather than every tick.
DT._phaseCurves = DT._phaseCurves or {}

-- 12.0 makes UnitHealth/UnitHealthMax return secret values for hostile units.
-- Blizzard's escape hatch is UnitHealthPercent(unit, true, curve): the curve
-- maps HP fraction (0..1) to an output value, and the curve evaluation runs
-- server-side. BUT the result is still SECRET-tagged on hostile units (the
-- base `SecretReturns = true` flag wins over `SecretWhenCurveSecret = true`;
-- confirmed via diagnostic).
--
-- That means we CANNOT extract a clean integer tier in addon code — `==` and
-- ordered comparisons against secret numbers throw whenever execution is
-- tainted (and our addon IS tainted by the time the ticker fires, from
-- earlier secret-value flows); such a comparison works only in a fresh,
-- untainted event handler.
--
-- Workaround: drive the bar visuals DIRECTLY from the secret HP curve output
-- via APIs flagged `AllowedWhenTainted`:
--   - StatusBar:SetValue(secret)  ← bar fill
--   - Region:SetAlpha(secret)     ← visibility (0/1 from a binary alpha curve)
--   - AbbreviateNumbers(secret) → secret string → FontString:SetText(secret str)
--
-- Step interpolation: curve(x) returns y of latest AddPoint(x', y) with
-- x' <= x. For threshold=75, lead=5 we map HP fractions to remaining tiers:
--    HP (0..0.75001]   → 0  (already phased, hide)
--    HP (0.75001..0.76001] → 1
--    HP (0.76001..0.77001] → 2
--    ...
--    HP (0.79001..0.80001] → 5  (just entered window)
--    HP (0.80001..1]   → 0  (above window, hide)
-- The alpha curve mirrors this with 0/1: 0 outside [threshold, threshold+lead],
-- 1 inside.

local function BuildPhaseValueCurve(threshold, lead)
    if not (UnitHealthPercent and C_CurveUtil and Enum and Enum.LuaCurveType) then return nil end
    if lead <= 0 then return nil end
    local curve = C_CurveUtil.CreateCurve()
    if not curve then return nil end
    curve:SetType(Enum.LuaCurveType.Step)

    local epsilon = 0.00001
    curve:AddPoint(0, 0)
    for tick = 1, lead do
        local hp = (threshold + tick - 1) / 100 + epsilon
        if hp > 1 then break end
        curve:AddPoint(hp, tick)
    end
    local top = (threshold + lead) / 100 + epsilon
    if top <= 1 then
        curve:AddPoint(top, 0)
    end
    return curve
end

-- Countdown alpha: 1 in (threshold, threshold+lead], 0 elsewhere.
-- Drives bar.bar (StatusBar containing fill + label + timerText).
local function BuildPhaseCountdownAlphaCurve(threshold, lead)
    if not (UnitHealthPercent and C_CurveUtil and Enum and Enum.LuaCurveType) then return nil end
    if lead <= 0 then return nil end
    local curve = C_CurveUtil.CreateCurve()
    if not curve then return nil end
    curve:SetType(Enum.LuaCurveType.Step)

    local epsilon = 0.00001
    curve:AddPoint(0, 0)
    curve:AddPoint(threshold / 100 + epsilon, 1)
    local top = (threshold + lead) / 100 + epsilon
    if top <= 1 then
        curve:AddPoint(top, 0)
    end
    return curve
end

-- Transitioned alpha: 1 in (threshold - PHASE_TRANSITIONED_BAND, threshold], 0 elsewhere.
-- Drives the "Phase Transitioned" overlay text. Narrow 1% band → brief flash
-- (~1-3s of M+ DPS), not lead-wide which lingered too long.
local function BuildPhaseTransitionedAlphaCurve(threshold, lead)
    if not (UnitHealthPercent and C_CurveUtil and Enum and Enum.LuaCurveType) then return nil end
    if lead <= 0 then return nil end
    local curve = C_CurveUtil.CreateCurve()
    if not curve then return nil end
    curve:SetType(Enum.LuaCurveType.Step)

    local epsilon = 0.00001
    local low = math.max(0, threshold - PHASE_TRANSITIONED_BAND) / 100 + epsilon
    curve:AddPoint(0, 0)
    curve:AddPoint(low, 1)
    curve:AddPoint(threshold / 100 + epsilon, 0)
    return curve
end

-- Frame alpha (union): 1 in (threshold - PHASE_TRANSITIONED_BAND, threshold+lead], 0 elsewhere.
-- Drives the outer phase bar frame so the layout slot itself fades during the
-- combined countdown + transitioned-flash bands.
local function BuildPhaseFrameAlphaCurve(threshold, lead)
    if not (UnitHealthPercent and C_CurveUtil and Enum and Enum.LuaCurveType) then return nil end
    if lead <= 0 then return nil end
    local curve = C_CurveUtil.CreateCurve()
    if not curve then return nil end
    curve:SetType(Enum.LuaCurveType.Step)

    local epsilon = 0.00001
    local low = math.max(0, threshold - PHASE_TRANSITIONED_BAND) / 100 + epsilon
    curve:AddPoint(0, 0)
    curve:AddPoint(low, 1)
    local top = (threshold + lead) / 100 + epsilon
    if top <= 1 then
        curve:AddPoint(top, 0)
    end
    return curve
end

function DT:_GetPhaseCurves(threshold, lead)
    local key = tostring(threshold) .. ":" .. tostring(lead)
    local cached = self._phaseCurves[key]
    if cached then return cached.value, cached.countdown, cached.transitioned, cached.frame end
    local valueCurve        = BuildPhaseValueCurve(threshold, lead)
    local countdownCurve    = BuildPhaseCountdownAlphaCurve(threshold, lead)
    local transitionedCurve = BuildPhaseTransitionedAlphaCurve(threshold, lead)
    local frameCurve        = BuildPhaseFrameAlphaCurve(threshold, lead)
    if valueCurve and countdownCurve and transitionedCurve and frameCurve then
        self._phaseCurves[key] = {
            value        = valueCurve,
            countdown    = countdownCurve,
            transitioned = transitionedCurve,
            frame        = frameCurve,
        }
        dprint(string_format("PhaseCurves built: threshold=%d lead=%d", threshold, lead))
    else
        dprint(string_format("PhaseCurves BUILD FAILED: threshold=%d lead=%d UHP=%s C_CurveUtil=%s",
            threshold, lead,
            tostring(UnitHealthPercent ~= nil),
            tostring(C_CurveUtil ~= nil)))
    end
    return valueCurve, countdownCurve, transitionedCurve, frameCurve
end

-- A rule with endsAtStage hides once the encounter's own stage reaches it;
-- one with endsOnShield once the shield has swapped to its unit.
function DT._PhaseRuleEnded(rule, stage, swap)
    local endsAt = rule.endsAtStage
    if type(endsAt) == "number" and type(stage) == "number" and stage >= endsAt then return true end
    return Swap.RuleEnded(rule, swap)
end

function DT:RefreshPhaseBars()
    local encounterID = self.activeEncounterID
    if not encounterID then return end
    local phases = self:GetEncounterPhases(encounterID)
    if not phases then return end

    for i, rule in ipairs(phases) do
        local key = self:MakePhaseRuleKey(encounterID, i)
        if not key then break end
        local unit = rule.unit or "boss1"
        local threshold = tonumber(rule.threshold) or 0
        local lead = self:GetPhaseEffectiveLead(key)
        local disabled = self:IsPhaseDisabled(key) or DT._PhaseRuleEnded(rule, self._encounterStage, self._shieldSwap)

        if disabled or not UnitExists(unit) or UnitIsDead(unit) or lead <= 0 then
            self:_HidePhaseBar(key)
        else
            local valueCurve, countdownCurve, transitionedCurve, frameCurve =
                self:_GetPhaseCurves(threshold, lead)
            if valueCurve and countdownCurve and transitionedCurve and frameCurve and UnitHealthPercent then
                -- ---@type number — number-output curves return a number per LuaCurveEvaluatedResult;
                -- the stub's union (number | colorRGBA) is just because the stub doesn't track curve type.
                ---@type number
                local secretValue        = UnitHealthPercent(unit, true, valueCurve)
                ---@type number
                local secretCountdown    = UnitHealthPercent(unit, true, countdownCurve)
                ---@type number
                local secretTransitioned = UnitHealthPercent(unit, true, transitionedCurve)
                ---@type number
                local secretFrameAlpha   = UnitHealthPercent(unit, true, frameCurve)
                self:_ShowPhaseBar(key, secretValue, secretCountdown, secretTransitioned, secretFrameAlpha, lead)
            end
        end
    end
end

function DT:StartPhaseTracking(encounterID)
    self:StopPhaseTracking()
    if not encounterID then return end
    local phases = self:GetEncounterPhases(encounterID)
    if not phases or #phases == 0 then return end
    self.activeEncounterID = encounterID
    dprint(string_format("StartPhaseTracking encounterID=%d rules=%d", encounterID, #phases))
    self:RefreshPhaseBars()
    self.phaseTicker = C_Timer.NewTicker(PHASE_TICK_SECONDS, function()
        DT:RefreshPhaseBars()
    end)
end

function DT:StopPhaseTracking()
    if self.phaseTicker then
        self.phaseTicker:Cancel()
        self.phaseTicker = nil
    end
    if self.activeEncounterID then
        dprint("StopPhaseTracking encounterID=" .. tostring(self.activeEncounterID))
    end
    self.activeEncounterID = nil
    -- Runs at every encounter start and end and on disable, so a stage never
    -- outlives its encounter.
    self._encounterStage = nil
    self._shieldSwap = nil
    self:_ShieldWarningStop()
    self:_HideAllPhaseBars()
end

-- ╔══════════════════════════════════════════════════════════╗
-- ║  Shield bars (boss absorb tracker)                       ║
-- ║  Spawns a remaining / total (percent) bar on a boss's    ║
-- ║  channel start inside a shield parent's window. Used     ║
-- ║  for boss intermission shields (e.g. Vordaza's Necrotic  ║
-- ║  Convergence) where the team's progress through the      ║
-- ║  shield is the relevant cue. Reads the secret-value      ║
-- ║  UnitGetTotalAbsorbs token and passes it directly to     ║
-- ║  SetValue + AbbreviateNumbers (allowed-when-tainted).    ║
-- ║  Per-shield-bar state lives on the frame itself          ║
-- ║  (its shield* fields). Refresh timers                    ║
-- ║  keyed by spellID in DT._shieldRefreshTimers.            ║
-- ╚══════════════════════════════════════════════════════════╝

DT._shieldRefreshTimers = DT._shieldRefreshTimers or {}
DT._absorbEventRegistered = false
-- Plain-number parent spell IDs with a shield binding in the active encounter,
-- built at ENCOUNTER_START.
DT._activeShieldSpellIds = DT._activeShieldSpellIds or {}
-- Per parent: true while its watch's channel window is open. CHANNEL_START's
-- spell ID is secret on a hostile unit, so timing, not the spell, identifies
-- the parent.
DT._shieldArming = DT._shieldArming or {}
-- Pre-channel watches keyed by parent spell ID (one shield per parent) and by
-- owner + exact label for Pause/Resume and StopBar correlation.
DT._shieldWatches = DT._shieldWatches or {}
DT._shieldWatchByLabel = DT._shieldWatchByLabel or {}
-- Cleanup cap per shown shield, from its binding's timeout.
DT._shieldFallbackTimers = DT._shieldFallbackTimers or {}
-- One frame kit per parent, reused for the session.
DT._shieldKits = DT._shieldKits or {}

-- How long an explicit parent's Finished opens its channel window.
local SHIELD_FINISH_WINDOW = 2

-- castBarID is documented as never secret; anything else counts as absent.
local function PlainCastBarId(value)
    if issecretvalue and issecretvalue(value) then return nil end
    if not State.IsCastBarId(value) then return nil end
    return value
end

function DT:_ShowShieldBar(spellId, unit, castBarId, owner)
    if not (spellId and unit and owner) then return end
    local cfg = self:GetSpellShieldBar(spellId)
    if not cfg then return end
    if self:IsSpellDisabled(spellId) then return end
    if not self:ShouldShowSpellRole(spellId) then return end
    local generation, reason = State.NextSlot(self._state, owner, "shield", spellId)
    if not generation then
        dprint("shield refused: " .. tostring(reason))
        return
    end

    local key = ShieldBarKey(spellId)
    local bar = self._shieldKits[spellId]
    -- CreateBar gives the shield the regular bar's font, texture and icon;
    -- baseDuration=1 is a throwaway, the range is overwritten below.
    if not bar then
        bar = self:CreateBar(key, 1, 0, "bar", cfg.displayText or "SHIELD", spellId)
        bar:SetScript("OnUpdate", nil)
        -- SetValue with the secret absorb value secret-poisons this StatusBar's
        -- getters, so a plain countdown must never recycle the kit: ReleaseBar
        -- gives it hide-only teardown and this parent reuses it.
        bar._dtPoolKey = nil
        bar.isShieldBar = true
        bar.shieldSpellId = spellId
        if bar.icon then
            bar.icon:SetTexture(self:ResolveSpellIcon(spellId) or 134400)
        end
        self._shieldKits[spellId] = bar
    end
    if self.bars[key] ~= bar then
        ApplyVisualsToBar(bar)
        self._barSortCounter = self._barSortCounter + 1
        bar.sortIndex = self._barSortCounter
        self.bars[key] = bar
    end

    bar.shieldUnit = unit
    bar.shieldCastBarId = castBarId
    bar.shieldOwner = owner
    bar.shieldGeneration = generation
    -- Recomputed per activation so a keystone level change takes effect.
    bar.shieldMax = cfg.baseAmount * GetShieldLevelMultiplier()
    bar.bar:SetMinMaxValues(0, bar.shieldMax)
    bar.bar:SetValue(bar.shieldMax)
    bar._lastValue = nil
    bar.shieldTotalText = FormatShieldTotal(bar.shieldMax)
    bar.shieldPercentOptions = NewShieldPercentOptions(bar.shieldMax)
    if bar.timerText then
        WriteShieldText(bar.timerText, bar.shieldMax, bar.shieldTotalText, bar.shieldPercentOptions)
    end
    bar:Show()
    -- No sound: the parent's countdown already announced this mechanic.
    self:LayoutBars()

    local pending = self._shieldRefreshTimers[spellId]
    if pending then
        self:CancelTimer(pending)
        self._shieldRefreshTimers[spellId] = nil
    end
    local fallback = self._shieldFallbackTimers[spellId]
    if fallback then self:CancelTimer(fallback) end
    self._shieldFallbackTimers[spellId] = self:ScheduleTimer(function()
        self._shieldFallbackTimers[spellId] = nil
        if self:_IsShieldCurrent(spellId, owner, generation) then self:_HideShieldBar(spellId) end
    end, cfg.timeout)
    self:_RefreshShieldBar(spellId)
end

function DT:_HideShieldBar(spellId)
    if not spellId then return end
    local timer = self._shieldRefreshTimers[spellId]
    if timer then
        self:CancelTimer(timer)
        self._shieldRefreshTimers[spellId] = nil
    end
    local fallback = self._shieldFallbackTimers[spellId]
    if fallback then
        self:CancelTimer(fallback)
        self._shieldFallbackTimers[spellId] = nil
    end
    local key = ShieldBarKey(spellId)
    local bar = self.bars[key]
    if not bar then return end
    -- No PlayBarSound here — see _ShowShieldBar for rationale. Primary text/bar
    -- already plays the curated sound on its own hide/StopBar path.
    ReleaseBar(bar)
    self.bars[key] = nil
    self:LayoutBars()
end

function DT:_RefreshShieldBar(spellId)
    if not spellId then return end
    local bar = self.bars[ShieldBarKey(spellId)]
    if not (bar and bar:IsShown()) then return end

    -- Only the unit that channeled the shield; while it is missing the bar
    -- waits for an end signal instead of moving to another boss.
    local unit = bar.shieldUnit
    if not (unit and UnitExists(unit)) then return end

    local absorbAmount = UnitGetTotalAbsorbs(unit)
    if absorbAmount == nil then return end

    -- Direct SetValue: GatedSetValue's cached delta check compares values,
    -- which a secret value refuses.
    bar.bar:SetValue(absorbAmount)
    if bar.timerText then
        WriteShieldText(bar.timerText, absorbAmount, bar.shieldTotalText, bar.shieldPercentOptions)
    end
end

function DT:_ScheduleShieldRefresh(spellId)
    if not spellId then return end
    if self._shieldRefreshTimers[spellId] then return end
    local bar = self.bars[ShieldBarKey(spellId)]
    if not bar then return end
    local owner, generation = bar.shieldOwner, bar.shieldGeneration
    self._shieldRefreshTimers[spellId] = self:ScheduleTimer(function()
        self._shieldRefreshTimers[spellId] = nil
        if self:_IsShieldCurrent(spellId, owner, generation) then self:_RefreshShieldBar(spellId) end
    end, SHIELD_REFRESH_THROTTLE)
end

-- The shown bar is still this activation and its owner's scope is live, so a
-- hide, a re-activation, owner retirement or an epoch bump drops queued work.
function DT:_IsShieldCurrent(spellId, owner, generation)
    local bar = self.bars[ShieldBarKey(spellId)]
    if not (bar and bar.shieldOwner == owner and bar.shieldGeneration == generation) then return false end
    return State.IsSlotCurrent(self._state, owner, "shield", spellId, generation)
end

function DT:_HideAllShieldBars()
    for spellId in pairs(self._shieldRefreshTimers) do
        local timer = self._shieldRefreshTimers[spellId]
        if timer then self:CancelTimer(timer) end
        self._shieldRefreshTimers[spellId] = nil
    end
    for spellId in pairs(self._shieldFallbackTimers) do
        local timer = self._shieldFallbackTimers[spellId]
        if timer then self:CancelTimer(timer) end
        self._shieldFallbackTimers[spellId] = nil
    end
    for spellId in pairs(self._shieldArming) do
        self._shieldArming[spellId] = false
    end
    for _, watch in pairs(self._shieldWatches) do
        CancelJob(self, watch.armJob)
        CancelJob(self, watch.disarmJob)
    end
    self._shieldWatches = {}
    self._shieldWatchByLabel = {}
    local changed = false
    for k, bar in pairs(self.bars) do
        if bar.isShieldBar then
            ReleaseBar(bar)
            self.bars[k] = nil
            changed = true
        end
    end
    if changed then self:LayoutBars() end
end

-- Hides only the shield bars/watches owned by `owner` — StopBars/OnBossDisable
-- from one boss module must not clear another owner's live channel-observed
-- shield bar.
function DT:_HideOwnerShieldBars(owner)
    for _, bar in pairs(self.bars) do
        if bar.isShieldBar and bar.shieldOwner == owner then
            self:_HideShieldBar(bar.shieldSpellId)
        end
    end
    local watchesByLabel = self._shieldWatchByLabel[owner]
    if watchesByLabel then
        for _, watch in pairs(watchesByLabel) do
            self:_CloseShieldWatch(watch)
        end
        self._shieldWatchByLabel[owner] = nil
    end
end

-- The arming flag is cleared only while this watch still owns its parent, so
-- closing a replaced watch cannot disarm its successor.
function DT:_CloseShieldWatch(watch)
    CancelJob(self, watch.armJob)
    CancelJob(self, watch.disarmJob)
    if self._shieldWatches[watch.spellId] == watch then
        self._shieldWatches[watch.spellId] = nil
        self._shieldArming[watch.spellId] = false
    end
    local byLabel = self._shieldWatchByLabel[watch.owner]
    if byLabel and byLabel[watch.label] == watch then byLabel[watch.label] = nil end
end

-- Called before anything that can retire the new instance, so its release
-- finds the link.
function DT:_LinkShieldWatch(owner, label, spellId, inst)
    local watch = self._shieldWatches[spellId]
    if watch and watch.owner == owner and watch.label == label then
        watch.instance = inst
    end
end

-- Only the watch linked to this very instance, so releasing a replaced
-- predecessor leaves its successor's watch alone.
function DT:_ReleaseShieldWatchOf(inst)
    local byLabel = self._shieldWatchByLabel[inst.owner]
    local watch = byLabel and byLabel[inst.label]
    if not (watch and watch.instance == inst) then return end
    local finished = watch.opened == true or inst.anchorElapsed ~= nil
    if State.ShieldWatchOnRetire(watch.explicit, finished) == "close" then
        self:_CloseShieldWatch(watch)
    end
end

function DT:OnUnitAbsorbAmountChanged(_, unit)
    if not AcceptBossUnit(unit) then return end
    for i = 1, #self._activeShieldSpellIds do
        local spellId = self._activeShieldSpellIds[i]
        local bar = self.bars[ShieldBarKey(spellId)]
        if bar and bar:IsShown() and State.ShieldUnitMatches(bar.shieldUnit, nil, unit, nil) then
            self:_ScheduleShieldRefresh(spellId)
        end
    end
end

-- An explicit watch keeps its record past disarm, so its parent's late
-- Finished can re-open the window.
function DT:_ArmShieldChannelWatch(owner, label, spellId, remaining, span, now, explicit)
    local generation, reason = State.NextSlot(self._state, owner, "shieldWatch", spellId)
    if not generation then
        dprint("shield watch refused: " .. tostring(reason))
        return
    end

    local previous = self._shieldWatches[spellId]
    if previous then self:_CloseShieldWatch(previous) end

    local clock = State.NewClock(remaining, span, now)
    if not clock then return end
    local armAt = math.max(remaining - 1, 0)
    local watch = {
        owner = owner, spellId = spellId, label = label, generation = generation,
        clock = clock, armAt = armAt, disarmAt = armAt + 5, explicit = explicit == true,
    }

    local armJob = {
        owner = owner, kind = "shieldWatch", slotKey = spellId, generation = generation,
        clockPolicy = "elapsed", deadline = armAt, clock = clock,
    }
    armJob.action = function()
        watch.armJob = nil
        self._shieldArming[spellId] = true
        local disarmJob = {
            owner = owner, kind = "shieldWatch", slotKey = spellId, generation = generation,
            clockPolicy = "elapsed", deadline = watch.disarmAt, clock = clock,
        }
        disarmJob.action = function()
            watch.disarmJob = nil
            if watch.explicit then
                self._shieldArming[spellId] = false
            else
                self:_CloseShieldWatch(watch)
            end
        end
        watch.disarmJob = ScheduleJob(self, disarmJob, GetTime())
    end
    watch.armJob = ScheduleJob(self, armJob, now)

    self._shieldWatches[spellId] = watch
    self._shieldWatchByLabel[owner] = self._shieldWatchByLabel[owner] or {}
    self._shieldWatchByLabel[owner][label] = watch
end

-- outcome is nil when the stop found no published occurrence.
function DT:_ResolveShieldWatchOnStop(owner, label, outcome, now)
    local byLabel = self._shieldWatchByLabel[owner]
    local watch = byLabel and byLabel[label]
    if not watch then return end
    local action = State.ResolveShieldWatch(watch.explicit, outcome, watch.opened == true)
    if action == "close" then
        self:_CloseShieldWatch(watch)
    elseif action == "open" then
        CancelJob(self, watch.armJob)
        CancelJob(self, watch.disarmJob)
        watch.armJob = nil
        watch.armingHeld = nil
        watch.opened = true
        self._shieldArming[watch.spellId] = true
        local disarmJob = {
            owner = owner, kind = "shieldWatch", slotKey = watch.spellId, generation = watch.generation,
            clockPolicy = "wall", deadline = now + SHIELD_FINISH_WINDOW,
        }
        disarmJob.action = function()
            watch.disarmJob = nil
            self:_CloseShieldWatch(watch)
        end
        watch.disarmJob = ScheduleJob(self, disarmJob, now)
    end
end

-- Single CHANNEL_START handler: the shield spawn first, then the DEBUG_DT2
-- observation. The guard runs once for both.
function DT:OnUnitChannelStart(_, unit, _, _, castBarId)
    if not AcceptBossUnit(unit) then return end
    self:_ShieldChannelStart(unit, PlainCastBarId(castBarId))
    self:_ObserveCastStart("channel", unit, GetTime())
end

-- The window is consumed before the show, so a repeated start cannot spawn a
-- second bar.
function DT:_ShieldChannelStart(unit, castBarId)
    for i = 1, #self._activeShieldSpellIds do
        local spellId = self._activeShieldSpellIds[i]
        if self._shieldArming[spellId] then
            local watch = self._shieldWatches[spellId]
            self._shieldArming[spellId] = false
            if watch then
                self:_CloseShieldWatch(watch)
                self:_ShowShieldBar(spellId, unit, castBarId, watch.owner)
            end
            return
        end
    end
end

function DT:OnUnitChannelStop(_, unit, _, _, _, castBarId)
    if not AcceptBossUnit(unit) then return end
    self:_HideShieldsOnUnit(unit, PlainCastBarId(castBarId))
end

-- A boss's channel turns interruptible once its shield is consumed.
function DT:OnUnitSpellcastInterruptible(_, unit)
    if not AcceptBossUnit(unit) then return end
    self:_HideShieldsOnUnit(unit, nil)
end

function DT:_HideShieldsOnUnit(unit, castBarId)
    for i = 1, #self._activeShieldSpellIds do
        local spellId = self._activeShieldSpellIds[i]
        local bar = self.bars[ShieldBarKey(spellId)]
        if bar and bar:IsShown()
            and State.ShieldUnitMatches(bar.shieldUnit, bar.shieldCastBarId, unit, castBarId) then
            self:_HideShieldBar(spellId)
        end
    end
end

-- Parent spell IDs with a shield binding in the encounter, legacy or explicit.
function DT:_CollectShieldSpellIds(encounterID)
    local out = {}
    local byParent = encounterID and self._bindings and self._bindings.shields[encounterID]
    if not byParent then return out end
    for parentId in pairs(byParent) do out[#out + 1] = parentId end
    return out
end

function DT:_RegisterAbsorbEvent()
    if self._absorbEventRegistered then return end
    self:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED", "OnUnitAbsorbAmountChanged")
    self:_AcquireUnitCastEvent("UNIT_SPELLCAST_CHANNEL_START", "shield")
    self:_AcquireUnitCastEvent("UNIT_SPELLCAST_CHANNEL_STOP", "shield")
    self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTIBLE", "OnUnitSpellcastInterruptible")
    self._absorbEventRegistered = true
    dprint("ShieldBar events registered (absorb + channel start/stop + interruptible)")
end

function DT:_UnregisterAbsorbEvent()
    if not self._absorbEventRegistered then return end
    self:UnregisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
    self:_ReleaseUnitCastEvent("UNIT_SPELLCAST_CHANNEL_START", "shield")
    self:_ReleaseUnitCastEvent("UNIT_SPELLCAST_CHANNEL_STOP", "shield")
    self:UnregisterEvent("UNIT_SPELLCAST_INTERRUPTIBLE")
    self._absorbEventRegistered = false
    dprint("ShieldBar events unregistered")
end

-- Feature set per unit-cast event; the slot is registered while any feature
-- holds it, so one feature's close never drops another's handler.
function DT:_AcquireUnitCastEvent(event, feature)
    local holders = self._unitCastHolders[event]
    if holders[feature] then return end
    if next(holders) == nil then
        self:RegisterEvent(event, UNIT_CAST_HANDLERS[event])
    end
    holders[feature] = true
end

function DT:_ReleaseUnitCastEvent(event, feature)
    local holders = self._unitCastHolders[event]
    if not holders[feature] then return end
    holders[feature] = nil
    if next(holders) == nil then
        self:UnregisterEvent(event)
    end
end

function DT:_ReleaseAllUnitCastEvents()
    for event, holders in pairs(self._unitCastHolders) do
        if next(holders) ~= nil then
            self._unitCastHolders[event] = {}
            self:UnregisterEvent(event)
        end
    end
end

-- Observe after confirmation so diagnostics include the confirmed state.
function DT:OnUnitCastStart(_, unit, _castGUID, spellID, castBarID)
    if not AcceptBossUnit(unit) then return end
    local now = GetTime()
    local confirmedInst = self:_ConfirmCastStart(unit, now)
    self:_MatchCastStart(unit, spellID, castBarID, now)
    self:_ObserveCastStart("cast", unit, now, confirmedInst)
end

-- castConfirm rows only: a 1.5 s wall window after the Finished anchor in
-- which the first boss cast start re-bases the origin, once. The watch ends
-- on the confirm or at the window end; the window-end job is an owned wall
-- job the instance's retirement drops.
function DT:_ArmCastConfirm(inst, now)
    if inst.binding.castConfirm ~= "boss-cast-start" then return end
    if self._castWatches[inst] then return end
    local watch = { inst = inst, generation = inst.generation, windowEnd = now + CONFIRM_WINDOW }
    local job = {
        owner = inst.owner, scope = inst.scope, kind = "castWatch",
        instance = inst, instanceGeneration = inst.generation,
        clockPolicy = "wall", deadline = watch.windowEnd,
    }
    job.action = function() self:_CloseCastWatch(inst, "window") end
    watch.job = job
    self._castWatches[inst] = watch
    self:_AcquireUnitCastEvent("UNIT_SPELLCAST_START", "watch")
    ScheduleJob(self, job, now)
end

function DT:_CloseCastWatch(inst, reason)
    local watch = self._castWatches[inst]
    if not watch then return end
    self._castWatches[inst] = nil
    CancelJob(self, watch.job)
    if reason == "window" then
        dprint("confirm ignored reason=window text=" .. tostring(inst.label))
    end
    if next(self._castWatches) == nil then
        self:_ReleaseUnitCastEvent("UNIT_SPELLCAST_START", "watch")
    end
end

-- Stale and overdue entries close before anything is counted: the window
-- job is a wall timer that runs on a later frame, so a start delivered in
-- between must neither confirm nor make two watches ambiguous. Two armed
-- in-window watches refuse both; only Slam opts in, so that is unreachable
-- with the 3207 rows and is what keeps the matcher bounded.
function DT:_ConfirmCastStart(unit, now)
    for inst, watch in pairs(self._castWatches) do
        if not State.IsCurrent(self._state, inst, watch.generation, inst.moduleEpoch, inst.encounterEpoch) then
            self:_CloseCastWatch(inst, "retired")
        elseif now > watch.windowEnd then
            self:_CloseCastWatch(inst, "window")
        end
    end
    local armed, armedCount = nil, 0
    for _, watch in pairs(self._castWatches) do
        armedCount = armedCount + 1
        armed = watch
    end
    if armedCount == 0 then return end
    if armedCount > 1 then
        dprint("confirm ignored reason=ambiguous unit=" .. unit)
        return
    end
    local inst = armed.inst
    local total, reason = State.Confirm(inst, now)
    if not total then
        dprint(string_format("confirm ignored reason=%s text=%s", tostring(reason), tostring(inst.label)))
        return
    end
    dprint(string_format("confirm text=%s unit=%s confirmElapsed=%.3f total=%.3f",
        tostring(inst.label), unit, inst.anchorElapsed, total))
    self:_OnInstanceAnchored(inst, total, now)
    self:_CloseCastWatch(inst, "confirmed")
    return inst
end

-- DEBUG_DT2 only, logging only: 3.0 wall seconds of boss cast and channel
-- starts after any Finished anchor. Kept open through a confirm so
-- competing and late starts are recorded; closure logs what was seen and why
-- it closed. Arrivals outside every window are not observed.
function DT:_OpenObservationWindow(inst, now)
    if self._observeWindows[inst] then return end
    local window = { inst = inst, openedAt = now, count = 0 }
    local job = {
        owner = inst.owner, scope = inst.scope, kind = "observe",
        instance = inst, instanceGeneration = inst.generation,
        clockPolicy = "wall", deadline = now + OBSERVE_WINDOW,
    }
    job.action = function() self:_CloseObservationWindow(inst, "timer") end
    window.job = job
    self._observeWindows[inst] = window
    self:_AcquireUnitCastEvent("UNIT_SPELLCAST_START", "observe")
    self:_AcquireUnitCastEvent("UNIT_SPELLCAST_CHANNEL_START", "observe")
    ScheduleJob(self, job, now)
end

function DT:_CloseObservationWindow(inst, reason)
    local window = self._observeWindows[inst]
    if not window then return end
    self._observeWindows[inst] = nil
    CancelJob(self, window.job)
    if window.count == 0 then
        local observed = GetTime() - window.openedAt
        if observed > OBSERVE_WINDOW then observed = OBSERVE_WINDOW end
        dprint(string_format("castStart none label=%s observed=%.3f closed=%s",
            tostring(inst.label), observed, tostring(reason)))
    end
    if next(self._observeWindows) == nil then
        self:_ReleaseUnitCastEvent("UNIT_SPELLCAST_START", "observe")
        self:_ReleaseUnitCastEvent("UNIT_SPELLCAST_CHANNEL_START", "observe")
    end
end

-- An arrival after the deadline closes the window instead of counting: the
-- window job is a wall timer that may run a frame later.
-- confirmedInst is the instance this same arrival just confirmed, so the
-- arrival is not also reported as a second start.
function DT:_ObserveCastStart(kind, unit, now, confirmedInst)
    for inst, window in pairs(self._observeWindows) do
        if now > window.openedAt + OBSERVE_WINDOW then
            self:_CloseObservationWindow(inst, "timer")
        else
            window.count = window.count + 1
            local watchState = "none"
            if self._castWatches[inst] then
                watchState = "armed"
            elseif inst.confirmed then
                watchState = "confirmed"
            end
            dprint(string_format("castStart kind=%s unit=%s at=%.3f sinceAnchor=%.3f label=%s watch=%s",
                kind, unit, now, now - window.openedAt, tostring(inst.label), watchState))
            if kind == "cast" and watchState == "confirmed" and inst ~= confirmedInst then
                dprint(string_format("confirm ignored reason=second text=%s unit=%s", tostring(inst.label), unit))
            end
        end
    end
end

local function ReadCastSnapshot(unit)
    if not UnitCastingInfo then return nil end
    local ok, name, _, _, startMs, endMs, _, _, _, spellId, castBarId = pcall(UnitCastingInfo, unit)
    if not ok then return nil end
    if issecretvalue and (issecretvalue(name) or issecretvalue(spellId)
        or issecretvalue(startMs) or issecretvalue(endMs)) then
        return nil
    end
    if name == nil then return nil end
    return spellId, PlainCastBarId(castBarId), startMs, endMs
end

function DT:_WatchCastMatch(inst)
    self._castMatches[inst] = inst.generation
    self:_AcquireUnitCastEvent("UNIT_SPELLCAST_START", "castMatch")
end

function DT:_CloseCastMatch(inst)
    local matches = self._castMatches
    if not (matches and matches[inst]) then return end
    matches[inst] = nil
    if next(matches) == nil then
        self:_ReleaseUnitCastEvent("UNIT_SPELLCAST_START", "castMatch")
    end
end

function DT:_CastMatchCandidates()
    local list = {}
    for inst, generation in pairs(self._castMatches) do
        if State.IsCurrent(self._state, inst, generation, inst.moduleEpoch, inst.encounterEpoch) then
            list[#list + 1] = inst
        else
            self:_CloseCastMatch(inst)
        end
    end
    return list
end

-- A nil startSpell takes the unit's running cast as its own START. Returns
-- the cast start and end, or nil, nil and the refusal reason.
function DT:_CastEvidence(unit, spells, startSpell, startBar, now)
    local spellId, castBarId, startMs, endMs = ReadCastSnapshot(unit)
    if startSpell == nil then startSpell, startBar = spellId, castBarId end
    local castStart, castEnd = State.CastTimesFromEvidence(spells, startSpell, startBar,
        spellId, castBarId, startMs, endMs, now)
    if not castStart then return nil, nil, castEnd, startSpell, startBar end
    return castStart, castEnd, nil, startSpell, startBar
end

local FOLLOW_EVENTS = {
    "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET",
}

function DT:_FollowCast(inst, unit, castBarId, spellId)
    self._castFollows[inst] = { unit = unit, bar = castBarId, spell = spellId, generation = inst.generation }
    for i = 1, #FOLLOW_EVENTS do self:_AcquireUnitCastEvent(FOLLOW_EVENTS[i], "castFollow") end
end

function DT:_CloseCastFollow(inst)
    local follows = self._castFollows
    if not (follows and follows[inst]) then return end
    follows[inst] = nil
    if next(follows) == nil then
        for i = 1, #FOLLOW_EVENTS do self:_ReleaseUnitCastEvent(FOLLOW_EVENTS[i], "castFollow") end
    end
end

-- An early end of a followed cast, bound by its token and public cast bar
-- only, ends its countdown without a completion claim. A completing stop
-- reconciles the countdown with the cast's real end: only the user offset
-- still ahead remains, on wall time, so a paused clock resumes.
function DT:_OnFollowedCastEnded(unit, castBarID, kind)
    local follows = self._castFollows
    if not follows or next(follows) == nil or not AcceptBossUnit(unit) then return end
    local bar = PlainCastBarId(castBarID)
    if bar == nil then return end
    local now = GetTime()
    for inst, follow in pairs(follows) do
        if not State.IsCurrent(self._state, inst, follow.generation, inst.moduleEpoch, inst.encounterEpoch) then
            self:_CloseCastFollow(inst)
        elseif follow.unit == unit and follow.bar == bar then
            self:_CloseCastFollow(inst)
            local outcome, reason = State.EndFollowedCast(inst, kind, now)
            dprint(string_format("cast follow %s text=%s outcome=%s", kind, tostring(inst.label),
                tostring(outcome or reason)))
            if outcome == "ended-early" then
                State.Retire(self._state, inst)
                self:ReleaseInstancePresentations(inst, true)
            elseif outcome == "completed" then
                local total, left, resumed = State.CompleteFollowedCast(inst, now)
                if resumed then self:_OnSourcePauseChanged(inst, false, now) end
                if total and left <= 0 then
                    State.Retire(self._state, inst)
                    self:ReleaseInstancePresentations(inst, true)
                elseif total then
                    self:_OnInstanceAnchored(inst, total, now)
                end
            end
        end
    end
end

function DT:OnUnitCastStop(_, unit, _castGUID, _spellID, castBarID)
    self:_OnFollowedCastEnded(unit, castBarID, "stopped")
end

-- One eligible occurrence takes one unused cast; any hold or wait ends. A
-- curated row runs its effective extension from the cast's start; a cast-end
-- row runs to the cast's end and follows it. No sound plays.
function DT:_ApplyCastMatch(unit, spellId, castBarId, castStart, castEnd, now)
    local inst, reason = State.SelectCastOccurrence(self:_CastMatchCandidates(), spellId, now, castStart)
    if not inst then
        dprint("cast match refused reason=" .. tostring(reason) .. " spell=" .. tostring(spellId))
        return nil, reason
    end
    if not State.TakeCastBar(self._state, inst.encounterId, castBarId) then
        dprint("cast match refused reason=used bar=" .. tostring(castBarId))
        return nil, "used"
    end
    local total, matchReason = State.MatchCast(inst, now, castStart, castEnd)
    if not total then
        dprint("cast match refused reason=" .. tostring(matchReason))
        return nil, matchReason
    end
    self:_CancelHold(inst)
    self:_OnInstanceAnchored(inst, total, now)
    self:_CloseCastMatch(inst)
    if inst.castExtension ~= nil then self:_FollowCast(inst, unit, castBarId, spellId) end
    dprint(string_format("cast match text=%s unit=%s spell=%s bar=%s start=%.3f end=%.3f total=%.3f",
        tostring(inst.label), unit, tostring(spellId), tostring(castBarId), castStart, castEnd, total))
    return inst
end

function DT:_MatchCastStart(unit, spellID, castBarID, now)
    local matches = self._castMatches
    if not matches or next(matches) == nil then return end
    if issecretvalue and issecretvalue(spellID) then return end
    local spells
    for inst in pairs(matches) do
        if inst.binding.castMatch.spells[spellID] then
            spells = inst.binding.castMatch.spells
            break
        end
    end
    if not spells then return end
    local startBar = PlainCastBarId(castBarID)
    local castStart, castEnd, reason = self:_CastEvidence(unit, spells, spellID, startBar, now)
    if not castStart then
        dprint("cast match refused reason=" .. tostring(reason) .. " unit=" .. unit)
        return
    end
    self:_ApplyCastMatch(unit, spellID, startBar, castStart, castEnd, now)
end

-- A refused refresh keeps the last readable end and the same cast's cancellation ownership.
function DT:OnUnitCastDelayed(_, unit, _castGUID, _spellID, castBarID)
    if not AcceptBossUnit(unit) then return end
    local bar = PlainCastBarId(castBarID)
    if bar == nil then return end
    local now = GetTime()
    for inst, follow in pairs(self._castFollows) do
        if not State.IsCurrent(self._state, inst, follow.generation, inst.moduleEpoch, inst.encounterEpoch) then
            self:_CloseCastFollow(inst)
        elseif follow.unit == unit and follow.bar == bar then
            local _, castEnd, reason = self:_CastEvidence(unit, { [follow.spell] = true }, follow.spell, bar, now)
            local total
            if castEnd then total, reason = State.FollowCastEnd(inst, now, castEnd) end
            if total then
                self:_OnInstanceAnchored(inst, total, now)
                dprint(string_format("cast follow text=%s bar=%s end=%.3f total=%.3f",
                    tostring(inst.label), tostring(bar), castEnd, total))
            else
                dprint("cast follow kept last end reason=" .. tostring(reason) .. " text=" .. tostring(inst.label))
            end
        end
    end
end

function DT:_ReadCastReadability(spells)
    local answers = {}
    local predicate = C_Secrets and C_Secrets.ShouldUnitSpellCastBeSecret
    if type(predicate) ~= "function" then return answers end
    for i = 1, #BOSS_UNITS do
        local unit = BOSS_UNITS[i]
        local exists = UnitExists(unit)
        if not (issecretvalue and issecretvalue(exists)) and exists == true then
            for spellId in pairs(spells) do
                local ok, secret = pcall(predicate, unit, spellId)
                local answer = "unknown"
                if ok and not (issecretvalue and issecretvalue(secret)) then
                    if secret == false then
                        answer = "readable"
                    elseif secret == true then
                        answer = "secret"
                    end
                end
                answers[#answers + 1] = { spellId = spellId, answer = answer }
            end
        end
    end
    return answers
end

-- Only an admissible, unused running cast can suppress the wait; ambiguity keeps the estimate.
function DT:_BeginCastWait(inst, now)
    local castMatch = inst.binding.castMatch
    if not (castMatch and castMatch.within) or not self._castMatches[inst] then return end
    local running, castUnit, castStart, castEnd, spellId, castBarId = 0, nil, nil, nil, nil, nil
    for i = 1, #BOSS_UNITS do
        local unit = BOSS_UNITS[i]
        local unitStart, unitEnd, _, unitSpell, unitBar = self:_CastEvidence(unit, castMatch.spells, nil, nil, now)
        if unitStart and State.AdmitsCastStart(inst, now, unitStart)
            and not State.IsCastBarUsed(self._state, inst.encounterId, unitBar) then
            running = running + 1
            castUnit, castStart, castEnd, spellId, castBarId = unit, unitStart, unitEnd, unitSpell, unitBar
        end
    end
    if running > 1 then
        dprint("cast wait refused reason=ambiguous-running text=" .. tostring(inst.label))
        return
    end
    local untaken = false
    if running == 1 then
        local matched, matchReason = self:_ApplyCastMatch(castUnit, spellId, castBarId, castStart, castEnd, now)
        if matched == inst then return end
        if matchReason == "ambiguous" then
            dprint("cast wait refused reason=ambiguous-occurrence text=" .. tostring(inst.label))
            return
        end
        untaken = matched == nil
    end
    local selected, reason = State.SelectWait(castMatch.spells, self:_ReadCastReadability(castMatch.spells))
    if not selected then
        dprint("cast wait refused reason=" .. tostring(reason) .. " text=" .. tostring(inst.label))
        return
    end
    local bound, waitReason = State.BeginCastWait(inst, now, untaken)
    if not bound then
        dprint("cast wait refused reason=" .. tostring(waitReason) .. " text=" .. tostring(inst.label))
        return
    end
    ArmHoldJob(self, inst, bound, now, function() self:_EndCastWait(inst, GetTime()) end)
    if inst.state == "retired" then return end
    -- The retire job never ends a longer estimate before the wait's job does.
    local total = inst.anchorElapsed + inst.binding.extension
    self:_OnInstanceAnchored(inst, total, now, math.max(total, bound))
    dprint(string_format("cast wait text=%s bound=%.3f", tostring(inst.label), bound))
end

-- An unmatched wait returns to a running estimate; past it, the occurrence
-- ends silently without claiming completion.
function DT:_EndCastWait(inst, now)
    self:_CancelHold(inst)
    local outcome = State.EndCastWait(inst, now)
    if not outcome then return end
    dprint(string_format("cast wait ended text=%s outcome=%s", tostring(inst.label), outcome))
    if outcome == "expired" then
        State.Retire(self._state, inst)
        self:ReleaseInstancePresentations(inst, true)
    else
        self:_OnInstanceAnchored(inst, inst.anchorElapsed + inst.binding.extension, now)
    end
end

function DT:_CloseAllCastWork(reason)
    for inst in pairs(self._castWatches) do self:_CloseCastWatch(inst, reason) end
    for inst in pairs(self._observeWindows) do self:_CloseObservationWindow(inst, reason) end
    for inst in pairs(self._castMatches) do self:_CloseCastMatch(inst) end
    for inst in pairs(self._castFollows) do self:_CloseCastFollow(inst) end
end

-- The fourth return bounds Finished admission for a zero-extension parent.
function DT:_ReadTimelineState(inst)
    if TIMELINE_STATE_FINISHED == nil or TIMELINE_STATE_CANCELED == nil then return nil, nil, "no-enum" end
    if not (C_EncounterTimeline and C_EncounterTimeline.GetEventState) then return nil, nil, "no-api" end
    local eventId, reasonOrQueue = State.ResolveTimelineEvent(self._state, inst)
    if not eventId then return nil, nil, reasonOrQueue end
    local state = C_EncounterTimeline.GetEventState(eventId)
    if issecretvalue and issecretvalue(state) then return nil, eventId, "secret-state" end
    if state == TIMELINE_STATE_FINISHED then return "finished", eventId, nil, reasonOrQueue end
    if state == TIMELINE_STATE_CANCELED then return "canceled", eventId end
    if TIMELINE_STATE_PAUSED ~= nil and state == TIMELINE_STATE_PAUSED then return "paused", eventId end
    if TIMELINE_STATE_ACTIVE ~= nil and state == TIMELINE_STATE_ACTIVE then return "active", eventId end
    return nil, eventId, "state=" .. tostring(state)
end

-- GetStage is plain module state, but the owner is a foreign table: refuse
-- anything secret or malformed rather than compare it.
function DT._ReadProviderStage(owner)
    if issecretvalue and issecretvalue(owner) then return nil, "secret-owner" end
    if type(owner) ~= "table" then return nil, "invalid-owner" end
    if canaccesstable and not canaccesstable(owner) then return nil, "inaccessible-owner" end
    local member = owner.GetStage
    if issecretvalue and issecretvalue(member) then return nil, "secret-getstage" end
    if type(member) ~= "function" then return nil, "no-getstage" end
    local ok, stage = pcall(member, owner)
    if not ok then return nil, "getstage-error" end
    if issecretvalue and issecretvalue(stage) then return nil, "secret-stage" end
    if type(stage) ~= "number" or stage ~= stage or stage == math.huge or stage == -math.huge then
        return nil, "invalid-stage"
    end
    return stage
end

-- The stage a Timer receipt starts, or nil: the encounter's stageCue row, with
-- a published duration that rounds to the cue's at one decimal, as the
-- provider rounds it. Only the row and the duration decide; no text is read.
function DT._StageCueStage(cue, curationId, time)
    if type(cue) ~= "table" or curationId ~= cue.spellID then return nil end
    if type(time) ~= "number" or math.floor(time * 10 + 0.5) ~= cue.duration * 10 then return nil end
    return cue.stage
end

-- The encounter's own stage. It starts at 1 for an encounter with a stageCue
-- and only moves forward, so a repeated or replayed cue changes nothing. The
-- provider's stage is not read: it can be left over from an earlier pull.
function DT:_NoteEncounterStage(stage)
    local current = self._encounterStage
    if type(current) ~= "number" or stage <= current then return end
    self._encounterStage = stage
    if self._windMap then self:_WindMapStage(stage) end
end

-- Encounter-source events only; the fields read are NeverSecret and the
-- secret ones (spell identity, icons, severity) are never touched.
function DT:OnEncounterTimelineEventAdded(_, eventInfo)
    local encounterId = self._activeEncounterId
    if not encounterId or type(eventInfo) ~= "table" then return end
    if TIMELINE_SOURCE_ENCOUNTER == nil then return end
    local source, id, duration = eventInfo.source, eventInfo.id, eventInfo.duration
    if issecretvalue and (issecretvalue(source) or issecretvalue(id) or issecretvalue(duration)) then
        return
    end
    if source ~= TIMELINE_SOURCE_ENCOUNTER then return end
    local maxQueue = eventInfo.maxQueueDuration
    if issecretvalue and issecretvalue(maxQueue) then maxQueue = nil end
    local ok, reason = State.RecordTimelineEvent(self._state, encounterId, id, duration, GetTime(), maxQueue)
    if not ok then
        dprint("timeline record refused: " .. tostring(reason))
        return
    end
    dprint(string_format("timeline event id=%s duration=%s maxQueue=%s at=%.3f",
        tostring(id), tostring(duration), tostring(maxQueue), GetTime()))
end

function DT:_RegisterTimelineEvent()
    if self._timelineEventRegistered then return end
    self:RegisterEvent("ENCOUNTER_TIMELINE_EVENT_ADDED", "OnEncounterTimelineEventAdded")
    self._timelineEventRegistered = true
end

function DT:_UnregisterTimelineEvent()
    if not self._timelineEventRegistered then return end
    self:UnregisterEvent("ENCOUNTER_TIMELINE_EVENT_ADDED")
    self._timelineEventRegistered = false
end

-- The provider can publish marked pull receipts before KE's encounter start.
-- Hold validated payloads until that start; stops and expiry void them.
local PULL_HOLD_WINDOW, PULL_HOLD_PER_SOURCE = 0.5, 4

local function DropHeldPullReceipts(self, owner, label)
    local held = self._pullHold
    if #held == 0 then return end
    local kept = {}
    for i = 1, #held do
        local entry = held[i]
        if entry.owner ~= owner or (label ~= nil and entry.label ~= label) then
            kept[#kept + 1] = entry
        end
    end
    self._pullHold = kept
end

function DT:_HoldPullReceipt(event, ...)
    local owner = ...
    if issecretvalue and issecretvalue(owner) then return end
    if event == "BigWigs_StopBar" or event == "BigWigs_PauseBar" or event == "BigWigs_ResumeBar" then
        local label = select(2, ...)
        if issecretvalue and issecretvalue(label) then return end
        if label ~= nil then DropHeldPullReceipts(self, owner, label) end
        return
    end
    if event == "BigWigs_StopBars" or event == "BigWigs_OnBossDisable" then
        DropHeldPullReceipts(self, owner, nil)
        return
    end
    local binding, label, cap = self:_ValidatePullReceipt(event, ...)
    if not binding then return end
    local held, fromSource = self._pullHold, 0
    for i = 1, #held do
        local entry = held[i]
        -- A Timer label already held would be refused as outstanding after the start.
        if label ~= nil and entry.owner == owner and entry.label == label then return end
        if entry.source == binding.curationId then fromSource = fromSource + 1 end
    end
    if cap and fromSource >= cap then return end
    if fromSource >= PULL_HOLD_PER_SOURCE then
        dprint("pull receipt dropped: source full")
        return
    end
    held[#held + 1] = { event = event, owner = owner, label = label, source = binding.curationId,
        encounterId = binding.encounterId, at = GetTime(), traceReceipt = self:_CaptureTraceReceipt(),
        n = select("#", ...), ... }
    dprint(string_format("pull receipt held event=%s encounter=%d", event, binding.encounterId))
end

local function IsTimerPayloadReadable(key, time, text, icon, isCooldown, isBarEnabled)
    return not (issecretvalue and (issecretvalue(key) or issecretvalue(time) or issecretvalue(text)
        or issecretvalue(icon) or issecretvalue(isCooldown) or issecretvalue(isBarEnabled)))
end

local function IsMessagePayloadReadable(key, message)
    return not (issecretvalue and (issecretvalue(key) or issecretvalue(message)))
end

-- Malformed receipts must not reserve a label or consume capacity.
function DT:_ValidatePullReceipt(event, ...)
    if event == "BigWigs_Timer" then
        local owner, key, time, maxTime, text, _, icon, isCooldown, isBarEnabled = ...
        if not IsTimerPayloadReadable(key, time, text, icon, isCooldown, isBarEnabled) then return nil end
        if type(text) ~= "string" or text == "" then return nil end
        local meta = self:_ResolveOwnerMeta(owner)
        if not meta then return nil end
        local binding = State.ResolvePullBinding(self._bindings, meta, "Timer", key, isCooldown)
        if not binding or not DT._NormalizeSpan(binding.spanMode, time, maxTime) then return nil end
        return binding, text
    elseif event == "BigWigs_Message" then
        local owner, key, message = ...
        if not IsMessagePayloadReadable(key, message) then return nil end
        local meta = self:_ResolveOwnerMeta(owner)
        if not meta then return nil end
        local binding = State.ResolvePullBinding(self._bindings, meta, "Message", key, nil)
        local data = binding and binding.cueKey and self:GetSpellInfo(binding.cueKey)
        if not data or not self:_MatchCueMessage(owner, binding, data, message) then return nil end
        return binding, nil, data.maxPerPull
    end
    return nil
end

-- Taken before the replay, so each held receipt runs once.
function DT:_ReplayPullReceipts(id)
    local held = self._pullHold
    self._pullHold = {}
    if #held == 0 then return end
    local now, replayed = GetTime(), 0
    for i = 1, #held do
        local entry = held[i]
        local age = now - entry.at
        if entry.encounterId == id and age >= 0 and age <= PULL_HOLD_WINDOW then
            replayed = replayed + 1
            self:_ReplayProviderEvent(entry.traceReceipt, nil, entry.event, nil, unpack(entry, 1, entry.n))
        end
    end
    dprint(string_format("pull replay encounter=%s replayed=%d of %d", tostring(id), replayed, #held))
end

-- Without an encounter end before a pull, the previous pull's kick countdown
-- or result would still be showing.
local function EndInterruptCues(self)
    local ending = {}
    for owner, byKind in pairs(self._slotPresentations) do
        local byKey = byKind.cue
        if byKey then
            for slotKey in pairs(byKey) do
                local cueKey = slotKey:match("^[^#]+")
                local data = cueKey and self:GetSpellInfo(cueKey)
                if data and data.interruptResult then
                    ending[#ending + 1] = { owner = owner, cueKey = cueKey }
                end
            end
        end
    end
    for i = 1, #ending do self:_EndCue(ending[i].owner, ending[i].cueKey) end
end

-- A secret answer reads as unknown.
local function ReadBossSlot(unit)
    local present = UnitExists(unit)
    if issecretvalue and issecretvalue(present) then return nil end
    return present == true
end

function DT:_StopBossAppearWatch()
    if not self._bossAppear then return end
    self._bossAppear = nil
    self:UnregisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
end

-- Registered only for an encounter with a boss-appear cue.
function DT:_StartBossAppearWatch(id)
    local byEncounter = self._bindings and self._bindings.bossAppear
    local units = id and byEncounter and byEncounter[id]
    if not units then
        self:_StopBossAppearWatch()
        return
    end
    local watch = {}
    for unit, binding in pairs(units) do
        local track = State.NewBossAppearTrack()
        State.NoteBossAppear(track, ReadBossSlot(unit))
        watch[unit] = { cueKey = binding.cueKey, track = track }
    end
    self._bossAppear = watch
    self:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT", "OnBossAppearEvent")
end

function DT:OnBossAppearEvent()
    local watch = self._bossAppear
    if not watch then return end
    for unit, entry in pairs(watch) do
        if State.NoteBossAppear(entry.track, ReadBossSlot(unit)) then
            self:_ShowBossAppearCue(entry.cueKey, GetTime())
        end
    end
end

-- The cue draws under the one boss module admitted for the active encounter.
function DT:_ShowBossAppearCue(cueKey, now)
    if not self:ShouldShowSpell(cueKey) then
        dprint("boss appear suppressed reason=filtered cue=" .. cueKey)
        return
    end
    local data = self:GetSpellInfo(cueKey)
    if not data then return end
    local owner, ownerReason = State.SoleEncounterOwner(self._state, self._activeEncounterId)
    if not owner then
        dprint("boss appear refused reason=" .. tostring(ownerReason) .. " cue=" .. cueKey)
        return
    end
    local display = self:GetSpellDisplay(cueKey)
    local window = self:GetSpellEffectiveShowAtSeconds(cueKey, display)
    local revealAt, endAt = State.PlanSequel(now, 0, data.duration, window)
    if not revealAt then
        dprint("boss appear refused reason=" .. tostring(endAt) .. " cue=" .. cueKey)
        return
    end
    self:_ScheduleCueWindow(owner, cueKey, display, revealAt, endAt, now)
end

function DT:OnEncounterStart(_, encounterID)
    EndInterruptCues(self)
    CloseCueInterrupts(self)
    self._activeEncounterId = tonumber(encounterID)
    local id = self._activeEncounterId
    self:StartPhaseTracking(id)
    -- An encounter with a stage cue starts in stage 1. StartPhaseTracking has
    -- just cleared the previous encounter's stage, and this runs before the
    -- wind map starts and before any held receipt is replayed.
    local stagedEncounter = id and KE.EncounterData and KE.EncounterData[id]
    self._encounterStage = (stagedEncounter and stagedEncounter.stageCue) and 1 or nil
    local swapCfg = stagedEncounter and stagedEncounter.shieldSwap
    self._shieldSwap = swapCfg and Swap.New(swapCfg) or nil
    self:_ShieldWarningStart()
    if id then State.ClearCueCounts(self._state, id) end
    -- Drops a shield left by an encounter that never ended, and releases the
    -- shield events for an encounter without a shield binding.
    self:_HideAllShieldBars()
    self._activeShieldSpellIds = self:_CollectShieldSpellIds(id)
    if id and #self._activeShieldSpellIds > 0 then
        self:_RegisterAbsorbEvent()
    else
        self:_UnregisterAbsorbEvent()
    end
    self:_WindMapEncounterStart(id, true)
    self:_StartBossAppearWatch(id)
    self:_ReplayPullReceipts(id)
end

-- Retires this encounter's work now instead of waiting for the publisher's delayed disable.
function DT:OnEncounterEnd()
    local id = self._activeEncounterId
    if id then
        self:_CloseAllCastWork("encounter-end")
        local retired = State.RetireEncounter(self._state, id)
        for i = 1, #retired do
            self:ReleaseInstancePresentations(retired[i], false)
        end
        for owner, scope in pairs(self._state.scopes) do
            if scope.encounterId == id then
                ReleaseOwnerWork(self, owner)
            end
        end
    end
    self._ownerMeta = {}
    self._pullHold = {}
    self._activeEncounterId = nil
    self:StopPhaseTracking()
    self:_UnregisterAbsorbEvent()
    self:_HideAllShieldBars()
    self._activeShieldSpellIds = {}
    self:_ReleaseAllUnitCastEvents()
    self:_WindMapTeardown()
    self:_StopBossAppearWatch()
end

-- Settings preview bars/texts: looping fake bars for live feedback while editing GUI panels.
local PREVIEW_BAR_KEYS = { "__preview_bar_1", "__preview_bar_2", "__preview_bar_3" }
local PREVIEW_TEXT_KEYS = { "__preview_text_1", "__preview_text_2", "__preview_text_3" }
local PREVIEW_BAR_LABELS = { "Sample Bar A", "Sample Bar B", "Sample Bar C" }
local PREVIEW_TEXT_LABELS = { "Sample Text A", "Sample Text B", "Sample Text C" }
local PREVIEW_DURATIONS = { 3, 6, 10 }
local PREVIEW_ICON_IDS = { 236273, 460952, 429383 }

DT.previewBarShown = false
DT.previewTextShown = false

local function CreatePreviewBar(self, key, label, duration, displayMode, iconID, sortIndex)
    local existing = self.bars[key]
    if existing then
        ReleaseBar(existing)
    end
    local bar = self:CreateBar(label, duration, 0, displayMode)
    bar.isPreview = true
    bar.loop = true
    bar.sortIndex = sortIndex
    -- CreateBar uses `text` as the dict key. Override so our preview keys
    -- don't collide with a real BigWigs bar literally named "Sample Timer A".
    bar.text = key
    -- Stash iconTex so text-mode previews can render the KE-standard icon
    -- block in ApplyVisualsToBar (bar mode also paints bar.icon directly).
    -- iconTex must be set BEFORE re-running ApplyVisualsToBar — CreateBar
    -- already ran it once with iconTex=nil (preview doesn't pass spellId),
    -- so we re-apply here to surface the icon block on the preview frame.
    bar.iconTex = iconID
    if iconID and bar.icon then
        bar.icon:SetTexture(iconID)
    end
    ApplyVisualsToBar(bar)
    self.bars[key] = bar
end

function DT:ShowSettingsBarPreviews()
    -- Group preview owns BarGroup; clear single-spell preview to avoid double-render.
    self:HideSpellPreview()
    if self.previewBarShown then
        self:ApplySettings()
        return
    end
    self.previewBarShown = true
    for i, key in ipairs(PREVIEW_BAR_KEYS) do
        CreatePreviewBar(self, key, PREVIEW_BAR_LABELS[i], PREVIEW_DURATIONS[i], "bar", PREVIEW_ICON_IDS[i], i)
    end
    self:LayoutBars()
end

function DT:HideSettingsBarPreviews()
    if not self.previewBarShown then return end
    self.previewBarShown = false
    for _, key in ipairs(PREVIEW_BAR_KEYS) do
        local bar = self.bars[key]
        if bar then
            ReleaseBar(bar)
            self.bars[key] = nil
        end
    end
    self:LayoutBars()
end

function DT:RefreshSettingsBarPreviews()
    if self.previewBarShown then
        self:ApplySettings()
    else
        self:ShowSettingsBarPreviews()
    end
end

function DT:ShowSettingsTextPreviews()
    -- Group preview owns TextGroup; clear single-spell preview to avoid double-render.
    self:HideSpellPreview()
    if self.previewTextShown then
        self:ApplySettings()
        return
    end
    self.previewTextShown = true
    for i, key in ipairs(PREVIEW_TEXT_KEYS) do
        CreatePreviewBar(self, key, PREVIEW_TEXT_LABELS[i], PREVIEW_DURATIONS[i], "text", PREVIEW_ICON_IDS[i], i)
    end
    self:LayoutBars()
end

function DT:HideSettingsTextPreviews()
    if not self.previewTextShown then return end
    self.previewTextShown = false
    for _, key in ipairs(PREVIEW_TEXT_KEYS) do
        local bar = self.bars[key]
        if bar then
            ReleaseBar(bar)
            self.bars[key] = nil
        end
    end
    self:LayoutBars()
end

function DT:RefreshSettingsTextPreviews()
    if self.previewTextShown then
        self:ApplySettings()
    else
        self:ShowSettingsTextPreviews()
    end
end

-- Per-spell preview: ONE looping bar/text rendered with the selected spell's effective settings.
local SPELL_PREVIEW_KEY = "__spell_preview"
local SPELL_PREVIEW_BASE_DURATION = 8

DT.spellPreviewSpellId = nil

function DT:ShowSpellPreview(spellId)
    if not spellId then
        self:HideSpellPreview()
        return
    end
    -- Idempotent on same spell — RefreshContent fires on every tab switch and shouldn't restart the loop.
    if self.spellPreviewSpellId == spellId and self.bars[SPELL_PREVIEW_KEY] then
        return
    end
    self:HideSpellPreview()
    self:HideSettingsBarPreviews()
    self:HideSettingsTextPreviews()

    local data = self:GetSpellInfo(spellId) or {}
    local extension = self:GetSpellExtension(spellId) or 0
    local displayMode = self:GetSpellDisplay(spellId) or "text"
    local displayText = self:GetSpellDisplayText(spellId)

    local fallback = tostring(spellId)
    if type(spellId) == "number" then
        fallback = string_format("Spell %d", spellId)
    end
    local label = data.name or fallback

    -- Preview chain MUST mirror the render entry point's (override → curator
    -- → group default → 0) so what the user sees here matches in-fight.
    local effectiveShowAt = self:GetSpellEffectiveShowAtSeconds(spellId, displayMode)
    -- forceDuration / spawnOnMessage / phantomFollowupOf spells all use a
    -- curated duration field for the preview so what the user sees here
    -- matches what they'll see in-fight, not the generic 8s preview-base
    -- or a reveal-window slice.
    local forceDur = self:GetSpellForceDuration(spellId)
    local curatedDur
    if (data.spawnOnMessage or data.phantomFollowupOf) and data.duration then
        curatedDur = tonumber(data.duration)
    elseif DT.IsCueKey(spellId) then
        -- Provider-timed cues use a sample length outside the encounter.
        curatedDur = data.duration or SPELL_PREVIEW_BASE_DURATION
        if data.duration and effectiveShowAt > 0 and effectiveShowAt < curatedDur then
            curatedDur = effectiveShowAt
        end
    end
    local baseDuration
    if forceDur then
        baseDuration = forceDur
    elseif curatedDur then
        baseDuration = curatedDur
    elseif effectiveShowAt > 0 then
        local binding = self:GetSpellAdmittedBinding(spellId)
        if binding then
            -- The rule-6 floor keeps this positive; the max(1, ...) clamp
            -- would preview a longer bar than the row runs.
            baseDuration = effectiveShowAt - extension
        else
            baseDuration = math.max(1, effectiveShowAt - extension)
        end
    else
        baseDuration = SPELL_PREVIEW_BASE_DURATION
    end

    local bar = self:CreateBar(label, baseDuration, extension,
                               displayMode, displayText, spellId)
    bar.isPreview = true
    bar.loop = true
    -- sortIndex=1 keeps the preview at top — real bars start at 1000.
    bar.sortIndex = 1
    bar.text = SPELL_PREVIEW_KEY

    if bar.icon then
        bar.icon:SetTexture(self:ResolveSpellIcon(spellId) or 134400)
    end

    self.bars[SPELL_PREVIEW_KEY] = bar
    self.spellPreviewSpellId = spellId
    self:LayoutBars()
end

function DT:HideSpellPreview()
    local bar = self.bars[SPELL_PREVIEW_KEY]
    if bar then
        ReleaseBar(bar)
        self.bars[SPELL_PREVIEW_KEY] = nil
    end
    self.spellPreviewSpellId = nil
    self:LayoutBars()
end

function DT:RefreshSpellPreview()
    if not self.spellPreviewSpellId then return end
    local id = self.spellPreviewSpellId
    self:HideSpellPreview()
    self:ShowSpellPreview(id)
end

-- Per-phase preview: a static "Phase Transition X%" bar rendered with the
-- selected rule's effective settings. Mid-window value (lead/2) so the
-- user sees a representative state, not the just-entered or about-to-fire edge.
local PHASE_PREVIEW_KEY = "__phase_preview"
DT.phasePreviewKey = nil

-- Preview-private kit cache, one per display mode (bar/text kits differ).
-- Clicking phase-rule rows used to build a fresh CreatePhaseBar kit per
-- click and strand the old one (frames are never GC'd). In-fight phase
-- bars are NOT cached here — they still build fresh kits per pull.
local phasePreviewKits = {}

function DT:ShowPhasePreview(key)
    if not (key and self:IsPhaseRuleKey(key)) then
        self:HidePhasePreview()
        return
    end
    -- Idempotent on same key.
    if self.phasePreviewKey == key and self.bars[PHASE_PREVIEW_KEY] then
        return
    end
    self:HidePhasePreview()
    self:HideSpellPreview()
    self:HideSettingsBarPreviews()
    self:HideSettingsTextPreviews()

    -- Build a phase-style bar wired to the rule's effective overrides.
    -- We pass the real key so color/display-mode helpers resolve correctly,
    -- but we re-key it under PHASE_PREVIEW_KEY in self.bars so a real
    -- in-fight phase bar can coexist (e.g. testing on a target dummy with
    -- active encounter). Reuse the cached kit for this display mode when
    -- one exists; sortIndex 1 places the preview before other phase rows.
    local mode = self:GetPhaseDisplay(key)
    local bar = phasePreviewKits[mode]
    if bar then
        ConfigurePhaseBar(self, bar, key, 1)
        bar:Show()
    else
        bar = CreatePhaseBar(self, key, 1)
        phasePreviewKits[mode] = bar
    end
    bar.isPreview = true
    bar.text = PHASE_PREVIEW_KEY

    local lead = self:GetPhaseEffectiveLead(key)
    local sample = math.max(1, math.ceil(lead / 2))
    local baseLabel = self:GetPhaseEffectiveLabel(key)
    if bar.displayMode == "bar" then
        if bar.label then bar.label:SetText(baseLabel) end
        if bar.timerText then bar.timerText:SetText(string_format("%d%%", sample)) end
        if bar.bar and lead > 0 then
            bar.bar:SetMinMaxValues(0, lead)
            bar.bar:SetValue(sample)
        end
    else
        if bar.label then bar.label:SetText(string_format("%s %d%%", baseLabel, sample)) end
    end

    self.bars[PHASE_PREVIEW_KEY] = bar
    self.phasePreviewKey = key
    self:LayoutBars()
end

function DT:HidePhasePreview()
    local bar = self.bars[PHASE_PREVIEW_KEY]
    if bar then
        -- Phase kits aren't pool-tagged — ReleaseBar hides without pooling.
        ReleaseBar(bar)
        self.bars[PHASE_PREVIEW_KEY] = nil
    end
    self.phasePreviewKey = nil
    self:LayoutBars()
end

function DT:RefreshPhasePreview()
    if not self.phasePreviewKey then return end
    local key = self.phasePreviewKey
    self:HidePhasePreview()
    self:ShowPhasePreview(key)
end

local AURA_BOSS_TOKENS = { "boss1", "boss2", "boss3", "boss4", "boss5" }

function DT.MakeAuraKey(encounterId, spellID, trigger)
    return "aura:" .. tostring(encounterId) .. ":" .. tostring(spellID) .. ":" .. tostring(trigger)
end

function DT.IsAuraKey(key)
    return type(key) == "string" and key:find("^aura:") ~= nil
end

local AURA_RULE_FIELDS = { spellID = true, trigger = true, unit = true, name = true, sound = true, disabled = true }
local AURA_RULE_TRIGGERS = { added = true, removed = true, increased = true }
local AURA_RULE_UNITS = { player = true, boss = true }

function DT.IsWellFormedAuraRule(rule)
    if type(rule) ~= "table" then return false end
    for field in pairs(rule) do
        if not AURA_RULE_FIELDS[field] then return false end
    end
    if type(rule.spellID) ~= "number" then return false end
    if not AURA_RULE_TRIGGERS[rule.trigger] or not AURA_RULE_UNITS[rule.unit] then return false end
    if type(rule.name) ~= "string" or rule.name == "" then return false end
    if type(rule.sound) ~= "string" or rule.sound == "" then return false end
    return rule.disabled == nil or type(rule.disabled) == "boolean"
end

-- Target and nameplate aliases could register the same enemy sound again.
function DT._BuildAuraSoundWanted(encounterData, registry, ctx)
    local wanted = {}
    if not ctx.enabled or ctx.muted or not ctx.instanceID then return wanted end
    local dungeonKey
    for i = 1, #registry do
        if registry[i].instanceID == ctx.instanceID then dungeonKey = registry[i].key end
    end
    if not dungeonKey then return wanted end

    for encounterId, enc in pairs(encounterData) do
        if enc.dungeon == dungeonKey and type(enc.auraSounds) == "table" then
            for i = 1, #enc.auraSounds do
                local rule = enc.auraSounds[i]
                local trigger
                if DT.IsWellFormedAuraRule(rule) then trigger = ctx.triggers[rule.trigger] end
                if trigger ~= nil then
                    local key = DT.MakeAuraKey(encounterId, rule.spellID, rule.trigger)
                    local name = not ctx.isDisabled(key) and ctx.soundFor(key) or nil
                    local path = name and ctx.resolveMedia(name) or nil
                    if path and rule.unit == "player" then
                        wanted[#wanted + 1] = { trigger = trigger, unitToken = "player",
                            spellID = rule.spellID, path = path, channel = ctx.channel }
                    elseif path then
                        for t = 1, #AURA_BOSS_TOKENS do
                            wanted[#wanted + 1] = { trigger = trigger, unitToken = AURA_BOSS_TOKENS[t],
                                spellID = rule.spellID, path = path, channel = ctx.channel }
                        end
                    end
                end
            end
        end
    end
    return wanted
end

local function CurrentInstanceMapID()
    if not GetInstanceInfo then return nil end
    return (select(8, GetInstanceInfo()))
end

function DT:_UpdateAuraSoundEvents(wantEvents)
    wantEvents = wantEvents and true or false
    if wantEvents == (self._auraSoundEvents == true) then return end
    self._auraSoundEvents = wantEvents
    if wantEvents then
        self:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", "OnAuraSoundRestrictionChanged")
        self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnAuraSoundRelease")
    else
        self:UnregisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
end

function DT:OnAuraSoundRelease()
    if self._auraSounds and self._auraSounds:IsPending() then self:SyncAuraSounds() end
end

-- The restriction state is read one frame after the event, once it has settled.
function DT:OnAuraSoundRestrictionChanged()
    if not (self._auraSounds and self._auraSounds:IsPending()) then return end
    C_Timer.After(0, function() self:OnAuraSoundRelease() end)
end

-- The client owns aura matching and playback; Lua retains only registration IDs.
function DT:SyncAuraSounds()
    self:UpdateDB()
    local enabled = self._auraSoundsActive == true and self.db ~= nil and self.db.Enabled == true
    local instanceID
    if enabled then instanceID = CurrentInstanceMapID() end
    local triggerEnum = Enum and Enum.UnitAuraSoundTrigger
    local wanted = {}
    if triggerEnum and KE.LSM then
        wanted = DT._BuildAuraSoundWanted(KE.EncounterData or {}, KE.DungeonTimerDungeons or {}, {
            enabled = enabled,
            instanceID = instanceID,
            muted = self.db ~= nil and self.db.MutePresetSounds == true,
            channel = (self.db and self.db.SoundChannel) or "Master",
            triggers = { added = triggerEnum.Added, removed = triggerEnum.Removed,
                increased = triggerEnum.ApplicationsIncreased },
            isDisabled = function(key) return self:IsSpellDisabled(key) end,
            soundFor = function(key) return self:GetEffectiveSpellSoundOnShow(key) end,
            resolveMedia = function(name) return KE.LSM:Fetch("sound", name, true) end,
        })
    end

    local registry = self._auraSounds
    if not registry then
        if #wanted == 0 then
            self:_UpdateAuraSoundEvents(false)
            return
        end
        local Sound = KE.AuraSound
        if not (Sound and C_UnitAuras and C_UnitAuras.AddAuraSound and C_UnitAuras.RemoveAuraSound) then return end
        registry = Sound.New({
            api = { Add = C_UnitAuras.AddAuraSound, Remove = C_UnitAuras.RemoveAuraSound },
            isHidden = function()
                if not KE.AreAuraIdentitiesHidden then return true end
                return KE:AreAuraIdentitiesHidden()
            end,
            onDiagnostic = dprint,
        })
        self._auraSounds = registry
    end
    registry:SyncRules(wanted)
    if #wanted == 0 and not registry:IsPending() then self._auraSounds = nil end
    self:_UpdateAuraSoundEvents(enabled and registry:IsPending())
end

-- The WRONG TARGET alert keeps its enable in its own setting, not in the
-- spell disable list.
function DT:_IsProviderCueEnabled(cueKey)
    if type(cueKey) == "string" and cueKey:find("^warn:") then
        local warning = self.db and self.db.ShieldWarning
        return warning ~= nil and warning.Enabled == true
    end
    return not self:IsSpellDisabled(cueKey)
end

-- A warning key has no spell of its own; its encounter names the icon spell.
function DT:_ResolveProviderIcon(cueKey)
    local entry = CUE_PROVIDER_OPTIONS[cueKey]
    if not (entry and cueKey:find("^warn:")) then return self:ResolveSpellIcon(cueKey) end
    local enc = KE.EncounterData and KE.EncounterData[entry.encounterId]
    local swap = enc and enc.shieldSwap
    local icon = type(swap) == "table" and swap.icon or nil
    if not (icon and C_Spell and C_Spell.GetSpellTexture) then return nil end
    return C_Spell.GetSpellTexture(icon)
end

function DT:_ProviderSetupGate(cueKey, inCombat)
    local entry = CUE_PROVIDER_OPTIONS[cueKey]
    local applicable = true
    if entry and entry.mythicOnly then
        applicable = false
        if GetInstanceInfo then
            local _, _, difficulty, _, _, _, _, instanceID = GetInstanceInfo()
            if IsPlainValue(instanceID, "number") then
                applicable = instanceID ~= entry.instanceID or (IsPlainValue(difficulty, "number")
                    and (difficulty == 8 or difficulty == 23))
            end
        end
    end
    return State.ProviderSetupGate({
        hasDescriptor = entry ~= nil,
        applicable = applicable,
        moduleEnabled = self._providerSetupActive == true and (self.db and self.db.Enabled) and true or false,
        cueEnabled = self:_IsProviderCueEnabled(cueKey),
        inCombat = inCombat,
    })
end

function DT:_ProviderSetupCueKeys()
    return CUE_PROVIDER_ORDER
end

function DT:_GetProviderSetupNotice(cueKey)
    local entry = CUE_PROVIDER_OPTIONS[cueKey]
    if not entry then return nil end
    local refusal = self:_ProviderSetupGate(cueKey, false)
    if refusal then return refusal == "not-applicable" and refusal or "disabled", entry end
    local status, _, _, reason = self:_ReadCueProviderOption(cueKey)
    return status, entry, reason
end

function DT:_RetireProviderPrompt(cueKey)
    if cueKey and self._cueProviderKey ~= cueKey then return end
    local accept = self._cueProviderAccept
    self._cueProviderAccept = nil
    self._cueProviderOrigin = nil
    self._cueProviderKey = nil
    if accept then KE:ClosePromptIfOwner(accept) end
end

-- A town dismissal must not suppress the next dungeon visit.
function DT:_NoteProviderPromptAnswered(cueKey)
    local entry, answered = CUE_PROVIDER_OPTIONS[cueKey], self._providerSetupAnswered
    if entry and answered and CurrentInstanceMapID() == entry.instanceID then answered[cueKey] = true end
end

function DT:_RunProviderSetupCheck(explicit, cueKey)
    local entry, answered = CUE_PROVIDER_OPTIONS[cueKey], self._providerSetupAnswered
    local inInstance = entry ~= nil and CurrentInstanceMapID() == entry.instanceID
    -- Before the gate: leaving ends the visit even while the alert is disabled.
    if answered and not inInstance then answered[cueKey] = nil end
    if self:_ProviderSetupGate(cueKey, false) then
        self:_RetireProviderPrompt(cueKey)
        NotifyCueProviderNotice(self, cueKey)
        return nil
    end
    local status, _, _, reason = self:_ReadCueProviderOption(cueKey)
    local plan = State.PlanProviderSetup({
        explicit = explicit,
        inInstance = inInstance,
        status = status,
        answered = answered[cueKey] == true,
        pending = self._cueProviderAccept
            and (self._cueProviderKey == cueKey and self._cueProviderOrigin or "other") or nil,
    })
    if plan == "open" then
        self:_OpenCueProviderPrompt(cueKey, explicit and "explicit" or "auto")
    elseif plan == "close" then
        self:_RetireProviderPrompt(cueKey)
    end
    NotifyCueProviderNotice(self, cueKey)
    return reason
end

-- The flag outlives disable so re-enabling before the callback cannot queue another.
function DT:_RequestProviderSetupCheck()
    if not self._providerSetupActive or self._providerSetupQueued then return end
    self._providerSetupQueued = true
    C_Timer.After(0, function()
        self._providerSetupQueued = false
        if not self._providerSetupActive then return end
        local pendingKey = self._cueProviderKey
        if pendingKey then self:_RunProviderSetupCheck(false, pendingKey) end
        for _, cueKey in ipairs(CUE_PROVIDER_ORDER) do
            if cueKey ~= pendingKey then self:_RunProviderSetupCheck(false, cueKey) end
        end
    end)
end

function DT:_OnProviderCueChanged(spellId)
    if not CUE_PROVIDER_OPTIONS[spellId] then return end
    if not self:_IsProviderCueEnabled(spellId) then self:_RetireProviderPrompt(spellId) end
    self:_RequestProviderSetupCheck()
end

-- Native loading respects disabled addons; the provider's zone loader enables them.
local function LoadProviderAddOn(name)
    local addOns = C_AddOns
    if not (addOns and addOns.IsAddOnLoaded and addOns.LoadAddOn) then return false end
    local okState, _, isLoaded = pcall(addOns.IsAddOnLoaded, name)
    if okState and isLoaded == true then return true end
    local okCall, loaded, why = pcall(addOns.LoadAddOn, name)
    if okCall and loaded == true then return true end
    if okCall and IsPlainValue(why, "string") then return false, why end
    return false
end

local function LoadProviderContent(entry)
    if not IsReadableTable(BigWigs) then
        local loaded, why = LoadProviderAddOn("BigWigs_Core")
        if not loaded or not IsReadableTable(BigWigs) then return why, "BigWigs_Core" end
    end
    local loaded, why = LoadProviderAddOn(entry.contentAddon)
    if not loaded then return why, entry.contentAddon end
end

---@param reportedFailures table<string, boolean>?
function DT:_CheckProviderSetupNow(cueKey, reportedFailures)
    if self:_ProviderSetupGate(cueKey, InCombatLockdown() and true or false) then
        NotifyCueProviderNotice(self, cueKey)
        return
    end
    local entry = CUE_PROVIDER_OPTIONS[cueKey]
    local _, _, _, before = self:_ReadCueProviderOption(cueKey)
    local loadReason, failedAddon
    if before == "not-loaded" then loadReason, failedAddon = LoadProviderContent(entry) end
    self._providerSetupAnswered[cueKey] = nil
    if self:_RunProviderSetupCheck(true, cueKey) ~= "not-loaded" then return end
    failedAddon = failedAddon or entry.contentAddon
    if reportedFailures then
        if reportedFailures[failedAddon] then return end
        reportedFailures[failedAddon] = true
    end
    if loadReason then
        KE:Print(string_format("BigWigs addon %s is not loaded (%s).", failedAddon, loadReason))
    else
        KE:Print(string_format("BigWigs addon %s is not loaded. Check that BigWigs and LittleWigs"
            .. " are enabled.", failedAddon))
    end
end

function DT:OnProviderSetupSignal(event)
    if event == "BigWigs_ProfileUpdate" then
        self:_RetireProviderPrompt()
        self._providerSetupAnswered = {}
    end
    self:_RequestProviderSetupCheck()
end

function DT:OnInitialize()
    -- db must be populated BEFORE KitnEssentials:OnEnable's auto-enable loop checks module.db.Enabled.
    self:UpdateDB()
    self:SetEnabledState(false)
end

function DT:OnEnable()
    dprint("OnEnable")
    self:UpdateDB()

    self._state = State.New()
    self._bindings = State.BuildBindings(KE.EncounterData)
    self._ownerMeta = {}
    self._presentations = {}
    self._effectiveBindings = {}
    self._jobs = {}
    self._ownedJobs = {}
    self._slotJobs = {}
    self._cueInstances = {}
    self._cueLabels = {}
    self._forecastGates = {}
    self._gateSuppressed = {}
    self._slotPresentations = {}
    self._cueInterrupts = {}
    self._shieldWatches = {}
    self._shieldWatchByLabel = {}
    self._holdJobs = {}
    self._castWatches = {}
    self._observeWindows = {}
    self._castMatches = {}
    self._castFollows = {}
    self._observedRetireJobs = {}
    self._unitCastHolders = {
        UNIT_SPELLCAST_START = {}, UNIT_SPELLCAST_CHANNEL_START = {}, UNIT_SPELLCAST_CHANNEL_STOP = {},
        UNIT_SPELLCAST_INTERRUPTED = {}, UNIT_SPELLCAST_DELAYED = {}, UNIT_SPELLCAST_STOP = {},
        UNIT_SPELLCAST_FAILED = {}, UNIT_SPELLCAST_FAILED_QUIET = {},
    }
    self._activeEncounterId = nil
    self._pullHold = {}

    -- Tables first: a refused enable is still followed by OnDisable, which walks them.
    if not (self.db and self.db.Enabled) then return end
    self:UpdateGroupPositions()

    local encCount, spellCount = 0, 0
    for _, enc in pairs(KE.EncounterData or {}) do
        encCount = encCount + 1
        if enc.spells then
            for _ in pairs(enc.spells) do spellCount = spellCount + 1 end
        end
    end
    dprint(string_format("EncounterData: %d encounters, %d spells", encCount, spellCount))

    if BigWigsLoader then
        for _, event in ipairs(BIGWIGS_EVENTS) do
            BigWigsLoader.RegisterMessage(self, event, "EventCallback")
        end
        dprint("registered " .. #BIGWIGS_EVENTS .. " BigWigs events")
        BigWigsLoader.RegisterMessage(self, "BigWigs_BossModuleRegistered", "OnProviderSetupSignal")
        BigWigsLoader.RegisterMessage(self, "BigWigs_ProfileUpdate", "OnProviderSetupSignal")
    else
        dprint("BigWigsLoader missing — event registration skipped")
    end

    if LibSpec then
        LibSpec.RegisterGroup(self, function(...) DT:OnLibSpecGroupUpdate(...) end)
        dprint("LibSpec registered")
    else
        dprint("LibSpec missing — role filter degraded to always-DAMAGER")
    end

    -- Phase tracker (HP%-driven) plus the encounter identity Timer/CastTimer/
    -- Message admission compares against.
    self:RegisterEvent("ENCOUNTER_START", "OnEncounterStart")
    self:RegisterEvent("ENCOUNTER_END",   "OnEncounterEnd")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
    self:_RegisterTimelineEvent()

    if KE.db and KE.db.RegisterCallback then
        KE.db.RegisterCallback(self, "OnProfileChanged", "OnProfileBoundary")
        KE.db.RegisterCallback(self, "OnProfileCopied", "OnProfileBoundary")
        KE.db.RegisterCallback(self, "OnProfileReset", "OnProfileBoundary")
    end

    self._auraSoundsActive = true
    self:SyncAuraSounds()

    -- Also covers a boss module registered before the subscription above.
    self._providerSetupAnswered = {}
    self._providerSetupActive = true
    self:_RequestProviderSetupCheck()
    self:ApplyWindMapSettings()
end

-- A loading screen ends every live boss publication and an admitted owner
-- re-publishes after re-engage, so no instance-ID comparison is needed.
function DT:OnPlayerEnteringWorld()
    RetireOrdinaryWork(self)
    self:_StopBossAppearWatch()
    self:StopDiagnosticTrace("world-change")
    -- One frame later the instance map ID has settled.
    C_Timer.After(0, function() self:SyncAuraSounds() end)
    self:_RequestProviderSetupCheck()
end

-- Independent of ProfileManager's refresh suppression; ApplySettings must not restart clocks.
function DT:OnProfileBoundary()
    RetireOrdinaryWork(self)
    self:StopDiagnosticTrace("profile-change")
    self:SyncAuraSounds()
    self:_RetireProviderPrompt()
    self:_RequestProviderSetupCheck()
    self:ApplyWindMapSettings()
    self:ApplyShieldWarningSettings()
end

function DT:OnDisable()
    dprint("OnDisable")
    if BigWigsLoader then
        for _, event in ipairs(BIGWIGS_EVENTS) do
            BigWigsLoader.UnregisterMessage(self, event)
        end
        BigWigsLoader.UnregisterMessage(self, "BigWigs_BossModuleRegistered")
        BigWigsLoader.UnregisterMessage(self, "BigWigs_ProfileUpdate")
    end
    if LibSpec then
        LibSpec.UnregisterGroup(self)
    end
    self:UnregisterEvent("ENCOUNTER_START")
    self:UnregisterEvent("ENCOUNTER_END")
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    self:_UnregisterTimelineEvent()
    self:_StopBossAppearWatch()
    if KE.db and KE.db.UnregisterCallback then
        KE.db.UnregisterCallback(self, "OnProfileChanged")
        KE.db.UnregisterCallback(self, "OnProfileCopied")
        KE.db.UnregisterCallback(self, "OnProfileReset")
    end
    RetireOrdinaryWork(self)
    self:_RetireProviderPrompt()
    self._providerSetupActive = false
    self._providerSetupAnswered = nil
    self._cueProviderNotice = nil
    self._providerSetupHeaderNotice = nil
    self._auraSoundsActive = false
    if self._auraSounds then
        self._auraSounds:RetireAll()
        self._auraSounds = nil
    end
    self:_UpdateAuraSoundEvents(false)
    self:_UnregisterAbsorbEvent()
    self:_ReleaseAllUnitCastEvents()
    self:_HideAllShieldBars()
    self:StopPhaseTracking()
    self:HideSettingsBarPreviews()
    self:HideSettingsTextPreviews()
    self:HideSpellPreview()
    self:HidePhasePreview()
    self:StopDiagnosticTrace("module-disabled")
end

function DT:StartDiagnosticTrace(reset)
    if not DEBUG_DT2 then KE:Print("NEED: enable the Dungeon Timers diagnostic build"); return end
    local trace, reason = Trace.Start(self, reset)
    if not trace then KE:Print("NEED: " .. reason); return end
    KE:Print(string_format("DT trace %s: revision %d, %d rows saved, %d omitted.",
        reason, self._timerStateRevision, #trace.store.rows, trace.store.omitted))
end

function DT:StopDiagnosticTrace(reason)
    local trace = self._debugTrace
    if not (trace and trace.active) then return end
    trace:Stop(reason or "user")
    KE:Print(string_format("DT trace stopped: %d rows saved, %d omitted. /reload to save to disk.",
        #trace.store.rows, trace.store.omitted))
end

function DT:_SuppressConcurrentRestarts(inst)
    if not inst.binding.suppressConcurrentRestart then return false end
    if not State.IsScopeCurrent(self._state, inst.owner, inst.scope) then return false end
    local instances = self._state.instancesByOwner[inst.owner]
    for _, other in pairs(instances) do
        local candidate, anchored = inst, other
        if inst.anchorAt then candidate, anchored = other, inst end
        if State.IsConcurrentRestart(candidate, anchored) then
            State.Retire(self._state, candidate)
            self:ReleaseInstancePresentations(candidate, false)
            dprint(string_format("restart suppressed text=%s event=%s anchorEvent=%s",
                tostring(candidate.label), tostring(candidate.timelineIdentity), tostring(anchored.anchorEventId)))
            if candidate == inst then return true end
        end
    end
    return false
end

function DT:EventCallback(event, ...)
    local trace = self._debugTrace
    if not (DEBUG_DT2 and trace and trace.active) then
        self:_HandleProviderEvent(event, nil, ...)
        return
    end
    local previousReceipt = trace.receipt
    trace.receipt = trace:Provider(event, ...)
    self:_HandleProviderEvent(event, nil, ...)
    trace.receipt = previousReceipt
end

-- Held receipts keep the trace row of the provider call that delivered them.
function DT:_CaptureTraceReceipt()
    local trace = self._debugTrace
    if not (DEBUG_DT2 and trace and trace.active) then return nil end
    return trace:Capture()
end

-- A replayed receipt's decisions, its announcement included, belong to that
-- row, not to the caller's.
function DT:_ReplayProviderEvent(captured, announcement, event, receipt, ...)
    local trace = self._debugTrace
    if not (DEBUG_DT2 and trace and trace.active) then
        if announcement then dprint(announcement) end
        self:_HandleProviderEvent(event, receipt, ...)
        return
    end
    local previousReceipt = trace.receipt
    trace.receipt = Trace.Restore(captured, trace)
    if announcement then dprint(announcement) end
    self:_HandleProviderEvent(event, receipt, ...)
    trace.receipt = previousReceipt
end

function DT:_ReplayTimerReplacement(receipt)
    if TIMELINE_STATE_ACTIVE == nil or not (C_EncounterTimeline and C_EncounterTimeline.GetEventState) then return end
    local id = State.ResolveTimelineEvent(self._state, receipt)
    if not id then return end
    local state = C_EncounterTimeline.GetEventState(id)
    if issecretvalue and issecretvalue(state) then return end
    if state ~= TIMELINE_STATE_ACTIVE then return end
    self:_ReplayProviderEvent(receipt.payload.traceReceipt, "Timer replacement replayed event=" .. tostring(id),
        "BigWigs_Timer", receipt, unpack(receipt.payload, 1, 9))
end

function DT:_HandleProviderEvent(event, receipt, ...)
    if not self._activeEncounterId then self:_HoldPullReceipt(event, ...) end
    if event == "BigWigs_Timer" then
        local owner, key, time, maxTime, text, counter, icon, isCooldown, isBarEnabled = ...
        -- Consumed before any refusal, so no earlier StartBar can reach a later receipt.
        local meta, ownerReason = self:_ResolveOwnerMeta(owner)
        local evidenceNow = GetTime()
        local evidence, startKey, startText, startTime, startCooldown, startEventId
        if not receipt then
            evidence, startKey, startText, startTime, startCooldown, startEventId =
                State.TakeStartBar(self._state, meta and owner or nil, evidenceNow)
        end
        if not IsTimerPayloadReadable(key, time, text, icon, isCooldown, isBarEnabled) then
            if evidence == "pending" then State.PoisonStartBars(self._state, owner, evidenceNow) end
            return
        end

        if not meta then
            dprint("Timer refused owner: " .. tostring(ownerReason))
            return
        end
        local identity
        if receipt then
            identity = receipt.timelineIdentity
        else
            identity = State.MatchStartBar(evidence, startKey, startText, startTime, startCooldown,
                startEventId, key, text, time, isCooldown, isBarEnabled)
        end
        if identity == "refused" then State.PoisonStartBars(self._state, owner, evidenceNow) end

        local binding, bindReason = State.ResolveBinding(self._bindings, meta, self._activeEncounterId,
            "Timer", key, isCooldown)
        if not binding then
            dprint("Timer refused binding: " .. tostring(bindReason))
            return
        end

        local spellIdNum = binding.curationId
        local now = receipt and receipt.sourceClock.receivedAt or GetTime()

        -- The owner and the binding are this encounter's; the cue counts before
        -- any later refusal or filter of its own row.
        local cueEncounter = KE.EncounterData and KE.EncounterData[binding.encounterId]
        local cueStage = cueEncounter and DT._StageCueStage(cueEncounter.stageCue, spellIdNum, time)
        if cueStage then self:_NoteEncounterStage(cueStage) end

        -- NextSlot needs an admitted scope; AdmitOwner reuses a live one so repeated
        -- Timers keep the owner's slot generations valid.
        local admitScope, admitReason = State.AdmitOwner(self._state, owner, self._activeEncounterId)
        if not admitScope then
            dprint("Timer refused admission: " .. tostring(admitReason))
            return
        end

        -- The explicit contract refuses malformed input before conversion;
        -- the legacy route keeps its coercion.
        local receivedTime = time
        if binding.policy ~= "estimated-impact" then receivedTime = tonumber(time) or 0 end
        local remaining, span = DT._NormalizeSpan(binding.spanMode, receivedTime, maxTime)
        if not remaining then
            dprint("Timer refused span: " .. tostring(span))
            return
        end

        local previous = State.Find(self._state, owner, text)
        if previous and previous.state ~= "retired" and previous.binding.holdOverlapping then
            dprint("Timer refused live overlap replacement")
            return
        end

        -- Record ownership before filtering so later label-only callbacks cannot reach an older cue.
        State.NotePublication(self._state, owner, text, binding)

        -- Refuse a pilot label still awaiting a stop before any shield,
        -- phantom, filter, admission, job or sound work for this receipt.
        if binding.collisionPolicy then
            local observed, obsReason = State.ObservePilotLabel(self._state, owner, self._activeEncounterId, text)
            if not observed then
                if not receipt and obsReason == "outstanding" then
                    local held = State.HoldTimerReplacement(self._state, owner, text, binding, remaining, now, identity,
                        { owner, key, time, maxTime, text, counter, icon, isCooldown, isBarEnabled,
                            traceReceipt = self:_CaptureTraceReceipt() })
                    if held then
                        dprint("Timer replacement held event=" .. tostring(identity))
                        return
                    end
                end
                dprint("Timer refused awaiting-stop: " .. tostring(obsReason))
                return
            end
        end

        -- A filtered Timer receipt still replaces the cue's prior occurrence.
        if binding.cueKey then
            self:_EndCue(owner, binding.cueKey)
            self._cueLabels[owner] = self._cueLabels[owner] or {}
            self._cueLabels[owner][binding.cueKey] = text
        end

        -- Armed from the normalized receipt, before the parent's own gates.
        local shield = self:GetSpellShieldBar(spellIdNum)
        if shield then
            self:_ArmShieldChannelWatch(owner, text, spellIdNum, remaining, span, now, shield.explicit)
        end

        -- Spawned before the parent's disabled/role gates: the phantom filters itself.
        local phantoms = self._bindings.phantoms[binding.encounterId]
            and self._bindings.phantoms[binding.encounterId][spellIdNum]
        if phantoms then
            for i = 1, #phantoms do
                self:_SpawnPhantomFollowup(owner, phantoms[i], icon, now)
            end
        end

        -- A cast-matched row reads its exact event at every provider stop.
        local timelineIdentity
        if binding.anchor == "timeline-finished" or binding.castMatch then
            timelineIdentity = identity
            dprint("Timer identity: " .. tostring(identity))
        end
        -- Read from the raw receipt, before the filters and the icon override below.
        local mapData = self._windMap and self:_WindMapRead(binding, icon, counter)

        local sequels = self._bindings.sequels[binding.encounterId]
        local sequel = sequels and sequels[spellIdNum]
        local queues = self._bindings.queues[binding.encounterId]
        local queue = queues and queues[spellIdNum]
        -- A same-label republish replaces the parent occurrence; the fresh slot
        -- generation drops a child job or cue left from the old anchor.
        -- A cue child is owned by the owner and the cue: no parent receipt ends it.
        if sequel and not sequel.cueKey then
            State.NextSlot(self._state, owner, "sequel", SequelSlotKey(text, sequel.key))
        end

        if self:IsSpellDisabled(spellIdNum) then
            dprint(string_format("Timer FILTERED text=%s reason=disabled", tostring(text)))
            if sequel or queue or mapData then
                self:_StartTrackOnly(owner, text, binding, spellIdNum, remaining, span, now, timelineIdentity,
                    mapData, not (sequel or queue))
            end
            return
        end

        -- Curated duration replaces the published one; ClassifyStop enforces the single-Stop exception.
        local forceDur = self:GetSpellForceDuration(spellIdNum)
        if forceDur then remaining, span = forceDur, forceDur end

        -- iconOverride: swap BigWigs's icon for a curated texture.
        local iconOverride = self:GetSpellIconOverride(spellIdNum)
        if iconOverride then icon = iconOverride end

        -- Secondary uses curated role only (no user-override GUI yet).
        local primaryAllowed = self:ShouldShowSpellRole(spellIdNum)
        local secondary = self:GetSpellSecondary(spellIdNum)
        local secondaryAllowed = false
        if secondary then
            if not (self.db and self.db.RoleFilterEnabled) then
                secondaryAllowed = true
            elseif not secondary.role then
                secondaryAllowed = true  -- untagged → fail open
            else
                local allow = ROLE_ALLOW_LIST[self.playerRole]
                secondaryAllowed = allow and (allow[secondary.role] == true) or false
            end
        end

        if not primaryAllowed and not secondaryAllowed then
            dprint(string_format("Timer FILTERED text=%s reason=role", tostring(text)))
            if sequel or queue or mapData then
                self:_StartTrackOnly(owner, text, binding, spellIdNum, remaining, span, now, timelineIdentity,
                    mapData, not (sequel or queue))
            end
            return
        end

        local effective = self:GetSpellExtension(spellIdNum)
        local effectiveBinding = self:_EffectiveBinding(binding, effective)

        local inst, predecessor = State.Start(self._state, owner, text, effectiveBinding, remaining, span, now, primaryAllowed)
        if not inst then
            dprint("Timer refused start: " .. tostring(predecessor))
            return
        end
        if predecessor then
            self:ReleaseInstancePresentations(predecessor, false)
        end
        self:_LinkShieldWatch(owner, text, spellIdNum, inst)
        inst.timelineIdentity = timelineIdentity
        if binding.canceledStop then State.RecordPublishedStage(inst, (DT._ReadProviderStage(owner))) end
        if self:_SuppressConcurrentRestarts(inst) then return end
        self._presentations[inst] = {}
        if binding.cueKey then
            self._cueInstances[owner] = self._cueInstances[owner] or {}
            self._cueInstances[owner][binding.cueKey] = inst
        end
        if effectiveBinding.ownsExpiry then self:_ArmOwnedExpiry(inst, now) end
        if mapData then self:_WindMapAttach(inst, mapData) end
        inst.receiptIcon = icon
        if State.GateCovers(self._forecastGates[owner], spellIdNum, now) then
            self._gateSuppressed[inst] = { silent = false }
            dprint("Timer gated text=" .. tostring(text))
            return
        end

        local extension = effectiveBinding.extension or 0
        local shownRemaining = remaining + (effectiveBinding.forecastLead or 0)
        local displayMode = self:GetSpellDisplay(spellIdNum)
        local displayText = self:GetSpellDisplayText(spellIdNum)
        local castDisplayText = self:GetSpellCastDisplayText(spellIdNum)
        dprint(string_format("Timer text=%s spellId=%s remaining=%.2f span=%.2f ext=%.2f primary=%s secondary=%s",
            tostring(text), tostring(spellIdNum), remaining, span, extension,
            tostring(primaryAllowed), tostring(secondaryAllowed)))

        if primaryAllowed then
            local record = { instance = inst, generation = inst.generation, role = "primary", shown = false }
            local frame = RenderPresentation(self, {}, record, shownRemaining, extension, displayMode,
                icon, displayText, spellIdNum, castDisplayText, false)
            if frame then self._presentations[inst].primary = frame end
        end
        if secondaryAllowed and secondary then
            local secRecord = { instance = inst, generation = inst.generation, role = "secondary", shown = false }
            local secFrame = RenderPresentation(self, {}, secRecord, shownRemaining, extension,
                secondary.display or "text", icon, secondary.displayText, spellIdNum, nil, true)
            if secFrame then self._presentations[inst].secondary = secFrame end
        end
        local presentations = self._presentations[inst]
        if inst.binding.castMatch and inst.state ~= "retired"
            and (inst.mapObserved or (presentations and (presentations.primary or presentations.secondary))) then
            self:_WatchCastMatch(inst)
        end
    elseif event == "BigWigs_StartBar" then
        -- Argument 10 (counting the message name) is a custom timeline bar's event
        -- ID; argument 9 is another field and is nil in that shape.
        if not self._activeEncounterId then return end
        local owner, key, text, time, _, isCooldown, _, otherEventId, timelineEventId = ...
        local now = GetTime()
        if not self:_ResolveOwnerMeta(owner) then
            State.PoisonStartBars(self._state, nil, now)
            return
        end
        local accepted = not (issecretvalue and (issecretvalue(key) or issecretvalue(text)
            or issecretvalue(time) or issecretvalue(isCooldown) or issecretvalue(otherEventId)
            or issecretvalue(timelineEventId)))
        accepted = accepted and otherEventId == nil and type(isCooldown) == "boolean"
        local outcome = State.NoteStartBar(self._state, owner, self._activeEncounterId, now, accepted,
            key, text, time, isCooldown, timelineEventId)
        dprint("StartBar evidence: " .. tostring(outcome))
    elseif event == "BigWigs_CastTimer" then
        -- No CastTimer binding is installed, so this always refuses; never routed through Timer's positions.
        local owner, key, time, _, text = ...
        -- A cast bar's StartBar never carries identity; taken first so it cannot reach a later receipt.
        local meta, ownerReason = self:_ResolveOwnerMeta(owner)
        State.TakeStartBar(self._state, meta and owner or nil, GetTime())
        if issecretvalue and (issecretvalue(key) or issecretvalue(time)
            or issecretvalue(text)) then
            return
        end
        if not meta then
            dprint("CastTimer refused owner: " .. tostring(ownerReason))
            return
        end
        local binding, bindReason = State.ResolveBinding(self._bindings, meta, self._activeEncounterId,
            "CastTimer", key, nil)
        if not binding then
            dprint("CastTimer refused binding: " .. tostring(bindReason))
            return
        end
    elseif event == "BigWigs_PauseBar" then
        local owner, text = ...
        if issecretvalue and issecretvalue(text) then return end
        local meta = self:_ResolveOwnerMeta(owner)
        if not meta then return end
        local now = GetTime()
        -- Pausing an exhausted clock would incorrectly extend its ending interval on resume.
        local pauseTarget = State.FindPublished(self._state, owner, text)
        if pauseTarget and pauseTarget.binding.cueKey then self:_ExpireTimerCue(pauseTarget, now) end
        local inst, changed = State.Pause(self._state, owner, text, now)
        if inst and changed then
            self:_OnSourcePauseChanged(inst, true, now)
        end
        local watch = self._shieldWatchByLabel[owner] and self._shieldWatchByLabel[owner][text]
        if watch then
            local watchChanged = State.PauseClock(watch.clock, now)
            if watchChanged == true then
                watch.armingHeld = self._shieldArming[watch.spellId]
                self._shieldArming[watch.spellId] = false
                PauseJobHandle(self, watch.armJob)
                PauseJobHandle(self, watch.disarmJob)
            end
        end
    elseif event == "BigWigs_ResumeBar" then
        local owner, text = ...
        if issecretvalue and issecretvalue(text) then return end
        local meta = self:_ResolveOwnerMeta(owner)
        if not meta then return end
        local now = GetTime()
        local inst, changed = State.Resume(self._state, owner, text, now)
        if inst and changed then
            self:_OnSourcePauseChanged(inst, false, now)
        end
        local watch = self._shieldWatchByLabel[owner] and self._shieldWatchByLabel[owner][text]
        if watch then
            local watchChanged = State.ResumeClock(watch.clock, now)
            if watchChanged == true then
                self._shieldArming[watch.spellId] = watch.armingHeld
                watch.armingHeld = nil
                ResumeJobHandle(self, watch.armJob, now)
                ResumeJobHandle(self, watch.disarmJob, now)
            end
        end
    elseif event == "BigWigs_StopBar" then
        local owner, text = ...
        if issecretvalue and issecretvalue(text) then return end
        local meta = self:_ResolveOwnerMeta(owner)
        if not meta then return end
        local now = GetTime()
        -- Clear the awaiting-stop entry before the no-instance return: a
        -- valid stop frees its label even when filtering or expiry already
        -- removed the instance.
        State.ResolveAwaitingStop(self._state, owner, text)
        -- An expired cue still owns the stop; do not fall back to an older same-label row.
        local inst, publishedCue = State.FindPublished(self._state, owner, text)
        if not inst then
            self:_ResolveShieldWatchOnStop(owner, text, nil, now)
            if publishedCue then self:_EndCueOccurrence(owner, publishedCue, text) end
            dprint(string_format("StopBar text=%s no instance at=%.3f", tostring(text), now))
            return
        end
        local wasPaused = inst.state == "paused"
        local forceDur = self:GetSpellForceDuration(inst.binding.curationId)
        local timelineState, eventId, stateReason, queueAllowance
        if inst.binding.anchor or inst.binding.castMatch then
            timelineState, eventId, stateReason, queueAllowance = self:_ReadTimelineState(inst)
        end
        local providerStage
        if inst.binding.canceledStop and timelineState == "canceled" then
            providerStage = DT._ReadProviderStage(owner)
        end
        local outcome = State.ClassifyStop(inst, now, forceDur, timelineState, queueAllowance, providerStage)
        local replacement = State.TakeTimerReplacement(self._state, inst, now, outcome, timelineState, eventId)
        if inst.mapObserved then self:_WindMapStop(inst, outcome, timelineState) end
        if inst.binding.castMatch then
            State.NoteCastMatchStop(inst, timelineState)
            if inst.castMatchClosed and inst.waitBound ~= nil then self:_EndCastWait(inst, now) end
        end
        dprint(string_format("StopBar text=%s outcome=%s event=%s state=%s wasPaused=%s at=%.3f elapsed=%.3f",
            tostring(text), tostring(outcome), tostring(eventId), tostring(timelineState or stateReason),
            tostring(wasPaused), now, now - inst.sourceClock.receivedAt))
        self:_ResolveShieldWatchOnStop(owner, text, outcome, now)
        if outcome == "ignore" then
            dprint("StopBar ignored (forceDuration self-drains or already anchored): " .. tostring(text))
        elseif outcome == "retire" then
            State.EndForecastWait(inst)
            State.Retire(self._state, inst)
            self:ReleaseInstancePresentations(inst, true, timelineState == "canceled")
        elseif outcome == "enter-legacy-cast" then
            local fill = State.BeginLegacyCast(inst, now, inst.binding.extension)
            self:_ApplyCastPhaseVisual(inst, fill)
        elseif outcome == "legacy-followup-and-retire" then
            if State.TakeFollowup(self._state, inst) then
                local presentations = self._presentations[inst]
                self:_SpawnPostCastBar(inst, presentations and presentations.primary)
            end
            State.Retire(self._state, inst)
            self:ReleaseInstancePresentations(inst, true)
        elseif outcome == "anchor" or outcome == "resume-and-anchor" then
            -- (a) the hold ends before any job can resume against the anchor;
            -- (b) a paused instance resumes in full (clock and state) at the
            -- stop instant, since the publisher never resumes a Finished bar;
            -- (c) anchor; (d) move job deadlines before resuming overdue work.
            self:_CancelHold(inst)
            if outcome == "resume-and-anchor" then
                State.Resume(self._state, owner, text, now)
            end
            local total, anchorReason = State.Anchor(inst, now, eventId)
            if total then
                self:_SuppressConcurrentRestarts(inst)
                dprint(string_format("anchor text=%s event=%s anchorElapsed=%.3f total=%.3f",
                    tostring(text), tostring(eventId), inst.anchorElapsed, total))
                if self._gateSuppressed[inst] then self:_RestoreGatedPresentation(inst, now) end
                self:_OnInstanceAnchored(inst, total, now)
                if outcome == "resume-and-anchor" then
                    self:_OnSourcePauseChanged(inst, false, now)
                end
                self:_ArmCastConfirm(inst, now)
                self:_BeginCastWait(inst, now)
                self:_EndCuesOnAnchor(inst)
                self:_ScheduleSequel(inst, now)
                self:_ApplyQueuedForecast(inst, now)
                -- A refused restore just retired the instance; a window opened now could
                -- never time out, because RunJob drops a retired instance's job.
                if DEBUG_DT2 and not inst.trackOnly and inst.state ~= "retired" then
                    self:_OpenObservationWindow(inst, now)
                end
            else
                dprint("anchor refused: " .. tostring(anchorReason))
            end
            -- The owned expiry was just canceled, so a tracking-only parent has
            -- nothing left to time once its Finished is resolved. An observed one
            -- keeps the retire job its anchor armed.
            if inst.trackOnly and not self._observedRetireJobs[inst] then
                State.Retire(self._state, inst)
                self:ReleaseInstancePresentations(inst, false)
            end
        elseif outcome == "keep-estimate" then
            self:_SuppressPendingShowSound(inst)
            State.EndForecastWait(inst)
        elseif outcome == "retain-canceled" then
            -- A canceled occurrence starts nothing an anchor would; its jobs keep their deadlines.
            State.RetainEstimate(inst, "canceled")
            self:_SuppressPendingShowSound(inst)
        elseif outcome == "retain-finished" then
            State.RetainEstimate(inst, "finished")
        end
        if replacement then self:_ReplayTimerReplacement(replacement) end
    elseif event == "BigWigs_StopBars" or event == "BigWigs_OnBossDisable" then
        local owner = ...
        local meta = self:_ResolveOwnerMeta(owner)
        if not meta then return end
        dprint("StopBars/OnBossDisable owner=" .. tostring(owner))
        local retired = State.RetireOwner(self._state, owner)
        for i = 1, #retired do
            self:ReleaseInstancePresentations(retired[i], false)
        end
        ReleaseOwnerWork(self, owner)
        self:_HideOwnerShieldBars(owner)
        if self._windMap then self:_WindMapOwnerStopped(owner) end
    elseif event == "BigWigs_Message" then
        local owner, key, message = ...
        if not IsMessagePayloadReadable(key, message) then return end
        local meta, ownerReason = self:_ResolveOwnerMeta(owner)
        if not meta then
            dprint("Message refused owner: " .. tostring(ownerReason))
            return
        end
        if self._shieldSwap and Swap.OnMessage(self._shieldSwap, key, GetTime()) then
            dprint("shield swap to=" .. tostring(self._shieldSwap.shielded))
            self:RefreshPhaseBars()
            self:_ShieldWarningUpdate()
        end
        local binding, bindReason = State.ResolveBinding(self._bindings, meta, self._activeEncounterId,
            "Message", key, nil)
        if not binding then
            dprint("Message refused binding: " .. tostring(bindReason))
            return
        end
        local scope, scopeReason = State.AdmitOwner(self._state, owner, self._activeEncounterId)
        if not scope then
            dprint("Message refused admission: " .. tostring(scopeReason))
            return
        end
        if binding.cueKey then
            self:_OnCueMessage(owner, binding, GetTime(), message)
        else
            self:_SpawnMessageBar(owner, binding, key, GetTime())
        end
    end
end
