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

-- The engine-side aura ID CVar. Two refusal rules live here and both fail
-- silently: writing the CVar under MODIFIER would render IDs the user asked to
-- see only while a key is held, and letting the Lua line through while the
-- engine draws its own puts the ID on the tooltip twice.
describe("Tooltips SyncAuraSpellIDCVar", function()
    -- Returns the module plus the write log, with the CVar seeded to `initial`
    -- ("1"/"0"), or absent from the client when `initial` is nil.
    local function load(showIDs, enabled, initial)
        local writes = {}
        local store = { tooltipShowAuraSpellIDs = initial }
        local TT = L.loadTooltips(nil, {
            C_CVar = {
                GetCVar = function(key) return store[key] end,
                SetCVar = function(key, value)
                    store[key] = value
                    writes[#writes + 1] = { key, value }
                end,
            },
        })
        TT.db = { ShowIDs = showIDs }
        TT.IsEnabled = function() return enabled end
        return TT, writes
    end

    it("turns engine rendering on for ALWAYS", function()
        local TT, writes = load("ALWAYS", true, "0")
        TT:SyncAuraSpellIDCVar()
        assert.same({ { "tooltipShowAuraSpellIDs", "1" } }, writes)
        assert.is_true(TT.engineAuraIDs)
    end)

    it("leaves it off for MODIFIER, which the engine cannot honour", function()
        local TT, writes = load("MODIFIER", true, "1")
        TT:SyncAuraSpellIDCVar()
        assert.same({ { "tooltipShowAuraSpellIDs", "0" } }, writes)
        assert.is_false(TT.engineAuraIDs)
    end)

    it("leaves it off for NEVER", function()
        local TT, writes = load("NEVER", true, "1")
        TT:SyncAuraSpellIDCVar()
        assert.same({ { "tooltipShowAuraSpellIDs", "0" } }, writes)
    end)

    it("hands the CVar back when the module is disabled", function()
        local TT, writes = load("ALWAYS", false, "1")
        TT:SyncAuraSpellIDCVar()
        assert.same({ { "tooltipShowAuraSpellIDs", "0" } }, writes)
        assert.is_false(TT.engineAuraIDs)
    end)

    it("does not write when the CVar already holds the wanted value", function()
        local TT, writes = load("ALWAYS", true, "1")
        TT:SyncAuraSpellIDCVar()
        assert.same({}, writes)
        assert.is_true(TT.engineAuraIDs)
    end)

    it("never writes a CVar this client does not have", function()
        local TT, writes = load("ALWAYS", true, nil)
        TT:SyncAuraSpellIDCVar()
        assert.same({}, writes)
    end)
end)

describe("Tooltips AddAuraIDLine", function()
    local function tip()
        local lines = {}
        return {
            lines = lines,
            AddLine = function(_, text) lines[#lines + 1] = text end,
            Show = function() end,
        }
    end

    it("adds nothing while the engine is drawing the ID itself", function()
        local TT = L.loadTooltips()
        TT.engineAuraIDs = true
        local tt = tip()
        TT._AddAuraIDLine(tt, nil, 403264)
        assert.same({}, tt.lines)
    end)

    it("adds the line when the engine is not", function()
        local TT = L.loadTooltips()
        TT.engineAuraIDs = false
        local tt = tip()
        TT._AddAuraIDLine(tt, nil, 403264)
        assert.same({ "|cff7c7c7cSpell ID:|r 403264" }, tt.lines)
    end)
end)
