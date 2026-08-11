-- Tier 1: a refusal rule with four ways to say no, and every wrong answer is
-- invisible. A measurement that should have been refused widens the box around
-- nothing; one that should have been allowed leaves the box inside its own
-- text. Neither gets filed as a bug.
--
-- The secret branch is deliberately absent. A headless secret is a plain table,
-- so a spec for it would prove the guard is CALLED and could never prove the
-- comparison below it is unreachable, which is the only thing that matters.
-- That one is settled by the API reference and in game.
local L = require("dev.spec._ke_loader")

describe("KE:MeasureFontString", function()
    local KE
    setup(function() KE = L.loadGlobals() end)

    local function fs(w, h)
        return {
            GetStringWidth = function() return w end,
            GetStringHeight = function() return h end,
        }
    end

    it("measures a string that answers with two positive numbers", function()
        local w, h = KE:MeasureFontString(fs(9, 16))
        assert.equals(9, w)
        assert.equals(16, h)
    end)

    it("refuses nothing at all", function()
        assert.is_nil(KE:MeasureFontString(nil))
    end)

    -- The overlay callback runs against whatever the module hands it, and a
    -- module that has not built its buttons yet hands over a plain table.
    it("refuses an object that is not a font string", function()
        assert.is_nil(KE:MeasureFontString({}))
    end)

    -- The empty string between populates. Zero is the reading that would
    -- collapse the box onto its anchor while the text is merely absent for a
    -- frame, which is the whole reason the caller keeps its previous sample.
    it("refuses a zero measurement", function()
        assert.is_nil(KE:MeasureFontString(fs(0, 16)))
        assert.is_nil(KE:MeasureFontString(fs(9, 0)))
    end)

    it("refuses a negative measurement", function()
        assert.is_nil(KE:MeasureFontString(fs(-1, 16)))
        assert.is_nil(KE:MeasureFontString(fs(9, -1)))
    end)

    it("refuses a non-number measurement", function()
        assert.is_nil(KE:MeasureFontString(fs("9", 16)))
        assert.is_nil(KE:MeasureFontString(fs(9, "16")))
    end)

    -- Each axis has to be able to fail on its own. A guard written against the
    -- width alone passes every case above that varies the width, and reports a
    -- height nobody checked.
    it("refuses on either axis independently", function()
        assert.is_nil(KE:MeasureFontString(fs(9, nil)))
        assert.is_nil(KE:MeasureFontString(fs(nil, 16)))
    end)
end)
