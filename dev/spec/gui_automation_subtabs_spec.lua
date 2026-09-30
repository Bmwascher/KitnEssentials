-- The Automation page is tabbed: GUI-Automation.lua declares the strip via
-- RegisterTabbedContent. Four modules on it have their own switches and no
-- other route into the interface: Vantus Rune Withdrawer (General), Auction
-- House Filter and Merchant Pages (Vendors & Bags), and Combat Logger (its
-- own tab). The tab list must keep those tabs reachable in every state --
-- including a missing db, since the master toggle itself lives inside that
-- table. This spec proves that branch and that every declared tab id
-- resolves to a registered content builder, the same discipline
-- gui_blizzardframes_subtabs_spec.lua uses for the Dark Theme page.
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
        helpers.loadModule("GUI/GUITabs/GUIQoL/GUI-CombatLogger.lua", KE)
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

    -- Every offered tab must have a builder: a declared id without one renders
    -- a blank page in game rather than failing anywhere.
    local function offered(tabs)
        local set = {}
        for _, tab in ipairs(tabs) do
            assert.is_function(GUIFrame.registeredContent[tab.id],
                "no RegisterContent builder for declared subtab id " .. tab.id)
            set[tab.id] = true
        end
        return set
    end

    it("gives every tab a builder while the master is on", function()
        offered(strip({ Enabled = true }))
    end)

    -- The reachability guarantee this page exists to keep. Every tab holding a
    -- module that runs independently of the master must survive master-off and
    -- a missing db, or that module's only switch disappears.
    it("keeps General, Vendors & Bags and Combat Logger reachable while the master is off or the db is missing", function()
        for _, db in ipairs({ { Enabled = false }, false }) do
            local set = offered(strip(db or nil))
            for _, id in ipairs({ "AutomationGeneral", "AutomationVendors", "CombatLogger" }) do
                assert.is_true(set[id] == true, id .. " is not offered with db " .. tostring(db))
            end
        end
    end)
end)
