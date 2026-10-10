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
local IsInInstance     = IsInInstance
local UIParent         = UIParent

local ATTACH_KEY = "potionReady"
local DETACHED_HEIGHT = 30

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
PR._listening         = false

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
-- Pure, so the rule is spec-covered; the caller supplies the three reads.
function PR.PassesGates(db, inInstance, inCombat, isHealer)
    if db.InstanceOnly and not inInstance then return false end
    if db.CombatOnly and not inCombat then return false end
    if db.DisableOnHealer and isHealer then return false end
    return true
end

function PR:PassesVisibility()
    local db = self.db
    return PR.PassesGates(db, self.inInstance, self.inCombat, db.DisableOnHealer and KE:IsPlayerHealerSpec())
end

-- The cooldown and bag events only matter while the text may show. Only
-- CheckPotions turns them off, because it hides the text in the same call;
-- anywhere else, onlyOn keeps them until then, so the text hides on the same
-- event it always did.
function PR:SyncListening(onlyOn)
    local want = (self:IsEnabled() and self.db and self.db.Enabled and self:PassesVisibility())
        and true or false
    if want == self._listening then return end
    if onlyOn and not want then return end
    self._listening = want
    if want then
        self:RegisterEvent("BAG_UPDATE_DELAYED", "BAG_UPDATE_DELAYED")
        self:RegisterEvent("SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_COOLDOWN")
    else
        self:UnregisterEvent("BAG_UPDATE_DELAYED")
        self:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
    end
end

---------------------------------------------------------------------------------
-- Core Logic
---------------------------------------------------------------------------------
-- Every show and hide of the text goes through here, so an attached text's
-- place in the Combat Texts stack follows it.
function PR:SetTextShown(shown)
    if not self.frame then return end
    if shown then self.frame:Show() else self.frame:Hide() end
    local cm = KitnEssentials:GetModule("CombatTexts", true)
    if cm then cm:AttachedFrameChanged(ATTACH_KEY) end
end

function PR:CheckPotions()
    if not self.frame then return end
    self:SyncListening()
    if self.isPreview then return end
    if not self:PassesVisibility() then
        self:SetTextShown(false)
        return
    end

    for _, id in ipairs(POTION_IDS) do
        if HasPotion(id) and IsPotionReady(id) then
            self:SetTextShown(true)
            return
        end
    end

    self:SetTextShown(false)
end

---------------------------------------------------------------------------------
-- Frame Creation
---------------------------------------------------------------------------------
function PR:CreateFrame()
    if self.frame then return end

    local f = CreateFrame("Frame", "KE_PotionReady", UIParent)
    f:SetSize(200, DETACHED_HEIGHT)
    f:Hide()

    local t = f:CreateFontString(nil, "OVERLAY")
    t:SetPoint("CENTER", f, "CENTER", 0, 0)

    self.frame = f
    self.text  = t
    -- Attached, the login anchor pass must not put the text back on its own
    -- Player Frame position.
    KE:RegisterAnchorRepair(f, function()
        return not self:IsAttached() and self.db.anchorFrameType == "PLAYERFRAME"
    end, function() self:ApplySettings() end)
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
function PR:IsAttached()
    local cm = KitnEssentials:GetModule("CombatTexts", true)
    return cm ~= nil and cm:AcceptsAttach(self.db.AttachToCombatTexts == true)
end

-- Attached, the text is a Combat Texts row: that module's face and outline,
-- the resolved size, and the line height Combat Texts gives its own rows.
-- Only an active module takes a slot: the page applies settings to a kept
-- frame while the module is off.
function PR:ApplySettings()
    if not self.frame or not self.text then return end
    local db = self.db
    local cm = KitnEssentials:GetModule("CombatTexts", true)
    local attached = (self:IsEnabled() or self.isPreview) and cm ~= nil and self:IsAttached()

    local face, outline, size = db.FontFace, db.FontOutline, db.FontSize
    if attached and cm then
        face, outline = cm.db.FontFace, cm.db.FontOutline
        size = cm.ResolveAttachedSize(true, db.AttachOwnFontSize, db.FontSize, cm.db.FontSize)
    end
    KE:ApplyFontToText(self.text, face, size, outline)

    local r, g, b, a = KE:GetAccentColor(db.ColorMode, db.Color)
    self.text:SetTextColor(r, g, b, a)
    self.text:SetText(db.Text or "Potion Ready")

    self.frame:SetFrameStrata(db.Strata or "HIGH")
    if attached and cm then
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

    -- A profile switch reaches this module here only; a gate it opens needs
    -- the events on for the next cooldown or bag change.
    self:SyncListening(true)
end

---------------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------------
function PR:RegWithEditMode()
    if not KE.EditMode then return end
    -- Attached, the Combat Texts mover moves the text; a second mover for it
    -- would fight that one.
    if self:IsAttached() then
        if self.editModeRegistered then
            KE.EditMode:UnregisterElement("PotionReady")
            self.editModeRegistered = false
        end
        return
    end
    if not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key         = "PotionReady",
            module      = self,
            displayName = "Combat Potion Ready",
            frame       = self.frame,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos)
                self.db.Position = pos
                KE:ApplyFramePosition(self.frame, self.db.Position, self.db)
            end,
            getParentFrame = function()
                return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame)
            end,
            -- No sidebar row of its own -- this lives on the Status Texts
            -- page, so guiTab picks its tab there.
            guiPath = "StatusTexts",
            guiTab = "PotionReady",
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
    self:SetTextShown(true)
end

function PR:HidePreview()
    self.isPreview = false
    local cm = KitnEssentials:GetModule("CombatTexts", true)
    if cm then cm:SyncAttachSubscription(self, self:IsEnabled()) end
    if self.db and self.db.Enabled and self.frame then
        self:CheckPotions()
    elseif self.frame then
        self:SetTextShown(false)
    end
end

---------------------------------------------------------------------------------
-- Event Handlers
---------------------------------------------------------------------------------
function PR:PLAYER_ENTERING_WORLD()
    local inInstance = IsInInstance()
    self.inInstance = inInstance == true
    -- At once rather than with the delayed check: a cooldown event inside that
    -- second repaints the text.
    self:SyncListening(true)
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

-- The event fires for every group member; only the player's spec decides.
function PR:PLAYER_SPECIALIZATION_CHANGED(_, unit)
    if unit ~= "player" then return end
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
    self:RegisterEvent("PLAYER_REGEN_DISABLED",        "PLAYER_REGEN_DISABLED")
    self:RegisterEvent("PLAYER_REGEN_ENABLED",         "PLAYER_REGEN_ENABLED")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED","PLAYER_SPECIALIZATION_CHANGED")
    -- The events that keep these fire only on a change, so a state already in
    -- place when the module comes on (a reload mid-fight, enabling inside an
    -- instance) is read here.
    self.inCombat = UnitAffectingCombat("player") and true or false
    self.inInstance = IsInInstance() == true
    self:SyncListening()
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
    self:SetTextShown(false)
    local cm = KitnEssentials:GetModule("CombatTexts", true)
    if cm then
        cm:SetAttachedFrame(ATTACH_KEY, nil)
        cm:SyncAttachSubscription(self, false)
    end
    self.isPreview = false
    self.inCombat  = false
    self._listening = false
end
