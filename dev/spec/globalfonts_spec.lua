-- Modules/Skinning/GlobalFonts.lua -- the Platynator guard. Apply() is the
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

describe("GlobalFonts Platynator guard", function()
    local S, applied, planted

    local function load(loadedAddOns)
        _G.C_AddOns = { IsAddOnLoaded = function(name) return loadedAddOns[name] == true end }
        applied = {}
        S = { FONT_FACE = "Expressway", RegisterEarly = function() end }
        local KE = {
            Skins = S,
            ApplyFont = function(_, obj, face, size, flags)
                applied[obj] = { face, size, flags }
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
        _G.C_AddOns = nil
    end)

    it("writes nothing while Platynator is loaded", function()
        load({ Platynator = true })
        assert.equals("Platynator", S.GlobalFontsBlockedBy())
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
end)
