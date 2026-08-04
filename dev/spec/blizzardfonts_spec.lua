-- Modules/Skinning/BlizzardFonts.lua -- game-wide replacement of Blizzard's
-- shared font OBJECTS. Loaded directly (not through dev/spec/_ke_loader.lua)
-- because the module needs _G font-object fakes the loader has no shape for
-- -- see fontObject() below. KE.GetFontOutline and KE.FONT are stubbed here
-- rather than pulled from a real Core/Globals.lua load: the boundary under
-- test is whether BlizzardFonts CALLS them correctly, not what they compute
-- (Core/Globals.lua's own spec already covers GetFontOutline's filter).
local helpers = require("dev.spec._helpers")

-- A stand-in for a Blizzard font OBJECT. Records what the sweep writes and
-- reports a known "stock" state so the restore round-trip is checkable.
local function fontObject(path, size, flags)
    local o = {
        _font = { path, size, flags },
        _shadowColor = { 0, 0, 0, 1 },
        _shadowOffset = { 1, -1 },
    }
    function o:GetFont() return self._font[1], self._font[2], self._font[3] end
    function o:SetFont(p, s, f) self._font = { p, s, f } end
    function o:GetShadowColor() return unpack(self._shadowColor) end
    function o:SetShadowColor(r, g, b, a) self._shadowColor = { r, g, b, a } end
    function o:GetShadowOffset() return unpack(self._shadowOffset) end
    function o:SetShadowOffset(x, y) self._shadowOffset = { x, y } end
    return o
end

describe("BlizzardFonts", function()
    local KE, BF, planted

    -- Mirrors Core/Globals.lua's filter exactly (nil/""/"NONE"/
    -- "SOFTOUTLINE" collapse to "", everything else passes through), so
    -- assertions can tell OUTLINE/THICKOUTLINE apart from the collapsed case.
    local function stubOutline(_, outline)
        if not outline or outline == "" or outline == "NONE" or outline == "SOFTOUTLINE" then
            return ""
        end
        return outline
    end

    -- Loads a fresh copy of the module (new `originals` upvalue each time)
    -- against a hand-built KE. dbOverrides may replace BlizzardFonts and/or
    -- BlizzardFrames; anything not given falls back to a sane default.
    local function load(dbOverrides)
        dbOverrides = dbOverrides or {}
        local modules = helpers.installAddonShim()
        KE = {
            FONT = "Fonts\\Expressway.TTF",
            ShouldNotLoadModule = function() return false end,
            GetFontOutline = stubOutline,
            db = {
                profile = {
                    Skinning = {
                        BlizzardFonts = dbOverrides.BlizzardFonts or { Enabled = true, Sizes = {} },
                        BlizzardFrames = dbOverrides.BlizzardFrames or { FontBaseSize = 12 },
                    },
                },
            },
        }
        helpers.loadModule("Modules/Skinning/BlizzardFonts.lua", KE)
        BF = modules["BlizzardFonts"]
        return KE, BF
    end

    -- Plants a fake font object on _G and remembers the name so after_each
    -- can strike it back off -- busted insulates _G per FILE, not per test
    -- (dev/spec/_ke_loader.lua), and every describe below shares one.
    local function plant(name, obj)
        _G[name] = obj
        planted[#planted + 1] = name
        return obj
    end

    before_each(function()
        planted = {}
    end)

    after_each(function()
        for _, name in ipairs(planted) do
            _G[name] = nil
        end
    end)

    describe("base-size scaling", function()
        -- SystemFont_Med3 { "SystemFont_Med3", 14 }: stock 14, no CATEGORY
        -- entry, no outline kind -- isolates the scale math from both the
        -- category-override branch and the outline mapping.
        it("writes a 14pt entry at 14 when FontBaseSize is the stock 12", function()
            load({ BlizzardFrames = { FontBaseSize = 12 } })
            local obj = plant("SystemFont_Med3", fontObject("Fonts\\FRIZQT__.TTF", 10, ""))
            BF:ApplyAll()
            local _, size = obj:GetFont()
            assert.equals(14, size)
        end)

        it("POSITIVE CONTROL: scales the same 14pt entry to 21 at FontBaseSize 18", function()
            load({ BlizzardFrames = { FontBaseSize = 18 } })
            local obj = plant("SystemFont_Med3", fontObject("Fonts\\FRIZQT__.TTF", 10, ""))
            BF:ApplyAll()
            local _, size = obj:GetFont()
            assert.equals(21, size)   -- floor(14 * 18 / 12 + 0.5)
        end)
    end)

    describe("category override", function()
        -- ObjectiveFont { "ObjectiveFont", 12, "S" }: CATEGORY maps it to
        -- "Objective", so a Sizes.Objective override must win over scaling.
        it("wins over scaling: writes the override 9, not the scaled 18", function()
            load({
                BlizzardFonts = { Enabled = true, Sizes = { Objective = 9 } },
                BlizzardFrames = { FontBaseSize = 18 },
            })
            local obj = plant("ObjectiveFont", fontObject("Fonts\\FRIZQT__.TTF", 10, ""))
            BF:ApplyAll()
            local _, size = obj:GetFont()
            assert.equals(9, size)
        end)

        it("scales again once the override is removed", function()
            load({
                BlizzardFonts = { Enabled = true, Sizes = {} },
                BlizzardFrames = { FontBaseSize = 18 },
            })
            local obj = plant("ObjectiveFont", fontObject("Fonts\\FRIZQT__.TTF", 10, ""))
            BF:ApplyAll()
            local _, size = obj:GetFont()
            assert.equals(18, size)   -- floor(12 * 18 / 12 + 0.5), no override left
        end)
    end)

    describe("outline kinds", function()
        before_each(function() load() end)

        it("maps an O entry to OUTLINE", function()
            local obj = plant("ObjectiveTrackerHeaderFont", fontObject("Fonts\\FRIZQT__.TTF", 10, ""))
            BF:ApplyAll()
            local _, _, flags = obj:GetFont()
            assert.equals("OUTLINE", flags)
        end)

        it("maps a T entry to THICKOUTLINE", function()
            local obj = plant("NumberFont_Outline_Huge", fontObject("Fonts\\FRIZQT__.TTF", 10, ""))
            BF:ApplyAll()
            local _, _, flags = obj:GetFont()
            assert.equals("THICKOUTLINE", flags)
        end)

        it("maps an S entry to the empty flag", function()
            local obj = plant("ObjectiveFont", fontObject("Fonts\\FRIZQT__.TTF", 10, ""))
            BF:ApplyAll()
            local _, _, flags = obj:GetFont()
            assert.equals("", flags)
        end)

        -- Same empty flag as S -- if a future edit gave flagless entries
        -- their own distinct treatment, this is what would notice.
        it("maps a flagless entry to the same empty flag as S", function()
            local obj = plant("SystemFont_Med3", fontObject("Fonts\\FRIZQT__.TTF", 10, ""))
            BF:ApplyAll()
            local _, _, flags = obj:GetFont()
            assert.equals("", flags)
        end)
    end)

    describe("shadow zeroing", function()
        before_each(function() load() end)

        it("zeroes shadow colour and offset on an O-kind entry", function()
            local obj = plant("ObjectiveTrackerHeaderFont", fontObject("Fonts\\FRIZQT__.TTF", 10, ""))
            BF:ApplyAll()
            assert.same({ 0, 0, 0, 0 }, obj._shadowColor)
            assert.same({ 0, 0 }, obj._shadowOffset)
        end)

        it("zeroes shadow colour and offset on an S-kind entry too", function()
            local obj = plant("ObjectiveFont", fontObject("Fonts\\FRIZQT__.TTF", 10, ""))
            BF:ApplyAll()
            assert.same({ 0, 0, 0, 0 }, obj._shadowColor)
            assert.same({ 0, 0 }, obj._shadowOffset)
        end)
    end)

    describe("restore round-trip", function()
        it("restores font, shadow colour and offset exactly, twice over", function()
            load()
            -- QuestFont { "QuestFont", 13 }: CATEGORY maps it to "QuestText",
            -- but Sizes is empty here, so it scales to its own stock 13 at
            -- the default FontBaseSize 12 -- an identity scale that keeps
            -- this test about restore, not about the size math.
            local obj = plant("QuestFont", fontObject("Fonts\\FRIZQT__.TTF", 13, ""))
            local stockPath, stockSize, stockFlags = obj:GetFont()
            local sr, sg, sb, sa = obj:GetShadowColor()
            local sx, sy = obj:GetShadowOffset()

            BF:ApplyAll()
            BF:RestoreAll()
            local p1, s1, f1 = obj:GetFont()
            assert.same({ stockPath, stockSize, stockFlags }, { p1, s1, f1 })
            assert.same({ sr, sg, sb, sa }, { obj:GetShadowColor() })
            assert.same({ sx, sy }, { obj:GetShadowOffset() })

            -- Second sweep: `originals` must still hold the ORIGINAL stock
            -- values, not the values the first ApplyAll wrote, or this
            -- second restore would land on the post-sweep font instead.
            BF:ApplyAll()
            BF:RestoreAll()
            local p2, s2, f2 = obj:GetFont()
            assert.same({ stockPath, stockSize, stockFlags }, { p2, s2, f2 })
            assert.same({ sr, sg, sb, sa }, { obj:GetShadowColor() })
            assert.same({ sx, sy }, { obj:GetShadowOffset() })
        end)
    end)

    describe("disabled", function()
        it("ApplyAll writes nothing", function()
            load({ BlizzardFonts = { Enabled = false, Sizes = {} } })
            local obj = plant("QuestFont", fontObject("Fonts\\FRIZQT__.TTF", 13, ""))
            BF:ApplyAll()
            local p, s, f = obj:GetFont()
            assert.same({ "Fonts\\FRIZQT__.TTF", 13, "" }, { p, s, f })
        end)
    end)

    describe("missing font object", function()
        it("is skipped, not an error, and its neighbour still gets styled", function()
            load()
            -- MailTextFontNormal (also in FONT_LIST) is deliberately left
            -- unplanted: its _G slot is nil.
            local obj = plant("QuestFont", fontObject("Fonts\\FRIZQT__.TTF", 13, ""))
            assert.has_no.errors(function() BF:ApplyAll() end)
            local _, size = obj:GetFont()
            assert.equals(13, size)
        end)
    end)
end)
