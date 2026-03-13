-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class HuntersMark: AceModule
local HM = KitnEssentials:NewModule("HuntersMark")

local CreateFrame = CreateFrame
local UnitExists = UnitExists
local UnitClass = UnitClass
local UnitIsBossMob = UnitIsBossMob
local InCombatLockdown = InCombatLockdown
local IsInInstance = IsInInstance
local next = next
local wipe = wipe
local type = type

-- Class check
local _, playerClass = UnitClass("player")
local isHunter = playerClass == "HUNTER"

-- Module locals
local SPELL_ID = 257284 -- Hunter's Mark
local markedUnits = {}

HM.isPreview = false

--------------------------------------------------------------------------------
-- Inline helpers (KE has no core ApplyZoom/AddBorders/CreateIconFrame)
--------------------------------------------------------------------------------
local function ApplyZoom(texture, zoom)
    local texMin = 0.25 * zoom
    local texMax = 1 - 0.25 * zoom
    texture:SetTexCoord(texMin, texMax, texMin, texMax)
end

local function AddBorders(frame, color)
    local r, g, b, a = color[1], color[2], color[3], color[4] or 1

    local top = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    top:SetHeight(1)
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    top:SetColorTexture(r, g, b, a)
    top:SetTexelSnappingBias(0)
    top:SetSnapToPixelGrid(false)

    local bottom = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    bottom:SetHeight(1)
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    bottom:SetColorTexture(r, g, b, a)
    bottom:SetTexelSnappingBias(0)
    bottom:SetSnapToPixelGrid(false)

    local left = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    left:SetWidth(1)
    left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    left:SetColorTexture(r, g, b, a)
    left:SetTexelSnappingBias(0)
    left:SetSnapToPixelGrid(false)

    local right = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    right:SetWidth(1)
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    right:SetColorTexture(r, g, b, a)
    right:SetTexelSnappingBias(0)
    right:SetSnapToPixelGrid(false)
end

local function CreateIconFrame(parent, iconSize)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(iconSize, iconSize)

    AddBorders(frame, { 0, 0, 0, 1 })

    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetAllPoints(frame)
    ApplyZoom(frame.icon, 0.3)

    function frame:SetIconSize(newSize)
        self:SetSize(newSize, newSize)
        self.icon:SetAllPoints(self)
    end

    return frame
end

--------------------------------------------------------------------------------
-- DB
--------------------------------------------------------------------------------
function HM:UpdateDB()
    self.db = KE.db.profile.HuntersMark
end

function HM:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

--------------------------------------------------------------------------------
-- Raid check
--------------------------------------------------------------------------------
local function IsInRaid()
    local inInstance, instanceType = IsInInstance()
    return inInstance and instanceType == "raid"
end

--------------------------------------------------------------------------------
-- Warning frame
--------------------------------------------------------------------------------
function HM:CreateWarningFrame()
    if self.frame then return end

    local frame = CreateFrame("Frame", "KE_HuntersMarkWarning", UIParent)
    frame:SetSize(200, 40)

    -- Center text
    local text = frame:CreateFontString(nil, "OVERLAY")
    text:SetFont(KE.FONT, self.db.FontSize or 16, "")
    text:SetPoint("CENTER")
    text:SetText("MISSING MARK")
    frame.text = text

    -- Left icon
    local iconSize = self.db.FontSize or 16
    local leftIcon = CreateIconFrame(frame, iconSize)
    leftIcon:SetPoint("RIGHT", text, "LEFT", -4, 0)
    frame.leftIcon = leftIcon

    -- Right icon
    local rightIcon = CreateIconFrame(frame, iconSize)
    rightIcon:SetPoint("LEFT", text, "RIGHT", 4, 0)
    frame.rightIcon = rightIcon

    frame:Hide()
    self.frame = frame
    self:ApplySettings()
end

--------------------------------------------------------------------------------
-- Warning display logic
--------------------------------------------------------------------------------
function HM:UpdateWarningDisplay()
    if not isHunter then return end
    if self.isPreview then return end
    if not self.frame then return end

    -- No boss nameplates visible
    if not next(markedUnits) then
        self.frame:Hide()
        return
    end

    -- Check if any visible boss has mark
    for _, hasAura in next, markedUnits do
        if hasAura then
            self.frame:Hide()
            return
        end
    end

    -- Boss nameplate exists but missing mark
    self.frame:Show()
end

--------------------------------------------------------------------------------
-- Aura scanning
--------------------------------------------------------------------------------
function HM:CheckUnitForMark(unit)
    if not isHunter then return end
    if not unit or not UnitExists(unit) or not UnitIsBossMob(unit) then return end

    local hasMarkNow = false
    AuraUtil.ForEachAura(unit, "HARMFUL", nil, function(auraInfo)
        if auraInfo and auraInfo.spellId == SPELL_ID and auraInfo.sourceUnit == "player" then
            hasMarkNow = true
            return true
        end
    end, true)

    markedUnits[unit] = hasMarkNow
    self:UpdateWarningDisplay()
end

--------------------------------------------------------------------------------
-- Enable/disable nameplate scanning
--------------------------------------------------------------------------------
function HM:SetScanningActive(active)
    if not isHunter then return end
    if not self.scannerFrame then return end

    if active then
        self.scannerFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        self.scannerFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
        self.scannerFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        self.scannerFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        self.scannerFrame:RegisterUnitEvent("UNIT_AURA",
            "nameplate1", "nameplate2", "nameplate3", "nameplate4", "nameplate5",
            "nameplate6", "nameplate7", "nameplate8", "nameplate9", "nameplate10", "target")
    else
        self.scannerFrame:UnregisterEvent("NAME_PLATE_UNIT_ADDED")
        self.scannerFrame:UnregisterEvent("NAME_PLATE_UNIT_REMOVED")
        self.scannerFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
        self.scannerFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        self.scannerFrame:UnregisterEvent("UNIT_AURA")
        wipe(markedUnits)
        if self.frame then self.frame:Hide() end
    end
end

--------------------------------------------------------------------------------
-- Scanner setup
--------------------------------------------------------------------------------
function HM:StartScanning()
    if not isHunter then return end
    if self.isPreview then return end
    if self.scannerFrame then return end

    self:CreateWarningFrame()

    local scanner = CreateFrame("Frame")
    scanner:RegisterEvent("PLAYER_ENTERING_WORLD")

    scanner:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_ENTERING_WORLD" then
            C_Timer.After(0.5, function()
                self:SetScanningActive(IsInRaid())
            end)
            return
        end

        if not IsInRaid() then return end

        if event == "PLAYER_REGEN_DISABLED" then
            if self.frame then self.frame:Hide() end
            return
        end

        if event == "PLAYER_REGEN_ENABLED" then
            wipe(markedUnits)
            for _, namePlate in next, C_NamePlate.GetNamePlates() do
                if namePlate.unitToken then
                    self:CheckUnitForMark(namePlate.unitToken)
                end
            end
            return
        end

        if InCombatLockdown() then return end
        if type(unit) ~= "string" then return end

        if event == "NAME_PLATE_UNIT_REMOVED" then
            markedUnits[unit] = nil
            self:UpdateWarningDisplay()
        elseif event == "NAME_PLATE_UNIT_ADDED" or event == "UNIT_AURA" then
            self:CheckUnitForMark(unit)
        end
    end)

    self.scannerFrame = scanner

    if IsInRaid() then
        self:SetScanningActive(true)
    end
end

--------------------------------------------------------------------------------
-- Apply settings
--------------------------------------------------------------------------------
function HM:ApplySettings()
    if not self.db or not self.frame then return end

    KE:ApplyFramePosition(self.frame, self.db.Position, self.db)

    -- Text settings
    local text = self.frame.text
    if text then
        local color = self.db.Color or { 1, 0.82, 0, 1 }
        KE:ApplyFontToText(text, self.db.FontFace, self.db.FontSize, self.db.FontOutline)
        text:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    end

    -- Icon settings
    local texture = C_Spell.GetSpellTexture(SPELL_ID)

    if self.frame.leftIcon then
        self.frame.leftIcon:SetIconSize(self.db.FontSize)
        self.frame.leftIcon.icon:SetTexture(texture)
    end

    if self.frame.rightIcon then
        self.frame.rightIcon:SetIconSize(self.db.FontSize)
        self.frame.rightIcon.icon:SetTexture(texture)
    end
end

--------------------------------------------------------------------------------
-- Enable / Disable
--------------------------------------------------------------------------------
function HM:OnEnable()
    if not isHunter then return end
    if not self.db.Enabled then return end
    self:StartScanning()
    self:RegWithEditMode()
end

function HM:OnDisable()
    if self.scannerFrame then
        self.scannerFrame:UnregisterAllEvents()
        self.scannerFrame:SetScript("OnEvent", nil)
        self.scannerFrame = nil
    end
    if self.frame then
        self.frame:Hide()
        self.frame = nil
    end
    wipe(markedUnits)
    self.isPreview = false
end

--------------------------------------------------------------------------------
-- Edit Mode
--------------------------------------------------------------------------------
function HM:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "HuntersMark", displayName = "Hunter's Mark", frame = self.frame,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos) self.db.Position = pos; KE:ApplyFramePosition(self.frame, self.db.Position, self.db) end,
            getParentFrame = function() return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame) end,
            guiPath = "HuntersMark",
        })
        self.editModeRegistered = true
    end
end

--------------------------------------------------------------------------------
-- Preview
--------------------------------------------------------------------------------
function HM:ShowPreview()
    if not self.frame then
        self:CreateWarningFrame()
    end
    self:RegWithEditMode()
    self.isPreview = true
    self.frame:SetAlpha(1)
    self.frame:Show()
    self:ApplySettings()
end

function HM:HidePreview()
    self.isPreview = false
    if not self.frame then return end
    self.frame:Hide()

    if not self.db.Enabled then return end

    -- If module was enabled during preview, scanner never started
    if not self.scannerFrame then
        self:StartScanning()
        return
    end

    if IsInRaid() then
        wipe(markedUnits)
        for _, namePlate in next, C_NamePlate.GetNamePlates() do
            local unit = namePlate.unitToken
            if unit then
                self:CheckUnitForMark(unit)
            end
        end
    end
end
