-- KitnEssentials namespace
---@class KE
---@diagnostic disable: undefined-field
local KE = select(2, ...)
local addonName = select(1, ...)

-- Localization
local ipairs = ipairs
local print = print
local string_gsub = string.gsub
local ReloadUI = ReloadUI
local C_AddOns = C_AddOns
local C_Timer = C_Timer
local EditModeManagerFrame = EditModeManagerFrame
local _G = _G

-- Libraries
KE.LSM = LibStub("LibSharedMedia-3.0")
KE.LDS = LibStub("LibDualSpec-1.0", true)

-- Addon media paths
KE.PATH = ([[Interface\AddOns\%s\Media\]]):format(addonName)
KE.FONT = KE.PATH .. [[Fonts\]] .. "Expressway.TTF"

-- Register LSM media
if KE.LSM then
    KE.LSM:Register("font", "Expressway", KE.FONT)
    KE.LSM:Register("statusbar", "KitnUI", KE.PATH .. [[Statusbars\KitnEssentials.blp]])
    KE.LSM:Register("border", "WHITE8X8", [[Interface\Buttons\WHITE8X8]])
end

-- Helper to get font path from name
function KE:GetFontPath(fontName)
    if KE.LSM and fontName then
        local path = KE.LSM:Fetch("font", fontName)
        if path then return path end
    end
    return "Fonts\\FRIZQT__.TTF"
end

-- Helper to get statusbar path from name
function KE:GetStatusbarPath(barName)
    if KE.LSM and barName then
        local path = KE.LSM:Fetch("statusbar", barName)
        if path then return path end
    end
    return "Interface\\TargetingFrame\\UI-StatusBar"
end

-- Addon metadata
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

-- ElvUI detection: returns true when ElvUI is active and user wants ElvUI to handle skinning
function KE:ShouldNotLoadModule()
    return C_AddOns.IsAddOnLoaded("ElvUI") and self.db and self.db.profile.UseElvUI and self.db.profile.UseElvUI.Enabled
end

-- Check if Edit Mode is active
function KE:IsEditModeActive()
    return EditModeManagerFrame and EditModeManagerFrame:IsShown()
end

-- Print message to chat with addon prefix
function KE:Print(msg)
    print(self:ColorTextByTheme("Kitn") .. "Essentials:|r " .. msg)
end

-- Slash commands
SLASH_KITNESSENTIALS1 = "/kes"
SLASH_KITNESSENTIALS2 = "/kitnessentials"
SLASH_KITNESSENTIALS3 = "/dunnigan"
SlashCmdList["KITNESSENTIALS"] = function(msg)
    msg = (msg or ""):lower()
    msg = string_gsub(msg, "^%s+", "")
    msg = string_gsub(msg, "%s+$", "")
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

-- Initialization message
function KE:Init()
    C_Timer.After(2, function()
        if KE.db and KE.db.global and KE.db.global._guiReset then
            KE.db.global._guiReset = nil
            KE:Print("GUI Reset")
        else
            KE:Print(KE:ColorTextByTheme("/kes") .. " to open the configuration window.")
        end
    end)
end

-- Resolve anchor frame from db settings
function KE:ResolveAnchorFrame(anchorFrameType, parentFrameName)
    if anchorFrameType == "SCREEN" or anchorFrameType == "UIPARENT" then
        return UIParent
    elseif anchorFrameType == "SELECTFRAME" and parentFrameName then
        local frame = _G[parentFrameName]
        return frame or UIParent
    end
    return UIParent
end

-- Convert font outline value for SetFont API
function KE:GetFontOutline(outline)
    if not outline or outline == "NONE" or outline == "SOFTOUTLINE" or outline == "" then
        return ""
    end
    return outline
end

-- Safely apply font settings to a FontString
function KE:ApplyFont(fontString, fontName, fontSize, fontOutline)
    if not fontString then return false end
    local fontPath = self:GetFontPath(fontName)
    if not fontPath or fontPath == "" then
        fontPath = "Fonts\\FRIZQT__.TTF"
    end
    local outline = self:GetFontOutline(fontOutline)
    local size = fontSize
    if not size or size <= 0 then size = 12 end
    local success = fontString:SetFont(fontPath, size, outline)
    if not success then
        success = fontString:SetFont("Fonts\\FRIZQT__.TTF", size, outline)
    end
    return success
end

-- Get text justification from anchor point
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

-- Preview Manager
local PreviewManager = {}
KE.PreviewManager = PreviewManager

local PREVIEW_MODULES = {
    "MissingBuffs", "CombatCross", "CombatTexts", "CombatRes",
    "CombatTimer", "PetStatusText", "DragonRiding",
    "FocusCastbar", "GatewayAlert", "HuntersMark", "RangeChecker",
    "TimeSpiral", "Recuperate",
}

PreviewManager.guiOpen = false
PreviewManager.editModeActive = false
PreviewManager.previewsActive = false

function PreviewManager:UpdatePreviewState()
    local shouldShowPreviews = self.guiOpen or self.editModeActive
    if shouldShowPreviews and not self.previewsActive then
        self:StartAllPreviews()
        self.previewsActive = true
    elseif not shouldShowPreviews and self.previewsActive then
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

function PreviewManager:StartAllPreviews()
    local Addon = KitnEssentials
    if not Addon then return end
    for _, moduleName in ipairs(PREVIEW_MODULES) do
        local module = Addon:GetModule(moduleName, true)
        if module and module.ShowPreview and module.db and module.db.Enabled then
            module:ShowPreview()
        end
    end
end

function PreviewManager:StopAllPreviews()
    local Addon = KitnEssentials
    if not Addon then return end
    for _, moduleName in ipairs(PREVIEW_MODULES) do
        local module = Addon:GetModule(moduleName, true)
        if module and module.HidePreview then
            module:HidePreview()
        end
    end
end

function PreviewManager:IsPreviewActive()
    return self.previewsActive
end

-- Apply frame position from config
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
    self:SnapFrameToPixels(frame)
end
