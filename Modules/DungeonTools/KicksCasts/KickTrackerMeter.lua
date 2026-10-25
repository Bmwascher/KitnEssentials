-- ╔══════════════════════════════════════════════════════════╗
-- ║  KickTrackerMeter.lua                                    ║
-- ║  Module: Interrupt Tracker                               ║
-- ║  Purpose: who kicked when the game hides the kicker,     ║
-- ║           from the Damage Meter's interrupt lists.       ║
-- ╚══════════════════════════════════════════════════════════╝
-- In a dungeon the game hides who stopped a cast. The Damage Meter still
-- keeps, for each group member and pet, an Interrupts list with one entry per
-- enemy spell they kicked this fight, and rows of class and spec icon in
-- count order; both read plainly. Each Interrupts update is read once, a
-- frame later, against the last read, and KT.Decide names the kicker from the
-- best evidence: a list that grew, a new or moved row only one teammate fits,
-- the player's own cast a moment before, or the only teammate who could have
-- kicked. Hidden nameplate interrupts within PAIR_WINDOW of an update take
-- its answer for their kicked spell and raid mark. The meter's totals are
-- secret in combat and are never read here.
--
-- A kick nobody is named for gets a reveal layer over the bar of each
-- teammate who could have landed it: a copy of their bar on cooldown inside a
-- clip whose left edge hangs from the fill of a hidden status bar, fed their
-- total before the update as its value and after it as its maximum. The fill
-- is whole, and the clip empty, unless the total rose; then the clip opens
-- over the whole bar. Only the teammate who kicked shows the kick, and Lua
-- never learns who. Layers are pooled, newest on top, each with an opaque
-- backing, and go when their clock ends, when a sure kick of the teammate
-- supersedes them, when the bar goes, and on deactivation, preview, disable
-- and every settings change. Nothing is ever read back from a layer.

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@type KickTracker
local KT = KitnEssentials:GetModule("KickTracker")

local GetTime = GetTime
local C_Timer = C_Timer
local C_DamageMeter = C_DamageMeter
-- Group-member and pet unit reads stay plain; KE:IsSafeValue still guards
-- each pet GUID.
---@type fun(unit: string): string?
local UnitGUID = UnitGUID
local UnitExists = UnitExists
local GetSpecializationInfoForSpecID = GetSpecializationInfoForSpecID
local issecretvalue = issecretvalue
local canaccesstable = canaccesstable
local string_format = string.format
local pairs = pairs
local type = type
local wipe = wipe

local PAIR_WINDOW = 0.25  -- a hidden plate and the meter update it pairs with
local OWN_WINDOW = 1      -- after the player's kick cast, a credited kick is the player's
local CURRENT = Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Current
local METER_INTERRUPTS = Enum and Enum.DamageMeterType and Enum.DamageMeterType.Interrupts
local EMPTY = {}

-- Flip true to log each meter decision (plain counts and names only).
-- Default false; revert after diagnosis.
local DEBUG_KT_METER = false

local CreateFrame = CreateFrame
local table_remove = table.remove
local unpack = unpack
local WHITE = "Interface\\Buttons\\WHITE8X8"
-- A layer's gate is GATE_SPAN bar widths (each GATE_PAD wider) long, so a
-- total that rose by one opens the clip over the whole bar up to GATE_SPAN
-- interrupts in a fight; its right end sits GATE_EDGE past the bar's, and it
-- is GATE_TALL taller than the bar, centered.
local GATE_SPAN, GATE_PAD, GATE_EDGE, GATE_TALL = 100, 4, 2, 24
local LAYER_STEP = 4    -- frame levels a bar copy takes: the bar, its fill, its icon two above
local LAYER_DEPTH = 29  -- the deepest stack drawn in order; deeper layers share the top level
-- Main kicks a Warlock's demon casts: the demon's own list moves for them.
local DEMON_KICKS = { [19647] = true, [89766] = true }
local PET_SLOT = { party1 = "partypet1", party2 = "partypet2", party3 = "partypet3", party4 = "partypet4" }

local function NewRead()
    return { rows = {}, rowsOk = false, n = {}, a = {}, guid = {} }
end

-- A read: rows (KT.RowKey per meter row, in order), rowsOk, sid (its
-- update's plain session ID, or nil), and per slot n (list length, plain), a (total, opaque: only
-- ever handed to a layer) and guid.
KT.meterBase = NewRead()   -- the read the next update is measured against
KT.meterRead = NewRead()   -- the spare the next read fills
KT.meterPrevN, KT.meterPrevA = {}, {}  -- one update's baseline (KT.BaselineCounts)
KT.meterGrowth = {}    -- [unit] = this update's list growth before expected counts
KT.meterExpected = {}  -- [unit] = { n, at, guid }: readable kicks whose growth is still owed
KT.meterCredited = {}  -- [unit] = the update that last credited them by growth
KT.meterByUnit, KT.meterGuidOf = {}, {}
KT.meterDecision = { grew = {}, growthOf = {}, entries = {}, cooling = {}, candidates = {}, rowList = {},
                     plates = 0, ownPending = false }  -- KT.Decide's inputs for the last update
KT.meterMemo = { lastT = -1, pairedT = -1, grew = false }  -- the last update's answer
KT.meterNeedsBase = true  -- the next read is a baseline, not evidence
KT.plates = {}    -- the hidden-plate batch, oldest first
KT.platesT = -1   -- the batch's start
KT.layersOf = {}    -- [guid] = that teammate's live layers, oldest first
KT.freeLayers = {}  -- released layers, ready for reuse
KT.meterFight = 0   -- moves at each new fight and baseline, so an older baseline counts as 0
KT.plateAdmitted = {}  -- one update's teammates KT.AdmitGate took, for the plate display

local function ClearRead(read)
    wipe(read.rows)
    wipe(read.n)
    wipe(read.a)
    wipe(read.guid)
    read.rowsOk, read.sid = false, nil
end

-- A meter value is used only as a plain, accessible table.
local function Usable(t)
    return not issecretvalue(t) and type(t) == "table" and canaccesstable(t)
end

local function PlainNumber(v)
    if issecretvalue(v) or type(v) ~= "number" then return nil end
    return v
end

local function MeterReady()
    return C_DamageMeter and C_DamageMeter.GetCombatSessionFromType
        and C_DamageMeter.GetCombatSessionSourceFromType and CURRENT and METER_INTERRUPTS
end

-- The Current session's rows in the meter's order, each keyed by KT.RowKey (a
-- row whose class or icon does not read keeps its place with a key that
-- matches nobody). Returns whether the rows read.
local function ReadRows(rows)
    wipe(rows)
    local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, CURRENT, METER_INTERRUPTS)
    if not ok or not Usable(session) then return false end
    local sources = session.combatSources
    if not Usable(sources) then return false end
    for i = 1, #sources do
        local src = sources[i]
        local class, icon, isLocal
        if Usable(src) then
            class = src.classFilename
            if issecretvalue(class) or type(class) ~= "string" then class = nil end
            icon = PlainNumber(src.specIconID)
            isLocal = src.isLocalPlayer
            if issecretvalue(isLocal) then isLocal = nil end
        end
        rows[i] = KT.RowKey(class, icon, isLocal)
    end
    return true
end

-- One source by its GUID: its list length (plain) and its total (opaque,
-- never read), or nil when the read is not usable.
local function ReadSource(guid)
    local ok, source = pcall(C_DamageMeter.GetCombatSessionSourceFromType, CURRENT, METER_INTERRUPTS, guid)
    if not ok or not Usable(source) then return nil, nil end
    local spells = source.combatSpells
    if not Usable(spells) then return nil, nil end
    return #spells, source.totalAmount
end

local specIcons = {}
local function SpecIconOf(specID)
    if type(specID) ~= "number" or specID <= 0 then return nil end
    local cached = specIcons[specID]
    if cached ~= nil then return cached or nil end
    local ok, _, _, _, icon = pcall(GetSpecializationInfoForSpecID, specID)
    if not ok or issecretvalue(icon) or type(icon) ~= "number" then icon = false end
    specIcons[specID] = icon
    return icon or nil
end

---------------------------------------------------------------------------------
-- Reads
---------------------------------------------------------------------------------
function KT:MembersByUnit()
    local byUnit, guidOf = wipe(self.meterByUnit), wipe(self.meterGuidOf)
    for guid, member in pairs(self.partyMembers) do
        local unit = member.unit
        if unit then byUnit[unit], guidOf[unit] = member, guid end
    end
    return byUnit, guidOf
end

-- One read into read: the rows, then each slot's list length and total by
-- its GUID (each member, and each pet whose GUID reads plain). At most 11
-- protected calls. A slot whose read fails has no count.
function KT:ReadMeter(read)
    local _, guidOf = self:MembersByUnit()
    wipe(read.n)
    wipe(read.a)
    wipe(read.guid)
    if not MeterReady() then
        wipe(read.rows)
        read.rowsOk, read.sid = false, nil
        return
    end
    read.rowsOk, read.sid = ReadRows(read.rows), nil
    for i = 1, #KT.SLOTS do
        local slot = KT.SLOTS[i]
        local guid = guidOf[slot]
        if not guid and KT.SlotOwner(slot) ~= slot and UnitExists(slot) then
            local petGuid = UnitGUID(slot)
            if KE:IsSafeValue(petGuid) then guid = petGuid end
        end
        if guid then
            read.guid[slot] = guid
            local n, total = ReadSource(guid)
            if n then read.n[slot], read.a[slot] = n, total end
        end
    end
end

---------------------------------------------------------------------------------
-- The decision
---------------------------------------------------------------------------------
-- The player's kick cast is unresolved and T lies within OWN_WINDOW after it.
function KT:OwnPending(T)
    local at = self._ownT
    return self._ownPending == true and at ~= nil and T >= at and T - at <= OWN_WINDOW
end

-- KT.Decide's inputs that do not come from the read: the teammates with a
-- kick row, which of them are modeled as cooling at T, and the own cast.
function KT:DecisionInputs(T, byUnit)
    local e = self.meterDecision
    wipe(e.grew)
    wipe(e.growthOf)
    wipe(e.entries)
    wipe(e.cooling)
    wipe(e.candidates)
    for i = 2, #KT.OWNERS do
        local unit = KT.OWNERS[i]
        local member = byUnit[unit]
        if member and member.interruptData then
            e.candidates[#e.candidates + 1] = unit
            e.cooling[unit] = KT.MainCooling(member, T)
        end
    end
    e.ownPending = self:OwnPending(T)
    e.plates, e.rowKey, e.rowHow = 0, nil, nil
    return e
end

-- A readable kick grows its kicker's list in the next update; one expected
-- count keeps that growth from being credited again. A kick whose growth an
-- earlier update already credited adds none.
function KT:ExpectMeter(owner, guid, now)
    local credited = self.meterCredited[owner]
    if credited and now - credited <= PAIR_WINDOW then return end
    local e = self.meterExpected[owner]
    if e and e.guid == guid then
        e.n, e.at = e.n + 1, now
    else
        self.meterExpected[owner] = { n = 1, at = now, guid = guid }
    end
end

-- A credited kick. A teammate's clock starts at the paired plate's time or
-- the update's, for a confirmed success. The player's clock already runs from
-- the cast; a growth credit confirms its success (KT.OwnSuccessFrom). The
-- kicked spell goes on the row only with exactly one plate.
function KT:RecordMeterKick(unit, T, at, plate, how, ownPending)
    local member, guid = self.meterByUnit[unit], self.meterGuidOf[unit]
    if not member or not guid then return end
    if how == "breakdown" or how == "several" then self.meterCredited[unit] = T end
    if unit == "player" then
        self._ownPending = false
        if KT.OwnSuccessFrom(how, ownPending) then self:ApplyOwnSuccess() end
        if plate then self:ShowKicked(guid, KT.KickedFrom(plate)) end
        if plate and self.platesOn then self:PlaceKickIcon(guid, plate.unit, plate.stamp, true) end
        return
    end
    self:ReleaseLayers(guid, (at > T) and at or T)
    if self.platesOn then self:PlatesSupersede(guid, (at > T) and at or T) end
    local duration = self:ClockDuration(member, true)
    if not duration then return end
    local remaining = duration - (GetTime() - at)
    if remaining <= 0 then return end
    self:ConfirmKick(guid, duration, remaining)
    self:ShowKicked(guid, plate and KT.KickedFrom(plate) or nil)
    if plate and self.platesOn then self:PlaceKickIcon(guid, plate.unit, plate.stamp, true) end
end

-- Decides the update, credits it, and lets the waiting plates go with its
-- answer. Several growers are each credited, with no kicked spell.
function KT:SettleMeter(T, e, landedHere)
    local plates = self.plates
    e.plates = landedHere and #plates or 0
    local who, how, several = KT.Decide(e)
    local first = landedHere and plates[1] or nil
    if several then
        for i = 1, #several do self:RecordMeterKick(several[i], T, T, nil, how, e.ownPending) end
    elseif who then
        self:RecordMeterKick(who, T, first and first.startTime or T, (e.plates == 1) and first or nil,
            how, e.ownPending)
    end
    local memo = self.meterMemo
    memo.lastT, memo.who, memo.how, memo.grew = T, who, how, #e.grew > 0
    -- A grip or a mass interrupt is no kick: no layer. The plate's mark goes
    -- on the layers only when nobody was named.
    if how ~= "mass" and how ~= "grip" then
        self:BuildGate(T, (not who and not several) and first or nil)
    end
    if DEBUG_KT_METER then
        KE:Print(string_format("[KT] meter grew=%d row=%s plates=%d how=%s who=%s", #e.grew,
            tostring(e.rowHow), e.plates, tostring(how), tostring(who)))
    end
    if landedHere then
        memo.pairedT = T
        self:DropPlates()
    end
end

-- The first Interrupts update of a frame, read a frame later against the last
-- read; T is the update's time and sid its plain session ID, or nil. A new
-- fight (KT.NewFightAt) starts growth from nothing. An update with no growth,
-- no row, no own cast pending and no plate waiting decides nothing.
function KT:AttributeMeter(T, sid)
    if self.meterNeedsBase then
        self:RebaseMeter()
        self.meterBase.sid = sid
        return
    end
    local base, read = self.meterBase, self.meterRead
    self:ReadMeter(read)
    local byUnit = self.meterByUnit
    KT.CarryCounts(read, base)
    local prevN = KT.BaselineCounts(read, base, wipe(self.meterPrevN), wipe(self.meterPrevA))
    local prevRows = base.rows
    local shrank = KT.NewFightAt(sid, base.sid, KT.ListsMoved(read.rows, read.n, prevRows, prevN))
    read.sid = sid
    self:ReleasePetSwaps(read, base)
    self.meterBase, self.meterRead = read, base
    -- A new fight keeps the expected counts: one inside PAIR_WINDOW is a
    -- readable kick of this fight, already charged, and growth from nothing
    -- would charge it again.
    if shrank then
        prevRows = EMPTY
        wipe(prevN)
        wipe(self.meterPrevA)
        KT.RestartCarried(read)
        self.meterFight = self.meterFight + 1
    end
    if self.platesOn then self:PlatesCounts(T, self.meterBase.a) end

    local e = self:DecisionInputs(T, byUnit)
    local growth = wipe(self.meterGrowth)
    KT.OwnerGrowth(read.n, prevN, growth, e.entries)
    local readableHere = false
    for i = 1, #KT.OWNERS do
        local unit = KT.OWNERS[i]
        local expected = self.meterExpected[unit]
        if expected and expected.guid ~= read.guid[unit] then self.meterExpected[unit] = nil end
        local left, readable = KT.TakeGrowth(self.meterExpected, unit, growth[unit] or 0, T, PAIR_WINDOW)
        if readable then readableHere = true end
        if left > 0 then
            e.grew[#e.grew + 1] = unit
            e.growthOf[unit] = left
        end
    end

    -- A row no teammate fits is no evidence, nor one a readable kick in this
    -- update moved, even a kick on a repeated spell that grew no list.
    local rowKey, rowHow = KT.ChangedRow(read.rows, prevRows)
    if rowKey then KT.KeyMembers(rowKey, byUnit, SpecIconOf, e.rowList) else wipe(e.rowList) end
    if #e.rowList == 0 or (readableHere and #e.grew == 0) then rowKey, rowHow = nil, nil end
    e.rowKey, e.rowHow = rowKey, rowHow

    local landedHere = #self.plates > 0 and T - self.platesT <= PAIR_WINDOW
    if not rowKey and #e.grew == 0 and not e.ownPending and not landedHere then
        local memo = self.meterMemo
        memo.lastT, memo.who, memo.how, memo.grew = T, nil, "none", false
        self:BuildGate(T, nil)
        return
    end
    self:SettleMeter(T, e, landedHere)
end

---------------------------------------------------------------------------------
-- The plate batch
---------------------------------------------------------------------------------
-- A batch that arrived after its update's read takes that update's answer.
-- One kicker named already gets a single plate's spell and mark, their
-- clock keeping the update's time. An update that named nobody and grew no
-- list is decided again with the batch (rule 4, 7 or 5).
function KT:PairWith(T0)
    local memo, e, plates = self.meterMemo, self.meterDecision, self.plates
    if memo.who then
        local guid = self.meterGuidOf[memo.who]
        if #plates == 1 and guid then self:ShowKicked(guid, KT.KickedFrom(plates[1])) end
        if #plates == 1 and guid and self.platesOn then self:PlaceKickIcon(guid, plates[1].unit, plates[1].stamp, true) end
    elseif not memo.grew then
        e.plates = #plates
        local who, how = KT.Decide(e)
        if who then
            local first = plates[1]
            self:RecordMeterKick(who, T0, first.startTime, (#plates == 1) and first or nil, how, e.ownPending)
            memo.who = who
        end
        memo.how = how
    end
    memo.pairedT = T0
    if not memo.who then self:MarkLayers(T0, plates[1]) end
    if not memo.who and self.platesOn then self:PlatesLatePlates(T0, plates) end
    if DEBUG_KT_METER then
        KE:Print(string_format("[KT] late plates=%d how=%s who=%s", #plates, tostring(memo.how), tostring(memo.who)))
    end
    self:DropPlates()
end

-- A frame after a plate: an update that arrived in the plate's own frame
-- takes the batch with its read; only when none did does the last answered
-- update serve it.
function KT:LatePair()
    self._latePairArmed = false
    if #self.plates == 0 or self._meterReadPending then return end
    local memo = self.meterMemo
    local T0 = memo.lastT
    if T0 >= 0 and self.platesT - T0 <= PAIR_WINDOW and memo.pairedT ~= T0 then self:PairWith(T0) end
end

function KT:DropPlates()
    wipe(self.plates)
    self.platesT = -1
end

-- A batch no update takes within PAIR_WINDOW is dropped: no clock, nothing
-- shown. A read still pending is waited for.
function KT:FlushPlates()
    self._plateFlushArmed = false
    if #self.plates == 0 then return end
    local left = PAIR_WINDOW - (GetTime() - self.platesT)
    if left > 0.001 or self._meterReadPending then
        self._plateFlushArmed = true
        local activation = self.activationID
        C_Timer.After((left > 0) and left or 0, function()
            if self.activationID == activation then self:FlushPlates() end
        end)
        return
    end
    if DEBUG_KT_METER then KE:Print("[KT] hidden plates dropped: no meter update") end
    self:DropPlates()
end

function KT:ArmPlateFlush()
    if self._plateFlushArmed then return end
    self._plateFlushArmed = true
    local activation = self.activationID
    C_Timer.After(PAIR_WINDOW, function()
        if self.activationID == activation then self:FlushPlates() end
    end)
end

-- A hidden kicker's interrupt starts a batch, or joins the one started within
-- PAIR_WINDOW; an older unanswered batch is dropped first.
function KT:QueueHiddenPlate(entry, now)
    local plates = self.plates
    if #plates > 0 and now - self.platesT > PAIR_WINDOW then self:DropPlates() end
    if #plates == 0 then self.platesT = now end
    plates[#plates + 1] = entry
    local memo = self.meterMemo
    if not self._meterReadPending and not self._latePairArmed and memo.lastT >= 0
        and now - memo.lastT <= PAIR_WINDOW and memo.pairedT ~= memo.lastT then
        self._latePairArmed = true
        local activation = self.activationID
        C_Timer.After(0, function()
            if self.activationID == activation then self:LatePair() end
        end)
    end
    self:ArmPlateFlush()
end

---------------------------------------------------------------------------------
-- Baselines and events
---------------------------------------------------------------------------------
-- A new baseline (activation, a meter reset, the preview, a read that must
-- be a baseline): the read is adopted as it stands.
function KT:RebaseMeter()
    local base, read = self.meterBase, self.meterRead
    self:ReadMeter(read)
    KT.CarryCounts(read, base)
    wipe(self.meterExpected)
    self:ReleasePetSwaps(read, base)
    self.meterBase, self.meterRead = read, base
    self.meterNeedsBase = false
    self.meterFight = self.meterFight + 1
    if self.platesOn then self:PlatesCounts(GetTime(), self.meterBase.a) end
end

-- The meter event fires for every meter type, hundreds of times a second in
-- a big pull; any other type is one check and a return. The first Interrupts
-- update of a frame starts one read a frame later, after that frame's other
-- updates and plates; the read takes the last plain session ID they carried.
-- The preview keeps the baseline current instead.
function KT:OnMeterUpdate(_, meterType, sessionID)
    if not METER_INTERRUPTS or issecretvalue(meterType) or meterType ~= METER_INTERRUPTS then return end
    local sid = KT.CurrentSessionOf(PlainNumber(sessionID))
    if sid then self._meterSid = sid end
    if self._meterReadPending then return end
    self._meterReadPending, self._meterSid = true, sid
    local activation, T = self.activationID, GetTime()
    C_Timer.After(0, function()
        if self.activationID ~= activation then return end
        self._meterReadPending = false
        if not self.isActive then return end
        if self.isPreview then
            self:RebaseMeter()
        else
            self:AttributeMeter(T, self._meterSid)
        end
    end)
end

function KT:OnMeterReset()
    if self.isActive then self:RebaseMeter() end
end

-- Every meter state goes together (deactivation, preview, disable): the
-- batch, the reads with their totals, the expected counts and the last
-- answer. The next read is a baseline.
function KT:ClearMeterState()
    self:DropPlates()
    ClearRead(self.meterBase)
    ClearRead(self.meterRead)
    wipe(self.meterPrevN)
    wipe(self.meterPrevA)
    wipe(self.meterExpected)
    wipe(self.meterCredited)
    local memo = self.meterMemo
    memo.lastT, memo.pairedT, memo.who, memo.how, memo.grew = -1, -1, nil, nil, false
    self._meterReadPending, self._latePairArmed, self._plateFlushArmed = false, false, false
    self.meterNeedsBase = true
    self:ReleaseAllLayers()
    if self.platesOn then self:PlatesReset() end
end

---------------------------------------------------------------------------------
-- Reveal layers
---------------------------------------------------------------------------------
-- The slot whose totals gate a teammate's layer: their demon's when their
-- main kick is a demon's and the demon has entries, else their own.
local function GateSlot(member, unit, counts)
    local data, pet = member.interruptData, PET_SLOT[unit]
    if data and DEMON_KICKS[data.id] and pet and (counts[pet] or 0) >= 1 then return pet end
    return unit
end
KT.GateSlot = GateSlot

-- One update's layers: each teammate KT.AdmitGate takes gets one over their
-- bar, fed the gate slot's totals from before and after the update. plate is
-- the update's first hidden plate, for its raid mark, when nobody was named.
function KT:BuildGate(T, plate)
    local base, prevN, prevA = self.meterBase, self.meterPrevN, self.meterPrevA
    local byUnit, guidOf = self.meterByUnit, self.meterGuidOf
    local admitted = self.platesOn and wipe(self.plateAdmitted) or nil
    for i = 2, #KT.OWNERS do
        local unit = KT.OWNERS[i]
        local member = byUnit[unit]
        if member then
            local slot = GateSlot(member, unit, base.n)
            local before, after = prevA[slot], base.a[slot]
            local hasTotals = before ~= nil and after ~= nil
            if KT.AdmitGate(member, KT.MainCooling(member, T), prevN[slot], base.n[slot], hasTotals) then
                self:AddLayer(guidOf[unit], member, T, before, after, plate)
                if admitted then admitted[#admitted + 1] = unit end
            end
        end
    end
    if admitted then self:PlatesGate(T, admitted, prevA, base.a, plate and self.plates or nil) end
end

-- A layer: holder > gate (a hidden StatusBar) + clip > a copy of a bar, built
-- once and pooled. Only the clip's left edge moves, with the gate's fill.
function KT:NewLayer()
    local layer = CreateFrame("Frame", nil, self.containerFrame)
    layer:Hide()
    layer:EnableMouse(false)
    -- The gate draws nothing, and the clip is not its child, so the copy keeps
    -- its alpha. Its fill is not snapped to the pixel grid, so its edge sits
    -- exactly where the values put it.
    local gate = CreateFrame("StatusBar", nil, layer)
    gate:EnableMouse(false)
    gate:SetStatusBarTexture(WHITE)
    gate:SetAlpha(0)
    local fill = gate:GetStatusBarTexture()
    fill:SetVertexColor(0, 0, 0, 0)
    if fill.SetSnapToPixelGrid then
        fill:SetSnapToPixelGrid(false)
        fill:SetTexelSnappingBias(0)
    end
    local clip = CreateFrame("Frame", nil, layer)
    clip:SetClipsChildren(true)
    clip:EnableMouse(false)
    local copy = self:CreateBar()
    copy:SetParent(clip)
    -- Opaque backing: neither the teammate's own bar nor an older layer
    -- shows through.
    copy.cover = copy:CreateTexture(nil, "BACKGROUND", nil, -8)
    copy.cover:SetAllPoints(copy)
    copy:Show()
    layer.gate, layer.fill, layer.clip, layer.copy = gate, fill, clip, copy
    layer.member = {}
    return layer
end

local function LayerLevels(layer, base)
    layer:SetFrameLevel(base)
    layer.gate:SetFrameLevel(base)
    layer.clip:SetFrameLevel(base)
    local copy = layer.copy
    copy:SetFrameLevel(base)
    copy.statusBar:SetFrameLevel(base + 1)
    copy.iconFrame:SetFrameLevel(base + 3)
end

-- Above the teammate's own bar, each newer layer above the older ones.
local function LayerBase(bar, depth)
    if depth > LAYER_DEPTH then depth = LAYER_DEPTH end
    return bar:GetFrameLevel() + LAYER_STEP + LAYER_STEP * depth
end

-- The layer laid over the teammate's bar, depth layers up their stack.
function KT:PlaceLayer(layer, bar, depth)
    local db = self.db
    layer:ClearAllPoints()
    layer:SetAllPoints(bar)
    local copy = layer.copy
    copy:ClearAllPoints()
    copy:SetAllPoints(bar)
    local gate = layer.gate
    gate:SetSize(GATE_SPAN * (db.BarWidth + GATE_PAD), db.BarHeight + GATE_TALL)
    gate:ClearAllPoints()
    gate:SetPoint("RIGHT", bar, "RIGHT", GATE_EDGE, 0)
    LayerLevels(layer, LayerBase(bar, depth))
end

-- The copy drawn as the teammate's bar cooling from the layer's start, with
-- an opaque backing in the background color and the plate's raid mark.
function KT:PaintLayer(layer, member, plate)
    local copy, fake = layer.copy, layer.member
    fake.name, fake.displayName = member.name, member.displayName
    fake.classToken, fake.interruptData = member.classToken, member.interruptData
    fake.kickStart, fake.kickDuration = layer.t, layer.endAt - layer.t
    self:UpdateBarVisuals(copy, fake)
    local r, g, b = unpack(self.db.BackgroundColor)
    copy.cover:SetColorTexture(r, g, b, 1)
    if plate then self:ApplyNameMarks(copy, plate.raidMark, plate.hasRaidMark) end
end

-- The totals handed to the gate (before as its value, after as its maximum),
-- then the clip hung from the fill again: its left edge on the fill's right
-- edge, its right edge the gate's.
local function FeedLayer(layer)
    local gate, fill, clip = layer.gate, layer.fill, layer.clip
    gate:SetMinMaxValues(0, layer.after)
    gate:SetValue(layer.before)
    clip:ClearAllPoints()
    clip:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
    clip:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT", 0, 0)
    clip:SetPoint("TOPRIGHT", gate, "TOPRIGHT", 0, 0)
    clip:SetPoint("BOTTOMRIGHT", gate, "BOTTOMRIGHT", 0, 0)
end

-- Back to the pool: hidden, the copy reset (its icon and mark may be secret),
-- the gate whole, the totals dropped.
function KT:FreeLayer(layer)
    layer:Hide()
    self:ResetBarRegions(layer.copy)
    layer.gate:SetMinMaxValues(0, 1)
    layer.gate:SetValue(1)
    layer.t, layer.endAt, layer.before, layer.after, layer.feed = nil, nil, nil, nil, nil
    self.freeLayers[#self.freeLayers + 1] = layer
end

local function freeLayer(layer)
    KT:FreeLayer(layer)
end

-- A layer over the teammate's bar from the update's time T for their longest
-- duration, fed now and once more on the next display pass.
function KT:AddLayer(guid, member, T, before, after, plate)
    local bar = guid and self.activeBars[guid]
    local longest = bar and self:ClockDuration(member, false)
    if not longest or T + longest <= GetTime() then return end
    local list = self.layersOf[guid]
    if not list then
        list = {}
        self.layersOf[guid] = list
    end
    local layer = table_remove(self.freeLayers) or self:NewLayer()
    list[#list + 1] = layer
    KT.NewLayerClock(layer, T, longest)
    layer.before, layer.after = before, after
    self:PlaceLayer(layer, bar, #list - 1)
    self:PaintLayer(layer, member, plate)
    FeedLayer(layer)
    layer.feed = true
    if self.db.ShowTimer then KT.SetTimerText(layer.copy, KT.FormatRemaining(layer.endAt - GetTime())) end
    layer:Show()
end

-- The teammate's layers that started at or before upto go (all with nil): a
-- sure kick of theirs supersedes them, or their bar went.
function KT:ReleaseLayers(guid, upto)
    local list = self.layersOf[guid]
    if not list then return end
    KT.ReleaseUpTo(list, upto, freeLayer)
    self:RelevelLayers(guid)
end

-- Levels the teammate's layers again by their place in the stack, or drops
-- the teammate's list once it is empty, so the display pass walks only
-- teammates with a live layer.
function KT:RelevelLayers(guid)
    local list, bar = self.layersOf[guid], self.activeBars[guid]
    if not list then return end
    if #list == 0 then
        self.layersOf[guid] = nil
        return
    end
    if not bar then return end
    for i = 1, #list do LayerLevels(list[i], LayerBase(bar, i - 1)) end
end

function KT:ReleaseAllLayers()
    for _, list in pairs(self.layersOf) do KT.ReleaseUpTo(list, nil, freeLayer) end
    wipe(self.layersOf)
end

-- A teammate whose demon appeared, went or was replaced loses the layers
-- gated on the old source. Pets are compared through the member's GUID, so a
-- move to another party slot neither hides a change nor fakes one.
function KT:ReleasePetSwaps(read, last)
    for i = 2, #KT.OWNERS do
        local unit = KT.OWNERS[i]
        local guid = read.guid[unit]
        if guid then
            for j = 2, #KT.OWNERS do
                local was = KT.OWNERS[j]
                if last.guid[was] == guid then
                    if read.guid[PET_SLOT[unit]] ~= last.guid[PET_SLOT[was]] then self:ReleaseLayers(guid) end
                    break
                end
            end
        end
    end
end

-- A plate paired after its update joins that update's layers for its mark.
function KT:MarkLayers(T, plate)
    if not (plate and plate.hasRaidMark) then return end
    for _, list in pairs(self.layersOf) do
        for i = 1, #list do
            local layer = list[i]
            if layer.t == T then self:ApplyNameMarks(layer.copy, plate.raidMark, true) end
        end
    end
end

-- The display pass over the layers: an ended clock releases its layer, a
-- running one writes its countdown, and a layer fed since the last pass is
-- fed once more and then forgets the totals. Returns whether any layer lives.
function KT:TickLayers(now)
    local any, showTimer = false, self.db.ShowTimer
    for guid, list in pairs(self.layersOf) do
        local removed = false
        for i = #list, 1, -1 do
            local layer = list[i]
            if KT.LayerExpired(layer, now) then
                freeLayer(layer)
                table_remove(list, i)
                removed = true
            else
                any = true
                if layer.feed then
                    FeedLayer(layer)
                    layer.feed, layer.before, layer.after = nil, nil, nil
                end
                if showTimer then KT.SetTimerText(layer.copy, KT.FormatRemaining(layer.endAt - now)) end
            end
        end
        -- Setting an existing key to nil during pairs is allowed in Lua.
        if removed then self:RelevelLayers(guid) end
    end
    return any
end
