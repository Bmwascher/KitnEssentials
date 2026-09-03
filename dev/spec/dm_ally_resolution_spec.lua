-- ╔══════════════════════════════════════════════════════════╗
-- ║  dev/spec/dm_ally_resolution_spec.lua                    ║
-- ║  Roster join decision table for an in-combat ally row.   ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- WHY THIS EARNS A SPEC: it is a refusal rule whose wrong answers are silent.
-- A bad match does not throw -- it fetches another player's damage and renders
-- it under the clicked row's name. Every row below that refuses is a row no
-- other check defends, and the same-class-same-spec case cannot currently be
-- smoked at all (no twin pair is available), so this file is its only evidence.
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
        assert.equals("guid-arms", DM.MatchRowToRoster(members, "WARRIOR", 22, 2))
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
        -- player, so the row tally must too; counting the own row on one side only
        -- made a player and an ally of one class refuse each other as a surplus.
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
        -- warrior in the index, so a warrior row resolves to whichever one
        -- happened to be readable. Silently, and to the wrong player.
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
