-- Tier 1: Modules/QoL/ColorPicker.lua's five pure conversion helpers, reached
-- through debug.getupvalue chains (the module never exports them and is
-- never restructured to make them reachable). GetHexColor's hex-window math
-- is what a bad three/short-digit expansion would silently corrupt --
-- AlphaValue(0.0096) is the case that catches a floor-without-rounding
-- regression (see the loader's comment on strjoin's argument order too).
local L = require("dev.spec._ke_loader")

local function makeBox(text, numLetters)
    return {
        GetText = function() return text end,
        GetNumLetters = function() return numLetters end,
    }
end

describe("ColorPicker.lua pure conversion helpers", function()
    local seams

    before_each(function()
        local _, _, s = L.loadColorPicker()
        seams = s
    end)

    it("installs the real string globals it promises", function()
        assert.equals(string.len, _G.strlen)
    end)

    describe("GetHexColor", function()
        it("reads a straight six-digit hex string", function()
            local r, g, b = seams.getHexColor(makeBox("ff8000", 6))
            assert.near(1, r, 1e-9)
            assert.near(128 / 255, g, 1e-9)
            assert.near(0, b, 1e-9)
        end)

        it("expands a three-digit hex string (f80 -> ff8800)", function()
            local r, g, b = seams.getHexColor(makeBox("f80", 3))
            assert.near(1, r, 1e-9)
            assert.near(136 / 255, g, 1e-9)
            assert.near(0, b, 1e-9)
        end)

        it("zero-extends a short input (ff -> ff0000)", function()
            local r, g, b = seams.getHexColor(makeBox("ff", 2))
            assert.near(1, r, 1e-9)
            assert.near(0, g, 1e-9)
            assert.near(0, b, 1e-9)
        end)

        it("falls back to 0 for invalid digits", function()
            local r, g, b = seams.getHexColor(makeBox("zz", 2))
            assert.near(0, r, 1e-9)
            assert.near(0, g, 1e-9)
            assert.near(0, b, 1e-9)
        end)
    end)

    describe("ExpandFromThree", function()
        it("doubles each digit", function()
            assert.equals("ff8800", seams.expandFromThree("f", "8", "0"))
            assert.equals("aabbcc", seams.expandFromThree("a", "b", "c"))
        end)
    end)

    describe("ExtendToSix", function()
        it("pads with trailing zeros to six characters", function()
            assert.equals("ff0000", seams.extendToSix("ff"))
            assert.equals("100000", seams.extendToSix("1"))
        end)
    end)

    describe("Round255", function()
        it("rounds a 0-1 fraction to a 0-255 integer", function()
            assert.equals(0, seams.round255(0))
            assert.equals(255, seams.round255(1))
            assert.equals(128, seams.round255(0.5))
        end)
    end)

    describe("AlphaValue", function()
        it("converts a 0-1 alpha to a 0-100 integer, rounding not truncating", function()
            assert.equals(0, seams.alphaValue(nil))
            assert.equals(100, seams.alphaValue(1))
            assert.equals(50, seams.alphaValue(0.5))
            -- 0.0096 * 100 = 0.96; +.05 = 1.01; floor = 1. Plain truncation
            -- (floor(0.96)) would wrongly return 0.
            assert.equals(1, seams.alphaValue(0.0096))
        end)
    end)
end)
