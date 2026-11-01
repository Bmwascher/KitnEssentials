-- ╔══════════════════════════════════════════════════════════╗
-- ║  SpellReflect.lua                                        ║
-- ║  Module: Spell Reflect                                   ║
-- ║  Purpose: Counts down to the boss casts Spell Reflection ║
-- ║           can catch and shows when a press is in time.   ║
-- ║  Note: Warrior only. Needs BigWigs boss timers.          ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- Dungeon Timers' boss data, split text layout and countdown string load later
-- in Modules.xml, so they are read when used, never at file scope.

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class SpellReflect: AceModule, AceEvent-3.0
---@field db table
---@field frame table? the cue; created when the module first goes live or previews
---@field driver table? runs the step while a record is near
---@field records table records by bar text
---@field entries table spell entries by spell id, built when going live
---@field live boolean Spell Reflection is known and BigWigs is listened to
---@field watching boolean SPELL_UPDATE_COOLDOWN is registered
---@field bigWigsHooked boolean
---@field driving boolean the driver's OnUpdate is set
---@field ready boolean Spell Reflection's last ready reading
---@field isPreview boolean
---@field glowing boolean
---@field sample table? the preview's sample record
---@field shownRec table? the record painted last
---@field shownPhase string?
---@field shownReady boolean?
---@field lastCount string?
---@field lastLine string?
---@field wakeTimer table? runs a step when the next record reaches Lead
---@field evalPending boolean? a deferred loadout check is scheduled
---@field editModeRegistered boolean? true while the Edit Mode element is registered
---@field editModeFrame table? the frame the Edit Mode element was registered with
local SR = KitnEssentials:NewModule("SpellReflect", "AceEvent-3.0")
-- Gates the preview manager.
SR.classRestriction = "WARRIOR"

local Rules = KE.SpellReflectRules
local Ask = KE.PlateSlots.Ask
local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

local CreateFrame = CreateFrame
local C_Timer = C_Timer
local GetTime = GetTime
local PlaySoundFile = PlaySoundFile
local UnitClass = UnitClass
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local pairs, pcall, tostring, type = pairs, pcall, tostring, type
local math_floor, math_max = math.floor, math.max
local wipe = wipe

-- Flip to true, /reload, repro, read the log.
local DEBUG_SR = false

local REFLECT_ID = Rules.REFLECT_ID
local FALLBACK_ICON = 134400
local STEP = 0.05
-- Talent state is not reliable on the frame a talent event fires.
local TALENT_EVAL_DELAY = 2
local NAME_GAP = 3
local TEST_KEY = "__test"
local SAMPLE_ID, SAMPLE_NAME, SAMPLE_LEFT = 1297017, "Void Blast", 1.6
local GRAY = { 0.6, 0.6, 0.6, 1 }
local RED = { 1, 0.3, 0.3, 1 }

local EDIT_MODE_ELEMENT = {
    key = "SpellReflect",
    displayName = "Spell Reflect",
    guiPath = "ClassTools",
    guiTab = "SpellReflect",
}

local BIGWIGS_HANDLERS = {
    BigWigs_Timer = "OnBigWigsTimer",
    BigWigs_StartBar = "OnBigWigsStartBar",
    BigWigs_StopBar = "OnBigWigsStopBar",
    BigWigs_Message = "OnBigWigsMessage",
    BigWigs_PauseBar = "OnBigWigsPauseBar",
    BigWigs_ResumeBar = "OnBigWigsResumeBar",
    BigWigs_StopBars = "OnBigWigsClear",
    BigWigs_OnBossWin = "OnBigWigsClear",
    BigWigs_OnBossWipe = "OnBigWigsClear",
    BigWigs_OnBossDisable = "OnBigWigsClear",
}

local function IsSecret(value)
    return KE:IsSecretValue(value)
end

local function IsKnown(spellID)
    return Ask(C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook, spellID)
end

-- Not wrapped in pcall: the API allows tainted callers, and every id passed
-- is a plain number from the spell list.
local function SpellIcon(spellID)
    local getTexture = C_Spell and C_Spell.GetSpellTexture
    local icon = getTexture and getTexture(spellID)
    if not IsSecret(icon) and icon then return icon end
    return FALLBACK_ICON
end

local function ColorFor(db, key)
    if key == "GO" then return db.GoColor end
    if key == "GRAY" then return GRAY end
    return db.TextColor
end

local function SetColor(fontString, color)
    fontString:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
end

local function ModeOf(spellId)
    return Rules.ModeOf(SR.db and SR.db.Modes, spellId)
end

local function OnDriverUpdate(driver, elapsed)
    driver.acc = driver.acc + elapsed
    if driver.acc < STEP then return end
    driver.acc = 0
    SR:Step()
end

local function WakeStep()
    SR.wakeTimer = nil
    if SR.live then SR:Step() end
end

local function DeferredEvaluate()
    SR.evalPending = nil
    if SR:IsEnabled() then SR:Evaluate() end
end

local function SampleEntry()
    local entry = SR.entries[SAMPLE_ID]
    if entry then return entry end
    local open, close = Rules.Window(SAMPLE_ID, 0)
    return { id = SAMPLE_ID, name = SAMPLE_NAME, open = open, close = close }
end

---------------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------------
function SR:UpdateDB()
    self.db = KE.db.profile.SpellReflect
end

function SR:OnInitialize()
    self:UpdateDB()
    self.records, self.entries = {}, {}
    self.live, self.watching, self.bigWigsHooked, self.driving = false, false, false, false
    self.ready, self.isPreview, self.glowing = true, false, false
    self:SetEnabledState(false)
end

function SR:CreateFrame_()
    if self.frame then return end
    local frame = CreateFrame("Frame", "KE_SpellReflect", UIParent)
    frame:SetSize(56, 56)
    frame:Hide()

    local iconBox = CreateFrame("Frame", nil, frame)
    iconBox:SetAllPoints(frame)
    iconBox.icon = iconBox:CreateTexture(nil, "ARTWORK")
    iconBox.icon:SetAllPoints(iconBox)
    iconBox.icon:SetTexture(SpellIcon(REFLECT_ID))
    KE:ApplyIconZoom(iconBox.icon)
    KE:AddIconBorders(iconBox, { 0, 0, 0, 1 })
    iconBox.cooldown = CreateFrame("Cooldown", nil, iconBox, "CooldownFrameTemplate")
    iconBox.cooldown:SetAllPoints(iconBox)
    iconBox.cooldown:SetDrawEdge(false)
    iconBox.cooldown:SetDrawBling(false)
    iconBox.cooldown:SetHideCountdownNumbers(true)
    iconBox.cooldown:Hide()
    -- Above the sweep, so the count stays readable.
    local textLayer = CreateFrame("Frame", nil, iconBox)
    textLayer:SetAllPoints(iconBox)
    textLayer:SetFrameLevel(iconBox.cooldown:GetFrameLevel() + 1)
    iconBox.count = textLayer:CreateFontString(nil, "OVERLAY")
    iconBox.count:SetPoint("CENTER")
    iconBox.name = textLayer:CreateFontString(nil, "OVERLAY")
    iconBox.name:SetPoint("TOP", iconBox, "BOTTOM", 0, -NAME_GAP)
    iconBox.sides = {}
    for i = 1, 2 do
        local side = CreateFrame("Frame", nil, textLayer)
        side.icon = side:CreateTexture(nil, "ARTWORK")
        side.icon:SetAllPoints(side)
        KE:ApplyIconZoom(side.icon)
        KE:AddIconBorders(side, { 0, 0, 0, 1 })
        iconBox.sides[i] = side
    end
    iconBox.sides[1]:SetPoint("RIGHT", iconBox.name, "LEFT", -NAME_GAP, 0)
    iconBox.sides[2]:SetPoint("LEFT", iconBox.name, "RIGHT", NAME_GAP, 0)
    frame.iconBox = iconBox

    local textBox = CreateFrame("Frame", nil, frame)
    textBox:SetAllPoints(frame)
    textBox.label = textBox:CreateFontString(nil, "OVERLAY")
    textBox.timer = textBox:CreateFontString(nil, "OVERLAY")
    textBox.line = textBox:CreateFontString(nil, "OVERLAY")
    textBox.line:SetPoint("TOP", textBox, "BOTTOM", 0, -2)
    local small = CreateFrame("Frame", nil, textBox)
    small.icon = small:CreateTexture(nil, "ARTWORK")
    small.icon:SetAllPoints(small)
    small.icon:SetTexture(SpellIcon(REFLECT_ID))
    KE:ApplyIconZoom(small.icon)
    KE:AddIconBorders(small, { 0, 0, 0, 1 })
    textBox.iconFrame = small
    textBox:Hide()
    frame.textBox = textBox

    self.frame = frame
    self.driver = CreateFrame("Frame")
    self.driver.acc = 0
end

function SR:BuildEntries()
    local entries = self.entries
    wipe(entries)
    for spellId, data in pairs(Rules.Index(KE.EncounterData)) do
        local open, close = Rules.Window(spellId, data.castLength)
        entries[spellId] = { id = spellId, name = data.name, open = open, close = close }
    end
end

---------------------------------------------------------------------------------
-- Position and Edit Mode
---------------------------------------------------------------------------------
function SR:ApplyPosition()
    if self.frame then KE:ApplyFramePosition(self.frame, self.db.Position, self.db) end
end

-- Every unregister goes through here. The cache below is what makes a repeat
-- RegisterAnchor a no-op, so dropping the key without clearing it would block
-- re-registration for the rest of the session.
function SR:UnregisterAnchor()
    KE.EditMode:UnregisterElement("SpellReflect")
    self.editModeRegistered = nil
    self.editModeFrame = nil
end

function SR:RegisterAnchor()
    if not (self.live or self.isPreview) then
        self:UnregisterAnchor()
        return
    end
    -- Re-registering the same frame would cancel a drag in progress.
    if self.editModeRegistered and self.editModeFrame == self.frame then return end

    local cfg = {}
    for k, v in pairs(EDIT_MODE_ELEMENT) do cfg[k] = v end
    cfg.frame = self.frame
    cfg.module = self
    cfg.getPosition = function() return self.db.Position end
    -- A drag is computed in the frame Anchored To resolves to.
    cfg.getParentFrame = function()
        return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame)
    end
    cfg.setPosition = function(pos)
        local p = self.db.Position
        p.AnchorFrom, p.AnchorTo = pos.AnchorFrom, pos.AnchorTo
        p.XOffset, p.YOffset = pos.XOffset, pos.YOffset
        self:ApplyPosition()
    end
    KE.EditMode:RegisterElement(cfg)
    self.editModeRegistered = true
    self.editModeFrame = self.frame
end

---------------------------------------------------------------------------------
-- Style
---------------------------------------------------------------------------------
function SR:TextMode()
    return self.db.DisplayMode == "TEXT"
end

function SR:ApplyStyle()
    local frame, db = self.frame, self.db
    if not frame then return end
    local face, outline = db.FontFace, db.FontOutline
    local iconBox, textBox = frame.iconBox, frame.textBox
    self:StopGlow()
    if self:TextMode() then
        local size = db.TextSize or 30
        frame:SetSize(size * 8, size + 4)
        KE:ApplyFontToText(textBox.label, face, size, outline)
        KE:ApplyFontToText(textBox.timer, face, size, outline)
        KE:ApplyFontToText(textBox.line, face, math_max(10, math_floor(size / 2)), outline)
        textBox.iconFrame:SetSize(size, size)
        KE.ApplySplitTextLayout(textBox, textBox.label, textBox.timer, textBox.iconFrame, true, "CENTER")
        iconBox:Hide()
        textBox:Show()
    else
        local size = db.IconSize or 56
        local nameSize = db.NameFontSize or 14
        frame:SetSize(size, size)
        KE:ApplyFontToText(iconBox.count, face, db.FontSize or 26, outline)
        KE:ApplyFontToText(iconBox.name, face, nameSize, outline)
        for i = 1, 2 do iconBox.sides[i]:SetSize(nameSize, nameSize) end
        textBox:Hide()
        iconBox:Show()
    end
    self.shownRec, self.shownPhase, self.shownReady, self.lastCount, self.lastLine = nil, nil, nil, nil, nil
end

function SR:StartGlow()
    if self.glowing or not LCG then return end
    LCG.PixelGlow_Start(self.frame.iconBox, self.db.GlowColor, 8, 0.25, nil, 2, 0, 0, true, nil)
    self.glowing = true
end

function SR:StopGlow()
    if not self.glowing then return end
    if LCG and self.frame then LCG.PixelGlow_Stop(self.frame.iconBox) end
    self.glowing = false
end

---------------------------------------------------------------------------------
-- Cooldown
---------------------------------------------------------------------------------
function SR:ApplySweep()
    if not self.frame then return end
    local cooldown = self.frame.iconBox.cooldown
    if self.ready then
        cooldown:Clear()
        return
    end
    local getDuration = C_Spell and C_Spell.GetSpellCooldownDuration
    local duration = getDuration and getDuration(REFLECT_ID, true)
    if duration then
        cooldown:SetCooldownFromDurationObject(duration, false)
    else
        cooldown:Clear()
    end
end

-- Only isActive and isOnGCD are read; neither is ever secret. isOnGCD is
-- trustworthy only inside SPELL_UPDATE_COOLDOWN, so any other read uses
-- isActive alone and never counts as a press.
function SR:ReadCooldown(fromEvent)
    local getCooldown = C_Spell and C_Spell.GetSpellCooldown
    local info = getCooldown and getCooldown(REFLECT_ID)
    local isActive, isOnGCD
    if type(info) == "table" then
        isActive = info.isActive
        if fromEvent then isOnGCD = info.isOnGCD end
    end
    local wasReady = self.ready
    if fromEvent and Rules.IsPress(wasReady, isActive, isOnGCD) then
        local marked = Rules.MarkPressed(self.records, GetTime())
        if DEBUG_SR then KE:Print("[SR] press, records done: " .. marked) end
    end
    self.ready = Rules.IsReady(isActive, isOnGCD)
    if self.ready ~= wasReady then self:ApplySweep() end
end

function SR:OnCooldownUpdate()
    self:ReadCooldown(true)
    self:Step()
end

-- The cooldown is listened to only while a record is near.
function SR:SyncWatch(on)
    if on == self.watching then return end
    self.watching = on
    if on then
        self:RegisterEvent("SPELL_UPDATE_COOLDOWN", "OnCooldownUpdate")
        self:ReadCooldown(false)
        self:ApplySweep()
    else
        self:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
    end
end

---------------------------------------------------------------------------------
-- Paint
---------------------------------------------------------------------------------
function SR:PlaySound(key)
    if not key or key == "None" or not KE.LSM then return end
    local path = KE.LSM:Fetch("sound", key, true)
    if path then pcall(PlaySoundFile, path, "Master") end
end

function SR:PaintIconState(rec, colorKey, notReady, glow)
    local db, box = self.db, self.frame.iconBox
    SetColor(box.count, ColorFor(db, colorKey))
    if notReady then
        box.icon:SetVertexColor(RED[1], RED[2], RED[3])
    else
        box.icon:SetVertexColor(1, 1, 1)
    end
    local showName = notReady or db.ShowSpellName ~= false
    box.name:SetShown(showName)
    if showName then
        box.name:SetText(notReady and Rules.NOT_READY or (rec.name or ""))
        SetColor(box.name, notReady and RED or db.TextColor)
    end
    local sides = showName and not notReady and db.ShowNameIcons ~= false
    local texture = sides and SpellIcon(rec.id) or nil
    for i = 1, 2 do
        box.sides[i]:SetShown(sides)
        if texture then box.sides[i].icon:SetTexture(texture) end
    end
    box.cooldown:SetShown(notReady)
    if glow and db.Glow ~= false then self:StartGlow() else self:StopGlow() end
end

function SR:PaintTextState(label, colorKey, notReady)
    local db, box = self.db, self.frame.textBox
    local color = notReady and RED or ColorFor(db, colorKey)
    box.label:SetText(label)
    SetColor(box.label, color)
    SetColor(box.timer, color)
    SetColor(box.line, notReady and GRAY or db.TextColor)
end

-- State parts are set only when the record, its phase or the ready state
-- changes; the count and the small line only when their string changes.
function SR:Paint(rec, now, ready, silent)
    local db, frame = self.db, self.frame
    local phase = Rules.Phase(rec, now)
    local word, colorKey, notReady, glow = Rules.Look(phase, ready)
    local count = word and Rules.NOW_WORD or KE.FormatSplitTimer((Rules.Countdown(rec, now)))
    local changed = rec ~= self.shownRec or phase ~= self.shownPhase or ready ~= self.shownReady
    if changed then
        self.shownRec, self.shownPhase, self.shownReady = rec, phase, ready
        self.lastCount, self.lastLine = nil, nil
    end
    if self:TextMode() then
        local box = frame.textBox
        local label, timer, line = Rules.TextLines(word, notReady, count, rec.name or "")
        if changed then self:PaintTextState(label, colorKey, notReady) end
        if timer ~= self.lastCount then
            box.timer:SetText(timer)
            self.lastCount = timer
        end
        if line ~= self.lastLine then
            box.line:SetText(line)
            self.lastLine = line
        end
    else
        if changed then self:PaintIconState(rec, colorKey, notReady, glow) end
        if count ~= self.lastCount then
            frame.iconBox.count:SetText(count)
            self.lastCount = count
        end
    end
    if not frame:IsShown() then frame:Show() end
    if not silent then
        local sound = Rules.SoundFor(rec, phase, ready)
        if sound == "READY" then
            self:PlaySound(db.ReadySound)
        elseif sound == "NOT_READY" then
            self:PlaySound(db.NotReadySound)
        end
    end
end

function SR:HideCue()
    if not self.frame then return end
    self:StopGlow()
    self.frame:Hide()
    self.shownRec, self.shownPhase, self.shownReady, self.lastCount, self.lastLine = nil, nil, nil, nil, nil
end

function SR:PaintSample()
    local now = GetTime()
    local sample = self.sample
    if not sample then
        sample = Rules.NewTest(SampleEntry(), now)
        self.sample = sample
    end
    sample.ends, sample.born = now + SAMPLE_LEFT, now
    self:Paint(sample, now, true, true)
end

---------------------------------------------------------------------------------
-- Driver
---------------------------------------------------------------------------------
function SR:SetDriving(on)
    if on == self.driving or not self.driver then return end
    self.driving = on
    if on then
        self.driver.acc = 0
        self.driver:SetScript("OnUpdate", OnDriverUpdate)
    else
        self.driver:SetScript("OnUpdate", nil)
    end
end

function SR:ScheduleWake(delay)
    if self.wakeTimer then
        self.wakeTimer:Cancel()
        self.wakeTimer = nil
    end
    if delay then self.wakeTimer = C_Timer.NewTimer(math_max(delay, STEP), WakeStep) end
end

-- One pass: drop finished records and those of spells set to Off, show the
-- one that wins, and keep the cooldown watch, the per-frame step and the
-- wake as Rules.Schedule asks for each record.
function SR:Step()
    if not self.frame then return end
    local now, db, records = GetTime(), self.db, self.records
    local near, ticking, wake = false, false, nil
    for text, rec in pairs(records) do
        local phase = Rules.Phase(rec, now)
        if phase == "OVER" or (not rec.test and ModeOf(rec.id) == "OFF") then
            if DEBUG_SR then KE:Print("[SR] dropped " .. tostring(rec.name)) end
            records[text] = nil
        else
            local lead = rec.test and Rules.TEST_LEAD or db.Lead
            local isNear, ticks, due = Rules.Schedule(rec, phase, now, lead)
            if isNear then near = true end
            if ticks then
                ticking = true
            elseif not wake or due < wake then
                wake = due
            end
        end
    end

    self:SyncWatch(near)
    local best
    if not self.isPreview or records[TEST_KEY] then
        local dead = Ask(UnitIsDeadOrGhost, "player") == true
        best = Rules.Pick(records, now, db.Lead, ModeOf, self.ready, dead)
    end
    if best then
        self:Paint(best, now, self.ready, false)
    elseif self.isPreview then
        self:PaintSample()
    else
        self:HideCue()
    end
    self:SetDriving(ticking)
    self:ScheduleWake((not ticking) and wake or nil)
end

---------------------------------------------------------------------------------
-- BigWigs
---------------------------------------------------------------------------------
function SR:StartBar(owner, key, duration, text)
    if not Rules.PayloadReadable(IsSecret, owner, key, duration, text) then return end
    if type(key) ~= "number" or type(duration) ~= "number" or duration <= 0 or type(text) ~= "string" then
        return
    end
    local entry = self.entries[key]
    if not entry or ModeOf(key) == "OFF" then return end
    Rules.Start(self.records, entry, owner, text, duration, GetTime())
    if DEBUG_SR then
        KE:Print(("[SR] bar %d %s, text %q, %.1f s"):format(key, tostring(entry.name), text, duration))
    end
    self:Step()
end

function SR:OnBigWigsTimer(_, owner, key, duration, _, text)
    self:StartBar(owner, key, duration, text)
end

function SR:OnBigWigsStartBar(_, owner, key, text, duration)
    self:StartBar(owner, key, duration, text)
end

-- The time to zero is logged before the record changes, so the stop and
-- message timing can be checked against the bar's own zero.
local function LogTiming(what, rec, now)
    if not (DEBUG_SR and rec) then return end
    local toZero = rec.left or (rec.ends - now)
    KE:Print(("[SR] %s %s, %.2f s to zero"):format(what, tostring(rec.name), toZero))
end

function SR:OnBigWigsStopBar(_, _, text)
    if IsSecret(text) or type(text) ~= "string" then return end
    local now = GetTime()
    LogTiming("stop", self.records[text], now)
    local result = Rules.Stop(self.records, text, now)
    if not result then return end
    if DEBUG_SR then KE:Print("[SR] stop: " .. result) end
    self:Step()
end

function SR:OnBigWigsMessage(_, _, _, text)
    if IsSecret(text) or type(text) ~= "string" then return end
    local now = GetTime()
    LogTiming("message", self.records[text], now)
    if not Rules.Said(self.records, text, now) then return end
    if DEBUG_SR then KE:Print("[SR] cast started by message") end
    self:Step()
end

function SR:PauseBar(text, paused)
    if IsSecret(text) or type(text) ~= "string" then return end
    if Rules.Pause(self.records, text, GetTime(), paused) then
        if DEBUG_SR then KE:Print("[SR] " .. (paused and "pause " or "resume ") .. text) end
        self:Step()
    end
end

function SR:OnBigWigsPauseBar(_, _, text)
    self:PauseBar(text, true)
end

function SR:OnBigWigsResumeBar(_, _, text)
    self:PauseBar(text, false)
end

function SR:OnBigWigsClear(event, owner)
    if IsSecret(owner) or owner == nil then return end
    Rules.Clear(self.records, owner)
    if DEBUG_SR then KE:Print("[SR] cleared by " .. tostring(event)) end
    self:Step()
end

function SR:OnClearAll(event)
    Rules.Clear(self.records, nil)
    if DEBUG_SR then KE:Print("[SR] cleared all by " .. tostring(event)) end
    self:Step()
end

function SR:HookBigWigs(on)
    if on == self.bigWigsHooked then return end
    local loader = BigWigsLoader
    if not (loader and loader.RegisterMessage and loader.UnregisterMessage) then return end
    for message, method in pairs(BIGWIGS_HANDLERS) do
        if on then
            loader.RegisterMessage(self, message, method)
        else
            loader.UnregisterMessage(self, message)
        end
    end
    self.bigWigsHooked = on
end

---------------------------------------------------------------------------------
-- Activation
---------------------------------------------------------------------------------
function SR:SetLive(on)
    if on == self.live then return end
    self.live = on
    self:HookBigWigs(on)
    if on then
        self:RegisterEvent("ENCOUNTER_END", "OnClearAll")
    else
        self:UnregisterEvent("ENCOUNTER_END")
        Rules.Clear(self.records, nil)
        self:ScheduleWake(nil)
        self:SetDriving(false)
        self:SyncWatch(false)
    end
end

function SR:Evaluate()
    if not self:IsEnabled() then return end
    if IsKnown(REFLECT_ID) == true then
        self:BuildEntries()
        self:CreateFrame_()
        self:SetLive(true)
        self:ApplyPosition()
        self:ApplyStyle()
        self:RegisterAnchor()
        self:Step()
    else
        self:SetLive(false)
        if self.frame and not self.isPreview then
            self:HideCue()
            self:UnregisterAnchor()
        end
    end
end

function SR:OnTalentChanged()
    if self.evalPending then return end
    self.evalPending = true
    C_Timer.After(TALENT_EVAL_DELAY, DeferredEvaluate)
end

-- The event fires for every group member; a unit flagged secret could be the
-- player, so it counts as the player's own.
function SR:OnSpecChanged(_, unit)
    if IsSecret(unit) or unit == "player" then self:OnTalentChanged() end
end

function SR:OnEnteringWorld(event)
    self:OnClearAll(event)
    if not self.live then self:OnTalentChanged() end
end

function SR:ApplySettings()
    self:UpdateDB()
    if self.db.Enabled then
        if not self:IsEnabled() then
            KitnEssentials:EnableModule("SpellReflect")
        elseif self.isPreview then
            -- The step paints only the sample while previewing, so repaint it.
            self:ShowPreview()
        else
            self:Evaluate()
        end
    elseif self:IsEnabled() then
        KitnEssentials:DisableModule("SpellReflect")
    end
end

function SR:Test()
    local _, class = UnitClass("player")
    if class ~= "WARRIOR" then
        KE:Print("Spell Reflect is Warrior only.")
        return
    end
    if not self.live then
        KE:Print("Spell Reflect starts once Spell Reflection is learned.")
        return
    end
    self.records[TEST_KEY] = Rules.NewTest(SampleEntry(), GetTime())
    self:Step()
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function SR:OnEnable()
    self:UpdateDB()
    -- Class before anything else: a non-warrior gets no events, frame or mover.
    local _, class = UnitClass("player")
    if class ~= "WARRIOR" then return end

    self:RegisterEvent("PLAYER_TALENT_UPDATE", "OnTalentChanged")
    self:RegisterEvent("TRAIT_CONFIG_UPDATED", "OnTalentChanged")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnSpecChanged")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnteringWorld")
    self:Evaluate()
    -- At login the spellbook may not be readable yet; a second pass catches it.
    self:OnTalentChanged()
end

function SR:OnDisable()
    self:UnregisterAllEvents()
    self.watching = false
    self:HookBigWigs(false)
    self.live = false
    Rules.Clear(self.records, nil)
    self:ScheduleWake(nil)
    self:SetDriving(false)
    self:HideCue()
    self.isPreview = false
    self:UnregisterAnchor()
end

---------------------------------------------------------------------------------
-- Preview (PreviewManager contract)
---------------------------------------------------------------------------------
-- A placement sample in the current display mode: a Void Blast in its window.
function SR:ShowPreview()
    self:UpdateDB()
    self:CreateFrame_()
    self.isPreview = true
    self:ApplyPosition()
    self:ApplyStyle()
    self:PaintSample()
    self:RegisterAnchor()
end

-- Also called on a disabled module during section changes, so every path is
-- safe without a live display.
function SR:HidePreview()
    self.isPreview = false
    if self:IsEnabled() then
        self:Evaluate()
        return
    end
    if not self.frame then return end
    self:HideCue()
    self:UnregisterAnchor()
end
