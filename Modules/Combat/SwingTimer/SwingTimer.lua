-- ╔══════════════════════════════════════════════════════════╗
-- ║  SwingTimer.lua                                          ║
-- ║  Module: Swing Timer                                     ║
-- ║  Purpose: One bar per weapon on the game's swing event.  ║
-- ║           The engine draws fill and countdown; KE code   ║
-- ║           runs only on events and timer edges.           ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class SwingTimer: AceModule, AceEvent-3.0
local ST = KitnEssentials:NewModule("SwingTimer", "AceEvent-3.0")
local H = KE.CastbarHelpers
local R = KE.SwingTimerRules
local PROOF = R.PROOF

local C_Timer = C_Timer
local CreateFrame = CreateFrame
local GetTime = GetTime
local ipairs, pcall, select = ipairs, pcall, select

local WEAPON_KEYS = { "MH", "OH", "R" }
local SWING_TYPE = { MH = 0, OH = 1, R = 2 }
local SPEED_RETURN = { MH = 1, OH = 2, R = 3 }
local BASE_COLOR = { MH = "ColorMH", OH = "ColorOH", R = "ColorR" }
local AUTO_ATTACK_SPELL = 6603
local MAX_ACTION_SLOTS = 180
local BLIZZARD_CVAR = "showSwingTimer"
local PREVIEW_TIME = "1.4"
local TEXT_UPDATE_SECONDS = 0.05
local POSITION_RETRY_SECONDS = 0.5
local SPARK_WIDTH = 12
local WHITE = { 1, 1, 1, 1 }
local RANGE_RED = { 0.95, 0.20, 0.20, 1 }
local EDITMODE_OPTS = { key = "SwingTimer", displayName = "Swing Timer", guiPath = "SwingTimer" }
-- Forever's own event, absent from the retail docs the drift check reads.
local RANGE_EVENT = "PLAYER_SWING_RANGE_UPDATE"
local ENABLED_EVENTS = {
    "PLAYER_SWING", "WEAPON_SLOT_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_DEAD",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTER_COMBAT", "PLAYER_LEAVE_COMBAT",
    "START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL",
}

local function FillDirection(deplete)
    local direction = Enum.StatusBarTimerDirection
    return deplete and direction.RemainingTime or direction.ElapsedTime
end

local function WorldLatency()
    local _, _, home, world = GetNetStats()
    if KE:IsSecretValue(home) or KE:IsSecretValue(world) then return 0 end
    local ms = (world and world > 0) and world or home
    return (ms or 0) / 1000
end

local function BlizzardCVarOn()
    local value = C_CVar.GetCVar(BLIZZARD_CVAR)
    -- An unreadable setting counts as on, so the shared range flag is left alone.
    if KE:IsSecretValue(value) then return true end
    return value ~= nil and value ~= "0"
end

local function BuildFormatter()
    if not (C_DurationUtil.CreateDurationTextBinding and C_StringUtil and C_StringUtil.CreateNumericRuleFormatter
        and Enum.NumericRuleFormatRounding) then
        return nil
    end
    local formatter = C_StringUtil.CreateNumericRuleFormatter()
    local ok = pcall(formatter.AddBreakpoint, formatter, {
        threshold = 0, step = 0.1, rounding = Enum.NumericRuleFormatRounding.Up, format = "%.1f",
    })
    return ok and formatter or nil
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function ST:UpdateDB()
    self.db = KE.db.profile.SwingTimer
end

function ST:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function ST:RefuseMissingApi()
    self.apiMissing = true
    KE:Print("Swing Timer needs a game timer this client does not have, so it stays idle.")
end

function ST:OnEnable()
    if not self.db.Enabled then return end
    if not (C_DurationUtil and C_DurationUtil.CreateDuration
        and Enum.StatusBarTimerDirection and Enum.StatusBarInterpolation) then
        self:RefuseMissingApi()
        return
    end
    self:CreateFrame()
    if not self.bars.MH.bar.SetTimerDuration then
        self:RefuseMissingApi()
        return
    end
    -- A frame built under another profile keeps that profile's look otherwise:
    -- the profile manager leaves a newly enabled module to apply its own settings.
    for _, row in ipairs(self.rows) do self:StyleBar(row) end
    self:ApplyPosition()
    self:RegWithEditMode()
    self:CancelPositionTimer()
    self.positionTimer = C_Timer.NewTimer(POSITION_RETRY_SECONDS, function()
        self.positionTimer = nil
        self:ApplyPosition()
    end)

    for _, event in ipairs(ENABLED_EVENTS) do self:RegisterEvent(event) end
    if not self.unitEvents then
        local f = CreateFrame("Frame")
        f:SetScript("OnEvent", function(_, event, ...)
            self[event](self, event, ...)
        end)
        self.unitEvents = f
    end
    self.unitEvents:RegisterUnitEvent("UNIT_ATTACK_SPEED", "player")

    self:SyncEvents()
    self:Reseed()
end

function ST:CancelPositionTimer()
    if self.positionTimer then
        self.positionTimer:Cancel()
        self.positionTimer = nil
    end
end

function ST:OnDisable()
    self:UnregisterAllEvents()
    if self.unitEvents then self.unitEvents:UnregisterAllEvents() end
    self:CancelPositionTimer()
    self:ResetState()
    if self.frame and not self.apiMissing then
        self:ReleaseRange()
        for _, row in ipairs(self.rows) do
            self:CancelEdgeTimers(row)
            row.starts, row.ends, row.swingDuration = nil, nil, nil
            row.state, row.phase, row.used, row.outOfRange = "empty", nil, false, false
            self:SetWord(row, nil)
            self:ParkBar(row, false)
            self:HideMarks(row)
        end
    end
    if self.frame then self.frame:Hide() end
end

function ST:ResetState()
    self.isPreview = false
    self.meleeOn = false
    self.autoRepeatOn = false
    self.inCombat = false
end

---------------------------------------------------------------------------------
-- Public methods (called from GUI / EditMode)
---------------------------------------------------------------------------------
function ST:CreateFrame()
    if self.frame then return end
    local db = self.db
    local parent = KE:ResolveAnchorFrame(db.anchorFrameType, db.ParentFrame, nil, true)
    local frame = CreateFrame("Frame", "KE_SwingTimerFrame", parent)
    frame:SetSize(db.Width, db.Height)
    frame:EnableMouse(false)
    frame:Hide()
    self.frame = frame
    KE:ApplyFramePosition(frame, db.Position, db, true)

    local _, classFile = UnitClass("player")
    self.classFile = classFile
    self.guideClass = R.IsGuideClass(classFile)
    self.order = R.BarOrder(classFile)
    self.formatter = BuildFormatter()

    self.bars, self.rows = {}, {}
    for _, key in ipairs(WEAPON_KEYS) do
        self.bars[key] = self:BuildBar(key)
    end
end

function ST:ApplySettings()
    if not self.frame or self.apiMissing or not self:IsEnabled() then return end
    self:SyncEvents()
    self:CheckAllRanges()
    for _, row in ipairs(self.rows) do self:StyleBar(row) end
    self:LayoutBars()
    self:ApplyPosition()
    if self.isPreview then
        for _, row in ipairs(self.rows) do self:PaintPreview(row) end
        self:UpdateHolder()
    else
        self:RefreshAll()
    end
end

function ST:ApplyPosition()
    if not self.frame then return end
    KE:ApplyFramePosition(self.frame, self.db.Position, self.db, true)
end

function ST:RegWithEditMode()
    H.RegWithEditMode(self, EDITMODE_OPTS)
end

function ST:ShowPreview()
    if self.apiMissing then return end
    if not self.frame then self:CreateFrame() end
    self:RegWithEditMode()
    self.isPreview = true
    self:LayoutBars()
    for _, row in ipairs(self.rows) do self:PaintPreview(row) end
    self:UpdateHolder()
end

function ST:HidePreview()
    self.isPreview = false
    if not self.frame then return end
    if self.apiMissing or not self:IsEnabled() then
        self.frame:Hide()
        return
    end
    self:LayoutBars()
    self:RefreshAll()
end

---------------------------------------------------------------------------------
-- Bar construction
---------------------------------------------------------------------------------
function ST:BuildBar(key)
    local row = { key = key, name = key, baseColor = BASE_COLOR[key], swingType = SWING_TYPE[key] }
    row.isMelee = key == "MH" or key == "OH"
    row.state = "empty"
    row.onEdge = function() self:RefreshBar(row) end

    local frame = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    row.frame = frame
    local px = KE:GetPixelSize()

    local bar = CreateFrame("StatusBar", nil, frame)
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", px, -px)
    bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -px, px)
    bar:SetStatusBarTexture(KE:GetStatusbarPath(self.db.StatusBarTexture))
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    row.bar = bar

    local spark = bar:CreateTexture(nil, "OVERLAY")
    spark:SetBlendMode("ADD")
    spark:SetTexture([[Interface\CastingBar\UI-CastingBar-Spark]])
    spark:SetPoint("CENTER", bar:GetStatusBarTexture(), "RIGHT", 0, 0)
    spark:Hide()
    row.spark = spark

    -- Above the fill in both directions, so a depleting bar shows the marks too.
    local overlay = CreateFrame("Frame", nil, bar)
    overlay:SetAllPoints(bar)
    overlay:SetFrameLevel(bar:GetFrameLevel() + 1)
    row.overlay = overlay
    row.window = overlay:CreateTexture(nil, "ARTWORK")
    row.zoneStop = overlay:CreateTexture(nil, "ARTWORK")
    row.zoneGo = overlay:CreateTexture(nil, "ARTWORK")
    row.tick = overlay:CreateTexture(nil, "ARTWORK", nil, 1)

    local time = overlay:CreateFontString(nil, "OVERLAY")
    time:SetPoint("RIGHT", overlay, "RIGHT", -4, 0)
    time:SetJustifyH("RIGHT")
    time:SetWordWrap(false)
    row.time = time
    local label = overlay:CreateFontString(nil, "OVERLAY")
    label:SetPoint("LEFT", overlay, "LEFT", 4, 0)
    label:SetPoint("RIGHT", time, "LEFT", -4, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    row.label = label

    -- Fonts first: a font string with no font throws on its first text.
    self:StyleBar(row)

    row.duration = C_DurationUtil.CreateDuration()
    if self.formatter then
        local binding = C_DurationUtil.CreateDurationTextBinding()
        binding:SetFontString(time)
        binding:SetDuration(row.duration)
        binding:SetFormatter(self.formatter)
        binding:SetUpdateInterval(TEXT_UPDATE_SECONDS)
        binding:SetExpiredText("")
        binding:SetZeroDurationText("")
        binding:SetEnabled(false)
        row.binding = binding
    end

    self.rows[#self.rows + 1] = row
    return row
end

function ST:StyleBar(row)
    local db = self.db
    row.frame:SetSize(db.Width, db.Height)
    H.ApplyFrameBackdrop(row.frame, db.BackdropColor, db.BorderColor)
    local texture = KE:GetStatusbarPath(db.StatusBarTexture)
    row.bar:SetStatusBarTexture(texture)
    -- The stop zone shares the fill's texture, so one color shows as one shade on both.
    row.zoneStop:SetTexture(texture)
    row.spark:SetSize(SPARK_WIDTH, db.Height)
    KE:ApplyFontToText(row.label, db.FontFace, db.FontSize, db.FontOutline)
    KE:ApplyFontToText(row.time, db.FontFace, db.FontSize, db.FontOutline)
    local wr, wg, wb, wa = KE:ResolveColor(db.ColorWindow, WHITE)
    row.window:SetColorTexture(wr, wg, wb, wa)
    row.shownColor, row.windowFraction, row.zoneStopBy = nil, nil, nil
    self:HideMarks(row)
end

function ST:HideMarks(row)
    row.window:Hide()
    row.zoneStop:Hide()
    row.zoneGo:Hide()
    row.tick:Hide()
end

---------------------------------------------------------------------------------
-- Painters
---------------------------------------------------------------------------------
function ST:CancelEdgeTimers(row)
    if row.endTimer then
        row.endTimer:Cancel()
        row.endTimer = nil
    end
    if row.stopTimer then
        row.stopTimer:Cancel()
        row.stopTimer = nil
    end
end

function ST:StartFill(row, start, duration, deplete)
    row.duration:SetTimeFromStart(start, duration)
    row.bar:SetTimerDuration(row.duration, Enum.StatusBarInterpolation.Immediate, FillDirection(deplete))
    row.spark:Show()
end

-- A parked timer keeps painting its terminal state and SetValue alone does not
-- repaint it, so the timer is re-armed on a finished duration as well.
function ST:ParkBar(row, full)
    row.duration:SetTimeFromStart(GetTime() - 1, 1)
    row.bar:SetTimerDuration(row.duration, Enum.StatusBarInterpolation.Immediate, FillDirection(not full))
    row.bar:SetValue(full and 1 or 0)
    row.spark:Hide()
end

-- The binding goes off before a word is written, or it overwrites the word.
function ST:SetWord(row, word)
    if row.binding then row.binding:SetEnabled(false) end
    row.time:SetText(word or "")
end

function ST:ShowCountdown(row, duration)
    if not row.binding or not self.db.ShowTime then
        self:SetWord(row, nil)
        return
    end
    row.binding:SetDuration(duration)
    row.binding:SetEnabled(true)
    row.binding:UpdateFontString()
end

function ST:SetLabel(row, text)
    if row.shownLabel == text then return end
    row.shownLabel = text
    row.label:SetText(text)
end

function ST:SetFillColor(row, colorKey)
    if row.shownColor == colorKey then return end
    row.shownColor = colorKey
    local r, g, b, a = KE:ResolveColor(self.db[colorKey], WHITE)
    row.bar:SetStatusBarColor(r, g, b, a)
end

function ST:PaintIdentity(row)
    self:SetLabel(row, row.name)
    self:SetFillColor(row, row.baseColor)
end

function ST:PaintRange(row)
    local db = self.db
    local out = row.outOfRange and db.RangeCheck and not self.isPreview
    row.frame:SetAlpha(out and R.OUT_OF_RANGE_ALPHA or 1)
    local r, g, b, a = KE:ResolveColor(out and RANGE_RED or db.TextColor, WHITE)
    row.label:SetTextColor(r, g, b, a)
    row.time:SetTextColor(r, g, b, a)
end

function ST:BarWidth()
    return self.db.Width - 2 * KE:GetPixelSize()
end

-- Places a texture over a stretch of the bar, given as fractions along the fill.
function ST:PlaceSpan(row, texture, from, to)
    local deplete = self.db.Deplete
    local width = self:BarWidth()
    local left = R.Mirror(deplete and to or from, deplete) * width
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", row.overlay, "TOPLEFT", left, 0)
    texture:SetPoint("BOTTOMLEFT", row.overlay, "BOTTOMLEFT", left, 0)
    texture:SetWidth(math.max((to - from) * width, KE:GetPixelSize()))
end

function ST:PlaceWindow(row)
    local db = self.db
    local fraction
    if row.isMelee and db.EndWindow then
        fraction = R.EndWindow(db.EndWindowSeconds, row.swingDuration, db.AddLatency,
            db.AddLatency and WorldLatency() or 0)
    end
    if not fraction then
        row.window:Hide()
        return
    end
    if row.windowFraction ~= fraction then
        row.windowFraction = fraction
        self:PlaceSpan(row, row.window, 1 - fraction, 1)
    end
    row.window:Show()
end

function ST:PaintPreview(row)
    self:CancelEdgeTimers(row)
    self:SetWord(row, PREVIEW_TIME)
    self:ParkBar(row, true)
    self:HideMarks(row)
    self:PaintIdentity(row)
    self:PaintRange(row)
end

---------------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------------
function ST:AttackOn(row)
    if row.key == "R" then return self.autoRepeatOn end
    return self.meleeOn
end

-- From the swing and attack state rather than row.state, which a preview stops
-- updating while swings go on.
function ST:SwingRunning(row, now)
    return R.MeleeState(row.isTarget or self:AttackOn(row), now, row.ends) == "running"
end

function ST:GuideOn()
    return self.guideClass and self.db.RangedGuide
end

function ST:IsGuided(row)
    return row.key == "R" and self:GuideOn()
end

function ST:TargetEstimateOn()
    return PROOF.TARGET_BAR and self.db.TargetEstimate
end

function ST:RefreshMelee(row)
    self:CancelEdgeTimers(row)
    local now = GetTime()
    local state = R.MeleeState(self:AttackOn(row), now, row.ends)
    row.state = state
    self:PaintIdentity(row)
    if state == "running" then
        self:StartFill(row, row.starts, row.swingDuration, self.db.Deplete)
        self:ShowCountdown(row, row.duration)
        self:PlaceWindow(row)
        row.endTimer = C_Timer.NewTimer(row.ends - now, row.onEdge)
    else
        local out = row.outOfRange and self.db.RangeCheck
        self:SetWord(row, state == "parked" and (out and "RANGE" or "READY") or nil)
        self:ParkBar(row, state == "parked")
        row.window:Hide()
    end
    self:PaintRange(row)
end

-- The one recompute: it reads state and the clock, so any event or timer edge
-- can call it, and closing a preview restores live state through it.
function ST:RefreshBar(row)
    if self.isPreview then return end
    self:RefreshMelee(row)
    self:UpdateHolder()
end

function ST:RefreshAll()
    for _, row in ipairs(self.rows) do self:RefreshBar(row) end
    self:UpdateHolder()
end

function ST:UpdateHolder()
    local anyLive = false
    for _, row in ipairs(self.rows) do
        if row.state ~= "empty" and row.frame:IsShown() then
            anyLive = true
            break
        end
    end
    self.frame:SetShown(R.FrameShown(self.db.Visibility, self.inCombat, anyLive, self.isPreview))
end

---------------------------------------------------------------------------------
-- Weapons and layout
---------------------------------------------------------------------------------
-- Returns whether any weapon's known state changed.
function ST:ReadWeapons()
    local changed = false
    for _, key in ipairs(WEAPON_KEYS) do
        local row = self.bars[key]
        local wasKnown = row.known
        local read = select(SPEED_RETURN[key], UnitAttackSpeed("player"))
        row.speed, row.known = R.ResolveSpeed(not KE:IsSecretValue(read), read, row.speed)
        if row.known ~= wasKnown then changed = true end
    end
    return changed
end

function ST:ApplyBarShown(row)
    local isPrimary = (row.key == "R") == (self.guideClass == true)
    local shown = row.slot ~= nil
        and (self.isPreview or R.BarShown(self.db.ShowWhenSwings, isPrimary, row.known, row.used))
    row.frame:SetShown(shown)
end

function ST:LayoutBars()
    local db = self.db
    local known = {}
    for _, key in ipairs(WEAPON_KEYS) do known[key] = self.bars[key].known end
    local slots = R.Slots(self.order, known)
    local rows = 0
    for _, key in ipairs(WEAPON_KEYS) do
        local row = self.bars[key]
        row.slot = slots[key]
        if row.slot then
            row.frame:ClearAllPoints()
            row.frame:SetPoint("TOP", self.frame, "TOP", 0, -(row.slot - 1) * (db.Height + db.Spacing))
            rows = math.max(rows, row.slot)
        end
        self:ApplyBarShown(row)
    end
    self.frame:SetSize(db.Width, rows * db.Height + (rows - 1) * db.Spacing)
end

function ST:ClearUsed()
    for _, key in ipairs(WEAPON_KEYS) do
        local row = self.bars[key]
        row.used = false
        self:ApplyBarShown(row)
    end
end

function ST:SeedState()
    local melee = C_Spell.IsCurrentSpell(AUTO_ATTACK_SPELL)
    self.meleeOn = not KE:IsSecretValue(melee) and melee == true
    self.autoRepeatOn = false
    for slot = 1, MAX_ACTION_SLOTS do
        -- The API refuses an invalid slot and the client's slot count is undocumented.
        local ok, repeating = pcall(C_ActionBar.IsAutoRepeatAction, slot)
        if ok and not KE:IsSecretValue(repeating) and repeating then
            self.autoRepeatOn = true
            break
        end
    end
end

function ST:Reseed()
    self.inCombat = InCombatLockdown()
    self:ClearUsed()
    self:ReadWeapons()
    self:LayoutBars()
    self:SeedState()
    self:CheckAllRanges()
    self:RefreshAll()
end

---------------------------------------------------------------------------------
-- Range
---------------------------------------------------------------------------------
function ST:CheckRange(row)
    if not self.db.RangeCheck then
        row.outOfRange = false
        return
    end
    ---@diagnostic disable-next-line: wrong-flavor-api
    C_SwingTimer.EnableRangeCheck(row.swingType, true)
    ---@diagnostic disable-next-line: wrong-flavor-api
    local inRange = C_SwingTimer.IsTargetWithinSwingRange(row.swingType)
    row.outOfRange = R.OutOfRange(not KE:IsSecretValue(inRange), inRange)
end

function ST:CheckAllRanges()
    for _, key in ipairs(WEAPON_KEYS) do self:CheckRange(self.bars[key]) end
end

function ST:ReleaseRange()
    if not R.ReleaseRangeFlag(BlizzardCVarOn()) then return end
    for _, key in ipairs(WEAPON_KEYS) do
        ---@diagnostic disable-next-line: wrong-flavor-api
        C_SwingTimer.EnableRangeCheck(SWING_TYPE[key], false)
    end
end

function ST:OnRangeChanged(row)
    if self.isPreview then return end
    if row.state == "parked" or row.phase == "aim" then
        self:RefreshBar(row)
    else
        self:PaintRange(row)
    end
end

function ST:SyncEvents()
    local db = self.db
    if db.RangeCheck then
        self:RegisterEvent(RANGE_EVENT)
    else
        self:UnregisterEvent(RANGE_EVENT)
        self:ReleaseRange()
    end
    if db.RangeCheck or self:TargetEstimateOn() then
        self:RegisterEvent("PLAYER_TARGET_CHANGED")
    else
        self:UnregisterEvent("PLAYER_TARGET_CHANGED")
    end
end

---------------------------------------------------------------------------------
-- Event handlers (Ace3 and the unit frame dispatch by method name)
---------------------------------------------------------------------------------
function ST:NoteSwing(row, duration)
    if not row.speed then row.speed = duration end
    row.used = true
    if row.known then
        self:ApplyBarShown(row)
    else
        row.known = true
        self:LayoutBars()
    end
end

function ST:PLAYER_SWING(_, duration, swingType)
    if KE:IsSecretValue(duration) or KE:IsSecretValue(swingType) then return end
    local key = R.BarFor(swingType)
    if not key or not R.ValidDuration(duration) then return end
    local row = self.bars[key]
    local now = GetTime()
    row.starts, row.ends, row.swingDuration = now, now + duration, duration
    self:NoteSwing(row, duration)
    if key == "R" then
        self.autoRepeatOn = true
    else
        self.meleeOn = true
    end
    self:CheckRange(row)
    self:RefreshBar(row)
end

function ST:PLAYER_SWING_RANGE_UPDATE(_, swingType, isInRange, checksRange)
    if KE:IsSecretValue(swingType) then return end
    local key = R.BarFor(swingType)
    if not key then return end
    local row = self.bars[key]
    local readable = not KE:IsSecretValue(isInRange) and not KE:IsSecretValue(checksRange)
    row.outOfRange = R.OutOfRangeFromEvent(readable, isInRange, checksRange)
    self:OnRangeChanged(row)
end

function ST:PLAYER_TARGET_CHANGED()
    for _, key in ipairs(WEAPON_KEYS) do
        local row = self.bars[key]
        self:CheckRange(row)
        self:OnRangeChanged(row)
    end
end

function ST:WEAPON_SLOT_CHANGED()
    local now = GetTime()
    for _, key in ipairs(WEAPON_KEYS) do
        local row = self.bars[key]
        local read = select(SPEED_RETURN[key], UnitAttackSpeed("player"))
        local readable = not KE:IsSecretValue(read)
        local restart = R.SwapRestartSpeed(readable, read)
        row.speed, row.known = R.ResolveSpeed(readable, read, row.speed)
        if restart and self:SwingRunning(row, now) then
            row.starts, row.ends, row.swingDuration = now, now + restart, restart
            self:RefreshBar(row)
        end
    end
    self:LayoutBars()
end

function ST:UNIT_ATTACK_SPEED()
    if self:ReadWeapons() then self:LayoutBars() end
end

function ST:PLAYER_ENTERING_WORLD()
    self:Reseed()
end

function ST:PLAYER_DEAD()
    self.meleeOn, self.autoRepeatOn = false, false
    for _, row in ipairs(self.rows) do row.ends = nil end
    self:RefreshAll()
end

function ST:PLAYER_REGEN_DISABLED()
    self.inCombat = true
    self:UpdateHolder()
end

function ST:PLAYER_REGEN_ENABLED()
    self.inCombat = false
    self:ClearUsed()
    self:SeedState()
    self:RefreshAll()
end

function ST:SetMeleeOn(on)
    self.meleeOn = on
    self:RefreshBar(self.bars.MH)
    self:RefreshBar(self.bars.OH)
end

function ST:PLAYER_ENTER_COMBAT()
    self:SetMeleeOn(true)
end

function ST:PLAYER_LEAVE_COMBAT()
    self:SetMeleeOn(false)
end

function ST:START_AUTOREPEAT_SPELL()
    self.autoRepeatOn = true
    self:RefreshBar(self.bars.R)
end

function ST:STOP_AUTOREPEAT_SPELL()
    self.autoRepeatOn = false
    self:RefreshBar(self.bars.R)
end
