-- Modules/ClassUtilities/DoTTrackerRules.lua -- the rules a later edit breaks
-- silently: who counts, the label each answer shows, which DoTs a spec lists,
-- what the add and remove controls refuse, and the module's guards (what the
-- restriction gate must hold back, how far the build runs, how many enemies
-- may count, when the timer and the threat event act). The seed table is data
-- and gets no case.
local L = require("dev.spec._ke_loader")

describe("dot tracker rules", function()
    local KE, Rules

    before_each(function()
        KE = L.loadDoTTrackerRules()
        Rules = KE.DoTTrackerRules
    end)

    describe("who counts", function()
        local NIL = {}
        local KEYS = { "exists", "canAttack", "canAssist", "isDead", "inCombat" }

        local function api(changes)
            local reads = { exists = true, canAttack = true, canAssist = false, isDead = false, inCombat = true }
            for key, value in pairs(changes) do
                if value == NIL then reads[key] = nil else reads[key] = value end
            end
            local out = {}
            for _, key in ipairs(KEYS) do
                out[key] = function() return reads[key] end
            end
            return out
        end

        it("rejects in order; an unreadable existence rejects, any other unreadable read lets through", function()
            local cases = {
                { {}, true, true, nil },
                { { exists = false }, true, true, "no unit" },
                { { exists = NIL }, true, true, "no unit" },
                { { canAttack = false }, true, true, "not attackable" },
                { { canAssist = true }, true, true, "assistable" },
                { { isDead = true }, true, true, "dead" },
                { { inCombat = false }, true, true, "not in combat" },
                { { inCombat = false }, false, true, nil },
                { { inCombat = false }, true, false, nil },
                { { canAttack = NIL, canAssist = NIL, isDead = NIL, inCombat = NIL }, true, true, nil },
            }
            for i, case in ipairs(cases) do
                local reason = Rules.Verdict("nameplate1", case[2], case[3], api(case[1]))
                assert.equals(case[4], reason, "case " .. i)
            end
        end)

        it("steps the strict rules aside only when relaxing is allowed and nobody passes", function()
            local cases = {
                { true, false, false },
                { true, true, true },
                { false, nil, true },
                { false, false, true },
            }
            for i, case in ipairs(cases) do
                assert.equals(case[3], KE.PlateSlots.PickStrict(case[1], case[2]), "case " .. i)
            end
        end)
    end)

    it("picks each answer's text and color key from k, the total and the format", function()
        local cases = {
            { 3, 6, "FRACTION", "3/6", "some" },
            { 6, 6, "FRACTION", "6/6", "all" },
            { 2, 6, "COUNT", "2", "some" },
            { 2, 6, "MISSING", "4", "some" },
            { 6, 6, "MISSING", "0", "all" },
            { 0, 0, "FRACTION", "0/0", "some" },
            { 0, 0, "MISSING", "0", "some" },
            { 5, 6, nil, "5/6", "some" },
        }
        for i, case in ipairs(cases) do
            assert.equals(case[4], Rules.Label(case[1], case[2], case[3]), "text " .. i)
            assert.equals(case[5], Rules.LabelColorKey(case[1], case[2]), "color " .. i)
        end
    end)

    describe("the list a spec shows", function()
        local unreadable = function() return nil end

        it("keeps seeds in order minus disabled ones, then enabled customs ascending", function()
            local seeds = { DRUID = { [102] = { { id = 1 }, { id = 2 }, { id = 3 } } } }
            local spells = {
                ["102:2"] = { enabled = false },
                ["102:9"] = { enabled = true, custom = true },
                ["102:5"] = { enabled = true, custom = true },
                ["102:6"] = { enabled = false, custom = true },
                ["102:1"] = { enabled = true, custom = true },
                ["103:7"] = { enabled = true, custom = true },
                ["102:04"] = { enabled = true, custom = true },
                ["0102:4"] = { enabled = true, custom = true },
                ["bad"] = { enabled = true, custom = true },
                ["102:8"] = "junk",
            }
            assert.same({ 1, 3, 5, 9 }, Rules.ResolveList(seeds, spells, "DRUID", 102, unreadable))
            assert.same({}, Rules.ResolveList(seeds, spells, "DRUID", nil, unreadable))
        end)

        it("gates a talent row on its talent and drops a row its replacement is known for", function()
            local seeds = { PRIEST = { [256] = {
                { id = 589, replacedBy = 204197 },
                { id = 204213, talent = 204197 },
            } } }
            local cases = {
                { true, { 204213 } },
                { false, { 589 } },
                { nil, { 589, 204213 } },
            }
            for i, case in ipairs(cases) do
                local known = function() return case[1] end
                assert.same(case[2], Rules.ResolveList(seeds, {}, "PRIEST", 256, known), "case " .. i)
            end
        end)
    end)

    describe("adding and removing a DoT", function()
        local seeds = { DRUID = { [102] = { { id = 1 } } } }
        local spells
        local function nameOf(id) return id ~= 999 and "Name" or nil end

        before_each(function()
            spells = { ["102:9"] = { enabled = true, custom = true } }
        end)

        it("adds only a new, real, whole id", function()
            local cases = {
                { "abc", nil, "whole number" },
                { "12.5", nil, "whole number" },
                { "0", nil, "whole number" },
                { "999", nil, "No spell" },
                { "1", nil, "already listed" },
                { "9", nil, "already listed" },
                { "42", 42, nil },
            }
            for i, case in ipairs(cases) do
                local id, reason = Rules.CanAdd(seeds, spells, "DRUID", 102, case[1], nameOf)
                assert.equals(case[2], id, "id " .. i)
                if case[3] then assert.matches(case[3], reason, nil, true) end
            end
        end)

        it("removes only an added DoT of that spec", function()
            local cases = {
                { "x", nil, "whole number" },
                { "1", nil, "untick" },
                { "42", nil, "not one of" },
                { "9", "102:9", nil },
            }
            for i, case in ipairs(cases) do
                local key, reason = Rules.CanRemove(seeds, spells, "DRUID", 102, case[1])
                assert.equals(case[2], key, "key " .. i)
                if case[3] then assert.matches(case[3], reason, nil, true) end
            end
        end)
    end)

    describe("the module's guards", function()
        it("plans the row to apply and asks the gate only when gated work is owed", function()
            local A, NONE = { 1, 2 }, {}
            -- shown, wanted, refilter, timer work, gate answer -> row, allowed, gate asks
            local cases = {
                { A, { 1, 2 }, false, false, false, "wanted", true, 0 },
                { A, { 1, 3 }, true, false, true, "wanted", true, 1 },
                { A, { 1, 3 }, true, false, false, "shown", false, 1 },
                { A, { 1 }, false, false, false, "shown", false, 1 },
                { A, { 1, 2, 3 }, false, false, false, "shown", false, 1 },
                { A, NONE, false, false, false, "shown", false, 1 },
                { A, { 1, 2 }, false, true, false, "shown", false, 1 },
                { NONE, { 1, 3 }, true, false, false, nil, false, 1 },
                { NONE, { 1, 3 }, false, true, false, "wanted", false, 1 },
            }
            for i, case in ipairs(cases) do
                local asked = 0
                local function request()
                    asked = asked + 1
                    return case[5]
                end
                local row, allowed = Rules.PlanApply(case[1], case[2], case[3], case[4], request)
                local expected = (case[6] == "wanted" and case[2]) or (case[6] == "shown" and case[1]) or nil
                assert.equals(expected, row, "row " .. i)
                assert.equals(case[7], allowed, "allowed " .. i)
                assert.equals(case[8], asked, "asked " .. i)
            end
        end)

        it("counts no more enemies than the cap or the fewest sensors a shown DoT has", function()
            local function cells(counts)
                local out = {}
                for i, n in ipairs(counts) do
                    out[i] = { sensors = {} }
                    for s = 1, n do out[i].sensors[s] = true end
                end
                return out
            end
            local cases = {
                { 20, { 8, 8 }, 2, 8 },
                { 20, { 8, 3 }, 2, 3 },
                { 5, { 8, 8 }, 2, 5 },
                { 20, { 8, 3 }, 1, 8 },
                { 20, {}, 0, 0 },
            }
            for i, case in ipairs(cases) do
                assert.equals(case[4], Rules.UsableCap(case[1], cells(case[2]), case[3]), "case " .. i)
            end
        end)

        it("builds 8 enemies ahead, then 4 past the highest slot taken, never past the cap", function()
            local cases = { { 20, 0, 8 }, { 20, 6, 10 }, { 20, 18, 20 }, { 5, 0, 5 }, { 40, 30, 34 } }
            for i, case in ipairs(cases) do
                assert.equals(case[3], Rules.BuildTarget(case[1], case[2]), "case " .. i)
            end
        end)

        it("wants the target timer only on a target that exists and is not known to be assistable", function()
            local cases = {
                { true, false, true },
                { true, nil, true },
                { true, true, false },
                { false, false, false },
                { nil, false, false },
            }
            for i, case in ipairs(cases) do
                assert.equals(case[3], Rules.TimerWanted(case[1], case[2]), "case " .. i)
            end
        end)

        it("scans on a threat change only for an uncounted plate while a slot is free", function()
            local cases = { { false, 3, 20, true }, { true, 3, 20, false }, { false, 20, 20, false } }
            for i, case in ipairs(cases) do
                assert.equals(case[4], Rules.WantsThreatScan(case[1], case[2], case[3]), "case " .. i)
            end
        end)
    end)
end)
