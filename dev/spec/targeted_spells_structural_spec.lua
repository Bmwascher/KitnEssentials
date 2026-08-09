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

    local function db(overrides)
        local d = {
            IconSize = 36, TextSpacing = 45, Gap = 3, Grow = "UP", MaxIcons = 10,
            FontSize = 32, FontFace = "Expressway", FontOutline = "OUTLINE",
            Decimals = 1, FontColor = { 1, 0.976, 0.153, 1 },
        }
        for k, v in pairs(overrides or {}) do d[k] = v end
        return d
    end

    it("is stable for the same settings", function()
        assert.equals(TS.RebuildKey(db()), TS.RebuildKey(db()))
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
        { name = "font face",         change = { FontFace = "GoodFont" } },
        { name = "font outline",      change = { FontOutline = "" } },
        { name = "decimals",          change = { Decimals = 0 } },
        { name = "countdown colour",  change = { FontColor = { 0, 1, 0, 1 } } },
    }

    for _, term in ipairs(TERMS) do
        it("changes when the " .. term.name .. " changes", function()
            assert.are_not.equals(TS.RebuildKey(db()), TS.RebuildKey(db(term.change)))
        end)
    end

    -- The decoy. An in-place setting must NOT force a rebuild, or every glow
    -- checkbox tears down the pool and the key is worse than not having it.
    it("does not change for an in-place setting", function()
        assert.equals(TS.RebuildKey(db()), TS.RebuildKey(db({ GlowImportant = true })))
    end)

    -- Concatenated terms can collude: without separators, icon size 36 with
    -- text spacing 3 and icon size 3 with text spacing 63 both read "363".
    it("does not collide when a digit moves between terms", function()
        assert.are_not.equals(
            TS.RebuildKey(db({ IconSize = 36, TextSpacing = 3 })),
            TS.RebuildKey(db({ IconSize = 3, TextSpacing = 63 })))
    end)

    -- Absent terms are built by deletion, not by an override table: a nil in an
    -- override never survives pairs(), so the two keys would be identical and
    -- the case would pass against a helper that ignored absence entirely.
    local function without(field)
        local d = db()
        d[field] = nil
        return d
    end

    -- An absent term must not read as equal to a present one. There are no
    -- fallbacks in the key on purpose, so this is what holds that line.
    it("tells an absent setting apart from a present one", function()
        assert.are_not.equals(TS.RebuildKey(db()), TS.RebuildKey(without("FontSize")))
    end)

    -- A missing colour table must not throw from a lifecycle path, and must
    -- still differ from a present one.
    it("survives a missing colour table", function()
        assert.are_not.equals(TS.RebuildKey(db()), TS.RebuildKey(without("FontColor")))
    end)
end)

-- The branch the key exists to drive, at both the doors that reach it.
describe("TS structural sync", function()
    local TS, rebuilt, glowed, gated

    setup(function()
        TS = require("dev.spec._ke_loader").loadTargetedSpells()
    end)

    local function settings()
        return {
            IconSize = 36, TextSpacing = 45, Gap = 3, Grow = "UP", MaxIcons = 10,
            FontSize = 32, FontFace = "Expressway", FontOutline = "OUTLINE",
            Decimals = 1, FontColor = { 1, 1, 1, 1 },
        }
    end

    before_each(function()
        rebuilt, glowed, gated = 0, 0, 0
        TS.db = settings()
        TS.activeEntries = { {} }
        TS.builtRebuildKey = TS.RebuildKey(TS.db)

        TS.UpdateDB = function() end
        TS.RebuildEntries = function() rebuilt = rebuilt + 1 end
        TS.UpdateGlow = function() glowed = glowed + 1 end
        TS.CheckContentGate = function() gated = gated + 1 end
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
            TS.builtRebuildKey = TS.RebuildKey({ IconSize = 60 })

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

        -- Rebuild once and stop. The glow loop below the handoff would walk
        -- entries the rebuild has already released, and the rebuild gates too.
        it("hands off exactly once and returns when the geometry changed", function()
            TS.db.IconSize = 60

            TS:ApplySettings()

            assert.equals(1, rebuilt)
            assert.equals(0, glowed)
            assert.equals(0, gated)
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
