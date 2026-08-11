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

    -- Every refusal asserts BOTH returns. Asserting only the first passes an
    -- implementation that refuses the width and hands back a height anyway,
    -- because the caller would then store a half-measurement as if it were one.
    local function refuses(candidate)
        local w, h = KE:MeasureFontString(candidate)
        assert.is_nil(w)
        assert.is_nil(h)
    end

    it("measures a string that answers with two positive numbers", function()
        local w, h = KE:MeasureFontString(fs(9, 16))
        assert.equals(9, w)
        assert.equals(16, h)
    end)

    it("refuses nothing at all", function()
        refuses(nil)
    end)

    -- The overlay callback runs against whatever the module hands it, and a
    -- module that has not built its buttons yet hands over a plain table.
    it("refuses an object that is not a font string", function()
        refuses({})
    end)

    -- Each getter is tested separately, because one of them existing does not
    -- imply the other. A guard that checks only the width calls the height
    -- method on something that does not have it, and throws where it meant to
    -- refuse -- which no assertion about the return value can catch.
    it("refuses an object carrying only the width getter", function()
        refuses({ GetStringWidth = function() return 9 end })
    end)

    it("refuses an object carrying only the height getter", function()
        refuses({ GetStringHeight = function() return 16 end })
    end)

    -- The empty string between populates. Zero is the reading that would
    -- collapse the box onto its anchor while the text is merely absent for a
    -- frame, which is the whole reason the caller keeps its previous sample.
    it("refuses a zero measurement", function()
        refuses(fs(0, 16))
        refuses(fs(9, 0))
    end)

    it("refuses a negative measurement", function()
        refuses(fs(-1, 16))
        refuses(fs(9, -1))
    end)

    it("refuses a non-number measurement", function()
        refuses(fs("9", 16))
        refuses(fs(9, "16"))
    end)

    -- Each axis has to be able to fail on its own. A guard written against the
    -- width alone passes every case above that varies the width, and reports a
    -- height nobody checked.
    it("refuses on either axis independently", function()
        refuses(fs(9, nil))
        refuses(fs(nil, 16))
    end)
end)
