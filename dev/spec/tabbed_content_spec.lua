-- Tier 2: GUI/GUIMain/GUI-TabbedContent.lua — tab resolution and live
-- dispatch. The file only READS KE.GUIFrame, so it loads against a hand-built
-- stub (GUI-Core.lua creates that table and would clobber the stub).
-- CreateSubTabs is stubbed: the tab strip is frame work verified in-game;
-- what is testable here is which builder is dispatched and with what offset.
local helpers = require("dev.spec._helpers")

describe("GUI-TabbedContent", function()
    local GUIFrame, rendered

    local TABS = {
        { id = "PetStatusText", label = "Pet Status" },
        { id = "StanceText",    label = "Missing Forms" },
        { id = "HealerMana",    label = "Healer Mana" },
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
            assert.equals("PetStatusText", GUIFrame:ResolveActiveTab("StatusTexts", TABS))
        end)

        it("returns the remembered tab when it is still valid", function()
            GUIFrame.tabbedPageState["StatusTexts"] = "HealerMana"
            assert.equals("HealerMana", GUIFrame:ResolveActiveTab("StatusTexts", TABS))
        end)

        it("falls back to the first tab when the remembered id no longer exists", function()
            GUIFrame.tabbedPageState["StatusTexts"] = "DispelGlow"
            assert.equals("PetStatusText", GUIFrame:ResolveActiveTab("StatusTexts", TABS))
        end)
    end)

    -- Nested sub-rows are not pages, so a nested id can never match an outer
    -- tab. Without translation it falls through to the first tab and the row
    -- never learns which of its children was asked for.
    describe("ResolveActiveTab with nested ids", function()
        before_each(function()
            GUIFrame:RegisterNestedTabs("StanceText", { "STForms", "STIcons" })
        end)

        it("leaves an outer tab alone", function()
            GUIFrame.tabbedPageState["StatusTexts"] = "HealerMana"
            assert.equals("HealerMana", GUIFrame:ResolveActiveTab("StatusTexts", TABS))
            assert.is_nil(GUIFrame.pendingNestedTab["StanceText"])
        end)

        it("resolves a nested id to its owning outer tab", function()
            GUIFrame.tabbedPageState["StatusTexts"] = "STIcons"
            assert.equals("StanceText", GUIFrame:ResolveActiveTab("StatusTexts", TABS))
        end)

        -- Rewriting to the owner rather than clearing is the point: clearing
        -- would send the next rebuild back to the first tab.
        it("rewrites the page state to the owner, not to nil", function()
            GUIFrame.tabbedPageState["StatusTexts"] = "STIcons"
            GUIFrame:ResolveActiveTab("StatusTexts", TABS)
            assert.equals("StanceText", GUIFrame.tabbedPageState["StatusTexts"])
        end)

        it("hands the nested id down under its owner", function()
            GUIFrame.tabbedPageState["StatusTexts"] = "STForms"
            GUIFrame:ResolveActiveTab("StatusTexts", TABS)
            assert.equals("STForms", GUIFrame.pendingNestedTab["StanceText"])
        end)

        it("falls back and sets nothing pending when the owner is not on offer", function()
            GUIFrame.tabbedPageState["StatusTexts"] = "STForms"
            local shortTabs = { { id = "HealerMana", label = "Healer Mana" } }
            assert.equals("HealerMana", GUIFrame:ResolveActiveTab("StatusTexts", shortTabs))
            assert.is_nil(GUIFrame.pendingNestedTab["StanceText"])
        end)

        it("still falls back for an id that is neither outer nor nested", function()
            GUIFrame.tabbedPageState["StatusTexts"] = "NotATabAtAll"
            assert.equals("PetStatusText", GUIFrame:ResolveActiveTab("StatusTexts", TABS))
        end)
    end)

    describe("dispatch", function()
        it("resolves builders live, so registration order does not matter", function()
            GUIFrame:RegisterTabbedContent("StatusTexts", TABS)
            register("PetStatusText")
            GUIFrame.registeredContent["StatusTexts"](nil, 0)
            assert.same({ "PetStatusText" }, rendered)
        end)

        it("renders only the active tab", function()
            register("PetStatusText")
            register("HealerMana")
            GUIFrame:RegisterTabbedContent("StatusTexts", TABS)
            GUIFrame.tabbedPageState["StatusTexts"] = "HealerMana"
            GUIFrame.registeredContent["StatusTexts"](nil, 0)
            assert.same({ "HealerMana" }, rendered)
        end)

        it("returns an offset advanced past both the tab strip and the builder", function()
            register("PetStatusText")
            GUIFrame:RegisterTabbedContent("StatusTexts", TABS)
            assert.equals(130, GUIFrame.registeredContent["StatusTexts"](nil, 0))
        end)

        it("survives a tab whose builder is not registered", function()
            GUIFrame:RegisterTabbedContent("StatusTexts", TABS)
            assert.equals(30, GUIFrame.registeredContent["StatusTexts"](nil, 0))
            assert.same({}, rendered)
        end)
    end)

    describe("headerBuilder", function()
        it("short-circuits with no tab strip and no content when collapse is true", function()
            register("PetStatusText")
            GUIFrame:RegisterTabbedContent("StatusTexts", TABS, {
                headerBuilder = function(_, yOffset) return yOffset + 40, true end,
            })
            assert.equals(40, GUIFrame.registeredContent["StatusTexts"](nil, 0))
            assert.same({}, rendered)
        end)

        it("renders the tab strip and content when collapse is false", function()
            register("PetStatusText")
            GUIFrame:RegisterTabbedContent("StatusTexts", TABS, {
                headerBuilder = function(_, yOffset) return yOffset + 40, false end,
            })
            assert.equals(170, GUIFrame.registeredContent["StatusTexts"](nil, 0))
            assert.same({ "PetStatusText" }, rendered)
        end)
    end)

    -- Which tab a page opens on: an Edit Mode seed or a tab picked this
    -- session, then defaultTab, then the first tab.
    describe("defaultTab", function()
        it("is used when no tab is remembered, and its pick is remembered", function()
            register("HealerMana")
            GUIFrame:RegisterTabbedContent("StatusTexts", TABS, {
                defaultTab = function() return "HealerMana" end,
            })
            GUIFrame.registeredContent["StatusTexts"](nil, 0)
            assert.same({ "HealerMana" }, rendered)
            assert.equals("HealerMana", GUIFrame.tabbedPageState["StatusTexts"])
        end)

        it("is not consulted while a tab is remembered or seeded", function()
            GUIFrame:RegisterNestedTabs("StanceText", { "STForms" })
            for _, remembered in ipairs({ "PetStatusText", "STForms" }) do
                local consulted = false
                GUIFrame.tabbedPageState["StatusTexts"] = remembered
                GUIFrame:RegisterTabbedContent("StatusTexts", TABS, {
                    defaultTab = function()
                        consulted = true
                        return "HealerMana"
                    end,
                })
                GUIFrame.registeredContent["StatusTexts"](nil, 0)
                assert.is_false(consulted, remembered)
            end
        end)

        it("falls back to the first tab and remembers nothing for an unusable pick", function()
            register("PetStatusText")
            for _, pick in ipairs({ false, "NotATab" }) do
                GUIFrame.tabbedPageState["StatusTexts"] = nil
                GUIFrame:RegisterTabbedContent("StatusTexts", TABS, {
                    defaultTab = function() return pick or nil end,
                })
                GUIFrame.registeredContent["StatusTexts"](nil, 0)
                assert.is_nil(GUIFrame.tabbedPageState["StatusTexts"])
            end
            assert.same({ "PetStatusText", "PetStatusText" }, rendered)
        end)
    end)

    -- A nested tabbed page is handed its tab through pendingNestedTab by the
    -- outer page's resolve, and must take it exactly once.
    describe("pending nested tab", function()
        local INNER = {
            { id = "STForms", label = "Forms" },
            { id = "STIcons", label = "Icons" },
        }

        it("wins over the remembered tab, is remembered, and is cleared", function()
            register("STIcons")
            GUIFrame:RegisterTabbedContent("StanceText", INNER)
            GUIFrame.tabbedPageState["StanceText"] = "STForms"
            GUIFrame.pendingNestedTab["StanceText"] = "STIcons"
            GUIFrame.registeredContent["StanceText"](nil, 0)
            assert.same({ "STIcons" }, rendered)
            assert.equals("STIcons", GUIFrame.tabbedPageState["StanceText"])
            assert.is_nil(GUIFrame.pendingNestedTab["StanceText"])
        end)

        it("lands a two-level jump on the nested tab", function()
            register("STIcons")
            GUIFrame:RegisterNestedTabs("StanceText", { "STForms", "STIcons" })
            GUIFrame:RegisterTabbedContent("StanceText", INNER)
            GUIFrame:RegisterTabbedContent("StatusTexts", TABS)
            GUIFrame.tabbedPageState["StatusTexts"] = "STIcons"
            GUIFrame.registeredContent["StatusTexts"](nil, 0)
            assert.same({ "STIcons" }, rendered)
        end)
    end)
end)
