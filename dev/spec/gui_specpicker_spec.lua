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

-- Re-picking the class already on screen has to draw nothing: every redraw
-- orphans its frames permanently, and the fallback rebuilds the whole page. In
-- game the refusal shows up only as the absence of a redraw, which is why it is
-- pinned here rather than left to smoke.
describe("SpecPicker rebuild on pick", function()
    local STUBBED = {
        "C_SpecializationInfo", "C_Timer", "UnitClass",
        "LOCALIZED_CLASS_NAMES_MALE", "CLASS_ICON_TCOORDS",
    }
    local GUIFrame, saved, refreshes, picked

    before_each(function()
        saved = {}
        for _, key in ipairs(STUBBED) do saved[key] = _G[key] end

        _G.C_SpecializationInfo = {}
        -- Fires straight through: the fallback defers its rebuild by a frame,
        -- and the assertions are on whether it happens at all, not when.
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

    it("with onPick, hands a changed class to onPick and never rebuilds the page", function()
        local handed = {}
        GUIFrame:CreateClassPickerRow(nil, {
            scope = "test", classTokens = { "EVOKER", "MAGE" },
            onPick = function(key) handed[#handed + 1] = key end,
        })

        picked("EVOKER")
        assert.same({}, handed, "re-picked the class already shown")

        picked("MAGE")
        assert.same({ "MAGE" }, handed, "picked a different class")
        assert.equals(0, refreshes)
    end)

    it("with onPick, refuses the class the last pick put on screen, not the first one", function()
        local handed = {}
        GUIFrame:CreateClassPickerRow(nil, {
            scope = "test", classTokens = { "EVOKER", "MAGE" },
            onPick = function(key) handed[#handed + 1] = key end,
        })

        picked("MAGE")
        picked("MAGE")
        assert.same({ "MAGE" }, handed, "re-picked the class the pick put on screen")

        picked("EVOKER")
        assert.same({ "MAGE", "EVOKER" }, handed, "picked the class shown at build time")
    end)

    it("without onPick, rebuilds the page only when the pick changes the class on screen", function()
        local _, shown = GUIFrame:CreateClassPickerRow(nil, {
            scope = "test", classTokens = { "EVOKER", "MAGE" },
        })
        assert.equals("EVOKER", shown)

        picked("EVOKER")
        assert.equals(0, refreshes, "re-picked the class already shown")

        picked("MAGE")
        assert.equals(1, refreshes, "picked a different class")
    end)

    -- Every label opens with the same texture escape and first differs at the
    -- icon's crop numbers, so a sort on the label orders the list by position on
    -- the class sheet. WARRIOR and DEATHKNIGHT discriminate that: WARRIOR's crop
    -- sorts first as text, DEATHKNIGHT's name sorts first as a word.
    it("orders options by localized class name, not by the icon's crop", function()
        _G.CLASS_ICON_TCOORDS = {
            WARRIOR = { 0, 0.25, 0, 0.25 },
            DEATHKNIGHT = { 0.25, .5, 0.5, .75 },
        }
        _G.LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Warrior", DEATHKNIGHT = "Death Knight" }

        local options = GUIFrame.BuildClassOptions({ "WARRIOR", "DEATHKNIGHT" }, nil)
        local keys = {}
        for index, option in ipairs(options) do keys[index] = option.key end
        assert.same({ "DEATHKNIGHT", "WARRIOR" }, keys)
    end)
end)

-- The per-spec checkbox write is `if checked then nil else false`. The idiom it
-- avoids, `checked and nil or false`, cannot yield nil: both branches are
-- falsy, so it stores false on every tick and a spec turned off can never be
-- turned back on. The box still looks ticked, so the failure is silent.
describe("SpecEnableCard per-spec checkboxes", function()
    local STUBBED = { "C_SpecializationInfo", "GetSpecializationInfoForSpecID" }
    local GUIFrame, saved, checkboxes, changes

    before_each(function()
        saved = {}
        for _, key in ipairs(STUBBED) do saved[key] = _G[key] end
        _G.C_SpecializationInfo = {}
        _G.GetSpecializationInfoForSpecID = function(specID)
            return specID, "Spec " .. specID, nil, "icon"
        end

        checkboxes, changes = {}, 0
        local function noopRow() return { AddWidget = function() end } end
        local KE = helpers.loadModule("GUI/GUIWidgets/GUI-SpecPicker.lua", {
            ColorTextByTheme = function(_, text) return text end,
            GUIFrame = {
                RegisterContentCleanup = function() end,
                CreateCard = function()
                    local card = { content = {} }
                    function card:AddRow() end
                    function card:AddLabel() end
                    function card:GetNextOffset() return 0 end
                    return card
                end,
                CreateWidgetStateManager = function()
                    return { Register = function() end, UpdateAll = function() end }
                end,
                CreateRow = function() return noopRow() end,
                -- Four parameters: the widget calls this with a colon.
                CreateCompactCheckbox = function(_, _, label, config)
                    local box = { label = label, value = config.value, callback = config.callback }
                    checkboxes[#checkboxes + 1] = box
                    return box
                end,
            },
            Theme = {},
        })
        GUIFrame = KE.GUIFrame
        -- Two specs of one class is enough to prove the callback keys by the
        -- spec it was built for rather than by whichever one ran last.
        GUIFrame.GetClassSpecs = function() return { EVOKER = { 1467, 1473 } } end
        GUIFrame.GetCurrentSpecID = function() return 1467 end
        GUIFrame.CreateClassPickerRow = function() return noopRow(), "EVOKER" end
    end)

    after_each(function()
        for _, key in ipairs(STUBBED) do _G[key] = saved[key] end
    end)

    it("stores an opt-out only for the spec unticked, and removes it when re-ticked", function()
        local db = {}
        GUIFrame:CreateSpecEnableCard({}, 0, {
            db = db,
            scope = "test",
            note = "note",
            onChange = function() changes = changes + 1 end,
        })
        assert.equals(2, #checkboxes)
        for _, box in ipairs(checkboxes) do
            assert.is_true(box.value)
        end

        checkboxes[1].callback(false)
        assert.is_false(db.EnabledSpecs[1467])
        assert.is_nil(db.EnabledSpecs[1473])

        checkboxes[1].callback(true)
        assert.is_nil(db.EnabledSpecs[1467])
        assert.is_nil(db.EnabledSpecs[1473])

        -- Every write re-applies the gate, or the module would not react until
        -- the next spec change.
        assert.equals(2, changes)
    end)
end)
