-- Kick tick placement in Modules/Combat/CastbarHelpers.lua: the choice between
-- hanging the kick bar off the cast's elapsed edge and covering the castbar.
-- The layout itself, and secret values inside it, are verified in game.
local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })

describe("Castbar kick tick placement", function()
    local H

    before_each(function()
        mock.install({ issecretvalue = function(v) return v == SECRET end })
        helpers.installAddonShim()
        local KE = helpers.loadModule("Modules/Combat/CastbarHelpers.lua", { curves = {} })
        H = KE.CastbarHelpers
    end)

    after_each(function()
        mock.reset()
    end)

    it("offsets only with an elapsed time and a readable, laid-out width", function()
        local cases = {
            { elapsed = 3,   width = 300,    offset = true,  name = "elapsed and a laid-out width" },
            { elapsed = nil, width = 300,    offset = false, name = "no elapsed time" },
            { elapsed = 3,   width = nil,    offset = false, name = "no width" },
            { elapsed = 3,   width = SECRET, offset = false, name = "secret width" },
            { elapsed = 3,   width = 1,      offset = false, name = "pre-layout width" },
            { elapsed = 3,   width = 2,      offset = true,  name = "width at the floor" },
        }
        for _, c in ipairs(cases) do
            assert.equals(c.offset, H.ShouldOffsetKickBar(c.elapsed, c.width), c.name)
        end
    end)
end)
