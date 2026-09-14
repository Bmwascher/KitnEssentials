-- End-of-cast decisions in Modules/Combat/CastbarHelpers.lua, lifted to two
-- pure predicates so the castbar itself is never faked. Colours, the hold
-- timer, the frame and the GUI are verified in game.
local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

describe("Castbar end-of-cast decisions", function()
    local H

    before_each(function()
        mock.install()
        helpers.installAddonShim()
        local KE = helpers.loadModule("Modules/Combat/CastbarHelpers.lua", { curves = {} })
        H = KE.CastbarHelpers
    end)

    it("holds the bar only for an enabled hold on an interrupted cast", function()
        local cases = {
            { settings = nil,                 interrupted = true,  hold = false, name = "no settings" },
            { settings = { Enabled = false }, interrupted = true,  hold = false, name = "hold disabled" },
            { settings = { Enabled = true },  interrupted = false, hold = false, name = "finished or failed cast" },
            { settings = { Enabled = true },  interrupted = true,  hold = true,  name = "interrupted cast" },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.hold, H.ShouldHoldOnEnd(c.settings, c.interrupted), c.name)
        end
    end)

    it("re-syncs a stale end onto a live cast, except after an interrupt or a channel stop", function()
        local cases = {
            { channelStop = false, interrupted = false, live = true,  resync = true,  name = "stale cast stop" },
            { channelStop = false, interrupted = false, live = false, resync = false, name = "nothing casting" },
            { channelStop = false, interrupted = true,  live = true,  resync = false, name = "interrupt keeps its overlay" },
            { channelStop = true,  interrupted = false, live = true,  resync = false, name = "channel stop always ends" },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.resync, H.ShouldResyncOnEnd(c.channelStop, c.interrupted, c.live), c.name)
        end
    end)
end)
