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
-- Seconds a row stays shown after its last absorb-change event, then icon+number
-- fade together. Tunable trade-off: LONGER = a static (un-hit) shield stays shown
-- more reliably, but a fully-dropped shield shows its "0" longer before fading
-- (a secret 0 can't be blanked while abbreviating). Absorb events fire constantly
-- while actually taking damage, so this window only matters in no-incoming-damage lulls.
local DISPLAY_HOLD = 10
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

    -- Shield row (top) + heal-absorb row (below). Icons are pinned to a FIXED
    -- anchor on the frame (see PA:LayoutRows) so they never shift as the number
    -- width changes; each number is left-justified to the right of its icon and
    -- grows outward. Objects are created here; PA:LayoutRows sets their points.
    f.shieldText = f:CreateFontString(nil, "OVERLAY")
    f.shieldText:SetJustifyH("LEFT")

    f.shieldIconFrame = CreateFrame("Frame", nil, f)
    f.shieldIconFrame:SetSize(db.IconSize or 18, db.IconSize or 18)
    KE:AddIconBorders(f.shieldIconFrame)
    f.shieldIcon = f.shieldIconFrame:CreateTexture(nil, "ARTWORK")
    f.shieldIcon:SetAllPoints(f.shieldIconFrame)
    KE:ApplyIconZoom(f.shieldIcon)

    f.healText = f:CreateFontString(nil, "OVERLAY")
    f.healText:SetJustifyH("LEFT")

    f.healIconFrame = CreateFrame("Frame", nil, f)
    f.healIconFrame:SetSize(db.IconSize or 18, db.IconSize or 18)
    KE:AddIconBorders(f.healIconFrame)
    f.healIcon = f.healIconFrame:CreateTexture(nil, "ARTWORK")
    f.healIcon:SetAllPoints(f.healIconFrame)
    KE:ApplyIconZoom(f.healIcon)

    self.frame = f
    self.shieldText = f.shieldText
    self.shieldIcon = f.shieldIcon
    self.shieldIconFrame = f.shieldIconFrame
    self.healText = f.healText
    self.healIcon = f.healIcon
    self.healIconFrame = f.healIconFrame

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
    self.shieldIconFrame:SetSize(sz, sz)
    self.shieldIcon:SetTexture(GetSpellIcon(SHIELD_SPELL_ID))
    self.healIconFrame:SetSize(sz, sz)
    self.healIcon:SetTexture(GetSpellIcon(HEALABSORB_SPELL_ID))

    self:LayoutRows()
    self:ApplyPosition()
    self:RefreshDisplay()
end

-- Positions both rows. Icons are anchored to a FIXED point on the frame so they
-- never move as the number width changes; each number is left-justified to the
-- right of its icon. When icons are hidden the number takes the icon's slot so no
-- empty gap remains. Re-run on any font/icon-size change so the rows stay tidy.
function PA:LayoutRows()
    if not self.frame then return end
    local db = self.db
    local sz = db.IconSize or 18
    local rowH = math.max(sz, db.FontSize or 18)
    local half = (rowH + ROW_GAP) * 0.5

    self.shieldIconFrame:ClearAllPoints()
    self.shieldIconFrame:SetPoint("LEFT", self.frame, "LEFT", 0, half)
    self.healIconFrame:ClearAllPoints()
    self.healIconFrame:SetPoint("TOP", self.shieldIconFrame, "BOTTOM", 0, -ROW_GAP)

    self.shieldText:ClearAllPoints()
    self.healText:ClearAllPoints()
    if db.ShowIcon ~= false then
        self.shieldText:SetPoint("LEFT", self.shieldIconFrame, "RIGHT", ICON_TEXT_GAP, 0)
        self.healText:SetPoint("LEFT", self.healIconFrame, "RIGHT", ICON_TEXT_GAP, 0)
    else
        self.shieldText:SetPoint("LEFT", self.shieldIconFrame, "LEFT", 0, 0)
        self.healText:SetPoint("LEFT", self.healIconFrame, "LEFT", 0, 0)
    end
end

function PA:ApplyPosition()
    if not self.frame then return end
    KE:ApplyFramePosition(self.frame, self.db.Position, self.db)
end

---------------------------------------------------------------------------------
-- Display
--
-- Each row (number + icon) is gated on its OWN absorb-change activity: shown for
-- DISPLAY_HOLD seconds after that type's last event, then hidden. The secret rules
-- forbid testing amount == 0, so we can't hide the instant an absorb hits zero; a
-- dropped absorb shows its last value (or "0" when abbreviating) then fades after
-- DISPLAY_HOLD. Numbers and icons hide together so a stale "0" never persists and
-- the heal-absorb row isn't a permanent zero.
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
        self.shieldIconFrame:SetShown(showIcon and self.shieldIcon:GetTexture() ~= nil)
        self.healIconFrame:SetShown(showIcon and self.healIcon:GetTexture() ~= nil)
        self.frame:Show()
        return
    end

    local now = GetTime()
    local showIcon = db.ShowIcon ~= false
    local hideWhenZero = db.HideWhenZero ~= false
    local shieldActive = self.lastShieldEvent and (now - self.lastShieldEvent) < DISPLAY_HOLD
    local healActive = self.lastHealAbsorbEvent and (now - self.lastHealAbsorbEvent) < DISPLAY_HOLD

    if shieldActive then
        self.shieldText:SetText(Format(self:GetShieldAmount(), db.AbbreviateNumber, hideWhenZero))
        self.shieldText:Show()
        self.shieldIconFrame:SetShown(showIcon and self.shieldIcon:GetTexture() ~= nil)
    else
        self.shieldText:SetText("")
        self.shieldText:Hide()
        self.shieldIconFrame:Hide()
    end

    if healActive then
        self.healText:SetText(Format(self:GetHealAbsorbAmount(), db.AbbreviateNumber, hideWhenZero))
        self.healText:Show()
        self.healIconFrame:SetShown(showIcon and self.healIcon:GetTexture() ~= nil)
    else
        self.healText:SetText("")
        self.healText:Hide()
        self.healIconFrame:Hide()
    end

    if shieldActive or healActive then
        self.frame:Show()
    else
        self.frame:Hide()
    end
end

function PA:ScheduleRefresh()
    if self.refreshScheduled then return end
    self.refreshScheduled = C_Timer.NewTimer(REFRESH_THROTTLE, function() self:RefreshDisplay() end)
end

-- Records an absorb-change event time for one row and schedules a refresh at
-- DISPLAY_HOLD so the row hides if nothing newer arrives. Per-type timers so the
-- shield row hides on its own schedule regardless of heal-absorb activity.
function PA:MarkActive(which)
    local now = GetTime()
    local timerKey
    if which == "shield" then
        self.lastShieldEvent = now
        timerKey = "shieldHideTimer"
    else
        self.lastHealAbsorbEvent = now
        timerKey = "healHideTimer"
    end
    if self[timerKey] then self[timerKey]:Cancel() end
    self[timerKey] = C_Timer.NewTimer(DISPLAY_HOLD, function()
        self[timerKey] = nil
        self:RefreshDisplay()
    end)
end

---------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------
function PA:OnShieldChanged(_, unit)
    if unit ~= "player" then return end
    self:MarkActive("shield")
    self:ScheduleRefresh()
end

function PA:OnHealAbsorbChanged(_, unit)
    if unit ~= "player" then return end
    self:MarkActive("heal")
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
    if self.shieldHideTimer then self.shieldHideTimer:Cancel(); self.shieldHideTimer = nil end
    if self.healHideTimer then self.healHideTimer:Cancel(); self.healHideTimer = nil end
    self.isPreview = false
    if self.frame then self.frame:Hide() end
    self:UnregisterAllEvents()
end
