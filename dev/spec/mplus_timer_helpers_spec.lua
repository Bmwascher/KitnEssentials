-- Pure-helper spec for MPT.FormatTime / ComputeThresholds.
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
end)

describe("MPT.ComputeThresholds", function()
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
