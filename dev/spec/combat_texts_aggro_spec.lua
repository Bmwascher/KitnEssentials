-- The aggro line's show rule and its sound re-arm guard. The combat, spec,
-- instance and threat reads, and the real sound gap, stay an in-game check.
local L = require("dev.spec._ke_loader")

describe("Combat Texts aggro rule", function()
    it("shows only in combat, off a tank spec, inside the gate, on a plain status of 2 or more", function()
        local CM = L.loadCombatTexts()
        local rows = {
            { name = "status 2, every gate met", db = {},
              inCombat = true, isTank = false, inInstance = true, threat = 2, secret = false, want = true },
            { name = "status 1", db = {},
              inCombat = true, isTank = false, inInstance = true, threat = 1, secret = false, want = false },
            { name = "no reading", db = {},
              inCombat = true, isTank = false, inInstance = true, threat = nil, secret = false, want = false },
            { name = "secret reading", db = {},
              inCombat = true, isTank = false, inInstance = true, threat = 2, secret = true, want = false },
            { name = "out of combat", db = {},
              inCombat = false, isTank = false, inInstance = true, threat = 2, secret = false, want = false },
            { name = "tank spec", db = {},
              inCombat = true, isTank = true, inInstance = true, threat = 2, secret = false, want = false },
            { name = "instances only, outside", db = { AggroInstanceOnly = true },
              inCombat = true, isTank = false, inInstance = false, threat = 2, secret = false, want = false },
            { name = "instances only off, outside", db = { AggroInstanceOnly = false },
              inCombat = true, isTank = false, inInstance = false, threat = 2, secret = false, want = true },
            { name = "line disabled", db = { AggroEnabled = false },
              inCombat = true, isTank = false, inInstance = true, threat = 2, secret = false, want = false },
        }
        for _, c in ipairs(rows) do
            assert.are.equal(c.want,
                CM.ShouldShowAggro(c.db, c.inCombat, c.isTank, c.inInstance, c.threat, c.secret), c.name)
        end
    end)
end)

describe("Combat Texts aggro sound", function()
    it("plays once, refuses while blocked without scheduling, and plays again after the re-arm", function()
        local plays, timers = {}, {}
        local CM, KE = L.loadCombatTexts({
            C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end },
            PlaySoundFile = function(path) plays[#plays + 1] = path end,
        })
        KE.LSM = { Fetch = function(_, _, name) return "sound/" .. name end }
        CM.db = { AggroSoundEnabled = true, AggroSoundFile = "Alarm", AggroSoundChannel = "SFX" }

        CM:PlayAggroSound()
        assert.are.equal(1, #plays, "first attempt plays")
        assert.are.equal(1, #timers, "first attempt schedules the re-arm")

        CM:PlayAggroSound()
        assert.are.equal(1, #plays, "blocked attempt does not play")
        assert.are.equal(1, #timers, "blocked attempt does not schedule")

        timers[1]()
        CM:PlayAggroSound()
        assert.are.equal(2, #plays, "re-armed attempt plays")
        assert.are.equal(2, #timers, "re-armed attempt schedules again")
    end)
end)
