-- GUI/GUITabs/GUIUtilities/GUI-NoMovementAlert.lua -- which class card 7 draws.
--
-- Moving the card onto the shared spec picker changed one thing a player can
-- see: the class used to come from db.SpellEditorClass, a pick stored in the
-- profile, and now comes from whatever CreateClassPickerRow hands back for this
-- visit. Profiles written before the change still carry that key, so the case
-- runs the builder with a stale value that disagrees with the picker -- the old
-- read draws the stored class, the shipped one draws the picker's, and nothing
-- writes the key back.
--
-- The page reads KE.GUIFrame only, so it loads against a hand-built stub the way
-- GUI-SecondaryStats does. The real registered builder runs; the stub factories
-- record what it asks for and restate none of its logic.
local helpers = require("dev.spec._helpers")

describe("GUI-NoMovementAlert tracked spells card", function()
    local db, specHeaders, pickerConfig

    before_each(function()
        specHeaders = {}
        pickerConfig = nil

        -- Attached, themed and silent so cards 2-6 take their short branch.
        -- None of them reaches card 7's class; each one skipped is a widget
        -- factory the stub does not have to carry.
        db = {
            Enabled = true,
            AttachToCombatTexts = true,
            ColorMode = "THEME",
            SoundEnabled = false,
            MaxRemainingEnabled = false,
            SpellEditorClass = "MAGE",
            Spells = {},
        }

        _G.UnitClass = function() return "Mage", "MAGE" end

        local function noopRow()
            local row = {}
            function row:AddWidget() end
            return row
        end

        local GUIFrame = {
            registeredContent = {},
            RegisterContent = function(self, id, fn) self.registeredContent[id] = fn end,
            CreateCard = function()
                local card = { content = {} }
                function card:AddRow() end
                function card:AddLabel() end
                function card:AddHeaderToggle() end
                function card:GetContentHeight() return 0 end
                return card
            end,
            CreateRow = function() return noopRow() end,
            CreateDropdown = function() return {} end,
            CreateEditBox = function() return {} end,
            CreateCheckbox = function() return {} end,
            CreateSpecHeaderRow = function(_, _, labelText)
                specHeaders[#specHeaders + 1] = labelText
                return {}
            end,
            GetCurrentSpecID = function() return nil end,
            -- Hands back a class the stored pick disagrees with, which is the
            -- whole point of the case.
            CreateClassPickerRow = function(_, _, config)
                pickerConfig = config
                return noopRow(), "DRUID"
            end,
        }

        local KE = helpers.loadModule("GUI/GUITabs/GUIUtilities/GUI-NoMovementAlert.lua", {
            GUIFrame = GUIFrame,
            Theme = { paddingSmall = 4, paddingMedium = 8 },
            db = { profile = { NoMovementAlert = db } },
            ColorTextByTheme = function(_, text) return text end,
            MOVEMENT_ABILITIES = {
                DRUID = { [102] = { 1850 } },
                MAGE  = { [62] = { 1953 } },
            },
            MOVEMENT_DEFAULT_OFF = {},
            MOVEMENT_SPELL_KEY = function(specId, spellId) return specId .. ":" .. spellId end,
        })
        KE.GUIFrame.registeredContent["NoMovementAlert"]({}, 0)
    end)

    it("draws the picker's class, not the one left in the profile", function()
        assert.same({ "Spec 102" }, specHeaders)

        -- Untouched: the key is dead weight in old profiles, and a builder that
        -- still wrote it would be reading it too.
        assert.equals("MAGE", db.SpellEditorClass)

        -- The picker cannot return a class the card can draw unless it is
        -- offered every class the presets cover.
        assert.equals("NoMovementAlert", pickerConfig.scope)
        table.sort(pickerConfig.classTokens)
        assert.same({ "DRUID", "MAGE" }, pickerConfig.classTokens)
    end)
end)
