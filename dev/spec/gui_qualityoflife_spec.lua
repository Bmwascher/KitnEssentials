-- Two pages in this phase moved their contents behind tab strips. A strip
-- declares ids; a sibling file registers builders for them. Nothing else checks
-- that the two lists agree, and a mismatch renders a blank page in game rather
-- than failing anywhere.
local helpers = require("dev.spec._helpers")

describe("tabbed pages: declared ids resolve to builders", function()
    local KE, GUIFrame

    before_each(function()
        GUIFrame = {
            registeredContent = {},
            tabStrips = {},
            RegisterContent = function(self, id, fn) self.registeredContent[id] = fn end,
            RegisterTabbedContent = function(self, id, tabs) self.tabStrips[id] = tabs end,
        }

        KE = {
            GUIFrame = GUIFrame,
            Theme = {},
            db = { profile = {} },
        }

        helpers.loadModule("GUI/GUITabs/GUIClassUtilities/GUI-SpellAlerts.lua", KE)
        helpers.loadModule("GUI/GUITabs/GUIQoL/GUI-MoveFrames.lua", KE)
        helpers.loadModule("GUI/GUITabs/GUIQoL/GUI-CopyAnything.lua", KE)
        helpers.loadModule("GUI/GUITabs/GUIDungeons/GUI-KeystoneHelper.lua", KE)
        helpers.loadModule("GUI/GUITabs/GUIQoL/GUI-QualityOfLife.lua", KE)
    end)

    local function strip(id)
        local tabs = GUIFrame.tabStrips[id]
        assert.is_not_nil(tabs, "no tab strip registered for " .. id)
        return type(tabs) == "function" and tabs() or tabs
    end

    it("gives Keystone Helper five tabs, each with a builder", function()
        local tabs = strip("KeystoneHelper")
        assert.equals(5, #tabs)
        for _, tab in ipairs(tabs) do
            assert.is_function(GUIFrame.registeredContent[tab.id],
                "no builder registered for declared tab id " .. tab.id)
        end
    end)

    it("declares the five Keystone Helper tabs in order", function()
        local tabs = strip("KeystoneHelper")
        local ids = {}
        for _, tab in ipairs(tabs) do ids[#ids + 1] = tab.id end
        assert.are.same({
            "KeystoneHelperGeneral",
            "KeystoneHelperAppearance",
            "KeystoneHelperReset",
            "KeystoneHelperReroll",
            "KeystoneHelperYourKey",
        }, ids)
    end)

    it("gives Quality of Life three tabs, each with a builder", function()
        local tabs = strip("QualityOfLife")
        assert.equals(3, #tabs)
        assert.are.same({ "SpellAlerts", "MoveFrames", "CopyAnything" },
            { tabs[1].id, tabs[2].id, tabs[3].id })
        for _, tab in ipairs(tabs) do
            assert.is_function(GUIFrame.registeredContent[tab.id],
                "no builder registered for declared tab id " .. tab.id)
        end
    end)
end)
