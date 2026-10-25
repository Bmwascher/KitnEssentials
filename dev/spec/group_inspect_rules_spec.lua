-- Tier 1: the shared inspect queue's pure rules
-- (Modules/Core/GroupInspect/GroupInspectRules.lua): whose wishes count, who
-- is asked next and when nobody is, who hears an answer, and when a talent
-- walk runs, fails or may report a rank of 0. Limits are read from the rules'
-- constants, so a tuning edit fails no case.
local L = require("dev.spec._ke_loader")

local function loadRules() return L.loadGroupInspectRules() end

-- An owner as the service keeps one: nil demand is inactive. wants and stale
-- map a GUID to its owner's answer.
local function owner(demand, wants, stale)
    local has
    if demand then
        has = {}
        for _, entry in ipairs(demand) do has[entry.guid] = true end
    end
    return {
        demand = demand,
        has = has,
        callbacks = {
            Wants = function(guid) return wants ~= nil and wants[guid] == true end,
            OnlyStale = function(guid) return stale ~= nil and stale[guid] == true end,
        },
    }
end

-- A queue record as NextInspect reads it.
local function entry(name, extra)
    local e = { name = name, canInspect = true }
    for key, value in pairs(extra or {}) do e[key] = value end
    return e
end

describe("GroupInspectRules demand union", function()
    it("lists each GUID once, in subscription then list order, skipping inactive and released owners", function()
        local R = loadRules()
        local a, b, b2, c, d = { guid = "a" }, { guid = "b" }, { guid = "b" }, { guid = "c" }, { guid = "d" }
        local released = owner({ c })
        released.released = true
        local list = R.Union({ owner({ a, b }), owner(nil), released, owner({ b2, d }) }, {})
        assert.are.equal(3, #list)
        assert.are.equal(a, list[1].entry, "first owner, first entry")
        assert.are.equal(b, list[2].entry, "the first listing of a GUID wins")
        assert.are.equal(d, list[3].entry, "a later owner's new GUID")
    end)

    it("asks the owners listing a GUID, or every active owner when none lists it", function()
        local R = loadRules()
        local lister, other = owner({ { guid = "x" } }), owner({})
        local owners = { lister, other, owner(nil) }
        local cases = {
            { name = "listed", guid = "x", want = { lister } },
            { name = "listed by nobody", guid = "gone", want = { lister, other } },
        }
        for _, case in ipairs(cases) do
            local got = R.Askers(owners, case.guid)
            assert.are.equal(#case.want, #got, case.name)
            for i, o in ipairs(case.want) do assert.are.equal(o, got[i], case.name) end
        end
    end)

    it("wants a GUID when any asker does, and calls it only stale when every wanting asker does", function()
        local R = loadRules()
        local x = { guid = "x" }
        local cases = {
            { name = "nobody wants it", a = {}, b = {}, wanted = false },
            { name = "one wants it, unread", a = { wants = true }, b = {}, wanted = true, stale = false },
            { name = "one wants it, only stale", a = { wants = true, stale = true }, b = {},
              wanted = true, stale = true },
            { name = "two want it, one unread", a = { wants = true, stale = true }, b = { wants = true },
              wanted = true, stale = false },
        }
        for _, case in ipairs(cases) do
            local owners = {
                owner({ x }, { x = case.a.wants }, { x = case.a.stale }),
                owner({ x }, { x = case.b.wants }, { x = case.b.stale }),
            }
            assert.are.equal(case.wanted, R.Wanted(owners, "x"), case.name)
            if case.wanted then assert.are.equal(case.stale, R.OnlyStale(owners, "x"), case.name) end
        end
    end)
end)

describe("GroupInspectRules.NextInspect", function()
    it("asks nothing while an inspect view is open, in combat, or within INSPECT_GAP of the last request", function()
        local R = loadRules()
        local entries = { entry("a") }
        local cases = {
            { name = "window open", state = { inspectShown = true, now = 10 } },
            { name = "talent view inspecting", state = { talentsInspecting = true, now = 10 } },
            { name = "in combat", state = { inCombat = true, now = 10 } },
            { name = "within the gap", state = { now = 10, lastRequest = 10.5 - R.INSPECT_GAP } },
        }
        for _, case in ipairs(cases) do
            assert.is_nil(R.NextInspect(case.state, entries), case.name)
        end
        assert.are.equal("a", R.NextInspect({ now = 10, lastRequest = 10 - R.INSPECT_GAP }, entries).name)
    end)

    it("skips a GUID nobody wants, out of range, offline or resting", function()
        local R = loadRules()
        local cases = {
            { name = "not wanted", extra = { done = true } },
            { name = "out of range", extra = { canInspect = false } },
            { name = "offline", extra = { offline = true } },
            { name = "resting", extra = { waitUntil = 40 } },
        }
        for _, case in ipairs(cases) do
            local got = R.NextInspect({ now = 10 }, { entry("skipped", case.extra), entry("next") })
            assert.are.equal("next", got and got.name, case.name)
        end
    end)

    it("asks nobody within FOREIGN_GAP seconds of another addon's inspect request", function()
        local R = loadRules()
        local entries = { entry("a") }
        local cases = {
            { name = "inside the gap", foreignAt = 10.5 - R.FOREIGN_GAP },
            { name = "at the gap", foreignAt = 10 - R.FOREIGN_GAP, want = "a" },
            { name = "no foreign request", want = "a" },
        }
        for _, case in ipairs(cases) do
            local got = R.NextInspect({ now = 10, foreignAt = case.foreignAt }, entries)
            assert.are.equal(case.want, got and got.name, case.name)
        end
    end)

    it("rests a GUID for TRY_WAIT seconds after MAX_TRIES tries, or STALE_TRIES when only stale", function()
        local R = loadRules()
        local cases = {
            { name = "unread", stale = false, cap = R.MAX_TRIES },
            { name = "stale", stale = true, cap = R.STALE_TRIES },
        }
        for _, case in ipairs(cases) do
            local e = entry("a")
            for _ = 1, case.cap - 1 do R.CountTry(e, 100, case.stale) end
            assert.is_nil(e.waitUntil, case.name)
            R.CountTry(e, 100, case.stale)
            local back = 100 + R.TRY_WAIT
            assert.are.same({ 0, back }, { e.tries, e.waitUntil }, case.name)
            assert.is_nil(R.NextInspect({ now = back - 1 }, { e }), case.name)
            assert.are.equal(e, R.NextInspect({ now = back }, { e }), case.name)
        end
    end)
end)

describe("GroupInspectRules.TimedOut", function()
    it("gives up on a request at TIMEOUT seconds and not before", function()
        local R = loadRules()
        assert.is_false(R.TimedOut(10 + R.TIMEOUT - 0.5, 10), "before")
        assert.is_true(R.TimedOut(10 + R.TIMEOUT, 10), "at the timeout")
    end)
end)

describe("GroupInspectRules.NodeEntries", function()
    it("fails a node that is not a table or whose entry list is not one, and keeps an empty list", function()
        local R = loadRules()
        local empty = {}
        local cases = {
            { name = "no node" },
            { name = "not a table", node = 5 },
            { name = "entry list not a table", node = { entryIDs = false } },
            { name = "empty entry list", node = { entryIDs = empty }, want = empty },
        }
        for _, case in ipairs(cases) do
            assert.are.equal(case.want, R.NodeEntries(case.node), case.name)
        end
    end)
end)

describe("GroupInspectRules.WalkPlan", function()
    it("refuses another spec's loadout even with a covering index, and walks only an unspent spec out of combat", function()
        local R = loadRules()
        local cases = {
            { name = "covered, own loadout", covered = true, loadout = 65, want = "read" },
            { name = "covered, another spec's loadout", covered = true, loadout = 70, want = "miss" },
            { name = "covered, no loadout spec", covered = true, want = "miss" },
            { name = "uncovered, own loadout", loadout = 65, want = "walk" },
            { name = "uncovered, tries spent", spent = true, loadout = 65, want = "miss" },
            { name = "uncovered, in combat", combat = true, loadout = 65, want = "skip" },
        }
        for _, case in ipairs(cases) do
            local got = R.WalkPlan(case.spent == true, 65, case.loadout, case.combat == true, case.covered == true)
            assert.are.equal(case.want, got, case.name)
        end
    end)
end)

describe("GroupInspectRules.CountMiss", function()
    it("counts one miss per spec per inspect answer, however many reads walked it", function()
        local R = loadRules()
        local misses, counted = {}, {}
        R.CountMiss(misses, counted, 65, 1)
        R.CountMiss(misses, counted, 65, 1)
        R.CountMiss(misses, counted, 70, 1)
        assert.are.same({ [65] = 1, [70] = 1 }, misses, "answer 1")
        R.CountMiss(misses, counted, 65, 2)
        assert.are.equal(2, misses[65], "answer 2")
    end)

    it("counts every failed walk outside an inspect answer", function()
        local R = loadRules()
        local misses, counted = {}, {}
        R.CountMiss(misses, counted, 65, nil)
        R.CountMiss(misses, counted, 65, nil)
        assert.are.equal(2, misses[65])
    end)
end)

describe("GroupInspectRules coverage", function()
    it("calls an index short when a newly wanted talent is outside the IDs it was built for", function()
        local R = loadRules()
        local built = { covered = { [1] = true, [2] = true } }
        local cases = {
            { name = "covered", index = built, want = { [1] = true }, covers = true },
            { name = "a newly wanted talent", index = built, want = { [1] = true, [3] = true }, covers = false },
            { name = "no index yet", want = { [1] = true }, covers = false },
        }
        for _, case in ipairs(cases) do
            assert.are.equal(case.covers, R.Covers(case.index, case.want), case.name)
        end
    end)

    it("reads a covered, unfound, kept talent as 0 and leaves skipped and uncovered ones unread", function()
        local R = loadRules()
        local want = { [1] = true, [2] = true, [3] = true, [4] = true }
        local found = { [1] = { {} } }
        local covered = { [1] = true, [2] = true, [3] = true }
        assert.are.same({ [1] = 2, [2] = 0 }, R.FillAbsent({ [1] = 2 }, want, { [3] = true }, found, covered))
    end)
end)

describe("GroupInspectRules owner release", function()
    it("calls no owner released by an earlier owner's call in the same dispatch", function()
        local R = loadRules()
        local first, second = owner({}), owner({})
        local called = {}
        R.Dispatch({ first, second }, function(o)
            called[#called + 1] = o
            if o == first then second.released = true end
        end)
        assert.are.equal(1, #called)
        assert.are.equal(first, called[1])
    end)

    it("has no active owner once the last active one is released", function()
        local R = loadRules()
        local active, inactive = owner({}), owner(nil)
        local owners = { active, inactive }
        assert.is_true(R.AnyActive(owners), "one active")
        active.released = true
        assert.is_false(R.AnyActive(owners), "released and inactive")
    end)
end)
