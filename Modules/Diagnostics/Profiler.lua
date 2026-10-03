-- ╔══════════════════════════════════════════════════════════╗
-- ║  Profiler.lua                                            ║
-- ║  Module: KE In-Game Profiler                             ║
-- ║  Purpose: Push-button CPU + memory sampling for KE work, ║
-- ║           accessed via /kes profiler <subcommand>.       ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local C_CVar_GetCVar     = C_CVar.GetCVar
local C_CVar_SetCVar     = C_CVar.SetCVar
local GetAddOnCPUUsage   = GetAddOnCPUUsage
local GetAddOnMemoryUsage = GetAddOnMemoryUsage
local GetFrameCPUUsage   = GetFrameCPUUsage
local UpdateAddOnCPUUsage = UpdateAddOnCPUUsage
local UpdateAddOnMemoryUsage = UpdateAddOnMemoryUsage
local ResetCPUUsage      = ResetCPUUsage
local GetTime            = GetTime
local GetFramerate       = GetFramerate

local print     = print
local format    = string.format
local sort      = table.sort
local insert    = table.insert
local concat    = table.concat
local pairs     = pairs
local ipairs    = ipairs
local type      = type
local pcall     = pcall
local tonumber  = tonumber
local tostring  = tostring
local math_min  = math.min
local math_max  = math.max
local math_huge = math.huge
local time      = time
local date      = date

---------------------------------------------------------------------------------
-- Output helpers
---------------------------------------------------------------------------------

local PREFIX = "|cffFF008CKitn|r|cffffffffEssentials Profiler:|r "
local function p(msg) print(PREFIX .. tostring(msg)) end
local function pf(fmt, ...) print(PREFIX .. format(fmt, ...)) end

---------------------------------------------------------------------------------
-- DB
---------------------------------------------------------------------------------
-- Snapshots live in AceDB global section so they survive /reload.
-- Falls back to an in-memory table when KE.db isn't ready yet.

local _memDB = { snapshots = {}, lastMemKB = 0 }

local function ResolveDB()
    if KE.db and KE.db.global then
        local g = KE.db.global
        if not g.profiler then
            g.profiler = { snapshots = {}, lastMemKB = 0 }
        end
        g.profiler.snapshots = g.profiler.snapshots or {}
        return g.profiler
    end
    return _memDB
end

---------------------------------------------------------------------------------
-- Profiling cvar
---------------------------------------------------------------------------------

local function ProfilingEnabled()
    -- The legacy GetAddOnCPUUsage / UpdateAddOnCPUUsage path that this
    -- profiler uses depends specifically on the `scriptProfile` cvar.
    -- `C_AddOnProfiler.IsEnabled()` returns true for all users (per its
    -- docs: "AddOn profiler will be enabled for all users"), but it
    -- governs the *new* C_AddOnProfiler.GetAddOnMetric data path —
    -- a different data source. If we trust IsEnabled() and scriptProfile
    -- happens to be 0, snap output reads `cpu=0.00 ms, frames=0` while
    -- claiming profiling is on. The cvar is the authoritative gate for
    -- the legacy API we actually call.
    return tonumber(C_CVar_GetCVar("scriptProfile")) == 1
end

local detailedProfilingActive = ProfilingEnabled()

local cpuWindowSequence = 0
local cpuWindow
local frameIds = {}
local nextFrameId = 0

local function ResetFrameIds()
    frameIds = {}
    nextFrameId = 0
end

local function ResolveFrameId(frameObject)
    local frameId = frameIds[frameObject]
    if not frameId then
        nextFrameId = nextFrameId + 1
        frameId = nextFrameId
        frameIds[frameObject] = frameId
    end
    return frameId
end

local function StartCpuWindow()
    cpuWindowSequence = cpuWindowSequence + 1
    local startedAt = GetTime()
    ResetFrameIds()
    cpuWindow = {
        id = format("%d:%.6f:%d", time(), startedAt, cpuWindowSequence),
        startedAt = startedAt,
    }
end

local function GetMetricEnum(metricName)
    local enum = Enum and Enum.AddOnProfilerMetric
    return enum and enum[metricName]
end

local function GetMetricValue(metricName)
    if not (C_AddOnProfiler and C_AddOnProfiler.GetAddOnMetric) then
        return nil
    end
    local metric = GetMetricEnum(metricName)
    if not metric then return nil end
    return C_AddOnProfiler.GetAddOnMetric("KitnEssentials", metric)
end

local function FormatFooterPercent(percent)
    if percent < 0.01 then return "<0.01%" end
    if percent < 0.1 then return format("~%.2f%%", percent) end
    return format("~%.1f%%", percent)
end

local function GetFooterDisplay()
    local recentMs = GetMetricValue("RecentAverageTime")
    if type(recentMs) ~= "number" then
        return "CPU: unavailable", detailedProfilingActive
    end

    local cpuText = format("CPU: %.4f MS", recentMs)
    local fps = GetFramerate and GetFramerate()
    if type(fps) == "number" and fps > 0 then
        local framePercent = recentMs / (1000 / fps) * 100
        cpuText = format("%s (%s)", cpuText, FormatFooterPercent(framePercent))
    end
    return cpuText, detailedProfilingActive
end

local function CaptureCpuSummary()
    UpdateAddOnCPUUsage()
    local addonMs = GetAddOnCPUUsage("KitnEssentials") or 0
    local elapsed
    if cpuWindow then
        elapsed = math_max(GetTime() - cpuWindow.startedAt, 0)
    end
    local rate
    local percent
    if elapsed and elapsed > 0 then
        rate = addonMs / elapsed
        percent = rate / 10
    end
    return {
        addonMs = addonMs,
        windowId = cpuWindow and cpuWindow.id or nil,
        elapsed = elapsed,
        rate = rate,
        percent = percent,
        recentMs = GetMetricValue("RecentAverageTime"),
        peakMs = GetMetricValue("PeakTime"),
    }
end

---------------------------------------------------------------------------------
-- Frame discovery
---------------------------------------------------------------------------------
-- Walks _G for KE-named globals + Ace modules' .frame attribute and samples
-- direct and inclusive CPU for each discovered frame.
--
-- Frames built from one template have been observed to report one shared cost
-- each, which fits GetFrameCPUUsage charging a script handler rather than a
-- frame instance; inclusive sampling then multiplies that by the child count.
-- Only the direct figure is reported, and identical counters are grouped.

local function IsFrame(v)
    if type(v) ~= "table" then return false end
    if not v.GetObjectType then return false end
    local ok = pcall(v.GetObjectType, v)
    return ok
end

local function AddCandidate(candidates, name, frameObject, priority)
    if not IsFrame(frameObject) then return end
    insert(candidates, {
        name = name,
        frame = frameObject,
        priority = priority,
    })
end

local function BuildFrameCandidates()
    local candidates = {}

    for key, value in pairs(_G) do
        if type(key) == "string"
            and (key:sub(1, 3) == "KE_" or key:sub(1, 14) == "KitnEssentials") then
            AddCandidate(candidates, key, value, 1)
        end
    end

    if KitnEssentials and KitnEssentials.IterateModules then
        for name, module in KitnEssentials:IterateModules() do
            AddCandidate(candidates, name .. ".frame", module.frame, 2)
            AddCandidate(candidates, name .. ".bar", module.bar, 2)
            AddCandidate(candidates, name .. ".container", module.container, 2)
            AddCandidate(candidates, name .. ".panel", module.panel, 2)
        end
    end

    if KE and type(KE.GUIFrame) == "table" then
        AddCandidate(candidates, "KE.GUIFrame.frame", KE.GUIFrame.frame, 3)
        AddCandidate(candidates, "KE.GUIFrame", KE.GUIFrame, 3)
    end

    sort(candidates, function(a, b)
        if a.priority ~= b.priority then
            return a.priority < b.priority
        end
        return a.name < b.name
    end)
    return candidates
end

local function GatherCpuRows()
    local rows = {}
    local seen = {}

    for _, candidate in ipairs(BuildFrameCandidates()) do
        local frameObject = candidate.frame
        if not seen[frameObject] then
            seen[frameObject] = true
            local selfOK, selfMs, selfCalls = pcall(GetFrameCPUUsage, frameObject, false)
            local treeOK, treeMs, treeCalls = pcall(GetFrameCPUUsage, frameObject, true)
            if selfOK and treeOK
                and type(selfMs) == "number" and type(treeMs) == "number"
                and (selfMs > 0 or treeMs > 0) then
                insert(rows, {
                    frameId = ResolveFrameId(frameObject),
                    name = candidate.name,
                    selfMs = selfMs,
                    -- The API declares a non-nilable call count: a missing one is
                    -- a broken contract, not an idle frame.
                    selfCalls = type(selfCalls) == "number" and selfCalls or nil,
                    treeMs = treeMs,
                    treeCalls = type(treeCalls) == "number" and treeCalls or nil,
                })
            end
        end
    end

    sort(rows, function(a, b)
        if a.treeMs ~= b.treeMs then
            return a.treeMs > b.treeMs
        end
        return a.name < b.name
    end)
    return rows
end

-- Equal counters are evidence of a shared handler, not proof: an accidental
-- collision groups too, and partial sharing does not group at all. The label
-- claims only what was measured.
local NAMES_SHOWN = 3
local FRAME_CAVEAT = "Frames with identical CPU counters are grouped: frames built from one template have been observed to report one shared cost each. These costs do not sum to a total: a handler shared by frames that differ elsewhere is charged in full to each of them. Timer and plain Lua callback work is not attributed to frames."

local function DescribeGroup(names, count)
    if count < 2 then
        return names[1]
    end
    local shown = {}
    for index = 1, math_min(NAMES_SHOWN, count) do
        shown[index] = names[index]
    end
    local suffix = count > NAMES_SHOWN and " ..." or ""
    return format("identical counters x%d: %s%s", count, concat(shown, ", "), suffix)
end

local function CollectGroups(entries, keyOf)
    local groups = {}
    local byKey = {}

    for _, entry in ipairs(entries) do
        local key = keyOf(entry)
        local group = byKey[key]
        if not group then
            group = { names = {}, count = 0 }
            for field, value in pairs(entry) do
                if field ~= "name" then
                    group[field] = value
                end
            end
            byKey[key] = group
            groups[#groups + 1] = group
        end
        group.count = group.count + 1
        group.names[group.count] = entry.name
    end

    for _, group in ipairs(groups) do
        sort(group.names)
    end
    return groups
end

-- A NaN call count still reaches the row's own %d conversion, which prints it
-- as a number nothing measured. A counter that cannot be trusted is dropped
-- instead.
local function IsFinite(value)
    return type(value) == "number"
        and value == value
        and value ~= math_huge
        and value ~= -math_huge
end

-- An absent call count is not a measured zero. Unknown stays unknown wherever a
-- count is printed, keyed or compared; a present but unusable one is dropped.
local function CounterUsable(value)
    return value == nil or IsFinite(value)
end

local function CounterKey(value)
    return value and format("%.17g", value) or "?"
end

local function FormatCalls(selfCalls)
    return selfCalls and format("%d", selfCalls) or "?"
end

-- A cost with no calls behind it has no rate: the division would print a zero
-- the sample never contained.
local function FormatPerCall(selfMs, selfCalls)
    if selfCalls and selfCalls > 0 then
        return format("%.4f ms/call", selfMs / selfCalls)
    end
    return "? ms/call"
end

local function GroupSharedRows(rows)
    local scored = {}
    local dropped = 0
    for _, row in ipairs(rows) do
        if not (IsFinite(row.selfMs) and CounterUsable(row.selfCalls)) then
            dropped = dropped + 1
        elseif row.selfMs > 0 then
            scored[#scored + 1] = {
                name = row.name,
                selfMs = row.selfMs,
                selfCalls = row.selfCalls,
            }
        end
    end

    local groups = CollectGroups(scored, function(entry)
        return format("%.17g|%s", entry.selfMs, CounterKey(entry.selfCalls))
    end)

    sort(groups, function(a, b)
        if a.selfMs ~= b.selfMs then
            return a.selfMs > b.selfMs
        end
        return a.names[1] < b.names[1]
    end)
    return groups, dropped
end

---------------------------------------------------------------------------------
-- Public commands
---------------------------------------------------------------------------------

local function ToggleProfile(state)
    if state == "on" then
        C_CVar_SetCVar("scriptProfile", "1")
        p("scriptProfile = 1.  /reload required for the cvar to actually start sampling.")
    elseif state == "off" then
        C_CVar_SetCVar("scriptProfile", "0")
        p("scriptProfile = 0.  /reload to stop sampling.")
    else
        local cvarOn = tonumber(C_CVar_GetCVar("scriptProfile")) == 1
        local namespaceOn = (C_AddOnProfiler and C_AddOnProfiler.IsEnabled and C_AddOnProfiler.IsEnabled()) and true or false
        pf("scriptProfile cvar:        %s  (drives GetAddOnCPUUsage — the legacy path /kes profiler uses)",
            cvarOn and "ON" or "OFF")
        pf("C_AddOnProfiler.IsEnabled: %s  (drives the new GetAddOnMetric path — separate data source)",
            namespaceOn and "ON" or "OFF")
        if not cvarOn then
            p("To enable CPU profiling: /kes profiler on, then /reload.  The cvar requires a /reload to start sampling.")
        end
    end
end

local PROFILER_WARNING_TEXT = "CPU profiling is enabled and reduces FPS. Disable it when testing is finished with /kes profiler off, then /reload."
local profilerWarningFrame = CreateFrame("Frame")
local profilerPopupPending = false

local function DisableProfilingAndReload()
    C_CVar_SetCVar("scriptProfile", "0")
    ReloadUI()
end

-- A Blizzard popup shown from addon code taints the popup list that secure
-- code walks at login, so this uses KE's own prompt.
local function ShowProfilerWarningPopup()
    KE:CreatePrompt("CPU Profiler",
        "|cffFF008CKitn|r|cffffffffEssentials|r CPU profiling is enabled. It adds measurable overhead and should stay on only while testing. Disable it and reload now?",
        false, nil, false, nil, nil, nil, nil, DisableProfilingAndReload, nil,
        "Disable & Reload", "Keep Enabled", nil, nil, { waitIfBusy = true })
end

local function HandleProfilerLogin()
    profilerWarningFrame:UnregisterEvent("PLAYER_LOGIN")
    if not detailedProfilingActive then return end

    p("|cffff3333" .. PROFILER_WARNING_TEXT .. "|r")
    if InCombatLockdown() then
        profilerPopupPending = true
        profilerWarningFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    ShowProfilerWarningPopup()
end

local function HandleProfilerRegen()
    profilerWarningFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    profilerPopupPending = false
    if not ProfilingEnabled() then return end
    ShowProfilerWarningPopup()
end

profilerWarningFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        HandleProfilerLogin()
    elseif event == "PLAYER_REGEN_ENABLED" and profilerPopupPending then
        HandleProfilerRegen()
    end
end)
profilerWarningFrame:RegisterEvent("PLAYER_LOGIN")

local function PrintCpuTop(arg)
    if not ProfilingEnabled() then
        p("Profiling is OFF. /kes profiler on then /reload to enable CPU profiling.")
        return
    end

    local n = tonumber(arg) or 15
    local summary = CaptureCpuSummary()
    local rows = GatherCpuRows()

    if summary.rate then
        pf("CPU window: %.1f sec since /kes profiler reset.", summary.elapsed)
        pf("KitnEssentials: %.2f ms total | %.2f ms/sec | %.2f%% of one CPU-second.",
            summary.addonMs, summary.rate, summary.percent)
    elseif summary.elapsed ~= nil then
        pf("CPU window: %.1f sec since /kes profiler reset; exercise the UI before calculating a rate.",
            summary.elapsed)
        pf("KitnEssentials total: %.2f ms.", summary.addonMs)
    else
        pf("KitnEssentials total: %.2f ms (sampling duration unknown; use /kes profiler reset for a normalized rate).",
            summary.addonMs)
    end

    if summary.recentMs ~= nil and summary.peakMs ~= nil then
        pf("Live profiler: recent avg %.4f ms/tick | peak since launch %.4f ms.",
            summary.recentMs, summary.peakMs)
    end

    if #rows == 0 then
        p("No frame CPU samples yet. Try /kes profiler reset, exercise the UI, then /kes profiler cpu again.")
        p(FRAME_CAVEAT)
        return
    end

    local groups, dropped = GroupSharedRows(rows)
    if dropped > 0 then
        pf("%d frame(s) omitted: a counter was not a finite number.", dropped)
    end
    pf("Top %d named KE frames by direct CPU:", n)
    for index = 1, math_min(n, #groups) do
        local group = groups[index]
        pf("  %2d. %.2f ms (calls=%s, %s) %s",
            index, group.selfMs, FormatCalls(group.selfCalls),
            FormatPerCall(group.selfMs, group.selfCalls),
            DescribeGroup(group.names, group.count))
    end
    if #groups == 0 then
        p("  No direct frame work recorded.")
    end
    p(FRAME_CAVEAT)
end

local function PrintMemory()
    UpdateAddOnMemoryUsage()
    local kb = GetAddOnMemoryUsage("KitnEssentials") or 0
    local db = ResolveDB()
    local last = db.lastMemKB or 0
    local delta = kb - last
    db.lastMemKB = kb
    if last == 0 then
        pf("KitnEssentials memory: %.1f KB  (baseline set — call /kes profiler mem again to see delta).", kb)
    else
        local sign = delta >= 0 and "+" or ""
        pf("KitnEssentials memory: %.1f KB  (%s%.1f KB since last /kes profiler mem call).", kb, sign, delta)
    end
end

local function ResetCpu()
    ResetCPUUsage()
    StartCpuWindow()
    p("CPU counters reset. Exercise the UI, then /kes profiler cpu.")
end

local CPU_REPORT_SCHEMA = 2

local function CaptureSnapshot(label)
    local summary
    if ProfilingEnabled() then
        summary = CaptureCpuSummary()
    end
    UpdateAddOnMemoryUsage()
    local rows = summary and GatherCpuRows() or {}

    local snap = {
        schema = CPU_REPORT_SCHEMA,
        label = label,
        time = time(),
        date = date("%Y-%m-%d %H:%M:%S"),
        memKB = GetAddOnMemoryUsage("KitnEssentials") or 0,
        cpuMS = summary and summary.addonMs or 0,
        cpuWindowId = summary and summary.windowId or nil,
        cpuElapsed = summary and summary.elapsed or nil,
        frames = {},
    }

    for _, row in ipairs(rows) do
        snap.frames[#snap.frames + 1] = {
            frameId = row.frameId,
            name = row.name,
            selfMs = row.selfMs,
            selfCalls = row.selfCalls,
            treeMs = row.treeMs,
            treeCalls = row.treeCalls,
        }
    end
    return snap
end

local function SnapshotFrameCount(snapshot)
    return #(snapshot.frames or snapshot.functions or {})
end

-- Twenty covers a before/after series with room and bounds the saved block.
local SNAPSHOT_CAP = 20

-- The oldest by time among every label except `keep`, the one just written.
-- Equal times fall to the lower label so the pick is the same every run; a
-- snapshot with no numeric time sorts oldest.
local function OldestSnapshotLabel(snapshots, keep)
    local oldestLabel, oldestTime = nil, math_huge
    for label, snapshot in pairs(snapshots) do
        if label ~= keep then
            local stamp = -math_huge
            if type(snapshot) == "table" and type(snapshot.time) == "number" then
                stamp = snapshot.time
            end
            if oldestLabel == nil or stamp < oldestTime
                or (stamp == oldestTime and tostring(label) < tostring(oldestLabel)) then
                oldestLabel, oldestTime = label, stamp
            end
        end
    end
    return oldestLabel
end

local function TakeSnapshot(label)
    local snap = CaptureSnapshot(label)
    local snapshots = ResolveDB().snapshots
    snapshots[label] = snap
    pf("Snapshot saved: %s (mem=%.1f KB, cpu=%.2f ms, frames=%d)",
        label, snap.memKB, snap.cpuMS, SnapshotFrameCount(snap))

    local count = 0
    for _ in pairs(snapshots) do count = count + 1 end
    while count > SNAPSHOT_CAP do
        local oldest = OldestSnapshotLabel(snapshots, label)
        if oldest == nil then break end
        snapshots[oldest] = nil
        count = count - 1
        pf("Dropped oldest snapshot: %s", tostring(oldest))
    end
end

local function ListSnapshots()
    local db = ResolveDB()
    local names = {}
    for key in pairs(db.snapshots) do
        insert(names, key)
    end
    sort(names)
    if #names == 0 then
        p("No snapshots saved.")
        return
    end
    pf("Snapshots (%d):", #names)
    for _, key in ipairs(names) do
        local snapshot = db.snapshots[key]
        pf("  [%s] mem=%.1f KB cpu=%.2f ms frames=%d @%s",
            key, snapshot.memKB or 0, snapshot.cpuMS or 0,
            SnapshotFrameCount(snapshot), snapshot.date or "?")
    end
end

local function SnapshotByName(name)
    if name == "now" then
        return CaptureSnapshot("now")
    end
    return ResolveDB().snapshots[name]
end

local function HasComparableCpuWindow(a, b)
    return a.schema == CPU_REPORT_SCHEMA
        and b.schema == CPU_REPORT_SCHEMA
        and a.cpuWindowId ~= nil
        and a.cpuWindowId == b.cpuWindowId
        and type(a.cpuElapsed) == "number"
        and type(b.cpuElapsed) == "number"
        and b.cpuElapsed > a.cpuElapsed
        and type(a.cpuMS) == "number"
        and type(b.cpuMS) == "number"
        and b.cpuMS >= a.cpuMS
end

local function BuildFrameIndexes(snapshot)
    local byId = {}
    local byName = {}
    for _, row in ipairs(snapshot.frames or {}) do
        if row.frameId == nil or type(row.name) ~= "string"
            or byId[row.frameId] or byName[row.name] then
            return nil, nil
        end
        byId[row.frameId] = row
        byName[row.name] = row.frameId
    end
    return byId, byName
end

local function FiniteCounterPair(old, row)
    return IsFinite(old.selfMs or 0) and IsFinite(row.selfMs or 0)
        and CounterUsable(old.selfCalls) and CounterUsable(row.selfCalls)
end

-- An unknown count on either side is not a decrease. Read as zero it would
-- refuse every frame delta in the diff over a count nothing measured.
local function CallsDecreased(old, row)
    return old.selfCalls ~= nil and row.selfCalls ~= nil
        and row.selfCalls < old.selfCalls
end

local function FrameCountersComparable(a, b)
    local beforeById, beforeByName = BuildFrameIndexes(a)
    local afterById, afterByName = BuildFrameIndexes(b)
    if not beforeById or not afterById then
        return nil, "identity"
    end

    for name, beforeId in pairs(beforeByName) do
        local afterId = afterByName[name]
        if afterId and afterId ~= beforeId then
            return nil, "identity"
        end
    end

    for frameId, row in pairs(afterById) do
        local old = beforeById[frameId]
        -- Tree counters are captured but no longer reported. A tree-only drop
        -- has benign causes (a descendant destroyed or reparented) and would
        -- otherwise veto direct deltas over a figure nothing prints.
        --
        -- A non-finite counter is passed over rather than compared: any value
        -- is below an infinity, so comparing one would refuse the whole diff
        -- over a single unusable row. The delta path drops and counts it.
        if old and FiniteCounterPair(old, row)
            and ((row.selfMs or 0) < (old.selfMs or 0)
            or CallsDecreased(old, row)) then
            return nil, "counter"
        end
    end
    return beforeById
end

-- Grouped on the whole before/after tuple, not on the delta: equal growth from
-- different baselines would print one member's numbers as if they were shared.
local function PositiveFrameDeltas(beforeById, b)
    local deltas = {}
    local newlyObserved = 0
    local dropped = 0
    for _, row in ipairs(b.frames or {}) do
        local old = beforeById[row.frameId]
        if not old then
            newlyObserved = newlyObserved + 1
        else
            local prior = old.selfMs or 0
            local current = row.selfMs or 0
            local delta = current - prior
            if not FiniteCounterPair(old, row) then
                dropped = dropped + 1
            elseif delta > 0.01 then
                deltas[#deltas + 1] = {
                    name = row.name,
                    delta = delta,
                    prior = prior,
                    current = current,
                    priorCalls = old.selfCalls,
                    currentCalls = row.selfCalls,
                }
            end
        end
    end

    local groups = CollectGroups(deltas, function(entry)
        return format("%.17g|%.17g|%s|%s",
            entry.prior, entry.current,
            CounterKey(entry.priorCalls), CounterKey(entry.currentCalls))
    end)

    sort(groups, function(x, y)
        if x.delta ~= y.delta then
            return x.delta > y.delta
        end
        return x.names[1] < y.names[1]
    end)
    return groups, newlyObserved, dropped
end

local function DiffSnapshots(aName, bName)
    bName = bName or "now"
    local a = SnapshotByName(aName)
    if not a then pf("Snapshot '%s' not found.", aName); return end
    local b = SnapshotByName(bName)
    if not b then pf("Snapshot '%s' not found.", bName); return end

    pf("Diff: '%s' -> '%s'", aName, bName)
    pf("  Memory: %.1f KB -> %.1f KB (%+.1f KB)",
        a.memKB or 0, b.memKB or 0, (b.memKB or 0) - (a.memKB or 0))

    if not HasComparableCpuWindow(a, b) then
        p("  CPU/frame deltas unavailable: snapshots are not comparable within one known /kes profiler reset window.")
        return
    end

    local seconds = b.cpuElapsed - a.cpuElapsed
    local cpuDelta = b.cpuMS - a.cpuMS
    pf("  CPU: %+.2f ms over %.1f sec (%.2f ms/sec)",
        cpuDelta, seconds, cpuDelta / seconds)

    local beforeById, frameProblem = FrameCountersComparable(a, b)
    if not beforeById then
        if frameProblem == "identity" then
            p("  Frame deltas unavailable: a saved name resolved to a different frame object or frame identity was missing.")
        else
            p("  Frame deltas unavailable: a frame counter decreased, indicating an external reset or invalid sample.")
        end
        return
    end

    local selfDeltas, newlyObserved, dropped = PositiveFrameDeltas(beforeById, b)
    if newlyObserved > 0 then
        pf("  %d newly observed frame(s) omitted from frame deltas.", newlyObserved)
    end
    if dropped > 0 then
        pf("  %d frame(s) omitted: a counter was not a finite number.", dropped)
    end
    if #selfDeltas > 0 then
        p("  Top direct-frame deltas:")
        for index = 1, math_min(10, #selfDeltas) do
            local delta = selfDeltas[index]
            pf("    %+.2f ms (%.2f -> %.2f) %s",
                delta.delta, delta.prior, delta.current,
                DescribeGroup(delta.names, delta.count))
        end
        p("  " .. FRAME_CAVEAT)
    end
end

local function ClearSnapshots()
    local db = ResolveDB()
    db.snapshots = {}
    p("Snapshots cleared.")
end

local function PrintTopAddOns(arg)
    if not (C_AddOnProfiler and C_AddOnProfiler.GetTopKAddOnsForMetric) then
        p("C_AddOnProfiler.GetTopKAddOnsForMetric not available.")
        return
    end
    local n = tonumber(arg) or 10
    local metric = GetMetricEnum("RecentAverageTime")
    if not metric then p("Enum.AddOnProfilerMetric.RecentAverageTime missing."); return end
    local results = C_AddOnProfiler.GetTopKAddOnsForMetric(metric, n)
    if not results or #results == 0 then
        p("No addon metrics returned.")
        return
    end
    pf("Top %d addons by RecentAverageTime (60-tick avg, ms):", n)
    for i, r in ipairs(results) do
        pf("  %2d. %.4f ms  %s", i, r.metricValue or 0, r.addOnName or "?")
    end
end

local function PrintPeak()
    if not (C_AddOnProfiler and C_AddOnProfiler.GetAddOnMetric) then
        p("C_AddOnProfiler.GetAddOnMetric not available.")
        return
    end
    local function get(metricName)
        local m = GetMetricEnum(metricName)
        if not m then return 0 end
        return C_AddOnProfiler.GetAddOnMetric("KitnEssentials", m) or 0
    end
    pf("KitnEssentials live metrics:")
    pf("  Last tick:            %.4f ms", get("LastTime"))
    pf("  Recent avg (60 tick): %.4f ms", get("RecentAverageTime"))
    pf("  Session avg:          %.4f ms", get("SessionAverageTime"))
    pf("  Peak (since launch):  %.4f ms", get("PeakTime"))
    pf("  Ticks > 1ms:  %d", get("CountTimeOver1Ms"))
    pf("  Ticks > 5ms:  %d", get("CountTimeOver5Ms"))
    pf("  Ticks > 10ms: %d", get("CountTimeOver10Ms"))
    pf("  Ticks > 50ms: %d", get("CountTimeOver50Ms"))
end

---------------------------------------------------------------------------------
-- Census
---------------------------------------------------------------------------------
-- On demand only. Each walking and ranking phase works one unit at a time
-- under one count and millisecond budget per step; the frame list is read
-- whole in one step, and the report is one bounded step. It registers
-- nothing, and baselines live in these locals for the session, never in saved
-- data.

local EnumerateFrames  = EnumerateFrames
local debugprofilestop = debugprofilestop
local rawget           = rawget
local next             = next
local strfind          = string.find
local math_floor       = math.floor

local CENSUS_SLICE = 4000
local CENSUS_BUDGET_MS = 4
-- About a minute at 60 fps. A walk still running then (a live table growing
-- as fast as it is read) stops and reports as incomplete.
local CENSUS_MAX_STEPS = 3600
local CENSUS_TOP = 10
local UNKNOWN_CREATOR = "unknown creator"
local WALKING = { libs = true, globals = true, collect = true, frames = true, tables = true }
local RANKED = { "histogram", "creators", "byKey" }

-- Owner markers for the table walk: SAVED counts KE.db.sv on its own line,
-- ROOT is the KE namespace itself.
local SAVED, ROOT = {}, {}

local censusRunning = false
local censusFirst, censusPrev

local function CensusKey(objectType, children, regions)
    return format("%s %d:%d", tostring(objectType), children, regions)
end

-- Every read here is a secret aspect in 12.x, so each return is tested before
-- it is used. A frame with a parent stops after two calls.
local function CensusInspect(frame)
    local forbidden = frame:IsForbidden()
    if KE:IsSecretValue(forbidden) then return "unreadable" end
    if forbidden then return "forbidden" end
    local parent = frame:GetParent()
    if KE:IsSecretValue(parent) then return "unreadable" end
    if parent ~= nil then return "outside" end
    local name = frame:GetName()
    if KE:IsSecretValue(name) then return "unreadable" end
    if name ~= nil then return "outside" end
    local objectType = frame:GetObjectType()
    local children = frame:GetNumChildren()
    local regions = frame:GetNumRegions()
    if KE:IsSecretValue(objectType) or KE:IsSecretValue(children) or KE:IsSecretValue(regions) then
        return "unreadable"
    end
    local creator = frame:GetSourceLocation()
    if KE:IsSecretValue(creator) or type(creator) ~= "string" or creator == "" then
        creator = nil
    end
    return "bucket", CensusKey(objectType, children, regions), creator
end

-- A frame object (a table holding its userdata at [0]) is counted, never
-- entered: its fields lead into parent chains and Blizzard's tables. A secret
-- at [0] cannot be classified, so it is counted the same way.
local function CensusPush(run, value, owner)
    if KE:IsSecretValue(value) or type(value) ~= "table" or run.seen[value] then return end
    run.seen[value] = true
    local handle = rawget(value, 0)
    if KE:IsSecretValue(handle) or type(handle) == "userdata" then
        run.frameRefs = run.frameRefs + 1
        return
    end
    local top = run.top + 1
    run.top = top
    run.stackTables[top] = value
    run.stackOwners[top] = owner
end

local function CensusEntry(run, key, value, owner)
    local childOwner = owner
    if owner == SAVED then
        run.savedEntries = run.savedEntries + 1
    else
        local label = owner
        if owner == ROOT then
            label = "KE"
            childOwner = KE:IsSecretValue(key) and "?" or tostring(key)
        end
        run.entries = run.entries + 1
        run.byKey[label] = (run.byKey[label] or 0) + 1
    end
    CensusPush(run, key, childOwner)
    CensusPush(run, value, childOwner)
end

-- KE's own globals carry the house prefixes. Every other table in _G belongs
-- to Blizzard or another addon and is not walked, however KE reaches it (a
-- field, or a hook registry keyed by the hooked table).
local function IsOwnGlobal(name)
    if KE:IsSecretValue(name) or type(name) ~= "string" then return false end
    return (strfind(name, "^KE_") or strfind(name, "^KitnEssentials")
        or strfind(name, "^KITNESSENTIALS")) ~= nil
end

-- Every ranked key is a string: histogram keys, creator locations and owner
-- labels are all built as strings.
local function Outranks(count, key, row)
    return count > row.count or (count == row.count and key < row.key)
end

-- Keeps the top CENSUS_TOP rows, one key per call, without a full sort.
local function RankInto(rows, key, count)
    local n = #rows
    if n == CENSUS_TOP and not Outranks(count, key, rows[n]) then return end
    if n == CENSUS_TOP then
        rows[n] = nil
        n = n - 1
    end
    local i = n
    while i > 0 and Outranks(count, key, rows[i]) do
        rows[i + 1] = rows[i]
        i = i - 1
    end
    rows[i + 1] = { key = key, count = count }
end

local function PrintRows(rows)
    for _, row in ipairs(rows) do pf("  %6d  %s", row.count, row.key) end
end

local function PrintDiff(run, label, base)
    pf("Since the %s census: parentless unnamed %+d, tables %+d, entries %+d.",
        label, run.bucket - base.bucket, run.tableCount - base.tableCount,
        run.entries - base.entries)
    for _, row in ipairs(run.ranked.histogram) do
        pf("  %+6d  %s", row.count - (base.histogram[row.key] or 0), row.key)
    end
end

-- Bounded whatever the census found: three lists of ten and two diffs of ten.
-- A run stopped at the step cap keeps no baseline, or every later diff would
-- compare against partial counts.
local function CensusReport(run, started)
    local ranked = run.ranked
    if run.stoppedAt then
        pf("INCOMPLETE: stopped after %d steps; every count below is partial.", run.stoppedAt)
    end
    pf("Census: %d frames, %d forbidden, %d unreadable.", run.frames, run.forbidden, run.unreadable)
    pf("Parentless unnamed frames: %d. Top %d by type and children:regions:", run.bucket, CENSUS_TOP)
    PrintRows(ranked.histogram)
    pf("Top %d creators:", CENSUS_TOP)
    PrintRows(ranked.creators)
    pf("  %6d  %s", run.unknownCreators, UNKNOWN_CREATOR)
    pf("KE_GUI_ORPHAN_COUNT: %d", KE_GUI_ORPHAN_COUNT or 0)
    pf("Saved data: %d entries under KE.db.sv.", run.savedEntries)
    pf("KE tables: %d tables, %d entries, %d frame references, %d skipped. Top %d keys:",
        run.tableCount, run.entries, run.frameRefs, run.skipped, CENSUS_TOP)
    PrintRows(ranked.byKey)
    if censusPrev then PrintDiff(run, "previous", censusPrev) end
    if censusFirst and censusFirst ~= censusPrev then PrintDiff(run, "first", censusFirst) end

    local ms = debugprofilestop() - started
    if ms > run.slowestMs then run.slowestMs = ms end
    local perStep = run.frameSteps > 0 and math_floor(run.frames / run.frameSteps) or 0
    pf("Walk: %d steps, %d frames per frame step, slowest step %.2f ms, %.0f ms elapsed.",
        run.steps, perStep, run.slowestMs, debugprofilestop() - run.started)
    run.phase = "done"

    if run.stoppedAt then return end
    local summary = {
        bucket = run.bucket,
        tableCount = run.tableCount,
        entries = run.entries,
        histogram = run.histogram,
    }
    censusPrev = summary
    censusFirst = censusFirst or summary
end

-- One unbudgeted step that freezes the game for seconds, so it runs after the
-- warning line has been drawn and never in combat. It calls nothing on a
-- frame: a handle kept into a later game frame ends the walk early.
local function CensusCollect(run)
    if InCombatLockdown() then error("combat started before the frame list was read", 0) end
    local list, n, frame = run.frameList, 0, EnumerateFrames()
    while frame do
        n = n + 1
        list[n] = frame
        frame = EnumerateFrames(frame)
    end
    run.phase = "frames"
end

local function CensusFrame(run)
    local index = run.frameIndex
    local frame = run.frameList[index]
    if not frame then
        run.phase, run.frameList = "tables", nil
        return
    end
    run.frameIndex = index + 1
    run.frames = run.frames + 1
    local ok, kind, key, creator = pcall(CensusInspect, frame)
    if not ok or kind == "unreadable" then
        run.unreadable = run.unreadable + 1
    elseif kind == "forbidden" then
        run.forbidden = run.forbidden + 1
    elseif kind == "bucket" then
        run.bucket = run.bucket + 1
        run.histogram[key] = (run.histogram[key] or 0) + 1
        if creator then
            run.creators[creator] = (run.creators[creator] or 0) + 1
        else
            run.unknownCreators = run.unknownCreators + 1
        end
    end
end

local function CensusTableEntry(run)
    if not run.tbl then
        local top = run.top
        if top == 0 then
            run.phase, run.rankIndex, run.key = "rank", 1, nil
            return
        end
        run.tbl, run.owner, run.key = run.stackTables[top], run.stackOwners[top], nil
        run.stackTables[top], run.stackOwners[top] = nil, nil
        run.top = top - 1
        if run.owner ~= SAVED then run.tableCount = run.tableCount + 1 end
    end
    -- A throw means the table changed between steps (its key was removed):
    -- the rest of that table is skipped and counted.
    local ok, key, value = pcall(next, run.tbl, run.key)
    if not ok then
        run.skipped = run.skipped + 1
        run.tbl = nil
    elseif not KE:IsSecretValue(key) and key == nil then
        run.tbl = nil
    else
        run.key = key
        CensusEntry(run, key, value, run.owner)
    end
end

-- One unit of whichever walking or ranking phase the run is in. A `next` that
-- throws while marking libraries or globals is deliberately not caught: it
-- aborts the census, because a partial mark would let the walk enter tables
-- that are not KE's.
local function CensusUnit(run)
    local phase = run.phase
    if phase == "libs" or phase == "globals" then
        local key, value = next(phase == "libs" and run.libraries or _G, run.key)
        run.key = key
        if not KE:IsSecretValue(key) and key == nil then
            run.phase = phase == "libs" and "globals" or "collect"
        elseif not KE:IsSecretValue(value) and type(value) == "table"
            and (phase == "libs" or not IsOwnGlobal(key)) then
            run.seen[value] = true
        end
    elseif phase == "frames" then
        CensusFrame(run)
    elseif phase == "tables" then
        CensusTableEntry(run)
    else
        local source = RANKED[run.rankIndex]
        if not source then
            run.phase = "report"
            return
        end
        local key, count = next(run[source], run.key)
        run.key = key
        if key == nil then
            run.rankIndex = run.rankIndex + 1
        else
            RankInto(run.ranked[source], key, count)
        end
    end
end

-- Entries added to or removed from a live table between steps may be counted
-- or missed; the step cap is what ends a walk that never catches up. The step
-- is counted before any work, so the report step counts itself.
local function CensusSlice(run)
    local started = debugprofilestop()
    run.steps = run.steps + 1
    if run.phase == "report" then
        CensusReport(run, started)
        return
    end
    local framesBefore = run.frames
    if run.phase == "collect" then
        CensusCollect(run)
    else
        local deadline = started + CENSUS_BUDGET_MS
        local units = 0
        while run.phase ~= "report" and run.phase ~= "collect"
            and units < CENSUS_SLICE and debugprofilestop() < deadline do
            CensusUnit(run)
            units = units + 1
        end
    end
    if run.frames > framesBefore then run.frameSteps = run.frameSteps + 1 end
    local ms = debugprofilestop() - started
    if ms > run.slowestMs then run.slowestMs = ms end
    if WALKING[run.phase] and run.steps >= CENSUS_MAX_STEPS then
        run.stoppedAt = run.steps
        run.phase, run.rankIndex, run.key, run.tbl = "rank", 1, nil, nil
    end
end

-- Every exit clears the running flag, so a throw or a failed schedule never
-- leaves the command refusing for the rest of the session.
local function CensusStep(run)
    local ok, err = pcall(CensusSlice, run)
    if ok and run.phase ~= "done" then
        if pcall(C_Timer.After, 0, function() CensusStep(run) end) then return end
        ok, err = false, "could not schedule the next step"
    end
    censusRunning = false
    if not ok then pf("Census aborted: %s", tostring(err)) end
end

local function RunCensus()
    if censusRunning then
        p("Census already running.")
        return
    end
    if InCombatLockdown() then
        p("Census refused in combat.")
        return
    end
    if not pcall(EnumerateFrames) then
        p("Census aborted: the frame list could not be read.")
        return
    end
    local libraries
    local stub = LibStub
    if not KE:IsSecretValue(stub) and type(stub) == "table" then libraries = rawget(stub, "libs") end
    if KE:IsSecretValue(libraries) or type(libraries) ~= "table" then libraries = {} end
    local run = {
        phase = "libs", libraries = libraries,
        frameList = {}, frameIndex = 1, started = debugprofilestop(),
        frames = 0, forbidden = 0, unreadable = 0, bucket = 0,
        histogram = {}, creators = {}, unknownCreators = 0,
        steps = 0, frameSteps = 0, slowestMs = 0,
        top = 0, stackTables = {}, stackOwners = {}, seen = { [_G] = true },
        tableCount = 0, entries = 0, savedEntries = 0, frameRefs = 0, skipped = 0,
        byKey = {}, ranked = { histogram = {}, creators = {}, byKey = {} },
    }
    -- KE.db.sv goes on the stack last, so its walk runs first and marks every
    -- saved table seen before KE.db.profile can reach it.
    CensusPush(run, KE, ROOT)
    CensusPush(run, KE.db and KE.db.sv, SAVED)
    -- Printed before the flag goes up: a throw here must not leave every later
    -- start refused. Nothing runs between the flag and the protected step.
    p("Census started.")
    p("The game will freeze for a few seconds while the frame list is read.")
    censusRunning = true
    CensusStep(run)
end

local function ResetCensus()
    censusFirst, censusPrev = nil, nil
    p("Census baseline cleared.")
end

---------------------------------------------------------------------------------
-- Help
---------------------------------------------------------------------------------

local function PrintHelp()
    p("Usage: /kes profiler <subcommand>")
    p("  on | off          — toggle scriptProfile cvar. /reload required to take effect.")
    p("  status            — show whether profiling is ON/OFF.")
    p("  cpu [N]           — addon rate plus the direct-frame ranking (default 15).")
    p("  top [N]           — top-N addons (any) by RecentAverageTime (default 10).")
    p("  peak              — addon-wide live tick metrics; does not identify callbacks.")
    p("  mem               — KE memory + delta from previous mem call.")
    p("  reset             — reset CPU counters and begin a known sampling window.")
    p("  snap <label>      — capture memory, addon CPU, and named-frame counters.")
    p("  list              — list saved snapshots.")
    p("  diff <a> [b]      — diff snapshots in one reset window (default b = now).")
    p("  clear             — delete all saved snapshots.")
    p("  census            — count frames and KE tables; diff against earlier runs.")
    p("  census reset      — forget this session's census baselines.")
    p("Workflow: /kes profiler on -> /reload -> /kes profiler reset -> exercise UI -> /kes profiler cpu")
end

---------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------

local Profiler = {}

Profiler.CPU_REPORT_SCHEMA = CPU_REPORT_SCHEMA

function Profiler.RunCommand(input)
    input = input or ""
    -- Trim. Don't lowercase the rest — labels may be case-sensitive.
    local cmd, rest = input:match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()

    if cmd == "" or cmd == "help" or cmd == "?" then
        PrintHelp()
    elseif cmd == "on" or cmd == "off" then
        ToggleProfile(cmd)
    elseif cmd == "status" then
        ToggleProfile()
    elseif cmd == "cpu" then
        PrintCpuTop(rest)
    elseif cmd == "top" then
        PrintTopAddOns(rest)
    elseif cmd == "peak" then
        PrintPeak()
    elseif cmd == "mem" or cmd == "memory" then
        PrintMemory()
    elseif cmd == "reset" then
        ResetCpu()
    elseif cmd == "snap" or cmd == "snapshot" then
        if rest == "" then p("Usage: /kes profiler snap <label>"); return end
        TakeSnapshot(rest)
    elseif cmd == "list" then
        ListSnapshots()
    elseif cmd == "diff" then
        local a, b = rest:match("^(%S+)%s*(%S*)$")
        if not a or a == "" then p("Usage: /kes profiler diff <a> [b]"); return end
        DiffSnapshots(a, (b ~= "" and b) or nil)
    elseif cmd == "clear" then
        ClearSnapshots()
    elseif cmd == "census" then
        if rest:lower() == "reset" then
            ResetCensus()
        else
            RunCensus()
        end
    else
        pf("Unknown subcommand '%s'.  Try /kes profiler help.", cmd)
    end
end

-- Expose individual entry points for future GUI hookup
Profiler.PrintCpuTop    = PrintCpuTop
Profiler.PrintTopAddOns = PrintTopAddOns
Profiler.PrintPeak      = PrintPeak
Profiler.PrintMemory    = PrintMemory
Profiler.TakeSnapshot   = TakeSnapshot
Profiler.DiffSnapshots  = DiffSnapshots
Profiler.ListSnapshots  = ListSnapshots
Profiler.ClearSnapshots = ClearSnapshots
Profiler.ResetCpu       = ResetCpu
Profiler.GatherCpuRows  = GatherCpuRows
Profiler.GroupSharedRows = GroupSharedRows
Profiler.GetFooterDisplay = GetFooterDisplay
Profiler.OldestSnapshotLabel = OldestSnapshotLabel
Profiler.CensusKey = CensusKey

KE.Profiler = Profiler
