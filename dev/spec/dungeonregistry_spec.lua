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

    it("labels a numeric iconID and falls back to the question-mark texture for nil", function()
        local cases = {
            {
                iconID = 1002596, name = "Skyreach",
                expected = "|T1002596:16:16:0:0:64:64:5:59:5:59|t Skyreach",
            },
            {
                iconID = nil, name = "Den of Nalorakk",
                expected = "|TInterface\\Icons\\INV_Misc_QuestionMark:16:16:0:0:64:64:5:59:5:59|t Den of Nalorakk",
            },
        }
        for _, c in ipairs(cases) do
            assert.equal(c.expected, KE.GetDungeonTimerDungeonLabel(c.iconID, c.name))
        end
    end)

    it("keeps every boss with rows under its true ordinal, reminder-only bosses included", function()
        local cases = {
            { name = "bossOrder wins over position", orders = { 3, 4, 5 }, expected = { 3, 5 } },
            { name = "position without bossOrder", orders = {}, expected = { 1, 3 } },
        }
        for _, c in ipairs(cases) do
            local timer, aura = { id = 11 }, { id = "aura:3:7:added", isAura = true }
            local groups = KE.GroupDungeonTimerBossRows({
                { id = 1, name = "One", bossOrder = c.orders[1], items = { timer } },
                { id = 2, name = "Two", bossOrder = c.orders[2], items = {} },
                { id = 3, name = "Three", bossOrder = c.orders[3], items = { aura } },
            })
            assert.equal(2, #groups, c.name)
            assert.same({ "One", "Three" }, { groups[1].name, groups[2].name }, c.name)
            assert.same(c.expected, { groups[1].ordinal, groups[2].ordinal }, c.name)
            assert.is_nil(groups[1].firstReminder, c.name)
            assert.same({ aura }, groups[2].spells, c.name)
            assert.equal(1, groups[2].firstReminder, c.name)
        end
    end)

    it("lists a boss's timer rows before its reminder rows, routed by aura identity, not wording", function()
        local onYou = { id = "aura:1:9:added", isAura = true, data = { name = "Fire Bomb on you" } }
        local ended = { id = "cue:1:shield", data = { name = "Shield ended" } }
        local groups = KE.GroupDungeonTimerBossRows({
            { id = 1, name = "One", bossOrder = 1, items = { onYou, ended } },
        })
        assert.same({ ended, onYou }, groups[1].spells)
        assert.equal(2, groups[1].firstReminder)
    end)

    it("orders a boss's rows by its rowOrder and keeps the rest in their incoming order", function()
        local spellA, spellB = { id = 101 }, { id = 102 }
        local cueX = { id = "cue:1:x", isCue = true, cueName = "x" }
        local phase = { id = "phase:1:1", isPhase = true }
        local map = { id = "map:1:wind", isWindMap = true }
        local aura = { id = "aura:1:9:added", isAura = true }
        local items = { spellA, spellB, cueX, phase, map, aura }
        local cases = {
            { name = "named rows first, in list order", order = { "x", 102 },
                expected = { cueX, spellB, spellA, phase, map, aura } },
            { name = "unnamed rows keep their incoming order after a named one", order = { 102 },
                expected = { spellB, spellA, cueX, phase, map, aura } },
            { name = "no list keeps the incoming order", order = nil, expected = items },
        }
        for _, c in ipairs(cases) do
            local result = KE.OrderDungeonTimerBossRows(items, c.order)
            assert.equal(#c.expected, #result, c.name)
            for i = 1, #c.expected do
                assert.equal(c.expected[i], result[i], c.name)
            end
        end
    end)

    it("counts coverage for the selected season only", function()
        local encounters = {
            [10] = { dungeon = "Alpha", spells = { [1] = {}, [2] = {} }, phaseCues = { a = {} }, phases = { {} },
                auraSounds = { { ok = true }, { ok = false } } },
            [30] = { dungeon = "Delta", spells = { [4] = {} }, auraSounds = { { ok = true } } },
        }
        local trash = {
            [100] = { dungeonKey = "Alpha", mobs = {
                [7] = { spells = { [5] = {}, [6] = { hidden = true } } },
                [8] = { spells = { [9] = { hidden = true } } },
            } },
            [300] = { dungeonKey = "Delta", mobs = { [9] = { spells = { [10] = {} } } } },
        }
        local c = KE.CountDungeonTimerCoverage(REG, encounters, trash, 1, function(rule) return rule.ok end)
        assert.same({ dungeons = 1, bosses = 1, timers = 4, reminders = 1, trashEnemies = 1, trashAbilities = 1 }, c)
    end)
end)
