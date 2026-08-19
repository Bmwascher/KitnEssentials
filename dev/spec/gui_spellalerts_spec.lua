-- GUI/GUITabs/GUIClassUtilities/GUI-SpellAlerts.lua — what the per-spec
-- checkboxes and the opacity slider WRITE.
--
-- The page reads KE.GUIFrame only, so it loads against a hand-built stub the
-- way GUI-BlizzardFrames does. Assertions run the REAL registered builder and
-- then invoke the real widget callbacks, because the bug this covers lived in
-- the callback body and nowhere else: `checked and nil or false` cannot
-- produce nil, since nil and false are both falsy and the or-branch swallows
-- the and-branch's nil. Every tick stored false, so a spec turned off could
-- never be turned back on.
local helpers = require("dev.spec._helpers")

describe("GUI-SpellAlerts", function()
    local KE, GUIFrame, checkboxes, sliders, applyCalls, cvars

    before_each(function()
        checkboxes = {}
        sliders = {}
        applyCalls = 0
        cvars = { spellActivationOverlayOpacity = "0.65" }

        -- File-scope captures in the page: every one of these must be on _G
        -- BEFORE the load or the page holds nil.
        _G.GetNumClasses = function() return 1 end
        _G.C_CreatureInfo = {
            GetClassInfo = function() return { className = "Mage", classFile = "MAGE" } end,
        }
        -- Two specs is enough to prove the callback keys by the spec it was
        -- built for rather than by whichever one ran last.
        local specRows = {
            [1] = { 62, "Arcane" },
            [2] = { 63, "Fire" },
        }
        _G.GetSpecializationInfoForClassID = function(_, specNum)
            local row = specRows[specNum]
            if not row then return nil end
            return row[1], row[2], nil, "icon"
        end
        _G.RAID_CLASS_COLORS = { MAGE = { colorStr = "ff3fc6ea" } }
        _G.C_CVar = {
            GetCVar = function(name) return cvars[name] end,
            SetCVar = function(name, value) cvars[name] = value end,
        }
        _G.SetCVar = _G.C_CVar.SetCVar

        GUIFrame = {
            registeredContent = {},
            RegisterContent = function(self, id, fn) self.registeredContent[id] = fn end,
            CreateWidgetStateManager = function()
                return { Register = function() end, UpdateAll = function() end }
            end,
            CreateCard = function()
                local card = { content = {} }
                function card:AddRow() end
                function card:AddLabel() end
                function card:AddHeaderToggle() end
                function card:GetNextOffset() return 0 end
                return card
            end,
            CreateRow = function()
                local row = {}
                function row:AddWidget() end
                return row
            end,
            CreateText = function() return {} end,
            CreateSlider = function(_, _, _, config)
                local slider = { value = config.value, callback = config.callback }
                sliders[#sliders + 1] = slider
                return slider
            end,
            CreateCheckbox = function(_, _, label, config)
                local checkbox = { label = label, value = config.value, callback = config.callback }
                checkboxes[#checkboxes + 1] = checkbox
                return checkbox
            end,
        }

        KE = {
            GUIFrame = GUIFrame,
            Theme = { rowHeight = 30, rowHeightLast = 40 },
            db = { profile = { SpellAlerts = { Enabled = true, EnabledSpecs = {} } } },
            ColorTextByTheme = function(_, text) return text end,
            Print = function() end,
        }

        local modules = helpers.installAddonShim()
        modules.SpellAlerts = { ApplyForCurrentSpec = function() applyCalls = applyCalls + 1 end }
        _G.KitnEssentials.EnableModule = function() end
        _G.KitnEssentials.DisableModule = function() end

        helpers.loadModule("GUI/GUITabs/GUIClassUtilities/GUI-SpellAlerts.lua", KE)
    end)

    local function build()
        GUIFrame.registeredContent["SpellAlerts"](nil, 0)
    end

    local function specs()
        return KE.db.profile.SpellAlerts.EnabledSpecs
    end

    it("stores nil, not false, when a spec is ticked on", function()
        -- The regression. Storing false here reads back as opted out, so the
        -- box the player just ticked comes back unticked and the overlay
        -- stays off for that spec forever.
        build()
        checkboxes[1].callback(true)
        assert.is_nil(specs()[62])
    end)

    it("stores false when a spec is ticked off", function()
        -- The other half: an explicit false is the opt-out marker. Storing nil
        -- here would read back as the default, which is ON.
        build()
        checkboxes[1].callback(false)
        assert.is_false(specs()[62])
    end)

    it("turns a spec back on after it was turned off", function()
        -- Off then on, through the same callback, is the sequence a player
        -- actually performs and the one that was impossible.
        build()
        checkboxes[1].callback(false)
        checkboxes[1].callback(true)
        assert.is_nil(specs()[62])
    end)

    it("keys each checkbox by its own spec", function()
        build()
        checkboxes[2].callback(false)
        assert.is_nil(specs()[62])
        assert.is_false(specs()[63])
    end)

    it("reads a stored opt-out back into the checkbox", function()
        specs()[62] = false
        build()
        assert.is_false(checkboxes[1].value)
        assert.is_true(checkboxes[2].value)
    end)

    it("re-asserts the per-spec state after the opacity slider writes", function()
        -- Blizzard's own settings callback drives
        -- displaySpellActivationOverlays off the opacity value, so the slider
        -- silently overrides the per-spec choice unless ours is re-applied.
        build()
        local before = applyCalls
        sliders[1].callback(50)
        assert.equals("0.5", cvars.spellActivationOverlayOpacity)
        assert.is_true(applyCalls > before)
    end)
end)
