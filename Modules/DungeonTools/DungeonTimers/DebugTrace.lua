---@class KE
local KE = select(2, ...)

local Trace = {}
Trace.__index = Trace
KE._DungeonTimerTrace = Trace

local issecretvalue = issecretvalue
local canaccesstable = canaccesstable
local GetTime = GetTime
local format = string.format
local concat = table.concat
-- Capture scope per instance map: the encounters whose provider and encounter
-- rows are kept, and the cast spells that get access rows.
local DESCRIPTORS = {
    [2859] = { key = "vale", encounters = { [3199] = true, [3200] = true, [3201] = true, [3202] = true } },
    [2521] = { key = "ruby", encounters = { [2623] = true }, spells = { 381525, 381602, 381605 } },
    [1762] = { key = "kingsrest", encounters = { [2143] = true }, spells = { 269230, 269231, 269232 } },
}
local DEFAULT_DESCRIPTOR = DESCRIPTORS[2859]
local MAX_ROWS, MAX_BYTES = 40000, 8 * 1024 * 1024
local EVENTS = {
    "ENCOUNTER_START", "ENCOUNTER_END",
    "ENCOUNTER_TIMELINE_EVENT_ADDED", "ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED",
    "ENCOUNTER_TIMELINE_EVENT_REMOVED", "ENCOUNTER_TIMELINE_EVENT_HIGHLIGHT",
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_CHANNEL_STOP", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
    "INSTANCE_ENCOUNTER_ENGAGE_UNIT", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
}

local function IsNumber(value)
    if issecretvalue(value) then return false end
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function IsTable(value)
    if issecretvalue(value) then return false end
    return type(value) == "table" and canaccesstable(value)
end

local function Scalar(value)
    if issecretvalue(value) then return "<secret>" end
    local kind = type(value)
    if kind == "string" then
        return (value:sub(1, 320):gsub("[\r\n\t|]", " "))
    end
    if kind == "number" then return IsNumber(value) and tostring(value) or "<invalid-number>" end
    if kind == "boolean" or kind == "nil" then return tostring(value) end
    return "<" .. kind .. ">"
end

local function IsUnit(unit)
    if issecretvalue(unit) or type(unit) ~= "string" then return false end
    return unit == "target" or unit == "focus" or unit:match("^boss%d+$") ~= nil
        or unit:match("^nameplate%d+$") ~= nil
end

-- A failed or missing query becomes a marker; the value itself is written
-- through Scalar, which redacts a secret.
local function Query(fn, ...)
    if type(fn) ~= "function" then return "<no-api>" end
    local ok, value = pcall(fn, ...)
    if not ok then return "<query-failed>" end
    return value
end

function Trace.New(store, rowLimit, byteLimit, descriptor)
    return setmetatable({
        store = store, active = true, rowLimit = rowLimit or MAX_ROWS, byteLimit = byteLimit or MAX_BYTES,
        owners = {}, ownerCount = 0, timeline = {}, units = {}, attempt = store.attempt or 0,
        descriptor = descriptor or DEFAULT_DESCRIPTOR,
    }, Trace)
end

function Trace:Append(event, ...)
    if not self.active then return end
    local store = self.store
    store.sequence = store.sequence + 1
    if store.full or #store.rows >= self.rowLimit or store.bytes >= self.byteLimit then
        store.full = true
        store.omitted = store.omitted + 1
        return
    end
    local parts = { format("%d|%.3f|enc=%s|pull=%d|%s", store.sequence, GetTime(),
        tostring(self.encounter), self.attempt, event) }
    for i = 1, select("#", ...), 2 do
        parts[#parts + 1] = select(i, ...) .. "=" .. Scalar(select(i + 1, ...))
    end
    local line = concat(parts, "|")
    if store.bytes + #line > self.byteLimit then
        store.full = true
        store.omitted = store.omitted + 1
        return
    end
    store.rows[#store.rows + 1] = line
    store.bytes = store.bytes + #line
    return store.sequence
end

function Trace:Decision(message)
    self:Append("KE", "receipt", self.receipt, "message", message)
end

-- A held provider call is replayed later; its decisions keep the row that
-- delivered it, and only while the same capture is still running.
function Trace:Capture()
    if not self.active then return nil end
    return { trace = self, row = self.receipt }
end

function Trace.Restore(captured, current)
    if type(captured) ~= "table" or current == nil or captured.trace ~= current or not current.active then
        return nil
    end
    return captured.row
end

function Trace:Owner(owner)
    if not IsTable(owner) then return nil, nil, "inaccessible-owner" end
    local known = self.owners[owner]
    if known then return known.id, known.encounter, known.reason end
    local member = owner.GetEncounterID
    local encounter, reason
    if issecretvalue(member) or type(member) ~= "function" then
        reason = "no-readable-encounter-method"
    else
        local ok, a, b, c, d = pcall(member, owner)
        if ok then
            for i = 1, 4 do
                local id = select(i, a, b, c, d)
                if IsNumber(id) and self.descriptor.encounters[id] then encounter = id; break end
            end
            reason = encounter and (self.descriptor.key .. "-owner") or "other-owner"
        else
            reason = "encounter-method-error"
        end
    end
    self.ownerCount = self.ownerCount + 1
    known = { id = self.ownerCount, encounter = encounter, reason = reason }
    self.owners[owner] = known
    return known.id, known.encounter, known.reason
end

function Trace:Provider(event, owner, ...)
    if not self.active then return end
    local id, encounter, reason = self:Owner(owner)
    if not (self.encounter or encounter) then return end
    local stage = self.module._ReadProviderStage(owner)
    local row
    if event == "BigWigs_Timer" or event == "BigWigs_CastTimer" then
        local key, time, maxTime, text, counter, icon, cooldownOrText, barEnabled = ...
        row = self:Append(event, "owner", id, "ownerEncounter", encounter, "ownerState", reason,
            "stage", stage, "key", key, "text", text, "time", time, "maxTime", maxTime,
            "counter", counter, "icon", icon, event == "BigWigs_Timer" and "cooldown" or "rawText",
            cooldownOrText, "barEnabled", barEnabled)
    elseif event == "BigWigs_StartBar" then
        local key, text, time, _, cooldown, maxTime, otherId, timelineId = ...
        row = self:Append(event, "owner", id, "ownerEncounter", encounter, "ownerState", reason,
            "stage", stage, "key", key, "text", text, "time", time, "cooldown", cooldown,
            "maxTime", maxTime, "otherId", otherId, "timelineId", timelineId)
    elseif event == "BigWigs_Message" then
        local key, message = ...
        row = self:Append(event, "owner", id, "ownerEncounter", encounter, "ownerState", reason,
            "stage", stage, "key", key, "message", message)
    else
        local text = ...
        row = self:Append(event, "owner", id, "ownerEncounter", encounter, "ownerState", reason,
            "stage", stage, "text", text)
    end
    return row
end

local function TimelineState(id)
    local ok, state = pcall(C_EncounterTimeline.GetEventState, id)
    return ok and Scalar(state) or "<query-failed>"
end

function Trace:Timeline(event, value)
    if event == "ENCOUNTER_TIMELINE_EVENT_ADDED" then
        if not IsTable(value) then self:Append(event, "refused", "inaccessible-event"); return end
        local id, source = value.id, value.source
        if not IsNumber(id) or not IsNumber(source) or source ~= Enum.EncounterTimelineEventSource.Encounter then
            return
        end
        local state = TimelineState(id)
        self.timeline[id] = state
        self:Append(event, "id", id, "duration", value.duration, "queue", value.maxQueueDuration,
            "state", state, "spellId", value.spellID, "spellName", value.spellName)
    elseif IsNumber(value) and self.timeline[value] then
        -- Removed fires after the API has discarded the event; retain its last observed state.
        if event == "ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED" then self.timeline[value] = TimelineState(value) end
        self:Append(event, "id", value, "lastState", self.timeline[value])
        if event == "ENCOUNTER_TIMELINE_EVENT_REMOVED" then self.timeline[value] = nil end
    end
end

-- Readability forecasts for the descriptor's cast spells on each boss token.
-- They are not evidence of who cast what.
function Trace:Access()
    local spells = self.descriptor.spells
    if not spells then return end
    local secrets = C_Secrets
    if type(secrets) ~= "table" then
        self:Append("ACCESS", "refused", "no-api")
        return
    end
    for i = 1, #spells do
        self:Append("ACCESS", "spellId", spells[i], "secrecy", Query(secrets.GetSpellCastSecrecy, spells[i]))
    end
    for i = 1, 5 do
        local unit = "boss" .. i
        local exists = Query(UnitExists, unit)
        if not issecretvalue(exists) and exists == true then
            self:Append("ACCESS", "unit", unit, "casting", Query(secrets.ShouldUnitSpellCastingBeSecret, unit))
            for j = 1, #spells do
                self:Append("ACCESS", "unit", unit, "spellId", spells[j],
                    "castSecret", Query(secrets.ShouldUnitSpellCastBeSecret, unit, spells[j]))
            end
        end
    end
end

-- Only a pair the API says it can compare is compared, and only a readable
-- answer is kept. Target-assisted evidence never certifies production identity.
function Trace:TargetIs(unit)
    if unit == "target" then return nil end
    local secrets = C_Secrets
    local canCompare = type(secrets) == "table" and secrets.CanCompareUnitTokens
    if type(canCompare) ~= "function" or type(UnitIsUnit) ~= "function" then return "compare-refused" end
    local ok, permitted = pcall(canCompare, "target", unit)
    if not ok or issecretvalue(permitted) or permitted ~= true then return "compare-refused" end
    local same
    ok, same = pcall(UnitIsUnit, "target", unit)
    if not ok or issecretvalue(same) or type(same) ~= "boolean" then return "compare-refused" end
    return same
end

function Trace:Snapshot(unit)
    local name, _, _, startMs, endMs, _, _, _, spellId, barId = UnitCastingInfo(unit)
    if issecretvalue(name) or name ~= nil then
        self:Append("CAST_SNAPSHOT", "unit", unit, "generation", self.units[unit], "name", name,
            "spellId", spellId, "barId", barId, "startMs", startMs, "endMs", endMs)
    end
    local channel, _, _, channelStart, channelEnd, _, _, channelSpell, _, _, channelBar = UnitChannelInfo(unit)
    if issecretvalue(channel) or channel ~= nil then
        self:Append("CHANNEL_SNAPSHOT", "unit", unit, "generation", self.units[unit], "name", channel,
            "spellId", channelSpell, "barId", channelBar, "startMs", channelStart, "endMs", channelEnd)
    end
end

function Trace:OnEvent(event, ...)
    if not self.active then return end
    if event == "ENCOUNTER_START" then
        local id, _, difficulty, size = ...
        if not IsNumber(id) or not self.descriptor.encounters[id] then return end
        self.encounter, self.attempt = id, self.attempt + 1
        self.store.attempt = self.attempt
        self.units = {}
        self:Append(event, "id", id, "difficulty", difficulty, "groupSize", size, "role", self.module.playerRole)
        local encounter = KE.EncounterData[id]
        for spellId in pairs(encounter.spells) do
            self:Append("FILTER", "spellId", spellId, "allowed", self.module:ShouldShowSpell(spellId))
        end
        self:Access()
    elseif event == "ENCOUNTER_END" then
        local id, _, difficulty, _, success = ...
        if not IsNumber(id) or not self.descriptor.encounters[id] then return end
        self:Append(event, "id", id, "difficulty", difficulty, "success", success)
        self.encounter = nil
    elseif event:match("^ENCOUNTER_TIMELINE_") then
        self:Timeline(event, ...)
    elseif self.encounter then
        if event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
            for i = 1, 5 do self:Snapshot("boss" .. i) end
            self:Access()
        elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" then
            local unit = event == "PLAYER_TARGET_CHANGED" and "target" or "focus"
            self.units[unit] = (self.units[unit] or 0) + 1
            self:Append(event, "unit", unit, "generation", self.units[unit])
            self:Snapshot(unit)
        else
            local unit, _, spellId, fourth, fifth = ...
            -- CHANNEL_STOP and INTERRUPTED insert a GUID before the public castBarID.
            local barId = fourth
            if event == "UNIT_SPELLCAST_CHANNEL_STOP" or event == "UNIT_SPELLCAST_INTERRUPTED" then
                barId = fifth
            end
            if issecretvalue(unit) then
                self:Append(event, "unit", unit, "spellId", spellId, "barId", barId)
                return
            end
            if not IsUnit(unit) then return end
            if event == "NAME_PLATE_UNIT_ADDED" then
                self.units[unit] = (self.units[unit] or 0) + 1
                self:Append(event, "unit", unit, "generation", self.units[unit], "targetIs", self:TargetIs(unit))
                self:Snapshot(unit)
            elseif event == "NAME_PLATE_UNIT_REMOVED" then
                self:Append(event, "unit", unit, "generation", self.units[unit])
            else
                self:Append(event, "unit", unit, "generation", self.units[unit], "spellId", spellId, "barId", barId,
                    "targetIs", self:TargetIs(unit))
                if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_DELAYED"
                    or event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
                    self:Snapshot(unit)
                end
            end
        end
    end
end

function Trace:Stop(reason)
    if not self.active then return end
    self:Append("STOP", "reason", reason)
    self.store.stopped, self.store.stopReason = GetTime(), Scalar(reason)
    self.active = false
    if self.frame then self.frame:UnregisterAllEvents(); self.frame:SetScript("OnEvent", nil) end
    self.owners, self.timeline, self.units = {}, {}, {}
    self.receipt, self.encounter = nil, nil
end

function Trace.Start(module, reset)
    if not module:IsEnabled() or not (module.db and module.db.Enabled) then
        return nil, "enable Dungeon Timers"
    end
    if InCombatLockdown() then return nil, "leave combat" end
    local _, _, _, _, _, _, _, instanceId = GetInstanceInfo()
    local descriptor = IsNumber(instanceId) and DESCRIPTORS[instanceId] or nil
    if not descriptor then return nil, "enter The Blinding Vale, Ruby Life Pools or Kings' Rest" end
    local previous = module._debugTrace
    if previous and previous.active then return previous, "already armed" end
    if not (KE.db and KE.db.global) then return nil, "wait for the profile to load" end
    local store = KE.db.global.DungeonTimerTrace
    if reset or not store then
        store = { schema = 1, descriptor = descriptor.key, revision = module._timerStateRevision, started = GetTime(),
            rows = {}, sequence = 0, bytes = 0, omitted = 0 }
    elseif type(store) ~= "table" or store.schema ~= 1 or type(store.rows) ~= "table"
        or not IsNumber(store.sequence) or not IsNumber(store.bytes) or not IsNumber(store.omitted)
        or (store.descriptor or DEFAULT_DESCRIPTOR.key) ~= descriptor.key then
        return nil, "start a new trace with StartDiagnosticTrace(true)"
    end
    KE.db.global.DungeonTimerTrace = store
    store.stopped, store.stopReason = nil, nil
    local trace = Trace.New(store, nil, nil, descriptor)
    module._debugTrace = trace
    trace.module = module
    local frame = module._debugTraceFrame or CreateFrame("Frame")
    module._debugTraceFrame, trace.frame = frame, frame
    frame:SetScript("OnEvent", function(_, event, ...) trace:OnEvent(event, ...) end)
    for _, event in ipairs(EVENTS) do frame:RegisterEvent(event) end
    trace:Append("ARM", "revision", module._timerStateRevision, "priorRows", #store.rows)
    return trace, "armed"
end
