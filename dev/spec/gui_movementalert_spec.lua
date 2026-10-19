-- KitnEssentials_Options/Combat/StatusTexts/GUI-NoMovementAlert.lua -- which class card 7 draws.
--
-- Moving the card onto the shared spec picker changed one thing a player can
-- see: the class used to come from db.SpellEditorClass, a pick stored in the
-- profile, and now comes from whatever CreateClassPickerRow hands back for this
-- visit. Profiles written before the change still carry that key, so the case
-- runs the builder with a stale value that disagrees with the picker -- the old
-- read draws the stored class, the shipped one draws the picker's, and nothing
-- writes the key back.
--
-- The page reads KE.GUIFrame and, through the KitnEssentials global, the
-- module's IsAttached(); both are hand-built stubs, the GUIFrame one the way
-- GUI-SecondaryStats does it. The real registered builder runs; the stub
-- factories record what it asks for and restate none of its logic.
local helpers = require("dev.spec._helpers")

describe("GUI-NoMovementAlert tracked spells card", function()
    local db, specHeaders

    before_each(function()
        specHeaders = {}

        -- Attached, themed and silent so cards 2-6 take their short branch.
        -- The page follows the module's IsAttached(), not the saved box, so
        -- the stub module reports attached too. None of them reaches card
        -- 7's class; each one skipped is a widget factory the stub does not
        -- have to carry.
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
                function card:MarkBody() return {} end
                return card
            end,
            CreateRow = function() return noopRow() end,
            CreateDropdown = function() return {} end,
            CreateEditBox = function() return {} end,
            CreateCheckbox = function() return {} end,
            CreateCompactCheckbox = function() return {} end,
            CreateAttachSizeRow = function() return {} end,
            CreateSpecHeaderRow = function(_, _, labelText)
                specHeaders[#specHeaders + 1] = labelText
                return {}
            end,
            -- Hands back a class the stored pick disagrees with, which is the
            -- whole point of the case.
            CreateClassPickerRow = function() return noopRow(), "DRUID" end,
        }

        -- Kept in place after the load (loadModule only borrows a global when
        -- none exists), because the builder looks the module up when it runs.
        -- ApplySettings is reached only from widget callbacks, which the stub
        -- factories never fire.
        _G.KitnEssentials = {
            GetModule = function(_, name)
                if name == "NoMovementAlert" then
                    return { IsAttached = function() return true end }
                end
            end,
        }
        local KE = helpers.loadModule("KitnEssentials_Options/Combat/StatusTexts/GUI-NoMovementAlert.lua", {
            GUIFrame = GUIFrame,
            GetPlayerSpecId = function() return nil end,
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

    after_each(function()
        _G.KitnEssentials = nil
    end)

    it("draws the picker's class, not the one left in the profile", function()
        assert.same({ "Spec 102" }, specHeaders)

        -- Untouched: the key is dead weight in old profiles, and a builder that
        -- still wrote it would be reading it too.
        assert.equals("MAGE", db.SpellEditorClass)
    end)
end)
