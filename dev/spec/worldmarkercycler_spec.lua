-- ╔══════════════════════════════════════════════════════════╗
-- ║  dev/spec/worldmarkercycler_spec.lua                     ║
-- ║  World Marker Cycler: availability priming.              ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- The module computes ONE thing in ordinary Lua: which positions of the user's
-- marker order are believed free. Marker selection itself lives in a secure
-- snippet, which does not run headlessly and is verified in game.
--
-- The oracle LOADS the emitted snippet body instead of matching its text, so
-- these cases pin what the module meant rather than how it spelled it.

local L = require("dev.spec._ke_loader")

-- Runs an emitted "avail=newtable() avail[1]=true ..." body and returns the
-- table it built.
local function runAvailBody(body)
    local chunk = assert(loadstring(body))
    local env = { newtable = function() return {} end }
    setfenv(chunk, env)
    chunk()
    return env.avail
end

describe("WorldMarkerCycler availability priming", function()
    it("flags each ORDER POSITION by the marker sitting at it, not by marker id", function()
        -- Permuted deliberately: in the default { 1, 2, ... 8 } a position and
        -- the marker id at it coincide, so an identity list cannot tell the two
        -- indexings apart and would pass either way.
        local order = { 5, 3, 8, 1, 7, 2, 6, 4 }
        local active = { [1] = true, [3] = true, [6] = true }

        local WMC, _, executed = L.loadWorldMarkerCycler({
            IsRaidMarkerActive = function(id) return active[id] == true end,
        })
        WMC.db = { OrderList = order }

        WMC:PrimeAvailability()

        local avail = runAvailBody(executed[#executed].body)
        for pos, id in ipairs(order) do
            assert.equals(not active[id], avail[pos], "position " .. pos)
        end
    end)

    it("refuses to prime in combat, emitting nothing", function()
        local WMC, _, executed = L.loadWorldMarkerCycler({
            InCombatLockdown = function() return true end,
        })
        WMC.db = { OrderList = { 1, 2, 3 } }
        local before = #executed

        WMC:PrimeAvailability()

        assert.equals(before, #executed)
    end)
end)
