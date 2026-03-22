-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local CL = KitnEssentials:NewModule("CombatLogger", "AceEvent-3.0", "AceTimer-3.0")

-- Localization
local GetInstanceInfo = GetInstanceInfo
local LoggingCombat = LoggingCombat
local C_CVar = C_CVar
local C_PvP = C_PvP
local C_Timer = C_Timer
local IsArenaSkirmish = C_PvP.IsArenaSkirmish
local IsWargame = IsWargame
local ReloadUI = ReloadUI

-- Module state
CL.isLogging = false
CL.delayStopTimer = nil
CL.arenaCheckTimer = nil

function CL:UpdateDB()
    self.db = KE.db.profile.CombatLogger
end

function CL:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

--------------------------------------------------------------------------------
-- ACL (Advanced Combat Logging) check
--------------------------------------------------------------------------------
StaticPopupDialogs["KE_COMBATLOGGER_ACL_PROMPT"] = {
    text = "|cffFF008CKitnEssentials|r\n\nAdvanced Combat Logging is disabled. This is required for detailed log analysis on Warcraft Logs.\n\nEnable it now?",
    button1 = "Enable & Reload",
    button2 = "Skip",
    OnAccept = function()
        C_CVar.SetCVar("advancedCombatLogging", "1")
        ReloadUI()
    end,
    timeout = 0,
    whileDead = false,
    hideOnEscape = true,
    preferredIndex = 3,
}

function CL:CheckACL()
    if self.db.DisableACLPrompt then return true end
    local acl = C_CVar.GetCVar("advancedCombatLogging")
    if acl ~= "1" then
        StaticPopup_Show("KE_COMBATLOGGER_ACL_PROMPT")
        return false
    end
    return true
end

--------------------------------------------------------------------------------
-- Start / Stop logging
--------------------------------------------------------------------------------
function CL:StartLogging()
    -- Cancel any pending delayed stop
    if self.delayStopTimer then
        self:CancelTimer(self.delayStopTimer)
        self.delayStopTimer = nil
    end

    if not self.isLogging then
        LoggingCombat(true)
        self.isLogging = true
        KE:Print("Combat logging |cff00ff00started|r.")
    end
end

function CL:StopLogging()
    if not self.isLogging then return end

    if self.db.DelayStop then
        if not self.delayStopTimer then
            KE:Print("Combat logging will stop in 30 seconds...")
            self.delayStopTimer = self:ScheduleTimer("StopLoggingNow", 30)
        end
    else
        self:StopLoggingNow()
    end
end

function CL:StopLoggingNow()
    if self.delayStopTimer then
        self:CancelTimer(self.delayStopTimer)
        self.delayStopTimer = nil
    end

    if self.isLogging then
        LoggingCombat(false)
        self.isLogging = false
        KE:Print("Combat logging |cffff4444stopped|r.")
    end
end

--------------------------------------------------------------------------------
-- Instance / difficulty mapping
--------------------------------------------------------------------------------
function CL:ShouldLog(instanceType, difficultyID, maxPlayers)
    local db = self.db

    if instanceType == "party" then
        -- Guard: maxPlayers <= 5 to exclude raids queued as party
        if maxPlayers and maxPlayers > 5 then return false end

        if difficultyID == 1 then return db.DungeonNormal end
        if difficultyID == 2 then return db.DungeonHeroic end
        if difficultyID == 23 then return db.DungeonMythic end
        if difficultyID == 8 then return db.DungeonMythicPlus end
        if difficultyID == 24 then return db.DungeonTimewalking end
        return false

    elseif instanceType == "raid" then
        if difficultyID == 7 or difficultyID == 17 then return db.RaidLFR end
        if difficultyID == 3 or difficultyID == 4 or difficultyID == 9 or difficultyID == 14 then return db.RaidNormal end
        if difficultyID == 5 or difficultyID == 6 or difficultyID == 15 then return db.RaidHeroic end
        if difficultyID == 16 then return db.RaidMythic end
        if difficultyID == 33 or difficultyID == 151 then return db.RaidTimewalking end
        return false

    elseif instanceType == "pvp" then
        if C_PvP.IsRatedBattleground() then return db.PvPRatedBG end
        return db.PvPRegularBG

    elseif instanceType == "scenario" then
        if difficultyID == 167 then return db.ScenarioTorghast end
        return false
    end

    return false
end

--------------------------------------------------------------------------------
-- Arena check (needs 5s delay for API readiness)
--------------------------------------------------------------------------------
function CL:CheckArenaLogging()
    local db = self.db
    local shouldLog = false

    if C_PvP.IsRatedArena() and not IsArenaSkirmish() and not C_PvP.IsSoloShuffle() and not IsWargame() then
        shouldLog = db.PvPRatedArena
    elseif IsArenaSkirmish() then
        shouldLog = db.PvPArenaSkirmish
    elseif C_PvP.IsSoloShuffle() then
        shouldLog = db.PvPSoloShuffle
    elseif IsWargame() then
        shouldLog = db.PvPWarGame
    end

    if shouldLog then
        if self:CheckACL() then
            self:StartLogging()
        end
    elseif self.isLogging then
        self:StopLogging()
    end
end

--------------------------------------------------------------------------------
-- Zone check handlers
--------------------------------------------------------------------------------
function CL:CheckEnableLogging()
    if not self.db.Enabled then return end

    local _, instanceType, difficultyID, _, maxPlayers = GetInstanceInfo()

    -- Arena handled separately
    if instanceType == "arena" then return end

    if self:ShouldLog(instanceType, difficultyID, maxPlayers) then
        if not self.isLogging then
            if self:CheckACL() then
                self:StartLogging()
            end
        end
    end
end

function CL:CheckDisableLogging()
    -- Nothing to stop if we're not logging and have no pending timer
    if not self.isLogging and not self.delayStopTimer then return end

    local _, instanceType, difficultyID, _, maxPlayers = GetInstanceInfo()

    if not instanceType or instanceType == "none" then
        self:StopLogging()
        return
    end

    -- Arena handled separately
    if instanceType == "arena" then return end

    -- Still in instance but this content type is disabled
    if not self:ShouldLog(instanceType, difficultyID, maxPlayers) then
        if self.isLogging then
            self:StopLogging()
        end
    end
end

--------------------------------------------------------------------------------
-- Event handlers
--------------------------------------------------------------------------------
function CL:OnEvent_InstanceInfo()
    self:CheckEnableLogging()
end

function CL:OnEvent_ZoneChanged()
    self:CheckDisableLogging()
end

function CL:OnEvent_EnteringWorld()
    -- Sync logging state
    self.isLogging = LoggingCombat() or false

    local _, instanceType = GetInstanceInfo()
    if instanceType == "arena" then
        -- Arena APIs need a delay
        if self.arenaCheckTimer then
            self:CancelTimer(self.arenaCheckTimer)
        end
        self.arenaCheckTimer = self:ScheduleTimer(function()
            self.arenaCheckTimer = nil
            self:CheckArenaLogging()
        end, 5)
    else
        self:CheckEnableLogging()
    end
end

--------------------------------------------------------------------------------
-- Module lifecycle
--------------------------------------------------------------------------------
function CL:ApplySettings()
    if not self.db.Enabled then return end
    -- Re-evaluate current zone with new settings
    self:OnEvent_EnteringWorld()
end

function CL:OnEnable()
    if not self.db.Enabled then return end

    -- Sync initial logging state (LoggingCombat() with no args returns current state)
    self.isLogging = LoggingCombat() or false

    -- Register events
    self:RegisterEvent("UPDATE_INSTANCE_INFO", "OnEvent_InstanceInfo")
    self:RegisterEvent("PLAYER_DIFFICULTY_CHANGED", "OnEvent_InstanceInfo")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "OnEvent_ZoneChanged")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEvent_EnteringWorld")
    self:RegisterEvent("CHALLENGE_MODE_START", "OnEvent_InstanceInfo")

    -- Check ACL on login
    C_Timer.After(2, function()
        self:CheckACL()
    end)

    -- Check current zone immediately
    C_Timer.After(1, function()
        self:OnEvent_EnteringWorld()
    end)
end

function CL:OnDisable()
    if self.isLogging then
        self:StopLoggingNow()
    end
    if self.delayStopTimer then
        self:CancelTimer(self.delayStopTimer)
        self.delayStopTimer = nil
    end
    if self.arenaCheckTimer then
        self:CancelTimer(self.arenaCheckTimer)
        self.arenaCheckTimer = nil
    end
    self:UnregisterAllEvents()
end
