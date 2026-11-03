-- The Position Settings card's Anchored To reset rule. The reset's writes and
-- its single change callback are card code and stay an in-game check.
local L = require("dev.spec._ke_loader")

describe("PositionCardRules.CrossesKind", function()
    it("is true only between a frame type and a screen type", function()
        local Rules = L.loadPositionCardRules()
        local cases = {
            { "SELECTFRAME", "SCREEN", true },
            { "SELECTFRAME", "UIPARENT", true },
            { "PLAYERFRAME", "SCREEN", true },
            { "PLAYERFRAME", "UIPARENT", true },
            { "SCREEN", "SELECTFRAME", true },
            { "UIPARENT", "PLAYERFRAME", true },
            { "SELECTFRAME", "PLAYERFRAME", false },
            { "PLAYERFRAME", "SELECTFRAME", false },
            { "SCREEN", "UIPARENT", false },
            { "UIPARENT", "SCREEN", false },
            { "SELECTFRAME", "SELECTFRAME", false },
            { "SCREEN", "SCREEN", false },
            { "UNKNOWN", "SELECTFRAME", true },
            { "UNKNOWN", "UIPARENT", false },
        }
        for _, c in ipairs(cases) do
            assert.are.equal(c[3], Rules.CrossesKind(c[1], c[2]), c[1] .. " to " .. c[2])
        end
    end)
end)
