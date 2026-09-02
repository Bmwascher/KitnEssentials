-- Tier 2: Core/Globals.lua pure helpers — color resolution, profile-defaults
-- backfill, font-outline filter/options, anchor mappings, healer position
-- matrix, font repair walk. The REAL file loads headless via L.loadGlobals();
-- its fake LSM treats only "Expressway" and "GoodFont" as valid fonts, so
-- repair outcomes ("kept" vs "reset") are distinguishable.
local L = require("dev.spec._ke_loader")

describe("Core/Globals.lua helpers", function()
    local KE
    before_each(function()
        KE = L.loadGlobals()
    end)

    describe("KE:ResolveColor", function()
        it("returns the default 4-tuple when saved is nil", function()
            local r, g, b, a = KE:ResolveColor(nil, { 0.1, 0.2, 0.3, 0.4 })
            assert.equals(0.1, r)
            assert.equals(0.2, g)
            assert.equals(0.3, b)
            assert.equals(0.4, a)
        end)

        it("falls back to alpha 1 when saved is nil and the default has no alpha", function()
            local _, _, _, a = KE:ResolveColor(nil, { 0.1, 0.2, 0.3 })
            assert.equals(1, a)
        end)

        it("fills a sparse AceDB table per index from the default", function()
            -- AceDB stores {[3]=x} when only one channel was edited (:358 comment)
            local r, g, b, a = KE:ResolveColor({ [3] = 0.549 }, { 1, 0, 0, 0.5 })
            assert.equals(1, r)
            assert.equals(0, g)
            assert.equals(0.549, b)
            assert.equals(0.5, a)
        end)

        it("resolves missing alpha via saved[4] → default[4] → 1", function()
            local _, _, _, a1 = KE:ResolveColor({ 0.2, 0.3, 0.4 }, { 0, 0, 0, 0.25 })
            assert.equals(0.25, a1)
            local _, _, _, a2 = KE:ResolveColor({ 0.2, 0.3, 0.4 }, { 0, 0, 0 })
            assert.equals(1, a2)
        end)

        it("ignores the default entirely when saved is complete", function()
            local r, g, b, a = KE:ResolveColor({ 0.9, 0.8, 0.7, 0.6 }, { 0, 0, 0, 0 })
            assert.equals(0.9, r)
            assert.equals(0.8, g)
            assert.equals(0.7, b)
            assert.equals(0.6, a)
        end)
    end)

    describe("KE:FillProfileDefaults", function()
        -- The crash class this prevents (Globals.lua): AceDB's __index
        -- backfill does NOT deep-fill nested sub-tables that already exist in
        -- saved data, so `db.DeathNotifications.FocusDeath.Enabled` crashes
        -- after FocusDeath is added to defaults post-release.
        it("deep-fills a nested key missing from an existing saved sub-table", function()
            KE.db = {
                profile = { DeathNotifications = { Enabled = true } },
                defaults = { profile = { DeathNotifications = {
                    Enabled = false,
                    FocusDeath = { Enabled = true, Sound = "Kick" },
                } } },
            }
            KE:FillProfileDefaults()
            assert.is_true(KE.db.profile.DeathNotifications.FocusDeath.Enabled)
            assert.equals("Kick", KE.db.profile.DeathNotifications.FocusDeath.Sound)
        end)

        it("never overwrites an existing saved value", function()
            KE.db = {
                profile = { FontSize = 20 },
                defaults = { profile = { FontSize = 12 } },
            }
            KE:FillProfileDefaults()
            assert.equals(20, KE.db.profile.FontSize)
        end)

        it("preserves an explicit false (nil check, not truthiness)", function()
            KE.db = {
                profile = { Enabled = false },
                defaults = { profile = { Enabled = true } },
            }
            KE:FillProfileDefaults()
            assert.is_false(KE.db.profile.Enabled)
        end)

        it("creates a missing sub-table as a fresh copy, never an alias of defaults", function()
            -- Aliasing would let later profile writes mutate the shared defaults table.
            KE.db = {
                profile = {},
                defaults = { profile = { Module = { Threshold = 5 } } },
            }
            KE:FillProfileDefaults()
            assert.equals(5, KE.db.profile.Module.Threshold)
            assert.are_not.equal(KE.db.defaults.profile.Module, KE.db.profile.Module)
        end)

        it("replaces a non-table saved value when the default is a table", function()
            -- Globals.lua — the default's SHAPE wins so nested reads can't crash.
            KE.db = {
                profile = { Module = true },
                defaults = { profile = { Module = { Enabled = true } } },
            }
            KE:FillProfileDefaults()
            assert.is_true(KE.db.profile.Module.Enabled)
        end)
    end)

    describe("KE:GetFontOutline", function()
        it("resolves SOFTOUTLINE to a plain outline — the custom renderer it named is gone", function()
            -- The option is still offered and still sits in saved profiles, so
            -- it has to degrade rather than be rejected. Returning "" instead
            -- would silently strip the outline from every text already set to it.
            assert.equals("OUTLINE", KE:GetFontOutline("SOFTOUTLINE"))
        end)

        it("maps NONE, empty string, and nil to \"\"", function()
            assert.equals("", KE:GetFontOutline("NONE"))
            assert.equals("", KE:GetFontOutline(""))
            assert.equals("", KE:GetFontOutline(nil))
        end)

        it("passes real font flags through unchanged", function()
            assert.equals("OUTLINE", KE:GetFontOutline("OUTLINE"))
            assert.equals("THICKOUTLINE", KE:GetFontOutline("THICKOUTLINE"))
            assert.equals("SLUG,OUTLINE", KE:GetFontOutline("SLUG,OUTLINE"))
            assert.equals("MONOCHROME", KE:GetFontOutline("MONOCHROME"))
        end)
    end)

    describe("KE:GetFontOutlineOptions", function()
        local function keysOf(opts)
            local keys = {}
            for i, opt in ipairs(opts) do keys[i] = opt.key end
            return keys
        end

        it("appends MONOCHROME only with includeMono", function()
            local keys = keysOf(KE:GetFontOutlineOptions({ includeMono = true }))
            assert.equals(4, #keys)
            assert.equals("MONOCHROME", keys[4])
        end)

        it("never offers SOFTOUTLINE — the renderer it named is gone", function()
            for _, flags in ipairs({ {}, { includeMono = true }, { includeSoft = true } }) do
                for _, key in ipairs(keysOf(KE:GetFontOutlineOptions(flags))) do
                    assert.are_not.equal("SOFTOUTLINE", key)
                end
            end
        end)
    end)

    describe("KE:ApplyFont — SimpleHTML vs FontString dispatch", function()
        -- Regression: the Communities skin fed a guild MOTD body (a SimpleHTML)
        -- to ApplyFont, which called the FontString form and threw "bad
        -- argument #1". Both object types expose SetFont, so a caller cannot
        -- tell them apart — the branch has to live in this helper.
        local function recorder(isSimpleHTML, throwOn)
            local obj = { calls = {} }
            obj.IsObjectType = function(_, t) return isSimpleHTML and t == "SimpleHTML" end
            obj.SetFont = function(_, ...)
                local args = { ... }
                if throwOn and args[1] == throwOn then error("bad textType", 0) end
                obj.calls[#obj.calls + 1] = args
                return true
            end
            return obj
        end

        it("POSITIVE CONTROL: a FontString still gets the 3-arg form, path first", function()
            local fs = recorder(false)
            KE:ApplyFont(fs, "Expressway", 13, "OUTLINE")
            assert.equals(1, #fs.calls)
            assert.equals(3, #fs.calls[1])
            assert.equals(KE:GetFontPath("Expressway"), fs.calls[1][1])
            assert.equals(13, fs.calls[1][2])
            assert.equals("OUTLINE", fs.calls[1][3])
        end)

        it("a SimpleHTML gets the 4-arg form once per text type, never the 3-arg form", function()
            local html = recorder(true)
            KE:ApplyFont(html, "Expressway", 13, "OUTLINE")
            local types = {}
            for i, call in ipairs(html.calls) do
                assert.equals(4, #call)
                types[i] = call[1]
                assert.equals(KE:GetFontPath("Expressway"), call[2])
                assert.equals(13, call[3])
                assert.equals("OUTLINE", call[4])
            end
            assert.same({ "p", "h1", "h2", "h3" }, types)
        end)

        it("returns true for a SimpleHTML without consulting SetFont's return", function()
            assert.is_true(KE:ApplyFont(recorder(true), "Expressway", 13, "OUTLINE"))
        end)

        it("swallows a rejected text type instead of propagating it", function()
            -- HTMLTextType is not enumerated in the generated API docs, so an
            -- unsupported member must not abort the remaining types.
            local html = recorder(true, "h3")
            assert.has_no.errors(function()
                KE:ApplyFont(html, "Expressway", 13, "OUTLINE")
            end)
            assert.equals(3, #html.calls)
        end)
    end)

    describe("anchor → justify vs anchor → point (deliberate divergence)", function()
        it("TOPRIGHT: justify expands to RIGHT; GetPointFromAnchor deliberately does not (:415)", function()
            assert.equals("RIGHT", KE:GetTextJustifyFromAnchor("TOPRIGHT"))
            assert.equals("RIGHT", KE:GetTextPointFromAnchor("TOPRIGHT"))
            assert.equals("CENTER", KE:GetPointFromAnchor("TOPRIGHT"))
        end)
    end)

    describe("KE:GetActivePositionConfig", function()
        -- Loader default spec stubs report a HEALER role, so the live healer
        -- path is reachable; individual cases reassign the _G stubs (read at
        -- call time) to flip the role.
        local function healerDb()
            return {
                Position = { XOffset = 0 },
                anchorFrameType = "SCREEN",
                ParentFrame = "BaseParent",
                Strata = "MEDIUM",
                UseHealerPosition = true,
                HealerPosition = { XOffset = 50 },
                HealerAnchorFrameType = "SELECTFRAME",
                HealerParentFrame = "HealParent",
                HealerStrata = "HIGH",
            }
        end

        it("uses the healer config live when UseHealerPosition and the spec is a healer", function()
            local db = healerDb()
            local pos, aft, pf, strata = KE:GetActivePositionConfig(db)
            assert.equals(db.HealerPosition, pos)
            assert.equals("SELECTFRAME", aft)
            assert.equals("HealParent", pf)
            assert.equals("HIGH", strata)
        end)

        it("uses the base config live when UseHealerPosition is off, even as a healer", function()
            local db = healerDb()
            db.UseHealerPosition = nil
            local pos, aft, pf, strata = KE:GetActivePositionConfig(db)
            assert.equals(db.Position, pos)
            assert.equals("SCREEN", aft)
            assert.equals("BaseParent", pf)
            assert.equals("MEDIUM", strata)
        end)

        it("uses the base config live for a non-healer spec, even with UseHealerPosition on", function()
            _G.GetSpecializationRole = function() return "DAMAGER" end
            local db = healerDb()
            local pos = KE:GetActivePositionConfig(db)
            assert.equals(db.Position, pos)
        end)

        it("treats no specialization (nil index) as non-healer", function()
            _G.GetSpecialization = function() return nil end
            local db = healerDb()
            local pos = KE:GetActivePositionConfig(db)
            assert.equals(db.Position, pos)
        end)

        it("forceContext HEALER overrides a non-healer live spec", function()
            _G.GetSpecializationRole = function() return "DAMAGER" end
            local db = healerDb()
            local pos = KE:GetActivePositionConfig(db, "HEALER")
            assert.equals(db.HealerPosition, pos)
        end)

        it("forceContext DEFAULT overrides a healer live spec", function()
            local db = healerDb()
            local pos, aft = KE:GetActivePositionConfig(db, "DEFAULT")
            assert.equals(db.Position, pos)
            assert.equals("SCREEN", aft)
        end)

        it("falls back to the base config when the healer context has no HealerPosition", function()
            local db = healerDb()
            db.HealerPosition = nil
            local pos = KE:GetActivePositionConfig(db, "HEALER")
            assert.equals(db.Position, pos)
        end)

        it("falls back per FIELD to the base config for unset Healer* companions", function()
            local db = healerDb()
            db.HealerParentFrame = nil
            db.HealerStrata = nil
            local pos, aft, pf, strata = KE:GetActivePositionConfig(db)
            assert.equals(db.HealerPosition, pos)   -- healer position still wins
            assert.equals("SELECTFRAME", aft)       -- set → healer value
            assert.equals("BaseParent", pf)         -- unset → base value
            assert.equals("MEDIUM", strata)         -- unset → base value
        end)
    end)

    describe("KE:ValidateProfileFonts", function()
        -- Repair rule (Globals.lua): a font KEY is "Font" exactly or
        -- anything ending in "FontFace"; an invalid value repairs to the
        -- per-key default, then to "Expressway" when that default is also
        -- invalid or missing.
        it("repairs an invalid font to its per-key default", function()
            KE.db = {
                profile = { Font = "BadFont" },
                defaults = { profile = { Font = "GoodFont" } },
            }
            KE:ValidateProfileFonts()
            assert.equals("GoodFont", KE.db.profile.Font)
        end)

        it("falls back to Expressway when the per-key default is itself invalid", function()
            KE.db = {
                profile = { Font = "BadFont" },
                defaults = { profile = { Font = "AlsoBadFont" } },
            }
            KE:ValidateProfileFonts()
            assert.equals("Expressway", KE.db.profile.Font)
        end)

        it("falls back to Expressway when no defaults are registered", function()
            KE.db = { profile = { Font = "BadFont" } }
            KE:ValidateProfileFonts()
            assert.equals("Expressway", KE.db.profile.Font)
        end)

        it("keeps a valid font untouched", function()
            KE.db = {
                profile = { Font = "GoodFont" },
                defaults = { profile = { Font = "Expressway" } },
            }
            KE:ValidateProfileFonts()
            assert.equals("GoodFont", KE.db.profile.Font)
        end)

        it("recurses into sub-tables and repairs *FontFace keys against sub-defaults", function()
            KE.db = {
                profile = { Module = { TimerFontFace = "BadFont" } },
                defaults = { profile = { Module = { TimerFontFace = "GoodFont" } } },
            }
            KE:ValidateProfileFonts()
            assert.equals("GoodFont", KE.db.profile.Module.TimerFontFace)
        end)

        it("leaves non-font keys and non-string font values untouched", function()
            KE.db = {
                profile = {
                    Texture = "BadFont",        -- not a font key
                    FontSize = 12,              -- not a font key
                    SubFont = "BadFont",        -- "Font" must match exactly
                    FontFaceStyle = "BadFont",  -- must END in FontFace
                    Font = 42,                  -- font key, but not a string
                },
                defaults = { profile = {} },
            }
            KE:ValidateProfileFonts()
            assert.equals("BadFont", KE.db.profile.Texture)
            assert.equals(12, KE.db.profile.FontSize)
            assert.equals("BadFont", KE.db.profile.SubFont)
            assert.equals("BadFont", KE.db.profile.FontFaceStyle)
            assert.equals(42, KE.db.profile.Font)
        end)

        -- An empty face is not a value, it is a broken one: the repair walk
        -- resolves it to the key's own default.
        it("still repairs an empty font whose per-key default is a real font", function()
            KE.db = {
                profile = { Module = { FontFace = "" } },
                defaults = { profile = { Module = { FontFace = "GoodFont" } } },
            }
            KE:ValidateProfileFonts()
            assert.equals("GoodFont", KE.db.profile.Module.FontFace)
        end)
    end)

    describe("KE:SlugFlags", function()
        -- GetLocale is not managed by _wow_mock, so it lives on _G and is
        -- reassigned per test. Core/Globals.lua calls it inline for exactly
        -- this reason.
        local function enable(locale)
            KE.db = { profile = { UseSlugFonts = true } }
            _G.GetLocale = function() return locale or "enUS" end
        end

        local function disable()
            KE.db = { profile = { UseSlugFonts = false } }
            _G.GetLocale = function() return "enUS" end
        end

        it("slugs plain text — slug is a glyph renderer, not an outline effect", function()
            enable()
            assert.equals("SLUG", KE:SlugFlags(""))
            assert.equals("SLUG", KE:SlugFlags(nil))
        end)

        it("leaves large outlined text unslugged — the stroke scales with the glyph", function()
            enable()
            assert.equals("OUTLINE", KE:SlugFlags("OUTLINE", 32))
        end)

        it("still slugs outlined text at the size ceiling", function()
            enable()
            assert.equals("OUTLINE, SLUG", KE:SlugFlags("OUTLINE", 24))
        end)

        it("slugs large text that carries no outline", function()
            enable()
            assert.equals("SLUG", KE:SlugFlags("", 32))
        end)

        it("slugs outlined text when the caller passes no size", function()
            enable()
            assert.equals("OUTLINE, SLUG", KE:SlugFlags("OUTLINE"))
        end)

        it("KE:ApplyFont hands the size to the gate, not just the outline", function()
            enable()
            local fs = { calls = {} }
            fs.IsObjectType = function() return false end
            fs.SetFont = function(_, ...) fs.calls[#fs.calls + 1] = { ... }; return true end

            KE:ApplyFont(fs, "Expressway", 32, "OUTLINE")
            assert.equals("OUTLINE", fs.calls[1][3])

            KE:ApplyFont(fs, "Expressway", 14, "OUTLINE")
            assert.equals("OUTLINE, SLUG", fs.calls[2][3])
        end)

        it("leaves THICKOUTLINE and MONOCHROME alone — slug renders badly with either", function()
            enable()
            for _, flag in ipairs({ "THICKOUTLINE", "MONOCHROME" }) do
                assert.equals(flag, KE:SlugFlags(flag))
            end
        end)

        it("is idempotent on already-slugged flags", function()
            enable()
            assert.equals("OUTLINE, SLUG", KE:SlugFlags("OUTLINE, SLUG"))
            assert.equals("SLUG,OUTLINE", KE:SlugFlags("SLUG,OUTLINE"))
        end)

        it("strips the concatenated form when disabled", function()
            disable()
            assert.equals("OUTLINE", KE:SlugFlags("OUTLINE, SLUG"))
        end)

        it("strips the leading legacy form when disabled", function()
            disable()
            assert.equals("OUTLINE", KE:SlugFlags("SLUG,OUTLINE"))
        end)

        it("strips a bare SLUG to empty when disabled", function()
            disable()
            assert.equals("", KE:SlugFlags("SLUG"))
        end)

        it("passes non-slug flags through untouched when disabled", function()
            disable()
            assert.equals("OUTLINE", KE:SlugFlags("OUTLINE"))
            assert.equals("", KE:SlugFlags(""))
            assert.is_nil(KE:SlugFlags(nil))
        end)

        it("overrides the setting on locales where slug renders blank", function()
            enable("koKR")
            assert.equals("OUTLINE", KE:SlugFlags("OUTLINE, SLUG"))
            assert.equals("OUTLINE", KE:SlugFlags("OUTLINE"))
        end)

        it("treats a missing db as disabled", function()
            KE.db = nil
            _G.GetLocale = function() return "enUS" end
            assert.equals("OUTLINE", KE:SlugFlags("OUTLINE, SLUG"))
        end)
    end)

    describe("KE:NormalizeFontOutline", function()
        it("maps the retired slug keys to their surviving equivalent", function()
            assert.equals("NONE", KE:NormalizeFontOutline("SLUG"))
            assert.equals("OUTLINE", KE:NormalizeFontOutline("SLUG,OUTLINE"))
            assert.equals("OUTLINE", KE:NormalizeFontOutline("OUTLINE, SLUG"))
        end)

        it("shows a saved SOFTOUTLINE as Outline rather than as a raw key", function()
            -- A dropdown handed a key it has no option for renders the key
            -- itself as the label, so an unmapped stored value would read
            -- "SOFTOUTLINE" in the menu. This is what makes the removal
            -- survive existing profiles without a migration.
            assert.equals("OUTLINE", KE:NormalizeFontOutline("SOFTOUTLINE"))
        end)

        it("passes surviving keys through unchanged", function()
            assert.equals("NONE", KE:NormalizeFontOutline("NONE"))
            assert.equals("OUTLINE", KE:NormalizeFontOutline("OUTLINE"))
            assert.equals("THICKOUTLINE", KE:NormalizeFontOutline("THICKOUTLINE"))
            assert.equals("MONOCHROME", KE:NormalizeFontOutline("MONOCHROME"))
        end)

        it("defaults a nil value to OUTLINE", function()
            assert.equals("OUTLINE", KE:NormalizeFontOutline(nil))
        end)
    end)
end)

describe("KE:RunAfterCombat", function()
    it("runs immediately when out of combat", function()
        local KE = L.loadGlobals()
        _G.InCombatLockdown = function() return false end
        local ran = false
        KE:RunAfterCombat(function() ran = true end)
        assert.is_true(ran)
    end)

    it("queues during combat and drains once on PLAYER_REGEN_ENABLED", function()
        local KE = L.loadGlobals()
        local inCombat = true
        _G.InCombatLockdown = function() return inCombat end
        local runs = 0
        KE:RunAfterCombat(function() runs = runs + 1 end)
        KE:RunAfterCombat(function() runs = runs + 1 end)
        assert.equal(0, runs)
        inCombat = false
        -- fire the helper's PLAYER_REGEN_ENABLED handler off the queue frame
        local f = KE._combatQueueFrame
        f:GetScript("OnEvent")(f, "PLAYER_REGEN_ENABLED")
        assert.equal(2, runs)
        f:GetScript("OnEvent")(f, "PLAYER_REGEN_ENABLED")
        assert.equal(2, runs)  -- queue drained, no double-run
    end)

    it("runs the remaining queued closures when an earlier one errors", function()
        local KE, caughtErrors = L.loadGlobals()
        local inCombat = true
        _G.InCombatLockdown = function() return inCombat end
        local secondRan = false
        KE:RunAfterCombat(function() error("boom") end)
        KE:RunAfterCombat(function() secondRan = true end)
        inCombat = false
        local f = KE._combatQueueFrame
        f:GetScript("OnEvent")(f, "PLAYER_REGEN_ENABLED")
        assert.is_true(secondRan)
        assert.equal(1, #caughtErrors)
        assert.matches("boom", caughtErrors[1])
    end)
end)

describe("KE:GetFontPath global resolution", function()
    local KE

    before_each(function()
        KE = L.loadGlobals()
    end)

    -- The loader's fake LSM returns "path/" .. name for any Fetch, so the
    -- resolved name is readable straight off the returned path.
    it("resolves a nil font name through the global font", function()
        KE.db = { profile = { GlobalFont = "GoodFont" } }
        assert.equals("path/GoodFont", KE:GetFontPath(nil))
    end)

    it("resolves a nil font name to Expressway with no db", function()
        KE.db = nil
        assert.equals("path/Expressway", KE:GetFontPath(nil))
    end)

    it("lets an explicit font name win over the global", function()
        KE.db = { profile = { GlobalFont = "GoodFont" } }
        assert.equals("path/Expressway", KE:GetFontPath("Expressway"))
    end)
end)

describe("KE:GetEffectiveFont", function()
    local KE

    before_each(function()
        KE = L.loadGlobals()
    end)

    -- Precedence, not just presence: a table carrying all three must return
    -- the FIRST key. Three separate single-key tests cannot catch a helper
    -- that reads them in the wrong order.
    it("reads the three keys in FontFace, Font, fontFace order", function()
        assert.equals("A", KE:GetEffectiveFont({ FontFace = "A", Font = "B", fontFace = "C" }))
        assert.equals("B", KE:GetEffectiveFont({ Font = "B", fontFace = "C" }))
    end)

    -- nil, not a face: the value flows into KE:GetFontPath, which resolves an
    -- unset name through the global font.
    it("returns nil for a nil table", function()
        assert.is_nil(KE:GetEffectiveFont(nil))
    end)

    it("returns nil for a table with no font key", function()
        assert.is_nil(KE:GetEffectiveFont({ Size = 12 }))
    end)
end)

describe("KE:StoredFontFace", function()
    local KE

    before_each(function()
        KE = L.loadGlobals()
    end)

    -- Locks the nil return; KE:StoredFontFace carries why it cannot be an
    -- and/or expression.
    it("stores nil for the sentinel", function()
        assert.is_nil(KE:StoredFontFace(KE.FONT_FOLLOW_GLOBAL))
    end)
end)

describe("KE:AddFollowGlobalFont", function()
    local KE

    local function arrayList()
        return { { key = "Arial", text = "Arial" }, { key = "Zapf", text = "Zapf" } }
    end

    before_each(function()
        KE = L.loadGlobals()
        KE.db = { profile = { GlobalFont = "GoodFont" } }
    end)

    it("labels the entry with the current global font", function()
        local list = KE:AddFollowGlobalFont({ Arial = "Arial" })
        assert.equals("Use Global Font (GoodFont)", list[KE.FONT_FOLLOW_GLOBAL])
    end)

    it("prefers an explicit effectiveName over the global font", function()
        local list = KE:AddFollowGlobalFont({ Arial = "Arial" }, "Naowh")
        assert.equals("Use Global Font (Naowh)", list[KE.FONT_FOLLOW_GLOBAL])
    end)

    it("returns the same table it was given", function()
        local list = { Arial = "Arial" }
        assert.equals(list, KE:AddFollowGlobalFont(list))
    end)

    it("leaves existing entries untouched", function()
        local list = KE:AddFollowGlobalFont({ Arial = "Arial" })
        assert.equals("Arial", list.Arial)
    end)

    it("builds a list when given nil", function()
        local list = KE:AddFollowGlobalFont(nil)
        assert.equals("Use Global Font (GoodFont)", list[KE.FONT_FOLLOW_GLOBAL])
    end)

    -- Asserted on SHAPE, not merely on presence; KE:AddFollowGlobalFont carries
    -- why a hash key on an array-shaped list never renders.
    describe("array-shaped lists", function()
        it("inserts at index 1, ahead of the sorted faces", function()
            local list = KE:AddFollowGlobalFont(arrayList())
            assert.equals(KE.FONT_FOLLOW_GLOBAL, list[1].key)
            assert.equals("Use Global Font (GoodFont)", list[1].text)
        end)

        it("does not also write a hash key", function()
            local list = KE:AddFollowGlobalFont(arrayList())
            assert.is_nil(list[KE.FONT_FOLLOW_GLOBAL])
        end)

        it("keeps the existing entries and their order", function()
            local list = KE:AddFollowGlobalFont(arrayList())
            assert.equals(3, #list)
            assert.equals("Arial", list[2].key)
            assert.equals("Zapf", list[3].key)
        end)
    end)

    describe("hash-shaped lists", function()
        it("gains no array element", function()
            local list = KE:AddFollowGlobalFont({ Arial = "Arial" })
            assert.equals(0, #list)
        end)

        it("treats an empty list as a hash", function()
            local list = KE:AddFollowGlobalFont({})
            assert.equals(0, #list)
            assert.equals("Use Global Font (GoodFont)", list[KE.FONT_FOLLOW_GLOBAL])
        end)
    end)
end)
