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

-- File-level upvalues for globals used in per-tick / per-bar render paths.
local IsInInstance = IsInInstance
local C_ChallengeMode = C_ChallengeMode
local AbbreviateNumbers = AbbreviateNumbers
local issecretvalue = issecretvalue

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
    -- self.db is assigned in OnInitialize (always runs before OnEnable in the
    -- Ace3 lifecycle), so only the Enabled flag needs checking here.
    if not self.db.Enabled then return end

    self.enabled = true

    -- Combat-state events drive the shared ticker (see Combat-only ticker
    -- section). NEVER use RegisterUnitEvent (Ace3 doesn't expose it and 12.0
    -- discourages it for KE); UNIT_FLAGS is registered broad and filtered by
    -- the group-combat check inside the handler.
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnRegenDisabled")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnRegenEnabled")
    self:RegisterEvent("ENCOUNTER_END", "OnCombatForceStop")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnCombatForceStop")
    self:RegisterEvent("UNIT_FLAGS", "OnUnitFlags")
    self:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED", "OnSessionUpdated")
    self:RegisterEvent("DAMAGE_METER_RESET", "OnMeterReset")

    if DEBUG_DM then
        KE:Print("[DM] OnEnable: module active")
    end
end

function DM:OnDisable()
    self.enabled = false

    self:UnregisterAllEvents()
    self:StopTicker()
    self._sessionPending = false

    if self.dock then
        self.dock:Hide()
    end

    if DEBUG_DM then
        KE:Print("[DM] OnDisable: module inactive")
    end
end

---------------------------------------------------------------------------------
-- Combat-only ticker (shared across all windows)
--
-- Mirrors EllesmereUI's StartSharedTicker/StopSharedTicker (single ticker for
-- every window). The ticker only runs while the player or group is in combat,
-- so idle CPU is zero. DM:Tick (implemented in the render chunk) repaints every
-- window from the current sessions; it is resolved at runtime here (called as a
-- method) so this lifecycle layer doesn't depend on the render layer load order.
---------------------------------------------------------------------------------

-- Starts (or restarts) the shared refresh ticker. Cancel-before-start so a
-- stale ticker is never left orphaned if combat is re-entered without a clean
-- stop. RefreshRate defaults to 0.5s when the DB value is missing.
function DM:StartTicker()
    if self._ticker then
        self._ticker:Cancel()
        self._ticker = nil
    end

    local rate = (self.db and self.db.RefreshRate) or 0.5
    self._ticker = C_Timer.NewTicker(rate, function()
        DM:Tick()
    end)

    if DEBUG_DM then
        KE:Print("[DM] StartTicker: rate", rate)
    end
end

-- Cancels the shared ticker and paints one final frame so the bars settle on
-- the post-combat totals (out of combat the amounts declassify to plain numbers).
function DM:StopTicker()
    if self._ticker then
        self._ticker:Cancel()
        self._ticker = nil
    end

    self:Tick()

    if DEBUG_DM then
        KE:Print("[DM] StopTicker: final paint")
    end
end

-- True when the player is in combat, or any group member is. UnitAffectingCombat
-- is safe to read here (not a secret return). InCombatLockdown short-circuits the
-- common case so the group scan only runs when the player has already left
-- combat (e.g. died mid-pull while the group keeps fighting).
function DM:GroupInCombat()
    if InCombatLockdown() then return true end

    if IsInRaid() then
        local n = GetNumGroupMembers()
        for i = 1, n do
            if UnitAffectingCombat("raid" .. i) then return true end
        end
    elseif IsInGroup() then
        -- Party units exclude the player, so iterate one fewer than the count.
        local n = GetNumGroupMembers() - 1
        for i = 1, n do
            if UnitAffectingCombat("party" .. i) then return true end
        end
    end

    return false
end

---------------------------------------------------------------------------------
-- Combat-state event handlers
--
-- The ticker is combat-gated: started on entering combat, stopped once the whole
-- group has left combat. ENCOUNTER_END and PLAYER_ENTERING_WORLD force it down
-- unconditionally (boss kill/wipe and zoning are hard segment boundaries).
---------------------------------------------------------------------------------

-- Player entered combat: spin up the shared ticker.
function DM:OnRegenDisabled()
    if DEBUG_DM then KE:Print("[DM] PLAYER_REGEN_DISABLED -> StartTicker") end
    self:StartTicker()
end

-- Player left combat. If the group is still fighting (player died mid-pull),
-- keep ticking and re-check shortly; only stop once everyone is out of combat.
function DM:OnRegenEnabled()
    if not self:GroupInCombat() then
        if DEBUG_DM then KE:Print("[DM] PLAYER_REGEN_ENABLED -> StopTicker") end
        self:StopTicker()
    else
        if DEBUG_DM then KE:Print("[DM] PLAYER_REGEN_ENABLED -> group still in combat, re-check") end
        local rate = (self.db and self.db.RefreshRate) or 0.5
        C_Timer.After(rate, function()
            if not DM:GroupInCombat() then
                DM:StopTicker()
            end
        end)
    end
end

-- Boss kill/wipe or zoning: hard segment boundary, force the ticker down.
function DM:OnCombatForceStop()
    if DEBUG_DM then KE:Print("[DM] ENCOUNTER_END/PLAYER_ENTERING_WORLD -> force StopTicker") end
    self:StopTicker()
end

-- A group member's flags changed (often: they entered combat before us). Start
-- the ticker if the group is fighting and we're not already ticking, so bars
-- populate before the player is tagged.
function DM:OnUnitFlags()
    if self:GroupInCombat() and not self._ticker then
        if DEBUG_DM then KE:Print("[DM] UNIT_FLAGS -> group in combat, StartTicker") end
        self:StartTicker()
    end
end

-- The damage-meter session changed. In combat the ticker already covers
-- repaints, so only react out of combat. Debounce to one paint per 0.1s burst
-- (the event can fire rapidly as the API finalizes a segment).
function DM:OnSessionUpdated()
    if InCombatLockdown() then return end
    if self._sessionPending then return end

    self._sessionPending = true
    C_Timer.After(0.1, function()
        DM._sessionPending = false
        if DEBUG_DM then KE:Print("[DM] DAMAGE_METER_COMBAT_SESSION_UPDATED (debounced) -> Tick") end
        DM:Tick()
    end)
end

-- Meter data was reset: repaint immediately so cleared bars show.
function DM:OnMeterReset()
    if DEBUG_DM then KE:Print("[DM] DAMAGE_METER_RESET -> Tick") end
    self:Tick()
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
        if DEBUG_DM then KE:Print("[DM] GetSession FromID failed:", session) end
        return nil
    end

    if not C_DamageMeter.GetCombatSessionFromType then return nil end
    local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, sessionType, dmType)
    if ok then return session end
    if DEBUG_DM then KE:Print("[DM] GetSession FromType failed:", session) end
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
        if DEBUG_DM then KE:Print("[DM] GetSource FromID failed:", source) end
        return nil
    end

    if not C_DamageMeter.GetCombatSessionSourceFromType then return nil end
    local ok, source = pcall(C_DamageMeter.GetCombatSessionSourceFromType, sessionType, dmType, sourceGUID)
    if ok then return source end
    if DEBUG_DM then KE:Print("[DM] GetSource FromType failed:", source) end
    return nil
end

---------------------------------------------------------------------------------
-- Value formatter
--
-- AbbreviateNumbers returns a (secret-in-combat) string, and concatenating two
-- such strings with .. is confirmed safe. So the combined "total | perSec"
-- string is built from a single value FontString's worth of data without ever
-- calling tostring on, or comparing, the raw amounts.
--
-- The formatter returns (string, isSecret). In combat the amounts are secret,
-- so the produced string is secret too; the render layer MUST NOT dirty-check
-- it with == / ~= (that throws a taint error). Out of combat the amounts are
-- plain numbers and the string is a normal string the caller can cache and
-- compare. issecretvalue on the result tells the caller which path applies.
--
-- The render layer reads self.db.ShowPerSec once before the bar loop and calls
-- this file-local directly, rather than re-reading the DB per bar through a
-- method wrapper.
---------------------------------------------------------------------------------

-- Returns (string, isSecret): the abbreviated total, or "total | perSec" when
-- showPerSec is true and perSec is available. Never touches the numeric amounts
-- directly (no tostring, no comparisons). `total` is nil-guarded with a
-- truthiness gate (NOT `== nil`, which is a taint-throwing equality on a secret
-- number in combat); a secret number is truthy, so `not total` is only true for
-- a genuinely nil/empty source, which yields an empty, non-secret string.
local function FormatBarValue(total, perSec, showPerSec)
    if not total then return "", false end

    local str
    if showPerSec and perSec then
        str = AbbreviateNumbers(total) .. " | " .. AbbreviateNumbers(perSec)
    else
        str = AbbreviateNumbers(total)
    end

    return str, issecretvalue(str)
end

KE.DamageMeter._FormatBarValue = FormatBarValue

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
-- state. IsChallengeModeActive's return is passed through as raw truthiness
-- (no `or false` coercion) to avoid undefined behavior should it ever return a
-- secret boolean; mirrors WarpDepleteForces' IsInChallengeMode helper.
function DM:GetActiveContext()
    local instanceType = select(2, IsInInstance())
    local isChallenge = C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
        and C_ChallengeMode.IsChallengeModeActive()
    return self:MapContext(instanceType, isChallenge)
end

-- Resolves the active per-context config for a window: the live-context entry
-- if present, else the Default entry. Returns nil when the window or its
-- Contexts table is absent. `context` may be supplied by the render layer (it
-- resolves the active context once per tick and passes it to each window) to
-- avoid recomputing it N times; otherwise it is resolved here.
function DM:ResolveWindowConfig(winIdx, context)
    local windows = self.db and self.db.Windows
    local window = windows and windows[winIdx]
    if not window or not window.Contexts then return nil end
    context = context or self:GetActiveContext()
    return window.Contexts[context] or window.Contexts.Default
end
