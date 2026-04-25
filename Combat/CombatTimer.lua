-- ╔══════════════════════════════════════════════════════════╗
-- ║  CombatTimer.lua                                         ║
-- ║  Module: Combat Timer                                    ║
-- ║  Purpose: Configurable in-combat duration display        ║
-- ║           with multiple format options.                  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class CombatTimer: AceModule, AceEvent-3.0
local CT = KitnEssentials:NewModule("CombatTimer", "AceEvent-3.0")

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
local CreateFrame = CreateFrame
local GetTime = GetTime
local math_floor = math.floor
local string_format = string.format

CT.frame = nil
CT.text = nil
CT.startTime = 0
CT.running = false
CT.lastDisplayedText = ""
CT.isPreview = false

KE.lastCombatDuration = 0

local function GetRefreshRate(format)
    return (format == "MM:SS:MS") and 0.1 or 0.25
end

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function CT:UpdateDB()
    self.db = KE.db.profile.CombatTimer
    self.refreshRate = GetRefreshRate(self.db.Format)
end

function CT:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

---------------------------------------------------------------------------------
-- Formatting
---------------------------------------------------------------------------------
local function GetBrackets(style)
    if style == "round" then return "(", ")"
    elseif style == "none" then return "", ""
    else return "[", "]" end
end

-- Returns the digits-only timer string (no brackets). Brackets are rendered
-- as separate FontStrings pinned to the frame's edges so they don't shift
-- as proportional digit widths vary.
local function FormatTime(total_seconds, format)
    local mins = math_floor(total_seconds / 60)
    local secs = math_floor(total_seconds % 60)
    if format == "MM:SS:MS" then
        local frac = total_seconds - math_floor(total_seconds)
        local ms = math_floor(frac * 10)
        return string_format("%02d:%02d:%d", mins, secs, ms)
    end
    return string_format("%02d:%02d", mins, secs)
end

---------------------------------------------------------------------------------
-- Frame Creation
---------------------------------------------------------------------------------
function CT:CreateFrame()
    if self.frame then return end
    local frame = CreateFrame("Frame", "KE_CombatTimerFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate")
    frame:SetSize(100, 25)
    KE:ApplyFramePosition(frame, self.db.Position, self.db)
    frame:SetFrameLevel(100)
    frame:EnableMouse(false)
    frame:SetMouseClickEnabled(false)
    frame:Hide()

    -- Brackets are separate FontStrings pinned to the frame's edges so they
    -- don't shift as proportional digit widths vary in the digits FontString.
    -- Inset is 0 so the brackets sit snug to the frame edge — visual gap to
    -- the digits is controlled by the small safety pad in UpdateFrameSize.
    local bracketL = frame:CreateFontString(nil, "OVERLAY")
    bracketL:SetPoint("LEFT", frame, "LEFT", 0, 0)
    bracketL:SetJustifyH("LEFT")
    bracketL:SetJustifyV("MIDDLE")
    KE:ApplyFont(bracketL, "Expressway", 14, "")

    local bracketR = frame:CreateFontString(nil, "OVERLAY")
    bracketR:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    bracketR:SetJustifyH("RIGHT")
    bracketR:SetJustifyV("MIDDLE")
    KE:ApplyFont(bracketR, "Expressway", 14, "")

    local text = frame:CreateFontString("KE_CombatTimerText", "OVERLAY")
    text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    text:SetJustifyH("CENTER")
    text:SetJustifyV("MIDDLE")
    KE:ApplyFont(text, "Expressway", 14, "")
    text:SetText("00:00")

    self.frame = frame
    frame.text = text
    self.text = text
    self.bracketL = bracketL
    self.bracketR = bracketR
end

---------------------------------------------------------------------------------
-- Update Logic
---------------------------------------------------------------------------------
function CT:UpdateFrameSize()
    if not self.frame or not self.text then return end

    -- Measure against a fixed reference string so frame width stays stable
    -- regardless of which digits are currently rendered (proportional fonts
    -- give "1" a different width than "0", which would shift bracket
    -- positions if the brackets shared a FontString with the digits).
    local current = self.text:GetText()
    local refDigits = (self.db.Format == "MM:SS:MS") and "00:00:0" or "00:00"
    self.text:SetText(refDigits)

    local digitsW = self.text:GetStringWidth() or 0
    local bracketW = 0
    if self.bracketL and self.bracketL:IsShown() then
        bracketW = (self.bracketL:GetStringWidth() or 0) + (self.bracketR:GetStringWidth() or 0)
    end

    -- Frame width = digits + brackets + 2px (1px each side). The 1px
    -- clearance keeps the bracket characters' soft-outline eastern/western
    -- shadows from bleeding into the adjacent digits, while staying tight
    -- enough that there's no visible gap. ceil rounds up to even pixels so
    -- text centering doesn't land on a sub-pixel boundary.
    local total = math.ceil(digitsW + bracketW)
    if total % 2 == 1 then total = total + 1 end
    if KE:IsSafeValue(total) then
        self.frame:SetSize(total, (self.db.FontSize or 28) + 8)
    end

    if current ~= nil then self.text:SetText(current) end
end

function CT:UpdateText()
    if not self.text then return end
    local total_time
    if self.running then
        total_time = self.startTime > 0 and (GetTime() - self.startTime) or 0
    else
        total_time = KE.lastCombatDuration or 0
    end
    local status = FormatTime(total_time, self.db.Format)
    if status ~= self.lastDisplayedText then
        self.text:SetText(status)
        self.lastDisplayedText = status
        self:UpdateFrameSize()
    end
end

---------------------------------------------------------------------------------
-- Apply Settings
---------------------------------------------------------------------------------
function CT:ApplySettings()
    if not self.text then return end
    self.refreshRate = GetRefreshRate(self.db.Format)

    -- Same font on all three FontStrings so brackets and digits visually
    -- align (matching x-height, weight, soft-outline rendering).
    KE:ApplyFontToText(self.text, self.db.FontFace, self.db.FontSize, self.db.FontOutline, self.db.FontShadow)
    KE:ApplyFontToText(self.bracketL, self.db.FontFace, self.db.FontSize, self.db.FontOutline, self.db.FontShadow)
    KE:ApplyFontToText(self.bracketR, self.db.FontFace, self.db.FontSize, self.db.FontOutline, self.db.FontShadow)

    -- Bracket characters + visibility per BracketStyle. When the style is
    -- "none" the digits FontString takes over the full frame width and
    -- respects the user's anchor-justify preference (legacy behavior).
    local open, close = GetBrackets(self.db.BracketStyle)
    self.text:ClearAllPoints()
    if open == "" then
        self.bracketL:Hide()
        self.bracketR:Hide()
        -- Soft-outline shadows are parented to the FRAME, not the bracket
        -- FontString, so :Hide() on the bracket alone leaves 8 shadow ghosts
        -- visible. Explicitly hide the .softOutline as well.
        if self.bracketL.softOutline then self.bracketL.softOutline:SetShown(false) end
        if self.bracketR.softOutline then self.bracketR.softOutline:SetShown(false) end
        local justify = KE:GetTextJustifyFromAnchor(self.db.Position.AnchorFrom)
        local point = KE:GetTextPointFromAnchor(self.db.Position.AnchorFrom)
        self.text:SetJustifyH(justify)
        if point == "LEFT" then
            self.text:SetPoint("LEFT", self.frame, "LEFT", 4, 0)
        elseif point == "RIGHT" then
            self.text:SetPoint("RIGHT", self.frame, "RIGHT", -4, 0)
        else
            self.text:SetPoint("CENTER", self.frame, "CENTER", 0, 0)
        end
    else
        self.bracketL:SetText(open)
        self.bracketR:SetText(close)
        self.bracketL:Show()
        self.bracketR:Show()
        self.text:SetJustifyH("CENTER")
        self.text:SetPoint("CENTER", self.frame, "CENTER", 0, 0)
    end

    -- Colors apply to all three so the timer reads as one piece.
    local textColor = self.running and self.db.ColorInCombat or self.db.ColorOutOfCombat
    local r, g, b, a = 1, 1, 1, 1
    if textColor then
        r = textColor[1] or 1
        g = textColor[2] or 1
        b = textColor[3] or 1
        a = textColor[4] or 1
    end
    self.text:SetTextColor(r, g, b, a)
    self.bracketL:SetTextColor(r, g, b, a)
    self.bracketR:SetTextColor(r, g, b, a)

    if self.frame then
        KE:ApplyBackdrop(self.frame, self.db.Backdrop)
    end
    self:UpdateFrameSize()
    self:UpdateText()
    self:ApplyPosition()
end

---------------------------------------------------------------------------------
-- Core Logic
---------------------------------------------------------------------------------
function CT:OnUpdate(elapsed)
    if not self.running and not self.isPreview then return end
    self.elapsed = (self.elapsed or 0) + elapsed
    local refresh = self.refreshRate or GetRefreshRate(self.db.Format)
    if self.elapsed < refresh then return end
    self.elapsed = self.elapsed - refresh
    self:UpdateText()
end

function CT:OnEnterCombat()
    if self.running or not self.db.Enabled then return end
    self.startTime = GetTime()
    self.running = true
    KE.lastCombatDuration = 0
    self.lastDisplayedText = ""
    if self.frame then self.frame:Show() end
    self:ApplySettings()
    self:UpdateText()
end

function CT:OnExitCombat()
    if not self.running then return end
    KE.lastCombatDuration = GetTime() - self.startTime
    self.running = false
    self.startTime = 0
    if self.db.ShowChatMessage ~= false then
        local duration = FormatTime(KE.lastCombatDuration, self.db.Format)
        KE:Print("Combat lasted " .. duration)
    end
    self:ApplySettings()
    self:UpdateText()
end

---------------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------------
function CT:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "CombatTimer", displayName = "Combat Timer", frame = self.frame,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos) self.db.Position = pos; KE:ApplyFramePosition(self.frame, self.db.Position, self.db) end,
            getParentFrame = function() return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame) end,
            guiPath = "CombatTimer",
        })
        self.editModeRegistered = true
    end
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------
function CT:ShowPreview()
    if not self.frame then self:CreateFrame() end
    self:RegWithEditMode()
    self.isPreview = true
    self.frame:Show()
    self:ApplySettings()
end

function CT:HidePreview()
    self.isPreview = false
    if self.frame and not self.running and not self.db.Enabled then
        self.frame:Hide()
    end
end

function CT:ApplyPosition()
    if not self.db.Enabled then return end
    if not self.frame then return end
    KE:ApplyFramePosition(self.frame, self.db.Position, self.db)
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function CT:OnEnable()
    if not self.db.Enabled then return end
    self:CreateFrame()
    self:RegWithEditMode()
    self:ApplySettings()
    C_Timer.After(0.5, function() self:ApplyPosition() end)
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnEnterCombat")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnExitCombat")
    self.frame:SetScript("OnUpdate", function(_, elapsed) self:OnUpdate(elapsed) end)
    if self.db.Enabled then self.frame:Show() end
end

function CT:OnDisable()
    if self.frame then
        self.frame:SetScript("OnUpdate", nil)
        self.frame:Hide()
    end
    self.running = false
    self.isPreview = false
    self:UnregisterAllEvents()
end
