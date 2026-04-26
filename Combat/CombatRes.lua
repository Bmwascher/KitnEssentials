-- ╔══════════════════════════════════════════════════════════╗
-- ║  CombatRes.lua                                           ║
-- ║  Module: Battle Res                                      ║
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
local pcall = pcall
local C_Spell = C_Spell
local tostring = tostring
local GetTime = GetTime
local string_format = string.format
local math_floor = math.floor


local SPELL_ID = 20484 -- Rebirth
local UPDATE_INTERVAL = 0.1

CR.frame = nil
CR.lastUpdate = 0
CR.lastTimerText = ""
CR.lastChargeText = ""
CR.lastChargeColor = nil
CR.isPreview = false

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
    local fontPath = KE:GetFontPath(db.FontFace or "Expressway") or KE.FONT
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

    -- Timer text
    frame.timerText = frame.content:CreateFontString(nil, "OVERLAY")
    frame.timerText:SetFont(fontPath, fontSize, "")
    frame.timerText:SetTextColor(1, 1, 1, 1)

    -- Separator text
    frame.separator = frame.content:CreateFontString(nil, "OVERLAY")
    frame.separator:SetFont(fontPath, fontSize, "")
    frame.separator:SetText("|")
    frame.separator:SetTextColor(1, 1, 1, 1)

    -- Charge text
    frame.charge = frame.content:CreateFontString(nil, "OVERLAY")
    frame.charge:SetFont(fontPath, fontSize, "")
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
    local fontName = db.FontFace or "Expressway"
    local fontSize = db.FontSize or 16
    local fontOutline = db.FontOutline or "SOFTOUTLINE"

    -- Apply font to all text elements (no shadow)
    KE:ApplyFontToText(self.frame.separator, fontName, fontSize, fontOutline)
    KE:ApplyFontToText(self.frame.charge, fontName, fontSize, fontOutline)
    KE:ApplyFontToText(self.frame.timerText, fontName, fontSize, fontOutline)
    KE:ApplyFontToText(self.frame.CRText, fontName, fontSize, fontOutline)
    KE:ApplyFontToText(self.frame.bracketOpen, fontName, fontSize, fontOutline)
    KE:ApplyFontToText(self.frame.bracketClose, fontName, fontSize, fontOutline)

    -- Per-element colors from DB
    local sepColor = db.SeparatorColor or { 1, 1, 1, 1 }
    local timerColor = db.TimerColor or { 1, 1, 1, 1 }

    -- Set separator text and color
    self.frame.separator:SetText(db.Separator or "|")
    self.frame.separator:SetTextColor(sepColor[1], sepColor[2], sepColor[3], sepColor[4] or 1)

    -- Set charge prefix text and color (uses separator color)
    self.frame.CRText:SetText(db.SeparatorCharges or "CR:")
    self.frame.CRText:SetTextColor(sepColor[1], sepColor[2], sepColor[3], sepColor[4] or 1)

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
    self.frame.bracketOpen:SetTextColor(sepColor[1], sepColor[2], sepColor[3], sepColor[4] or 1)
    self.frame.bracketClose:SetTextColor(sepColor[1], sepColor[2], sepColor[3], sepColor[4] or 1)

    -- Timer text color
    self.frame.timerText:SetTextColor(timerColor[1], timerColor[2], timerColor[3], timerColor[4] or 1)

    self:UpdateAnchors()
    self:ApplyBackdropSettings()
end

---------------------------------------------------------------------------------
-- Backdrop Settings
---------------------------------------------------------------------------------
function CR:ApplyBackdropSettings()
    if not self.frame then return end

    local backdrop = self.db.Backdrop or {}

    -- Size frame from content (GetStringWidth can return secret after combat)
    local totalWidth = 8 -- padding
    local tainted = false
    for _, fs in ipairs({ self.frame.bracketOpen, self.frame.CRText, self.frame.charge, self.frame.separator, self.frame.timerText, self.frame.bracketClose }) do
        if fs and fs:GetText() and fs:GetText() ~= "" then
            local sw = fs:GetStringWidth()
            if KE:IsSafeValue(sw) then
                totalWidth = totalWidth + sw + (self.db.TextSpacing or 4)
            else
                tainted = true
            end
        end
    end
    if not tainted then
        local h = (self.db.FontSize or 16) + 10
        self.frame:SetSize(math.max(totalWidth, 80), h)
    end

    if backdrop.Enabled then
        local bgColor = backdrop.Color or { 0, 0, 0, 0.6 }
        local borderColor = backdrop.BorderColor or { 0, 0, 0, 1 }
        local borderSize = backdrop.BorderSize or 1
        self.frame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false,
            tileSize = 0,
            edgeSize = borderSize,
            insets = { left = 0, right = 0, top = 0, bottom = 0 },
        })
        self.frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 0.6)
        self.frame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
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
            local ac = self.db.ChargeAvailableColor or DEFAULT_CHARGE_AVAILABLE
            if self.lastChargeColor ~= "available" then
                self.lastChargeColor = "available"
                self.frame.charge:SetTextColor(ac[1], ac[2], ac[3], ac[4] or 1)
            end
        else
            self.frame:Hide()
            self.lastTimerText = ""
            self.lastChargeText = ""
            self.lastChargeColor = nil
        end
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
        local color = hasCharges
            and (self.db.ChargeAvailableColor or DEFAULT_CHARGE_AVAILABLE)
            or (self.db.ChargeUnavailableColor or DEFAULT_CHARGE_UNAVAILABLE)
        self.frame.charge:SetTextColor(color[1], color[2], color[3], color[4] or 1)
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

    KE:ApplyFramePositionWithSnap(self.frame, self.db.Position, self.db)
    self:ApplyTextSettings()

    if not self.db.Enabled and not self.isPreview then
        self.frame:Hide()
        return
    end
    self:Update()
    -- ApplyTextSettings -> ApplyBackdropSettings sized the frame from
    -- GetStringWidth before Update populated the timer/charge FontStrings,
    -- so the result was too narrow until something re-sized it (e.g. a
    -- second edit-mode entry). Re-size now that all content is in place.
    self:ApplyBackdropSettings()
end

function CR:ApplyPosition()
    if not self.frame then return end
    KE:ApplyFramePositionWithSnap(self.frame, self.db.Position, self.db)
end

---------------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------------
function CR:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "CombatRes", displayName = "Combat Res", frame = self.frame,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos) self.db.Position = pos; KE:ApplyFramePositionWithSnap(self.frame, self.db.Position, self.db) end,
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
    if not self.db.Enabled and self.frame then
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

    -- Try to get charge data
    local chargeTable = C_Spell.GetSpellCharges(SPELL_ID)

    if chargeTable and chargeTable.currentCharges then
        -- Charges available — show frame and ensure OnUpdate is running
        if not self.frame:IsShown() then
            self.frame:Show()
        end
        if not self.frame:GetScript("OnUpdate") then
            self.frame:SetScript("OnUpdate", function(_, elapsed)
                self:OnUpdate(elapsed)
            end)
        end
        self:Update()
    end
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

    -- Set up OnUpdate for timer tracking
    self.frame:SetScript("OnUpdate", function(_, elapsed)
        self:OnUpdate(elapsed)
    end)

    -- Register events to detect when battle res charges become available
    self:RegisterEvent("SPELL_UPDATE_CHARGES", "OnCombatEvent")
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatEvent")
    self:RegisterEvent("CHALLENGE_MODE_START", "OnCombatEvent")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnCombatEvent")
end

function CR:OnDisable()
    if self.frame then
        self.frame:SetScript("OnUpdate", nil)
        self.frame:Hide()
    end
    self.isPreview = false
    self:UnregisterAllEvents()
end
