-- Tier 2: the settings window's size and position rules in
-- GUI/GUIMain/GUI-Core.lua.
--
-- The grip caps the window at the room left to the screen's right and bottom
-- edges, a press that barely moves keeps the size it had, and the window opens
-- at the top-left corner its saved anchor describes, moved onto the screen if
-- it fell off it. The five rules are pure, so they are tested directly; the
-- drag, the bounds call and the anchoring are checked in game.
local helpers = require("dev.spec._helpers")

describe("GUI-Core window size rules", function()
    local GUIFrame

    before_each(function()
        local KE = { Theme = { headerHeight = 32, borderSize = 1 } }
        -- GUI-Core asks the availability policy; a retail load admits all.
        helpers.loadModule("Core/Availability.lua", KE)
        helpers.loadModule("GUI/GUIMain/GUI-Core.lua", KE)
        GUIFrame = KE.GUIFrame
    end)

    it("gives the room to the right and bottom edges, never below the minimum", function()
        local cases = {
            { name = "room on both sides", args = { 650, -157, 2560, 1440, 950, 550 }, w = 1910, h = 1283 },
            { name = "width room below the minimum", args = { 2000, -157, 2560, 1440, 950, 550 }, w = 950, h = 1283 },
            { name = "height room below the minimum", args = { 100, -1000, 2560, 1440, 950, 550 }, w = 2460, h = 550 },
            { name = "screen height a hair under a pixel", args = { 650, -157, 2560, 1439.9999, 950, 550 }, w = 1910, h = 1283 },
            { name = "half-pixel room floors", args = { 650.5, -157, 2560, 1440, 950, 550 }, w = 1909, h = 1283 },
        }
        for _, case in ipairs(cases) do
            local w, h = GUIFrame.ResizeRoom(unpack(case.args))
            assert.equals(case.w, w, case.name)
            assert.equals(case.h, h, case.name)
        end
    end)

    it("moves a restored corner onto the screen, leaving room for the minimum", function()
        local cases = {
            { name = "corner already fits", args = { 650, -157, 2560, 1440, 950, 550 }, x = 650, y = -157 },
            { name = "corner left of and above the screen", args = { -1279.5, 1361.5, 2560, 1440, 950, 550 }, x = 0, y = 0 },
            { name = "corner too close to the right and bottom", args = { 2000, -1000, 2560, 1440, 950, 550 }, x = 1610, y = -890 },
        }
        for _, case in ipairs(cases) do
            local x, y = GUIFrame.ClampCorner(unpack(case.args))
            assert.equals(case.x, x, case.name)
            assert.equals(case.y, y, case.name)
        end
    end)

    it("fits a size between the minimum and the room, the minimum winning", function()
        local cases = {
            { name = "below the minimum", args = { 900, 500, 950, 550, 1910, 1283 }, w = 950, h = 550 },
            { name = "above the room", args = { 2000, 1300, 950, 550, 1910, 1283 }, w = 1910, h = 1283 },
            { name = "inside the range", args = { 1141, 963, 950, 550, 1910, 1283 }, w = 1141, h = 963 },
            { name = "room below the minimum", args = { 1200, 600, 950, 550, 560, 440 }, w = 950, h = 550 },
        }
        for _, case in ipairs(cases) do
            local w, h = GUIFrame.FitWindowSize(unpack(case.args))
            assert.equals(case.w, w, case.name)
            assert.equals(case.h, h, case.name)
        end
    end)

    it("keeps the grab size only when both sides moved under 2 px", function()
        local cases = {
            { name = "1 px on both sides", now = { 1142, 962 }, w = 1141, h = 963 },
            { name = "2 px on the width", now = { 1143, 963 }, w = 1143, h = 963 },
            { name = "1 px wide and 3 px tall", now = { 1142, 966 }, w = 1142, h = 966 },
        }
        for _, case in ipairs(cases) do
            local w, h = GUIFrame.KeepGrabSize(1141, 963, case.now[1], case.now[2])
            assert.equals(case.w, w, case.name)
            assert.equals(case.h, h, case.name)
        end
    end)

    it("converts any anchor pair to the top-left corner, nil for an unknown name", function()
        local cases = {
            { name = "logged CENTER>CENTER", args = { "CENTER", "CENTER", -59.5, 81.5, 1141, 963, 2560, 1440 }, x = 650, y = -157 },
            { name = "TOPLEFT>TOPLEFT", args = { "TOPLEFT", "TOPLEFT", 10, -20, 100, 50, 1000, 800 }, x = 10, y = -20 },
            { name = "BOTTOMRIGHT>BOTTOMRIGHT", args = { "BOTTOMRIGHT", "BOTTOMRIGHT", -10, 20, 100, 50, 1000, 800 }, x = 890, y = -730 },
            { name = "RIGHT>LEFT", args = { "RIGHT", "LEFT", 300, 0, 100, 50, 1000, 800 }, x = 200, y = -375 },
            { name = "TOP>BOTTOM", args = { "TOP", "BOTTOM", 0, 100, 100, 50, 1000, 800 }, x = 450, y = -700 },
            { name = "BOTTOMLEFT>TOPRIGHT", args = { "BOTTOMLEFT", "TOPRIGHT", -200, -100, 100, 50, 1000, 800 }, x = 800, y = -50 },
            { name = "unknown frame point", args = { "MIDDLE", "CENTER", 0, 0, 100, 50, 1000, 800 } },
            { name = "missing relative point", args = { "CENTER", nil, 0, 0, 100, 50, 1000, 800 } },
        }
        for _, case in ipairs(cases) do
            local x, y = GUIFrame.TopLeftFromPoint(unpack(case.args, 1, 8))
            if case.x then
                assert.equals(case.x, x, case.name)
                assert.equals(case.y, y, case.name)
            else
                assert.is_nil(x, case.name)
            end
        end
    end)
end)
