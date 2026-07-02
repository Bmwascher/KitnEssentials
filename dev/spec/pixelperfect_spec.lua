-- Tier 2: Core/PixelPerfect.lua snap math, loaded for real via the shared
-- loader. Pedigree: a pixel-grid divisor mix-up (frame:GetEffectiveScale vs
-- KE:GetPixelSize) was the root cause of the 2026-05-27 pixel-perfect
-- overhaul — these cases pin the surviving formula:
--   pixelSize = 768 / (physH * effScale)   (PixelPerfect.lua:48)
-- Float results are compared NUMERICALLY (assert.near / ==), never through
-- tostring: 5.1 prints "1" where 5.4 prints "1.0".
local L = require("dev.spec._ke_loader")

-- Both fixture scales produce an EXACT IEEE pixelSize (1.0 and 0.5), so ==
-- is legal wherever the source itself guarantees exactness; everything else
-- uses assert.near.
local PERFECT = 768 / 1440                 -- physH 1440 → pixelSize exactly 1
local NP_PS = 768 / 1440                   -- effScale 1.0 → pixelSize 768/1440

describe("PixelPerfect.lua pixel-size cache", function()
    local KE, opts
    before_each(function()
        opts = {}
        KE = L.loadPixelPerfect(opts)      -- defaults: physH 1440, eff 768/1440
    end)

    it("computes pixelSize 1 at perfect UI scale", function()
        assert.equals(1, KE:GetPixelSize())
    end)

    it("computes 768/(physH*effScale) at non-perfect scale", function()
        opts.effectiveScale = 1.0
        KE = L.loadPixelPerfect(opts)
        assert.equals(NP_PS, KE:GetPixelSize())
    end)

    it("serves the stale cache until UpdatePixelCache recomputes", function()
        opts.effectiveScale = 1.0          -- stub reads opts live; cache doesn't
        assert.equals(1, KE:GetPixelSize())
        KE:UpdatePixelCache()
        assert.equals(NP_PS, KE:GetPixelSize())
    end)

    it("keeps the last good cache when effScale is invalid", function()
        opts.effectiveScale = 0            -- recompute guard, PixelPerfect.lua:44
        KE:UpdatePixelCache()
        assert.equals(1, KE:GetPixelSize())
    end)

    it("recomputes on UI_SCALE_CHANGED via the watcher frame", function()
        -- Loader's mock.install starts a fresh frame list; the file creates
        -- exactly one frame (the watcher, :261) so _G.frames[1] is it. The
        -- handler also calls ResnapAllBorders with no registry (nil-guard :211).
        opts.effectiveScale = 1.0
        _G.frames[1]:Fire("UI_SCALE_CHANGED")
        assert.equals(NP_PS, KE:GetPixelSize())
    end)
end)

describe("PixelSnap at perfect scale (pixelSize 1)", function()
    local KE
    before_each(function()
        KE = L.loadPixelPerfect({ effectiveScale = PERFECT })
    end)

    it("rounds to the nearest pixel, half away from zero", function()
        assert.equals(0, KE:PixelSnap(0.4))
        assert.equals(1, KE:PixelSnap(0.5))
        assert.equals(1, KE:PixelSnap(0.6))
    end)

    it("is symmetric around zero", function()
        for _, v in ipairs({ 0.2, 0.4, 0.5, 0.6, 1.3, 7.9 }) do
            assert.equals(-KE:PixelSnap(v), KE:PixelSnap(-v))
        end
        assert.equals(-1, KE:PixelSnap(-0.6))
    end)

    it("maps nil and 0 to 0", function()
        assert.equals(0, KE:PixelSnap(nil))
        assert.equals(0, KE:PixelSnap(0))
    end)
end)

describe("PixelSnap at non-perfect scale (pixelSize 768/1440)", function()
    local KE
    before_each(function()
        KE = L.loadPixelPerfect({ effectiveScale = 1.0 })
    end)

    it("lands every result on an exact pixel multiple", function()
        for _, v in ipairs({ 0.3, 1, 2.5, 7.1, -1.7 }) do
            local px = KE:PixelSnap(v) / NP_PS
            assert.near(math.floor(px + 0.5), px, 1e-9)
        end
        assert.near(2 * NP_PS, KE:PixelSnap(1), 1e-12)  -- 1.875px rounds to 2px
    end)

    it("keeps non-integer multiples untouched by the cleanup", function()
        local snapped = KE:PixelSnap(1)                 -- 2px = 1.0666... units
        assert.is_true(math.abs(snapped - math.floor(snapped + 0.5)) > 0.001)
    end)

    it("cleans near-integer results to exact integers", function()
        -- 7.9 → 15px = 15*(768/1440) ≈ 8 within float error; the <0.001
        -- cleanup (:88-:89) must return the EXACT integer, symmetrically.
        assert.equals(8, KE:PixelSnap(7.9))
        assert.equals(-8, KE:PixelSnap(-7.9))
    end)
end)

describe("PixelSnapEven", function()
    local KE
    before_each(function()
        KE = L.loadPixelPerfect({ effectiveScale = PERFECT })
    end)

    it("bumps odd pixel counts up to even", function()
        assert.equals(4, KE:PixelSnapEven(3))
    end)

    it("keeps even pixel counts", function()
        assert.equals(4, KE:PixelSnapEven(4))
    end)

    it("bumps negative odd counts toward zero", function()
        -- :104 always adds +1 (Lua's floored % gives px%2 ∈ {0,1} for
        -- negatives too), so -3px becomes -2px, not -4px.
        assert.equals(-2, KE:PixelSnapEven(-3))
    end)

    it("maps nil and 0 to 0", function()
        assert.equals(0, KE:PixelSnapEven(nil))
        assert.equals(0, KE:PixelSnapEven(0))
    end)

    it("returns even pixel multiples at non-perfect scale", function()
        KE = L.loadPixelPerfect({ effectiveScale = 1.0 })
        assert.near(2 * NP_PS, KE:PixelSnapEven(1), 1e-12)  -- 1.875px → 2px
    end)
end)

describe("PixelHalfFloor", function()
    local KE
    before_each(function()
        KE = L.loadPixelPerfect({ effectiveScale = PERFECT })
    end)

    it("floors half the rounded pixel count", function()
        assert.equals(1, KE:PixelHalfFloor(3))
        assert.equals(2, KE:PixelHalfFloor(4))
        assert.equals(2, KE:PixelHalfFloor(5))
    end)

    it("floors negative counts downward", function()
        assert.equals(-2, KE:PixelHalfFloor(-3))   -- floor(-3/2) = -2px
    end)

    it("maps nil and 0 to 0", function()
        assert.equals(0, KE:PixelHalfFloor(nil))
        assert.equals(0, KE:PixelHalfFloor(0))
    end)

    it("returns pixel multiples at non-perfect scale", function()
        KE = L.loadPixelPerfect({ effectiveScale = 1.0 })
        assert.near(NP_PS, KE:PixelHalfFloor(1.6), 1e-12)  -- 3px → floor(1.5) = 1px
    end)
end)

describe("PixelSnapCenter", function()
    local KE
    before_each(function()
        KE = L.loadPixelPerfect({ effectiveScale = PERFECT })
    end)

    it("snaps to a half-pixel center for odd pixel widths", function()
        assert.equals(100.5, KE:PixelSnapCenter(100.2, 11))
    end)

    it("takes the nearest half-pixel via floor+0.5 for odd widths", function()
        -- :127 floors to the pixel below then adds half — for a half-integer
        -- grid that IS the nearest half-pixel (100.7 → 100.5, not 101.5).
        assert.equals(100.5, KE:PixelSnapCenter(100.7, 11))
    end)

    it("snaps to a whole pixel for even widths", function()
        assert.equals(100, KE:PixelSnapCenter(100.2, 10))
    end)

    it("snaps to a whole pixel with no dim", function()
        assert.equals(101, KE:PixelSnapCenter(100.7))
    end)

    it("treats dim 0 as no dim", function()
        assert.equals(100, KE:PixelSnapCenter(100.2, 0))   -- dim>0 guard :124
    end)

    it("passes nil through (unlike PixelSnap's 0)", function()
        assert.is_nil(KE:PixelSnapCenter(nil))             -- :121
    end)

    it("centers odd widths on integer+0.5 pixels at non-perfect scale", function()
        KE = L.loadPixelPerfect({ effectiveScale = 1.0 })
        local center = KE:PixelSnapCenter(1, 3 * NP_PS)    -- 3px-wide frame
        assert.near(1.5, center / NP_PS, 1e-9)             -- half-pixel center
        assert.near(1.5 * NP_PS, center, 1e-12)
    end)
end)

describe("SnapFrameToPixels", function()
    local KE

    -- Records geometry queries and anchor writes. Only the five methods the
    -- source touches (:237-:254) exist — anything else erroring is a signal.
    local function makeFrame(left, bottom, point)
        local f = { clearCalls = 0, setCalls = {} }
        function f:GetLeft() return left end
        function f:GetBottom() return bottom end
        function f:GetPoint()
            if not point then return nil end
            return point[1], point[2], point[3], point[4], point[5]
        end
        function f:ClearAllPoints() self.clearCalls = self.clearCalls + 1 end
        function f:SetPoint(p, rel, relPoint, x, y)
            self.setCalls[#self.setCalls + 1] =
                { point = p, relativeTo = rel, relativePoint = relPoint, x = x, y = y }
        end
        return f
    end

    before_each(function()
        -- physH 1536 / eff 1.0 → pixelSize EXACTLY 0.5 (dyadic float). The
        -- aligned no-op depends on offset == 0 exactly (:248), so the fixture
        -- scale must make pixel multiples exactly representable.
        KE = L.loadPixelPerfect({ physicalHeight = 1536, effectiveScale = 1.0 })
        assert.equals(0.5, KE:GetPixelSize())
    end)

    it("re-anchors a sub-pixel frame by the snap delta", function()
        -- left 10.2 → 10.0 (dx ≈ -0.2); bottom 20.3 → 20.5 (dy ≈ +0.2)
        local f = makeFrame(10.2, 20.3, { "TOPLEFT", "REL", "BOTTOMLEFT", 3, -5 })
        KE:SnapFrameToPixels(f)
        assert.equals(1, f.clearCalls)
        assert.equals(1, #f.setCalls)
        local c = f.setCalls[1]
        assert.equals("TOPLEFT", c.point)
        assert.equals("REL", c.relativeTo)
        assert.equals("BOTTOMLEFT", c.relativePoint)
        assert.near(2.8, c.x, 1e-9)
        assert.near(-4.8, c.y, 1e-9)
        -- the delta puts the edge on the pixel grid
        assert.near(20, (10.2 + (c.x - 3)) / 0.5, 1e-9)
    end)

    it("defaults nil point offsets to 0 before adding the delta", function()
        local f = makeFrame(10.2, 20.3, { "CENTER", nil, "CENTER", nil, nil })
        KE:SnapFrameToPixels(f)                            -- (x or 0) at :254
        local c = f.setCalls[1]
        assert.near(-0.2, c.x, 1e-9)
        assert.near(0.2, c.y, 1e-9)
    end)

    it("leaves an already-aligned frame untouched", function()
        local f = makeFrame(10.0, 20.5, { "TOPLEFT", "REL", "TOPLEFT", 0, 0 })
        KE:SnapFrameToPixels(f)
        assert.equals(0, f.clearCalls)
        assert.equals(0, #f.setCalls)
    end)

    it("is a no-op for a sub-pixel frame with no anchor point", function()
        local f = makeFrame(10.2, 20.3, nil)               -- GetPoint → nil, :251
        KE:SnapFrameToPixels(f)
        assert.equals(0, f.clearCalls)
        assert.equals(0, #f.setCalls)
    end)

    it("tolerates frames without geometry and nil frames", function()
        local f = makeFrame(nil, nil, { "CENTER", nil, "CENTER", 0, 0 })
        KE:SnapFrameToPixels(f)                            -- GetLeft nil, :239
        assert.equals(0, #f.setCalls)
        KE:SnapFrameToPixels(nil)                          -- :234
    end)
end)
