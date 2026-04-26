-- ╔══════════════════════════════════════════════════════════╗
-- ║  PotionReady.lua                                         ║
-- ║  Module: Combat Potion Ready                             ║
-- ║  Purpose: Shows "Potion Ready" text when a combat        ║
-- ║           potion is in bags and off cooldown. Respects   ║
-- ║           instance, combat, and healer visibility.       ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class PotionReady: AceModule, AceEvent-3.0
local PR = KitnEssentials:NewModule("PotionReady", "AceEvent-3.0")

local C_Item           = C_Item
local C_Container      = C_Container
local C_Timer          = C_Timer
local CreateFrame      = CreateFrame
local GetSpecialization     = GetSpecialization
local GetSpecializationRole = GetSpecializationRole
local IsInInstance     = IsInInstance
local UIParent         = UIParent

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
local POTION_IDS = {
    -- Regular potions
    241308, 241309,                 -- Light's Potential (Gold, Silver)
    241288, 241289,                 -- Potion of Recklessness (Gold, Silver)
    241292, 241293,                 -- Draught of Rampant Abandon (Gold, Silver)
    241300, 241301,                 -- Lightfused Mana Potion (Gold, Silver)
    241294, 241295,                 -- Potion of Devoured Dreams (Gold, Silver)
    241302, 241303,                 -- Void-Shrouded Tincture (Gold, Silver)
    -- Fleeting potions
    245898, 245897,                 -- Fleeting Light's Potential (Gold, Silver)
    245902, 245903,                 -- Fleeting Potion of Recklessness (Gold, Silver)
    245910, 245911,                 -- Fleeting Draught of Rampant Abandon (Gold, Silver)
    245916, 245917,                 -- Fleeting Lightfused Mana Potion (Gold, Silver)
    245904, 245905,                 -- Fleeting Potion of Devoured Dreams (Gold, Silver)
}

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------
PR.frame    = nil
PR.text     = nil
PR.isPreview          = false
PR.editModeRegistered = false
PR.inCombat           = false
PR.inInstance         = false

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function PR:UpdateDB()
    self.db = KE.db.profile.PotionReady
end

---------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------
local function HasPotion(id)
    local count = C_Item.GetItemCount(id, false, false, true)
    return count and count > 0
end

local function IsPotionReady(id)
    local start, duration, enable = C_Container.GetItemCooldown(id)
    if not start or not enable then return false end
    return enable == 1 and (start == 0 or duration == 0)
end

---------------------------------------------------------------------------------
-- Visibility Checks
---------------------------------------------------------------------------------
local function IsHealer()
    local specIndex = GetSpecialization()
    if not specIndex then return false end
    local role = GetSpecializationRole(specIndex)
    return role == "HEALER"
end

function PR:PassesVisibility()
    local db = self.db
    if db.InstanceOnly and not self.inInstance then return false end
    if db.CombatOnly  and not self.inCombat    then return false end
    if db.DisableOnHealer and IsHealer()        then return false end
    return true
end

---------------------------------------------------------------------------------
-- Core Logic
---------------------------------------------------------------------------------
function PR:CheckPotions()
    if not self.frame then return end
    if self.isPreview then return end
    if not self:PassesVisibility() then
        self.frame:Hide()
        return
    end

    for _, id in ipairs(POTION_IDS) do
        if HasPotion(id) and IsPotionReady(id) then
            self.frame:Show()
            return
        end
    end

    self.frame:Hide()
end

---------------------------------------------------------------------------------
-- Frame Creation
---------------------------------------------------------------------------------
function PR:CreateFrame()
    if self.frame then return end

    local f = CreateFrame("Frame", "KE_PotionReady", UIParent)
    f:SetSize(200, 30)
    f:Hide()

    local t = f:CreateFontString(nil, "OVERLAY")
    t:SetPoint("CENTER", f, "CENTER", 0, 0)

    self.frame = f
    self.text  = t
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
function PR:ApplySettings()
    if not self.frame or not self.text then return end
    local db = self.db

    KE:ApplyFontToText(self.text, db.FontFace, db.FontSize, db.FontOutline)

    local r, g, b, a = KE:GetAccentColor(db.ColorMode, db.Color)
    self.text:SetTextColor(r, g, b, a)
    self.text:SetText(db.Text or "Potion Ready")

    self.frame:SetFrameStrata(db.Strata or "HIGH")
    KE:ApplyFramePositionWithSnap(self.frame, db.Position, db)
end

---------------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------------
function PR:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key         = "PotionReady",
            displayName = "Combat Potion Ready",
            frame       = self.frame,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos)
                self.db.Position = pos
                KE:ApplyFramePositionWithSnap(self.frame, self.db.Position, self.db)
            end,
            getParentFrame = function()
                return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame)
            end,
            guiPath = "PotionReady",
        })
        self.editModeRegistered = true
    end
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------
function PR:ShowPreview()
    if not self.frame then self:CreateFrame() end
    self:RegWithEditMode()
    self.isPreview = true
    self:ApplySettings()
    self.text:SetText(self.db.Text or "Potion Ready")
    self.frame:Show()
end

function PR:HidePreview()
    self.isPreview = false
    if self.db and self.db.Enabled then
        self:CheckPotions()
    elseif self.frame then
        self.frame:Hide()
    end
end

---------------------------------------------------------------------------------
-- Event Handlers
---------------------------------------------------------------------------------
function PR:PLAYER_ENTERING_WORLD()
    local inInstance = IsInInstance()
    self.inInstance = inInstance == true
    C_Timer.After(1, function()
        if self.db and self.db.Enabled then self:CheckPotions() end
    end)
end

function PR:ZONE_CHANGED_NEW_AREA()
    local inInstance = IsInInstance()
    self.inInstance = inInstance == true
    self:CheckPotions()
end

function PR:BAG_UPDATE_DELAYED()
    self:CheckPotions()
end

function PR:SPELL_UPDATE_COOLDOWN()
    if self.isPreview then return end
    self:CheckPotions()
end

function PR:PLAYER_REGEN_DISABLED()
    self.inCombat = true
    self:CheckPotions()
end

function PR:PLAYER_REGEN_ENABLED()
    self.inCombat = false
    self:CheckPotions()
end

function PR:PLAYER_SPECIALIZATION_CHANGED()
    self:CheckPotions()
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function PR:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function PR:OnEnable()
    if not self.db or not self.db.Enabled then return end

    self:CreateFrame()
    self:RegWithEditMode()

    C_Timer.After(0.5, function()
        if not self.db or not self.db.Enabled then return end
        self:ApplySettings()
        self:CheckPotions()
    end)

    self:RegisterEvent("PLAYER_ENTERING_WORLD",       "PLAYER_ENTERING_WORLD")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA",        "ZONE_CHANGED_NEW_AREA")
    self:RegisterEvent("BAG_UPDATE_DELAYED",           "BAG_UPDATE_DELAYED")
    self:RegisterEvent("SPELL_UPDATE_COOLDOWN",        "SPELL_UPDATE_COOLDOWN")
    self:RegisterEvent("PLAYER_REGEN_DISABLED",        "PLAYER_REGEN_DISABLED")
    self:RegisterEvent("PLAYER_REGEN_ENABLED",         "PLAYER_REGEN_ENABLED")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED","PLAYER_SPECIALIZATION_CHANGED")
end

function PR:OnThemeChanged()
    if not self.db or not self.db.Enabled then return end
    if (self.db.ColorMode or "custom") == "theme" and self.text then
        local r, g, b, a = KE:GetAccentColor(self.db.ColorMode, self.db.Color)
        self.text:SetTextColor(r, g, b, a)
    end
end

function PR:OnDisable()
    self:UnregisterAllEvents()
    if self.frame then self.frame:Hide() end
    self.isPreview = false
    self.inCombat  = false
end
