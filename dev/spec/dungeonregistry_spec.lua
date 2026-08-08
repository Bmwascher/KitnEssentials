-- Specs for the Dungeon Timers dungeon registry helpers: season list
-- derivation, per-season filtering, and initial-selection resolution
-- (current dungeon > saved selection > newest-season fallback).
local loader = require("dev.spec._ke_loader")

describe("DungeonRegistry", function()
    local KE

    -- Synthetic two-season registry: resolver behavior must not depend on
    -- the shipped data, so every case runs against this table.
    local REG = {
        { key = "Alpha", name = "Alpha Halls",  iconID = 1, instanceID = 100, season = 1 },
        { key = "Bravo", name = "Bravo Depths", iconID = 2, instanceID = 200, season = 1 },
        { key = "Delta", name = "Delta Vault",  iconID = 3, instanceID = 300, season = 2 },
    }

    before_each(function()
        KE = loader.loadDungeonRegistry()
    end)

    it("lists distinct seasons ascending", function()
        assert.same({ 1, 2 }, KE.GetDungeonTimerSeasons(REG))
    end)

    it("filters dungeons by season preserving registry order", function()
        local s1 = KE.GetDungeonTimerDungeonsForSeason(REG, 1)
        assert.equal(2, #s1)
        assert.equal("Alpha", s1[1].key)
        assert.equal("Bravo", s1[2].key)
        local s2 = KE.GetDungeonTimerDungeonsForSeason(REG, 2)
        assert.equal(1, #s2)
        assert.equal("Delta", s2[1].key)
    end)

    it("selects the current dungeon when inside a tracked instance", function()
        local season, key = KE.ResolveDungeonTimerSelection(REG, 200, { dungeon = "Delta" })
        assert.equal(1, season)
        assert.equal("Bravo", key)
    end)

    it("falls back to the saved selection outside tracked instances", function()
        local season, key = KE.ResolveDungeonTimerSelection(REG, 999, { dungeon = "Delta" })
        assert.equal(2, season)
        assert.equal("Delta", key)
    end)

    it("ignores a stale saved key and lands on the newest season", function()
        local season, key = KE.ResolveDungeonTimerSelection(REG, nil, { dungeon = "Removed" })
        assert.equal(2, season)
        assert.equal("Delta", key)
    end)

    it("defaults to newest season, first dungeon, with nothing to go on", function()
        local season, key = KE.ResolveDungeonTimerSelection(REG, nil, nil)
        assert.equal(2, season)
        assert.equal("Delta", key)
    end)

    it("shipped registry carries eight season-1 dungeons with unique keys and instanceIDs", function()
        local reg = KE.DungeonTimerDungeons
        assert.equal(8, #reg)
        local keys, instances = {}, {}
        for _, d in ipairs(reg) do
            assert.equal(1, d.season)
            assert.is_string(d.key)
            assert.is_string(d.name)
            assert.is_number(d.iconID)
            assert.is_number(d.instanceID)
            assert.is_nil(keys[d.key])
            assert.is_nil(instances[d.instanceID])
            keys[d.key] = true
            instances[d.instanceID] = true
        end
    end)
end)
