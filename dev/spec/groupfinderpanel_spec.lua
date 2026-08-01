-- `dev.spec.` is the path form busted resolves from the repo root, and it is
-- what all 26 sibling specs use. `spec._ke_loader` does not load.
local loader = require("dev.spec._ke_loader")

describe("GroupFinderPanel pure helpers", function()
    describe("Abbreviate", function()
        local abbrev
        before_each(function()
            local _, _, seams = loader.loadGroupFinderPanel()
            abbrev = seams.abbreviate
        end)

        it("prefers the override table", function()
            assert.equals("WRS", abbrev("Windrunner Spire"))
        end)

        it("takes initials of a plain multi-word name", function()
            assert.equals("TD", abbrev("Test Dungeon"))
        end)

        it("drops of/the/and", function()
            assert.equals("HF", abbrev("Halls of the Fallen"))
        end)

        it("splits on hyphens", function()
            assert.equals("BRD", abbrev("Black-Rock Depths"))
        end)

        it("splits on apostrophes", function()
            -- The apostrophe is a word boundary in the gmatch pattern, so
            -- "Kael'thas" is two words ("Kael", "thas"), not one -- initials
            -- are K, T, C, not K, C.
            assert.equals("KTC", abbrev("Kael'thas Citadel"))
        end)

        it("falls back to four uppercased characters when the initials are too short", function()
            -- One word, no stop word: initials give "D", which is under the
            -- two-character floor, so the fallback takes the first four
            -- characters uppercased.
            assert.equals("DEEP", abbrev("Deep"))
        end)
    end)

    describe("GetPartyRoles", function()
        it("counts the player's spec role when solo", function()
            local _, _, seams = loader.loadGroupFinderPanel({
                IsInGroup = function() return false end,
            })
            local roles = seams.getPartyRoles()
            assert.equals(1, roles.DAMAGER)
            assert.equals(0, roles.TANK)
        end)

        it("falls back to the spec role when assigned is NONE in a group", function()
            local _, _, seams = loader.loadGroupFinderPanel({
                IsInGroup = function() return true end,
                GetNumGroupMembers = function() return 1 end,
                UnitGroupRolesAssigned = function() return "NONE" end,
            })
            assert.equals(1, seams.getPartyRoles().DAMAGER)
        end)
    end)

    describe("SORT_MODE comparators", function()
        it("orders by overall score", function()
            local _, _, seams = loader.loadGroupFinderPanel()
            local f = seams.sortMode.OVERALL_SCORE.func
            assert.equals(1, f({ overall = 3000 }, { overall = 2000 }))
            assert.equals(-1, f({ overall = 1000 }, { overall = 2000 }))
            assert.equals(0, f({ overall = 2000 }, { overall = 2000 }))
        end)

        it("orders by this dungeon's leader score", function()
            local _, _, seams = loader.loadGroupFinderPanel()
            local f = seams.sortMode.DUNGEON_SCORE.func
            assert.equals(1, f({ leaderScore = 200 }, { leaderScore = 100 }))
        end)

        it("has no comparator for DEFAULT", function()
            local _, _, seams = loader.loadGroupFinderPanel()
            assert.is_nil(seams.sortMode.DEFAULT.func)
        end)
    end)

    describe("PlayerSpecRole", function()
        it("returns nil rather than calling a deprecated global when the API is absent", function()
            local _, _, seams = loader.loadGroupFinderPanel({
                C_SpecializationInfo = {},
            })
            assert.is_nil(seams.playerSpecRole())
        end)
    end)
end)
