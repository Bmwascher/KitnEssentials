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

    -- The anchor frame is one entry tall and every entry chains off its outer
    -- edge, so the box has to be moved onto the stack, not just grown. The
    -- negative term is the frame's own height and it is the whole point of
    -- this arithmetic -- an off-by-one there parks the box half an icon away
    -- from the thing it names, which is exactly the bug being fixed.
    describe("TS.PreviewStackInset", function()
        it("moves the box below the frame when the stack grows down", function()
            local l, r, t, b = TS.PreviewStackInset({ IconSize = 36, Gap = 3, Grow = "DOWN" })
            assert.equals(0, l)
            assert.equals(0, r)
            assert.equals(-36, t)
            assert.equals(75, b)
        end)

        it("moves the box above the frame when the stack grows up", function()
            local l, r, t, b = TS.PreviewStackInset({ IconSize = 36, Gap = 3, Grow = "UP" })
            assert.equals(0, l)
            assert.equals(0, r)
            assert.equals(75, t)
            assert.equals(-36, b)
        end)

        it("treats an absent growth setting as down", function()
            local _, _, t, b = TS.PreviewStackInset({ IconSize = 36, Gap = 3 })
            assert.equals(-36, t)
            assert.equals(75, b)
        end)

        it("tracks icon size and gap", function()
            local _, _, _, b = TS.PreviewStackInset({ IconSize = 50, Gap = 10, Grow = "DOWN" })
            assert.equals(110, b)
        end)

        -- The box must stay a box. Frame height and stack span are both derived
        -- from IconSize, so span always exceeds it for any positive count --
        -- this pins that rather than trusting it.
        it("always leaves a positive box height", function()
            local _, _, t, b = TS.PreviewStackInset({ IconSize = 36, Gap = 0, Grow = "DOWN" })
            assert.is_true(36 + t + b > 0)
        end)

        it("returns zeroes rather than erroring without a db", function()
            local l, r, t, b = TS.PreviewStackInset(nil)
            assert.equals(0, l)
            assert.equals(0, r)
            assert.equals(0, t)
            assert.equals(0, b)
        end)
    end)
end)
