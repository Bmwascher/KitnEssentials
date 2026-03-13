-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class CombatCross: AceModule, AceEvent-3.0
local CC = KitnEssentials:NewModule("CombatCross", "AceEvent-3.0")

-- Localization
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local UIFrameFadeIn = UIFrameFadeIn
local UIParent = UIParent

-- Constants
local FONT_SIZE_MULTIPLIER = 2

-- Module state
CC.frame = nil
CC.text = nil
CC.previewActive = false
CC.combatActive = false

function CC:UpdateDB()
    self.db = KE.db.profile.CombatCross
end

function CC:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

-- Get color based on color mode
function CC:GetColor()
    local colorMode = self.db.ColorMode or "custom"
    return KE:GetAccentColor(colorMode, self.db.Color)
end

-- Create the combat cross frame
function CC:CreateFrame()
    if self.frame then return end

    self.frame = CreateFrame("Frame", "KE_CombatCrossFrame", UIParent)
    self.frame:SetSize(30, 30)
    self.frame:SetPoint("CENTER")
    self.frame:SetFrameStrata("HIGH")
    self.frame:SetFrameLevel(100)
    self.frame:Hide()

    -- Create cross text ("+" rendered at large font size)
    local fontSize = (self.db.Thickness or 22) * FONT_SIZE_MULTIPLIER
    local fontPath = KE:GetFontPath(self.db.FontFace) or KE.FONT
    local outline = self.db.Outline and "OUTLINE" or ""

    self.text = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.text:SetPoint("CENTER")
    self.text:SetFont(fontPath, fontSize, outline)
    self.text:SetText("+")

    self.text:ClearAllPoints()
    self.text:SetPoint("CENTER", self.frame, "CENTER", 0, 0)
end

-- Apply settings from profile
function CC:ApplySettings()
    if not self.frame or not self.text then return end

    -- Apply position & strata
    KE:ApplyFramePosition(self.frame, self.db.Position, self.db)

    -- Apply font with outline
    local fontSize = (self.db.Thickness or 22) * FONT_SIZE_MULTIPLIER
    local fontPath = KE:GetFontPath(self.db.FontFace) or KE.FONT
    local outline = self.db.Outline and "OUTLINE" or ""
    self.text:SetFont(fontPath, fontSize, outline)

    -- Apply color
    local r, g, b, a = self:GetColor()
    self.text:SetTextColor(r, g, b, a)
end

-- Apply position only
function CC:ApplyPosition()
    if not self.frame then return end
    KE:ApplyFramePosition(self.frame, self.db.Position, self.db)
end

-- Show combat cross
function CC:Show(isPreview)
    if not self.frame then
        self:CreateFrame()
        self:ApplySettings()
    end
    if not self.frame then return end

    if isPreview then
        self.previewActive = true
    else
        self.combatActive = true
    end

    if self.previewActive or self.combatActive then
        if not self.frame:IsShown() then
            self.frame:Show()
            self.frame:SetAlpha(0)
            UIFrameFadeIn(self.frame, 0.3, 0, 1)
        end
    end
end

-- Hide combat cross
function CC:Hide(isPreview)
    if not self.frame then return end

    if isPreview then
        self.previewActive = false
    else
        self.combatActive = false
    end

    if not self.previewActive and not self.combatActive then
        self.frame:Hide()
    end
end

function CC:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "CombatCross", displayName = "Combat Cross", frame = self.frame,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos) self.db.Position = pos; KE:ApplyFramePosition(self.frame, self.db.Position, self.db) end,
            getParentFrame = function() return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame) end,
            guiPath = "CombatCross",
        })
        self.editModeRegistered = true
    end
end

-- Preview support
function CC:ShowPreview()
    if InCombatLockdown() then return end
    self:RegWithEditMode()
    self:Show(true)
end

function CC:HidePreview()
    if InCombatLockdown() then return end
    if not self.previewActive then return end
    self:Hide(true)
end

-- Combat events
function CC:OnEnterCombat()
    if not self.db.Enabled then return end
    self:Show(false)
end

function CC:OnExitCombat()
    if not self.db.Enabled then return end
    self:Hide(false)
end

-- Refresh
function CC:Refresh()
    self:ApplySettings()
end

-- Module OnEnable
function CC:OnEnable()
    if not self.db.Enabled then return end
    self:CreateFrame()
    self:RegWithEditMode()
    self:ApplySettings()

    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnEnterCombat")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnExitCombat")
end

-- Module OnDisable
function CC:OnDisable()
    self:UnregisterAllEvents()
    if self.frame then self.frame:Hide() end
end
