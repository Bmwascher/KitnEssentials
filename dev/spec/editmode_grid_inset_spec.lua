-- Tier 2: icon-grid overlay insets. The aura containers are sized to the grid
-- extent but the grid itself is pinned to the module's anchor corner and grows
-- from there, so flipping a growth direction slides the whole grid out of its
-- own frame. This is arithmetic KE invented, it branches on three settings, and
-- a wrong term is invisible in game until someone flips a growth direction and
-- the box lands somewhere else -- so it is tested rather than smoked.
-- The REAL Core/Globals.lua loads headless via L.loadGlobals().
local L = require("dev.spec._ke_loader")

describe("KE:GetGridOverlayInset", function()
    local KE

    before_each(function()
        KE = L.loadGlobals()
    end)

    -- Shipped AuraDebuffs settings: 3x2 grid of 52pt icons, 1pt spacing,
    -- anchored BOTTOMLEFT, growing RIGHT and UP. Anchor and growth agree, so
    -- the grid fills the frame and there is nothing to inset.
    it("returns zero on every edge when anchor and growth agree", function()
        local l, r, t, b = KE:GetGridOverlayInset(3, 2, 52, 1, "BOTTOMLEFT", false, true)
        assert.equals(0, l)
        assert.equals(0, r)
        assert.equals(0, t)
        assert.equals(0, b)
    end)

    -- Same grid, horizontal growth flipped. Frame width is
    -- (3-1)*53 + 52 = 158; the grid slides left by width minus one icon.
    it("insets the full grid span when horizontal growth opposes the anchor", function()
        local l, r, t, b = KE:GetGridOverlayInset(3, 2, 52, 1, "BOTTOMLEFT", true, true)
        assert.equals(106, l)
        assert.equals(-106, r)
        assert.equals(0, t)
        assert.equals(0, b)
    end)

    -- Same grid, vertical growth flipped. Frame height is (2-1)*53 + 52 = 105.
    it("insets downward when vertical growth opposes the anchor", function()
        local l, r, t, b = KE:GetGridOverlayInset(3, 2, 52, 1, "BOTTOMLEFT", false, false)
        assert.equals(0, l)
        assert.equals(0, r)
        assert.equals(-53, t)
        assert.equals(53, b)
    end)

    -- Shipped AuraExternals settings: 2x2, anchored BOTTOMRIGHT, growing LEFT
    -- and UP. Agreeing pair again, so zero.
    it("returns zero for a right-anchored grid growing left", function()
        local l, r, t, b = KE:GetGridOverlayInset(2, 2, 52, 1, "BOTTOMRIGHT", true, true)
        assert.equals(0, l)
        assert.equals(0, r)
        assert.equals(0, t)
        assert.equals(0, b)
    end)

    -- Same grid, horizontal growth flipped: (2-1)*53 + 52 = 105, minus one
    -- icon, spills right.
    it("insets right when a right-anchored grid grows right", function()
        local l, r, t, b = KE:GetGridOverlayInset(2, 2, 52, 1, "BOTTOMRIGHT", false, true)
        assert.equals(-53, l)
        assert.equals(53, r)
        assert.equals(0, t)
        assert.equals(0, b)
    end)

    -- A CENTER anchor splits the overhang evenly, because button[1] straddles
    -- the frame's centre instead of sitting on a corner. Width 158, one icon
    -- 52, so 106 of overhang -- 53 to each side depending on growth.
    it("splits the overhang evenly for a centre anchor", function()
        local l, r, t, b = KE:GetGridOverlayInset(3, 2, 52, 1, "CENTER", false, true)
        assert.equals(-53, l)
        assert.equals(53, r)
        assert.equals(26.5, t)
        assert.equals(-26.5, b)
    end)

    it("splits the overhang the other way when growth flips", function()
        local l, r, t, b = KE:GetGridOverlayInset(3, 2, 52, 1, "CENTER", true, false)
        assert.equals(53, l)
        assert.equals(-53, r)
        assert.equals(-26.5, t)
        assert.equals(26.5, b)
    end)

    -- A single column or row has no overhang to distribute in that axis, in any
    -- combination. This is the guard against an off-by-one in the (n-1) terms.
    it("returns zero on an axis with a single icon", function()
        local l, r = KE:GetGridOverlayInset(1, 2, 52, 1, "BOTTOMLEFT", true, true)
        assert.equals(0, l)
        assert.equals(0, r)

        local _, _, t, b = KE:GetGridOverlayInset(3, 1, 52, 1, "BOTTOMLEFT", false, false)
        assert.equals(0, t)
        assert.equals(0, b)
    end)

    -- TOPRIGHT exercises both axes' non-default branch at once.
    it("handles a top-right anchor on both axes", function()
        local l, r, t, b = KE:GetGridOverlayInset(3, 2, 52, 1, "TOPRIGHT", false, true)
        assert.equals(-106, l)
        assert.equals(106, r)
        assert.equals(53, t)
        assert.equals(-53, b)
    end)

    -- Called before a db exists, or with a settings table mid-edit, must not
    -- throw from a layout path. Zero is the plain SetAllPoints behaviour.
    it("returns zeroes rather than erroring on missing numbers", function()
        local l, r, t, b = KE:GetGridOverlayInset(nil, nil, nil, nil, nil, false, false)
        assert.equals(0, l)
        assert.equals(0, r)
        assert.equals(0, t)
        assert.equals(0, b)
    end)
end)
