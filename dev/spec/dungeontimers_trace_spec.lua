-- Declared-secret stubs verify refusal routing, not live secret-value or taint behavior.
local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

describe("Dungeon Timers diagnostic retention", function()
    local Trace, KE, store, secret, module

    before_each(function()
        secret = setmetatable({}, { __tostring = function() error("secret was formatted") end })
        mock.install({ issecretvalue = function(value) return value == secret end })
        _G.GetInstanceInfo = function() return nil, nil, nil, nil, nil, nil, nil, 2859 end
        KE = helpers.loadModule("Modules/DungeonTools/DungeonTimers/DebugTrace.lua", { db = { global = {} } })
        Trace = KE._DungeonTimerTrace
        store = { rows = {}, sequence = 0, bytes = 0, omitted = 0 }
        module = { db = { Enabled = true }, IsEnabled = function() return true end, _timerStateRevision = 1 }
    end)

    it("keeps ordered records and refuses writes after stop", function()
        local trace = Trace.New(store)
        local first = trace:Append("first", "value", "one")
        local second = trace:Append("second", "value", "two")
        assert.is_true(second > first)
        assert.matches("|first|value=one", store.rows[1], 1, true)
        assert.matches("|second|value=two", store.rows[2], 1, true)
        trace:Stop("finished")
        local count, sequence = #store.rows, store.sequence
        trace:Append("late")
        assert.equals(count, #store.rows)
        assert.equals(sequence, store.sequence)
    end)

    it("retains the prefix and counts all later omissions when rows fill", function()
        local trace = Trace.New(store, 1)
        trace:Append("first")
        local first = store.rows[1]
        trace:Append("second")
        trace:Append("third")
        assert.same({ first }, store.rows)
        assert.equals(2, store.omitted)
    end)

    it("keeps lifecycle decisions before encounter and receipt context arrives", function()
        local trace = Trace.New(store)
        trace:Decision("lifecycle")
        assert.equals(1, #store.rows)
        assert.matches("|KE|receipt=nil|message=lifecycle", store.rows[1], 1, true)
    end)

    it("does not resume appending smaller rows after the byte budget fills", function()
        local trace = Trace.New(store, 100, 70)
        trace:Append("first")
        local first = store.rows[1]
        trace:Append("long", "value", string.rep("x", 100))
        trace:Append("x")
        assert.same({ first }, store.rows)
        assert.equals(2, store.omitted)
        assert.equals(#first, store.bytes)
    end)

    it("records only bounded clean scalars and redacts declared secrets", function()
        local trace = Trace.New(store)
        trace:Append("values", "secret", secret, "raw", {}, "text", "one\ntwo|three",
            "number", 5, "bool", false, "bad", math.huge, "long", string.rep("x", 1000))
        local line = store.rows[1]
        assert.matches("secret=<secret>|raw=<table>|text=one two three|number=5|bool=false|bad=<invalid-number>",
            line, 1, true)
        assert.is_true(#line < 600)
    end)

    it("refuses to arm a disabled module without replacing its saved data", function()
        KE.db.global.DungeonTimerTrace = store
        for _, disabled in ipairs({ "engine", "setting" }) do
            module.IsEnabled = function() return disabled ~= "engine" end
            module.db.Enabled = disabled ~= "setting"
            assert.is_nil(Trace.Start(module))
            assert.equals(store, KE.db.global.DungeonTimerTrace)
            assert.is_nil(module._debugTrace)
        end
    end)

    it("keeps public cast evidence for an unreadable unit without querying it", function()
        _G.UnitCastingInfo = function() error("unreadable unit was queried") end
        _G.UnitChannelInfo = function() error("unreadable unit was queried") end
        local trace = Trace.New(store)
        trace.encounter = 3199
        trace:OnEvent("UNIT_SPELLCAST_START", secret, secret, secret, 17)
        trace:OnEvent("UNIT_SPELLCAST_CHANNEL_STOP", secret, secret, secret, secret, 18)
        assert.matches("unit=<secret>|spellId=<secret>|barId=17", store.rows[1], 1, true)
        assert.matches("unit=<secret>|spellId=<secret>|barId=18", store.rows[2], 1, true)
    end)

    it("refuses to arm in combat without creating an observer", function()
        _G.InCombatLockdown = function() return true end
        assert.is_nil(Trace.Start(module))
        assert.is_nil(module._debugTraceFrame)
        assert.is_nil(KE.db.global.DungeonTimerTrace)
    end)

    it("refuses to arm outside Vale or with an unreadable instance ID", function()
        for _, instanceId in ipairs({ 1, secret }) do
            _G.GetInstanceInfo = function() return nil, nil, nil, nil, nil, nil, nil, instanceId end
            assert.is_nil(Trace.Start(module))
            assert.is_nil(module._debugTraceFrame)
        end
    end)

    it("keeps active capture data and resumes stopped data without replacing the frame", function()
        local first = Trace.Start(module)
        first:Append("evidence")
        local rows, frame = first.store.rows, first.frame
        assert.equals(first, Trace.Start(module, true))
        assert.equals(rows, first.store.rows)
        first:Stop("reload")
        local count = #rows
        local resumed = Trace.Start(module)
        assert.equals(rows, resumed.store.rows)
        assert.equals(count + 1, #rows)
        assert.equals(frame, resumed.frame)
        assert.is_nil(resumed.store.stopped)
        resumed:Stop("done")
        local fresh = Trace.Start(module, true)
        assert.is_not.equals(rows, fresh.store.rows)
        assert.equals(frame, fresh.frame)
    end)

    it("refuses incompatible saved data without replacing it or creating an observer", function()
        for _, field in ipairs({ "schema", "rows", "sequence", "bytes", "omitted" }) do
            local incompatible = { schema = 1, rows = { "prior evidence" }, sequence = 1, bytes = 14, omitted = 0 }
            incompatible[field] = false
            KE.db.global.DungeonTimerTrace = incompatible
            assert.is_nil(Trace.Start(module))
            assert.equals(incompatible, KE.db.global.DungeonTimerTrace)
            assert.is_nil(module._debugTraceFrame)
        end
    end)

    it("arms in each traced map, admits only that map's encounters and refuses another map's saved data", function()
        local function owner(id) return { GetEncounterID = function() return id end } end
        local cases = {
            { map = 2859, admitted = 3201, refused = 2623 },
            { map = 2521, admitted = 2623, refused = 3201 },
            { map = 1762, admitted = 2143, refused = 2623 },
        }
        for _, case in ipairs(cases) do
            _G.GetInstanceInfo = function() return nil, nil, nil, nil, nil, nil, nil, case.map end
            local trace = Trace.Start(module, true)
            assert.is_not_nil(trace, case.map)
            assert.equals(case.admitted, select(2, trace:Owner(owner(case.admitted))), case.map)
            assert.is_nil(select(2, trace:Owner(owner(case.refused))), case.map)
            trace:Stop("next")
        end
        local saved = KE.db.global.DungeonTimerTrace
        _G.GetInstanceInfo = function() return nil, nil, nil, nil, nil, nil, nil, 2859 end
        assert.is_nil(Trace.Start(module))
        assert.equals(saved, KE.db.global.DungeonTimerTrace)
        assert.is_not_nil(Trace.Start(module, true))
    end)

    it("compares a unit with the target only after a readable permission", function()
        local trace = Trace.New(store)
        local compared = 0
        _G.UnitIsUnit = function()
            compared = compared + 1
            return true
        end
        local cases = {
            { permission = true, expected = true },
            { permission = false, expected = "compare-refused" },
            { permission = secret, expected = "compare-refused" },
            { fails = true, expected = "compare-refused" },
        }
        for _, case in ipairs(cases) do
            _G.C_Secrets = { CanCompareUnitTokens = function()
                if case.fails then error("comparison query failed") end
                return case.permission
            end }
            assert.equals(case.expected, trace:TargetIs("nameplate3"))
        end
        assert.equals(1, compared)
        _G.C_Secrets = nil
        assert.equals("compare-refused", trace:TargetIs("boss1"))
    end)

    it("restores a held receipt's row only for the same running trace", function()
        local trace = Trace.New(store)
        trace.receipt = 7
        local captured = trace:Capture()
        trace.receipt = 9
        assert.equals(7, Trace.Restore(captured, trace))
        assert.is_nil(Trace.Restore(captured, Trace.New(store)))
        assert.is_nil(Trace.Restore(nil, trace))
        trace:Stop("done")
        assert.is_nil(Trace.Restore(captured, trace))
        assert.is_nil(trace:Capture())
    end)
end)
