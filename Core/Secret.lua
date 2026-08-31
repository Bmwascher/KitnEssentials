-- ╔══════════════════════════════════════════════════════════╗
-- ║  Secret.lua                                              ║
-- ║  Purpose: Centralized secret value utilities and         ║
-- ║           restriction state management for 12.1.         ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- Restriction States:
--   0: No restrictions, all operations allowed
--   1: Partial restrictions (map transitions)
--   2: Full restrictions (combat, M+, encounter, PvP)
--
-- Usage:
--   if KE:IsFullyRestricted() then return end
--   if KE:IsSecretValue(value) then return end
--   KE:DeferUntilUnrestricted(1, function() ... end)

---@class KE
local KE = select(2, ...)

-- Local references
local wipe = wipe
local ipairs = ipairs
local type = type
local table_insert = table.insert
local InCombatLockdown = InCombatLockdown
local CreateFrame = CreateFrame
local issecretvalue = issecretvalue
local issecrettable = issecrettable
local canaccessvalue = canaccessvalue
local UnitGUID = UnitGUID
local UnitName = UnitName

---------------------------------------------------------------------------------
-- Secret Value Utilities
---------------------------------------------------------------------------------

function KE:IsSecretValue(value)
    return issecretvalue and issecretvalue(value)
end

function KE:NotSecretValue(value)
    return not self:IsSecretValue(value)
end

-- Combined check: value exists and is NOT a secret
function KE:IsSafeValue(value)
    if self:IsSecretValue(value) then return false end
    return type(value) ~= "nil"
end

function KE:IsSecretTable(object)
    return issecrettable and issecrettable(object)
end

function KE:NotSecretTable(object)
    return not self:IsSecretTable(object)
end

function KE:CanAccessValue(value)
    return not canaccessvalue or canaccessvalue(value)
end

function KE:CanNotAccessValue(value)
    return not self:CanAccessValue(value)
end

function KE:HasSecretValues(object)
    return object and object.HasSecretValues and object:HasSecretValues()
end

function KE:NoSecretValues(object)
    return not self:HasSecretValues(object)
end

-- Join text around a body that may be secret. C_StringUtil.WrapString is
-- AllowedWhenTainted, so it accepts a secret in any position.
--
-- Plain `..` and format() are measured NOT to throw on secret text, so the
-- wrapper is a preference, not a requirement: it returns nil where a plain join
-- has no failure mode to report, which lets a caller degrade deliberately.
--
-- The shape it actually handles is a plain `..` between TWO secrets, which is
-- unverified. A secret used as the format STRING is a different matter: this
-- wrapper cannot parse one either, and nothing should try -- such a body is
-- printed as it arrived.
--
-- The return may itself be secret, and nothing here needs to know: `ok` is a
-- plain boolean from pcall, type() never throws whatever it is handed, and no
-- other statement touches `joined`. Returns nil when the join is unavailable,
-- so callers can fall back to the undecorated body.
---@param body any text to wrap, secret or not
---@param prefix string|nil
---@param suffix string|nil
---@return any|nil joined
function KE:WrapSecretText(body, prefix, suffix)
    local wrap = C_StringUtil and C_StringUtil.WrapString
    if not wrap or type(body) == "nil" then return nil end

    local ok, joined = pcall(wrap, body, prefix, suffix)
    if not ok or type(joined) == "nil" then return nil end
    return joined
end

-- Aura index scans (C_UnitAuras.GetAuraDataByIndex and its Buff/Debuff
-- siblings) carry RequiresUnitAuraAccess, whose failure mode is a HARD ERROR
-- for a tainted caller -- not a secret return. So ask before scanning;
-- sampling an aura to find out IS the error being avoided.
--
-- Two independent sources, combined fail-closed. ShouldAurasBeSecret is the
-- gate KE already proved in dungeons (DungeonTimers' Guidance check), but it
-- only predicts whether queries GENERALLY return secrets, and the hard error
-- comes from a separate access precondition -- so its "no" is not permission,
-- and an active restriction type still hides auras on its own documented
-- authority. Hidden when either says so; visible only when neither does.
-- Neither available means no restriction system to consult: answer "not
-- hidden" and let the call proceed.
--
-- StanceText keeps its own copy of the state list on purpose; its aura path
-- is dormant and the guard is documented to travel with it.
local AURA_HIDDEN_STATES
do
    local kinds = Enum and Enum.AddOnRestrictionType
    AURA_HIDDEN_STATES = kinds and {
        kinds.Combat, kinds.Encounter, kinds.ChallengeMode, kinds.PvPMatch,
    } or nil
end

function KE:AreAuraIdentitiesHidden()
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local ok, secret = pcall(C_Secrets.ShouldAurasBeSecret)
        if ok and secret == true then return true end
    end
    if not (AURA_HIDDEN_STATES and C_RestrictedActions
        and C_RestrictedActions.IsAddOnRestrictionActive) then
        return false
    end
    for _, state in ipairs(AURA_HIDDEN_STATES) do
        if C_RestrictedActions.IsAddOnRestrictionActive(state) then return true end
    end
    return false
end

-- The per-spell question, for a guard that protects a query about ONE spell.
--
-- A spell can be flagged never- or always-secret, and that flag outranks the
-- broad restriction state in BOTH directions -- readable inside a keystone,
-- or secret with nothing restricting at all. So when this question can be
-- asked it is the only one asked: falling through to the broad state after an
-- exact "no" would put back the approximation this exists to remove.
--
-- The identifier is whatever the guarded query itself passes -- id, name,
-- name with subtext, or link. Asking by id about a name query can answer
-- about a different spell, because a name lookup resolves overrides.
--
-- The broad helper above remains correct for enumeration and index calls,
-- where there is no single spell to ask about.
function KE:IsAuraHiddenForSpell(spellIdentifier)
    if spellIdentifier and C_Secrets and C_Secrets.ShouldSpellAuraBeSecret then
        local ok, secret = pcall(C_Secrets.ShouldSpellAuraBeSecret, spellIdentifier)
        if ok then return secret == true end
    end
    return self:AreAuraIdentitiesHidden()
end

-- The single gate every UNIT_AURA consumer calls before it touches the event.
-- Order is the point: the unit token is refused before anything compares or
-- slices it, because a comparison against a secret throws exactly as a truth
-- test does. The three payload lists are asked with the TABLE predicate, which
-- also catches a plain table whose reads hand back secrets -- the shape the
-- consumers' loops would otherwise walk into.
--
-- This answers whether the PAYLOAD can be read. It does not answer whether the
-- aura APIs may be called; that is AreAuraIdentitiesHidden, and every consumer
-- asks both.
--
-- A nil updateInfo is READABLE, not unreadable. What each caller does with it
-- differs -- one rebuilds, the others return -- and folding the decision in
-- here would take it away from them.
function KE:IsUnreadableAuraPayload(unit, updateInfo)
    if self:IsSecretValue(unit) then return true end
    if updateInfo == nil then return false end
    if self:IsSecretValue(updateInfo) or self:IsSecretTable(updateInfo) then
        return true
    end
    if self:IsSecretValue(updateInfo.isFullUpdate) then return true end
    local added   = updateInfo.addedAuras
    local updated = updateInfo.updatedAuraInstanceIDs
    local removed = updateInfo.removedAuraInstanceIDs
    if (added ~= nil and (self:IsSecretValue(added) or self:IsSecretTable(added)))
        or (updated ~= nil and (self:IsSecretValue(updated) or self:IsSecretTable(updated)))
        or (removed ~= nil and (self:IsSecretValue(removed) or self:IsSecretTable(removed))) then
        return true
    end
    return false
end

---------------------------------------------------------------------------------
-- Safe Unit Helpers
---------------------------------------------------------------------------------

-- Get unit name safely, returns nil if unit or name is secret
function KE:GetSafeUnitName(unit)
    if not self:IsSafeValue(unit) then return nil end
    if type(unit) ~= "string" then return nil end

    local name = UnitName(unit)
    if not self:IsSafeValue(name) then return nil end

    return name
end

-- Get unit GUID safely, returns nil if unit or guid is secret
function KE:GetSafeUnitGUID(unit)
    if not self:IsSafeValue(unit) then return nil end
    if type(unit) ~= "string" then return nil end

    local guid = UnitGUID(unit)
    if not self:IsSafeValue(guid) then return nil end

    return guid
end

-- Safely get text from a FontString, returns nil if secret
function KE:GetSafeText(fontString)
    if not fontString or not fontString.GetText then return nil end

    local text = fontString:GetText()
    if not self:IsSafeValue(text) then return nil end

    return text
end

---------------------------------------------------------------------------------
-- Restriction State Management
---------------------------------------------------------------------------------

local currentRestrictionState = 0
local restrictionTypes = {}
local deferredCallbacks = {}

-- The restriction event supplies numeric enum values, not strings, and its
-- state enum starts at Inactive = 0 -- truthy in Lua. So the table is keyed by
-- the enum value and always stores an explicit boolean. Without the enum table
-- there is nothing to key by: fall back to the combat edge alone rather than
-- inventing string keys the event will never match.
local RestrictionType = Enum and Enum.AddOnRestrictionType
local RestrictionState = Enum and Enum.AddOnRestrictionState

local COMBAT_KEY = RestrictionType and RestrictionType.Combat or "Combat"
local MAP_KEY = RestrictionType and RestrictionType.Map
local FULL_KEYS = RestrictionType and {
    RestrictionType.Combat,
    RestrictionType.Encounter,
    RestrictionType.ChallengeMode,
    RestrictionType.PvPMatch,
} or { COMBAT_KEY }

-- Get current restriction state (0 = none, 1 = partial, 2 = full)
function KE:GetRestrictionState()
    return currentRestrictionState
end

-- Check if fully restricted (combat, M+, encounter, PvP)
function KE:IsFullyRestricted()
    return currentRestrictionState == 2
end

-- Check if any restriction is active
function KE:IsRestricted()
    return currentRestrictionState > 0
end

-- Check if safe to perform protected operations
function KE:CanMakeProtectedCalls()
    return currentRestrictionState < 2 and not InCombatLockdown()
end

-- Queue a function to run when restrictions release to specified state or lower
-- targetState: 0 = run when fully clear, 1 = run when partial or clear
function KE:DeferUntilUnrestricted(targetState, callback)
    if not callback then return end

    -- If already at or below the target state, execute immediately
    if currentRestrictionState <= targetState then
        callback()
        return
    end

    -- Queue for later execution
    table_insert(deferredCallbacks, {
        targetState = targetState,
        callback = callback
    })
end

---------------------------------------------------------------------------------
-- Internal State Logic
---------------------------------------------------------------------------------

local function SetRestrictionState(newState)
    if currentRestrictionState == newState then return end

    local oldState = currentRestrictionState
    currentRestrictionState = newState

    -- If restrictions released, execute deferred callbacks
    if newState < oldState then
        local toExecute = {}
        local toKeep = {}

        for _, entry in ipairs(deferredCallbacks) do
            if entry.targetState >= newState then
                table_insert(toExecute, entry.callback)
            else
                table_insert(toKeep, entry)
            end
        end

        -- Update queue first (in case callbacks add new entries)
        wipe(deferredCallbacks)
        for _, entry in ipairs(toKeep) do
            table_insert(deferredCallbacks, entry)
        end

        -- Execute callbacks
        for _, callback in ipairs(toExecute) do
            callback()
        end
    end
end

local function RecomputeState()
    for _, key in ipairs(FULL_KEYS) do
        if restrictionTypes[key] then
            SetRestrictionState(2)
            return
        end
    end
    if MAP_KEY and restrictionTypes[MAP_KEY] then
        SetRestrictionState(1)
    else
        SetRestrictionState(0)
    end
end

local function UpdateRestrictionType(key, active)
    if key == nil then return end
    restrictionTypes[key] = active or nil
    RecomputeState()
end

-- IsAddOnRestrictionActive is documented to answer false for the whole of
-- ADDON_RESTRICTION_STATE_CHANGED dispatch, so this is the only place it can
-- be trusted. Without it, reloading inside an encounter or a keystone starts
-- from "unrestricted" and stays there until the next transition.
local function SeedRestrictionState()
    if RestrictionType and C_RestrictedActions
        and C_RestrictedActions.IsAddOnRestrictionActive then
        for _, key in ipairs(FULL_KEYS) do
            restrictionTypes[key] = C_RestrictedActions.IsAddOnRestrictionActive(key) or nil
        end
        if MAP_KEY then
            restrictionTypes[MAP_KEY] =
                C_RestrictedActions.IsAddOnRestrictionActive(MAP_KEY) or nil
        end
    end
    if InCombatLockdown() then restrictionTypes[COMBAT_KEY] = true end
    RecomputeState()
end

---------------------------------------------------------------------------------
-- Event Handling
---------------------------------------------------------------------------------

local restrictionFrame = CreateFrame("Frame")
restrictionFrame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
restrictionFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
restrictionFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
restrictionFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

restrictionFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_RESTRICTION_STATE_CHANGED" then
        local restrictionType, state = ...
        -- Activating counts as restricted: it means enforcement begins as soon
        -- as this dispatch ends, and anything queued in between would run into
        -- it. Compared, never truth-tested -- Inactive is 0.
        local active = RestrictionState ~= nil
            and (state == RestrictionState.Activating
                or state == RestrictionState.Active)
        UpdateRestrictionType(restrictionType, active)
    elseif event == "PLAYER_ENTERING_WORLD" then
        SeedRestrictionState()
    elseif event == "PLAYER_REGEN_DISABLED" then
        UpdateRestrictionType(COMBAT_KEY, true)
    elseif event == "PLAYER_REGEN_ENABLED" then
        UpdateRestrictionType(COMBAT_KEY, false)
    end
end)
