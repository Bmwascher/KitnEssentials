-- ╔══════════════════════════════════════════════════════════╗
-- ║  GreatVaultAlert.lua                                     ║
-- ║  Module: Great Vault Alert                               ║
-- ║  Purpose: Shows loot spec when opening the Great Vault   ║
-- ║           with class color and sound alert.              ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class GreatVaultAlert: AceModule, AceEvent-3.0
local GVA = KitnEssentials:NewModule("GreatVaultAlert", "AceEvent-3.0")

local CreateFrame = CreateFrame
local UnitClass = UnitClass
local InCombatLockdown = InCombatLockdown
local PlaySoundFile = PlaySoundFile
local C_Timer = C_Timer
local string_format = string.format

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
local VAULT_SPELL_ID = 1271478

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------
GVA.alertFrame = nil
GVA.isPreview = false
GVA.editModeRegistered = false

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function GVA:UpdateDB()
    self.db = KE.db.profile.GreatVaultAlert
end

---------------------------------------------------------------------------------
-- Core Logic
---------------------------------------------------------------------------------
function GVA:GetLootSpecInfo()
    local specID = GetLootSpecialization()
    local name, icon

    if specID == 0 then
        local index = GetSpecialization()
        if index then
            local info = { GetSpecializationInfo(index) }
            name = info[2]
            icon = info[4]
        end
    else
        local info = { GetSpecializationInfoByID(specID) }
        name = info[2]
        icon = info[4]
    end

    local _, class = UnitClass("player")
    local color = RAID_CLASS_COLORS[class] and RAID_CLASS_COLORS[class].colorStr or "ffffffff"

    return name or "Unknown", icon or 0, color
end

---------------------------------------------------------------------------------
-- Frame Creation
---------------------------------------------------------------------------------
function GVA:CreateAlertFrame()
    if self.alertFrame then return end

    local frame = CreateFrame("Frame", "KE_GreatVaultAlertFrame", UIParent)
    frame:SetSize(400, 30)
    frame:SetFrameStrata(self.db.Strata or "HIGH")

    local text = frame:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER")
    frame.text = text

    frame:Hide()
    self.alertFrame = frame
end

function GVA:ShowAlert(specName, specIcon, classColorStr)
    if not self.alertFrame then return end
    local db = self.db

    KE:ApplyFont(self.alertFrame.text, db.FontFace, db.FontSize, db.FontOutline)

    local msg = string_format(
        "Opening |cff7ad5ff[Great Vault]|r as: |c%s|T%d:0|t %s|r",
        classColorStr, specIcon, specName
    )
    self.alertFrame.text:SetText(msg)
    self.alertFrame:SetAlpha(1)
    self.alertFrame:Show()

    -- Auto-hide after duration
    if self._hideTimer then self._hideTimer:Cancel() end
    self._hideTimer = C_Timer.NewTimer(db.AlertDuration or 3, function()
        if self.alertFrame and not self.isPreview then
            self.alertFrame:Hide()
        end
    end)
end

function GVA:HideAlert()
    if self._hideTimer then self._hideTimer:Cancel(); self._hideTimer = nil end
    if self.alertFrame then self.alertFrame:Hide() end
end

---------------------------------------------------------------------------------
-- Event Handlers
---------------------------------------------------------------------------------
function GVA:OnSpellcastStart(_, unit, _, spellID)
    if unit ~= "player" or spellID ~= VAULT_SPELL_ID then return end
    if InCombatLockdown() then return end

    local specName, specIcon, classColorStr = self:GetLootSpecInfo()
    self:ShowAlert(specName, specIcon, classColorStr)

    if self.db.ShowChatMessage then
        local chatMsg = string_format(
            "Opening |cff7ad5ff[Great Vault]|r as: |c%s|T%d:0|t %s|r",
            classColorStr, specIcon, specName
        )
        KE:Print(chatMsg)
    end

    if self.db.PlaySound and self.db.SoundFile and self.db.SoundFile ~= "None" then
        local path = KE.LSM and KE.LSM:Fetch("sound", self.db.SoundFile)
        if path then
            PlaySoundFile(path, self.db.SoundChannel or "Master")
        end
    end
end

function GVA:OnSpellcastSucceeded(_, unit, _, spellID)
    if unit ~= "player" or spellID ~= VAULT_SPELL_ID then return end

    if self.db.ShowChatMessage then
        local specName, specIcon, classColorStr = self:GetLootSpecInfo()
        local chatMsg = string_format(
            "Opened |cff7ad5ff[Great Vault]|r as: |c%s|T%d:0|t %s|r",
            classColorStr, specIcon, specName
        )
        KE:Print(chatMsg)
    end

    self:HideAlert()
end

function GVA:OnSpellcastInterrupted(_, unit, _, spellID)
    if unit ~= "player" or spellID ~= VAULT_SPELL_ID then return end
    self:HideAlert()
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
function GVA:ApplySettings()
    if not self.alertFrame then return end

    KE:ApplyFramePosition(self.alertFrame, self.db.Position, self.db)

    if self.db.Strata then
        self.alertFrame:SetFrameStrata(self.db.Strata)
    end

    if self.alertFrame.text then
        KE:ApplyFont(self.alertFrame.text, self.db.FontFace, self.db.FontSize, self.db.FontOutline)
    end
end

---------------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------------
function GVA:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "GreatVaultAlert",
            displayName = "Great Vault Alert",
            frame = self.alertFrame,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos)
                self.db.Position = pos
                KE:ApplyFramePosition(self.alertFrame, self.db.Position, self.db)
            end,
            getParentFrame = function()
                return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame)
            end,
            guiPath = "GreatVaultAlert",
        })
        self.editModeRegistered = true
    end
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------
function GVA:ShowPreview()
    if not self.alertFrame then
        self:CreateAlertFrame()
    end
    self:RegWithEditMode()
    self.isPreview = true

    local specName, specIcon, classColorStr = self:GetLootSpecInfo()
    self:ShowAlert(specName, specIcon, classColorStr)
    self:ApplySettings()
end

function GVA:HidePreview()
    self.isPreview = false
    self:HideAlert()
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function GVA:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function GVA:OnEnable()
    if not self.db.Enabled then return end

    self:CreateAlertFrame()
    self:RegWithEditMode()

    self:RegisterEvent("UNIT_SPELLCAST_START", "OnSpellcastStart")
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnSpellcastSucceeded")
    self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", "OnSpellcastInterrupted")
    self:RegisterEvent("UNIT_SPELLCAST_STOP", "OnSpellcastInterrupted")

    self:ApplySettings()
end

function GVA:OnDisable()
    self:UnregisterAllEvents()
    self:HideAlert()
    self.isPreview = false
end
