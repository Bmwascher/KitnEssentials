-- Modules/Skinning/UIWidgets.lua -- restyles Blizzard's on-screen UI widget
-- frames (top-centre status bars / text widgets used by M+ timers, event
-- progress, power bars). Almost everything in this module touches real
-- widget frames and is only verifiable in-game; the ApplySettings
-- font-cache invalidation path is the pure decision point reachable
-- headlessly through dev/spec/_ke_loader.lua's loadUIWidgets.
local L = require("dev.spec._ke_loader")

describe("UIWidgets", function()

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

    describe("ApplyTopCenter snapshot lifecycle", function()
        -- The container's pre-move placement is recorded once and replayed
        -- on disable; a wrong record silently leaves the frame moved.
        local function fakeContainer(point, rel, relPoint, x, y, scale, strata)
            local f = { point = point, rel = rel, relPoint = relPoint, x = x, y = y,
                        scale = scale, strata = strata, shown = true }
            function f:GetPoint() return self.point, self.rel, self.relPoint, self.x, self.y end
            function f:SetPoint(p, r, rp, px, py)
                self.point, self.rel, self.relPoint, self.x, self.y = p, r, rp, px, py
            end
            function f:ClearAllPoints() end
            function f:GetScale() return self.scale end
            function f:SetScale(s) self.scale = s end
            function f:GetFrameStrata() return self.strata end
            function f:SetFrameStrata(s) self.strata = s end
            function f:SetShown(b) self.shown = b end
            function f:Show() self.shown = true end
            return f
        end

        local function loadWithContainer()
            local UIW, KE = L.loadUIWidgets()
            KE.ApplyFramePosition = function() end
            UIW:UpdateDB()
            UIW.db.Enabled = true
            UIW.db.TopCenter = {
                Enabled = true, Hide = false, Scale = 1.5, Strata = "HIGH",
                Position = { AnchorFrom = "TOP", AnchorTo = "TOP", XOffset = 0, YOffset = -200 },
            }
            UIW.topCenterHolder = { name = "holder" }
            local c = fakeContainer("TOP", _G.UIParent, "TOP", 0, -15, 1, "MEDIUM")
            _G.UIWidgetTopCenterContainerFrame = c
            return UIW, c
        end

        it("disabling after repeated applies replays the placement recorded before the first move", function()
            local UIW, c = loadWithContainer()
            UIW:ApplyTopCenter()
            UIW.db.TopCenter.Scale = 2
            UIW.db.TopCenter.Hide = true
            UIW:ApplyTopCenter()
            assert.equals(2, c.scale)
            assert.is_false(c.shown)

            UIW.db.TopCenter.Enabled = false
            UIW:ApplyTopCenter()
            assert.equals("TOP", c.point)
            assert.equals(_G.UIParent, c.rel)
            assert.equals(-15, c.y)
            assert.equals(1, c.scale)
            assert.equals("MEDIUM", c.strata)
            assert.is_true(c.shown)
        end)

        it("re-enabling after a restore records the current placement, not the stale one", function()
            local UIW, c = loadWithContainer()
            UIW:ApplyTopCenter()
            UIW.db.TopCenter.Enabled = false
            UIW:ApplyTopCenter()

            -- The container is elsewhere by the time the control comes back.
            c:SetPoint("TOP", _G.UIParent, "TOP", 0, -40)
            c.scale = 0.8
            UIW.db.TopCenter.Enabled = true
            UIW:ApplyTopCenter()
            UIW.db.TopCenter.Enabled = false
            UIW:ApplyTopCenter()
            assert.equals(-40, c.y)
            assert.equals(0.8, c.scale)
        end)
    end)
end)
