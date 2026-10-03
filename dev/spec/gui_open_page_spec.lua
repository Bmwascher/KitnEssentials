-- Tier 2: the page-link queue in GUI/GUIWidgets/GUI-Sidebar.lua OpenPage.
--
-- A page link that cannot select yet is queued, and Show selects it later.
-- A newer link must replace or drop the queued one, or Show later puts the
-- older page over it. Show and ShowPage are stubbed: the window and the
-- selection are frame work verified in game.
local helpers = require("dev.spec._helpers")

describe("GUI-Sidebar page-link queue", function()
    local GUIFrame, shown

    before_each(function()
        shown = {}
        GUIFrame = {}
        helpers.loadModule("GUI/GUIWidgets/GUI-Sidebar.lua", { GUIFrame = GUIFrame })
        GUIFrame.Show = function() end
        GUIFrame.ShowPage = function(_, itemId) shown[#shown + 1] = itemId end
    end)

    it("lets the newest page link win over an older queued one", function()
        local cases = {
            {
                name = "open pending: the newer link replaces the queued one",
                pending = true, wantQueued = "B", wantShown = nil,
            },
            {
                name = "window built, nothing pending: the newer link selects and drops the queued one",
                pending = false, wantQueued = nil, wantShown = "B",
            },
        }
        for _, case in ipairs(cases) do
            shown = {}
            GUIFrame._openPending = case.pending or nil
            GUIFrame.mainFrame = {}
            GUIFrame._pendingPage = { itemId = "A" }
            GUIFrame:OpenPage("B")
            local queued = GUIFrame._pendingPage
            assert.equals(case.wantQueued, queued and queued.itemId, case.name)
            assert.equals(case.wantShown, shown[1], case.name)
        end
    end)
end)
