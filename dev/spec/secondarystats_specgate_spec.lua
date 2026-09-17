-- Modules/QoL/SecondaryStats.lua -- the per-spec gate. Absent means enabled, so
-- the branch that decides "nothing stored" from "stored off" is the one a later
-- edit breaks silently: get it backwards and every untouched profile loses the
-- readout on update. The lifecycle around it (which events are registered, when
-- the frame is torn down) is event-driven and is verified in game.
local L = require("dev.spec._ke_loader")

describe("SecondaryStats per-spec gate", function()
    local SS

    before_each(function()
        SS = L.loadSecondaryStats()
    end)

    it("refuses a spec that was explicitly turned off", function()
        assert.is_false(SS:IsSpecEnabled({ EnabledSpecs = { [1473] = false } }, 1473))
    end)

    it("allows a spec that carries an explicit true", function()
        assert.is_true(SS:IsSpecEnabled({ EnabledSpecs = { [1473] = true } }, 1473))
    end)

    it("allows a spec with nothing stored against it", function()
        -- Both shapes of "nothing stored": another spec's opt-out present, and
        -- no table at all. An untouched profile is the second one.
        assert.is_true(SS:IsSpecEnabled({ EnabledSpecs = { [1467] = false } }, 1473))
        assert.is_true(SS:IsSpecEnabled({}, 1473))
    end)

    it("allows the readout when no spec can be resolved", function()
        assert.is_true(SS:IsSpecEnabled({ EnabledSpecs = { [1473] = false } }, nil))
    end)
end)
