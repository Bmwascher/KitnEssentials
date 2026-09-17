-- GUI/GUIWidgets/GUI-SpecPicker.lua -- which class the picker opens on.
--
-- This is the rule the widget exists to fix: a pick stored in the profile made
-- the page open on whatever class was inspected last rather than the one the
-- player is on. The fallback chain has four outcomes and only the first two are
-- reachable in normal play, so the other two are what a later edit breaks
-- unnoticed. The dropdown, the session reset and the layout are smoke.
local helpers = require("dev.spec._helpers")

describe("SpecPicker class resolution", function()
    local GUIFrame, savedSpecInfo

    before_each(function()
        -- The widget binds KE.GUIFrame and KE.Theme at load, indexes
        -- C_SpecializationInfo at file scope, and registers a cleanup callback
        -- on GUIFrame, so all of it must exist before loadModule.
        savedSpecInfo = _G.C_SpecializationInfo
        _G.C_SpecializationInfo = {}
        local KE = helpers.loadModule("GUI/GUIWidgets/GUI-SpecPicker.lua", {
            GUIFrame = { RegisterContentCleanup = function() end },
            Theme = {},
        })
        GUIFrame = KE.GUIFrame
    end)

    -- Restored so the empty namespace does not outlive this file and leave a
    -- later spec loading a module against a C_SpecializationInfo with nothing
    -- in it.
    after_each(function()
        _G.C_SpecializationInfo = savedSpecInfo
    end)

    it("opens on the visit's pick, else the player's class, else the first offered", function()
        local tokens = { "DRUID", "EVOKER", "MAGE" }
        local cases = {
            { name = "pick made this visit",      session = "MAGE",    player = "EVOKER", want = "MAGE" },
            { name = "no pick yet",               session = nil,       player = "EVOKER", want = "EVOKER" },
            { name = "pick is not on offer",      session = "WARLOCK", player = "EVOKER", want = "EVOKER" },
            { name = "player's class not offered", session = nil,      player = "WARLOCK", want = "DRUID" },
        }
        for _, case in ipairs(cases) do
            assert.equals(case.want,
                GUIFrame.ResolvePickerClass(case.session, case.player, tokens), case.name)
        end
    end)
end)

-- A pick rebuilds the whole page, and that rebuild orphans every frame on the
-- page permanently and reads as a flash. Re-picking the class already on screen
-- has to refuse it. In game the refusal shows up only as the absence of a flash,
-- which is why it is pinned here rather than left to smoke.
describe("SpecPicker rebuild on pick", function()
    local STUBBED = { "C_SpecializationInfo", "C_Timer", "UnitClass", "LOCALIZED_CLASS_NAMES_MALE" }
    local GUIFrame, saved, refreshes, picked

    before_each(function()
        saved = {}
        for _, key in ipairs(STUBBED) do saved[key] = _G[key] end

        _G.C_SpecializationInfo = {}
        -- Fires straight through: the picker defers its rebuild by a frame, and
        -- the assertion below is on whether it happens at all, not when.
        _G.C_Timer = { After = function(_, fn) fn() end }
        _G.UnitClass = function() return "Evoker", "EVOKER" end
        _G.LOCALIZED_CLASS_NAMES_MALE = { EVOKER = "Evoker", MAGE = "Mage" }

        refreshes, picked = 0, nil
        local KE = helpers.loadModule("GUI/GUIWidgets/GUI-SpecPicker.lua", {
            ColorTextByTheme = function(_, text) return text end,
            GUIFrame = {
                RegisterContentCleanup = function() end,
                CreateRow = function() return { AddWidget = function() end } end,
                CreateDropdown = function(_, _, _, config) picked = config.callback; return {} end,
                RefreshContent = function() refreshes = refreshes + 1 end,
            },
            Theme = {},
        })
        GUIFrame = KE.GUIFrame
    end)

    after_each(function()
        for _, key in ipairs(STUBBED) do _G[key] = saved[key] end
    end)

    it("rebuilds the page only when the pick changes the class on screen", function()
        local _, shown = GUIFrame:CreateClassPickerRow(nil, {
            scope = "test", classTokens = { "EVOKER", "MAGE" },
        })
        assert.equals("EVOKER", shown)

        picked("EVOKER")
        assert.equals(0, refreshes, "re-picked the class already shown")

        picked("MAGE")
        assert.equals(1, refreshes, "picked a different class")
    end)
end)
