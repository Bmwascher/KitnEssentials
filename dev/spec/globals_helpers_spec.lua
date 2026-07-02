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
        -- The crash class this prevents (Globals.lua:329): AceDB's __index
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
            -- Globals.lua:340 — the default's SHAPE wins so nested reads can't crash.
            KE.db = {
                profile = { Module = true },
                defaults = { profile = { Module = { Enabled = true } } },
            }
            KE:FillProfileDefaults()
            assert.is_true(KE.db.profile.Module.Enabled)
        end)

        it("is a no-op without db or without registered defaults", function()
            KE.db = nil
            assert.has_no.errors(function() KE:FillProfileDefaults() end)
            KE.db = { profile = { Keep = 1 } }
            KE:FillProfileDefaults()
            assert.equals(1, KE.db.profile.Keep)
        end)
    end)

    describe("KE:GetFontOutline", function()
        it("filters SOFTOUTLINE to \"\" — invariant: KE's soft outline is a custom 8-shadow system, never a real font flag", function()
            assert.equals("", KE:GetFontOutline("SOFTOUTLINE"))
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

        it("returns the 5 universal modes with no flags", function()
            assert.same(
                { "NONE", "OUTLINE", "THICKOUTLINE", "SLUG", "SLUG,OUTLINE" },
                keysOf(KE:GetFontOutlineOptions())
            )
        end)

        it("appends SOFTOUTLINE only with includeSoft", function()
            local keys = keysOf(KE:GetFontOutlineOptions({ includeSoft = true }))
            assert.equals(6, #keys)
            assert.equals("SOFTOUTLINE", keys[6])
        end)

        it("appends MONOCHROME only with includeMono", function()
            local keys = keysOf(KE:GetFontOutlineOptions({ includeMono = true }))
            assert.equals(6, #keys)
            assert.equals("MONOCHROME", keys[6])
        end)

        it("orders soft before mono when both flags are set", function()
            local keys = keysOf(KE:GetFontOutlineOptions({ includeSoft = true, includeMono = true }))
            assert.equals(7, #keys)
            assert.equals("SOFTOUTLINE", keys[6])
            assert.equals("MONOCHROME", keys[7])
        end)
    end)

    describe("anchor → justify vs anchor → point (deliberate divergence)", function()
        it("TOPRIGHT: justify expands to RIGHT; GetPointFromAnchor deliberately does not (:415)", function()
            assert.equals("RIGHT", KE:GetTextJustifyFromAnchor("TOPRIGHT"))
            assert.equals("RIGHT", KE:GetTextPointFromAnchor("TOPRIGHT"))
            assert.equals("CENTER", KE:GetPointFromAnchor("TOPRIGHT"))
        end)

        it("expands all corner anchors on the justify side only", function()
            assert.equals("LEFT", KE:GetTextJustifyFromAnchor("BOTTOMLEFT"))
            assert.equals("CENTER", KE:GetPointFromAnchor("BOTTOMLEFT"))
            assert.equals("RIGHT", KE:GetTextJustifyFromAnchor("BOTTOMRIGHT"))
            assert.equals("CENTER", KE:GetPointFromAnchor("BOTTOMRIGHT"))
        end)

        it("agrees on plain LEFT/RIGHT and on the CENTER fallback", function()
            assert.equals("LEFT", KE:GetTextJustifyFromAnchor("LEFT"))
            assert.equals("LEFT", KE:GetPointFromAnchor("LEFT"))
            assert.equals("RIGHT", KE:GetTextJustifyFromAnchor("RIGHT"))
            assert.equals("RIGHT", KE:GetPointFromAnchor("RIGHT"))
            assert.equals("CENTER", KE:GetTextJustifyFromAnchor("TOP"))
            assert.equals("CENTER", KE:GetPointFromAnchor("TOP"))
            assert.equals("CENTER", KE:GetTextJustifyFromAnchor(nil))
            assert.equals("CENTER", KE:GetPointFromAnchor(nil))
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
        -- Repair rule (Globals.lua:308): a font KEY is "Font" exactly or
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

        it("is a no-op without db", function()
            KE.db = nil
            assert.has_no.errors(function() KE:ValidateProfileFonts() end)
        end)
    end)
end)
