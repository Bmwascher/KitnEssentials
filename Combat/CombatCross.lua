-- ╔══════════════════════════════════════════════════════════╗
-- ║  CombatCross.lua                                         ║
-- ║  Module: Player Crosshair                                ║
-- ║  Purpose: Static crosshair overlay with range-based      ║
-- ║           color warning (melee/ranged/healer).           ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class CombatCross: AceModule, AceEvent-3.0
local CC = KitnEssentials:NewModule("CombatCross", "AceEvent-3.0")

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
local select = select
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local UIFrameFadeIn = UIFrameFadeIn
local UIParent = UIParent
local GetSpecialization = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo
local C_Spell = C_Spell
local UnitExists = UnitExists

local FONT_SIZE_MULTIPLIER = 2
local RANGE_UPDATE_THROTTLE = 0.1
local rangeUpdateElapsed = 0

local MELEE_RANGE_ABILITIES = {
    -- Melee DPS
    [71]  = 6552,   -- Arms Warrior: Pummel
    [72]  = 6552,   -- Fury Warrior: Pummel
    [251] = 49020,  -- Frost DK: Obliterate
    [252] = 49998,  -- Unholy DK: Death Strike
    [577] = 162794, -- Havoc DH: Chaos Strike
    [103] = 22568,  -- Feral Druid: Ferocious Bite
    [255] = 186270, -- Survival Hunter: Raptor Strike
    [259] = 1329,   -- Assassination Rogue: Mutilate
    [260] = 193315, -- Outlaw Rogue: Sinister Strike
    [261] = 53,     -- Subtlety Rogue: Backstab
    [263] = 17364,  -- Enhancement Shaman: Stormstrike
    [269] = 100780, -- Windwalker Monk: Tiger Palm
    [70]  = 96231,  -- Retribution Paladin: Rebuke
    -- Tanks
    [73]  = 6552,   -- Protection Warrior: Pummel
    [250] = 49998,  -- Blood DK: Death Strike
    [581] = 225921, -- Vengeance DH: Shear
    [104] = 22568,  -- Guardian Druid: Mangle
    [268] = 100780, -- Brewmaster Monk: Tiger Palm
    [66]  = 35395,  -- Protection Paladin: Crusader Strike
}

local RANGED_RANGE_ABILITIES = {
    [102]  = 5176,   -- Balance Druid: Wrath (40yd)
    [1467] = 361469, -- Devastation Evoker: Living Flame (25yd)
    [1473] = 361469, -- Augmentation Evoker: Living Flame (25yd)
    [253]  = 77767,  -- Beast Mastery Hunter: Cobra Shot (40yd)
    [254]  = 185358, -- Marksmanship Hunter: Arcane Shot (40yd)
    [62]   = 30451,  -- Arcane Mage: Arcane Blast (40yd)
    [63]   = 133,    -- Fire Mage: Fireball (40yd)
    [64]   = 116,    -- Frost Mage: Frostbolt (40yd)
    [258]  = 589,    -- Shadow Priest: Shadow Word: Pain (40yd)
    [262]  = 188196, -- Elemental Shaman: Lightning Bolt (40yd)
    [265]  = 686,    -- Affliction Warlock: Shadow Bolt (40yd)
    [266]  = 686,    -- Demonology Warlock: Shadow Bolt (40yd)
    [267]  = 29722,  -- Destruction Warlock: Incinerate (40yd)
    [1480] = 473662, -- Devourer Demon Hunter: Consume (25yd)
}

local HEALER_RANGE_ABILITIES = {
    [105]  = 8936,   -- Restoration Druid: Regrowth (40yd)
    [1468] = 361469, -- Preservation Evoker: Living Flame (25yd)
    [270]  = 116670, -- Mistweaver Monk: Vivify (40yd)
    [65]   = 19750,  -- Holy Paladin: Flash of Light (40yd)
    [256]  = 17,     -- Discipline Priest: Power Word: Shield (40yd)
    [257]  = 2061,   -- Holy Priest: Flash Heal (40yd)
    [264]  = 8004,   -- Restoration Shaman: Healing Surge (40yd)
}

CC.frame = nil
CC.text = nil
CC.previewActive = false
CC.combatActive = false
CC.rangeAbility = nil
CC.specType = nil
CC.lastInRange = nil
CC.onUpdateActive = false

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function CC:UpdateDB()
    self.db = KE.db.profile.CombatCross
end

function CC:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

---------------------------------------------------------------------------------
-- Range Detection
---------------------------------------------------------------------------------
function CC:ResolveRangeAbility()
    local specIndex = GetSpecialization()
    if not specIndex then
        self.rangeAbility = nil
        self.specType = nil
        return
    end
    local specID = select(1, GetSpecializationInfo(specIndex))
    if not specID then
        self.rangeAbility = nil
        self.specType = nil
        return
    end
    if MELEE_RANGE_ABILITIES[specID] then
        self.rangeAbility = MELEE_RANGE_ABILITIES[specID]
        self.specType = "melee"
    elseif RANGED_RANGE_ABILITIES[specID] then
        self.rangeAbility = RANGED_RANGE_ABILITIES[specID]
        self.specType = "ranged"
    elseif HEALER_RANGE_ABILITIES[specID] then
        self.rangeAbility = HEALER_RANGE_ABILITIES[specID]
        self.specType = "ranged"
    else
        self.rangeAbility = nil
        self.specType = nil
    end
end

function CC:UpdateRangeColor()
    if not self.text then return end
    if not UnitExists("target") then
        if self.lastInRange == false then
            self.lastInRange = nil
            local r, g, b, a = self:GetColor()
            self.text:SetTextColor(r, g, b, a)
        end
        return
    end

    local inRange = C_Spell.IsSpellInRange(self.rangeAbility, "target")

    if inRange == nil then
        if self.lastInRange ~= nil then
            self.lastInRange = nil
            local r, g, b, a = self:GetColor()
            self.text:SetTextColor(r, g, b, a)
        end
        return
    end

    local nowInRange = (inRange == 1 or inRange == true)
    if nowInRange == self.lastInRange then return end
    self.lastInRange = nowInRange

    if nowInRange then
        local r, g, b, a = self:GetColor()
        self.text:SetTextColor(r, g, b, a)
    else
        local c = self.db.OutOfRangeColor or { 1, 0, 0, 1 }
        self.text:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    end
end

function CC:ShouldRunRangeUpdate()
    if not self.combatActive then return false end
    if not self.rangeAbility or not self.specType then return false end
    if self.specType == "melee" and not self.db.RangeColorMeleeEnabled then return false end
    if self.specType == "ranged" and not self.db.RangeColorRangedEnabled then return false end
    return true
end

function CC:UpdateOnUpdateState()
    if not self.frame then return end

    if self:ShouldRunRangeUpdate() then
        if not self.onUpdateActive then
            self.onUpdateActive = true
            rangeUpdateElapsed = 0
            self.frame:SetScript("OnUpdate", function(_, elapsed) self:OnUpdate(elapsed) end)
        end
    else
        if self.onUpdateActive then
            self.onUpdateActive = false
            self.frame:SetScript("OnUpdate", nil)
            -- Reset color to default when disabling
            if self.text then
                local r, g, b, a = self:GetColor()
                self.text:SetTextColor(r, g, b, a)
            end
            self.lastInRange = nil
        end
    end
end

function CC:OnUpdate(elapsed)
    rangeUpdateElapsed = rangeUpdateElapsed + elapsed
    if rangeUpdateElapsed < RANGE_UPDATE_THROTTLE then return end
    rangeUpdateElapsed = 0

    self:UpdateRangeColor()
end

function CC:GetColor()
    local colorMode = self.db.ColorMode or "custom"
    return KE:GetAccentColor(colorMode, self.db.Color)
end

---------------------------------------------------------------------------------
-- Frame Creation
---------------------------------------------------------------------------------
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

    self.text = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.text:SetPoint("CENTER")
    self.text:SetFont(fontPath, fontSize, "")
    self.text:SetText("+")

    if self.db.Outline then
        self.frame.softOutline = KE:CreateSoftOutline(self.text, {
            thickness = 1,
            color = { 0, 0, 0 },
            alpha = 0.9,
        })
    end

    self.text:ClearAllPoints()
    self.text:SetPoint("CENTER", self.frame, "CENTER", 0, 0)
end

---------------------------------------------------------------------------------
-- Apply Settings
---------------------------------------------------------------------------------
function CC:ApplySettings()
    if not self.frame or not self.text then return end

    -- Apply position & strata
    KE:ApplyFramePosition(self.frame, self.db.Position, self.db)

    -- Apply font
    local fontSize = (self.db.Thickness or 22) * FONT_SIZE_MULTIPLIER
    local fontPath = KE:GetFontPath(self.db.FontFace) or KE.FONT
    self.text:SetFont(fontPath, fontSize, "")

    if self.db.Outline then
        if not self.frame.softOutline then
            self.frame.softOutline = KE:CreateSoftOutline(self.text, {
                thickness = 1,
                color = { 0, 0, 0 },
                alpha = 0.9,
            })
        else
            self.frame.softOutline:SetShown(true)
        end
    else
        if self.frame.softOutline then
            self.frame.softOutline:SetShown(false)
        end
    end

    -- Apply color
    local r, g, b, a = self:GetColor()
    self.text:SetTextColor(r, g, b, a)

    -- Force range color re-evaluation on next update cycle
    self.lastInRange = nil

    -- Update range checking state
    self:UpdateOnUpdateState()
end

function CC:ApplyPosition()
    if not self.frame then return end
    KE:ApplyFramePosition(self.frame, self.db.Position, self.db)
end

---------------------------------------------------------------------------------
-- Show / Hide
---------------------------------------------------------------------------------
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

function CC:Hide(isPreview)
    if not self.frame then return end

    if isPreview then
        self.previewActive = false
    else
        self.combatActive = false
        -- Restore normal color when leaving combat
        if self.text then
            local r, g, b, a = self:GetColor()
            self.text:SetTextColor(r, g, b, a)
        end
        self.lastInRange = nil
    end

    if not self.previewActive and not self.combatActive then
        self.frame:Hide()
    end
end

---------------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------------
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

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------
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

---------------------------------------------------------------------------------
-- Event Handlers
---------------------------------------------------------------------------------
function CC:OnSpecChanged()
    self:ResolveRangeAbility()
    self.lastInRange = nil
    self:UpdateOnUpdateState()
end

function CC:OnEnterCombat()
    if not self.db.Enabled then return end
    self:Show(false)
    self:UpdateOnUpdateState()
end

function CC:OnExitCombat()
    if not self.db.Enabled then return end
    self:Hide(false)
    self:UpdateOnUpdateState()
end

function CC:Refresh()
    self:ApplySettings()
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function CC:OnEnable()
    if not self.db.Enabled then return end
    self:CreateFrame()
    self:RegWithEditMode()
    self:ApplySettings()
    self:ResolveRangeAbility()

    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnEnterCombat")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnExitCombat")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnSpecChanged")
end

function CC:OnThemeChanged()
    if not self.db or not self.db.Enabled then return end
    if (self.db.ColorMode or "custom") == "theme" and self.text then
        local r, g, b, a = self:GetColor()
        self.text:SetTextColor(r, g, b, a)
        self.lastInRange = nil -- force re-evaluation
    end
end

function CC:OnDisable()
    self:UnregisterAllEvents()
    if self.frame then
        self.frame:SetScript("OnUpdate", nil)
        self.frame:Hide()
    end
    self.rangeAbility = nil
    self.specType = nil
    self.lastInRange = nil
    self.onUpdateActive = false
end
