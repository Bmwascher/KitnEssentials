-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

-- Slash Commands: /cd, /wa (Cooldown Manager), /rl (Reload UI), /fs (Frame Stack),
-- /leave + /drop (Leave Party), /reset (Reset Instances), /mute, /music,
-- SetPITarget macro helper, and /kitn subcommand integration

local InCombatLockdown = InCombatLockdown
local UnitName = UnitName
local ReloadUI = ReloadUI
local IsAddOnLoaded = C_AddOns.IsAddOnLoaded
local GetCVar = C_CVar.GetCVar
local SetCVar = C_CVar.SetCVar
local IsInGroup = IsInGroup
local UnitIsGroupLeader = UnitIsGroupLeader
local _G = _G
local table_insert = table.insert
local print = print

local db
local PREFIX = "|cffFF008CKitn:|r "

------------------------------------------------------------------------
-- CDM Slash Command (/cd and /wa)
------------------------------------------------------------------------
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
    local waLoaded = IsAddOnLoaded("WeakAuras")
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

------------------------------------------------------------------------
-- SetPITarget global function
------------------------------------------------------------------------
local piRegistered = false

local function BuildPIMacro(targetName)
    local lines = { "#showtooltip" }
    table_insert(lines, "/cast [@mouseover,help,nodead][@" .. targetName .. ",exists,nodead][] Power Infusion")
    if db.PITrinket1 then table_insert(lines, "/use 13") end
    if db.PITrinket2 then table_insert(lines, "/use 14") end
    if db.PIVampiricEmbrace then table_insert(lines, "/use Vampiric Embrace") end
    for _, key in ipairs({ "PIRacial", "PIConsumable", "PICustom" }) do
        local val = db[key]
        if val and val ~= "" then
            table_insert(lines, "/use " .. val)
        end
    end
    return table.concat(lines, "\n")
end

local function RegisterSetPITarget()
    if piRegistered then return end
    _G.SetPITarget = function()
        local macroIndex = GetMacroIndexByName("PI")
        if not macroIndex or macroIndex == 0 then
            print(PREFIX .. "|cffFF4444No macro named \"PI\" found. Create one first.|r")
            return
        end
        local n = UnitName("mouseover") or UnitName("target") or "target"
        if not InCombatLockdown() then
            EditMacro(macroIndex, nil, nil, BuildPIMacro(n))
            print(PREFIX .. "PI macro updated to " .. n)
        end
    end
    piRegistered = true
end

local function UnregisterSetPITarget()
    if not piRegistered then return end
    _G.SetPITarget = nil
    piRegistered = false
end

------------------------------------------------------------------------
-- /rl Slash Command (Reload UI)
------------------------------------------------------------------------
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

------------------------------------------------------------------------
-- /fs Slash Command (Frame Stack)
------------------------------------------------------------------------
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

------------------------------------------------------------------------
-- /leave + /drop Slash Command (Leave Party/Raid)
------------------------------------------------------------------------
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

------------------------------------------------------------------------
-- /reset Slash Command (Reset Instances)
------------------------------------------------------------------------
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

------------------------------------------------------------------------
-- /mute Slash Command (Toggle Master Sound)
------------------------------------------------------------------------
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

------------------------------------------------------------------------
-- /music Slash Command (Toggle Music)
------------------------------------------------------------------------
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

------------------------------------------------------------------------
-- /kitn subcommand integration
------------------------------------------------------------------------
local kitnHooked = false

local function ToggleCVar(cvar)
    local current = GetCVar(cvar)
    local newVal = current == "1" and "0" or "1"
    SetCVar(cvar, newVal)
    return newVal == "1"
end

local function RegisterKitnCommands()
    if kitnHooked then return end

    -- Ensure the global tables exist (KitnUI/KitnUI Lite creates KitnCommands,
    -- but KE may load first)
    KitnCommands = KitnCommands or {}
    KitnHelpLines = KitnHelpLines or {}

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

    -- /kitn pi — set PI target (calls SetPITarget)
    KitnCommands["pi"] = function()
        if _G.SetPITarget then
            _G.SetPITarget()
        else
            print(PREFIX .. "SetPITarget is not enabled.")
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

    -- Help lines (printed by KitnUI/KitnUI Lite after their own help)
    table_insert(KitnHelpLines, "  |cff888888— KitnEssentials —|r")
    table_insert(KitnHelpLines, "  /kitn essentials   - Open KitnEssentials settings")
    table_insert(KitnHelpLines, "  /kitn cd           - Toggle Cooldown Manager panel")
    table_insert(KitnHelpLines, "  /kitn edit         - Toggle Edit Mode (drag UI elements)")
    table_insert(KitnHelpLines, "  /kitn pi           - Set PI macro target (mouseover or target)")
    table_insert(KitnHelpLines, "  /kitn clearchat    - Clear all chat frames")
    table_insert(KitnHelpLines, "  /kitn chatbubbles  - Toggle chat bubbles")
    table_insert(KitnHelpLines, "  /kitn nameplates   - Toggle enemy nameplates")
    table_insert(KitnHelpLines, "  /kitn friendplates - Toggle friendly nameplates")
    table_insert(KitnHelpLines, "  /kitn actioncam    - Toggle action camera")
    table_insert(KitnHelpLines, "  /kitn errors       - Toggle Lua error display")

    kitnHooked = true
end

------------------------------------------------------------------------
-- Module init — called from Main.lua profile callbacks
------------------------------------------------------------------------
function KE:ApplySlashCommands()
    db = KE.db and KE.db.profile.SlashCommands
    if not db then return end

    if db.CDMEnabled then
        RegisterCDM()
    else
        UnregisterCDM()
    end

    if db.SetPITargetEnabled then
        RegisterSetPITarget()
    else
        UnregisterSetPITarget()
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
