-- Tier 2: a fixed-size decoration hung off one edge of a host and centred on
-- the other axis. Two terms, one of which is a max() guard that only fires
-- once the decoration outgrows its host -- a combination the GUI sliders allow
-- and nobody would think to smoke. The REAL Core/Globals.lua loads headless
-- via L.loadGlobals().
local L = require("dev.spec._ke_loader")

describe("KE:GetSideDecorationInset", function()
    local KE

    before_each(function()
        KE = L.loadGlobals()
    end)

    -- Shipped DungeonCasts settings: a 20pt raid marker 4pt clear of a 27pt
    -- bar. It fits inside the bar's height, so only the outward term applies.
    it("returns size plus gap outward and nothing across", function()
        local outward, cross = KE:GetSideDecorationInset(20, 4, 27)
        assert.equals(24, outward)
        assert.equals(0, cross)
    end)

    -- Marker exactly as tall as its host is still flush, not overflowing.
    it("returns nothing across when the decoration exactly fits", function()
        local _, cross = KE:GetSideDecorationInset(27, 4, 27)
        assert.equals(0, cross)
    end)

    -- The GUI extremes: a 40pt marker on a 16pt bar overhangs by half the
    -- difference at the top and again at the bottom.
    it("splits the overhang across both perpendicular edges", function()
        local outward, cross = KE:GetSideDecorationInset(40, 4, 16)
        assert.equals(44, outward)
        assert.equals(12, cross)
    end)

    -- A host taller than the decoration must never produce a negative inset;
    -- a negative would pull the box inward and hide part of the bar.
    it("never returns a negative cross inset", function()
        local _, cross = KE:GetSideDecorationInset(12, 4, 40)
        assert.equals(0, cross)
    end)

    it("returns zeroes rather than erroring on missing numbers", function()
        local outward, cross = KE:GetSideDecorationInset(nil, nil, nil)
        assert.equals(0, outward)
        assert.equals(0, cross)
    end)
end)
