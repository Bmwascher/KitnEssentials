-- Tier 1: the light-color test (Core/AddonTheme.lua, KE.IsLightColor) that
-- turns settings-window text dark on a light accent. The rows sit at the
-- edges of the threshold: the lightest preset color above it and the
-- brightest below it.
local L = require("dev.spec._ke_loader")

describe("KE.IsLightColor", function()
    it("is true above the 0.6 luminance line and false below it", function()
        local KE = L.loadAddonTheme()
        local cases = {
            { name = "white", r = 1, g = 1, b = 1, want = true },
            { name = "Sunwell gold, 0.698", r = 1.0, g = 0.843, b = 0.0, want = true },
            { name = "Dreamsurge green, 0.455", r = 0.125, g = 0.816, b = 0.043, want = false },
        }
        for _, case in ipairs(cases) do
            assert.are.equal(case.want, KE.IsLightColor(case.r, case.g, case.b), case.name)
        end
    end)
end)
