-- Tier 2: Modules/Skinning/SkinAPI.lua. Covers the three pieces of this file
-- that are pure enough to test headlessly: the per-frame border math, the
-- secret-value guards, and the theme palette mapping. Everything that dresses
-- a live frame is out of reach here and is verified in-game (spec §8.4).
local L = require("dev.spec._ke_loader")

describe("SkinAPI EdgeFor", function()
    local S
    before_each(function() S = L.loadSkinAPI().Skins end)

    it("returns one physical pixel at UIParent scale", function()
        -- physH 1440, uiScale 1 -> 768/1440
        local bd = { GetEffectiveScale = function() return 1 end }
        assert.near(768 / 1440, S._EdgeFor(bd), 1e-9)
    end)

    it("divides by the frame's scale factor above UIParent", function()
        local bd = { GetEffectiveScale = function() return 1.1 end }
        assert.near((768 / 1440) / 1.1, S._EdgeFor(bd), 1e-9)
    end)

    it("divides by a sub-unity scale factor too", function()
        local bd = { GetEffectiveScale = function() return 0.8 end }
        assert.near((768 / 1440) / 0.8, S._EdgeFor(bd), 1e-9)
    end)

    it("falls back to the UIParent value when the scale read is missing", function()
        assert.near(768 / 1440, S._EdgeFor({}), 1e-9)
    end)

    it("falls back to the UIParent value when the scale is zero", function()
        local bd = { GetEffectiveScale = function() return 0 end }
        assert.near(768 / 1440, S._EdgeFor(bd), 1e-9)
    end)
end)

describe("SkinAPI secret guards", function()
    local S
    before_each(function()
        S = L.loadSkinAPI({
            issecretvalue = function(v) return v == "SECRET" end,
        }).Skins
    end)

    it("passes a clean rect straight through", function()
        local f = { GetRect = function() return 1, 2, 3, 4 end }
        local l, b, w, h = S.SafeRect(f)
        assert.same({ 1, 2, 3, 4 }, { l, b, w, h })
    end)

    it("returns nil when any rect component is secret", function()
        for i = 1, 4 do
            local vals = { 1, 2, 3, 4 }
            vals[i] = "SECRET"
            local f = { GetRect = function() return vals[1], vals[2], vals[3], vals[4] end }
            assert.is_nil(S.SafeRect(f))
        end
    end)

    it("returns nil when the frame has no GetRect", function()
        assert.is_nil(S.SafeRect({}))
        assert.is_nil(S.SafeRect(nil))
    end)

    it("returns nil when GetRect yields nothing", function()
        assert.is_nil(S.SafeRect({ GetRect = function() return nil end }))
    end)

    it("passes a clean size straight through", function()
        local f = { GetSize = function() return 10, 20 end }
        local w, h = S.SafeSize(f)
        assert.same({ 10, 20 }, { w, h })
    end)

    it("returns nil when either size component is secret", function()
        assert.is_nil(S.SafeSize({ GetSize = function() return "SECRET", 20 end }))
        assert.is_nil(S.SafeSize({ GetSize = function() return 10, "SECRET" end }))
    end)
end)

describe("SkinAPI palette", function()
    local KE, S
    before_each(function()
        KE = L.loadSkinAPI()
        S = KE.Skins
    end)

    it("keeps the reference greys verbatim", function()
        assert.same({ 0.031, 0.031, 0.031, 0.80 }, S.palette.window)
        assert.same({ 0.055, 0.055, 0.055, 0.90 }, S.palette.control)
        assert.same({ 0.06, 0.06, 0.06, 0.80 }, S.palette.panel)
        assert.same({ 0, 0, 0, 0.25 }, S.palette.inlineTint)
        assert.same({ 0, 0, 0, 1 }, S.palette.border)
    end)

    it("keeps the reference brand alphas verbatim", function()
        assert.equals(0.8, S.palette.brandFillA)
        assert.equals(0.35, S.palette.brandRestA)
    end)

    it("takes brand rgb from the theme accent", function()
        assert.near(1.0, S.palette.brand[1], 1e-9)
        assert.near(0.0, S.palette.brand[2], 1e-9)
        assert.near(0.549, S.palette.brand[3], 1e-9)
    end)

    it("keeps the reference hover alpha, not the theme alpha", function()
        -- armHover applies 0.15 separately; a themed alpha would double-apply
        assert.equals(0.15, S.palette.hover[4])
    end)

    it("gives progress the accent rgb at alpha 0.40", function()
        assert.near(1.0, S.palette.progress[1], 1e-9)
        assert.equals(0.40, S.palette.progress[4])
    end)

    it("mutates colour tables in place so file-scope captures stay live", function()
        -- brand is captured by BRAND_HL:431, hover by HOVER_COLOR:448 and
        -- CLOSE_REST:626. Both tables must keep their identity across a
        -- refresh or those captures hold an orphan.
        local capturedBrand = S.palette.brand
        local capturedHover = S.palette.hover
        KE.GetThemeColor = function(_, key)
            if key == "accent" then return { 0.0, 1.0, 0.5, 1 } end
            return { 0.2, 0.4, 0.6, 0.25 }
        end
        S.RefreshPalette()
        assert.are.equal(capturedBrand, S.palette.brand)
        assert.are.equal(capturedHover, S.palette.hover)
        assert.near(0.0, capturedBrand[1], 1e-9)
        assert.near(1.0, capturedBrand[2], 1e-9)
        assert.near(0.5, capturedBrand[3], 1e-9)
        assert.near(0.2, capturedHover[1], 1e-9)
        assert.equals(0.15, capturedHover[4])   -- reference alpha survives
    end)
end)

describe("SkinAPI WaitFor", function()
    local S, timers

    before_each(function()
        timers = {}
        S = L.loadSkinAPI({
            C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end },
        }).Skins
    end)

    local function pump(n)
        for _ = 1, n do
            local queued = timers
            timers = {}
            for _, fn in ipairs(queued) do fn() end
        end
    end

    it("runs immediately when the check already passes", function()
        local ran = false
        S.WaitFor(function() return true end, function() ran = true end)
        assert.is_true(ran)
        assert.equals(0, #timers)   -- no poll was queued
    end)

    it("polls until the check passes, then runs once", function()
        local ready, runs = false, 0
        S.WaitFor(function() return ready end, function() runs = runs + 1 end)
        pump(3)
        assert.equals(0, runs)
        ready = true
        pump(1)
        assert.equals(1, runs)
        pump(5)
        assert.equals(1, runs)      -- does not re-run
    end)

    it("gives up at maxFrames without running", function()
        local runs = 0
        S.WaitFor(function() return false end, function() runs = runs + 1 end, 3)
        pump(10)
        assert.equals(0, runs)
        assert.equals(0, #timers)   -- stopped queueing
    end)
end)
