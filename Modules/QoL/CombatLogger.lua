-- ╔══════════════════════════════════════════════════════════╗
-- ║  CombatLogger.lua                                        ║
-- ║  Module: Combat Logger                                   ║
-- ║  Purpose: Automatic combat logging for raids, dungeons,  ║
-- ║           M+, PvP, and arenas with per-content toggles.  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local CL = KitnEssentials:NewModule("CombatLogger", "AceEvent-3.0", "AceTimer-3.0")

local GetInstanceInfo = GetInstanceInfo
local LoggingCombat = LoggingCombat
local C_ChatInfo = C_ChatInfo
local C_CVar = C_CVar
local C_PvP = C_PvP
local C_Timer = C_Timer
-- A plain global, not a C_PvP member: the namespaced name is nil, so caching it
-- here left every arena check calling nil. Blizzard's own PvP match code calls
-- the global form.
local IsArenaSkirmish = IsArenaSkirmish
local IsWargame = IsWargame

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------
CL.isLogging = false      -- what the client reports
CL.startedByUs = false    -- ...and whether this module is the one that asked
CL.delayStopTimer = nil
CL.arenaCheckTimer = nil

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function CL:UpdateDB()
    self.db = KE.db.profile.CombatLogger
end

function CL:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

---------------------------------------------------------------------------------
-- Frame Creation
---------------------------------------------------------------------------------
-- No reload. Blizzard's own control for this is a plain SetupCVarCheckbox
-- (Blizzard_SettingsDefinitions_Shared/Network.lua) whose only commit flag is
-- KioskProtected -- no Restart, no ClientRestart. What DOES need handling is a
-- log that is already running, because whether it is an advanced log was
-- decided when it opened; cycling it costs one file boundary, which every log
-- watcher already handles from an ordinary /combatlog toggle.
StaticPopupDialogs["KE_COMBATLOGGER_ACL_PROMPT"] = {
    text = "|cffFF008CKitnEssentials|r\n\nAdvanced Combat Logging is disabled. This is required for detailed log analysis on Warcraft Logs.\n\nEnable it now?",
    button1 = _G.ENABLE or "Enable",
    button2 = _G.CANCEL or "Cancel",
    OnAccept = function()
        local mod = KitnEssentials:GetModule("CombatLogger", true)
        if mod then mod:EnableAdvanced() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

---------------------------------------------------------------------------------
-- Core Logic
---------------------------------------------------------------------------------
function CL:IsAdvanced()
    return C_CVar.GetCVar("advancedCombatLogging") == "1"
end

function CL:EnableAdvanced()
    -- Compare before writing: SetCVar makes the client flush its config, which
    -- is expensive enough to be felt.
    if self:IsAdvanced() then return end
    C_CVar.SetCVar("advancedCombatLogging", "1")

    -- A running log keeps whatever format it opened with, so restart it.
    if self.isLogging then
        LoggingCombat(false)
        LoggingCombat(true)
    end

    if not self.db.QuietMode then
        KE:Print("Advanced Combat Logging is now |cff00ff00on|r.")
    end
end

-- Asks, and answers "yes" either way. Someone who turned the prompt off has not
-- said they want logging disabled, and a basic log beats no log -- accepting
-- the prompt later cycles the running log, which is what makes that ordering
-- safe.
function CL:CheckACL()
    if self:IsAdvanced() then return true end
    if not self.db.DisableACLPrompt then
        StaticPopup_Show("KE_COMBATLOGGER_ACL_PROMPT")
    end
    return true
end

function CL:StartLogging(label)
    -- Cancel any pending delayed stop
    if self.delayStopTimer then
        self:CancelTimer(self.delayStopTimer)
        self.delayStopTimer = nil
    end

    if self.isLogging then return end

    LoggingCombat(true)
    -- Believe the client rather than the call, so ownership is never claimed
    -- over a log that did not actually open.
    self:SyncLoggingState()
    if not self.isLogging then return end
    self.startedByUs = true

    if not self.db.QuietMode then
        KE:Print("Combat logging |cff00ff00started|r" .. (label and (" for " .. label) or "") .. ".")
    end
end

-- Read the client's own answer rather than trusting the flag, which a /reload
-- resets.
function CL:SyncLoggingState()
    local enabled
    if C_ChatInfo and C_ChatInfo.IsLoggingCombat then
        enabled = C_ChatInfo.IsLoggingCombat()
    else
        enabled = LoggingCombat()
    end
    self.isLogging = enabled and true or false
    -- Cannot own a log that is not running -- someone may have closed ours by
    -- hand. Without this, startedByUs outlives the log it described.
    if not self.isLogging then self.startedByUs = false end
    return self.isLogging
end

-- A /reload inside a raid loses startedByUs, so a log we opened would never be
-- closed again. If one is running in content we would have started it for, take
-- it back. One running anywhere else was started by hand and is left alone.
--
-- Adopting is the one path that changes who owns the log without changing
-- whether one is running, so it used to print nothing -- and this is the moment
-- the addon becomes the thing that will close it.
function CL:AdoptExistingLog(shouldLog, label)
    if not (self.isLogging and shouldLog) then return end
    if self.startedByUs then return end

    self.startedByUs = true
    if not self.db.QuietMode then
        KE:Print("Took over the combat log already running"
            .. (label and (" for " .. label) or "")
            .. "; it will be closed on the way out.")
    end
end

function CL:StopLogging()
    -- Never close a log we did not open. Someone who typed /combatlog by hand,
    -- or another addon's log, is not ours to end.
    if not self.isLogging or not self.startedByUs then return end

    if self.db.DelayStop then
        if not self.delayStopTimer then
            if not self.db.QuietMode then
                KE:Print("Combat logging will stop in 30 seconds...")
            end
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
        self.startedByUs = false
        if not self.db.QuietMode then
            KE:Print("Combat logging |cffff4444stopped|r.")
        end
    end
end

function CL:ShouldLog(instanceType, difficultyID, maxPlayers)
    local db = self.db

    if instanceType == "party" then
        -- Guard: maxPlayers <= 5 to exclude raids queued as party
        if maxPlayers and maxPlayers > 5 then return false end

        if difficultyID == 1 then return db.DungeonNormal == true, "a Normal dungeon" end
        if difficultyID == 2 then return db.DungeonHeroic == true, "a Heroic dungeon" end
        if difficultyID == 23 then return db.DungeonMythic == true, "a Mythic dungeon" end
        if difficultyID == 8 then return db.DungeonMythicPlus == true, "Mythic+" end
        if difficultyID == 24 then return db.DungeonTimewalking == true, "a Timewalking dungeon" end
        return false

    elseif instanceType == "raid" then
        if difficultyID == 7 or difficultyID == 17 then return db.RaidLFR == true, "LFR" end
        if difficultyID == 3 or difficultyID == 4 or difficultyID == 9 or difficultyID == 14 then
            return db.RaidNormal == true, "a Normal raid"
        end
        if difficultyID == 5 or difficultyID == 6 or difficultyID == 15 then
            return db.RaidHeroic == true, "a Heroic raid"
        end
        if difficultyID == 16 then return db.RaidMythic == true, "a Mythic raid" end
        if difficultyID == 33 or difficultyID == 151 then
            return db.RaidTimewalking == true, "a Timewalking raid"
        end
        return false

    elseif instanceType == "pvp" then
        if C_PvP.IsRatedBattleground() then return db.PvPRatedBG == true, "a rated battleground" end
        return db.PvPRegularBG == true, "a battleground"

    elseif instanceType == "scenario" then
        if difficultyID == 167 then return db.ScenarioTorghast == true, "Torghast" end
        return false
    end

    return false
end

function CL:CheckArenaLogging()
    local db = self.db
    local shouldLog, label = false, nil

    if C_PvP.IsRatedArena() and not IsArenaSkirmish() and not C_PvP.IsSoloShuffle() and not IsWargame() then
        shouldLog, label = db.PvPRatedArena, "a rated arena"
    elseif IsArenaSkirmish() then
        shouldLog, label = db.PvPArenaSkirmish, "an arena skirmish"
    elseif C_PvP.IsSoloShuffle() then
        shouldLog, label = db.PvPSoloShuffle, "Solo Shuffle"
    elseif IsWargame() then
        shouldLog, label = db.PvPWarGame, "a war game"
    end

    self:SyncLoggingState()
    self:AdoptExistingLog(shouldLog, label)

    if shouldLog then
        if self:CheckACL() then
            self:StartLogging(label)
        end
    elseif self.isLogging then
        self:StopLogging()
    end
end

function CL:CheckEnableLogging()
    if not self.db.Enabled then return end

    local _, instanceType, difficultyID, _, maxPlayers = GetInstanceInfo()

    -- Arena handled separately
    if instanceType == "arena" then return end

    local shouldLog, label = self:ShouldLog(instanceType, difficultyID, maxPlayers)
    self:SyncLoggingState()
    self:AdoptExistingLog(shouldLog, label)

    if shouldLog and not self.isLogging then
        if self:CheckACL() then
            self:StartLogging(label)
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

---------------------------------------------------------------------------------
-- Event Handlers
---------------------------------------------------------------------------------
function CL:OnEvent_InstanceInfo()
    self:CheckEnableLogging()
end

function CL:OnEvent_ZoneChanged()
    self:CheckDisableLogging()
end

function CL:OnEvent_EnteringWorld()
    self:SyncLoggingState()

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

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
function CL:ApplySettings()
    if not self.db.Enabled then return end
    -- Re-evaluate current zone with new settings
    self:OnEvent_EnteringWorld()
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function CL:OnEnable()
    if not self.db.Enabled then return end

    self:SyncLoggingState()

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
    -- Only if it was ours; StopLoggingNow is unconditional, so the ownership
    -- test has to happen here.
    if self.isLogging and self.startedByUs then
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
