-- ╔══════════════════════════════════════════════════════════╗
-- ║  Profiler.lua                                            ║
-- ║  Module: KE In-Game Profiler                             ║
-- ║  Purpose: Push-button CPU + memory sampling for KE work, ║
-- ║           accessed via /kes profiler <subcommand>.        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local C_CVar_GetCVar     = C_CVar.GetCVar
local C_CVar_SetCVar     = C_CVar.SetCVar
local GetAddOnCPUUsage   = GetAddOnCPUUsage
local GetAddOnMemoryUsage = GetAddOnMemoryUsage
local GetFunctionCPUUsage = GetFunctionCPUUsage
local UpdateAddOnCPUUsage = UpdateAddOnCPUUsage
local UpdateAddOnMemoryUsage = UpdateAddOnMemoryUsage
local ResetCPUUsage      = ResetCPUUsage

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
local math_abs  = math.abs
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
    return tonumber(C_CVar_GetCVar("scriptProfile")) == 1
end

---------------------------------------------------------------------------------
-- Function discovery
---------------------------------------------------------------------------------
-- Walk a single table; collect direct function children only. Avoids deep
-- recursion (which over-collects helpers from libs and ace internals).

local function CollectFunctions(out, prefix, t, skipKey)
    if type(t) ~= "table" then return end
    for k, v in pairs(t) do
        if type(k) == "string" and type(v) == "function" then
            if not skipKey or not skipKey[k] then
                insert(out, { name = prefix .. k, fn = v })
            end
        end
    end
end

-- Methods inherited from AceAddon / AceEvent / AceHook / AceTimer / etc.
-- We don't want to surface these — they're framework noise, not KE code.
local ACE_SKIP = {
    Print = true, Printf = true,
    NewModule = true, GetModule = true, IterateModules = true,
    SetDefaultModuleState = true, SetDefaultModuleLibraries = true,
    SetDefaultModulePrototype = true, SetDefaultModuleStorage = true,
    Enable = true, Disable = true, IsEnabled = true,
    GetName = true, EnableModule = true, DisableModule = true,
    SetEnabledState = true, OnInitialize = true,
    RegisterEvent = true, UnregisterEvent = true,
    UnregisterAllEvents = true, IsEventRegistered = true,
    RegisterMessage = true, UnregisterMessage = true, SendMessage = true,
    UnregisterAllMessages = true, IsMessageRegistered = true,
    Hook = true, SecureHook = true, RawHook = true, Unhook = true,
    UnhookAll = true, IsHooked = true, HookScript = true, SecureHookScript = true,
    RawHookScript = true, SecureRawHook = true,
    ScheduleTimer = true, ScheduleRepeatingTimer = true,
    CancelTimer = true, CancelAllTimers = true, TimeLeft = true,
    Serialize = true, Deserialize = true,
    callbacks = true,
}

local function GatherCpuRows()
    UpdateAddOnCPUUsage()
    local funcs = {}

    -- KE namespace top-level helpers (KE:ApplyFontToText, KE:ColorTextByTheme, ...)
    CollectFunctions(funcs, "KE.", KE)

    -- Each Ace module (module-level methods only)
    if KitnEssentials and KitnEssentials.IterateModules then
        for name, mod in KitnEssentials:IterateModules() do
            CollectFunctions(funcs, name .. ":", mod, ACE_SKIP)
        end
    end

    local rows = {}
    for _, entry in ipairs(funcs) do
        -- false = exclusive (self-time only). Inclusive over-counts when both
        -- a wrapper and its callee are in the namespace.
        local ok, ms, calls = pcall(GetFunctionCPUUsage, entry.fn, false)
        if ok and type(ms) == "number" and ms > 0 then
            insert(rows, { name = entry.name, ms = ms, calls = calls or 0 })
        end
    end
    sort(rows, function(a, b) return a.ms > b.ms end)
    return rows
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
        local on = ProfilingEnabled()
        pf("scriptProfile is currently %s.  Use /kes profiler on or /kes profiler off.", on and "ON" or "OFF")
    end
end

local function PrintCpuTop(arg)
    if not ProfilingEnabled() then
        p("scriptProfile is OFF.  Run /kes profiler on then /reload to enable CPU profiling.")
        return
    end
    local n = tonumber(arg) or 15
    local rows = GatherCpuRows()
    if #rows == 0 then
        p("No CPU samples yet.  Try /kes profiler reset, exercise the UI for a bit, then /kes profiler cpu again.")
        return
    end
    UpdateAddOnCPUUsage()
    local addonMs = GetAddOnCPUUsage("KitnEssentials") or 0
    pf("Top %d KE functions by self-ms (KitnEssentials total: %.2f ms):", n, addonMs)
    for i = 1, math_min(n, #rows) do
        local r = rows[i]
        local perCall = (r.calls > 0) and (r.ms / r.calls) or 0
        pf("  %2d. %.2f ms  (calls=%d, %.4f ms/call)  %s",
            i, r.ms, r.calls, perCall, r.name)
    end
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
    p("CPU counters reset.  Exercise the UI, then /kes profiler cpu.")
end

local function CaptureSnapshot(label)
    UpdateAddOnMemoryUsage()
    UpdateAddOnCPUUsage()
    local snap = {
        label = label,
        time  = time(),
        date  = date("%Y-%m-%d %H:%M:%S"),
        memKB = GetAddOnMemoryUsage("KitnEssentials") or 0,
        cpuMS = GetAddOnCPUUsage("KitnEssentials") or 0,
        functions = {},
    }
    if ProfilingEnabled() then
        local rows = GatherCpuRows()
        for i = 1, math_min(50, #rows) do
            local r = rows[i]
            snap.functions[#snap.functions + 1] = { name = r.name, ms = r.ms, calls = r.calls }
        end
    end
    return snap
end

local function TakeSnapshot(label)
    local snap = CaptureSnapshot(label)
    ResolveDB().snapshots[label] = snap
    pf("Snapshot saved: %s  (mem=%.1f KB, cpu=%.2f ms, fns=%d)",
        label, snap.memKB, snap.cpuMS, #snap.functions)
end

local function ListSnapshots()
    local db = ResolveDB()
    local names = {}
    for k in pairs(db.snapshots) do insert(names, k) end
    sort(names)
    if #names == 0 then
        p("No snapshots saved.")
        return
    end
    pf("Snapshots (%d):", #names)
    for _, k in ipairs(names) do
        local s = db.snapshots[k]
        pf("  [%s]  mem=%.1f KB  cpu=%.2f ms  @%s",
            k, s.memKB or 0, s.cpuMS or 0, s.date or "?")
    end
end

local function SnapshotByName(name)
    if name == "now" then
        return CaptureSnapshot("now")
    end
    return ResolveDB().snapshots[name]
end

local function DiffSnapshots(aName, bName)
    bName = bName or "now"
    local a = SnapshotByName(aName)
    if not a then pf("Snapshot '%s' not found.", aName); return end
    local b = SnapshotByName(bName)
    if not b then pf("Snapshot '%s' not found.", bName); return end

    pf("Diff: '%s' -> '%s'", aName, bName)
    pf("  Memory: %.1f KB -> %.1f KB  (%+.1f KB)",
        a.memKB, b.memKB, b.memKB - a.memKB)
    pf("  CPU:    %.2f ms -> %.2f ms  (%+.2f ms)",
        a.cpuMS, b.cpuMS, b.cpuMS - a.cpuMS)

    local aMap = {}
    for _, f in ipairs(a.functions or {}) do aMap[f.name] = f end
    local diffs = {}
    for _, f in ipairs(b.functions or {}) do
        local af = aMap[f.name]
        local prev = af and af.ms or 0
        local d = f.ms - prev
        if math_abs(d) > 0.01 then
            insert(diffs, { name = f.name, prev = prev, now = f.ms, d = d })
        end
    end
    sort(diffs, function(x, y) return x.d > y.d end)
    if #diffs == 0 then return end
    pf("  Top function deltas:")
    for i = 1, math_min(10, #diffs) do
        local d = diffs[i]
        pf("    %+.2f ms  (%.2f -> %.2f)  %s", d.d, d.prev, d.now, d.name)
    end
end

local function ClearSnapshots()
    local db = ResolveDB()
    db.snapshots = {}
    p("Snapshots cleared.")
end

---------------------------------------------------------------------------------
-- Help
---------------------------------------------------------------------------------

local function PrintHelp()
    p("Usage: /kes profiler <subcommand>")
    p("  on | off          — toggle scriptProfile cvar (CPU sampling). /reload required.")
    p("  status            — show whether scriptProfile is ON/OFF.")
    p("  cpu [N]           — top-N hottest KE functions by self-ms (default 15).")
    p("  mem               — KE memory + delta from previous mem call.")
    p("  reset             — reset CPU counters (fresh sampling window).")
    p("  snap <label>      — capture a labeled snapshot to KitnEssentialsDB.")
    p("  list              — list saved snapshots.")
    p("  diff <a> [b]      — diff snapshot 'a' against 'b' (default b = now).")
    p("  clear             — delete all saved snapshots.")
    p("Workflow: /kes profiler on -> /reload -> /kes profiler reset -> exercise UI -> /kes profiler cpu")
end

---------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------

local Profiler = {}

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
Profiler.PrintMemory    = PrintMemory
Profiler.TakeSnapshot   = TakeSnapshot
Profiler.DiffSnapshots  = DiffSnapshots
Profiler.ListSnapshots  = ListSnapshots
Profiler.ClearSnapshots = ClearSnapshots
Profiler.ResetCpu       = ResetCpu
Profiler.GatherCpuRows  = GatherCpuRows

KE.Profiler = Profiler
