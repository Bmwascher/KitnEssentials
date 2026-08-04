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

-- Aura-addon detection. GetAddOnInfo THROWS for an addon that isn't installed
-- rather than returning nil, so an unwrapped call short-circuits the whole
-- check on the first missing name -- hence the pcall per name. This tests
-- INSTALLED, not loaded: a user who has M33kAuras but hasn't loaded it yet
-- still owns /wa.
local AURA_ADDONS = { "WeakAuras", "M33kAuras", "M33kAurasOptions" }

local function IsAddOnInstalled(name)
    if not C_AddOns or not C_AddOns.GetAddOnInfo then return false end
    local ok, result = pcall(C_AddOns.GetAddOnInfo, name)
    return ok and result ~= nil
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

local function RegisterCDM()
    local wantWA = WantsWA()

    if cdmRegistered and waRegistered == wantWA then return end

    SLASH_KE_CDM1 = "/cd"
    if wantWA then
        SLASH_KE_CDM2 = "/wa"
    else
        SLASH_KE_CDM2 = nil
    end
    waRegistered = wantWA

    if not cdmRegistered then
        function SlashCmdList.KE_CDM(msg, editbox)
            ShowCooldownViewerSettings()
        end
        cdmRegistered = true
    end
end

local function UnregisterCDM()
    if not cdmRegistered then return end
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
