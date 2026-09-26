-- Core/Globals.lua -- the per-spec gate. Absent means enabled, so the branch
-- that tells "nothing stored" from "stored off" is the one a later edit breaks
-- silently: get it backwards and every untouched profile loses the module on
-- update. The lifecycles around it are event-driven and verified in game.
local L = require("dev.spec._ke_loader")

describe("KE:IsSpecEnabled", function()
    local KE

    before_each(function()
        KE = L.loadGlobals()
    end)

    it("refuses a spec that was explicitly turned off", function()
        assert.is_false(KE:IsSpecEnabled({ [1473] = false }, 1473))
    end)

    it("allows a spec with nothing, or true, stored against it", function()
        local cases = {
            { name = "true stored",            specs = { [1473] = true } },
            { name = "another spec's opt-out", specs = { [1467] = false } },
            { name = "empty table",            specs = {} },
            { name = "no table",               specs = nil },
        }
        for _, case in ipairs(cases) do
            assert.is_true(KE:IsSpecEnabled(case.specs, 1473), case.name)
        end
    end)

    it("allows every spec when none can be resolved", function()
        assert.is_true(KE:IsSpecEnabled({ [1473] = false }, nil))
    end)
end)
