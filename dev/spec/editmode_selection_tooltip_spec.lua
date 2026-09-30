-- Tier 2: the selection tooltip shows the same numbers as the nudge box, which
-- rounds; string.format's %d truncates a fraction and would read one off.
local L = require("dev.spec._ke_loader")

describe("EditMode selection tooltip lines", function()
    local EditMode

    before_each(function()
        local KE = L.loadGlobals()
        EditMode = L.loadEditMode(KE)
    end)

    it("rounds fractional offsets the way the nudge box does", function()
        local _, position = EditMode.SelectionTooltipLines("Event Toasts", 12.6, -80.6)
        assert.equals("Position: 13, -81", position)
    end)

    it("leaves the position line out when the element reports no position", function()
        local _, position = EditMode.SelectionTooltipLines("Event Toasts", nil, nil)
        assert.is_nil(position)
    end)
end)
