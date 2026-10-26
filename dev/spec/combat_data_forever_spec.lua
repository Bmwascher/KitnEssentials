-- Tier 1: the Forever rank lookups (Modules/Combat/CombatDataForever.lua).
-- The families tested are found in the module's own RANK_FAMILIES at test
-- time, so no data cell is pinned.
local helpers = require("dev.spec._helpers")

local function loadData()
    _G.KitnEssentials = _G.KitnEssentials or {}
    return helpers.loadModule("Modules/Combat/CombatDataForever.lua", {}).CombatDataForever
end

-- The lowest-keyed family of three or more ranks, another family, and an
-- id in no family.
local function fixtures(D)
    local keys = {}
    for key in pairs(D.RANK_FAMILIES) do keys[#keys + 1] = key end
    table.sort(keys)
    local long, other
    for _, key in ipairs(keys) do
        local ranks = D.RANK_FAMILIES[key]
        if not long and #ranks >= 3 then
            long = ranks
        elseif not other then
            other = ranks
        end
        if long and other then break end
    end
    local lone = 1
    while D.FamilyOf(lone) do lone = lone + 1 end
    return long, other, lone
end

describe("CombatDataForever: rank lookups", function()
    it("gives the highest known rank from any rank, and a lone id itself when known", function()
        local D = loadData()
        local long, _, lone = fixtures(D)
        local known = { [long[1]] = true, [long[2]] = true, [lone] = true }
        local isKnown = function(id) return known[id] == true end
        local none = function() return false end
        for _, row in ipairs({
            { name = "asked with the first id", id = long[1], known = isKnown, want = long[2] },
            { name = "asked with a middle rank", id = long[2], known = isKnown, want = long[2] },
            { name = "asked with the top rank", id = long[#long], known = isKnown, want = long[2] },
            { name = "no rank known", id = long[1], known = none, want = nil },
            { name = "a lone id known", id = lone, known = isKnown, want = lone },
            { name = "a lone id not known", id = lone, known = none, want = nil },
        }) do
            assert.equals(row.want, D.HighestKnown(row.id, row.known), row.name)
        end
    end)

    it("tells ranks of one family apart from other families", function()
        local D = loadData()
        local long, other, lone = fixtures(D)
        for _, row in ipairs({
            { name = "two ranks of one family", a = long[1], b = long[#long], want = true },
            { name = "one id twice", a = lone, b = lone, want = true },
            { name = "two families", a = long[1], b = other[1], want = false },
            { name = "a nil", a = long[1], b = nil, want = false },
        }) do
            assert.equals(row.want, D.SameFamily(row.a, row.b), row.name)
        end
    end)

    it("collapses a list to the highest known rank of each spell, once", function()
        local D = loadData()
        local long, other, lone = fixtures(D)
        local known = { [long[1]] = true, [long[2]] = true, [lone] = true }
        local got = D.Collapse({ long[1], long[#long], lone, other[1] }, function(id) return known[id] == true end)
        local want = { long[2], lone }
        table.sort(want)
        assert.same(want, got)
    end)
end)
