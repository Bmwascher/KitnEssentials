-- Tier 1: invented branching arithmetic with a derived, capped threshold. Every
-- value below was produced by running the specified arithmetic, not by reading
-- it. Two traps are pinned deliberately: ties round toward positive and are
-- therefore asymmetric about the origin, and a value sitting exactly on a line
-- returns itself -- so an on-line input cannot tell a snap from a no-op and is
-- never used as one here.
local L = require("dev.spec._ke_loader")

local function ctx(spacing, originX, originY, enabled)
    return {
        enabled = enabled ~= false,
        spacing = spacing,
        originX = originX or 0,
        originY = originY or 0,
    }
end

describe("KE:SnapCenter threshold derivation", function()
    local KE
    setup(function() KE = L.loadGlobals() end)

    -- min(spacing/2, 12). At 8 and 16 the cap does not bite, so the threshold
    -- IS half the spacing and coverage is total -- there is no "just outside"
    -- value to test at those settings, and asking for one is how this block was
    -- wrong the first time.
    for _, spacing in ipairs({ 8, 16 }) do
        it("snaps everything at spacing " .. spacing, function()
            for _, v in ipairs({ 1, 3, 5, 7, 9, 11 }) do
                local x = KE:SnapCenter(v, 0, ctx(spacing))
                assert.equals(0, x % spacing)
            end
        end)
    end

    -- At 32 and 64 the cap bites, which is what creates the dead space.
    it("snaps at the threshold and declines past it at spacing 32", function()
        assert.equals(0, KE:SnapCenter(12, 0, ctx(32)))
        assert.equals(12.5, KE:SnapCenter(12.5, 0, ctx(32)))
    end)

    it("leaves the midpoint of a 32 cell unsnapped", function()
        assert.equals(16, KE:SnapCenter(16, 0, ctx(32)))
    end)

    it("snaps at the threshold and declines past it at spacing 64", function()
        assert.equals(0, KE:SnapCenter(12, 0, ctx(64)))
        assert.equals(12.5, KE:SnapCenter(12.5, 0, ctx(64)))
    end)

    -- 32 and 64 share a threshold only because of the cap. Without it, 64's
    -- threshold would be 32 and this would snap.
    it("caps rather than using half the spacing at 64", function()
        assert.equals(20, KE:SnapCenter(20, 0, ctx(64)))
    end)
end)

describe("KE:SnapCenter snapping", function()
    local KE
    setup(function() KE = L.loadGlobals() end)

    it("snaps to the nearest line, not always the origin", function()
        -- spacing 32, origin 1280 -> lines at 1248, 1280, 1312.
        local x = KE:SnapCenter(1306, 0, ctx(32, 1280))
        assert.equals(1312, x)
    end)

    it("leaves a value in the dead space alone", function()
        -- 1296 is 16 from both neighbouring lines; the threshold is 12.
        local x = KE:SnapCenter(1296, 0, ctx(32, 1280))
        assert.equals(1296, x)
    end)

    -- y = 736 sits 16 from both its neighbouring lines, so it is genuinely in
    -- the dead space. A value merely "far from the centre" is not enough: 900
    -- looks unsnapped but lands exactly on the threshold of another line.
    it("decides the two axes independently", function()
        local x, y, cx, cy = KE:SnapCenter(1280, 736, ctx(32, 1280, 720))
        assert.equals(1280, x)
        assert.equals(736, y)
        assert.is_true(cx)
        assert.is_false(cy)
    end)

    it("reports the centre only at the origin itself", function()
        local _, _, cx = KE:SnapCenter(1306, 0, ctx(32, 1280))
        assert.is_false(cx)
    end)

    it("works with a non-whole origin", function()
        local x = KE:SnapCenter(684, 0, ctx(32, 682.5))
        assert.equals(682.5, x)
    end)
end)

describe("KE:SnapCenter tie handling", function()
    local KE
    setup(function() KE = L.loadGlobals() end)

    -- Ties round toward positive, the same idiom SnapFrameToPixels uses. The
    -- asymmetry about the origin is intended: these two cases are the same
    -- distance from zero and land on different lines. A later "fix" that makes
    -- them symmetric breaks here, which is the point.
    it("rounds a positive tie away from the origin", function()
        local x = KE:SnapCenter(4, 0, ctx(8))
        assert.equals(8, x)
    end)

    it("rounds a negative tie toward the origin", function()
        local x = KE:SnapCenter(-4, 0, ctx(8))
        assert.equals(0, x)
    end)

    it("resolves a tie the same way every time", function()
        local first = KE:SnapCenter(4, 0, ctx(8))
        local second = KE:SnapCenter(4, 0, ctx(8))
        assert.equals(first, second)
    end)
end)

describe("KE:SnapCenter refusals", function()
    local KE
    setup(function() KE = L.loadGlobals() end)

    -- enabled lives in the context so the off-path cannot be implemented
    -- separately by each caller and drift.
    it("returns the input untouched when disabled", function()
        local x, y, cx, cy = KE:SnapCenter(700.4, 12.3, ctx(32, 1280, 720, false))
        assert.equals(700.4, x)
        assert.equals(12.3, y)
        assert.is_false(cx)
        assert.is_false(cy)
    end)

    it("returns the input untouched with no context at all", function()
        local x, y, cx, cy = KE:SnapCenter(700.4, 12.3, nil)
        assert.equals(700.4, x)
        assert.equals(12.3, y)
        assert.is_false(cx)
        assert.is_false(cy)
    end)

    it("returns the input untouched when spacing is missing or zero", function()
        local x = KE:SnapCenter(700.4, 0, { enabled = true, spacing = 0, originX = 0, originY = 0 })
        assert.equals(700.4, x)

        local x2 = KE:SnapCenter(700.4, 0, { enabled = true, originX = 0, originY = 0 })
        assert.equals(700.4, x2)
    end)
end)
