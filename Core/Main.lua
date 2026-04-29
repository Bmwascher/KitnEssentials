-- ╔══════════════════════════════════════════════════════════╗
-- ║  Main.lua                                                ║
-- ║  Purpose: Main addon initialization, AceAddon setup,     ║
-- ║           slash command registration, and login flow.    ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local IsInInstance = IsInInstance
local LibStub = LibStub

local aceAddon = LibStub("AceAddon-3.0")

local DEFAULT_PROFILE = "Default"

---@class KitnEssentials : AceAddon-3.0, AceEvent-3.0, AceHook-3.0
local KitnEssentials = aceAddon:NewAddon("KitnEssentials", "AceEvent-3.0", "AceHook-3.0")
_G.KitnEssentials = KitnEssentials

KE.encounterActive = false

---------------------------------------------------------------------------------
-- AceAddon Lifecycle
---------------------------------------------------------------------------------

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

    -- Backfill missing nested defaults into the saved profile (AceDB's defaults
    -- system doesn't deep-fill sub-tables that already exist in saved data),
    -- then validate font keys against LSM. Order matters — fill first so the
    -- font validator can see all expected keys.
    KE:FillProfileDefaults()
    KE:ValidateProfileFonts()

    -- Profile change callbacks
    KE.db.RegisterCallback(KE, "OnProfileChanged", function()
        KE:FillProfileDefaults()
        KE:ValidateProfileFonts()
        if KE.ProfileManager then
            KE.ProfileManager:RefreshAllModules()
        end
    end)
    KE.db.RegisterCallback(KE, "OnProfileCopied", function()
        KE:FillProfileDefaults()
        KE:ValidateProfileFonts()
        if KE.ProfileManager then
            KE.ProfileManager:RefreshAllModules()
        end
    end)
    KE.db.RegisterCallback(KE, "OnProfileReset", function()
        KE:FillProfileDefaults()
        KE:ValidateProfileFonts()
        if KE.ProfileManager then
            KE.ProfileManager:RefreshAllModules()
        end
    end)

    -- Activate saved theme settings now that DB is ready
    if KE.RefreshTheme then KE:RefreshTheme() end
end

---------------------------------------------------------------------------------
-- Minimap Icon
---------------------------------------------------------------------------------

function KE:SetupMinimapIcon()
    local LDB = LibStub("LibDataBroker-1.1", true)
    local LDBIcon = LibStub("LibDBIcon-1.0", true)
    if not LDB or not LDBIcon then return end

    local MyLDB = LDB:NewDataObject("KitnEssentials", {
        type = "launcher",
        text = "KitnEssentials",
        icon = "Interface\\AddOns\\KitnEssentials\\Media\\Icon\\KitnUI",
        OnClick = function(_, button)
            if button == "LeftButton" then
                if KE.GUIFrame then KE.GUIFrame:Toggle() end
            elseif button == "RightButton" then
                if KE.EditMode then KE.EditMode:Toggle() end
            elseif button == "MiddleButton" then
                ReloadUI()
            end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine(KE:ColorTextByTheme("Kitn") .. "|cffb3b3b3Essentials|r")
            tt:AddLine("|cffFFD100Left-Click|r to open options", 0.60, 0.60, 0.60)
            tt:AddLine("|cffFFD100Right-Click|r to toggle edit mode", 0.60, 0.60, 0.60)
            tt:AddLine("|cffFFD100Middle-Click|r to reload UI", 0.60, 0.60, 0.60)
        end,
    })

    LDBIcon:Register("KitnEssentials", MyLDB, KE.db.profile.Minimap)
    KE.minimapIcon = LDBIcon
end

---------------------------------------------------------------------------------
-- Event Handlers
---------------------------------------------------------------------------------

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
    for _, module in KitnEssentials:IterateModules() do
        if module:IsEnabled() and module.ApplySettings then
            module:ApplySettings()
        end
    end
end

---------------------------------------------------------------------------------
-- Addon Enable
---------------------------------------------------------------------------------

function KitnEssentials:OnEnable()
    if KE.RefreshTheme then KE:RefreshTheme() end
    if KE.Init then KE:Init() end

    -- Enable modules based on saved settings
    local skipSkinning = KE:ShouldNotLoadModule()
    for name, module in self:IterateModules() do
        if module.db and module.db.Enabled then
            -- Skip skinning modules when ElvUI handles skinning
            if skipSkinning and name:find("^Skin") then
                -- Do not enable
            else
                self:EnableModule(name)
            end
        end
    end

    -- Slash commands (/cd, /wa, SetPITarget)
    if KE.ApplySlashCommands then KE:ApplySlashCommands() end

    -- Minimap icon (delayed for theme readiness)
    C_Timer.After(1, function()
        KE:SetupMinimapIcon()
    end)

    -- Event registration
    self:RegisterEvent("ENCOUNTER_END", OnEncounterEnd)
    self:RegisterEvent("ENCOUNTER_START", OnEncounterStart)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", OnPlayerEnteringWorld)
end
