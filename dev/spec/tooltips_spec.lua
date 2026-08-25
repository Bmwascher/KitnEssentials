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

    it("adds the line", function()
        local TT = L.loadTooltips()
        local tt = tip()
        TT._AddAuraIDLine(tt, 403264)
        assert.same({ "|cffca3c3cSpell ID:|r 403264" }, tt.lines)
    end)

    it("adds nothing for a secret id", function()
        local TT = L.loadTooltips(nil, { issecretvalue = function() return true end })
        local tt = tip()
        TT._AddAuraIDLine(tt, 403264)
        assert.same({}, tt.lines)
    end)
end)

-- The zone-in re-assert. Another addon writing the same CVar from its own
-- settings would otherwise decide the value for everyone.
describe("Tooltips PLAYER_ENTERING_WORLD", function()
    local function load(initial)
        local deferred, writes = {}, {}
        local store = { tooltipShowAuraSpellIDs = initial }
        local TT = L.loadTooltips(nil, {
            C_Timer = { After = function(_, fn) deferred[#deferred + 1] = fn end },
            C_CVar = {
                GetCVar = function(key) return store[key] end,
                SetCVar = function(key, value) store[key] = value; writes[#writes + 1] = value end,
            },
        })
        TT.db = { ShowIDs = "ALWAYS" }
        TT.IsEnabled = function() return true end
        return TT, deferred, writes, store
    end

    it("re-asserts once more after the same-frame handlers", function()
        local TT, deferred, writes, store = load("0")
        TT:PLAYER_ENTERING_WORLD()
        assert.same({ "1" }, writes)
        assert.equal(1, #deferred)

        store.tooltipShowAuraSpellIDs = "0"   -- another addon, same frame
        deferred[1]()
        assert.same({ "1", "1" }, writes)
        assert.equal("1", store.tooltipShowAuraSpellIDs)
    end)

    it("writes nothing on a zone-in where nothing disagrees", function()
        local TT, deferred, writes = load("1")
        TT:PLAYER_ENTERING_WORLD()
        deferred[1]()
        assert.same({}, writes)
    end)
end)

-- Pins the field the aura line is read from. Blizzard documents neither id nor
-- auraInstanceID on tooltip data, so a later edit "correcting" this to the
-- instance id would print a plausible wrong number under a Spell ID label.
describe("Tooltips OnTooltipSetUnitAura", function()
    local function tip()
        local lines = {}
        return {
            lines = lines,
            IsForbidden = function() return false end,
            GetName = function() return "GameTooltip" end,
            AddLine = function(_, text) lines[#lines + 1] = text end,
            Show = function() end,
        }
    end

    it("reads the spell id from data.id, not data.auraInstanceID", function()
        local TT = L.loadTooltips()
        TT.db = { ShowIDs = "ALWAYS" }
        local tt = tip()
        TT:OnTooltipSetUnitAura(tt, { id = 383169, auraInstanceID = 42 })
        assert.same({ "|cffca3c3cSpell ID:|r 383169" }, tt.lines)
    end)

    it("adds nothing when the tooltip data carries no id", function()
        local TT = L.loadTooltips()
        TT.db = { ShowIDs = "ALWAYS" }
        local tt = tip()
        TT:OnTooltipSetUnitAura(tt, {})
        assert.same({}, tt.lines)
    end)

    it("adds nothing when the id is secret", function()
        local TT = L.loadTooltips(nil, { issecretvalue = function() return true end })
        TT.db = { ShowIDs = "ALWAYS" }
        local tt = tip()
        TT:OnTooltipSetUnitAura(tt, { id = 383169 })
        assert.same({}, tt.lines)
    end)

    it("respects the modifier setting", function()
        local TT = L.loadTooltips({ IsModifierKeyDown = function() return false end })
        TT.db = { ShowIDs = "MODIFIER" }
        local tt = tip()
        TT:OnTooltipSetUnitAura(tt, { id = 383169 })
        assert.same({}, tt.lines)
    end)
end)

-- Moving the engine's own aura ID line to the bottom. The swallow and the
-- re-issue are one decision split across two callbacks, so they are driven
-- together: swallowing without re-issuing loses the ID outright.
describe("Tooltips engine aura ID relocation", function()
    local function tip(isAura)
        local lines = {}
        return {
            lines = lines,
            IsForbidden = function() return false end,
            GetName = function() return "GameTooltip" end,
            IsTooltipType = function(_, t) return isAura and t == 7 end,
            AddLine = function(_, text) lines[#lines + 1] = text end,
            Show = function() end,
        }
    end

    local function load(overrides)
        local TT = L.loadTooltips(nil, overrides)
        TT.db = { ShowIDs = "ALWAYS" }
        TT.engineAuraIDs = true
        return TT
    end

    it("swallows the engine line and re-issues it at the bottom in our colour", function()
        local TT = load()
        local tt = tip(true)
        assert.is_true(TT._SwallowEngineAuraIDLine(tt, { leftText = "Spell ID: 381748" }))
        TT:OnTooltipSetUnitAura(tt, { id = 381748 })
        assert.same({ "|cffca3c3cSpell ID:|r 381748" }, tt.lines)
    end)

    it("leaves the engine line alone and adds none of its own when the wording does not match", function()
        local TT = load()
        local tt = tip(true)
        assert.is_nil(TT._SwallowEngineAuraIDLine(tt, { leftText = "You feel lucky." }))
        TT:OnTooltipSetUnitAura(tt, { id = 381748 })
        assert.same({}, tt.lines)
    end)

    it("never swallows on a tooltip that is not an aura", function()
        local TT = load()
        local tt = tip(false)
        assert.is_nil(TT._SwallowEngineAuraIDLine(tt, { leftText = "Spell ID: 381748" }))
    end)

    it("never swallows a line it cannot read, so combat keeps the engine's line", function()
        local TT = load({ issecretvalue = function() return true end })
        local tt = tip(true)
        assert.is_nil(TT._SwallowEngineAuraIDLine(tt, { leftText = "Spell ID: 381748" }))
    end)

    it("does not swallow while the engine is not drawing at all", function()
        local TT = load()
        TT.engineAuraIDs = false
        local tt = tip(true)
        assert.is_nil(TT._SwallowEngineAuraIDLine(tt, { leftText = "Spell ID: 381748" }))
    end)

    it("does not carry a swallow over to the next tooltip", function()
        local TT = load()
        local first = tip(true)
        TT._SwallowEngineAuraIDLine(first, { leftText = "Spell ID: 381748" })
        TT:OnTooltipSetUnitAura(first, { id = 381748 })

        local second = tip(true)   -- no engine line on this one
        TT:OnTooltipSetUnitAura(second, { id = 999 })
        assert.same({}, second.lines)
    end)
end)
