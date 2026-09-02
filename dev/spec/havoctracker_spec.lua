local L = require("dev.spec._ke_loader")

-- The gate is this module's refusal rule: off-class, off-spec, or switched off,
-- it must build nothing at all. The observable is which sink EvaluateGate
-- reaches, so every case asserts on a call count rather than on frame state.
local DESTRUCTION, AFFLICTION = 267, 265

describe("HavocTracker gate", function()
    it("refuses for a non-Warlock even with the module enabled", function()
        local HT, rec = L.loadHavocTracker({ class = "MAGE", specIndex = 3, specID = DESTRUCTION })
        HT:EvaluateGate()
        assert.equals(0, rec.activate)
        assert.equals(1, rec.deactivate)
        -- The spec id deliberately MATCHES here, so a pass cannot come from the
        -- spec check standing in for the class check.
        assert.is_false(HT:IsWantedSpec())
    end)

    it("refuses for an Affliction Warlock", function()
        local HT, rec = L.loadHavocTracker({ specIndex = 1, specID = AFFLICTION })
        HT:EvaluateGate()
        assert.equals(0, rec.activate)
        assert.equals(1, rec.deactivate)
    end)

    it("refuses a Destruction Warlock while the module is switched off", function()
        local HT, rec = L.loadHavocTracker({
            specIndex = 3, specID = DESTRUCTION, db = { Enabled = false },
        })
        HT:EvaluateGate()
        assert.equals(0, rec.activate)
        assert.equals(1, rec.deactivate)
        -- The spec check itself still passes: this refusal came from the switch.
        assert.is_true(HT:IsWantedSpec())
    end)

    it("activates for an enabled Destruction Warlock", function()
        local HT, rec = L.loadHavocTracker({ specIndex = 3, specID = DESTRUCTION })
        HT:EvaluateGate()
        assert.equals(1, rec.activate)
        assert.equals(0, rec.deactivate)
    end)

    it("refuses without erroring when no specialization is chosen", function()
        -- GetSpecialization returns 0 on a character with no spec. Reading spec
        -- info at index 0 is what the guard exists to avoid.
        local HT, rec = L.loadHavocTracker({ specIndex = 0, specID = DESTRUCTION })
        HT:EvaluateGate()
        assert.equals(0, rec.activate)
        assert.equals(1, rec.deactivate)
        assert.is_false(HT:IsWantedSpec())
    end)
end)
