-- GUI/GUIWidgets/GUI-GlowSettingsCard.lua: the pixel row and the border row
-- each carry a Thickness slider over one key, so a change on the visible one
-- must reach the hidden one before a type switch shows it. Loads against a
-- hand-built GUIFrame stub the way gui_spellalerts_spec does; the assertion
-- runs the real builder and the real slider callback, because the defect
-- lives in the card's own refresh and nowhere else.
local helpers = require("dev.spec._helpers")

describe("GUI-GlowSettingsCard thickness sync", function()
    local KE, GUIFrame, sliders

    before_each(function()
        sliders = {}
        local function widget()
            local w = {}
            function w:SetShown() end
            function w:SetEnabled() end
            return w
        end
        GUIFrame = {
            CreateCard = function()
                local card = { content = {}, headerHeight = 0 }
                function card.content:SetHeight() end
                function card:AddRow() end
                function card:GetNextOffset() return 0 end
                function card:SetHeight() end
                function card:SetAlpha() end
                return card
            end,
            CreateRow = function()
                local row = {}
                function row:AddWidget() end
                function row:SetShown() end
                function row:ClearAllPoints() end
                function row:SetPoint() end
                return row
            end,
            CreateSeparator = function() return {} end,
            CreateCheckbox = widget,
            CreateDropdown = widget,
            CreateColorPicker = widget,
            CreateSlider = function(_, _, label, config)
                local slider = widget()
                slider.label = label
                slider.value = config.value
                slider.callback = config.callback
                function slider:SetValue(val) self.value = val end
                sliders[#sliders + 1] = slider
                return slider
            end,
        }
        KE = {
            GUIFrame = GUIFrame,
            Theme = { rowHeight = 30, rowHeightSeparator = 10, paddingSmall = 4 },
        }
        helpers.loadModule("GUI/GUIWidgets/GUI-GlowSettingsCard.lua", KE)
    end)

    it("shows the saved thickness on both Thickness sliders after a type switch", function()
        local db = { GlowEnabled = true, GlowType = "border", GlowThickness = 2 }
        local card = GUIFrame:CreateGlowSettingsCard(nil, 0, { db = db })
        local thickness = {}
        for _, s in ipairs(sliders) do
            if s.label == "Thickness" then thickness[#thickness + 1] = s end
        end
        assert.equals(2, #thickness)
        thickness[2].callback(6)
        db.GlowType = "pixel"
        card.updateTypeVisibility()
        assert.equals(6, thickness[1].value)
        assert.equals(6, thickness[2].value)
    end)
end)
