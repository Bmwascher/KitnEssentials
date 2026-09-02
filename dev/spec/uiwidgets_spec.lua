-- Modules/Skinning/UIWidgets.lua -- restyles Blizzard's on-screen UI widget
-- frames (top-centre status bars / text widgets used by M+ timers, event
-- progress, power bars). Almost everything in this module touches real
-- widget frames and is only verifiable in-game; InTooltip (a file-local
-- recovered via debug.getupvalue) and the ApplySettings font-cache
-- invalidation path are the pure decision points reachable headlessly
-- through dev/spec/_ke_loader.lua's loadUIWidgets.
local L = require("dev.spec._ke_loader")

describe("UIWidgets", function()
    describe("InTooltip identity", function()
        local InTooltip

        before_each(function()
            local _, _, seams = L.loadUIWidgets()
            InTooltip = seams.InTooltip
        end)

        it("does not error when a tooltip global is itself nil", function()
            -- None of GameTooltip/ItemRefTooltip/etc. are planted at all.
            assert.has_no.errors(function()
                assert.is_false(InTooltip(nil, {}))
            end)
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
