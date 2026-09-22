-- Tier 2: Core/Widgets.lua -- the typed confirm gate behind
-- KE:CreatePrompt's opts.requireTyped.
--
-- The refusal rule pinned here: the accept button stays disabled until the
-- edit box holds the required string exactly. The gate is a pure predicate
-- (KE.PromptTypedGateOpen) rather than a fake dialog: the dialog is a
-- build-once singleton of frames, edit boxes and scripts, and a stateful fake
-- of it would encode the widget's layout, not the rule. The predicate is the
-- only thing the OnTextChanged and OnEnterPressed scripts consult.
local mock = require("dev.spec._wow_mock")
local helpers = require("dev.spec._helpers")

describe("Core/Widgets.lua typed confirm gate", function()
    local KE

    before_each(function()
        mock.install()
        KE = helpers.loadModule("Core/Widgets.lua", {})
    end)

    it("opens only on an exact match", function()
        local cases = {
            { typed = "Default",  required = "Default", open = true },
            { typed = "default",  required = "Default", open = false },
            { typed = "Default ", required = "Default", open = false },
            { typed = "",         required = "Default", open = false },
            { typed = "Default",  required = nil,       open = false },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.open, KE.PromptTypedGateOpen(c.typed, c.required),
                ("typed %q against %s"):format(c.typed, tostring(c.required)))
        end
    end)
end)
