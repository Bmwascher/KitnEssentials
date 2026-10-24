-- Tier 1: GUI/GUIMain/GUI-ProfilesTab.lua -- GUIFrame.ShouldOfferRetailCopy,
-- the rule behind the one-time Copy from Retail popup. The page file loads
-- with a GUIFrame whose two registration calls do nothing; no other state.
local helpers = require("dev.spec._helpers")

describe("GUI-ProfilesTab.lua Copy from Retail offer", function()
    local GUIFrame

    before_each(function()
        local noop = function() end
        local KE = helpers.loadModule("GUI/GUIMain/GUI-ProfilesTab.lua", {
            GUIFrame = { RegisterContent = noop, RegisterTabbedContent = noop },
        })
        GUIFrame = KE.GUIFrame
    end)

    it("offers only on a baseline load whose flag is not true", function()
        local cases = {
            { baseline = true,  seen = false, offered = true },
            { baseline = true,  seen = nil,   offered = true },
            { baseline = true,  seen = true,  offered = false },
            { baseline = false, seen = false, offered = false },
            { baseline = false, seen = nil,   offered = false },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.offered, GUIFrame.ShouldOfferRetailCopy(c.baseline, c.seen),
                ("baseline %s, seen %s"):format(tostring(c.baseline), tostring(c.seen)))
        end
    end)
end)
