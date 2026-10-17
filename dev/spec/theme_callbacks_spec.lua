-- Tier 1: theme callbacks (Core/AddonTheme.lua, KE:AddThemeCallback and
-- KE:NotifyThemeChange). A function registered twice runs once per
-- notification, and a failing module handler or callback reaches the error
-- handler without stopping the next callback.
local L = require("dev.spec._ke_loader")

describe("theme callbacks", function()
    before_each(function() _G.KitnEssentials = nil end)

    it("runs a function registered twice once per notification", function()
        local KE = L.loadAddonTheme()
        local calls = 0
        local function fn() calls = calls + 1 end
        KE:AddThemeCallback(fn)
        KE:AddThemeCallback(fn)
        KE:NotifyThemeChange()
        assert.are.equal(1, calls)
    end)

    it("reports a failing module handler or callback and keeps calling with the accent", function()
        local caught = {}
        local KE = L.loadAddonTheme({
            geterrorhandler = function() return function(err) caught[#caught + 1] = err end end,
        })
        local broken = { OnThemeChanged = function() error("module failed") end }
        _G.KitnEssentials = { IterateModules = function() return pairs({ Broken = broken }) end }
        local got
        KE:AddThemeCallback(function() error("callback failed") end)
        KE:AddThemeCallback(function(r, g, b) got = { r, g, b } end)
        KE:NotifyThemeChange()
        local a = KE.Theme.accent
        assert.are.same({ a[1], a[2], a[3] }, got)
        assert.are.equal(2, #caught)
        assert.matches("module failed", caught[1])
        assert.matches("callback failed", caught[2])
    end)
end)
