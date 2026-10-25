-- ╔══════════════════════════════════════════════════════════╗
-- ║  PartyStops.lua                                          ║
-- ║  Module: Party Stops                                     ║
-- ║  Purpose: Party members' crowd-control stops as icons    ║
-- ║           counting down their cooldowns.                 ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- NOTHING HERE READS AN ENEMY AURA. Each stop a teammate can have gets a
-- feed: one aura container per watched plate, chained, each 16384 wide while
-- the stop's debuff is up, under a span frame as wide as the chain. One hit
-- test on the span answers "on any watched enemy"; where auras are secret
-- the answer is secret too and only reaches EvaluateColorValueFromBoolean.
-- The game names no caster, so every teammate of the stop's class who fits
-- it starts. The player's own stops start from the cast, never from a feed.
--
-- Containers are made, grouped and bound in combat: their API carries no
-- combat restriction, only their aura buttons do. One is built per frame.

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class PartyStops: AceModule, AceEvent-3.0
local PS = KitnEssentials:NewModule("PartyStops", "AceEvent-3.0")

local _G = _G
local C_ChallengeMode = C_ChallengeMode
local C_ClassColor = C_ClassColor
local C_CurveUtil = C_CurveUtil
local C_Spell = C_Spell
local C_SpellBook = C_SpellBook
local C_Timer = C_Timer
local CreateFrame = CreateFrame
local EventRegistry = EventRegistry
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local IsInInstance = IsInInstance
local UIParent = UIParent
local UnitAffectingCombat = UnitAffectingCombat
local UnitCanAttack = UnitCanAttack
local UnitClass = UnitClass
local UnitExists = UnitExists
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitIsBossMob = UnitIsBossMob
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitName = UnitName
local issecretvalue = issecretvalue
local ipairs, next, pairs, pcall, type = ipairs, next, pairs, pcall, type
local math_floor, math_max = math.floor, math.max
local string_format = string.format
local wipe = wipe

local Rules = KE.PartyStopsRules
local Data = KE.PartyStopsData
local CDRules = KE.PartyCooldownsRules
local Cell = KE.PartyCooldownsCell
local Track = KE.PartyCooldownsSensor
local Ask = KE.PlateSlots.Ask
local CanAssist = KE.PlateSlots.CanAssist
local EvalBool = C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean

-- Flip to true, /reload, repro, read the log. It never prints a name or an
-- aura value.
local DEBUG_PS = false

local KEY = "PartyStops"
local FRAME_NAME = "KE_PartyStops"
local LAYOUT_TEMPLATE = "DisableUntrustedLayoutScriptsTemplate"
local SENSOR_TEMPLATE = "CustomAuraContainerTemplate," .. LAYOUT_TEMPLATE
local SENSOR_GROUP = "stop"
-- The player's own debuffs are left out: those stops start from the cast.
-- There is no fallback to every caster's debuffs, which would start a
-- same-class teammate's icon from the player's own stop.
local NOT_MINE = "HARMFUL|!PLAYER"
-- A lit sensor reaches across the screen from just off its left edge.
local STRIDE = 16384
local SENSOR_LAYOUT = { elementWidth = STRIDE, elementHeight = 1, elementSpacing = 0, lineSpacing = 0 }
-- Up to 40 idle 1 px sensors chained from here never reach the screen.
local HEAD_X = -(40 + 12)
local READ_DELAY = 0.2
local READS = 2
-- Blind lasts long enough to be up already on a newly watched enemy, so its
-- reads skip this long after any plate is taken.
local HOLD_SETTLE = 0.4
local EDIT_HOLD = 0.5
local HIDDEN_RETRY = 1
-- 4 dispatches a second so a new second is seen within 0.25 s. Three cost a
-- GetTime and a compare; the fourth runs one Rules.Tick per shown icon and,
-- per running one, 2 SetMinMaxValues and a seat check.
local TICK = 0.25
local ROSTER_LATE = 0.5
local MAX_SENSOR_FAILS = 2
-- Preview samples in turn: this share of the cooldown gone; 1 is ready.
local PREVIEW_AT = { 0.35, 1, 0.7 }
local TOKENS = { "player", "party1", "party2", "party3", "party4" }
local ROLES = { TANK = true, HEALER = true, DAMAGER = true }
local BLACK = { 0, 0, 0, 1 }
local WHITE = { 1, 1, 1 }
local EMPTY = {}

PS.members = {}
PS.byKey = {}
PS.icons = {}
PS.own = {}
PS.cells = {}
PS.feeds = {}
PS.sampleIcons = {}
PS.style = { colors = { stop = BLACK } }
-- The last layout's grid, and the insets that fit the KE Edit Mode box and
-- the screen clamp to it.
PS.shape = { left = 0, right = 0, top = 0, bottom = 0 }
PS.live = false
PS.previewing = false
PS.editMode = false

local WANT = Rules.WantByClass(Data)
-- A cast's spell ID, or a cast alias, to its stop.
local castOf = {}
for id, stop in pairs(Data.STOPS) do
    castOf[id] = id
    for _, alias in ipairs(stop.cast or EMPTY) do castOf[alias] = id end
end

local handle, ticker, lastN, lateTimer, sensHost, castFrame
local pending, readsLeft, holdUntil, takenAt = false, 0, 0, 0
local slotFrames, parkDebt, buttonDebt, demand = {}, {}, {}, {}
local placement, entry, keyEntry, textures, colors = {}, { kind = "stop" }, {}, {}, {}
local QueueBuild, Arm

local function Debug(fmt, ...)
    if DEBUG_PS then KE:Print("Party Stops: " .. string_format(fmt, ...)) end
end

-- The value when it is plain and of the kind asked for, else nil.
local function Plain(value, kind)
    if issecretvalue(value) or type(value) ~= kind then return nil end
    return value
end

---------------------------------------------------------------------------------
-- Plates
---------------------------------------------------------------------------------
local unitApi = {
    exists    = function(unit) return Ask(UnitExists, unit) end,
    canAttack = function(unit) return Ask(UnitCanAttack, "player", unit) end,
    canAssist = CanAssist,
    isDead    = function(unit) return Ask(UnitIsDeadOrGhost, unit) end,
    isBoss    = function(unit) return Ask(UnitIsBossMob, unit) end,
    inCombat  = function(unit) return Ask(UnitAffectingCombat, unit) end,
}

local function Verdict(unit, strict)
    return Rules.Verdict(unit, unitApi, strict)
end

-- In combat with no plate in combat yet, the combat test is set aside, so a
-- pull's opening stop counts before the mob is flagged.
local function Relax()
    return InCombatLockdown()
end

---------------------------------------------------------------------------------
-- The countdown
---------------------------------------------------------------------------------
local function TickList(list, n)
    local any = false
    for _, icon in ipairs(list) do
        local t = icon.t
        local running, changed = CDRules.Tick(t, n, issecretvalue)
        if t.loop and not running then
            CDRules.StartLoop(t, n)
            running, changed = true, true
        end
        if changed then Track.Push(t, n) end
        local c = t.cell
        if running and c then
            for k = 1, 2 do
                local sl = t.slot[k]
                if issecretvalue(sl.v) or sl.v ~= 0 then pcall(Cell.Range, c, k, sl, t.u, n) end
            end
            if not changed then pcall(Cell.Seat, c) end
        end
        any = any or running
    end
    return any
end

-- Work happens once a second; live counts go on under the preview.
local function Tick()
    local n = Track.Now()
    if n == lastN then return end
    lastN = n
    local live = TickList(PS.icons, n)
    local samples = PS.previewing and TickList(PS.sampleIcons, n)
    if not (live or samples) and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local function Wake()
    if ticker then return end
    lastN = nil
    ticker = C_Timer.NewTicker(TICK, Tick)
end

---------------------------------------------------------------------------------
-- The grid
---------------------------------------------------------------------------------
local function Texture(id)
    local tex = textures[id]
    if tex then return tex end
    local ok, value = pcall(C_Spell.GetSpellTexture, id)
    if ok and value then textures[id] = value end
    return ok and value or nil
end

local function ClassColor(class)
    if type(class) ~= "string" then return WHITE end
    local c = colors[class]
    if c then return c end
    local ok, color = pcall(C_ClassColor.GetClassColor, class)
    if not (ok and color) then return WHITE end
    c = { color.r, color.g, color.b }
    colors[class] = c
    return c
end

local function Restyle()
    local db, s = PS.db, PS.style
    s.size, s.spacing = db.IconSize or 38, db.Spacing or 1
    s.fontName, s.outline, s.fontSize = db.FontFace, db.FontOutline, db.TextSize or 14
    s.showText = db.ShowText ~= false
end

-- The name sits on a frame of its own, above every layer of the cell.
local function NewCell(i)
    local c = Cell.New(PS.frame)
    local tag = CreateFrame("Frame", nil, c)
    tag:SetAllPoints(c)
    local who = tag:CreateFontString(nil, "OVERLAY")
    who:SetJustifyH("CENTER")
    who:SetWordWrap(false)
    who:SetPoint("BOTTOM", c, "BOTTOM", 0, 2)
    who:Hide()
    c.psTag, c.psWho = tag, who
    PS.cells[i] = c
    return c
end

-- A nickname when the provider has one, else the name. Either may be secret,
-- and a secret one reaches SetText whole.
local function Name(c, m)
    local who, db = c.psWho, PS.db
    if db.ShowNames == false then
        who:Hide()
        return
    end
    local name = m.sample
    if not name and m.unit then
        local ok, value = pcall(KE.GetNicknameOrName, KE, m.unit)
        if not ok then ok, value = pcall(UnitName, m.unit) end
        if ok then name = value end
    end
    -- Secrecy first: type() on a secret is itself illegal.
    local secret = issecretvalue(name)
    if not secret and name == nil then
        who:Hide()
        return
    end
    KE:ApplyFontToText(who, db.FontFace, db.NameSize or 10, db.FontOutline)
    local color = ClassColor(m.class)
    who:SetTextColor(color[1], color[2], color[3], 1)
    who:SetWidth(PS.style.size)
    local ok
    if secret then
        ok = pcall(who.SetText, who, name)
    else
        ok = pcall(who.SetText, who, Rules.Short(name, db.NameLength or 4))
    end
    if not ok then who:SetText("") end
    who:Show()
end

-- The first icon sits on the frame's AnchorFrom point and the grid grows away
-- from it, so that icon stays put as the count changes. A direction against
-- that point grows the grid past the frame, so the KE Edit Mode box and the
-- screen clamp, which would use the frame's rectangle, are inset onto the
-- grid.
local function Layout(count)
    local s, db, shape = PS.style, PS.db, PS.shape
    local perRow = Rules.PerRow(db.IconsPerRow)
    local step = s.size + s.spacing
    local pin = db.Position and db.Position.AnchorFrom or "CENTER"
    for i = 1, count do
        local c = PS.cells[i]
        local x, y = Rules.GridPlace(i, perRow, db.Grow, step)
        c:ClearAllPoints()
        c:SetPoint(pin, PS.frame, pin, x, y)
        pcall(Cell.Seat, c)
    end
    local cols, rows = Rules.GridShape(count, perRow, db.Grow)
    PS.frame:SetSize((cols - 1) * step + s.size, (rows - 1) * step + s.size)
    if shape.cols ~= cols or shape.rows ~= rows or shape.pin ~= pin or shape.grow ~= db.Grow
        or shape.size ~= s.size or shape.spacing ~= s.spacing then
        shape.cols, shape.rows, shape.pin, shape.grow = cols, rows, pin, db.Grow
        shape.size, shape.spacing = s.size, s.spacing
        local growsLeft, growsUp = Rules.Grows(db.Grow)
        local left, right, top, bottom = KE:GetGridOverlayInset(cols, rows, s.size, s.spacing, pin, growsLeft, growsUp)
        shape.left, shape.right, shape.top, shape.bottom = left, right, top, bottom
        -- The box's insets all count outward; the clamp's left and bottom
        -- insets count inward, so those two change sign.
        PS.frame:SetClampRectInsets(-left, right, top, -bottom)
        -- The box reads its insets only when it refreshes.
        if KE.EditMode then KE.EditMode:RefreshLiveState() end
    end
end

local function OverlayInset()
    local shape = PS.shape
    return shape.left, shape.right, shape.top, shape.bottom
end

local function ApplyPosition()
    local frame = PS.frame
    if not frame or not KE:CanReanchorNow(frame) then return end
    local db = PS.db
    placement.anchorFrameType, placement.ParentFrame, placement.Strata = db.anchorFrameType, db.ParentFrame, db.Strata
    KE:ApplyFramePosition(frame, db.Position, placement)
end

-- A cell drawn for another tracker takes its cell from the old one, so a read
-- never writes into a cell its tracker no longer owns.
local function Loose(c, t)
    local old = c.psT
    if old and old ~= t and old.cell == c then old.cell = nil end
    c.psT = t
end

local function Draw()
    local frame = PS.frame
    if not frame then return end
    Restyle()
    local list = PS.previewing and PS.sampleIcons or PS.icons
    local n = Track.Now()
    for i, icon in ipairs(list) do
        local c = PS.cells[i] or NewCell(i)
        local t = icon.t
        Loose(c, t)
        entry.texture, entry.cd = Texture(icon.id), t.cd
        Cell.Dress(c, PS.style, entry)
        c.psTag:SetFrameLevel(c:GetFrameLevel() + 7)
        t.cell = c
        Name(c, icon.m)
        c:Show()
        Track.Push(t, n)
    end
    for i = #list + 1, #PS.cells do
        local c = PS.cells[i]
        Loose(c, nil)
        Cell.Clear(c)
    end
    Layout(#list)
    ApplyPosition()
    frame:SetShown(#list > 0)
    if #list > 0 then Wake() end
end

-- One sample per tracked stop, named after its class, so the preview wraps
-- and sizes as the live grid does. A sample keeps its count while its stop
-- keeps its place.
local function BuildSamples()
    local db, list = PS.db, PS.sampleIcons
    local off = db.SpellOff or EMPTY
    local n, count = Track.Now(), 0
    for _, id in ipairs(Rules.SpellList(db, Data)) do
        if off[id] ~= true then
            count = count + 1
            local stop = Data.STOPS[id]
            local icon = list[count]
            if not icon then
                icon = { m = {} }
                list[count] = icon
            end
            if icon.id ~= id then
                local t = CDRules.NewTracker(stop.cd, false)
                local share = PREVIEW_AT[(count - 1) % #PREVIEW_AT + 1]
                if share < 1 then
                    t.loop = stop.cd - math_floor(stop.cd * share)
                    CDRules.StartLoop(t, n)
                else
                    CDRules.Clear(t, n)
                end
                icon.t, icon.id = t, id
            end
            icon.m.class, icon.m.sample = stop.class, Data.CLASS_NAMES[stop.class]
        end
    end
    for i = #list, count + 1, -1 do list[i] = nil end
end

---------------------------------------------------------------------------------
-- Sensors
---------------------------------------------------------------------------------
-- The engine runs this inside the add and swallows its errors, so it records
-- its own result; Settle tries a refused one again.
local function QuietButton(button)
    button:SetSize(1, 1)
    button:SetMouseClickEnabled(false)
    button:SetMouseMotionEnabled(false)
end

local function InitSensorButton(button)
    buttonDebt[button] = (not pcall(QuietButton, button)) or nil
end

-- A refused disable is owed and tried again by Settle. An owed sensor may
-- still answer for its old plate inside the span, so its feed is not read
-- until the debt clears; once idle, the hidden host stops it regardless.
local function Park(s)
    s.psUnit = nil
    parkDebt[s] = (not pcall(s.SetEnabled, s, false)) or nil
end

-- Unit before enable: enabling registers the unit's aura events. A refused
-- call leaves the sensor's state unknown, so it is parked.
local function Aim(s, unit)
    if pcall(s.SetUnit, s, unit) and pcall(s.SetEnabled, s, true) then
        s.psUnit = unit
        parkDebt[s] = nil
    else
        Park(s)
    end
end

local function Owed(f)
    if next(parkDebt) == nil then return false end
    for _, s in ipairs(f.sensors) do
        if parkDebt[s] then return true end
    end
    return false
end

local function Unprime(f)
    for _, t in ipairs(f.trackers) do t.primed = false end
end

-- A feed that held an owed sensor is unprimed before the debt is retried, so
-- the read armed after it only records, whether or not a read saw the debt.
local function Settle()
    local owed = next(parkDebt) ~= nil
    if owed then
        for _, f in pairs(PS.feeds) do
            if Owed(f) then Unprime(f) end
        end
    end
    for s in pairs(parkDebt) do Park(s) end
    for button in pairs(buttonDebt) do InitSensorButton(button) end
    if owed and PS.live then Arm() end
end

-- The span runs from the head to a tail on the last sensor, so it is as wide
-- as the chain. Frames hung off a container take the layout template.
local function FeedOf(id)
    local f = PS.feeds[id]
    if f then return f end
    local include = {}
    for _, d in ipairs(Data.STOPS[id].debuffs) do include[d] = true end
    local head = CreateFrame("Frame", nil, sensHost)
    head:SetSize(1, 1)
    head:SetPoint("TOPLEFT", UIParent, "TOPLEFT", HEAD_X, 0)
    local tail = CreateFrame("Frame", nil, sensHost, LAYOUT_TEMPLATE)
    tail:SetSize(1, 1)
    tail:SetPoint("TOPLEFT", head, "TOPLEFT", 0, 0)
    local span = CreateFrame("Frame", nil, sensHost, LAYOUT_TEMPLATE)
    span:SetPoint("TOPLEFT", head, "TOPLEFT", 0, 0)
    span:SetPoint("BOTTOMRIGHT", tail, "BOTTOMRIGHT", 0, 0)
    -- The client copies a group's options at each add, so a feed's sensors
    -- share one table.
    f = {
        id = id, sensors = {}, trackers = EMPTY, on = false, fails = 0,
        head = head, tail = tail, span = span,
        group = {
            maxFrameCount = 1,
            candidateFilters = { includeSpellIDs = include },
            initializeFrame = InitSensorButton,
            layout = SENSOR_LAYOUT,
        },
    }
    PS.feeds[id] = f
    return f
end

local function GroupSensor(s, group)
    s:SetSize(1, 1)
    s:EnableMouse(false)
    s:AddAuraGroup(SENSOR_GROUP, NOT_MINE, group)
end

-- The sensor, or nil when its container or group was refused.
local function NewSensor(f)
    local ok, s = pcall(CreateFrame, "AuraContainer", nil, sensHost, SENSOR_TEMPLATE)
    if not ok or not s then return nil end
    local grouped = pcall(GroupSensor, s, f.group)
    pcall(s.SetEnabled, s, false)
    if not grouped then
        pcall(s.Hide, s)
        return nil
    end
    return s
end

local function PlaceSensor(s, f, last)
    if last then
        s:SetPoint("TOPLEFT", last, "TOPRIGHT", 0, 0)
    else
        s:SetPoint("TOPLEFT", f.head, "TOPLEFT", 0, 0)
    end
    f.tail:ClearAllPoints()
    f.tail:SetPoint("TOPLEFT", s, "TOPRIGHT", 0, 0)
end

-- Returns false when the build failed. A sensor bound at once on a held plate
-- asks for a read; a hold feed's also restarts the hold, so its first answer
-- is a baseline taken before the next use rather than the next use itself.
local function Grow(f)
    local s = NewSensor(f)
    if not s then return false end
    if not pcall(PlaceSensor, s, f, f.sensors[#f.sensors]) then
        pcall(s.Hide, s)
        return false
    end
    local j = #f.sensors + 1
    f.sensors[j] = s
    local unit = f.on and PS.slots:UnitOf(j)
    if unit then
        Aim(s, unit)
        if Data.STOPS[f.id].hold then takenAt = GetTime() end
        Arm()
    end
    Debug("built sensor %d for %d", j, f.id)
    return true
end

local function NextMissing()
    local cap = Rules.Watched(PS.db.EnemiesWatched)
    for _, id in ipairs(Data.ORDER) do
        local f = PS.feeds[id]
        if f and f.on and not f.stalled and f.fails < MAX_SENSOR_FAILS and #f.sensors < cap then return f end
    end
    return nil
end

-- One container per frame: each costs the client an aura pass. 200 at the
-- cap take about 3.3 s at 60 fps, once per session and cap.
local function BuildStep()
    PS.buildQueued = false
    if not PS.live then return end
    local f = NextMissing()
    if not f then return end
    if not Grow(f) then
        f.fails, f.stalled = f.fails + 1, true
        Debug("a sensor for %d was refused", f.id)
    end
    QueueBuild()
end

QueueBuild = function()
    if PS.buildQueued or not PS.live then return end
    PS.buildQueued = true
    C_Timer.After(0, BuildStep)
end

---------------------------------------------------------------------------------
-- Reads
---------------------------------------------------------------------------------
local function UnprimeAll()
    for _, f in pairs(PS.feeds) do Unprime(f) end
end

local function HoldOn()
    for _, f in pairs(PS.feeds) do
        if f.on and Data.STOPS[f.id].hold then return true end
    end
    return false
end

local function ReadFeed(f, n, now)
    local stop = Data.STOPS[f.id]
    if Owed(f) or (stop.hold and now < takenAt + HOLD_SETTLE) then
        Unprime(f)
        return
    end
    local ok, lit = pcall(f.span.IsMouseOver, f.span, 1e5, -1e5, 0, 0)
    if not ok then return end
    -- Closed door: no use is seen here, and a count already running from
    -- plain reads goes on.
    if issecretvalue(lit) and not CDRules.DoorOpen(PS.door) then
        Unprime(f)
        return
    end
    local at, changedCount = n - (stop.lag or 0), 0
    for _, t in ipairs(f.trackers) do
        local okFeed, changed = pcall(CDRules.Feed, t, lit, nil, at, issecretvalue, EvalBool)
        if okFeed and changed then
            changedCount = changedCount + 1
            Track.Push(t, n)
        end
    end
    if changedCount > 0 then
        Wake()
        Debug("stop %d: %d icons changed", f.id, changedCount)
    end
end

-- While the interface is hidden its containers show nothing, and Blizzard's
-- Edit Mode feeds every container sample auras, so neither is read.
local function ReadAll()
    if not PS.live then
        pending = false
        return
    end
    local now = GetTime()
    if now < holdUntil then
        C_Timer.After(holdUntil - now + READ_DELAY, ReadAll)
        return
    end
    if not UIParent:IsShown() then
        UnprimeAll()
        C_Timer.After(HIDDEN_RETRY, ReadAll)
        return
    end
    if PS.editMode then
        UnprimeAll()
        pending = false
        return
    end
    readsLeft = readsLeft - 1
    -- A read skipped by the hold sets no baseline, so while a hold feed is on
    -- the chain goes on until one read lands after the hold: at most two more
    -- reads per take.
    if readsLeft < 1 and now < takenAt + HOLD_SETTLE and HoldOn() then readsLeft = 1 end
    if readsLeft > 0 then
        C_Timer.After(READ_DELAY, ReadAll)
    else
        pending = false
    end
    local n = Track.Now()
    for _, f in pairs(PS.feeds) do
        if f.on and f.sensors[1] then pcall(ReadFeed, f, n, now) end
    end
end

-- UNIT_AURA is only a trigger; its payload is never read. Each asks for two
-- reads 0.2 s apart, since a container lays out after its own pass.
Arm = function()
    readsLeft = READS
    if pending or not PS.live then return end
    pending = true
    C_Timer.After(READ_DELAY, ReadAll)
end

-- UNIT_AURA per held plate: PlateSlots' own unit events are unfiltered and
-- rescan on every event of the player.
local function OnTake(slot, unit)
    local evt = slotFrames[slot]
    if not evt then
        evt = CreateFrame("Frame")
        evt:SetScript("OnEvent", Arm)
        slotFrames[slot] = evt
    end
    evt:UnregisterAllEvents()
    evt:RegisterUnitEvent("UNIT_AURA", unit)
    takenAt = GetTime()
    for _, f in pairs(PS.feeds) do
        local s = f.on and f.sensors[slot]
        if s then Aim(s, unit) end
    end
    Debug("slot %d taken", slot)
    Arm()
end

local function OnRelease(slot)
    local evt = slotFrames[slot]
    if evt then evt:UnregisterAllEvents() end
    for _, f in pairs(PS.feeds) do
        local s = f.sensors[slot]
        if s then Park(s) end
    end
    Debug("slot %d released", slot)
    Arm()
end

-- A faction change can turn a held mob assistable, so it is rechecked like a
-- flag change.
local function OnPlateUnitEvent(slots, _, unit)
    slots:Recheck(unit)
end

---------------------------------------------------------------------------------
-- Own casts and talents
---------------------------------------------------------------------------------
local function KnownSpell(id)
    local ok, known = pcall(C_SpellBook.IsSpellKnown, id)
    return ok and not issecretvalue(known) and known == true
end

local function Known(stop, id)
    if KnownSpell(id) then return true end
    for _, alias in ipairs(stop.cast or EMPTY) do
        if KnownSpell(alias) then return true end
    end
    return false
end

-- A stop whose spell the player knows counts its need talents as taken,
-- whatever the talent read says.
local function ReadOwn()
    local ranks = {}
    PS.ownRanks = ranks
    local okClass, _, class = pcall(UnitClass, "player")
    class = okClass and Plain(class, "string") or nil
    if not class then return end
    local okSpec, spec = pcall(KE.GetPlayerSpecId, KE)
    spec = okSpec and Plain(spec, "number") or nil
    local want = WANT[class]
    if want and spec then
        local read, reason = KE.GroupInspect:ReadOwnRanks(spec, want)
        if read then
            for id, rank in pairs(read) do ranks[id] = rank end
        elseif reason == "combat" then
            PS.ownOwed = true
        end
    end
    for id, stop in pairs(Data.STOPS) do
        if stop.class == class and stop.need and Known(stop, id) then
            for _, talent in ipairs(stop.need) do ranks[talent] = 1 end
        end
    end
end

local function OnCast(_, _, _, _, spellID)
    if issecretvalue(spellID) then return end
    local id = castOf[spellID]
    local t = id and PS.own[id]
    if not t then return end
    local n = Track.Now()
    CDRules.StartPlain(t, n)
    Track.Push(t, n)
    Wake()
    Debug("own cast %d", spellID)
end

local function SetOwnCasts(on)
    if not castFrame or on == PS.castsOn then return end
    PS.castsOn = on
    if on then
        castFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    else
        castFrame:UnregisterAllEvents()
    end
end

---------------------------------------------------------------------------------
-- Roster
---------------------------------------------------------------------------------
local function SpecOf(m)
    if m.isPlayer then
        local ok, spec = pcall(KE.GetPlayerSpecId, KE)
        return ok and Plain(spec, "number") or nil
    end
    local snap = handle and m.guid and handle:Get(m.guid)
    return snap and Plain(snap.spec, "number") or nil
end

local function RoleOf(unit)
    local ok, role = pcall(UnitGroupRolesAssigned, unit)
    if not ok or issecretvalue(role) or not ROLES[role] then return nil end
    return role
end

-- The player first, when included, then party1 to party4. A member who left
-- is dropped with their counts; a class that reads secret keeps the last one.
local function Roster()
    local db, seen = PS.db, {}
    wipe(PS.members)
    for _, unit in ipairs(TOKENS) do
        local isPlayer = unit == "player"
        if (isPlayer and db.IncludeSelf ~= false) or (not isPlayer and Ask(UnitExists, unit) == true) then
            local guid = KE:GetSafeUnitGUID(unit)
            local key = isPlayer and "player" or guid or unit
            local m = PS.byKey[key]
            if not m then
                m = { key = key, trackers = {} }
                PS.byKey[key] = m
            end
            m.unit, m.guid, m.isPlayer = unit, guid, isPlayer
            local ok, _, class = pcall(UnitClass, unit)
            class = ok and Plain(class, "string") or nil
            if class then m.class = class end
            m.spec, m.role = SpecOf(m), RoleOf(unit)
            seen[key] = true
            PS.members[#PS.members + 1] = m
        end
    end
    for key in pairs(PS.byKey) do
        if not seen[key] then PS.byKey[key] = nil end
    end
end

-- A teammate's talent their spec's tree lacks reads 0; the snapshot's absent
-- set tells Fits it was not found.
local function RanksOf(m)
    if m.isPlayer then return PS.ownRanks, nil end
    local snap = handle and m.guid and handle:Get(m.guid)
    if not snap then return nil, nil end
    return snap.ranks, snap.absent
end

-- The base length while any length talent is unread.
local function Length(stop, ranks)
    return stop.mods and CDRules.ModLength(stop.cd, stop.mods, ranks, nil) or stop.cd
end

-- A new length in the same code unit keeps the count running.
local function TrackerFor(m, id, cd, n)
    local t = m.trackers[id]
    if t and CDRules.Unit(t.cd) == CDRules.Unit(cd) then
        t.cd = cd
        return t
    end
    t = CDRules.NewTracker(cd, false)
    CDRules.Clear(t, n)
    m.trackers[id] = t
    return t
end

local function InDungeon()
    local ok, inInstance, kind = pcall(IsInInstance)
    return ok and Plain(inInstance, "boolean") == true and Plain(kind, "string") == "party"
end

local function KeyActive()
    local ok, active = pcall(C_ChallengeMode.IsChallengeModeActive)
    return ok and Plain(active, "boolean") == true
end

-- Teammates are inspected only inside a dungeon, through the shared queue.
local function UpdateDemand()
    if not handle then return end
    if not (PS.live and InDungeon()) then
        handle:SetDemand(nil)
        return
    end
    wipe(demand)
    for _, m in ipairs(PS.members) do
        if not m.isPlayer and m.guid and m.class and WANT[m.class] then demand[#demand + 1] = m end
    end
    -- An empty list would keep the shared inspector active with nothing to do.
    handle:SetDemand(#demand > 0 and demand or nil)
end

-- A feed that turns on unprimes its trackers, so its first read only records.
local function SetFeeds(want)
    local any = false
    for id, list in pairs(want) do
        any = true
        local f = FeedOf(id)
        f.trackers, f.stalled = list, nil
        if not f.on then
            f.on = true
            Unprime(f)
            for j, s in ipairs(f.sensors) do
                local unit = PS.slots:UnitOf(j)
                if unit then Aim(s, unit) end
            end
        end
    end
    for id, f in pairs(PS.feeds) do
        if f.on and not want[id] then
            f.on, f.trackers = false, EMPTY
            for _, s in ipairs(f.sensors) do Park(s) end
        end
    end
    if any then
        QueueBuild()
        Arm()
    end
end

local function Refresh()
    PS.refreshQueued = false
    if not PS:IsEnabled() then return end
    local n = Track.Now()
    wipe(PS.icons)
    wipe(PS.own)
    local want = {}
    if PS.live then
        Roster()
        local db = PS.db
        local off = db.SpellOff or EMPTY
        for _, id in ipairs(Rules.SpellList(db, Data)) do
            if off[id] ~= true then
                local stop = Data.STOPS[id]
                for _, m in ipairs(PS.members) do
                    local ranks, absent = RanksOf(m)
                    if Rules.Fits(stop, m, ranks, absent) then
                        local t = TrackerFor(m, id, Length(stop, ranks), n)
                        PS.icons[#PS.icons + 1] = { t = t, m = m, id = id }
                        if m.isPlayer then
                            PS.own[id] = t
                        else
                            local list = want[id] or {}
                            want[id] = list
                            list[#list + 1] = t
                        end
                    end
                end
            end
        end
    end
    SetFeeds(want)
    SetOwnCasts(next(PS.own) ~= nil)
    UpdateDemand()
    if PS.previewing then BuildSamples() end
    Draw()
end

-- Roster, talent and settings changes come in bursts; one pass on the next
-- frame answers all of them.
local function QueueRefresh()
    if PS.refreshQueued then return end
    PS.refreshQueued = true
    C_Timer.After(0, Refresh)
end

---------------------------------------------------------------------------------
-- Inspector
---------------------------------------------------------------------------------
local function Covered(snap, want)
    for id in pairs(want) do
        if not snap.covered[id] then return false end
    end
    return true
end

local function Teammate(guid)
    local m = PS.byKey[guid]
    if not (m and not m.isPlayer and m.class and WANT[m.class]) then return nil end
    return m
end

local callbacks = {
    Wants = function(guid)
        local m = Teammate(guid)
        if not m then return false end
        local snap = handle and handle:Get(guid) or nil
        return not (snap ~= nil and Covered(snap, WANT[m.class]) and snap.stale == nil)
    end,
    OnlyStale = function(guid)
        local m = Teammate(guid)
        if not m then return false end
        local snap = handle and handle:Get(guid) or nil
        return snap ~= nil and Covered(snap, WANT[m.class]) and snap.stale ~= nil
    end,
    OnRead = function(guid, _, snap)
        local m = Teammate(guid)
        if m and handle and type(snap.spec) == "number" then
            handle:ReadRanks(guid, snap.spec, WANT[m.class])
        end
    end,
    OnChanged = function() QueueRefresh() end,
}

---------------------------------------------------------------------------------
-- Live and idle
---------------------------------------------------------------------------------
local function OnEditModeEnter()
    PS.editMode = true
    UnprimeAll()
end

-- The first read after Edit Mode only records, after a hold.
local function OnEditModeExit()
    PS.editMode = false
    holdUntil = math_max(holdUntil, GetTime() + EDIT_HOLD)
    UnprimeAll()
    Arm()
end

local function LateRoster()
    lateTimer = nil
    QueueRefresh()
end

local LIVE_EVENTS = {
    GROUP_ROSTER_UPDATE = "OnRoster",
    PLAYER_ROLES_ASSIGNED = "OnRoster",
    PLAYER_ENTERING_WORLD = "OnRoster",
    PLAYER_SPECIALIZATION_CHANGED = "OnSpecChanged",
    TRAIT_CONFIG_UPDATED = "OnOwnTalents",
    PLAYER_TALENT_UPDATE = "OnOwnTalents",
    READY_CHECK = "OnReadyCheck",
    CHALLENGE_MODE_START = "OnKeyStart",
    PLAYER_REGEN_DISABLED = "OnCombatStart",
    PLAYER_REGEN_ENABLED = "OnCombatEnd",
    ADDON_RESTRICTION_STATE_CHANGED = "OnRestrictionChanged",
}

local function GoLive()
    if PS.live then return end
    PS.live = true
    PS.door = PS.door or CDRules.DoorVerdict(EvalBool, issecretvalue)
    handle = handle or KE.GroupInspect:Subscribe(KEY, callbacks)
    sensHost:Show()
    PS.slots:SetCap(Rules.Watched(PS.db.EnemiesWatched))
    PS.slots:Start()
    for event, method in pairs(LIVE_EVENTS) do PS:RegisterEvent(event, method) end
    local manager = _G.EditModeManagerFrame
    PS.editMode = manager ~= nil and manager:IsEditModeActive() == true
    EventRegistry:RegisterCallback("EditMode.Enter", OnEditModeEnter, PS)
    EventRegistry:RegisterCallback("EditMode.Exit", OnEditModeExit, PS)
    ReadOwn()
    QueueRefresh()
    Debug("live")
end

-- The read chain and the build loop end at their next step.
local function GoIdle()
    if not PS.live then return end
    PS.live = false
    PS.slots:Stop()
    for _, f in pairs(PS.feeds) do
        f.on, f.trackers = false, EMPTY
        for _, s in ipairs(f.sensors) do Park(s) end
    end
    sensHost:Hide()
    for event in pairs(LIVE_EVENTS) do PS:UnregisterEvent(event) end
    SetOwnCasts(false)
    EventRegistry:UnregisterCallback("EditMode.Enter", PS)
    EventRegistry:UnregisterCallback("EditMode.Exit", PS)
    PS.editMode = false
    if lateTimer then
        lateTimer:Cancel()
        lateTimer = nil
    end
    if handle then handle:SetDemand(nil) end
    QueueRefresh()
    Debug("idle")
end

-- Made at the first enable and kept for reuse; idle, nothing runs on them.
local function MakeFrames()
    if PS.frame then return end
    local frame = CreateFrame("Frame", FRAME_NAME, UIParent)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(false)
    frame:Hide()
    PS.frame = frame
    -- Shown only while live: a hidden container drops its aura events, which
    -- also stops a sensor whose disable was refused.
    sensHost = CreateFrame("Frame", nil, UIParent)
    sensHost:SetSize(1, 1)
    sensHost:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    sensHost:Hide()
    castFrame = CreateFrame("Frame")
    castFrame:SetScript("OnEvent", OnCast)
    PS.slots = KE.PlateSlots.New({
        verdict = Verdict,
        relax = Relax,
        onTake = OnTake,
        onRelease = OnRelease,
        tickSeconds = 2,
        unitEvents = { "UNIT_FLAGS", "UNIT_FACTION" },
        onUnitEvent = OnPlateUnitEvent,
        cap = Rules.Watched(PS.db.EnemiesWatched),
    })
end

local function Predicate(facts)
    return Rules.Live(facts, PS.db)
end

local function ApplyQueued()
    PS.applyQueued = false
    if not PS:IsEnabled() then return end
    PS:UpdateDB()
    KE.Context:Evaluate(KEY)
    if PS.slots then PS.slots:SetCap(Rules.Watched(PS.db.EnemiesWatched)) end
    QueueRefresh()
end

---------------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------------
function PS:UpdateDB()
    self.db = KE.db.profile.PartyStops
end

function PS:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function PS:OnEnable()
    self:UpdateDB()
    if not self.db.Enabled then return end
    if not KE:AuraContainersAvailable(LAYOUT_TEMPLATE) then
        Debug("aura containers unavailable: inactive")
        return
    end
    MakeFrames()
    self:RegWithEditMode()
    KE.Context:Subscribe(KEY, {
        needs = { "zone", "group" },
        predicate = Predicate,
        onUnknown = "closed",
        onEnter = GoLive,
        onLeave = GoIdle,
    })
end

function PS:OnDisable()
    KE.Context:Unsubscribe(KEY)
    GoIdle()
    if handle then
        handle:Release()
        handle = nil
    end
    self:UnregisterAllEvents()
    self.previewing = false
    wipe(self.icons)
    wipe(self.own)
    wipe(self.sampleIcons)
    Draw()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    -- Clearing the guard is what lets a later enable register again.
    if KE.EditMode then KE.EditMode:UnregisterElement(KEY) end
    self.editModeRegistered = false
end

-- A dragged slider asks many times a frame; one pass on the next frame
-- answers all of them.
function PS:ApplySettings()
    if not self:IsEnabled() or self.applyQueued then return end
    self.applyQueued = true
    C_Timer.After(0, ApplyQueued)
end

function PS:OnRoster()
    QueueRefresh()
    if lateTimer then lateTimer:Cancel() end
    lateTimer = C_Timer.NewTimer(ROSTER_LATE, LateRoster)
end

function PS:OnSpecChanged(_, unit)
    if issecretvalue(unit) then return end
    if unit == "player" then
        ReadOwn()
    elseif handle then
        local guid = KE:GetSafeUnitGUID(unit)
        if guid then
            handle:Refresh(guid, "spec")
            handle:Wake()
        end
    end
    QueueRefresh()
end

function PS:OnOwnTalents()
    ReadOwn()
    QueueRefresh()
end

function PS:OnReadyCheck()
    if handle and InDungeon() and not KeyActive() then
        handle:Refresh(nil, "ready check")
        handle:Wake()
    end
end

-- The game resets cooldowns of 90 s or more when a key starts.
function PS:OnKeyStart()
    local n = Track.Now()
    for _, m in pairs(self.byKey) do
        for _, t in pairs(m.trackers) do
            keyEntry.cd = t.cd
            if CDRules.KeyStartClear(t, keyEntry, n) then Track.Push(t, n) end
        end
    end
end

-- Next frame, when InCombatLockdown already reads true.
function PS:OnCombatStart()
    self.slots:QueueScan()
end

function PS:OnCombatEnd()
    self.slots:QueueScan()
    Settle()
    if self.ownOwed then
        self.ownOwed = nil
        ReadOwn()
        QueueRefresh()
    end
end

function PS:OnRestrictionChanged()
    Settle()
end

---------------------------------------------------------------------------------
-- KE Edit Mode and preview
---------------------------------------------------------------------------------
function PS:RegWithEditMode()
    if not KE.EditMode or self.editModeRegistered then return end
    KE.EditMode:RegisterElement({
        key = KEY,
        displayName = "Party Stops",
        frame = self.frame,
        module = self,
        getPosition = function() return self.db.Position end,
        -- A revert can restore another AnchorFrom, which the icons are laid
        -- out from.
        setPosition = function(pos)
            self.db.Position = pos
            Draw()
        end,
        getOverlayInset = OverlayInset,
        getParentFrame = function()
            return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame)
        end,
        guiPath = "KicksCasts",
        guiTab = KEY,
        isEligible = function() return self:IsEnabled() end,
    })
    self.editModeRegistered = true
end

-- Set even while not live, so a page opened solo shows samples.
function PS:ShowPreview()
    if not (self:IsEnabled() and self.frame) then return end
    self.previewing = true
    Refresh()
end

-- Samples start afresh at the next preview.
function PS:HidePreview()
    if not self.previewing then return end
    self.previewing = false
    wipe(self.sampleIcons)
    Refresh()
end
