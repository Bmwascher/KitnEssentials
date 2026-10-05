-- Modules/Utilities/TimeSpiral.lua -- which movement-spell icon the display
-- shows. The spell lookup, the spec read and the paint are smoke.
local L = require("dev.spec._ke_loader")

local FALLBACK = 4622479

local function knownSet(ids)
    local set = {}
    for _, id in ipairs(ids) do set[id] = true end
    return function(spellID) return set[spellID] == true end
end

describe("TimeSpiral icon pick", function()
    local pick

    before_each(function()
        local TSP = L.loadTimeSpiral()
        pick = TSP.PickIcon
    end)

    it("takes the first known entry in priority order", function()
        local list = { { 79206, 451170 }, { 192063, 463565 }, { 58875, 132328 } }
        local cases = {
            { name = "all known",           known = { 79206, 192063, 58875 }, expected = 451170 },
            { name = "first unknown",       known = { 192063, 58875 },        expected = 463565 },
            { name = "only the last known", known = { 58875 },                expected = 132328 },
        }
        for _, case in ipairs(cases) do
            assert.equals(case.expected, pick(list, knownSet(case.known), FALLBACK), case.name)
        end
    end)

    it("returns the fallback when nothing in the list is known", function()
        local cases = {
            { name = "none known", list = { { 1953, 135736 }, { 212653, 135739 } } },
            { name = "no list",    list = nil },
        }
        for _, case in ipairs(cases) do
            assert.equals(FALLBACK, pick(case.list, knownSet({}), FALLBACK), case.name)
        end
    end)
end)
