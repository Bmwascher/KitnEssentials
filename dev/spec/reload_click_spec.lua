-- Tier 2: Core/Widgets.lua -- the order of a prompt's accept click, and which
-- accepts make a reload prompt.
--
-- A client can refuse an addon reload asked for after the prompt has closed
-- and other work has run, so the click asks for it first. Both rules are
-- tested as the functions the click and KE:CreatePrompt call
-- (KE.RunPromptAccept, KE.IsReloadAccept), with recording stubs for the close
-- and the reload, rather than through a fake dialog, for the reason
-- prompt_typed_gate_spec.lua gives.
local mock = require("dev.spec._wow_mock")
local helpers = require("dev.spec._helpers")

describe("Core/Widgets.lua reload click", function()
    local KE

    before_each(function()
        mock.install()
        KE = helpers.loadModule("Core/Widgets.lua", {})
    end)

    it("asks for the reload before the close and the accept, and only on a reload prompt", function()
        for _, row in ipairs({
            { name = "reload accept, no work",   kind = "reload", want = { "reload", "close" } },
            { name = "reload accept with work",  kind = "work",   want = { "reload", "close", "work" } },
            { name = "plain accept",             kind = "plain",  want = { "close", "work" } },
        }) do
            local log = {}
            local function work() log[#log + 1] = "work" end
            local accept = work
            if row.kind == "reload" then
                accept = KE:NewReloadAccept()
            elseif row.kind == "work" then
                accept = KE:NewReloadAccept(work)
            end
            -- The two fields KE:CreatePrompt sets that a confirm prompt's click reads.
            local dialog = { _onAccept = accept, _isReloadPrompt = KE.IsReloadAccept(accept) }
            -- ClosePrompt's contract: clear the accept, return it.
            local function close(d)
                log[#log + 1] = "close"
                local snapshot = d._onAccept
                d._onAccept = nil
                return snapshot
            end
            KE.RunPromptAccept(dialog, close, function() log[#log + 1] = "reload" end)
            assert.same(row.want, log, row.name)
        end
    end)
end)
