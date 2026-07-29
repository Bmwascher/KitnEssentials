-- Tier 2: Modules/Skinning/SkinAPI.lua. Covers the three pieces of this file
-- that are pure enough to test headlessly: the per-frame border math, the
-- secret-value guards, and the theme palette mapping. Everything that dresses
-- a live frame is out of reach here and is verified in-game (spec §8.4).
local L = require("dev.spec._ke_loader")

describe("SkinAPI EdgeFor", function()
    local S
    before_each(function() S = L.loadSkinAPI().Skins end)

    it("returns one physical pixel at UIParent scale", function()
        -- physH 1440, uiScale 1 -> 768/1440
        local bd = { GetEffectiveScale = function() return 1 end }
        assert.near(768 / 1440, S._EdgeFor(bd), 1e-9)
    end)

    it("divides by the frame's scale factor above UIParent", function()
        local bd = { GetEffectiveScale = function() return 1.1 end }
        assert.near((768 / 1440) / 1.1, S._EdgeFor(bd), 1e-9)
    end)

    it("divides by a sub-unity scale factor too", function()
        local bd = { GetEffectiveScale = function() return 0.8 end }
        assert.near((768 / 1440) / 0.8, S._EdgeFor(bd), 1e-9)
    end)

    it("falls back to the UIParent value when the scale read is missing", function()
        assert.near(768 / 1440, S._EdgeFor({}), 1e-9)
    end)

    it("falls back to the UIParent value when the scale is zero", function()
        local bd = { GetEffectiveScale = function() return 0 end }
        assert.near(768 / 1440, S._EdgeFor(bd), 1e-9)
    end)
end)

describe("SkinAPI secret guards", function()
    local S
    before_each(function()
        S = L.loadSkinAPI({
            issecretvalue = function(v) return v == "SECRET" end,
        }).Skins
    end)

    it("passes a clean rect straight through", function()
        local f = { GetRect = function() return 1, 2, 3, 4 end }
        local l, b, w, h = S.SafeRect(f)
        assert.same({ 1, 2, 3, 4 }, { l, b, w, h })
    end)

    it("returns nil when any rect component is secret", function()
        for i = 1, 4 do
            local vals = { 1, 2, 3, 4 }
            vals[i] = "SECRET"
            local f = { GetRect = function() return vals[1], vals[2], vals[3], vals[4] end }
            assert.is_nil(S.SafeRect(f))
        end
    end)

    it("returns nil when the frame has no GetRect", function()
        assert.is_nil(S.SafeRect({}))
        assert.is_nil(S.SafeRect(nil))
    end)

    it("returns nil when GetRect yields nothing", function()
        assert.is_nil(S.SafeRect({ GetRect = function() return nil end }))
    end)

    it("passes a clean size straight through", function()
        local f = { GetSize = function() return 10, 20 end }
        local w, h = S.SafeSize(f)
        assert.same({ 10, 20 }, { w, h })
    end)

    it("returns nil when either size component is secret", function()
        assert.is_nil(S.SafeSize({ GetSize = function() return "SECRET", 20 end }))
        assert.is_nil(S.SafeSize({ GetSize = function() return 10, "SECRET" end }))
    end)
end)

describe("SkinAPI palette", function()
    local KE, S
    before_each(function()
        KE = L.loadSkinAPI()
        S = KE.Skins
    end)

    it("keeps the reference greys verbatim", function()
        assert.same({ 0.031, 0.031, 0.031, 0.80 }, S.palette.window)
        assert.same({ 0.055, 0.055, 0.055, 0.90 }, S.palette.control)
        assert.same({ 0.06, 0.06, 0.06, 0.80 }, S.palette.panel)
        assert.same({ 0, 0, 0, 0.25 }, S.palette.inlineTint)
        assert.same({ 0, 0, 0, 1 }, S.palette.border)
    end)

    it("keeps the reference brand alphas verbatim", function()
        assert.equals(0.8, S.palette.brandFillA)
        assert.equals(0.35, S.palette.brandRestA)
    end)

    it("takes brand rgb from the theme accent", function()
        assert.near(1.0, S.palette.brand[1], 1e-9)
        assert.near(0.0, S.palette.brand[2], 1e-9)
        assert.near(0.549, S.palette.brand[3], 1e-9)
    end)

    it("keeps the reference hover wash verbatim, rgb included", function()
        -- Was themed from accentHover. Because accent and accentHover share
        -- one rgb and differ only in alpha, that made hover identical to
        -- brand and every rest/hover pair invisible. armHover applies 0.15
        -- separately, so a themed alpha would double-apply on top.
        assert.same({ 0.851, 0.851, 0.851, 0.15 }, S.palette.hover)
    end)

    it("never lets the hover wash collapse onto the brand colour", function()
        -- The regression this guards: a mouseover state the same colour as
        -- the resting state reads in-game as no mouseover at all.
        local h, b = S.palette.hover, S.palette.brand
        assert.is_false(h[1] == b[1] and h[2] == b[2] and h[3] == b[3])
    end)

    it("gives progress the accent rgb at alpha 0.40", function()
        assert.near(1.0, S.palette.progress[1], 1e-9)
        assert.equals(0.40, S.palette.progress[4])
    end)

    it("mutates colour tables in place so file-scope captures stay live", function()
        -- brand is captured by BRAND_HL and CLOSE_HOVER, hover by
        -- HOVER_COLOR. Both tables must keep their identity across a refresh
        -- or those captures hold an orphan.
        local capturedBrand = S.palette.brand
        local capturedHover = S.palette.hover
        KE.GetThemeColor = function(_, key)
            if key == "accent" then return { 0.0, 1.0, 0.5, 1 } end
            return { 0.2, 0.4, 0.6, 0.25 }
        end
        S.RefreshPalette()
        assert.are.equal(capturedBrand, S.palette.brand)
        assert.are.equal(capturedHover, S.palette.hover)
        assert.near(0.0, capturedBrand[1], 1e-9)
        assert.near(1.0, capturedBrand[2], 1e-9)
        assert.near(0.5, capturedBrand[3], 1e-9)
        -- A refresh themes brand and progress only; the hover wash is
        -- neutral by design and no accent may reach it.
        assert.same({ 0.851, 0.851, 0.851, 0.15 }, capturedHover)
    end)
end)

describe("SkinAPI WaitFor", function()
    local S, timers

    before_each(function()
        timers = {}
        S = L.loadSkinAPI({
            C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end },
        }).Skins
    end)

    local function pump(n)
        for _ = 1, n do
            local queued = timers
            timers = {}
            for _, fn in ipairs(queued) do fn() end
        end
    end

    it("runs immediately when the check already passes", function()
        local ran = false
        S.WaitFor(function() return true end, function() ran = true end)
        assert.is_true(ran)
        assert.equals(0, #timers)   -- no poll was queued
    end)

    it("polls until the check passes, then runs once", function()
        local ready, runs = false, 0
        S.WaitFor(function() return ready end, function() runs = runs + 1 end)
        pump(3)
        assert.equals(0, runs)
        ready = true
        pump(1)
        assert.equals(1, runs)
        pump(5)
        assert.equals(1, runs)      -- does not re-run
    end)

    it("gives up at maxFrames without running", function()
        local runs = 0
        S.WaitFor(function() return false end, function() runs = runs + 1 end, 3)
        pump(10)
        assert.equals(0, runs)
        assert.equals(0, #timers)   -- stopped queueing
    end)
end)

describe("SkinAPI SetFont", function()
    local KE, S, applied

    local function fontString()
        return {
            SetFont = function() end,
            GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end,
            SetShadowColor = function() end,
        }
    end

    before_each(function()
        KE = L.loadSkinAPI()
        S = KE.Skins
        applied = {}
        -- SetFont routes through KE:ApplyFont; record every call it makes.
        KE.ApplyFont = function(_, fs, face, size, outline)
            applied[#applied + 1] = { fs = fs, face = face, size = size, outline = outline }
        end
    end)

    it("applies the font on first call", function()
        local fs = fontString()
        S.SetFont(fs, 12, "")
        assert.equals(1, #applied)
        assert.equals(12, applied[1].size)
        assert.equals(S.FONT_FACE, applied[1].face)
    end)

    it("skips a repeat call with identical size, outline and offset", function()
        local fs = fontString()
        S.SetFont(fs, 12, "")
        S.SetFont(fs, 12, "")
        assert.equals(1, #applied)
    end)

    it("re-applies when the outline changes", function()
        local fs = fontString()
        S.SetFont(fs, 12, "")
        S.SetFont(fs, 12, "OUTLINE")
        assert.equals(2, #applied)
    end)

    it("re-applies every registered string when the offset moves", function()
        local a, b = fontString(), fontString()
        S.SetFont(a, 12, "")
        S.SetFont(b, 14, "")
        assert.equals(2, #applied)
        S.SetFontOffset(2)
        assert.equals(4, #applied)
        -- The offset-change loop walks fontRegistry with pairs(), whose
        -- iteration order over table keys is unspecified by Lua and not
        -- something a correct S.SetFontOffset can control. Sort instead of
        -- indexing a fixed slot so this doesn't hinge on hash-bucket luck.
        local sizes = { applied[3].size, applied[4].size }
        table.sort(sizes)
        assert.same({ 14, 16 }, sizes)   -- a's and b's rec.size, each +2 offset
    end)

    it("re-applies at the new size when the offset moves after skinning", function()
        local fs = fontString()
        S.SetFont(fs, 12, "")
        assert.equals(12, applied[1].size)
        S.SetFontOffset(3)
        assert.equals(15, applied[#applied].size)
    end)

    it("clamps the effective size to 8", function()
        local fs = fontString()
        S.SetFont(fs, 10, "")
        S.SetFontOffset(-4)
        assert.equals(8, applied[#applied].size)
    end)

    it("ignores a repeated offset set", function()
        local fs = fontString()
        S.SetFont(fs, 12, "")
        S.SetFontOffset(0)
        assert.equals(1, #applied)
    end)

    -- The lazy offset init is plan-introduced: the reference reads a
    -- different db path (SkinningAPI.lua:2130-2134). Exercise the repointed
    -- one so a wrong key surfaces here rather than in game.
    it("picks the offset up from the database on first call", function()
        KE.db.profile.Skinning.BlizzardFrames.FontOffset = 2
        local fs = fontString()
        S.SetFont(fs, 12, "")
        assert.equals(14, applied[1].size)
    end)

    it("treats a missing database section as offset zero", function()
        KE.db.profile.Skinning.BlizzardFrames = nil
        local fs = fontString()
        S.SetFont(fs, 12, "")
        assert.equals(12, applied[1].size)
    end)
end)

describe("SkinAPI skin registry", function()
    local KE, S

    before_each(function()
        KE = L.loadSkinAPI()
        S = KE.Skins
        KE.ShouldNotLoadModule = function() return false end
        KE.db.profile.Skinning.BlizzardFrames = { Enabled = true, Skins = {} }
    end)

    it("runs a skin whose key is absent from the Skins table", function()
        local ran = false
        S._runList({ { fn = function() ran = true end, key = "alpha" } })
        assert.is_true(ran)
        assert.equals("ok", S.skinStatus.alpha)
    end)

    it("skips a skin explicitly set to false and records it as disabled", function()
        KE.db.profile.Skinning.BlizzardFrames.Skins.alpha = false
        local ran = false
        S._runList({ { fn = function() ran = true end, key = "alpha" } })
        assert.is_false(ran)
        assert.equals("disabled", S.skinStatus.alpha)
    end)

    it("treats an entry with no key as always enabled", function()
        local ran = false
        S._runList({ { fn = function() ran = true end } })
        assert.is_true(ran)
    end)

    it("records a throwing skin as an error rather than propagating", function()
        assert.has_no.errors(function()
            S._runList({ { fn = function() error("boom") end, key = "alpha" } })
        end)
        assert.truthy(S.skinStatus.alpha:find("ERROR"))
    end)

    it("keeps running later skins after one throws", function()
        local second = false
        S._runList({
            { fn = function() error("boom") end, key = "alpha" },
            { fn = function() second = true end, key = "beta" },
        })
        assert.is_true(second)
        assert.equals("ok", S.skinStatus.beta)
    end)

    it("indexes every entry that carries a key, enabled or not", function()
        KE.db.profile.Skinning.BlizzardFrames.Skins.beta = false
        S._runList({
            { fn = function() end, key = "alpha" },
            { fn = function() end, key = "beta" },
        })
        assert.truthy(S.skinIndex.alpha)
        assert.truthy(S.skinIndex.beta)
    end)

    it("is inactive when the module is disabled", function()
        KE.db.profile.Skinning.BlizzardFrames.Enabled = false
        assert.is_false(S:IsActive() and true or false)
    end)

    it("is inactive when another addon owns Blizzard skinning", function()
        KE.ShouldNotLoadModule = function() return true end
        assert.is_false(S:IsActive())
    end)

    -- Regression for the load-on-demand trap: a plan draft registered the
    -- GM chat skin early, which would have run it once before its addon
    -- existed and then dropped it. This pins the queueing behaviour.
    it("holds an addon-registered skin until that addon is announced", function()
        local ran = 0
        S:Register("Blizzard_GMChatUI", function() ran = ran + 1 end, "GMChat")
        S._runList({})                  -- the early list: must not run it
        assert.equals(0, ran)
        local BF = _G.KitnEssentials:GetModule("BlizzardFrames")
        BF:RunForAddon("Blizzard_GMChatUI")
        assert.equals(1, ran)
        BF:RunForAddon("Blizzard_GMChatUI")
        assert.equals(1, ran)           -- drained, not re-run
    end)
end)

describe("A6.1 helper surface", function()
    -- S.Frame is the entry point most skin files call first: 59 direct calls
    -- across 50 files under Frames/ and Addons/. A missing or misnamed helper
    -- here fails those ports together rather than one at a time.
    local REQUIRED = {
        "SafeCenter", "CropAtlasEdges", "RefreshEdgesUnder", "FixSubPixelEdge",
        "LockStripped", "LockTextColor", "RowHover", "HoverWash",
        "RotateButton", "SelectedFill", "MaxMinFrame", "IconBorder",
        "NavButton", "SweepCheckChildren", "RecenterTabText", "TabSetSelected",
        "Tab", "OverlayButton", "BleedOutside", "Stepper", "QualityTier",
        "Vanish", "HideAll", "Apply", "Each", "SlotIcon", "Icon", "ItemButton",
        "HookScrollBox", "HookScrollBoxIcons", "SideTab", "NavCrumb",
        "Collapse", "ReplaceIconString", "StripParchment", "StylePulloutFrames",
        "StyleSharedDropDownList", "FontStrings", "FontStringsDeep", "Portrait",
        "Inset", "StaticPopup", "Frame", "Tabs",
    }

    it("exposes every helper the frame skins call", function()
        -- `.Skins` is load-bearing. L.loadSkinAPI returns the KE table
        -- (dev/spec/_helpers.lua:17-24 returns KE), not the Skins namespace;
        -- indexing the return directly finds nothing and the test can never
        -- pass. dev/spec/skinapi_spec.lua:9 already does it this way.
        local S = L.loadSkinAPI().Skins
        local missing = {}
        for _, name in ipairs(REQUIRED) do
            if type(S[name]) ~= "function" then
                missing[#missing + 1] = name
            end
        end
        assert.same({}, missing)
    end)

    it("leaks no global named RecenterTabText", function()
        L.loadSkinAPI()
        -- The reference forward-declares it as a local at SkinningAPI.lua:1305
        -- so the eight call sites below it can reach it. Dropping that line
        -- turns the definition into a global write.
        assert.is_nil(rawget(_G, "RecenterTabText"))
    end)

    it("S.Frame tolerates a nil frame", function()
        local S = L.loadSkinAPI().Skins
        assert.has_no.errors(function() S.Frame(nil) end)
    end)
end)
