-- Tier 2: Modules/Skinning/Tooltips.lua. Pure helpers and the CVar lifecycle
-- are reachable headlessly; live tooltip dressing is verified in-game.
local L = require("dev.spec._ke_loader")

local function auraTip()
    local lines = {}
    return {
        lines = lines,
        AddLine = function(_, text) lines[#lines + 1] = text end,
        Show = function() end,
    }
end

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

describe("Tooltips SyncAuraSpellIDCVar", function()
    local function load(showIDs, enabled, initial, opts)
        opts = opts or {}
        local writes = {}
        local store = { tooltipShowAuraSpellIDs = initial }
        local TT = L.loadTooltips(nil, {
            C_CVar = {
                GetCVar = function(key) return store[key] end,
                SetCVar = function(key, value)
                    writes[#writes + 1] = { key, value }
                    if opts.refuse then return false end
                    store[key] = value
                    return true
                end,
            },
        })
        TT.db = { ShowIDs = showIDs }
        TT.IsEnabled = function() return enabled end
        return TT, writes, store
    end

    it("turns engine rendering on for ALWAYS", function()
        local TT, writes, store = load("ALWAYS", true, "0")
        TT:SyncAuraSpellIDCVar()
        assert.same({ { "tooltipShowAuraSpellIDs", "1" } }, writes)
        assert.equal("1", store.tooltipShowAuraSpellIDs)
    end)

    it("leaves it off for MODIFIER, which the engine cannot honour", function()
        local TT, writes, store = load("MODIFIER", true, "1")
        TT:SyncAuraSpellIDCVar()
        assert.same({ { "tooltipShowAuraSpellIDs", "0" } }, writes)
        assert.equal("0", store.tooltipShowAuraSpellIDs)
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
    end)

    it("turns it off on an explicit force-off even while still enabled", function()
        local TT, writes, store = load("ALWAYS", true, "1")
        TT:SyncAuraSpellIDCVar(true)
        assert.same({ { "tooltipShowAuraSpellIDs", "0" } }, writes)
        assert.equal("0", store.tooltipShowAuraSpellIDs)
    end)

    it("does not write when the CVar already holds the wanted value", function()
        local TT, writes = load("ALWAYS", true, "1")
        TT:SyncAuraSpellIDCVar()
        assert.same({}, writes)
    end)

    it("never writes a CVar this client does not have", function()
        local TT, writes = load("ALWAYS", true, nil)
        TT:SyncAuraSpellIDCVar()
        assert.same({}, writes)
    end)

    it("leaves the Lua line available when the client refuses the write", function()
        local TT, writes, store = load("ALWAYS", true, "0", { refuse = true })
        TT:SyncAuraSpellIDCVar()
        assert.same({ { "tooltipShowAuraSpellIDs", "1" } }, writes)
        assert.equal("0", store.tooltipShowAuraSpellIDs)
        local tt = auraTip()
        TT._AddAuraIDLine(tt, 403264)
        assert.same({ "|cffca3c3cSpell ID:|r 403264" }, tt.lines)
    end)

    it("follows a mid-session flip by another addon", function()
        local TT, _, store = load("ALWAYS", true, "0")
        TT:SyncAuraSpellIDCVar()
        assert.is_true(TT._EngineDrawsAuraIDs())
        store.tooltipShowAuraSpellIDs = "0"
        local tt = auraTip()
        TT._AddAuraIDLine(tt, 403264)
        assert.same({ "|cffca3c3cSpell ID:|r 403264" }, tt.lines)
    end)
end)

describe("Tooltips AddAuraIDLine", function()
    local function load(cvar)
        return L.loadTooltips(nil, {
            C_CVar = {
                GetCVar = function() return cvar end,
                SetCVar = function() return true end,
            },
        })
    end

    it("adds nothing while the engine is drawing the ID itself", function()
        local TT = load("1")
        local tt = auraTip()
        TT._AddAuraIDLine(tt, 403264)
        assert.same({}, tt.lines)
    end)

    it("adds the line when the engine is not", function()
        local TT = load("0")
        local tt = auraTip()
        TT._AddAuraIDLine(tt, 403264)
        assert.same({ "|cffca3c3cSpell ID:|r 403264" }, tt.lines)
    end)
end)

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

        store.tooltipShowAuraSpellIDs = "0"
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

    it("keeps the CVar off when a queued reassert runs after teardown", function()
        local TT, deferred, writes, store = load("0")
        TT.UnregisterEvent = function() end

        TT:PLAYER_ENTERING_WORLD()
        assert.equal(1, #deferred)
        assert.is_true(TT:IsEnabled())

        TT:OnDisable()
        assert.is_true(TT:IsEnabled())
        assert.equal("0", store.tooltipShowAuraSpellIDs)

        deferred[1]()
        assert.same({ "1", "0" }, writes)
        assert.equal("0", store.tooltipShowAuraSpellIDs)
    end)
end)

-- Tooltip data does not document these fields; data.id is the spell ID.
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

describe("Tooltips OnTooltipSetUnitAura embedded refusal", function()
    local function tip(name, throws)
        local lines = {}
        return {
            lines = lines,
            IsForbidden = function() return false end,
            GetName = function() if throws then error("forbidden object") end return name end,
            AddLine = function(_, text) lines[#lines + 1] = text end,
            Show = function() end,
        }
    end

    local function load()
        local TT = L.loadTooltips()
        TT.db = { ShowIDs = "ALWAYS" }
        return TT
    end

    it("refuses an embedded tooltip by name", function()
        local TT = load()
        local tt = tip("EmbeddedItemTooltip")
        TT:OnTooltipSetUnitAura(tt, { id = 383169 })
        assert.same({}, tt.lines)
    end)

    it("refuses a widget-owned tooltip whose name cannot be read", function()
        local TT = load()
        local tt = tip(nil, true)
        TT:OnTooltipSetUnitAura(tt, { id = 383169 })
        assert.same({}, tt.lines)
    end)

    it("still writes to an ordinary named tooltip", function()
        local TT = load()
        local tt = tip("GameTooltip")
        TT:OnTooltipSetUnitAura(tt, { id = 383169 })
        assert.same({ "|cffca3c3cSpell ID:|r 383169" }, tt.lines)
    end)
end)
