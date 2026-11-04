-- The Range Checker's update period: the player's Update Throttle, never
-- below the floor, 0.1 s when unset. Starting, canceling and restarting the
-- ticker are timer behavior and stay an in-game check.
local L = require("dev.spec._ke_loader")

describe("RangeChecker tick period", function()
    it("uses the throttle, floored at 0.05 s, defaulting to 0.1 s", function()
        local RC = L.loadRangeChecker()
        local cases = {
            { throttle = nil,  want = 0.1 },
            { throttle = 0,    want = 0.05 },
            { throttle = 0.05, want = 0.05 },
            { throttle = 0.1,  want = 0.1 },
            { throttle = 1,    want = 1 },
        }
        for _, c in ipairs(cases) do
            assert.are.equal(c.want, RC._TickPeriod(c.throttle), tostring(c.throttle))
        end
    end)
end)
