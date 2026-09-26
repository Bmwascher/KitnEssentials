-- ╔══════════════════════════════════════════════════════════╗
-- ║  dev/spec/dm_spell_history_spec.lua                      ║
-- ║  Spell history cast classifier and ring arithmetic.      ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- Loads the REAL Modules/DamageMeter/SpellHistory.lua headlessly
-- (L.loadDMSpellHistory) and drives its pure functions: DM.SpellHistoryClassify,
-- which decides whether a cast shows, as what and in which state, and the two
-- ring helpers the strip positions its icons with.
--
-- WHY THESE EARN A SPEC: the classifier is invented branching logic whose
-- mistakes are silent in game -- a channel tick shown as a cast, a pet's
-- autocast filling the strip, a failed cast left grey after it succeeded.
-- Every game lookup is injected through `api`, so no Blizzard subsystem is
-- faked.
--
-- NOT tested here, per the project's tiered policy: the frames, the fade, the
-- event wiring and the item scan. Those are smoke.
local L = require("dev.spec._ke_loader")

local SUCCEEDED = "UNIT_SPELLCAST_SUCCEEDED"
local START = "UNIT_SPELLCAST_START"
local FAILED = "UNIT_SPELLCAST_FAILED"
local INTERRUPTED = "UNIT_SPELLCAST_INTERRUPTED"
local CHANNEL_START = "UNIT_SPELLCAST_CHANNEL_START"
local CHANNEL_STOP = "UNIT_SPELLCAST_CHANNEL_STOP"

-- The one value the fake api reports as secret.
local SECRET = { secret = true }

-- 100 plain, 101 overridden by 150, 103 whose override reads 0, 102 known
-- with no texture. 300-303 are pet spells: autocast off, on, secret, missing.
local KNOWN = { [100] = true, [101] = true, [102] = true, [103] = true }
local OVERRIDE = { [101] = 150, [103] = 0 }
local TEXTURE = {
    [100] = "tex100", [103] = "tex103", [150] = "tex150",
    [300] = "tex300", [301] = "tex301", [302] = "tex302", [303] = "tex303",
}
local PET_KNOWN = { [300] = true, [301] = true, [302] = true, [303] = true }
local AUTOCAST = { [300] = false, [301] = true, [302] = SECRET }
local ITEM_FOR = { [5000] = 9000 }
local ITEM_ICON = { [9000] = "icon9000" }

local DM
local lookups

-- Counts every game lookup, so a case can prove none ran.
local function counted(fn)
    return function(...)
        lookups = lookups + 1
        return fn(...)
    end
end

local function newApi()
    return {
        isSecret = function(v) return v == SECRET end,
        isKnown = counted(function(id) return KNOWN[id] == true end),
        isPetKnown = counted(function(id) return PET_KNOWN[id] == true end),
        autoCast = counted(function(id) return AUTOCAST[id] end),
        itemFor = counted(function(id) return ITEM_FOR[id] end),
        getOverride = counted(function(id)
            local override = OVERRIDE[id]
            if override == nil then return id end
            return override
        end),
        getTexture = counted(function(id) return TEXTURE[id] end),
        getItemIcon = counted(function(item) return ITEM_ICON[item] end),
    }
end

local function newState(items)
    return { items = items ~= false }
end

local function classify(state, api, event, unit, spellID, castGUID)
    return DM.SpellHistoryClassify(event, unit, spellID, castGUID, state, api)
end

before_each(function()
    DM = L.loadDMSpellHistory()
    lookups = 0
    assert(DM and DM.SpellHistoryClassify, "loadDMSpellHistory did not expose DM.SpellHistoryClassify")
end)

describe("SpellHistoryClassify: which casts show", function()
    it("accepts a plain known player spell with its own texture", function()
        local tex, kind, status = classify(newState(), newApi(), SUCCEEDED, "player", 100, "g1")
        assert.equals("tex100", tex)
        assert.equals("spell", kind)
        assert.equals("ok", status)
    end)

    it("shows the override's texture, and the spell's own when the override reads 0", function()
        for _, row in ipairs({
            { spell = 101, want = "tex150" },
            { spell = 103, want = "tex103" },
        }) do
            local tex = classify(newState(), newApi(), SUCCEEDED, "player", row.spell, "g1")
            assert.equals(row.want, tex)
        end
    end)

    it("refuses a secret spell ID or cast GUID before any lookup", function()
        for _, row in ipairs({
            { spell = SECRET, guid = "g1" },
            { spell = 100, guid = SECRET },
        }) do
            lookups = 0
            local tex, _, status = classify(newState(), newApi(), SUCCEEDED, "player", row.spell, row.guid)
            assert.is_nil(tex)
            assert.is_nil(status)
            assert.equals(0, lookups)
        end
    end)

    it("skips a player spell the lookups refuse", function()
        -- 999: not known and no item. 102: known, no texture.
        for _, spell in ipairs({ 999, 102 }) do
            local tex, _, status = classify(newState(), newApi(), SUCCEEDED, "player", spell, "g1")
            assert.is_nil(tex)
            assert.is_nil(status)
        end
    end)

    it("shows an item use with the item's icon, only while items are included", function()
        for _, row in ipairs({
            { items = true, tex = "icon9000", kind = "item" },
            { items = false },
        }) do
            local tex, kind = classify(newState(row.items), newApi(), SUCCEEDED, "player", 5000, "g1")
            assert.equals(row.tex, tex)
            assert.equals(row.kind, kind)
        end
    end)

    it("accepts a pet-spellbook pet cast and refuses any other pet cast", function()
        for _, row in ipairs({
            { spell = 300, tex = "tex300", kind = "pet" },
            { spell = 100 },
        }) do
            local tex, kind = classify(newState(), newApi(), SUCCEEDED, "pet", row.spell, "g1")
            assert.equals(row.tex, tex)
            assert.equals(row.kind, kind)
        end
    end)

    it("skips a pet spell unless its autocast flag reads plainly off", function()
        -- 301: on. 302: secret. 303: missing.
        for _, spell in ipairs({ 301, 302, 303 }) do
            local tex, _, status = classify(newState(), newApi(), SUCCEEDED, "pet", spell, "g1")
            assert.is_nil(tex)
            assert.is_nil(status)
        end
    end)
end)

describe("SpellHistoryClassify: channels", function()
    it("shows a channel once and skips its ticks, whichever event comes first, through a pet cast or the pet's stop", function()
        for _, row in ipairs({
            { first = CHANNEL_START, second = SUCCEEDED },
            { first = SUCCEEDED, second = CHANNEL_START },
            { first = SUCCEEDED, second = CHANNEL_START, petCast = true },
            { first = CHANNEL_START, second = SUCCEEDED, petStop = true },
        }) do
            local state, api = newState(), newApi()
            local shown = 0
            local function fire(event, guid)
                if classify(state, api, event, "player", 100, guid) then shown = shown + 1 end
            end
            fire(row.first, "c1")
            -- A pet cast shown between the channel's two opening events.
            if row.petCast then classify(state, api, SUCCEEDED, "pet", 300, "p1") end
            fire(row.second, "c1")
            fire(SUCCEEDED, "tick1")
            -- The pet's channel ending between the player's ticks.
            if row.petStop then classify(state, api, CHANNEL_STOP, "pet", 300, "p1") end
            fire(SUCCEEDED, "tick2")
            assert.equals(1, shown)
        end
    end)

    it("ends tick suppression at its channel's CHANNEL_STOP or a secret one, not an older channel's", function()
        for _, row in ipairs({
            { spell = 100, guid = "c1", want = "tex100" },
            { spell = SECRET, guid = SECRET, want = "tex100" },
            -- Recast as a new channel before the old one's stop arrives.
            { spell = 100, guid = "c1", recast = true },
        }) do
            local state, api = newState(), newApi()
            classify(state, api, CHANNEL_START, "player", 100, "c1")
            if row.recast then classify(state, api, CHANNEL_START, "player", 100, "c2") end
            classify(state, api, CHANNEL_STOP, "player", row.spell, row.guid)
            local tex = classify(state, api, SUCCEEDED, "player", 100, "n1")
            assert.equals(row.want, tex)
        end
    end)
end)

describe("SpellHistoryClassify: failed casts", function()
    it("shows a started cast that is interrupted or fails as failed", function()
        for _, event in ipairs({ INTERRUPTED, FAILED }) do
            local state, api = newState(), newApi()
            classify(state, api, START, "player", 100, "f1")
            local tex, kind, status = classify(state, api, event, "player", 100, "f1")
            assert.equals("tex100", tex)
            assert.equals("spell", kind)
            assert.equals("failed", status)
        end
    end)

    it("ignores a failure with no START, or with another cast's START", function()
        for _, startGUID in ipairs({ false, "a1" }) do
            local state, api = newState(), newApi()
            if startGUID then classify(state, api, START, "player", 100, startGUID) end
            local tex, _, status = classify(state, api, FAILED, "player", 100, "b1")
            assert.is_nil(tex)
            assert.is_nil(status)
        end
    end)

    it("ignores FAILED_QUIET even after a matching START", function()
        local state, api = newState(), newApi()
        classify(state, api, START, "player", 100, "f1")
        local tex, _, status = classify(state, api, "UNIT_SPELLCAST_FAILED_QUIET", "player", 100, "f1")
        assert.is_nil(tex)
        assert.is_nil(status)
    end)

    it("restores a failed icon when the same cast then succeeds, then carries on", function()
        local state, api = newState(), newApi()
        classify(state, api, START, "player", 100, "f1")
        classify(state, api, FAILED, "player", 100, "f1")
        local tex, kind, status = classify(state, api, SUCCEEDED, "player", 100, "f1")
        assert.is_nil(tex)
        assert.is_nil(kind)
        assert.equals("restore", status)
        tex, kind, status = classify(state, api, SUCCEEDED, "player", 100, "n2")
        assert.equals("tex100", tex)
        assert.equals("spell", kind)
        assert.equals("ok", status)
    end)
end)

describe("SpellHistory ring", function()
    it("NextHead starts at 1 from an empty ring and wraps at the size", function()
        for _, row in ipairs({ { 0, 5, 1 }, { 1, 5, 2 }, { 5, 5, 1 } }) do
            assert.equals(row[3], DM.SpellHistoryNextHead(row[1], row[2]))
        end
    end)

    it("SlotPosition puts the head slot at 0 and counts older slots across the wrap", function()
        -- Head 3 in a ring of 5: slots 3, 2, 1, 5, 4 are positions 0 to 4.
        for _, row in ipairs({ { 3, 0 }, { 2, 1 }, { 1, 2 }, { 5, 3 }, { 4, 4 } }) do
            assert.equals(row[2], DM.SpellHistorySlotPosition(row[1], 3, 5))
        end
    end)
end)
