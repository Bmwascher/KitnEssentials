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

CR.frame = nil
CR.lastUpdate = 0
CR.lastTimerText = ""
CR.lastChargeText = ""
CR.lastChargeColor = nil
CR.isPreview = false
CR._onUpdateActive = false

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

    -- Set separator text and color
    self.frame.separator:SetText(db.Separator or "|")
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

    self:UpdateAnchors()
    self:ApplyBackdropSettings()
end

---------------------------------------------------------------------------------
-- Backdrop Settings
---------------------------------------------------------------------------------
-- Sizes from fixed references, not the live text. On a right-side anchor a
-- width change walks the frame's left edge, and the content is anchored to
-- that edge, so the text walks with it.
function CR:ResizeToContent()
    if not self.frame then return end

    local timerLive = self.frame.timerText:GetText()
    local chargeLive = self.frame.charge:GetText()
    self.frame.timerText:SetText(TIMER_REF)
    self.frame.charge:SetText(CHARGE_REF)

    local totalWidth = 8 -- padding
    local tainted = false
    for _, fs in ipairs({ self.frame.bracketOpen, self.frame.CRText, self.frame.charge, self.frame.separator, self.frame.timerText, self.frame.bracketClose }) do
        if fs and fs:GetText() and fs:GetText() ~= "" then
            -- Refuses secret, non-numeric and zero-or-less; a zero reading
            -- would collapse the box around text that is merely unlaid.
            local sw = KE:MeasureFontString(fs)
            if sw then
                totalWidth = totalWidth + sw + (self.db.TextSpacing or 4)
            else
                tainted = true
            end
        end
    end

    if timerLive ~= nil then self.frame.timerText:SetText(timerLive) end
    if chargeLive ~= nil then self.frame.charge:SetText(chargeLive) end

    if not tainted then
        local h = (self.db.FontSize or 16) + 10
        -- Snap before the floor: PixelSnap rounds either way, so snapping the
        -- floored value can land under it.
        self.frame:SetSize(math.max(KE:PixelSnap(totalWidth), 80), h)
    end
end

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
function CR:Update()
    if not self.frame then return end

    local chargeTable = C_Spell.GetSpellCharges(SPELL_ID)

    if not chargeTable or not chargeTable.currentCharges then
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
-- Apply Settings
---------------------------------------------------------------------------------
function CR:ApplySettings()
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
function CR:OnCombatEvent()
    if not self.db.Enabled then return end
    if not self.frame then return end
    -- Update() self-manages show/hide and attaches the OnUpdate only when a
    -- cooldown is actively counting down, so a single call covers every event.
    self:Update()
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function CR:OnEnable()
    if not self.db.Enabled then return end
    self:CreateFrame()
    self:RegWithEditMode()

    -- Reset preview state
    self.isPreview = false

    C_Timer.After(0.5, function()
        self:ApplySettings()
    end)

    -- No unconditional OnUpdate: Update() attaches the timer script only while
    -- a cooldown is counting down (see _SetOnUpdateActive). ApplySettings ->
    -- Update does the first paint; the charge events below wake it thereafter.

    -- Register events to detect when battle res charges become available
    self:RegisterEvent("SPELL_UPDATE_CHARGES", "OnCombatEvent")
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatEvent")
    self:RegisterEvent("CHALLENGE_MODE_START", "OnCombatEvent")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnCombatEvent")
end

function CR:OnDisable()
    if self.frame then
        self:_SetOnUpdateActive(false)
        self.frame:Hide()
    end
    self.isPreview = false
    self:UnregisterAllEvents()
end
