-- Tier 1: the refusal rule that decides whether a settings change is in-place
-- or needs the frames rebuilt. It is invented logic, it is the whole fix for a
-- profile switch leaving the entry frames at the previous profile's size, and
-- it fails silently: a term left out of the key means that setting stops
-- triggering a rebuild and nobody notices until the frames look wrong.
local L = require("dev.spec._ke_loader")

describe("TS.StructuralKey", function()
    local TS
    setup(function()
        TS = L.loadTargetedSpells()
    end)

    local function db(overrides)
        local d = { IconSize = 36, TextSpacing = 32, Gap = 3, Grow = "DOWN" }
        for k, v in pairs(overrides or {}) do d[k] = v end
        return d
    end

    it("is stable for the same settings", function()
        assert.equals(TS.StructuralKey(db()), TS.StructuralKey(db()))
    end)

    -- One case per term. Each of these four feeds either the anchor's size, an
    -- entry's size, or the spacer chain, so each must force a rebuild.
    it("changes when the icon size changes", function()
        assert.are_not.equals(TS.StructuralKey(db()), TS.StructuralKey(db({ IconSize = 60 })))
    end)

    it("changes when the text spacing changes", function()
        assert.are_not.equals(TS.StructuralKey(db()), TS.StructuralKey(db({ TextSpacing = 48 })))
    end)

    it("changes when the gap changes", function()
        assert.are_not.equals(TS.StructuralKey(db()), TS.StructuralKey(db({ Gap = 10 })))
    end)

    it("changes when the growth direction changes", function()
        assert.are_not.equals(TS.StructuralKey(db()), TS.StructuralKey(db({ Grow = "UP" })))
    end)

    -- The decoy. An in-place setting must NOT force a rebuild, or every glow
    -- checkbox tears down the pool and the key is worse than not having it.
    it("does not change for an in-place setting", function()
        assert.equals(TS.StructuralKey(db()), TS.StructuralKey(db({ GlowImportant = true })))
    end)

    -- Concatenated terms can collude: without separators, IconSize 36 with
    -- TextSpacing 3 and IconSize 3 with TextSpacing 63 both read "363".
    it("does not collide when a digit moves between terms", function()
        assert.are_not.equals(
            TS.StructuralKey(db({ IconSize = 36, TextSpacing = 3 })),
            TS.StructuralKey(db({ IconSize = 3, TextSpacing = 63 })))
    end)

    -- An unsaved profile reaches this with the same defaults the frame
    -- builders use, so a fresh profile must not read as a change.
    it("treats absent settings as the builders' own defaults", function()
        assert.equals(TS.StructuralKey(db()), TS.StructuralKey({}))
    end)

    it("returns a comparable value rather than erroring without a db", function()
        assert.equals("", TS.StructuralKey(nil))
    end)
end)
