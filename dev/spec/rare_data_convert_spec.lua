-- Tier 1: the rare table's conversion rules (dev/scripts/_rare_data_convert.lua),
-- on rows built here. The shipped table is never pinned: data_build_spec builds
-- it and holds its form, and --check holds it to these rules against the raw file.
local Convert = dofile("dev/scripts/_rare_data_convert.lua")
local Source = dofile("dev/scripts/_data_source.lua")

local function rareRow(over)
    local row = { "Rare", 10, 10, 0, -1, -1, 1429, { 50.0, 50.0 } }
    for index, value in pairs(over or {}) do row[index] = value end
    return row
end

local function converted(rares, loot)
    return Convert.Convert(rares or {}, loot or {})
end

-- The stored lines, built back the way the data file and KE.BuildData build them.
local function buildBack(lines)
    local ns = {}
    local chunk = assert(loadstring(table.concat(lines, "\n") .. "\n"))
    setfenv(chunk, { KitnEssentials = { GetNamespace = function() return ns end } })
    chunk()
    return assert(loadstring(ns.DataSources.RareAlertTable))()
end

describe("Rare table conversion", function()
    it("stores a level at or below 0 as absent, both fields", function()
        for _, row in ipairs({
            { name = "both -1", low = -1, high = -1 },
            { name = "both 0", low = 0, high = 0 },
            { name = "low only", low = 0, high = 12 },
            { name = "high only", low = 12, high = -1 },
        }) do
            local rares = converted({ [1] = rareRow({ [2] = row.low, [3] = row.high }) })
            assert.is_nil(rares[1].low, row.name)
            assert.is_nil(rares[1].high, row.name)
        end
        local rares = converted({ [1] = rareRow({ [2] = 11, [3] = 12 }) })
        assert.equals(11, rares[1].low)
        assert.equals(12, rares[1].high)
    end)

    it("stores items 286749 and 286746 at quality 2 and leaves other items alone", function()
        local _, loot = converted({}, { [1] = {
            { 286749, 1, 63.9, "A", 1 }, { 286746, 1, 53.6, "B", 1 }, { 2407, 1, 1.3, "C" },
        } })
        assert.equals(2, loot[1][1].quality)
        assert.equals(2, loot[1][2].quality)
        assert.equals(1, loot[1][3].quality)
    end)

    it("stores a chance above 100 as 100 and keeps 0 and values under 100", function()
        local _, loot = converted({}, { [1] = {
            { 8244, 3, 111.4, "A" }, { 2, 2, 0, "B" }, { 3, 2, 99.9, "C" },
        } })
        assert.equals(100, loot[1][1].chance)
        assert.equals(0, loot[1][2].chance)
        assert.equals(99.9, loot[1][3].chance)
    end)

    it("keeps the named fields, stores a flag of 1 as true, and drops the trail and the more count", function()
        local rares, loot = converted(
            { [7] = { "Seven", 8, 9, 1, 1, 0, 1438, { 1.5, 2.5 }, { 9, 9 } }, [8] = rareRow() },
            { [7] = { { 5, 2, 1, "New one", 1 }, { 6, 2, 1, "Old one", 0 }, more = 4 } })
        assert.same({
            name = "Seven", low = 8, high = 9, elite = true, reactA = 1, reactH = 0, map = 1438,
            spots = { 1.5, 2.5 },
        }, rares[7])
        assert.is_nil(rares[8].elite)
        assert.same({
            { id = 5, quality = 2, chance = 1, name = "New one", new = true },
            { id = 6, quality = 2, chance = 1, name = "Old one" },
        }, loot[7])
    end)

    it("writes one creature per line in id order, and the lines build back to the same tables", function()
        local rares, loot = converted(
            { [61] = rareRow({ [1] = 'A "quoted" name' }), [5] = rareRow({ [2] = -1, [3] = -1 }) },
            { [61] = { { 1, 2, 3, "Drop", 1 } } })
        local lines = Convert.Lines(rares, loot, Source.Wrap)
        local rows = 0
        for _, line in ipairs(lines) do
            if line:match("^%[%d+%]=") then rows = rows + 1 end
        end
        assert.equals(3, rows)
        assert.truthy(table.concat(lines, "\n"):find("%[5%]=.-%[61%]="))
        local built = buildBack(lines)
        assert.same(rares, built.rares)
        assert.same(loot, built.loot)
    end)

    it("refuses a row the stored form cannot hold, naming its creature", function()
        for _, row in ipairs({
            { name = "no name", rares = { [3] = rareRow({ [1] = false }) } },
            { name = "control character", rares = { [3] = rareRow({ [1] = "Two\nlines" }) } },
            { name = "no map", rares = { [3] = rareRow({ [7] = "1429" }) } },
            { name = "spots not a list", rares = { [3] = rareRow({ [8] = 50 }) } },
            { name = "drop with no id", loot = { [3] = { { nil, 2, 1, "Drop" } } } },
        }) do
            local ok, err = pcall(Convert.Convert, row.rares or {}, row.loot or {})
            assert.is_false(ok, row.name)
            assert.truthy(tostring(err):find("rare 3", 1, true), row.name)
        end
    end)
end)
