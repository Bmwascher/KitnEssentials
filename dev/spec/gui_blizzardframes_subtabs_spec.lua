-- The Dark Theme page is tabbed: GUI-BlizzardFrames.lua declares the strip via
-- RegisterTabbedContent, and each entry's id must be matched by a
-- GUIFrame:RegisterContent(id, fn) call -- which may live in a sibling file
-- (GUI-UIWidgets.lua, GUI-LootRoll.lua, GUI-LootFrame.lua, GUI-CharacterPanel.lua
-- and GUI-BlizzardMessages.lua all register into the same strip). Neither
-- tabbed_content_spec.lua (a synthetic TABS fixture, not GUI-BlizzardFrames.lua's
-- own list) nor gui_blizzardframes_spec.lua (stubs RegisterTabbedContent to a
-- no-op, discarding the strip entirely) proves every declared id actually
-- resolves. This spec loads all six real GUI files against one shared stub and
-- checks the strip against the registrations, so a subtab id typo (declared in
-- the strip but never registered, or registered under a different id than the
-- strip declares) fails here instead of silently rendering a blank page in-game.
local helpers = require("dev.spec._helpers")

describe("GUI-BlizzardFrames: subtab id coverage", function()
    local KE, GUIFrame
    local elvui

    before_each(function()
        elvui = false

        GUIFrame = {
            registeredContent = {},
            tabStrips = {},
            RegisterContent = function(self, id, fn) self.registeredContent[id] = fn end,
            RegisterTabbedContent = function(self, id, tabs) self.tabStrips[id] = tabs end,
        }

        KE = {
            GUIFrame = GUIFrame,
            -- GUI-UIWidgets.lua and GUI-BlizzardMessages.lua both call this
            -- eagerly at file scope, building their font-outline dropdown lists.
            GetFontOutlineOptions = function() return {} end,
            -- GUI-BlizzardMessages.lua reads `KE.LSM or LibStub(...)` at file
            -- scope. Seeding LSM short-circuits the LibStub call, which has no
            -- global here.
            LSM = {},
            -- The strip's first branch. Called as KE:ShouldNotLoadModule(), so
            -- the colon's self argument is discarded.
            ShouldNotLoadModule = function() return elvui end,
            -- GetDB() reads KE.db.profile.Skinning.BlizzardFrames. The strip is
            -- state-dependent, so the db has to be real enough to drive every
            -- branch; Enabled is flipped per example below.
            db = { profile = { Skinning = { BlizzardFrames = { Enabled = false } } } },
        }

        helpers.loadModule("GUI/GUITabs/GUISkinning/GUI-UIWidgets.lua", KE)
        helpers.loadModule("GUI/GUITabs/GUISkinning/GUI-LootRoll.lua", KE)
        helpers.loadModule("GUI/GUITabs/GUISkinning/GUI-LootFrame.lua", KE)
        helpers.loadModule("GUI/GUITabs/GUISkinning/GUI-BlizzardMessages.lua", KE)
        helpers.loadModule("GUI/GUITabs/GUIQoL/GUI-CharacterPanel.lua", KE)
        helpers.loadModule("GUI/GUITabs/GUISkinning/GUI-BlizzardFrames.lua", KE)
    end)

    -- The strip is declared as a function, evaluated per build, so the list
    -- depends on the skin engine AND on ElvUI. Resolve it the same way
    -- GUI-TabbedContent.lua does.
    local function strip(enabled, elvuiActive)
        KE.db.profile.Skinning.BlizzardFrames.Enabled = enabled
        elvui = elvuiActive and true or false
        local tabs = GUIFrame.tabStrips["SkinBlizzardFrames"]
        assert.is_not_nil(tabs)
        return type(tabs) == "function" and tabs() or tabs
    end

    local function idSet(tabs)
        local ids = {}
        for _, tab in ipairs(tabs) do ids[tab.id] = true end
        return ids
    end

    local function assertEveryIdResolves(tabs)
        for _, tab in ipairs(tabs) do
            assert.is_function(GUIFrame.registeredContent[tab.id],
                "no RegisterContent builder for declared subtab id " .. tab.id)
        end
    end

    it("registers a builder for every id declared while the engine is on", function()
        local tabs = strip(true, false)
        assert.equals(8, #tabs)
        assertEveryIdResolves(tabs)
    end)

    it("registers a builder for every id declared while the engine is off", function()
        assertEveryIdResolves(strip(false, false))
    end)

    it("registers a builder for every id declared while ElvUI is active", function()
        assertEveryIdResolves(strip(true, true))
    end)

    -- The reachability guarantee this page exists to keep: modules that are
    -- independent of the skin engine ship ENABLED, so their settings must stay
    -- reachable while it is off. There is no other route to them -- not the
    -- sidebar, not the keyword search, not Edit Mode's Open Settings.
    it("keeps exactly the engine-independent tabs while the engine is off", function()
        local tabs = strip(false, false)
        -- Count first. A set keyed by id cannot see a duplicate or an extra
        -- entry, so the membership assertions below would all still pass while
        -- the strip rendered more than the six promised tabs.
        assert.equals(6, #tabs)

        local ids = idSet(tabs)
        assert.is_true(ids["SkinBlizzardFramesGeneral"])
        assert.is_true(ids["SkinBlizzardFramesLootRoll"])
        assert.is_true(ids["SkinBlizzardFramesLootWindow"])
        assert.is_true(ids["SkinBlizzardFramesWidgets"])
        assert.is_true(ids["CharacterPanel"])
        assert.is_true(ids["SkinMessages"])

        -- and neither tab that configures the engine itself, which would render
        -- live-looking controls that do nothing.
        assert.is_nil(ids["SkinBlizzardFramesFrames"])
        assert.is_nil(ids["SkinBlizzardFramesAddons"])
    end)

    -- General survives ElvUI because Raid Control rides on it and has no ElvUI
    -- gate at all; Character Screen survives because Character Panel keeps its
    -- non-overlapping features. Everything else on this page DOES stand down
    -- under ElvUI, so offering those tabs would be the same
    -- live-looking-but-dead failure.
    it("keeps exactly General and Character Screen while ElvUI is active", function()
        local tabs = strip(true, true)
        assert.equals(2, #tabs)

        local ids = idSet(tabs)
        assert.is_true(ids["SkinBlizzardFramesGeneral"])
        assert.is_true(ids["CharacterPanel"])

        assert.is_nil(ids["SkinBlizzardFramesFrames"])
        assert.is_nil(ids["SkinBlizzardFramesAddons"])
        assert.is_nil(ids["SkinBlizzardFramesLootRoll"])
        assert.is_nil(ids["SkinBlizzardFramesLootWindow"])
        assert.is_nil(ids["SkinBlizzardFramesWidgets"])
        assert.is_nil(ids["SkinMessages"])
    end)

    -- ElvUI wins over the engine flag. Without this, a reader could believe the
    -- engine-on branch runs first and ElvUI only trims it.
    it("shows the same two tabs under ElvUI whether the engine is on or off", function()
        -- One assertion covering both counts. Two scalar assert.equals calls
        -- would stop at the first failure, so the second state's count would be
        -- masked and the red run would under-report what is broken.
        assert.same({ 2, 2 }, { #strip(true, true), #strip(false, true) })
    end)

    it("positive control: the two absorbed page ids resolve", function()
        assert.is_function(GUIFrame.registeredContent["CharacterPanel"])
        assert.is_function(GUIFrame.registeredContent["SkinMessages"])
    end)

    it("negative control: an invented id has no registered builder", function()
        assert.is_nil(GUIFrame.registeredContent["SkinBlizzardFramesBogus"])
    end)
end)
