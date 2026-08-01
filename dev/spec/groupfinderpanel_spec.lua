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

describe("GroupFinderPanel SanitizeResult", function()
    local function load(secretFields)
        secretFields = secretFields or {}
        return loader.loadGroupFinderPanel({
            issecretvalue = function(v)
                for _, s in ipairs(secretFields) do if rawequal(v, s) then return true end end
                return false
            end,
        })
    end

    local info
    before_each(function()
        info = {
            activityIDs = { 42 },
            numMembers = 3,
            numBNetFriends = 1, numCharFriends = 0, numGuildMates = 2,
            leaderOverallDungeonScore = 2500,
            leaderBestDungeonScoreInfo = { mapScore = 180 },
        }
    end)

    it("derives plain values when nothing is secret", function()
        local GFP = load()
        _G.C_LFGList.GetActivityInfoTable = function() return { groupFinderActivityGroupID = 7 } end
        _G.C_LFGList.GetSearchResultPlayerInfo = function() return { assignedRole = "DAMAGER" } end
        local rec = GFP._SanitizeResult(1, info, true, true)
        assert.is_true(rec.gidKnown)
        assert.equals(7, rec.gid)
        assert.equals(3, rec.roles.DAMAGER)
        assert.equals(3, rec.friends)
        assert.equals(2500, rec.overall)
        assert.equals(180, rec.leaderScore)
    end)

    it("returns no raw API field -- the record is newly constructed", function()
        local GFP = load()
        _G.C_LFGList.GetActivityInfoTable = function() return { groupFinderActivityGroupID = 7 } end
        _G.C_LFGList.GetSearchResultPlayerInfo = function() return { assignedRole = "TANK" } end
        local rec = GFP._SanitizeResult(1, info, true, true)
        assert.is_false(rawequal(rec.roles, info))
        assert.is_false(rawequal(rec.leaderScore, info.leaderBestDungeonScoreInfo))
    end)

    it("zeroes a secret score rather than carrying it", function()
        local GFP = load({ 2500 })
        local rec = GFP._SanitizeResult(1, info, false, false)
        assert.equals(0, rec.overall)
    end)

    it("reports the group as UNKNOWN when numMembers is secret, and keeps roles nil", function()
        local GFP = load({ 3 })
        local rec = GFP._SanitizeResult(1, info, false, true)
        assert.is_nil(rec.roles)
    end)

    it("skips a secret role rather than using it as a table key", function()
        local GFP = load({ "HEALER" })
        _G.C_LFGList.GetSearchResultPlayerInfo = function() return { assignedRole = "HEALER" } end
        local rec = GFP._SanitizeResult(1, info, false, true)
        assert.equals(0, rec.roles.HEALER)
    end)

    it("zeroes friend counts when any one of the three is secret", function()
        local GFP = load({ 2 })  -- numGuildMates
        local rec = GFP._SanitizeResult(1, info, false, false)
        assert.equals(0, rec.friends)
    end)

    it("fails OPEN -- a throwing guard yields neutral values, not a dropped result", function()
        local GFP = loader.loadGroupFinderPanel({
            issecretvalue = function() error("simulated taint throw") end,
        })
        local rec = GFP._SanitizeResult(1, info, true, true)
        assert.equals(0, rec.overall)
        assert.is_false(rec.gidKnown)
        assert.is_nil(rec.roles)
    end)
end)

describe("GroupFinderPanel SanitizeScore", function()
    it("fails CLOSED on a secret score", function()
        local GFP = loader.loadGroupFinderPanel({
            issecretvalue = function(v) return v == 2500 end,
        })
        _G.C_LFGList.GetSearchResultInfo = function()
            return { leaderOverallDungeonScore = 2500 }
        end
        assert.is_nil(GFP._SanitizeScore(1))
    end)

    it("returns nil for a zero score", function()
        local GFP = loader.loadGroupFinderPanel()
        _G.C_LFGList.GetSearchResultInfo = function()
            return { leaderOverallDungeonScore = 0 }
        end
        assert.is_nil(GFP._SanitizeScore(1))
    end)

    it("returns the score when readable and non-zero", function()
        local GFP = loader.loadGroupFinderPanel()
        _G.C_LFGList.GetSearchResultInfo = function()
            return { leaderOverallDungeonScore = 1800 }
        end
        assert.equals(1800, GFP._SanitizeScore(1))
    end)
end)
