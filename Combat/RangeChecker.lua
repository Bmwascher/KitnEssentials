-- ╔══════════════════════════════════════════════════════════╗
-- ║  RangeChecker.lua                                        ║
-- ║  Module: Range Display                                   ║
-- ║  Purpose: Target range text with out-of-range color      ║
-- ║           warning using LibRangeCheck-3.0.               ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class RangeChecker: AceModule, AceEvent-3.0
local RC = KitnEssentials:NewModule("RangeChecker", "AceEvent-3.0")
local LRC = LibStub("LibRangeCheck-3.0", true)

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
local CreateFrame = CreateFrame
local UnitExists, UnitIsUnit = UnitExists, UnitIsUnit
local InCombatLockdown = InCombatLockdown
local unpack = unpack

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function RC:UpdateDB()
    self.db = KE.db.profile.RangeChecker
end

function RC:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

---------------------------------------------------------------------------------
-- Color
---------------------------------------------------------------------------------
function RC:BuildGradientPalette()
    local r1, g1, b1 = KE:ResolveColor(self.db.ColorOne,   { 1, 0, 0, 1 })
    local r2, g2, b2 = KE:ResolveColor(self.db.ColorTwo,   { 1, 0.42, 0, 1 })
    local r3, g3, b3 = KE:ResolveColor(self.db.ColorThree, { 1, 0.82, 0, 1 })
    local r4, g4, b4 = KE:ResolveColor(self.db.ColorFour,  { 0, 1, 0, 1 })

    self.gradientPalette = {
        r1, g1, b1,
        r2, g2, b2,
        r3, g3, b3,
        r4, g4, b4,
    }
end

function RC:GetColorForRange(minRange)
    local maxRange = self.db.MaxRange or 40

    return KE:ColorGradient(
        maxRange - (minRange or 0),
        maxRange,
        unpack(self.gradientPalette)
    )
end

function RC:FormatRangeText(minRange, maxRange)
    if minRange and maxRange then
        return minRange .. " - " .. maxRange
    elseif maxRange then
        return "0 - " .. maxRange
    elseif minRange then
        -- minRange-only = target is beyond LibRangeCheck's longest checker for
        -- this target relation (typically opposite-faction / hostile NPC, where
        -- hostile-spell ranges cap at ~25-40y depending on class/spec). The
        -- "+" indicates "at least this far"; the actual distance can't be
        -- measured further without a longer-range checker spell on the player.
        return minRange .. "+"
    else
        return "--"
    end
end

---------------------------------------------------------------------------------
-- Frame Creation
---------------------------------------------------------------------------------
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

---------------------------------------------------------------------------------
-- Apply Settings
---------------------------------------------------------------------------------
function RC:ApplySettings()
    self:BuildGradientPalette()
    if not self.frame or not self.text then return end
    KE:ApplyFontToText(self.text, self.db.FontFace, self.db.FontSize, self.db.FontOutline)
    self.frame:SetFrameStrata(self.db.Strata or "HIGH")
    -- Invalidate cached text dimensions — font/size may have changed.
    self.lastSizedText = nil
    self:ApplyPosition()
end

function RC:ApplyPosition()
    if not self.db.Enabled then return end
    if not self.frame then return end
    KE:ApplyFramePositionWithSnap(self.frame, self.db.Position, self.db)
end

---------------------------------------------------------------------------------
-- Core Logic
---------------------------------------------------------------------------------
function RC:ShouldShow()
    if not self.db.Enabled then return false end
    if self.isPreview then return true end
    if not UnitExists("target") then return false end
    if UnitIsUnit("target", "player") then return false end
    if self.db.CombatOnly and not InCombatLockdown() then return false end
    return true
end

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
    -- Last-string gate: range text changes infrequently relative to the 10fps
    -- poll. SetText invalidates FontString layout even when the rendered output
    -- is identical. Safe because rangeText derives from LibRangeCheck integers,
    -- not secret-tainted unit data. Same pattern as DungeonTimers timeStr gate.
    if rangeText ~= self.lastRangeText then
        self.lastRangeText = rangeText
        self.text:SetText(rangeText)
    end

    local rangeValue = minRange or maxRange or 40

    if rangeValue ~= self.lastRangeValue then
        self.lastRangeValue = rangeValue
        local r, g, b = self:GetColorForRange(rangeValue)
        self.text:SetTextColor(r, g, b, 1)
    end

    -- Only re-query frame size when the displayed text actually changes
    -- (GetStringWidth/GetStringHeight are not cheap in the throttled poll).
    if rangeText ~= self.lastSizedText then
        self.lastSizedText = rangeText
        local textWidth = self.text:GetStringWidth() or 50
        local textHeight = self.text:GetStringHeight() or 20
        -- GetStringWidth returns a float; snap derived size to pixel grid so
        -- the frame's right/bottom edges land on integer pixels.
        self.frame:SetSize(KE:PixelSnap(textWidth + 10), KE:PixelSnap(textHeight + 4))
    end
    self.frame:Show()
end

local updateElapsed = 0
function RC:OnUpdate(elapsed)
    updateElapsed = updateElapsed + elapsed
    if updateElapsed < (self.db.UpdateThrottle or 0.1) then return end
    updateElapsed = 0
    self:UpdateRange()
end

---------------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------------
function RC:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "RangeChecker", displayName = "Range Checker", frame = self.frame,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos) self.db.Position = pos; KE:ApplyFramePositionWithSnap(self.frame, self.db.Position, self.db) end,
            getParentFrame = function() return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame) end,
            guiPath = "RangeChecker",
        })
        self.editModeRegistered = true
    end
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------
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

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
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

function RC:OnDisable()
    if self.frame then
        self.frame:SetScript("OnUpdate", nil)
        self.frame:Hide()
    end
    self.isPreview = false
    self:UnregisterAllEvents()
end
