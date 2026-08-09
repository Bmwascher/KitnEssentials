-- Tier 2: position offsets are whole numbers. The GUI position sliders step by
-- 1, so a fractional stored offset is a value the slider cannot represent.
-- Halves round toward positive infinity, so -80.5 becomes -80; that asymmetry
-- is deliberate and pinned here.
local L = require("dev.spec._ke_loader")

describe("KE:RoundOffset", function()
    local KE

    before_each(function() KE = L.loadGlobals() end)

    it("leaves a whole number alone", function()
        assert.equals(240, KE:RoundOffset(240))
        assert.equals(-80, KE:RoundOffset(-80))
        assert.equals(0, KE:RoundOffset(0))
    end)

    it("rounds a positive fraction to nearest", function()
        assert.equals(240, KE:RoundOffset(240.4))
        assert.equals(241, KE:RoundOffset(240.6))
    end)

    it("rounds a negative fraction to nearest", function()
        assert.equals(-80, KE:RoundOffset(-80.4))
        assert.equals(-81, KE:RoundOffset(-80.6))
    end)

    it("rounds a positive half up", function()
        assert.equals(241, KE:RoundOffset(240.5))
    end)

    it("rounds a negative half toward zero, deliberately", function()
        assert.equals(-80, KE:RoundOffset(-80.5))
    end)

    it("returns 0 for a nil or non-numeric value", function()
        assert.equals(0, KE:RoundOffset(nil))
        assert.equals(0, KE:RoundOffset("240"))
        assert.equals(0, KE:RoundOffset({}))
    end)
end)
