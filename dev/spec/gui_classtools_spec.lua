-- GUI/GUITabs/GUIClassUtilities/GUI-ClassTools.lua -- which tab Class Tools
-- opens on. A pick that names no tab on the strip falls silently to the first
-- tab, so each pick is checked against the strip the file registers.
local helpers = require("dev.spec._helpers")

describe("GUI-ClassTools: own-class tab", function()
    local GUIFrame

    before_each(function()
        GUIFrame = {
            tabStrips = {},
            RegisterTabbedContent = function(self, id, tabs) self.tabStrips[id] = tabs end,
            RegisterNestedTabs = function() end,
        }
        helpers.loadModule("GUI/GUITabs/GUIClassUtilities/GUI-ClassTools.lua", { GUIFrame = GUIFrame })
    end)

    it("picks a tab of its own, on the strip, for each class with a tool", function()
        local onStrip = {}
        for _, tab in ipairs(GUIFrame.tabStrips["ClassTools"]) do onStrip[tab.id] = true end
        for _, class in ipairs({ "EVOKER", "HUNTER", "PRIEST", "WARLOCK" }) do
            local pick = GUIFrame.ClassToolsTabForClass(class)
            assert.is_true(onStrip[pick] == true, class .. " picks " .. tostring(pick) .. ", which is not on the strip")
            assert.are_not.equals("ClassToolsAllClasses", pick, class)
        end
    end)

    it("falls back to All Classes for a class with no tab, or none", function()
        assert.equals("ClassToolsAllClasses", GUIFrame.ClassToolsTabForClass("MAGE"))
        assert.equals("ClassToolsAllClasses", GUIFrame.ClassToolsTabForClass(nil))
    end)
end)
