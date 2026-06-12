-- Pure-helper spec. Mirrors MPT.FormatTime / ComputeThresholds / ThresholdRemaining.
-- If these bodies drift from MythicPlusTimer.lua the spec is stale; keep in sync.
local floor, max, format = math.floor, math.max, string.format
local PLUS_TWO_RATIO, PLUS_THREE_RATIO = 0.8, 0.6

local MPT = {}
function MPT.FormatTime(sec, withMs)
    if not sec or sec < 0 then sec = 0 end
    local whole = floor(sec)
    local m, s = floor(whole / 60), floor(whole % 60)
    if withMs then
        local ms = floor(((sec - whole) * 1000) + 0.5)
        if ms >= 1000 then whole = whole + 1; m = floor(whole/60); s = floor(whole%60); ms = 0 end
        return format("%02d:%02d.%03d", m, s, ms)
    end
    return format("%02d:%02d", m, s)
end
function MPT.ComputeThresholds(maxTime, hasPeril)
    maxTime = maxTime or 0
    if maxTime <= 0 then return { plus1 = 0, plus2 = 0, plus3 = 0 } end
    local plus2, plus3 = maxTime * PLUS_TWO_RATIO, maxTime * PLUS_THREE_RATIO
    if hasPeril then
        local base = maxTime - 90
        if base > 0 then plus2 = base * PLUS_TWO_RATIO + 90; plus3 = base * PLUS_THREE_RATIO + 90 end
    end
    return { plus1 = maxTime, plus2 = plus2, plus3 = plus3 }
end
function MPT.ThresholdRemaining(elapsed, cutoff)
    return max(0, (cutoff or 0) - (elapsed or 0))
end

describe("MPT.FormatTime", function()
    it("formats whole seconds as MM:SS", function()
        assert.equals("00:00", MPT.FormatTime(0))
        assert.equals("01:05", MPT.FormatTime(65))
        assert.equals("33:20", MPT.FormatTime(2000))
    end)
    it("clamps nil/negative to 00:00", function()
        assert.equals("00:00", MPT.FormatTime(nil))
        assert.equals("00:00", MPT.FormatTime(-5))
    end)
    it("renders milliseconds when requested", function()
        assert.equals("00:01.500", MPT.FormatTime(1.5, true))
    end)
    it("rolls ms>=1000 up to the next second", function()
        assert.equals("00:01.000", MPT.FormatTime(0.9999, true))
    end)
end)

describe("MPT.ComputeThresholds", function()
    it("returns zeros for non-positive maxTime", function()
        local t = MPT.ComputeThresholds(0, false)
        assert.same({ plus1 = 0, plus2 = 0, plus3 = 0 }, t)
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
    it("returns the gap before the cutoff", function()
        assert.equals(120, MPT.ThresholdRemaining(480, 600))
    end)
    it("clamps to zero past the cutoff", function()
        assert.equals(0, MPT.ThresholdRemaining(700, 600))
    end)
    it("treats nil args as zero", function()
        assert.equals(0, MPT.ThresholdRemaining(nil, nil))
    end)
end)
