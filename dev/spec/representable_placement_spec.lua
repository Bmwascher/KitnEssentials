-- Tier 1: invented arithmetic, and a right-inverse, which is the rare case
-- where the property is stronger than any table of expected numbers. Asserting
-- specific centres would only re-transcribe the formula; asserting that the
-- round trip closes catches a wrong term in either direction.
--
-- Every anchor pair is covered rather than a sample. There are 81 and the
-- helper branches on substrings of the anchor name, so a pair that behaves
-- differently is exactly the kind of thing a sample misses.
local L = require("dev.spec._ke_loader")

local ANCHORS = {
    "CENTER", "LEFT", "RIGHT", "TOP", "BOTTOM",
    "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT",
}

describe("KE:ResolveRepresentablePlacement", function()
    local KE
    setup(function() KE = L.loadGlobals() end)

    -- A fractional parent origin, deliberately. An integer one makes every
    -- offset land whole on its own and hides the entire problem this function
    -- exists for. The frame is an odd width for the same reason: half of it is
    -- fractional, so a LEFT or RIGHT anchor cannot come out whole by accident.
    local PARENT = { left = 100.25, bottom = 50.75, width = 800.5, height = 600.5 }
    local FRAME = { width = 37, height = 23 }

    local function place(centreX, centreY, from, to)
        return KE:ResolveRepresentablePlacement(centreX, centreY, from, to,
            FRAME.width, FRAME.height,
            PARENT.left, PARENT.bottom, PARENT.width, PARENT.height)
    end

    local function resolve(centreX, centreY, from, to)
        return KE:ResolveAnchorOffsets(centreX, centreY, from, to,
            FRAME.width, FRAME.height,
            PARENT.left, PARENT.bottom, PARENT.width, PARENT.height)
    end

    it("closes the round trip for all 81 anchor pairs", function()
        for _, from in ipairs(ANCHORS) do
            for _, to in ipairs(ANCHORS) do
                local offsetX, offsetY, centreX, centreY =
                    place(613.4, 421.9, from, to)

                local backX, backY = resolve(centreX, centreY, from, to)
                assert.equals(offsetX, backX,
                    "x round trip broke on " .. from .. " -> " .. to)
                assert.equals(offsetY, backY,
                    "y round trip broke on " .. from .. " -> " .. to)
            end
        end
    end)

    it("agrees with ResolveAnchorOffsets on the offsets themselves", function()
        -- The two functions share their anchor terms, so this pins that the
        -- sharing is real. If someone re-inlines one of them, this fails before
        -- the round-trip case does and says which direction went wrong.
        for _, from in ipairs(ANCHORS) do
            for _, to in ipairs(ANCHORS) do
                local offsetX, offsetY = place(613.4, 421.9, from, to)
                local wantX, wantY = resolve(613.4, 421.9, from, to)
                assert.equals(wantX, offsetX, "x differs on " .. from .. " -> " .. to)
                assert.equals(wantY, offsetY, "y differs on " .. from .. " -> " .. to)
            end
        end
    end)

    it("returns whole-number offsets", function()
        for _, from in ipairs(ANCHORS) do
            local offsetX, offsetY = place(613.4, 421.9, from, "CENTER")
            assert.equals(offsetX, math.floor(offsetX))
            assert.equals(offsetY, math.floor(offsetY))
        end
    end)

    -- The bound this function is allowed to claim. Half a UI unit per axis,
    -- from the rounding and nothing else. The pixel snap that follows at commit
    -- is not modelled here and is not covered by this number.
    it("moves the centre by at most half a unit on each axis", function()
        for _, from in ipairs(ANCHORS) do
            for _, to in ipairs(ANCHORS) do
                for step = 0, 9 do
                    local wantX = 613.0 + step * 0.1
                    local _, _, gotX, gotY = place(wantX, 421.9, from, to)
                    assert.is_true(math.abs(gotX - wantX) <= 0.5,
                        "x moved too far on " .. from .. " -> " .. to)
                    assert.is_true(math.abs(gotY - 421.9) <= 0.5,
                        "y moved too far on " .. from .. " -> " .. to)
                end
            end
        end
    end)

    -- An already-representable centre must survive untouched, or every drag
    -- that does not snap would still drift.
    it("leaves a centre that is already representable alone", function()
        local _, _, centreX, centreY = place(613.4, 421.9, "CENTER", "CENTER")
        local _, _, againX, againY = place(centreX, centreY, "CENTER", "CENTER")
        assert.equals(centreX, againX)
        assert.equals(centreY, againY)
    end)
end)

-- Concrete values, because the round trip above cannot see a wrong SHARED
-- term. Both functions read the same anchor helpers, so flipping one moves
-- them together and the round trip still closes -- mutation-tested, and it
-- survived. A property test is only as strong as the independence of the two
-- sides, and here they are deliberately not independent.
--
-- Parent left 100.25, bottom 50.75, size 800.5 x 600.5. Frame 37 x 23, both
-- odd so a half-extent is fractional. Centre 613.4, 421.9. Every number below
-- was produced by running the arithmetic, then checked against the branch it
-- exercises.
describe("KE:ResolveAnchorOffsets anchor terms", function()
    local KE
    setup(function() KE = L.loadGlobals() end)

    local function offsets(from, to)
        return KE:ResolveAnchorOffsets(613.4, 421.9, from, to, 37, 23,
            100.25, 50.75, 800.5, 600.5)
    end

    it("measures from the frame's own anchor point", function()
        local baseX, baseY = offsets("CENTER", "CENTER")
        assert.equals(113, baseX)
        assert.equals(71, baseY)

        -- LEFT moves the measured point half a width toward -x, so the stored
        -- offset shrinks by that much. RIGHT does the opposite.
        assert.equals(94, (offsets("LEFT", "CENTER")))
        assert.equals(131, (offsets("RIGHT", "CENTER")))

        local _, topY = offsets("TOP", "CENTER")
        local _, bottomY = offsets("BOTTOM", "CENTER")
        assert.equals(82, topY)
        assert.equals(59, bottomY)
    end)

    it("measures to the parent's anchor point", function()
        assert.equals(513, (offsets("CENTER", "LEFT")))
        assert.equals(-287, (offsets("CENTER", "RIGHT")))

        local _, topY = offsets("CENTER", "TOP")
        local _, bottomY = offsets("CENTER", "BOTTOM")
        assert.equals(-229, topY)
        assert.equals(371, bottomY)
    end)

    -- A corner moves both axes, and the rounding happens ONCE at the end. So
    -- the answer is not the sum of the separately rounded parts above: y here
    -- is 383, while composing the single-axis results gives 382. The x axis
    -- happens to agree either way, which is exactly why the y axis is the one
    -- worth pinning -- a version that rounded each term as it went would pass
    -- half of this case.
    it("applies both axes of a corner anchor, rounding once", function()
        local x, y = offsets("TOPLEFT", "BOTTOMRIGHT")
        assert.equals(-306, x)
        assert.equals(383, y)
    end)
end)
