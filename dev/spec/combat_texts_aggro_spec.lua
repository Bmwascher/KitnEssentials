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

-- Combat Texts with every aggro gate met. The threat reading and the clock
-- are set through the returned table; timers collect the scheduled calls.
local function loadHoldCase(isForever)
    local s = { timers = {}, now = 10, threat = 2, shown = 0 }
    local CM, KE = L.loadCombatTexts({
        C_Timer = { After = function(_, fn) s.timers[#s.timers + 1] = fn end },
        GetTime = function() return s.now end,
        UnitThreatSituation = function() return s.threat end,
    })
    KE.IS_FOREVER = isForever
    KE.IsSecretValue = function() return false end
    KE.InRealInstancedContent = function() return true end
    KE.IsPlayerTankSpec = function() return false end
    CM.db = { Enabled = true, AggroHoldTime = 0.5 }
    CM.inCombat = true
    CM.ShowPersistentMessage = function() s.shown = s.shown + 1 end
    return CM, s
end

describe("Combat Texts aggro hold", function()
    it("returns the time left before the line may show", function()
        local CM = L.loadCombatTexts()
        local rows = {
            { name = "hold 0", since = 10, now = 10, hold = 0, want = 0 },
            { name = "under the hold", since = 10, now = 10.25, hold = 0.5, want = 0.25 },
            { name = "hold reached", since = 10, now = 10.5, hold = 0.5, want = 0 },
            { name = "past the hold", since = 10, now = 12, hold = 0.5, want = 0 },
            { name = "no start yet", since = nil, now = 10, hold = 0.5, want = 0.5 },
            { name = "hold above 3 is clamped", since = 10, now = 10, hold = 9, want = 3 },
            { name = "missing hold", since = 10, now = 10, hold = nil, want = 0 },
        }
        for _, c in ipairs(rows) do
            assert.are.equal(c.want, CM.AggroHoldRemaining(c.since, c.now, c.hold), c.name)
        end
    end)

    it("shows the line only once aggro has lasted the hold, on both clients", function()
        for _, forever in ipairs({ false, true }) do
            local CM, s = loadHoldCase(forever)
            local client = forever and "Forever: " or "retail: "

            CM:CheckAggro()
            assert.are.equal(0, s.shown, client .. "nothing shows at the start of the hold")
            assert.are.equal(1, #s.timers, client .. "the hold arms one timer")
            CM:CheckAggro()
            assert.are.equal(1, #s.timers, client .. "a second passing event arms no second timer")

            s.threat, s.now = 1, 10.2
            CM:CheckAggro()
            s.now = 10.5
            s.timers[1]()
            assert.are.equal(0, s.shown, client .. "a blip shorter than the hold never shows")

            s.threat, s.now = 2, 11
            CM:CheckAggro()
            assert.are.equal(2, #s.timers, client .. "a new hold arms a new timer")
            s.now = 11.5
            s.timers[2]()
            assert.are.equal(1, s.shown, client .. "aggro held for the hold shows the line")
        end
    end)
end)
