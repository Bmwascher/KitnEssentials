-- Modules/Skinning/UIWidgets.lua -- restyles Blizzard's on-screen UI widget
-- frames (top-centre status bars / text widgets used by M+ timers, event
-- progress, power bars). Almost everything in this module touches real
-- widget frames and is only verifiable in-game; the three pure decision
-- points are reachable headlessly through dev/spec/_ke_loader.lua's
-- loadUIWidgets (see that file for how InTooltip and SetFontIfChanged, both
-- file-locals, are recovered via debug.getupvalue).
local L = require("dev.spec._ke_loader")

describe("UIWidgets", function()
    describe("InTooltip identity", function()
        local InTooltip
        local planted

        before_each(function()
            local _, _, seams = L.loadUIWidgets()
            InTooltip = seams.InTooltip
            planted = {}
        end)

        after_each(function()
            for _, name in ipairs(planted) do
                _G[name] = nil
            end
        end)

        local function plant(name, tip)
            _G[name] = tip
            planted[#planted + 1] = name
            return tip
        end

        it("returns true for the container GameTooltip actually owns", function()
            local container = {}
            plant("GameTooltip", { widgetContainer = container })
            assert.is_true(InTooltip(nil, container))
        end)

        it("POSITIVE CONTROL: returns false for a different container", function()
            local container = {}
            local other = {}
            plant("GameTooltip", { widgetContainer = container })
            assert.is_false(InTooltip(nil, other))
        end)

        it("returns false for a nil container", function()
            plant("GameTooltip", { widgetContainer = {} })
            assert.is_false(InTooltip(nil, nil))
        end)

        it("does not error when a tooltip global is itself nil", function()
            -- None of GameTooltip/ItemRefTooltip/etc. are planted at all.
            assert.has_no.errors(function()
                assert.is_false(InTooltip(nil, {}))
            end)
        end)

        it("uses rawget: a container reachable only via __index still returns false", function()
            local container = {}
            -- tip.widgetContainer resolves to `container` through the
            -- metatable, but tip has no REAL widgetContainer field. The
            -- reference deliberately uses rawget, so this must be false.
            local tip = setmetatable({}, { __index = function() return container end })
            plant("GameTooltip", tip)
            assert.is_false(InTooltip(nil, container))
        end)
    end)

    describe("StyleWidgetByType dispatch", function()
        local UIW, ran

        before_each(function()
            UIW = L.loadUIWidgets()
            UIW:UpdateDB()
            UIW.db.StatusBar = { Enabled = true }
            UIW.db.TextWidget = { Enabled = true }
            ran = nil
            UIW.StyleStatusBarWidget = function() ran = "bar" end
            UIW.StyleTextWidget = function() ran = "text" end
        end)

        local function widget(has)
            local w = { IsForbidden = function() return false end }
            if has.Bar then w.Bar = {} end
            if has.Text then w.Text = {} end
            return w
        end

        it("routes a .Bar widget to the status bar styler", function()
            UIW:StyleWidgetByType(widget({ Bar = true }))
            assert.equals("bar", ran)
        end)

        it("routes a .Text widget with no .Bar to the text styler", function()
            UIW:StyleWidgetByType(widget({ Text = true }))
            assert.equals("text", ran)
        end)

        it("routes a widget with both .Bar and .Text to the status bar styler", function()
            UIW:StyleWidgetByType(widget({ Bar = true, Text = true }))
            assert.equals("bar", ran)
        end)

        it("routes a widget with neither field nowhere", function()
            UIW:StyleWidgetByType(widget({}))
            assert.is_nil(ran)
        end)

        it("routes a .Bar widget nowhere when StatusBar.Enabled is false", function()
            UIW.db.StatusBar.Enabled = false
            UIW:StyleWidgetByType(widget({ Bar = true }))
            assert.is_nil(ran)
        end)
    end)

    describe("SetFontIfChanged gating", function()
        local SetFontIfChanged

        before_each(function()
            local _, _, seams = L.loadUIWidgets()
            SetFontIfChanged = seams.SetFontIfChanged
        end)

        local function fakeFontString(path, size, outline)
            local calls = 0
            local fs = { path = path, size = size, outline = outline }
            function fs:GetFont() return self.path, self.size, self.outline end
            function fs:SetFont(p, s, o)
                calls = calls + 1
                self.path, self.size, self.outline = p, s, o
            end
            function fs:calls() return calls end
            return fs
        end

        it("does not call SetFont when path, size and outline are unchanged", function()
            local fs = fakeFontString("Fonts\\Expressway.TTF", 12, "OUTLINE")
            SetFontIfChanged(fs, "Fonts\\Expressway.TTF", 12, "OUTLINE")
            assert.equals(0, fs:calls())
        end)

        it("calls SetFont exactly once when only the path differs", function()
            local fs = fakeFontString("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
            SetFontIfChanged(fs, "Fonts\\Expressway.TTF", 12, "OUTLINE")
            assert.equals(1, fs:calls())
        end)

        it("calls SetFont exactly once when only the size differs", function()
            local fs = fakeFontString("Fonts\\Expressway.TTF", 10, "OUTLINE")
            SetFontIfChanged(fs, "Fonts\\Expressway.TTF", 12, "OUTLINE")
            assert.equals(1, fs:calls())
        end)

        it("calls SetFont exactly once when only the outline differs", function()
            local fs = fakeFontString("Fonts\\Expressway.TTF", 12, "")
            SetFontIfChanged(fs, "Fonts\\Expressway.TTF", 12, "OUTLINE")
            assert.equals(1, fs:calls())
        end)

        it("does NOT write when the stored outline is nil and the requested outline is the empty string", function()
            local fs = fakeFontString("Fonts\\Expressway.TTF", 12, nil)
            SetFontIfChanged(fs, "Fonts\\Expressway.TTF", 12, "")
            assert.equals(0, fs:calls())
        end)
    end)

    describe("ApplySettings font cache invalidation", function()
        -- GetFontSettings caches the resolved font/outline keyed on
        -- _styleGen, and _styleGen only bumps inside UpdateDB. ApplySettings
        -- is the GUI dropdown callback's entry point, so if it doesn't call
        -- UpdateDB the Font/Outline dropdowns are dead: the DB write lands,
        -- but every widget keeps rendering with whatever font was cached at
        -- the last reload or profile switch.
        local function fakeText()
            local fs = {}
            function fs:GetFont() return self.path, self.size, self.outline end
            function fs:SetFont(p, s, o) self.path, self.size, self.outline = p, s, o end
            function fs:SetShadowColor() end
            function fs:ClearAllPoints() end
            function fs:SetPoint() end
            function fs:SetJustifyH() end
            function fs:SetJustifyV() end
            return fs
        end

        local function fakeWidget()
            return { IsForbidden = function() return false end, Text = fakeText() }
        end

        it("restyles with the newly configured font after ApplySettings, not the stale cached one", function()
            local UIW = L.loadUIWidgets()
            UIW:UpdateDB()
            UIW.db.Enabled = true
            UIW.db.TextWidget = { Enabled = true, StyleText = true, Size = 12 }
            UIW.db.FontFace = "Fonts\\Old.ttf"
            UIW.db.FontOutline = "OUTLINE"

            -- Resolve and cache the font once, same as the initial styling
            -- pass that ran at login.
            local widget1 = fakeWidget()
            UIW:StyleTextWidget(widget1)
            assert.equals("Fonts\\Old.ttf", widget1.Text.path)

            -- Simulate the GUI dropdown callback: write the new font to the
            -- DB, then call ApplySettings, exactly as the GUI tab does.
            UIW.db.FontFace = "Fonts\\New.ttf"
            UIW:ApplySettings()

            local widget2 = fakeWidget()
            UIW:StyleTextWidget(widget2)
            assert.equals("Fonts\\New.ttf", widget2.Text.path)
        end)
    end)
end)
