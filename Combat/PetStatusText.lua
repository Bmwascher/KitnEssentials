-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

-- Create module
---@class PetStatusText: AceModule, AceEvent-3.0
local PS = KitnEssentials:NewModule("PetStatusText", "AceEvent-3.0")

-- Localization
local UnitClass = UnitClass
local IsMounted = IsMounted
local UnitOnTaxi = UnitOnTaxi
local UnitInVehicle = UnitInVehicle
local UnitHasVehicleUI = UnitHasVehicleUI
local GetSpecialization = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo
local UnitExists = UnitExists
local CreateFrame = CreateFrame
local GetPetActionInfo = GetPetActionInfo
local PetHasActionBar = PetHasActionBar
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local IsPlayerSpell = IsPlayerSpell
local C_Timer = C_Timer
local C_SpellBook = C_SpellBook

-- Tracked pet classes
local PET_CLASSES = {
    ["HUNTER"] = { summonSpellId = 883, reviveSpellId = 982, specId = nil },
    ["WARLOCK"] = { summonSpellId = 688, reviveSpellId = nil, specId = nil },
    ["DEATHKNIGHT"] = { summonSpellId = 46584, reviveSpellId = nil, specId = 252 },
    ["MAGE"] = { summonSpellId = 31687, reviveSpellId = nil, specId = 64 },
}

-- Module state
local petInfo = nil
local petDeathTracked = false

-- Pet status enum
local PET_STATUS = {
    NONE = 0,
    MISSING = 1,
    DEAD = 2,
    PASSIVE = 3,
}

-- Module state
PS.frame = nil
PS.text = nil

-- Helper: Is player mounted or in vehicle
local function IsPlayerMounted()
    return IsMounted() or UnitOnTaxi("player") or UnitInVehicle("player") or UnitHasVehicleUI("player")
end

-- Helper: Check if pet is on passive stance
local function IsPetOnPassive()
    if not UnitExists("pet") or not PetHasActionBar() then return false end
    for slot = 1, 10 do
        local name, _, isToken, isActive = GetPetActionInfo(slot)
        if isToken and name == "PET_MODE_PASSIVE" and isActive then return true end
    end
    return false
end

-- Helper: Check and track pet death state
local function CheckAndUpdatePetDeathState()
    if UnitExists("pet") and not UnitIsDeadOrGhost("pet") then
        petDeathTracked = false
        return false
    end

    if UnitExists("pet") and UnitIsDeadOrGhost("pet") then
        petDeathTracked = true
        return true
    end

    if petDeathTracked then return true end

    return false
end

-- Reset death tracking
local function ResetPetDeathTracking()
    petDeathTracked = false
end

-- Check pet status and return status code + text + color
local function CheckPetStatus()
    if not petInfo then return PET_STATUS.NONE, nil, nil end
    if IsPlayerMounted() then return PET_STATUS.NONE, nil, nil end

    local specIndex = GetSpecialization()
    local specID = GetSpecializationInfo(specIndex)

    -- MM Hunter with Unbreakable Bond (466867) or Spotter's Mark (466872) — both replace the pet
    if specID == 254 and (IsPlayerSpell(466867) or IsPlayerSpell(466872)) then
        return PET_STATUS.NONE, nil, nil
    end

    -- Spec check for class-specific pets
    if petInfo.specId then
        if specIndex then
            if specID ~= petInfo.specId then return PET_STATUS.NONE, nil, nil end
        end
    end

    if not C_SpellBook.IsSpellKnown(petInfo.summonSpellId) then return PET_STATUS.NONE, nil, nil end

    -- Priority: Dead > Passive > Missing
    if CheckAndUpdatePetDeathState() then
        return PET_STATUS.DEAD, PS.db.PetDead, PS.db.DeadColor
    end

    if UnitExists("pet") then
        if IsPetOnPassive() then
            return PET_STATUS.PASSIVE, PS.db.PetPassive, PS.db.PassiveColor
        end
        return PET_STATUS.NONE, nil, nil
    else
        -- Check for Grimoire of Sacrifice (Warlock talent that consumes the pet)
        local sacrificeAura = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID(196099)
        if sacrificeAura then
            return PET_STATUS.NONE, nil, nil
        end
        return PET_STATUS.MISSING, PS.db.PetMissing, PS.db.MissingColor
    end
end

-- Update db
function PS:UpdateDB()
    self.db = KE.db.profile.PetStatusText
end

-- Module init
function PS:OnInitialize()
    self:UpdateDB()

    local _, class = UnitClass("player")
    petInfo = PET_CLASSES[class]

    self:SetEnabledState(false)
end

-- Create the display frame
function PS:CreateFrame()
    if self.frame then return end

    local frame = CreateFrame("Frame", "KE_PetStatusTextFrame", UIParent)
    frame:SetSize(200, 50)

    local text = frame:CreateFontString(nil, "OVERLAY")
    local fontPath = KE:GetFontPath(self.db.FontFace)
    text:SetFont(fontPath, self.db.FontSize, self.db.FontOutline or "")
    text:SetTextColor(1, 0.82, 0, 1)
    text:ClearAllPoints()
    text:SetPoint("CENTER", frame, "CENTER", 0, 0)

    self.frame = frame
    self.frame.text = text
    self.text = text

    local width, height = math.max(text:GetWidth(), 170), math.max(text:GetHeight(), 18)
    frame:SetSize(width + 5, height + 5)

    self.frame:Hide()
end

-- Update the displayed text
function PS:UpdatePetText()
    local status, message, color = CheckPetStatus()

    if message and color then
        self.text:SetText(message)
        self.text:SetTextColor(color[1], color[2], color[3], color[4] or 1)
        self.frame:Show()
    else
        if self.frame then self.frame:Hide() end
    end
end

-- Apply all settings
function PS:ApplySettings()
    if not self.frame then return end

    KE:ApplyFramePosition(self.frame, self.db.Position, self.db)
    KE:ApplyFontToText(self.text, self.db.FontFace, self.db.FontSize, self.db.FontOutline)

    if self.isPreview then
        self:ShowPreview(self.previewState)
    end
end

function PS:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "PetStatusText", displayName = "Pet Status Text", frame = self.frame,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos) self.db.Position = pos; KE:ApplyFramePosition(self.frame, self.db.Position, self.db) end,
            getParentFrame = function() return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame) end,
            guiPath = "PetStatusText",
        })
        self.editModeRegistered = true
    end
end

-- Preview mode for GUI
function PS:ShowPreview(state)
    if not self.frame then
        self:CreateFrame()
    end
    self:RegWithEditMode()

    self.isPreview = true
    self.previewState = state or "missing"

    local previewText, previewColor
    if self.previewState == "dead" then
        previewText = self.db.PetDead or "PET DEAD"
        previewColor = self.db.DeadColor or { 1, 0.2, 0.2, 1 }
    elseif self.previewState == "passive" then
        previewText = self.db.PetPassive or "PET PASSIVE"
        previewColor = self.db.PassiveColor or { 0.3, 0.7, 1, 1 }
    else
        previewText = self.db.PetMissing or "PET MISSING"
        previewColor = self.db.MissingColor or { 1, 0.82, 0, 1 }
    end

    self.text:SetText(previewText)
    self.text:SetTextColor(previewColor[1], previewColor[2], previewColor[3], previewColor[4] or 1)
    self.frame:Show()
end

function PS:HidePreview()
    self.isPreview = false
    if self.db.Enabled then
        self:UpdatePetText()
    else
        if self.frame then self.frame:Hide() end
    end
end

-- Module OnEnable
function PS:OnEnable()
    if not self.db.Enabled then return end
    if not petInfo then return end

    self:CreateFrame()
    self:RegWithEditMode()

    self:RegisterEvent("UNIT_PET", function(_, unit)
        if unit == "player" then
            C_Timer.After(0.2, function()
                if UnitExists("pet") and not UnitIsDeadOrGhost("pet") then
                    ResetPetDeathTracking()
                end
                self:UpdatePetText()
            end)
        end
    end)

    self:RegisterEvent("PLAYER_REGEN_ENABLED", "UpdatePetText")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function() C_Timer.After(1, function() self:UpdatePetText() end) end)
    self:RegisterEvent("SPELLS_CHANGED", "UpdatePetText")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "UpdatePetText")
    self:RegisterEvent("UNIT_DIED", "UpdatePetText")

    self:RegisterEvent("PET_BAR_UPDATE", function()
        C_Timer.After(0.1, function() self:UpdatePetText() end)
    end)

    self:UpdatePetText()

    C_Timer.After(1, function()
        self:ApplySettings()
    end)
end

-- Module OnDisable
function PS:OnDisable()
    if self.frame then self.frame:Hide() end
    self:UnregisterAllEvents()
end
