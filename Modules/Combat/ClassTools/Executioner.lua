-- ╔══════════════════════════════════════════════════════════╗
-- ║  Executioner.lua                                         ║
-- ║  Module: Executioner Stacks                              ║
-- ║  Purpose: Shows each Executioner stack and hidden timer  ║
-- ║           of a Slayer warrior, and a cancel cue.         ║
-- ║  Note: Warrior only; live while Slayer's Dominance is    ║
-- ║        known.                                            ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- The game hides the buff's timers in combat, so the stacks are counted from
-- Slayer's Strike procs and set to the real buff whenever it is readable.

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class Executioner: AceModule, AceEvent-3.0
local EX = KitnEssentials:NewModule("Executioner", "AceEvent-3.0")
-- Gates the preview manager.
EX.classRestriction = "WARRIOR"

local Rules = KE.ExecutionerRules
local Ask = KE.PlateSlots.Ask
local IsOwnSpecChange = KE.ShamanProcRules.IsOwnSpecChange
local LCG = LibStub("LibCustomGlow-1.0", true)

local CreateFrame = CreateFrame
local C_Timer = C_Timer
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local UnitClass = UnitClass
local UnitAffectingCombat = UnitAffectingCombat
local GetMacroIndexByName = GetMacroIndexByName
local GetNumMacros = GetNumMacros
local CreateMacro = CreateMacro
local EditMacro = EditMacro
local PickupMacro = PickupMacro
local PlaySoundFile = PlaySoundFile
local ipairs, pcall, tostring, type = ipairs, pcall, tostring, type
local math_max, math_min = math.max, math.min
local string_lower = string.lower
local wipe = wipe

-- Flip to true, /reload, repro, read the log.
local DEBUG_EXE = false

-- Talent state is not reliable on the frame a talent event fires.
local TALENT_EVAL_DELAY = 2
local STEP = 0.05
local WHITE = "Interface\\Buttons\\WHITE8X8"
local MARK_WIDTH, MARK_HEIGHT, MARK_GAP = 26, 13, 3
local ROW_GAP = 4
local HIDDEN_LABEL_WIDTH = 34
local CUE_TEXT_SIZE = 13
local STACK_COLOR = { 0.94, 0.62, 0.15, 1 }
local HIDDEN_COLOR = { 0.89, 0.29, 0.29, 1 }
local CUE_TEXT_COLOR = { 1, 0.82, 0.2, 1 }

-- The documented caps stand in when the constants table is missing.
local MACRO_CONSTS = Constants and Constants.MacroConsts
local MAX_ACCOUNT_MACROS = MACRO_CONSTS and MACRO_CONSTS.MAX_ACCOUNT_MACROS or 120
local MAX_CHARACTER_MACROS = MACRO_CONSTS and MACRO_CONSTS.MAX_CHARACTER_MACROS or 30

local function IsKnown(spellID)
    return Ask(C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook, spellID)
end

local function ModeOf(db)
    local mode = db.DisplayMode
    if mode == "PIPS" or mode == "ICON" or mode == "CUE_ONLY" then return mode end
    return "BARS"
end

local function BuffIcon()
    local getTexture = C_Spell and C_Spell.GetSpellTexture
    if getTexture then
        local ok, icon = pcall(getTexture, Rules.BUFF)
        if ok and not KE:IsSecretValue(icon) and icon then return icon end
    end
    return Rules.CANCEL_ICON
end

local function DeferredEvaluate()
    EX.evalTimer = nil
    if EX:IsEnabled() then EX:Evaluate() end
end

local function RunQueuedCheck()
    EX.checkTimer = nil
    EX:RunCheck()
end

local function RunExpiry()
    EX.expiryTimer = nil
    if not EX:IsEnabled() then return end
    Rules.Expire(EX.state, GetTime())
    EX:ArmExpiry()
    EX:Refresh()
end

---------------------------------------------------------------------------------
-- Fills and seconds
---------------------------------------------------------------------------------
local zeroDuration

-- The engine drains the fill from a plain start and length; no Lua runs per
-- frame for it.
local function StartFill(el, timer)
    el.duration:SetTimeFromStart(timer.ends - timer.len, timer.len)
    el.sb:SetTimerDuration(el.duration, Enum.StatusBarInterpolation.Immediate,
        Enum.StatusBarTimerDirection.RemainingTime)
    el.timer = timer
end

-- A zero duration stops the engine drive; the bar then holds `value`.
local function StopFill(el, value)
    if not zeroDuration then zeroDuration = C_DurationUtil.CreateDuration() end
    el.sb:SetTimerDuration(zeroDuration, Enum.StatusBarInterpolation.Immediate,
        Enum.StatusBarTimerDirection.ElapsedTime)
    el.sb:SetMinMaxValues(0, 1)
    el.sb:SetValue(value or 0)
    el.timer = nil
end

-- Every value here is a number this module computed, never a secret, so the
-- changed-text gate is safe.
local function SetSeconds(el, left)
    local key = Rules.SecondsKey(left)
    if key ~= el.lastKey then
        el.lastKey = key
        el.time:SetText(Rules.Seconds(left))
    end
end

local function NewElement(parent)
    local el = CreateFrame("Frame", nil, parent)
    local bg = el:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(el)
    bg:SetColorTexture(0.06, 0.06, 0.06, 0.85)
    KE:AddIconBorders(el, { 0, 0, 0, 1 })
    -- Inset by the border, which sits on this frame and the bar would cover.
    local px = KE:GetPixelSize()
    local sb = CreateFrame("StatusBar", nil, el)
    sb:SetPoint("TOPLEFT", el, "TOPLEFT", px, -px)
    sb:SetPoint("BOTTOMRIGHT", el, "BOTTOMRIGHT", -px, px)
    sb:SetStatusBarTexture(WHITE)
    sb:SetMinMaxValues(0, 1)
    sb:SetValue(0)
    el.sb = sb
    el.time = sb:CreateFontString(nil, "OVERLAY")
    el.label = sb:CreateFontString(nil, "OVERLAY")
    el.duration = C_DurationUtil.CreateDuration()
    el:Hide()
    return el
end

local function DriverStep(frame, elapsed)
    local acc = frame.acc + elapsed
    if acc < STEP then
        frame.acc = acc
        return
    end
    frame.acc = 0
    local now = GetTime()
    local els = EX.textEls
    for i = 1, #els do
        local el = els[i]
        SetSeconds(el, el.timer.ends - now)
    end
end

---------------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------------
function EX:UpdateDB()
    self.db = KE.db.profile.Executioner
end

function EX:OnInitialize()
    self:UpdateDB()
    self.state = Rules.New()
    self.live, self.isPreview, self.resumePreview = false, false, false
    self.combatEvents, self.glowEvents, self.fighting = false, false, false
    self.driving, self.cueShown, self.cueGlow, self.cueHeld = false, false, false, false
    self.bars, self.textEls, self.testTimers = {}, {}, {}
    self.pinnedPos = {}
    self.secretSeen, self.fixes = 0, 0
    self.testMacro = nil
    -- Clears per cause ("cancel", "death", "key"), apart from corrections,
    -- so a smoke step can tell which path emptied the count.
    self.clears = {}
    self.length = Rules.BASE
    self:SetEnabledState(false)
end

function EX:CreateFrames()
    if self.frame then return end
    local frame = CreateFrame("Frame", "KE_Executioner", UIParent)
    frame:SetSize(1, 1)
    frame:Hide()
    frame.acc = 0
    self.frame = frame
    KE:RegisterAnchorRepair(frame, function()
        return self.db.anchorFrameType == "PLAYERFRAME"
    end, function() self:ApplyPosition() end)

    local cue = CreateFrame("Frame", "KE_ExecutionerCancel", UIParent)
    cue:Hide()
    cue.icon = cue:CreateTexture(nil, "ARTWORK")
    cue.icon:SetAllPoints(cue)
    cue.icon:SetTexture(Rules.CANCEL_ICON)
    KE:ApplyIconZoom(cue.icon)
    KE:AddIconBorders(cue, { 0, 0, 0, 1 })
    cue.text = cue:CreateFontString(nil, "OVERLAY")
    cue.text:SetPoint("TOP", cue, "BOTTOM", 0, -2)
    self.cue = cue
    KE:RegisterAnchorRepair(cue, function()
        return self.db.Cue.anchorFrameType == "PLAYERFRAME"
    end, function() self:ApplyCuePosition() end)
end

-- AceEvent has no unit events; a frame of its own lets the client filter by
-- unit.
function EX:CreateCastFrame()
    if self.castFrame then return end
    local frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", function(_, event, _, _, spellID)
        if event == "UNIT_AURA" then
            self:OnAura()
        else
            self:OnSignal("UNIT_SPELLCAST_SUCCEEDED", spellID)
        end
    end)
    self.castFrame = frame
end

---------------------------------------------------------------------------------
-- Position and Edit Mode
---------------------------------------------------------------------------------
-- The vertical edge is always the top, so a mode change keeps the top in
-- place; the horizontal edge follows the saved anchor.
function EX:PinnedPoint()
    local from = self.db.Position.AnchorFrom or ""
    local horizontal = from:find("LEFT") and "LEFT" or (from:find("RIGHT") and "RIGHT" or "")
    return "TOP" .. horizontal
end

function EX:ApplyPosition()
    local frame, db = self.frame, self.db
    if not frame then return end
    local pos, pinned = db.Position, self.pinnedPos
    pinned.AnchorFrom = self:PinnedPoint()
    pinned.AnchorTo = pos.AnchorTo
    pinned.XOffset = pos.XOffset
    pinned.YOffset = pos.YOffset
    KE:ApplyFramePosition(frame, pinned, db)
end

function EX:ApplyCuePosition()
    if not self.cue then return end
    local cue = self.db.Cue
    KE:ApplyFramePosition(self.cue, cue.Position, cue)
end

function EX:UnregisterTracker()
    KE.EditMode:UnregisterElement("Executioner")
    self.trackerRegistered, self.anchorMode = nil, nil
end

function EX:UnregisterCue()
    KE.EditMode:UnregisterElement("ExecutionerCancel")
    self.cueRegistered = nil
end

function EX:UnregisterAnchors()
    self:UnregisterTracker()
    self:UnregisterCue()
end

function EX:TrackerElement()
    return {
        key = "Executioner",
        displayName = Rules.LABEL,
        frame = self.frame,
        module = self,
        guiPath = "ClassTools",
        guiTab = "Executioner",
        getPosition = function() return self.db.Position end,
        getAnchorFrom = function() return self:PinnedPoint() end,
        getParentFrame = function()
            return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame)
        end,
        setPosition = function(pos)
            local p = self.db.Position
            p.AnchorFrom, p.AnchorTo = pos.AnchorFrom, pos.AnchorTo
            p.XOffset, p.YOffset = pos.XOffset, pos.YOffset
            self:ApplyPosition()
        end,
    }
end

function EX:CueElement()
    return {
        key = "ExecutionerCancel",
        displayName = Rules.LABEL .. " Cancel Icon",
        frame = self.cue,
        module = self,
        guiPath = "ClassTools",
        guiTab = "Executioner",
        getPosition = function() return self.db.Cue.Position end,
        getParentFrame = function()
            local cue = self.db.Cue
            return KE:ResolveAnchorFrame(cue.anchorFrameType, cue.ParentFrame)
        end,
        setPosition = function(pos)
            local p = self.db.Cue.Position
            p.AnchorFrom, p.AnchorTo = pos.AnchorFrom, pos.AnchorTo
            p.XOffset, p.YOffset = pos.XOffset, pos.YOffset
            self:ApplyCuePosition()
        end,
    }
end

-- Registering the same frame again would cancel a drag in progress, so only
-- a mode change, which resizes the box, registers the tracker again.
function EX:RegisterAnchors()
    if not self.frame then return end
    local active = self.live or self.isPreview
    local mode = ModeOf(self.db)
    if active and mode ~= "CUE_ONLY" then
        if self.trackerRegistered and self.anchorMode ~= mode then self:UnregisterTracker() end
        if not self.trackerRegistered then
            KE.EditMode:RegisterElement(self:TrackerElement())
            self.trackerRegistered, self.anchorMode = true, mode
        end
    else
        self:UnregisterTracker()
    end
    if active and self.db.Cue.Enabled then
        if not self.cueRegistered then
            KE.EditMode:RegisterElement(self:CueElement())
            self.cueRegistered = true
        end
    else
        self:UnregisterCue()
    end
end

---------------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------------
function EX:GetRoot(key)
    local root = self[key]
    if not root then
        root = CreateFrame("Frame", nil, self.frame)
        root:SetAllPoints(self.frame)
        root:Hide()
        self[key] = root
    end
    return root
end

function EX:StyleText(el, size)
    local db = self.db
    KE:ApplyFontToText(el.time, db.FontFace, size, db.FontOutline)
    KE:ApplyFontToText(el.label, db.FontFace, size, db.FontOutline)
    el.lastKey, el.kind, el.timer, el.empty = nil, nil, nil, nil
end

function EX:StyleCentered(el, size)
    self:StyleText(el, size)
    el.time:ClearAllPoints()
    el.time:SetPoint("CENTER", el.sb, "CENTER", 0, 0)
    el.time:SetShown(self.db.ShowSeconds ~= false)
    el.label:Hide()
end

function EX:StyleBar(el, i)
    local db = self.db
    local height, gap = db.BarHeight or 14, db.Spacing or 2
    local step = (i - 1) * (height + gap)
    el:SetSize(db.BarWidth or 180, height)
    el:ClearAllPoints()
    if db.GrowDirection == "UP" then
        el:SetPoint("BOTTOMLEFT", self.barsRoot, "BOTTOMLEFT", 0, step)
    else
        el:SetPoint("TOPLEFT", self.barsRoot, "TOPLEFT", 0, -step)
    end
    self:StyleText(el, db.FontSize or 11)
    el.time:ClearAllPoints()
    el.time:SetPoint("RIGHT", el.sb, "RIGHT", -3, 0)
    el.label:ClearAllPoints()
    el.label:SetPoint("LEFT", el.sb, "LEFT", 3, 0)
    el.time:SetShown(db.ShowSeconds ~= false)
    el.label:SetShown(db.ShowLabels ~= false)
end

function EX:GetBar(i)
    local el = self.bars[i]
    if not el then
        el = NewElement(self.barsRoot)
        self.bars[i] = el
        self:StyleBar(el, i)
    end
    return el
end

-- The box keeps room for every bar the mode can draw, so a timer appearing
-- or ending never moves the others.
function EX:LayoutBars()
    local db = self.db
    local root = self:GetRoot("barsRoot")
    local height, gap = db.BarHeight or 14, db.Spacing or 2
    local slots = db.ShowHidden ~= false and Rules.MAX_BARS or Rules.CAP
    self.frame:SetSize(db.BarWidth or 180, height * slots + gap * (slots - 1))
    for i, el in ipairs(self.bars) do self:StyleBar(el, i) end
    root:Show()
end

function EX:CreatePips()
    if self.pips then return end
    local root = self:GetRoot("pipsRoot")
    local pips = { segs = {}, marks = {} }
    pips.count = root:CreateFontString(nil, "OVERLAY")
    pips.hiddenLabel = root:CreateFontString(nil, "OVERLAY")
    for i = 1, Rules.CAP do pips.segs[i] = NewElement(root) end
    for j = 1, Rules.MAX_MARKS do pips.marks[j] = NewElement(root) end
    self.pips = pips
end

function EX:LayoutPips()
    self:CreatePips()
    local db, pips, root = self.db, self.pips, self.pipsRoot
    local pw, ph, gap = db.PipWidth or 34, db.PipHeight or 18, db.PipSpacing or 3
    local size = db.FontSize or 11
    local markSize = math_max(6, size - 1)
    local showHidden = db.ShowHidden ~= false
    local countW = db.ShowStackCount ~= false and (ph + 8) or 0
    local segX = countW > 0 and countW + 6 or 0
    local segRow = segX + Rules.CAP * pw + (Rules.CAP - 1) * gap
    local hiddenRow = segX + HIDDEN_LABEL_WIDTH + Rules.MAX_MARKS * MARK_WIDTH + (Rules.MAX_MARKS - 1) * MARK_GAP
    local width = showHidden and math_max(segRow, hiddenRow) or segRow
    local height = showHidden and (ph + ROW_GAP + MARK_HEIGHT) or ph
    self.frame:SetSize(width, height)

    KE:ApplyFontToText(pips.count, db.FontFace, ph + 8, db.FontOutline)
    pips.count:ClearAllPoints()
    pips.count:SetPoint("CENTER", root, "TOPLEFT", countW / 2, -ph / 2)
    pips.count:SetShown(countW > 0)
    pips.lastCount = nil

    local sr, sg, sb, sa = KE:ResolveColor(db.StackColor, STACK_COLOR)
    for i, el in ipairs(pips.segs) do
        el:SetSize(pw, ph)
        el:ClearAllPoints()
        el:SetPoint("TOPLEFT", root, "TOPLEFT", segX + (i - 1) * (pw + gap), 0)
        self:StyleCentered(el, size)
        el.sb:SetStatusBarColor(sr, sg, sb, sa)
        el:Show()
    end

    KE:ApplyFontToText(pips.hiddenLabel, db.FontFace, markSize, db.FontOutline)
    pips.hiddenLabel:ClearAllPoints()
    pips.hiddenLabel:SetPoint("LEFT", root, "TOPLEFT", segX, -(ph + ROW_GAP + MARK_HEIGHT / 2))
    pips.hiddenLabel:SetText("hidden")
    pips.hiddenLabel:Hide()
    local hr, hg, hb, ha = KE:ResolveColor(db.HiddenColor, HIDDEN_COLOR)
    for j, el in ipairs(pips.marks) do
        el:SetSize(MARK_WIDTH, MARK_HEIGHT)
        el:ClearAllPoints()
        el:SetPoint("TOPLEFT", root, "TOPLEFT",
            segX + HIDDEN_LABEL_WIDTH + (j - 1) * (MARK_WIDTH + MARK_GAP), -(ph + ROW_GAP))
        self:StyleCentered(el, markSize)
        el.sb:SetStatusBarColor(hr, hg, hb, ha)
        el:Hide()
    end
    root:Show()
end

function EX:CreateIcon()
    if self.iconEl then return end
    local root = self:GetRoot("iconRoot")
    local ic = CreateFrame("Frame", nil, root)
    ic:SetAllPoints(root)
    ic.tex = ic:CreateTexture(nil, "ARTWORK")
    ic.tex:SetAllPoints(ic)
    ic.tex:SetTexture(BuffIcon())
    KE:ApplyIconZoom(ic.tex)
    KE:AddIconBorders(ic, { 0, 0, 0, 1 })
    ic.cooldown = CreateFrame("Cooldown", nil, ic, "CooldownFrameTemplate")
    ic.cooldown:SetAllPoints(ic)
    ic.cooldown:SetDrawEdge(false)
    ic.cooldown:SetDrawSwipe(true)
    ic.cooldown:SetDrawBling(false)
    ic.cooldown:SetCountdownMillisecondsThreshold(3)
    -- Above the swipe, so the count and badge are never darkened.
    local overlay = CreateFrame("Frame", nil, ic)
    overlay:SetAllPoints(ic)
    overlay:SetFrameLevel(ic.cooldown:GetFrameLevel() + 1)
    ic.count = overlay:CreateFontString(nil, "OVERLAY")
    ic.count:SetPoint("BOTTOMRIGHT", ic, "BOTTOMRIGHT", -2, 1)
    ic.badge = CreateFrame("Frame", nil, overlay)
    ic.badge:SetPoint("CENTER", ic, "TOPRIGHT", 0, 0)
    ic.badge.bg = ic.badge:CreateTexture(nil, "BACKGROUND")
    ic.badge.bg:SetAllPoints(ic.badge)
    ic.badgeText = ic.badge:CreateFontString(nil, "OVERLAY")
    ic.badgeText:SetPoint("CENTER", ic.badge, "CENTER", 0, 0)
    ic.badge:Hide()
    self.iconEl = ic
end

function EX:LayoutIcon()
    self:CreateIcon()
    local db, ic = self.db, self.iconEl
    local size, font = db.IconSize or 46, db.FontSize or 11
    self.frame:SetSize(size, size)
    ic.cooldown:SetHideCountdownNumbers(db.ShowSeconds == false)
    KE:ApplyCooldownTextStyle(ic.cooldown, db.FontFace, font + 3, db.FontOutline)
    KE:ApplyFontToText(ic.count, db.FontFace, font + 7, db.FontOutline)
    KE:ApplyFontToText(ic.badgeText, db.FontFace, font + 1, db.FontOutline)
    local hr, hg, hb = KE:ResolveColor(db.HiddenColor, HIDDEN_COLOR)
    ic.badge.bg:SetColorTexture(hr, hg, hb, 1)
    ic.badge:SetSize(font + 12, font + 5)
    ic.timer, ic.lastCount, ic.lastHidden = nil, nil, nil
    self.iconRoot:Show()
end

function EX:StyleCue()
    local cue, c, db = self.cue, self.db.Cue, self.db
    local size = c.Size or 44
    cue:SetSize(size, size)
    KE:ApplyFontToText(cue.text, db.FontFace, CUE_TEXT_SIZE, db.FontOutline)
    local r, g, b, a = KE:ResolveColor(c.TextColor, CUE_TEXT_COLOR)
    cue.text:SetTextColor(r, g, b, a)
    cue.text:SetText("Cancel")
    cue.text:SetShown(c.ShowText ~= false)
    -- A running glow keeps its old settings; the next cue update restarts it.
    if self.cueGlow then self:SetCueGlow(false) end
end

-- Only the chosen mode's child frame is shown; the others get no calls.
function EX:ApplyLayout()
    if not self.frame then return end
    local mode = ModeOf(self.db)
    self.shownMode = mode
    if self.barsRoot then self.barsRoot:Hide() end
    if self.pipsRoot then self.pipsRoot:Hide() end
    if self.iconRoot then self.iconRoot:Hide() end
    if mode == "BARS" then
        self:LayoutBars()
    elseif mode == "PIPS" then
        self:LayoutPips()
    elseif mode == "ICON" then
        self:LayoutIcon()
    end
    self:ApplyPosition()
    self:StyleCue()
    self:ApplyCuePosition()
end

---------------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------------
-- The preview holds still: its fills stop at the sample's value.
function EX:Fill(el, timer, now)
    if self.isPreview then
        StopFill(el, (timer.ends - now) / timer.len)
    elseif el.timer ~= timer then
        StartFill(el, timer)
    end
end

function EX:DrawBars(state, now)
    local db = self.db
    local timers, stacks = state.timers, state.stacks
    local n = db.ShowHidden ~= false and #timers or stacks
    if n > Rules.MAX_BARS then n = Rules.MAX_BARS end
    local showSeconds = db.ShowSeconds ~= false
    local textEls = self.textEls
    wipe(textEls)
    for i = 1, n do
        local el, timer = self:GetBar(i), timers[i]
        local kind = i <= stacks and "stack" or "hidden"
        if el.kind ~= kind then
            el.kind = kind
            local r, g, b, a
            if kind == "stack" then
                r, g, b, a = KE:ResolveColor(db.StackColor, STACK_COLOR)
            else
                r, g, b, a = KE:ResolveColor(db.HiddenColor, HIDDEN_COLOR)
            end
            el.sb:SetStatusBarColor(r, g, b, a)
            el.label:SetText(kind == "stack" and tostring(i) or "hidden")
        end
        self:Fill(el, timer, now)
        if showSeconds then
            SetSeconds(el, timer.ends - now)
            textEls[#textEls + 1] = el
        end
        el:Show()
    end
    for i = n + 1, #self.bars do self.bars[i]:Hide() end
end

function EX:DrawPips(state, now)
    local db, pips = self.db, self.pips
    local timers, stacks = state.timers, state.stacks
    local showSeconds = db.ShowSeconds ~= false
    local textEls = self.textEls
    wipe(textEls)
    for i = 1, Rules.CAP do
        local el = pips.segs[i]
        local timer = i <= stacks and timers[i] or nil
        if timer then
            el.empty = false
            self:Fill(el, timer, now)
            if showSeconds then
                SetSeconds(el, timer.ends - now)
                textEls[#textEls + 1] = el
            end
        elseif not el.empty then
            StopFill(el, 0)
            el.empty = true
            el.time:SetText("")
            el.lastKey = nil
        end
    end
    local marks = 0
    if db.ShowHidden ~= false then marks = math_min(Rules.MAX_MARKS, #timers - stacks) end
    for j = 1, Rules.MAX_MARKS do
        local el = pips.marks[j]
        if j <= marks then
            local timer = timers[stacks + j]
            self:Fill(el, timer, now)
            if showSeconds then
                SetSeconds(el, timer.ends - now)
                textEls[#textEls + 1] = el
            end
            el:Show()
        else
            el:Hide()
        end
    end
    pips.hiddenLabel:SetShown(marks > 0)
    if pips.lastCount ~= stacks then
        pips.lastCount = stacks
        pips.count:SetText(tostring(stacks))
    end
end

function EX:DrawIcon(state)
    local db, ic = self.db, self.iconEl
    wipe(self.textEls)
    local first = state.timers[1]
    if first and ic.timer ~= first then
        ic.cooldown:SetCooldown(first.ends - first.len, first.len)
        ic.timer = first
    end
    local stacks = state.stacks
    if ic.lastCount ~= stacks then
        ic.lastCount = stacks
        ic.count:SetText(tostring(stacks))
    end
    local hidden = Rules.Hidden(state)
    if db.ShowHidden ~= false and hidden > 0 then
        if ic.lastHidden ~= hidden then
            ic.lastHidden = hidden
            ic.badgeText:SetText("+" .. hidden)
        end
        ic.badge:Show()
    else
        ic.badge:Hide()
    end
end

function EX:Draw(mode, state, now)
    if mode == "PIPS" then
        self:DrawPips(state, now)
    elseif mode == "ICON" then
        self:DrawIcon(state)
    else
        self:DrawBars(state, now)
    end
end

function EX:StopDriver()
    wipe(self.textEls)
    if self.driving then
        self.driving = false
        self.frame:SetScript("OnUpdate", nil)
    end
end

-- Attached only while Bars or Pips show seconds for at least one timer.
function EX:SyncDriver(mode)
    local want = (mode == "BARS" or mode == "PIPS") and #self.textEls > 0
    if want == self.driving then return end
    self.driving = want
    if want then
        self.frame.acc = 0
        self.frame:SetScript("OnUpdate", DriverStep)
    else
        self.frame:SetScript("OnUpdate", nil)
    end
end

function EX:Testing()
    return self.testUntil ~= nil and GetTime() < self.testUntil
end

function EX:CombatAllows()
    return Rules.CombatAllows(self.db.OnlyInCombat == true, self.fighting == true, self:Testing())
end

function EX:TrackerVisible(mode)
    return mode ~= "CUE_ONLY" and (self.live or self:Testing())
        and #self.state.timers > 0 and self:CombatAllows()
end

function EX:Refresh()
    if self.isPreview or not self.frame then return end
    local mode = ModeOf(self.db)
    if self.shownMode ~= mode then self:ApplyLayout() end
    local now = GetTime()
    local state = self.state
    Rules.Expire(state, now)
    self:UpdateCue(now)
    if not self:TrackerVisible(mode) then
        self.frame:Hide()
        self:StopDriver()
        return
    end
    self:Draw(mode, state, now)
    self.frame:Show()
    self:SyncDriver(mode)
end

---------------------------------------------------------------------------------
-- Cancel cue
---------------------------------------------------------------------------------
function EX:SuddenDeathUp()
    local overlay = C_SpellActivationOverlay
    local check = overlay and overlay.IsSpellOverlayed
    if not check then return false end
    for _, id in ipairs(Rules.EXECUTES) do
        if Ask(check, id) == true then return true end
    end
    return false
end

function EX:SetCueGlow(on)
    self.cueGlow = on
    if not (LCG and self.cue) then return end
    if on then
        local c = self.db.Cue
        LCG.PixelGlow_Start(self.cue, c.GlowColor, c.GlowLines, c.GlowFrequency,
            c.GlowLength, c.GlowThickness, 0, 0, true, nil)
    else
        LCG.PixelGlow_Stop(self.cue)
    end
end

function EX:PlayCueSound(now)
    local sound = self.db.Cue.Sound
    if not sound or sound == "None" or not KE.LSM then return end
    if not Rules.SoundDue(self.cueSoundAt, now) then return end
    self.cueSoundAt = now
    local path = KE.LSM:Fetch("sound", sound, true)
    if path then pcall(PlaySoundFile, path, "Master") end
end

function EX:UpdateCue(now)
    local cue = self.cue
    if not cue then return end
    local c = self.db.Cue
    local shown, held = false, false
    if self.isPreview then
        shown = c.Enabled == true
    elseif c.Enabled and (self.live or self:Testing()) and self:CombatAllows() then
        local state = self.state
        local wanted = Rules.CueWanted(state.stacks, Rules.Hidden(state))
        local waitSD = c.WaitSuddenDeath == true
        local sdUp = wanted and waitSD and self:SuddenDeathUp() or false
        shown, held = Rules.CueState(wanted, waitSD, sdUp)
    end
    if DEBUG_EXE and held ~= self.cueHeld then
        KE:Print("[EXE] cue " .. (held and "held for Sudden Death" or "no longer held"))
    end
    self.cueHeld = held
    if shown ~= self.cueShown then
        self.cueShown = shown
        cue:SetShown(shown)
        if shown and not self.isPreview then self:PlayCueSound(now) end
    end
    local glow = shown and c.GlowEnabled ~= false
    if glow ~= self.cueGlow then self:SetCueGlow(glow) end
end

---------------------------------------------------------------------------------
-- Counting
---------------------------------------------------------------------------------
function EX:ArmExpiry()
    if self.expiryTimer then
        self.expiryTimer:Cancel()
        self.expiryTimer = nil
    end
    local first = self.state.timers[1]
    if not first then return end
    local wait = first.ends + Rules.LAG - GetTime()
    if wait < 0 then wait = 0 end
    self.expiryTimer = C_Timer.NewTimer(wait, RunExpiry)
end

function EX:OnSignal(event, spellID)
    if KE:IsSecretValue(spellID) then
        self.secretSeen = self.secretSeen + 1
        return
    end
    local door = Rules.DoorFor(event, spellID, false)
    if not door then return end
    local state = self.state
    local result = Rules.Signal(state, door, GetTime(), self.length, self.ignoreUntil)
    if DEBUG_EXE then
        KE:Print(("[EXE] %s: %s, %d +%d"):format(door, result, state.stacks, Rules.Hidden(state)))
    end
    if result == "counted" then
        self:ArmExpiry()
        self:Refresh()
    end
end

function EX:OnCooldownPing(_, spellID)
    self:OnSignal("SPELL_UPDATE_COOLDOWN", spellID)
end

function EX:OnAura()
    if self.checkTimer or KE:IsAuraHiddenForSpell(Rules.BUFF) then return end
    self.checkTimer = C_Timer.NewTimer(Rules.CHECK_DELAY, RunQueuedCheck)
end

function EX:CancelCheck()
    if self.checkTimer then
        self.checkTimer:Cancel()
        self.checkTimer = nil
    end
end

function EX:RunCheck()
    if not self.live then return end
    local now = GetTime()
    local state = self.state
    local changed = Rules.Expire(state, now)
    if Rules.CheckAllowed(state, now, self.testUntil) and not KE:IsAuraHiddenForSpell(Rules.BUFF) then
        local getAura = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
        local aura = getAura and getAura(Rules.BUFF)
        if not KE:IsSecretValue(aura) then
            local applications = aura and aura.applications
            local n = Rules.ReadStacks(false, aura, applications, KE:IsSecretValue(applications))
            if n then
                local counted = state.stacks
                if DEBUG_EXE then KE:Print(("[EXE] check: counted %d, real %d"):format(counted, n)) end
                if Rules.Correct(state, n, now, self.length) then
                    self.fixes = self.fixes + 1
                    changed = true
                end
            end
        end
    end
    if changed then
        self:ArmExpiry()
        self:Refresh()
    end
end

function EX:Clear(why)
    local state = self.state
    if #state.timers == 0 and state.stacks == 0 then return end
    Rules.Wipe(state)
    self.clears[why] = (self.clears[why] or 0) + 1
    if DEBUG_EXE then KE:Print("[EXE] cleared: " .. why) end
    self:ArmExpiry()
    self:Refresh()
end

function EX:OnDead()
    self:Clear("death")
end

function EX:OnKeyStart()
    self:Clear("key")
end

function EX:OnCombatChange(event)
    self.fighting = event == "PLAYER_REGEN_DISABLED"
    self:Refresh()
end

function EX:OnGlowChange()
    if #self.state.timers > 0 then self:Refresh() end
end

---------------------------------------------------------------------------------
-- Cancel hooks
---------------------------------------------------------------------------------
local hooksInstalled = false
local buffNameLower

local function OnCancel(spell)
    if not (EX:IsEnabled() and EX.live) then return end
    if not buffNameLower then
        local getName = C_Spell and C_Spell.GetSpellName
        if getName then
            local ok, name = pcall(getName, Rules.BUFF)
            if ok and not KE:IsSecretValue(name) and type(name) == "string" and name ~= "" then
                buffNameLower = string_lower(name)
            end
        end
    end
    if Rules.IsBuffCancel(spell, KE:IsSecretValue(spell), buffNameLower) then
        EX:Clear("cancel")
    end
end

-- Post-hooks cannot be removed, so they stay installed and return at once
-- while the module is off.
local function InstallHooks()
    if hooksInstalled then return end
    hooksInstalled = true
    if type(CancelSpellByName) == "function" then
        hooksecurefunc("CancelSpellByName", OnCancel)
    end
    if C_Spell and C_Spell.CancelSpellByID then
        hooksecurefunc(C_Spell, "CancelSpellByID", OnCancel)
    end
end

---------------------------------------------------------------------------------
-- Activation
---------------------------------------------------------------------------------
function EX:SyncOptionalEvents()
    local db = self.db
    local wantCombat = self.live and db.OnlyInCombat == true
    if wantCombat ~= self.combatEvents then
        self.combatEvents = wantCombat
        if wantCombat then
            self.fighting = Ask(UnitAffectingCombat, "player") == true
            self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatChange")
            self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatChange")
        else
            self:UnregisterEvent("PLAYER_REGEN_DISABLED")
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        end
    end
    local c = db.Cue
    local wantGlow = self.live and c.Enabled == true and c.WaitSuddenDeath == true
    if wantGlow ~= self.glowEvents then
        self.glowEvents = wantGlow
        if wantGlow then
            self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "OnGlowChange")
            self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", "OnGlowChange")
        else
            self:UnregisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
            self:UnregisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
        end
    end
end

-- Going live opens the ignore window too: the cooldown event can be
-- registered in the middle of a login burst.
function EX:SetLive(on)
    if on ~= self.live then
        self.live = on
        if on then
            self.state = Rules.New()
            self.ignoreUntil = GetTime() + Rules.ZONE_IN_IGNORE
            self:CreateCastFrame()
            self.castFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
            self.castFrame:RegisterUnitEvent("UNIT_AURA", "player")
            self:RegisterEvent("SPELL_UPDATE_COOLDOWN", "OnCooldownPing")
            self:RegisterEvent("PLAYER_DEAD", "OnDead")
            self:RegisterEvent("CHALLENGE_MODE_START", "OnKeyStart")
            InstallHooks()
        else
            if self.castFrame then self.castFrame:UnregisterAllEvents() end
            self:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
            self:UnregisterEvent("PLAYER_DEAD")
            self:UnregisterEvent("CHALLENGE_MODE_START")
            Rules.Wipe(self.state)
            self:ArmExpiry()
            self:CancelCheck()
        end
    end
    self:SyncOptionalEvents()
end

function EX:Evaluate()
    if not self:IsEnabled() then return end
    local _, class = UnitClass("player")
    local live = class == "WARRIOR" and IsKnown(Rules.DOMINANCE) == true
    self.length = Rules.Length(IsKnown(Rules.FOCUS) == true)
    if live then
        self:CreateFrames()
        self:SetLive(true)
        if not self.isPreview then self:ApplyLayout() end
        self:RegisterAnchors()
    else
        self:SetLive(false)
        if not self.isPreview then self:UnregisterAnchors() end
    end
    self:Refresh()
end

-- One talent change fires several events; Evaluate runs once, after the last.
function EX:OnTalentChanged()
    if self.evalTimer then self.evalTimer:Cancel() end
    self.evalTimer = C_Timer.NewTimer(TALENT_EVAL_DELAY, DeferredEvaluate)
end

function EX:OnSpecChanged(_, unit)
    if IsOwnSpecChange(unit, KE:IsSecretValue(unit)) then
        self:OnTalentChanged()
    end
end

-- Timers keep running across a zone change; only the re-announce burst is
-- ignored. With nothing live it re-reads talents, since at a cold login both
-- enable-time reads can land before talents are readable.
function EX:OnEnteringWorld()
    self.ignoreUntil = GetTime() + Rules.ZONE_IN_IGNORE
    if not self.live then self:OnTalentChanged() end
end

function EX:ApplySettings()
    self:UpdateDB()
    if self.db.Enabled then
        if not self:IsEnabled() then
            KitnEssentials:EnableModule("Executioner")
        elseif self.isPreview then
            self:SyncOptionalEvents()
            -- Refresh returns early while previewing, so repaint the preview.
            self:ShowPreview()
        else
            self:SyncOptionalEvents()
            self:ApplyLayout()
            self:RegisterAnchors()
            self:Refresh()
        end
    elseif self:IsEnabled() then
        KitnEssentials:DisableModule("Executioner")
    end
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function EX:OnEnable()
    self:UpdateDB()
    -- Class before anything else: a non-warrior gets no events, frame or mover.
    local _, class = UnitClass("player")
    if class ~= "WARRIOR" then return end

    self:RegisterEvent("PLAYER_TALENT_UPDATE", "OnTalentChanged")
    self:RegisterEvent("TRAIT_CONFIG_UPDATED", "OnTalentChanged")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnSpecChanged")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnteringWorld")
    self:Evaluate()
    -- At login the talents may not be readable yet; a second pass catches them.
    self:OnTalentChanged()
end

function EX:OnDisable()
    self:UnregisterAllEvents()
    if self.castFrame then self.castFrame:UnregisterAllEvents() end
    self.live, self.combatEvents, self.glowEvents = false, false, false
    if self.expiryTimer then
        self.expiryTimer:Cancel()
        self.expiryTimer = nil
    end
    if self.evalTimer then
        self.evalTimer:Cancel()
        self.evalTimer = nil
    end
    self:CancelCheck()
    for _, timer in ipairs(self.testTimers) do timer:Cancel() end
    wipe(self.testTimers)
    self.testUntil = nil
    Rules.Wipe(self.state)
    self.isPreview, self.resumePreview = false, false
    if self.frame then
        self:StopDriver()
        self.frame:Hide()
    end
    if self.cue then self.cue:Hide() end
    self.cueShown = false
    if self.cueGlow then self:SetCueGlow(false) end
    self:UnregisterAnchors()
end

---------------------------------------------------------------------------------
-- Preview (PreviewManager contract), test run, status, macro
---------------------------------------------------------------------------------
function EX:PreviewState(now)
    local state = Rules.New()
    local length = Rules.BASE + Rules.FOCUS_ADD
    for i, left in ipairs(Rules.PREVIEW_LEFT) do
        state.timers[i] = { ends = now + left, len = length }
    end
    state.stacks = Rules.PREVIEW_STACKS
    return state
end

-- A placement sample: it ignores the talent, the count and Only in Combat.
function EX:ShowPreview()
    self:UpdateDB()
    self:CreateFrames()
    self.isPreview = true
    self:StopDriver()
    self:ApplyLayout()
    local now = GetTime()
    local mode = self.shownMode
    if mode == "CUE_ONLY" then
        self.frame:Hide()
    else
        self:Draw(mode, self:PreviewState(now), now)
        self.frame:Show()
    end
    self:UpdateCue(now)
    self:RegisterAnchors()
end

-- Also called on a disabled module during section changes, so every path is
-- safe without a live display.
function EX:HidePreview()
    self.isPreview, self.resumePreview = false, false
    if self:IsEnabled() then
        self:Evaluate()
        return
    end
    if self.frame then self.frame:Hide() end
    if self.cue then
        self.cue:Hide()
        self.cueShown = false
        if self.cueGlow then self:SetCueGlow(false) end
    end
    self:UnregisterAnchors()
end

-- Sample procs on any class; real procs on a live Slayer still count.
function EX:Test()
    self:UpdateDB()
    self:CreateFrames()
    -- The preview manager still counts the page's preview as shown and
    -- will not call ShowPreview again, so the test brings it back.
    if self.isPreview then self.resumePreview = true end
    self.isPreview = false
    for _, timer in ipairs(self.testTimers) do timer:Cancel() end
    wipe(self.testTimers)
    Rules.Wipe(self.state)
    local now = GetTime()
    local length = Rules.Length(IsKnown(Rules.FOCUS) == true)
    self.testUntil = now + Rules.TEST_AT[#Rules.TEST_AT] + length + 1
    for _, at in ipairs(Rules.TEST_AT) do
        self.testTimers[#self.testTimers + 1] = C_Timer.NewTimer(at, function()
            Rules.Proc(self.state, GetTime(), length)
            self:ArmExpiry()
            self:Refresh()
        end)
    end
    self.testTimers[#self.testTimers + 1] = C_Timer.NewTimer(self.testUntil - now + 0.05, function()
        self.testUntil = nil
        wipe(self.testTimers)
        if self.resumePreview then
            self.resumePreview = false
            self:ShowPreview()
        else
            self:Refresh()
        end
    end)
    self:ApplyLayout()
    self:Refresh()
end

function EX:TalentStatus()
    return IsKnown(Rules.DOMINANCE) == true, Rules.Length(IsKnown(Rules.FOCUS) == true)
end

-- Returns success and the line the page prints.
function EX:CreateCancelMacro()
    local name, icon, body = Rules.MACRO_NAME, Rules.CANCEL_ICON, Rules.MACRO_BODY
    -- Set only by a smoke macro: reaches the paths that need full lists or a
    -- failed write.
    local override = self.testMacro
    local maxGeneral = override and override.maxGeneral or MAX_ACCOUNT_MACROS
    local maxCharacter = override and override.maxCharacter or MAX_CHARACTER_MACROS
    local index = GetMacroIndexByName(name)
    local numGeneral, numCharacter = GetNumMacros()
    local plan = Rules.MacroPlan(InCombatLockdown(), index, numGeneral, numCharacter, maxGeneral, maxCharacter)
    if plan == "combat" then return false, "Not in combat." end
    if plan == "full" then return false, "No free macro slot." end
    local ok, err
    if override and override.fail then
        ok, err = false, "test failure"
    elseif plan == "edit" then
        ok, err = pcall(EditMacro, index, name, icon, body)
    else
        ok, err = pcall(CreateMacro, name, icon, body, plan == "character")
    end
    index = GetMacroIndexByName(name)
    if not ok or not index or index == 0 then
        return false, "Could not save the macro: " .. tostring(err)
    end
    PickupMacro(index)
    return true, "\"" .. name .. "\" is on your cursor: drop it on a bar."
end
