-- Tier: a guard rule. The RC skin hooks LibWindow's shared SetScale only with
-- its row's dispatch gate open (a debug rerun can run the skin with the row
-- off), and at most once per session, so reruns never stack hooks.

local helpers = require("dev.spec._helpers")

local function loadPredicate()
    local S = { Register = function() end }
    helpers.loadModule("Modules/Skinning/Addons/RCLootCouncil.lua", { Skins = S })
    return S._RCScaleHookNeeded
end

describe("RC skin: when to hook LibWindow's SetScale", function()
    it("hooks only with the gate open, the library present and no hook yet", function()
        local needed = loadPredicate()
        for _, row in ipairs({
            { "gate closed",    false, true,  false, false },
            { "first hook",     true,  true,  false, true  },
            { "already hooked", true,  true,  true,  false },
            { "no library",     true,  false, false, false },
        }) do
            assert.equals(row[5], needed(row[2], row[3], row[4]) and true or false, row[1])
        end
    end)
end)
