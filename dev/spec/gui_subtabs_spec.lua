-- Tier 1: GUI/GUIWidgets/GUI-KESubTabs.lua -- GUIFrame.SubTabOffset, the x of
-- each tab in a fill strip. Placement, the strip's passes and the look are
-- frame layout, checked in game.
local helpers = require("dev.spec._helpers")

describe("GUI-KESubTabs.lua fill tab offset", function()
    local GUIFrame

    before_each(function()
        -- The file makes its strip pool at load; nothing else runs.
        local KE = helpers.loadModule("GUI/GUIWidgets/GUI-KESubTabs.lua", {
            GUIFrame = { NewWidgetPool = function() return {} end },
            Theme = {},
        })
        GUIFrame = KE.GUIFrame
    end)

    it("adds every earlier width unrounded and one gap per earlier tab, from 0", function()
        local cases = {
            { name = "first tab",           widths = { 117.4, 137.2 },        spacing = 1, index = 1, x = 0 },
            { name = "fractional widths",   widths = { 117.4, 137.2, 125.9 }, spacing = 1, index = 3, x = 256.6 },
            { name = "gap per earlier tab", widths = { 100, 50, 25, 10 },     spacing = 4, index = 4, x = 187 },
        }
        for _, c in ipairs(cases) do
            assert.near(c.x, GUIFrame.SubTabOffset(c.widths, c.index, c.spacing), 1e-9, c.name)
        end
    end)
end)
