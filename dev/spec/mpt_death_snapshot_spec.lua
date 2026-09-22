-- Tier 2: Modules/Dungeons/MythicPlusTimer/MythicPlusTimer.lua, the alive
-- snapshot behind OnDeathCountUpdated. The snapshot and both scans are
-- file-local, so the case drives the public entry point and reads the death
-- log. The fake is one unit -> { guid, dead } table, because the guard under
-- test is which of two API returns identifies a member, and only a scan over
-- unit tokens exercises it.
local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

describe("MPT death snapshot identity", function()
    local MPT, units, deathCount

    before_each(function()
        mock.install({ C_Timer = { After = function() end } })
        local modules = helpers.installAddonShim()
        -- Captured at file scope, so it must exist before the load.
        _G.C_ChallengeMode = {
            GetDeathCount = function() return deathCount, 0 end,
        }
        helpers.loadModule("Modules/Dungeons/MythicPlusTimer/MythicPlusTimer.lua",
            { Print = function() end, db = { global = {}, profile = {} } })
        MPT = modules["MythicPlusTimer"]
        assert(MPT and MPT.OnDeathCountUpdated, "real MythicPlusTimer.lua did not load")
        MPT.NotifyRefresh = function() end
        MPT.db = {}

        -- A two-member party: the scan maps the last index to "player".
        units = {
            party1 = { guid = "Player-1-A", dead = false },
            player = { guid = "Player-1-B", dead = false },
        }
        deathCount = 0
        _G.GetNumGroupMembers = function() return 2 end
        _G.IsInRaid = function() return false end
        _G.UnitGUID = function(unit) return units[unit].guid end
        _G.UnitName = function() return "Kitn" end
        _G.UnitClass = function() return "Mage", "MAGE" end
        _G.UnitIsDeadOrGhost = function(unit) return units[unit].dead end
    end)

    after_each(function()
        _G.C_ChallengeMode = nil
        mock.reset()
    end)

    it("records one death per member when two members share a short name", function()
        MPT:OnDeathCountUpdated()   -- count 0: seeds the alive snapshot
        units.party1.dead = true
        units.player.dead = true
        deathCount = 2
        MPT:OnDeathCountUpdated()
        assert.equals(2, #MPT.run.deathLog)
    end)
end)
