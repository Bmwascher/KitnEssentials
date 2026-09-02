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
local math_floor = math.floor
local string_format = string.format

-- KE.CombatState listener/cadence key. Registered in OnEnable, dropped in
-- OnDisable, so a re-enable cannot stack a duplicate.
local LISTENER_KEY = "CombatTimer"

CT.frame = nil
CT.text = nil
CT.lastDisplayedText = ""
CT.isPreview = false

-- Brackets live in the timer string itself, as the reference renders them.
-- They were previously two extra FontStrings pinned to the frame edges, which
-- left the space between a bracket and the digits to whatever the frame sizing
-- had spare rather than to the font's own spacing. Cached because FormatTime
-- runs on every tick.
local cachedOpenBracket, cachedCloseBracket = "[", "]"

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

local function FormatTime(total_seconds, format)
    local mins = math_floor(total_seconds / 60)
    local secs = math_floor(total_seconds % 60)
    if format == "MM:SS:MS" then
        local frac = total_seconds - math_floor(total_seconds)
        local ms = math_floor(frac * 10)
        return string_format("%s%02d:%02d:%d%s",
            cachedOpenBracket, mins, secs, ms, cachedCloseBracket)
    end
    return string_format("%s%02d:%02d%s",
        cachedOpenBracket, mins, secs, cachedCloseBracket)
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

    local text = frame:CreateFontString("KE_CombatTimerText", "OVERLAY")
    text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    text:SetJustifyH("CENTER")
    text:SetJustifyV("MIDDLE")
    KE:ApplyFont(text, "Expressway", 14, "")
    text:SetText(cachedOpenBracket .. "00:00" .. cachedCloseBracket)

    self.frame = frame
    frame.text = text
    self.text = text
end

---------------------------------------------------------------------------------
-- Update Logic
---------------------------------------------------------------------------------
function CT:UpdateFrameSize()
    if not self.frame or not self.text then return end

    -- Measure against a fixed reference string, brackets included, so the frame
    -- stays put as the digits tick. GetStringWidth() straight after SetText()
    -- also returns stale metrics, which mis-sized the backdrop.
    local current = self.text:GetText()
    local refBody = (self.db.Format == "MM:SS:MS") and "00:00:0" or "00:00"
    self.text:SetText(cachedOpenBracket .. refBody .. cachedCloseBracket)

    -- Snapped to an even pixel multiple: GetStringWidth() is a float, and
    -- rounding keeps text-CENTER on integer pixels and the right edge on the
    -- pixel grid. ApplyFramePosition's auto-snap aligns LEFT/BOTTOM, not width.
    local total = KE:PixelSnapEven(self.text:GetStringWidth() or 0)
    -- Height from the rendered string, not the configured size: an outline adds
    -- to the glyph box, so a size-derived height clips the tallest outlines.
    local height = self.text:GetStringHeight() or 0
    if not (KE:IsSafeValue(height) and height > 0) then height = self.db.FontSize or 28 end
    if KE:IsSafeValue(total) then
        self.frame:SetSize(total, height + 8)
    end

    if current ~= nil then self.text:SetText(current) end
end

-- Paints total_seconds through the current format, skipping the redraw when
-- the rendered string hasn't changed.
function CT:_PaintTime(total_seconds)
    local status = FormatTime(total_seconds, self.db.Format)
    if status ~= self.lastDisplayedText then
        self.text:SetText(status)
        self.lastDisplayedText = status
        self:UpdateFrameSize()
    end
end

-- The settled-case renderer: reads the pin back through the service and takes
-- no reading of its own. Used out of combat and by the preview OnUpdate.
function CT:UpdateText()
    if not self.text then return end
    self:_PaintTime(KE.CombatState:GetDuration() or 0)
end

-- Colour is the only thing a combat transition changes, so it is split out of
-- ApplySettings: running the whole of that on every enter and exit re-applied
-- the font, re-anchored the text and re-measured the frame twice per fight for
-- nothing.
function CT:UpdateCombatColor()
    if not self.text then return end
    local textColor = KE.CombatState:IsLive() and self.db.ColorInCombat or self.db.ColorOutOfCombat
    local r, g, b, a = 1, 1, 1, 1
    if textColor then
        r = textColor[1] or 1
        g = textColor[2] or 1
        b = textColor[3] or 1
        a = textColor[4] or 1
    end
    self.text:SetTextColor(r, g, b, a)
end

---------------------------------------------------------------------------------
-- Apply Settings
---------------------------------------------------------------------------------
function CT:ApplySettings()
    if not self.text then return end
    self.refreshRate = GetRefreshRate(self.db.Format)
    KE.CombatState:SetFineCadence(LISTENER_KEY, self.db.Format == "MM:SS:MS")

    cachedOpenBracket, cachedCloseBracket = GetBrackets(self.db.BracketStyle)
    KE:ApplyFontToText(self.text, self.db.FontFace, self.db.FontSize, self.db.FontOutline, self.db.FontShadow)

    -- One string, so placement is just where it sits in the frame: pinned to
    -- the held edge for an edge anchor, centred otherwise. Pinning the held
    -- edge keeps that edge still as the rendered width changes.
    local justify = KE:GetTextJustifyFromAnchor(self.db.Position.AnchorFrom)
    local point = KE:GetTextPointFromAnchor(self.db.Position.AnchorFrom)
    self.text:ClearAllPoints()
    self.text:SetJustifyH(justify)
    if point == "LEFT" then
        self.text:SetPoint("LEFT", self.frame, "LEFT", 0, 0)
    elseif point == "RIGHT" then
        self.text:SetPoint("RIGHT", self.frame, "RIGHT", 0, 0)
    else
        self.text:SetPoint("CENTER", self.frame, "CENTER", 0, 0)
    end

    -- The rendered string changes with the bracket style, so force a re-stamp.
    self.lastDisplayedText = ""

    self:UpdateCombatColor()

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
-- Attached only for preview: live paint runs entirely off OnClockTick, per the
-- paint contract.
function CT:OnUpdate(elapsed)
    if not self.isPreview then return end
    self.elapsed = (self.elapsed or 0) + elapsed
    local refresh = self.refreshRate or GetRefreshRate(self.db.Format)
    if self.elapsed < refresh then return end
    self.elapsed = self.elapsed - refresh
    self:UpdateText()
end

-- Attach/detach the OnUpdate script based on whether work is needed. Out of
-- combat with no preview, the script is detached entirely so the frame pays
-- zero dispatch overhead per render tick.
function CT:_SetOnUpdateActive(active)
    if not self.frame then return end
    if active then
        if self._onUpdateActive then return end
        self.frame:SetScript("OnUpdate", function(_, elapsed) self:OnUpdate(elapsed) end)
        self._onUpdateActive = true
    else
        if not self._onUpdateActive then return end
        self.frame:SetScript("OnUpdate", nil)
        self._onUpdateActive = false
    end
end

---------------------------------------------------------------------------------
-- KE.CombatState listener
---------------------------------------------------------------------------------
-- Shows the frame and the in-combat colour. Attaches nothing: the service's
-- clock tick drives the paint, and it already broadcast a blank OnClockTick
-- immediately before this.
function CT:OnStart()
    if self.frame then self.frame:Show() end
    self.lastDisplayedText = ""
    self:UpdateCombatColor()
end

-- Applies the out-of-combat colour and repaints from the pin, already the
-- final value on screen since a freeze broadcasts a last OnClockTick first.
-- Zoning is not a fight ending, and a fight the player never entered is not
-- theirs to report.
function CT:OnStop(reason)
    self:UpdateCombatColor()
    self:UpdateText()
    if self.db.ShowChatMessage ~= false and reason ~= "reset" and KE.CombatState:PlayerJoined() then
        local duration = FormatTime(KE.CombatState:GetDuration() or 0, self.db.Format)
        KE:Print("Combat lasted " .. duration)
    end
end

-- The only live paint path. fraction supplies the MM:SS:MS format's final
-- digit; it stays under 1, so it never shifts the mins/secs it is added to.
function CT:OnClockTick(seconds, fraction)
    if not self.text then return end
    self:_PaintTime((seconds or 0) + (fraction or 0))
end

---------------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------------
function CT:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "CombatTimer", displayName = "Combat Timer", frame = self.frame,
            module = self,
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
    self:_SetOnUpdateActive(true)
end

function CT:HidePreview()
    self.isPreview = false
    if self.frame and not KE.CombatState:IsLive() and not self.db.Enabled then
        self.frame:Hide()
    end
    self:_SetOnUpdateActive(false)
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
    KE.CombatState:RegisterListener(LISTENER_KEY, {
        OnStart = function() self:OnStart() end,
        OnStop = function(reason) self:OnStop(reason) end,
        OnClockTick = function(seconds, fraction) self:OnClockTick(seconds, fraction) end,
    })
    KE.CombatState:SetFineCadence(LISTENER_KEY, self.db.Format == "MM:SS:MS")
    if self.db.Enabled then self.frame:Show() end
end

function CT:OnDisable()
    if self.frame then
        self:_SetOnUpdateActive(false)
        self.frame:Hide()
    end
    self.isPreview = false
    KE.CombatState:SetFineCadence(LISTENER_KEY, false)
    KE.CombatState:UnregisterListener(LISTENER_KEY)
    self:UnregisterAllEvents()
end
