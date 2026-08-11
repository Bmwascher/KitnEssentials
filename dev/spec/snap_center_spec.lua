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

-- Element candidates. The dragged box's three edge offsets are measured from
-- its frame centre, so a symmetric box of width 20 is -10, 0, 10. Every
-- expected number below was produced by running the arithmetic.
--
-- Cases that are purely about elements use a spacing of 1000, which puts the
-- nearest grid line hundreds of units away. A distant ORIGIN does not do that
-- job -- the lattice is infinite, so there is always a line nearby -- and an
-- earlier draft of these cases got that wrong and passed for the wrong reason.
local function elementCtx(spacing, candidates, near, centre, far, originX)
    return {
        enabled = true,
        spacing = spacing,
        originX = originX or 0,
        originY = 0,
        candidatesX = candidates,
        edgeLeft = near,
        edgeCentreX = centre,
        edgeRight = far,
    }
end

describe("KE:SnapCenter element candidates", function()
    local KE
    setup(function() KE = L.loadGlobals() end)

    -- Each of the three edges gets its own case. A version written against the
    -- centre alone passes every case that varies the centre and silently never
    -- aligns an edge, which is most of what this feature is for.
    it("aligns the box left edge to a candidate", function()
        -- Left edge sits 10 left of centre, so centre 210 puts it on 200.
        local x, _, _, _, guideX = KE:SnapCenter(208, 0, elementCtx(1000, { 200 }, -10, 0, 10))
        assert.equals(210, x)
        assert.equals(200, guideX)
    end)

    it("aligns the box centre to a candidate", function()
        local x, _, _, _, guideX = KE:SnapCenter(202, 0, elementCtx(1000, { 200 }, -10, 0, 10))
        assert.equals(200, x)
        assert.equals(200, guideX)
    end)

    it("aligns the box right edge to a candidate", function()
        local x, _, _, _, guideX = KE:SnapCenter(192, 0, elementCtx(1000, { 200 }, -10, 0, 10))
        assert.equals(190, x)
        assert.equals(200, guideX)
    end)

    it("reports no guide on an axis that did not reach a candidate", function()
        local x, _, _, _, guideX = KE:SnapCenter(150, 0, elementCtx(1000, { 200 }, -10, 0, 10))
        assert.equals(150, x)
        assert.is_nil(guideX)
    end)

    -- The shared threshold. At spacing 8 it is 4, not the cap, so an element 5
    -- away must be refused. A separate element threshold would accept it.
    -- NO CASE for "elements share the grid's threshold", deliberately. It was
    -- written, it passed, and mutation-testing showed it passed under the wrong
    -- implementation too -- so it was measuring nothing.
    --
    -- The rule turns out to be unobservable, and the reason is worth keeping.
    -- The two thresholds differ only below spacing 24, where the grid's is
    -- spacing/2 rather than the cap. But a lattice of that spacing always has a
    -- line within spacing/2 of any value, so the grid ALWAYS matches there. An
    -- element allowed only by the wider cap is by definition further away than
    -- spacing/2, hence further than the grid line, so it loses the comparison
    -- anyway. Sharing one threshold is still the right implementation -- it
    -- cannot be wrong and it needs no second constant -- but no test can tell
    -- it from the alternative, and a test that claims to is worse than none.
end)

describe("KE:SnapCenter element against grid", function()
    local KE
    setup(function() KE = L.loadGlobals() end)

    it("takes whichever is closer", function()
        -- Grid line at 200, element at 206.
        local near = elementCtx(32, { 206 }, -10, 0, 10, 200)

        -- 204: grid 4 away, element 2 away, so the element wins.
        local x, _, _, _, guideX = KE:SnapCenter(204, 0, near)
        assert.equals(206, x)
        assert.equals(206, guideX)

        -- 201: grid 1 away, element 5 away, so the grid wins and draws nothing.
        local x2, _, _, _, guideX2 = KE:SnapCenter(201, 0, near)
        assert.equals(200, x2)
        assert.is_nil(guideX2)
    end)

    it("gives an exact tie to the element", function()
        -- Grid line 200, element 204, value 202: both are 2 away.
        local x, _, _, _, guideX =
            KE:SnapCenter(202, 0, elementCtx(32, { 204 }, -10, 0, 10, 200))
        assert.equals(204, x)
        assert.equals(204, guideX)
    end)

    -- An element landing on the origin must not light the centre guide as well,
    -- or one axis shows two lines.
    it("reports onCentre false when an element wins at the origin", function()
        local _, _, onCentreX =
            KE:SnapCenter(200, 0, elementCtx(32, { 200 }, 0, 0, 0, 200))
        assert.is_false(onCentreX)
    end)
end)

describe("KE:SnapCenter element tie-breaking", function()
    local KE
    setup(function() KE = L.loadGlobals() end)

    -- Candidate order must not decide the answer: the list is built from a
    -- pairs() walk upstream, so first-seen is not contractual.
    it("does not depend on candidate order", function()
        local first = KE:SnapCenter(205, 0, elementCtx(32, { 200, 210 }, -5, 0, 5))
        local second = KE:SnapCenter(205, 0, elementCtx(32, { 210, 200 }, -5, 0, 5))
        assert.equals(first, second)
    end)

    it("breaks a same-centre tie on the higher matched coordinate", function()
        -- Offsets -5/0/5 against 200 and 210 at value 205: 200 minus -5 and
        -- 210 minus 5 both give 205, same displacement, so only the drawn
        -- coordinate can separate them.
        local _, _, _, _, guideA = KE:SnapCenter(205, 0, elementCtx(32, { 200, 210 }, -5, 0, 5))
        local _, _, _, _, guideB = KE:SnapCenter(205, 0, elementCtx(32, { 210, 200 }, -5, 0, 5))
        assert.equals(210, guideA)
        assert.equals(guideA, guideB)
    end)
end)

describe("KE:SnapCenter suppression and degenerate candidates", function()
    local KE
    setup(function() KE = L.loadGlobals() end)

    it("returns the raw value and no guide while suppressed", function()
        local c = elementCtx(32, { 200 }, -10, 0, 10, 200)
        local x, y, onX, onY, guideX, guideY = KE:SnapCenter(202, 200, c, true)
        assert.equals(202, x)
        assert.equals(200, y)
        assert.is_false(onX)
        assert.is_false(onY)
        assert.is_nil(guideX)
        assert.is_nil(guideY)
    end)

    -- One visible element means no neighbours, which is ordinary rather than
    -- broken. Grid snapping has to survive it, or the feature makes the tool
    -- worse on a sparse screen than it was before.
    it("leaves grid snapping working with no candidates", function()
        assert.equals(200, KE:SnapCenter(202, 0, elementCtx(32, {}, -10, 0, 10, 200)))
        assert.equals(200, KE:SnapCenter(202, 0, elementCtx(32, nil, -10, 0, 10, 200)))
    end)

    it("leaves grid snapping working when the edge offsets are missing", function()
        local x, _, _, _, guideX =
            KE:SnapCenter(202, 0, elementCtx(32, { 204 }, nil, nil, nil, 200))
        assert.equals(200, x)
        assert.is_nil(guideX)
    end)
end)
