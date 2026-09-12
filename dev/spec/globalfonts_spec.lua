-- Modules/Skinning/GlobalFonts.lua -- the Platynator guard and the stock-size
-- snapshot. Apply() is the
-- refusal surface: it must write nothing while Platynator is loaded, since
-- that addon's nameplate setup breaks once the sweep has rewritten
-- GameFontNormal. Loaded directly (not through dev/spec/_ke_loader.lua): the
-- module needs a _G font-object fake and a KE.Skins seed the loader has no
-- shape for. C_AddOns.IsAddOnLoaded is a constant stub per case, not a
-- stateful fake -- the guard reads it once per Apply.
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
    local S, applied, planted

    local function load(loadedAddOns)
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
        local KE = {
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
    end)

    it("writes nothing while Platynator is loaded", function()
        load({ Platynator = true })
        assert.equals("Platynator", S.GlobalFontsBlockedBy())
        S.ApplyGlobalFonts()
        assert.is_nil(next(applied))
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
end)
