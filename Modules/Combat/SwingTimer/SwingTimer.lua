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
-- Floors for a size another addon hands over; the page's sliders keep their own
-- ranges.
local MATCH_MIN_WIDTH = 20
local MATCH_MIN_ROW_HEIGHT = 4
local MATCH_TOLERANCE = 0.01
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
    self.movementOn = false
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
    if PROOF.TARGET_BAR then self:DisableTarget() end
    self:UnregisterAllEvents()
    if self.unitEvents then self.unitEvents:UnregisterAllEvents() end
    self:CancelPositionTimer()
    self:ResetState()
    -- The first layout after an enable pulls a match made while the module was off.
    self.pulledRows, self.pulledSpacing, self.pulledHeight, self.pulledWidth = nil, nil, nil, nil
    if self.frame and not self.apiMissing then
        self:ReleaseRange()
        for _, row in ipairs(self.rows) do
            self:CancelEdgeTimers(row)
            row.starts, row.ends, row.swingDuration = nil, nil, nil
            row.state, row.phase, row.used, row.outOfRange = "empty", nil, false, false
            row.latency = nil
            self:SetWord(row, nil)
            self:ParkBar(row, false)
            self:HideMarks(row)
        end
    end
    if self.frame then self.frame:Hide() end
end

function ST:ResetState()
    if self.sealTimer then
        self.sealTimer:Cancel()
        self.sealTimer = nil
    end
    self.queued, self.seal = nil, nil
    self.movementOn, self.moving, self.lastStop = false, false, nil
    self.castEnd = nil
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
    -- Switching a color back on sends no event, and the attack or seal may already be up.
    self:UpdateQueue()
    self:ReadSealAuras()
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
    self:RegWithUnlock()
end

-- EllesmereUI's unlock mode: its elements can anchor to the bars and match their
-- size, and the bars can take their width or height from one of its elements.
-- Never withdrawn, like every KE element there; isHidden reports a module that
-- is off.
function ST:RegWithUnlock()
    if self.unlockRegistered or not KE.EUIUnlock then return end
    self.unlockRegistered = true
    KE.EUIUnlock:Register({
        key = "SwingTimer",
        displayName = "Swing Timer",
        frame = self.frame,
        getPosition = function() return self.db.Position end,
        setPosition = function(pos)
            self.db.Position = pos
            self:ApplyPosition()
        end,
        getParentFrame = function()
            return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame)
        end,
    }, {
        label = "Swing Timer",
        order = 630,
        isHidden = function()
            return not (self.db and self.db.Enabled and self.frame and not self.apiMissing)
        end,
        setWidth = function(width) self:SetMatchedWidth(width) end,
        setHeight = function(height) self:SetMatchedHeight(height) end,
    })
end

-- A matched size writes the profile as the page's slider does. Returning early
-- on an unchanged size ends the resize, match and resize loop.
function ST:SetMatchedWidth(width)
    local db = self.db
    local value = KE:PixelSnap(math.max(width, MATCH_MIN_WIDTH))
    if math.abs(value - (db.Width or 0)) < MATCH_TOLERANCE then return end
    db.Width = value
    self:ApplySettings()
end

-- A matched height is the whole stack's, shared over the rows laid out.
function ST:SetMatchedHeight(height)
    local db = self.db
    local value = KE:PixelSnap(R.RowHeightFor(height, self.rowCount, db.Spacing, MATCH_MIN_ROW_HEIGHT))
    if math.abs(value - (db.Height or 0)) < MATCH_TOLERANCE then return end
    db.Height = value
    self:ApplySettings()
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

-- Every arm records its fill: GetValue reads 0 on a timer-driven bar, so the
-- record is the only way to know where the bar stands.
function ST:RecordFill(row, start, duration, drains, timed)
    row.fillStart, row.fillDuration, row.fillDrains = start, duration, drains
    row.fillSwing, row.holdsEnd, row.redHold = row.starts, timed, nil
end

function ST:StartFill(row, start, duration, deplete)
    self:RecordFill(row, start, duration, deplete, true)
    local interpolation = Enum.StatusBarInterpolation
    local how = row.easeNext and interpolation.ExponentialEaseOut or interpolation.Immediate
    row.easeNext = nil
    row.duration:SetTimeFromStart(start, duration)
    row.bar:SetTimerDuration(row.duration, how, FillDirection(deplete))
    row.spark:Show()
end

-- A parked timer keeps painting its terminal state and SetValue alone does not
-- repaint it, so the timer is re-armed on a finished duration as well.
function ST:ParkBar(row, full)
    local start = GetTime() - 1
    self:RecordFill(row, start, 1, not full, false)
    row.duration:SetTimeFromStart(start, 1)
    row.bar:SetTimerDuration(row.duration, Enum.StatusBarInterpolation.Immediate, FillDirection(not full))
    row.bar:SetValue(full and 1 or 0)
    row.spark:Hide()
end

-- The full red hold of a move that holds the shot; a stop from it starts the
-- aim afresh.
function ST:HoldRed(row)
    self:ParkBar(row, true)
    row.redHold = true
end

-- Whether the bar stands on a timed fill of the swing it shows, or holds the
-- end of one.
function ST:OnOwnFill(row)
    return row.holdsEnd == true and row.fillSwing == row.starts
end

-- A bar waiting on its shot or swing stays where it stands: a fill of this
-- swing still running finishes, a finished one holds its end, and an emptied
-- or held bar stays as it is.
function ST:HoldBar(row, now)
    local own = self:OnOwnFill(row)
    if own and now < row.fillStart + row.fillDuration then
        self:StartFill(row, row.fillStart, row.fillDuration, row.fillDrains)
        row.endTimer = C_Timer.NewTimer(row.fillStart + row.fillDuration - now, row.onEdge)
        return
    end
    self:ParkBar(row, R.FillAt(row.fillStart, row.fillDuration, row.fillDrains, now) > 0.5)
    row.holdsEnd = own
end

-- Moves the bar on from where it stands to reach `toward` at endAt. Off a fill
-- of this swing, the red hold starts afresh from the far end, and any other
-- paint, such as an emptied bar or the preview, takes the drain's live position.
function ST:FillToward(row, now, endAt, toward)
    local fraction
    if self:OnOwnFill(row) then
        fraction = R.FillAt(row.fillStart, row.fillDuration, row.fillDrains, now)
    elseif row.redHold then
        fraction = 1 - toward
    else
        local from = R.AimStart(row.stopAt or now, self.lastStop)
        fraction = R.FillAt(from, endAt - from, toward == 0, now)
    end
    local start, duration, drains = R.FillToward(fraction, now, endAt, toward)
    if start then
        self:StartFill(row, start, duration, drains)
    else
        self:ParkBar(row, toward == 1)
        row.holdsEnd = true
    end
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
    local queued, seal = self.queued, self.seal
    local name = row.isMelee and ((queued and queued.name) or (seal and seal.name)) or nil
    self:SetLabel(row, name and (row.name .. "  " .. name) or row.name)
    self:SetFillColor(row, R.BarColorKey(row.isMelee, queued and queued.colorKey, seal and seal.colorKey, row.baseColor))
end

function ST:PaintRange(row)
    local db = self.db
    local out = row.outOfRange and db.RangeCheck and row.state ~= "empty" and not self.isPreview
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
        if state == "parked" then
            self:HoldBar(row, now)
        else
            self:ParkBar(row, false)
        end
        row.window:Hide()
    end
    self:PaintRange(row)
end

-- The one recompute: it reads state and the clock, so any event or timer edge
-- can call it, and closing a preview restores live state through it.
function ST:RefreshBar(row)
    -- Above the preview's return: the listeners follow the state, not the painting.
    if row.key == "R" then self:SyncMovement() end
    if self.isPreview then
        row.easeNext = nil
        return
    end
    if row.isTarget then
        self:RefreshTarget(row)
    elseif self:IsGuided(row) then
        self:RefreshGuide(row)
    else
        self:RefreshMelee(row)
    end
    -- A repaint that parked leaves the mark unspent; it never carries over.
    row.easeNext = nil
    self:PlaceTick(row)
    self:UpdateHolder()
end

-- A restart on a shown bar slides to its new fill; every other paint is at once.
function ST:MarkRestart(row)
    row.easeNext = not self.isPreview and row.frame:IsVisible()
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
        row.known = R.WeaponKnown(not KE:IsSecretValue(read), read, row.known)
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
    if PROOF.TARGET_BAR then rows = self:LayoutTarget(rows + 1) end
    self.rowCount = rows
    self.frame:SetSize(db.Width, rows * db.Height + (rows - 1) * db.Spacing)
    self:UpdateHolder()
    -- A matched height belongs to the whole stack, so it is pulled again when the
    -- rows, spacing or row height change, and a matched width when the width
    -- does. Nothing else pulls: a pull re-applies the target's other children too.
    -- Recorded only on a true answer: a pull refused inside another axis's apply
    -- stays pending, and the width check below, after the height pull, takes it.
    local unlock = KE.EUIUnlock
    if unlock then
        if (rows ~= self.pulledRows or db.Spacing ~= self.pulledSpacing or db.Height ~= self.pulledHeight)
            and unlock:PullMatch("SwingTimer", "height") then
            self.pulledRows, self.pulledSpacing, self.pulledHeight = rows, db.Spacing, db.Height
        end
        if db.Width ~= self.pulledWidth and unlock:PullMatch("SwingTimer", "width") then
            self.pulledWidth = db.Width
        end
    end
end

function ST:ClearUsed()
    for _, key in ipairs(WEAPON_KEYS) do
        local row = self.bars[key]
        row.used = false
        self:ApplyBarShown(row)
    end
end

function ST:SeedState()
    if PROOF.BLIZZARD_BUTTON then self:ReadBlizzard() end
    self:UpdateQueue()
    self:ReadSealAuras()
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
    self:SyncCastEvents()
    self:SyncGuideEvents()
    self:SyncColorEvents()
    if PROOF.TARGET_BAR then self:EnableTarget() end
    self:SyncCombatEvent()
    if db.RangeCheck or self:TargetEstimateOn() then
        self:RegisterEvent("PLAYER_TARGET_CHANGED")
    else
        self:UnregisterEvent("PLAYER_TARGET_CHANGED")
    end
end

---------------------------------------------------------------------------------
-- Event handlers (Ace3 and the unit frame dispatch by method name)
---------------------------------------------------------------------------------
function ST:NoteSwing(row)
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
    -- Read before NoteSwing shows a bar, so one that appears with its swing paints at once.
    self:MarkRestart(row)
    row.starts, row.ends, row.swingDuration = now, now + duration, duration
    self:TakeLatency(row)
    self:NoteSwing(row)
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
    if PROOF.TARGET_BAR then self:OnTargetChanged() end
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
        row.known = R.WeaponKnown(readable, read, row.known)
        if restart and self:SwingRunning(row, now) then
            self:MarkRestart(row)
            row.starts, row.ends, row.swingDuration = now, now + restart, restart
            self:TakeLatency(row)
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
    -- A weapon dropped in combat read secret, and no swing of its own corrects it.
    if self:ReadWeapons() then self:LayoutBars() end
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

---------------------------------------------------------------------------------
-- Cast tick
---------------------------------------------------------------------------------
local CAST_EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_CHANNEL_STOP",
}

-- The player's cast end in seconds. Nil with no cast, with an unreadable one,
-- and for Auto Shot and Shoot, so those never count as casting.
local function ReadCastEnd()
    local _, _, _, _, endMS, _, _, _, spellID = UnitCastingInfo("player")
    if KE:IsSecretValue(endMS) or KE:IsSecretValue(spellID) then return nil end
    if not endMS then
        _, _, _, _, endMS, _, _, spellID = UnitChannelInfo("player")
        if KE:IsSecretValue(endMS) or KE:IsSecretValue(spellID) then return nil end
    end
    if not endMS or R.TickIgnored(spellID) then return nil end
    return endMS / 1000
end

function ST:SyncCastEvents()
    local db = self.db
    local want = db.CastTickMelee or db.CastTickRanged or self:GuideOn()
    for _, event in ipairs(CAST_EVENTS) do
        if want then
            self.unitEvents:RegisterUnitEvent(event, "player")
        else
            self.unitEvents:UnregisterEvent(event)
        end
    end
    -- A cast already running sends no start event.
    self.castEnd = want and ReadCastEnd() or nil
end

function ST:TickAllowed(row)
    local db = self.db
    if row.isMelee then return db.CastTickMelee end
    if row.key ~= "R" or not db.CastTickRanged then return false end
    return not (self:IsGuided(row) and db.HunterStyle == "windup")
end

function ST:PlaceTick(row)
    local fraction, clipped
    if self.castEnd and row.state == "running" and row.phase ~= "aim" and self:TickAllowed(row) then
        fraction, clipped = R.TickFraction(self.castEnd, row.starts, row.swingDuration)
    end
    if not fraction then
        row.tick:Hide()
        return
    end
    local x = R.Mirror(fraction, self.db.Deplete) * self:BarWidth()
    local px = KE:GetPixelSize()
    row.tick:ClearAllPoints()
    row.tick:SetPoint("TOP", row.overlay, "TOPLEFT", x, 0)
    row.tick:SetPoint("BOTTOM", row.overlay, "BOTTOMLEFT", x, 0)
    row.tick:SetWidth(2 * px)
    local color = clipped and RANGE_RED or WHITE
    row.tick:SetColorTexture(color[1], color[2], color[3], color[4])
    row.tick:Show()
end

function ST:OnCastChanged()
    self.castEnd = ReadCastEnd()
    local ranged = self.bars.R
    if self:IsGuided(ranged) and (ranged.state == "parked" or ranged.phase == "aim") then
        self:RefreshBar(ranged)
    end
    if self.isPreview then return end
    for _, key in ipairs(WEAPON_KEYS) do self:PlaceTick(self.bars[key]) end
end

for _, event in ipairs(CAST_EVENTS) do ST[event] = ST.OnCastChanged end

---------------------------------------------------------------------------------
-- Ranged guide
---------------------------------------------------------------------------------
local GOLD_ZONE_ALPHA = 0.5
local RED_ZONE_ALPHA = 0.6
local GO_BAND = { 0.95, 0.96, 0.97, 0.62 }
local GUIDE_LABEL = { MOVE = "R  MOVE", STILL = "R  STILL", STOP = "R  STOP" }
local GUIDE_COLOR = { MOVE = "ColorR", STILL = "ColorStill", STOP = "ColorStop" }

-- The latency belongs to the swing, guide on or off, so switching the guide on
-- mid-swing has nothing to catch up on.
function ST:TakeLatency(row)
    if row.key ~= "R" or not self.guideClass then return end
    row.latency = WorldLatency()
end

-- Before the first swing there is no latency to read.
function ST:ShotAt(row)
    return R.ShotTime(row.ends or 0, self.lastStop, R.AIM_SECONDS, row.latency or 0)
end

function ST:HideZones(row)
    row.zoneStop:Hide()
    row.zoneGo:Hide()
end

function ST:PlaceZones(row, aim, latency, stopping)
    local stopBy, go = R.Zones(row.swingDuration, aim, latency)
    if row.zoneStopBy ~= stopBy or row.zoneGoAt ~= go then
        row.zoneStopBy, row.zoneGoAt = stopBy, go
        self:PlaceSpan(row, row.zoneStop, stopBy, go)
        self:PlaceSpan(row, row.zoneGo, go, 1)
    end
    local r, g, b = KE:ResolveColor(self.db[stopping and "ColorStop" or "ColorStill"], WHITE)
    row.zoneStop:SetVertexColor(r, g, b, stopping and RED_ZONE_ALPHA or GOLD_ZONE_ALPHA)
    row.zoneGo:SetColorTexture(GO_BAND[1], GO_BAND[2], GO_BAND[3], GO_BAND[4])
    row.zoneStop:Show()
    row.zoneGo:Show()
end

function ST:PaintReload(row, now)
    local db = self.db
    local aim, latency = R.AIM_SECONDS, row.latency or 0
    local stopAt = math.max(row.ends - aim - latency, row.starts)
    local inZone = now >= stopAt
    local word = R.ReloadWord(inZone, self.moving)
    row.state, row.phase, row.stopAt = "running", "reload", stopAt
    self:SetLabel(row, GUIDE_LABEL[word])
    self:SetFillColor(row, GUIDE_COLOR[word])
    if db.HunterStyle == "windup" then
        self:HideZones(row)
        -- The bar's timer covers the reload or the aim; the countdown runs to the
        -- shot, which a stop inside the zone moves past the swing end.
        local shotAt = self:ShotAt(row)
        row.shotDuration = row.shotDuration or C_DurationUtil.CreateDuration()
        row.shotDuration:SetTimeFromStart(row.starts, shotAt - row.starts)
        if word == "MOVE" then
            self:StartFill(row, row.starts, stopAt - row.starts, db.Deplete)
        elseif word == "STOP" then
            self:HoldRed(row)
        else
            self:FillToward(row, now, shotAt, db.Deplete and 1 or 0)
        end
        self:ShowCountdown(row, row.shotDuration)
    else
        self:StartFill(row, row.starts, row.swingDuration, db.Deplete)
        self:ShowCountdown(row, row.duration)
        self:PlaceZones(row, aim, latency, word == "STOP")
    end
    if not inZone then row.stopTimer = C_Timer.NewTimer(stopAt - now, row.onEdge) end
    row.endTimer = C_Timer.NewTimer(row.ends - now, row.onEdge)
end

function ST:PaintDue(row, now)
    local db = self.db
    local out = row.outOfRange and db.RangeCheck
    local shotAt = self:ShotAt(row)
    local phase = R.RangedAtEnd(self.moving, self.castEnd ~= nil, out, now, shotAt)
    self:HideZones(row)
    if phase == "aim" then
        row.state, row.phase = "running", "aim"
        self:SetLabel(row, GUIDE_LABEL.STILL)
        self:SetFillColor(row, GUIDE_COLOR.STILL)
        -- After a stop in the zone the drain is already part way down; the aim
        -- carries it on rather than starting again from the top.
        self:FillToward(row, now, shotAt, db.Deplete and 1 or 0)
        self:ShowCountdown(row, row.duration)
        row.endTimer = C_Timer.NewTimer(shotAt - now, row.onEdge)
        return
    end
    row.state, row.phase = "parked", phase
    if phase == "held" then
        self:SetLabel(row, GUIDE_LABEL.STOP)
        self:SetFillColor(row, GUIDE_COLOR.STOP)
        self:SetWord(row, "HELD")
        self:HoldRed(row)
    else
        self:PaintIdentity(row)
        self:SetWord(row, out and "RANGE" or "READY")
        self:HoldBar(row, now)
    end
end

function ST:RefreshGuide(row)
    self:CancelEdgeTimers(row)
    local now = GetTime()
    if not self.autoRepeatOn then
        row.state, row.phase = "empty", nil
        self:HideZones(row)
        self:PaintIdentity(row)
        self:SetWord(row, nil)
        self:ParkBar(row, false)
    elseif row.ends and now < row.ends then
        self:PaintReload(row, now)
    else
        self:PaintDue(row, now)
    end
    self:PaintRange(row)
end

function ST:SyncMovement()
    local want = self:IsGuided(self.bars.R) and self.autoRepeatOn
    if want and not self.movementOn then
        self.movementOn = true
        self:RegisterEvent("PLAYER_STARTED_MOVING")
        self:RegisterEvent("PLAYER_STOPPED_MOVING")
        local moving = IsPlayerMoving()
        self.moving = not KE:IsSecretValue(moving) and moving == true
    elseif not want and self.movementOn then
        self.movementOn = false
        self:UnregisterEvent("PLAYER_STARTED_MOVING")
        self:UnregisterEvent("PLAYER_STOPPED_MOVING")
        self.moving = false
    end
end

function ST:SyncGuideEvents()
    if not self:GuideOn() then self.bars.R.phase = nil end
    self:SyncMovement()
end

function ST:OnMovementChanged(moving)
    self.moving = moving
    local now = GetTime()
    if not moving then self.lastStop = now end
    local row = self.bars.R
    -- Before the stop-by line nothing on the bar depends on movement.
    if row.phase == "reload" and now < row.stopAt then return end
    if row.phase then self:RefreshBar(row) end
end

function ST:PLAYER_STARTED_MOVING()
    self:OnMovementChanged(true)
end

function ST:PLAYER_STOPPED_MOVING()
    self:OnMovementChanged(false)
end

---------------------------------------------------------------------------------
-- Queue and seal colors
---------------------------------------------------------------------------------
local MAX_AURAS = 40

function ST:PaintMeleeIdentity()
    if self.isPreview then return end
    self:PaintIdentity(self.bars.MH)
    self:PaintIdentity(self.bars.OH)
end

-- Names, so that every rank of a spell matches. Built once, for the classes
-- that have them.
function ST:BuildColorNames()
    if self.colorNamesBuilt then return end
    self.colorNamesBuilt = true
    local spells = R.QUEUE_SPELLS[self.classFile]
    if spells then
        self.queueNames = {}
        for _, entry in ipairs(spells) do
            local name = C_Spell.GetSpellName(entry.id)
            if not KE:IsSecretValue(name) and name then
                self.queueNames[#self.queueNames + 1] = { name = name, colorKey = entry.colorKey }
            end
        end
    end
    if self.classFile == "PALADIN" then
        self.sealByName = {}
        for _, entry in ipairs(R.SEALS) do
            local name = C_Spell.GetSpellName(entry.id)
            if not KE:IsSecretValue(name) and name then
                self.sealByName[name] = { name = name, colorKey = entry.colorKey }
            end
        end
    end
end

function ST:SetQueued(entry)
    if self.queued == entry then return end
    self.queued = entry
    self:PaintMeleeIdentity()
end

-- An unreadable answer counts as not queued: no color rather than a wrong one.
function ST:UpdateQueue()
    if not (self.queueNames and self.db.QueueColors) then return end
    local queued
    for _, entry in ipairs(self.queueNames) do
        local current = C_Spell.IsCurrentSpell(entry.name)
        if not KE:IsSecretValue(current) and current then
            queued = entry
            break
        end
    end
    self:SetQueued(queued)
end

function ST:ACTIONBAR_UPDATE_STATE()
    self:UpdateQueue()
end

function ST:SetSeal(seal, seconds)
    if self.sealTimer then
        self.sealTimer:Cancel()
        self.sealTimer = nil
    end
    self.seal = seal
    if seal and seconds then
        self.sealTimer = C_Timer.NewTimer(seconds, function()
            self.sealTimer = nil
            self.seal = nil
            self:PaintMeleeIdentity()
        end)
    end
    self:PaintMeleeIdentity()
end

-- Out of combat with auras visible only, since no aura is read in combat.
function ST:ReadSealAuras()
    if not (self.sealByName and self.db.SealColors) then return end
    if R.SealSource(KE:AreAuraIdentitiesHidden(), InCombatLockdown()) ~= "auras" then return end
    for i = 1, MAX_AURAS do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura then break end
        local name = aura.name
        local seal = not KE:IsSecretValue(name) and self.sealByName[name]
        if seal then
            local length, expires = aura.duration, aura.expirationTime
            if KE:IsSecretValue(length) or KE:IsSecretValue(expires) then
                self:SetSeal(seal, self.sealLength or R.SEAL_SECONDS)
            else
                self.sealLength = R.SealSeconds(true, length, self.sealLength)
                local remaining = (expires or 0) - GetTime()
                self:SetSeal(seal, remaining > 0 and remaining or self.sealLength)
            end
            return
        end
    end
    self:SetSeal(nil)
end

-- An unreadable cast changes nothing, and neither does any other spell: the color
-- stays on the last known seal until its counted end.
function ST:UNIT_SPELLCAST_SUCCEEDED(_, _, _, spellID)
    if not self.sealByName or KE:IsSecretValue(spellID) then return end
    local name = C_Spell.GetSpellName(spellID)
    if KE:IsSecretValue(name) then return end
    local seal = R.SealFromCast(name, self.sealByName)
    if not seal then return end
    self:SetSeal(seal, R.SealSeconds(false, nil, self.sealLength))
end

function ST:UNIT_AURA(_, unit, updateInfo)
    if KE:IsUnreadableAuraPayload(unit, updateInfo) then return end
    self:ReadSealAuras()
end

function ST:SyncColorEvents()
    local db = self.db
    self:BuildColorNames()
    if R.QueueEventWanted(self.classFile, db.QueueColors) then
        self:RegisterEvent("ACTIONBAR_UPDATE_STATE")
    else
        self:UnregisterEvent("ACTIONBAR_UPDATE_STATE")
        self:SetQueued(nil)
    end
    if self.classFile == "PALADIN" and db.SealColors then
        self.unitEvents:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        self.unitEvents:RegisterUnitEvent("UNIT_AURA", "player")
    else
        self.unitEvents:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        self.unitEvents:UnregisterEvent("UNIT_AURA")
        self:SetSeal(nil)
    end
end

---------------------------------------------------------------------------------
-- Blizzard's bar
---------------------------------------------------------------------------------
local function BlizzardFlagStore()
    return KE.db.global
end

-- Reading the setting on clears a stale flag.
function ST:ReadBlizzard()
    local cvarOn = BlizzardCVarOn()
    local store = BlizzardFlagStore()
    store.SwingTimerHidBlizzard = R.BlizzardFlag(cvarOn, store.SwingTimerHidBlizzard)
    return cvarOn, store.SwingTimerHidBlizzard
end

-- Returns whether the page shows its card, and the button's action.
function ST:BlizzardButtonState()
    return R.BlizzardButton(self:ReadBlizzard())
end

function ST:ToggleBlizzardBar()
    if not PROOF.BLIZZARD_BUTTON then return end
    local cvarOn, flag = self:ReadBlizzard()
    local inCombat = InCombatLockdown()
    local value, newFlag = R.BlizzardClick(cvarOn, flag, inCombat)
    if not value then
        if inCombat then KE:Print("Blizzard's swing bar cannot be changed in combat.") end
        return
    end
    C_CVar.SetCVar(BLIZZARD_CVAR, value)
    BlizzardFlagStore().SwingTimerHidBlizzard = newFlag
    -- The write clears the range flags, so they are turned back on.
    if self:IsEnabled() and self.bars then self:CheckAllRanges() end
end

---------------------------------------------------------------------------------
-- Parry haste
---------------------------------------------------------------------------------
-- The swing keeps its length and its start moves, so a second parry measures
-- against the same swing. The next swing event corrects this.
function ST:ShortenSwing(row)
    local now = GetTime()
    if not self:SwingRunning(row, now) then return end
    row.ends = now + R.ParryHastened(row.ends - now, row.swingDuration)
    row.starts = row.ends - row.swingDuration
    self:MarkRestart(row)
    self:RefreshBar(row)
end

function ST:SyncCombatEvent()
    if self:TargetEstimateOn() then
        self.unitEvents:RegisterUnitEvent("UNIT_COMBAT", "player", "target")
    elseif PROOF.OWN_PARRY_HASTE then
        self.unitEvents:RegisterUnitEvent("UNIT_COMBAT", "player")
    else
        self.unitEvents:UnregisterEvent("UNIT_COMBAT")
    end
end

function ST:UNIT_COMBAT(_, unit, action, _, _, school)
    if KE:IsSecretValue(unit) or KE:IsSecretValue(action) then return end
    if PROOF.OWN_PARRY_HASTE and unit == "player" and action == "PARRY" then self:ShortenSwing(self.bars.MH) end
    if self:TargetEstimateOn() then self:OnTargetCombat(unit, action, school) end
end
