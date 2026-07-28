-- Tier 2: Modules/Skinning/Tooltips.lua. Only the four pure helpers are
-- reachable headlessly; everything that dresses a live tooltip is verified
-- in-game (spec section 10).
local L = require("dev.spec._ke_loader")

describe("Tooltips ShortValue", function()
    local TT
    before_each(function() TT = L.loadTooltips() end)

    it("formats billions with one decimal", function()
        assert.equals("1.5B", TT._ShortValue(1.5e9))
    end)

    it("formats millions with one decimal", function()
        assert.equals("2.3M", TT._ShortValue(2.3e6))
    end)

    it("formats thousands with one decimal", function()
        assert.equals("4.2K", TT._ShortValue(4200))
    end)

    it("formats values below a thousand as whole numbers", function()
        assert.equals("999", TT._ShortValue(999))
    end)

    it("takes the higher bracket exactly on a boundary", function()
        assert.equals("1.0K", TT._ShortValue(1000))
        assert.equals("1.0M", TT._ShortValue(1e6))
        assert.equals("1.0B", TT._ShortValue(1e9))
    end)
end)

describe("Tooltips ColorsMatch", function()
    local TT
    before_each(function() TT = L.loadTooltips() end)

    it("matches identical colours", function()
        assert.is_true(TT._ColorsMatch({ 1, 0.5, 0, 1 }, { 1, 0.5, 0, 1 }))
    end)

    it("rejects a difference in any component", function()
        for i = 1, 4 do
            local b = { 1, 0.5, 0, 1 }
            b[i] = 0.123
            assert.is_false(TT._ColorsMatch({ 1, 0.5, 0, 1 }, b))
        end
    end)

    it("treats a missing component as zero", function()
        assert.is_true(TT._ColorsMatch({ 1, 0, 0 }, { 1, 0, 0, 0 }))
    end)

    it("returns false when either side is nil", function()
        assert.is_false(TT._ColorsMatch(nil, { 1, 1, 1, 1 }))
        assert.is_false(TT._ColorsMatch({ 1, 1, 1, 1 }, nil))
    end)
end)

describe("Tooltips ReactionColor", function()
    it("returns the faction bar colour for the unit's reaction", function()
        local TT = L.loadTooltips()
        local r, g, b = TT._ReactionColor("target")
        assert.same({ 0.37, 0.87, 0.37 }, { r, g, b })
    end)

    it("falls back to white when the reaction has no colour", function()
        local TT = L.loadTooltips({ UnitReaction = function() return 99 end })
        local r, g, b = TT._ReactionColor("target")
        assert.same({ 1, 1, 1 }, { r, g, b })
    end)

    it("falls back to white when there is no reaction at all", function()
        local TT = L.loadTooltips({ UnitReaction = function() return nil end })
        local r, g, b = TT._ReactionColor("target")
        assert.same({ 1, 1, 1 }, { r, g, b })
    end)
end)

describe("Tooltips WantIDs", function()
    it("never shows IDs on NEVER", function()
        local TT = L.loadTooltips({ IsModifierKeyDown = function() return true end })
        assert.is_false(TT._WantIDs({ ShowIDs = "NEVER" }))
    end)

    it("always shows IDs on ALWAYS", function()
        local TT = L.loadTooltips({ IsModifierKeyDown = function() return false end })
        assert.is_true(TT._WantIDs({ ShowIDs = "ALWAYS" }))
    end)

    it("follows the modifier key on MODIFIER", function()
        local held = L.loadTooltips({ IsModifierKeyDown = function() return true end })
        assert.is_true(held._WantIDs({ ShowIDs = "MODIFIER" }))
        local free = L.loadTooltips({ IsModifierKeyDown = function() return false end })
        assert.is_false(free._WantIDs({ ShowIDs = "MODIFIER" }))
    end)

    it("defaults to MODIFIER when the setting is missing", function()
        local held = L.loadTooltips({ IsModifierKeyDown = function() return true end })
        assert.is_true(held._WantIDs({}))
    end)
end)
