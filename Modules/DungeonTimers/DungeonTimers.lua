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

local DEBUG_DT2 = true

local BIGWIGS_EVENTS = {
    "BigWigs_Timer",
    "BigWigs_StopBar",
    "BigWigs_StopBars",
    "BigWigs_OnBossDisable",
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
}

-- Color-only aliases. The original text is preserved; only the color is borrowed from the aliased preset.
local DISPLAY_PRESET_ALIASES = {
    ADDS         = "ADD",
    ["AIM BEAMS"] = "CLEAR",
    ["AOE + FEET"] = "FEET",
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
    SUCC         = "AOE",
    TOTEMS       = "ADD",
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

local function dprint(msg)
    if DEBUG_DT2 then
        KE:Print("[DT2] " .. tostring(msg))
    end
end

-- Preview bars loop endlessly so they're gated out to prevent sound spam.
local function PlayBarSound(self, key)
    if self.isPreview then return end
    if not self.spellId then return end
    local soundKey
    if key == "show" then
        soundKey = DT:GetSpellSoundOnShow(self.spellId)
    elseif key == "hide" then
        soundKey = DT:GetSpellSoundOnHide(self.spellId)
    end
    if not soundKey or soundKey == "" or soundKey == "None" then return end
    local LSM = KE.LSM
    if not LSM then return end
    local file = LSM:Fetch("sound", soundKey)
    if file then
        PlaySoundFile(file, "Master")
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

-- Per-spell sound on bar show. Returns LSM sound key or nil. "None"
-- and empty string also mean "no sound" — the setter prunes them so
-- only meaningful values are stored.
function DT:GetSpellSoundOnShow(spellId)
    if not (self.db and self.db.SpellSoundsOnShow and spellId) then return nil end
    return self.db.SpellSoundsOnShow[spellId]
end

function DT:SetSpellSoundOnShow(spellId, soundKey)
    if not (self.db and spellId) then return end
    self.db.SpellSoundsOnShow = self.db.SpellSoundsOnShow or {}
    if not soundKey or soundKey == "" or soundKey == "None" then
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
    if not soundKey or soundKey == "" or soundKey == "None" then
        self.db.SpellSoundsOnHide[spellId] = nil
    else
        self.db.SpellSoundsOnHide[spellId] = soundKey
    end
end

function DT:HasSpellSound(spellId)
    return self:GetSpellSoundOnShow(spellId) ~= nil
        or self:GetSpellSoundOnHide(spellId) ~= nil
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

function DT:UpdateDB()
    if not (KE.db and KE.db.profile) then return end
    -- AceDB defaults don't deep-fill nested sub-tables when their parent already exists in saved data —
    -- backfill manually on first sight so Dungeons.DungeonTimers picks up its defaults.
    if not (KE.db.profile.Dungeons and KE.db.profile.Dungeons.DungeonTimers) then
        if KE.FillProfileDefaults then
            KE:FillProfileDefaults()
        end
    end
    self.db = KE.db.profile.Dungeons and KE.db.profile.Dungeons.DungeonTimers
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
    local userColor = frame.spellId and DT:GetSpellColorOverride(frame.spellId) or nil
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

    -- Bar mode = white over colored fill. Text mode = label IS the colored cue.
    if frame.phase ~= "cast" then
        local c = frame.barColor or DEFAULT_BAR_COLOR
        if isBar then
            if frame.label then frame.label:SetTextColor(1, 1, 1) end
            if frame.timerText then frame.timerText:SetTextColor(1, 1, 1) end
        else
            if frame.label then frame.label:SetTextColor(c[1], c[2], c[3]) end
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
        else
            local align = (textDisplay and textDisplay.textAlign) or "CENTER"
            frame.label:SetPoint("LEFT", frame.bar, "LEFT", 0, 0)
            frame.label:SetPoint("RIGHT", frame.bar, "RIGHT", 0, 0)
            frame.label:SetJustifyH(align)
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
    local spellShowAt = self:GetSpellShowAtSeconds(spellId)
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

    if elapsed >= bar.duration - STOP_TOLERANCE and extension > 0 then
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
        dprint(string_format("StopBar %s → killed (elapsed=%.2f base=%.2f ext=%.2f)",
            text, elapsed, bar.duration, extension))
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

-- Settings preview bars/texts: looping fake bars for live feedback while editing GUI panels.
local PREVIEW_BAR_KEYS = { "__preview_bar_1", "__preview_bar_2", "__preview_bar_3" }
local PREVIEW_TEXT_KEYS = { "__preview_text_1", "__preview_text_2", "__preview_text_3" }
local PREVIEW_BAR_LABELS = { "Sample Timer A", "Sample Timer B", "Sample Timer C" }
local PREVIEW_TEXT_LABELS = { "Sample Text A", "Sample Text B", "Sample Text C" }
local PREVIEW_DURATIONS = { 8, 12, 16 }
local PREVIEW_ICON_IDS = { 136116, 136048, 132288 }

DT.previewBarShown = false
DT.previewTextShown = false

local function CreatePreviewBar(self, key, label, duration, displayMode, iconID, sortIndex)
    local existing = self.bars[key]
    if existing then
        existing:SetScript("OnUpdate", nil)
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
    local baseDuration
    if effectiveShowAt > 0 then
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
        local tex = (C_Spell and C_Spell.GetSpellTexture
                     and C_Spell.GetSpellTexture(spellId))
                    or 134400
        bar.icon:SetTexture(tex)
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
end

function DT:EventCallback(event, ...)
    if event == "BigWigs_Timer" then
        local addon, spellId, duration, _, text, count, icon = ...
        local baseDur = tonumber(duration) or 0
        local spellIdNum = tonumber(spellId)

        -- Curated-only gate: BigWigs's own bars handle uncurated content; we don't double up.
        if not self:GetSpellInfo(spellIdNum) then
            return
        end

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
    elseif event == "BigWigs_StopBar" then
        local _, text = ...
        dprint("StopBar text=" .. tostring(text))
        self:StopBar(text)
    elseif event == "BigWigs_StopBars" then
        local addon = ...
        dprint("StopBars mod=" .. tostring(addon and addon.moduleName or addon))
        self:StopAllBars()
    elseif event == "BigWigs_OnBossDisable" then
        local addon = ...
        dprint("OnBossDisable mod=" .. tostring(addon and addon.moduleName or addon))
        self:StopAllBars()
    end
end
