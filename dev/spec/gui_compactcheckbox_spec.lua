-- Tier 2: GUI/GUIWidgets/GUI-KEToggle.lua -- CreateCompactCheckbox's disabled
-- contract. A disabled cell keeps mouse input (it must stay hoverable, because
-- its tooltip is the only thing that says why it is greyed), so the refusal
-- lives in OnClick. That makes it plain Lua, and worth pinning: a later edit
-- that deletes the branch leaves a greyed-looking row that still writes the
-- user's saved skin choice, with no visible symptom.
local mock = require("dev.spec._wow_mock")
local helpers = require("dev.spec._helpers")

describe("GUIFrame:CreateCompactCheckbox", function()
    local GUIFrame, fired, tipped, mouseKilled

    before_each(function()
        mock.install()
        -- Records what OnEnter asked the tooltip to say. SetText's first real
        -- argument is the text; the leading _ absorbs the colon call's self.
        tipped = nil
        _G.GameTooltip = setmetatable({
            SetText = function(_, text) tipped = text end,
        }, { __index = function() return function() end end })

        -- Wrap the mock's factory so every frame this spec builds reports an
        -- EnableMouse(false). Firing OnEnter by hand cannot detect an
        -- unhoverable cell -- the mock models no hit-testing, so the handler
        -- runs either way -- and without this the tooltip example below would
        -- stay green through exactly the regression it exists to catch.
        mouseKilled = false
        local baseCreateFrame = _G.CreateFrame
        _G.CreateFrame = function(...)
            local f = baseCreateFrame(...)
            -- A real key beats the mock frame's catch-all __index.
            function f:EnableMouse(v) if v == false then mouseKilled = true end end
            return f
        end

        fired = 0
        GUIFrame = {}
        helpers.loadModule("GUI/GUIWidgets/GUI-KEToggle.lua", {
            GUIFrame = GUIFrame,
            -- Every Theme key answers one colour triple. The widget only ever
            -- indexes [1]..[3], so one table serves them all.
            Theme = setmetatable({}, { __index = function() return { 1, 1, 1 } end }),
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

    -- The other half of the disabled contract, and the reason SetEnabled does
    -- NOT call EnableMouse(false). A greyed row's tooltip is the only thing
    -- that says why it is greyed once the per-row text marker is gone, so an
    -- unhoverable greyed row would make the note line above the grid a lie.
    it("a disabled cell stays hoverable and still shows its tooltip", function()
        local cell = build(true, "EllesmereUI already skins this window.")
        -- The load-bearing assertion. The one below only proves the handler
        -- forwards the text when something calls it; this proves something
        -- still CAN. Assert it first so a regression names itself.
        assert.is_false(mouseKilled,
            "the widget disabled mouse input, so this cell cannot be hovered in game")
        cell._scripts.OnEnter(cell)
        assert.equals("EllesmereUI already skins this window.", tipped)
    end)
end)
