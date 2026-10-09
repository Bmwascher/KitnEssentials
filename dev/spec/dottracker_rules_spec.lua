-- Modules/ClassUtilities/DoTTrackerRules.lua -- the rules a later edit breaks
-- silently: who counts, the label, color and cap each answer takes, which DoTs
-- a spec lists, how a saved entry is written, what the add and remove controls
-- refuse, and the module's guards (what the restriction gate must hold back,
-- how far the build runs, how many enemies may count, when the timer and the
-- threat event act). The seed table is data and gets no case.
local L = require("dev.spec._ke_loader")

describe("dot tracker rules", function()
    local KE, Rules

    before_each(function()
        KE = L.loadDoTTrackerRules()
        Rules = KE.DoTTrackerRules
    end)

    describe("who counts", function()
        local NIL = {}
        local KEYS = { "exists", "canAttack", "canAssist", "isDead", "inCombat", "groupThreat" }

        local function api(changes)
            local reads = {
                exists = true, canAttack = true, canAssist = false, isDead = false, inCombat = true, groupThreat = true,
            }
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
            -- reads, strict, in-combat rule on, group rule on, expected
            local cases = {
                { {}, true, true, true, nil },
                { { exists = false }, true, true, true, "no unit" },
                { { exists = NIL }, true, true, true, "no unit" },
                { { canAttack = false }, true, true, true, "not attackable" },
                { { canAssist = true }, true, true, true, "assistable" },
                { { isDead = true }, true, true, true, "dead" },
                { { inCombat = false }, true, true, true, "not in combat" },
                { { inCombat = false }, false, true, true, nil },
                { { inCombat = false }, true, false, true, nil },
                { { groupThreat = false }, true, true, true, "not fighting your group" },
                { { groupThreat = NIL }, true, true, true, nil },
                { { groupThreat = false }, true, true, false, nil },
                { { groupThreat = false }, false, true, true, nil },
                { { inCombat = false, groupThreat = false }, true, true, true, "not in combat" },
                { { canAttack = NIL, canAssist = NIL, isDead = NIL, inCombat = NIL, groupThreat = NIL }, true, true, true, nil },
            }
            for i, case in ipairs(cases) do
                local reason = Rules.Verdict("nameplate1", case[2], case[3], case[4], api(case[1]))
                assert.equals(case[5], reason, "case " .. i)
            end
        end)

        it("finds the group on a threat list at any true read, and stays unsure only when a read failed", function()
            -- watcher reads in order, expected
            local cases = {
                { { true }, true },
                { { NIL, true }, true },
                { { false, NIL }, nil },
                { { false, false }, false },
                { {}, false },
            }
            for i, case in ipairs(cases) do
                local watchers, reads = {}, {}
                for j, value in ipairs(case[1]) do
                    watchers[j] = "w" .. j
                    if value ~= NIL then reads["w" .. j] = value end
                end
                local function read(watcher, unit)
                    assert.equals("nameplate1", unit)
                    return reads[watcher]
                end
                assert.equals(case[2], Rules.GroupThreat("nameplate1", watchers, read), "case " .. i)
            end
            local function noRead() error("no read expected without a watcher list") end
            assert.is_nil(Rules.GroupThreat("nameplate1", nil, noRead), "no list")
        end)

        it("watches the player, pet and party, and nobody in a raid or with an unread group", function()
            -- in a raid, group size, expected list
            local cases = {
                { false, 0, { "player", "pet" } },
                { false, 3, { "player", "pet", "party1", "party2" } },
                { false, 5, { "player", "pet", "party1", "party2", "party3", "party4" } },
                { true, 20, nil },
                { nil, 3, nil },
                { false, nil, nil },
            }
            for i, case in ipairs(cases) do
                assert.same(case[3], Rules.Watchers(case[1], case[2]), "case " .. i)
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

    describe("colors, caps and saved entries", function()
        it("takes a DoT's own color from its override, else its seed, and none while DoT Colors is off", function()
            local row = { id = 1, color = { 0.1, 0.2, 0.3 } }
            local override = { 1, 0, 0, 1 }
            -- entry, row, DoT Colors on, expected
            local cases = {
                { { color = override }, row, true, override },
                { { enabled = true }, row, true, row.color },
                { nil, row, true, row.color },
                { { enabled = true }, nil, true, nil },
                { "junk", { id = 1 }, true, nil },
                { { color = override }, row, false, nil },
            }
            for i, case in ipairs(cases) do
                assert.equals(case[4], Rules.ColorOf(case[1], case[2], case[3]), "case " .. i)
            end
        end)

        it("paints All Have It only at full coverage with Full Coverage Color on, else the own color or Some Have It", function()
            local own, some, all = {}, {}, {}
            -- k, d, own color, Full Coverage Color on, expected
            local cases = {
                { 6, 6, own, true, all },
                { 6, 6, own, false, own },
                { 3, 6, own, true, own },
                { 3, 6, nil, true, some },
                { 6, 6, nil, false, some },
                { 0, 0, own, true, own },
            }
            for i, case in ipairs(cases) do
                assert.equals(case[5], Rules.CountColor(case[1], case[2], case[3], some, all, case[4]), "case " .. i)
            end
        end)

        it("caps the denominator at the DoT's target limit and clamps the count to it", function()
            -- k, total, cap, shown k, d
            local cases = {
                { 3, 10, nil, 3, 10 },
                { 3, 4, 6, 3, 4 },
                { 6, 6, 6, 6, 6 },
                { 5, 10, 6, 5, 6 },
                { 8, 10, 6, 6, 6 },
                { 0, 0, 1, 0, 0 },
            }
            for i, case in ipairs(cases) do
                local k, d = Rules.Capped(case[1], case[2], case[3])
                assert.equals(case[4], k, "k " .. i)
                assert.equals(case[5], d, "d " .. i)
            end
        end)

        it("writes one field of a saved entry and drops an entry left empty", function()
            local color, other = { 1, 0, 0, 1 }, { 0, 1, 0, 1 }
            local spells = {
                ["71:1"] = { enabled = false, color = color },
                ["71:3"] = "junk",
                ["71:4"] = { color = color, custom = true, enabled = true },
            }
            Rules.SetField(spells, "71:1", "enabled", true)
            assert.same({ enabled = true, color = color }, spells["71:1"])
            Rules.SetField(spells, "71:1", "color", other)
            assert.same({ enabled = true, color = other }, spells["71:1"])
            Rules.SetField(spells, "71:1", "color", nil)
            assert.same({ enabled = true }, spells["71:1"])
            Rules.SetField(spells, "71:2", "color", color)
            assert.same({ color = color }, spells["71:2"])
            Rules.SetField(spells, "71:3", "enabled", true)
            assert.same({ enabled = true }, spells["71:3"])
            Rules.SetField(spells, "71:2", "color", nil)
            assert.is_nil(spells["71:2"])
            Rules.SetField(spells, "71:4", "color", nil)
            assert.same({ custom = true, enabled = true }, spells["71:4"])
        end)

        it("saves a picked color, and none when a row without an override gets back the color it opened with", function()
            local shown = { 0.5, 0.65, 1 }
            -- picked r, g, b, a; row had an override when drawn; expected save
            local cases = {
                { { 0.5, 0.65, 1, 1 }, false, nil },
                { { 0.5, 0.65, 1, 1 }, true, { 0.5, 0.65, 1, 1 } },
                { { 1, 0, 0, 1 }, false, { 1, 0, 0, 1 } },
                { { 0.5, 0.65, 1, 0.5 }, false, { 0.5, 0.65, 1, 0.5 } },
            }
            for i, case in ipairs(cases) do
                local c = case[1]
                assert.same(case[3], Rules.PickedColor(c[1], c[2], c[3], c[4], shown, case[2]), "case " .. i)
            end
        end)
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

        it("lists a talent-list row while any talent is known or unreadable, and a default-off row only once ticked", function()
            local seeds = { WARRIOR = { [71] = {
                { id = 1, talent = { 10, 11, 12 } },
                { id = 2, defaultOff = true },
            } } }
            -- talent reads (a missing key is unreadable), saved entries, expected list
            local cases = {
                { { [10] = false, [11] = true, [12] = false }, {}, { 1 } },
                { { [10] = false, [12] = false }, {}, { 1 } },
                { { [10] = false, [11] = false, [12] = false }, {}, {} },
                { { [11] = true }, { ["71:2"] = { color = { 1, 0, 0, 1 } } }, { 1 } },
                { { [11] = true }, { ["71:2"] = { enabled = true } }, { 1, 2 } },
            }
            for i, case in ipairs(cases) do
                local reads = case[1]
                local known = function(id) return reads[id] end
                assert.same(case[3], Rules.ResolveList(seeds, case[2], "WARRIOR", 71, known), "case " .. i)
            end
        end)

        it("lists a merged row once, counts its extra ids, and shows the extra icon only on a known hero talent", function()
            local row = { id = 146739, also = { 445474 }, iconTalent = 445465, iconId = 445474 }
            local seeds = { WARLOCK = { [265] = { row } } }
            local spells = {
                ["265:445474"] = { enabled = true, custom = true },
                ["265:42"] = { enabled = true, custom = true },
            }
            assert.same({ 146739, 42 }, Rules.ResolveList(seeds, spells, "WARLOCK", 265, unreadable))
            assert.same({ [146739] = true, [445474] = true }, Rules.FilterIds(146739, Rules.AlsoOf(row)))
            assert.same({ [42] = true }, Rules.FilterIds(42, Rules.AlsoOf(nil)))
            local icons = { { true, 445474 }, { false, 146739 }, { nil, 146739 } }
            for i, case in ipairs(icons) do
                assert.equals(case[2], Rules.IconOf(row, 146739, function() return case[1] end), "icon " .. i)
            end
            assert.equals(42, Rules.IconOf(nil, 42, function() return true end))
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

        it("refuses a merged row's extra id as already listed", function()
            local merged = { WARLOCK = { [265] = { { id = 146739, also = { 445474 } } } } }
            local id, reason = Rules.CanAdd(merged, {}, "WARLOCK", 265, "445474", nameOf)
            assert.is_nil(id)
            assert.matches("already listed", reason, nil, true)
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

        it("re-points a pooled cell for a new id, or for the same id with other extra ids", function()
            local merged = { 445474 }
            local function alsoOf(id)
                if id == 146739 then return merged end
                return Rules.AlsoOf(nil)
            end
            -- pooled cells, wanted list, expected
            local cases = {
                { { { id = 1, also = {} } }, { 1 }, false },
                { { { id = 1, also = {} } }, { 2 }, true },
                { { { id = 146739, also = {} } }, { 146739 }, true },
                { { { id = 146739, also = { 445474 } } }, { 146739 }, false },
                { { { id = 1, also = {} }, { id = 9, also = {} } }, { 1 }, false },
                { { {} }, { 146739 }, false },
            }
            for i, case in ipairs(cases) do
                assert.equals(case[3], Rules.NeedsRefilter(case[1], case[2], alsoOf), "case " .. i)
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
