-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

-- Create module
---@class RangeChecker: AceModule, AceEvent-3.0
local RC = KitnEssentials:NewModule("RangeChecker", "AceEvent-3.0")
local LRC = LibStub("LibRangeCheck-3.0", true)

-- Localization
local CreateFrame = CreateFrame
local UnitExists, UnitIsUnit = UnitExists, UnitIsUnit
local InCombatLockdown = InCombatLockdown
local unpack = unpack
local tostring = tostring

-- Update db
function RC:UpdateDB()
    self.db = KE.db.profile.RangeChecker
end

-- Module init
function RC:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

-- Build color gradient palette from 4 colors
function RC:BuildGradientPalette()
    local c1 = self.db.ColorOne or { 1, 0, 0 }
    local c2 = self.db.ColorTwo or { 1, 0.42, 0 }
    local c3 = self.db.ColorThree or { 1, 0.82, 0 }
    local c4 = self.db.ColorFour or { 0, 1, 0 }

    self.gradientPalette = {
        c1[1], c1[2], c1[3],
        c2[1], c2[2], c2[3],
        c3[1], c3[2], c3[3],
        c4[1], c4[2], c4[3],
    }
end

-- Get color based on range via gradient
function RC:GetColorForRange(minRange)
    local maxRange = self.db.MaxRange or 40

    return KE:ColorGradient(
        maxRange - (minRange or 0),
        maxRange,
        unpack(self.gradientPalette)
    )
end

-- Format range text
function RC:FormatRangeText(minRange, maxRange)
    if minRange and maxRange then
        return minRange .. " - " .. maxRange
    elseif maxRange then
        return "0 - " .. maxRange
    elseif minRange then
        return tostring(minRange)
    else
        return "--"
    end
end

-- Create range display frame
function RC:CreateFrame()
    if self.frame then return end
    local parent = KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame)

    local frame = CreateFrame("Frame", "KE_RangeCheckerFrame", parent)
    frame:SetSize(100, 25)
    frame:SetFrameStrata(self.db.Strata or "HIGH")
    frame:EnableMouse(false)
    frame:SetMouseClickEnabled(false)
    frame:Hide()

    local text = frame:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    text:SetJustifyH("CENTER")

    self.frame = frame
    self.text = text

    self:ApplySettings()
end

-- Apply settings
function RC:ApplySettings()
    self:BuildGradientPalette()
    if not self.frame or not self.text then return end
    KE:ApplyFontToText(self.text, self.db.FontFace, self.db.FontSize, self.db.FontOutline)
    self.frame:SetFrameStrata(self.db.Strata or "HIGH")
    self:ApplyPosition()
end

-- Apply position
function RC:ApplyPosition()
    if not self.db.Enabled then return end
    if not self.frame then return end
    KE:ApplyFramePosition(self.frame, self.db.Position, self.db)
end

-- Check if we should show the range display
function RC:ShouldShow()
    if not self.db.Enabled then return false end
    if self.isPreview then return true end
    if not UnitExists("target") then return false end
    if UnitIsUnit("target", "player") then return false end
    if self.db.CombatOnly and not InCombatLockdown() then return false end
    return true
end

-- Update range display
function RC:UpdateRange()
    if not self.frame or not self.text then return end

    if not self:ShouldShow() then
        self.frame:Hide()
        return
    end

    local minRange, maxRange

    if self.isPreview then
        minRange, maxRange = 10, 15
    else
        if LRC then
            minRange, maxRange = LRC:GetRange("target")
        end
    end

    local rangeText = self:FormatRangeText(minRange, maxRange)
    self.text:SetText(rangeText)

    local rangeValue = minRange or maxRange or 40

    if rangeValue ~= self.lastRangeValue then
        self.lastRangeValue = rangeValue
        local r, g, b = self:GetColorForRange(rangeValue)
        self.text:SetTextColor(r, g, b, 1)
    end

    local textWidth = self.text:GetStringWidth() or 50
    local textHeight = self.text:GetStringHeight() or 20
    self.frame:SetSize(textWidth + 10, textHeight + 4)
    self.frame:Show()
end

-- OnUpdate handler
local updateElapsed = 0
function RC:OnUpdate(elapsed)
    updateElapsed = updateElapsed + elapsed
    if updateElapsed < self.db.UpdateThrottle then return end
    updateElapsed = 0
    self:UpdateRange()
end

function RC:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "RangeChecker", displayName = "Range Checker", frame = self.frame,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos) self.db.Position = pos; KE:ApplyFramePosition(self.frame, self.db.Position, self.db) end,
            getParentFrame = function() return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame) end,
            guiPath = "RangeChecker",
        })
        self.editModeRegistered = true
    end
end

-- Preview mode
function RC:ShowPreview()
    if not self.frame then self:CreateFrame() end
    self:RegWithEditMode()
    self.isPreview = true
    self:ApplySettings()
    self:UpdateRange()
end

function RC:HidePreview()
    self.isPreview = false
    self:UpdateRange()
end

-- Module enable
function RC:OnEnable()
    if not self.db.Enabled then return end
    if not LRC then
        KE:Print("RangeChecker: LibRangeCheck-3.0 not found!")
        return
    end
    self:CreateFrame()
    self:RegWithEditMode()
    C_Timer.After(0.5, function() self:ApplyPosition() end)

    self:RegisterEvent("PLAYER_TARGET_CHANGED", function() self:UpdateRange() end)
    self:RegisterEvent("PLAYER_REGEN_DISABLED", function() self:UpdateRange() end)
    self:RegisterEvent("PLAYER_REGEN_ENABLED", function() self:UpdateRange() end)

    self.frame:SetScript("OnUpdate", function(_, elapsed) self:OnUpdate(elapsed) end)
    self:UpdateRange()
end

-- Module disable
function RC:OnDisable()
    if self.frame then
        self.frame:SetScript("OnUpdate", nil)
        self.frame:Hide()
    end
    self.isPreview = false
    self:UnregisterAllEvents()
end
