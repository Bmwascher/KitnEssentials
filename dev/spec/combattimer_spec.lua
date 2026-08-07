-- Modules/Combat/CombatTimer.lua -- the stop rule only. The frames, the
-- OnUpdate ticker and the event wiring are verified in game; what is tested
-- here is the one rule a later edit breaks silently, and the one that is
-- awkward to smoke: you would have to stage a boss fight and deliberately
-- drop combat mid-pull to see it.
local L = require("dev.spec._ke_loader")

describe("combat timer stop rule", function()
    local CT

    before_each(function()
        CT = L.loadCombatTimer()
    end)

    local function shouldStop(isEncounterTimer, isEncounterEvent, encounterInProgress)
        return CT:ShouldStopTimer(isEncounterTimer, isEncounterEvent, encounterInProgress)
    end

    it("stops a plain combat timer when combat ends", function()
        assert.is_true(shouldStop(false, false, false))
    end)

    it("stops an encounter timer when the encounter ends", function()
        assert.is_true(shouldStop(true, true, true))
    end)

    it("keeps an encounter timer running when combat merely drops", function()
        -- The whole point: a boss fight sheds and regains combat freely, and
        -- restarting the clock on each one makes the readout useless.
        assert.is_falsy(shouldStop(true, false, true))
    end)

    it("stops an encounter timer on a combat end once the encounter is over", function()
        -- Wipe or release, where an ENCOUNTER_END may never reach us.
        assert.is_true(shouldStop(true, false, false))
    end)

    it("keeps a plain combat timer running when an encounter ends", function()
        -- Trash pulled during a boss's death does not end the trash timer.
        assert.is_falsy(shouldStop(false, true, false))
    end)
end)
