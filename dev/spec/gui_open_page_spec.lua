-- Tier 2: page-link ordering in GUI/GUIWidgets/GUI-Sidebar.lua OpenPage.
--
-- OpenPage records its link before calling Show, and only Show's tail
-- selects it, so the newest request is the one selected: an older waiting
-- link is replaced before Show runs, and a link made inside Show (a handler
-- running in the pages' load) replaces the outer one. Show and ShowPage are
-- stubbed: the window and the selection are frame work verified in game.
local helpers = require("dev.spec._helpers")

describe("GUI-Sidebar page-link ordering", function()
    local GUIFrame, selected, seenAtShow, nestedLink

    before_each(function()
        GUIFrame = {}
        helpers.loadModule("GUI/GUIWidgets/GUI-Sidebar.lua", { GUIFrame = GUIFrame })
        GUIFrame.Show = function(self)
            if seenAtShow == nil then
                local waiting = self._pendingPage
                seenAtShow = waiting and waiting.itemId or false
            end
            if nestedLink then
                local link = nestedLink
                nestedLink = nil
                self:OpenPage(link)
            end
        end
        GUIFrame.ShowPage = function(_, itemId) selected[#selected + 1] = itemId end
    end)

    it("selects only the newest page link, and only through Show", function()
        local cases = {
            {
                name = "an older waiting link is replaced before Show runs",
                waiting = "Old", nested = nil, wantSeen = "A", wantWaiting = "A",
            },
            {
                name = "a link made inside Show beats the outer one",
                waiting = nil, nested = "B", wantSeen = "A", wantWaiting = "B",
            },
        }
        for _, case in ipairs(cases) do
            selected, seenAtShow, nestedLink = {}, nil, case.nested
            GUIFrame._openPending = nil
            GUIFrame.mainFrame = {}
            GUIFrame._pendingPage = case.waiting and { itemId = case.waiting } or nil
            GUIFrame:OpenPage("A")
            local waiting = GUIFrame._pendingPage
            assert.equals(case.wantSeen, seenAtShow, case.name)
            assert.equals(case.wantWaiting, waiting and waiting.itemId, case.name)
            assert.equals(0, #selected, case.name)
        end
    end)
end)
