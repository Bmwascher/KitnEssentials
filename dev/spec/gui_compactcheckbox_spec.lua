-- Tier 2: GUI/GUIWidgets/GUI-KEToggle.lua -- CreateCompactCheckbox's disabled
-- contract. A disabled cell keeps its saved value on click, so the refusal
-- lives in OnClick. That makes it plain Lua, and worth pinning: a later edit
-- that deletes the branch leaves a greyed-looking row that still writes the
-- user's saved skin choice, with no visible symptom.
local mock = require("dev.spec._wow_mock")
local helpers = require("dev.spec._helpers")

describe("GUIFrame:CreateCompactCheckbox", function()
    local GUIFrame, fired

    before_each(function()
        mock.install()

        fired = 0
        GUIFrame = {}
        helpers.loadModule("GUI/GUIWidgets/GUI-KEToggle.lua", {
            GUIFrame = GUIFrame,
            -- Colour keys answer one triple each; the widget only indexes
            -- [1]..[3], so one table serves them all. fontSizeSmall is a real
            -- NUMBER (Core/AddonTheme.lua) and must be seeded explicitly --
            -- the label size is derived from it arithmetically, so the catch-all
            -- would hand back a table and throw.
            Theme = setmetatable({ fontSizeSmall = 12 }, { __index = function() return { 1, 1, 1 } end }),
            ApplyThemeFont = function() end,
        })
    end)

    local function build(disabled, tooltip)
        -- The mock's CreateFrame ignores its arguments, so any frame serves as
        -- the parent; the widget only needs something to parent to.
        return GUIFrame:CreateCompactCheckbox(CreateFrame(), "Achievements", {
            value = true,
            disabled = disabled,
            tooltip = tooltip,
            callback = function() fired = fired + 1 end,
        })
    end

    it("positive control: an enabled cell toggles and fires its callback", function()
        local cell = build(false)
        cell._scripts.OnClick(cell)
        assert.equals(1, fired)
        assert.is_false(cell:GetChecked())
    end)

    it("a disabled cell neither toggles nor fires", function()
        local cell = build(true)
        cell._scripts.OnClick(cell)
        assert.equals(0, fired)
        -- Unchanged, not just uncalled: the user's saved value survives.
        assert.is_true(cell:GetChecked())
    end)

    it("re-enabling restores the click", function()
        local cell = build(true)
        cell:SetEnabled(true)
        cell._scripts.OnClick(cell)
        assert.equals(1, fired)
    end)
end)
