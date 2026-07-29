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

-- Task 0B: per-registration bookkeeping (skinRegistrations), the truthful
-- skinStatus aggregate, and the two diagnostics that read them. Every case
-- here runs on the composed loader and dispatches through the production
-- seam (S:Register/S:RegisterEarly + BF:RunForAddon), never solely through a
-- hand-built S._runList list -- both of the strongest breaks found against
-- an earlier version of this task worked by satisfying a component test
-- while the real path never carried the data, which is exactly the gap that
-- hid Task 0A's crash from busted (dev/spec/euiwindows_spec.lua).
describe("SkinAPI per-registration diagnostics", function()
    local KE, S, BF

    before_each(function()
        KE = L.loadSkinAPI_EUIWindows()
        S = KE.Skins
        KE.ShouldNotLoadModule = function() return false end
        KE.db.profile.Skinning.BlizzardFrames = { Enabled = true, Skins = {} }
        BF = _G.KitnEssentials:GetModule("BlizzardFrames")
    end)

    local function captureVerify()
        local printed = {}
        local realPrint = _G.print
        _G.print = function(msg) printed[#printed + 1] = msg end
        local ok, err = pcall(S.DebugVerify)
        _G.print = realPrint
        assert.is_true(ok, err)
        return printed
    end

    local function findLine(printed, needle)
        for _, line in ipairs(printed) do
            if line:find(needle, 1, true) then return line end
        end
        return nil
    end

    describe("register time", function()
        it("records the addon and starts pending through S:Register", function()
            S:Register("Blizzard_X", function() end, "Key")
            local record = S.skinRegistrations.Key[1]
            assert.equals("Blizzard_X", record.addon)
            assert.equals("pending", record.status)
        end)

        it("leaves addon nil through S:RegisterEarly", function()
            S:RegisterEarly(function() end, "Key")
            local record = S.skinRegistrations.Key[1]
            assert.is_nil(record.addon)
            -- Positive control: a nil addon is "no addon to match on", not
            -- "no record" -- the record itself still exists and is pending.
            assert.equals("pending", record.status)
        end)

        it("exposes S.skinRegistrations as a table", function()
            assert.is_table(S.skinRegistrations)
        end)
    end)

    describe("dispatch, per record and named", function()
        local HOUSING_ADDONS = {
            "Blizzard_HousingDashboard", "Blizzard_HouseList", "Blizzard_HouseEditor",
            "Blizzard_HouseCustomization", "Blizzard_HouseNeighborhood",
            "Blizzard_HousingCatalog", "Blizzard_HousingBasicsFTUE",
            "Blizzard_HouseGuestList", "Blizzard_HousingFacade",
        }

        -- Nine registrations, one per Blizzard addon name, the dashboard
        -- among them -- the shape EllesmereUI's real "housing" row filters.
        -- Nine correct records whose statuses land on the wrong entries
        -- would still give counts of 8 ok / 1 suppressed, so every
        -- assertion below names the addon rather than counting.
        it("suppresses exactly the dashboard and runs the other eight, named", function()
            S.suppressed = { Housing = { euiKey = "housing", addons = { Blizzard_HousingDashboard = true } } }
            for _, addon in ipairs(HOUSING_ADDONS) do
                S:Register(addon, function() end, "Housing")
            end
            for _, addon in ipairs(HOUSING_ADDONS) do
                BF:RunForAddon(addon)
            end

            local byAddon = {}
            for _, record in ipairs(S.skinRegistrations.Housing) do
                byAddon[record.addon] = record
            end

            assert.equals("suppressed", byAddon.Blizzard_HousingDashboard.status)
            assert.equals("housing", byAddon.Blizzard_HousingDashboard.suppressor)
            for _, addon in ipairs(HOUSING_ADDONS) do
                if addon ~= "Blizzard_HousingDashboard" then
                    assert.equals("ok", byAddon[addon].status)
                end
            end
        end)

        it("suppresses exactly the companion config and runs the other two, named for Delves", function()
            local DELVES_ADDONS = {
                "Blizzard_DelvesCompanionConfiguration", "Blizzard_DelvesDifficultyPicker", "Blizzard_DelvesDashboard",
            }
            S.suppressed = { Delves = { euiKey = "delves", addons = { Blizzard_DelvesCompanionConfiguration = true } } }
            for _, addon in ipairs(DELVES_ADDONS) do
                S:Register(addon, function() end, "Delves")
            end
            for _, addon in ipairs(DELVES_ADDONS) do
                BF:RunForAddon(addon)
            end

            local byAddon = {}
            for _, record in ipairs(S.skinRegistrations.Delves) do
                byAddon[record.addon] = record
            end
            assert.equals("suppressed", byAddon.Blizzard_DelvesCompanionConfiguration.status)
            assert.equals("ok", byAddon.Blizzard_DelvesDifficultyPicker.status)
            assert.equals("ok", byAddon.Blizzard_DelvesDashboard.status)
        end)
    end)

    describe("suppression precedence pins", function()
        it("runs a nil-addon registration against a filtered row", function()
            S.suppressed = { Key = { euiKey = "eui", addons = { Blizzard_X = true } } }
            local ran = false
            S:RegisterEarly(function() ran = true end, "Key")
            local record = S.skinRegistrations.Key[1]
            S._runList({ record.entry })
            assert.is_true(ran)
            assert.equals("ok", record.status)
        end)

        it("suppresses a nil-addon registration against an unfiltered row", function()
            S.suppressed = { Key = "eui" }
            local ran = false
            S:RegisterEarly(function() ran = true end, "Key")
            local record = S.skinRegistrations.Key[1]
            S._runList({ record.entry })
            assert.is_false(ran)
            assert.equals("suppressed", record.status)
        end)

        it("suppresses an addon registration against an unfiltered row", function()
            S.suppressed = { Key = "eui" }
            local ran = false
            S:Register("Blizzard_X", function() ran = true end, "Key")
            BF:RunForAddon("Blizzard_X")
            assert.is_false(ran)
            assert.equals("suppressed", S.skinRegistrations.Key[1].status)
        end)
    end)

    describe("aggregate", function()
        it("aggregates mixed ok+suppressed to partial, specifically not ok, and never colours either record red", function()
            S.suppressed = { Key = { euiKey = "eui", addons = { Blizzard_A = true } } }
            S:Register("Blizzard_A", function() end, "Key")
            S:Register("Blizzard_B", function() end, "Key")
            BF:RunForAddon("Blizzard_A")
            BF:RunForAddon("Blizzard_B")
            assert.equals("partial", S.skinStatus.Key)
            assert.not_equals("ok", S.skinStatus.Key)

            local printed = captureVerify()
            local suppressedLine = findLine(printed, "Blizzard_A")
            local okLine = findLine(printed, "Blizzard_B")
            assert.truthy(suppressedLine:find("suppressed by EllesmereUI", 1, true))
            assert.falsy(suppressedLine:find("|cffff0000", 1, true), "suppressed rendered red inside a partial key")
            assert.falsy(okLine:find("|cffff0000", 1, true), "ok rendered red inside a partial key")
        end)

        it("lets any error outrank partial", function()
            S:Register("Blizzard_A", function() error("boom") end, "Key")
            S:Register("Blizzard_B", function() end, "Key")
            BF:RunForAddon("Blizzard_A")
            BF:RunForAddon("Blizzard_B")
            assert.truthy(S.skinStatus.Key:find("ERROR"))
            assert.not_equals("partial", S.skinStatus.Key)

            -- Positive control for every "not the error colour" assertion in
            -- this file: a real error string must still render red, or the
            -- fallback in statusColor could silently stop being red (or its
            -- literal could drift) with every falsy assertion staying green.
            local errLine = findLine(captureVerify(), "Blizzard_A")
            assert.truthy(errLine:find("|cffff0000", 1, true), "a real error did not render in the error colour")
        end)

        it("aggregates all user-disabled to disabled", function()
            KE.db.profile.Skinning.BlizzardFrames.Skins.Key = false
            S:Register("Blizzard_A", function() end, "Key")
            S:Register("Blizzard_B", function() end, "Key")
            BF:RunForAddon("Blizzard_A")
            BF:RunForAddon("Blizzard_B")
            assert.equals("disabled", S.skinStatus.Key)
        end)

        it("aggregates all suppressed to suppressed, specifically not disabled", function()
            S.suppressed = { Key = "eui" }
            S:Register("Blizzard_A", function() end, "Key")
            S:Register("Blizzard_B", function() end, "Key")
            BF:RunForAddon("Blizzard_A")
            BF:RunForAddon("Blizzard_B")
            assert.equals("suppressed", S.skinStatus.Key)
            assert.not_equals("disabled", S.skinStatus.Key)
        end)

        it("aggregates to pending before anything dispatches, and off pending once dispatched", function()
            S:Register("Blizzard_A", function() end, "Key")
            assert.equals("pending", S.skinStatus.Key)
            BF:RunForAddon("Blizzard_A")
            assert.equals("ok", S.skinStatus.Key)
        end)
    end)

    describe("verify output", function()
        it("prints a suppressed record as 'suppressed by EllesmereUI', never 'disabled', and not in the error colour", function()
            S.suppressed = { Key = "eui" }
            S:Register("Blizzard_A", function() end, "Key")
            BF:RunForAddon("Blizzard_A")

            local line = findLine(captureVerify(), "Blizzard_A")
            assert.truthy(line, "no line printed for the suppressed record")
            assert.truthy(line:find("suppressed by EllesmereUI", 1, true))
            assert.falsy(line:find("|cffff0000", 1, true), "suppressed rendered in the error colour")
            assert.falsy(line:find("disabled", 1, true), "suppressed printed as disabled")
        end)

        it("does not render a pending record in the error colour", function()
            S:Register("Blizzard_A", function() end, "Key")

            local line = findLine(captureVerify(), "Blizzard_A")
            assert.truthy(line, "no pending line printed")
            assert.truthy(line:find("pending", 1, true))
            assert.falsy(line:find("|cffff0000", 1, true), "pending rendered in the error colour")
        end)
    end)

    describe("rerun", function()
        local function captureOne(fn)
            local printed = {}
            local realPrint = _G.print
            _G.print = function(msg) printed[#printed + 1] = msg end
            local ok, err = pcall(fn)
            _G.print = realPrint
            assert.is_true(ok, err)
            return printed[1]
        end

        it("refuses a multi-registration key with no selector, rather than picking one", function()
            local runsA, runsB = 0, 0
            S:Register("Blizzard_A", function() runsA = runsA + 1 end, "Key")
            S:Register("Blizzard_B", function() runsB = runsB + 1 end, "Key")
            BF:RunForAddon("Blizzard_A")
            BF:RunForAddon("Blizzard_B")

            local line = captureOne(function() S.DebugRerun("Key") end)
            assert.equals(1, runsA)   -- from the original dispatch only
            assert.equals(1, runsB)
            assert.truthy(line:find("registrations", 1, true))
        end)

        it("runs only the selected record by addon name", function()
            local runsA, runsB = 0, 0
            S:Register("Blizzard_A", function() runsA = runsA + 1 end, "Key")
            S:Register("Blizzard_B", function() runsB = runsB + 1 end, "Key")
            BF:RunForAddon("Blizzard_A")
            BF:RunForAddon("Blizzard_B")

            captureOne(function() S.DebugRerun("Key", "Blizzard_B") end)
            assert.equals(1, runsA)
            assert.equals(2, runsB)
        end)

        it("runs only the selected record by #id", function()
            local runsA, runsB = 0, 0
            S:Register("Blizzard_A", function() runsA = runsA + 1 end, "Key")
            S:Register("Blizzard_B", function() runsB = runsB + 1 end, "Key")
            BF:RunForAddon("Blizzard_A")
            BF:RunForAddon("Blizzard_B")

            captureOne(function() S.DebugRerun("Key", "#1") end)
            assert.equals(2, runsA)
            assert.equals(1, runsB)
        end)

        it("refuses a selected suppressed record with its own message", function()
            S.suppressed = { Key = { euiKey = "eui", addons = { Blizzard_A = true } } }
            local runsA = 0
            S:Register("Blizzard_A", function() runsA = runsA + 1 end, "Key")
            S:Register("Blizzard_B", function() end, "Key")
            BF:RunForAddon("Blizzard_A")
            BF:RunForAddon("Blizzard_B")

            local line = captureOne(function() S.DebugRerun("Key", "Blizzard_A") end)
            assert.equals(0, runsA)
            assert.truthy(line:find("suppressed by EllesmereUI", 1, true))
            assert.truthy(line:find("Rerunning it would double", 1, true))
        end)

        it("keeps single-registration behaviour unchanged with no selector", function()
            local runs = 0
            S:Register("Blizzard_A", function() runs = runs + 1 end, "Key")
            BF:RunForAddon("Blizzard_A")
            assert.equals(1, runs)
            captureOne(function() S.DebugRerun("Key") end)
            assert.equals(2, runs)
        end)

        -- Regression: a registered-but-never-dispatched key used to hit the
        -- old S.skinIndex lookup's "no dispatched skin named" refusal for
        -- free, because skinIndex is only ever written inside runList.
        -- S.skinRegistrations is written at REGISTER time, so that dispatch
        -- gate disappeared -- rerunning a pending record would call
        -- entry.fn against frames that were never created, printing a false
        -- "completed" or a false "ERROR:" for a window that simply never
        -- opened. Positive control is the test just above: a dispatched
        -- single registration runs fine with the same call shape.
        it("refuses a pending record rather than running it against nothing", function()
            local ran = false
            S:Register("Blizzard_A", function() ran = true end, "Key")
            -- Never dispatched: Blizzard_A never "loaded" this session.

            local line = captureOne(function() S.DebugRerun("Key") end)
            assert.is_false(ran)
            assert.truthy(line:find("Blizzard_A", 1, true))
            assert.truthy(line:find("has not loaded", 1, true))
        end)

        it("says so on an unknown selector rather than running something", function()
            local runsA, runsB = 0, 0
            S:Register("Blizzard_A", function() runsA = runsA + 1 end, "Key")
            S:Register("Blizzard_B", function() runsB = runsB + 1 end, "Key")
            BF:RunForAddon("Blizzard_A")
            BF:RunForAddon("Blizzard_B")

            local line = captureOne(function() S.DebugRerun("Key", "Blizzard_Nope") end)
            assert.equals(1, runsA)
            assert.equals(1, runsB)
            assert.truthy(line:find("has no registration", 1, true))
        end)
    end)
end)

-- Free regression pin (Step 2/8 of the task brief): the "SkinAPI skin
-- registry" describe block above builds its _runList entries by hand and
-- never calls S:Register, so those entries carry no skinRegistrations
-- record. That is deliberate -- it is what proves the dispatch-time update
-- tolerates a missing record without skipping the skinStatus write. Don't
-- "fix" those tests to go through S:Register; that would remove the only
-- coverage of the tolerate-a-missing-record path.

-- The slash parser change (Core/Globals.lua): "rerun <key> [selector]" now
-- captures an optional second token and forwards both to S.DebugRerun.
-- KE.Skins is stubbed here (not the real SkinAPI) because this case is only
-- about the parsing/forwarding wiring -- the registry and dispatch behaviour
-- behind DebugRerun are already proven above.
describe("SkinAPI rerun via the real slash handler", function()
    it("forwards key and selector through the two-token rerun form", function()
        local KE = L.loadGlobals()
        local calls = {}
        KE.Skins = {
            DebugRerun = function(key, selector) calls[#calls + 1] = { key = key, selector = selector } end,
            DebugVerify = function() end,
        }
        local handler = _G.SlashCmdList["KITNESSENTIALS"]

        handler("skins rerun Housing")
        assert.equals("Housing", calls[1].key)
        assert.is_nil(calls[1].selector)

        handler("skins rerun Housing Blizzard_HouseList")
        assert.equals("Housing", calls[2].key)
        assert.equals("Blizzard_HouseList", calls[2].selector)
    end)
end)
