-- ╔══════════════════════════════════════════════════════════╗
-- ║  TaintReport.lua                                         ║
-- ║  Bounded protected-action diagnostics and copy report.   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local CreateFrame = CreateFrame
local canaccessvalue = canaccessvalue
local canaccesstable = canaccesstable
local debugstack = debugstack
local time = time
local date = date
local GetBuildInfo = _G.GetBuildInfo
local C_AddOns = C_AddOns
local UIParent = UIParent
local UISpecialFrames = _G.UISpecialFrames
local GameFontNormal = _G.GameFontNormal

local pcall = pcall
local type = type
local next = next
local ipairs = ipairs
local tostring = tostring
local string_sub = string.sub
local string_len = string.len
local string_gsub = string.gsub
local string_match = string.match
local string_find = string.find
local string_lower = string.lower
local string_format = string.format
local table_insert = table.insert
local table_sort = table.sort
local table_concat = table.concat
local math_min = math.min
local math_rad = math.rad
local math_huge = math.huge

local SCHEMA_VERSION = 1
local MAX_GROUPS = 25
local MAX_STACK_WALKS = 5
local MAX_SOURCE_SITES = 3
local MAX_REFUSED_KEYS = 50
local MAX_TRACKED_KEYS = 75
local STACK_HEAD_LINES = 16
local STACK_TAIL_LINES = 16
local MAX_KE_LINES = 6
local MAX_RAW_ACTION_LENGTH = 512
local MAX_ACTION_LENGTH = 160
local MAX_RAW_STACK_LENGTH = 16384
local MAX_RAW_STACK_LINE = 1024
local MAX_SOURCE_LENGTH = 300
local MAX_PERSISTED_GROUPS = 10
local MAX_AGE_SECONDS = 1209600
local MAX_CLOCK_SKEW_SECONDS = 300
local MAX_REPORT_ADDON_INDICES = 1024
local MAX_REPORT_ADDONS = 300
local MAX_RAW_ENV_STRING_LENGTH = 1024
local MAX_ENV_STRING_LENGTH = 300
local MAX_REPORT_CHUNK = 1024
local MAX_MANDATORY_PREFIX_LENGTH = 8192
local MAX_REPORT_LENGTH = 90000
local MAX_COUNTER = 2147483647

local ADDON_LABEL = "KitnEssentials"
local UNKNOWN_ACTION = "<function unavailable>"
local TRUNCATION_MARKER = " [truncated]"
local REPORT_TRUNCATION_MARKER = "\n[report truncated]\n"
local REPORT_FRAME_NAME = "KE_TaintReportFrame"
local CLOSE_TEXTURE = "Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\KitnCustomCrossv3.png"

local VALID_EVENTS = {
    ADDON_ACTION_BLOCKED = true,
    ADDON_ACTION_FORBIDDEN = true,
}

local eventFrame = CreateFrame("Frame")
local TaintReport = {}

local currentGroups = {}
local restoredGroups = {}
local currentByEvent = {}
local restoredByEvent = {}
local refusedByEvent = {}
local totalGroups = 0
local refusedKeys = 0
local refusedKeysAreLowerBound = false
local refusedOccurrences = 0
local inaccessibleAttribution = 0
local unavailableActionPayloads = 0
local pendingNotifications = 0
local carriedOmitted = 0
local carriedSupersededRestored = 0
local attachedGlobal
local initialized = false
local dirty = false
local canonicalText
local dialog

local function DirectCanAccess(value)
    return canaccessvalue(value)
end

local function SafeCanAccess(value)
    local ok, result = pcall(DirectCanAccess, value)
    return ok and result == true
end

local function DirectCanAccessTable(value)
    return canaccesstable(value)
end

local function SafeCanAccessTable(value)
    local ok, result = pcall(DirectCanAccessTable, value)
    return ok and result == true
end

local function AccessibleTable(value)
    if not SafeCanAccess(value) then return false end
    if type(value) ~= "table" then return false end
    return SafeCanAccessTable(value)
end

local function AdvanceCounter(value, amount)
    amount = amount or 1
    if value >= MAX_COUNTER or amount <= 0 then
        return value, false
    end
    if amount >= MAX_COUNTER - value then
        return MAX_COUNTER, true
    end
    return value + amount, true
end

local function LowerBoundText(value, forced)
    if forced or value >= MAX_COUNTER then
        return "at least " .. value
    end
    return tostring(value)
end

local function GuardedPrefix(value, maximum)
    if not SafeCanAccess(value) or type(value) ~= "string" then return nil end
    local truncated = string_len(value) > maximum
    local prefix = string_sub(value, 1, maximum)
    if not SafeCanAccess(prefix) then return nil end
    return prefix, truncated
end

local function NormalizeRetained(value, maximum, forceMarker)
    if not SafeCanAccess(value) or type(value) ~= "string" then return nil end
    local normalized = string_gsub(value, "[%z\1-\31\127]", " ")
    if not SafeCanAccess(normalized) then return nil end
    normalized = string_match(normalized, "^%s*(.-)%s*$")
    if not SafeCanAccess(normalized) then return nil end

    local truncated = forceMarker or string_len(normalized) > maximum
    if truncated then
        local payload = math_min(string_len(normalized), maximum - string_len(TRUNCATION_MARKER))
        normalized = string_sub(normalized, 1, payload) .. TRUNCATION_MARKER
        if not SafeCanAccess(normalized) then return nil end
    end
    if string_len(normalized) > maximum then return nil end
    return normalized, truncated
end

local function BoundedString(value, rawMaximum, retainedMaximum)
    local prefix, rawTruncated = GuardedPrefix(value, rawMaximum)
    if not prefix then return nil end
    return NormalizeRetained(prefix, retainedMaximum, rawTruncated)
end

local function CanonicalString(value, maximum)
    if not SafeCanAccess(value) or type(value) ~= "string" then return nil end
    if string_len(value) == 0 or string_len(value) > maximum then return nil end
    if string_find(value, "[%z\1-\31\127]") then return nil end
    if string_match(value, "^%s") or string_match(value, "%s$") then return nil end
    return value
end

local function ReadInteger(value, minimum, maximum)
    if not SafeCanAccess(value) or type(value) ~= "number" then return nil end
    if value ~= value or value == math_huge or value == -math_huge then return nil end
    if value % 1 ~= 0 or value < minimum or value > maximum then return nil end
    return value
end

local function ReadTimestamp(value)
    if not SafeCanAccess(value) or type(value) ~= "number" then return nil end
    if value ~= value or value == math_huge or value == -math_huge then return nil end
    if value % 1 ~= 0 or value < 0 then return nil end
    return value
end

local function ValidateDenseArray(value, maximum)
    if not AccessibleTable(value) then return nil end
    local result = {}
    local count = 0
    local key

    for _ = 1, maximum + 1 do
        local nextKey, nextValue = next(value, key)
        if nextKey == nil then
            key = nil
            break
        end
        if not SafeCanAccess(nextKey) or type(nextKey) ~= "number"
            or nextKey % 1 ~= 0 or nextKey < 1 or nextKey > maximum then
            return nil
        end
        if not SafeCanAccess(nextValue) then return nil end
        count = count + 1
        result[nextKey] = nextValue
        key = nextKey
    end

    if key ~= nil then return nil end
    for index = 1, count do
        if result[index] == nil then return nil end
    end
    return result, count
end

local function SafeFinishedString(value)
    return SafeCanAccess(value) and type(value) == "string"
end

local function NormalizeStackLine(line)
    if not SafeCanAccess(line) or type(line) ~= "string" then return nil end
    local normalized = string_gsub(line, "\\", "/")
    if not SafeCanAccess(normalized) then return nil end
    local lowered = string_lower(normalized)
    if not SafeCanAccess(lowered) then return nil end
    return lowered
end

local function IsKESourceLine(line)
    local normalized = NormalizeStackLine(line)
    if not normalized then return nil end
    if not string_find(normalized, "interface/addons/kitnessentials/", 1, true) then
        return false
    end
    if not string_find(normalized, ".lua", 1, true) then return false end
    if string_find(normalized, "modules/diagnostics/taintreport.lua", 1, true) then
        return false
    end
    return true
end

local function RetainSourceLine(line)
    local retained = NormalizeRetained(line, MAX_SOURCE_LENGTH, false)
    return retained
end

local function ParseStack(stack)
    local raw, rawTruncated = GuardedPrefix(stack, MAX_RAW_STACK_LENGTH)
    if not raw then return nil end

    local lines = {}
    local lineTruncated = false
    for rawLine in string.gmatch(raw, "[^\r\n]+") do
        if not SafeCanAccess(rawLine) then return nil end
        local line, wasTruncated = GuardedPrefix(rawLine, MAX_RAW_STACK_LINE)
        if not line then return nil end
        if wasTruncated then lineTruncated = true end
        local isKE = IsKESourceLine(line)
        if isKE == nil then return nil end
        if isKE then
            local retained = RetainSourceLine(line)
            if not retained then return nil end
            lines[#lines + 1] = retained
        end
    end

    local site = lines[1]
    local keLines = {}
    local seen = {}
    local omitted = 0
    for _, line in ipairs(lines) do
        if not seen[line] then
            seen[line] = true
            if #keLines < MAX_KE_LINES then
                keLines[#keLines + 1] = line
            else
                omitted = AdvanceCounter(omitted)
            end
        end
    end
    return {
        site = site,
        keLines = keLines,
        keLinesOmitted = omitted,
        inputTruncated = rawTruncated or lineTruncated,
    }
end

local function ReadableStack()
    local ok, stack = pcall(debugstack, 3, STACK_HEAD_LINES, STACK_TAIL_LINES)
    if not ok or not SafeCanAccess(stack) or type(stack) ~= "string" then
        return nil
    end
    return ParseStack(stack)
end

local function MapGet(map, event, action)
    local eventMap = map[event]
    return eventMap and eventMap[action]
end

local function MapSet(map, event, action, value)
    local eventMap = map[event]
    if not eventMap then
        eventMap = {}
        map[event] = eventMap
    end
    eventMap[action] = value
end

local function MapClear(map, event, action)
    local eventMap = map[event]
    if not eventMap then return end
    eventMap[action] = nil
end

local function NewGroup(event, action, scope, timestamp)
    return {
        event = event,
        action = action,
        firstSeen = timestamp,
        lastSeen = timestamp,
        count = 0,
        walks = 0,
        notWalked = 0,
        stackUnavailable = 0,
        stackInputTruncated = 0,
        sources = {},
        sourceUnavailable = 0,
        sourceSamplesOmitted = 0,
        scope = scope,
    }
end

local function AddGroup(group)
    local list = group.scope == "current" and currentGroups or restoredGroups
    local map = group.scope == "current" and currentByEvent or restoredByEvent
    list[#list + 1] = group
    MapSet(map, group.event, group.action, group)
    totalGroups = totalGroups + 1
end

local function RemoveRestoredGroup(group)
    for index, candidate in ipairs(restoredGroups) do
        if candidate == group then
            table.remove(restoredGroups, index)
            break
        end
    end
    MapClear(restoredByEvent, group.event, group.action)
    totalGroups = totalGroups - 1
end

local function IdentityMatches(group, event, action)
    return group.event == event and group.action == action
end

local function OldestRestoredGroup()
    local oldest
    for _, group in ipairs(restoredGroups) do
        if not oldest or group.lastSeen < oldest.lastSeen
            or (group.lastSeen == oldest.lastSeen and group.event < oldest.event)
            or (group.lastSeen == oldest.lastSeen and group.event == oldest.event
                and group.action < oldest.action) then
            oldest = group
        end
    end
    return oldest
end

local function CarryRemovedRestored(group, event, action)
    if IdentityMatches(group, event, action) then
        carriedSupersededRestored = AdvanceCounter(carriedSupersededRestored)
    else
        carriedOmitted = AdvanceCounter(carriedOmitted)
    end
end

local function RecordRefusal(event, action)
    refusedOccurrences = AdvanceCounter(refusedOccurrences)
    if MapGet(refusedByEvent, event, action) then return end
    if refusedKeys < MAX_REFUSED_KEYS and totalGroups + refusedKeys < MAX_TRACKED_KEYS then
        MapSet(refusedByEvent, event, action, true)
        refusedKeys = refusedKeys + 1
    else
        refusedKeysAreLowerBound = true
    end
end

local function MergeKELines(source, sample)
    local seen = {}
    for _, line in ipairs(source.keLines) do seen[line] = true end
    for _, line in ipairs(sample.keLines) do
        if not seen[line] then
            seen[line] = true
            if #source.keLines < MAX_KE_LINES then
                source.keLines[#source.keLines + 1] = line
            else
                source.keLinesOmitted = AdvanceCounter(source.keLinesOmitted)
            end
        end
    end
    source.keLinesOmitted = AdvanceCounter(source.keLinesOmitted, sample.keLinesOmitted)
end

local function RecordStackSample(group, sample)
    if not sample then
        group.stackUnavailable = AdvanceCounter(group.stackUnavailable)
        return
    end
    if sample.inputTruncated then
        group.stackInputTruncated = AdvanceCounter(group.stackInputTruncated)
    end
    if not sample.site then
        group.sourceUnavailable = AdvanceCounter(group.sourceUnavailable)
        return
    end

    for _, source in ipairs(group.sources) do
        if source.site == sample.site then
            source.observedSamples = AdvanceCounter(source.observedSamples)
            MergeKELines(source, sample)
            return
        end
    end

    if #group.sources >= MAX_SOURCE_SITES then
        group.sourceSamplesOmitted = AdvanceCounter(group.sourceSamplesOmitted)
        return
    end

    local lines = {}
    for _, line in ipairs(sample.keLines) do lines[#lines + 1] = line end
    group.sources[#group.sources + 1] = {
        site = sample.site,
        keLines = lines,
        keLinesOmitted = sample.keLinesOmitted,
        observedSamples = 1,
    }
end

local function NotifyNewGroup(action)
    if not initialized then
        pendingNotifications = AdvanceCounter(pendingNotifications)
        return
    end
    if not KE.Print then return end
    local message = "A protected action attributed to KitnEssentials was captured: "
        .. action .. ". Use /kes taint."
    if SafeFinishedString(message) then KE:Print(message) end
end

local function AdvanceGroup(group, sampled, sample)
    local newCount, advanced = AdvanceCounter(group.count)
    if not advanced then return end
    group.count = newCount
    group.lastSeen = time()
    dirty = true

    if sampled then
        group.walks = group.walks + 1
        RecordStackSample(group, sample)
    else
        group.notWalked = group.count - group.walks
    end
end

local function OnBlocked(event, attribution, actionValue)
    if not SafeCanAccess(attribution) then
        inaccessibleAttribution = AdvanceCounter(inaccessibleAttribution)
        return
    end
    if type(attribution) ~= "string" or string_len(attribution) ~= string_len(ADDON_LABEL) then
        return
    end
    if attribution ~= ADDON_LABEL then return end

    local action = BoundedString(actionValue, MAX_RAW_ACTION_LENGTH, MAX_ACTION_LENGTH)
    if not action or action == "" then
        unavailableActionPayloads = AdvanceCounter(unavailableActionPayloads)
        action = UNKNOWN_ACTION
    end

    local group = MapGet(currentByEvent, event, action)
    if group then
        local sampled = group.count < MAX_COUNTER and group.walks < MAX_STACK_WALKS
        local sample
        if sampled then sample = ReadableStack() end
        AdvanceGroup(group, sampled, sample)
        return
    end

    if totalGroups >= MAX_GROUPS then
        local evicted = OldestRestoredGroup()
        if evicted then
            RemoveRestoredGroup(evicted)
            CarryRemovedRestored(evicted, event, action)
            dirty = true
        else
            RecordRefusal(event, action)
            return
        end
    end

    group = NewGroup(event, action, "current", time())
    AddGroup(group)
    local sample = ReadableStack()
    AdvanceGroup(group, true, sample)
    NotifyNewGroup(action)
end

local function CopySource(source)
    local lines = {}
    for _, line in ipairs(source.keLines) do lines[#lines + 1] = line end
    return {
        site = source.site,
        keLines = lines,
        keLinesOmitted = source.keLinesOmitted,
        observedSamples = source.observedSamples,
    }
end

local function CopyStoredGroup(group)
    local sources = {}
    for _, source in ipairs(group.sources) do sources[#sources + 1] = CopySource(source) end
    return {
        event = group.event,
        action = group.action,
        firstSeen = group.firstSeen,
        lastSeen = group.lastSeen,
        count = group.count,
        walks = group.walks,
        notWalked = group.notWalked,
        stackUnavailable = group.stackUnavailable,
        stackInputTruncated = group.stackInputTruncated,
        sourceUnavailable = group.sourceUnavailable,
        sourceSamplesOmitted = group.sourceSamplesOmitted,
        sources = sources,
    }
end

local function SanitizeSource(raw)
    if not AccessibleTable(raw) then return nil end
    local site = CanonicalString(raw.site, MAX_SOURCE_LENGTH)
    local lineArray = ValidateDenseArray(raw.keLines, MAX_KE_LINES)
    local omitted = ReadInteger(raw.keLinesOmitted, 0, MAX_COUNTER)
    local observed = ReadInteger(raw.observedSamples, 1, MAX_COUNTER)
    if not site or not lineArray or omitted == nil or not observed then return nil end

    local lines = {}
    local seen = {}
    for _, rawLine in ipairs(lineArray) do
        local line = CanonicalString(rawLine, MAX_SOURCE_LENGTH)
        if not line or seen[line] then return nil end
        seen[line] = true
        lines[#lines + 1] = line
    end
    return {
        site = site,
        keLines = lines,
        keLinesOmitted = omitted,
        observedSamples = observed,
    }
end

local function SanitizeGroup(raw, savedAt, now)
    if not AccessibleTable(raw) then return nil, "invalid" end
    local event = CanonicalString(raw.event, 64)
    local action = CanonicalString(raw.action, MAX_ACTION_LENGTH)
    local firstSeen = ReadTimestamp(raw.firstSeen)
    local lastSeen = ReadTimestamp(raw.lastSeen)
    local count = ReadInteger(raw.count, 1, MAX_COUNTER)
    local walks = ReadInteger(raw.walks, 0, MAX_COUNTER)
    local notWalked = ReadInteger(raw.notWalked, 0, MAX_COUNTER)
    local stackUnavailable = ReadInteger(raw.stackUnavailable, 0, MAX_COUNTER)
    local stackInputTruncated = ReadInteger(raw.stackInputTruncated, 0, MAX_COUNTER)
    local sourceUnavailable = ReadInteger(raw.sourceUnavailable, 0, MAX_COUNTER)
    local sourceSamplesOmitted = ReadInteger(raw.sourceSamplesOmitted, 0, MAX_COUNTER)
    local sourceArray = ValidateDenseArray(raw.sources, MAX_SOURCE_SITES)

    if not event or not VALID_EVENTS[event] or not action or not firstSeen or not lastSeen
        or not count or walks == nil or notWalked == nil or stackUnavailable == nil
        or stackInputTruncated == nil or sourceUnavailable == nil
        or sourceSamplesOmitted == nil or not sourceArray then
        return nil, "invalid"
    end
    if firstSeen > lastSeen or lastSeen > now + MAX_CLOCK_SKEW_SECONDS
        or firstSeen > now + MAX_CLOCK_SKEW_SECONDS
        or lastSeen > savedAt + MAX_CLOCK_SKEW_SECONDS then
        return nil, "invalid"
    end
    if now - lastSeen > MAX_AGE_SECONDS then return nil, "expired" end
    if walks > math_min(count, MAX_STACK_WALKS) or notWalked ~= count - walks
        or stackInputTruncated > walks then
        return nil, "invalid"
    end

    local sources = {}
    local seenSites = {}
    local observedTotal = 0
    for _, rawSource in ipairs(sourceArray) do
        local source = SanitizeSource(rawSource)
        if not source or seenSites[source.site] then return nil, "invalid" end
        seenSites[source.site] = true
        sources[#sources + 1] = source
        observedTotal = observedTotal + source.observedSamples
    end
    if stackUnavailable + sourceUnavailable + sourceSamplesOmitted + observedTotal ~= walks then
        return nil, "invalid"
    end

    return {
        event = event,
        action = action,
        firstSeen = firstSeen,
        lastSeen = lastSeen,
        count = count,
        walks = walks,
        notWalked = notWalked,
        stackUnavailable = stackUnavailable,
        stackInputTruncated = stackInputTruncated,
        sourceUnavailable = sourceUnavailable,
        sourceSamplesOmitted = sourceSamplesOmitted,
        sources = sources,
        scope = "restored",
    }
end

local function SanitizeStore(raw)
    if not AccessibleTable(raw) then return nil end
    local schema = ReadInteger(raw.schema, 0, MAX_COUNTER)
    local savedAt = ReadTimestamp(raw.savedAt)
    local omitted = ReadInteger(raw.omitted, 0, MAX_COUNTER)
    local superseded = ReadInteger(raw.supersededRestored, 0, MAX_COUNTER)
    if schema ~= SCHEMA_VERSION or not savedAt or omitted == nil or superseded == nil then
        return nil
    end

    local now = time()
    if savedAt > now + MAX_CLOCK_SKEW_SECONDS then return nil end
    local groupArray = ValidateDenseArray(raw.groups, MAX_PERSISTED_GROUPS)
    if not groupArray then return nil end

    local groups = {}
    local seen = {}
    local dropped = 0
    for _, rawGroup in ipairs(groupArray) do
        local group = SanitizeGroup(rawGroup, savedAt, now)
        if group then
            local eventSeen = seen[group.event]
            if not eventSeen then eventSeen = {}; seen[group.event] = eventSeen end
            if eventSeen[group.action] then
                dropped = AdvanceCounter(dropped)
            else
                eventSeen[group.action] = true
                groups[#groups + 1] = group
            end
        else
            dropped = AdvanceCounter(dropped)
        end
    end
    if #groups == 0 then return nil end
    omitted = AdvanceCounter(omitted, dropped)
    return {
        savedAt = savedAt,
        groups = groups,
        omitted = omitted,
        supersededRestored = superseded,
    }
end

local function StableGroupSort(a, b)
    if a.lastSeen ~= b.lastSeen then return a.lastSeen > b.lastSeen end
    if a.event ~= b.event then return a.event < b.event end
    return a.action < b.action
end

local function FreshStore(savedAt, groups, omitted, superseded)
    local copies = {}
    for _, group in ipairs(groups) do copies[#copies + 1] = CopyStoredGroup(group) end
    return {
        schema = SCHEMA_VERSION,
        savedAt = savedAt,
        groups = copies,
        omitted = omitted,
        supersededRestored = superseded,
    }
end

local function RestoreStore(raw)
    local store = SanitizeStore(raw)
    if not store then return nil end

    carriedOmitted = store.omitted
    carriedSupersededRestored = store.supersededRestored
    table_sort(store.groups, StableGroupSort)
    local admitted = {}
    for _, group in ipairs(store.groups) do
        if totalGroups < MAX_GROUPS then
            AddGroup(group)
            admitted[#admitted + 1] = group
        elseif MapGet(currentByEvent, group.event, group.action) then
            carriedSupersededRestored = AdvanceCounter(carriedSupersededRestored)
        else
            carriedOmitted = AdvanceCounter(carriedOmitted)
        end
    end
    if #admitted == 0 then return nil end
    return FreshStore(store.savedAt, admitted, carriedOmitted, carriedSupersededRestored)
end

local function PersistenceCandidates()
    local current = {}
    local restored = {}
    for _, group in ipairs(currentGroups) do current[#current + 1] = group end
    for _, group in ipairs(restoredGroups) do restored[#restored + 1] = group end
    table_sort(current, StableGroupSort)
    table_sort(restored, StableGroupSort)
    local candidates = {}
    for _, group in ipairs(current) do candidates[#candidates + 1] = group end
    for _, group in ipairs(restored) do candidates[#candidates + 1] = group end
    return candidates
end

local function Persist()
    if not attachedGlobal or not dirty then return end
    local seen = {}
    local selected = {}
    local omitted = carriedOmitted
    local superseded = carriedSupersededRestored

    for _, group in ipairs(PersistenceCandidates()) do
        local eventSeen = seen[group.event]
        if not eventSeen then eventSeen = {}; seen[group.event] = eventSeen end
        if eventSeen[group.action] then
            if group.scope == "restored" then
                superseded = AdvanceCounter(superseded)
            end
        else
            eventSeen[group.action] = true
            if #selected < MAX_PERSISTED_GROUPS then
                selected[#selected + 1] = group
            else
                omitted = AdvanceCounter(omitted)
            end
        end
    end

    attachedGlobal.TaintLog = FreshStore(time(), selected, omitted, superseded)
    dirty = false
end

local function ResetMemory()
    currentGroups = {}
    restoredGroups = {}
    currentByEvent = {}
    restoredByEvent = {}
    refusedByEvent = {}
    totalGroups = 0
    refusedKeys = 0
    refusedKeysAreLowerBound = false
    refusedOccurrences = 0
    inaccessibleAttribution = 0
    unavailableActionPayloads = 0
    pendingNotifications = 0
    carriedOmitted = 0
    carriedSupersededRestored = 0
    dirty = false
    canonicalText = nil
end

local function Clear()
    ResetMemory()
    if attachedGlobal then attachedGlobal.TaintLog = nil end
    if dialog then
        dialog.restoring = true
        dialog.editBox:SetText("")
        dialog.restoring = false
        dialog.scrollbar:SetValue(0)
        dialog.frame:Hide()
    end
end

local function SafeEnvironmentString(value)
    local result = BoundedString(value, MAX_RAW_ENV_STRING_LENGTH, MAX_ENV_STRING_LENGTH)
    if not result or result == "" then return "unavailable" end
    return result
end

local function SafeAPICall(func, ...)
    if type(func) ~= "function" then return false end
    return pcall(func, ...)
end

local function LoadedState(identifier)
    local ok, _, loaded = SafeAPICall(C_AddOns and C_AddOns.IsAddOnLoaded, identifier)
    if not ok or not SafeCanAccess(loaded) or type(loaded) ~= "boolean" then
        return nil
    end
    return loaded
end

local function EnvironmentSnapshot()
    local environment = {
        rows = {},
        addonIndicesUnscanned = 0,
        loadedAddonsOmitted = 0,
        loadStatesUnavailable = 0,
        indexScanUnavailable = false,
    }

    local okVersion, version = SafeAPICall(C_AddOns and C_AddOns.GetAddOnMetadata,
        ADDON_LABEL, "Version")
    environment.addonVersion = okVersion and SafeEnvironmentString(version) or "unavailable"

    local okBuild, _, build = SafeAPICall(GetBuildInfo)
    environment.clientBuild = okBuild and SafeEnvironmentString(build) or "unavailable"
    local okDate, reportDate = SafeAPICall(date, "%Y-%m-%d %H:%M:%S", time())
    environment.reportDate = okDate and SafeEnvironmentString(reportDate) or "unavailable"

    local okCount, count = SafeAPICall(C_AddOns and C_AddOns.GetNumAddOns)
    if not okCount or not SafeCanAccess(count) or type(count) ~= "number"
        or count ~= count or count == math_huge or count == -math_huge
        or count % 1 ~= 0 or count < 0 or count > MAX_COUNTER then
        environment.indexScanUnavailable = true
    else
        local scanCount = math_min(count, MAX_REPORT_ADDON_INDICES)
        environment.addonIndicesUnscanned = count - scanCount
        for index = 1, scanCount do
            local infoOK, name, title = SafeAPICall(C_AddOns and C_AddOns.GetAddOnInfo, index)
            local loaded = LoadedState(index)
            if loaded == nil then
                environment.loadStatesUnavailable = AdvanceCounter(environment.loadStatesUnavailable)
            elseif loaded then
                local safeName = infoOK and SafeEnvironmentString(name) or "unavailable"
                local safeTitle = infoOK and SafeEnvironmentString(title) or "unavailable"
                local metadataOK, addonVersion = SafeAPICall(
                    C_AddOns and C_AddOns.GetAddOnMetadata, index, "Version")
                addonVersion = metadataOK and SafeEnvironmentString(addonVersion) or "unavailable"
                local sortName = string_lower(safeName)
                if not SafeCanAccess(sortName) then sortName = "unavailable" end
                if #environment.rows < MAX_REPORT_ADDONS then
                    environment.rows[#environment.rows + 1] = {
                        name = safeName,
                        title = safeTitle,
                        version = addonVersion,
                        sortName = sortName,
                    }
                else
                    environment.loadedAddonsOmitted = AdvanceCounter(environment.loadedAddonsOmitted)
                end
            end
        end
    end

    environment.bugSack = LoadedState("BugSack")
    environment.bugGrabber = LoadedState("BugGrabber")
    table_sort(environment.rows, function(a, b)
        if a.sortName ~= b.sortName then return a.sortName < b.sortName end
        return a.name < b.name
    end)
    return environment
end

local function AggregateLosses()
    local totals = {
        notWalked = 0,
        stackUnavailable = 0,
        stackInputTruncated = 0,
        sourceUnavailable = 0,
        sourceSamplesOmitted = 0,
        keLinesOmitted = 0,
    }
    local lower = {}

    local function add(key, value, forced)
        local advanced
        totals[key], advanced = AdvanceCounter(totals[key], value)
        if forced or value >= MAX_COUNTER or not advanced and value > 0 then lower[key] = true end
    end

    local function scan(groups)
        for _, group in ipairs(groups) do
            add("notWalked", group.notWalked, group.count >= MAX_COUNTER)
            add("stackUnavailable", group.stackUnavailable)
            add("stackInputTruncated", group.stackInputTruncated)
            add("sourceUnavailable", group.sourceUnavailable)
            add("sourceSamplesOmitted", group.sourceSamplesOmitted)
            for _, source in ipairs(group.sources) do
                add("keLinesOmitted", source.keLinesOmitted)
            end
        end
    end
    scan(currentGroups)
    scan(restoredGroups)
    return totals, lower
end

local function NewReportWriter()
    return {
        parts = {},
        length = 0,
        contentLimit = MAX_REPORT_LENGTH - string_len(REPORT_TRUNCATION_MARKER),
        truncated = false,
    }
end

local function WriteMandatory(writer, chunk)
    if not SafeFinishedString(chunk) or string_len(chunk) > MAX_REPORT_CHUNK then return false end
    if writer.length + string_len(chunk) > MAX_MANDATORY_PREFIX_LENGTH then return false end
    writer.parts[#writer.parts + 1] = chunk
    writer.length = writer.length + string_len(chunk)
    return true
end

local function WriteDetail(writer, chunk)
    if writer.truncated or not SafeFinishedString(chunk) then return false end
    if string_len(chunk) > MAX_REPORT_CHUNK then
        writer.truncated = true
        return false
    end
    local remaining = writer.contentLimit - writer.length
    if string_len(chunk) <= remaining then
        writer.parts[#writer.parts + 1] = chunk
        writer.length = writer.length + string_len(chunk)
        return true
    end
    if remaining > 0 then
        local partial = string_sub(chunk, 1, remaining)
        if SafeFinishedString(partial) then
            writer.parts[#writer.parts + 1] = partial
            writer.length = writer.length + string_len(partial)
        end
    end
    writer.truncated = true
    return false
end

local function FinalizeWriter(writer)
    local report = table_concat(writer.parts)
    if writer.truncated then report = report .. REPORT_TRUNCATION_MARKER end
    if not SafeFinishedString(report) then return nil end
    return report
end

local function DisclosureLine(label, value, forced)
    if value <= 0 then return nil end
    return string_format("%s: %s\n", label, LowerBoundText(value, forced))
end

local function WriteGroupDetails(writer, groups)
    for _, group in ipairs(groups) do
        WriteDetail(writer, string_format("\n[%s] %s\n", group.scope, group.event))
        WriteDetail(writer, "Action: " .. group.action .. "\n")
        WriteDetail(writer, "Occurrences: " .. LowerBoundText(group.count) .. "\n")
        WriteDetail(writer, string_format("First seen: %d | Last seen: %d | Stack samples: %d\n",
            group.firstSeen, group.lastSeen, group.walks))
        if group.notWalked > 0 then
            WriteDetail(writer, "Unsampled occurrences: "
                .. LowerBoundText(group.notWalked, group.count >= MAX_COUNTER) .. "\n")
        end
        if group.stackUnavailable > 0 then
            WriteDetail(writer, "Stack unavailable samples: "
                .. LowerBoundText(group.stackUnavailable) .. "\n")
        end
        if group.stackInputTruncated > 0 then
            WriteDetail(writer, "Stack input truncated samples: "
                .. LowerBoundText(group.stackInputTruncated) .. "\n")
        end
        if group.sourceUnavailable > 0 then
            WriteDetail(writer, "Source frame unavailable samples: "
                .. LowerBoundText(group.sourceUnavailable) .. "\n")
        end
        if group.sourceSamplesOmitted > 0 then
            WriteDetail(writer, "Source samples omitted: "
                .. LowerBoundText(group.sourceSamplesOmitted) .. "\n")
        end
        if #group.sources == 0 and group.walks > 0 then
            WriteDetail(writer, "Sampled source: source frame unavailable\n")
        end
        for sourceIndex, source in ipairs(group.sources) do
            WriteDetail(writer, string_format("Sampled source %d (%s observations): %s\n",
                sourceIndex, LowerBoundText(source.observedSamples), source.site))
            for _, line in ipairs(source.keLines) do
                WriteDetail(writer, "  KE line: " .. line .. "\n")
            end
            if source.keLinesOmitted > 0 then
                WriteDetail(writer, "  KE lines omitted: "
                    .. LowerBoundText(source.keLinesOmitted) .. "\n")
            end
        end
    end
end

local function ToolStateText(value)
    if value == nil then return "unavailable" end
    return value and "loaded" or "not loaded"
end

local function BuildReport()
    local environment = EnvironmentSnapshot()
    local totals, lower = AggregateLosses()
    local writer = NewReportWriter()

    local function mandatory(chunk)
        return WriteMandatory(writer, chunk)
    end

    if not mandatory("KitnEssentials Taint Report\n") then return nil end
    if not mandatory("Addon version: " .. environment.addonVersion .. "\n") then return nil end
    if not mandatory("Client build: " .. environment.clientBuild .. "\n") then return nil end
    if not mandatory("Report time: " .. environment.reportDate .. "\n") then return nil end
    if not mandatory("Warning: Blizzard attribution is not proof that KitnEssentials caused the taint.\n") then
        return nil
    end
    if environment.indexScanUnavailable then
        if not mandatory("Addon index scan: unavailable\n") then return nil end
    end

    local disclosures = {
        { "Inaccessible attribution events", inaccessibleAttribution },
        { "Unavailable action payloads", unavailableActionPayloads },
        { "Refused action groups", refusedKeys, refusedKeysAreLowerBound },
        { "Refused occurrences", refusedOccurrences },
        { "Persisted groups omitted", carriedOmitted },
        { "Restored groups superseded", carriedSupersededRestored },
        { "Addon indices unscanned", environment.addonIndicesUnscanned },
        { "Loaded addons omitted", environment.loadedAddonsOmitted },
        { "Addon load states unavailable", environment.loadStatesUnavailable },
        { "Unsampled occurrences", totals.notWalked, lower.notWalked },
        { "Stack unavailable samples", totals.stackUnavailable, lower.stackUnavailable },
        { "Stack input truncated samples", totals.stackInputTruncated, lower.stackInputTruncated },
        { "Source unavailable samples", totals.sourceUnavailable, lower.sourceUnavailable },
        { "Source samples omitted", totals.sourceSamplesOmitted, lower.sourceSamplesOmitted },
        { "KE lines omitted", totals.keLinesOmitted, lower.keLinesOmitted },
    }
    for _, disclosure in ipairs(disclosures) do
        local line = DisclosureLine(disclosure[1], disclosure[2], disclosure[3])
        if line and not mandatory(line) then return nil end
    end
    if not mandatory("Copy the full report and include the exact reproduction steps.\n") then return nil end
    if not mandatory("Sampled source frames are evidence samples, not proof of causation.\n") then
        return nil
    end

    if totalGroups == 0 then
        WriteDetail(writer, "\nNo KE-attributed protected actions were captured.\n")
    else
        WriteGroupDetails(writer, currentGroups)
        WriteGroupDetails(writer, restoredGroups)
    end

    WriteDetail(writer, "\nReport-time addon state\n")
    WriteDetail(writer, "BugSack: " .. ToolStateText(environment.bugSack) .. "\n")
    WriteDetail(writer, "BugGrabber: " .. ToolStateText(environment.bugGrabber) .. "\n")
    for _, row in ipairs(environment.rows) do
        WriteDetail(writer, string_format("Loaded addon: %s | %s | %s\n",
            row.name, row.title, row.version))
    end
    return FinalizeWriter(writer)
end

local function ThemeColor(key, fallback)
    if KE.GetThemeColor then
        local color = KE:GetThemeColor(key)
        if type(color) == "table" then return color end
    end
    return fallback
end

local function BuildDialog()
    if dialog then return dialog end

    local headerHeight = 32
    local contentPadding = 8
    local scrollbarWidth = 10
    local background = ThemeColor("bgDark", { 0.031, 0.031, 0.031, 0.9 })
    local headerBackground = ThemeColor("bgMedium", { 0.055, 0.055, 0.055, 0.95 })
    local border = ThemeColor("border", { 0, 0, 0, 1 })
    local accent = ThemeColor("accent", { 1, 0, 0.549, 1 })
    local primary = ThemeColor("textPrimary", { 1, 1, 1, 1 })
    local secondary = ThemeColor("textSecondary", { 0.8, 0.8, 0.8, 1 })
    local fontPath
    if KE.GetFontPath then fontPath = KE:GetFontPath() end
    if not fontPath and GameFontNormal and GameFontNormal.GetFont then
        fontPath = GameFontNormal:GetFont()
    end
    fontPath = fontPath or "Fonts\\FRIZQT__.TTF"

    local frame = CreateFrame("Frame", REPORT_FRAME_NAME, UIParent, "BackdropTemplate")
    table_insert(UISpecialFrames, REPORT_FRAME_NAME)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(background[1], background[2], background[3], background[4] or 1)
    frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
    frame:SetSize(760, 560)
    frame:Hide()
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)

    if KE.ApplyFramePosition then
        KE:ApplyFramePosition(
            frame,
            { AnchorFrom = "CENTER", AnchorTo = "CENTER", XOffset = 0, YOffset = 80 },
            { anchorFrameType = "SCREEN", ParentFrame = nil, Strata = "DIALOG" },
            true
        )
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
        frame:SetFrameStrata("DIALOG")
    end

    local moving = false
    local function StartDrag()
        if moving then return end
        moving = true
        frame:StartMoving()
    end
    local function StopDrag()
        if not moving then return end
        moving = false
        frame:StopMovingOrSizing()
    end
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", StartDrag)
    frame:SetScript("OnDragStop", StopDrag)
    frame:SetScript("OnHide", StopDrag)

    local header = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    header:SetHeight(headerHeight)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    header:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    header:SetBackdropColor(headerBackground[1], headerBackground[2],
        headerBackground[3], headerBackground[4] or 1)

    local headerBorder = header:CreateTexture(nil, "BORDER")
    headerBorder:SetHeight(1)
    headerBorder:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    headerBorder:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    headerBorder:SetColorTexture(border[1], border[2], border[3], border[4] or 1)

    local title = header:CreateFontString(nil, "OVERLAY")
    title:SetPoint("LEFT", header, "LEFT", 12, 0)
    title:SetPoint("RIGHT", header, "RIGHT", -34, 0)
    title:SetJustifyH("CENTER")
    title:SetFont(fontPath, 14, "OUTLINE")
    title:SetText("Taint Report")
    title:SetTextColor(primary[1], primary[2], primary[3], primary[4] or 1)
    title:SetShadowColor(0, 0, 0, 0)

    local closeButton = CreateFrame("Button", nil, header)
    closeButton:SetSize(22, 22)
    closeButton:SetPoint("RIGHT", header, "RIGHT", -6, 0)
    local closeTexture = closeButton:CreateTexture(nil, "ARTWORK")
    closeTexture:SetAllPoints()
    closeTexture:SetTexture(CLOSE_TEXTURE)
    closeTexture:SetRotation(math_rad(45))
    closeTexture:SetVertexColor(0.851, 0.851, 0.851, 1)
    closeTexture:SetTexelSnappingBias(0)
    closeTexture:SetSnapToPixelGrid(false)
    closeButton:SetScript("OnEnter", function()
        closeTexture:SetVertexColor(accent[1], accent[2], accent[3], accent[4] or 1)
    end)
    closeButton:SetScript("OnLeave", function()
        closeTexture:SetVertexColor(0.851, 0.851, 0.851, 1)
    end)
    closeButton:SetScript("OnClick", function() frame:Hide() end)

    local hint = header:CreateFontString(nil, "OVERLAY")
    hint:SetPoint("RIGHT", closeButton, "LEFT", -12, 0)
    hint:SetFont(fontPath, 13, "OUTLINE")
    hint:SetText("Click the report, then use Ctrl+A and Ctrl+C")
    hint:SetTextColor(secondary[1], secondary[2], secondary[3], secondary[4] or 0.8)

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", frame, "TOPLEFT", contentPadding,
        -headerHeight - contentPadding)
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -contentPadding, contentPadding)

    local scrollbar = CreateFrame("Slider", nil, content, "BackdropTemplate")
    scrollbar:SetWidth(scrollbarWidth)
    scrollbar:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
    scrollbar:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    scrollbar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    scrollbar:SetBackdropColor(background[1], background[2], background[3], 0.5)
    scrollbar:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
    scrollbar:SetOrientation("VERTICAL")
    scrollbar:SetMinMaxValues(0, 0)
    scrollbar:SetValue(0)
    scrollbar:Hide()
    local thumb = scrollbar:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(scrollbarWidth - 2, 40)
    thumb:SetColorTexture(accent[1], accent[2], accent[3], 0.8)
    scrollbar:SetThumbTexture(thumb)

    local scrollFrame = CreateFrame("ScrollFrame", nil, content)
    scrollFrame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetMaxLetters(MAX_REPORT_LENGTH)
    editBox:EnableMouse(true)
    editBox:SetAutoFocus(false)
    editBox:SetFont(fontPath, 15, "OUTLINE")
    editBox:SetShadowColor(0, 0, 0, 0)
    editBox:SetShadowOffset(0, 0)
    editBox:SetTextColor(primary[1], primary[2], primary[3], primary[4] or 1)
    editBox:SetWidth(scrollFrame:GetWidth())
    editBox:SetHeight(560 - headerHeight - contentPadding * 2)
    scrollFrame:SetScrollChild(editBox)

    dialog = {
        frame = frame,
        editBox = editBox,
        scrollFrame = scrollFrame,
        scrollbar = scrollbar,
        restoring = false,
        pendingTop = false,
    }

    editBox:SetScript("OnTextChanged", function(subject, userInput)
        if dialog.restoring or not userInput then return end
        dialog.restoring = true
        subject:SetText(canonicalText or "")
        dialog.restoring = false
    end)
    scrollbar:SetScript("OnValueChanged", function(_, value)
        scrollFrame:SetVerticalScroll(value)
    end)
    scrollFrame:SetScript("OnScrollRangeChanged", function(_, _, range)
        range = range or 0
        if range > 0 then
            scrollbar:Show()
            scrollbar:SetMinMaxValues(0, range)
            scrollFrame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT",
                -scrollbarWidth - 4, 0)
        else
            scrollbar:Hide()
            scrollbar:SetMinMaxValues(0, 0)
            scrollFrame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
        end
        editBox:SetWidth(scrollFrame:GetWidth())
        if dialog.pendingTop then
            scrollbar:SetValue(0)
            dialog.pendingTop = false
        end
    end)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(_, delta)
        local value = scrollbar:GetValue() - delta * 40
        local minimum, maximum = scrollbar:GetMinMaxValues()
        if value < minimum then value = minimum end
        if value > maximum then value = maximum end
        scrollbar:SetValue(value)
    end)
    return dialog
end

local function OpenReport()
    local report = BuildReport()
    if not report or not SafeFinishedString(report) then return end
    canonicalText = report
    local window = BuildDialog()
    window.pendingTop = true
    window.scrollbar:SetValue(0)
    window.restoring = true
    window.editBox:SetText(canonicalText)
    window.restoring = false
    window.frame:Show()
end

local function OnLogout()
    Persist()
end

function TaintReport.Initialize(db)
    if initialized then return end
    if not AccessibleTable(db) then return end
    local global = db.global
    if not AccessibleTable(global) then return end

    attachedGlobal = global
    initialized = true
    local wasDirty = dirty
    global.TaintLog = RestoreStore(global.TaintLog)
    dirty = wasDirty

    if pendingNotifications > 0 and KE.Print then
        local message = "Protected actions attributed to KitnEssentials were captured during startup. Use /kes taint."
        if SafeFinishedString(message) then KE:Print(message) end
        pendingNotifications = 0
    end
end

function TaintReport.RunCommand(input)
    if not SafeCanAccess(input) or type(input) ~= "string" then
        input = ""
    end
    local command = string_match(input, "^%s*(.-)%s*$")
    if not SafeCanAccess(command) then return end
    command = string_lower(command)
    if not SafeCanAccess(command) then return end

    if command == "" then
        OpenReport()
    elseif command == "clear" then
        Clear()
        if KE.Print then
            local message = "Taint report cleared."
            if SafeFinishedString(message) then KE:Print(message) end
        end
    elseif KE.Print then
        local message = "Usage: /kes taint [clear]"
        if SafeFinishedString(message) then KE:Print(message) end
    end
end

KE.TaintReport = TaintReport

eventFrame:RegisterEvent("ADDON_ACTION_BLOCKED")
eventFrame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        OnBlocked(event, ...)
    elseif event == "PLAYER_LOGOUT" then
        OnLogout()
    end
end)
