-- Tier 2: GUI/GUIMain/GUI-TabbedContent.lua — tab resolution and live
-- dispatch. The file only READS KE.GUIFrame, so it loads against a hand-built
-- stub (GUI-Core.lua creates that table and would clobber the stub).
-- CreateSubTabs is stubbed: the tab strip is frame work verified in-game;
-- what is testable here is which builder is dispatched and with what offset.
local helpers = require("dev.spec._helpers")

describe("GUI-TabbedContent", function()
    local GUIFrame, rendered

    local TABS = {
        { id = "InnervateTracker",   label = "Innervate Tracker" },
        { id = "MaintenanceTracker", label = "Maintenance Tracker" },
        { id = "HealerMana",         label = "Healer Mana" },
    }

    before_each(function()
        rendered = {}
        GUIFrame = {
            registeredContent = {},
            RegisterContent = function(self, id, fn) self.registeredContent[id] = fn end,
            CreateSubTabs = function(_, _, yOffset) return nil, yOffset + 30 end,
            RefreshContent = function() end,
        }
        helpers.loadModule("GUI/GUIMain/GUI-TabbedContent.lua", { GUIFrame = GUIFrame })
    end)

    local function register(name)
        GUIFrame.registeredContent[name] = function(_, yOffset)
            rendered[#rendered + 1] = name
            return yOffset + 100
        end
    end

    describe("ResolveActiveTab", function()
        it("defaults to the first tab when nothing is remembered", function()
            assert.equals("InnervateTracker", GUIFrame:ResolveActiveTab("HealerTools", TABS))
        end)

        it("returns the remembered tab when it is still valid", function()
            GUIFrame.tabbedPageState["HealerTools"] = "HealerMana"
            assert.equals("HealerMana", GUIFrame:ResolveActiveTab("HealerTools", TABS))
        end)

        it("falls back to the first tab when the remembered id no longer exists", function()
            GUIFrame.tabbedPageState["HealerTools"] = "DispelGlow"
            assert.equals("InnervateTracker", GUIFrame:ResolveActiveTab("HealerTools", TABS))
        end)
    end)

    -- Nested sub-rows are not pages, so a nested id can never match an outer
    -- tab. Without translation it falls through to the first tab and the row
    -- never learns which of its children was asked for.
    describe("ResolveActiveTab with nested ids", function()
        before_each(function()
            GUIFrame:RegisterNestedTabs("MaintenanceTracker", { "MTAuras", "MTLayout" })
        end)

        it("leaves an outer tab alone", function()
            GUIFrame.tabbedPageState["HealerTools"] = "HealerMana"
            assert.equals("HealerMana", GUIFrame:ResolveActiveTab("HealerTools", TABS))
            assert.is_nil(GUIFrame.pendingNestedTab["MaintenanceTracker"])
        end)

        it("resolves a nested id to its owning outer tab", function()
            GUIFrame.tabbedPageState["HealerTools"] = "MTLayout"
            assert.equals("MaintenanceTracker", GUIFrame:ResolveActiveTab("HealerTools", TABS))
        end)

        -- Rewriting to the owner rather than clearing is the point: clearing
        -- would send the next rebuild back to the first tab.
        it("rewrites the page state to the owner, not to nil", function()
            GUIFrame.tabbedPageState["HealerTools"] = "MTLayout"
            GUIFrame:ResolveActiveTab("HealerTools", TABS)
            assert.equals("MaintenanceTracker", GUIFrame.tabbedPageState["HealerTools"])
        end)

        it("hands the nested id down under its owner", function()
            GUIFrame.tabbedPageState["HealerTools"] = "MTAuras"
            GUIFrame:ResolveActiveTab("HealerTools", TABS)
            assert.equals("MTAuras", GUIFrame.pendingNestedTab["MaintenanceTracker"])
        end)

        it("falls back and sets nothing pending when the owner is not on offer", function()
            GUIFrame.tabbedPageState["HealerTools"] = "MTAuras"
            local shortTabs = { { id = "HealerMana", label = "Healer Mana" } }
            assert.equals("HealerMana", GUIFrame:ResolveActiveTab("HealerTools", shortTabs))
            assert.is_nil(GUIFrame.pendingNestedTab["MaintenanceTracker"])
        end)

        it("still falls back for an id that is neither outer nor nested", function()
            GUIFrame.tabbedPageState["HealerTools"] = "NotATabAtAll"
            assert.equals("InnervateTracker", GUIFrame:ResolveActiveTab("HealerTools", TABS))
        end)
    end)

    describe("dispatch", function()
        it("resolves builders live, so registration order does not matter", function()
            GUIFrame:RegisterTabbedContent("HealerTools", TABS)
            register("InnervateTracker")
            GUIFrame.registeredContent["HealerTools"](nil, 0)
            assert.same({ "InnervateTracker" }, rendered)
        end)

        it("renders only the active tab", function()
            register("InnervateTracker")
            register("HealerMana")
            GUIFrame:RegisterTabbedContent("HealerTools", TABS)
            GUIFrame.tabbedPageState["HealerTools"] = "HealerMana"
            GUIFrame.registeredContent["HealerTools"](nil, 0)
            assert.same({ "HealerMana" }, rendered)
        end)

        it("returns an offset advanced past both the tab strip and the builder", function()
            register("InnervateTracker")
            GUIFrame:RegisterTabbedContent("HealerTools", TABS)
            assert.equals(130, GUIFrame.registeredContent["HealerTools"](nil, 0))
        end)

        it("survives a tab whose builder is not registered", function()
            GUIFrame:RegisterTabbedContent("HealerTools", TABS)
            assert.equals(30, GUIFrame.registeredContent["HealerTools"](nil, 0))
            assert.same({}, rendered)
        end)
    end)

    describe("headerBuilder", function()
        it("short-circuits with no tab strip and no content when collapse is true", function()
            register("InnervateTracker")
            GUIFrame:RegisterTabbedContent("HealerTools", TABS, {
                headerBuilder = function(_, yOffset) return yOffset + 40, true end,
            })
            assert.equals(40, GUIFrame.registeredContent["HealerTools"](nil, 0))
            assert.same({}, rendered)
        end)

        it("renders the tab strip and content when collapse is false", function()
            register("InnervateTracker")
            GUIFrame:RegisterTabbedContent("HealerTools", TABS, {
                headerBuilder = function(_, yOffset) return yOffset + 40, false end,
            })
            assert.equals(170, GUIFrame.registeredContent["HealerTools"](nil, 0))
            assert.same({ "InnervateTracker" }, rendered)
        end)
    end)
end)
