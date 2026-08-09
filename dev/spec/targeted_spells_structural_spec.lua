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
        local d = { IconSize = 36, TextSpacing = 32, Gap = 3, Grow = "DOWN",
                    MaxIcons = 10, FontSize = 32 }
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

    it("changes when the entry cap changes", function()
        assert.are_not.equals(TS.StructuralKey(db()), TS.StructuralKey(db({ MaxIcons = 4 })))
    end)

    -- Font size is the term the page does NOT route through a rebuild, which is
    -- exactly why it is easy to leave out: it sizes the interrupt cross when an
    -- entry is built, so a pooled entry keeps the old one.
    it("changes when the font size changes", function()
        assert.are_not.equals(TS.StructuralKey(db()), TS.StructuralKey(db({ FontSize = 20 })))
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

    -- Each fallback must be the one the BUILDER for that term uses, not the
    -- shipped default -- the key describes the geometry the builders would
    -- actually produce, and for TextSpacing and Grow the two disagree. Pinning
    -- the builders' numbers here is what stops someone "correcting" them to
    -- match Defaults.lua and making a never-saved profile read as changed.
    it("falls back to the builders' own numbers, not the shipped defaults", function()
        assert.equals(
            TS.StructuralKey({ IconSize = 36, TextSpacing = 32, Gap = 3,
                               Grow = "DOWN", MaxIcons = 10, FontSize = 0 }),
            TS.StructuralKey({}))
    end)

    it("returns a comparable value rather than erroring without a db", function()
        assert.equals("", TS.StructuralKey(nil))
    end)
end)

-- The branch the key exists to drive. Separate describe because it needs the
-- module's own state and stubs, where the key above needs nothing at all.
describe("TS:ApplySettings handoff", function()
    local TS, rebuilt, glowed, gated

    setup(function()
        TS = require("dev.spec._ke_loader").loadTargetedSpells()
    end)

    before_each(function()
        rebuilt, glowed, gated = 0, 0, 0
        TS.db = { IconSize = 36, TextSpacing = 32, Gap = 3, Grow = "DOWN",
                  MaxIcons = 10, FontSize = 32 }
        TS.activeEntries = { { } }
        TS.builtStructuralKey = TS.StructuralKey(TS.db)

        TS.UpdateDB = function() end
        TS.RebuildEntries = function() rebuilt = rebuilt + 1 end
        TS.UpdateGlow = function() glowed = glowed + 1 end
        TS.CheckContentGate = function() gated = gated + 1 end
    end)

    it("takes the in-place path when nothing structural changed", function()
        TS:ApplySettings()

        assert.equals(0, rebuilt)
        assert.equals(1, glowed)
        assert.equals(1, gated)
    end)

    -- Rebuild ONCE and stop. The glow loop below the handoff would walk entries
    -- the rebuild has already released, and the rebuild runs its own gate.
    it("hands off exactly once and returns when the geometry changed", function()
        TS.db.IconSize = 60

        TS:ApplySettings()

        assert.equals(1, rebuilt)
        assert.equals(0, glowed)
        assert.equals(0, gated)
    end)

    -- A module that has never built anything must rebuild rather than assume
    -- the pool matches, or the very first switch is the one that gets missed.
    it("hands off when nothing has been built yet", function()
        TS.builtStructuralKey = nil

        TS:ApplySettings()

        assert.equals(1, rebuilt)
    end)
end)
