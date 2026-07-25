-- Tier 1/2: DamageMeter module-owned defaults seed (Modules/DamageMeter/Core.lua).
-- DM.FillMissingDefaults is the REAL FillMissing body (busted seam at the source);
-- DM:UpdateDB drives it against the real DM_DEFAULTS table. Pins the MIGRATION
-- semantics from the v3.0.x AceDB-registered era: AceDB's logout-time
-- removeDefaults stripped default-equal leaves and deleted nested tables that
-- became empty, so real SavedVariables carry holes (Dock.Columns[1] = nil,
-- anchor-less Position tables). The recursive refill must rebuild those exactly
-- as AceDB's login-time copyDefaults used to -- without ever touching a user-set
-- value (including falsy toggles).
local L = require("dev.spec._ke_loader")

describe("DamageMeter FillMissingDefaults", function()
    local DM
    before_each(function()
        DM = L.loadDMCore()
    end)

    it("fills missing keys and recurses into tables present on both sides", function()
        local saved = { Kept = 5, Nest = { UserKey = "u" } }
        DM.FillMissingDefaults(saved, { Kept = 1, Added = 2, Nest = { UserKey = "d", DefKey = "d2" } })
        assert.equals(5, saved.Kept)
        assert.equals(2, saved.Added)
        assert.equals("u", saved.Nest.UserKey)
        assert.equals("d2", saved.Nest.DefKey)
    end)

    it("never overwrites a non-nil leaf, including false", function()
        local saved = { Flag = false }
        DM.FillMissingDefaults(saved, { Flag = true })
        assert.is_false(saved.Flag)
    end)

    it("deep-copies filled tables (no aliasing of the defaults)", function()
        local defaults = { T = { a = 1 } }
        local saved = {}
        DM.FillMissingDefaults(saved, defaults)
        saved.T.a = 99
        assert.equals(1, defaults.T.a)
    end)
end)

describe("DamageMeter UpdateDB migration refill (real DM_DEFAULTS)", function()
    local DM, KE
    before_each(function()
        DM, KE = L.loadDMCore()
    end)

    -- Install `section` as the saved profile slice and run the real seed.
    local function seed(section)
        KE.db = { profile = { DamageMeter = section } }
        DM:UpdateDB()
        return KE.db.profile.DamageMeter
    end

    it("seeds a fresh profile fully and binds self.db", function()
        local db = seed(nil)   -- section absent entirely -> created + filled
        assert.equals(db, DM.db)
        assert.is_true(db.Enabled)
        assert.equals(212, db.Width)
        assert.equals("BOTTOMRIGHT", db.Position.AnchorFrom)
        assert.equals(1, db.Dock.Columns[1].Windows[1])
    end)

    it("refills the v3.0.x Dock.Columns[1] hole, keeping column 2 untouched", function()
        -- The confirmed live-SV shape: the shipped column 1 equaled the old
        -- registered default, so AceDB stripped it to nil at logout. A
        -- top-level-only fill would skip the non-nil Dock and lose window 1.
        local col2 = { WidthRatio = 1, Windows = { 2, 3 }, RowRatios = { 0.61, 0.39 } }
        local db = seed({ Dock = { Columns = { nil, col2 } } })
        local c1 = db.Dock.Columns[1]
        assert.equals("table", type(c1))
        assert.equals(1, c1.Windows[1])
        assert.equals(1, c1.WidthRatio)
        assert.equals(col2, db.Dock.Columns[2])   -- same table, not rebuilt
        assert.equals(2, col2.Windows[1])
    end)

    it("refills stripped Position anchors around kept offsets", function()
        -- EditMode drags preserve the default anchors (stripped at logout);
        -- only the offsets persisted. The refilled anchors make those offsets
        -- correct again -- a missing-anchor fallback would relocate the dock.
        local db = seed({ Position = { XOffset = -140, YOffset = 77 } })
        assert.equals("BOTTOMRIGHT", db.Position.AnchorFrom)
        assert.equals("BOTTOMRIGHT", db.Position.AnchorTo)
        assert.equals(-140, db.Position.XOffset)
        assert.equals(77, db.Position.YOffset)
    end)

    it("refills stripped color channels per index", function()
        -- A user color sharing one channel with the default was stored
        -- sparsely; the refilled channel must be the DEFAULT channel value,
        -- not a reader's fallback grey.
        local db = seed({ BarColor = { nil, 0.2, 0.2 } })
        assert.equals(0.302, db.BarColor[1])
        assert.equals(0.2, db.BarColor[2])
        assert.equals(0.2, db.BarColor[3])
    end)

    it("preserves user-set values, including falsy toggles", function()
        local db = seed({ Locked = false, VisibleBars = 20, ShowIcon = false })
        assert.is_false(db.Locked)
        assert.equals(20, db.VisibleBars)
        assert.is_false(db.ShowIcon)
    end)

    it("re-binds self.db when re-run against a new profile (switch path)", function()
        local a = seed({ VisibleBars = 11 })
        assert.equals(a, DM.db)
        local b = seed({ VisibleBars = 22 })
        assert.equals(b, DM.db)
        assert.equals(22, DM.db.VisibleBars)
        assert.equals(11, a.VisibleBars)   -- the old profile slice is untouched
    end)

    it("never touches pending state — it lives in the global section, not the profile", function()
        -- Persisted pending is PROFILE-INDEPENDENT (KE.db.global, History.lua):
        -- a profile op must neither mirror nor clear it. A leftover
        -- profile-section HistoryPending from the short-lived per-profile
        -- design is inert data UpdateDB simply ignores.
        local pending = { label = "Algeth'ar Academy", level = 20 }
        DM._pendingBundle = pending
        local db = seed({ HistoryPending = { label = "Leftover per-profile record" } })
        assert.equals("Leftover per-profile record", db.HistoryPending.label)
        assert.equals(pending, DM._pendingBundle)
    end)

    it("leaves the empty Windows default empty (no phantom windows)", function()
        local db = seed(nil)
        assert.is_nil(next(db.Windows))
    end)
end)
