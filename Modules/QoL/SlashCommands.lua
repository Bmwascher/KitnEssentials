-- ╔══════════════════════════════════════════════════════════╗
-- ║  SlashCommands.lua                                       ║
-- ║  Module: Slash Commands                                  ║
-- ║  Purpose: Registers /cd, /wa, /rl and the /kitn          ║
-- ║           subcommands.                                   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local InCombatLockdown = InCombatLockdown
local ReloadUI = ReloadUI
local GetCVar = C_CVar.GetCVar
local SetCVar = C_CVar.SetCVar
local _G = _G
local ipairs = ipairs
local table_insert = table.insert

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------
local db

---------------------------------------------------------------------------------
-- Core Logic
---------------------------------------------------------------------------------

-- /cd and /wa --

local cdmRegistered = false
local waRegistered = false

local function ShowCooldownViewerSettings()
    if InCombatLockdown() then return end
    local CooldownViewerSettings = _G.CooldownViewerSettings
    if not CooldownViewerSettings then return end

    if not CooldownViewerSettings:IsShown() then
        CooldownViewerSettings:Show()
    else
        CooldownViewerSettings:Hide()
    end
end

-- Aura-addon detection. DoesAddOnExist is the only call that answers this
-- directly: GetAddOnInfo's name return is non-nilable, so its result cannot
-- distinguish an installed addon from a missing one. This tests INSTALLED,
-- not loaded: a user who has M33kAuras but hasn't loaded it yet still owns /wa.
local AURA_ADDONS = { "WeakAuras", "M33kAuras", "M33kAurasOptions" }

local function IsAddOnInstalled(name)
    if not C_AddOns or not C_AddOns.DoesAddOnExist then return false end
    return C_AddOns.DoesAddOnExist(name) == true
end

function KE:HasAuraAddon()
    for _, name in ipairs(AURA_ADDONS) do
        if IsAddOnInstalled(name) then return true end
    end
    return false
end

-- /wa is offered only when nothing else owns it AND the user has not turned it
-- off. Tracked apart from /cd so the two can be re-applied independently: a
-- single registered flag made every apply after the first a no-op, which left
-- the alias live after the setting was switched off.
local function WantsWA()
    return (db == nil or db.WAEnabled ~= false) and not KE:HasAuraAddon()
end

-- The chat engine reads SLASH_KE_CDM1/2 only while it imports SlashCmdList,
-- and it moves every imported entry behind a proxy metatable and wipes the
-- table afterwards. Two consequences drive the shape below: an alias global
-- assigned after the handler was first registered is never read, and clearing
-- SlashCmdList.KE_CDM does not reach the imported copy or the resolved-command
-- cache. So every state change must drop the cached aliases AND write the
-- handler back, which is what makes the next import re-read the globals.
local function ForgetAlias(alias)
    local key = alias:upper()
    if _G.hash_SlashCmdList then _G.hash_SlashCmdList[key] = nil end
    if _G.hash_ChatTypeInfoList then _G.hash_ChatTypeInfoList[key] = nil end
end

local function CDMHandler()
    ShowCooldownViewerSettings()
end

local function RegisterCDM()
    local wantWA = WantsWA()

    if cdmRegistered and waRegistered == wantWA then return end

    ForgetAlias("/cd")
    ForgetAlias("/wa")

    SLASH_KE_CDM1 = "/cd"
    SLASH_KE_CDM2 = wantWA and "/wa" or nil
    SlashCmdList.KE_CDM = CDMHandler

    cdmRegistered = true
    waRegistered = wantWA
end

local function UnregisterCDM()
    if not cdmRegistered then return end
    ForgetAlias("/cd")
    ForgetAlias("/wa")
    SLASH_KE_CDM1 = nil
    SLASH_KE_CDM2 = nil
    SlashCmdList.KE_CDM = nil
    cdmRegistered = false
    waRegistered = false
end

-- /rl --

local rlRegistered = false

local function RegisterRL()
    if rlRegistered then return end
    SLASH_KE_RL1 = "/rl"
    function SlashCmdList.KE_RL(msg, editbox)
        ReloadUI()
    end
    rlRegistered = true
end

local function UnregisterRL()
    if not rlRegistered then return end
    ForgetAlias("/rl")
    SLASH_KE_RL1 = nil
    SlashCmdList.KE_RL = nil
    rlRegistered = false
end

-- /kitn subcommands --

local kitnHooked = false

local function ToggleCVar(cvar)
    local current = GetCVar(cvar)
    local newVal = current == "1" and "0" or "1"
    SetCVar(cvar, newVal)
    return newVal == "1"
end

local function RegisterKitnCommands()
    if kitnHooked then return end

    -- Ensure the global table exists (KitnUI/KitnUI Lite creates KitnCommands,
    -- but KE may load first)
    KitnCommands = KitnCommands or {}

    -- /kitn essentials — open KE settings
    KitnCommands["essentials"] = function()
        if KE.GUIFrame then KE.GUIFrame:Toggle() end
    end
    KitnCommands["kes"] = KitnCommands["essentials"]

    -- /kitn cd — toggle Cooldown Manager
    KitnCommands["cd"] = function()
        ShowCooldownViewerSettings()
    end

    -- /kitn edit — toggle edit mode
    KitnCommands["edit"] = function()
        if KE.EditMode then KE.EditMode:Toggle() end
    end

    -- /kitn pi — set PI target (calls into PIMacroBuilder module)
    KitnCommands["pi"] = function()
        local PImod = KitnEssentials:GetModule("PIMacroBuilder", true)
        if PImod and PImod:IsEnabled() then
            PImod:SetPITarget()
        else
            KE:Print("PI Macro Builder is not enabled.")
        end
    end

    -- /kitn clearchat — clear all visible chat frames
    KitnCommands["clearchat"] = function()
        for i = 1, NUM_CHAT_WINDOWS do
            local frame = _G["ChatFrame" .. i]
            if frame and frame:IsShown() then
                frame:Clear()
            end
        end
        KE:Print("Chat cleared.")
    end

    -- /kitn chatbubbles — toggle chat bubbles
    KitnCommands["chatbubbles"] = function()
        local enabled = ToggleCVar("chatBubbles")
        KE:Print("Chat bubbles " .. (enabled and "enabled" or "disabled") .. ".")
    end

    -- /kitn nameplates — toggle enemy nameplates
    KitnCommands["nameplates"] = function()
        local enabled = ToggleCVar("nameplateShowEnemies")
        KE:Print("Enemy nameplates " .. (enabled and "enabled" or "disabled") .. ".")
    end

    -- /kitn friendplates — toggle friendly nameplates
    KitnCommands["friendplates"] = function()
        local enabled = ToggleCVar("nameplateShowFriends")
        KE:Print("Friendly nameplates " .. (enabled and "enabled" or "disabled") .. ".")
    end

    -- /kitn actioncam — toggle action camera
    KitnCommands["actioncam"] = function()
        local enabled = ToggleCVar("test_cameraOverShoulder")
        SetCVar("test_cameraDynamicPitch", enabled and "1" or "0")
        KE:Print("Action camera " .. (enabled and "enabled" or "disabled") .. ".")
    end

    -- /kitn errors — toggle Lua error display
    KitnCommands["errors"] = function()
        local enabled = ToggleCVar("scriptErrors")
        KE:Print("Lua errors " .. (enabled and "shown" or "hidden") .. ".")
    end

    -- Slash lines (printed by /kitn slash)
    KitnSlashLines = KitnSlashLines or {}
    table_insert(KitnSlashLines, "  |cff888888— KitnEssentials —|r")
    table_insert(KitnSlashLines, "  /kitn essentials   - Open KitnEssentials settings")
    table_insert(KitnSlashLines, "  /kitn cd           - Toggle Cooldown Manager panel")
    table_insert(KitnSlashLines, "  /kitn edit         - Toggle Edit Mode (drag UI elements)")
    table_insert(KitnSlashLines, "  /kitn pi           - Set PI macro target (mouseover or target)")
    table_insert(KitnSlashLines, "  /kitn clearchat    - Clear all chat frames")
    table_insert(KitnSlashLines, "  /kitn chatbubbles  - Toggle chat bubbles")
    table_insert(KitnSlashLines, "  /kitn nameplates   - Toggle enemy nameplates")
    table_insert(KitnSlashLines, "  /kitn friendplates - Toggle friendly nameplates")
    table_insert(KitnSlashLines, "  /kitn actioncam    - Toggle action camera")
    table_insert(KitnSlashLines, "  /kitn errors       - Toggle Lua error display")

    kitnHooked = true
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
function KE:IsWAEnabled()
    local settings = KE.db and KE.db.profile.SlashCommands
    return not (settings and settings.WAEnabled == false)
end

-- Returns the new state so a caller can report it without re-reading the db.
function KE:SetWAEnabled(enabled)
    local settings = KE.db and KE.db.profile.SlashCommands
    if not settings then return KE:IsWAEnabled() end
    settings.WAEnabled = enabled and true or false
    KE:ApplySlashCommands()
    return settings.WAEnabled
end

-- Anything that is not "on" or "off" reports the current state rather than
-- guessing at an intent.
function KE:HandleWACommand(arg)
    arg = arg and arg:lower() or ""
    if arg == "on" or arg == "off" then
        KE:SetWAEnabled(arg == "on")
        KE:Print("/wa " .. arg .. ".")
        -- Turning the alias on while the whole command pair is off would
        -- otherwise report success and register nothing.
        local settings = KE.db and KE.db.profile.SlashCommands
        if arg == "on" and settings and settings.CDMEnabled == false then
            KE:Print("Note: the Cooldown Manager commands are switched off, so " ..
                "neither /cd nor /wa is registered right now.")
        end
        return
    end

    if KE:IsWAEnabled() then
        KE:Print("/wa is on. It is registered unless another aura addon owns it.")
    else
        KE:Print("/wa is off. /cd is unaffected.")
    end
    KE:Print("Use " .. KE:ColorTextByTheme("/kes wa on") .. " or " ..
        KE:ColorTextByTheme("/kes wa off") .. ".")
end

function KE:ApplySlashCommands()
    db = KE.db and KE.db.profile.SlashCommands
    if not db then return end

    if db.CDMEnabled then
        RegisterCDM()
    else
        UnregisterCDM()
    end

    if db.RLEnabled then
        RegisterRL()
    else
        UnregisterRL()
    end

    -- Always register /kitn subcommands
    RegisterKitnCommands()
end
