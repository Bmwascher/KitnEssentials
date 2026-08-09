-- Tier 1: invented arithmetic with two silent failure modes. A wrong fraction
-- or a dropped clamp misplaces the edit-mode box, and a wrong combiner operator
-- either inflates the hitbox or misplaces it — neither of which reads as a bug
-- to anyone looking at it.
local L = require("dev.spec._ke_loader")

describe("KE:GetAnchorFractions", function()
    local KE
    setup(function() KE = L.loadGlobals() end)

    -- Y runs from the bottom, because that is the direction frame offsets run.
    local POINTS = {
        TOPLEFT     = { 0,   1   }, TOP    = { 0.5, 1   }, TOPRIGHT    = { 1, 1   },
        LEFT        = { 0,   0.5 }, CENTER = { 0.5, 0.5 }, RIGHT       = { 1, 0.5 },
        BOTTOMLEFT  = { 0,   0   }, BOTTOM = { 0.5, 0   }, BOTTOMRIGHT = { 1, 0   },
    }

    for point, want in pairs(POINTS) do
        it("places " .. point, function()
            local x, y = KE:GetAnchorFractions(point)
            assert.equals(want[1], x)
            assert.equals(want[2], y)
        end)
    end

    -- Saved profiles predate the current dropdowns and can hold anything. A
    -- throw here would take the whole edit-mode overlay down with it.
    it("centres an unknown point instead of throwing", function()
        local x, y = KE:GetAnchorFractions("NOT_A_POINT")
        assert.equals(0.5, x)
        assert.equals(0.5, y)
    end)

    it("centres a nil point", function()
        local x, y = KE:GetAnchorFractions(nil)
        assert.equals(0.5, x)
        assert.equals(0.5, y)
    end)
end)

describe("KE:GetTextOverlayInset", function()
    local KE
    setup(function() KE = L.loadGlobals() end)

    -- A 10x10 element on a 30x30 host unless a case says otherwise.
    local function inset(hostPoint, elementPoint, dx, dy, ew, eh)
        return KE:GetTextOverlayInset(hostPoint, elementPoint, dx, dy,
            ew or 10, eh or 10, 30, 30)
    end

    it("overhangs nothing when the element sits inside the host", function()
        local l, r, t, b = inset("CENTER", "CENTER", 0, 0)
        assert.equals(0, l); assert.equals(0, r)
        assert.equals(0, t); assert.equals(0, b)
    end)

    it("overhangs right only when pushed right from a right anchor", function()
        local l, r, t, b = inset("RIGHT", "RIGHT", 12, 0)
        assert.equals(0, l); assert.equals(12, r)
        assert.equals(0, t); assert.equals(0, b)
    end)

    it("overhangs left only when pushed left from a left anchor", function()
        local l, r, t, b = inset("LEFT", "LEFT", -12, 0)
        assert.equals(12, l); assert.equals(0, r)
        assert.equals(0, t); assert.equals(0, b)
    end)

    it("overhangs top only when pushed up from a top anchor", function()
        local l, r, t, b = inset("TOP", "TOP", 0, 12)
        assert.equals(0, l); assert.equals(0, r)
        assert.equals(12, t); assert.equals(0, b)
    end)

    it("overhangs bottom only when pushed down from a bottom anchor", function()
        local l, r, t, b = inset("BOTTOM", "BOTTOM", 0, -12)
        assert.equals(0, l); assert.equals(0, r)
        assert.equals(0, t); assert.equals(12, b)
    end)

    -- The X and Y pairs are returned in different orders relative to the
    -- formula's sign, so a copy-paste between axes shows up here.
    it("does not confuse the vertical pair with the horizontal one", function()
        local _, _, t, b = inset("TOP", "TOP", 0, 12)
        assert.are_not.equals(t, b)
    end)

    it("splits the overhang evenly for a centred oversized element", function()
        local l, r, t, b = inset("CENTER", "CENTER", 0, 0, 50, 50)
        assert.equals(10, l); assert.equals(10, r)
        assert.equals(10, t); assert.equals(10, b)
    end)

    -- The reason the general two-fraction form exists. Saved profiles from
    -- before the current dropdowns can anchor an element's corner to a
    -- different corner of its host.
    it("handles a cross-corner anchor", function()
        local l, r, t, b = KE:GetTextOverlayInset(
            "TOPLEFT", "BOTTOMRIGHT", 0, 0, 10, 10, 30, 30)
        assert.equals(10, l); assert.equals(0, r)
        assert.equals(10, t); assert.equals(0, b)
    end)

    -- The cold-cache lower bound. With no measurement the element is a point,
    -- and the offset alone must still push the box out.
    it("still reports the offset for a zero-sized element", function()
        local l, r, t, b = inset("RIGHT", "RIGHT", 20, 0, 0, 0)
        assert.equals(0, l); assert.equals(20, r)
        assert.equals(0, t); assert.equals(0, b)
    end)

    it("survives nil sizes and offsets", function()
        assert.has_no.errors(function()
            KE:GetTextOverlayInset(nil, nil, nil, nil, nil, nil, nil, nil)
        end)
    end)
end)

describe("KE:CombineOverlayInsets", function()
    local KE
    setup(function() KE = L.loadGlobals() end)

    local GRID = { 5, -5, 3, -3 }

    -- Co-located elements are alternatives, not additions: they all overlay the
    -- same button. Summing them manufactures empty hitbox area on every edge.
    it("takes the largest overhang across elements, never their sum", function()
        local l, r, t, b = KE:CombineOverlayInsets(GRID, {
            { 4, 0, 0, 0 },
            { 7, 0, 0, 0 },
            { 2, 0, 0, 0 },
        })
        assert.equals(5 + 7, l)
        assert.equals(-5, r)
        assert.equals(3, t)
        assert.equals(-3, b)
    end)

    -- The grid term is a SHIFT whose two terms cancel. Taking a maximum against
    -- it instead of adding would drop the shift on one edge and misplace the
    -- box rather than merely mis-size it.
    it("adds to the grid term rather than maximising against it", function()
        local l, r = KE:CombineOverlayInsets({ -8, 8, 0, 0 }, { { 3, 3, 0, 0 } })
        assert.equals(-5, l)
        assert.equals(11, r)
    end)

    it("returns the grid term unchanged when no element overhangs", function()
        local l, r, t, b = KE:CombineOverlayInsets(GRID, { { 0, 0, 0, 0 } })
        assert.equals(5, l); assert.equals(-5, r)
        assert.equals(3, t); assert.equals(-3, b)
    end)

    it("returns the grid term unchanged for an empty element list", function()
        local l, r, t, b = KE:CombineOverlayInsets(GRID, {})
        assert.equals(5, l); assert.equals(-5, r)
        assert.equals(3, t); assert.equals(-3, b)
    end)
end)
