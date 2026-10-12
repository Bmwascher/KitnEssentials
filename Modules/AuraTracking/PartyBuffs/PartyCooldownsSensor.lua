-- ╔══════════════════════════════════════════════════════════╗
-- ║  PartyCooldownsSensor.lua                                ║
-- ║  Purpose: the buff sensors, reads, latch writes and      ║
-- ║           clock ticker behind Party Cooldowns cells.     ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- A sensor is a Blizzard aura container holding one 50000-wide element
-- while the buff is up, so IsMouseOver answers "present" without Lua reading
-- the aura. Where auras are secret the answer is secret too; it only reaches
-- EvaluateColorValueFromBoolean, whose result goes straight to the cell's
-- bars and alphas. Every container call is a pcall.

---@class KE
local KE = select(2, ...)

local C_CurveUtil = C_CurveUtil
local C_Timer = C_Timer
local CreateFrame = CreateFrame
local GetTime = GetTime
local UIParent = UIParent
local ipairs = ipairs
local issecretvalue = issecretvalue
local math_floor = math.floor
local math_max = math.max
local pairs = pairs
local pcall = pcall
local table_concat = table.concat
local tostring = tostring
local wipe = wipe

local Rules = KE.PartyCooldownsRules
local Cell = KE.PartyCooldownsCell
local EvalBool = C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean

local Track = {}
KE.PartyCooldownsSensor = Track

local SENSOR_GROUP = "cd"
-- A lit sensor spans the screen from just off its left edge.
local SENSOR_WIDTH = 50000
local READ_DELAY = 0.2
local READS = 2
local BIND_HOLD = 0.5
local HIDDEN_RETRY = 1
-- 4 dispatches a second so a new second is seen within 0.25 s. Three of them
-- cost one GetTime and one compare; the fourth walks the live trackers, with
-- 2 SetMinMaxValues per running slot (64 a second at 16 cells).
local TICK = 0.25

-- Whole seconds from an origin far enough back that no epoch goes negative.
local T0 = GetTime() - 1024

Track.live = {}
Track.slots = {}

local sensHost, ticker, lastN
local sensorsShown = false
-- Blizzard's Edit Mode feeds every aura container sample auras, so a sensor
-- shows nothing while it is open.
local editMode = false
-- Sensors whose disable was refused: their state is unknown until Settle.
local debt = {}

function Track.Now() return math_floor(GetTime() - T0 + 0.5) end

function Track.DoorOpen() return Rules.DoorOpen(Track.door) end

local function Push(t, n)
    local c = t.cell
    if not c then return end
    for k = 1, 2 do pcall(Cell.Write, c, k, t.slot[k], t.u, n) end
end
Track.Push = Push

-- Work happens once a second; the ticker stops when nothing shows a time.
local function Tick()
    local n = Track.Now()
    if n == lastN then return end
    lastN = n
    local any = false
    for t in pairs(Track.live) do
        local running, changed = Rules.Tick(t, n, issecretvalue)
        -- A preview sample starts again with t.loop seconds left.
        if t.loop and not running then
            local start = n - (t.cd - t.loop)
            Rules.Clear(t, start)
            Rules.StartPlain(t, start)
            running, changed = true, true
        end
        if changed then Push(t, n) end
        if running then
            any = true
            for k = 1, 2 do
                local sl = t.slot[k]
                if issecretvalue(sl.v) or sl.v ~= 0 then pcall(Cell.Range, t.cell, k, sl, t.u, n) end
            end
        end
    end
    if not any and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

function Track.Wake()
    if ticker then return end
    lastN = nil
    ticker = C_Timer.NewTicker(TICK, Tick)
end

function Track.Watch(t)
    Track.live[t] = true
    Track.Wake()
end

function Track.Forget(t)
    Track.live[t] = nil
    -- The last tracker gone: Tick would only cancel at the next whole second.
    if ticker and next(Track.live) == nil then
        ticker:Cancel()
        ticker = nil
    end
end

-- Sensor buttons whose setup was refused, set up again by Settle.
local buttonDebt = {}

-- The engine runs this inside the add and swallows its errors, so it records
-- its own result. The read uses the element's width, not the button's size.
local function InitSensorButton(button)
    local ok = pcall(function()
        button:SetSize(1, 1)
        button:SetMouseClickEnabled(false)
        button:SetMouseMotionEnabled(false)
    end)
    buttonDebt[button] = (not ok) or nil
end

local function BuffSet(buffs)
    local set = {}
    for _, id in ipairs(buffs) do set[id] = true end
    return set
end

-- short makes the sensor see only a proc copy of the buff.
local function NewSensor(buffs, short)
    if not sensHost then
        sensHost = CreateFrame("Frame", nil, UIParent)
        sensHost:SetSize(1, 1)
        sensHost:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
        sensHost:SetShown(sensorsShown)
    end
    local ok, sensor = pcall(CreateFrame, "AuraContainer", nil, sensHost, "CustomAuraContainerTemplate")
    if not ok or not sensor then return nil end
    local grouped = pcall(function()
        sensor:SetSize(1, 1)
        sensor:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -11, 0)
        sensor:EnableMouse(false)
        sensor:AddAuraGroup(SENSOR_GROUP, "HELPFUL", {
            maxFrameCount = 1,
            candidateFilters = { includeSpellIDs = BuffSet(buffs), maxDuration = short },
            initializeFrame = InitSensorButton,
            layout = { elementWidth = SENSOR_WIDTH, elementHeight = 1, elementSpacing = 0, lineSpacing = 0 },
        })
    end)
    if pcall(sensor.SetEnabled, sensor, false) then
        sensor.keOn = false
    else
        debt[sensor] = true
    end
    if not grouped then
        pcall(sensor.Hide, sensor)
        debt[sensor] = nil
        return nil
    end
    return sensor
end

-- A refused call leaves the sensor's state unknown, so every recorded field
-- is cleared and the next apply issues all three calls again; until then it is
-- parked and never read. Returns whether every call was accepted, and whether
-- any was issued (the sensor was bound, re-pointed or re-enabled).
local function Aim(sensor, sig, buffs, short, unit)
    local changed = sensor.keSig ~= sig or sensor.keUnit ~= unit or not sensor.keOn
    local ok = pcall(function()
        if sensor.keSig ~= sig then
            sensor:SetAuraGroupCandidateFilters(SENSOR_GROUP, { includeSpellIDs = BuffSet(buffs), maxDuration = short })
            sensor.keSig = sig
        end
        if sensor.keUnit ~= unit then
            sensor:SetUnit(unit)
            sensor.keUnit = unit
        end
        if not sensor.keOn then
            sensor:SetEnabled(true)
            sensor.keOn = true
        end
    end)
    if ok then
        debt[sensor] = nil
    else
        sensor.keOn, sensor.keSig, sensor.keUnit = nil, nil, nil
        Track.Park(sensor)
    end
    return ok, changed
end

-- keOn is true (enabled), false (disabled) or nil (unknown, never read). A
-- refused disable stays owed and Settle tries it again at the drain; while
-- the gate is closed the hidden host stops the sensor whatever it answered.
function Track.Park(sensor)
    if not sensor or sensor.keOn == false then return end
    if pcall(sensor.SetEnabled, sensor, false) then
        sensor.keOn = false
        debt[sensor] = nil
    else
        sensor.keOn = nil
        debt[sensor] = true
    end
end
local Park = Track.Park

-- Run at the drain. A sensor aimed since is enabled on purpose and leaves the
-- list.
function Track.Settle()
    for sensor in pairs(debt) do
        if sensor.keOn == true then debt[sensor] = nil else Park(sensor) end
    end
    for button in pairs(buttonDebt) do InitSensorButton(button) end
end

-- The host is a KE frame, so hiding it is never refused, and a hidden
-- container drops its aura events (Blizzard_AuraContainer.lua
-- ShouldRegisterForDynamicEvents).
-- A read in Edit Mode would look like every buff falling, and the first one
-- after it like every buff rising, so reads stop and the trackers unprime.
local function OnEditModeEnter()
    editMode = true
    for st in pairs(Track.slots) do Track.Unprime(st) end
end

local function OnEditModeExit()
    editMode = false
    Track.HoldAll(BIND_HOLD)
end

-- Called only by the content gate: no slot is bound when the sensors show,
-- and every later bind holds its reads.
function Track.ShowSensors()
    sensorsShown = true
    if sensHost then sensHost:Show() end
    local manager = _G.EditModeManagerFrame
    editMode = manager ~= nil and manager:IsEditModeActive() == true
    EventRegistry:RegisterCallback("EditMode.Enter", OnEditModeEnter, Track)
    EventRegistry:RegisterCallback("EditMode.Exit", OnEditModeExit, Track)
end

function Track.HideSensors()
    sensorsShown = false
    if sensHost then sensHost:Hide() end
    EventRegistry:UnregisterCallback("EditMode.Enter", Track)
    EventRegistry:UnregisterCallback("EditMode.Exit", Track)
    editMode = false
end

local function Lit(sensor)
    return pcall(sensor.IsMouseOver, sensor, 1e5, -1e5, 0, 0)
end

local function ReadCell(st, i, n)
    local t, sensor = st.trackers[i], st.sensors[i]
    if not (st.ready[i] and t and sensor and sensor.keOn == true) then return end
    local ok, lit = Lit(sensor)
    if not ok then return end
    local short
    if t.hasShort then
        local shortSensor = st.shorts[i]
        if not (shortSensor and shortSensor.keOn == true) then return end
        local okShort
        okShort, short = Lit(shortSensor)
        if not okShort then return end
    end
    -- Closed door: no use is seen here, and a count already running from
    -- plain reads goes on.
    if not Track.DoorOpen() and (issecretvalue(lit) or issecretvalue(short)) then
        t.primed = false
        return
    end
    if Rules.Feed(t, lit, short, n, issecretvalue, EvalBool) then
        Push(t, n)
        Track.Wake()
    end
end

-- While the interface is hidden its containers show nothing, so a read then
-- would look like every buff falling.
local function ReadSlot(st)
    if not st.unit then
        st.pending = false
        return
    end
    local now = GetTime()
    if now < st.holdUntil then
        C_Timer.After(st.holdUntil - now + READ_DELAY, st.readFn)
        return
    end
    if not UIParent:IsShown() then
        Track.Unprime(st)
        C_Timer.After(HIDDEN_RETRY, st.readFn)
        return
    end
    -- Leaving Edit Mode holds and re-arms every bound slot.
    if editMode then
        Track.Unprime(st)
        st.pending = false
        return
    end
    st.reads = st.reads - 1
    if st.reads > 0 then
        C_Timer.After(READ_DELAY, st.readFn)
    else
        st.pending = false
    end
    local n = Track.Now()
    for i = 1, st.count do pcall(ReadCell, st, i, n) end
end

function Track.NewSlot(holder)
    local st = {
        holder = holder, entries = {}, cells = {}, trackers = {}, sensors = {}, shorts = {},
        ready = {}, shown = {}, count = 0, reads = 0, holdUntil = 0,
    }
    st.evt = CreateFrame("Frame")
    st.evt:SetScript("OnEvent", function() Track.Arm(st) end)
    st.readFn = function() ReadSlot(st) end
    Track.slots[st] = true
    return st
end

-- UNIT_AURA is only a trigger; its payload is never read. Each asks for READS
-- reads READ_DELAY apart, since the container lays out after its own pass.
function Track.Arm(st)
    st.reads = READS
    if st.pending then return end
    st.pending = true
    C_Timer.After(READ_DELAY, st.readFn)
end

function Track.Unprime(st)
    for i = 1, st.count do
        local t = st.trackers[i]
        if t then t.primed = false end
    end
end

-- Reads wait seconds, or longer when an earlier hold ends later; the first
-- one after only records, so a refresh of the auras is not taken for a use.
function Track.Hold(st, seconds)
    st.holdUntil = math_max(st.holdUntil, GetTime() + seconds)
    Track.Unprime(st)
    if st.unit then Track.Arm(st) end
end

function Track.HoldAll(seconds)
    for st in pairs(Track.slots) do Track.Hold(st, seconds) end
end

-- At a key's start the game resets some cooldowns: their counts end and the
-- cells show ready. Clear only writes, so a count held in secret values is
-- cleared without being read, and its next read only records.
function Track.KeyStart()
    local n = Track.Now()
    for st in pairs(Track.slots) do
        for i = 1, st.count do
            local t, e = st.trackers[i], st.entries[i]
            if t and e and Rules.ResetsAtKeyStart(e) then
                Rules.Clear(t, n)
                Push(t, n)
            end
        end
    end
end

local function Sig(e)
    return table_concat(e.buffs, ",") .. "/" .. tostring(e.short) .. "/" .. e.cd
end

local function Retire(st, i)
    local c = st.cells[i]
    if c then Cell.Clear(c) end
    Park(st.sensors[i])
    Park(st.shorts[i])
    local t = st.trackers[i]
    if t then Track.Forget(t) end
    st.trackers[i], st.ready[i], st.shown[i] = nil, nil, nil
end

-- A cell that is not ready is hidden and unread; its first read once ready
-- only records. Returns true when the cell has just become ready.
local function Reveal(st, i, n)
    local c, t = st.cells[i], st.trackers[i]
    if st.ready[i] then
        Push(t, n)
        Track.Watch(t)
        c:Show()
        local fresh = not st.shown[i]
        st.shown[i] = true
        return fresh
    end
    st.shown[i] = nil
    Track.EmptyOverlaySlot(st, i)
    Park(st.sensors[i])
    Park(st.shorts[i])
    Track.Forget(t)
    t.primed = false
    Cell.Clear(c)
    return false
end

function Track.Withhold(st, i)
    if not st.ready[i] then return end
    st.ready[i] = false
    Reveal(st, i, Track.Now())
end

-- A new spec starts every cell ready, even where its list matches the old one.
function Track.Reset(st)
    for i = 1, st.count do
        local t = st.trackers[i]
        if t then Track.Forget(t) end
        st.trackers[i] = nil
    end
end

-- Aims an existing sensor. Returns whether the cell can use it, whether a
-- call was refused (as opposed to the sensor not being built yet), and
-- whether the sensor was bound, re-pointed or re-enabled.
local function Ready(sensor, sig, buffs, short, unit)
    if not sensor then return false, false, false end
    local ok, changed = Aim(sensor, sig, buffs, short, unit)
    return ok, not ok, changed
end

-- Points the slot's cells at entries for unit. Containers are only aimed
-- here; BuildNext makes the missing ones, one per call. A cell keeps its
-- running timer while its buffs and length are unchanged.
function Track.Apply(st, unit, entries, style, settings)
    local clean, moved = true, false
    local n = Track.Now()
    if st.unit ~= unit then
        for i = 1, st.count do Retire(st, i) end
        st.unit = unit
        moved = true
    end
    -- The trigger is recorded only once registered, so a refusal is retried.
    if st.evtUnit ~= unit then
        st.evt:UnregisterAllEvents()
        if pcall(st.evt.RegisterUnitEvent, st.evt, "UNIT_AURA", unit) then
            st.evtUnit = unit
        else
            st.evtUnit, clean = nil, false
        end
    end
    for i, e in ipairs(entries) do
        local c = st.cells[i]
        if not c then
            c = Cell.New(st.holder)
            st.cells[i] = c
        end
        Cell.Dress(c, style, e)
        local sig = Sig(e)
        local t = st.trackers[i]
        if not t or t.sig ~= sig then
            if t then Track.Forget(t) end
            t = Rules.NewTracker(e.cd, e.short ~= nil)
            t.sig, t.cell = sig, c
            Rules.Clear(t, n)
            st.trackers[i] = t
            moved = true
        end
        local ready, refused, aimed = Ready(st.sensors[i], sig, e.buffs, nil, unit)
        if e.short then
            local shortReady, shortRefused, shortAimed = Ready(st.shorts[i], sig, e.buffs, e.short, unit)
            ready, refused = ready and shortReady, refused or shortRefused
            aimed = aimed or shortAimed
        else
            Park(st.shorts[i])
        end
        if refused then clean = false end
        if aimed and ready then moved = true end
        st.ready[i] = ready
    end
    for i = #entries + 1, st.count do Retire(st, i) end
    st.entries, st.count = entries, #entries
    local overlayClean, restyle = Track.ApplyOverlay(st, entries, unit, settings)
    local fresh = false
    for i = 1, st.count do
        if Reveal(st, i, n) then fresh = true end
    end
    -- A sensor bound, re-pointed or re-enabled settles before it is read. A
    -- cell that has just become ready is primed by these reads, however long
    -- ago the slot's bind reads ran.
    if moved then Track.Hold(st, BIND_HOLD) elseif fresh then Track.Arm(st) end
    return clean and overlayClean, restyle
end

-- True while a cell of the slot waits for a container.
function Track.Missing(st)
    if not st.unit then return false end
    for i = 1, st.count do
        local e = st.entries[i]
        if not st.sensors[i] or (e.short and not st.shorts[i]) then return true end
    end
    return Track.OverlayMissing(st)
end

-- Builds one missing container: each is a full aura scan, so the caller
-- spends at most one per frame. Returns false when the build was refused.
function Track.BuildNext(st)
    if not st.unit then return true end
    for i = 1, st.count do
        local e = st.entries[i]
        if not st.sensors[i] then
            local sensor = NewSensor(e.buffs)
            if not sensor then return false end
            sensor.keSig = Sig(e)
            st.sensors[i] = sensor
            return true
        end
        if e.short and not st.shorts[i] then
            local short = NewSensor(e.buffs, e.short)
            if not short then return false end
            short.keSig = Sig(e)
            st.shorts[i] = short
            return true
        end
    end
    return Track.BuildOverlayNext(st)
end

function Track.Unbind(st)
    if not st.unit then return end
    st.unit, st.evtUnit = nil, nil
    st.evt:UnregisterAllEvents()
    for i = 1, st.count do Retire(st, i) end
    if st.overlay then
        st.overlayOff = true
        st.overlayHost:Hide()
        pcall(st.overlay.SetEnabled, st.overlay, false)
        st.overlayUnit = nil
    end
    st.count = 0
end

-- The secret path needs EvaluateColorValueFromBoolean to carry k / 255
-- exactly; it is measured once, on the first enable.
function Track.Enable()
    if not Track.door then Track.door = Rules.DoorVerdict(EvalBool, issecretvalue) end
end

function Track.Disable()
    for st in pairs(Track.slots) do Track.Unbind(st) end
    Track.HideSensors()
    wipe(Track.live)
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
end

---------------------------------------------------------------------------------
-- Active state: an engine aura slot per cell, laid over it. While the buff is
-- up it shows KE's swipe and timer; when the buff falls the engine hides it
-- and the cooling cell underneath shows.
---------------------------------------------------------------------------------
local OVERLAY_DESCRIPTORS = {
    offensive = { key = "cdOffensive",
        capabilities = { hasBorder = true, hasDispelRing = true, ringColorKey = "CellRingOffensive" } },
    defensive = { key = "cdDefensive",
        capabilities = { hasBorder = true, hasDispelRing = true, ringColorKey = "CellRingDefensive" } },
    trinket   = { key = "cdTrinket",
        capabilities = { hasBorder = true, hasDispelRing = true, ringColorKey = "CellRingTrinket" } },
}
Track.OVERLAY_DESCRIPTORS = OVERLAY_DESCRIPTORS

-- A slot's key changes after a failed add: a second add of a key asserts, and
-- the container cannot say whether the first one registered.
local function SlotKey(st, i)
    return "cd" .. i .. "." .. (st.overlayGen[i] or 0)
end

local EMPTY = { includeSpellIDs = {} }

-- Failed overlay builds per row: the container, its setup or a slot add. An
-- add can leave a button the container keeps for good; past this the row's
-- cells work without an overlay.
local MAX_OVERLAY_FAILS = 2

local function OverlaySpent(st)
    return (st.overlayFails or 0) >= MAX_OVERLAY_FAILS
end

-- Hides every button at once: the host is a KE frame, and hiding it is never
-- refused. Every cell of the slot stays unready until the drain.
local function Quarantine(st)
    st.overlayOff = true
    st.overlayHost:Hide()
    pcall(st.overlay.SetEnabled, st.overlay, false)
    st.overlayUnit = nil
    local n = Track.Now()
    for i = 1, st.count do
        if st.ready[i] then
            st.ready[i] = false
            Reveal(st, i, n)
        end
    end
end

-- One slot's filter: buffs, or nothing when buffs is nil. A refused call may
-- or may not have changed the filter, so it is recorded as unknown.
local function Point(st, i, buffs)
    local sig = buffs and table_concat(buffs, ",") or ""
    if st.overlaySigs[i] == sig then return true end
    local filters = buffs and { includeSpellIDs = BuffSet(buffs) } or EMPTY
    if pcall(st.overlay.SetAuraSlotCandidateFilters, st.overlay, SlotKey(st, i), filters) then
        st.overlaySigs[i] = sig
        return true
    end
    st.overlaySigs[i] = nil
    return false
end

-- A hidden cell's button is emptied, so it never shows over nothing.
function Track.EmptyOverlaySlot(st, i)
    if st.overlayOff or not (st.overlay and st.overlayButtons[i]) then return end
    if not Point(st, i, nil) then Quarantine(st) end
end

function Track.OverlayMissing(st)
    if OverlaySpent(st) then return false end
    if not (st.overlay and st.overlaySetUp) then return st.count > 0 end
    for i = 1, st.count do
        if not st.overlayButtons[i] then return true end
    end
    return false
end

-- Size, anchor and disable the new container. Until all of it is accepted the
-- overlay counts as not built and its host stays hidden.
local function SetUpOverlay(st)
    local container, host = st.overlay, st.overlayHost
    st.overlaySetUp = pcall(function()
        container:SetSize(1, 1)
        container:ClearAllPoints()
        container:SetPoint("CENTER", host, "CENTER", 0, 0)
        container:EnableMouse(false)
        container:SetEnabled(false)
    end)
    return st.overlaySetUp
end

-- One failed overlay build. The second result asks the caller to try again
-- next frame, which the cap makes safe.
local function Failed(st)
    st.overlayFails = (st.overlayFails or 0) + 1
    return false, true
end

-- One container or one aura slot per call, like the sensors.
function Track.BuildOverlayNext(st)
    if OverlaySpent(st) then return true end
    if not st.overlay then
        if st.count == 0 then return true end
        local host = st.overlayHost
        if not host then
            host = CreateFrame("Frame", nil, st.holder)
            host:SetAllPoints(st.holder)
            host:Hide()
            st.overlayHost = host
        end
        local ok, container = pcall(CreateFrame, "AuraContainer", nil, host, "CustomAuraContainerTemplate")
        if not ok or not container then return Failed(st) end
        st.overlay, st.overlayOff, st.overlaySetUp = container, true, false
        st.overlayButtons, st.overlaySigs, st.overlayKinds, st.overlayWant = {}, {}, {}, {}
        st.overlayGen, st.overlayMax = {}, 0
        if SetUpOverlay(st) then return true end
        return Failed(st)
    end
    if not st.overlaySetUp then
        if SetUpOverlay(st) then return true end
        return Failed(st)
    end
    local container = st.overlay
    for i = 1, st.count do
        if not st.overlayButtons[i] then
            local e, cell = st.entries[i], st.cells[i]
            local d, settings, key = OVERLAY_DESCRIPTORS[e.kind], st.overlaySettings, SlotKey(st, i)
            -- The engine runs this inside the add, before the button's
            -- restrictions attach, and swallows its errors, so it records its
            -- own result.
            local inited = false
            -- Added empty: a key a failed add left registered never shows,
            -- and the apply that follows points a good one at its buffs.
            local added, button = pcall(container.AddAuraSlot, container, key, "HELPFUL", {
                candidateFilters = EMPTY,
                initializeFrame = function(b)
                    inited = pcall(function()
                        b:ClearAllPoints()
                        b:SetPoint("CENTER", cell, "CENTER", 0, 0)
                        KE.AuraStyle.InitializeButton(b, nil, d, settings)
                        b:SetMouseClickEnabled(false)
                    end)
                end,
            })
            if added and button and inited then
                st.overlayButtons[i], st.overlaySigs[i], st.overlayKinds[i] = button, "", e.kind
                st.overlayMax = math_max(st.overlayMax, i)
                return true
            end
            -- No usable button (none returned, or its setup failed, and
            -- InitializeButton cannot run twice): whatever the engine kept
            -- stays empty under this key, and the next add uses a new key.
            st.overlayGen[i] = (st.overlayGen[i] or 0) + 1
            -- The container takes no access restriction (only its buttons do,
            -- after this setup), so every failure counts.
            return Failed(st)
        end
    end
    return true
end

-- Re-points the built slots: a ready cell's slot holds its buffs, any other
-- slot holds nothing. A cell whose slot is not built is not ready. Any refused
-- call hides the whole overlay and leaves every cell unready until the drain.
-- Returns whether every call was accepted, and whether a button now stands for
-- another kind.
function Track.ApplyOverlay(st, entries, unit, settings)
    st.overlaySettings = settings
    local container = st.overlay
    local spent = OverlaySpent(st)
    if not (container and st.overlaySetUp) then
        -- With the builds spent the cells work without an overlay.
        if not spent then
            for i = 1, #entries do st.ready[i] = false end
        end
        return true, false
    end
    local buttons, kinds, want = st.overlayButtons, st.overlayKinds, st.overlayWant
    local clean, restyle = true, false
    for i, e in ipairs(entries) do
        want[i] = e.kind
        if not buttons[i] then
            -- With the adds spent the cell works without an overlay: it turns
            -- gray when the buff appears instead of when it falls.
            if not spent then st.ready[i] = false end
        else
            if not Point(st, i, st.ready[i] and e.buffs or nil) then clean = false end
            if kinds[i] ~= e.kind then restyle = true end
        end
    end
    for i = #entries + 1, st.overlayMax do
        want[i] = nil
        if buttons[i] and not Point(st, i, nil) then clean = false end
    end
    clean = clean and pcall(function()
        if st.overlayUnit ~= unit then
            container:SetUnit(unit)
            st.overlayUnit = unit
        end
        container:SetFrameStrata(st.holder:GetFrameStrata())
        container:SetFrameLevel(st.holder:GetFrameLevel() + 10)
        container:SetEnabled(true)
    end)
    if clean then
        st.overlayOff = false
        st.overlayHost:Show()
    else
        Quarantine(st)
    end
    return clean, restyle
end

-- Behind the caller's gate: the buttons refuse addon writes while auras are
-- secret.
function Track.RestyleOverlay(st, settings)
    local clean = true
    for i, button in pairs(st.overlayButtons or {}) do
        local kind = st.overlayWant[i] or st.overlayKinds[i]
        local d = kind and OVERLAY_DESCRIPTORS[kind]
        if d then
            local ok = pcall(KE.AuraStyle.RegisterRegions, button, nil, d, settings)
            ok = pcall(KE.AuraStyle.StyleAuraFrame, button, settings, d.capabilities) and ok
            if ok then st.overlayKinds[i] = kind else clean = false end
        end
    end
    return clean
end
