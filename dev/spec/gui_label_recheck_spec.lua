-- Tier 2: the label recheck's decision in GUI/GUIMain/GUI-Core.lua.
--
-- After the settings window's width settles, card notes are measured again
-- and the page is rebuilt if one wraps differently. The decision waits while
-- the resize grip is held (its release checks), defers while the window is
-- closed or minimized (the page is rebuilt on reopen), and stops after two
-- rebuilds in a row, so a page that flips the scroll bar back and forth
-- cannot rebuild without end. It is pure, so it is tested directly; the
-- measuring and the rebuild are verified in game.
local helpers = require("dev.spec._helpers")

describe("GUI-Core label recheck decision", function()
    local GUIFrame

    before_each(function()
        local KE = { Theme = { headerHeight = 32, borderSize = 1 } }
        helpers.loadModule("GUI/GUIMain/GUI-Core.lua", KE)
        GUIFrame = KE.GUIFrame
    end)

    it("waits while sizing, defers while hidden, stops at the rebuild cap, and checks otherwise", function()
        local cases = {
            { name = "grip held", state = { sizing = true, hidden = false, rebuilds = 0 }, want = "wait" },
            { name = "grip held as the window closes", state = { sizing = true, hidden = true, rebuilds = 0 }, want = "wait" },
            { name = "window closed or minimized", state = { sizing = false, hidden = true, rebuilds = 0 }, want = "defer" },
            { name = "two rebuilds already in a row", state = { sizing = false, hidden = false, rebuilds = 2 }, want = "stop" },
            { name = "one rebuild so far", state = { sizing = false, hidden = false, rebuilds = 1 }, want = "check" },
            { name = "no count yet", state = { sizing = false, hidden = false }, want = "check" },
        }
        for _, case in ipairs(cases) do
            assert.equals(case.want, GUIFrame.LabelRecheckAction(case.state), case.name)
        end
    end)
end)
