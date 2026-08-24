-- Tier: KE-invented branching only (tiered test policy). The tooltip line match
-- is ported and covered by the structural diff; what is tested here is the
-- wrapper that stops a shared constant being mutated, the cap predicate, the
-- span builder's two independent gates, which side the span goes on, and the two
-- separate things that decide whether a slot repaints at all: the track
-- indicator's dirty key, and the detail render's pending flag.

local helpers = require("dev.spec._helpers")

-- The stub set is derived from `loadCP` in dev/spec/character_panel_enchant_spec.lua,
-- the proven recipe for standing this module up headless -- every stub there was
-- needed there. The structure around it differs: this one captures the module
-- registry and seeds KE inline, and it adds the two overrides this file needs --
-- a tooltip that returns the caller's lines, and the detailed item level lookup
-- the crafted-track fallback calls. Write the block below as it stands; do not
-- go and copy the other file.
--
-- Do NOT hand-minimise this stub set. The module captures several of these as
-- file-locals at load, so a stub dropped because "this file does not use it"
-- fails at load time rather than in the case that needed it.
local function loadCP(lines, overrides)
    local modules = helpers.installAddonShim()

    _G.C_TooltipInfo = {
        GetInventoryItem = function() return { lines = lines or {} } end,
        GetHyperlink = function() return nil end,
    }
    _G.C_Item = {
        GetItemInfoInstant = function() return nil end,
        GetDetailedItemLevelInfo = function() return nil end,
    }
    _G.C_Container = {}
    _G.C_Timer = { After = function() end }
    _G.CreateFrame = function() return nil end
    _G.InCombatLockdown = function() return false end
    _G.ENCHANTED_TOOLTIP_LINE = "Enchanted: %s"
    for _, name in ipairs({
        "GetInventoryItemLink", "GetExpansionForLevel", "UnitLevel",
        "GetInventoryItemQuality", "issecretvalue",
    }) do
        _G[name] = _G[name] or function() return nil end
    end
    _G.strsplit = function() return nil end
    local invslots = {
        INVSLOT_HEAD = 1, INVSLOT_NECK = 2, INVSLOT_SHOULDER = 3, INVSLOT_CHEST = 5,
        INVSLOT_WAIST = 6, INVSLOT_LEGS = 7, INVSLOT_FEET = 8, INVSLOT_WRIST = 9,
        INVSLOT_FINGER1 = 11, INVSLOT_FINGER2 = 12, INVSLOT_BACK = 15,
        INVSLOT_MAINHAND = 16, INVSLOT_OFFHAND = 17,
    }
    for name, id in pairs(invslots) do _G[name] = id end

    for k, v in pairs(overrides or {}) do _G[k] = v end

    helpers.loadModule("Modules/QoL/CharacterPanel.lua", {
        -- Read at FILE SCOPE: EMPTY_SOCKET_ICON is built by iterating it, so a
        -- missing key is not a nil method later, it is
        -- "bad argument #1 to 'ipairs' (table expected, got nil)" while the
        -- module is still loading -- and then no case reaches the function it
        -- names.
        GEM_SOCKET_TYPES = { { name = "Prismatic", locale = "EMPTY_SOCKET_PRISMATIC", icon = 1 } },
        Print = function() end,
        IsFullyRestricted = function() return false end,
        IsSafeValue = function(_, v) return v ~= nil end,
        EUIDrawsSlotElement = function() return false end,
    })
    return modules["CharacterPanel"]
end

local function upgradeLine(text)
    return { { leftText = text } }
end

-- The tooltip match and the count extraction are PORTED, and the design spec
-- classifies them as such -- so they get no cases here: a spec written from the
-- same reading cannot see an error in that reading, and the structural diff
-- catches transcription slips. What IS invented is returning a fresh wrapper
-- instead of the shared constant, and that has an invariant worth pinning.
describe("Item track extraction", function()
    -- The mutation trap. Two slots on the same track must not see each other's
    -- numbers; if the shared ITEM_TRACKS entry were written to, they would.
    it("never writes the count onto the shared track constant", function()
        local CP = loadCP(upgradeLine("Upgrade Level: Myth 4/6"))
        local first = CP:GetItemTrack("player", 1)
        assert.is_nil(first.track.cur)
        assert.is_nil(first.track.max)
        local CP2 = loadCP(upgradeLine("Upgrade Level: Myth 2/6"))
        local second = CP2:GetItemTrack("player", 1)
        assert.equals("4", first.cur)
        assert.equals("2", second.cur)
    end)
end)

describe("Upgrade cap predicate", function()
    it("is uncapped below the maximum", function()
        local CP = loadCP()
        assert.is_false(CP._IsUpgradeCapped({ cur = "4", max = "6" }))
    end)

    it("is capped at the maximum", function()
        local CP = loadCP()
        assert.is_true(CP._IsUpgradeCapped({ cur = "6", max = "6" }))
    end)

    it("is capped when there is no count to show", function()
        local CP = loadCP()
        assert.is_true(CP._IsUpgradeCapped({ }))
    end)
end)

describe("Upgrade span", function()
    local M = { letter = "M", color = { 1, 0.5, 0 } }

    it("shows letter and count together with no space between them", function()
        local CP = loadCP()
        local span = CP._UpgradeSpan({ track = M, cur = "4", max = "6" }, true, true)
        assert.is_truthy(span:find("M4/6", 1, true))
    end)

    it("shows the count alone when track letters are off", function()
        local CP = loadCP()
        local span = CP._UpgradeSpan({ track = M, cur = "4", max = "6" }, false, true)
        assert.is_truthy(span:find("4/6", 1, true))
        assert.is_falsy(span:find("M4", 1, true))
    end)

    it("shows the letter alone when upgrade progress is off", function()
        local CP = loadCP()
        local span = CP._UpgradeSpan({ track = M, cur = "4", max = "6" }, true, false)
        assert.is_truthy(span:find("M", 1, true))
        assert.is_falsy(span:find("4/6", 1, true))
    end)

    it("returns nil when both gates are off", function()
        local CP = loadCP()
        assert.is_nil(CP._UpgradeSpan({ track = M, cur = "4", max = "6" }, false, false))
    end)
end)

---------------------------------------------------------------------------------
-- The merge-versus-corner decision
--
-- Two render paths consult this and they run in different orders at different
-- call sites, so it has to be one function with one answer. Every case below is
-- a state in which the corner stands down; if any of them wrongly returns false
-- while the corner still hides, the track is drawn nowhere at all.
---------------------------------------------------------------------------------
describe("Slot track: the merge decision", function()
    local W = { track = { letter = "M", color = { 1, 1, 1 } }, cur = "4", max = "6" }
    local CAPPED = { track = { letter = "M", color = { 1, 1, 1 } }, cur = "6", max = "6" }
    local function db(over)
        local d = { ShowUpgradeProgress = true, ShowSlotItemLevel = true }
        for k, v in pairs(over or {}) do d[k] = v end
        return d
    end

    it("merges when progress is on, the item is uncapped and KE owns both", function()
        local CP = loadCP()
        assert.is_true(CP._MergeTrackIntoIlvl(db(), W, false, false))
    end)

    it("does not merge a capped item", function()
        local CP = loadCP()
        assert.is_false(CP._MergeTrackIntoIlvl(db(), CAPPED, false, false))
    end)

    it("does not merge when upgrade progress is off", function()
        local CP = loadCP()
        assert.is_false(CP._MergeTrackIntoIlvl(db({ ShowUpgradeProgress = false }), W, false, false))
    end)

    -- The hole this predicate exists to close: with item levels off there is no
    -- string to merge into, so the corner must KEEP the letter.
    it("does not merge when item levels are switched off", function()
        local CP = loadCP()
        assert.is_false(CP._MergeTrackIntoIlvl(db({ ShowSlotItemLevel = false }), W, false, false))
    end)

    -- Same hole, reached the other way.
    it("does not merge when EllesmereUI owns the item level", function()
        local CP = loadCP()
        assert.is_false(CP._MergeTrackIntoIlvl(db(), W, true, false))
    end)

    it("does not merge when EllesmereUI owns the track", function()
        local CP = loadCP()
        assert.is_false(CP._MergeTrackIntoIlvl(db(), W, false, true))
    end)

    it("does not merge with no db at all", function()
        local CP = loadCP()
        assert.is_false(CP._MergeTrackIntoIlvl(nil, W, false, false))
    end)
end)

-- The item level sits nearest the icon, so which side the span goes on depends
-- on which column the slot is in. Getting it backwards puts the track under the
-- model on one whole side of the sheet.
describe("Slot track: which side the span goes on", function()
    it("puts the span OUTSIDE the level in the right column", function()
        assert.equals("M4/6 250", loadCP()._IlvlLine("250", "M4/6", true))
    end)

    it("puts the span OUTSIDE the level in the left column", function()
        assert.equals("250 M4/6", loadCP()._IlvlLine("250", "M4/6", false))
    end)

    it("returns the level alone when there is no span", function()
        assert.equals("250", loadCP()._IlvlLine("250", nil, true))
    end)

    -- The offhand is in RIGHT_SLOTS, for gem and enchant anchoring, but its item
    -- level is centred above the icon like the main hand's. Ordering it by
    -- RIGHT_SLOTS alone makes the two adjacent weapons read in opposite orders.
    it("orders both weapon slots the same way, despite one being a right slot", function()
        local CP = loadCP()
        assert.is_false(CP._IlvlSpanOnLeft(16))
        assert.is_false(CP._IlvlSpanOnLeft(17))
    end)

    it("still orders an ordinary right-column slot to the right", function()
        assert.is_true(loadCP()._IlvlSpanOnLeft(6))
    end)
end)

-- The flag that stops the dirty check short-circuiting past a track the tooltip
-- had not loaded yet. Its whole job is to tell "not loaded" apart from "not
-- there" -- get that backwards and either the span never appears on a cold
-- cache, or every empty slot re-renders on every bag event forever.
describe("Slot track: the pending flag", function()
    it("pends an equipped item whose tooltip has not loaded", function()
        assert.is_true(loadCP()._TrackPending("|cffa335ee|Hitem:1|h[x]|h|r", nil))
    end)

    it("does NOT pend an empty slot, which has no tooltip either", function()
        assert.is_nil(loadCP()._TrackPending(nil, nil))
    end)

    it("clears once the tooltip has lines, whether or not it names a track", function()
        assert.is_nil(loadCP()._TrackPending("|cffa335ee|Hitem:1|h[x]|h|r", { lines = {} }))
    end)
end)

describe("Upgrade dirty key", function()
    it("distinguishes 5/6 from 6/6 on the same item and letter", function()
        local CP = loadCP()
        local M = { letter = "M" }
        -- The repaint this branch would otherwise skip: the letter does not
        -- change on the final upgrade, so a letter-only key cannot see it.
        assert.are_not.equal(
            CP._TrackDirtyKey({ track = M, cur = "5", max = "6" }),
            CP._TrackDirtyKey({ track = M, cur = "6", max = "6" }))
    end)
end)
