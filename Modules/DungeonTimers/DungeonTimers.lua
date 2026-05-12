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

local ipairs = ipairs
local pairs = pairs
local tostring = tostring
local tonumber = tonumber
local string_format = string.format
local table_insert = table.insert
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

local DEBUG_DT2 = true

local BIGWIGS_EVENTS = {
    "BigWigs_Timer",
    "BigWigs_StopBar",
    "BigWigs_StopBars",
    "BigWigs_OnBossDisable",
    "BigWigs_Message",
}

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

local STOP_TOLERANCE = 0.5  -- seconds: StopBar within this window of cast-phase boundary = natural countdown expiry
local STALE_GRACE = 1.5     -- seconds: bar at 0 self-destructs after this if StopBar never arrives (boss phased out etc.)

-- Non-printable suffix on the secondary bar's key in self.bars so it never collides with a real BigWigs text.
local SECONDARY_KEY_SUFFIX = "\1S"
-- Suffix for post-cast bars (synthetic follow-up after a cast finishes naturally).
local POSTCAST_KEY_SUFFIX = "\1V"
-- Synthetic key prefix for shield bars (boss absorb-tracker bars, e.g. Vordaza
-- Necrotic Convergence). Independent of any BigWigs text key — we own the
-- lifecycle via UNIT_SPELLCAST_CHANNEL_START/STOP, not BigWigs_Timer.
local SHIELD_KEY_PREFIX = "__shield:"
local SHIELD_REFRESH_THROTTLE = 0.1  -- absorb-changed coalescing window
local function ShieldBarKey(spellId) return SHIELD_KEY_PREFIX .. tostring(spellId) end

-- M+ damage scaling for boss absorb shields.
-- shield max = baseAmount × LEVEL_MULTIPLIERS[keystoneLevel].
-- Sourced from ExBoss/EXDB. Levels above 35 clamp to [35]; level 0 (no
-- keystone) uses 1.0. Same table powered the standalone VordazaShield module
-- before it was folded into DungeonTimers' shieldBar schema field.
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

local function ResolveBossUnit()
    for i = 1, 5 do
        local unit = "boss" .. tostring(i)
        if UnitExists(unit) then return unit end
    end
    return nil
end

-- Secret-safe percentage formatter. AbbreviateNumbers with breakpointData
-- divides the secret absorb token by 1% of the max (significandDivisor =
-- maxNum / 100), returning the bucket as a numeric percentage like "67%".
-- Direct arithmetic on the secret value would crash; AbbreviateNumbers is
-- allowed-when-tainted in 12.0 and produces a non-secret string.
local function FormatShieldPercent(secretValue, maxNum)
    if secretValue == nil or not maxNum or maxNum <= 0 then return "" end
    if type(AbbreviateNumbers) ~= "function" then return "" end
    local ok, text = pcall(AbbreviateNumbers, secretValue, {
        breakpointData = {
            {
                breakpoint           = 0,
                abbreviation         = "%",
                significandDivisor   = maxNum / 100,
                fractionDivisor      = 1,
                abbreviationIsGlobal = false,
            },
        },
    })
    if ok and type(text) == "string" then return text end
    return ""
end

-- 30 = "always show decimals" for typical 0-30s bars. User-configured threshold of 1 would render "5 4 3 2 1 0.9 0.8".
local DECIMAL_THRESHOLD_DEFAULT = 30

local DEFAULT_BAR_COLOR = { 0.3, 0.5, 0.9 }
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
    ADDS         = "ADD",
    ["AIM BEAMS"] = "CLEAR",
    ["AOE + FEET"] = "FEET",
    BEAM         = "AMP",
    ["CC ADDS"]  = "ADD",
    CLEARS       = "CLEAR",
    DISPEL       = "CLEAR",
    DROPS        = "SPREAD",
    FIXATES      = "FRONTAL",
    HOOK         = "FRONTAL",
    INTERMISSION = "DANCE",
    KNOCK        = "PULL",
    LEAP         = "PULL",
    MARKS        = "FRONTAL",
    MINIGAME     = "DANCE",
    SPLIT        = "AMP",
    SUCC          = "AOE",
    TOTEMS        = "ADD",
    VULNERABILITY = "VULN",
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

-- Read-only by convention — mutating either would break the ResolveDisplayPreset closure.
DT.DISPLAY_PRESETS = DISPLAY_PRESETS
DT.DISPLAY_PRESET_ALIASES = DISPLAY_PRESET_ALIASES

DT.bars = {}
DT.barGroup = nil
DT.textGroup = nil
DT.spellLookup = nil

-- Phase tracker (HP%-driven) — mirrors ExBoss healthThresholds. Bars live in self.bars
-- with internal "_phase_<n>" keys so LayoutBars handles them naturally.
DT.activeEncounterID = nil
DT.phaseTicker = nil
local PHASE_TICK_SECONDS = 0.5

local function dprint(msg)
    if DEBUG_DT2 then
        KE:Print("[DT2] " .. tostring(msg))
    end
end

-- Preview bars loop endlessly so they're gated out to prevent sound spam.
local function PlayBarSound(self, key)
    if self.isPreview then return end
    if not self.spellId then return end
    if DT.db and DT.db.MutePresetSounds then return end
    local soundKey
    if key == "show" then
        soundKey = DT:GetEffectiveSpellSoundOnShow(self.spellId)
    elseif key == "hide" then
        soundKey = DT:GetEffectiveSpellSoundOnHide(self.spellId)
    end
    if not soundKey then return end
    local LSM = KE.LSM
    if not LSM then return end
    local file = LSM:Fetch("sound", soundKey)
    if file then
        local channel = (DT.db and DT.db.SoundChannel) or "Master"
        PlaySoundFile(file, channel)
    end
end

-- BigWigs appends " (N)" for repeating-cast uniqueness; keep it in self.bars keys but strip it from the rendered label.
local function StripBigWigsCounter(text)
    if not text then return text end
    return (text:gsub(" %(%d+%)$", ""))
end

function DT:BuildSpellLookup()
    local lookup = {}
    for _, enc in pairs(KE.EncounterData or {}) do
        if enc.spells then
            for spellId, spellData in pairs(enc.spells) do
                lookup[spellId] = spellData
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

-- Extension past BigWigs's countdown so the bar hits 0 at impact, not at cast-start.
-- castDuration always extends; channelDuration only when extendByChannel = true (effect lands
-- at end-of-channel rather than the typical start). User offset added on top, floored at 0.
function DT:GetSpellExtension(spellId)
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
function DT:GetEffectiveSpellSoundOnShow(spellId)
    if not spellId then return nil end
    local override = self:GetSpellSoundOnShow(spellId)
    if override == "None" then return nil end
    if override then return override end
    local spellData = self:GetSpellInfo(spellId)
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

-- Optional shield-tracker bar config (e.g. Vordaza Necrotic Convergence). When
-- present, DT spawns an absorb-percent bar on UNIT_SPELLCAST_CHANNEL_START for
-- the parent spellID. See _ShowShieldBar for lifecycle.
function DT:GetSpellShieldBar(spellId)
    local data = self:GetSpellInfo(spellId)
    return data and data.shieldBar or nil
end

-- Phantom-followup entries: GUI-visible spell entries that don't fire from
-- their own BigWigs_Timer (their LittleWigs aura trigger is unreliable in
-- 12.0). Instead they spawn when the *parent* spell's BigWigs_StopBar fires
-- naturally (countdown completed → cast finished → buff applied). Allows
-- the VULN bar to have its own color/displayText/disabled/font row in the
-- GUI while staying chained to the parent's lifecycle.
function DT:GetSpellPhantomFollowupOf(spellId)
    local data = self:GetSpellInfo(spellId)
    return data and tonumber(data.phantomFollowupOf) or nil
end

-- Returns array of plain-integer spell IDs whose `phantomFollowupOf` points
-- at parentSpellId. Called from _StopBarKey's natural-end branch.
function DT:_CollectPhantomFollowups(parentSpellId)
    if not parentSpellId then return nil end
    local lookup = self.spellLookup or self:BuildSpellLookup()
    local out
    for spellId, data in pairs(lookup) do
        if tonumber(data.phantomFollowupOf) == parentSpellId then
            out = out or {}
            out[#out + 1] = spellId
        end
    end
    return out
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

-- Filter OFF by default — db.RoleFilterEnabled=false makes everything pass.
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
    for _, enc in pairs(KE.EncounterData or {}) do
        if enc.dungeon == dungeonKey and enc.spells then
            for spellId in pairs(enc.spells) do
                self.db.SpellRoleOverrides[spellId] = nil
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
    return "text"  -- phase rules default to text mode (matches ExBoss central_medium semantics)
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

-- Below threshold = "%.1f" decimals; at/above = ceil whole seconds ("5" means "5+ left").
local function UpdateTimeString(self, displayedTime)
    local threshold = self.decimalThreshold or DECIMAL_THRESHOLD_DEFAULT
    local timerStr
    if displayedTime < threshold then
        timerStr = string_format("%.1f", displayedTime)
    else
        timerStr = string_format("%d", math.ceil(displayedTime))
    end
    if self.timerText then
        GatedSetText(self.timerText, self, "_lastTimerStr", timerStr)
    elseif self.label and self.baseText then
        GatedSetText(self.label, self, "_lastTimerStr",
            self.baseText .. " \194\187 " .. timerStr)
    end
end

-- Spawns the parent's `postCastBar` follow-up (Nysarra-style: fires at
-- cast-phase-end). Phantom followups are NOT spawned here — they fire at
-- parent's Timer arrival (in EventCallback's BigWigs_Timer branch) because
-- LittleWigs's `self:Bar()` for L'ura's Backlash is a duration bar (active
-- window), not a CDBar (predictive countdown). Spawning the VULN phantom at
-- StopBar would mean rendering it AFTER the vulnerability window has ended.
local function SpawnFollowups(self)
    if self.isPreview then return end
    if self.postCastBar then DT:_SpawnPostCastBar(self) end
end

local function BarOnUpdate(self)
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
                end
                self._lastValue = nil
                self._lastTimerStr = nil
                return
            end
            -- Cast phase ended at impact — fire hide sound BEFORE Hide() so the cue lands.
            -- Spawn follow-up bars here (postCastBar + phantomFollowupOf entries) on
            -- natural completion; cast interrupts go through StopBar's KillBar branch
            -- and skip this block.
            SpawnFollowups(self)
            PlayBarSound(self, "hide")
            self:SetScript("OnUpdate", nil)
            self:Hide()
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
                -- Spawn follow-up bars BEFORE destroying — BigWigs's StopBar
                -- typically trails the countdown's zero-crossing by a few frames
                -- (~80ms observed), so by the time _StopBarKey runs the bar is
                -- already gone from self.bars. This branch is the primary spawn
                -- path for extension=0 entries like L'ura's Backlash (1266001).
                SpawnFollowups(self)
                PlayBarSound(self, "hide")
                self:SetScript("OnUpdate", nil)
                self:Hide()
                DT.bars[self.text] = nil
                DT:LayoutBars()
                return
            elseif -remaining >= STALE_GRACE then
                -- StopBar never arrived (boss phased / interrupt) — self-destruct so we don't sit at 0 forever.
                dprint(string_format("BarOnUpdate %s → killed (stale grace, overdue=%.2f total=%.2f)",
                    self.text or "?", -remaining, self.totalDuration))
                PlayBarSound(self, "hide")
                self:SetScript("OnUpdate", nil)
                self:Hide()
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
    -- Secondary bars read secondary.color; primary bars read spell.color.
    local curatorColor
    if frame.spellId then
        if frame.isSecondary then
            local secondary = DT:GetSpellSecondary(frame.spellId)
            curatorColor = secondary and secondary.color or nil
        else
            curatorColor = DT:GetSpellCuratorColor(frame.spellId)
        end
    end
    frame.barColor = userColor or curatorColor or presetColor or DEFAULT_BAR_COLOR

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
    end

    -- Settings change always invalidates the gating caches so the next tick
    -- re-applies fonts/widths/strings unconditionally.
    frame._lastValue = nil
    frame._lastTimerStr = nil

    -- Font on label + timerText
    local face, size, outline
    if isBar then
        face = (barDisplay and barDisplay.fontFace) or "Expressway"
        size = (barDisplay and barDisplay.fontSize) or 12
        outline = (barDisplay and barDisplay.fontOutline) or "OUTLINE"
    else
        face = (textDisplay and textDisplay.fontFace) or "Expressway"
        size = (textDisplay and textDisplay.fontSize) or 14
        outline = (textDisplay and textDisplay.fontOutline) or "SOFTOUTLINE"
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
            if frame.label then frame.label:SetTextColor(c[1], c[2], c[3]) end
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
            frame.label:SetPoint("LEFT", frame.bar, "LEFT", 0, 0)
            frame.label:SetPoint("RIGHT", frame.bar, "RIGHT", 0, 0)
            frame.label:SetJustifyH(align)
            if frame.transitionText then
                frame.transitionText:ClearAllPoints()
                frame.transitionText:SetPoint("LEFT", frame.bar, "LEFT", 0, 0)
                frame.transitionText:SetPoint("RIGHT", frame.bar, "RIGHT", 0, 0)
                frame.transitionText:SetJustifyH(align)
            end
        end
    end
end

function DT:CreateBar(text, baseDuration, extension, displayMode, displayText, spellId, castDisplayText, isSecondary)
    displayMode = displayMode or "text"
    local isBar = (displayMode == "bar")
    local group = isBar and self:EnsureBarGroup() or self:EnsureTextGroup()

    -- 1 logical-unit = 1 physical pixel at any UI scale (literal 1 fuzzes at non-1x).
    local px = (KE.GetPixelSize and KE:GetPixelSize()) or 1

    local frame = CreateFrame("Frame", nil, group)
    frame.displayMode = displayMode

    if isBar then
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
        frame.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

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
    else
        -- Text mode: bar is a transparent FontString anchor.
        frame.bar = CreateFrame("StatusBar", nil, frame)
        frame.bar:SetAllPoints()
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

    -- Bar mode = separate label/timerText FontStrings; text mode = one combined "name » timer" label.
    frame.label = frame.bar:CreateFontString(nil, "OVERLAY")
    if isBar then
        frame.timerText = frame.bar:CreateFontString(nil, "OVERLAY")
    end

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
    -- Only the primary bar carries it — secondary bars are siblings, not parents.
    -- Suffix check prevents recursion: synthetic post-cast bars (text ends with
    -- POSTCAST_KEY_SUFFIX) inherit parent's spellId, so GetSpellPostCastBar would
    -- return the same config again. Guard so a postCastBar can't chain into itself
    -- if a future curator gives it its own castDuration. Shield bars (key prefix
    -- SHIELD_KEY_PREFIX) also share the parent spellId and must skip postCastBar.
    local isSyntheticPostCast = text and text:sub(-#POSTCAST_KEY_SUFFIX) == POSTCAST_KEY_SUFFIX
    local isSyntheticShield   = text and text:sub(1, #SHIELD_KEY_PREFIX) == SHIELD_KEY_PREFIX
    if not isSecondary and not isSyntheticPostCast and not isSyntheticShield then
        frame.postCastBar = DT:GetSpellPostCastBar(spellId)
    end

    ApplyVisualsToBar(frame)
    -- frame.text keeps BigWigs's raw string for StopBar key matching; baseText is the rendered label.
    frame.baseText = resolvedLabel or StripBigWigsCounter(text)
    if isBar then
        frame.label:SetText(frame.baseText)
    else
        -- Threshold-aware initial render so we don't flash "8.0" → "8" on the next tick.
        local initialThreshold = frame.decimalThreshold or DECIMAL_THRESHOLD_DEFAULT
        local initialStr
        if total < initialThreshold then
            initialStr = string_format("%.1f", total)
        else
            initialStr = string_format("%d", math.ceil(total))
        end
        frame.label:SetText(frame.baseText .. " \194\187 " .. initialStr)
    end

    frame:SetScript("OnUpdate", BarOnUpdate)
    return frame
end

function DT:LayoutBars()
    local barGroup = self:EnsureBarGroup()
    local textGroup = self:EnsureTextGroup()
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

local function CancelRevealTimer(self, bar)
    if bar.revealTimer then
        self:CancelTimer(bar.revealTimer)
        bar.revealTimer = nil
    end
end

function DT:RevealBar(key)
    local bar = self.bars[key]
    if not bar then return end
    bar.revealTimer = nil

    -- Tighten the bar's visual range so it appears full and drains over the showWindow,
    -- not as a sliver representing showWindow / total.
    if bar.bar and bar.showWindow and bar.showWindow > 0 then
        bar.bar:SetMinMaxValues(0, bar.showWindow)
        bar.bar:SetValue(bar.showWindow)
        bar._lastValue = nil
    end

    bar:Show()
    PlayBarSound(bar, "show")
    self:LayoutBars()
end

function DT:RenderBar(text, baseDur, extension, displayMode, iconID, displayText, spellId, castDisplayText, isSecondary)
    if not text or not baseDur or baseDur <= 0 then return end
    local existing = self.bars[text]
    if existing then
        CancelRevealTimer(self, existing)
        existing:SetScript("OnUpdate", nil)
        existing:Hide()
    end
    local bar = self:CreateBar(text, baseDur, extension, displayMode, displayText, spellId, castDisplayText, isSecondary)
    self._barSortCounter = self._barSortCounter + 1
    bar.sortIndex = self._barSortCounter
    self.bars[text] = bar

    if iconID and bar.icon then
        bar.icon:SetTexture(iconID)
    end

    -- Hide bars whose total lifetime exceeds ShowAtSeconds; reveal at total-showWindow
    -- so they're visible for exactly showWindow seconds (including cast extension).
    self:UpdateDB()
    local groupCfg = (displayMode == "bar") and (self.db and self.db.BarGroup)
                                            or (self.db and self.db.TextGroup)
    -- Synthetic follow-ups (postCastBar, phantom) always show immediately —
    -- their reveal window is rarely what the user wants for a follow-up, and
    -- a postCastBar inherits the parent's spellId so GetSpellShowAtSeconds
    -- would pull the wrong value.
    local isPostCastFollow = text and text:sub(-#POSTCAST_KEY_SUFFIX) == POSTCAST_KEY_SUFFIX
    local isPhantomFollow  = text and text:sub(1, 8) == "phantom:"
    local spellShowAt
    if isPostCastFollow or isPhantomFollow then
        spellShowAt = 0
    else
        spellShowAt = self:GetSpellShowAtSeconds(spellId)
    end
    local showWindow = spellShowAt or (groupCfg and groupCfg.ShowAtSeconds) or 0
    local total = baseDur + (extension or 0)
    if showWindow > 0 and total > showWindow then
        bar:Hide()
        bar.showWindow = showWindow
        local delay = total - showWindow
        bar.revealTimer = self:ScheduleTimer("RevealBar", delay, text)
    else
        -- Immediately visible — RevealBar handles the deferred case.
        PlayBarSound(bar, "show")
    end

    self:LayoutBars()
end

local function KillBar(self, text)
    local bar = self.bars[text]
    if not bar then return end
    CancelRevealTimer(self, bar)
    bar:SetScript("OnUpdate", nil)
    -- Skip hide-sound if the bar never reached visibility (still in showAt delay).
    if bar:IsShown() then
        PlayBarSound(bar, "hide")
    end
    bar:Hide()
    self.bars[text] = nil
    self:LayoutBars()
end

-- Spawns a `spawnOnMessage` bar in response to a BigWigs_Message firing for
-- the configured spellId. Used when SPELL_AURA_APPLIED for hostile-target
-- auras doesn't fire in 12.0 but LittleWigs still issues a Message() from a
-- non-aura trigger (widget update, boss emote, CLEU success). Example:
-- Crawth's goal-tracker widget 4183 hitting barValue=3 fires
-- Message(376448, "red") which we use as the VULN spawn signal.
-- `leadDelay` mirrors ExBoss's "prepare" phase — the visible bar starts
-- leadDelay seconds after the message arrives, matching the moment the
-- buff actually lands on the boss.
local function ResolveIconOverride(value, fallback)
    if not value then return fallback end
    if type(value) == "number" and C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(value) or value
    end
    return value
end

function DT:_SpawnMessageBar(spellId, key)
    if not spellId then return end
    local data = self:GetSpellInfo(spellId)
    if not (data and data.spawnOnMessage) then return end
    if self:IsSpellDisabled(spellId) then return end
    if not self:ShouldShowSpellRole(spellId) then return end

    local duration = tonumber(data.duration) or 0
    if duration <= 0 then return end
    local text = "msg:" .. tostring(spellId) .. ":" .. tostring(key or "")
    local iconTex = ResolveIconOverride(data.iconOverride, self:ResolveSpellIcon(spellId))

    local function spawn()
        self:RenderBar(text, duration, 0, data.display or "bar",
                       iconTex, data.displayText, spellId, nil, false)
    end

    local lead = tonumber(data.leadDelay) or 0
    if lead > 0 and C_Timer and C_Timer.After then
        dprint(string_format("MessageBar spawn spell=%d delayed=%.1f", spellId, lead))
        C_Timer.After(lead, spawn)
    else
        dprint(string_format("MessageBar spawn spell=%d", spellId))
        spawn()
    end
end

-- Spawns a parent bar's `postCastBar` follow-up. Shared by two trigger paths:
--   (a) BarOnUpdate cast-phase-end (parent has castDuration; runs after the
--       cast phase finishes naturally)
--   (b) _StopBarKey natural-countdown-end with extension=0 (parent has no
--       cast phase; LittleWigs's StopBar marks the cast finish moment — used
--       for predictive bars like L'ura's Backlash where the buff lands on
--       cast-end and SPELL_AURA_APPLIED is unreliable in 12.0)
-- Optional iconOverride on the postCastBar config takes precedence over the
-- parent's inherited icon; useful when the follow-up represents a different
-- visual cue (e.g. KNOCK icon → VULNERABILITY icon).
function DT:_SpawnPostCastBar(parent)
    if not parent or not parent.postCastBar then return end
    local pcfg = parent.postCastBar
    local parentIcon = parent.icon and parent.icon.GetTexture and parent.icon:GetTexture() or nil
    local iconTex = ResolveIconOverride(pcfg.iconOverride, parentIcon)
    self:RenderBar(
        (parent.text or "") .. POSTCAST_KEY_SUFFIX,
        tonumber(pcfg.duration) or 0, 0,
        pcfg.display or "bar", iconTex, pcfg.displayText,
        parent.spellId, nil, false)
end

-- Spawns a phantom-followup bar using the phantom entry's own spellId so
-- per-spell GUI overrides (color, displayText, disabled, font) on the phantom
-- entry apply correctly. Key format `phantom:<spellId>` is unique across the
-- session — a re-fire of the same phantom replaces the previous bar.
-- parentIconTex is the icon from BigWigs_Timer's payload, used as a fallback
-- when the phantom doesn't set iconOverride. Called at PARENT TIMER TIME
-- (start of the parent's bar) — for L'ura, that's the start of the
-- vulnerability window, which is when BigWigs's `self:Bar()` duration timer
-- fires (it's a duration bar, not a CDBar predictive countdown).
function DT:_SpawnPhantomFollowup(phantomSpellId, parentIconTex)
    if not phantomSpellId then return end
    local data = self:GetSpellInfo(phantomSpellId)
    if not data then return end
    if self:IsSpellDisabled(phantomSpellId) then return end
    if not self:ShouldShowSpellRole(phantomSpellId) then return end

    local duration = tonumber(data.duration) or 0
    if duration <= 0 then return end

    local iconTex = ResolveIconOverride(data.iconOverride, parentIconTex)
    local text = "phantom:" .. tostring(phantomSpellId)
    dprint(string_format("PhantomFollowup spawn spell=%d duration=%.1f", phantomSpellId, duration))
    self:RenderBar(text, duration, 0, data.display or "bar",
                   iconTex, data.displayText, phantomSpellId, nil, false)
end

function DT:StopBar(text)
    if not text then return end
    -- Stop both keys: secondary bars share lifetime with primary, so one BigWigs StopBar covers both.
    self:_StopBarKey(text)
    self:_StopBarKey(text .. SECONDARY_KEY_SUFFIX)
end

function DT:_StopBarKey(text)
    if not text then return end
    local bar = self.bars[text]
    if not bar then return end

    -- forceDuration bars self-drain to 0; ignore BigWigs's premature StopBar
    -- (e.g. LittleWigs Backlash StopBar at 12.5s when our forced duration is 20s).
    -- Mass-cleanup paths (BigWigs_StopBars, BigWigs_OnBossDisable) still tear them down via StopAllBars.
    if bar.spellId and self:GetSpellForceDuration(bar.spellId) then
        dprint("StopBar (forceDuration; ignored): " .. tostring(text))
        return
    end

    -- Cast-phase StopBar = mid-cast interrupt. Kill.
    if bar.phase == "cast" then
        dprint("StopBar (cast interrupt): " .. tostring(text))
        KillBar(self, text)
        return
    end

    -- elapsed >= base-tolerance → countdown finished naturally → cast-phase transition.
    -- elapsed < base-tolerance   → mid-countdown interrupt → kill.
    local elapsed = GetTime() - bar.startTime
    local extension = bar.extension or 0
    local naturalEnd = (elapsed >= bar.duration - STOP_TOLERANCE)

    if naturalEnd and extension > 0 then
        local currentValue = bar.totalDuration - elapsed
        if currentValue <= 0 then
            dprint(string_format("StopBar %s → killed (stale, elapsed=%.2f total=%.2f)",
                text, elapsed, bar.totalDuration))
            KillBar(self, text)
            return
        end
        bar.phase = "cast"
        bar.castStartTime = GetTime()
        bar.castFromValue = currentValue
        bar.castDuration = extension
        -- Opt-in cast-phase label/color swap (castDisplayText). Bar mode swaps fill;
        -- text mode swaps label color (label IS the visible cue).
        if bar.castDisplayTextRaw then
            local cc = bar.castColor or DEFAULT_BAR_COLOR
            bar.baseText = bar.castBaseText or bar.baseText
            if bar.displayMode == "bar" then
                if bar.bar then bar.bar:SetStatusBarColor(cc[1], cc[2], cc[3]) end
                if bar.label then bar.label:SetText(bar.baseText) end
            else
                if bar.label then bar.label:SetTextColor(cc[1], cc[2], cc[3]) end
                bar._lastTimerStr = nil  -- force re-composition next OnUpdate tick
            end
        end
        dprint(string_format("StopBar %s → cast phase (fromValue=%.2f late=%.2fs)",
            text, currentValue, elapsed - bar.duration))
    else
        -- Natural completion with no cast phase → spawn postCastBar follow-up
        -- before killing the parent (so it can inherit the icon if its own
        -- iconOverride isn't set). Phantom followups are NOT spawned here —
        -- they're tied to parent's Timer arrival (see EventCallback), since
        -- LittleWigs predictive bars are duration bars (active window), not
        -- countdowns to a future cast.
        if naturalEnd and extension <= 0 and bar.postCastBar and not bar.isPreview then
            dprint(string_format("StopBar %s → killed (natural, spawning postCastBar)", text))
            self:_SpawnPostCastBar(bar)
        else
            dprint(string_format("StopBar %s → killed (elapsed=%.2f base=%.2f ext=%.2f)",
                text, elapsed, bar.duration, extension))
        end
        KillBar(self, text)
    end
end

function DT:StopAllBars()
    for text, bar in pairs(self.bars) do
        -- Preview bars are GUI-lifecycle owned, not encounter-lifecycle.
        if not bar.isPreview then
            CancelRevealTimer(self, bar)
            bar:SetScript("OnUpdate", nil)
            bar:Hide()
            self.bars[text] = nil
        end
    end
    self:LayoutBars()
end

-- ╔══════════════════════════════════════════════════════════╗
-- ║  Phase tracker (HP%-driven)                              ║
-- ║  Mirrors ExBoss healthThresholds. While unit HP is in    ║
-- ║  (threshold, threshold + lead], shows a "Phase Transition║
-- ║  X%" bar that updates as the boss takes damage. Always   ║
-- ║  shown to everyone (no role filter).                     ║
-- ║                                                          ║
-- ║  Per-rule overrides (Disabled / Display / Color / Sounds ║
-- ║  / Lead) are stored on phase rule keys and resolved      ║
-- ║  through DT:GetPhase* helpers (see above).               ║
-- ╚══════════════════════════════════════════════════════════╝

local PHASE_BAR_ICON = 6013778  -- matches PHASE_ROW_ICON in the GUI list
local PHASE_TRANSITIONED_LABEL = "Phase Transitioned"  -- shown briefly after HP crosses threshold
-- HP percent below threshold during which the "Phase Transitioned" overlay stays
-- visible. Narrow band → brief flash (mirrors ExBoss's behavior). At typical M+
-- DPS, 1% HP burns through in ~1-3s. Wider (e.g. lead-mirroring 5%) would linger
-- for the entire post-phase damage window which the user found too long.
local PHASE_TRANSITIONED_BAND = 1

local function PlayPhaseSound(key, hookKey)
    if not (key and hookKey) then return end
    if DT.db and DT.db.MutePresetSounds then return end
    local soundKey
    if hookKey == "show" then
        soundKey = DT:GetEffectivePhaseSoundOnShow(key)
    elseif hookKey == "hide" then
        soundKey = DT:GetEffectivePhaseSoundOnHide(key)
    end
    if not soundKey then return end
    local LSM = KE.LSM
    if not LSM then return end
    local file = LSM:Fetch("sound", soundKey)
    if file then
        local channel = (DT.db and DT.db.SoundChannel) or "Master"
        PlaySoundFile(file, channel)
    end
end

local function CreatePhaseBar(self, key, sortIndex)
    local mode = self:GetPhaseDisplay(key)
    local isBar = (mode == "bar")
    local group = isBar and self:EnsureBarGroup() or self:EnsureTextGroup()

    local px = (KE.GetPixelSize and KE:GetPixelSize()) or 1

    local frame = CreateFrame("Frame", nil, group)
    frame.displayMode = mode
    frame.text = key
    frame.phaseKey = key
    frame.isPhaseBar = true
    frame.phase = "phase"  -- distinguishes from "countdown"/"cast"
    frame.sortIndex = sortIndex

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
        frame.bar:SetMinMaxValues(0, 1)
        frame.bar:SetValue(1)

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

    return frame
end

-- Called every tick during the encounter with four secret HP-curve outputs:
--   secretValue        — bar fill / countdown integer (0..lead)
--   secretCountdown    — alpha for the countdown elements (bar.bar)
--   secretTransitioned — alpha for the "Phase Transitioned" overlay
--   secretFrameAlpha   — outer frame alpha (union of countdown + transitioned bands)
-- The bar is created lazily and kept in self.bars for the encounter's duration —
-- visibility is driven by SetAlpha because we can't read the secret value in addon
-- code to make a Show/Hide choice. Layout slot is permanently reserved during the
-- encounter; SetAlpha=0 hides the frame visually but keeps its layout position.
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
        local sortIdx = 50 + (ruleIdx or 1)  -- 51,52,... below real bars (1000+) so phase bars sort to the top
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
    -- Preview bars are GUI-lifecycle (mirrors StopAllBars' isPreview skip) so
    -- ENCOUNTER_END doesn't clear a preview the user is currently editing.
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
-- confirmed via diagnostic 2026-05-11).
--
-- That means we CANNOT extract a clean integer tier in addon code — `==` and
-- ordered comparisons against secret numbers throw whenever execution is
-- tainted (and our addon IS tainted by the time the ticker fires, from
-- earlier secret-value flows). The shield-bar comment about "secret == 0"
-- was misleading: it only works in fresh untainted event handlers like
-- UNIT_ABSORB_AMOUNT_CHANGED's direct invocation.
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
        local disabled = self:IsPhaseDisabled(key)

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
    self:_HideAllPhaseBars()
end

-- ╔══════════════════════════════════════════════════════════╗
-- ║  Shield bars (boss absorb tracker)                       ║
-- ║  Spawns an absorb-percent bar on UNIT_SPELLCAST_CHANNEL_ ║
-- ║  START for spells with a `shieldBar` schema field. Used  ║
-- ║  for boss intermission shields (e.g. Vordaza's Necrotic  ║
-- ║  Convergence) where the team's progress through the      ║
-- ║  shield is the relevant cue. Reads the secret-value      ║
-- ║  UnitGetTotalAbsorbs token and passes it directly to     ║
-- ║  SetValue + AbbreviateNumbers (allowed-when-tainted).    ║
-- ║  Per-shield-bar state lives on the frame itself          ║
-- ║  (shieldUnit/shieldSpellId/shieldMax). Refresh timers    ║
-- ║  keyed by spellID in DT._shieldRefreshTimers.            ║
-- ╚══════════════════════════════════════════════════════════╝

DT._shieldRefreshTimers = DT._shieldRefreshTimers or {}
DT._absorbEventRegistered = false
-- Plain-number spell IDs in the active encounter that have shieldBar config.
-- Built at ENCOUNTER_START, cleared at ENCOUNTER_END. Iterated by the absorb
-- handler to decide whether a non-zero boss absorb should spawn/refresh a
-- shield bar. Storing the literals here means we never have to recover them
-- from a (potentially secret) cast event.
DT._activeShieldSpellIds = DT._activeShieldSpellIds or {}

-- Why we drive the shield bar off UNIT_ABSORB_AMOUNT_CHANGED only:
--   1. UNIT_SPELLCAST_CHANNEL_START's spellID is SECRET on hostile units in
--      12.0; using it as a table key crashes. ExBoss works around this with
--      RegisterUnitEvent + an ExBoss-engine-driven arming flag we don't have.
--   2. BigWigs_Timer for the same spellID is the wrong moment — LittleWigs
--      uses Blizzard's encounter timeline (ENCOUNTER_TIMELINE_EVENT_ADDED)
--      and CDBar to render a COUNTDOWN UNTIL the next intermission, then
--      StopBar when the countdown ends (= boss begins casting). Spawning on
--      Timer would land 70s early (before the shield exists) and StopBar
--      would kill the bar at the exact moment the shield goes up.
--   3. The absorb amount is the source of truth: zero → no shield, non-zero
--      → shield up. `secret == 0` returns a clean non-secret boolean (same
--      operation EbonMightHelper uses for spellID matching), so we can tell
--      "shield up" from "shield broken" without secret-key indexing.
-- Limitation: assumes one shieldBar entry per encounter — if multiple bosses
-- in one encounter ever each have an absorb shield we'd need to disambiguate
-- by unit. Not a current concern (Vordaza is the only shieldBar boss).

function DT:_ShowShieldBar(spellId, unit)
    if not (spellId and unit) then return end
    local cfg = self:GetSpellShieldBar(spellId)
    if not cfg then return end
    if self:IsSpellDisabled(spellId) then return end
    if not self:ShouldShowSpellRole(spellId) then return end

    local key = ShieldBarKey(spellId)
    local bar = self.bars[key]

    -- Visual primitives reuse CreateBar so font/texture/color/icon all flow
    -- through the same DT settings as a regular bar. baseDuration=1 is a
    -- throwaway — we cancel OnUpdate immediately and overwrite the StatusBar
    -- range in _RefreshShieldBar.
    if not bar then
        local label = cfg.displayText or "SHIELD"
        bar = self:CreateBar(key, 1, 0, "bar", label, spellId)
        bar:SetScript("OnUpdate", nil)
        bar.isShieldBar = true
        bar.shieldSpellId = spellId
        self._barSortCounter = self._barSortCounter + 1
        bar.sortIndex = self._barSortCounter
        self.bars[key] = bar
        if bar.icon then
            bar.icon:SetTexture(self:ResolveSpellIcon(spellId) or 134400)
        end
    end

    bar.shieldUnit = unit
    -- Recompute max on every spawn so M+ level changes between channels (rare,
    -- but possible if the keystone level changes via custom mode) take effect.
    bar.shieldMax = (tonumber(cfg.baseAmount) or 0) * GetShieldLevelMultiplier()
    if bar.shieldMax <= 0 then bar.shieldMax = 1 end
    bar.bar:SetMinMaxValues(0, bar.shieldMax)
    bar.bar:SetValue(bar.shieldMax)
    bar._lastValue = nil  -- invalidate gating cache so first SetValue takes
    if bar.timerText then
        bar.timerText:SetText("100%")
    end
    bar:Show()
    PlayBarSound(bar, "show")
    self:LayoutBars()
    self:_RefreshShieldBar(spellId)
end

function DT:_HideShieldBar(spellId)
    if not spellId then return end
    local timer = self._shieldRefreshTimers[spellId]
    if timer then
        self:CancelTimer(timer)
        self._shieldRefreshTimers[spellId] = nil
    end
    local key = ShieldBarKey(spellId)
    local bar = self.bars[key]
    if not bar then return end
    PlayBarSound(bar, "hide")
    bar:SetScript("OnUpdate", nil)
    bar:Hide()
    self.bars[key] = nil
    self:LayoutBars()
end

function DT:_RefreshShieldBar(spellId)
    if not spellId then return end
    self._shieldRefreshTimers[spellId] = nil
    local key = ShieldBarKey(spellId)
    local bar = self.bars[key]
    if not (bar and bar:IsShown()) then return end

    local unit = bar.shieldUnit
    if not unit or not UnitExists(unit) then
        unit = ResolveBossUnit()
        if not unit then return end
        bar.shieldUnit = unit
    end

    local absorbAmount = UnitGetTotalAbsorbs(unit)
    if absorbAmount == nil then return end

    -- Secret-safe SetValue — passing the secret token directly is allowed
    -- by Blizzard. GatedSetValue would also work but its cached delta check
    -- is unsafe with secret values (equality on secrets = taint), so call
    -- SetValue directly here.
    bar.bar:SetValue(absorbAmount)
    if bar.timerText then
        bar.timerText:SetText(FormatShieldPercent(absorbAmount, bar.shieldMax))
    end
end

function DT:_ScheduleShieldRefresh(spellId)
    if not spellId then return end
    if self._shieldRefreshTimers[spellId] then return end
    self._shieldRefreshTimers[spellId] = self:ScheduleTimer("_RefreshShieldBar", SHIELD_REFRESH_THROTTLE, spellId)
end

function DT:_HideAllShieldBars()
    for spellId in pairs(self._shieldRefreshTimers) do
        local timer = self._shieldRefreshTimers[spellId]
        if timer then self:CancelTimer(timer) end
        self._shieldRefreshTimers[spellId] = nil
    end
    local changed = false
    for k, bar in pairs(self.bars) do
        if bar.isShieldBar then
            bar:SetScript("OnUpdate", nil)
            bar:Hide()
            self.bars[k] = nil
            changed = true
        end
    end
    if changed then self:LayoutBars() end
end

-- Drives the entire shield-bar lifecycle. UNIT_ABSORB_AMOUNT_CHANGED fires for
-- bossN whenever the unit's total absorb changes (shield applied, drained,
-- consumed). For each shieldBar entry in the active encounter:
--   absorb == 0 → kill bar if it exists (shield broken or never spawned)
--   absorb non-zero → spawn the bar if missing, otherwise refresh it
-- Comparing the secret absorb token to the literal 0 returns a clean
-- non-secret boolean (allowed-when-tainted). Only the LITERAL spellId from
-- _activeShieldSpellIds is used for any table indexing.
function DT:OnUnitAbsorbAmountChanged(_, unit)
    if type(unit) ~= "string" or not unit:match("^boss%d$") then return end
    if #self._activeShieldSpellIds == 0 then return end

    local absorb = UnitGetTotalAbsorbs(unit)
    if absorb == nil then return end
    local isZero = (absorb == 0)

    for i = 1, #self._activeShieldSpellIds do
        local spellId = self._activeShieldSpellIds[i]
        local key = ShieldBarKey(spellId)
        local existing = self.bars[key]
        if isZero then
            if existing then self:_HideShieldBar(spellId) end
        else
            if not existing then
                self:_ShowShieldBar(spellId, unit)
            else
                if existing.shieldUnit ~= unit then existing.shieldUnit = unit end
                self:_ScheduleShieldRefresh(spellId)
            end
        end
    end
end

-- Collects the plain-integer spell IDs in the encounter that have shieldBar
-- config. Keys of EncounterData[id].spells are integers from source.
function DT:_CollectShieldSpellIds(encounterID)
    local out = {}
    local enc = encounterID and KE.EncounterData and KE.EncounterData[encounterID]
    if not (enc and enc.spells) then return out end
    for spellId, spell in pairs(enc.spells) do
        if spell.shieldBar then out[#out + 1] = spellId end
    end
    return out
end

function DT:_RegisterAbsorbEvent()
    if self._absorbEventRegistered then return end
    self:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED", "OnUnitAbsorbAmountChanged")
    self._absorbEventRegistered = true
    dprint("ShieldBar absorb event registered")
end

function DT:_UnregisterAbsorbEvent()
    if not self._absorbEventRegistered then return end
    self:UnregisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
    self._absorbEventRegistered = false
    dprint("ShieldBar absorb event unregistered")
end

function DT:OnEncounterStart(_, encounterID)
    local id = tonumber(encounterID)
    self:StartPhaseTracking(id)
    self._activeShieldSpellIds = self:_CollectShieldSpellIds(id)
    if id and #self._activeShieldSpellIds > 0 then
        self:_RegisterAbsorbEvent()
    end
end

function DT:OnEncounterEnd()
    self:StopPhaseTracking()
    self:_UnregisterAbsorbEvent()
    self:_HideAllShieldBars()
    self._activeShieldSpellIds = {}
end

-- Settings preview bars/texts: looping fake bars for live feedback while editing GUI panels.
local PREVIEW_BAR_KEYS = { "__preview_bar_1", "__preview_bar_2", "__preview_bar_3" }
local PREVIEW_TEXT_KEYS = { "__preview_text_1", "__preview_text_2", "__preview_text_3" }
local PREVIEW_BAR_LABELS = { "Sample Timer A", "Sample Timer B", "Sample Timer C" }
local PREVIEW_TEXT_LABELS = { "Sample Text A", "Sample Text B", "Sample Text C" }
local PREVIEW_DURATIONS = { 8, 12, 16 }
local PREVIEW_ICON_IDS = { 136116, 136048, 132288 }

DT.previewBarShown = false
DT.previewTextShown = false

-- Soft-outline shadows are siblings of the main FontString (not its children), so
-- bar:Hide() doesn't take them down via inheritance the way you'd expect — they
-- linger as ghosts on screen until SetShown(false) is called explicitly. Touch
-- every FontString slot a phase / cast / regular bar can carry so this helper is
-- a safe drop-in for any bar lifecycle path.
local function HideBarSoftOutlines(bar)
    if not bar then return end
    if bar.label and bar.label.softOutline then bar.label.softOutline:SetShown(false) end
    if bar.timerText and bar.timerText.softOutline then bar.timerText.softOutline:SetShown(false) end
    if bar.transitionText and bar.transitionText.softOutline then bar.transitionText.softOutline:SetShown(false) end
end

local function CreatePreviewBar(self, key, label, duration, displayMode, iconID, sortIndex)
    local existing = self.bars[key]
    if existing then
        existing:SetScript("OnUpdate", nil)
        HideBarSoftOutlines(existing)
        existing:Hide()
    end
    local bar = self:CreateBar(label, duration, 0, displayMode)
    bar.isPreview = true
    bar.loop = true
    bar.sortIndex = sortIndex
    -- CreateBar uses `text` as the dict key. Override so our preview keys
    -- don't collide with a real BigWigs bar literally named "Sample Timer A".
    bar.text = key
    if iconID and bar.icon then
        bar.icon:SetTexture(iconID)
    end
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
            bar:SetScript("OnUpdate", nil)
            HideBarSoftOutlines(bar)
            bar:Hide()
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
        CreatePreviewBar(self, key, PREVIEW_TEXT_LABELS[i], PREVIEW_DURATIONS[i], "text", nil, i)
    end
    self:LayoutBars()
end

function DT:HideSettingsTextPreviews()
    if not self.previewTextShown then return end
    self.previewTextShown = false
    for _, key in ipairs(PREVIEW_TEXT_KEYS) do
        local bar = self.bars[key]
        if bar then
            bar:SetScript("OnUpdate", nil)
            HideBarSoftOutlines(bar)
            bar:Hide()
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

    local label = data.name or string_format("Spell %d", spellId)

    -- Preview chain MUST mirror RenderBar's (override → curator → group default → 0)
    -- so what the user sees here matches what they'll see in-fight.
    local groupKey = (displayMode == "bar") and "BarGroup" or "TextGroup"
    local groupCfg = self.db and self.db[groupKey]
    local groupDefault = (groupCfg and groupCfg.ShowAtSeconds) or 0
    local effectiveShowAt = self:GetSpellShowAtSeconds(spellId) or groupDefault
    -- forceDuration / spawnOnMessage / phantomFollowupOf spells all use a
    -- curated duration field for the preview so what the user sees here
    -- matches what they'll see in-fight, not the generic 8s preview-base
    -- or a reveal-window slice.
    local forceDur = self:GetSpellForceDuration(spellId)
    local curatedDur
    if (data.spawnOnMessage or data.phantomFollowupOf) and data.duration then
        curatedDur = tonumber(data.duration)
    end
    local baseDuration
    if forceDur then
        baseDuration = forceDur
    elseif curatedDur then
        baseDuration = curatedDur
    elseif effectiveShowAt > 0 then
        baseDuration = math.max(1, effectiveShowAt - extension)
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
        if bar.revealTimer then
            self:CancelTimer(bar.revealTimer)
            bar.revealTimer = nil
        end
        bar:SetScript("OnUpdate", nil)
        HideBarSoftOutlines(bar)
        bar:Hide()
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
    -- We pass the real key to CreatePhaseBar so color/display-mode helpers
    -- resolve correctly, but we re-key it under PHASE_PREVIEW_KEY in
    -- self.bars so a real in-fight phase bar can coexist (e.g. testing
    -- on a target dummy with active encounter).
    local bar = CreatePhaseBar(self, key, 1)  -- sortIndex 1 → top of layout
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
        HideBarSoftOutlines(bar)
        bar:Hide()
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

function DT:OnInitialize()
    -- db must be populated BEFORE KitnEssentials:OnEnable's auto-enable loop checks module.db.Enabled.
    self:UpdateDB()
    self:SetEnabledState(false)
end

function DT:OnEnable()
    dprint("OnEnable")
    self:UpdateDB()
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
    else
        dprint("BigWigsLoader missing — event registration skipped")
    end

    if LibSpec then
        LibSpec.RegisterGroup(self, function(...) DT:OnLibSpecGroupUpdate(...) end)
        dprint("LibSpec registered")
    else
        dprint("LibSpec missing — role filter degraded to always-DAMAGER")
    end

    -- Phase tracker (HP%-driven, mirrors ExBoss healthThresholds).
    self:RegisterEvent("ENCOUNTER_START", "OnEncounterStart")
    self:RegisterEvent("ENCOUNTER_END",   "OnEncounterEnd")
end

function DT:OnDisable()
    dprint("OnDisable")
    if BigWigsLoader then
        for _, event in ipairs(BIGWIGS_EVENTS) do
            BigWigsLoader.UnregisterMessage(self, event)
        end
    end
    if LibSpec then
        LibSpec.UnregisterGroup(self)
    end
    self:UnregisterEvent("ENCOUNTER_START")
    self:UnregisterEvent("ENCOUNTER_END")
    self:_UnregisterAbsorbEvent()
    self:_HideAllShieldBars()
    self:StopPhaseTracking()
end

function DT:EventCallback(event, ...)
    if event == "BigWigs_Timer" then
        local addon, spellId, duration, _, text, count, icon = ...
        local baseDur = tonumber(duration) or 0
        local spellIdNum = tonumber(spellId)

        -- Curated-only gate: BigWigs's own bars handle uncurated content; we don't double up.
        local spellData = self:GetSpellInfo(spellIdNum)
        if not spellData then
            return
        end

        -- spawnOnMessage entries opt out of the BigWigs_Timer path entirely —
        -- they're driven by BigWigs_Message below. LittleWigs may still fire a
        -- Timer for the same spellId from a fallback handler we don't want to
        -- react to (e.g. Crawth's FirestormApplied which doesn't fire in 12.0
        -- but exists in source).
        if spellData.spawnOnMessage then
            return
        end

        -- phantomFollowupOf entries opt out of the Timer path for their own
        -- spellId — they spawn as a side-effect of their PARENT's Timer (see
        -- below). LittleWigs may also fire a Timer for the phantom's own
        -- spellId from a fallback handler (e.g. SPELL_AURA_APPLIED) which we
        -- want to ignore to avoid double-rendering.
        if spellData.phantomFollowupOf then
            return
        end

        -- Phantom-followup spawn: separate GUI-configurable spell entries that
        -- share the parent's Timer lifecycle. Fires BEFORE the parent's own
        -- disabled/role gates so the user can disable the parent (KNOCK) while
        -- keeping the phantom (VULN) visible, or vice versa.
        do
            local phantoms = self:_CollectPhantomFollowups(spellIdNum)
            if phantoms then
                for i = 1, #phantoms do
                    self:_SpawnPhantomFollowup(phantoms[i], icon)
                end
            end
        end

        -- forceDuration override: replace BigWigs's reported duration with a curated one
        -- (e.g. Backlash's actual buff is 20s but LittleWigs hardcodes 12.5s). Bar will
        -- self-drain; _StopBarKey ignores BigWigs StopBar for these spells.
        local forceDur = self:GetSpellForceDuration(spellIdNum)
        if forceDur then baseDur = forceDur end

        -- iconOverride: swap BigWigs's icon for a curated texture (e.g. a more
        -- recognizable icon than the default spell texture).
        local iconOverride = self:GetSpellIconOverride(spellIdNum)
        if iconOverride then icon = iconOverride end

        if self:IsSpellDisabled(spellIdNum) then
            dprint(string_format("Timer FILTERED text=%s reason=disabled player=%s",
                tostring(text), tostring(self.playerRole)))
            return
        end

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
            dprint(string_format("Timer FILTERED text=%s reason=role role=%s secRole=%s player=%s",
                tostring(text),
                tostring(self:GetSpellRole(spellIdNum)),
                tostring(secondary and secondary.role),
                tostring(self.playerRole)))
            return
        end

        local ext = self:GetSpellExtension(spellIdNum)
        local total = baseDur + ext
        local displayMode = self:GetSpellDisplay(spellIdNum)
        local displayText = self:GetSpellDisplayText(spellIdNum)
        local castDisplayText = self:GetSpellCastDisplayText(spellIdNum)
        dprint(string_format("Timer text=%s spellId=%s base=%.2f ext=%.2f total=%.2f display=%s label=%s castLabel=%s mod=%s count=%s icon=%s primary=%s secondary=%s",
            tostring(text),
            tostring(spellId),
            baseDur,
            ext,
            total,
            displayMode,
            tostring(displayText),
            tostring(castDisplayText),
            tostring(addon and addon.moduleName or addon),
            tostring(count),
            tostring(icon),
            tostring(primaryAllowed),
            tostring(secondaryAllowed)))

        if primaryAllowed then
            self:RenderBar(text, baseDur, ext, displayMode, icon, displayText, spellIdNum, castDisplayText, false)
        end
        if secondaryAllowed and secondary then
            local secText = secondary.displayText
            local secMode = secondary.display or "text"
            self:RenderBar(text .. SECONDARY_KEY_SUFFIX, baseDur, ext, secMode, icon, secText, spellIdNum, nil, true)
        end
    elseif event == "BigWigs_Message" then
        -- Payload: (addon, key, color, text, icon, sound)
        -- key is a plain spell ID (LittleWigs/BigWigs serialize them as ints)
        -- for spell-keyed messages; can also be a string for custom options.
        local _, key = ...
        local spellIdNum = tonumber(key)
        if spellIdNum then
            self:_SpawnMessageBar(spellIdNum, key)
        end
    elseif event == "BigWigs_StopBar" then
        local _, text = ...
        dprint("StopBar text=" .. tostring(text))
        self:StopBar(text)
    elseif event == "BigWigs_StopBars" then
        local addon = ...
        dprint("StopBars mod=" .. tostring(addon and addon.moduleName or addon))
        self:StopAllBars()
        self:_HideAllShieldBars()
    elseif event == "BigWigs_OnBossDisable" then
        local addon = ...
        dprint("OnBossDisable mod=" .. tostring(addon and addon.moduleName or addon))
        self:StopAllBars()
        self:_HideAllShieldBars()
    end
end
