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
        it("shows dungeons and delves by default, hides dungeons when unchecked", function()
            local variants = {
                { db = db(), inInstance = true, instanceType = "party", difficultyID = 23, expect = true },
                { db = db({ ShowInDungeons = false }), inInstance = true, instanceType = "party", difficultyID = 23, expect = false },
                { db = db(), inInstance = true, instanceType = "scenario", difficultyID = TS.DELVE_DIFFICULTY_ID, expect = true },
            }
            for _, v in ipairs(variants) do
                assert.equals(v.expect, TS.ShouldShowForInstance(v.db, v.inInstance, v.instanceType, v.difficultyID))
            end
        end)

        it("hides raids/arena-bg/open world by default, shows when checked", function()
            local variants = {
                { db = db(), inInstance = true, instanceType = "raid", difficultyID = 16, expect = false },
                { db = db({ ShowInRaids = true }), inInstance = true, instanceType = "raid", difficultyID = 16, expect = true },
                { db = db(), inInstance = true, instanceType = "arena", difficultyID = 0, expect = false },
                { db = db({ ShowInPvP = true }), inInstance = true, instanceType = "pvp", difficultyID = 0, expect = true },
                { db = db(), inInstance = false, instanceType = nil, difficultyID = nil, expect = false },
                { db = db({ ShowInOpenWorld = true }), inInstance = false, instanceType = nil, difficultyID = nil, expect = true },
            }
            for _, v in ipairs(variants) do
                assert.equals(v.expect, TS.ShouldShowForInstance(v.db, v.inInstance, v.instanceType, v.difficultyID))
            end
        end)

        it("treats non-delve scenarios as open world", function()
            assert.is_false(TS.ShouldShowForInstance(db(), true, "scenario", 1))
            assert.is_true(TS.ShouldShowForInstance(db({ ShowInOpenWorld = true }), true, "scenario", 1))
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

    end)
end)
