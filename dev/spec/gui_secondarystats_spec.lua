-- GUI/GUITabs/GUIQoL/GUI-SecondaryStats.lua -- what the per-spec checkboxes
-- WRITE.
--
-- The write rule is `if checked then nil else false`, and the idiom it avoids,
-- `checked and nil or false`, cannot yield nil: both branches are falsy, so the
-- or-branch swallows the and-branch. That shipped once in a sibling page and
-- stored false on every tick, leaving a spec that could never be turned back
-- on. The failure is silent -- the box looks ticked and the setting says off --
-- so it is exactly the kind a later edit reintroduces unnoticed.
--
-- The page reads KE.GUIFrame only, so it loads against a hand-built stub the way
-- GUI-SpellAlerts does. The real registered builder runs and the real checkbox
-- callbacks are invoked, because the rule under test lives in the callback body
-- and nowhere else.
local helpers = require("dev.spec._helpers")

describe("GUI-SecondaryStats per-spec checkboxes", function()
    local db, checkboxes, gateCalls

    before_each(function()
        checkboxes = {}
        gateCalls = 0

        db = {
            Enabled = true,
            Stats = {
                crit      = { Shown = true,  ValueMode = "percent" },
                haste     = { Shown = true,  ValueMode = "percent" },
                mastery   = { Shown = true,  ValueMode = "percent" },
                vers      = { Shown = true,  ValueMode = "percent" },
                leech     = { Shown = false, ValueMode = "percent" },
                avoidance = { Shown = false, ValueMode = "percent" },
                speed     = { Shown = false, ValueMode = "percent" },
            },
        }

        _G.KitnEssentials = {
            GetModule = function()
                return { ApplySettings = function() end,
                         ApplySpecGate = function() gateCalls = gateCalls + 1 end }
            end,
        }

        local function noopRow()
            local row = {}
            function row:AddWidget() end
            return row
        end

        local GUIFrame = {
            registeredContent = {},
            RegisterContent = function(self, id, fn) self.registeredContent[id] = fn end,
            CreateWidgetStateManager = function()
                return { Register = function() end, RegisterGroup = function() end,
                         UpdateAll = function() end }
            end,
            CreateCard = function()
                local card = { content = {} }
                function card:AddRow() end
                function card:AddLabel() end
                function card:AddHeaderToggle() end
                function card:GetNextOffset() return 0 end
                function card:GetContentHeight() return 0 end
                return card
            end,
            CreateRow = function() return noopRow() end,
            CreateText = function() return {} end,
            CreateSlider = function() return {} end,
            CreateDropdown = function() return {} end,
            CreateColorPicker = function() return {} end,
            CreateCheckbox = function() return {} end,
            CreatePositionCard = function() return { positionWidgets = {} }, 0 end,
            CreateFontSettingsCard = function() return {}, 0, {} end,
            -- Two specs of one class is enough to prove the callback keys by the
            -- spec it was built for rather than by whichever one ran last.
            GetClassSpecs = function() return { EVOKER = { 1467, 1473 } } end,
            GetCurrentSpecID = function() return 1467 end,
            CreateClassPickerRow = function() return noopRow(), "EVOKER" end,
            -- Four parameters, not three: the page calls this with a colon, so
            -- the stub receives GUIFrame as well as the parent.
            CreateCompactCheckbox = function(_, _, label, config)
                local box = { label = label, value = config.value, callback = config.callback }
                checkboxes[#checkboxes + 1] = box
                return box
            end,
        }

        _G.GetSpecializationInfoForSpecID = function(specID)
            return specID, "Spec " .. specID, nil, "icon"
        end

        local KE = helpers.loadModule("GUI/GUITabs/GUIQoL/GUI-SecondaryStats.lua", {
            GUIFrame = GUIFrame,
            Theme = { rowHeight = 40, rowHeightLast = 44, paddingSmall = 4, paddingMedium = 8 },
            db = { profile = { SecondaryStats = db } },
            ColorTextByTheme = function(_, text) return text end,
        })
        KE.GUIFrame.registeredContent["SecondaryStats"]({}, 0)
    end)

    it("stores an opt-out only for the spec unticked, and removes it when re-ticked", function()
        assert.equals(2, #checkboxes)
        for _, box in ipairs(checkboxes) do
            assert.is_true(box.value)
        end

        checkboxes[1].callback(false)
        assert.is_false(db.EnabledSpecs[1467])
        assert.is_nil(db.EnabledSpecs[1473])

        -- The re-tick is the half that the `checked and nil or false` idiom
        -- breaks: it stored false again, so the spec stayed off for good.
        checkboxes[1].callback(true)
        assert.is_nil(db.EnabledSpecs[1467])
        assert.is_nil(db.EnabledSpecs[1473])

        -- Every write re-applies the gate, or the readout would not react until
        -- the next spec change.
        assert.equals(2, gateCalls)
    end)
end)
