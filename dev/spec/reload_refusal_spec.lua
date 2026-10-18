-- Tier 2: Core/Widgets.lua -- reloading on a client that refuses ReloadUI from
-- addon code.
--
-- The refusal rule: where the policy withholds AddonReload, no KE path calls
-- ReloadUI, which that client blocks for addon code; the reload prompt's secure
-- button reloads instead. The combat gate: that button's anchors and
-- attributes cannot change in lockdown. The button itself is frame work and is
-- smoked, not faked.
local mock = require("dev.spec._wow_mock")
local helpers = require("dev.spec._helpers")

describe("Core/Widgets.lua reload refusal", function()
    it("reloads directly after a retail load and only through the prompt after a baseline load", function()
        for _, row in ipairs({
            { load = "retail",   baseline = nil,  direct = 1, prompts = 0, accept = 1, prints = 0 },
            { load = "baseline", baseline = true, direct = 0, prompts = 1, accept = 0, prints = 1 },
        }) do
            mock.install({})
            local reloads = 0
            _G.ReloadUI = function() reloads = reloads + 1 end
            local KE = helpers.loadModule("Core/Availability.lua", { BASELINE_LOAD = row.baseline })
            helpers.loadModule("Core/Widgets.lua", KE)
            -- Replaced after the load, which defines CreatePrompt itself.
            local prompts, accept, prints = 0, nil, 0
            KE.CreatePrompt = function(_, _, _, _, _, _, _, _, _, _, onAccept)
                prompts = prompts + 1
                accept = onAccept
            end
            KE.Print = function() prints = prints + 1 end

            KE:ReloadUI()
            assert.equals(row.direct, reloads, row.load .. " direct reload")
            assert.equals(row.prompts, prompts, row.load .. " prompt")

            reloads = 0
            KE:CreateReloadPrompt()
            accept()
            assert.equals(row.accept, reloads, row.load .. " accept reload")
            assert.equals(row.prints, prints, row.load .. " accept print")
        end
    end)
end)

describe("Core/Widgets.lua secure reload gate", function()
    it("lays the secure button only for the reload prompt, where addon reloads are refused, out of lockdown", function()
        mock.install({})
        local KE = helpers.loadModule("Core/Widgets.lua", {})
        for _, row in ipairs({
            { name = "reload prompt, refused, out of combat", reload = true,  allowed = false, lockdown = false, want = true },
            { name = "in lockdown",                           reload = true,  allowed = false, lockdown = true,  want = false },
            { name = "addon reloads allowed",                 reload = true,  allowed = true,  lockdown = false, want = false },
            { name = "another prompt",                        reload = false, allowed = false, lockdown = false, want = false },
        }) do
            assert.equals(row.want, KE.SecureReloadWanted(row.reload, row.allowed, row.lockdown), row.name)
        end
    end)
end)
