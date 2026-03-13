-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local SK = KitnEssentials:NewModule("SkinUICleanup", "AceEvent-3.0", "AceHook-3.0")

-- Localization Setup
local ipairs = ipairs
local ObjectiveTrackerFrame = ObjectiveTrackerFrame
local QuestObjectiveTracker = QuestObjectiveTracker
local WorldQuestObjectiveTracker = WorldQuestObjectiveTracker
local ScenarioObjectiveTracker = ScenarioObjectiveTracker
local MonthlyActivitiesObjectiveTracker = MonthlyActivitiesObjectiveTracker
local BonusObjectiveTracker = BonusObjectiveTracker
local ProfessionsRecipeTracker = ProfessionsRecipeTracker
local AchievementObjectiveTracker = AchievementObjectiveTracker
local CampaignQuestObjectiveTracker = CampaignQuestObjectiveTracker

function SK:UpdateDB()
    self.db = KE.db.profile.Skinning.UICleanup
end

function SK:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

-- Elements to hide
local hiddenElements = {
    { name = "Objective Tracker Background", frame = ObjectiveTrackerFrame and ObjectiveTrackerFrame.Header and ObjectiveTrackerFrame.Header.Background },
    { name = "Quest Tracker Background", frame = QuestObjectiveTracker and QuestObjectiveTracker.Header and QuestObjectiveTracker.Header.Background },
    { name = "World Quest Tracker Background", frame = WorldQuestObjectiveTracker and WorldQuestObjectiveTracker.Header and WorldQuestObjectiveTracker.Header.Background },
    { name = "Scenario Tracker Background", frame = ScenarioObjectiveTracker and ScenarioObjectiveTracker.Header and ScenarioObjectiveTracker.Header.Background },
    { name = "Monthly Activities Tracker Background", frame = MonthlyActivitiesObjectiveTracker and MonthlyActivitiesObjectiveTracker.Header and MonthlyActivitiesObjectiveTracker.Header.Background },
    { name = "Bonus Objective Tracker Background", frame = BonusObjectiveTracker and BonusObjectiveTracker.Header and BonusObjectiveTracker.Header.Background },
    { name = "Professions Tracker Background", frame = ProfessionsRecipeTracker and ProfessionsRecipeTracker.Header and ProfessionsRecipeTracker.Header.Background },
    { name = "Achievement Tracker Background", frame = AchievementObjectiveTracker and AchievementObjectiveTracker.Header and AchievementObjectiveTracker.Header.Background },
    { name = "Campaign Tracker Background", frame = CampaignQuestObjectiveTracker and CampaignQuestObjectiveTracker.Header and CampaignQuestObjectiveTracker.Header.Background },
}

local function SetupHideBlizzardClutter()
    if not SK.db.Enabled then return end
    for _, entry in ipairs(hiddenElements) do
        if entry.frame then
            entry.frame:Hide()
        end
    end
end

function SK:ApplySettings()
    if KE:ShouldNotLoadModule() then return end
    SetupHideBlizzardClutter()
end

function SK:OnEnable()
    if KE:ShouldNotLoadModule() then return end
    if not self.db.Enabled then return end
    C_Timer.After(1.0, function()
        SetupHideBlizzardClutter()
    end)
end

function SK:OnDisable()
    self:UnregisterAllEvents()
    self:UnhookAll()
end
