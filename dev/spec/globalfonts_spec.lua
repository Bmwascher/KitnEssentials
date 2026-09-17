-- Modules/Skinning/GlobalFonts.lua -- the three refusals and the stock-size
-- snapshot. Apply() is the refusal surface: it must write nothing while
-- Platynator is loaded, since that addon's nameplate setup breaks once the
-- sweep has rewritten GameFontNormal, nothing while EllesmereUI's Apply to
-- All Game Text is on, since that rewrites every font object after this
-- sweep, and nothing while the frame-skin module is off. Loaded directly
-- (not through dev/spec/_ke_loader.lua): the module needs a _G font-object
-- fake and a KE.Skins seed the loader has no shape for.
-- C_AddOns.IsAddOnLoaded is a constant stub per case, not a stateful fake --
-- the guard reads it once per Apply.
local helpers = require("dev.spec._helpers")

local function fontObject(path, size, flags)
    local o = { _font = { path, size, flags } }
    function o:GetFont() return self._font[1], self._font[2], self._font[3] end
    function o:SetFont(p, s, f) self._font = { p, s, f } end
    function o:GetShadowColor() return 0, 0, 0, 1 end
    function o:SetShadowColor() end
    return o
end

-- An object with no height of its own reads its XML parent's font until it is
-- given one. That runtime propagation IS the defect the snapshot outruns, so a
-- fake without it cannot fail the case below.
local function childFontObject(parent)
    local o = { _font = nil }
    function o:GetFont()
        local f = self._font or { parent:GetFont() }
        return f[1], f[2], f[3]
    end
    function o:SetFont(p, s, f) self._font = { p, s, f } end
    function o:GetShadowColor() return 0, 0, 0, 1 end
    function o:SetShadowColor() end
    return o
end

describe("GlobalFonts", function()
    local S, KE, applied, planted

    -- The module creates its login watcher at file scope, so loading it needs a
    -- frame constructor. A no-op double is enough: what the watcher registers
    -- and when it fires are in-game concerns, and nothing here asserts on them.
    local function frameDouble()
        return {
            RegisterEvent = function() end,
            UnregisterEvent = function() end,
            UnregisterAllEvents = function() end,
            SetScript = function() end,
        }
    end

    local function load(loadedAddOns)
        _G.CreateFrame = function() return frameDouble() end
        _G.C_AddOns = { IsAddOnLoaded = function(name) return loadedAddOns[name] == true end }
        applied = {}
        S = {
            FONT_FACE = "Expressway",
            RegisterEarly = function() end,
            IsActive = function() return true end,
            -- SkinAPI owns the face rule and skinapi_spec covers it; this
            -- module's concern is which objects it writes and at what size.
            ResolveSkinFace = function() return "Expressway" end,
        }
        KE = {
            Skins = S,
            -- Writes as well as records: the real helper calls SetFont, and
            -- without that the parent never propagates to its child.
            ApplyFont = function(_, obj, face, size, flags)
                applied[obj] = { face, size, flags }
                obj:SetFont(face, size, flags)
            end,
            db = { profile = { Skinning = { BlizzardFrames = { FontBaseSize = 14 } } } },
        }
        helpers.loadModule("Modules/Skinning/GlobalFonts.lua", KE)
    end

    before_each(function()
        planted = fontObject("Fonts\\FRIZQT__.TTF", 12, "")
        _G.GameFontNormal = planted
    end)

    after_each(function()
        _G.GameFontNormal = nil
        _G.GameFontDisable = nil
        _G.C_AddOns = nil
        _G.CreateFrame = nil
    end)

    it("writes nothing while Platynator is loaded", function()
        load({ Platynator = true })
        assert.equals("Platynator", (S.GlobalFontsBlockedBy()))
        S.ApplyGlobalFonts()
        assert.is_nil(next(applied))
    end)

    it("writes nothing while EllesmereUI's Apply to All Game Text is on", function()
        load({})
        _G.EllesmereUIDB = { fonts = { applyToAllGameText = true } }
        assert.equals("EllesmereUI", (S.GlobalFontsBlockedBy()))
        S.ApplyGlobalFonts()
        assert.is_nil(next(applied))
        _G.EllesmereUIDB = nil
    end)

    it("writes nothing while the frame-skin module is off", function()
        load({})
        S.IsActive = function() return false end
        S.ApplyGlobalFonts()
        assert.is_nil(next(applied))
    end)

    it("sweeps when Platynator is absent", function()
        load({})
        assert.is_nil(S.GlobalFontsBlockedBy())
        S.ApplyGlobalFonts()
        assert.is_not_nil(applied[planted])
        assert.equals("Expressway", applied[planted][1])
    end)

    -- GameFontDisable inherits GameFontNormal and declares no height, so it
    -- follows whatever is written to the parent. A stock size read after that
    -- write is a scaled size, and scaling it again is what split the pair.
    it("does not rescale a child that followed its parent's swept size", function()
        local child = childFontObject(planted)
        _G.GameFontDisable = child
        load({})
        S.ApplyGlobalFonts()
        assert.equals(14, applied[planted][2])
        assert.equals(14, applied[child][2])
    end)

    -- The other sweep owns objects that are parents of these, and it writes on
    -- its own schedule. Once stock is taken, a foreign write to a parent must
    -- not reach this sweep's arithmetic.
    it("keeps the stock it snapshotted when another writer moves a parent", function()
        local child = childFontObject(planted)
        _G.GameFontDisable = child
        load({})
        S.SnapshotGlobalFontStock()
        planted:SetFont("Fonts\\Other.TTF", 20, "")
        S.ApplyGlobalFonts()
        assert.equals(14, applied[child][2])
    end)

    -- Standing down is only worth telling the player about when it cost them
    -- something: the refusals below keep the notice off profiles that lost nothing.
    describe("stand-down notice", function()
        local frames

        local function block()
            _G.EllesmereUIDB = { fonts = { applyToAllGameText = true } }
        end

        before_each(function()
            load({})
            frames = { FontBaseSize = 14 }
            KE.db.profile.Skinning.BlizzardFrames = frames
        end)

        after_each(function() _G.EllesmereUIDB = nil end)

        it("is due while a blocker holds the fonts and the row is on", function()
            block()
            local blocker, remedy = S.GlobalFontsNoticeDue()
            assert.equals("EllesmereUI", blocker)
            assert.is_string(remedy)
        end)

        -- With the frame-skin module off the sweep would not have run anyway,
        -- so yielding took nothing away.
        it("is not due while the frame-skin module is off", function()
            block()
            S.IsActive = function() return false end
            assert.is_nil(S.GlobalFontsNoticeDue())
        end)

        it("is not due while the per-row Global Fonts toggle is off", function()
            block()
            frames.Skins = { GlobalFonts = false }
            assert.is_nil(S.GlobalFontsNoticeDue())
        end)

        it("is not due once the notice has been delivered", function()
            block()
            frames._globalFontsBlockedWarned = true
            assert.is_nil(S.GlobalFontsNoticeDue())
        end)

        -- Both switches are off on purpose: with them on, a predicate that
        -- checked them before the blocker would still clear the flag and this
        -- case would pass. Off, it keeps a stale flag and never warns again.
        it("clears the delivered flag once the block has lifted, switches off too", function()
            S.IsActive = function() return false end
            frames.Skins = { GlobalFonts = false }
            frames._globalFontsBlockedWarned = true
            assert.is_nil(S.GlobalFontsNoticeDue())
            assert.is_nil(frames._globalFontsBlockedWarned)
        end)

        it("refuses without writing when the frame-skin table is missing", function()
            block()
            KE.db.profile.Skinning.BlizzardFrames = nil
            assert.is_nil(S.GlobalFontsNoticeDue())
        end)
    end)
end)
