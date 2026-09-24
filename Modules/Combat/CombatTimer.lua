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
local InCombatLockdown = InCombatLockdown
local math_floor = math.floor
local string_format = string.format
local select = select
local tostring = tostring

local DEBUG_CT = false

-- Nil when the namespace is absent: the timer then loses the encounter hold
-- and stops at a death; it never runs on.
local IsEncounterInProgress = C_InstanceEncounter and C_InstanceEncounter.IsEncounterInProgress

CT.frame = nil
CT.text = nil
CT.lastDisplayedText = ""
CT.isPreview = false
CT.running = false
CT.inEncounter = false
CT.startTime = 0
CT.span = 0
CT.ticker = nil

-- Brackets live in the timer string itself.
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

function CT:_PaintTime(total_seconds)
    local status = FormatTime(total_seconds, self.db.Format)
    if status ~= self.lastDisplayedText then
        self.text:SetText(status)
        self.lastDisplayedText = status
        self:UpdateFrameSize()
    end
end

function CT:UpdateText()
    if not self.text then return end
    self:_PaintTime(self.running and (GetTime() - self.startTime) or self.span)
end

-- Colour is the only thing a combat transition changes, so it is split out of
-- ApplySettings: running the whole of that on every enter and exit re-applied
-- the font, re-anchored the text and re-measured the frame twice per fight for
-- nothing.
function CT:UpdateCombatColor()
    if not self.text then return end
    local textColor = self.running and self.db.ColorInCombat or self.db.ColorOutOfCombat
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
    if self.running then self:_StartTicker() end

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
-- Attached only for preview: live paint runs off the paint ticker.
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
-- Combat state
---------------------------------------------------------------------------------
-- Pure, so the stop rules can be driven without the game. Actions: "start",
-- "restart" (a boss pulled mid-span), "stop", "reset" (a stop with no chat
-- line) or nil. encounterLive is consulted only out of combat with the mark
-- set, so a caller that skips the read may pass false.
---@param running boolean
---@param inEncounter boolean
---@param event string
---@param inCombat boolean
---@param encounterLive boolean
---@param success number?
---@return boolean running
---@return boolean inEncounter
---@return string? action
function CT.Transition(running, inEncounter, event, inCombat, encounterLive, success)
    if event == "PLAYER_REGEN_DISABLED" then
        if running then return true, inEncounter, nil end
        return true, inEncounter, "start"
    elseif event == "PLAYER_REGEN_ENABLED" or event == "TICK" then
        if inCombat then return running, inEncounter, nil end
        if inEncounter and encounterLive then return running, true, nil end
        if running then return false, false, "stop" end
        return false, false, nil
    elseif event == "ENCOUNTER_START" then
        if running then return true, true, "restart" end
        return false, true, nil
    elseif event == "ENCOUNTER_END" then
        -- A kill ends the span even while the lockdown lingers after it.
        if success == 1 or not inCombat then
            if running then return false, false, "stop" end
            return false, false, nil
        end
        return running, false, nil
    elseif event == "PLAYER_ENTERING_WORLD" then
        if inCombat then
            if running then return true, inEncounter, nil end
            return true, inEncounter, "start"
        end
        if running then return false, false, "reset" end
        return false, false, nil
    end
    return running, inEncounter, nil
end

function CT:_CancelTicker()
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
end

function CT:_StartTicker()
    self:_CancelTicker()
    self.ticker = C_Timer.NewTicker(self.refreshRate or GetRefreshRate(self.db.Format), function()
        self:OnPaintTick()
    end)
end

function CT:_StartSpan()
    self.startTime = GetTime()
    self.lastDisplayedText = ""
    if self.frame then self.frame:Show() end
    self:UpdateCombatColor()
    self:UpdateText()
    self:_StartTicker()
end

function CT:_Step(event, success)
    local inCombat = InCombatLockdown()
    local encounterLive = false
    if not inCombat and self.inEncounter and IsEncounterInProgress then
        encounterLive = IsEncounterInProgress()
    end
    local wasEncounter = self.inEncounter
    local running, inEncounter, action = CT.Transition(self.running, wasEncounter, event, inCombat, encounterLive, success)
    self.running, self.inEncounter = running, inEncounter
    if DEBUG_CT and (action or inEncounter ~= wasEncounter) then
        KE:Print("[CT] " .. event .. " combat=" .. (inCombat and "1" or "0")
            .. " enc=" .. (wasEncounter and "1" or "0") .. " live=" .. (encounterLive and "1" or "0")
            .. " success=" .. tostring(success) .. " -> " .. tostring(action))
    end
    if action == "start" then
        self:_StartSpan()
    elseif action == "restart" then
        self.startTime = GetTime()
        self.lastDisplayedText = ""
        self:UpdateText()
    elseif action == "stop" or action == "reset" then
        self.span = GetTime() - self.startTime
        self:_CancelTicker()
        self:OnStop(action)
    end
end

function CT:OnPaintTick()
    self:_Step("TICK")
    if self.running then self:UpdateText() end
end

-- success is ENCOUNTER_END's fifth payload value:
-- (encounterID, encounterName, difficultyID, groupSize, success).
function CT:OnCombatEvent(event, ...)
    local success
    if event == "ENCOUNTER_END" then success = select(5, ...) end
    self:_Step(event, success)
end

-- A loading screen is not a fight ending.
function CT:OnStop(reason)
    self:UpdateCombatColor()
    self:UpdateText()
    if self.db.ShowChatMessage ~= false and reason ~= "reset" then
        KE:Print("Combat lasted " .. FormatTime(self.span, self.db.Format))
    end
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
    if self.frame and not self.running and not self.db.Enabled then
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
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatEvent")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEvent")
    self:RegisterEvent("ENCOUNTER_START", "OnCombatEvent")
    self:RegisterEvent("ENCOUNTER_END", "OnCombatEvent")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnCombatEvent")
    if self.db.Enabled then self.frame:Show() end
end

function CT:OnDisable()
    if self.frame then
        self:_SetOnUpdateActive(false)
        self.frame:Hide()
    end
    self.isPreview = false
    self:_CancelTicker()
    self.running = false
    self.inEncounter = false
    self:UnregisterAllEvents()
end
