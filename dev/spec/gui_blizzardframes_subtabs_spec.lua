-- The Blizzard Frames page is tabbed: GUI-BlizzardFrames.lua declares the
-- strip via RegisterTabbedContent, and each entry's id must be matched by a
-- GUIFrame:RegisterContent(id, fn) call -- which may live in a sibling file
-- (GUI-UIWidgets.lua, GUI-LootRoll.lua, GUI-LootFrame.lua all register into
-- the same strip). Neither tabbed_content_spec.lua (a synthetic TABS
-- fixture, not GUI-BlizzardFrames.lua's own list) nor gui_blizzardframes_spec.lua
-- (stubs RegisterTabbedContent to a no-op, discarding the strip entirely)
-- proves every declared id actually resolves. This spec loads all four real
-- GUI files against one shared stub and checks the strip against the
-- registrations, so a subtab id typo (declared in the strip but never
-- registered, or registered under a different id than the strip declares)
-- fails here instead of silently rendering a blank page in-game.
local helpers = require("dev.spec._helpers")

describe("GUI-BlizzardFrames: subtab id coverage", function()
    local KE, GUIFrame

    before_each(function()
        GUIFrame = {
            registeredContent = {},
            tabStrips = {},
            RegisterContent = function(self, id, fn) self.registeredContent[id] = fn end,
            RegisterTabbedContent = function(self, id, tabs) self.tabStrips[id] = tabs end,
        }

        -- GUI-UIWidgets.lua calls KE:GetFontOutlineOptions() eagerly at file
        -- scope (building its font-outline dropdown list) -- the only
        -- top-level call across the four files that isn't inside a
        -- RegisterContent closure, so it is the only stub this needs.
        KE = {
            GUIFrame = GUIFrame,
            GetFontOutlineOptions = function() return {} end,
            -- GetDB() reads KE.db.profile.Skinning.BlizzardFrames. The strip is
            -- now state-dependent, so the db has to be real enough to drive
            -- both branches; Enabled is flipped per example below.
            db = { profile = { Skinning = { BlizzardFrames = { Enabled = false } } } },
        }

        helpers.loadModule("GUI/GUITabs/GUISkinning/GUI-UIWidgets.lua", KE)
        helpers.loadModule("GUI/GUITabs/GUISkinning/GUI-LootRoll.lua", KE)
        helpers.loadModule("GUI/GUITabs/GUISkinning/GUI-LootFrame.lua", KE)
        helpers.loadModule("GUI/GUITabs/GUISkinning/GUI-BlizzardFrames.lua", KE)
    end)

    -- The strip is declared as a function now, evaluated per build, so the
    -- list depends on whether the skin engine is on. Resolve it the same way
    -- GUI-TabbedContent.lua does.
    local function strip(enabled)
        KE.db.profile.Skinning.BlizzardFrames.Enabled = enabled
        local tabs = GUIFrame.tabStrips["SkinBlizzardFrames"]
        assert.is_not_nil(tabs)
        return type(tabs) == "function" and tabs() or tabs
    end

    local function assertEveryIdResolves(tabs)
        for _, tab in ipairs(tabs) do
            assert.is_function(GUIFrame.registeredContent[tab.id],
                "no RegisterContent builder for declared subtab id " .. tab.id)
        end
    end

    it("registers a RegisterContent builder for every id declared while the engine is on", function()
        local tabs = strip(true)
        assert.equals(6, #tabs)
        assertEveryIdResolves(tabs)
    end)

    it("registers a RegisterContent builder for every id declared while the engine is off", function()
        assertEveryIdResolves(strip(false))
    end)

    -- The reachability guarantee this page exists to keep: the three modules
    -- that are independent of the skin engine ship ENABLED, so their settings
    -- must stay reachable while it is off. There is no other route to them --
    -- not the sidebar, not the keyword search, not Edit Mode's Open Settings.
    it("keeps exactly the engine-independent tabs while the engine is off", function()
        local ids = {}
        for _, tab in ipairs(strip(false)) do ids[tab.id] = true end

        assert.is_true(ids["SkinBlizzardFramesLootRoll"])
        assert.is_true(ids["SkinBlizzardFramesLootWindow"])
        assert.is_true(ids["SkinBlizzardFramesWidgets"])

        -- and none of the engine's own tabs, which would render live-looking
        -- controls that do nothing.
        assert.is_nil(ids["SkinBlizzardFramesGeneral"])
        assert.is_nil(ids["SkinBlizzardFramesFrames"])
        assert.is_nil(ids["SkinBlizzardFramesAddons"])
    end)

    it("positive control: the two new loot subtab ids resolve", function()
        assert.is_function(GUIFrame.registeredContent["SkinBlizzardFramesLootRoll"])
        assert.is_function(GUIFrame.registeredContent["SkinBlizzardFramesLootWindow"])
    end)

    it("negative control: an invented id has no registered builder", function()
        assert.is_nil(GUIFrame.registeredContent["SkinBlizzardFramesBogus"])
    end)
end)
