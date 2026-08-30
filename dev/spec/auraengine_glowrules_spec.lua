local L = require("dev.spec._ke_loader")

describe("glow type coercion", function()
    it("maps the retired autocast style onto the pixel border", function()
        local G = L.loadAuraGlowRules()
        assert.equals("pixel", G.ResolveType("autocast"))
    end)

    it("maps the two fill styles to procloop", function()
        local G = L.loadAuraGlowRules()
        assert.equals("procloop", G.ResolveType("button"))
        assert.equals("procloop", G.ResolveType("proc"))
    end)

    it("falls back to the default for nil and for an unknown value", function()
        local G = L.loadAuraGlowRules()
        assert.equals("ants", G.ResolveType(nil))
        assert.equals("ants", G.ResolveType("something-else"))
    end)

    it("passes an already-valid new key through unchanged", function()
        local G = L.loadAuraGlowRules()
        assert.equals("alert", G.ResolveType("alert"))
        assert.equals("procloop", G.ResolveType("procloop"))
    end)
end)

describe("speed normalisation and conversion", function()
    it("converts a mid-range frequency to its period", function()
        local G = L.loadAuraGlowRules()
        assert.equals(4, G.FrequencyToDuration(G.NormaliseFrequency(0.25, 0.05, 2)))
    end)

    -- Direction is the half a test can restate without catching. Getting it
    -- backwards would make a higher Speed animate slower, silently.
    it("makes a HIGHER speed produce a SHORTER duration", function()
        local G = L.loadAuraGlowRules()
        local fast = G.FrequencyToDuration(G.NormaliseFrequency(1, 0.05, 2))
        local slow = G.FrequencyToDuration(G.NormaliseFrequency(0.1, 0.05, 2))
        assert.is_true(fast < slow)
    end)

    it("treats zero, nil and a non-number as the shipped default", function()
        local G = L.loadAuraGlowRules()
        assert.equals(0.25, G.NormaliseFrequency(0, 0.05, 2))
        assert.equals(0.25, G.NormaliseFrequency(nil, 0.05, 2))
        assert.equals(0.25, G.NormaliseFrequency("banana", 0.05, 2))
    end)

    it("clamps to the ADAPTER bounds, not to constants", function()
        local G = L.loadAuraGlowRules()
        assert.equals(2, G.NormaliseFrequency(5, 0.05, 2))
        assert.equals(1, G.NormaliseFrequency(5, 0.05, 1))
        assert.equals(0.05, G.NormaliseFrequency(0.001, 0.05, 2))
    end)

    -- The reason Externals widens its range at all: a stored 0.5s proc
    -- duration is frequency 2, and a maximum of 1 would silently halve it.
    it("preserves a 0.5 second proc period at the widened maximum", function()
        local G = L.loadAuraGlowRules()
        assert.equals(0.5, G.FrequencyToDuration(G.NormaliseFrequency(2, 0.05, 2)))
    end)
end)

describe("speed adapter legacy branch", function()
    local KEYS = { type = "GlowType", frequency = "GlowFrequency", duration = "GlowDuration" }

    it("reads a tuned proc duration back as its frequency", function()
        local G = L.loadAuraGlowRules()
        local db = { GlowType = "proc", GlowDuration = 0.5, GlowFrequency = 0.25 }
        assert.equals(2, G.ReadSpeed(db, KEYS))
    end)

    it("falls through to GlowFrequency when the proc duration is zero", function()
        local G = L.loadAuraGlowRules()
        local db = { GlowType = "proc", GlowDuration = 0, GlowFrequency = 0.5 }
        assert.equals(0.5, G.ReadSpeed(db, KEYS))
    end)

    it("falls through when the duration key is missing", function()
        local G = L.loadAuraGlowRules()
        local db = { GlowType = "proc", GlowFrequency = 0.5 }
        assert.equals(0.5, G.ReadSpeed(db, KEYS))
    end)

    it("ignores the legacy branch for a stored type that is not proc", function()
        local G = L.loadAuraGlowRules()
        local db = { GlowType = "pixel", GlowDuration = 0.5, GlowFrequency = 0.25 }
        assert.equals(0.25, G.ReadSpeed(db, KEYS))
    end)

    -- Writing both together is what retires the legacy branch. Without the
    -- type write the raw value stays proc, the read rule keeps preferring
    -- GlowDuration, and the user's new Speed is read straight back as the old.
    it("writes BOTH the frequency and the coerced type", function()
        local G = L.loadAuraGlowRules()
        local db = { GlowType = "proc", GlowDuration = 0.5, GlowFrequency = 0.25 }
        G.WriteSpeed(db, KEYS, 0.8)
        assert.equals(0.8, db.GlowFrequency)
        assert.equals("procloop", db.GlowType)
    end)

    it("leaves a second read on the written frequency, not the legacy duration", function()
        local G = L.loadAuraGlowRules()
        local db = { GlowType = "proc", GlowDuration = 0.5, GlowFrequency = 0.25 }
        G.WriteSpeed(db, KEYS, 0.8)
        assert.equals(0.8, G.ReadSpeed(db, KEYS))
    end)
end)

describe("glow type settling", function()
    local KEYS = { type = "GlowType", frequency = "GlowFrequency", duration = "GlowDuration" }

    it("preserves a proc user's tuned period as a frequency", function()
        local G = L.loadAuraGlowRules()
        local db = { GlowType = "proc", GlowDuration = 0.5, GlowFrequency = 0.25 }
        G.SetType(db, KEYS, "ants")
        assert.equals("ants", db.GlowType)
        assert.equals(2, db.GlowFrequency)
    end)

    it("leaves an ordinary user's frequency alone", function()
        local G = L.loadAuraGlowRules()
        local db = { GlowType = "pixel", GlowDuration = 1, GlowFrequency = 0.8 }
        G.SetType(db, KEYS, "procloop")
        assert.equals("procloop", db.GlowType)
        assert.equals(0.8, db.GlowFrequency)
    end)

    -- Writes go into the user's profile, so a nil read must never reach one.
    it("writes the default rather than nil when nothing is stored", function()
        local G = L.loadAuraGlowRules()
        local db = { GlowType = "pixel" }
        G.SetType(db, KEYS, "ants")
        assert.equals(0.25, db.GlowFrequency)
    end)

    -- The regression this function exists to prevent: writing the type first
    -- and reading afterwards yields the wrong number.
    it("does not read the speed back through the NEW type", function()
        local G = L.loadAuraGlowRules()
        local db = { GlowType = "proc", GlowDuration = 0.5, GlowFrequency = 0.25 }
        G.SetType(db, KEYS, "alert")
        assert.is_false(db.GlowFrequency == 0.25)
    end)
end)

describe("flipbook restart predicate", function()
    it("restarts when nothing has been applied yet", function()
        local G = L.loadAuraGlowRules()
        local wanted = G.FlipbookState(G.FLIPBOOKS.ants, 1)
        assert.is_true(G.NeedsRestart(nil, wanted))
    end)

    it("restarts on an atlas swap between two styles sharing a grid", function()
        local G = L.loadAuraGlowRules()
        local ants = G.FLIPBOOKS.ants
        local proc = G.FLIPBOOKS.procloop
        assert.equals(ants.rows, proc.rows)
        assert.equals(ants.columns, proc.columns)
        assert.equals(ants.frames, proc.frames)
        assert.is_true(G.NeedsRestart(
            G.FlipbookState(ants, 1), G.FlipbookState(proc, 1)))
    end)

    it("does not restart when only unrelated settings changed", function()
        local G = L.loadAuraGlowRules()
        local applied = G.FlipbookState(G.FLIPBOOKS.ants, 1)
        local wanted  = G.FlipbookState(G.FLIPBOOKS.ants, 1)
        assert.is_false(G.NeedsRestart(applied, wanted))
    end)

    it("restarts when the duration changes", function()
        local G = L.loadAuraGlowRules()
        assert.is_true(G.NeedsRestart(
            G.FlipbookState(G.FLIPBOOKS.ants, 1),
            G.FlipbookState(G.FLIPBOOKS.ants, 2)))
    end)

    it("gives the raw-texture style a real cell size and the atlases none", function()
        local G = L.loadAuraGlowRules()
        assert.equals(48, G.FLIPBOOKS.alert.frameWidth)
        assert.equals(48, G.FLIPBOOKS.alert.frameHeight)
        assert.equals(0, G.FLIPBOOKS.ants.frameWidth)
        assert.equals(0, G.FLIPBOOKS.ants.frameHeight)
        assert.equals(0, G.FLIPBOOKS.procloop.frameWidth)
        assert.equals(0, G.FLIPBOOKS.procloop.frameHeight)
    end)
end)

describe("pixel glow rules", function()
    it("lists all four selectable styles with a kind", function()
        local G = L.loadAuraGlowRules()
        assert.equals("pixel", G.STYLES.pixel.kind)
        assert.equals("flipbook", G.STYLES.ants.kind)
        assert.equals("flipbook", G.STYLES.procloop.kind)
        assert.equals("flipbook", G.STYLES.alert.kind)
    end)

    it("resolves pixel to itself now that it renders again", function()
        local G = L.loadAuraGlowRules()
        assert.equals("pixel", G.ResolveType("pixel"))
    end)

    it("clamps the dash count and defaults a bad one to eight", function()
        local G = L.loadAuraGlowRules()
        assert.equals(8, G.NormalisePixelCount(nil))
        assert.equals(8, G.NormalisePixelCount(0))
        assert.equals(8, G.NormalisePixelCount("not a number"))
        assert.equals(1, G.NormalisePixelCount(1))
        assert.equals(16, G.NormalisePixelCount(99))
        assert.equals(5, G.NormalisePixelCount(5.7))
    end)

    it("clamps the dash thickness and defaults a bad one to one", function()
        local G = L.loadAuraGlowRules()
        assert.equals(1, G.NormalisePixelThickness(nil))
        assert.equals(1, G.NormalisePixelThickness(0))
        assert.equals(8, G.NormalisePixelThickness(99))
        assert.equals(3, G.NormalisePixelThickness(3))
    end)

    it("divides the perimeter into equal dash cycles", function()
        local G = L.loadAuraGlowRules()
        local p = G.PixelPerimeter(8, 40, 40, 4)
        assert.equals(8, p.count)
        -- perimeter 160 over 8 dashes
        assert.equals(20, p.cycle)
        -- one cycle of travel per dash, over the whole period
        assert.equals(0.5, p.step)
    end)

    it("phases each edge by its cumulative perimeter offset in cycles", function()
        local G = L.loadAuraGlowRules()
        local p = G.PixelPerimeter(8, 40, 40, 4)
        assert.equals(0, p.phase[1])
        assert.equals(2, p.phase[2])
        assert.equals(4, p.phase[3])
        assert.equals(6, p.phase[4])
    end)

    it("spans a strip one whole cycle longer than its edge", function()
        local G = L.loadAuraGlowRules()
        local p = G.PixelPerimeter(8, 40, 60, 4)
        -- cycle = 200/8 = 25; horizontal edge 40 long, vertical 60
        assert.equals(25, p.cycle)
        assert.equals((40 + 25) / 25, p.spanH)
        assert.equals((60 + 25) / 25, p.spanV)
    end)

    it("falls back to a sane count when the caller passes rubbish", function()
        local G = L.loadAuraGlowRules()
        local p = G.PixelPerimeter(0, 40, 40, 4)
        assert.equals(8, p.count)
    end)
end)
