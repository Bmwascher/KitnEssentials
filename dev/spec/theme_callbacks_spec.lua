-- Tier 1: theme callbacks (Core/AddonTheme.lua, KE:AddThemeCallback and
-- KE:NotifyThemeChange). A function registered twice runs once per
-- notification, and a failing callback does not stop the next one.
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

    it("keeps calling after a failing callback and passes the accent", function()
        local KE = L.loadAddonTheme()
        local got
        KE:AddThemeCallback(function() error("callback failed") end)
        KE:AddThemeCallback(function(r, g, b) got = { r, g, b } end)
        KE:NotifyThemeChange()
        local a = KE.Theme.accent
        assert.are.same({ a[1], a[2], a[3] }, got)
    end)
end)
