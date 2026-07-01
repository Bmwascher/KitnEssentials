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
-- Fallback fade-hold (seconds) used when db.FadeTime is unset. The live value is
-- db.FadeTime (GUI slider). LONGER = a static (un-hit) shield's icon/number stays
-- shown more reliably, but a fully-dropped shield shows its "0" longer before fading
-- (a secret 0 can't be blanked while abbreviating). Absorb events fire constantly
-- while actually taking damage, so this window only matters in no-incoming-damage lulls.
local DISPLAY_HOLD = 10
local ROW_GAP = 4        -- fallback gap between rows; live value is db.RowSpacing
local ICON_TEXT_GAP = 4  -- fallback icon<->number gap; live value is db.IconSpacing
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

    -- Shield row + heal-absorb row. Icons anchor to a fixed point per row (see
    -- PA:PositionRows) so they never shift as the number width changes; the number
    -- grows away from its icon. Objects are created here; PA:PositionRows lays them
    -- out each refresh (auto-centering a lone row) and PA:AnchorText sets intra-row.
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

    self:ApplyPosition()
    self:RefreshDisplay()
end

-- Anchors a row's number to its icon. growLeft mirrors the row so the number
-- extends LEFT of the icon (used by LEFT growth). With the icon hidden the number
-- takes the icon's slot so no empty gap remains.
function PA:AnchorText(textObj, iconFrame, showIcon, growLeft)
    local gap = self.db.IconSpacing or ICON_TEXT_GAP
    textObj:ClearAllPoints()
    if growLeft then
        textObj:SetJustifyH("RIGHT")
        textObj:SetPoint("RIGHT", iconFrame, showIcon and "LEFT" or "RIGHT",
            showIcon and -gap or 0, 0)
    else
        textObj:SetJustifyH("LEFT")
        textObj:SetPoint("LEFT", iconFrame, showIcon and "RIGHT" or "LEFT",
            showIcon and gap or 0, 0)
    end
end

-- Positions the two rows. The shield row is the primary and holds the anchor
-- center; the heal-absorb row grows away from it in db.GrowthDirection (DOWN/UP =
-- stacked, RIGHT/LEFT = side-by-side). When only the heal row is shown it takes the
-- center instead -- reachable only in abbreviated mode, where shown-state is exact;
-- in full-numbers mode both rows count as shown, so this keeps fixed slots. Icons
-- stay put as their OWN number widens; a row only moves when the OTHER row toggles.
function PA:PositionRows(shieldShown, healShown)
    if not self.frame then return end
    local db = self.db
    local f = self.frame
    local dir = db.GrowthDirection or "DOWN"
    local showIcon = db.ShowIcon ~= false

    if dir == "SPLIT" then
        self:PositionSplit(shieldShown, healShown, showIcon)
        return
    end

    local sz = db.IconSize or 18
    local rowGap = db.RowSpacing or ROW_GAP
    local stepV = math.max(sz, db.FontSize or 18) + rowGap
    -- Icon side (left/right of the number) is user-configurable only in the stacked
    -- Down/Up modes; the side-by-side and lone-in-horizontal cases keep the
    -- layout-chosen side so the numbers grow clear of each other.
    local iconRight = (dir == "DOWN" or dir == "UP") and db.IconSide == "RIGHT"
    local healCenter = healShown and not shieldShown

    -- Shield row: at the anchor center; number sits on the side set by Icon Side.
    self.shieldIconFrame:ClearAllPoints()
    self.shieldIconFrame:SetPoint("LEFT", f, "CENTER", 0, 0)
    self:AnchorText(self.shieldText, self.shieldIconFrame, showIcon, iconRight)

    -- Heal-absorb row: centered when lone, else grown off the shield row.
    self.healIconFrame:ClearAllPoints()
    if healCenter then
        self.healIconFrame:SetPoint("LEFT", f, "CENTER", 0, 0)
        self:AnchorText(self.healText, self.healIconFrame, showIcon, iconRight)
    elseif dir == "UP" then
        self.healIconFrame:SetPoint("LEFT", f, "CENTER", 0, stepV)
        self:AnchorText(self.healText, self.healIconFrame, showIcon, iconRight)
    elseif dir == "RIGHT" then
        self.healIconFrame:SetPoint("LEFT", self.shieldText, "RIGHT", rowGap, 0)
        self:AnchorText(self.healText, self.healIconFrame, showIcon, false)
    elseif dir == "LEFT" then
        self.healIconFrame:SetPoint("RIGHT", self.shieldIconFrame, "LEFT", -rowGap, 0)
        self:AnchorText(self.healText, self.healIconFrame, showIcon, true)
    else -- DOWN (default)
        self.healIconFrame:SetPoint("LEFT", f, "CENTER", 0, -stepV)
        self:AnchorText(self.healText, self.healIconFrame, showIcon, iconRight)
    end
end

-- SPLIT (flank) layout: the two readouts sit on opposite sides of the anchor with a
-- db.Separation gap between their inner (icon) edges, numbers growing OUTWARD so they
-- never collide. A lone absorb centers on the anchor (abbreviated mode; in
-- full-numbers mode both count as shown, so they stay flanked).
function PA:PositionSplit(shieldShown, healShown, showIcon)
    local f = self.frame
    local half = (self.db.Separation or 40) * 0.5

    self.shieldIconFrame:ClearAllPoints()
    self.healIconFrame:ClearAllPoints()

    if shieldShown and healShown then
        -- Shield flanks left (icon inner-right, number grows left); heal flanks right.
        self.shieldIconFrame:SetPoint("RIGHT", f, "CENTER", -half, 0)
        self:AnchorText(self.shieldText, self.shieldIconFrame, showIcon, true)
        self.healIconFrame:SetPoint("LEFT", f, "CENTER", half, 0)
        self:AnchorText(self.healText, self.healIconFrame, showIcon, false)
    else
        -- Lone absorb: whichever is shown centers on the anchor, number grows right.
        self.shieldIconFrame:SetPoint("LEFT", f, "CENTER", 0, 0)
        self:AnchorText(self.shieldText, self.shieldIconFrame, showIcon, false)
        self.healIconFrame:SetPoint("LEFT", f, "CENTER", 0, 0)
        self:AnchorText(self.healText, self.healIconFrame, showIcon, false)
    end
end

function PA:ApplyPosition()
    if not self.frame then return end
    KE:ApplyFramePosition(self.frame, self.db.Position, self.db)
end

---------------------------------------------------------------------------------
-- Display
--
-- Two regimes, chosen by db.AbbreviateNumber, because the secret rules forbid
-- testing amount == 0 (so we can never hide the instant an absorb hits zero):
--
--  * Abbreviate ON  — an abbreviated secret 0 renders as "0" and can't self-blank,
--    so BOTH number and icon are transient: shown within the fade window (GetHold),
--    then hidden together. A dropped shield shows "0" until the window lapses.
--  * Abbreviate OFF — TruncateWhenZero blanks a secret 0 to "" with no branch, so
--    the NUMBER is always shown (empty at zero, no timer) and persists for as long
--    as a shield is up. Only the ICON is transient (a texture can't self-blank),
--    fading after the window.
--
-- The fade window is db.FadeTime (fallback DISPLAY_HOLD), tracked per row so the
-- shield and heal-absorb rows time out independently.
---------------------------------------------------------------------------------
function PA:GetHold()
    local t = tonumber(self.db.FadeTime) or DISPLAY_HOLD
    if t < 1 then t = 1 end
    return t
end

-- Renders one row and returns whether the frame must stay shown for it. See the
-- Display header for the two regimes.
function PA:RenderRow(textObj, iconFrame, iconTex, amount, lastEvent, now, hold, abbreviate, hideWhenZero, showIcon)
    local Format = KE.PlayerAbsorbsFormat.Format
    local active = lastEvent ~= nil and (now - lastEvent) < hold
    local iconOK = showIcon and iconTex:GetTexture() ~= nil
    if abbreviate then
        if active then
            textObj:SetText(Format(amount, true, hideWhenZero))
            textObj:Show()
            iconFrame:SetShown(iconOK)
        else
            textObj:SetText("")
            textObj:Hide()
            iconFrame:Hide()
        end
        return active
    end
    -- Persist regime: number self-blanks via TruncateWhenZero; icon stays transient.
    textObj:SetText(Format(amount, false, hideWhenZero))
    textObj:Show()
    iconFrame:SetShown(active and iconOK)
    return true
end

function PA:RefreshDisplay()
    self.refreshScheduled = nil
    if not self.frame then return end
    local db = self.db
    local Format = KE.PlayerAbsorbsFormat.Format

    if self.isPreview then
        local showIcon = db.ShowIcon ~= false
        self.shieldText:SetText(Format(PREVIEW_SHIELD, db.AbbreviateNumber, db.HideWhenZero ~= false))
        self.shieldText:Show()
        self.healText:SetText(Format(PREVIEW_HEALABSORB, db.AbbreviateNumber, db.HideWhenZero ~= false))
        self.healText:Show()
        self.shieldIconFrame:SetShown(showIcon and self.shieldIcon:GetTexture() ~= nil)
        self.healIconFrame:SetShown(showIcon and self.healIcon:GetTexture() ~= nil)
        self:PositionRows(true, true)
        self.frame:Show()
        return
    end

    local now = GetTime()
    local hold = self:GetHold()
    local abbreviate = db.AbbreviateNumber == true
    local hideWhenZero = db.HideWhenZero ~= false
    local showIcon = db.ShowIcon ~= false

    local shieldShown = self:RenderRow(self.shieldText, self.shieldIconFrame, self.shieldIcon,
        self:GetShieldAmount(), self.lastShieldEvent, now, hold, abbreviate, hideWhenZero, showIcon)
    local healShown = self:RenderRow(self.healText, self.healIconFrame, self.healIcon,
        self:GetHealAbsorbAmount(), self.lastHealAbsorbEvent, now, hold, abbreviate, hideWhenZero, showIcon)

    self:PositionRows(shieldShown, healShown)

    if shieldShown or healShown then
        self.frame:Show()
    else
        self.frame:Hide()
    end
end

function PA:ScheduleRefresh()
    if self.refreshScheduled then return end
    self.refreshScheduled = C_Timer.NewTimer(REFRESH_THROTTLE, function() self:RefreshDisplay() end)
end

-- Records an absorb-change event time for one row and schedules a refresh after the
-- fade window (GetHold) so the row re-evaluates if nothing newer arrives. Per-type
-- timers so the shield row times out on its own schedule regardless of heal activity.
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
    self[timerKey] = C_Timer.NewTimer(self:GetHold(), function()
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
