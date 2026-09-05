-- The CVars page is tabbed: GUI-CVars.lua declares the strip via
-- RegisterTabbedContent, and offers the Dev tab only when the client has one of
-- the CVars that fill it -- AU:HasLiveDevCVars carries why. This spec proves
-- that branch and that every declared tab id resolves to a registered content
-- builder, the same discipline gui_automation_subtabs_spec.lua uses for the
-- Automation page.
--
-- The Automation stand-in exposes HasLiveDevCVars alone: the predicate's own
-- inputs (the live read AND the match predicate both biting) are already
-- covered in cvars_live_read_spec.lua, so faking anything more here would test
-- the fake. The fixture holds nothing the three cases do not reach.
local helpers = require("dev.spec._helpers")

describe("GUI-CVars: subtab id coverage", function()
    local KE, GUIFrame

    before_each(function()
        GUIFrame = {
            registeredContent = {},
            tabStrips = {},
            RegisterContent = function(self, id, fn) self.registeredContent[id] = fn end,
            RegisterTabbedContent = function(self, id, tabs) self.tabStrips[id] = tabs end,
        }

        KE = { GUIFrame = GUIFrame }

        helpers.loadModule("GUI/GUITabs/GUIQoL/GUI-CVars.lua", KE)
    end)

    -- The strip is declared as a function, evaluated per build. Resolve it the
    -- same way GUI-TabbedContent.lua does, with the Automation module standing
    -- where GetModule would find it.
    local function strip(automation)
        _G.KitnEssentials = {
            GetModule = function(_, name)
                if name == "Automation" then return automation end
                return nil
            end,
        }
        local tabs = GUIFrame.tabStrips["CVars"]
        assert.is_not_nil(tabs)
        return type(tabs) == "function" and tabs() or tabs
    end

    local function assertEveryIdResolves(tabs)
        for _, tab in ipairs(tabs) do
            assert.is_function(GUIFrame.registeredContent[tab.id],
                "no RegisterContent builder for declared subtab id " .. tab.id)
        end
    end

    it("offers General then Dev while the client has a dev CVar", function()
        local tabs = strip({ HasLiveDevCVars = function() return true end })
        assert.equals(2, #tabs)
        assert.equals("CVarsGeneral", tabs[1].id)
        assert.equals("CVarsDev", tabs[2].id)
        assertEveryIdResolves(tabs)
    end)

    -- The rule this page gains. Without it the Dev tab renders its warning
    -- label over an empty card.
    it("drops the Dev tab when the client has none of them", function()
        local tabs = strip({ HasLiveDevCVars = function() return false end })
        assert.equals(1, #tabs)
        assert.equals("CVarsGeneral", tabs[1].id)
        assertEveryIdResolves(tabs)
    end)

    -- A page built before GetModule can answer must not offer a tab whose card
    -- has nothing to fill it.
    it("drops the Dev tab when the Automation module is absent entirely", function()
        local tabs = strip(nil)
        assert.equals(1, #tabs)
        assert.equals("CVarsGeneral", tabs[1].id)
        assertEveryIdResolves(tabs)
    end)
end)
