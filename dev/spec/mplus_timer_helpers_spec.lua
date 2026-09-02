-- Pure-helper spec for MPT.FormatTime / ComputeThresholds / ThresholdRemaining.
-- Loads the REAL Modules/Dungeons/MythicPlusTimer/MythicPlusTimer.lua headlessly
-- (no mirrored bodies) so the assertions run against the live implementation.
-- If the file ever gains load-time C_* calls / event registrations this setup
-- breaks loudly — that is the intended tripwire; fix the load path, don't re-mirror.
local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

local MPT
setup(function()
    mock.install()   -- CreateFrame (tickerFrame), wipe
    local modules = helpers.installAddonShim()
    helpers.loadModule("Modules/Dungeons/MythicPlusTimer/MythicPlusTimer.lua")
    MPT = modules["MythicPlusTimer"]
    assert(MPT and MPT.FormatTime, "real MythicPlusTimer.lua did not expose FormatTime")
end)

describe("MPT.FormatTime", function()
    it("formats whole seconds as MM:SS", function()
        assert.equals("00:00", MPT.FormatTime(0))
        assert.equals("01:05", MPT.FormatTime(65))
        assert.equals("33:20", MPT.FormatTime(2000))
    end)
    it("rolls ms>=1000 up to the next second", function()
        assert.equals("00:01.000", MPT.FormatTime(0.9999, true))
    end)
    it("clamps nil and negative input to 00:00", function()
        assert.equals("00:00", MPT.FormatTime(nil))
        assert.equals("00:00", MPT.FormatTime(-5))
    end)
end)

describe("MPT.ComputeThresholds", function()
    it("returns zeros for a nil or non-positive maxTime", function()
        assert.same({ plus1 = 0, plus2 = 0, plus3 = 0 }, MPT.ComputeThresholds(0, false))
        assert.same({ plus1 = 0, plus2 = 0, plus3 = 0 }, MPT.ComputeThresholds(nil, true))
    end)
    it("computes 80/60 percent cutoffs without peril", function()
        local t = MPT.ComputeThresholds(1000, false)
        assert.equals(1000, t.plus1)
        assert.equals(800, t.plus2)
        assert.equals(600, t.plus3)
    end)
    it("recomputes on (maxTime-90) when peril is present", function()
        -- base = 1000-90 = 910; plus2 = 910*0.8+90 = 818; plus3 = 910*0.6+90 = 636
        local t = MPT.ComputeThresholds(1000, true)
        assert.equals(1000, t.plus1)
        assert.equals(818, t.plus2)
        assert.equals(636, t.plus3)
    end)
end)

describe("MPT.ThresholdRemaining", function()
    it("returns the gap before the cutoff and never goes negative, nil args reading as zero", function()
        assert.equals(120, MPT.ThresholdRemaining(480, 600))
        assert.equals(0, MPT.ThresholdRemaining(700, 600))
        assert.equals(0, MPT.ThresholdRemaining(nil, nil))
    end)
end)
