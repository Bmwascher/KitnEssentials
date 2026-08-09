-- Tier 1: invented branching arithmetic. The four directions and the modifier
-- multiplier are each a place a sign or a factor can be wrong, and every wrong
-- answer still moves the element -- just not where the user asked.
local L = require("dev.spec._ke_loader")

describe("KE:ArrowNudgeDelta", function()
    local KE
    setup(function() KE = L.loadGlobals() end)

    -- Y is positive upward, matching the d-pad handlers and the stored offsets.
    it("steps one unit per arrow", function()
        local cases = {
            UP    = { 0,  1 },
            DOWN  = { 0, -1 },
            LEFT  = { -1, 0 },
            RIGHT = { 1,  0 },
        }
        for key, want in pairs(cases) do
            local dx, dy = KE:ArrowNudgeDelta(key, false)
            assert.equals(want[1], dx)
            assert.equals(want[2], dy)
        end
    end)

    it("steps ten units with the modifier held", function()
        local cases = {
            UP    = { 0,  10 },
            DOWN  = { 0, -10 },
            LEFT  = { -10, 0 },
            RIGHT = { 10,  0 },
        }
        for key, want in pairs(cases) do
            local dx, dy = KE:ArrowNudgeDelta(key, true)
            assert.equals(want[1], dx)
            assert.equals(want[2], dy)
        end
    end)

    -- The key handler branches on this being nil. Returning 0, 0 would make
    -- every keypress look like an arrow that happened not to move.
    it("returns nil for anything that is not an arrow", function()
        assert.is_nil(KE:ArrowNudgeDelta("ESCAPE", false))
        assert.is_nil(KE:ArrowNudgeDelta("A", true))
        assert.is_nil(KE:ArrowNudgeDelta("", false))
        assert.is_nil(KE:ArrowNudgeDelta(nil, false))
    end)
end)
