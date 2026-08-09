-- Tier 1: the refusal rule that decides whether a settings change is in-place
-- or needs the pooled entry frames rebuilt. It is invented logic, it is the
-- whole fix for a profile switch leaving those frames at the previous profile's
-- size, and it fails silently: a term left out of the key means that setting
-- stops triggering a rebuild and nobody notices until the frames look wrong.
local L = require("dev.spec._ke_loader")

-- What KE:GetFontOutline does with each stored value. Its own mapping is specced
-- in globals_helpers_spec; here it only has to be a mapping that collapses
-- several stored values onto one rendered one, because that collapse is the
-- thing CurrentRebuildKey has to respect.
local OUTLINE_RESOLVES_TO = {
    SOFTOUTLINE = "OUTLINE",
    OUTLINE = "OUTLINE",
    THICKOUTLINE = "THICKOUTLINE",
    NONE = "",
    [""] = "",
}

-- What KE:GetFontPath does with a stored face name: nil means the profile's
-- global font, a registered name becomes its file, and anything the media
-- library does not know falls back to the default font. Its own behaviour is
-- specced with the Core helpers; here it only has to be a lookup with a
-- fallback, because the fallback is what collapses distinct names onto one file.
local FALLBACK_FONT = "Fonts\\FRIZQT__.TTF"
local FONT_FILES = {
    Expressway = "Media\\Expressway.TTF",
    Naowh = "Media\\Naowh.TTF",
    -- Two names, one file. A rename or an alias in the media library does this.
    ExpresswayAlias = "Media\\Expressway.TTF",
}

local function fontPathResolver(globalFontGetter)
    return function(_, name)
        name = name or globalFontGetter()
        return FONT_FILES[name] or FALLBACK_FONT
    end
end

describe("TS.RebuildKey", function()
    local TS
    setup(function()
        TS = L.loadTargetedSpells()
    end)

    -- Font FILE and outline are parameters, not db fields: both stored values
    -- stand for something else at render time, so the resolutions live in
    -- CurrentRebuildKey and these cases hold them constant unless testing them.
    local PATH, OUTLINE = FONT_FILES.Expressway, "OUTLINE"

    local function db(overrides)
        local d = {
            IconSize = 36, TextSpacing = 45, Gap = 3, Grow = "UP", MaxIcons = 10,
            FontSize = 32, Decimals = 1, FontColor = { 1, 0.976, 0.153, 1 },
        }
        for k, v in pairs(overrides or {}) do d[k] = v end
        return d
    end

    local function key(overrides, path, outline)
        return TS.RebuildKey(db(overrides), path or PATH, outline or OUTLINE)
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
        { name = "decimals",          change = { Decimals = 0 } },
        { name = "countdown colour",  change = { FontColor = { 0, 1, 0, 1 } } },
    }

    for _, term in ipairs(TERMS) do
        it("changes when the " .. term.name .. " changes", function()
            assert.are_not.equals(key(), key(term.change))
        end)
    end

    it("changes when the resolved font file changes", function()
        assert.are_not.equals(key(), key(nil, FONT_FILES.Naowh))
    end)

    it("changes when the resolved font outline changes", function()
        assert.are_not.equals(key(), key(nil, nil, "THICKOUTLINE"))
    end)

    -- The decoy. An in-place setting must NOT force a rebuild, or every glow
    -- checkbox tears down the pool and the key is worse than not having it.
    it("does not change for an in-place setting", function()
        assert.equals(key(), key({ GlowImportant = true }))
    end)

    -- The raw settings are deliberately NOT read. Keying them would make a
    -- profile that names the global font, or stores a legacy outline value,
    -- differ from one that does not while both render the same.
    it("ignores the raw FontFace setting", function()
        assert.equals(key(), key({ FontFace = "Whatever" }))
    end)

    it("ignores the raw FontOutline setting", function()
        assert.equals(key(), key({ FontOutline = "SOFTOUTLINE" }))
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
        return TS.RebuildKey(d, PATH, OUTLINE)
    end

    -- An absent term must not read as equal to a present one. The key is
    -- deliberately fail-closed on absence — it costs one extra rebuild and buys
    -- never mistaking a real change for no change — so this holds that line.
    it("tells an absent setting apart from a present one", function()
        assert.are_not.equals(key(), without("FontSize"))
    end)

    -- A missing colour table must not throw from a lifecycle path, and must
    -- still differ from a present one.
    it("survives a missing colour table", function()
        assert.are_not.equals(key(), without("FontColor"))
    end)
end)

-- Both font terms are stored values that stand for something else at render
-- time. Keying them raw is wrong in both directions, so the resolution is its
-- own seam and gets its own cases.
describe("TS:CurrentRebuildKey", function()
    local TS, KE, globalFont, outlineAsked

    setup(function()
        TS, KE = L.loadTargetedSpells()
        KE.GetGlobalFont = function() return globalFont end
        KE.GetFontPath = fontPathResolver(function() return globalFont end)
        KE.GetFontOutline = function(_, stored)
            outlineAsked = stored
            return OUTLINE_RESOLVES_TO[stored] or stored
        end
    end)

    before_each(function()
        globalFont = "Expressway"
        outlineAsked = nil
        TS.db = { IconSize = 36, FontSize = 32, FontOutline = "OUTLINE" }
    end)

    describe("the font file", function()
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
            TS.db.FontFace = "Naowh"
            local before = TS:CurrentRebuildKey()
            globalFont = "GoodFont"

            assert.equals(before, TS:CurrentRebuildKey())
        end)

        -- The reason the FILE is keyed and not the name. Two names that resolve
        -- to one file render identically, so a switch between them must not
        -- tear down the pool.
        it("reads the same for two names that resolve to one file", function()
            TS.db.FontFace = "Expressway"
            local named = TS:CurrentRebuildKey()
            TS.db.FontFace = "ExpresswayAlias"

            assert.equals(named, TS:CurrentRebuildKey())
        end)

        -- Same reason, the shape that actually happens: a font the media
        -- library never registered draws as the default, so two unknown names
        -- both render the default and must key alike.
        it("reads the same for two names the media library does not know", function()
            TS.db.FontFace = "NotInstalled"
            local missing = TS:CurrentRebuildKey()
            TS.db.FontFace = "AlsoNotInstalled"

            assert.equals(missing, TS:CurrentRebuildKey())
        end)
    end)

    describe("the font outline", function()
        -- The wiring, not the mapping: whatever the renderer resolves an
        -- outline to, the key has to ask the same question.
        it("asks the shared resolver what the stored value renders as", function()
            TS.db.FontOutline = "SOFTOUTLINE"
            TS:CurrentRebuildKey()

            assert.equals("SOFTOUTLINE", outlineAsked)
        end)

        it("reads the same for two stored values that render alike", function()
            TS.db.FontOutline = "OUTLINE"
            local plain = TS:CurrentRebuildKey()
            TS.db.FontOutline = "SOFTOUTLINE"

            assert.equals(plain, TS:CurrentRebuildKey())
        end)

        it("still tells genuinely different outlines apart", function()
            local plain = TS:CurrentRebuildKey()
            TS.db.FontOutline = "THICKOUTLINE"

            assert.are_not.equals(plain, TS:CurrentRebuildKey())
        end)
    end)

    it("survives being asked before the db exists", function()
        TS.db = nil

        assert.equals("", TS:CurrentRebuildKey())
    end)
end)

-- The branch the key exists to drive, at both the doors that reach it.
describe("TS structural sync", function()
    local TS, KE, rebuilt, glowed, gated, positioned

    setup(function()
        TS, KE = L.loadTargetedSpells()
        KE.GetGlobalFont = function() return "Expressway" end
        KE.GetFontPath = fontPathResolver(function() return "Expressway" end)
        KE.GetFontOutline = function(_, stored) return OUTLINE_RESOLVES_TO[stored] or stored end
    end)

    local function settings()
        return {
            Enabled = true,
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
            TS.builtRebuildKey = TS.RebuildKey({ IconSize = 60 }, FONT_FILES.Expressway, "OUTLINE")

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
-- whole pool. A quarter second is long enough for a profile switch, so the
-- queued timer must re-ask whether its rebuild is still wanted rather than
-- trust the answer it had when it was set.
describe("TS:QueueRebuild invalidation", function()
    local TS, KE, rebuilt, pending

    -- Held rather than run, so the window between queueing and firing is the
    -- thing under test. Installed at LOAD time: the module localizes C_Timer at
    -- file scope, so a swap afterwards never reaches it.
    setup(function()
        TS, KE = L.loadTargetedSpells({
            C_Timer = { After = function(_, fn) pending = fn end },
        })
        KE.GetGlobalFont = function() return "Expressway" end
        KE.GetFontPath = fontPathResolver(function() return "Expressway" end)
        KE.GetFontOutline = function(_, stored) return OUTLINE_RESOLVES_TO[stored] or stored end
    end)

    -- The real RebuildEntries touches frames; this one keeps the single
    -- behaviour the timer depends on, which is that a rebuild stamps the key.
    before_each(function()
        rebuilt = 0
        pending = nil

        TS._rebuildQueued = false
        TS.db = { Enabled = true, IconSize = 36, FontSize = 32, FontOutline = "OUTLINE" }
        TS.builtRebuildKey = TS:CurrentRebuildKey()
        TS.RebuildEntries = function(self)
            self._rebuildQueued = false
            self.builtRebuildKey = self:CurrentRebuildKey()
            rebuilt = rebuilt + 1
        end
    end)

    it("still rebuilds when the change is still wanted", function()
        TS.db.IconSize = 60
        TS:QueueRebuild()
        pending()

        assert.equals(1, rebuilt)
    end)

    it("stands down when a synchronous rebuild already happened", function()
        TS.db.IconSize = 60
        TS:QueueRebuild()
        TS:RebuildEntries()   -- the profile-switch path, mid-wait
        pending()

        assert.equals(1, rebuilt)
    end)

    -- The hole a captured token could not see: nothing rebuilt, but the profile
    -- that arrived in the meantime already matches what is built, so the timer
    -- would drop a pool for no reason.
    it("stands down when the new profile already matches what is built", function()
        TS.db.IconSize = 60
        TS:QueueRebuild()
        TS.db.IconSize = 36   -- switched to a profile equal to the built state
        pending()

        assert.equals(0, rebuilt)
    end)

    -- Same hole, other shape: a switch can disable the module outright, and
    -- that path never reaches ApplySettings at all.
    it("stands down when the module was disabled before it fired", function()
        TS.db.IconSize = 60
        TS:QueueRebuild()
        TS.db.Enabled = false
        pending()

        assert.equals(0, rebuilt)
    end)

    it("can queue again after standing down", function()
        TS.db.IconSize = 60
        TS:QueueRebuild()
        TS:RebuildEntries()
        pending()

        TS.db.IconSize = 48
        TS:QueueRebuild()
        pending()

        assert.equals(2, rebuilt)
    end)
end)
