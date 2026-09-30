-- Tier 2: Core/Widgets.lua -- KE.PromptWaits, the predicate KE:CreatePrompt
-- consults for opts.waitIfBusy: an unsolicited prompt waits while another is
-- open, and in combat. The predicate is tested rather than a fake dialog, for the reason
-- prompt_typed_gate_spec.lua gives: a stateful fake of the singleton would
-- encode its layout, not the rule.
local mock = require("dev.spec._wow_mock")
local helpers = require("dev.spec._helpers")

describe("Core/Widgets.lua prompt wait rule", function()
    local KE

    before_each(function()
        mock.install()
        KE = helpers.loadModule("Core/Widgets.lua", {})
    end)

    it("waits only when opted in and another prompt is showing or combat is on", function()
        local cases = {
            { waitIfBusy = true,  showing = true,  inCombat = false, waits = true },
            { waitIfBusy = true,  showing = false, inCombat = false, waits = false },
            { waitIfBusy = true,  showing = false, inCombat = true,  waits = true },
            { waitIfBusy = nil,   showing = true,  inCombat = false, waits = false },
            { waitIfBusy = false, showing = false, inCombat = true,  waits = false },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.waits, KE.PromptWaits(c.waitIfBusy, c.showing, c.inCombat),
                ("waitIfBusy %s, showing %s, inCombat %s"):format(
                    tostring(c.waitIfBusy), tostring(c.showing), tostring(c.inCombat)))
        end
    end)
end)
