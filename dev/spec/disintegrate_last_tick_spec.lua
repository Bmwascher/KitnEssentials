-- Tier: logic KE invented for the last-tick highlight. Which index is last
-- decides which pooled texture gets the highlight colour, and a wrong answer
-- only shows as a mark in the wrong colour. The tick-time arithmetic these
-- cases pass through is moved code, covered by the diff, not by this file.

local loader = require("dev.spec._ke_loader")
local mock = require("dev.spec._wow_mock")

describe("DisintegrateTicks last tick", function()
    local DT

    before_each(function()
        DT = loader.loadDisintegrateTicks()
    end)

    after_each(function()
        mock.reset()
    end)

    -- A fresh cast lasts three intervals with 4 ticks and four with 5, at any
    -- haste, so the tick at the channel's end is hidden and the one before it
    -- is last.
    it("fresh cast: the last shown tick is the one before the channel end", function()
        local rows = {
            { maxTicks = 4, duration = 3.0, interval = 1.0, expected = 2 },
            { maxTicks = 5, duration = 3.0, interval = 0.75, expected = 3 },
        }
        for _, row in ipairs(rows) do
            assert.equals(row.expected,
                DT.LastShownTick(row.maxTicks, row.duration, row.interval, false, 0))
        end
    end)

    it("chained cast: the chaining branch shows every tick but the final one", function()
        local rows = {
            { maxTicks = 4, expected = 3 },
            { maxTicks = 5, expected = 4 },
        }
        for _, row in ipairs(rows) do
            assert.equals(row.expected,
                DT.LastShownTick(row.maxTicks, 3.0, 1.0, true, 0.4))
        end
    end)

    it("the colour choice follows the toggle", function()
        local tickColor = { 0.1, 0.2, 0.3, 0.4 }
        local lastTickColor = { 0.5, 0.6, 0.7, 0.8 }
        local rows = {
            { enabled = true, index = 3, expected = lastTickColor, why = "on, last tick" },
            { enabled = false, index = 3, expected = tickColor, why = "off, last tick" },
            { enabled = true, index = 2, expected = tickColor, why = "on, another tick" },
        }
        for _, row in ipairs(rows) do
            local db = {
                LastTickEnabled = row.enabled,
                TickColor = tickColor,
                LastTickColor = lastTickColor,
            }
            assert.equals(row.expected, (DT.TickColorFor(row.index, 3, db)), row.why)
        end
    end)
end)
