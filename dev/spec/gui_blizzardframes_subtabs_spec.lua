-- The Dark Theme page is tabbed: GUI-BlizzardFrames.lua declares the strip via
-- RegisterTabbedContent, and each entry's id must be matched by a
-- GUIFrame:RegisterContent(id, fn) call -- which may live in a sibling file
-- (GUI-UIWidgets.lua, GUI-LootRoll.lua, GUI-LootFrame.lua and
-- GUI-BlizzardMessages.lua all register into the same strip). Neither
-- tabbed_content_spec.lua (a synthetic TABS fixture, not GUI-BlizzardFrames.lua's
-- own list) nor gui_blizzardframes_spec.lua (stubs RegisterTabbedContent to a
-- no-op, discarding the strip entirely) proves every declared id actually
-- resolves. This spec loads every real GUI file that registers into the strip
-- against one shared stub and
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
            -- The nested-tab registry, matching GUI-TabbedContent.lua.
            -- GUI-BlizzardFrames.lua registers its sub-row ids at FILE SCOPE,
            -- so both have to exist before the load below.
            nestedTabOwner = {},
            pendingNestedTab = {},
            RegisterContent = function(self, id, fn) self.registeredContent[id] = fn end,
            RegisterTabbedContent = function(self, id, tabs) self.tabStrips[id] = tabs end,
            RegisterNestedTabs = function(self, ownerId, nestedIds)
                for _, nestedId in ipairs(nestedIds) do
                    self.nestedTabOwner[nestedId] = ownerId
                end
            end,
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
            ColorTextByTheme = function(_, text) return text end,
        }

        helpers.loadModule("GUI/GUITabs/GUISkinning/GUI-UIWidgets.lua", KE)
        helpers.loadModule("GUI/GUITabs/GUISkinning/GUI-LootRoll.lua", KE)
        helpers.loadModule("GUI/GUITabs/GUISkinning/GUI-LootFrame.lua", KE)
        helpers.loadModule("GUI/GUITabs/GUISkinning/GUI-BlizzardMessages.lua", KE)
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
        assert.equals(4, #tabs)
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
        -- the strip rendered more than the three promised tabs.
        assert.equals(3, #tabs)

        local ids = idSet(tabs)
        assert.is_true(ids["SkinBlizzardFramesGeneral"])
        assert.is_true(ids["SkinBlizzardFramesFonts"])
        assert.is_true(ids["SkinBlizzardFramesElements"])

        -- and not the tab that configures the engine itself, which would render
        -- live-looking controls that do nothing. Window Colors and Addon Skins
        -- have no tab at all now: the first leads General, the second follows
        -- Frame Skins.
        assert.is_nil(ids["SkinBlizzardFramesSkins"])
        assert.is_nil(ids["SkinBlizzardFramesFrames"])
        assert.is_nil(ids["SkinBlizzardFramesAddons"])
        assert.is_nil(ids["SkinBlizzardFramesColors"])
    end)

    -- General survives ElvUI because Raid Control and the group-finder pages
    -- ride on it and none has an ElvUI gate. Elements does NOT survive: every
    -- tab it still carries configures a skin this addon stands down from, so
    -- offering them would be the same live-looking-but-dead failure.
    it("keeps exactly General while ElvUI is active", function()
        local tabs = strip(true, true)
        assert.equals(1, #tabs)

        local ids = idSet(tabs)
        assert.is_true(ids["SkinBlizzardFramesGeneral"])

        assert.is_nil(ids["SkinBlizzardFramesElements"])
        assert.is_nil(ids["SkinBlizzardFramesSkins"])
        assert.is_nil(ids["SkinBlizzardFramesFrames"])
        assert.is_nil(ids["SkinBlizzardFramesAddons"])
        assert.is_nil(ids["SkinBlizzardFramesFonts"])
        assert.is_nil(ids["SkinBlizzardFramesColors"])
        assert.is_nil(ids["SkinBlizzardFramesLootRoll"])
        assert.is_nil(ids["SkinBlizzardFramesLootWindow"])
        assert.is_nil(ids["SkinBlizzardFramesWidgets"])
        assert.is_nil(ids["CharacterPanel"])
        assert.is_nil(ids["SkinMessages"])
    end)

    -- ElvUI wins over the engine flag. Without this, a reader could believe the
    -- engine-on branch runs first and ElvUI only trims it.
    it("shows the same one tab under ElvUI whether the engine is on or off", function()
        -- One assertion covering both counts. Two scalar assert.equals calls
        -- would stop at the first failure, so the second state's count would be
        -- masked and the red run would under-report what is broken.
        assert.same({ 1, 1 }, { #strip(true, true), #strip(false, true) })
    end)

    it("positive control: the absorbed page id resolves", function()
        assert.is_function(GUIFrame.registeredContent["SkinMessages"])
    end)

    it("negative control: an invented id has no registered builder", function()
        assert.is_nil(GUIFrame.registeredContent["SkinBlizzardFramesBogus"])
    end)

    -- The row no longer gates on the conflict state: the whole Elements tab
    -- drops out of the strip there, so this list is the same either way.
    it("offers the same three elements in both states", function()
        elvui = false
        local offTabs = GUIFrame._VisibleElementTabs()
        elvui = true
        local onTabs = GUIFrame._VisibleElementTabs()

        assert.same({ 3, 3 }, { #offTabs, #onTabs })
        assert.equals("SkinBlizzardFramesLootRoll", offTabs[1].id)
        assert.equals("SkinBlizzardFramesWidgets", offTabs[3].id)
        assert.same(idSet(offTabs), idSet(onTabs))
    end)

    it("no longer carries the character screen", function()
        elvui = false
        assert.is_nil(idSet(GUIFrame._VisibleElementTabs())["CharacterPanel"])
    end)

    it("registers a builder for every element id in both states", function()
        elvui = false
        assertEveryIdResolves(GUIFrame._VisibleElementTabs())
        elvui = true
        assertEveryIdResolves(GUIFrame._VisibleElementTabs())
    end)

    -- Edit Mode's Open Settings names one of the nested ids. GUI-TabbedContent
    -- translates it to the owning outer tab and leaves the nested id pending;
    -- this row is what has to pick it up.
    describe("pending nested id", function()
        -- Runs the row's own builder and reports which element it selected.
        -- The four child builders are replaced with inert recorders: the real
        -- ones need the whole card stack, and what is under test here is the
        -- selection, not what those pages render.
        local function buildRow()
            local selected
            GUIFrame.CreateSubTabs = function(_, _, yOffset, opts)
                selected = opts.activeId
                return nil, yOffset
            end
            for _, id in ipairs({ "SkinBlizzardFramesLootRoll", "SkinBlizzardFramesLootWindow",
                                  "SkinBlizzardFramesWidgets" }) do
                GUIFrame.registeredContent[id] = function(_, yOffset) return yOffset end
            end
            GUIFrame.registeredContent["SkinBlizzardFramesElements"]({}, 0)
            return selected
        end

        it("becomes the active element on the next build", function()
            elvui = false
            GUIFrame.pendingNestedTab["SkinBlizzardFramesElements"] = "SkinBlizzardFramesWidgets"
            assert.equals("SkinBlizzardFramesWidgets", buildRow())
        end)

        -- Re-reading it every rebuild would drag the user back here whenever
        -- the page redraws after they clicked a different sub-tab.
        it("is cleared after that build, so a later switch is not overridden", function()
            elvui = false
            GUIFrame.pendingNestedTab["SkinBlizzardFramesElements"] = "SkinBlizzardFramesWidgets"
            buildRow()
            assert.is_nil(GUIFrame.pendingNestedTab["SkinBlizzardFramesElements"])
            assert.equals("SkinBlizzardFramesWidgets", buildRow())
        end)

        -- A pending id that is not an element at all must be corrected rather
        -- than rendering an empty page. Character Panel is the live case: it
        -- left this row, so a session that remembered it still has to resolve.
        it("is corrected by the validity loop when the id is not an element", function()
            elvui = false
            GUIFrame.pendingNestedTab["SkinBlizzardFramesElements"] = "CharacterPanel"
            assert.equals("SkinBlizzardFramesLootRoll", buildRow())
        end)
    end)
end)
