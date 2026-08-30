-- luacheck: std lua51+busted
local helpers = require("dev.spec._helpers")

local function frame()
    return {
        GetObjectType = function()
            return "Frame"
        end,
    }
end

local function loadProfiler(options)
    options = options or {}

    local printed = {}
    local calls = {}
    local now = options.now or 100
    local addonMs = options.addonMs or 0
    local frameCPU = options.frameCPU or {}
    local modules = options.modules or {}

    _G.print = function(message)
        printed[#printed + 1] = message
    end
    _G.C_CVar = {
        GetCVar = function()
            return "1"
        end,
        SetCVar = function()
        end,
    }
    _G.GetTime = function()
        return now
    end
    _G.time = function()
        return 1800000000
    end
    _G.date = function()
        return "2026-08-29 22:00:00"
    end
    _G.ResetCPUUsage = function()
        calls[#calls + 1] = "reset"
    end
    _G.UpdateAddOnCPUUsage = function()
        calls[#calls + 1] = "update-addon"
    end
    _G.GetAddOnCPUUsage = function()
        calls[#calls + 1] = "addon-total"
        return addonMs
    end
    _G.UpdateAddOnMemoryUsage = function()
    end
    _G.GetAddOnMemoryUsage = function()
        return options.memKB or 0
    end
    _G.GetFrameCPUUsage = function(subject, includeChildren)
        calls[#calls + 1] = includeChildren and "frame-tree" or "frame-self"
        local values = frameCPU[subject] or {}
        if includeChildren then
            return values.treeMs or 0, values.treeCalls or 0
        end
        return values.selfMs or 0, values.selfCalls or 0
    end
    _G.Enum = {
        AddOnProfilerMetric = {
            SessionAverageTime = 0,
            RecentAverageTime = 1,
            EncounterAverageTime = 2,
            LastTime = 3,
            PeakTime = 4,
            CountTimeOver1Ms = 5,
            CountTimeOver5Ms = 6,
            CountTimeOver10Ms = 7,
            CountTimeOver50Ms = 8,
        },
    }
    _G.C_AddOnProfiler = {
        IsEnabled = function()
            return true
        end,
        GetAddOnMetric = function(_, metric)
            if metric == _G.Enum.AddOnProfilerMetric.RecentAverageTime then
                return options.recentMs or 0
            end
            if metric == _G.Enum.AddOnProfilerMetric.PeakTime then
                return options.peakMs or 0
            end
            return 0
        end,
        GetTopKAddOnsForMetric = function()
            return {}
        end,
    }

    _G.KitnEssentials = {
        IterateModules = function()
            calls[#calls + 1] = "enumerate-modules"
            local index = 0
            return function()
                index = index + 1
                local item = modules[index]
                if item then
                    return item.name, item.module
                end
            end
        end,
    }

    local KE = {
        db = {
            global = {},
        },
    }
    helpers.loadModule("Modules/Diagnostics/Profiler.lua", KE)

    return {
        KE = KE,
        profiler = KE.Profiler,
        printed = printed,
        calls = calls,
        setNow = function(value)
            now = value
        end,
        setAddonMs = function(value)
            addonMs = value
        end,
        setFrameCPU = function(subject, values)
            frameCPU[subject] = values
        end,
        clearCalls = function()
            for index = #calls, 1, -1 do
                calls[index] = nil
            end
        end,
    }
end

local function firstCallIndex(calls, expected)
    for index, value in ipairs(calls) do
        if value == expected then
            return index
        end
    end
end

describe("Profiler CPU rows", function()
    before_each(function()
        _G.KE_Alpha = nil
        _G.KE_Beta = nil
        _G.KE_Gamma = nil
        _G.KE_Global = nil
        _G.KE_Zeta = nil
    end)

    it("uses a deterministic name and records self and tree cost", function()
        local subject = frame()
        _G.KE_Zeta = subject
        _G.KE_Alpha = subject

        local state = loadProfiler({
            frameCPU = {
                [subject] = {
                    selfMs = 12,
                    selfCalls = 100,
                    treeMs = 40,
                    treeCalls = 300,
                },
            },
        })
        local rows = state.profiler.GatherCpuRows()

        assert.equals(1, #rows)
        assert.equals(1, rows[1].frameId)
        assert.equals("KE_Alpha", rows[1].name)
        assert.equals(12, rows[1].selfMs)
        assert.equals(100, rows[1].selfCalls)
        assert.equals(40, rows[1].treeMs)
        assert.equals(300, rows[1].treeCalls)
        assert.equals(28, rows[1].childMs)
    end)

    it("prefers a global alias over module and GUI aliases", function()
        local subject = frame()
        _G.KE_Global = subject

        local state = loadProfiler({
            modules = {
                {
                    name = "ModuleAlias",
                    module = { frame = subject },
                },
            },
            frameCPU = {
                [subject] = {
                    selfMs = 1,
                    selfCalls = 1,
                    treeMs = 1,
                    treeCalls = 1,
                },
            },
        })
        state.KE.GUIFrame = subject

        local rows = state.profiler.GatherCpuRows()

        assert.equals(1, #rows)
        assert.equals("KE_Global", rows[1].name)
    end)

    it("prefers a module alias over the GUI fallback", function()
        local subject = frame()
        local state = loadProfiler({
            modules = {
                {
                    name = "ModuleAlias",
                    module = { frame = subject },
                },
            },
            frameCPU = {
                [subject] = {
                    selfMs = 1,
                    selfCalls = 1,
                    treeMs = 1,
                    treeCalls = 1,
                },
            },
        })
        state.KE.GUIFrame = subject

        local rows = state.profiler.GatherCpuRows()

        assert.equals(1, #rows)
        assert.equals("ModuleAlias.frame", rows[1].name)
    end)

    it("captures addon total before enumeration and frame reads on both paths", function()
        local subject = frame()
        local state = loadProfiler({
            addonMs = 20,
            modules = {
                {
                    name = "OrderProbe",
                    module = { frame = subject },
                },
            },
            frameCPU = {
                [subject] = {
                    selfMs = 2,
                    selfCalls = 10,
                    treeMs = 3,
                    treeCalls = 12,
                },
            },
        })

        local function assertSummaryFirst(action)
            state.clearCalls()
            action()

            local addonIndex = firstCallIndex(state.calls, "addon-total")
            local enumerationIndex = firstCallIndex(state.calls, "enumerate-modules")
            local frameIndex = firstCallIndex(state.calls, "frame-self")
            assert.is_number(addonIndex)
            assert.is_number(enumerationIndex)
            assert.is_number(frameIndex)
            assert.is_true(addonIndex < enumerationIndex)
            assert.is_true(enumerationIndex < frameIndex)
        end

        assertSummaryFirst(function()
            state.profiler.RunCommand("cpu 1")
        end)
        assertSummaryFirst(function()
            state.profiler.TakeSnapshot("order")
        end)
    end)

    it("keeps snap and diff callable across the Task 2 row transition", function()
        local subject = frame()
        _G.KE_Alpha = subject
        local state = loadProfiler({
            addonMs = 10,
            frameCPU = {
                [subject] = {
                    selfMs = 1,
                    selfCalls = 10,
                    treeMs = 2,
                    treeCalls = 20,
                },
            },
        })

        state.profiler.TakeSnapshot("compat-before")
        state.setAddonMs(20)
        state.setFrameCPU(subject, {
            selfMs = 3,
            selfCalls = 20,
            treeMs = 5,
            treeCalls = 30,
        })
        state.profiler.TakeSnapshot("compat-after")

        assert.has_no.errors(function()
            state.profiler.DiffSnapshots("compat-before", "compat-after")
        end)
    end)
end)

describe("Profiler CPU report", function()
    before_each(function()
        _G.KE_Alpha = nil
        _G.KE_Beta = nil
        _G.KE_Gamma = nil
        _G.KE_Global = nil
        _G.KE_Zeta = nil
    end)

    it("prints normalized cost for a known reset window", function()
        local state = loadProfiler({
            now = 100,
            addonMs = 255.16,
            recentMs = 0.125,
            peakMs = 2.5,
        })
        state.profiler.ResetCpu()
        state.setNow(130)
        state.profiler.RunCommand("cpu 1")

        local output = table.concat(state.printed, "\n")
        assert.is_truthy(output:find("30.0 sec", 1, true))
        assert.is_truthy(output:find("8.51 ms/sec", 1, true))
        assert.is_truthy(output:find("0.85% of one CPU-second", 1, true))
        assert.is_truthy(output:find("recent avg 0.1250 ms/tick", 1, true))
        assert.is_truthy(output:find("peak since launch 2.5000 ms", 1, true))
    end)

    it("does not invent a rate before KE establishes a reset window", function()
        local state = loadProfiler({
            addonMs = 255.16,
        })
        state.profiler.RunCommand("cpu 1")

        local output = table.concat(state.printed, "\n")
        assert.is_truthy(output:find("sampling duration unknown", 1, true))
        assert.is_nil(output:find("ms/sec", 1, true))
    end)

    it("distinguishes an immediate reset from an unknown window", function()
        local state = loadProfiler({
            now = 100,
            addonMs = 0,
        })
        state.profiler.ResetCpu()
        state.profiler.RunCommand("cpu 1")

        local output = table.concat(state.printed, "\n")
        assert.is_truthy(output:find("0.0 sec", 1, true))
        assert.is_truthy(output:find("exercise the UI", 1, true))
        assert.is_nil(output:find("sampling duration unknown", 1, true))
    end)

    it("labels direct work, overlapping trees, and callback limits", function()
        local subject = frame()
        _G.KE_Alpha = subject
        local state = loadProfiler({
            frameCPU = {
                [subject] = {
                    selfMs = 2,
                    selfCalls = 10,
                    treeMs = 7,
                    treeCalls = 20,
                },
            },
        })
        state.profiler.RunCommand("cpu 1")

        local output = table.concat(state.printed, "\n")
        assert.is_truthy(output:find("direct CPU", 1, true))
        assert.is_truthy(output:find("inclusive CPU", 1, true))
        assert.is_truthy(output:find("Tree rows overlap", 1, true))
        assert.is_truthy(output:find("addon-wide tick metrics only", 1, true))
        assert.is_truthy(output:find("cannot identify which callback", 1, true))
    end)

    it("sorts direct and tree sections independently with name tie breaks", function()
        local alpha = frame()
        local beta = frame()
        local gamma = frame()
        _G.KE_Alpha = alpha
        _G.KE_Beta = beta
        _G.KE_Gamma = gamma

        local state = loadProfiler({
            frameCPU = {
                [alpha] = {
                    selfMs = 5,
                    selfCalls = 5,
                    treeMs = 12,
                    treeCalls = 12,
                },
                [beta] = {
                    selfMs = 5,
                    selfCalls = 5,
                    treeMs = 4,
                    treeCalls = 4,
                },
                [gamma] = {
                    selfMs = 9,
                    selfCalls = 9,
                    treeMs = 9,
                    treeCalls = 9,
                },
            },
        })
        state.profiler.RunCommand("cpu 3")

        local output = table.concat(state.printed, "\n")
        local directStart = assert(output:find("by direct CPU:", 1, true))
        local treeStart = assert(output:find("by inclusive CPU:", directStart, true))
        local directOutput = output:sub(directStart, treeStart - 1)
        local treeOutput = output:sub(treeStart)

        local directGamma = assert(directOutput:find("KE_Gamma", 1, true))
        local directAlpha = assert(directOutput:find("KE_Alpha", 1, true))
        local directBeta = assert(directOutput:find("KE_Beta", 1, true))
        assert.is_true(directGamma < directAlpha)
        assert.is_true(directAlpha < directBeta)

        local treeAlpha = assert(treeOutput:find("KE_Alpha", 1, true))
        local treeGamma = assert(treeOutput:find("KE_Gamma", 1, true))
        local treeBeta = assert(treeOutput:find("KE_Beta", 1, true))
        assert.is_true(treeAlpha < treeGamma)
        assert.is_true(treeGamma < treeBeta)
    end)
end)
