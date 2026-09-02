-- Specs for the searchable-dropdown row matcher: substring semantics,
-- case folding, texture-tag stripping, and the key fallback.
local L = require("dev.spec._ke_loader")

describe("DropdownSearchMatches", function()
    local KE

    before_each(function()
        KE = L.loadGlobals()
    end)

    it("matches case-insensitive substrings", function()
        assert.is_true(KE.DropdownSearchMatches("Algeth'ar Academy", "AlgetharAcademy", "ACAD"))
        assert.is_false(KE.DropdownSearchMatches("Algeth'ar Academy", "AlgetharAcademy", "terrace"))
    end)

    it("treats the query as plain text, not a Lua pattern", function()
        assert.is_false(KE.DropdownSearchMatches("Peon Ready", "PeonReady", "P.on"))
        assert.is_true(KE.DropdownSearchMatches("A-B (loud)", "ab", "(loud)"))
    end)

    it("strips inline texture tags before matching", function()
        local iconText = "|T4578414:16:16:0:0:64:64:5:59:5:59|t Algeth'ar Academy"
        assert.is_true(KE.DropdownSearchMatches(iconText, "AlgetharAcademy", "algeth"))
        assert.is_false(KE.DropdownSearchMatches(iconText, "AlgetharAcademy", "4578414"))
    end)

    it("falls back to the key when display text is nil", function()
        assert.is_true(KE.DropdownSearchMatches(nil, "KitnUI", "kitn"))
        assert.is_false(KE.DropdownSearchMatches(nil, "KitnUI", "elv"))
    end)
end)
