-- Pure unit test for MPT.BuildDeathRows (the death-list tooltip's rows).
-- Loads the REAL core file headlessly, the same way mpt_raceline_spec does.
local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

local MPT
setup(function()
    mock.install()
    local modules = helpers.installAddonShim()
    helpers.loadModule("Modules/Dungeons/MythicPlusTimer/MythicPlusTimer.lua")
    MPT = modules["MythicPlusTimer"]
    assert(MPT and MPT.BuildDeathRows, "core file did not expose BuildDeathRows")
end)

describe("MPT.BuildDeathRows", function()
    it("TIME lists every death chronologically, equal seconds by name, without reordering the log", function()
        local log = {
            { t = 300, name = "Cleric", class = "PRIEST" },
            { t = 100, name = "Tank",   class = "WARRIOR" },
            { t = 300, name = "Archer", class = "HUNTER" },
            { t = 200, name = "Tank",   class = "WARRIOR" },
        }
        local before = {}
        for i, e in ipairs(log) do before[i] = e end
        local rows = MPT.BuildDeathRows(log, "TIME")
        assert.are.same({
            { t = 100, name = "Tank",   class = "WARRIOR" },
            { t = 200, name = "Tank",   class = "WARRIOR" },
            { t = 300, name = "Archer", class = "HUNTER" },
            { t = 300, name = "Cleric", class = "PRIEST" },
        }, rows)
        for i = 1, #before do assert.are.equal(before[i], log[i]) end
    end)

    it("COUNT gives one row per player with their total, most deaths first, ties by name", function()
        local log = {
            { t = 10, name = "Mage",   class = "MAGE" },
            { t = 20, name = "Tank",   class = "WARRIOR" },
            { t = 30, name = "Druid",  class = "DRUID" },
            { t = 40, name = "Tank",   class = "WARRIOR" },
            { t = 50, name = "Tank",   class = "WARRIOR" },
            { t = 60, name = "Mage",   class = "MAGE" },
            { t = 70, name = "Archer", class = "HUNTER" },
        }
        local rows = MPT.BuildDeathRows(log, "COUNT")
        local got = {}
        for i, row in ipairs(rows) do got[i] = row.name .. "=" .. row.count end
        assert.are.same({ "Tank=3", "Mage=2", "Archer=1", "Druid=1" }, got)
    end)

    it("COUNT keeps a player's class once any of their entries recorded one", function()
        local rows = MPT.BuildDeathRows({
            { t = 1, name = "Rogue" },
            { t = 2, name = "Rogue", class = "ROGUE" },
            { t = 3, name = "Rogue" },
        }, "COUNT")
        assert.are.equal("ROGUE", rows[1].class)
    end)
end)
