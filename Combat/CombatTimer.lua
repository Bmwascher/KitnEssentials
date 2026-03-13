-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class CombatTimer: AceModule, AceEvent-3.0
local CT = KitnEssentials:NewModule("CombatTimer", "AceEvent-3.0")

local CreateFrame = CreateFrame
local GetTime = GetTime
local math_floor, math_max = math.floor, math.max
local string_format = string.format

CT.frame = nil
CT.text = nil
CT.startTime = 0
CT.running = false
CT.lastDisplayedText = ""
CT.isPreview = false

KE.lastCombatDuration = 0

function CT:UpdateDB()
    self.db = KE.db.profile.CombatTimer
end

function CT:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

local function GetBrackets(style)
    if style == "round" then return "(", ")"
    elseif style == "none" then return "", ""
    else return "[", "]" end
end

local function FormatTime(total_seconds, format, bracketStyle)
    local mins = math_floor(total_seconds / 60)
    local secs = math_floor(total_seconds % 60)
    local open, close = GetBrackets(bracketStyle)
    if format == "MM:SS:MS" then
        local frac = total_seconds - math_floor(total_seconds)
        local ms = math_floor(frac * 10)
        return string_format("%s%02d:%02d:%d%s", open, mins, secs, ms, close)
    end
    return string_format("%s%02d:%02d%s", open, mins, secs, close)
end

local function GetRefreshRate(format)
    return (format == "MM:SS:MS") and 0.1 or 0.25
end

function CT:CreateFrame()
    if self.frame then return end
    local frame = CreateFrame("Frame", "KE_CombatTimerFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate")
    frame:SetSize(100, 25)
    KE:ApplyFramePosition(frame, self.db.Position, self.db)
    frame:SetFrameLevel(100)
    frame:EnableMouse(false)
    frame:SetMouseClickEnabled(false)
    frame:Hide()

    local text = frame:CreateFontString("KE_CombatTimerText", "OVERLAY")
    text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    text:SetFont(KE.FONT, 14, "")
    local open, close = GetBrackets(self.db.BracketStyle)
    text:SetText(open .. "00:00" .. close)
    text:SetJustifyH("CENTER")
    text:SetJustifyV("MIDDLE")

    self.frame = frame
    frame.text = text
    self.text = text
end

function CT:UpdateFrameSize()
    if not self.frame then return end
    local backdrop = self.db.Backdrop or {}
    self.frame:SetSize(backdrop.bgWidth or 100, backdrop.bgHeight or 26)
end

function CT:UpdateText()
    if not self.text then return end
    local total_time
    if self.running then
        total_time = self.startTime > 0 and (GetTime() - self.startTime) or 0
    else
        total_time = KE.lastCombatDuration or 0
    end
    local status = FormatTime(total_time, self.db.Format, self.db.BracketStyle)
    if status ~= self.lastDisplayedText then
        self.text:SetText(status)
        self.lastDisplayedText = status
        self:UpdateFrameSize()
    end
end

function CT:ApplySettings()
    if not self.text then return end
    KE:ApplyFontToText(self.text, self.db.FontFace, self.db.FontSize, self.db.FontOutline, self.db.FontShadow)
    local justify = KE:GetTextJustifyFromAnchor(self.db.Position.AnchorFrom)
    local point = KE:GetTextPointFromAnchor(self.db.Position.AnchorFrom)
    self.text:ClearAllPoints()
    self.text:SetJustifyH(justify)
    if point == "LEFT" then
        self.text:SetPoint("LEFT", self.frame, "LEFT", 4, 0)
    elseif point == "RIGHT" then
        self.text:SetPoint("RIGHT", self.frame, "RIGHT", -4, 0)
    else
        self.text:SetPoint("CENTER", self.frame, "CENTER", 0, 0)
    end
    local textColor = self.running and self.db.ColorInCombat or self.db.ColorOutOfCombat
    if textColor then
        self.text:SetTextColor(textColor[1] or 1, textColor[2] or 1, textColor[3] or 1, textColor[4] or 1)
    else
        self.text:SetTextColor(1, 1, 1, 1)
    end
    if self.frame then
        KE:ApplyBackdrop(self.frame, self.db.Backdrop)
    end
    self:UpdateFrameSize()
    self:UpdateText()
    self:ApplyPosition()
end

function CT:OnUpdate(elapsed)
    if not self.running and not self.isPreview then return end
    self.elapsed = (self.elapsed or 0) + elapsed
    local refresh = GetRefreshRate(self.db.Format)
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
        local duration = FormatTime(KE.lastCombatDuration, self.db.Format, self.db.BracketStyle)
        KE:Print("Combat lasted " .. duration)
    end
    self:ApplySettings()
    self:UpdateText()
end

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
