---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class PlayerAbsorbs: AceModule, AceEvent-3.0
local PA = KitnEssentials:NewModule("PlayerAbsorbs", "AceEvent-3.0")

local CreateFrame = CreateFrame
local UIParent = UIParent
local C_Timer = C_Timer
local GetTime = GetTime
local UnitGetTotalAbsorbs = _G.UnitGetTotalAbsorbs
local UnitGetTotalHealAbsorbs = _G.UnitGetTotalHealAbsorbs
local C_Spell = _G.C_Spell

local SHIELD_SPELL_ID = 17        -- Power Word: Shield (icon)
local HEALABSORB_SPELL_ID = 6788  -- Weakened Soul (icon)
local REFRESH_THROTTLE = 0.2
local ICON_HIDE_DELAY = 10
local ROW_GAP = 2
local ICON_TEXT_GAP = 3
local PREVIEW_SHIELD = 1200000
local PREVIEW_HEALABSORB = 340000

local function GetSpellIcon(spellID)
    if C_Spell and type(C_Spell.GetSpellTexture) == "function" then
        return C_Spell.GetSpellTexture(spellID)
    end
    return nil
end

---------------------------------------------------------------------------------
-- DB
---------------------------------------------------------------------------------
function PA:UpdateDB()
    self.db = KE.db.profile.PlayerAbsorbs
end

function PA:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
    self.lastShieldEvent = nil
    self.lastHealAbsorbEvent = nil
end

---------------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------------
function PA:GetShieldAmount()
    return UnitGetTotalAbsorbs and UnitGetTotalAbsorbs("player") or 0
end

function PA:GetHealAbsorbAmount()
    return UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs("player") or 0
end

---------------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------------
function PA:CreateFrame()
    if self.frame then return end
    local db = self.db

    local f = CreateFrame("Frame", "KE_PlayerAbsorbsFrame", UIParent)
    f:SetSize(120, 48)
    f:EnableMouse(false)
    f:SetMouseClickEnabled(false)
    f:Hide()

    -- Shield row: number centered on the frame anchor, icon to its left.
    f.shieldText = f:CreateFontString(nil, "OVERLAY")
    f.shieldText:SetPoint("CENTER", f, "CENTER", 0, (db.FontSize or 18) * 0.5 + ROW_GAP)
    f.shieldText:SetJustifyH("CENTER")

    f.shieldIcon = f:CreateTexture(nil, "ARTWORK")
    KE:ApplyIconZoom(f.shieldIcon)
    f.shieldIcon:SetPoint("RIGHT", f.shieldText, "LEFT", -ICON_TEXT_GAP, 0)

    -- Heal-absorb row: directly below the shield row.
    f.healText = f:CreateFontString(nil, "OVERLAY")
    f.healText:SetPoint("TOP", f.shieldText, "BOTTOM", 0, -ROW_GAP)
    f.healText:SetJustifyH("CENTER")

    f.healIcon = f:CreateTexture(nil, "ARTWORK")
    KE:ApplyIconZoom(f.healIcon)
    f.healIcon:SetPoint("RIGHT", f.healText, "LEFT", -ICON_TEXT_GAP, 0)

    self.frame = f
    self.shieldText = f.shieldText
    self.shieldIcon = f.shieldIcon
    self.healText = f.healText
    self.healIcon = f.healIcon

    self:ApplySettings()
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
function PA:ApplySettings()
    if not self.frame then return end
    local db = self.db

    self.frame:SetScale(db.Scale or 1)

    KE:ApplyFontToText(self.shieldText, db.FontFace, db.FontSize, db.FontOutline)
    KE:ApplyFontToText(self.healText, db.FontFace, db.FontSize, db.FontOutline)

    local sr, sg, sb, sa = KE:ResolveColor(db.ShieldColor, { 0.37, 0.82, 1, 1 })
    self.shieldText:SetTextColor(sr, sg, sb, sa)
    local hr, hg, hb, ha = KE:ResolveColor(db.HealAbsorbColor, { 1, 0.48, 0.48, 1 })
    self.healText:SetTextColor(hr, hg, hb, ha)

    local sz = db.IconSize or 18
    self.shieldIcon:SetSize(sz, sz)
    self.shieldIcon:SetTexture(GetSpellIcon(SHIELD_SPELL_ID))
    self.healIcon:SetSize(sz, sz)
    self.healIcon:SetTexture(GetSpellIcon(HEALABSORB_SPELL_ID))

    -- Reposition the shield row relative to font size so the two rows stay tidy.
    self.shieldText:ClearAllPoints()
    self.shieldText:SetPoint("CENTER", self.frame, "CENTER", 0, (db.FontSize or 18) * 0.5 + ROW_GAP)

    self:ApplyPosition()
    self:RefreshDisplay()
end

function PA:ApplyPosition()
    if not self.frame then return end
    KE:ApplyFramePosition(self.frame, self.db.Position, self.db)
end

---------------------------------------------------------------------------------
-- Display (persistent numbers via formatter, transient icons via event timing)
---------------------------------------------------------------------------------
function PA:RefreshDisplay()
    self.refreshScheduled = nil
    if not self.frame then return end
    local db = self.db
    local Format = KE.PlayerAbsorbsFormat.Format

    if self.isPreview then
        self.shieldText:SetText(Format(PREVIEW_SHIELD, db.AbbreviateNumber, db.HideWhenZero ~= false))
        self.healText:SetText(Format(PREVIEW_HEALABSORB, db.AbbreviateNumber, db.HideWhenZero ~= false))
        local showIcon = db.ShowIcon ~= false
        self.shieldIcon:SetShown(showIcon and self.shieldIcon:GetTexture() ~= nil)
        self.healIcon:SetShown(showIcon and self.healIcon:GetTexture() ~= nil)
        self.frame:Show()
        return
    end

    self.shieldText:SetText(Format(self:GetShieldAmount(), db.AbbreviateNumber, db.HideWhenZero ~= false))
    self.healText:SetText(Format(self:GetHealAbsorbAmount(), db.AbbreviateNumber, db.HideWhenZero ~= false))

    local now = GetTime()
    local showIcon = db.ShowIcon ~= false
    local shieldActive = showIcon and self.lastShieldEvent
        and (now - self.lastShieldEvent) < ICON_HIDE_DELAY
    local healActive = showIcon and self.lastHealAbsorbEvent
        and (now - self.lastHealAbsorbEvent) < ICON_HIDE_DELAY
    self.shieldIcon:SetShown(shieldActive and self.shieldIcon:GetTexture() ~= nil)
    self.healIcon:SetShown(healActive and self.healIcon:GetTexture() ~= nil)

    self.frame:Show()
end

function PA:ScheduleRefresh()
    if self.refreshScheduled then return end
    self.refreshScheduled = C_Timer.NewTimer(REFRESH_THROTTLE, function() self:RefreshDisplay() end)
end

-- Records an absorb-change event time and schedules the icon to hide after
-- ICON_HIDE_DELAY (the only secret-safe way to hide a texture at zero).
function PA:MarkIconActive(which)
    local now = GetTime()
    if which == "shield" then
        self.lastShieldEvent = now
    else
        self.lastHealAbsorbEvent = now
    end
    if self.iconHideTimer then self.iconHideTimer:Cancel() end
    self.iconHideTimer = C_Timer.NewTimer(ICON_HIDE_DELAY, function()
        self.iconHideTimer = nil
        self:RefreshDisplay()
    end)
end

---------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------
function PA:OnShieldChanged(_, unit)
    if unit ~= "player" then return end
    self:MarkIconActive("shield")
    self:ScheduleRefresh()
end

function PA:OnHealAbsorbChanged(_, unit)
    if unit ~= "player" then return end
    self:MarkIconActive("heal")
    self:ScheduleRefresh()
end

function PA:OnGenericChanged(_, unit)
    if unit and unit ~= "player" then return end
    self:ScheduleRefresh()
end

function PA:OnEnteringWorld()
    self:ApplyPosition()
    self:ScheduleRefresh()
end

---------------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------------
function PA:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "PlayerAbsorbs", displayName = "Player Absorbs", frame = self.frame,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos)
                self.db.Position = pos
                KE:ApplyFramePosition(self.frame, self.db.Position, self.db)
            end,
            getParentFrame = function()
                return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame)
            end,
            guiPath = "PlayerAbsorbs",
        })
        self.editModeRegistered = true
    end
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------
function PA:ShowPreview()
    if self.isPreview then return end
    if not self.frame then self:CreateFrame() end
    self:RegWithEditMode()
    self.isPreview = true
    self:ApplySettings()
    self.frame:Show()
end

function PA:HidePreview()
    if not self.isPreview then return end
    self.isPreview = false
    if self.frame and not (self.db.Enabled and self:IsEnabled()) then
        self.frame:Hide()
    else
        self:RefreshDisplay()
    end
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function PA:OnEnable()
    if not self.db.Enabled then return end
    self:CreateFrame()
    self:RegWithEditMode()

    self:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED", "OnShieldChanged")
    self:RegisterEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "OnHealAbsorbChanged")
    self:RegisterEvent("UNIT_HEAL_PREDICTION", "OnGenericChanged")
    self:RegisterEvent("UNIT_MAXHEALTH", "OnGenericChanged")
    self:RegisterEvent("UNIT_MAX_HEALTH_MODIFIERS_CHANGED", "OnGenericChanged")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnteringWorld")

    C_Timer.After(0.5, function() self:ApplyPosition() end)
    self:ScheduleRefresh()
end

function PA:OnDisable()
    if self.refreshScheduled then self.refreshScheduled:Cancel(); self.refreshScheduled = nil end
    if self.iconHideTimer then self.iconHideTimer:Cancel(); self.iconHideTimer = nil end
    self.isPreview = false
    if self.frame then self.frame:Hide() end
    self:UnregisterAllEvents()
end
