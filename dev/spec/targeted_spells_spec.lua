-- Tier 1: pure gate/sort helpers on the TargetedSpells module table.
local L = require("dev.spec._ke_loader")

describe("TargetedSpells helpers (Modules/Dungeons/TargetedSpells.lua)", function()
    local TS
    setup(function()
        TS = L.loadTargetedSpells()
    end)

    local function db(overrides)
        local d = { ShowInDungeons = true, ShowInDelves = true,
                    ShowInRaids = false, ShowInOpenWorld = false, ShowInPvP = false }
        for k, v in pairs(overrides or {}) do d[k] = v end
        return d
    end

    describe("ShouldShowForInstance", function()
        it("shows in dungeons by default", function()
            assert.is_true(TS.ShouldShowForInstance(db(), true, "party", 23))
        end)
        it("hides in dungeons when unchecked", function()
            assert.is_false(TS.ShouldShowForInstance(db({ ShowInDungeons = false }), true, "party", 23))
        end)
        it("shows in delves (scenario + delve difficulty) by default", function()
            assert.is_true(TS.ShouldShowForInstance(db(), true, "scenario", TS.DELVE_DIFFICULTY_ID))
        end)
        it("treats non-delve scenarios as open world", function()
            assert.is_false(TS.ShouldShowForInstance(db(), true, "scenario", 1))
            assert.is_true(TS.ShouldShowForInstance(db({ ShowInOpenWorld = true }), true, "scenario", 1))
        end)
        it("hides in raids by default, shows when checked", function()
            assert.is_false(TS.ShouldShowForInstance(db(), true, "raid", 16))
            assert.is_true(TS.ShouldShowForInstance(db({ ShowInRaids = true }), true, "raid", 16))
        end)
        it("gates arena and battlegrounds on ShowInPvP", function()
            assert.is_false(TS.ShouldShowForInstance(db(), true, "arena", 0))
            assert.is_true(TS.ShouldShowForInstance(db({ ShowInPvP = true }), true, "pvp", 0))
        end)
        it("gates open world on ShowInOpenWorld", function()
            assert.is_false(TS.ShouldShowForInstance(db(), false, nil, nil))
            assert.is_true(TS.ShouldShowForInstance(db({ ShowInOpenWorld = true }), false, nil, nil))
        end)
    end)

    describe("CompareEntries", function()
        it("sorts by receipt time ascending", function()
            assert.is_true(TS.CompareEntries({ receiptTime = 1 }, { receiptTime = 2 }))
            assert.is_false(TS.CompareEntries({ receiptTime = 3 }, { receiptTime = 2 }))
        end)
        it("is stable-safe for equal times (strict less-than)", function()
            assert.is_false(TS.CompareEntries({ receiptTime = 2 }, { receiptTime = 2 }))
        end)
    end)
end)
