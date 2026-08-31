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

    local lifecycle = {}
    local eventFrames = {}
    local popupShows = {}
    local scriptProfile = tostring(options.scriptProfile == nil and 1 or options.scriptProfile)
    local inCombat = options.inCombat == true
    local fps = options.fps

    _G.print = function(message)
        printed[#printed + 1] = message
    end
    _G.C_CVar = {
        -- Reads are recorded, not just writes. The regen handler must unregister
        -- and clear its latch BEFORE it reads the CVar; without a read entry in
        -- lifecycle that ordering is unobservable, and a handler that reads first
        -- and tears down afterwards passes every other assertion here.
        GetCVar = function(name)
            lifecycle[#lifecycle + 1] = "cvar-read:" .. name
            if name == "scriptProfile" then return scriptProfile end
        end,
        SetCVar = function(name, value)
            lifecycle[#lifecycle + 1] = "cvar:" .. name .. "=" .. tostring(value)
            if name == "scriptProfile" then scriptProfile = tostring(value) end
        end,
    }

    if options.fpsAPIAvailable == false then
        _G.GetFramerate = nil
    else
        _G.GetFramerate = function()
            if options.failOnFramerateRead then error("unexpected framerate read") end
            return fps
        end
    end

    _G.InCombatLockdown = function()
        return inCombat
    end
    _G.ReloadUI = function()
        lifecycle[#lifecycle + 1] = "reload"
    end

    _G.CreateFrame = function()
        local scripts = {}
        local registered = {}
        local subject = {}

        function subject:SetScript(scriptName, callback)
            scripts[scriptName] = callback
        end
        function subject:RegisterEvent(event)
            registered[event] = true
            lifecycle[#lifecycle + 1] = "register:" .. event
        end
        function subject:UnregisterEvent(event)
            registered[event] = nil
            lifecycle[#lifecycle + 1] = "unregister:" .. event
        end
        function subject:IsEventRegistered(event)
            return registered[event] == true
        end
        function subject:Fire(event)
            local callback = scripts.OnEvent
            if registered[event] and callback then callback(subject, event) end
        end
        -- Delivers to OnEvent regardless of registration. Without this the
        -- pending-popup latch is unobservable: once the handler unregisters, Fire
        -- suppresses every later delivery, so a build that never clears the latch
        -- is indistinguishable from one that does.
        function subject:FireRaw(event)
            local callback = scripts.OnEvent
            if callback then callback(subject, event) end
        end

        eventFrames[#eventFrames + 1] = subject
        return subject
    end

    local popupDialogs
    if options.popupAPIsAvailable ~= false then
        popupDialogs = {}
    end
    _G.StaticPopupDialogs = popupDialogs
    if popupDialogs then
        _G.StaticPopup_Show = function(key)
            popupShows[#popupShows + 1] = key
            lifecycle[#lifecycle + 1] = "popup:" .. key
        end
    else
        _G.StaticPopup_Show = nil
    end

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
                if options.recentMetricUnavailable then return nil end
                if options.recentMs ~= nil then return options.recentMs end
                return 0
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
        lifecycle = lifecycle,
        popupShows = popupShows,
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
        fireEvent = function(event)
            for _, eventFrame in ipairs(eventFrames) do
                eventFrame:Fire(event)
            end
        end,
        fireEventRaw = function(event)
            for _, eventFrame in ipairs(eventFrames) do
                eventFrame:FireRaw(event)
            end
        end,
        isEventRegistered = function(event)
            for _, eventFrame in ipairs(eventFrames) do
                if eventFrame:IsEventRegistered(event) then return true end
            end
            return false
        end,
        setCombat = function(value)
            inCombat = value
        end,
        setScriptProfile = function(value)
            scriptProfile = tostring(value)
        end,
        getPopup = function(key)
            return popupDialogs and popupDialogs[key]
        end,
        clearLifecycle = function()
            for index = #lifecycle, 1, -1 do
                lifecycle[index] = nil
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

    it("explains callback attribution when addon CPU has no frame rows", function()
        local state = loadProfiler({
            addonMs = 42,
        })
        state.profiler.RunCommand("cpu 1")

        local output = table.concat(state.printed, "\n")
        assert.is_truthy(output:find("No frame CPU samples yet", 1, true))
        assert.is_truthy(output:find("Frame rankings omit timer and plain Lua callback attribution", 1, true))
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

describe("Profiler snapshots", function()
    before_each(function()
        _G.KE_Alpha = nil
        _G.KE_Beta = nil
        _G.KE_Gamma = nil
        _G.KE_Global = nil
        _G.KE_Zeta = nil
    end)

    it("reports CPU and frame deltas inside one known reset window", function()
        local subject = frame()
        _G.KE_Alpha = subject
        local state = loadProfiler({
            now = 100,
            addonMs = 10,
            memKB = 100,
            frameCPU = {
                [subject] = {
                    selfMs = 1,
                    selfCalls = 10,
                    treeMs = 2,
                    treeCalls = 20,
                },
            },
        })

        state.profiler.ResetCpu()
        state.profiler.TakeSnapshot("before")
        state.setNow(110)
        state.setAddonMs(30)
        state.setFrameCPU(subject, {
            selfMs = 5,
            selfCalls = 30,
            treeMs = 9,
            treeCalls = 50,
        })
        state.profiler.TakeSnapshot("after")
        state.profiler.DiffSnapshots("before", "after")

        local output = table.concat(state.printed, "\n")
        assert.is_truthy(output:find("+20.00 ms over 10.0 sec", 1, true))
        assert.is_truthy(output:find("2.00 ms/sec", 1, true))
        assert.is_truthy(output:find("+4.00 ms", 1, true))
        assert.is_truthy(output:find("+7.00 ms", 1, true))
    end)

    it("keeps one frame interval when a preferred alias is added", function()
        local subject = frame()
        _G.KE_Zeta = subject
        local state = loadProfiler({
            now = 100,
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

        state.profiler.ResetCpu()
        state.profiler.TakeSnapshot("before")
        _G.KE_Alpha = subject
        state.setNow(110)
        state.setAddonMs(20)
        state.setFrameCPU(subject, {
            selfMs = 5,
            selfCalls = 30,
            treeMs = 9,
            treeCalls = 50,
        })
        state.profiler.TakeSnapshot("after")
        state.profiler.DiffSnapshots("before", "after")

        local snapshots = state.KE.db.global.profiler.snapshots
        assert.equals(snapshots.before.frames[1].frameId,
            snapshots.after.frames[1].frameId)
        local output = table.concat(state.printed, "\n")
        assert.is_truthy(output:find("+4.00 ms", 1, true))
        assert.is_truthy(output:find("KE_Alpha", 1, true))
        assert.is_nil(output:find("Frame deltas unavailable", 1, true))
    end)

    it("omits a frame first observed in the later snapshot", function()
        local alpha = frame()
        local beta = frame()
        _G.KE_Alpha = alpha
        local state = loadProfiler({
            now = 100,
            addonMs = 10,
            frameCPU = {
                [alpha] = {
                    selfMs = 1,
                    selfCalls = 10,
                    treeMs = 2,
                    treeCalls = 20,
                },
                [beta] = {
                    selfMs = 100,
                    selfCalls = 100,
                    treeMs = 120,
                    treeCalls = 120,
                },
            },
        })

        state.profiler.ResetCpu()
        state.profiler.TakeSnapshot("before")
        _G.KE_Beta = beta
        state.setNow(110)
        state.setAddonMs(20)
        state.setFrameCPU(alpha, {
            selfMs = 3,
            selfCalls = 20,
            treeMs = 5,
            treeCalls = 30,
        })
        state.profiler.TakeSnapshot("after")
        state.profiler.DiffSnapshots("before", "after")

        local output = table.concat(state.printed, "\n")
        assert.is_truthy(output:find("1 newly observed frame", 1, true))
        assert.is_nil(output:find("KE_Beta", 1, true))
    end)

    it("refuses a same-name replacement even when its counters are higher", function()
        local original = frame()
        local replacement = frame()
        _G.KE_Alpha = original
        local state = loadProfiler({
            now = 100,
            addonMs = 10,
            frameCPU = {
                [original] = {
                    selfMs = 5,
                    selfCalls = 20,
                    treeMs = 8,
                    treeCalls = 30,
                },
                [replacement] = {
                    selfMs = 50,
                    selfCalls = 200,
                    treeMs = 80,
                    treeCalls = 300,
                },
            },
        })

        state.profiler.ResetCpu()
        state.profiler.TakeSnapshot("before")
        _G.KE_Alpha = replacement
        state.setNow(110)
        state.setAddonMs(20)
        state.profiler.TakeSnapshot("after")
        state.profiler.DiffSnapshots("before", "after")

        local output = table.concat(state.printed, "\n")
        assert.is_truthy(output:find("+10.00 ms over 10.0 sec", 1, true))
        assert.is_truthy(output:find("different frame object", 1, true))
    end)

    it("uses distinct window ids for two resets at the same clock", function()
        local state = loadProfiler({
            now = 100,
            addonMs = 10,
            memKB = 100,
        })

        state.profiler.ResetCpu()
        state.profiler.TakeSnapshot("before")
        state.profiler.ResetCpu()
        state.setAddonMs(5)
        state.setNow(110)
        state.profiler.TakeSnapshot("after")
        state.profiler.DiffSnapshots("before", "after")

        local snapshots = state.KE.db.global.profiler.snapshots
        assert.not_equals(snapshots.before.cpuWindowId,
            snapshots.after.cpuWindowId)
        local output = table.concat(state.printed, "\n")
        assert.is_truthy(output:find("CPU/frame deltas unavailable", 1, true))
    end)

    it("keeps legacy snapshots memory-diffable without CPU claims", function()
        local state = loadProfiler()
        state.KE.db.global.profiler = {
            lastMemKB = 0,
            snapshots = {
                before = {
                    memKB = 100,
                    cpuMS = 50,
                    functions = {
                        { name = "KE_Legacy", ms = 25, calls = 10 },
                    },
                },
                after = {
                    memKB = 125,
                    cpuMS = 60,
                    functions = {
                        { name = "KE_Legacy", ms = 30, calls = 12 },
                    },
                },
            },
        }

        state.profiler.DiffSnapshots("before", "after")

        local output = table.concat(state.printed, "\n")
        assert.is_truthy(output:find("+25.0 KB", 1, true))
        assert.is_truthy(output:find("CPU/frame deltas unavailable", 1, true))
    end)

    it("refuses same-window CPU deltas when addon CPU decreases", function()
        local state = loadProfiler({
            now = 100,
            addonMs = 10,
        })

        state.profiler.ResetCpu()
        state.profiler.TakeSnapshot("before")
        state.setNow(110)
        state.setAddonMs(5)
        state.profiler.TakeSnapshot("after")
        state.profiler.DiffSnapshots("before", "after")

        local output = table.concat(state.printed, "\n")
        assert.is_truthy(output:find("CPU/frame deltas unavailable", 1, true))
        assert.is_nil(output:find("CPU: +", 1, true))
    end)

    it("refuses reverse chronology with nondecreasing compared CPU", function()
        local state = loadProfiler({
            now = 100,
            addonMs = 10,
        })

        state.profiler.ResetCpu()
        state.profiler.TakeSnapshot("early")
        state.setNow(110)
        state.profiler.TakeSnapshot("late")
        state.profiler.DiffSnapshots("late", "early")

        local output = table.concat(state.printed, "\n")
        assert.is_truthy(output:find("CPU/frame deltas unavailable", 1, true))
    end)

    it("refuses frame deltas for a self-only counter decrease", function()
        local subject = frame()
        _G.KE_Alpha = subject
        local state = loadProfiler({
            now = 100,
            addonMs = 10,
            frameCPU = {
                [subject] = {
                    selfMs = 5,
                    selfCalls = 20,
                    treeMs = 8,
                    treeCalls = 30,
                },
            },
        })

        state.profiler.ResetCpu()
        state.profiler.TakeSnapshot("before")
        state.setNow(110)
        state.setAddonMs(20)
        state.setFrameCPU(subject, {
            selfMs = 4,
            selfCalls = 21,
            treeMs = 9,
            treeCalls = 31,
        })
        state.profiler.TakeSnapshot("after")
        state.profiler.DiffSnapshots("before", "after")

        local output = table.concat(state.printed, "\n")
        assert.is_truthy(output:find("+10.00 ms over 10.0 sec", 1, true))
        assert.is_truthy(output:find("Frame deltas unavailable", 1, true))
    end)

    it("refuses frame deltas for a tree-only counter decrease", function()
        local subject = frame()
        _G.KE_Alpha = subject
        local state = loadProfiler({
            now = 100,
            addonMs = 10,
            frameCPU = {
                [subject] = {
                    selfMs = 5,
                    selfCalls = 20,
                    treeMs = 8,
                    treeCalls = 30,
                },
            },
        })

        state.profiler.ResetCpu()
        state.profiler.TakeSnapshot("before")
        state.setNow(110)
        state.setAddonMs(20)
        state.setFrameCPU(subject, {
            selfMs = 6,
            selfCalls = 21,
            treeMs = 7,
            treeCalls = 31,
        })
        state.profiler.TakeSnapshot("after")
        state.profiler.DiffSnapshots("before", "after")

        local output = table.concat(state.printed, "\n")
        assert.is_truthy(output:find("+10.00 ms over 10.0 sec", 1, true))
        assert.is_truthy(output:find("Frame deltas unavailable", 1, true))
    end)

    it("refuses frame deltas for a self-call-only counter decrease", function()
        local subject = frame()
        _G.KE_Alpha = subject
        local state = loadProfiler({
            now = 100,
            addonMs = 10,
            frameCPU = {
                [subject] = {
                    selfMs = 5,
                    selfCalls = 20,
                    treeMs = 8,
                    treeCalls = 30,
                },
            },
        })

        state.profiler.ResetCpu()
        state.profiler.TakeSnapshot("before")
        state.setNow(110)
        state.setAddonMs(20)
        state.setFrameCPU(subject, {
            selfMs = 6,
            selfCalls = 19,
            treeMs = 9,
            treeCalls = 31,
        })
        state.profiler.TakeSnapshot("after")
        state.profiler.DiffSnapshots("before", "after")

        local output = table.concat(state.printed, "\n")
        assert.is_truthy(output:find("+10.00 ms over 10.0 sec", 1, true))
        assert.is_truthy(output:find("Frame deltas unavailable", 1, true))
    end)

    it("refuses frame deltas for a tree-call-only counter decrease", function()
        local subject = frame()
        _G.KE_Alpha = subject
        local state = loadProfiler({
            now = 100,
            addonMs = 10,
            frameCPU = {
                [subject] = {
                    selfMs = 5,
                    selfCalls = 20,
                    treeMs = 8,
                    treeCalls = 30,
                },
            },
        })

        state.profiler.ResetCpu()
        state.profiler.TakeSnapshot("before")
        state.setNow(110)
        state.setAddonMs(20)
        state.setFrameCPU(subject, {
            selfMs = 6,
            selfCalls = 21,
            treeMs = 9,
            treeCalls = 29,
        })
        state.profiler.TakeSnapshot("after")
        state.profiler.DiffSnapshots("before", "after")

        local output = table.concat(state.printed, "\n")
        assert.is_truthy(output:find("+10.00 ms over 10.0 sec", 1, true))
        assert.is_truthy(output:find("Frame deltas unavailable", 1, true))
    end)
end)

describe("Profiler footer display", function()
    it("keeps the same always-on metric while latching detailed mode per load", function()
        local enabled = loadProfiler({ scriptProfile = 1, recentMs = 0.0011, fps = 120 })
        local disabled = loadProfiler({ scriptProfile = 0, recentMs = 0.0011, fps = 120 })

        local enabledText, enabledDetailed = enabled.profiler.GetFooterDisplay()
        local disabledText, disabledDetailed = disabled.profiler.GetFooterDisplay()

        assert.are.equal("CPU: 0.0011 MS (~0.01%)", enabledText)
        assert.are.equal(enabledText, disabledText)
        assert.is_true(enabledDetailed)
        assert.is_false(disabledDetailed)
    end)

    it("does not change the detailed-state latch until a fresh module load", function()
        local enabled = loadProfiler({ scriptProfile = 1, recentMs = 0, fps = 60 })
        enabled.profiler.RunCommand("off")
        local _, stillEnabled = enabled.profiler.GetFooterDisplay()

        local disabled = loadProfiler({ scriptProfile = 0, recentMs = 0, fps = 60 })
        disabled.profiler.RunCommand("on")
        local _, stillDisabled = disabled.profiler.GetFooterDisplay()

        local reloadedOff = loadProfiler({ scriptProfile = 0, recentMs = 0, fps = 60 })
        local reloadedOn = loadProfiler({ scriptProfile = 1, recentMs = 0, fps = 60 })
        local _, offDetailed = reloadedOff.profiler.GetFooterDisplay()
        local _, onDetailed = reloadedOn.profiler.GetFooterDisplay()

        assert.is_true(stillEnabled)
        assert.is_false(stillDisabled)
        assert.is_false(offDetailed)
        assert.is_true(onDetailed)
    end)

    it("formats four decimals and every adaptive percentage branch", function()
        local cases = {
            { recentMs = 0.0001, fps = 60, expected = "CPU: 0.0001 MS (<0.01%)" },
            { recentMs = 0.0011, fps = 120, expected = "CPU: 0.0011 MS (~0.01%)" },
            { recentMs = 0.0110, fps = 120, expected = "CPU: 0.0110 MS (~0.1%)" },
        }

        for _, case in ipairs(cases) do
            local state = loadProfiler(case)
            local cpuText = state.profiler.GetFooterDisplay()
            assert.are.equal(case.expected, cpuText)
        end
    end)

    it("returns unavailable without reading framerate when the metric is absent", function()
        local state = loadProfiler({
            scriptProfile = 1,
            recentMetricUnavailable = true,
            failOnFramerateRead = true,
        })

        local cpuText, detailed = state.profiler.GetFooterDisplay()
        assert.are.equal("CPU: unavailable", cpuText)
        assert.is_true(detailed)
    end)

    it("retains milliseconds and omits only percentage for missing or nonpositive fps", function()
        local missing = loadProfiler({ recentMs = 0.0011, fpsAPIAvailable = false })
        local zero = loadProfiler({ recentMs = 0.0011, fps = 0 })
        local negative = loadProfiler({ recentMs = 0.0011, fps = -1 })

        assert.are.equal("CPU: 0.0011 MS", missing.profiler.GetFooterDisplay())
        assert.are.equal("CPU: 0.0011 MS", zero.profiler.GetFooterDisplay())
        assert.are.equal("CPU: 0.0011 MS", negative.profiler.GetFooterDisplay())
    end)
end)

local function countContaining(values, needle)
    local count = 0
    for _, value in ipairs(values) do
        if value:find(needle, 1, true) then count = count + 1 end
    end
    return count
end

local function indexOf(values, expected)
    for index, value in ipairs(values) do
        if value == expected then return index end
    end
end

describe("Profiler reload warning", function()
    it("does nothing on PLAYER_LOGIN when detailed profiling was inactive at load", function()
        local state = loadProfiler({ scriptProfile = 0 })
        state.clearLifecycle()
        state.fireEvent("PLAYER_LOGIN")

        assert.are.equal(0, #state.printed)
        assert.are.equal(0, #state.popupShows)
        assert.is_false(state.isEventRegistered("PLAYER_LOGIN"))
    end)

    it("prints and shows exactly one warning when detailed profiling is active", function()
        local state = loadProfiler({ scriptProfile = 1 })
        state.clearLifecycle()
        state.fireEvent("PLAYER_LOGIN")
        state.fireEvent("PLAYER_LOGIN")

        assert.are.equal(1, countContaining(state.printed, "CPU profiling is enabled and reduces FPS."))
        assert.same({ "KE_PROFILER_ENABLED" }, state.popupShows)
        assert.is_false(state.isEventRegistered("PLAYER_LOGIN"))
    end)

    it("keeps the chat warning as the fallback when popup APIs are unavailable", function()
        local state = loadProfiler({ scriptProfile = 1, popupAPIsAvailable = false })
        state.clearLifecycle()
        state.fireEvent("PLAYER_LOGIN")

        assert.are.equal(1, countContaining(state.printed, "CPU profiling is enabled and reduces FPS."))
        assert.are.equal(0, #state.popupShows)
    end)

    it("sets scriptProfile to zero before reloading from Disable and Reload", function()
        local state = loadProfiler({ scriptProfile = 1 })
        state.fireEvent("PLAYER_LOGIN")
        local popup = state.getPopup("KE_PROFILER_ENABLED")
        assert.is_table(popup)
        assert.are.equal("Disable & Reload", popup.button1)
        assert.are.equal("Keep Enabled", popup.button2)

        state.clearLifecycle()
        popup.OnAccept()

        local cvarIndex = indexOf(state.lifecycle, "cvar:scriptProfile=0")
        local reloadIndex = indexOf(state.lifecycle, "reload")
        assert.is_number(cvarIndex)
        assert.is_number(reloadIndex)
        assert.is_true(cvarIndex < reloadIndex)
    end)

    it("wires no state-changing hook to Keep Enabled or to dismissal", function()
        local state = loadProfiler({ scriptProfile = 1 })
        state.fireEvent("PLAYER_LOGIN")
        local popup = state.getPopup("KE_PROFILER_ENABLED")

        -- Blizzard dispatches button 2 through OnCancel or OnButton2, and
        -- fires OnHide on dismissal. Keep Enabled is a one-load no-op, so all
        -- three must be absent; asserting only OnCancel would pass against an
        -- implementation that moved the work to either of the others.
        assert.is_nil(popup.OnCancel)
        assert.is_nil(popup.OnButton2)
        assert.is_nil(popup.OnHide)
        assert.is_function(popup.OnAccept)
    end)

    it("prints immediately in combat and tears down before one deferred popup", function()
        local state = loadProfiler({ scriptProfile = 1, inCombat = true })
        state.clearLifecycle()
        state.fireEvent("PLAYER_LOGIN")

        assert.are.equal(1, countContaining(state.printed, "CPU profiling is enabled and reduces FPS."))
        assert.are.equal(0, #state.popupShows)
        assert.is_true(state.isEventRegistered("PLAYER_REGEN_ENABLED"))

        state.setCombat(false)
        state.clearLifecycle()
        state.fireEvent("PLAYER_REGEN_ENABLED")

        local unregisterIndex = indexOf(state.lifecycle, "unregister:PLAYER_REGEN_ENABLED")
        local cvarReadIndex = indexOf(state.lifecycle, "cvar-read:scriptProfile")
        local popupIndex = indexOf(state.lifecycle, "popup:KE_PROFILER_ENABLED")
        assert.is_number(unregisterIndex)
        assert.is_number(cvarReadIndex)
        assert.is_number(popupIndex)
        assert.is_true(unregisterIndex < cvarReadIndex)
        assert.is_true(cvarReadIndex < popupIndex)
        assert.is_false(state.isEventRegistered("PLAYER_REGEN_ENABLED"))
        assert.are.equal(1, #state.popupShows)
        assert.are.equal(1, countContaining(state.printed, "CPU profiling is enabled and reduces FPS."))

        state.fireEvent("PLAYER_REGEN_ENABLED")
        assert.are.equal(1, #state.popupShows)

        -- Raw delivery bypasses the unregister, so this is the only assertion
        -- that can fail when the handler forgets to clear its pending latch:
        -- a still-true latch re-enters the regen path and shows a second popup.
        state.fireEventRaw("PLAYER_REGEN_ENABLED")
        assert.are.equal(1, #state.popupShows)
    end)

    it("tears down and suppresses a deferred popup when the CVar was turned off", function()
        local state = loadProfiler({ scriptProfile = 1, inCombat = true })
        state.fireEvent("PLAYER_LOGIN")
        state.setScriptProfile(0)
        state.setCombat(false)
        state.clearLifecycle()
        state.fireEvent("PLAYER_REGEN_ENABLED")

        -- Exact sequence, not a membership check: the unregister must precede
        -- the CVar read, and nothing else may run on this path.
        assert.same({ "unregister:PLAYER_REGEN_ENABLED", "cvar-read:scriptProfile" }, state.lifecycle)
        assert.is_false(state.isEventRegistered("PLAYER_REGEN_ENABLED"))
        assert.are.equal(0, #state.popupShows)

        state.fireEvent("PLAYER_REGEN_ENABLED")
        assert.are.equal(0, #state.popupShows)
    end)
end)
