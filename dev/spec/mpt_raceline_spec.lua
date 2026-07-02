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
end)
