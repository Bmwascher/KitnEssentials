-- ╔══════════════════════════════════════════════════════════╗
-- ║  DamageMeter/Core.lua                                    ║
-- ║  Module: Damage Meter                                    ║
-- ║  Purpose: In-client damage/healing/threat meter with a   ║
-- ║           configurable dock, per-segment history, and    ║
-- ║           death log.                                     ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class DamageMeter: AceModule, AceEvent-3.0, AceConsole-3.0
local DM = KitnEssentials:NewModule("DamageMeter", "AceEvent-3.0", "AceConsole-3.0")

KE.DamageMeter = DM

local DEBUG_DM = false

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------

function DM:UpdateDB()
    self.db = KE.db.profile.DamageMeter
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------

function DM:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function DM:OnEnable()
    if not self.db or not self.db.Enabled then return end

    self.enabled = true

    if DEBUG_DM then
        KE:Print("[DM] OnEnable: module active")
    end
end

function DM:OnDisable()
    self.enabled = false

    if self.dock and self.dock.Hide then
        self.dock:Hide()
    end

    if DEBUG_DM then
        KE:Print("[DM] OnDisable: module inactive")
    end
end

---------------------------------------------------------------------------------
-- Secret-safe session getters
--
-- C_DamageMeter session/source returns carry secret values in combat
-- (totalAmount, amountPerSecond, maxAmount). The getters themselves can also
-- reject secret arguments while execution is tainted, so every API call is
-- wrapped in pcall and the result is discarded on failure. The caller renders
-- the returned tables via native widget interpolation; it must never perform
-- Lua arithmetic or comparisons on the secret fields.
---------------------------------------------------------------------------------

-- Returns the combat session table { combatSources, maxAmount, totalAmount,
-- durationSeconds } for the requested type/id, or nil on failure. When
-- sessionID is non-nil the FromID variant is used (a specific stored session);
-- otherwise the live FromType variant is used.
function DM:GetSession(sessionType, dmType, sessionID)
    if not C_DamageMeter then return nil end

    if sessionID ~= nil then
        if not C_DamageMeter.GetCombatSessionFromID then return nil end
        local ok, session = pcall(C_DamageMeter.GetCombatSessionFromID, sessionID, dmType)
        if ok then return session end
        return nil
    end

    if not C_DamageMeter.GetCombatSessionFromType then return nil end
    local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, sessionType, dmType)
    if ok then return session end
    return nil
end

-- Returns the per-source detail table for a single combat source (keyed by
-- sourceGUID), or nil on failure. Mirrors GetSession's FromID/FromType branch.
function DM:GetSource(sessionType, dmType, sourceGUID, sessionID)
    if not C_DamageMeter then return nil end

    if sessionID ~= nil then
        if not C_DamageMeter.GetCombatSessionSourceFromID then return nil end
        local ok, source = pcall(C_DamageMeter.GetCombatSessionSourceFromID, sessionID, dmType, sourceGUID)
        if ok then return source end
        return nil
    end

    if not C_DamageMeter.GetCombatSessionSourceFromType then return nil end
    local ok, source = pcall(C_DamageMeter.GetCombatSessionSourceFromType, sessionType, dmType, sourceGUID)
    if ok then return source end
    return nil
end

---------------------------------------------------------------------------------
-- Value formatter
--
-- AbbreviateNumbers returns a (secret-in-combat) string, and concatenating two
-- such strings with .. is confirmed safe. So the combined "total | perSec"
-- string is built from a single value FontString's worth of data without ever
-- calling tostring on, or comparing, the raw amounts.
---------------------------------------------------------------------------------

-- File-local: returns the abbreviated total, or "total | perSec" when showPerSec
-- is true and perSec is available. Never touches the numeric amounts directly.
local function FormatBarValue(total, perSec, showPerSec)
    if showPerSec and perSec ~= nil then
        return AbbreviateNumbers(total) .. " | " .. AbbreviateNumbers(perSec)
    end
    return AbbreviateNumbers(total)
end

-- Reads the ShowPerSec preference and delegates to FormatBarValue.
function DM:FormatBarValue(total, perSec)
    local showPerSec = self.db and self.db.ShowPerSec or false
    return FormatBarValue(total, perSec, showPerSec)
end

---------------------------------------------------------------------------------
-- Content-context resolver
--
-- Mirrors KickTracker:GetActiveContext (Modules/Dungeons/KickTracker.lua) but
-- keyed off the instance type rather than the player's spec. Each window stores
-- per-context configs under Windows[i].Contexts; the live context drives which
-- one is active, falling back to Default.
---------------------------------------------------------------------------------

local CTX_BY_INSTANCE = {
    party     = "Dungeon",
    raid      = "Raid",
    arena     = "Arena",
    pvp       = "Battleground",
    scenario  = "Scenario",
    none      = "Default",
}

-- Maps a Blizzard instanceType (plus the Challenge Mode flag) to a KE context
-- key. Mythic+ is a party instance with an active keystone.
function DM:MapContext(instanceType, isChallenge)
    if instanceType == "party" and isChallenge then
        return "Mythic+"
    end
    return CTX_BY_INSTANCE[instanceType] or "Default"
end

-- Live content context derived from the current instance type and keystone
-- state.
function DM:GetActiveContext()
    local instanceType = select(2, IsInInstance())
    local isChallenge = (C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
        and C_ChallengeMode.IsChallengeModeActive()) or false
    return self:MapContext(instanceType, isChallenge)
end

-- Resolves the active per-context config for a window: the live-context entry
-- if present, else the Default entry. Returns nil when the window or its
-- Contexts table is absent.
function DM:ResolveWindowConfig(winIdx)
    local windows = self.db and self.db.Windows
    local window = windows and windows[winIdx]
    if not window or not window.Contexts then return nil end
    return window.Contexts[self:GetActiveContext()] or window.Contexts.Default
end
