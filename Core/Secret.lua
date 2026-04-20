-- ╔══════════════════════════════════════════════════════════╗
-- ║  Secret.lua                                              ║
-- ║  Purpose: Centralized secret value utilities and         ║
-- ║           restriction state management for 12.0.         ║
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
    return value ~= nil and not self:IsSecretValue(value)
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

local function UpdateRestrictionType(restrictionType, active)
    restrictionTypes[restrictionType] = active

    -- Full (2): Combat, Encounter, ChallengeMode, PvPMatch
    -- Partial (1): Map transitions
    -- None (0): Everything else
    if restrictionTypes.Combat or
       restrictionTypes.Encounter or
       restrictionTypes.ChallengeMode or
       restrictionTypes.PvPMatch then
        SetRestrictionState(2)
    elseif restrictionTypes.Map then
        SetRestrictionState(1)
    else
        SetRestrictionState(0)
    end
end

---------------------------------------------------------------------------------
-- Event Handling
---------------------------------------------------------------------------------

local restrictionFrame = CreateFrame("Frame")
restrictionFrame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
restrictionFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
restrictionFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

restrictionFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_RESTRICTION_STATE_CHANGED" then
        local restrictionType, state = ...
        UpdateRestrictionType(restrictionType, state)
    elseif event == "PLAYER_REGEN_DISABLED" then
        UpdateRestrictionType("Combat", true)
    elseif event == "PLAYER_REGEN_ENABLED" then
        UpdateRestrictionType("Combat", false)
    end
end)

---------------------------------------------------------------------------------
-- Protected Error Listener
---------------------------------------------------------------------------------

local protectedErrorFrame = CreateFrame("Frame")
protectedErrorFrame:RegisterEvent("ADDON_ACTION_BLOCKED")
protectedErrorFrame:RegisterEvent("ADDON_ACTION_FORBIDDEN")

protectedErrorFrame:SetScript("OnEvent", function(_, event, addonName, funcName)
    if addonName == "KitnEssentials" then
        KE:Print(("Protected function violation: %s (%s)"):format(funcName or "unknown", event))
    end
end)
