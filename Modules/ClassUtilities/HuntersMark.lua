-- ╔══════════════════════════════════════════════════════════╗
-- ║  HuntersMark.lua                                         ║
-- ║  Module: Hunter's Mark Missing                           ║
-- ║  Purpose: Alert when Hunter's Mark is not applied to     ║
-- ║           the current target.                            ║
-- ║  Note: Hunter only.                                      ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class HuntersMark: AceModule, AceEvent-3.0
---@field editModeRegistered boolean? true while the Edit Mode element is registered; nil once dropped
local HM = KitnEssentials:NewModule("HuntersMark", "AceEvent-3.0")
HM.classRestriction = "HUNTER"

local CreateFrame = CreateFrame
local UnitExists = UnitExists
local UnitClass = UnitClass
local UnitIsBossMob = UnitIsBossMob
local IsInInstance = IsInInstance
local C_NamePlate = C_NamePlate
local next = next
local wipe = wipe
local type = type

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
local _, playerClass = UnitClass("player")
local isHunter = playerClass == "HUNTER"
local SPELL_ID = 257284 -- Hunter's Mark
local ATTACH_KEY = "huntersMark"
local DETACHED_HEIGHT = 40

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------
local markedUnits = {}
local pendingUnitUpdates = {} -- Coalescing table for UNIT_AURA events
HM.isPreview = false

-- Get safe unit token from nameplate
local function GetSafeUnitToken(namePlate)
    if not namePlate then return nil end
    local unit = namePlate.unitToken
    if not KE:IsSafeValue(unit) then return nil end
    if type(unit) ~= "string" then return nil end
    return unit
end

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function HM:UpdateDB()
    self.db = KE.db.profile.HuntersMark
end

function HM:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

---------------------------------------------------------------------------------
-- Core Logic
---------------------------------------------------------------------------------

-- Icon helpers: KE:ApplyIconZoom() and KE:AddIconBorders() in Core/Widgets.lua
local function CreateIconFrame(parent, iconSize)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(iconSize, iconSize)

    KE:AddIconBorders(frame)

    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetAllPoints(frame)
    KE:ApplyIconZoom(frame.icon)

    function frame:SetIconSize(newSize)
        self:SetSize(newSize, newSize)
        self.icon:SetAllPoints(self)
    end

    return frame
end

local function IsInRaid()
    local inInstance, instanceType = IsInInstance()
    return inInstance and instanceType == "raid"
end

-- Every show and hide of the warning goes through here, so an attached
-- warning's place in the Combat Texts stack follows it.
function HM:SetWarningShown(shown)
    if not self.frame then return end
    if shown then self.frame:Show() else self.frame:Hide() end
    local cm = KitnEssentials:GetModule("CombatTexts", true)
    if cm then cm:AttachedFrameChanged(ATTACH_KEY) end
end

function HM:UpdateWarningDisplay()
    if not isHunter then return end
    if self.isPreview then return end
    if not self.scanArmed then return end
    if not self.frame then return end

    -- During full restriction: hide and stop tracking entirely
    if KE:IsFullyRestricted() then
        wipe(markedUnits)
        self:SetWarningShown(false)
        return
    end

    -- No boss nameplates visible
    if not next(markedUnits) then
        self:SetWarningShown(false)
        return
    end

    -- Check if any visible boss has mark
    for _, hasAura in next, markedUnits do
        if hasAura then
            self:SetWarningShown(false)
            return
        end
    end

    -- Boss nameplate exists but missing mark
    self:SetWarningShown(true)
end

function HM:CheckUnitForMark(unit)
    if not isHunter then return end
    if not self.scanArmed then return end
    if KE:IsFullyRestricted() then return end
    -- The scan below hard errors without aura access, and the state machine
    -- above answers from the last event rather than from the restriction
    -- system. Ask the live question before the call that can throw.
    if KE:AreAuraIdentitiesHidden() then return end

    -- Validate unit is safe to use
    if not KE:IsSafeValue(unit) then return end
    if type(unit) ~= "string" then return end
    if not UnitExists(unit) or not UnitIsBossMob(unit) then return end

    local hasMarkNow = false
    local hitSecret = false

    AuraUtil.ForEachAura(unit, "HARMFUL", nil, function(auraInfo)
        if not auraInfo then return end

        -- A secret spell id cannot be matched; flag it and skip this aura
        if KE:IsSecretValue(auraInfo.spellId) then
            hitSecret = true
            return
        end

        -- Any hunter's mark counts, not only the player's own: the debuff is
        -- one per target.
        if auraInfo.spellId == SPELL_ID then
            hasMarkNow = true
            return true
        end
    end, true)

    -- If we hit secrets, assume mark is present (avoid false warnings)
    if hitSecret then
        markedUnits[unit] = true
    else
        markedUnits[unit] = hasMarkNow
    end

    self:UpdateWarningDisplay()
end

function HM:SetScanningActive(active)
    if not isHunter then return end
    if not self.scannerFrame then return end
    -- A world-enter callback queued before a disable can land after it; it
    -- must neither register the raid events nor hide a disabled preview.
    if not self.scanArmed then return end

    if active then
        self.scannerFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        self.scannerFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
        self.scannerFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        self.scannerFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        self.scannerFrame:RegisterEvent("ENCOUNTER_START")
        self.scannerFrame:RegisterEvent("ENCOUNTER_END")
        -- UNIT_AURA is registered unfiltered; the handler keeps nameplate units
        -- and the player's target.
        self.scannerFrame:RegisterEvent("UNIT_AURA")
    else
        self.scannerFrame:UnregisterEvent("NAME_PLATE_UNIT_ADDED")
        self.scannerFrame:UnregisterEvent("NAME_PLATE_UNIT_REMOVED")
        self.scannerFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
        self.scannerFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        self.scannerFrame:UnregisterEvent("ENCOUNTER_START")
        self.scannerFrame:UnregisterEvent("ENCOUNTER_END")
        self.scannerFrame:UnregisterEvent("UNIT_AURA")
        wipe(markedUnits)
        self:SetWarningShown(false)
    end
end

---------------------------------------------------------------------------------
-- Frame Creation
---------------------------------------------------------------------------------
function HM:CreateWarningFrame()
    if self.frame then return end

    local frame = CreateFrame("Frame", "KE_HuntersMarkWarning", UIParent)
    frame:SetSize(200, DETACHED_HEIGHT)

    local text = frame:CreateFontString(nil, "OVERLAY")
    text:SetFont(KE.FONT, self.db.FontSize or 16, "")
    text:SetPoint("CENTER")
    text:SetText("MISSING MARK")
    frame.text = text

    local iconSize = self.db.FontSize or 16
    local leftIcon = CreateIconFrame(frame, iconSize)
    leftIcon:SetPoint("RIGHT", text, "LEFT", -4, 0)
    frame.leftIcon = leftIcon

    local rightIcon = CreateIconFrame(frame, iconSize)
    rightIcon:SetPoint("LEFT", text, "RIGHT", 4, 0)
    frame.rightIcon = rightIcon

    frame:Hide()
    self.frame = frame
    -- Attached, the login anchor pass must not put the warning back on its
    -- own Player Frame position.
    KE:RegisterAnchorRepair(frame, function()
        return not self:IsAttached() and self.db.anchorFrameType == "PLAYERFRAME"
    end, function() self:ApplySettings() end)
    self:ApplySettings()
end

function HM:StartScanning()
    if not isHunter then return end
    -- A closed settings preview calls this whenever the saved setting is on,
    -- including while the module is disabled.
    if not self:IsEnabled() then return end
    if self.isPreview then return end
    if self.scanArmed then return end
    self.scanArmed = true

    -- Both frames outlive a disable. A re-enable re-registers the kept scanner
    -- and re-applies settings that may have changed while it was off.
    if self.frame then
        self:ApplySettings()
    else
        self:CreateWarningFrame()
    end
    if self.scannerFrame then
        self.scannerFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        if IsInRaid() then self:SetScanningActive(true) end
        return
    end

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

        -- Combat/encounter events: wipe and hide
        if event == "ENCOUNTER_START" or event == "PLAYER_REGEN_DISABLED" then
            wipe(markedUnits)
            self:SetWarningShown(false)
            return
        end

        -- When restrictions release, rescan all nameplates
        if event == "ENCOUNTER_END" or event == "PLAYER_REGEN_ENABLED" then
            if KE:IsFullyRestricted() then return end
            wipe(markedUnits)
            for _, namePlate in next, C_NamePlate.GetNamePlates() do
                local safeUnit = GetSafeUnitToken(namePlate)
                if safeUnit then
                    self:CheckUnitForMark(safeUnit)
                end
            end
            return
        end

        if KE:IsFullyRestricted() then return end

        -- Validate unit is safe before processing
        if not KE:IsSafeValue(unit) then return end
        if type(unit) ~= "string" then return end

        if event == "NAME_PLATE_UNIT_REMOVED" then
            markedUnits[unit] = nil
            pendingUnitUpdates[unit] = nil
            self:UpdateWarningDisplay()
        elseif event == "NAME_PLATE_UNIT_ADDED" then
            self:CheckUnitForMark(unit)
        elseif event == "UNIT_AURA" then
            -- Only nameplate units and the player's target.
            if not unit then return end
            if unit ~= "target" and not unit:match("^nameplate%d+$") then return end
            -- Coalesce UNIT_AURA events per-unit to prevent redundant scans
            if pendingUnitUpdates[unit] then return end
            pendingUnitUpdates[unit] = true
            C_Timer.After(0, function()
                pendingUnitUpdates[unit] = nil
                if KE:IsFullyRestricted() then return end
                self:CheckUnitForMark(unit)
            end)
        end
    end)

    self.scannerFrame = scanner

    if IsInRaid() then
        self:SetScanningActive(true)
    end
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
function HM:IsAttached()
    local cm = KitnEssentials:GetModule("CombatTexts", true)
    return cm ~= nil and cm:AcceptsAttach(self.db.AttachToCombatTexts == true)
end

-- Attached, the warning is a Combat Texts row: that module's face and
-- outline, the resolved size, and a row height that fits the text and icons.
-- Only an active module takes a slot: the page applies settings to a kept
-- frame while the module is off.
function HM:ApplySettings()
    if not self.db or not self.frame then return end
    local db = self.db
    local cm = KitnEssentials:GetModule("CombatTexts", true)
    local attached = (self:IsEnabled() or self.isPreview) and cm ~= nil and self:IsAttached()

    local face, outline, size = db.FontFace, db.FontOutline, db.FontSize
    if attached and cm then
        face, outline = cm.db.FontFace, cm.db.FontOutline
        size = cm.ResolveAttachedSize(true, db.AttachOwnFontSize, db.FontSize, cm.db.FontSize)
        self.frame:SetHeight(size + 2)
        attached = cm:SetAttachedFrame(ATTACH_KEY, self.frame)
    end
    if not attached then
        if cm then cm:SetAttachedFrame(ATTACH_KEY, nil) end
        self.frame:SetHeight(DETACHED_HEIGHT)
        KE:ApplyFramePosition(self.frame, db.Position, db)
    end
    if cm then cm:SyncAttachSubscription(self, self:IsEnabled() or self.isPreview) end
    if self:IsEnabled() or self.isPreview then self:RegWithEditMode() end

    -- Text settings
    local text = self.frame.text
    if text then
        local r, g, b, a = KE:ResolveColor(db.Color, { 1, 0.82, 0, 1 })
        KE:ApplyFontToText(text, face, size, outline)
        text:SetTextColor(r, g, b, a)
    end

    -- Icon settings
    local texture = C_Spell.GetSpellTexture(SPELL_ID)

    if self.frame.leftIcon then
        self.frame.leftIcon:SetIconSize(size)
        self.frame.leftIcon.icon:SetTexture(texture)
    end

    if self.frame.rightIcon then
        self.frame.rightIcon:SetIconSize(size)
        self.frame.rightIcon.icon:SetTexture(texture)
    end
end

---------------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------------
function HM:RegWithEditMode()
    if not KE.EditMode then return end
    -- Attached, the Combat Texts mover moves the warning; a second mover for
    -- it would fight that one.
    if self:IsAttached() then
        if self.editModeRegistered then
            KE.EditMode:UnregisterElement("HuntersMark")
            self.editModeRegistered = nil
        end
        return
    end
    if self.editModeRegistered then return end
    KE.EditMode:RegisterElement({
        key = "HuntersMark", displayName = "Hunter's Mark Warning", frame = self.frame,
        module = self,
        getPosition = function() return self.db.Position end,
        setPosition = function(pos) self.db.Position = pos; KE:ApplyFramePosition(self.frame, self.db.Position, self.db) end,
        getParentFrame = function() return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame) end,
        guiPath = "ClassTools",
        guiTab = "HuntersMark",
    })
    self.editModeRegistered = true
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------
function HM:ShowPreview()
    if not self.frame then
        self:CreateWarningFrame()
    end
    self:RegWithEditMode()
    self.isPreview = true
    self.frame:SetAlpha(1)
    self:ApplySettings()
    self:SetWarningShown(true)
end

function HM:HidePreview()
    self.isPreview = false
    if not self.frame then return end
    self:SetWarningShown(false)
    local cm = KitnEssentials:GetModule("CombatTexts", true)
    if cm then cm:SyncAttachSubscription(self, self:IsEnabled()) end

    if not self.db.Enabled then return end

    -- If module was enabled during preview, scanning never started
    if not self.scanArmed then
        self:StartScanning()
        return
    end

    if IsInRaid() then
        wipe(markedUnits)
        for _, namePlate in next, C_NamePlate.GetNamePlates() do
            local safeUnit = GetSafeUnitToken(namePlate)
            if safeUnit then
                self:CheckUnitForMark(safeUnit)
            end
        end
    end
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function HM:OnEnable()
    if not isHunter then return end
    if not self.db.Enabled then return end
    self:StartScanning()
    self:RegWithEditMode()
end

function HM:OnDisable()
    -- Both frames are kept for the next enable; only the events go.
    self.scanArmed = false
    if self.scannerFrame then
        self.scannerFrame:UnregisterAllEvents()
    end
    self:SetWarningShown(false)
    local cm = KitnEssentials:GetModule("CombatTexts", true)
    if cm then
        cm:SetAttachedFrame(ATTACH_KEY, nil)
        cm:SyncAttachSubscription(self, false)
    end
    -- Keeps the element out of /kes edit while the module is off. Clearing the
    -- guard is what lets a later enable register again.
    if KE.EditMode then KE.EditMode:UnregisterElement("HuntersMark") end
    self.editModeRegistered = nil
    wipe(markedUnits)
    self.isPreview = false
end
