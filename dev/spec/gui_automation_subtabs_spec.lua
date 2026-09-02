-- The Automation page is tabbed: GUI-Automation.lua declares the strip via
-- RegisterTabbedContent. Three of its Vendors & Bags cards (Auction House
-- Filter, Vantus Rune Withdrawer, Merchant Pages) are independent modules
-- with no other route into the interface, so the tab list must keep
-- AutomationVendors reachable in every state -- including a missing db,
-- since the master toggle itself lives inside that table. This spec proves
-- that branch and that every declared tab id resolves to a registered
-- content builder, the same discipline gui_blizzardframes_subtabs_spec.lua
-- uses for the Dark Theme page.
local helpers = require("dev.spec._helpers")

describe("GUI-Automation: subtab id coverage", function()
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
            db = { profile = { Automation = { Enabled = true } } },
        }

        helpers.loadModule("GUI/GUITabs/GUIQoL/GUI-Automation.lua", KE)
    end)

    -- The strip is declared as a function, evaluated per build, so the list
    -- depends on KE.db.profile.Automation. Resolve it the same way
    -- GUI-TabbedContent.lua does.
    local function strip(automationDB)
        KE.db.profile.Automation = automationDB
        local tabs = GUIFrame.tabStrips["Automation"]
        assert.is_not_nil(tabs)
        return type(tabs) == "function" and tabs() or tabs
    end

    local function assertEveryIdResolves(tabs)
        for _, tab in ipairs(tabs) do
            assert.is_function(GUIFrame.registeredContent[tab.id],
                "no RegisterContent builder for declared subtab id " .. tab.id)
        end
    end

    it("offers all four tabs, in order, while the master is on", function()
        local tabs = strip({ Enabled = true })
        assert.equals(4, #tabs)
        assert.equals("AutomationGeneral", tabs[1].id)
        assert.equals("AutomationInterface", tabs[2].id)
        assert.equals("AutomationQuests", tabs[3].id)
        assert.equals("AutomationVendors", tabs[4].id)
        assertEveryIdResolves(tabs)
    end)

    -- The reachability guarantee this page exists to keep. Every tab holding a
    -- module that runs independently of the master must survive master-off, or
    -- that module's only switch disappears: Vantus Rune Withdrawer sits on
    -- General, and Auction House Filter and Merchant Pages sit on Vendors.
    -- There is no other route to any of the three.
    it("keeps General and Vendors & Bags reachable while the master is off", function()
        local tabs = strip({ Enabled = false })
        assert.equals(2, #tabs)
        assert.equals("AutomationGeneral", tabs[1].id)
        assert.equals("AutomationVendors", tabs[2].id)
        assertEveryIdResolves(tabs)
    end)

    -- A missing db must not strand the three independent modules either.
    it("keeps General and Vendors & Bags reachable when the db is missing entirely", function()
        local tabs = strip(nil)
        assert.equals(2, #tabs)
        assert.equals("AutomationGeneral", tabs[1].id)
        assert.equals("AutomationVendors", tabs[2].id)
        assertEveryIdResolves(tabs)
    end)
end)
