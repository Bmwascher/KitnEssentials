-- The kick pass scheduler, the range-fade transition rule and the Targeting
-- You arming rule, all pure rules on the module. The cooldown reads, the
-- colour curves, the alpha sinks, the stacked StatusBars and the pulse are
-- verified in game.
local L = require("dev.spec._ke_loader")

describe("DungeonCasts kick pass scheduler", function()
    it("reads once per interval", function()
        local DC = L.loadDungeonCasts()
        local cases = {
            { now = 10,    due = true,  name = "first tick" },
            { now = 10.1,  due = false, name = "inside the interval" },
            { now = 10.2,  due = true,  name = "past the interval" },
            { now = 10.25, due = false, name = "re-armed by the previous pass" },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.due, DC:KickPassDue(c.now), c.name)
        end
        -- The stored deadline itself is due: a `<=` in the guard would refuse
        -- it. Read back rather than recomputed, so no float equality.
        assert.is_true(DC:KickPassDue(DC._nextKickPass), "at the stored deadline")
    end)
end)

describe("DungeonCasts kick range fade", function()
    it("writes the bar alpha only when the range state changes", function()
        local inRange = true
        local DC = L.loadDungeonCasts({
            C_Spell = { IsSpellInRange = function() return inRange end },
        })
        DC.db = { Kick = { RangeFade = true, RangeAlpha = 0.45 } }
        DC.interruptId = 1
        -- No cachedDuration: both alphas are plain numbers, no curve.
        local bar = { unit = "nameplate1", writes = 0 }
        function bar:SetAlpha(alpha)
            self.alpha = alpha
            self.writes = self.writes + 1
        end
        local steps = {
            { inRange = true,  writes = 0, alpha = nil,  name = "in range from the start keeps the populate alpha" },
            { inRange = false, writes = 1, alpha = 0.45, name = "stepping out dims once" },
            { inRange = false, writes = 1, alpha = 0.45, name = "staying out writes nothing" },
            { inRange = true,  writes = 2, alpha = 1,    name = "stepping back in restores once" },
            { inRange = true,  writes = 2, alpha = 1,    name = "staying in writes nothing" },
        }
        for _, step in ipairs(steps) do
            inRange = step.inRange
            DC:UpdateKickRange(bar)
            assert.equals(step.writes, bar.writes, step.name)
            assert.equals(step.alpha, bar.alpha, step.name)
        end
    end)
end)
