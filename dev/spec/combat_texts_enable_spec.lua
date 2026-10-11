-- A disable must stop the delayed calls Combat Texts schedules at enable. The
-- real OnDisable runs against a captured timer; the Ace methods the addon
-- shim's module table lacks are stubbed.
local L = require("dev.spec._ke_loader")

describe("Combat Texts enable timers", function()
    it("a disable before the delayed call fires stops it", function()
        local rows = {
            { name = "no disable", steps = { "schedule" }, want = 1 },
            { name = "disable", steps = { "schedule", "disable" }, want = 0 },
            { name = "disable, then a new schedule", steps = { "schedule", "disable", "schedule" }, want = 1 },
        }
        for _, row in ipairs(rows) do
            local timers, ran = {}, 0
            local CM = L.loadCombatTexts({
                C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end },
            })
            CM.IsEnabled = function() return false end
            CM.SendMessage = function() end
            CM.UnregisterAllEvents = function() end
            for _, step in ipairs(row.steps) do
                if step == "schedule" then
                    CM:DelayWhileEnabled(0.5, function() ran = ran + 1 end)
                else
                    CM:OnDisable()
                end
            end
            for _, fire in ipairs(timers) do fire() end
            assert.equals(row.want, ran, row.name)
        end
    end)
end)
