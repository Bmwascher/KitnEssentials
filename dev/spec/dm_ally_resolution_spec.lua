-- ╔══════════════════════════════════════════════════════════╗
-- ║  dev/spec/dm_ally_resolution_spec.lua                    ║
-- ║  Roster join decision table for an in-combat ally row.   ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- WHY THIS EARNS A SPEC: it is a refusal rule whose wrong answers produce no
-- error. A bad match fetches another player's damage and renders it under the
-- clicked row's name. Each refusing case below is one no other check covers, and
-- the same-class-same-spec case cannot be smoked at all right now (no twin pair
-- is available), so this file is its only evidence.
--
-- MatchRowToRoster is PURE over a plain table, so there is no fake of
-- C_DamageMeter here and none is needed. Membership tables are written inline.
local L = require("dev.spec._ke_loader")

local DM

local function member(guid, class, spec)
    return { guid = guid, class = class, spec = spec }
end

before_each(function()
    DM = L.loadDMCore({})
    assert(DM and DM.MatchRowToRoster, "loadDMCore did not expose DM.MatchRowToRoster")
    -- Not managed by the mock's defaults; OnRosterChanged reads it through
    -- DetailCombatActive, so it only has to exist by the time a case calls that.
    _G.UnitAffectingCombat = function() return false end
end)

describe("MatchRowToRoster resolves only when exactly one member can be meant", function()
    it("resolves a lone member of the row's class, whatever the spec", function()
        local members = {
            member("guid-war", "WARRIOR", 1), member("guid-mage", "MAGE", 2),
        }
        for _, rowSpec in ipairs({ 1, 0, false }) do
            local spec = rowSpec ~= false and rowSpec or nil
            local guid, why = DM.MatchRowToRoster(members, "WARRIOR", spec, 1)
            assert.equals("guid-war", guid)
            assert.is_nil(why)
        end
    end)

    it("breaks a same-class tie on the spec when both specs are known", function()
        local members = {
            member("guid-fury", "WARRIOR", 11), member("guid-arms", "WARRIOR", 22),
        }
        assert.equals("guid-arms", DM.MatchRowToRoster(members, "WARRIOR", 22, 2, { [11] = 1, [22] = 1 }))
    end)
end)

describe("MatchRowToRoster refuses rather than guessing", function()
    it("refuses two members sharing class AND spec -- the twin case", function()
        local members = {
            member("guid-twin-a", "WARRIOR", 11), member("guid-twin-b", "WARRIOR", 11),
        }
        local guid, why = DM.MatchRowToRoster(members, "WARRIOR", 11, 2)
        assert.is_nil(guid)
        assert.equals("ambiguous", why)
    end)

    it("refuses a same-class tie when the ROW's spec is unknown", function()
        local members = {
            member("guid-fury", "WARRIOR", 11), member("guid-arms", "WARRIOR", 22),
        }
        -- nil is an unresolved pug member; 0 is what the client reports for a mob.
        for _, rowSpec in ipairs({ "nil", 0 }) do
            local spec = rowSpec ~= "nil" and rowSpec or nil
            local guid, why = DM.MatchRowToRoster(members, "WARRIOR", spec, 2)
            assert.is_nil(guid)
            assert.equals("specunknown", why)
        end
    end)

    it("refuses a same-class tie when a CANDIDATE's spec is unknown", function()
        -- The unknown candidate could BE the row. Narrowing to the one known
        -- match here is exactly how a half-resolved roster resolves by default.
        local members = {
            member("guid-known", "WARRIOR", 11), member("guid-unknown", "WARRIOR", nil),
        }
        local guid, why = DM.MatchRowToRoster(members, "WARRIOR", 11, 2)
        assert.is_nil(guid)
        assert.equals("specunknown", why)
    end)

    it("refuses a poisoned roster index", function()
        local guid, why = DM.MatchRowToRoster(nil, "WARRIOR", 11, 1)
        assert.is_nil(guid)
        assert.equals("roster", why)
    end)

    it("refuses a row with no class -- an enemy mob reports empty", function()
        local members = { member("guid-war", "WARRIOR", 11) }
        for _, rowClass in ipairs({ "", "nil" }) do
            local cls = rowClass ~= "nil" and rowClass or nil
            local guid, why = DM.MatchRowToRoster(members, cls, 11, 1)
            assert.is_nil(guid)
            assert.equals("noclass", why)
        end
    end)

    it("refuses when the session has MORE sources of the class than the group has", function()
        -- A departed player's row outlives their group membership. A class-bearing
        -- entity is present that the roster cannot account for, and nothing says
        -- which row is which.
        local members = { member("guid-war", "WARRIOR", 11) }
        local guid, why = DM.MatchRowToRoster(members, "WARRIOR", 11, 2)
        assert.is_nil(guid)
        assert.equals("surplus", why)
    end)

    it("lets a player and a same-class ally resolve -- the tally excludes the own row", function()
        -- Both sides must describe the same population. The roster excludes the
        -- player, so the row tally must too. Counting the own row on one side
        -- only made a player and an ally of one class refuse each other as a
        -- surplus.
        local members = { member("guid-ally-war", "WARRIOR", 11) }
        assert.equals("guid-ally-war", DM.MatchRowToRoster(members, "WARRIOR", 11, 1))
    end)

    it("refuses when the row count is missing rather than assuming one", function()
        local members = { member("guid-war", "WARRIOR", 11) }
        local guid, why = DM.MatchRowToRoster(members, "WARRIOR", 11, nil)
        assert.is_nil(guid)
        assert.equals("rowcount", why)
    end)

    it("refuses a class nobody in the group has", function()
        local members = { member("guid-mage", "MAGE", 2) }
        local guid, why = DM.MatchRowToRoster(members, "WARRIOR", 11, 1)
        assert.is_nil(guid)
        assert.equals("nomatch", why)
    end)
end)

-- BuildRosterIndex calls IsInRaid/IsInGroup/GetNumGroupMembers/UnitGUID/
-- UnitClass directly with no injectable seam, so there is no pure predicate
-- to extract this onto -- the fake is the only way to drive it.
describe("BuildRosterIndex fails closed on an unreadable member", function()
    local SECRET = { __secret = true }

    local function loadWithRoster(classOf, guidOf)
        return L.loadDMCore({
            IsInRaid = function() return false end,
            IsInGroup = function() return true end,
            GetNumGroupMembers = function() return 4 end,
            UnitExists = function(u) return classOf[u] ~= nil end,
            UnitGUID = function(u)
                if u == "player" then return "guid-player" end
                return guidOf[u]
            end,
            UnitClass = function(u) return "Localized", classOf[u] end,
        })
    end

    it("returns every readable member when the whole roster reads plain", function()
        local dm = loadWithRoster(
            { party1 = "WARRIOR", party2 = "MAGE" },
            { party1 = "guid-1",  party2 = "guid-2" })
        local members = dm.BuildRosterIndex()
        assert.equals(2, #members)
        assert.equals("WARRIOR", members[1].class)
        assert.equals("guid-1", members[1].guid)
    end)

    it("returns nil -- NOT the readable remainder -- when one member is secret", function()
        -- The failure this defends: dropping the unreadable warrior leaves ONE
        -- warrior in the index, so a warrior row resolves to whichever one was
        -- readable, with no error and to the wrong player.
        local dm = loadWithRoster(
            { party1 = "WARRIOR", party2 = "WARRIOR" },
            { party1 = "guid-1",  party2 = SECRET })
        assert.is_nil(dm.BuildRosterIndex())
    end)

    it("returns nil when a member's CLASS is secret", function()
        local dm = L.loadDMCore({
            IsInRaid = function() return false end,
            IsInGroup = function() return true end,
            GetNumGroupMembers = function() return 4 end,
            UnitExists = function(u) return u == "party1" end,
            UnitGUID = function() return "guid-1" end,
            UnitClass = function() return "Localized", SECRET end,
        })
        assert.is_nil(dm.BuildRosterIndex())
    end)

    it("skips an ABSENT unit rather than poisoning -- an empty slot is not a member", function()
        local dm = loadWithRoster({ party1 = "WARRIOR" }, { party1 = "guid-1" })
        local members = dm.BuildRosterIndex()
        assert.equals(1, #members)
    end)

    it("excludes the local player, so a player+ally same-spec pair still resolves", function()
        local dm = loadWithRoster(
            { party1 = "WARRIOR" },
            { party1 = "guid-player" })
        assert.equals(0, #dm.BuildRosterIndex())
    end)

    it("returns an empty index when solo", function()
        local dm = L.loadDMCore({
            IsInRaid = function() return false end,
            IsInGroup = function() return false end,
        })
        assert.equals(0, #dm.BuildRosterIndex())
    end)
end)

describe("MatchRowToRoster one-row guard", function()
    it("refuses a known match unless every member has one row, every row's spec is known and this spec has one row", function()
        -- A member whose recorded spec is out of date (or a departed player's row)
        -- may hold the claimed spec, so the claim cannot say which row is whose.
        local members = {
            member("guid-stale", "SHAMAN", 11), member("guid-resto", "SHAMAN", 22),
        }
        local cases = {
            { name = "two rows of the spec", rows = 2, specRows = { [22] = 2 }, why = "ambiguous" },
            { name = "no per-spec row counts", rows = 2, specRows = nil, why = "ambiguous" },
            { name = "another row's spec unknown", rows = 2, specRows = { [22] = 1, [0] = 1 }, why = "specunknown" },
            { name = "a member with no row", rows = 1, specRows = { [22] = 1 }, why = "rowless" },
        }
        for _, c in ipairs(cases) do
            local guid, why = DM.MatchRowToRoster(members, "SHAMAN", 22, c.rows, c.specRows)
            assert.is_nil(guid, c.name)
            assert.equals(c.why, why, c.name)
        end
    end)
end)

describe("The meter's own spec as a roster source", function()
    it("is read before the LibSpec spec", function()
        local dm = L.loadDMCore({
            IsInRaid = function() return false end,
            IsInGroup = function() return true end,
            GetNumGroupMembers = function() return 3 end,
            UnitExists = function(u) return u == "party1" or u == "party2" end,
            UnitGUID = function(u)
                if u == "player" then return "guid-player" end
                return ({ party1 = "guid-1", party2 = "guid-2" })[u]
            end,
            UnitClass = function() return "Localized", "SHAMAN" end,
        })
        dm.meterSpecByGUID["guid-1"] = 262
        dm.specIconByGUID["guid-1"] = 999
        dm.specIconByGUID["guid-2"] = 264
        local members = dm.BuildRosterIndex()
        assert.equals(262, members[1].spec)
        assert.equals(264, members[2].spec)
    end)

    it("records neither a forgotten member nor someone outside the harvestable set", function()
        local harvestable = { ["guid-1"] = true, ["guid-2"] = true }
        DM:ForgetMeterSpec("guid-1")
        local cases = {
            { name = "a forgotten member", guid = "guid-1" },
            { name = "not harvestable", guid = "guid-left" },
        }
        for _, c in ipairs(cases) do
            DM.HarvestMeterSpec(DM.meterSpecByGUID, DM._meterSpecBlocked, harvestable,
                { sourceGUID = c.guid, specIconID = 262 })
            assert.is_nil(DM.meterSpecByGUID[c.guid], c.name)
        end
        -- Control: a harvestable member nobody forgot is recorded.
        DM.HarvestMeterSpec(DM.meterSpecByGUID, DM._meterSpecBlocked, harvestable,
            { sourceGUID = "guid-2", specIconID = 264 })
        assert.equals(264, DM.meterSpecByGUID["guid-2"])
    end)
end)

describe("The harvestable set", function()
    it("drops a member who left, even while nothing is recorded", function()
        local dm = L.loadDMCore({
            IsInRaid = function() return false end,
            IsInGroup = function() return true end,
            GetNumGroupMembers = function() return 2 end,
            UnitExists = function(u) return u == "party1" end,
            UnitGUID = function(u)
                if u == "player" then return "guid-player" end
                return ({ party1 = "guid-1" })[u]
            end,
            UnitClass = function() return "Localized", "SHAMAN" end,
        })
        dm._specHarvestSet["guid-1"] = true
        dm._specHarvestSet["guid-left"] = true
        dm:OnRosterChanged()
        assert.is_true(dm._specHarvestSet["guid-1"])
        assert.is_nil(dm._specHarvestSet["guid-left"])
    end)
end)

describe("MatchRowToRoster leaver refusal", function()
    it("refuses with 'leaver' on the lone-member path and the spec tie-break", function()
        -- A departed member's row stays in the session and can balance a
        -- same-class member who has no row yet.
        local cases = {
            { name = "lone member", spec = 11, rows = 1, specRows = { [11] = 1 },
              members = { member("guid-war", "WARRIOR", 11) } },
            { name = "spec tie-break", spec = 22, rows = 2, specRows = { [11] = 1, [22] = 1 },
              members = { member("guid-fury", "WARRIOR", 11), member("guid-arms", "WARRIOR", 22) } },
        }
        for _, c in ipairs(cases) do
            local guid, why = DM.MatchRowToRoster(c.members, "WARRIOR", c.spec, c.rows, c.specRows, true)
            assert.is_nil(guid, c.name)
            assert.equals("leaver", why, c.name)
        end
    end)
end)

describe("Leaver marking", function()
    it("marks the class of a fight member no longer in the group, and only theirs", function()
        local fightMembers = { ["guid-1"] = "SHAMAN", ["guid-2"] = "MAGE" }
        local leaverClass = {}
        DM.MarkLeavers(fightMembers, { ["guid-2"] = true }, leaverClass)
        assert.is_true(leaverClass.SHAMAN)
        assert.is_nil(leaverClass.MAGE)
    end)
end)

describe("Leaver refusal on Overall", function()
    it("refuses a class that lost a member since the meter reset, only on Overall", function()
        -- An Overall row outlives its owner's membership, so a departed
        -- member's row can balance a same-class member who has no row there.
        DM._leaverUnknown = false
        local cases = {
            { name = "Overall, a leaver's class", classes = { SHAMAN = true }, overall = true, want = true },
            { name = "Overall, leavers unknown", unknown = true, overall = true, want = true },
            { name = "Overall, another class", classes = { MAGE = true }, overall = true, want = false },
            { name = "not Overall", classes = { SHAMAN = true }, unknown = true, overall = false, want = false },
        }
        for _, c in ipairs(cases) do
            DM._overallLeaverClass = c.classes or {}
            DM._overallLeaverUnknown = c.unknown == true
            assert.equals(c.want, DM:LeaverRefused("SHAMAN", c.overall), c.name)
        end
    end)
end)

describe("Recording Overall's rows", function()
    it("records plain ally rows, skips the own row, and reports a secret GUID", function()
        local SECRET = { __secret = true }
        local overallMembers, leaverClass = {}, {}
        local complete = DM.AddOverallSources({
            { classFilename = "SHAMAN", sourceGUID = SECRET, isLocalPlayer = false },
            { classFilename = "MAGE", sourceGUID = "guid-gone", isLocalPlayer = false },
            { classFilename = "PRIEST", sourceGUID = "guid-me", isLocalPlayer = true },
        }, overallMembers)
        assert.is_false(complete)
        assert.is_nil(overallMembers["guid-me"])
        DM.MarkLeavers(overallMembers, { ["guid-here"] = true }, leaverClass)
        assert.is_true(leaverClass.MAGE)
    end)
end)

describe("GroupGUIDSet leaves the player out", function()
    -- A two-member raid whose first raid token is the player.
    local function loadRaid(playerGUID)
        return L.loadDMCore({
            IsInRaid = function() return true end,
            IsInGroup = function() return true end,
            GetNumGroupMembers = function() return 2 end,
            UnitExists = function(u) return u == "raid1" or u == "raid2" end,
            UnitGUID = function(u)
                if u == "player" then return playerGUID end
                return ({ raid1 = "guid-player", raid2 = "guid-2" })[u]
            end,
            UnitClass = function(u) return "Localized", ({ raid1 = "PRIEST", raid2 = "MAGE" })[u] end,
        })
    end

    it("drops the player's GUID from a raid's set and classes", function()
        -- Raid tokens include the player. Recorded, the player's class would be
        -- marked a leaver when the raid becomes a party.
        local classes = {}
        local set = loadRaid("guid-player"):GroupGUIDSet(classes)
        assert.is_nil(set["guid-player"])
        assert.is_nil(classes["guid-player"])
        assert.is_true(set["guid-2"])
        assert.equals("MAGE", classes["guid-2"])
    end)

    it("returns nil when the player's GUID cannot be read", function()
        -- Unknown, as for an unreadable member: the walk cannot tell the player
        -- from anyone else.
        assert.is_nil(loadRaid(nil):GroupGUIDSet({}))
    end)
end)

describe("ResolveAllyGUID on a pinned window", function()
    it("refuses an ally on a window pinned to a stored native session that the same roster resolves unpinned", function()
        -- Only a native pin refuses: the fallback is not a pin, and a History
        -- pin's rows are fetched by their own plain GUIDs.
        DM.RosterIndex = function() return { member("guid-sham", "SHAMAN", 262) } end
        DM._leaverUnknown = false
        local cases = {
            { name = "unpinned", W = {}, want = "guid-sham" },
            { name = "Current-empty fallback only", W = { _fallbackSessionID = 3 }, want = "guid-sham" },
            { name = "History pin", W = { _curSessionID = -1 }, want = "guid-sham" },
            { name = "native pin", W = { _curSessionID = 3 }, why = "pinned" },
        }
        for _, c in ipairs(cases) do
            local guid, why = DM:ResolveAllyGUID(c.W, "SHAMAN", 262, 1, { [262] = 1 }, false)
            assert.equals(c.want, guid, c.name)
            assert.equals(c.why, why, c.name)
        end
    end)
end)
