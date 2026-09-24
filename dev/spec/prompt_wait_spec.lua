-- Tier 2: Core/Widgets.lua -- the wait rule behind KE:CreatePrompt's
-- opts.waitIfBusy. The refusal rule pinned here: an unsolicited prompt never
-- replaces an open one. The rule is a pure predicate (KE.PromptWaits) rather
-- than a fake dialog, for the reason prompt_typed_gate_spec.lua gives: a
-- stateful fake of the singleton would encode its layout, not the rule.
local mock = require("dev.spec._wow_mock")
local helpers = require("dev.spec._helpers")

describe("Core/Widgets.lua prompt wait rule", function()
    local KE

    before_each(function()
        mock.install()
        KE = helpers.loadModule("Core/Widgets.lua", {})
    end)

    it("waits only when opted in and another prompt is showing", function()
        local cases = {
            { waitIfBusy = true,  showing = true,  waits = true },
            { waitIfBusy = true,  showing = false, waits = false },
            { waitIfBusy = nil,   showing = true,  waits = false },
            { waitIfBusy = false, showing = true,  waits = false },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.waits, KE.PromptWaits(c.waitIfBusy, c.showing),
                ("waitIfBusy %s, showing %s"):format(tostring(c.waitIfBusy), tostring(c.showing)))
        end
    end)
end)
