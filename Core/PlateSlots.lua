-- ╔══════════════════════════════════════════════════════════╗
-- ║  Core/PlateSlots.lua                                     ║
-- ║  Purpose: stable slots for counted enemy nameplates, and ║
-- ║           a build runner that does one step per frame.   ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- The nameplate half of a per-plate aura display: which counted plate holds
-- which slot, and when a slot is taken or let go. It makes no aura container;
-- the consumer builds and binds its own from the callbacks.

---@class KE
local KE = select(2, ...)

local math_floor, math_max, math_min = math.floor, math.max, math.min
local pcall, setmetatable, tonumber = pcall, setmetatable, tonumber

local MAX_PLATES = 40

local PlateSlots = {}
KE.PlateSlots = PlateSlots

local plateTokens, plateIndex

local function EnsureTokens()
    if plateTokens then return end
    plateTokens, plateIndex = {}, {}
    for i = 1, MAX_PLATES do
        local token = "nameplate" .. i
        plateTokens[i] = token
        plateIndex[token] = i
    end
end

local function Clamp(n)
    return math_max(0, math_min(MAX_PLATES, math_floor(tonumber(n) or 0)))
end

-- true, false, or nil when the call errors or answers with a secret. The
-- caller decides which way nil points.
function PlateSlots.Ask(fn, ...)
    if not fn then return nil end
    local ok, value = pcall(fn, ...)
    if not ok or (issecretvalue and issecretvalue(value)) then return nil end
    return value and true or false
end

function PlateSlots.PickStrict(relaxAllowed, anyPasses)
    return not relaxAllowed or anyPasses == true
end

---------------------------------------------------------------------------------
-- Slots
---------------------------------------------------------------------------------
local Slots = {}
Slots.__index = Slots

local function Counts(self, unit, strict)
    return self.verdict(unit, strict) == nil
end

local function FirstFree(self)
    local slot = 1
    while slot <= self.cap and self.unitOf[slot] do slot = slot + 1 end
    if slot > self.cap then return nil end
    return slot
end

local function Take(self, slot, unit)
    self.unitOf[slot] = unit
    self.slotOf[unit] = slot
    self.total = self.total + 1
    if self.onTake then self.onTake(slot, unit) end
end

local function Release(self, slot)
    local unit = self.unitOf[slot]
    if not unit then return false end
    self.unitOf[slot] = nil
    self.slotOf[unit] = nil
    self.total = self.total - 1
    if self.onRelease then self.onRelease(slot, unit) end
    return true
end

local function ScanDone(self)
    if self.onScanDone then self.onScanDone(self.total) end
end

local function OnEvent(frame, event, unit)
    local self = frame.owner
    local index = plateIndex[unit]
    if not index then return end
    if event == "NAME_PLATE_UNIT_REMOVED" then
        -- Let go now, not on the next frame: within this one the token can pass
        -- to another mob, and a later scan would find "the same unit" standing.
        self.up[index] = false
        local slot = self.slotOf[unit]
        if slot then Release(self, slot) end
        self:QueueScan()
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        self.up[index] = true
        self:QueueScan()
    elseif self.onUnitEvent then
        self.onUnitEvent(self, event, unit)
    end
end

function PlateSlots.New(opts)
    EnsureTokens()
    local self = setmetatable({
        verdict = opts.verdict,
        relax = opts.relax,
        onTake = opts.onTake,
        onRelease = opts.onRelease,
        onScanDone = opts.onScanDone,
        tickSeconds = opts.tickSeconds,
        unitEvents = opts.unitEvents,
        onUnitEvent = opts.onUnitEvent,
        cap = Clamp(opts.cap or MAX_PLATES),
        unitOf = {},
        slotOf = {},
        up = {},
        total = 0,
        strict = true,
        started = false,
        queued = false,
    }, Slots)
    self.runQueued = function()
        self.queued = false
        if self.started then self:ScanNow() end
    end
    self.tick = function() self:QueueScan() end
    return self
end

function Slots:Start()
    if self.started then return end
    self.started = true
    local frame = self.frame
    if not frame then
        frame = CreateFrame("Frame")
        frame.owner = self
        frame:SetScript("OnEvent", OnEvent)
        self.frame = frame
    end
    frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    if self.unitEvents then
        for i = 1, #self.unitEvents do frame:RegisterEvent(self.unitEvents[i]) end
    end
    if self.tickSeconds then
        self.ticker = C_Timer.NewTicker(self.tickSeconds, self.tick)
    end
    -- Plates already up fired their added events before this started.
    for i = 1, MAX_PLATES do
        self.up[i] = PlateSlots.Ask(UnitExists, plateTokens[i]) == true
    end
    self:QueueScan()
end

function Slots:Stop()
    if not self.started then return end
    self.started = false
    self.frame:UnregisterAllEvents()
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
    for slot = 1, MAX_PLATES do Release(self, slot) end
    ScanDone(self)
end

-- A pull is a burst of plate and flag events; one scan on the next frame
-- answers all of them.
function Slots:QueueScan()
    if self.queued or not self.started then return end
    self.queued = true
    C_Timer.After(0, self.runQueued)
end

function Slots:ScanNow()
    local up, unitOf, slotOf = self.up, self.unitOf, self.slotOf
    local relaxAllowed = self.relax ~= nil and self.relax() == true
    local anyPasses
    if relaxAllowed then
        anyPasses = false
        for i = 1, MAX_PLATES do
            if up[i] and Counts(self, plateTokens[i], true) then
                anyPasses = true
                break
            end
        end
    end
    local strict = PlateSlots.PickStrict(relaxAllowed, anyPasses)
    self.strict = strict

    for slot = 1, MAX_PLATES do
        local unit = unitOf[slot]
        if unit and (slot > self.cap or not Counts(self, unit, strict)) then Release(self, slot) end
    end
    -- A unit keeps its slot while it counts, so a pull bigger than the cap drops
    -- the latecomers instead of reshuffling.
    for i = 1, MAX_PLATES do
        local unit = plateTokens[i]
        if up[i] and not slotOf[unit] and Counts(self, unit, strict) then
            local free = FirstFree(self)
            if not free then break end
            Take(self, free, unit)
        end
    end
    ScanDone(self)
end

function Slots:Recheck(unit)
    local index = plateIndex[unit]
    if not self.started or not index or not self.up[index] then return end
    local slot = self.slotOf[unit]
    local counts = Counts(self, unit, self.strict)
    local released = false
    if slot and not counts then
        released = Release(self, slot)
    elseif not slot and counts then
        local free = FirstFree(self)
        if free then Take(self, free, unit) end
    end
    ScanDone(self)
    -- A freed slot belongs to the next plate waiting past the cap. With a
    -- relax rule, one plate can change the strictness for all of them, and
    -- the last scan's may be stale even while relaxing is off now. Only a
    -- full scan settles either.
    if released or self.relax then self:QueueScan() end
end

function Slots:SetCap(n)
    local cap = Clamp(n)
    if cap == self.cap then return end
    local lowered = cap < self.cap
    self.cap = cap
    if not self.started then return end
    if lowered then
        for slot = cap + 1, MAX_PLATES do Release(self, slot) end
        ScanDone(self)
    end
    self:QueueScan()
end

function Slots:UnitOf(slot) return self.unitOf[slot] end
function Slots:SlotOf(unit) return self.slotOf[unit] end
function Slots:Total() return self.total end
function Slots:Cap() return self.cap end
function Slots:IsStarted() return self.started end

---------------------------------------------------------------------------------
-- Build runner
---------------------------------------------------------------------------------
local Runner = {}
Runner.__index = Runner

function PlateSlots.NewBuildRunner(opts)
    local self = setmetatable({
        buildSlot = opts.buildSlot,
        onProgress = opts.onProgress,
        target = 0,
        step = 0,
        running = false,
        waiting = false,
    }, Runner)
    self.resumeNext = function()
        self.waiting = false
        self:Advance()
    end
    return self
end

local function Step(self, slot)
    local didWork = self.buildSlot(slot)
    self.step = slot
    if self.onProgress then self.onProgress(slot) end
    return didWork
end

-- A step that built something ends the frame; a step with nothing to build goes
-- on in the same one. A step that raises stops the walk rather than leave it
-- marked running, and the next Run picks up where it stopped.
function Runner:Advance()
    while self.running and self.step < self.target do
        local ok, didWork = pcall(Step, self, self.step + 1)
        if not ok then
            self.running = false
            error(didWork, 0)
        end
        if didWork and self.step < self.target then
            self.waiting = true
            C_Timer.After(0, self.resumeNext)
            return
        end
    end
    self.running = false
end

function Runner:Run(target)
    target = Clamp(target)
    if target > self.target then self.target = target end
    if self.running or self.step >= self.target then return end
    self.running = true
    if not self.waiting then self:Advance() end
end

function Runner:Cancel()
    self.running = false
    self.step = 0
    self.target = 0
end

function Runner:Built()
    return self.step
end
