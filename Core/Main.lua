-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)

-- Localization
local IsInInstance = IsInInstance
local LibStub = LibStub

local aceAddon = LibStub("AceAddon-3.0")

local DEFAULT_PROFILE = "Default"

-- Create the main addon object
---@class KitnEssentials : AceAddon-3.0, AceEvent-3.0, AceHook-3.0
local KitnEssentials = aceAddon:NewAddon("KitnEssentials", "AceEvent-3.0", "AceHook-3.0")
_G.KitnEssentials = KitnEssentials

-- Encounter state
KE.encounterActive = false

function KitnEssentials:OnInitialize()
    local defaults = KE:GetDefaultDB()
    if not defaults then
        defaults = { profile = {} }
    end
    KE.db = LibStub("AceDB-3.0"):New("KitnEssentialsDB", defaults, true)
    if KE.LDS then
        KE.LDS:EnhanceDatabase(KE.db, "KitnEssentials")
    end
    if KE.db.global and KE.db.global.UseGlobalProfile then
        local profileName = KE.db.global.GlobalProfile or DEFAULT_PROFILE
        KE.db:SetProfile(profileName)
    end

    -- Profile change callbacks
    KE.db.RegisterCallback(KE, "OnProfileChanged", function()
        if KE.ProfileManager then
            KE.ProfileManager:RefreshAllModules()
        end
    end)
    KE.db.RegisterCallback(KE, "OnProfileCopied", function()
        if KE.ProfileManager then
            KE.ProfileManager:RefreshAllModules()
        end
    end)
    KE.db.RegisterCallback(KE, "OnProfileReset", function()
        if KE.ProfileManager then
            KE.ProfileManager:RefreshAllModules()
        end
    end)
end

local function OnEncounterEnd()
    local _, instanceType = IsInInstance()
    if instanceType == "raid" and KE.encounterActive then
        KE.encounterActive = false
    end
end

local function OnEncounterStart()
    local _, instanceType = IsInInstance()
    if instanceType == "raid" then
        KE.encounterActive = true
    end
end

local function OnPlayerEnteringWorld()
    for name, module in KitnEssentials:IterateModules() do
        if module:IsEnabled() and module.ApplySettings then
            module:ApplySettings()
        end
    end
end

function KitnEssentials:OnEnable()
    if KE.RefreshTheme then KE:RefreshTheme() end
    if KE.Init then KE:Init() end

    -- Enable modules based on saved settings
    for name, module in self:IterateModules() do
        if module.db and module.db.Enabled then
            self:EnableModule(name)
        end
    end

    -- Slash commands (/cd, /wa, SetPITarget)
    if KE.ApplySlashCommands then KE:ApplySlashCommands() end

    -- Event registration
    self:RegisterEvent("ENCOUNTER_END", OnEncounterEnd)
    self:RegisterEvent("ENCOUNTER_START", OnEncounterStart)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", OnPlayerEnteringWorld)
end
