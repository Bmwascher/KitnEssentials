-- Pure unit test for MPT.ResolveRaceLine (the LINES-mode race line brain).
-- Loads the REAL core file headlessly: the wow mock supplies CreateFrame /
-- wipe / C_Timer for the file's parse-time needs; nothing auto-runs (Ace
-- lifecycle is never invoked here).
local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

local MPT
setup(function()
    mock.install()
    local modules = helpers.installAddonShim()
    helpers.loadModule("Modules/Dungeons/MythicPlusTimer/MythicPlusTimer.lua")
    MPT = modules["MythicPlusTimer"]
    assert(MPT and MPT.ResolveRaceLine, "core file did not expose ResolveRaceLine")
end)

describe("MPT.ResolveRaceLine", function()
    -- 30:00 key: +3 at 18:00, +2 at 24:00.
    local th = { plus1 = 1800, plus2 = 1440, plus3 = 1080 }

    it("races +3 from the countdown (elapsed 0)", function()
        local tier, cutoff, value, state = MPT.ResolveRaceLine(0, th, false)
        assert.are.equal(3, tier)
        assert.are.equal(1080, cutoff)
        assert.are.equal(1080, value)
        assert.are.equal("RACING", state)
    end)

    it("races +3 up to and including the cutoff second", function()
        local tier, _, value, state = MPT.ResolveRaceLine(1080, th, false)
        assert.are.equal(3, tier)
        assert.are.equal(0, value)
        assert.are.equal("RACING", state)
    end)

    it("collapses to +2 once +3 is passed", function()
        local tier, cutoff, value, state = MPT.ResolveRaceLine(1081, th, false)
        assert.are.equal(2, tier)
        assert.are.equal(1440, cutoff)
        assert.are.equal(359, value)
        assert.are.equal("RACING", state)
    end)

    it("counts the overshoot once +2 is passed", function()
        local tier, cutoff, value, state = MPT.ResolveRaceLine(1483, th, false)
        assert.are.equal(2, tier)
        assert.are.equal(1440, cutoff)
        assert.are.equal(43, value)
        assert.are.equal("OVER", state)
    end)

    it("locks green on a +3 finish", function()
        local tier, _, value, state = MPT.ResolveRaceLine(1000, th, true)
        assert.are.equal(3, tier)
        assert.are.equal(80, value)
        assert.are.equal("LOCKED_MADE", state)
    end)

    it("locks green on a +2 finish (never re-shows +3)", function()
        local tier, cutoff, value, state = MPT.ResolveRaceLine(1368, th, true)
        assert.are.equal(2, tier)
        assert.are.equal(1440, cutoff)
        assert.are.equal(72, value)
        assert.are.equal("LOCKED_MADE", state)
    end)

    it("locks red with the miss amount on a +1 finish", function()
        local tier, cutoff, value, state = MPT.ResolveRaceLine(1537, th, true)
        assert.are.equal(2, tier)
        assert.are.equal(1440, cutoff)
        assert.are.equal(97, value)
        assert.are.equal("LOCKED_MISSED", state)
    end)

    it("locks red on a depleted finish (overshoot vs +2, big timer owns +1)", function()
        local tier, _, value, state = MPT.ResolveRaceLine(1900, th, true)
        assert.are.equal(2, tier)
        assert.are.equal(460, value)
        assert.are.equal("LOCKED_MISSED", state)
    end)

    it("returns nil while thresholds are unusable (level-0 repair window)", function()
        assert.is_nil(MPT.ResolveRaceLine(10, { plus1 = 0, plus2 = 0, plus3 = 0 }, false))
        assert.is_nil(MPT.ResolveRaceLine(10, nil, false))
    end)

    it("tolerates a nil elapsed (treated as 0)", function()
        local tier, _, value = MPT.ResolveRaceLine(nil, th, false)
        assert.are.equal(3, tier)
        assert.are.equal(1080, value)
    end)

    it("races +1 after +2 falls when plusOneRace is on", function()
        local tier, cutoff, value, state = MPT.ResolveRaceLine(1500, th, false, true)
        assert.are.equal(1, tier)
        assert.are.equal(1800, cutoff)
        assert.are.equal(300, value)
        assert.are.equal("RACING", state)
    end)

    it("counts the +1 overshoot once the deadline passes (plusOneRace)", function()
        local tier, cutoff, value, state = MPT.ResolveRaceLine(1850, th, false, true)
        assert.are.equal(1, tier)
        assert.are.equal(1800, cutoff)
        assert.are.equal(50, value)
        assert.are.equal("OVER", state)
    end)

    it("locks back to the +2 delta at completion even with plusOneRace on", function()
        local tier, cutoff, value, state = MPT.ResolveRaceLine(1537, th, true, true)
        assert.are.equal(2, tier)
        assert.are.equal(1440, cutoff)
        assert.are.equal(97, value)
        assert.are.equal("LOCKED_MISSED", state)
    end)

    it("ignores plusOneRace while +3/+2 are still live", function()
        local tier = MPT.ResolveRaceLine(1000, th, false, true)
        assert.are.equal(3, tier)
        local tier2 = MPT.ResolveRaceLine(1400, th, false, true)
        assert.are.equal(2, tier2)
    end)

    it("falls back to the +2 overshoot when plus1 is unusable", function()
        local broken = { plus1 = 0, plus2 = 1440, plus3 = 1080 }
        local tier, cutoff, value, state = MPT.ResolveRaceLine(1500, broken, false, true)
        assert.are.equal(2, tier)
        assert.are.equal(1440, cutoff)
        assert.are.equal(60, value)
        assert.are.equal("OVER", state)
    end)
end)

describe("MPT.BuildTimerTemplate", function()
    it("reserves the millisecond form only when asked (live toggle or completion)", function()
        assert.are.equal("88:88.888/88:88", (MPT.BuildTimerTemplate("ELAPSED_TOTAL", true)))
        assert.are.equal("88:88/88:88",     (MPT.BuildTimerTemplate("ELAPSED_TOTAL", false)))
        assert.are.equal("88:88.888",       (MPT.BuildTimerTemplate("ELAPSED", true)))
        assert.are.equal("88:88",           (MPT.BuildTimerTemplate("ELAPSED", false)))
        assert.are.equal("88:88.888 (88:88 / 88:88)", (MPT.BuildTimerTemplate("ELAPSED_DETAIL", true)))
        assert.are.equal("88:88 (88:88 / 88:88)",     (MPT.BuildTimerTemplate("ELAPSED_DETAIL", false)))
    end)

    it("never reserves ms for remaining modes (they never render it)", function()
        assert.are.equal("88:88",       (MPT.BuildTimerTemplate("REMAINING", true)))
        assert.are.equal("88:88/88:88", (MPT.BuildTimerTemplate("REMAINING_TOTAL", true)))
    end)

    it("reports the anchor-gap count for split-FontString rows", function()
        local _, g1 = MPT.BuildTimerTemplate("ELAPSED_TOTAL", true)
        local _, g2 = MPT.BuildTimerTemplate("REMAINING_TOTAL", false)
        local _, g3 = MPT.BuildTimerTemplate("ELAPSED", true)
        local _, g4 = MPT.BuildTimerTemplate("ELAPSED_DETAIL", true)
        local _, g5 = MPT.BuildTimerTemplate("REMAINING", false)
        assert.are.equal(2, g1)
        assert.are.equal(2, g2)
        assert.are.equal(0, g3)
        assert.are.equal(0, g4)
        assert.are.equal(0, g5)
    end)

    it("falls back to the default format for nil/unknown modes", function()
        assert.are.equal("88:88.888/88:88", (MPT.BuildTimerTemplate(nil, true)))
        assert.are.equal("88:88/88:88",     (MPT.BuildTimerTemplate("BOGUS", false)))
    end)
end)

describe("MPT.LiveMsElapsed", function()
    -- Glues GetTimePreciseSec to the authoritative whole-second clock:
    -- smooth pass-through between corrections, forward snap on death
    -- penalties, re-anchor when the precise clock runs away.
    it("initializes the anchor from the authoritative elapsed", function()
        local p, base = MPT.LiveMsElapsed(1000.25, nil, 926)
        assert.are.equal(926, p)
        assert.are.equal(1000.25 - 926, base)
    end)

    it("passes the precise clock through between corrections", function()
        local base = 1000.25 - 926
        local p, nb = MPT.LiveMsElapsed(1000.75, base, 926)
        assert.are.equal(926.5, p)
        assert.are.equal(base, nb)
    end)

    it("tolerates a late authoritative tick without stuttering", function()
        -- precise reaches elapsed+1.3 because the 1 Hz tick fired late:
        -- NOT a correction — snapping here would reset the fraction every
        -- second and the ms display would stutter.
        local base = 1000.25 - 926
        local p, nb = MPT.LiveMsElapsed(1001.55, base, 926)
        assert.are.equal(927.3, p)
        assert.are.equal(base, nb)
    end)

    it("snaps forward when a death penalty jumps the authoritative clock", function()
        -- +15s penalty: authoritative elapsed leaps past the precise clock.
        local base = 1000.25 - 926
        local p, nb = MPT.LiveMsElapsed(1000.75, base, 941)
        assert.are.equal(941, p)
        assert.are.equal(1000.75 - 941, nb)
    end)

    it("re-anchors when the precise clock runs too far ahead (reload restore)", function()
        local base = 1000.25 - 926
        local p, nb = MPT.LiveMsElapsed(1002.00, base, 926)  -- precise 927.75 >= 926 + 1.6
        assert.are.equal(926, p)
        assert.are.equal(1002.00 - 926, nb)
    end)
end)
