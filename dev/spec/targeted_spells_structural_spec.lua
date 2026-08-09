-- Tier 1: the refusal rule that decides whether a settings change is in-place
-- or needs the pooled entry frames rebuilt. It is invented logic, it is the
-- whole fix for a profile switch leaving those frames at the previous profile's
-- size, and it fails silently: a term left out of the key means that setting
-- stops triggering a rebuild and nobody notices until the frames look wrong.
local L = require("dev.spec._ke_loader")

describe("TS.RebuildKey", function()
    local TS
    setup(function()
        TS = L.loadTargetedSpells()
    end)

    -- The face is a parameter, not a db field: a nil FontFace MEANS the
    -- profile's global font, so the resolution lives in CurrentRebuildKey and
    -- these cases hold the face constant unless they are testing it.
    local FACE = "Expressway"

    local function db(overrides)
        local d = {
            IconSize = 36, TextSpacing = 45, Gap = 3, Grow = "UP", MaxIcons = 10,
            FontSize = 32, FontOutline = "OUTLINE",
            Decimals = 1, FontColor = { 1, 0.976, 0.153, 1 },
        }
        for k, v in pairs(overrides or {}) do d[k] = v end
        return d
    end

    local function key(overrides, face)
        return TS.RebuildKey(db(overrides), face or FACE)
    end

    it("is stable for the same settings", function()
        assert.equals(key(), key())
    end)

    -- One case per term the settings page rebuilds for. That page is the single
    -- definition of the set; these cases are what stop the two drifting apart.
    local TERMS = {
        { name = "icon size",         change = { IconSize = 60 } },
        { name = "text spacing",      change = { TextSpacing = 20 } },
        { name = "gap",               change = { Gap = 10 } },
        { name = "growth direction",  change = { Grow = "DOWN" } },
        { name = "entry cap",         change = { MaxIcons = 4 } },
        { name = "font size",         change = { FontSize = 20 } },
        { name = "font outline",      change = { FontOutline = "" } },
        { name = "decimals",          change = { Decimals = 0 } },
        { name = "countdown colour",  change = { FontColor = { 0, 1, 0, 1 } } },
    }

    for _, term in ipairs(TERMS) do
        it("changes when the " .. term.name .. " changes", function()
            assert.are_not.equals(key(), key(term.change))
        end)
    end

    it("changes when the resolved font face changes", function()
        assert.are_not.equals(key(), key(nil, "GoodFont"))
    end)

    -- The decoy. An in-place setting must NOT force a rebuild, or every glow
    -- checkbox tears down the pool and the key is worse than not having it.
    it("does not change for an in-place setting", function()
        assert.equals(key(), key({ GlowImportant = true }))
    end)

    -- The raw FontFace setting is deliberately NOT read. Keying it would make
    -- a profile that names the global font explicitly differ from one that
    -- leaves it alone, while both render the same.
    it("ignores the raw FontFace setting", function()
        assert.equals(key(), key({ FontFace = "Whatever" }))
    end)

    -- Concatenated terms can collude: without separators, icon size 36 with
    -- text spacing 3 and icon size 3 with text spacing 63 both read "363".
    it("does not collide when a digit moves between terms", function()
        assert.are_not.equals(
            key({ IconSize = 36, TextSpacing = 3 }),
            key({ IconSize = 3, TextSpacing = 63 }))
    end)

    -- Absent terms are built by deletion, not by an override table: a nil in an
    -- override never survives pairs(), so the two keys would be identical and
    -- the case would pass against a helper that ignored absence entirely.
    local function without(field)
        local d = db()
        d[field] = nil
        return TS.RebuildKey(d, FACE)
    end

    -- An absent term must not read as equal to a present one. There are no
    -- fallbacks in the key on purpose, so this is what holds that line.
    it("tells an absent setting apart from a present one", function()
        assert.are_not.equals(key(), without("FontSize"))
    end)

    -- A missing colour table must not throw from a lifecycle path, and must
    -- still differ from a present one.
    it("survives a missing colour table", function()
        assert.are_not.equals(key(), without("FontColor"))
    end)
end)

-- A nil FontFace is not "no font" — it means the profile's global font. Keying
-- the raw setting is wrong in both directions, so the resolution is its own
-- seam and gets its own cases.
describe("TS:CurrentRebuildKey", function()
    local TS, KE, globalFont

    setup(function()
        TS, KE = L.loadTargetedSpells()
        KE.GetGlobalFont = function() return globalFont end
    end)

    before_each(function()
        globalFont = "Expressway"
        TS.db = { IconSize = 36, FontSize = 32 }
    end)

    it("follows the global font when the module has no choice of its own", function()
        local before = TS:CurrentRebuildKey()
        globalFont = "Naowh"

        assert.are_not.equals(before, TS:CurrentRebuildKey())
    end)

    it("reads the same whether the global font is named or left implicit", function()
        local implicit = TS:CurrentRebuildKey()
        TS.db.FontFace = "Expressway"

        assert.equals(implicit, TS:CurrentRebuildKey())
    end)

    it("ignores the global font once the module names its own", function()
        TS.db.FontFace = "GoodFont"
        local before = TS:CurrentRebuildKey()
        globalFont = "Naowh"

        assert.equals(before, TS:CurrentRebuildKey())
    end)
end)

-- The branch the key exists to drive, at both the doors that reach it.
describe("TS structural sync", function()
    local TS, KE, rebuilt, glowed, gated, positioned

    setup(function()
        TS, KE = L.loadTargetedSpells()
        KE.GetGlobalFont = function() return "Expressway" end
    end)

    local function settings()
        return {
            IconSize = 36, TextSpacing = 45, Gap = 3, Grow = "UP", MaxIcons = 10,
            FontSize = 32, FontFace = "Expressway", FontOutline = "OUTLINE",
            Decimals = 1, FontColor = { 1, 1, 1, 1 },
        }
    end

    before_each(function()
        rebuilt, glowed, gated, positioned = 0, 0, 0, 0
        TS.db = settings()
        TS.activeEntries = { {} }
        TS.builtRebuildKey = TS:CurrentRebuildKey()

        TS.UpdateDB = function() end
        TS.RebuildEntries = function() rebuilt = rebuilt + 1 end
        TS.UpdateGlow = function() glowed = glowed + 1 end
        TS.CheckContentGate = function() gated = gated + 1 end
        TS.ApplyPosition = function() positioned = positioned + 1 end
    end)

    describe("SyncStructure", function()
        it("does nothing while the pooled frames still match", function()
            assert.is_false(TS:SyncStructure())
            assert.equals(0, rebuilt)
        end)

        it("rebuilds when a rebuild-triggering setting changed", function()
            TS.db.IconSize = 60

            assert.is_true(TS:SyncStructure())
            assert.equals(1, rebuilt)
        end)

        -- The re-enable case. Disabling only releases entries into the pool, so
        -- coming back under another profile finds frames built to the old
        -- numbers; nothing else on that path would notice.
        it("rebuilds when the pool was built for another profile", function()
            TS.builtRebuildKey = TS.RebuildKey({ IconSize = 60 }, "Expressway")

            assert.is_true(TS:SyncStructure())
            assert.equals(1, rebuilt)
        end)

        -- A module that has never built anything must rebuild rather than
        -- assume, or the very first switch is the one that gets missed.
        it("rebuilds when nothing has been built yet", function()
            TS.builtRebuildKey = nil

            assert.is_true(TS:SyncStructure())
            assert.equals(1, rebuilt)
        end)
    end)

    describe("ApplySettings", function()
        it("takes the in-place path when nothing structural changed", function()
            TS:ApplySettings()

            assert.equals(0, rebuilt)
            assert.equals(1, glowed)
            assert.equals(1, gated)
        end)

        -- Position, parent and strata are profile settings the rebuild key
        -- cannot see, and a switch that leaves the module enabled reaches only
        -- this function. Without this the anchor keeps the other profile's spot.
        it("re-applies the anchor position on the in-place path", function()
            TS:ApplySettings()

            assert.equals(1, positioned)
        end)

        -- Rebuild once and stop. The glow loop below the handoff would walk
        -- entries the rebuild has already released, and the rebuild gates and
        -- re-positions on its own.
        it("hands off exactly once and returns when the geometry changed", function()
            TS.db.IconSize = 60

            TS:ApplySettings()

            assert.equals(1, rebuilt)
            assert.equals(0, glowed)
            assert.equals(0, gated)
            assert.equals(0, positioned)
        end)
    end)
end)

-- Frames are never collected in WoW, so a rebuild that runs twice orphans a
-- whole pool. The queue and the synchronous path can both fire for one change.
describe("TS:QueueRebuild invalidation", function()
    local TS, rebuilt, pending

    -- Held rather than run, so the window between queueing and firing is the
    -- thing under test. Installed at LOAD time: the module localizes C_Timer at
    -- file scope, so a swap afterwards never reaches it.
    setup(function()
        TS = L.loadTargetedSpells({
            C_Timer = { After = function(_, fn) pending = fn end },
        })
    end)

    before_each(function()
        rebuilt = 0
        pending = nil

        TS._rebuildQueued = false
        TS._rebuildGeneration = 0
        TS.RealRebuildEntries = TS.RealRebuildEntries or TS.RebuildEntries
        TS.RebuildEntries = function(self)
            self._rebuildGeneration = (self._rebuildGeneration or 0) + 1
            self._rebuildQueued = false
            rebuilt = rebuilt + 1
        end
    end)

    it("still rebuilds when nothing intervenes", function()
        TS:QueueRebuild()
        pending()

        assert.equals(1, rebuilt)
    end)

    it("stands down when a synchronous rebuild already happened", function()
        TS:QueueRebuild()
        TS:RebuildEntries()   -- the profile-switch path, mid-wait
        pending()

        assert.equals(1, rebuilt)
    end)

    it("can queue again after standing down", function()
        TS:QueueRebuild()
        TS:RebuildEntries()
        pending()

        TS:QueueRebuild()
        pending()

        assert.equals(2, rebuilt)
    end)
end)
