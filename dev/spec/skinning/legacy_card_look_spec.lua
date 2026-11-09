-- Tier: KE-invented branching (AGENTS.md, What gets a spec). The card look
-- mapping is the one rule in the Legacy page skin; the rest is smoke.

local helpers = require("dev.spec._helpers")

local function loadSkin()
    local S = {}
    helpers.loadModule("Modules/Skinning/DarkTheme/Frames/LegacyChallenges.lua", { Skins = S })
    return S
end

describe("Legacy challenge card look", function()
    it("maps selection, completion and account-wide to the border and title", function()
        local look = loadSkin()._LegacyCardLook
        -- selected, completed, accountWide, brandBorder, titleKey
        local cases = {
            { false, false, false, false, nil },
            { false, true, false, false, nil },
            { true, false, false, true, nil },
            { true, true, false, true, nil },
            { false, false, true, false, "accountDimmed" },
            { false, true, true, false, "account" },
            { true, false, true, true, "account" },
            { true, true, true, true, "account" },
        }
        for _, c in ipairs(cases) do
            local brandBorder, titleKey = look(c[1], c[2], c[3])
            assert.are.equal(c[4], brandBorder)
            assert.are.equal(c[5], titleKey)
        end
    end)
end)
