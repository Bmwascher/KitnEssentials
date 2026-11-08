-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/QoL/Campfire/Campfire.lua                       ║
-- ║  Module: Campfire                                        ║
-- ║  Purpose: Shows what the camp buff is doing and whether  ║
-- ║           a fire is worth stopping at, in the open       ║
-- ║           world. Event-driven: no Lua runs per frame.    ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class Campfire: AceModule
local CF = KitnEssentials:NewModule("Campfire")

local Rules = KE.CampfireRules
local Views = KE.CampfireViews
local Buttons = KE.CampfireButtons

local C_Item = C_Item
local C_Spell = C_Spell
local C_Timer = C_Timer
local C_TooltipInfo = C_TooltipInfo
local C_UnitAuras = C_UnitAuras
local CreateFrame = CreateFrame
local GetTime = GetTime
local IsInInstance = IsInInstance
local IsMounted = IsMounted
local IsResting = IsResting
local PlaySoundFile = PlaySoundFile
local UIParent = UIParent
local UnitAffectingCombat = UnitAffectingCombat
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitOnTaxi = UnitOnTaxi
local floor, huge, max = math.floor, math.huge, math.max
local ipairs, pairs, pcall = ipairs, pairs, pcall

local FEATURES = Rules.FEATURES
local EMPTY = {}

local TIP_RETRY = 5
local THRESHOLD_PAD = 0.1

local WORLD_EVENTS = {
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "ADDON_RESTRICTION_STATE_CHANGED",
    "PLAYER_UPDATE_RESTING", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
    "PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED",
}

-- What each shape-showing moment draws. timed: the buff's time. list: a bonus
-- list. dots: the checklist.
local LOOK = {
    Sitting = { fire = "catching", list = true, dots = true },
    Landing = { fire = "lit", timed = true, list = true },
    Passing = { fire = "lit", timed = true, list = true, dots = true },
    Spare = { fire = "lit", timed = true, list = true, dots = true },
    Low = { fire = "lit", timed = true, list = true },
    Shown = { fire = "lit", timed = true, list = true },
    FireHere = { fire = "lit", list = true, dots = true },
    NoCamp = { fire = "gray" },
}

CF.PREVIEW_CHOICES = {
    { key = "Low", text = "Running low" },
    { key = "Passing", text = "Passing a fire" },
    { key = "NoCamp", text = "Buff gone, no fire" },
    { key = "FireHere", text = "Buff gone, fire here" },
    { key = "Sitting", text = "Sitting" },
    { key = "Sitting12", text = "Sitting, 12 bonuses" },
    { key = "Landing", text = "Buff lands" },
    { key = "Combat", text = "In combat" },
}
-- Live play reaches Time to spare only once the refill is proven.
if Rules.REFILL_PROVEN then
    table.insert(CF.PREVIEW_CHOICES, 3, { key = "Spare", text = "Time to spare" })
end
local DEFAULT_PREVIEW = "Low"
CF.previewChoice = DEFAULT_PREVIEW

-- have: bonuses already held. fresh: new ones, which only a landing shows,
-- since a fire's bonuses read only once the buff lands. worst: all 12 held.
-- cover: one line dims and one dot is half, so the dim look can be judged.
local PREVIEW_SAMPLES = {
    Low = { moment = "Low", left = 240, duration = 3600, have = true },
    Passing = { moment = "Passing", left = 720, duration = 3600, have = true, near = true, cover = true },
    Spare = { moment = "Spare", left = 2400, duration = 3600, have = true, near = true },
    NoCamp = { moment = "NoCamp" },
    FireHere = { moment = "FireHere", near = true },
    Sitting = { moment = "Sitting", seat = 44, seatDuration = 60, left = 720, duration = 3600,
        have = true, near = true, cover = true },
    Sitting12 = { moment = "Sitting", seat = 44, seatDuration = 60, left = 720, duration = 3600,
        worst = true, near = true },
    Landing = { moment = "Landing", left = 3600, duration = 3600, have = true, fresh = true },
    Combat = { moment = "Low", left = 240, duration = 3600, have = true, combat = true },
}

local SAMPLE_HAVE = { { "Sta", 56 }, { "Int", 25 } }
local SAMPLE_FRESH = { { "Crit", 2 }, { "MP5", 29 }, { "AP", 20 } }
local SAMPLE_WORST = {
    { "Rested" }, { "Str", 34 }, { "Sta", 56 }, { "Int", 25 }, { "Spi", 32 }, { "Stats", 8 },
    { "Armor", 260 }, { "AP", 60 }, { "SP", 40 }, { "Crit", 2 }, { "MP5", 29 }, { "Disenchant" },
}
local SAMPLE_COVERER = "Power Word: Fortitude"

---------------------------------------------------------------------------------
-- Reads
---------------------------------------------------------------------------------

-- Returns the aura, and true when the read is hidden.
local function ReadCampAura(spellId)
    if KE:IsAuraHiddenForSpell(spellId) then return nil, true end
    local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellId)
    if KE:IsSecretValue(aura) then return nil, true end
    if not aura then return nil, false end
    if KE:IsSecretTable(aura) then return nil, true end
    return aura, false
end

-- Returns expiry and duration, and true when either reads secret.
local function TimesOf(aura)
    local expiry, duration = aura.expirationTime, aura.duration
    if KE:IsSecretValue(expiry) or KE:IsSecretValue(duration) then return nil, nil, true end
    if not expiry or not duration or expiry <= 0 or duration <= 0 then return nil, nil, false end
    return expiry, duration, false
end

local function PlayNamed(name)
    if not name or name == "None" or not KE.LSM then return end
    local path = KE.LSM:Fetch("sound", name, true)
    if path then pcall(PlaySoundFile, path, "Master") end
end

local function CountOf(itemId)
    local count = C_Item.GetItemCount(itemId)
    if KE:IsSecretValue(count) or count == nil then return 0 end
    return count
end

local function UsableOf(itemId)
    local usable = C_Item.IsUsableItem(itemId)
    if KE:IsSecretValue(usable) then return false end
    return usable and true or false
end

local function ReadStacks()
    local aura = ReadCampAura(Rules.WELL_RESTED)
    if not aura then return nil end
    local stacks = aura.applications
    if KE:IsSecretValue(stacks) then return nil end
    return stacks or 0
end

-- Well-Rested for the bag button: false when unreadable, else known with expiry and
-- duration nil when it is gone.
local function ReadRest(rest)
    local aura, hidden = ReadCampAura(Rules.WELL_RESTED)
    rest.expiry, rest.duration, rest.stacks = nil, nil, 0
    if hidden then return false end
    if not aura then return true end
    local expiry, duration, secret = TimesOf(aura)
    local stacks = aura.applications
    if secret or KE:IsSecretValue(stacks) then return false end
    rest.expiry, rest.duration, rest.stacks = expiry, duration, stacks or 0
    return true
end

local function IsWellFed()
    local food = KE.ReadyCheckConsumablesForever and KE.ReadyCheckConsumablesForever.food
    if not food then return false end
    for id in pairs(food) do
        if ReadCampAura(id) then return true end
    end
    return false
end

local function PlainSpellName(spellId)
    local name = C_Spell.GetSpellName(spellId)
    if KE:IsSecretValue(name) then return nil end
    return name
end

function CF:NameIndex()
    if not self.nameIndex then
        self.nameIndex = Rules.NameIndex(FEATURES, PlainSpellName)
    end
    return self.nameIndex
end

-- Returns the parsed lines, and whether any readable text came back past the
-- title. Text that parses to nothing counts as read, so a tooltip of another
-- shape does not keep retrying.
function CF:ReadTipLines(instanceId)
    local lines = {}
    if not instanceId or KE:AreAuraIdentitiesHidden() then return lines, false end
    local data = C_TooltipInfo.GetUnitBuffByAuraInstanceID("player", instanceId)
    if KE:IsSecretValue(data) or not data or KE:IsSecretTable(data) then return lines, false end
    local tipLines = data.lines
    if KE:IsSecretValue(tipLines) or not tipLines or KE:IsSecretTable(tipLines) then return lines, false end
    local index = self:NameIndex()
    local complete = false
    for n = 2, #tipLines do
        local text = tipLines[n].leftText
        if not KE:IsSecretValue(text) and text and text ~= "" then
            complete = true
            for piece in text:gmatch("[^\n]+") do
                local feature, amounts = Rules.ParseBonusLine(piece, index)
                if feature then lines[#lines + 1] = { feature = feature, amounts = amounts } end
            end
        end
    end
    return lines, complete
end

function CF:ReadCamp()
    -- A secret aura reads as nothing, so while auras are secret no read can
    -- tell a buff that is up from one that is gone.
    if KE:AreAuraIdentitiesHidden() then return false end
    local benefits, hidden = ReadCampAura(Rules.CAMP_BENEFITS)
    if hidden then return false end
    local inRange
    inRange, hidden = ReadCampAura(Rules.IN_RANGE)
    if hidden then return false end

    local expiry, duration, secret, instanceId
    if benefits then
        expiry, duration, secret = TimesOf(benefits)
        if secret then return false end
        instanceId = benefits.auraInstanceID
        if KE:IsSecretValue(instanceId) then instanceId = nil end
    end

    local seated, seatExpiry, seatDuration = false, nil, nil
    for _, id in ipairs(Rules.SEATED) do
        local aura
        aura, hidden = ReadCampAura(id)
        if hidden then return false end
        if aura and not seated then
            seatExpiry, seatDuration, secret = TimesOf(aura)
            if secret then return false end
            seated = true
        end
    end

    local c = self.camp
    c.buffUp = benefits ~= nil
    c.expiry, c.duration, c.instance = Rules.SteadyExpiry(c.expiry, expiry), duration, instanceId
    c.left = c.expiry and (c.expiry - GetTime()) or huge
    c.inRange = inRange ~= nil
    c.seated, c.seatDuration = seated, seatDuration
    c.seatExpiry = Rules.SteadyExpiry(c.seatExpiry, seatExpiry)
    return true
end

function CF:ReadDots(c)
    local stacks = ReadStacks()
    local maxStacks = Rules.WELL_RESTED_STACKS
    local restedState = Rules.DotState(stacks ~= nil, stacks, maxStacks)
    return {
        { name = "Camp Benefits", state = Rules.DotState(c.buffUp) },
        { name = "Well Fed", state = Rules.DotState(IsWellFed()) },
        { name = "Well-Rested", state = restedState,
            note = restedState == "part" and (stacks .. "/" .. maxStacks) or nil },
    }
end

function CF:ReadCovers()
    -- A hidden read says nothing: the last result holds and coverDirty stays set.
    if KE:AreAuraIdentitiesHidden() then return end
    local onYou = {}
    for _, id in ipairs(Rules.COVER_IDS) do
        local name = self.coverNames[id]
        if not name then
            name = PlainSpellName(id)
            if name then self.coverNames[id] = name end
        end
        if name and not KE:IsAuraHiddenForSpell(name) then
            local aura = C_UnitAuras.GetAuraDataBySpellName("player", name, "HELPFUL")
            if not KE:IsSecretValue(aura) and aura then onYou[id] = name end
        end
    end
    self.onYou = onYou
    self.coverDirty = false
end

function CF:ReadCoversIfDirty()
    if self.coverDirty and self.db.DimCovered and not self.inCombat then self:ReadCovers() end
end

---------------------------------------------------------------------------------
-- The held set
---------------------------------------------------------------------------------

function CF:ReadHeldSet(c, landed, key)
    if landed then self.heldBefore = self.held end
    local tipLines, tipComplete = self:ReadTipLines(c.instance)
    local rows = Rules.TipRows(FEATURES, tipLines)
    if self.heldBefore then
        self.landedNew, self.landedKept = Rules.NewBonuses(self.heldBefore, rows)
        -- Kept until the tooltip has answered, so the retry can compute new again.
        if tipComplete then self.heldBefore = nil end
    end
    self.held = rows
    self.heldKey = key
    self.tipEmpty = not tipComplete
end

-- One armed at a time. A callback from an earlier lifecycle touches nothing.
function CF:ArmTipRetry()
    if self.tipRetryGen == self.lifeGen then return end
    self.tipRetryGen = self.lifeGen
    local gen = self.lifeGen
    C_Timer.After(TIP_RETRY, function()
        if gen ~= self.lifeGen then return end
        self.tipRetryGen = nil
        if not self:IsEnabled() or self.previewing or self.inCombat then return end
        local c = self.camp
        if not self.tipEmpty or not self.shownMoment or not c.buffUp then return end
        self:ReadHeldSet(c, false, self.heldKey)
        self:MarkDirty()
    end)
end

---------------------------------------------------------------------------------
-- One-shots
---------------------------------------------------------------------------------

function CF:ArmDirtyIn(delay)
    if delay <= 0 then return end
    local gen = self.thresholdGen
    C_Timer.After(delay + THRESHOLD_PAD, function()
        if gen == self.thresholdGen and self:IsEnabled() then self:MarkDirty() end
    end)
end

function CF:ArmColorStep(left)
    local step = Rules.NextColorStepIn(left)
    if not step then return end
    local gen = self.thresholdGen
    C_Timer.After(step + THRESHOLD_PAD, function()
        if gen ~= self.thresholdGen or not self:IsEnabled() then return end
        local expiry = self.camp.expiry
        if not expiry then return end
        local now = expiry - GetTime()
        -- A preview owns the views for now, and the chain has to outlast it.
        if not self.previewing then Views.SetColorKey(Rules.RingColorKey(now, false)) end
        self:ArmColorStep(now)
    end)
end

-- Armed once per expiry and threshold settings, however often a refresh asks.
function CF:ArmThresholds()
    local c, db = self.camp, self.db
    local key = c.expiry and (c.expiry .. ":" .. db.ShowUnderMinutes .. ":" .. db.AlertUnderMinutes) or nil
    if key == self.thresholdKey then return end
    self.thresholdKey = key
    self.thresholdGen = self.thresholdGen + 1
    if not key then return end
    local left = c.expiry - GetTime()
    self:ArmDirtyIn(left - db.ShowUnderMinutes * 60)
    self:ArmDirtyIn(left - db.AlertUnderMinutes * 60)
    local reachedIn = Rules.SitGainReachedIn(left, c.duration, Rules.REFILL_PROVEN)
    if reachedIn then self:ArmDirtyIn(reachedIn) end
    self:ArmColorStep(left)
end

-- The record stays until its one-shot fires, so an alert that leaves and comes
-- back within one minute arms nothing new.
function CF:ArmAlertText(expiry)
    self.alertTextLive = true
    local boundary = Rules.AlertMinuteEnd(expiry, expiry - GetTime())
    if self.alertBoundary == boundary then return end
    self.alertBoundary = boundary
    local gen = self.lifeGen
    C_Timer.After(max(boundary - GetTime(), 0) + THRESHOLD_PAD, function()
        if gen ~= self.lifeGen or self.alertBoundary ~= boundary then return end
        self.alertBoundary = nil
        if self.alertTextLive then self:MarkDirty() end
    end)
end

---------------------------------------------------------------------------------
-- The buff across refreshes
---------------------------------------------------------------------------------

function CF:TrackBuff(c)
    local db = self.db
    local prev, now = self.prevState, self.nowState
    prev.seated, prev.expiry = self.sat, self.lastExpiry
    now.expiry = c.expiry
    local landed = Rules.IsLanding(prev, now)

    -- Stays set until a landing: the seated aura can go before the buff lands.
    if c.seated then self.sat = true end
    if landed then
        self.sat = false
        self.landing = true
        self.landingEnds = GetTime() + Views.LANDING_TIME
        self.landingToken = self.landingToken + 1
        if db.LandSoundEnabled then PlayNamed(db.LandSound) end
    end
    if self.lastExpiry and not c.buffUp and db.LapseSoundEnabled then PlayNamed(db.LapseSound) end

    -- Each refresh, because a threshold changed during a preview has no event of
    -- its own, and the refresh that ends the preview is the first to act on it.
    self.lastExpiry = c.expiry
    self:ArmThresholds()

    if c.buffUp then
        local key = (c.instance or 0) .. ":" .. floor(c.expiry or 0)
        if key ~= self.heldKey then self:ReadHeldSet(c, landed, key) end
    else
        self.held, self.heldKey, self.tipEmpty, self.heldBefore = EMPTY, nil, false, nil
    end
end

---------------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------------

-- The fire's call to act: capitalized to open a label, lower case after
-- "Camp Nearby".
local function SitWords(db, capital)
    if not db.ClickToSit then return "Sit here" end
    return capital and "Click to sit" or "click to sit"
end

function CF:AlertText(s)
    local c = s.c
    if c.buffUp and c.expiry then
        return (Rules.AlertLine(c.expiry - GetTime(), c.duration, s.refill))
    end
    return SitWords(self.db, false)
end

function CF:FillRenderLook(r, s, look)
    local db, c, moment = self.db, s.c, s.moment
    local seated = moment == "Sitting"
    r.seated = seated
    r.expiry, r.duration = nil, nil
    if seated then
        r.expiry, r.duration = c.seatExpiry, c.seatDuration
    elseif look.timed and c.expiry then
        r.expiry, r.duration = c.expiry, c.duration
    end
    r.left = r.expiry and max(r.expiry - GetTime(), 0) or nil
    r.colorKey = nil
    if r.expiry then
        r.colorKey = moment == "Landing" and "good" or Rules.RingColorKey(r.left, seated)
    end
    r.fullRing = moment == "Landing"
    r.landingToken = moment == "Landing" and self.landingToken or nil
    r.fire = (seated and not r.expiry) and "lit" or look.fire
    r.share = (seated and r.expiry) and (1 - r.left / r.duration) or nil

    local sitText = SitWords(db, true)
    r.label, r.labelColor = nil, "soft"
    if seated then
        r.label = "Resting"
    elseif moment == "Landing" then
        r.label, r.labelColor = "Camp Benefits", "green"
    elseif moment == "Passing" or moment == "Spare" or moment == "FireHere" then
        r.label = sitText
    elseif moment == "NoCamp" then
        r.label, r.labelColor = "No camp", "muted"
    end

    local lines = Rules.BuildLines(s.newRows, s.keptRows, db.DimCovered, s.onYou, seated and "kept" or "plain")
    r.lines = lines
    r.dots = s.dots
    r.showList = (look.list and (not s.inCombat or db.ListInCombat) and (#lines > 0 or s.dots ~= nil)) and true or false

    r.simpleLines = moment == "FireHere" and EMPTY or lines
    r.simpleHead = nil
    if moment == "FireHere" then
        local words = SitWords(db, false)
        r.simpleHead = KE:ColorTextByTheme("Camp Nearby") .. " " .. Views.White(words)
    elseif moment == "NoCamp" then
        r.simpleHead = Views.Muted("No camp")
    elseif seated then
        r.simpleHead = Views.Muted("Resting")
    elseif moment == "Landing" and #lines == 0 then
        r.simpleHead = Views.Green("Camp Benefits")
    elseif #lines == 0 then
        r.simpleHead = Views.White("Camp Active") .. " " .. Views.Muted("no bonuses")
    end
    r.panel = (seated and db.Checklist and s.dots) or nil
end

function CF:Draw(s)
    local db, r = self.db, self.render
    local look = LOOK[s.moment]
    self.lastMoment = s.moment
    self.shownMoment = s.showShape and s.moment or nil

    r.showShape = s.showShape
    r.shape = db.Shape
    r.buffUp = s.c.buffUp
    r.near = s.near
    r.clickable = Rules.SitClickable(s.near, db, s.inCombat)
    r.alertText = s.showAlert and self:AlertText(s) or nil
    if look then
        self:FillRenderLook(r, s, look)
    else
        r.seated, r.expiry, r.lines, r.landingToken, r.fullRing = false, nil, nil, nil, false
    end
    Views.Render(r, db)
end

function CF:DrawNothing(moment)
    self.lastMoment = moment
    self.shownMoment = nil
    self.alertTextLive = false
    self.landing = false
    Views.HideAll()
end

---------------------------------------------------------------------------------
-- The refresh
---------------------------------------------------------------------------------

-- One runner per lifecycle, not one closure per dirty flag. A call queued before
-- a disable or an instance touches nothing, not even the new lifecycle's flag.
local function NewRefreshRunner(gen)
    return function()
        if gen ~= CF.lifeGen then return end
        CF.dirty = false
        if CF:IsEnabled() then CF:RefreshNow() end
    end
end

function CF:NewLife()
    self.lifeGen = (self.lifeGen or 0) + 1
    self.dirty = false
    self.runRefresh = NewRefreshRunner(self.lifeGen)
end

function CF:MarkDirty()
    if self.dirty then return end
    self.dirty = true
    C_Timer.After(0, self.runRefresh)
end

function CF:SetButtonEvent(event, wanted)
    local on = self.buttonEvents
    if (on[event] or false) == wanted then return end
    on[event] = wanted
    if wanted then
        self.eventFrame:RegisterEvent(event)
    else
        self.eventFrame:UnregisterEvent(event)
    end
end

-- No button shows in combat or during a preview. The refresh that follows either
-- one registers what is wanted again.
function CF:StopButtonEvents()
    self:SetButtonEvent("BAG_UPDATE_COOLDOWN", false)
    self:SetButtonEvent("BAG_UPDATE_DELAYED", false)
end

-- One-shots at each step of the current Well-Rested: color changes, the low
-- threshold that shows the bag away from a fire, and the end.
function CF:ArmRest()
    local expiry = self.rest.expiry
    if expiry == self.restKey then return end
    self.restKey = expiry
    self.restGen = self.restGen + 1
    if not expiry then return end
    local gen, left = self.restGen, expiry - GetTime()
    for _, step in ipairs(Rules.REST_STEPS) do
        if left > step then
            C_Timer.After(left - step + THRESHOLD_PAD, function()
                if gen == self.restGen and self:IsEnabled() then self:MarkDirty() end
            end)
        end
    end
end

function CF:SyncButtons(moment, near, c)
    local db, i, rest = self.db, self.inputs, self.rest
    local nearOrSeated = near or c.seated
    local known = not self.inCombat and ReadRest(rest)
    if known then self:ArmRest() end
    local restLow = known and not i.dead and not i.onTaxi
        and Rules.RestLow(rest.expiry and rest.expiry - GetTime() or nil)
    local first, second = Rules.ButtonCandidates(moment, nearOrSeated, self.inCombat, db, restLow)
    self:SetButtonEvent("BAG_UPDATE_DELAYED", first ~= nil)
    if self.inCombat then return end

    local carried = self.carried
    carried.bag = (first == "bag" or second == "bag") and CountOf(Rules.SLEEPING_BAG) > 0
    carried.kit = first == "kit" and Rules.BestKit(Rules.KITS, CountOf, UsableOf) or nil
    local wanted = Rules.ButtonWanted(moment, nearOrSeated, self.inCombat, db, carried, restLow)
    Buttons.Sync(wanted, carried.kit, db, wanted == "bag" and known and rest or nil)
    self:SetButtonEvent("BAG_UPDATE_COOLDOWN", wanted == "kit")
end

function CF:FillInputs(c)
    local i = self.inputs
    i.inInstance, i.held, i.preview = false, false, nil
    i.inCombat = self.inCombat
    i.dead = UnitIsDeadOrGhost("player")
    i.onTaxi = UnitOnTaxi("player")
    i.inRest = IsResting()
    i.mounted = IsMounted()
    i.buffUp, i.left, i.duration = c.buffUp, c.left, c.duration or 0
    i.seated, i.inRange = c.seated, c.inRange
    i.dismissed = self.dismissed
    i.landing = self.landing
    i.refillProven = Rules.REFILL_PROVEN
    i.settings = self.db
    return i
end

-- A read hidden or secret keeps the last view, trimmed for combat. A show
-- threshold crossed meanwhile still shows the shape, from the stored expiry.
function CF:ApplyHeld()
    self.lastMoment = "Held"
    self.alertTextLive = false
    self:ArmThresholds()
    Views.EnterHeld(self.inCombat, self.db.ListInCombat)
    local shown = self.shownMoment
    if shown == "FireHere" or shown == "NoCamp" then
        Views.HideShape()
        self.shownMoment = nil
    end
    local c = self.camp
    if self.shownMoment or not c.expiry then return end
    c.left = c.expiry - GetTime()
    if c.left <= 0 then return end
    local i = self:FillInputs(c)
    i.seated, i.inRange, i.landing = false, false, false
    local moment, showShape = Rules.SelectMoment(i)
    if moment ~= "Low" and moment ~= "Shown" then return end
    local s = self.scene
    s.moment, s.showShape, s.showAlert, s.near = moment, showShape, false, false
    s.c, s.newRows, s.keptRows, s.onYou, s.dots = c, EMPTY, self.held, self.onYou, nil
    s.inCombat, s.refill = self.inCombat, Rules.REFILL_PROVEN
    self:Draw(s)
    self.lastMoment = "Held"
end

function CF:RefreshNow()
    if self.previewing or self.inInstance ~= false then return end
    local db = self.db

    -- No aura read at all here: this is the path that works while they are hidden.
    if Rules.TimerHiddenInCombat(self.inCombat, db) then
        self:DrawNothing("Nothing")
        return
    end

    local c = self.camp
    if not self:ReadCamp() then
        self:ApplyHeld()
        return
    end
    self:TrackBuff(c)
    if not c.inRange then self.dismissed = false end
    -- A preview or a new sit can stop the animation, which then never reports its end.
    if self.landing and not Rules.LandingActive(self.landingEnds, GetTime()) then self.landing = false end

    -- A fire's bonuses read only from the tooltip once the buff lands, so between
    -- landings every row shown is a held one.
    local newRows, keptRows = EMPTY, self.held
    local i = self:FillInputs(c)
    local moment, showShape, showAlert, near = Rules.SelectMoment(i)

    local look = LOOK[moment]
    if look and look.list and showShape then self:ReadCoversIfDirty() end

    if moment ~= "Landing" and moment ~= "Sitting" then self.landing = false end
    if moment == "Landing" then
        newRows, keptRows = self.landedNew or EMPTY, self.landedKept or self.held
    end

    local s = self.scene
    s.moment, s.showShape, s.showAlert, s.near = moment, showShape, showAlert, near
    s.c, s.newRows, s.keptRows, s.onYou = c, newRows, keptRows, self.onYou
    s.inCombat, s.refill = self.inCombat, Rules.REFILL_PROVEN
    s.dots = nil
    if look and look.dots and db.Checklist and not self.inCombat
        and (db.Shape == "ROUND" or moment == "Sitting") then
        s.dots = self:ReadDots(c)
    end
    self:Draw(s)

    if showAlert and c.expiry then
        self:ArmAlertText(c.expiry)
    else
        self.alertTextLive = false
    end
    if self.tipEmpty and self.shownMoment and not self.inCombat then self:ArmTipRetry() end
    self:SyncButtons(moment, near, c)
end

---------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------

function CF:OnEvent(event, ...)
    if event == "UNIT_AURA" then
        local unit, info = ...
        if KE:IsUnreadableAuraPayload(unit, info) or info == nil or info.isFullUpdate
            or info.addedAuras or info.removedAuraInstanceIDs then
            self.coverDirty = true
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        self.inCombat = true
        -- Here, because the combat refresh can end before it reaches the buttons.
        self:StopButtonEvents()
    elseif event == "PLAYER_REGEN_ENABLED" then
        self.inCombat = false
    elseif event == "BAG_UPDATE_COOLDOWN" then
        Buttons.UpdateCooldown()
        return
    end
    self:MarkDirty()
end

function CF:StartEvents()
    local frame = self.eventFrame
    frame:RegisterUnitEvent("UNIT_AURA", "player")
    for _, event in ipairs(WORLD_EVENTS) do frame:RegisterEvent(event) end
end

function CF:StopEvents()
    if self.eventFrame then self.eventFrame:UnregisterAllEvents() end
    self.buttonEvents = {}
end

function CF:BumpGenerations()
    self.thresholdGen = self.thresholdGen + 1
    self.thresholdKey = nil
    self.restGen, self.restKey = self.restGen + 1, nil
    self.previewGen = self.previewGen + 1
    self.alertBoundary, self.alertTextLive = nil, false
    self:NewLife()
    Buttons.StopCooldowns()
end

function CF:EnterInstance()
    self:StopEvents()
    self:BumpGenerations()
    self.lastExpiry, self.sat = nil, false
    -- No aura event arrives in here and no fire is in range, so the covers are
    -- read again on the way out and a dismissal ends here.
    self.coverDirty, self.dismissed = true, false
    self:DrawNothing("Nothing")
    KE:RunAfterCombat(function()
        if self:IsEnabled() and self.inInstance then Buttons.Sync(nil, nil, self.db) end
    end)
end

function CF:LeaveInstance()
    if not self.eventFrame then
        self.eventFrame = CreateFrame("Frame")
        self.eventFrame:SetScript("OnEvent", function(_, event, ...) self:OnEvent(event, ...) end)
    end
    self:StartEvents()
    self.inCombat = UnitAffectingCombat("player") and true or false
    -- Secure buttons: built out of combat, only if still on and still in the open world.
    KE:RunAfterCombat(function()
        if not self:IsEnabled() or self.inInstance ~= false then return end
        Buttons.Build()
        self:MarkDirty()
    end)
end

function CF:EnsureBuilt()
    if self.built then return end
    self.built = true
    Views.Build(self)
    self:RegisterEditMode()
end

function CF:ApplySettings()
    if not self:IsEnabled() then return end
    local inInstance = IsInInstance() and true or false
    -- Nothing is built inside an instance unless a preview asks for it.
    if not inInstance or self.previewing then self:EnsureBuilt() end
    if self.built then Views.ApplySettings(self.db) end
    if inInstance ~= self.inInstance then
        self.inInstance = inInstance
        if inInstance then self:EnterInstance() else self:LeaveInstance() end
    end
    if self.previewing then
        self:RenderPreview()
        return
    end
    if not inInstance then self:MarkDirty() end
end

function CF:OnThemeChanged()
    if not self:IsEnabled() then return end
    if self.previewing then
        self:RenderPreview()
    elseif self.inInstance == false then
        self:MarkDirty()
    end
end

function CF:DismissAlert()
    self.dismissed = true
    self:MarkDirty()
end

function CF:OnLandingFinished()
    self.landing = false
    if self.previewing then
        self:RenderPreview()
        return
    end
    Views.HideShape()
    self.shownMoment = nil
    self:RefreshNow()
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------

local function SampleRows(pairsList)
    local byShort = {}
    for _, feature in ipairs(FEATURES) do byShort[feature.short] = feature end
    local rows = {}
    for index, entry in ipairs(pairsList) do
        local feature = byShort[entry[1]]
        rows[index] = { id = feature.id, feature = feature, amounts = { entry[2] } }
    end
    return rows
end

function CF:RenderPreview()
    local db = self.db
    self.previewGen = self.previewGen + 1
    local choice = KE.PreviewManager.editModeActive and "Passing" or self.previewChoice
    local sample = PREVIEW_SAMPLES[choice]
    local i = self.inputs
    i.preview, i.settings = choice, db
    local _, _, showAlert = Rules.SelectMoment(i)
    i.preview = nil

    local now = GetTime()
    local c = {
        buffUp = sample.left ~= nil,
        expiry = sample.left and (now + sample.left) or nil,
        duration = sample.duration,
        seated = sample.seat ~= nil,
        seatExpiry = sample.seat and (now + sample.seat) or nil,
        seatDuration = sample.seatDuration,
    }

    local onYou = EMPTY
    if sample.cover then
        for _, feature in ipairs(FEATURES) do
            if feature.short == "Sta" then onYou = { [Rules.COVERED_BY[feature.id][1]] = SAMPLE_COVERER } end
        end
    end

    local newRows, keptRows = EMPTY, EMPTY
    if sample.worst then
        keptRows = SampleRows(SAMPLE_WORST)
    else
        if sample.fresh then newRows = SampleRows(SAMPLE_FRESH) end
        if sample.have then keptRows = SampleRows(SAMPLE_HAVE) end
    end

    local s = self.scene
    s.moment, s.showShape, s.showAlert, s.near = sample.moment, true, showAlert, sample.near or false
    s.c, s.newRows, s.keptRows, s.onYou = c, newRows, keptRows, onYou
    s.inCombat, s.refill = sample.combat or false, Rules.REFILL_PROVEN
    s.dots = nil
    if LOOK[sample.moment].dots and db.Checklist then
        s.dots = {
            { name = "Camp Benefits", state = Rules.DotState(c.buffUp) },
            { name = "Well Fed", state = "off" },
            { name = "Well-Rested", state = "part", note = "1/" .. Rules.WELL_RESTED_STACKS },
        }
    end
    if sample.moment == "Landing" then self.landingToken = self.landingToken + 1 end
    self:Draw(s)

    Buttons.Sync(nil, nil, db)
    self:StopButtonEvents()
    if sample.near and db.BagButton then
        Buttons.ShowSample("bag", db)
    elseif sample.moment == "NoCamp" and db.KitButton then
        Buttons.ShowSample("kit", db)
    else
        Buttons.HideSample()
    end

    if sample.seat then
        local gen = self.previewGen
        C_Timer.After(sample.seat, function()
            if gen == self.previewGen and self.previewing and self:IsEnabled() then self:RenderPreview() end
        end)
    end
end

function CF:ShowPreview()
    if not self:IsEnabled() then return end
    self.previewing = true
    self:ApplySettings()
end

function CF:HidePreview()
    if not self:IsEnabled() then return end
    self.previewing = false
    self.previewChoice = DEFAULT_PREVIEW
    self.previewGen = self.previewGen + 1
    Views.HideAll()
    Buttons.HideSample()
    self.shownMoment = nil
    if self.inInstance == false then self:MarkDirty() end
end

function CF:SetPreviewChoice(key)
    self.previewChoice = key
    if self.previewing then self:RenderPreview() end
end

---------------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------------

function CF:ElementConfig(key, displayName, frame, positionKey, eligible)
    return {
        key = key,
        module = self,
        displayName = displayName,
        frame = frame,
        getPosition = function() return self.db[positionKey] end,
        setPosition = function(pos)
            local position = self.db[positionKey]
            position.AnchorFrom = pos.AnchorFrom
            position.AnchorTo = pos.AnchorTo
            position.XOffset = pos.XOffset
            position.YOffset = pos.YOffset
            self:ApplySettings()
        end,
        getParentFrame = function() return UIParent end,
        isEligible = eligible,
        guiPath = "Campfire",
    }
end

function CF:RegisterEditMode()
    if not self.editElements then
        local function isOn() return self.db and self.db.Enabled end
        self.editElements = {
            { label = "Campfire Round", order = 621, config = self:ElementConfig("CampfireRound", "Campfire Round",
                Views.round, "RoundPosition", function() return isOn() and self.db.Shape == "ROUND" end) },
            { label = "Campfire Simple", order = 622, config = self:ElementConfig("CampfireSimple", "Campfire Simple",
                Views.simple, "SimplePosition", function() return isOn() and self.db.Shape == "SIMPLE" end) },
            { label = "Camp Nearby Alert", order = 623, config = self:ElementConfig("CampfireAlert", "Camp Nearby Alert",
                Views.alert, "AlertPosition", function() return isOn() and self.db.AlertEnabled end) },
        }
    end
    if KE.EditMode and not self.editModeRegistered then
        for _, element in ipairs(self.editElements) do KE.EditMode:RegisterElement(element.config) end
        self.editModeRegistered = true
    end
    if KE.EUIUnlock then
        for _, element in ipairs(self.editElements) do
            KE.EUIUnlock:Register(element.config, {
                label = element.label,
                order = element.order,
                isHidden = function() return not element.config.isEligible() end,
            })
        end
    end
end

function CF:UnregisterEditMode()
    if KE.EditMode and self.editElements then
        for _, element in ipairs(self.editElements) do KE.EditMode:UnregisterElement(element.config.key) end
    end
    self.editModeRegistered = false
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------

function CF:UpdateDB()
    self.db = KE.db.profile.Campfire
end

function CF:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function CF:ResetState()
    self.camp = { buffUp = false, inRange = false, seated = false, left = huge }
    self.inputs = {}
    self.scene = {}
    self.render = {}
    self.carried = {}
    self.rest = {}
    self.restGen, self.restKey = self.restGen or 0, nil
    self.prevState, self.nowState = {}, {}
    self.coverNames = self.coverNames or {}
    self.onYou = {}
    self.coverDirty = true
    self.held, self.heldKey, self.tipEmpty, self.heldBefore = EMPTY, nil, false, nil
    self.landedNew, self.landedKept = nil, nil
    self.sat, self.landing, self.dismissed, self.previewing = false, false, false, false
    self.landingEnds = nil
    self.lastExpiry, self.shownMoment, self.alertBoundary, self.alertTextLive = nil, nil, nil, false
    self.lastMoment = "Nothing"
    self.buttonEvents = {}
    self.inInstance = nil
    self.built = false
    self.thresholdGen = self.thresholdGen or 0
    self.thresholdKey = nil
    self.tipRetryGen = nil
    self.previewGen = self.previewGen or 0
    self.landingToken = self.landingToken or 0
    self:NewLife()
end

function CF:OnEnable()
    if not self.db.Enabled then return end
    self:ResetState()
    self:ApplySettings()
end

function CF:OnDisable()
    self:StopEvents()
    self:BumpGenerations()
    self.previewing = false
    self.previewChoice = DEFAULT_PREVIEW
    self.inInstance = nil
    Views.HideAll()
    Buttons.HideSample()
    self:UnregisterEditMode()
    KE:RunAfterCombat(function()
        if self:IsEnabled() then return end
        Buttons.Disarm()
    end)
end
