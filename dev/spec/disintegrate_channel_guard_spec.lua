-- Modules/ClassUtilities/DisintegrateTicks.lua: the channel-start guard. A
-- start whose channel info is missing or secret returns before any tick state
-- is touched. The secret row declares plain times secret, which the unguarded
-- code would use.
local L = require("dev.spec._ke_loader")

local DISINTEGRATE = 356995

describe("DisintegrateTicks channel start guard", function()
    it("leaves tick state alone when the channel info is missing or secret", function()
        local rows = {
            { name = "no channel info", info = function() return nil end,
              secret = function() return false end },
            { name = "secret times", info = function() return "Disintegrate", "", 0, 1000, 4000 end,
              secret = function(v) return v == 1000 or v == 4000 end },
        }
        for _, row in ipairs(rows) do
            local DT = L.loadDisintegrateTicks({ issecretvalue = row.secret, UnitChannelInfo = row.info })
            local ok, err = pcall(DT.OnEvent, DT, "UNIT_SPELLCAST_CHANNEL_START", "player", "cast-guid", DISINTEGRATE)
            assert.is_true(ok, row.name .. ": " .. tostring(err))
            assert.equals(0, DT.lastStart, row.name)
            assert.is_nil(DT.prevEndTime, row.name)
            assert.is_false(DT.channeling, row.name)
        end
    end)
end)
