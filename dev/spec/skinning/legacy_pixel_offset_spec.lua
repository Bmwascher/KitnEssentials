-- Tier: KE-invented arithmetic (AGENTS.md, What gets a spec). The offset that
-- moves the reward level box onto the physical pixel grid.

local helpers = require("dev.spec._helpers")

local function loadSkin()
    local S = {}
    helpers.loadModule("Modules/Skinning/DarkTheme/Frames/LegacyChallenges.lua", { Skins = S })
    return S
end

describe("Legacy reward level box pixel offset", function()
    it("moves a coordinate to the nearest whole pixel of the given size", function()
        local offset = loadSkin()._LegacyPixelOffset
        -- value, pixel size, expected offset
        local cases = {
            { 405.5, 1, 0.5 },
            { 1016.4, 1, -0.4 },
            { 300, 1, 0 },
            { 100.3, 0.5, 0.2 },
            { 100.2, 0.5, -0.2 },
        }
        for _, c in ipairs(cases) do
            assert.is_true(math.abs(offset(c[1], c[2]) - c[3]) < 1e-9)
        end
    end)
end)
