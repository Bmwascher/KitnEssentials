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

local print     = print
local format    = string.format
local sort      = table.sort
local insert    = table.insert
local pairs     = pairs
local ipairs    = ipairs
local type      = type
local pcall     = pcall
local tonumber  = tonumber
local tostring  = tostring
local math_min  = math.min
local math_max  = math.max
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
-- This developer profiler intentionally reports per-frame CPU; function-level
-- attribution is out of scope. We walk _G for KE-named globals + Ace modules'
-- .frame attribute and sample direct and inclusive CPU for each discovered frame.
--
-- Inclusive (includeChildren=true) over-counts when both a parent and its child
-- frame are reported separately, but it reveals the cost folded into a module's
-- bars and icons.

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
                    selfCalls = selfCalls or 0,
                    treeMs = treeMs,
                    treeCalls = treeCalls or 0,
                    childMs = math_max(treeMs - selfMs, 0),
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

local function SortedRows(rows, key)
    local copy = {}
    for _, row in ipairs(rows) do
        copy[#copy + 1] = row
    end
    sort(copy, function(a, b)
        if a[key] ~= b[key] then
            return a[key] > b[key]
        end
        return a.name < b.name
    end)
    return copy
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
        p("Frame rankings omit timer and plain Lua callback attribution. /kes profiler peak reports addon-wide tick metrics only; it cannot identify which callback caused a spike.")
        return
    end

    local selfRows = SortedRows(rows, "selfMs")
    pf("Top %d named KE frames by direct CPU:", n)
    local selfRank = 0
    for _, row in ipairs(selfRows) do
        if row.selfMs > 0 and selfRank < n then
            selfRank = selfRank + 1
            local perCall = row.selfCalls > 0 and row.selfMs / row.selfCalls or 0
            pf("  %2d. %.2f ms (calls=%d, %.4f ms/call) %s",
                selfRank, row.selfMs, row.selfCalls, perCall, row.name)
        end
    end
    if selfRank == 0 then
        p("  No direct frame work recorded.")
    end

    local treeRows = SortedRows(rows, "treeMs")
    pf("Top %d named KE frame trees by inclusive CPU:", n)
    for index = 1, math_min(n, #treeRows) do
        local row = treeRows[index]
        pf("  %2d. %.2f ms tree (self=%.2f, descendants=%.2f, calls=%d) %s",
            index, row.treeMs, row.selfMs, row.childMs, row.treeCalls, row.name)
    end
    p("Tree rows overlap and may include non-KE descendant work; do not add them or compare them directly with addon total.")
    p("Frame rankings omit timer and plain Lua callback attribution. /kes profiler peak reports addon-wide tick metrics only; it cannot identify which callback caused a spike.")
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

local function TakeSnapshot(label)
    local snap = CaptureSnapshot(label)
    ResolveDB().snapshots[label] = snap
    pf("Snapshot saved: %s (mem=%.1f KB, cpu=%.2f ms, frames=%d)",
        label, snap.memKB, snap.cpuMS, SnapshotFrameCount(snap))
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
        if old and ((row.selfMs or 0) < (old.selfMs or 0)
            or (row.selfCalls or 0) < (old.selfCalls or 0)
            or (row.treeMs or 0) < (old.treeMs or 0)
            or (row.treeCalls or 0) < (old.treeCalls or 0)) then
            return nil, "counter"
        end
    end
    return beforeById
end

local function PositiveFrameDeltas(beforeById, b, key)
    local deltas = {}
    local newlyObserved = 0
    for _, row in ipairs(b.frames or {}) do
        local old = beforeById[row.frameId]
        if not old then
            newlyObserved = newlyObserved + 1
        else
            local prior = old[key] or 0
            local current = row[key] or 0
            local delta = current - prior
            if delta > 0.01 then
                deltas[#deltas + 1] = {
                    name = row.name,
                    delta = delta,
                    prior = prior,
                    current = current,
                }
            end
        end
    end
    sort(deltas, function(x, y)
        if x.delta ~= y.delta then
            return x.delta > y.delta
        end
        return x.name < y.name
    end)
    return deltas, newlyObserved
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

    local selfDeltas, newlyObserved = PositiveFrameDeltas(beforeById, b, "selfMs")
    if newlyObserved > 0 then
        pf("  %d newly observed frame(s) omitted from frame deltas.", newlyObserved)
    end
    if #selfDeltas > 0 then
        p("  Top direct-frame deltas:")
        for index = 1, math_min(10, #selfDeltas) do
            local delta = selfDeltas[index]
            pf("    %+.2f ms (%.2f -> %.2f) %s",
                delta.delta, delta.prior, delta.current, delta.name)
        end
    end

    local treeDeltas = PositiveFrameDeltas(beforeById, b, "treeMs")
    if #treeDeltas > 0 then
        p("  Top inclusive frame-tree deltas:")
        for index = 1, math_min(10, #treeDeltas) do
            local delta = treeDeltas[index]
            pf("    %+.2f ms (%.2f -> %.2f) %s",
                delta.delta, delta.prior, delta.current, delta.name)
        end
        p("  Tree deltas overlap; do not add them together.")
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
-- Help
---------------------------------------------------------------------------------

local function PrintHelp()
    p("Usage: /kes profiler <subcommand>")
    p("  on | off          — toggle scriptProfile cvar. /reload required to take effect.")
    p("  status            — show whether profiling is ON/OFF.")
    p("  cpu [N]           — addon rate plus direct-frame and inclusive-tree rankings (default 15).")
    p("  top [N]           — top-N addons (any) by RecentAverageTime (default 10).")
    p("  peak              — addon-wide live tick metrics; does not identify callbacks.")
    p("  mem               — KE memory + delta from previous mem call.")
    p("  reset             — reset CPU counters and begin a known sampling window.")
    p("  snap <label>      — capture memory, addon CPU, and named-frame counters.")
    p("  list              — list saved snapshots.")
    p("  diff <a> [b]      — diff snapshots in one reset window (default b = now).")
    p("  clear             — delete all saved snapshots.")
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

KE.Profiler = Profiler
