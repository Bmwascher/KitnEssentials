-- ╔══════════════════════════════════════════════════════════╗
-- ║  DungeonTimers.lua                                       ║
-- ║  Module: Dungeon Timers (curated)                        ║
-- ║  Purpose: Layers curated castDuration data on top of     ║
-- ║           BigWigs's BigWigs_Timer events. Encounter data ║
-- ║           lives in EncounterData.lua (EXBoss-style hand- ║
-- ║           curated table keyed by encounterID/spellID).   ║
-- ║                                                          ║
-- ║  Created 2026-05-04 alongside the rename of the old      ║
-- ║  DungeonTimers module to "BigWigsTimers". The two coexist║
-- ║  during the rebuild — this module is off-by-default.     ║
-- ║                                                          ║
-- ║  N10 added the GUI integration: bar/text settings now    ║
-- ║  flow through KE.db.profile.Dungeons.DungeonTimers.      ║
-- ║  ApplySettings re-applies visuals to live bars in place. ║
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

-- LibSpec: same library KickTracker uses for party-spec tracking. Here we
-- only need the player's own role ("TANK" / "HEALER" / "DAMAGER"), but
-- registering via RegisterGroup is the project-standard pattern and gives
-- us automatic refresh on spec change without wiring up
-- PLAYER_SPECIALIZATION_CHANGED / ACTIVE_COMBAT_CONFIG_CHANGED ourselves.
-- Optional load — module degrades to "no role filter" if absent.
local LibSpec = LibStub("LibSpecialization", true)

-- Spell.role → which player roles see this bar.
-- tank/heal-tagged bars are role-specific (only that role); mechanic/other
-- show for everyone since they're class-agnostic dodge/positioning cues.
-- Spells with no role tag (uncurated) always show — fail open.
local ROLE_ALLOW_LIST = {
    TANK    = { tank = true,             mechanic = true, other = true },
    HEALER  = {             heal = true, mechanic = true, other = true },
    DAMAGER = {                          mechanic = true, other = true },
}

-- Fallback hardcoded sizes used only when DB hasn't been resolved yet (very
-- early init). Live values come from db.BarDisplay / db.TextDisplay.
local FALLBACK_BAR_WIDTH = 250
local FALLBACK_BAR_HEIGHT = 22
local FALLBACK_TEXT_HEIGHT = 22

local STOP_TOLERANCE = 0.5  -- seconds: StopBar within this window of the cast-phase boundary is treated as natural countdown expiry
local STALE_GRACE = 1.5     -- seconds: extension-bearing bar at 0 self-destructs if StopBar hasn't arrived within this window (boss phased out, BigWigs missed StopBar, etc.)

-- Decimal threshold default. Below this remaining time, the timer text
-- shows one decimal place ("0.8"); at or above, whole seconds ("5").
-- 30 effectively means "always show decimals" for typical bar lifetimes
-- (BigWigs timers are usually 0–30s) — preserves the pre-knob behavior.
-- A user-configured threshold of 1, for example, would render "5 4 3 2
-- 1 0.9 0.8 0.7" — clean integers above 1s, fine grain in the last
-- second.
local DECIMAL_THRESHOLD_DEFAULT = 30

-- Curated display presets — same keys + colors as BigWigsTimers
-- DISPLAY_PRESETS so users get consistent UX across both modules. A spell
-- whose `displayText = "DODGE"` (etc.) gets the matching label AND color.
-- Custom strings render as-is with the default base color.
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

-- Color-only aliases for common variants of a preset name. The user's
-- ORIGINAL text is preserved as the rendered label so "ADDS" renders
-- "ADDS" (not canonicalized to "ADD") — only the color is borrowed from
-- the aliased preset so plural-add mechanics group visually with single-
-- add ones. Add new aliases here as they come up.
local DISPLAY_PRESET_ALIASES = {
    ADDS         = "ADD",
    CLEARS       = "CLEAR",
    DISPEL       = "CLEAR",
    DROPS        = "SPREAD",
    HOOK         = "FRONTAL",
    INTERMISSION = "DANCE",
    LEAP         = "PULL",
    MARKS        = "FRONTAL",
    SPLIT        = "AMP",
    TOTEMS       = "ADD",
}

-- Lookup helper: returns the preset table entry for a string by matching
-- against keys then labels (case-insensitive both ways). Returns nil for
-- custom strings. The setter uses this for equivalence-pruning ("dodge"
-- and "DODGE" resolve to the same preset → both equivalent to a
-- curated "DODGE" → no override needed). Cheap: at most one hash lookup
-- + one 13-entry scan, on user-write only.
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

-- Resolve a displayText value to (label, color):
--   nil           → nil label (CreateBar falls back to BigWigs spell name),
--                   default color
--   preset key    → preset label + preset color (e.g. "TANK" → "TANK HIT")
--   preset label  → preset label + preset color (e.g. "TANK HIT" → same)
--   alias key     → user's ORIGINAL text + aliased preset's color (e.g.
--                   "ADDS" → label "ADDS", color of ADD preset)
--   custom string → string as label, default color
--
-- Case-insensitive match against both keys and labels — humans don't
-- always type in caps. Typing "dodge" / "Dodge" / "DODGE" all pick up
-- the orange preset, and the rendered label is the preset's canonical
-- form ("DODGE", uppercase) regardless of input casing. Custom strings
-- preserve their casing in the rendered output.
local function ResolveDisplayPreset(displayText)
    if not displayText then return nil, DEFAULT_BAR_COLOR end
    local preset = ResolvePresetByText(displayText)
    if preset then return preset.label, preset.color end
    -- Alias check — match "ADDS" / "Adds" / "adds" to the ADD preset's
    -- color while keeping the user's text as the rendered label.
    local aliasKey = DISPLAY_PRESET_ALIASES[displayText:upper()]
    if aliasKey and DISPLAY_PRESETS[aliasKey] then
        return displayText, DISPLAY_PRESETS[aliasKey].color
    end
    return displayText, DEFAULT_BAR_COLOR
end

-- Internal access for the override setter's equivalence check.
DT._ResolvePresetByText = ResolvePresetByText

-- Expose DISPLAY_PRESETS + DISPLAY_PRESET_ALIASES for GUI consumption
-- (preset chip grid + Color picker effective-color resolver in the
-- Display tab). Read-only by convention; mutating either would break
-- the ResolveDisplayPreset closure. GUI walks DT.DISPLAY_PRESETS.<key>
-- to get { label, color } pairs and DT.DISPLAY_PRESET_ALIASES.<key>
-- to map alternate inputs to a preset key.
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

-- Play a per-spell sound by LSM key. Called from the bar lifecycle
-- hooks (Show fires when the bar becomes visible; Hide fires on natural
-- expiration / interrupt). Preview bars are gated out — they loop
-- endlessly and would spam the sound channel.
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

-- BigWigs appends " (N)" to repeating-cast bar text for uniqueness. We need
-- the suffix in our key (so (1) and (2) don't collide in DT.bars) but the
-- user doesn't want to see iteration counters. Display the stripped version.
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

-- Bar extension past BigWigs's countdown: castDuration always counts;
-- channelDuration ONLY when the spell's effect lands at end-of-channel.
--
-- BigWigs's bar represents "time until cast/channel starts"; bar hitting
-- zero means the spell is about to fire. For pure casts, the actual hit
-- lands at end-of-cast — so we extend by castDuration to drain the bar to
-- zero AT impact. For most channels, the first damage tick lands right at
-- the channel's start (= BigWigs zero), so extending by channelDuration
-- would push our "now!" cue past when damage actually arrives. Mixed
-- cast+channel (boss casts 1s, then channels) extends only by castDuration
-- so the bar hits zero at the cast→channel boundary (= first damage tick).
--
-- The exception: spells whose payload arrives at END of channel (e.g. adds
-- spawn after a 4s channel finishes, not as it starts) opt in via
-- `extendByChannel = true` on their EncounterData entry. Their extension
-- becomes castDuration + channelDuration so the bar hits zero at the
-- effect's actual landing moment.
--
-- User time offset (per-spell): added to the curated value. Floored at 0
-- so a large negative offset makes the bar auto-hide at countdown end
-- (no cast phase) rather than going into undefined negative-extension
-- territory. The setter also clamps so this floor only fires defensively.
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

-- User per-spell time offset. nil = no override (extension is curated
-- value unchanged).
function DT:GetSpellTimeOffset(spellId)
    if not (self.db and self.db.SpellTimeOffsets and spellId) then return nil end
    return self.db.SpellTimeOffsets[spellId]
end

-- Sets the user time offset. Auto-prunes the entry when value rounds
-- to 0 so dragging the slider back to default leaves no stored override
-- and the modified indicator clears. Clamps at -curated (defensive —
-- the GUI also constrains the slider range).
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

-- Effective display mode (override → curator → "text" fallback). Used by
-- EventCallback to pick which group ("bar" or "text") a spawning bar
-- belongs to, and by the GUI tag rendering so the per-spell list shows
-- the user's overridden mode instead of the curator's default. Lua's
-- `or` chain works here because override values are always strings;
-- nil-vs-empty distinction can't sneak in.
function DT:GetSpellDisplay(spellId)
    local override = self:GetSpellDisplayOverride(spellId)
    if override then return override end
    local data = self:GetSpellInfo(spellId)
    return (data and data.display) or "text"
end

-- Curator's raw display field — ignores user override. Used by the GUI
-- to render the "Default: ..." caption next to the bar/text toggle so
-- users can see what they've deviated from.
function DT:GetSpellCuratorDisplay(spellId)
    local data = self:GetSpellInfo(spellId)
    return (data and data.display) or "text"
end

-- User per-spell display override. Returns "bar" / "text" / nil. nil
-- means "fall through to curator default".
function DT:GetSpellDisplayOverride(spellId)
    if not (self.db and self.db.SpellDisplayOverrides and spellId) then return nil end
    return self.db.SpellDisplayOverrides[spellId]
end

-- Sets the user override for display mode. Auto-prunes when the value
-- matches the curated default so toggling back to default leaves no
-- stored entry and the modified-stripe clears. Only "bar" / "text" are
-- accepted; anything else short-circuits.
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

-- Curated short-label override. Returns the user override (when set) or
-- the EncounterData displayText ("DODGE", "TANK HIT", "INTERRUPT" etc.)
-- or nil if none. RenderBar / CreateBar fall back to the BigWigs spell
-- name when nil. Resolution chain:
--   db.SpellDisplayTextOverrides[spellId] (user)  → wins
--   spell.displayText (curator)                    → fallback
--   nil                                            → no short label
function DT:GetSpellDisplayText(spellId)
    local override = self:GetSpellDisplayTextOverride(spellId)
    if override then return override end
    local data = self:GetSpellInfo(spellId)
    return data and data.displayText or nil
end

-- Curator's raw displayText — ignores user override. Used by the GUI
-- to render the "Default: X" caption next to the custom-label editor.
function DT:GetSpellCuratorDisplayText(spellId)
    local data = self:GetSpellInfo(spellId)
    return data and data.displayText or nil
end

-- User per-spell custom label. Returns a string or nil.
function DT:GetSpellDisplayTextOverride(spellId)
    if not (self.db and self.db.SpellDisplayTextOverrides and spellId) then return nil end
    return self.db.SpellDisplayTextOverrides[spellId]
end

-- Sets the custom label override. Whitespace is trimmed from the input.
-- Empty string OR string matching the curator default → entry is dropped
-- so toggling back leaves no stored override and the modified-stripe
-- clears. Otherwise stores the trimmed string verbatim. The display
-- preset resolver (DODGE / TANK HIT / etc.) runs at bar-creation time
-- against whatever this returns, so typing "DODGE" picks up the orange
-- preset color automatically.
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
        -- Equivalence prune: if both user input and curator resolve to
        -- the same preset, they render identically — drop the override.
        -- Catches "dodge" vs "DODGE" vs "Dodge" all matching curator
        -- "DODGE" and not creating a stored deviation. For non-preset
        -- strings, fall back to exact-match (case-sensitive because
        -- non-preset rendering preserves casing).
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

-- Per-spell sound on bar hide.
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

-- Convenience: true when the spell has any sound set (either show or
-- hide). Used by the GUI's spell list to flip the "S" indicator on the
-- row icon strip.
function DT:HasSpellSound(spellId)
    return self:GetSpellSoundOnShow(spellId) ~= nil
        or self:GetSpellSoundOnHide(spellId) ~= nil
end

-- Per-spell color override. Returns {r, g, b} or nil. Resolution chain
-- is applied in ApplyVisualsToBar: user override → preset color (from
-- effective displayText) → DEFAULT_BAR_COLOR.
function DT:GetSpellColorOverride(spellId)
    if not (self.db and self.db.SpellColorOverrides and spellId) then return nil end
    return self.db.SpellColorOverrides[spellId]
end

-- Sets the user color override. color = {r, g, b} stores the override;
-- color = nil clears it. No auto-prune against the curator default
-- because float comparison on color components is unreliable — users
-- click "Reset to default" explicitly to clear.
function DT:SetSpellColorOverride(spellId, color)
    if not (self.db and spellId) then return end
    self.db.SpellColorOverrides = self.db.SpellColorOverrides or {}
    if not color then
        self.db.SpellColorOverrides[spellId] = nil
        return
    end
    self.db.SpellColorOverrides[spellId] = { color[1], color[2], color[3] }
end

-- Per-spell decimal threshold. Returns the user override or the module-
-- level default (DECIMAL_THRESHOLD_DEFAULT, currently 30 = always
-- decimal). Used by UpdateTimeString to decide between "5.3" and "5"
-- formatting per tick.
function DT:GetSpellDecimalThreshold(spellId)
    if not (self.db and self.db.SpellDecimalThresholds and spellId) then
        return DECIMAL_THRESHOLD_DEFAULT
    end
    local stored = self.db.SpellDecimalThresholds[spellId]
    return stored or DECIMAL_THRESHOLD_DEFAULT
end

-- Sets the user's decimal threshold. Auto-prunes the entry when value
-- matches the module default so dragging back to default leaves no
-- stored override and the modified-stripe clears.
function DT:SetSpellDecimalThreshold(spellId, value)
    if not (self.db and spellId) then return end
    self.db.SpellDecimalThresholds = self.db.SpellDecimalThresholds or {}
    if value == DECIMAL_THRESHOLD_DEFAULT then
        self.db.SpellDecimalThresholds[spellId] = nil
    else
        self.db.SpellDecimalThresholds[spellId] = value
    end
end

-- Curated per-spell visibility threshold. Returns the EncounterData
-- showAtSeconds (number) or nil if no override. RenderBar's resolver
-- uses this BEFORE falling back to the group default. 0 is a meaningful
-- override that forces "always visible" even when the group hides.
--
-- Resolution order (per-spell visibility threshold):
--   db.SpellShowAtOverrides[spellId] (user override)  → wins
--   spell.showAtSeconds (curator default)             → fallback
--   nil                                                → no per-spell value
-- Lua's `or` treats 0 as truthy, so a user override of 0 correctly
-- forces "always visible" even when the curator set a non-zero default.
function DT:GetSpellShowAtSeconds(spellId)
    local userOverride = self:GetSpellShowAtOverride(spellId)
    if userOverride ~= nil then return userOverride end
    local data = self:GetSpellInfo(spellId)
    return data and data.showAtSeconds or nil
end

-- Curator's raw value from EncounterData. Used by the GUI to display
-- "default" indicators distinct from the user's override.
function DT:GetSpellCuratorShowAt(spellId)
    local data = self:GetSpellInfo(spellId)
    return data and data.showAtSeconds or nil
end

-- User per-spell override on the visibility threshold. nil = no override
-- (fall through to curator + group default chain).
function DT:GetSpellShowAtOverride(spellId)
    if not (self.db and self.db.SpellShowAtOverrides and spellId) then return nil end
    return self.db.SpellShowAtOverrides[spellId]
end

-- Sets the user override for showAt. Auto-clears the entry when the
-- value matches the effective default chain (curator → group → 0) so
-- dragging the slider back to the default position leaves no stored
-- override and the modified indicator clears correctly.
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

-- Curated spell role tag (tank/heal/mechanic/other) — populated from
-- EXBoss seed. Returns lowercase string or nil. Used by the role filter
-- to decide whether the player's current role should see this bar.
function DT:GetSpellRole(spellId)
    local data = self:GetSpellInfo(spellId)
    return data and data.role or nil
end

-- Player role cache. Defaults to DAMAGER so the allow-list never goes
-- empty before LibSpec resolves — a "show everything except heal/tank-
-- tagged" baseline is the safest fail-open default for uncurated content.
DT.playerRole = "DAMAGER"

-- LibSpec group callback. Fires for player + party members on spec change
-- AND once on PLAYER_LOGIN. We only care about the player's own row;
-- other-member updates are irrelevant for visibility filtering.
function DT:OnLibSpecGroupUpdate(_, role, _, playerName)
    if not playerName or playerName ~= UnitName("player") then return end
    if role and role ~= self.playerRole then
        self.playerRole = role
        dprint("playerRole=" .. tostring(role))
    end
end

-- Resolves "for this spell, would playerRoleToken see it?". Used by both
-- the live filter (ShouldShowSpellRole) AND the GUI role-overrides page —
-- a checkbox's value is just IsSpellAllowedForRole(spellId, "TANK") etc.
--
-- Resolution order (per role token):
--   db.SpellRoleOverrides[spellId][playerRoleToken] (if set) → wins
--   ROLE_ALLOW_LIST[playerRoleToken][spell.role]      → curated default
--   true                                              → fail open (uncurated)
--
-- Per-(spell,role) granularity in the override table: setting only
-- TANK = false leaves HEAL/DAMAGER reading curated. Mental model: the
-- override table only stores explicit deviations from curated.
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

-- Should this spell's bar render given the player's current role?
-- Filter is OFF by default (db.RoleFilterEnabled=false → always true).
function DT:ShouldShowSpellRole(spellId)
    if not (self.db and self.db.RoleFilterEnabled) then return true end
    return self:IsSpellAllowedForRole(spellId, self.playerRole)
end

-- Set a single (spell, playerRole) override. After writing, prune the
-- entry if every stored key now matches the curated default — auto-
-- clears redundant overrides so the "modified" indicator stays accurate
-- when users manually toggle a value back to its default. Cheap: one
-- comparison per write, never on render.
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

-- Wipe the override entry for a spell (all 3 player roles return to
-- curated defaults).
function DT:ResetSpellRoleOverride(spellId)
    if not (self.db and self.db.SpellRoleOverrides and spellId) then return end
    self.db.SpellRoleOverrides[spellId] = nil
end

-- Wipe overrides for every spell in every encounter under a given
-- dungeon key (e.g. "MaisaraCaverns"). Used by the per-dungeon Reset
-- button on the role-overrides GUI page.
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

-- Per-spell hard disable. Always-active filter (independent of the role
-- master toggle) — when set, the bar never renders regardless of role.
-- Tristate DB storage:
--   nil   = use curator default (data.disabled, defaults to false)
--   true  = explicit user disable (overrides curator)
--   false = explicit user enable (overrides curator-disabled default)
-- Storing only deviations keeps saved-vars tiny — when the user's setting
-- matches the curator default, SetSpellDisabled prunes to nil.
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
        -- Matches curator default — drop the override so the entry doesn't
        -- bloat saved-vars and "modified" indicator clears.
        self.db.SpellDisabled[spellId] = nil
    else
        self.db.SpellDisabled[spellId] = disabled
    end
end

-- Combined per-spell filter. Used by EventCallback as the single gate
-- before bar allocation — runs both the always-active disable check AND
-- the (optional) role-filter check. Returns true when the bar should
-- render, false when any filter trips.
function DT:ShouldShowSpell(spellId)
    if self:IsSpellDisabled(spellId) then return false end
    return self:ShouldShowSpellRole(spellId)
end

-- True when ANY user override exists for this spell (role allow-list,
-- hard disable, showAt threshold; future Display + Actions tabs will
-- extend this list). Drives the "modified" indicator on the spell list
-- rows so users can see at a glance which spells they've customized.
function DT:HasSpellOverrides(spellId)
    if not (self.db and spellId) then return false end
    -- Disabled override deviates from curator default whenever the user
    -- has stored an explicit value (tristate: nil = use default, true/false
    -- = explicit). Store-time auto-pruning keeps `false-on-curator-false`
    -- and `true-on-curator-true` from leaking in here as false positives.
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

-- Reset all per-spell overrides (role + disable + showAt). The GUI's
-- "Reset spell to default" button calls this so a single click returns
-- the spell to pure curated behavior across every per-spell knob.
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

-- One-time migration: early DungeonTimers schema nested AnchorFrom/To/XOffset/
-- YOffset under `BarGroup.Position` / `TextGroup.Position`. The flat shape (all
-- position keys at the group level) is required for PositionCard's full anchor
-- system (showAnchorFrameType + showStrata) since dbKeys can't traverse into a
-- sub-table. This migration runs once per profile per group and is a no-op
-- after the keys have been flattened.
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
    -- AceDB defaults don't deep-fill nested sub-tables that already exist in
    -- saved data (e.g. `Dungeons` is non-empty from BigWigsTimers, so the new
    -- `Dungeons.DungeonTimers` key isn't auto-populated). Trigger a backfill
    -- on first sight so positions/Enabled flags resolve correctly.
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
    -- Text rows scale with font size — use 1.6× the configured font size as
    -- the row height baseline so larger fonts don't clip and small ones don't
    -- waste vertical space. Floor of FALLBACK_TEXT_HEIGHT keeps the rows
    -- readable at very small font sizes.
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

-- Groups are 1px-tall point anchors. Bars stack outward from the group's
-- TOPLEFT (DOWN growth) or BOTTOMLEFT (UP growth) corner, so the user-set
-- group position = the start of the bar stack regardless of bar height.
-- Sizing the group as `barWidth × (barHeight × 12)` was the original setup,
-- but that means changing bar height changes the group's center, which —
-- with the default CENTER↔CENTER anchor — shifts the entire stack on screen
-- whenever font/height sliders change.
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

-- Pixel-aware SetValue gating. Skip the call when the visual delta is below
-- one pixel of bar width — saves ~6× WoW C-side calls vs raw per-frame
-- SetValue. Pattern matches DT (bigwigs) OnVisualUpdate / KT cooling-bar
-- (perf playbook entry #1). For text-mode bars there's no fill texture so
-- SetValue is a visual no-op anyway; we skip the call entirely there.
-- `frame` is the outer Frame, `frame.bar` is the inner StatusBar.
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

-- Last-string SetText gating. Skips bar.timerText:SetText when the formatted
-- string equals the prior tick's string. Safe here because preview/real
-- BigWigs durations are plain numbers (BigWigs computes them, not the secret-
-- value Unit*CastingDuration API). See feedback_dirty_check_secret_durations
-- for why this gating is unsafe on Castbar/DungeonCasts.
local function GatedSetText(textObj, holderBar, slot, str)
    if holderBar[slot] ~= str then
        textObj:SetText(str)
        holderBar[slot] = str
    end
end

-- Updates the visible time string. Bar mode writes to the right-justified
-- timerText FontString; text mode rewrites label as "name » timer" (one
-- FontString avoids the same-alignment overlap of two).
--
-- Decimal threshold semantics: below the threshold show "%.1f" (e.g.
-- "0.8"), at or above the threshold show whole seconds via ceil ("5"
-- means "5+ seconds left", matches WoW addon convention). Frame caches
-- the threshold at CreateBar time / ApplyVisualsToBar refresh — no DB
-- lookup per OnUpdate tick. Default DECIMAL_THRESHOLD_DEFAULT preserves
-- pre-knob "always decimal" behavior for bars without a per-spell
-- override.
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
            -- Loop bars (preview) reset to countdown phase with original colors
            -- instead of self-destructing.
            if self.loop then
                self.phase = "countdown"
                self.startTime = GetTime()
                local c = self.barColor or DEFAULT_BAR_COLOR
                if self.displayMode == "bar" then
                    if self.bar then
                        self.bar:SetStatusBarColor(c[1], c[2], c[3])
                    end
                    -- Bar mode: labels stay white over the colored fill.
                    if self.timerText then self.timerText:SetTextColor(1, 1, 1) end
                    if self.label then self.label:SetTextColor(1, 1, 1) end
                else
                    -- Text mode: restore preset color on the combined label.
                    if self.label then self.label:SetTextColor(c[1], c[2], c[3]) end
                end
                self._lastValue = nil
                self._lastTimerStr = nil
                return
            end
            -- Cast phase finished naturally (impact moment passed) → bar
            -- self-destructs. Fire hide sound first so the cue lands at
            -- the actual end-of-cast.
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
            -- Loop bars (preview): reset to full duration and continue.
            if self.loop then
                self.startTime = GetTime()
                remaining = self.totalDuration
                self._lastValue = nil
                self._lastTimerStr = nil
            -- No curated extension means no StopBar→cast transition is expected
            -- (e.g. BigWigs Wipe-module Respawn timer with spellId=nil). Auto-hide.
            -- Bars with extension > 0 keep their value clamped at 0 and wait for
            -- StopBar so the cast-phase transition can capture the right moment.
            elseif (self.extension or 0) <= 0 then
                -- Countdown ended with no cast extension (e.g. respawn
                -- timer or curator chose not to extend) → bar self-
                -- destructs. Fire hide sound at the zero crossing.
                PlayBarSound(self, "hide")
                self:SetScript("OnUpdate", nil)
                self:Hide()
                DT.bars[self.text] = nil
                DT:LayoutBars()
                return
            elseif -remaining >= STALE_GRACE then
                -- Extension-bearing bar has waited STALE_GRACE seconds at 0
                -- without StopBar — boss phased out, BigWigs missed StopBar,
                -- or interrupt removed the cast. Self-destruct so the bar
                -- doesn't sit at 0 indefinitely until OnBossDisable.
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

---------------------------------------------------------------------------------
-- Visual application — used both by CreateBar (initial) and ApplySettings
-- (reapply to live bars in-place). Kept as a free function so the logic isn't
-- duplicated. Only sets visual properties; doesn't touch state/timing.
--
-- Frame layout (bar mode):
--   frame (Frame, BackdropTemplate)              outer container, 1px border
--     ├─ iconFrame (Frame, BackdropTemplate)     square on left, 1px border
--     │     └─ icon (Texture, ARTWORK)           cropped via KE:ApplyIconZoom
--     └─ barContainer (Frame, BackdropTemplate)  fills right of icon, 1px border
--           └─ bar (StatusBar)                   fill texture
--                 ├─ label (FontString)          left text
--                 └─ timerText (FontString)      right text
-- Frame layout (text mode):
--   frame (Frame)
--     └─ bar (StatusBar, no texture)             container only
--           ├─ label (FontString)
--           └─ timerText (FontString)
---------------------------------------------------------------------------------
local function ApplyVisualsToBar(frame)
    local isBar = (frame.displayMode == "bar")
    local barDisplay = GetBarDisplay()
    local textDisplay = GetTextDisplay()

    -- Resolve per-spell knobs FIRST so the rest of the function reads
    -- fresh values. The bar-mode StatusBar color application (below)
    -- reads frame.barColor; if we resolve color further down it would
    -- paint with stale (or nil → default blue) data on the first pass.
    --
    -- Color chain: user override → preset (from displayTextRaw) →
    --              DEFAULT_BAR_COLOR (blue).
    -- Threshold: user override → DECIMAL_THRESHOLD_DEFAULT (always-decimal).
    -- Bars without spellId (preview Sample bars, Wipe-module Respawn
    -- timers) fall back to module defaults.
    if frame.spellId then
        frame.decimalThreshold = DT:GetSpellDecimalThreshold(frame.spellId)
    else
        frame.decimalThreshold = DECIMAL_THRESHOLD_DEFAULT
    end
    local _, presetColor = ResolveDisplayPreset(frame.displayTextRaw)
    local userColor = frame.spellId and DT:GetSpellColorOverride(frame.spellId) or nil
    frame.barColor = userColor or presetColor or DEFAULT_BAR_COLOR

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
        -- Icon visibility + sizing. iconEnabled toggles whether the bar
        -- starts after a square icon area or fills the full width. Width
        -- of barContainer drives the StatusBar fill width, which is what
        -- GatedSetValue measures.
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
            -- Countdown color = bar's preset color (or default blue when no
            -- preset). Cast phase has already overwritten this elsewhere,
            -- don't stomp on the cast tint here.
            if frame.phase ~= "cast" then
                local c = frame.barColor or DEFAULT_BAR_COLOR
                frame.bar:SetStatusBarColor(c[1], c[2], c[3])
            end
        end

        -- Cache the actual fill width (frame minus icon minus 2px border) for
        -- pixel-aware SetValue gating. Direct math beats per-frame :GetWidth()
        -- and stays accurate across width/iconEnabled changes.
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

    -- Initial text color. Bar mode: white labels overlaid on the colored
    -- fill — high-contrast, matches BigWigsTimers convention. Text mode:
    -- the label IS the visible color cue (no fill texture), so it gets
    -- the preset color directly. Cast phase overrides this elsewhere.
    if frame.phase ~= "cast" then
        local c = frame.barColor or DEFAULT_BAR_COLOR
        if isBar then
            if frame.label then frame.label:SetTextColor(1, 1, 1) end
            if frame.timerText then frame.timerText:SetTextColor(1, 1, 1) end
        else
            if frame.label then frame.label:SetTextColor(c[1], c[2], c[3]) end
        end
    end

    -- Text anchoring within the bar.
    -- Bars: separate label (LEFT-justified) and timer (RIGHT-justified)
    -- FontStrings, both with 4px padding so the bar's empty middle visually
    -- separates them.
    -- Texts: a SINGLE label FontString rendering "name » 4.5" (composed each
    -- tick by BarOnUpdate). Two FontStrings with the same alignment overlap;
    -- one FontString with the user's chosen alignment doesn't.
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

function DT:CreateBar(text, baseDuration, extension, displayMode, displayText, spellId)
    displayMode = displayMode or "text"
    local isBar = (displayMode == "bar")
    local group = isBar and self:EnsureBarGroup() or self:EnsureTextGroup()

    -- Pixel-perfect border thickness. KE:GetPixelSize returns logical units
    -- that map to exactly 1 physical pixel at the current UI scale; using a
    -- literal 1 instead would render fuzzy at non-1x scale.
    local px = (KE.GetPixelSize and KE:GetPixelSize()) or 1

    -- Outer container. No backdrop — barContainer's border + iconFrame's
    -- border cover the visible area, matching BigWigsTimers' pattern.
    local frame = CreateFrame("Frame", nil, group)
    frame.displayMode = displayMode

    if isBar then
        -- Icon container. Square, anchored LEFT. Size set in ApplyVisualsToBar.
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
        -- Default placeholder until the caller assigns a real iconID.
        frame.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

        -- Bar container holds the StatusBar inset by px so the pixel-perfect
        -- outer border shows. ApplyVisualsToBar repositions barContainer based
        -- on icon state.
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
        -- Text mode: no border, no icon, no fill. Bar is a transparent
        -- container so the FontStrings have something to anchor to.
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
    -- Optional spellId binding. When provided, ApplyVisualsToBar reads
    -- per-spell DB knobs (decimal threshold, future color/format) and
    -- caches them on the frame so the OnUpdate hot path doesn't pay a
    -- DB lookup per tick. Bars without a spellId (preview Sample bars,
    -- Wipe-module Respawn timers) fall back to module defaults.
    frame.spellId = spellId

    -- FontStrings parented to the StatusBar so they overlay the fill texture
    -- (same as BigWigsTimers).
    -- Bar mode: separate `label` (LEFT) and `timerText` (RIGHT). Bar middle
    --           gives them spatial separation, no separator needed.
    -- Text mode: ONE combined `label` rendering "name » 4.5". Updated each
    --            tick by BarOnUpdate. Two FontStrings with the same align
    --            overlap; combining them avoids that without using
    --            GetStringWidth (which has secret-value taint risk per
    --            reference_secret_value_behaviors).
    frame.label = frame.bar:CreateFontString(nil, "OVERLAY")
    if isBar then
        frame.timerText = frame.bar:CreateFontString(nil, "OVERLAY")
    end

    -- All sizing/font/anchoring derived from DB. Must run BEFORE the first
    -- SetText call below — WoW errors `FontString:SetText(): Font not set`
    -- if the FontString has no font assigned yet.
    -- Stash the raw displayText so ApplyVisualsToBar can re-resolve color
    -- on every settings refresh (lets the GUI color picker take effect
    -- live without rebuilding the bar). The label only needs resolving
    -- once at create time (preset key/label → canonical label).
    frame.displayTextRaw = displayText
    local resolvedLabel = ResolveDisplayPreset(displayText)

    ApplyVisualsToBar(frame)
    -- Curated short label wins when present; otherwise we strip BigWigs'
    -- " (N)" iteration counter from the spell name and use that. frame.text
    -- stays as the BigWigs raw text so DT.bars[] keying + StopBar routing
    -- match BigWigs's identifier. frame.baseText is the rendered label;
    -- OnUpdate composes "baseText » timer" for text-mode bars.
    frame.baseText = resolvedLabel or StripBigWigsCounter(text)
    if isBar then
        frame.label:SetText(frame.baseText)
    else
        -- Initial combined string; first OnUpdate tick refreshes the timer
        -- portion. Without an initial SetText the first frame would render
        -- empty; with this it renders the same combined shape it'll have
        -- one frame later. Threshold-aware so a bar with threshold=1
        -- starts as "name » 8" (integer above 1s) instead of "name » 8.0"
        -- and then snapping to "name » 8" one tick later.
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

    -- Anchor bars to the user's chosen AnchorFrom corner (matches
    -- BigWigsTimers PositionAllBars). This keeps the stack aligned to the
    -- corner the user picked: TOPRIGHT→TOPRIGHT keeps bars right-aligned
    -- to the group anchor point, CENTER→CENTER centers each row, etc.
    -- Hardcoding TOPLEFT here would make non-LEFT anchor configs hang off
    -- the wrong side of the user's chosen position.
    local barAnchorFrom = (barCfg and barCfg.AnchorFrom) or "CENTER"
    local textAnchorFrom = (textCfg and textCfg.AnchorFrom) or "CENTER"

    local barH = GetBarHeight()
    local textH = GetTextHeight()
    local barStride = barH + barSpacing
    local textStride = textH + textSpacing

    -- Collect into an ordered array so layout is deterministic. pairs() over
    -- the bars table iterates in hash order, which made the preview rows
    -- shuffle (e.g. C/A/B instead of A/B/C across reloads). sortIndex is
    -- assigned at creation time: previews get 1/2/3 explicitly; real bars
    -- get a monotonically increasing counter so they layout in the order
    -- BigWigs fires their timer events.
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

---------------------------------------------------------------------------------
-- ApplySettings: reapply DB-driven visuals to all live bars + group positions.
-- Called from GUI panels after the user changes a setting (font, width,
-- spacing, etc.). Aliased as UpdateFrameVisuals to mirror the BigWigsTimers
-- API surface — GUI files can call either name.
---------------------------------------------------------------------------------
function DT:ApplySettings()
    self:UpdateDB()
    self:UpdateGroupPositions()
    -- Groups stay 1×1 point anchors regardless of bar width changes; bar
    -- width is applied per-frame in ApplyVisualsToBar (see EnsureBarGroup).
    for _, bar in pairs(self.bars) do
        ApplyVisualsToBar(bar)
    end
    self:LayoutBars()
end

function DT:UpdateFrameVisuals()
    self:ApplySettings()
end

-- Monotonic counter for real-bar sort ordering. Previews use 1/2/3
-- explicitly; real bars get a high counter so they always lay out AFTER
-- previews and in BigWigs-event order. Bumped each RenderBar call.
DT._barSortCounter = 1000

-- Cancels any pending reveal timer on a bar. Called from KillBar /
-- StopBar's cast-phase transition / StopAllBars so timers don't fire
-- against bars that no longer exist.
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

    -- Reset the StatusBar's visual range so the bar appears full at reveal
    -- time and drains over the show window. Without this, a 45s base timer
    -- revealed at showWindow=10 would render as a 22% sliver (10/45) instead
    -- of a full bar draining to empty over the visible window.
    -- The countdown calc in BarOnUpdate stays unchanged (uses startTime +
    -- totalDuration); only the displayed bar range is tightened.
    if bar.bar and bar.showWindow and bar.showWindow > 0 then
        bar.bar:SetMinMaxValues(0, bar.showWindow)
        bar.bar:SetValue(bar.showWindow)
        bar._lastValue = nil
    end

    bar:Show()
    -- Bar just became visible after the showAt delay → fire show sound.
    PlayBarSound(bar, "show")
    self:LayoutBars()
end

function DT:RenderBar(text, baseDur, extension, displayMode, iconID, displayText, spellId)
    if not text or not baseDur or baseDur <= 0 then return end
    local existing = self.bars[text]
    if existing then
        CancelRevealTimer(self, existing)
        existing:SetScript("OnUpdate", nil)
        existing:Hide()
    end
    local bar = self:CreateBar(text, baseDur, extension, displayMode, displayText, spellId)
    self._barSortCounter = self._barSortCounter + 1
    bar.sortIndex = self._barSortCounter
    self.bars[text] = bar

    -- Real icon from the BigWigs_Timer event (BigWigs forwards the spell's
    -- iconID as the 7th arg). Falls through to the "?" placeholder set in
    -- CreateBar if the caller didn't supply one (e.g. preview bars use
    -- their own curated icons via CreatePreviewBar).
    if iconID and bar.icon then
        bar.icon:SetTexture(iconID)
    end

    -- Visibility threshold: hide bars whose total lifetime is longer than
    -- ShowAtSeconds; reveal via AceTimer at `total - showWindow` so the bar
    -- is visible for exactly `showWindow` seconds end-to-end (including any
    -- curated cast extension). Using baseDur instead would tack the cast
    -- duration on as extra visible time. ShowAtSeconds == 0 means always
    -- show (default).
    --
    -- Resolution chain (per-spell override wins):
    --   spell.showAtSeconds (EncounterData) → group.ShowAtSeconds (slider) → 0
    -- Spell-level 0 is a meaningful override that forces always-visible even
    -- when the group default would hide. Lua's `or` treats 0 as truthy, so
    -- nil-vs-0 distinction is preserved through the chain.
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
        -- Bar is immediately visible (no showAt delay or total fits in
        -- the window). Fire show sound now; RevealBar fires it for the
        -- delayed-reveal case.
        PlayBarSound(bar, "show")
    end

    self:LayoutBars()
end

local function KillBar(self, text)
    local bar = self.bars[text]
    if not bar then return end
    CancelRevealTimer(self, bar)
    bar:SetScript("OnUpdate", nil)
    -- Bar going away due to interrupt or external Stop. Fire hide sound
    -- BEFORE Hide() so the cue plays even if the frame is invisible
    -- next frame. Gated on bar:IsShown() so a bar killed during its
    -- showAt delay (still hidden) doesn't fire — there was nothing on
    -- screen to "hide" cleanly.
    if bar:IsShown() then
        PlayBarSound(bar, "hide")
    end
    bar:Hide()
    self.bars[text] = nil
    self:LayoutBars()
end

function DT:StopBar(text)
    if not text then return end
    local bar = self.bars[text]
    if not bar then return end

    -- Cast-phase StopBar = mid-cast interrupt. Kill.
    if bar.phase == "cast" then
        dprint("StopBar (cast interrupt): " .. tostring(text))
        KillBar(self, text)
        return
    end

    -- Countdown-phase StopBar:
    --   elapsed >= base - tolerance  → BigWigs's countdown finished naturally
    --                                  (auto-stop at zero OR real-cast-start
    --                                  fired StopBar). Transition the SAME bar
    --                                  in-place to cast phase: capture current
    --                                  visual value and drain to 0 over the
    --                                  curated castDuration. Cluster A: rate
    --                                  unchanged. Cluster B: rate slows so
    --                                  bar reaches 0 at real impact moment.
    --   elapsed <  base - tolerance  → mid-countdown interrupt, kill.
    local elapsed = GetTime() - bar.startTime
    local extension = bar.extension or 0

    if elapsed >= bar.duration - STOP_TOLERANCE and extension > 0 then
        local currentValue = bar.totalDuration - elapsed
        if currentValue <= 0 then
            -- StopBar arrived after the bar already drained past total — stale, kill.
            dprint(string_format("StopBar %s → killed (stale, elapsed=%.2f total=%.2f)",
                text, elapsed, bar.totalDuration))
            KillBar(self, text)
            return
        end
        bar.phase = "cast"
        bar.castStartTime = GetTime()
        bar.castFromValue = currentValue
        bar.castDuration = extension
        -- Don't force-show or cancel revealTimer here — the AceTimer scheduled
        -- in RenderBar uses (total - showWindow) which already accounts for
        -- the cast phase. If the bar's still hidden at cast transition, that
        -- means showWindow < extension and the timer hasn't fired yet; let it
        -- fire on time so the bar is visible for exactly showWindow seconds.
        -- RevealBar mid-cast just tightens the range and shows; OnUpdate's
        -- castFromValue / castDuration math keeps the visual coherent.
        -- No cast-phase color shift. Tried lighten-toward-white (looked
        -- like fading-out) and multiply-by-0.7 (looked muddy); both lost
        -- the preset's semantic color during the most important phase.
        -- The visible cue at cast start is already the bar draining over a
        -- shorter window with the timer counting down — that's sufficient.
        -- Matches BigWigs's own bar behavior (no color shift across phases).
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
        -- Spare preview bars — they're owned by GUI panel lifecycle, not the
        -- BigWigs encounter lifecycle. Real-boss StopBars/disable shouldn't
        -- nuke them mid-edit.
        if not bar.isPreview then
            CancelRevealTimer(self, bar)
            bar:SetScript("OnUpdate", nil)
            bar:Hide()
            self.bars[text] = nil
        end
    end
    self:LayoutBars()
end

---------------------------------------------------------------------------------
-- Settings preview bars/texts (GUI panel feedback)
-- Looping fake bars rendered into BarGroup / TextGroup so the user sees
-- live position / font / spacing feedback while editing the GUI panels.
-- Idempotent guards: Show is a no-op if previews already showing for that
-- mode; Hide is a no-op if not showing. ApplySettings (called on every GUI
-- callback) re-applies fonts/sizes in-place so previews stay smooth instead
-- of restarting their countdown each tick.
---------------------------------------------------------------------------------
local PREVIEW_BAR_KEYS = { "__preview_bar_1", "__preview_bar_2", "__preview_bar_3" }
local PREVIEW_TEXT_KEYS = { "__preview_text_1", "__preview_text_2", "__preview_text_3" }
local PREVIEW_BAR_LABELS = { "Sample Timer A", "Sample Timer B", "Sample Timer C" }
local PREVIEW_TEXT_LABELS = { "Sample Text A", "Sample Text B", "Sample Text C" }
local PREVIEW_DURATIONS = { 8, 12, 16 }
-- Three distinct, recognizable spell iconIDs so the preview rows visually
-- read as "real boss timers" while editing display settings. Stable across
-- WoW versions; not tied to any spell ID.
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
    -- Group preview owns the BarGroup while active; clear the single-spell
    -- preview so the two systems don't double-render in the same group.
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
    -- Group preview owns the TextGroup while active; clear the single-spell
    -- preview so the two systems don't double-render in the same group.
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

---------------------------------------------------------------------------------
-- Per-spell preview (Dungeon page selection feedback).
-- Renders ONE looping bar/text using the currently-selected spell's effective
-- settings (display mode, effective extension from time offset, real spell
-- name + icon, curated displayText). Lives in the user's configured BarGroup
-- or TextGroup so the preview spawns where real bars will appear.
--
-- Show is idempotent on identical spellId — a re-call from RefreshContent on
-- the same spell does nothing. Show on a DIFFERENT spell hides the old bar
-- and creates a new one. Refresh kills + recreates with current effective
-- settings (used by the Display-tab mode toggle and the time-offset slider
-- so visual updates land instantly without a full RefreshContent).
---------------------------------------------------------------------------------
local SPELL_PREVIEW_KEY = "__spell_preview"
local SPELL_PREVIEW_BASE_DURATION = 8

DT.spellPreviewSpellId = nil

function DT:ShowSpellPreview(spellId)
    if not spellId then
        self:HideSpellPreview()
        return
    end
    -- Idempotent guard: same spell already previewing? Don't restart its
    -- loop — RefreshContent fires on every tab switch / list click and we
    -- don't want the bar to visually reset each time.
    if self.spellPreviewSpellId == spellId and self.bars[SPELL_PREVIEW_KEY] then
        return
    end
    self:HideSpellPreview()
    -- Single-spell preview owns the group while active. Clear group
    -- previews so the two systems don't double-render. HideSettings*
    -- functions are idempotent guards on `previewBarShown` — cheap no-op
    -- when nothing's showing.
    self:HideSettingsBarPreviews()
    self:HideSettingsTextPreviews()

    local data = self:GetSpellInfo(spellId) or {}
    local extension = self:GetSpellExtension(spellId) or 0
    local displayMode = self:GetSpellDisplay(spellId) or "text"
    local displayText = self:GetSpellDisplayText(spellId)

    -- Label resolution: curated name → "Spell <id>" fallback. CreateBar
    -- internally resolves displayText through the preset table (DODGE,
    -- TANK HIT, etc.) so the rendered label respects curator overrides.
    local label = data.name or string_format("Spell %d", spellId)

    -- Preview duration: when showAt is set, we want the preview's visible
    -- window to match what the user will see in a real fight. In live
    -- gameplay, bars hide until (total - showAt) and then drain for
    -- exactly `showAt` seconds. For preview we don't need the hidden
    -- prelude — looping the visible portion is what the user is
    -- editing — so total visible = countdown + cast = showAt.
    --   countdown phase length = showAt - extension
    --   cast phase length      = extension
    -- Floor countdown at 1s so weird configs (showAt < extension) still
    -- produce a renderable bar.
    -- showAt == 0 (always visible): no visible-window semantic, fall
    -- back to the static 8s default + curated extension.
    --
    -- Resolution chain MUST mirror RenderBar's (override → curator →
    -- group default → 0). GetSpellShowAtSeconds only returns the first
    -- two; if those are nil, the live runtime applies the group default
    -- as a final fallback. Without that fallback the preview lies about
    -- what the user will see — e.g. group default 6, no per-spell
    -- override, GetSpellShowAtSeconds returns nil, preview would render
    -- the 8s static instead of 6s.
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
    -- sortIndex 1 keeps the preview bar at the top of the stack regardless
    -- of how many real bars spawn during a fight (their counter starts at
    -- 1000). 1 also matches the existing __preview_bar_1/2/3 ordering so
    -- if the Bars/Texts settings page IS active and shows its own previews,
    -- ours sits cleanly above without interleaving.
    bar.sortIndex = 1
    bar.text = SPELL_PREVIEW_KEY

    -- Bar mode: real spell icon (C_Spell.GetSpellTexture is taint-clean
    -- for curated spellIds — they're well-defined boss spells in the spell
    -- DB). Text mode: no icon, no-op.
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

-- Re-renders the active preview using the spell's current effective
-- settings. No-op when no preview is active. Used after the GUI changes
-- a setting that affects the bar's visual or duration (display mode,
-- time offset). Settings that affect ONLY the layout (group font/size/
-- spacing) flow through ApplySettings instead.
function DT:RefreshSpellPreview()
    if not self.spellPreviewSpellId then return end
    local id = self.spellPreviewSpellId
    self:HideSpellPreview()
    self:ShowSpellPreview(id)
end

function DT:OnInitialize()
    -- self.db must be populated BEFORE KitnEssentials:OnEnable runs its
    -- auto-enable loop (Core/Main.lua), which checks `module.db.Enabled`
    -- to decide whether to call EnableModule() at startup. Without this,
    -- the module never auto-enables across /reload — only the GUI checkbox
    -- can enable it for the current session.
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

    -- LibSpec gives us the player's role auto-refreshed on spec change.
    -- The callback fires once on PLAYER_LOGIN (or immediately on register
    -- if PLAYER_LOGIN already happened) and again whenever the player or
    -- a party member respecs. We filter to player-only inside the callback.
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

        -- Curated-only gate: skip any BigWigs_Timer event for a spell that
        -- we don't have curated data for. Without this filter, raid bosses
        -- + uncurated dungeons would still spawn bars in default blue
        -- whenever BigWigs fires, polluting the user's screen with the
        -- wrong content. The module is M+-curation-driven; if a spell isn't
        -- in EncounterData, BigWigs's own bars handle display (we don't
        -- duplicate). Filters BEFORE role/disable so the dprint trace doesn't
        -- spam for non-curated content.
        if not self:GetSpellInfo(spellIdNum) then
            return
        end

        -- Combined per-spell filter: hard-disable (always-active) +
        -- role allow-list (only when RoleFilterEnabled). Gates BEFORE
        -- bar allocation so we don't churn frames for hidden bars.
        if not self:ShouldShowSpell(spellIdNum) then
            local reason = self:IsSpellDisabled(spellIdNum) and "disabled" or "role"
            dprint(string_format("Timer FILTERED text=%s reason=%s role=%s player=%s",
                tostring(text), reason,
                tostring(self:GetSpellRole(spellIdNum)),
                tostring(self.playerRole)))
            return
        end

        local ext = self:GetSpellExtension(spellIdNum)
        local total = baseDur + ext
        local displayMode = self:GetSpellDisplay(spellIdNum)
        local displayText = self:GetSpellDisplayText(spellIdNum)
        dprint(string_format("Timer text=%s spellId=%s base=%.2f ext=%.2f total=%.2f display=%s label=%s mod=%s count=%s icon=%s",
            tostring(text),
            tostring(spellId),
            baseDur,
            ext,
            total,
            displayMode,
            tostring(displayText),
            tostring(addon and addon.moduleName or addon),
            tostring(count),
            tostring(icon)))
        self:RenderBar(text, baseDur, ext, displayMode, icon, displayText, spellIdNum)
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
