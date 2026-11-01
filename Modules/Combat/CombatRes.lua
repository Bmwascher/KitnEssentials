-- ╔══════════════════════════════════════════════════════════╗
-- ║  CombatRes.lua                                           ║
-- ║  Module: Combat Res                                      ║
-- ║  Purpose: Tracks battle resurrection charges and         ║
-- ║           cooldown with configurable text display.       ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class CombatRes: AceModule, AceEvent-3.0
local CR = KitnEssentials:NewModule("CombatRes", "AceEvent-3.0")

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
local CreateFrame = CreateFrame
local UIParent = UIParent
local C_Spell = C_Spell
local tostring = tostring
local GetTime = GetTime
local string_format = string.format
local math_floor = math.floor


local SPELL_ID = 20484 -- Rebirth

-- The frame is sized against these rather than the live text, so its width
-- never changes as the digits tick. Rebirth's recharge is minutes, so the
-- hours branch in Update() is unreachable and MM:SS bounds the timer; the
-- battle res pool is single-digit. Widest glyphs, not the values shown.
local TIMER_REF = "88:88"
local CHARGE_REF = "8"
-- MM:SS display only changes ~1Hz; 0.5s polling is ample (0.1 = 10Hz was
-- 10x oversampled for a seconds clock).
local UPDATE_INTERVAL = 0.5

-- Forever has no group res pool: a class with a res of its own sees that.
-- Every Soulstone shares one cooldown, so one stone's read answers for all.
local OWN_RES = {
    DRUID = { spell = 20484 },                                   -- Rebirth
    SHAMAN = { spell = 20608 },                                  -- Reincarnation
    WARLOCK = { items = { 5232, 16892, 16893, 16895, 16896 } },  -- Soulstones
}
local READY_TEXT = "Ready"
local OWN_RES_REFS = { READY_TEXT, TIMER_REF }
-- Set only where the camelot list loads CombatDataForever.lua.
local Ranks = KE.CombatDataForever
-- The cooldown reader is No Movement Alert's; its file loads first.
local NMA = KitnEssentials:GetModule("NoMovementAlert", true)

local function OwnSpellKnown(spellId)
    if not (C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook) then return false end
    local ok, known = pcall(C_SpellBook.IsSpellKnownOrInSpellBook, spellId,
        Enum.SpellBookSpellBank.Player, true)
    return ok and known == true
end

local function OwnSpellCooldown(spellId)
    if not NMA then return nil end
    return NMA:ReadCooldown(spellId)
end

local function HoldsAny(items)
    if not (C_Item and C_Item.GetItemCount) then return false end
    for _, id in ipairs(items) do
        local count = C_Item.GetItemCount(id, false, false, true)
        if count and count > 0 then return true end
    end
    return false
end

-- Seconds left, nil when no cooldown runs, false when the read is not
-- readable.
local function ItemCooldown(items)
    if not (C_Container and C_Container.GetItemCooldown) then return false end
    local start, duration = C_Container.GetItemCooldown(items[1])
    if not (KE:IsSafeValue(start) and KE:IsSafeValue(duration)) then return false end
    if start <= 0 or duration <= 0 then return nil end
    local remaining = start + duration - GetTime()
    if remaining > 0 then return remaining end
    return nil
end

-- Reused on every update; `spell` is set before each read.
local OWN_READS = {
    spellCooldown = OwnSpellCooldown,
    holdsAny = HoldsAny,
    itemCooldown = ItemCooldown,
}

local function FormatRemaining(seconds)
    if seconds >= 3600 then
        return string_format("%d:%02d", math_floor(seconds / 3600), math_floor((seconds % 3600) / 60))
    end
    return string_format("%02d:%02d", math_floor(seconds / 60), math_floor(seconds % 60))
end

local function PrefixShown(frame)
    local text = frame.CRText:GetText()
    return text ~= nil and text ~= ""
end

CR.frame = nil
CR.lastUpdate = 0
CR.lastTimerText = ""
CR.lastChargeText = ""
CR.lastChargeColor = nil
CR.isPreview = false
CR._onUpdateActive = false
CR.inCombat = false
CR.inEncounter = false
CR._chargeListening = false
-- Forever: the class's OWN_RES entry, and the rank of its spell the player knows.
CR.ownEntry = nil
CR.ownSpell = nil

local DEFAULT_CHARGE_AVAILABLE = { 0.3, 1, 0.3, 1 }
local DEFAULT_CHARGE_UNAVAILABLE = { 1, 0.3, 0.3, 1 }

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function CR:UpdateDB()
    self.db = KE.db.profile.CombatRes
end

function CR:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

---------------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------------
function CR:UpdateAnchors()
    if not self.frame or not self.frame.content then return end

    local db = self.db
    local textSpacing = db.TextSpacing or 4
    local padding = 4
    local growRight = (db.GrowthDirection or "RIGHT") == "RIGHT"

    self.frame.content:ClearAllPoints()
    self.frame.separator:ClearAllPoints()
    self.frame.charge:ClearAllPoints()
    self.frame.timerText:ClearAllPoints()
    if self.frame.CRText then self.frame.CRText:ClearAllPoints() end
    if self.frame.bracketOpen then self.frame.bracketOpen:ClearAllPoints() end
    if self.frame.bracketClose then self.frame.bracketClose:ClearAllPoints() end

    if KE.IS_FOREVER then
        self:AnchorOwnRes(growRight, textSpacing, padding)
        return
    end

    if growRight then
        -- Left-to-right: [CR: 2 | 02:00]
        self.frame.content:SetPoint("LEFT", self.frame, "LEFT", padding, 0)
        self.frame.bracketOpen:SetPoint("LEFT", self.frame.content, "LEFT", 0, 0)

        if self.frame.CRText then
            self.frame.CRText:SetPoint("LEFT", self.frame.bracketOpen, "RIGHT", -2, 0)
            self.frame.charge:SetPoint("LEFT", self.frame.CRText, "RIGHT", textSpacing, 0)
        else
            self.frame.charge:SetPoint("LEFT", self.frame.bracketOpen, "RIGHT", 0, 0)
        end

        self.frame.separator:SetPoint("LEFT", self.frame.charge, "RIGHT", textSpacing, 0)
        self.frame.timerText:SetPoint("LEFT", self.frame.separator, "RIGHT", textSpacing, 0)
        self.frame.bracketClose:SetPoint("LEFT", self.frame.timerText, "RIGHT", 0, 0)
        self.frame.timerText:SetJustifyH("LEFT")
    else
        -- Right-to-left: [00:02 | 2 :RC]
        self.frame.content:SetPoint("RIGHT", self.frame, "RIGHT", -padding, 0)
        self.frame.bracketClose:SetPoint("RIGHT", self.frame.content, "RIGHT", 0, 0)
        self.frame.timerText:SetPoint("RIGHT", self.frame.bracketClose, "LEFT", 0, 0)
        self.frame.separator:SetPoint("RIGHT", self.frame.timerText, "LEFT", -textSpacing, 0)
        self.frame.charge:SetPoint("RIGHT", self.frame.separator, "LEFT", -textSpacing, 0)

        if self.frame.CRText then
            self.frame.CRText:SetPoint("RIGHT", self.frame.charge, "LEFT", -textSpacing, 0)
            self.frame.bracketOpen:SetPoint("RIGHT", self.frame.CRText, "LEFT", 2, 0)
        else
            self.frame.bracketOpen:SetPoint("RIGHT", self.frame.charge, "LEFT", 0, 0)
        end

        self.frame.timerText:SetJustifyH("RIGHT")
    end
end

---------------------------------------------------------------------------------
-- Frame Creation
---------------------------------------------------------------------------------
function CR:CreateFrame()
    if self.frame then return end

    local db = self.db
    local fontPath = KE:GetFontPath(db.FontFace) or KE.FONT
    local fontSize = db.FontSize or 16

    local frame = CreateFrame("Frame", "KE_CombatResFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate")
    frame:SetSize(100, 26)
    frame:SetFrameStrata(db.Strata or "HIGH")
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        tileSize = 0,
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    frame:Hide()

    -- Content container
    frame.content = CreateFrame("Frame", nil, frame)
    frame.content:SetSize(1, 24)

    -- Seeded so the first sizing pass never measures an empty string, which
    -- reads as 0 and collapses the width to the floor. The frame is hidden
    -- until Update() overwrites this.
    frame.timerText = frame.content:CreateFontString(nil, "OVERLAY")
    frame.timerText:SetFont(fontPath, fontSize, "")
    frame.timerText:SetText(TIMER_REF)
    frame.timerText:SetTextColor(1, 1, 1, 1)

    -- Separator text
    frame.separator = frame.content:CreateFontString(nil, "OVERLAY")
    frame.separator:SetFont(fontPath, fontSize, "")
    frame.separator:SetText("|")
    frame.separator:SetTextColor(1, 1, 1, 1)

    -- Charge text, seeded for the same reason as timerText.
    frame.charge = frame.content:CreateFontString(nil, "OVERLAY")
    frame.charge:SetFont(fontPath, fontSize, "")
    frame.charge:SetText(CHARGE_REF)
    frame.charge:SetTextColor(1, 1, 1, 1)

    -- CR label text
    frame.CRText = frame.content:CreateFontString(nil, "OVERLAY")
    frame.CRText:SetFont(fontPath, fontSize, "")
    frame.CRText:SetText("CR:")
    frame.CRText:SetTextColor(1, 1, 1, 1)

    -- Bracket characters (default square)
    frame.bracketOpen = frame.content:CreateFontString(nil, "OVERLAY")
    frame.bracketOpen:SetFont(fontPath, fontSize, "")
    frame.bracketOpen:SetText("[")
    frame.bracketOpen:SetTextColor(1, 1, 1, 1)

    frame.bracketClose = frame.content:CreateFontString(nil, "OVERLAY")
    frame.bracketClose:SetFont(fontPath, fontSize, "")
    frame.bracketClose:SetText("]")
    frame.bracketClose:SetTextColor(1, 1, 1, 1)

    self.frame = frame
end

---------------------------------------------------------------------------------
-- Text Settings
---------------------------------------------------------------------------------
function CR:ApplyTextSettings()
    if not self.frame then return end

    local db = self.db
    local fontName = db.FontFace
    local fontSize = db.FontSize or 16
    local fontOutline = db.FontOutline or "OUTLINE"

    -- Apply font to all text elements (no shadow)
    KE:ApplyFontToText(self.frame.separator, fontName, fontSize, fontOutline)
    KE:ApplyFontToText(self.frame.charge, fontName, fontSize, fontOutline)
    KE:ApplyFontToText(self.frame.timerText, fontName, fontSize, fontOutline)
    KE:ApplyFontToText(self.frame.CRText, fontName, fontSize, fontOutline)
    KE:ApplyFontToText(self.frame.bracketOpen, fontName, fontSize, fontOutline)
    KE:ApplyFontToText(self.frame.bracketClose, fontName, fontSize, fontOutline)

    -- Per-element colors from DB (sparse-table-safe via ResolveColor)
    local sr, sg, sb, sa = KE:ResolveColor(db.SeparatorColor, { 1, 1, 1, 1 })
    local tr, tg, tb, ta = KE:ResolveColor(db.TimerColor, { 1, 1, 1, 1 })

    -- Set separator text and color. Forever draws no separator or timer.
    self.frame.separator:SetText(KE.IS_FOREVER and "" or (db.Separator or "|"))
    self.frame.separator:SetTextColor(sr, sg, sb, sa)

    -- Set charge prefix text and color (uses separator color)
    self.frame.CRText:SetText(db.SeparatorCharges or "CR:")
    self.frame.CRText:SetTextColor(sr, sg, sb, sa)

    -- Set bracket text from style
    local bracketStyle = db.BracketStyle or "square"
    if bracketStyle == "square" then
        self.frame.bracketOpen:SetText("[")
        self.frame.bracketClose:SetText("]")
    elseif bracketStyle == "round" then
        self.frame.bracketOpen:SetText("(")
        self.frame.bracketClose:SetText(")")
    else
        self.frame.bracketOpen:SetText("")
        self.frame.bracketClose:SetText("")
    end
    self.frame.bracketOpen:SetTextColor(sr, sg, sb, sa)
    self.frame.bracketClose:SetTextColor(sr, sg, sb, sa)

    -- Timer text color
    self.frame.timerText:SetTextColor(tr, tg, tb, ta)
    if KE.IS_FOREVER then self.frame.timerText:SetText("") end

    self:UpdateAnchors()
    self:ApplyBackdropSettings()
end

---------------------------------------------------------------------------------
-- Sizing
---------------------------------------------------------------------------------
-- Sizes from fixed references, not the live text. On a right-side anchor a
-- width change walks the frame's left edge, and the content is anchored to
-- that edge, so the text walks with it.
function CR:ResizeToContent()
    if not self.frame then return end
    if KE.IS_FOREVER then
        self:ResizeOwnRes()
        return
    end

    local timerLive = self.frame.timerText:GetText()
    local chargeLive = self.frame.charge:GetText()
    self.frame.timerText:SetText(TIMER_REF)
    self.frame.charge:SetText(CHARGE_REF)
    -- The references are on screen until the restore below. Dropping the dirty
    -- caches now means a throw in between cannot strand them until a reload;
    -- the next Update repaints, whenever one arrives.
    self.lastTimerText = ""
    self.lastChargeText = ""

    local totalWidth = 8 -- padding
    local secret = false
    for _, fs in ipairs({ self.frame.bracketOpen, self.frame.CRText, self.frame.charge, self.frame.separator, self.frame.timerText, self.frame.bracketClose }) do
        if fs and fs:GetText() and fs:GetText() ~= "" then
            local sw = fs:GetStringWidth()
            if not KE:IsSafeValue(sw) then
                -- One unreadable element vetoes the whole size: a partial sum
                -- would be confidently wrong rather than merely stale.
                secret = true
            else
                totalWidth = totalWidth + sw
            end
        end
    end

    -- Spacing is per JOINT, not per element: UpdateAnchors spaces three joints
    -- in either growth direction and gives the bracket joints fixed offsets.
    -- Counting per element reserved gaps that are never drawn, and missed the
    -- gap beside an element whose text is empty. The condition is the one
    -- UpdateAnchors branches on, so the two cannot disagree.
    totalWidth = totalWidth + (self.frame.CRText and 3 or 2) * (self.db.TextSpacing or 4)

    if timerLive ~= nil then self.frame.timerText:SetText(timerLive) end
    if chargeLive ~= nil then self.frame.charge:SetText(chargeLive) end

    if not secret then
        local h = (self.db.FontSize or 16) + 10
        -- Both terms are snapped: PixelSnap rounds either way, so snapping the
        -- result could land under the floor, and a raw floor is off-grid.
        self.frame:SetSize(math.max(KE:PixelSnap(totalWidth), KE:PixelSnap(80)), h)
    end
end

---------------------------------------------------------------------------------
-- Backdrop Settings
---------------------------------------------------------------------------------
function CR:ApplyBackdropSettings()
    if not self.frame then return end

    local backdrop = self.db.Backdrop or {}

    self:ResizeToContent()

    if backdrop.Enabled then
        local bgr, bgg, bgb, bga = KE:ResolveColor(backdrop.Color, { 0, 0, 0, 0.6 })
        local bdr, bdg, bdb, bda = KE:ResolveColor(backdrop.BorderColor, { 0, 0, 0, 1 })
        local borderSize = backdrop.BorderSize or 1
        self.frame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false,
            tileSize = 0,
            edgeSize = borderSize,
            insets = { left = 0, right = 0, top = 0, bottom = 0 },
        })
        self.frame:SetBackdropColor(bgr, bgg, bgb, bga)
        self.frame:SetBackdropBorderColor(bdr, bdg, bdb, bda)
    else
        self.frame:SetBackdropColor(0, 0, 0, 0)
        self.frame:SetBackdropBorderColor(0, 0, 0, 0)
    end
end

---------------------------------------------------------------------------------
-- Update Logic
---------------------------------------------------------------------------------
-- A brez pool exists in combat, from a key start, from an encounter pull or
-- inside an instance, and a count on screen keeps the event so its changes and
-- its end are still seen.
function CR.ShouldListen(shown, inCombat, inInstance, inEncounter)
    return (shown or inCombat or inInstance or inEncounter) and true or false
end

-- Returns true when this call turned the charge event on.
function CR:SyncChargeEvent()
    local shown = self.frame ~= nil and self.frame:IsShown()
    local want = self:IsEnabled()
        and CR.ShouldListen(shown, self.inCombat, KE.Context:IsActive("CombatRes"), self.inEncounter)
    if want == self._chargeListening then return false end
    self._chargeListening = want
    if want then
        self:RegisterEvent("SPELL_UPDATE_CHARGES", "OnCombatEvent")
    else
        self:UnregisterEvent("SPELL_UPDATE_CHARGES")
    end
    return want
end

function CR:Update()
    if not self.frame then return end
    if KE.IS_FOREVER then
        self:UpdateOwnRes()
        return
    end

    local chargeTable = C_Spell.GetSpellCharges(SPELL_ID)

    if not chargeTable or not chargeTable.currentCharges
        or not canaccessvalue(chargeTable.currentCharges)
        or not canaccessvalue(chargeTable.cooldownStartTime)
        or not canaccessvalue(chargeTable.cooldownDuration) then
        if self.isPreview then
            -- Show preview with fake data
            self.frame:Show()
            if self.lastTimerText ~= "02:00" then
                self.lastTimerText = "02:00"
                self.frame.timerText:SetText("02:00")
            end
            if self.lastChargeText ~= "2" then
                self.lastChargeText = "2"
                self.frame.charge:SetText("2")
            end
            if self.lastChargeColor ~= "available" then
                self.lastChargeColor = "available"
                local r, g, b, a = KE:ResolveColor(self.db.ChargeAvailableColor, DEFAULT_CHARGE_AVAILABLE)
                self.frame.charge:SetTextColor(r, g, b, a)
            end
        else
            self.frame:Hide()
            self.lastTimerText = ""
            self.lastChargeText = ""
            self.lastChargeColor = nil
        end
        -- No live brez pool (or static preview): nothing to count down.
        self:_SetOnUpdateActive(false)
        self:SyncChargeEvent()
        return
    end


    local cdStart = chargeTable.cooldownStartTime
    local curCharges = chargeTable.currentCharges
    local cdDur = chargeTable.cooldownDuration
    local hasCharges = curCharges > 0
    local expiTime = cdStart + cdDur
    local currentCd = expiTime - GetTime()

    self.frame:Show()

    -- Update timer text
    if currentCd > 0 then
        local timerText
        if currentCd >= 3600 then
            local hours = math_floor(currentCd / 3600)
            local minutes = math_floor((currentCd % 3600) / 60)
            timerText = string_format("%d:%02d", hours, minutes)
        else
            local minutes = math_floor(currentCd / 60)
            local seconds = math_floor(currentCd % 60)
            timerText = string_format("%02d:%02d", minutes, seconds)
        end

        if timerText ~= self.lastTimerText then
            self.lastTimerText = timerText
            self.frame.timerText:SetText(timerText)
        end
    else
        if self.lastTimerText ~= "00:00" then
            self.lastTimerText = "00:00"
            self.frame.timerText:SetText("00:00")
        end
    end

    -- Update charge text
    local chargeText = tostring(curCharges)
    if chargeText ~= self.lastChargeText then
        self.lastChargeText = chargeText
        self.frame.charge:SetText(chargeText)
    end

    -- Update charge color (green = available, red = unavailable)
    local colorKey = hasCharges and "available" or "unavailable"
    if colorKey ~= self.lastChargeColor then
        self.lastChargeColor = colorKey
        local r, g, b, a
        if hasCharges then
            r, g, b, a = KE:ResolveColor(self.db.ChargeAvailableColor, DEFAULT_CHARGE_AVAILABLE)
        else
            r, g, b, a = KE:ResolveColor(self.db.ChargeUnavailableColor, DEFAULT_CHARGE_UNAVAILABLE)
        end
        self.frame.charge:SetTextColor(r, g, b, a)
    end

    -- Detach-when-idle: keep the OnUpdate only while a cooldown is actively
    -- counting down. Full charges / no active recharge = static display, so
    -- detach; SPELL_UPDATE_CHARGES re-wakes us on the next brez consumption.
    self:_SetOnUpdateActive(currentCd > 0)
    self:SyncChargeEvent()
end

-- Attach/detach the per-frame timer script. Mirrors CombatTimer's
-- _SetOnUpdateActive / KickTracker's _RefreshOnUpdate: the OnUpdate exists
-- only while there's a live countdown, instead of running all session.
function CR:_SetOnUpdateActive(active)
    if not self.frame then return end
    if active then
        if not self._onUpdateActive then
            self._onUpdateActive = true
            self.lastUpdate = 0
            self.frame:SetScript("OnUpdate", function(_, elapsed)
                self:OnUpdate(elapsed)
            end)
        end
    elseif self._onUpdateActive then
        self._onUpdateActive = false
        self.frame:SetScript("OnUpdate", nil)
    end
end

function CR:OnUpdate(elapsed)
    self.lastUpdate = self.lastUpdate + elapsed
    if self.lastUpdate < UPDATE_INTERVAL then return end
    self.lastUpdate = 0
    self:Update()
end

---------------------------------------------------------------------------------
-- Forever: the player's own res
---------------------------------------------------------------------------------
-- Pure: the caller supplies the reads. Returns state, remaining, secret;
-- a nil state hides the text, "unknown" leaves it as it is. A stone's
-- cooldown counts whether or not one is held; "ready" needs a stone.
function CR.OwnResState(entry, reads)
    if not entry then return nil end
    if entry.spell then
        if not reads.spell then return nil end
        local remaining, _, secret = reads.spellCooldown(reads.spell)
        if remaining then return "cooldown", remaining, secret == true end
        return "ready"
    end
    local remaining = reads.itemCooldown(entry.items)
    if remaining == false then return "unknown" end
    if remaining then return "cooldown", remaining, false end
    if reads.holdsAny(entry.items) then return "ready" end
    return nil
end

-- Pure: "preview", "live", or nil when the display must read nothing and
-- make no frame (switched off, or a class with no res of its own).
function CR.OwnResDisplay(isPreview, moduleOn, entry)
    if isPreview then return "preview" end
    if not moduleOn or not entry then return nil end
    return "live"
end

-- "[CR: Ready]": the count slot only, no separator or timer.
function CR:AnchorOwnRes(growRight, textSpacing, padding)
    local f = self.frame
    local gap = PrefixShown(f) and textSpacing or 0
    f.separator:Hide()
    f.timerText:Hide()
    if growRight then
        f.content:SetPoint("LEFT", f, "LEFT", padding, 0)
        f.bracketOpen:SetPoint("LEFT", f.content, "LEFT", 0, 0)
        f.CRText:SetPoint("LEFT", f.bracketOpen, "RIGHT", -2, 0)
        f.charge:SetPoint("LEFT", f.CRText, "RIGHT", gap, 0)
        f.bracketClose:SetPoint("LEFT", f.charge, "RIGHT", 0, 0)
    else
        f.content:SetPoint("RIGHT", f, "RIGHT", -padding, 0)
        f.bracketClose:SetPoint("RIGHT", f.content, "RIGHT", 0, 0)
        f.charge:SetPoint("RIGHT", f.bracketClose, "LEFT", 0, 0)
        f.CRText:SetPoint("RIGHT", f.charge, "LEFT", -gap, 0)
        f.bracketOpen:SetPoint("RIGHT", f.CRText, "LEFT", 2, 0)
    end
end

-- The count slot holds "Ready" or a time, so it is sized for the wider of
-- the two; one joint, prefix to count, when the prefix shows.
function CR:ResizeOwnRes()
    local f = self.frame
    local live = f.charge:GetText()
    local slot, secret = 0, false
    for _, ref in ipairs(OWN_RES_REFS) do
        f.charge:SetText(ref)
        local w = f.charge:GetStringWidth()
        if KE:IsSafeValue(w) then slot = math.max(slot, w) else secret = true end
    end
    self.lastChargeText = ""
    local totalWidth = 8 + slot
    for _, fs in ipairs({ f.bracketOpen, f.CRText, f.bracketClose }) do
        local text = fs:GetText()
        if text and text ~= "" then
            local w = fs:GetStringWidth()
            if KE:IsSafeValue(w) then totalWidth = totalWidth + w else secret = true end
        end
    end
    if PrefixShown(f) then totalWidth = totalWidth + (self.db.TextSpacing or 4) end
    if live then f.charge:SetText(live) end
    if not secret then
        local h = (self.db.FontSize or 16) + 10
        f:SetSize(math.max(KE:PixelSnap(totalWidth), KE:PixelSnap(80)), h)
    end
end

-- text nil leaves the slot's text as it is.
function CR:PaintOwnRes(text, colorKey)
    if text and text ~= self.lastChargeText then
        self.lastChargeText = text
        self.frame.charge:SetText(text)
    end
    if colorKey ~= self.lastChargeColor then
        self.lastChargeColor = colorKey
        local r, g, b, a
        if colorKey == "available" then
            r, g, b, a = KE:ResolveColor(self.db.ChargeAvailableColor, DEFAULT_CHARGE_AVAILABLE)
        else
            r, g, b, a = KE:ResolveColor(self.db.ChargeUnavailableColor, DEFAULT_CHARGE_UNAVAILABLE)
        end
        self.frame.charge:SetTextColor(r, g, b, a)
    end
end

function CR:UpdateOwnRes()
    local display = CR.OwnResDisplay(self.isPreview, self.db.Enabled and self:IsEnabled(), self.ownEntry)
    if display == "preview" then
        self.frame:Show()
        self:PaintOwnRes(READY_TEXT, "available")
        self:_SetOnUpdateActive(false)
        return
    end
    -- Off, nothing shows: a preview closing on a switched-off module, or a
    -- stray OnUpdate, ends here rather than reading the res.
    local state, remaining, secret
    if display == "live" then
        OWN_READS.spell = self.ownSpell
        state, remaining, secret = CR.OwnResState(self.ownEntry, OWN_READS)
    end
    if state == "unknown" then return end
    if not state then
        self.frame:Hide()
        self.lastChargeText = ""
        self.lastChargeColor = nil
        self:_SetOnUpdateActive(false)
        return
    end
    self.frame:Show()
    if state == "ready" then
        self:PaintOwnRes(READY_TEXT, "available")
        self:_SetOnUpdateActive(false)
        return
    end
    if secret then
        -- A secret time can be drawn but not compared, so it is never cached.
        self.lastChargeText = ""
        self.frame.charge:SetFormattedText("%.0f", remaining)
        self:PaintOwnRes(nil, "unavailable")
    else
        self:PaintOwnRes(FormatRemaining(remaining), "unavailable")
    end
    self:_SetOnUpdateActive(true)
end

function CR:ResolveOwnSpell()
    local entry = self.ownEntry
    self.ownSpell = entry and entry.spell and Ranks and Ranks.HighestKnown(entry.spell, OwnSpellKnown) or nil
end

function CR:OnOwnSpellsChanged()
    self:ResolveOwnSpell()
    self:OnCombatEvent("SPELLS_CHANGED")
end

-- No pool to wait for, so no combat, instance or encounter listening: the
-- res is followed wherever the player is. A class with none stays idle.
function CR:EnableOwnRes()
    local _, class = UnitClass("player")
    self.ownEntry = class and OWN_RES[class] or nil
    if not self.ownEntry then return end
    self:CreateFrame()
    self:RegWithEditMode()
    self.isPreview = false
    self:ResolveOwnSpell()
    C_Timer.After(0.5, function()
        self:ApplySettings()
    end)
    -- The spellbook may not be readable yet at enable, so the rank is
    -- resolved again on entering the world as well as on a spell change.
    self:RegisterEvent("SPELLS_CHANGED", "OnOwnSpellsChanged")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnOwnSpellsChanged")
    if self.ownEntry.spell then
        self:RegisterEvent("SPELL_UPDATE_COOLDOWN", "OnCombatEvent")
    else
        self:RegisterEvent("BAG_UPDATE_COOLDOWN", "OnCombatEvent")
        self:RegisterEvent("BAG_UPDATE_DELAYED", "OnCombatEvent")
    end
end

---------------------------------------------------------------------------------
-- Apply Settings
---------------------------------------------------------------------------------
function CR:ApplySettings()
    -- Forever: switched off, or a class with no res of its own, makes no
    -- frame outside a preview, however often its settings are applied.
    if KE.IS_FOREVER
        and not CR.OwnResDisplay(self.isPreview, self.db.Enabled and self:IsEnabled(), self.ownEntry) then
        if self.frame then
            self:_SetOnUpdateActive(false)
            self.frame:Hide()
        end
        return
    end
    if not self.frame then
        self:CreateFrame()
    end

    KE:ApplyFramePosition(self.frame, self.db.Position, self.db)
    self:ApplyTextSettings()

    if not self.db.Enabled and not self.isPreview then
        self:_SetOnUpdateActive(false)
        self.frame:Hide()
        return
    end
    self:Update()
end

function CR:ApplyPosition()
    if not self.frame then return end
    KE:ApplyFramePosition(self.frame, self.db.Position, self.db)
end

---------------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------------
function CR:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "CombatRes", displayName = "Combat Res", frame = self.frame,
            module = self,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos) self.db.Position = pos; KE:ApplyFramePosition(self.frame, self.db.Position, self.db) end,
            getParentFrame = function() return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame) end,
            guiPath = "CombatRes",
        })
        self.editModeRegistered = true
    end
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------
function CR:ShowPreview()
    if not self.frame then
        self:CreateFrame()
    end
    self:RegWithEditMode()
    self.isPreview = true
    self:ApplySettings()
end

function CR:HidePreview()
    self.isPreview = false
    if not self.frame then return end
    if not self.db.Enabled then
        self.frame:Hide()
    end
    self:Update()
end

function CR:Refresh()
    self:ApplySettings()
end

---------------------------------------------------------------------------------
-- Event Handlers
---------------------------------------------------------------------------------
function CR:OnCombatEvent(event)
    if event == "PLAYER_REGEN_DISABLED" then self.inCombat = true end
    if not self.db.Enabled then return end
    if not self.frame then return end
    -- Update() self-manages show/hide and attaches the OnUpdate only when a
    -- cooldown is actively counting down, so a single call covers every event.
    self:Update()
end

function CR:OnRegenEnabled()
    self.inCombat = false
    self:SyncChargeEvent()
end

-- A pull can come before this player is in combat. The one read picks up a
-- pool the pull created before the charge event was on.
function CR:OnEncounterStart()
    self.inEncounter = true
    self:SyncChargeEvent()
    if self.db.Enabled and self.frame then self:Update() end
end

function CR:OnEncounterEnd()
    self.inEncounter = false
    self:SyncChargeEvent()
end

local function InInstance(facts)
    return facts.inInstance
end

-- Charge events missed while off are made up with one read. Not while
-- OnEnable subscribes: the first paint stays with the delayed ApplySettings.
local function OnContextEnter()
    if CR:SyncChargeEvent() and not CR._subscribing then CR:Update() end
end

local function OnContextLeave()
    CR:SyncChargeEvent()
end

-- An unreadable zone counts as inside, so the charge event stays on.
local CONTEXT_OPTIONS = {
    needs = { "zone" },
    predicate = InInstance,
    onEnter = OnContextEnter,
    onLeave = OnContextLeave,
    onUnknown = "open",
}

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function CR:OnEnable()
    if not self.db.Enabled then return end
    if KE.IS_FOREVER then
        self:EnableOwnRes()
        return
    end
    self:CreateFrame()
    self:RegWithEditMode()

    -- Reset preview state
    self.isPreview = false

    C_Timer.After(0.5, function()
        self:ApplySettings()
    end)

    -- No unconditional OnUpdate: Update() attaches the timer script only while
    -- a cooldown is counting down (see _SetOnUpdateActive). ApplySettings ->
    -- Update does the first paint; the charge events wake it thereafter.

    -- SPELL_UPDATE_CHARGES goes through SyncChargeEvent, on only while a pool
    -- can exist.
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatEvent")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnRegenEnabled")
    self:RegisterEvent("ENCOUNTER_START", "OnEncounterStart")
    self:RegisterEvent("ENCOUNTER_END", "OnEncounterEnd")
    self:RegisterEvent("CHALLENGE_MODE_START", "OnCombatEvent")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnCombatEvent")

    -- A fight or pull already under way fired its start event before this.
    self.inCombat = UnitAffectingCombat("player") and true or false
    local inProgress = C_InstanceEncounter and C_InstanceEncounter.IsEncounterInProgress
    self.inEncounter = (inProgress and inProgress()) == true
    self._subscribing = true
    KE.Context:Subscribe("CombatRes", CONTEXT_OPTIONS)
    self._subscribing = false
    self:SyncChargeEvent()
end

function CR:OnDisable()
    KE.Context:Unsubscribe("CombatRes")
    if self.frame then
        self:_SetOnUpdateActive(false)
        self.frame:Hide()
    end
    self.isPreview = false
    self:UnregisterAllEvents()
    self._chargeListening = false
    self.inCombat = false
    self.inEncounter = false
end
