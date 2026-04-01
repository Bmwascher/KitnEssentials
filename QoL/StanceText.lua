-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class StanceText: AceModule, AceEvent-3.0
local ST = KitnEssentials:NewModule("StanceText", "AceEvent-3.0")

-- Localization
local CreateFrame = CreateFrame
local GetShapeshiftForm, GetShapeshiftFormInfo = GetShapeshiftForm, GetShapeshiftFormInfo
local tostring = tostring
local C_UnitAuras = C_UnitAuras
local UnitClass = UnitClass
local issecretvalue = issecretvalue
local UIParent = UIParent

-- Module state
local playerClass = nil
local stanceTextFrame = nil

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
local function PlayerHasBuff(spellId)
    if not spellId then return false end
    if issecretvalue(spellId) then return false end
    local auraData = C_UnitAuras.GetPlayerAuraBySpellID(spellId)
    return auraData ~= nil
end

--------------------------------------------------------------------------------
-- Frame creation
--------------------------------------------------------------------------------
local function CreateStanceTextFrame()
    if stanceTextFrame then return end
    local db = ST.db

    stanceTextFrame = CreateFrame("Frame", "KE_StanceTextDisplay", UIParent)
    stanceTextFrame:SetSize(200, 30)
    stanceTextFrame:SetFrameStrata("HIGH")
    stanceTextFrame.text = stanceTextFrame:CreateFontString(nil, "OVERLAY")
    stanceTextFrame.text:SetFont(KE.FONT, 12, "")
    stanceTextFrame.text:SetPoint("CENTER", stanceTextFrame, "CENTER", 0, 0)

    KE:ApplyFramePosition(stanceTextFrame, db.Position, db)
    KE:ApplyFontToText(stanceTextFrame.text, db.FontFace, db.FontSize, db.FontOutline)

    local textPoint = KE:GetTextPointFromAnchor(db.Position.AnchorFrom)
    local textJustify = KE:GetTextJustifyFromAnchor(db.Position.AnchorFrom)
    stanceTextFrame.text:ClearAllPoints()
    stanceTextFrame.text:SetPoint(textPoint, stanceTextFrame, textPoint, 0, 0)
    stanceTextFrame.text:SetJustifyH(textJustify)
    stanceTextFrame.text:SetTextColor(1, 1, 1, 1)

    stanceTextFrame:Hide()
    ST.container = stanceTextFrame
end

--------------------------------------------------------------------------------
-- Core update
--------------------------------------------------------------------------------
local function UpdateStanceTextDisplay()
    if not ST.db then return end
    local db = ST.db

    if not db.Enabled then
        if stanceTextFrame then stanceTextFrame:Hide() end
        return
    end

    if playerClass ~= "WARRIOR" and playerClass ~= "PALADIN" and playerClass ~= "EVOKER" then
        if stanceTextFrame then stanceTextFrame:Hide() end
        return
    end

    if not stanceTextFrame then CreateStanceTextFrame() end

    local currentSpellId = nil

    -- Warrior / Evoker: detect via shapeshift form (persists in combat)
    if playerClass == "WARRIOR" or playerClass == "EVOKER" then
        local currentForm = GetShapeshiftForm()
        if currentForm > 0 then
            local _, _, _, formSpellId = GetShapeshiftFormInfo(currentForm)
            currentSpellId = formSpellId
        end
    end

    -- Paladin: detect via aura buff
    if playerClass == "PALADIN" then
        local paladinAuras = { 465, 317920, 32223 }
        for _, auraId in ipairs(paladinAuras) do
            if PlayerHasBuff(auraId) then
                currentSpellId = auraId
                break
            end
        end
    end

    if not currentSpellId then
        stanceTextFrame:Hide()
        return
    end

    local classData = db[playerClass]
    if not classData then
        stanceTextFrame:Hide()
        return
    end

    local stanceKey = tostring(currentSpellId)
    local stanceSettings = classData[stanceKey]

    if not stanceSettings or not stanceSettings.Enabled then
        stanceTextFrame:Hide()
        return
    end

    local text = stanceSettings.Text or "Stance"
    local color = stanceSettings.Color or { 1, 1, 1, 1 }

    stanceTextFrame.text:SetText(text)
    stanceTextFrame.text:SetTextColor(color[1], color[2], color[3], color[4] or 1)

    KE:ApplyFontToText(stanceTextFrame.text, db.FontFace, db.FontSize, db.FontOutline)
    KE:ApplyFramePosition(stanceTextFrame, db.Position, db)

    local textPoint = KE:GetTextPointFromAnchor(db.Position.AnchorFrom)
    local textJustify = KE:GetTextJustifyFromAnchor(db.Position.AnchorFrom)
    stanceTextFrame.text:ClearAllPoints()
    stanceTextFrame.text:SetPoint(textPoint, stanceTextFrame, textPoint, 0, 0)
    stanceTextFrame.text:SetJustifyH(textJustify)
    stanceTextFrame:Show()
end

--------------------------------------------------------------------------------
-- DB
--------------------------------------------------------------------------------
function ST:UpdateDB()
    self.db = KE.db.profile.StanceText
end

function ST:OnInitialize()
    self:UpdateDB()
    local _, class = UnitClass("player")
    playerClass = class
    self:SetEnabledState(false)
end

--------------------------------------------------------------------------------
-- Enable / Disable
--------------------------------------------------------------------------------
function ST:OnEnable()
    if not self.db or not self.db.Enabled then return end

    -- Only Warriors, Paladins, and Evokers have stance texts
    if playerClass ~= "WARRIOR" and playerClass ~= "PALADIN" and playerClass ~= "EVOKER" then return end

    CreateStanceTextFrame()
    self:RegWithEditMode()

    C_Timer.After(0.5, function() self:ApplySettings() end)

    self:RegisterEvent("UPDATE_SHAPESHIFT_FORM", function() UpdateStanceTextDisplay() end)
    self:RegisterEvent("UPDATE_SHAPESHIFT_FORMS", function() UpdateStanceTextDisplay() end)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function() C_Timer.After(1, UpdateStanceTextDisplay) end)

    -- Paladin auras are buffs, so track aura changes
    if playerClass == "PALADIN" then
        self:RegisterEvent("UNIT_AURA", function(_, unit)
            if unit == "player" then UpdateStanceTextDisplay() end
        end)
    end

    C_Timer.After(2, UpdateStanceTextDisplay)
end

function ST:OnDisable()
    self:UnregisterAllEvents()
    if stanceTextFrame then stanceTextFrame:Hide() end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------
function ST:Refresh()
    if self.db and self.db.Enabled then
        self:OnEnable()
    else
        self:OnDisable()
    end
end

function ST:ApplySettings()
    if not self.db then return end
    if not self.db.Enabled then return end

    if stanceTextFrame then
        KE:ApplyFontToText(stanceTextFrame.text, self.db.FontFace, self.db.FontSize, self.db.FontOutline)
        KE:ApplyFramePosition(stanceTextFrame, self.db.Position, self.db)

        local textPoint = KE:GetTextPointFromAnchor(self.db.Position.AnchorFrom)
        local textJustify = KE:GetTextJustifyFromAnchor(self.db.Position.AnchorFrom)
        stanceTextFrame.text:ClearAllPoints()
        stanceTextFrame.text:SetPoint(textPoint, stanceTextFrame, textPoint, 0, 0)
        stanceTextFrame.text:SetJustifyH(textJustify)

        if not self.db.Enabled then stanceTextFrame:Hide() end
    end

    UpdateStanceTextDisplay()
end

--------------------------------------------------------------------------------
-- Preview
--------------------------------------------------------------------------------
function ST:ShowPreview()
    if not stanceTextFrame then CreateStanceTextFrame() end
    self:RegWithEditMode()
    self.isPreview = true

    local db = self.db or {}

    if not db.Enabled then
        stanceTextFrame:Hide()
        return
    end

    KE:ApplyFontToText(stanceTextFrame.text, db.FontFace, db.FontSize, db.FontOutline)

    -- Show warrior Battle Stance as preview default
    local previewText = "BATTLE"
    local previewColor = { 1, 0, 0, 1 }

    local classData = db["WARRIOR"]
    if classData then
        local stanceSettings = classData["386164"]
        if stanceSettings then
            if stanceSettings.Text and stanceSettings.Text ~= "" then
                previewText = stanceSettings.Text
            end
            if stanceSettings.Color then
                previewColor = stanceSettings.Color
            end
        end
    end

    stanceTextFrame.text:SetText(previewText)
    stanceTextFrame.text:SetTextColor(previewColor[1], previewColor[2], previewColor[3], previewColor[4] or 1)

    KE:ApplyFramePosition(stanceTextFrame, db.Position, db)

    local textPoint = KE:GetTextPointFromAnchor(db.Position.AnchorFrom)
    local textJustify = KE:GetTextJustifyFromAnchor(db.Position.AnchorFrom)
    stanceTextFrame.text:ClearAllPoints()
    stanceTextFrame.text:SetPoint(textPoint, stanceTextFrame, textPoint, 0, 0)
    stanceTextFrame.text:SetJustifyH(textJustify)
    stanceTextFrame:Show()
end

function ST:HidePreview()
    self.isPreview = false
    if stanceTextFrame then stanceTextFrame:Hide() end
    if self.db and self.db.Enabled then
        C_Timer.After(0.1, UpdateStanceTextDisplay)
    end
end

--------------------------------------------------------------------------------
-- Edit Mode
--------------------------------------------------------------------------------
function ST:RegWithEditMode()
    if not KE.EditMode then return end
    if self.container and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "StanceText",
            displayName = "Stance Text",
            frame = self.container,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos) self.db.Position = pos; KE:ApplyFramePosition(self.container, self.db.Position, self.db) end,
            getParentFrame = function() return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame) end,
            guiPath = "StanceText",
        })
        self.editModeRegistered = true
    end
end
