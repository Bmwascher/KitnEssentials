-- Tier 1: KE:ColorCode and KE:WrapColor (Core/Colors.lua). Each channel is
-- rounded to the nearest of 255 steps, where a truncating format would
-- round down, and a missing channel reads as full.
local helpers = require("dev.spec._helpers")

describe("color code helpers", function()
    it("round each channel, read a missing channel as full, and wrap the text", function()
        local KE = helpers.loadModule("Core/Colors.lua", {})
        local cases = {
            { name = "half step rounds up",            r = 0.5,  g = 0.5,  b = 0.5,  code = "|cff808080" },
            { name = "zero and full",                  r = 0,    g = 1,    b = 0,    code = "|cff00ff00" },
            { name = "missing channel reads full",     r = 1,    g = nil,  b = 0,    code = "|cffffff00" },
            { name = "truncation and rounding differ", r = 0.25, g = 0.78, b = 0.92, code = "|cff40c7eb" },
        }
        for _, case in ipairs(cases) do
            assert.are.equal(case.code, KE:ColorCode(case.r, case.g, case.b), case.name)
            assert.are.equal(case.code .. "x|r", KE:WrapColor("x", case.r, case.g, case.b), case.name)
        end
    end)
end)
