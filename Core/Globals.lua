-- ╔══════════════════════════════════════════════════════════╗
-- ║  Globals.lua                                             ║
-- ║  Purpose: Global constants, helper functions, preview    ║
-- ║           manager, and edit mode integration.            ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
---@diagnostic disable: undefined-field
local KE = select(2, ...)
local addonName = select(1, ...)

local ipairs = ipairs
local print = print
local string_gsub = string.gsub
local ReloadUI = ReloadUI
local C_AddOns = C_AddOns
local C_Timer = C_Timer
local EditModeManagerFrame = EditModeManagerFrame
local _G = _G

---------------------------------------------------------------------------------
-- Libraries and Media
---------------------------------------------------------------------------------

KE.LSM = LibStub("LibSharedMedia-3.0")
KE.LDS = LibStub("LibDualSpec-1.0", true)

KE.PATH = ([[Interface\AddOns\%s\Media\]]):format(addonName)
KE.FONT = KE.PATH .. [[Fonts\]] .. "Expressway.TTF"

if KE.LSM then
    KE.LSM:Register("font", "Expressway", KE.FONT)
    KE.LSM:Register("statusbar", "KitnUI", KE.PATH .. [[Statusbars\KitnEssentials.blp]])
    KE.LSM:Register("border", "WHITE8X8", [[Interface\Buttons\WHITE8X8]])
end

---------------------------------------------------------------------------------
-- Media Helpers
---------------------------------------------------------------------------------

function KE:GetFontPath(fontName)
    if KE.LSM and fontName then
        local path = KE.LSM:Fetch("font", fontName)
        if path then return path end
    end
    return "Fonts\\FRIZQT__.TTF"
end

function KE:GetStatusbarPath(barName)
    if KE.LSM and barName then
        local path = KE.LSM:Fetch("statusbar", barName)
        if path then return path end
    end
    return "Interface\\TargetingFrame\\UI-StatusBar"
end

---------------------------------------------------------------------------------
-- Addon Metadata
---------------------------------------------------------------------------------

local function GetAddonMetadata()
    if not C_AddOns then return end
    KE.AddOnName = C_AddOns.GetAddOnMetadata(addonName, "Title")
    local ver = C_AddOns.GetAddOnMetadata(addonName, "Version")
    if not ver or ver:find("@") then
        ver = C_AddOns.GetAddOnMetadata(addonName, "X-Manual-Version") or "dev"
    end
    KE.Version = ver:gsub("^v", "")
    KE.Author = C_AddOns.GetAddOnMetadata(addonName, "Author")
end
GetAddonMetadata()

---------------------------------------------------------------------------------
-- Utility Helpers
---------------------------------------------------------------------------------

-- Returns true when ElvUI is active and user wants ElvUI to handle skinning
function KE:ShouldNotLoadModule()
    return C_AddOns.IsAddOnLoaded("ElvUI") and self.db and self.db.profile.UseElvUI and self.db.profile.UseElvUI.Enabled
end

function KE:IsEditModeActive()
    return EditModeManagerFrame and EditModeManagerFrame:IsShown()
end

function KE:Print(msg)
    print(self:ColorTextByTheme("Kitn") .. "Essentials:|r " .. msg)
end

---------------------------------------------------------------------------------
-- Slash Commands
---------------------------------------------------------------------------------

SLASH_KITNESSENTIALS1 = "/kes"
SLASH_KITNESSENTIALS2 = "/kitnessentials"
SLASH_KITNESSENTIALS3 = "/dunnigan"
SlashCmdList["KITNESSENTIALS"] = function(msg)
    msg = msg or ""
    msg = string_gsub(msg, "^%s+", "")
    msg = string_gsub(msg, "%s+$", "")

    -- /kes profiler <...> routes to the profiler with case preserved
    -- (snapshot labels are case-sensitive). Match before the lowercase pass.
    local profileRest = msg:match("^[Pp][Rr][Oo][Ff][Ii][Ll][Ee][Rr]%s*(.*)$")
                     or msg:match("^[Pp][Rr][Oo][Ff]%s*(.*)$")
    if profileRest then
        if KE.Profiler and KE.Profiler.RunCommand then
            KE.Profiler.RunCommand(profileRest)
        else
            print("|cffFF008CKitn|r|cffffffffEssentials:|r profiler not loaded.")
        end
        return
    end

    msg = msg:lower()
    if msg == "" or msg == "gui" then
        if KE.GUIFrame then
            KE.GUIFrame:Toggle()
        end
    elseif msg == "edit" or msg == "unlock" then
        if KE.EditMode then
            KE.EditMode:Toggle()
        end
    elseif msg == "resetgui" then
        if KE.db and KE.db.global then
            KE.db.global.GUIState = nil
            KE.db.global._guiReset = true
        end
        ReloadUI()
    end
end

---------------------------------------------------------------------------------
-- Initialization Message
---------------------------------------------------------------------------------

function KE:Init()
    C_Timer.After(2, function()
        if KE.db and KE.db.global and KE.db.global._guiReset then
            KE.db.global._guiReset = nil
            KE:Print("GUI Reset")
        elseif KE.db and KE.db.profile.ShowChatMessage then
            KE:Print(KE:ColorTextByTheme("/kes") .. " to open the configuration window.")
        end
    end)
end

---------------------------------------------------------------------------------
-- Frame Positioning
---------------------------------------------------------------------------------

function KE:ResolveAnchorFrame(anchorFrameType, parentFrameName)
    if anchorFrameType == "SCREEN" or anchorFrameType == "UIPARENT" then
        return UIParent
    elseif anchorFrameType == "SELECTFRAME" and parentFrameName then
        local frame = _G[parentFrameName]
        return frame or UIParent
    end
    return UIParent
end

---------------------------------------------------------------------------------
-- Font Helpers
---------------------------------------------------------------------------------

-- Filters SOFTOUTLINE to "" since it uses a custom shadow system instead
function KE:GetFontOutline(outline)
    if not outline or outline == "NONE" or outline == "SOFTOUTLINE" or outline == "" then
        return ""
    end
    return outline
end

---------------------------------------------------------------------------------
-- Font Validation
---------------------------------------------------------------------------------
-- TODO: 12.0.7 introduces a native font/asset validation API; until then,
-- a hidden FontString + pcall(SetFont) is the most reliable probe.

local fontProbe = UIParent:CreateFontString()
fontProbe:Hide()

local DEFAULT_FONT = "Expressway"

function KE:IsFontValid(fontPath)
    if not fontPath or fontPath == "" then return false end
    return pcall(fontProbe.SetFont, fontProbe, fontPath, 12, "")
end

-- Match KE's flat-DB font key convention. New modules adding a font reference
-- should use one of these key shapes so ValidateProfileFonts repairs them.
local function IsFontKey(key)
    if type(key) ~= "string" then return false end
    return key == "Font" or key:match("FontFace$")
end

local function ValidateFontsRecursive(tbl, defaults)
    if type(tbl) ~= "table" then return end
    local LSM = KE.LSM
    if not LSM then return end

    for key, value in pairs(tbl) do
        if IsFontKey(key) and type(value) == "string" then
            if not LSM:IsValid("font", value) then
                local defaultVal = defaults and defaults[key] or DEFAULT_FONT
                if not LSM:IsValid("font", defaultVal) then
                    defaultVal = DEFAULT_FONT
                end
                tbl[key] = defaultVal
            end
        elseif type(value) == "table" then
            local subDefaults = defaults and defaults[key]
            ValidateFontsRecursive(value, subDefaults)
        end
    end
end

function KE:ValidateProfileFonts()
    if not self.db or not self.db.profile then return end
    local defaults = self.db.defaults and self.db.defaults.profile
    ValidateFontsRecursive(self.db.profile, defaults)
end

-- AceDB defaults backfill works at the top profile level via __index, but it
-- does NOT deep-fill missing keys inside nested sub-tables that already exist
-- in saved data. When a new key (e.g. `DeathNotifications.FocusDeath`) is
-- added to defaults after a profile was saved, the old profile's nested table
-- stays missing that key, and code that does `db.DeathNotifications.FocusDeath.Enabled`
-- crashes with "attempt to index field (a nil value)". CopyMissingKeys walks
-- defaults and copies any missing key into saved, recursing into sub-tables.
local function CopyMissingKeys(tbl, defaults)
    if type(tbl) ~= "table" or type(defaults) ~= "table" then return end
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(tbl[k]) ~= "table" then tbl[k] = {} end
            CopyMissingKeys(tbl[k], v)
        elseif tbl[k] == nil then
            tbl[k] = v
        end
    end
end

function KE:FillProfileDefaults()
    if not self.db or not self.db.profile then return end
    local defaults = self.db.defaults and self.db.defaults.profile
    if not defaults then return end
    CopyMissingKeys(self.db.profile, defaults)
end

---------------------------------------------------------------------------------
-- Color Resolution
---------------------------------------------------------------------------------
-- AceDB stores user-edited color tables sparsely (e.g. {[3]=0.549}) when only
-- one channel was changed via the GUI, and may leave the whole table missing
-- after a profile reset. ResolveColor returns r,g,b,a as four values, falling
-- back to the caller-supplied default per index. Callers should pass the same
-- default array they ship in Defaults.lua.
function KE:ResolveColor(saved, default)
    if not saved then
        return default[1], default[2], default[3], default[4] or 1
    end
    return saved[1] or default[1],
           saved[2] or default[2],
           saved[3] or default[3],
           saved[4] or default[4] or 1
end

function KE:ApplyFont(fontString, fontName, fontSize, fontOutline)
    if not fontString then return false end
    local fontPath = self:GetFontPath(fontName)
    if not self:IsFontValid(fontPath) then
        fontPath = "Fonts\\FRIZQT__.TTF"
    end
    local outline = self:GetFontOutline(fontOutline)
    local size = (fontSize and fontSize > 0) and fontSize or 12
    local success = fontString:SetFont(fontPath, size, outline)
    if not success then
        success = fontString:SetFont("Fonts\\FRIZQT__.TTF", size, outline)
    end
    return success
end

---------------------------------------------------------------------------------
-- Text Justification
---------------------------------------------------------------------------------

function KE:GetTextJustifyFromAnchor(anchorPoint)
    if not anchorPoint then return "CENTER" end
    if anchorPoint == "RIGHT" or anchorPoint == "TOPRIGHT" or anchorPoint == "BOTTOMRIGHT" then
        return "RIGHT"
    elseif anchorPoint == "LEFT" or anchorPoint == "TOPLEFT" or anchorPoint == "BOTTOMLEFT" then
        return "LEFT"
    end
    return "CENTER"
end

function KE:GetTextPointFromAnchor(anchorPoint)
    local justify = self:GetTextJustifyFromAnchor(anchorPoint)
    if justify == "RIGHT" then return "RIGHT"
    elseif justify == "LEFT" then return "LEFT" end
    return "CENTER"
end

-- Simple 3-way anchor → point mapping: LEFT/RIGHT pass through, everything else → CENTER.
-- Differs from GetTextPointFromAnchor by NOT expanding TOPRIGHT/BOTTOMRIGHT to RIGHT.
function KE:GetPointFromAnchor(anchor)
    if anchor == "LEFT" then return "LEFT"
    elseif anchor == "RIGHT" then return "RIGHT"
    end
    return "CENTER"
end

---------------------------------------------------------------------------------
-- Preview Manager
---------------------------------------------------------------------------------

local PreviewManager = {}
KE.PreviewManager = PreviewManager

local PREVIEW_MODULES = {
    "StanceText", "CombatCross", "CombatTexts", "CombatRes",
    "CombatTimer", "PetStatusText", "DragonRiding",
    "FocusCastbar", "TargetCastbar", "RaidNotifications", "HuntersMark", "RangeChecker",
    "TimeSpiral", "DisintegrateTicks", "StasisTracker", "Recuperate", "BloodlustTracker", "KickTracker",
    "NoMovementAlert", "PrescienceTracker", "GreatVaultAlert", "PotionReady", "BossDebuffs",
    "EnemyCounter", "EbonMightTracker", "DungeonCasts", "DungeonTimers", "HealerMana",
    "ReadyCheckConsumables", "DeathNotifications",
}

-- Section → preview module mapping for section-based previews
-- Sections not listed here (Settings, Optimize, Skinning) have no previews
local SECTION_PREVIEW_MODULES = {
    combat_section = {
        "CombatRes", "BossDebuffs", "CombatTexts", "CombatTimer",
        "FocusCastbar", "TargetCastbar", "CombatCross", "RangeChecker",
    },
    utilities_section = {
        "BloodlustTracker", "StanceText", "PetStatusText", "PotionReady",
        "DisintegrateTicks", "StasisTracker", "EbonMightTracker", "PrescienceTracker",
        "RaidNotifications", "Recuperate", "TimeSpiral", "NoMovementAlert",
        "ReadyCheckConsumables",
    },
    qol_section = {
        "DragonRiding", "HuntersMark", "GreatVaultAlert",
    },
    dungeons_section = {
        "EnemyCounter", "KickTracker", "DungeonCasts", "HealerMana", "DeathNotifications",
    },
    dungeon_timers_section = {
        "DungeonTimers",
    },
}

-- Reverse lookup: sidebar item ID → section ID (built lazily)
local ITEM_TO_SECTION = nil

local function GetItemToSection()
    if ITEM_TO_SECTION then return ITEM_TO_SECTION end
    ITEM_TO_SECTION = {}
    local GUIFrame = KE.GUIFrame
    local sidebarConfig = GUIFrame and GUIFrame.sidebarConfig
    if sidebarConfig then
        for _, section in ipairs(sidebarConfig) do
            if section.items then
                for _, item in ipairs(section.items) do
                    ITEM_TO_SECTION[item.id] = section.id
                end
            end
        end
    end
    return ITEM_TO_SECTION
end

PreviewManager.guiOpen = false
PreviewManager.editModeActive = false
PreviewManager.previewsActive = false
PreviewManager.activeSection = nil

-- Per-module preview state cache (moduleName → "preview" | "hidden") so
-- ShowSectionPreviews / ShowModules only fire module:ShowPreview /
-- :HidePreview when the state actually changes. Without this, every
-- cross-section GUI nav re-fires ShowPreview on every preview module —
-- modules like RaidNotifications redundantly re-apply fonts/colors/sizes
-- to all rows on each transition. Wiped on StopAllPreviews so the next
-- show does fresh setup.
PreviewManager._moduleStates = {}

function PreviewManager:UpdatePreviewState()
    if self.editModeActive then
        -- Edit mode: show ALL previews regardless of section
        self:ShowModules(PREVIEW_MODULES)
        self.previewsActive = true
        return
    end

    if self.guiOpen then
        -- GUI open: show only the active section's previews
        self.previewsActive = true
        self:ShowSectionPreviews(self.activeSection)
    elseif self.previewsActive then
        self:StopAllPreviews()
        self.previewsActive = false
    end
end

function PreviewManager:SetGUIOpen(open)
    self.guiOpen = open
    self:UpdatePreviewState()
end

function PreviewManager:SetEditModeActive(active)
    self.editModeActive = active
    self:UpdatePreviewState()
end

function PreviewManager:SetActiveSection(sectionId)
    if self.activeSection == sectionId then return end
    self.activeSection = sectionId
    if self.guiOpen and not self.editModeActive then
        self:ShowSectionPreviews(sectionId)
    end
end

-- Resolve section from a sidebar item ID and activate it
function PreviewManager:SetActivePage(itemId)
    local lookup = GetItemToSection()
    local sectionId = lookup[itemId]
    self:SetActiveSection(sectionId)
end

function PreviewManager:ShowSectionPreviews(sectionId)
    local Addon = KitnEssentials
    if not Addon then return end

    local wantedModules = sectionId and SECTION_PREVIEW_MODULES[sectionId]
    local wantedSet = {}
    if wantedModules then
        for _, name in ipairs(wantedModules) do
            wantedSet[name] = true
        end
    end

    local classMatch = { [select(2, UnitClass("player"))] = true }
    local states = self._moduleStates

    for _, moduleName in ipairs(PREVIEW_MODULES) do
        local module = Addon:GetModule(moduleName, true)
        if module then
            local wantPreview = wantedSet[moduleName]
                and module.ShowPreview and module.db and module.db.Enabled
                and (not module.classRestriction or classMatch[module.classRestriction])
            if wantPreview then
                if states[moduleName] ~= "preview" then
                    module:ShowPreview()
                    states[moduleName] = "preview"
                end
            elseif module.HidePreview then
                if states[moduleName] ~= "hidden" then
                    module:HidePreview()
                    states[moduleName] = "hidden"
                end
            end
        end
    end
end

function PreviewManager:ShowModules(moduleList)
    local Addon = KitnEssentials
    if not Addon then return end
    local classMatch = { [select(2, UnitClass("player"))] = true }
    local states = self._moduleStates
    for _, moduleName in ipairs(moduleList) do
        local module = Addon:GetModule(moduleName, true)
        if module and module.ShowPreview and module.db and module.db.Enabled then
            if not module.classRestriction or classMatch[module.classRestriction] then
                if states[moduleName] ~= "preview" then
                    module:ShowPreview()
                    states[moduleName] = "preview"
                end
            end
        end
    end
end

function PreviewManager:StopAllPreviews()
    local Addon = KitnEssentials
    if not Addon then return end
    local states = self._moduleStates
    for _, moduleName in ipairs(PREVIEW_MODULES) do
        local module = Addon:GetModule(moduleName, true)
        if module and module.HidePreview then
            if states[moduleName] ~= "hidden" then
                module:HidePreview()
                states[moduleName] = "hidden"
            end
        end
    end
end

function PreviewManager:IsPreviewActive()
    return self.previewsActive
end

---------------------------------------------------------------------------------
-- Healer Position Override
---------------------------------------------------------------------------------

function KE:IsPlayerHealerSpec()
    local specIndex = _G.GetSpecialization()
    if not specIndex then return false end
    local role = _G.GetSpecializationRole(specIndex)
    return role == "HEALER"
end

function KE:GetActivePositionConfig(db)
    if db.UseHealerPosition and self:IsPlayerHealerSpec() and db.HealerPosition then
        return db.HealerPosition,
               db.HealerAnchorFrameType or db.anchorFrameType,
               db.HealerParentFrame or db.ParentFrame,
               db.HealerStrata or db.Strata
    end
    return db.Position, db.anchorFrameType, db.ParentFrame, db.Strata
end

function KE:ApplyActivePosition(frame, db, setParent)
    local posConfig, aft, pf, strata = self:GetActivePositionConfig(db)
    local config = { anchorFrameType = aft, ParentFrame = pf, Strata = strata }
    self:ApplyFramePosition(frame, posConfig, config, setParent)
end

function KE:ApplyFramePosition(frame, posConfig, Config, SetParent)
    if not frame or not posConfig then return end
    local parent = self:ResolveAnchorFrame(Config.anchorFrameType, Config.ParentFrame)
    if SetParent then
        frame:SetParent(parent)
    end
    frame:ClearAllPoints()
    frame:SetPoint(
        posConfig.AnchorFrom or "CENTER",
        parent,
        posConfig.AnchorTo or "CENTER",
        posConfig.XOffset or 0,
        posConfig.YOffset or 0
    )
    frame:SetFrameStrata(Config.Strata or "MEDIUM")
end

-- Like ApplyFramePosition but additionally snaps the frame's resulting screen
-- position to the integer pixel grid when Config.SnapToPixelGrid is true.
-- Use this for soft-outline modules whose anchor frames may end up at sub-
-- pixel screen positions (some ElvUI panels), which causes the soft-outline
-- shadows to anti-alias and look like a halo. The snap can absorb sub-pixel
-- offset deltas, so the user toggles it OFF while adjusting sliders, ON when
-- they want crisp text.
function KE:ApplyFramePositionWithSnap(frame, posConfig, Config, SetParent)
    self:ApplyFramePosition(frame, posConfig, Config, SetParent)
    if Config and Config.SnapToPixelGrid then
        self:SnapFrameToPixels(frame)
    end
end
