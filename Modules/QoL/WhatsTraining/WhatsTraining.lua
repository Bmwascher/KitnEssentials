-- ╔══════════════════════════════════════════════════════════╗
-- ║  WhatsTraining.lua                                       ║
-- ║  Module: What's Training                                 ║
-- ║  Purpose: Lifecycle, the one data load, events and the   ║
-- ║           plan the panel and toast draw.                 ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class WhatsTraining: AceModule, AceEvent-3.0
local WT = KitnEssentials:NewModule("WhatsTraining", "AceEvent-3.0")

local T = KE.Training or {}
KE.Training = T

local Rules = KE.TrainingRules

local C_AddOns, C_Timer = C_AddOns, C_Timer
local CopyTable = CopyTable
local EventUtil = EventUtil
local GetMoney = GetMoney
local InCombatLockdown = InCombatLockdown
local InputUtil = InputUtil
local UnitClass, UnitFactionGroup, UnitLevel, UnitRace = UnitClass, UnitFactionGroup, UnitLevel, UnitRace
local debugprofilestop = debugprofilestop
local pairs, select, type = pairs, select, type

local DATA_ADDON = "KitnEssentials_Data"
local MISSING_REASON = "MISSING"
local UNREADABLE_DATA = "a data file could not be read"
local CLASS_SOURCE = "TrainingClass"
local ROUTE_SOURCE = "TrainingRoute"
local LINK_TYPE = "ketraining"
local OPEN_LINK = "|Hketraining|h[Open]|h"
local LEVEL_UP_DELAY = 1
local SIDES = { Alliance = "A", Horde = "H" }

local built, pending = {}, {}
local failureSaid = false
local linkReady = false
local levelGeneration = 0

function KE.TrainingOwnsTrainer()
    return T.active == true and not T.gamepad
end

---------------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------------
local function DataReady(name, data)
    if name == ROUTE_SOURCE then
        T.Route.Narrow(data)
    else
        T.classData = data
        T.loadFailure = nil
        WT:RebuildPlan()
        if T.atTrainer then T.Read.Queue() end
    end
    T.Panel.QueueDraw()
end

local function DataFailed(name, text)
    if name == ROUTE_SOURCE then
        T.Route.failed = true
    else
        T.loadFailure = text
    end
    T.Panel.QueueDraw()
    if failureSaid then return end
    failureSaid = true
    KE:Print("What's Training could not load its data: " .. text)
end

local function IsValidData(name, data)
    if name == ROUTE_SOURCE then return Rules.RouteDataValid(data) end
    return Rules.ClassDataValid(data)
end

local function FailureText(loaded, reason, buildReason)
    if loaded then return buildReason or "unknown" end
    local text = reason and _G["ADDON_" .. reason]
    if type(text) == "string" then return text end
    return reason or "unknown"
end

function WT:LoadData(name)
    local step = Rules.BuildStep(built[name] ~= nil, InCombatLockdown())
    if step == "have" then return built[name] end
    if step == "wait" then
        pending[name] = true
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        return nil
    end
    local start = debugprofilestop()
    local loaded, reason
    if C_AddOns.DoesAddOnExist(DATA_ADDON) then
        loaded, reason = C_AddOns.LoadAddOn(DATA_ADDON)
    else
        reason = MISSING_REASON
    end
    local data, buildReason
    if loaded and KE.BuildData then data, buildReason = KE.BuildData(name) end
    if data and not IsValidData(name, data) then
        data, buildReason = nil, UNREADABLE_DATA
    end
    self.loadMs[name] = debugprofilestop() - start
    if data then
        built[name] = data
        DataReady(name, data)
        return data
    end
    DataFailed(name, FailureText(loaded, reason, buildReason))
    return nil
end

function WT:PLAYER_REGEN_ENABLED()
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    local names = pending
    pending = {}
    if not T.active then return end
    for name in pairs(names) do self:LoadData(name) end
end

function WT:RebuildPlan()
    if not T.classData then return end
    local store = T.Store()
    T.plan = Rules.Plan(T.classData.spells, {
        level = T.level, race = T.race, gold = GetMoney(),
        skipped = store.skipped, prices = store.prices,
        isKnown = T.IsKnown, nameOf = T.NameOf, weapons = T.classData.weapons,
    })
end

---------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------
local function ChatText(level, plan)
    local line = Rules.ChatLine(level, plan, T.Coins)
    if linkReady then line = line .. " " .. T.Paint("accent", OPEN_LINK) end
    return line
end

function WT:PLAYER_LEVEL_UP(_, level)
    level = level or UnitLevel("player")
    T.level = level
    self:RebuildPlan()
    T.Panel.QueueDraw()
    levelGeneration = levelGeneration + 1
    local mine = levelGeneration
    C_Timer.After(LEVEL_UP_DELAY, function()
        if mine ~= levelGeneration or not T.active then return end
        self:RebuildPlan()
        local plan = T.plan
        if not plan or #plan.now.rows == 0 then return end
        if self.db.Toast then T.Toast.Show(level) end
        if self.db.ChatLine then KE:Print(ChatText(level, plan)) end
    end)
end

function WT:TRAINER_SHOW()
    T.atTrainer = true
    self:RegisterEvent("TRAINER_SERVICE_INFO_NAME_UPDATE", "TRAINER_UPDATE")
    T.Learn.Reset()
    T.Read.Queue()
    T.Panel.OnTrainerShow()
end

function WT:TRAINER_UPDATE()
    T.Read.Queue()
end

function WT:TRAINER_CLOSED()
    if not T.atTrainer then return end
    self:UnregisterEvent("TRAINER_SERVICE_INFO_NAME_UPDATE")
    local atProfession = T.atProfession
    T.atTrainer = false
    T.atProfession = false
    T.Learn.Reset()
    if not atProfession then T.Swap.Scan() end
    T.Panel.OnTrainerClosed(not atProfession and #T.Swap.swaps > 0)
end

function WT:LEARNED_SPELL_IN_SKILL_LINE()
    self:RebuildPlan()
    T.Panel.QueueDraw()
    T.Swap.ScanSoon()
end

---------------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------------
function WT:ApplySettings()
    if not T.active then return end
    T.Swap.Scan()
    T.Panel.Refresh()
end

function WT:OpenPanel()
    if T.active then T.Panel.Open() end
end

function WT:HandleSlash()
    if not T.active then
        KE:Print("What's Training is off. Turn it on in the settings window: QoL section, What's Training row.")
        return
    end
    T.Panel.Toggle()
end

function WT:ResetToDefaults()
    for key, value in pairs(KE:GetDefaultDB().profile.WhatsTraining) do
        if key ~= "Enabled" then
            self.db[key] = type(value) == "table" and CopyTable(value) or value
        end
    end
    self:ApplySettings()
end

function WT:OnThemeChanged()
    if T.active then T.Panel.Repaint() end
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
local function RefreshTrainAll()
    local automation = KitnEssentials:GetModule("Automation", true)
    if automation and automation.RefreshTrainAll then automation:RefreshTrainAll() end
end

-- Registered once and never removed: LinkUtil has no unregister call and
-- asserts on a duplicate. The handler tests the module's state instead.
local function RegisterLink()
    local linkUtil = _G.LinkUtil
    if not (linkUtil and linkUtil.RegisterLinkHandler and linkUtil.IsLinkHandlerRegistered) then return end
    linkReady = true
    if linkUtil.IsLinkHandlerRegistered(LINK_TYPE) then return end
    linkUtil.RegisterLinkHandler(LINK_TYPE, function()
        if T.active then T.Panel.Open() end
    end)
end

local function CacheCharacter()
    local className, classToken, classId = UnitClass("player")
    T.className, T.classToken, T.classId = className, classToken, classId
    T.race = select(3, UnitRace("player"))
    T.side = SIDES[UnitFactionGroup("player")]
    T.level = UnitLevel("player")
    ---@diagnostic disable-next-line: wrong-flavor-api
    T.gamepad = InputUtil ~= nil and InputUtil.IsGamepadUIEnabled ~= nil and InputUtil.IsGamepadUIEnabled() == true
end

function WT:UpdateDB()
    self.db = KE.db.profile.WhatsTraining
    T.db = self.db
end

function WT:OnInitialize()
    self:UpdateDB()
    self.loadMs = {}
    T.module = self
    self:SetEnabledState(false)
end

function WT:OnEnable()
    if not self.db.Enabled then return end
    T.active = true
    CacheCharacter()
    -- Only the chat line stays latched: a failed load tries again on each enable.
    T.loadFailure = nil
    T.Route.failed = nil
    self:LoadData(CLASS_SOURCE .. T.classId)
    self:RebuildPlan()
    self:RegisterEvent("PLAYER_LEVEL_UP")
    self:RegisterEvent("TRAINER_SHOW")
    self:RegisterEvent("TRAINER_UPDATE")
    self:RegisterEvent("TRAINER_CLOSED")
    self:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE")
    if not T.gamepad and EventUtil and EventUtil.ContinueOnAddOnLoaded then
        EventUtil.ContinueOnAddOnLoaded("Blizzard_PlayerSpells", T.Panel.InstallBook)
        EventUtil.ContinueOnAddOnLoaded("Blizzard_TrainerUI", T.Panel.InstallTrainer)
    end
    -- Turned on with a trainer already open: no TRAINER_SHOW is coming, and
    -- Train All is about to hide.
    local trainer = _G.ClassTrainerFrame
    if trainer and trainer:IsShown() then self:TRAINER_SHOW() end
    RegisterLink()
    RefreshTrainAll()
end

function WT:OnDisable()
    T.active = false
    T.atTrainer = false
    T.atProfession = false
    pending = {}
    levelGeneration = levelGeneration + 1
    self:UnregisterAllEvents()
    T.Panel.HideAll()
    T.Toast.Hide()
    RefreshTrainAll()
end
