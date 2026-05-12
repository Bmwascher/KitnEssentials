-- ╔══════════════════════════════════════════════════════════╗
-- ║  SlashCommands.lua                                       ║
-- ║  Module: Slash Commands                                  ║
-- ║  Purpose: Registers /cd, /wa, /rl, /fs, /leave, /drop,   ║
-- ║           /reset, /mute, /music, and macro helpers.      ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local InCombatLockdown = InCombatLockdown
local ReloadUI = ReloadUI
local GetCVar = C_CVar.GetCVar
local SetCVar = C_CVar.SetCVar
local IsInGroup = IsInGroup
local UnitIsGroupLeader = UnitIsGroupLeader
local _G = _G
local table_insert = table.insert
local print = print

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------
local db
local PREFIX = "|cffFF008CKitn:|r "

---------------------------------------------------------------------------------
-- Core Logic
---------------------------------------------------------------------------------

-- /cd and /wa --

local cdmRegistered = false

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

local function RegisterCDM()
    if cdmRegistered then return end
    local waLoaded = WeakAuras ~= nil
    SLASH_KE_CDM1 = "/cd"
    if not waLoaded then
        SLASH_KE_CDM2 = "/wa"
    end
    function SlashCmdList.KE_CDM(msg, editbox)
        ShowCooldownViewerSettings()
    end
    cdmRegistered = true
end

local function UnregisterCDM()
    if not cdmRegistered then return end
    SLASH_KE_CDM1 = nil
    SLASH_KE_CDM2 = nil
    SlashCmdList.KE_CDM = nil
    cdmRegistered = false
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

-- /fs --

local fsRegistered = false

local function RegisterFS()
    if fsRegistered then return end
    SLASH_KE_FS1 = "/fs"
    function SlashCmdList.KE_FS(msg, editbox)
        UIParentLoadAddOn("Blizzard_DebugTools")
        FrameStackTooltip_Toggle()
    end
    fsRegistered = true
end

local function UnregisterFS()
    if not fsRegistered then return end
    SLASH_KE_FS1 = nil
    SlashCmdList.KE_FS = nil
    fsRegistered = false
end

-- /leave + /drop --

local leaveRegistered = false

local function RegisterLeaveParty()
    if leaveRegistered then return end
    SLASH_KE_LEAVE1 = "/leave"
    SLASH_KE_LEAVE2 = "/drop"
    function SlashCmdList.KE_LEAVE(msg, editbox)
        if IsInGroup() then
            C_PartyInfo.LeaveParty()
            print(PREFIX .. "Left the group.")
        else
            print(PREFIX .. "You are not in a group.")
        end
    end
    leaveRegistered = true
end

local function UnregisterLeaveParty()
    if not leaveRegistered then return end
    SLASH_KE_LEAVE1 = nil
    SLASH_KE_LEAVE2 = nil
    SlashCmdList.KE_LEAVE = nil
    leaveRegistered = false
end

-- /reset --

local resetRegistered = false

local function RegisterResetInstances()
    if resetRegistered then return end
    SLASH_KE_RESET1 = "/reset"
    function SlashCmdList.KE_RESET(msg, editbox)
        if not IsInGroup() or UnitIsGroupLeader("player") then
            ResetInstances()
            print(PREFIX .. "Instances reset.")
        else
            print(PREFIX .. "Only the party leader can reset instances.")
        end
    end
    resetRegistered = true
end

local function UnregisterResetInstances()
    if not resetRegistered then return end
    SLASH_KE_RESET1 = nil
    SlashCmdList.KE_RESET = nil
    resetRegistered = false
end

-- /mute --

local muteRegistered = false

local function RegisterMute()
    if muteRegistered then return end
    SLASH_KE_MUTE1 = "/mute"
    function SlashCmdList.KE_MUTE(msg, editbox)
        local current = GetCVar("Sound_EnableAllSound")
        local newVal = current == "1" and "0" or "1"
        SetCVar("Sound_EnableAllSound", newVal)
        local status = newVal == "1" and "unmuted" or "muted"
        print(PREFIX .. "Sound " .. status .. ".")
    end
    muteRegistered = true
end

local function UnregisterMute()
    if not muteRegistered then return end
    SLASH_KE_MUTE1 = nil
    SlashCmdList.KE_MUTE = nil
    muteRegistered = false
end

-- /music --

local musicRegistered = false

local function RegisterMusic()
    if musicRegistered then return end
    SLASH_KE_MUSIC1 = "/music"
    function SlashCmdList.KE_MUSIC(msg, editbox)
        local current = GetCVar("Sound_EnableMusic")
        local newVal = current == "1" and "0" or "1"
        SetCVar("Sound_EnableMusic", newVal)
        local status = newVal == "1" and "enabled" or "disabled"
        print(PREFIX .. "Music " .. status .. ".")
    end
    musicRegistered = true
end

local function UnregisterMusic()
    if not musicRegistered then return end
    SLASH_KE_MUSIC1 = nil
    SlashCmdList.KE_MUSIC = nil
    musicRegistered = false
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
            print(PREFIX .. "PI Macro Builder is not enabled.")
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
        print(PREFIX .. "Chat cleared.")
    end

    -- /kitn chatbubbles — toggle chat bubbles
    KitnCommands["chatbubbles"] = function()
        local enabled = ToggleCVar("chatBubbles")
        print(PREFIX .. "Chat bubbles " .. (enabled and "enabled" or "disabled") .. ".")
    end

    -- /kitn nameplates — toggle enemy nameplates
    KitnCommands["nameplates"] = function()
        local enabled = ToggleCVar("nameplateShowEnemies")
        print(PREFIX .. "Enemy nameplates " .. (enabled and "enabled" or "disabled") .. ".")
    end

    -- /kitn friendplates — toggle friendly nameplates
    KitnCommands["friendplates"] = function()
        local enabled = ToggleCVar("nameplateShowFriends")
        print(PREFIX .. "Friendly nameplates " .. (enabled and "enabled" or "disabled") .. ".")
    end

    -- /kitn actioncam — toggle action camera
    KitnCommands["actioncam"] = function()
        local enabled = ToggleCVar("test_cameraOverShoulder")
        SetCVar("test_cameraDynamicPitch", enabled and "1" or "0")
        print(PREFIX .. "Action camera " .. (enabled and "enabled" or "disabled") .. ".")
    end

    -- /kitn errors — toggle Lua error display
    KitnCommands["errors"] = function()
        local enabled = ToggleCVar("scriptErrors")
        print(PREFIX .. "Lua errors " .. (enabled and "shown" or "hidden") .. ".")
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

    if db.FSEnabled then
        RegisterFS()
    else
        UnregisterFS()
    end

    if db.LeavePartyEnabled then
        RegisterLeaveParty()
    else
        UnregisterLeaveParty()
    end

    if db.ResetInstancesEnabled then
        RegisterResetInstances()
    else
        UnregisterResetInstances()
    end

    if db.MuteEnabled then
        RegisterMute()
    else
        UnregisterMute()
    end

    if db.MusicEnabled then
        RegisterMusic()
    else
        UnregisterMusic()
    end

    -- Always register /kitn subcommands
    RegisterKitnCommands()
end
