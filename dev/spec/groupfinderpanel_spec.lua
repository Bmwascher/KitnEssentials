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
            assert.equals("WS", abbrev("Windrunner Spire"))
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

-- The guard this pins: GetSearchResultInfo reads the secret listing table, so
-- calling it from the LFGListSearchEntry_Update hook marks Blizzard's own
-- execution and their next read of activityIDs throws. A later edit that puts
-- the call back into the row hook breaks that silently in game.
describe("GroupFinderPanel score cache", function()
    it("fills from the panel's result list", function()
        local GFP = loader.loadGroupFinderPanel()
        _G.C_LFGList.GetSearchResultInfo = function(id)
            return { leaderOverallDungeonScore = id * 100 }
        end
        GFP._RefreshScoreCache({ results = { 3, 7 } })
        assert.equals(300, GFP._ScoreCache[3])
        assert.equals(700, GFP._ScoreCache[7])
    end)

    it("drops entries that are no longer in the list", function()
        local GFP = loader.loadGroupFinderPanel()
        _G.C_LFGList.GetSearchResultInfo = function() return { leaderOverallDungeonScore = 100 } end
        GFP._RefreshScoreCache({ results = { 1 } })
        GFP._RefreshScoreCache({ results = { 2 } })
        assert.is_nil(GFP._ScoreCache[1])
        assert.equals(100, GFP._ScoreCache[2])
    end)

    it("survives a panel with no results yet", function()
        local GFP = loader.loadGroupFinderPanel()
        GFP._RefreshScoreCache({})
        GFP._RefreshScoreCache(nil)
        assert.is_nil(next(GFP._ScoreCache))
    end)

    it("decorating a row reads the cache and never calls the search-result API", function()
        local GFP = loader.loadGroupFinderPanel()
        local calls = 0
        _G.C_LFGList.GetSearchResultInfo = function()
            calls = calls + 1
            return { leaderOverallDungeonScore = 1800 }
        end
        GFP._RefreshScoreCache({ results = { 1 } })
        assert.equals(1, calls) -- the cache fill is allowed to call it
        calls = 0

        -- Both of DecorateSearchEntry's gates have to pass, or the assertion
        -- below counts an early return instead of a cache read.
        GFP.db = { Enabled = true }
        _G.LFGListPVEStub = {}
        _G.PVEFrame = { activeTabIndex = 1 }
        _G.GroupFinderFrame = { selection = _G.LFGListPVEStub }
        _G.LFGListFrame = {
            SearchPanel = { IsShown = function() return true end, categoryID = 2 },
        }

        local decorated
        local entry = {
            resultID = 1,
            Name = {
                SetFormattedText = function(_, ...) decorated = { ... } end,
                GetText = function() return "Some Group" end,
            },
        }
        GFP._DecorateSearchEntry(entry)
        -- Proves the gates let this row through, so the zero below is a real
        -- result rather than an early return.
        -- decorated is the SetFormattedText varargs: format, hex, score, name.
        assert.is_table(decorated)
        assert.equals(1800, decorated[3])
        assert.equals(0, calls)
    end)
end)

describe("GroupFinderPanel lifecycle", function()
    it("is inactive when PGF is loaded, even with Enabled true", function()
        local GFP = loader.loadGroupFinderPanel({
            C_AddOns = { IsAddOnLoaded = function(n) return n == "PremadeGroupsFilter" end },
        })
        GFP.db.Enabled = true
        assert.is_true(GFP._PGFPresent())
        assert.is_false(GFP._IsActive())
    end)

    it("is inactive when disabled, even without PGF", function()
        local GFP = loader.loadGroupFinderPanel()
        GFP.db.Enabled = false
        assert.is_false(GFP._IsActive())
    end)

    it("is active when enabled and PGF is absent", function()
        local GFP = loader.loadGroupFinderPanel()
        GFP.db.Enabled = true
        assert.is_true(GFP._IsActive())
    end)

    it("takes the FIRST IsAddOnLoaded return, not the second", function()
        -- loadedOrLoading true, loaded false: a conflict bail must still fire.
        local GFP = loader.loadGroupFinderPanel({
            C_AddOns = { IsAddOnLoaded = function() return true, false end },
        })
        assert.is_true(GFP._PGFPresent())
    end)

    it("carries the six session keys across an enabled-to-enabled switch", function()
        local GFP, KE = loader.loadGroupFinderPanel()
        GFP.db.Enabled = true
        GFP.db.SortBy = "OVERALL_SCORE"
        GFP.db.HasTank = true
        GFP.db.DungeonFilter[7] = true
        local incoming = { Enabled = true, DungeonFilter = { [99] = true }, SortBy = "DEFAULT",
                           HasTank = false, HasHealer = false, PartyFit = false,
                           SortDescending = true }
        KE.db.profile.GroupFinderPanel = incoming
        GFP:UpdateDB()
        assert.equals("OVERALL_SCORE", GFP.db.SortBy)
        assert.is_true(GFP.db.HasTank)
        assert.is_true(GFP.db.DungeonFilter[7])
        assert.is_nil(GFP.db.DungeonFilter[99])
    end)

    it("COPIES DungeonFilter rather than aliasing it", function()
        local GFP, KE = loader.loadGroupFinderPanel()
        GFP.db.Enabled = true
        GFP.db.DungeonFilter[7] = true
        local old = GFP.db
        KE.db.profile.GroupFinderPanel = { Enabled = true, DungeonFilter = {} }
        GFP:UpdateDB()
        assert.is_false(rawequal(old.DungeonFilter, GFP.db.DungeonFilter))
        GFP.db.DungeonFilter[8] = true
        assert.is_nil(old.DungeonFilter[8])
    end)

    it("does not carry state when the incoming profile has the module off", function()
        local GFP, KE = loader.loadGroupFinderPanel()
        GFP.db.Enabled = true
        GFP.db.SortBy = "OVERALL_SCORE"
        KE.db.profile.GroupFinderPanel = { Enabled = false, DungeonFilter = {}, SortBy = "DEFAULT" }
        GFP:UpdateDB()
        assert.equals("DEFAULT", GFP.db.SortBy)
    end)

    it("sanitizes an unknown saved sort mode", function()
        local GFP, KE = loader.loadGroupFinderPanel()
        KE.db.profile.GroupFinderPanel.SortBy = "NO_SUCH_MODE"
        -- SetEnabledState is an Ace module lifecycle method; installAddonShim
        -- deliberately leaves those unstubbed (see _ke_loader.lua's
        -- loadLFGReminder note), so a test that drives OnInitialize stubs it.
        GFP.SetEnabledState = function() end
        GFP:OnInitialize()
        assert.equals("DEFAULT", GFP.db.SortBy)
    end)
end)
