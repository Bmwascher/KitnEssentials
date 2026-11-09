-- Tier: KE-invented branching (AGENTS.md, What gets a spec). The pixel nudge
-- that centers outlined digits in the reward level box.

local helpers = require("dev.spec._helpers")

local function loadSkin()
    local S = {}
    helpers.loadModule("Modules/Skinning/DarkTheme/Frames/LegacyChallenges.lua", { Skins = S })
    return S
end

describe("Legacy reward level number ink nudge", function()
    it("nudges outlined text only", function()
        local nudge = loadSkin()._LegacyInkNudge
        -- font flags, expected whole pixels
        local cases = {
            { "OUTLINE, SLUG", 2 },
            { "outline", 2 },
            { "SLUG", 0 },
            { "", 0 },
            { nil, 0 },
        }
        for _, c in ipairs(cases) do
            assert.are.equal(c[2], nudge(c[1]))
        end
    end)
end)
