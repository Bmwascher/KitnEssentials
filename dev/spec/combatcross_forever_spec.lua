-- Tier 1: the Player Crosshair's Forever range choice
-- (Modules/Combat/CombatCrossForever.lua): which spell and type a class,
-- a talent role and position, and a shapeshift form get. Expected ids are
-- read from the module's own table, so no data cell is pinned.
local helpers = require("dev.spec._helpers")

-- The form id a row marks secret; the stand-in reports only that one.
local secretForm

local function loadRule()
    _G.KitnEssentials = _G.KitnEssentials or {}
    local KE = helpers.loadModule("Modules/Combat/CombatCrossForever.lua", {
        IsSecretValue = function(_, value) return value ~= nil and value == secretForm end,
    })
    return KE.CombatCrossForever
end

describe("Player Crosshair on Forever: range choice", function()
    it("picks the range spell and type from the form, role, position and class", function()
        local FV = loadRule()
        local S = FV.RANGE_SPELLS
        local none = function() return false end
        local all = function() return true end
        for _, row in ipairs({
            { name = "a Druid in Cat Form reads melee over a healer role", class = "DRUID", role = "HEALER", position = "RANGED", form = 1, known = none, want = S.DRUID.cat, kind = "melee" },
            { name = "a Druid in Dire Bear Form reads melee", class = "DRUID", role = "TANK", position = "MELEE", form = 8, known = none, want = S.DRUID.bear, kind = "melee" },
            { name = "a healer reads the healer spell", class = "PRIEST", role = "HEALER", position = "RANGED", known = all, want = S.PRIEST.healer, kind = "ranged" },
            { name = "a Druid out of form never reads melee", class = "DRUID", role = "TANK", position = "MELEE", known = all, want = S.DRUID.ranged, kind = "ranged" },
            { name = "melee takes the first known melee id", class = "SHAMAN", role = "DAMAGER", position = "MELEE", known = all, want = S.SHAMAN.melee[1], kind = "melee" },
            { name = "melee falls back to the last id when none is known", class = "SHAMAN", role = "DAMAGER", position = "MELEE", known = none, want = S.SHAMAN.melee[#S.SHAMAN.melee], kind = "melee" },
            { name = "ranged takes the ranged spell", class = "SHAMAN", role = "DAMAGER", position = "RANGED", known = all, want = S.SHAMAN.ranged, kind = "ranged" },
            { name = "no position: a default-melee class reads melee", class = "WARRIOR", role = "DAMAGER", known = all, want = S.WARRIOR.melee[1], kind = "melee" },
            { name = "no position: any other class reads ranged", class = "MAGE", role = "DAMAGER", known = all, want = S.MAGE.ranged, kind = "ranged" },
            { name = "a class with no ranged spell asked for ranged reads melee", class = "ROGUE", role = "DAMAGER", position = "RANGED", known = all, want = S.ROGUE.melee[1], kind = "melee" },
            { name = "a secret form counts as no form", class = "DRUID", role = "DAMAGER", position = "RANGED", form = 1, secret = 1, known = all, want = S.DRUID.ranged, kind = "ranged" },
        }) do
            secretForm = row.secret
            local spell, kind = FV.PickRange(row.class, row.role, row.position, row.form, row.known)
            assert.equals(row.want, spell, row.name)
            assert.equals(row.kind, kind, row.name)
        end
        secretForm = nil
        assert.is_nil(FV.PickRange("DEATHKNIGHT", "DAMAGER", "MELEE", nil, function() return true end), "an unknown class")
    end)
end)
