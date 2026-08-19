-- Tier 2: Modules/Skinning/Tooltips.lua. Only the four pure helpers are
-- reachable headlessly; everything that dresses a live tooltip is verified
-- in-game (spec section 10).
local L = require("dev.spec._ke_loader")

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

-- The refusal rule. GetPlayerInfoByGUID answers with the FIRST class for a
-- creature GUID rather than failing, so anything that asks it without checking
-- the GUID paints every hostile NPC in that class's colour instead of red.
-- Returning nothing is what leaves Blizzard's own hostile red in place.
describe("Tooltips UnitColor", function()
    local PLAYER_GUID = "Player-1234-DEADBEEF"
    local CREATURE_GUID = "Creature-0-1234-5-6-7890-000000"

    it("class-colours a player GUID", function()
        local TT = L.loadTooltips()
        local c = TT._UnitColor("target", PLAYER_GUID)
        assert.same({ 0.20, 0.58, 0.50 }, { c:GetRGB() })
    end)

    it("never asks a creature GUID for a class", function()
        local asked = false
        local TT = L.loadTooltips({
            GetPlayerInfoByGUID = function() asked = true; return "Warrior", "WARRIOR" end,
        })
        TT._UnitColor("target", CREATURE_GUID)
        assert.is_false(asked)
    end)

    it("falls through to the reaction colour for a creature GUID", function()
        local TT = L.loadTooltips()
        local c = TT._UnitColor("target", CREATURE_GUID)
        assert.same({ 0.37, 0.87, 0.37 }, { c:GetRGB() })
    end)

    it("returns nothing for a secret-named unit that is not a player", function()
        local TT = L.loadTooltips(nil, {
            issecretvalue = function() return true end,
        })
        assert.is_nil(TT._UnitColor("target", CREATURE_GUID))
    end)

    it("returns nothing for a secret-named unit with no GUID at all", function()
        local TT = L.loadTooltips(nil, {
            issecretvalue = function() return true end,
        })
        assert.is_nil(TT._UnitColor("target", nil))
    end)

    it("class-colours a secret-named unit whose GUID says player", function()
        local TT = L.loadTooltips(nil, {
            issecretvalue = function(v) return v == "SECRET" end,
            UnitName = function() return "SECRET" end,
        })
        local c = TT._UnitColor("target", PLAYER_GUID)
        assert.same({ 0.20, 0.58, 0.50 }, { c:GetRGB() })
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
