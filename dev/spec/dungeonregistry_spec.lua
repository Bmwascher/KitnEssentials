-- Specs for the Dungeon Timers dungeon registry helpers: season list
-- derivation and initial-selection resolution (current dungeon > saved
-- selection > newest-season fallback).
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
end)
