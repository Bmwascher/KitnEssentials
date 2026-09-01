-- IsValidUnit's Combat Only refusal rule: a guard, not a throws case --
-- UnitAffectingCombat's return is non-nilable, so this only ever refuses on
-- an explicit false.

local L = require("dev.spec._ke_loader")

local function load(opts)
    opts = opts or {}
    return L.loadDungeonCasts({ UnitAffectingCombat = opts.combat })
end

describe("DungeonCasts Combat Only gate", function()
    it("refuses a unit that is not affecting combat when the flag is on", function()
        local DC = load({ combat = function() return false end })
        DC.db = { Frame = { CombatOnly = true } }
        assert.is_false(DC:IsValidUnit("nameplate1"))
    end)

    it("allows a unit that is affecting combat when the flag is on", function()
        local DC = load({ combat = function() return true end })
        DC.db = { Frame = { CombatOnly = true } }
        assert.is_true(DC:IsValidUnit("nameplate1"))
    end)

    it("allows a unit out of combat when the flag is off", function()
        local DC = load({ combat = function() return false end })
        DC.db = { Frame = { CombatOnly = false } }
        assert.is_true(DC:IsValidUnit("nameplate1"))
    end)
end)
