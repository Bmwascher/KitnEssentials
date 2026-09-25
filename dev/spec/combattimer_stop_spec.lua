-- Modules/Combat/CombatTimer.lua -- the stop and hold rules, lifted into the
-- pure CT.Transition(running, inEncounter, event, inCombat, encounterLive,
-- success). No Blizzard fake: the rules take their readings as arguments.
-- Event timing, the paint ticker and the frames are verified in game.
local L = require("dev.spec._ke_loader")

describe("combat timer stop rules", function()
    local CT

    before_each(function()
        CT = L.loadCombatTimer()
    end)

    local function check(rows)
        for _, r in ipairs(rows) do
            local running, mark, action = CT.Transition(r.running, r.mark, r.event, r.inCombat, r.live, r.success)
            assert.equals(r.expRunning, running, r.name)
            assert.equals(r.expMark, mark, r.name)
            assert.equals(r.expAction, action, r.name)
        end
    end

    it("stops when the player leaves combat outside an encounter, on the event or on the tick that finds it missed", function()
        check({
            { name = "PLAYER_REGEN_ENABLED", event = "PLAYER_REGEN_ENABLED", running = true, mark = false,
                inCombat = false, live = false, expRunning = false, expMark = false, expAction = "stop" },
            { name = "a TICK after a missed PLAYER_REGEN_ENABLED", event = "TICK", running = true, mark = false,
                inCombat = false, live = false, expRunning = false, expMark = false, expAction = "stop" },
        })
    end)

    it("stops at ENCOUNTER_END on a kill in or out of combat, and on a non-kill out of combat", function()
        check({
            { name = "a kill in combat", event = "ENCOUNTER_END", success = 1, running = true, mark = true,
                inCombat = true, live = false, expRunning = false, expMark = false, expAction = "stop" },
            { name = "a kill out of combat", event = "ENCOUNTER_END", success = 1, running = true, mark = true,
                inCombat = false, live = true, expRunning = false, expMark = false, expAction = "stop" },
            { name = "a reset out of combat", event = "ENCOUNTER_END", success = 0, running = true, mark = true,
                inCombat = false, live = true, expRunning = false, expMark = false, expAction = "stop" },
        })
    end)

    it("stops once out of combat when a reset left the mark set with no encounter in progress", function()
        check({
            { name = "TICK", event = "TICK", running = true, mark = true,
                inCombat = false, live = false, expRunning = false, expMark = false, expAction = "stop" },
            { name = "PLAYER_REGEN_ENABLED", event = "PLAYER_REGEN_ENABLED", running = true, mark = true,
                inCombat = false, live = false, expRunning = false, expMark = false, expAction = "stop" },
        })
    end)

    it("resets on a loading screen out of combat, and keeps or starts a span on one in combat", function()
        check({
            { name = "out of combat, running", event = "PLAYER_ENTERING_WORLD", running = true, mark = true,
                inCombat = false, live = false, expRunning = false, expMark = false, expAction = "reset" },
            { name = "in combat, running", event = "PLAYER_ENTERING_WORLD", running = true, mark = false,
                inCombat = true, live = false, expRunning = true, expMark = false },
            { name = "in combat, not running", event = "PLAYER_ENTERING_WORLD", running = false, mark = false,
                inCombat = true, live = false, expRunning = true, expMark = false, expAction = "start" },
        })
    end)

    it("sets the mark from a live encounter at any loading screen, so a later drop from combat holds", function()
        -- The TICK takes the mark the in-combat loading screen returned: a span
        -- rebuilt by a reload mid-boss, then held through a death.
        local running, mark, action = CT.Transition(false, false, "PLAYER_ENTERING_WORLD", true, true)
        assert.is_true(running)
        assert.is_true(mark)
        assert.equals("start", action)
        running, mark, action = CT.Transition(running, mark, "TICK", false, true)
        assert.is_true(running, "TICK after the reload")
        assert.is_true(mark, "TICK after the reload")
        assert.is_nil(action, "TICK after the reload")
        check({
            { name = "out of combat, not running (a reload while dead)", event = "PLAYER_ENTERING_WORLD",
                running = false, mark = false, inCombat = false, live = true,
                expRunning = false, expMark = true },
        })
    end)

    it("holds when the player drops combat mid-encounter, and a re-entry continues the same span", function()
        check({
            { name = "PLAYER_REGEN_ENABLED", event = "PLAYER_REGEN_ENABLED", running = true, mark = true,
                inCombat = false, live = true, expRunning = true, expMark = true },
            { name = "TICK", event = "TICK", running = true, mark = true,
                inCombat = false, live = true, expRunning = true, expMark = true },
            { name = "PLAYER_REGEN_DISABLED while held", event = "PLAYER_REGEN_DISABLED", running = true, mark = true,
                inCombat = true, live = false, expRunning = true, expMark = true },
        })
    end)

    it("keeps running through a non-kill ENCOUNTER_END while the player is in combat", function()
        check({
            { name = "a reset in combat", event = "ENCOUNTER_END", success = 0, running = true, mark = true,
                inCombat = true, live = false, expRunning = true, expMark = false },
        })
    end)

    it("restarts a running span at ENCOUNTER_START and only sets the mark on a stopped one", function()
        check({
            { name = "running", event = "ENCOUNTER_START", running = true, mark = false,
                inCombat = true, live = false, expRunning = true, expMark = true, expAction = "restart" },
            { name = "not running", event = "ENCOUNTER_START", running = false, mark = false,
                inCombat = false, live = false, expRunning = false, expMark = true },
        })
    end)
end)
