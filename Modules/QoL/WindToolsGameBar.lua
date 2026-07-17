-- ╔══════════════════════════════════════════════════════════╗
-- ║  WindToolsGameBar.lua                                    ║
-- ║  Module: WindTools Game Bar Hider                        ║
-- ║  Purpose: Hide ElvUI_WindTools' Game Bar in combat       ║
-- ║           and/or while in a Mythic+ keystone.            ║
-- ║                                                          ║
-- ║  Why a shim: WindTools writes its Visibility text box    ║
-- ║  directly to RegisterStateDriver, which only understands ║
-- ║  Blizzard macro conditionals. [combat] works natively    ║
-- ║  but there is no [mythicplus] conditional, so M+ hiding  ║
-- ║  needs CHALLENGE_MODE_* event-driven Unregister/Hide.    ║
-- ║                                                          ║
-- ║  Soft dependency: WindTools may not be loaded. Every     ║
-- ║  path no-ops if _G.WTGameBar is absent.                  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class WindToolsGameBar: AceModule, AceEvent-3.0, AceHook-3.0
local WT = KitnEssentials:NewModule("WindToolsGameBar", "AceEvent-3.0", "AceHook-3.0")

local C_Timer = C_Timer
local InCombatLockdown = InCombatLockdown
local IsInInstance = IsInInstance
local LibStub = LibStub
local RegisterStateDriver = RegisterStateDriver
local UnregisterStateDriver = UnregisterStateDriver
local select = select

-- Toggle for in-development tracing of state-driver changes + WindTools
-- UpdateBar hooks. Off in shipped code; flip true to verify hide/show
-- transitions in the chat log (matches project DEBUG_X convention).
local DEBUG_WTGB = false
local function dprint(msg)
    if DEBUG_WTGB then KE:Print("[WTGB] " .. tostring(msg)) end
end

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------

local DEFAULT_VISIBILITY = "[petbattle] hide; show"
-- GetInstanceInfo's 4th return is `difficultyID`. 8 = Mythic Keystone.
-- C_ChallengeMode.IsChallengeModeActive() also works but is timing-fragile
-- (true only between CHALLENGE_MODE_START and the actual run); the
-- difficulty check is the same data the dungeon uses to render its UI.
local MYTHIC_KEYSTONE_DIFFICULTY = 8

---------------------------------------------------------------------------------
-- DB
---------------------------------------------------------------------------------

function WT:UpdateDB()
    self.db = KE.db.profile.WindToolsGameBar
end

function WT:OnInitialize()
    self:UpdateDB()
    -- Start disabled; KitnEssentials:OnEnable iterates modules and calls
    -- EnableModule(name) for those whose db.Enabled is truthy. Matches the
    -- VantusRune / HuntersMark pattern across the project.
    self:SetEnabledState(false)
end

---------------------------------------------------------------------------------
-- WindTools accessors
---------------------------------------------------------------------------------

local function GetGameBarFrame()
    return _G.WTGameBar
end

-- Read the user's CURRENT WindTools visibility string each call so changes
-- they make in the WindTools UI flow through to our state driver next apply.
local function GetUserVisibilityString()
    local ElvUI_addon = _G.ElvUI
    if not ElvUI_addon then return nil end
    local E = ElvUI_addon[1]
    if not E or not E.db then return nil end
    local wt = E.db.WT
    if not wt or not wt.misc or not wt.misc.gameBar then return nil end
    local s = wt.misc.gameBar.visibility
    if type(s) ~= "string" or s == "" then return nil end
    return s
end

---------------------------------------------------------------------------------
-- M+ detection
---------------------------------------------------------------------------------

function WT:IsInMythicPlus()
    local inInstance, instanceType = IsInInstance()
    if not inInstance or instanceType ~= "party" then return false end
    local difficultyID = select(3, GetInstanceInfo())
    return difficultyID == MYTHIC_KEYSTONE_DIFFICULTY
end

---------------------------------------------------------------------------------
-- Visibility string builder
---------------------------------------------------------------------------------

-- If HideInCombat is enabled, prepend [combat] hide; to whatever the user has
-- saved in WindTools so the toggle is reversible without touching their DB.
local function BuildVisibilityString(db)
    local base = GetUserVisibilityString() or DEFAULT_VISIBILITY
    if db.HideInCombat then
        return "[combat] hide; " .. base
    end
    return base
end

---------------------------------------------------------------------------------
-- Apply state
---------------------------------------------------------------------------------

-- Single entry point for visibility changes. Defers if in combat lockdown
-- because RegisterStateDriver/UnregisterStateDriver write secure attributes
-- that are blocked while protected. The deferred path replays on
-- PLAYER_REGEN_ENABLED.
function WT:ApplyState()
    local bar = GetGameBarFrame()
    if not bar then return end
    if not self.db or not self.db.Enabled then return end

    if InCombatLockdown() then
        self._pendingApply = true
        return
    end
    self._pendingApply = nil

    if self.db.HideInMythicPlus and self:IsInMythicPlus() then
        UnregisterStateDriver(bar, "visibility")
        bar:Hide()
        self._hardHidden = true
        dprint("hard-hide (M+)")
    else
        self._hardHidden = false
        local s = BuildVisibilityString(self.db)
        RegisterStateDriver(bar, "visibility", s)
        dprint("driver → " .. s)
    end
end

-- Called from GUI when user toggles HideInCombat / HideInMythicPlus or edits
-- the underlying WindTools string. Re-evaluates and re-applies.
function WT:Refresh()
    if not self:IsEnabled() then return end
    self:ApplyState()
end

---------------------------------------------------------------------------------
-- Restore (used on disable)
---------------------------------------------------------------------------------

-- Hand the state driver back to WindTools' saved string. No-op if combat-
-- locked (the user can /reload or the next PLAYER_REGEN_ENABLED will catch
-- it via the module's normal flow when re-enabled).
function WT:RestoreOriginal()
    local bar = GetGameBarFrame()
    if not bar then return end
    if InCombatLockdown() then return end
    local original = GetUserVisibilityString() or DEFAULT_VISIBILITY
    RegisterStateDriver(bar, "visibility", original)
    bar:Show()
end

---------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------

-- WindTools' GB:PLAYER_ENTERING_WORLD does E:Delay(1, ...) → ProfileUpdate
-- → UpdateBar, which calls RegisterStateDriver and clobbers ours. Hook
-- UpdateBar as a SecureHook so our state always lands AFTER theirs. Done
-- lazily because WindTools might not be loaded at OnEnable time.
function WT:TryHookWindTools()
    if self._wtHooked then return true end
    if not LibStub then return false end
    local AceAddon = LibStub("AceAddon-3.0", true)
    if not AceAddon then return false end
    local W = AceAddon:GetAddon("ElvUI_WindTools", true)
    if not W then return false end
    local GB = W.GetModule and W:GetModule("GameBar", true)
    if not GB then return false end

    self:SecureHook(GB, "UpdateBar", function() self:ApplyState() end)
    self._wtHooked = true
    dprint("hooked WindTools GameBar.UpdateBar")
    return true
end

function WT:OnEnable()
    if not self.db or not self.db.Enabled then return end

    self:RegisterEvent("PLAYER_ENTERING_WORLD",      "OnZoneChanged")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA",      "OnZoneChanged")
    self:RegisterEvent("CHALLENGE_MODE_START",       "OnMythicStateChange")
    self:RegisterEvent("CHALLENGE_MODE_RESET",       "OnMythicStateChange")
    self:RegisterEvent("CHALLENGE_MODE_COMPLETED",   "OnMythicStateChange")
    self:RegisterEvent("PLAYER_REGEN_ENABLED",       "OnCombatEnd")

    -- Try once now (WindTools usually loaded by KE OnEnable time), then
    -- retry through PLAYER_ENTERING_WORLD if it wasn't ready. Initial apply
    -- waits past WindTools' own 1s ProfileUpdate delay; the hook handles
    -- every UpdateBar after that.
    self:TryHookWindTools()
    C_Timer.After(1.5, function()
        self:TryHookWindTools()
        self:ApplyState()
    end)
end

function WT:OnDisable()
    self:UnhookAll()
    self._wtHooked = false
    self:UnregisterAllEvents()
    self:RestoreOriginal()
    self._pendingApply = nil
    self._hardHidden = false
end

function WT:OnZoneChanged()
    -- Late retry in case WindTools loaded after our OnEnable (LoD profile,
    -- /reloadui timing edge cases). Hook is idempotent via _wtHooked guard.
    if not self._wtHooked then self:TryHookWindTools() end
    self:ApplyState()
end

function WT:OnMythicStateChange()
    self:ApplyState()
end

function WT:OnCombatEnd()
    if self._pendingApply then
        self:ApplyState()
    end
end
