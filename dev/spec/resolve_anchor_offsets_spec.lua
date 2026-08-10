-- Tier 1: invented branching arithmetic. Four branches on the frame's own
-- anchor and six on the parent's, across two axes, and every wrong branch still
-- produces a plausible position -- the element lands somewhere, just not where
-- it was dropped.
local L = require("dev.spec._ke_loader")

describe("KE:ResolveAnchorOffsets", function()
    local KE
    setup(function() KE = L.loadGlobals() end)

    -- A 100x50 element on a 1000x800 parent whose bottom-left is the origin.
    -- Its centre sits at 400,300 unless a case says otherwise.
    local function resolve(anchorFrom, anchorTo, cx, cy)
        return KE:ResolveAnchorOffsets(
            cx or 400, cy or 300, anchorFrom, anchorTo,
            100, 50, 0, 0, 1000, 800)
    end

    it("measures centre to centre", function()
        local x, y = resolve("CENTER", "CENTER")
        assert.equals(-100, x)   -- 400 - 500
        assert.equals(-100, y)   -- 300 - 400
    end)

    -- The frame's own anchor moves the measured point by half its size. Both
    -- signs, on both axes, in one case per axis.
    it("shifts by half the frame width on a left or right anchor", function()
        local left = resolve("LEFT", "CENTER")
        local right = resolve("RIGHT", "CENTER")
        assert.equals(-150, left)    -- (400 - 50) - 500
        assert.equals(-50, right)    -- (400 + 50) - 500
    end)

    it("shifts by half the frame height on a top or bottom anchor", function()
        local _, top = resolve("TOP", "CENTER")
        local _, bottom = resolve("BOTTOM", "CENTER")
        assert.equals(-75, top)      -- (300 + 25) - 400
        assert.equals(-125, bottom)  -- (300 - 25) - 400
    end)

    -- A corner moves both axes at once. Without this, an implementation that
    -- handled the axes in one if/elseif chain instead of two independent ones
    -- would pass everything above.
    it("shifts both axes on a corner anchor", function()
        local x, y = resolve("TOPLEFT", "CENTER")
        assert.equals(-150, x)
        assert.equals(-75, y)
    end)

    -- The parent's anchor picks which of its edges the offset is measured from.
    it("measures from the parent edge the anchor names", function()
        local xl = resolve("CENTER", "LEFT")
        local xr = resolve("CENTER", "RIGHT")
        assert.equals(400, xl)       -- 400 - 0
        assert.equals(-600, xr)      -- 400 - 1000
    end)

    it("measures from the parent top or bottom the anchor names", function()
        local _, yt = resolve("CENTER", "TOP")
        local _, yb = resolve("CENTER", "BOTTOM")
        assert.equals(-500, yt)      -- 300 - 800
        assert.equals(300, yb)       -- 300 - 0
    end)

    -- A parent that does not sit at the origin. Every other case puts it at
    -- 0,0, which makes parentLeft and parentBottom invisible -- drop either one
    -- and all of them still pass. Both corners are asserted because the two X
    -- branches use parentLeft differently: LEFT is parentLeft alone, RIGHT is
    -- parentLeft plus the width, and one case cannot pin both.
    it("respects a parent that is not at the origin", function()
        local bl = { KE:ResolveAnchorOffsets(
            400, 300, "CENTER", "BOTTOMLEFT",
            100, 50, 200, 100, 1000, 800) }
        assert.equals(200, bl[1])    -- 400 - 200
        assert.equals(200, bl[2])    -- 300 - 100

        local br = { KE:ResolveAnchorOffsets(
            400, 300, "CENTER", "BOTTOMRIGHT",
            100, 50, 200, 100, 1000, 800) }
        assert.equals(-800, br[1])   -- 400 - (200 + 1000)
        assert.equals(200, br[2])
    end)

    -- Offsets are whole. A fractional centre must not store a fraction.
    it("rounds both offsets", function()
        local x, y = resolve("CENTER", "CENTER", 400.4, 300.6)
        assert.equals(-100, x)
        assert.equals(-99, y)
    end)
end)
