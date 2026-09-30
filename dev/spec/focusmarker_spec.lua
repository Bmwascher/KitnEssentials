-- Tier 1: FM.AnnounceAllowed is a pure predicate over the values the
-- ready-check handler reads, so nothing about the client is faked beyond what
-- the file needs to load.
local helpers = require("dev.spec._helpers")
local mock = require("dev.spec._wow_mock")

describe("FocusMarker ready-check announce gate", function()
    local FM
    local KICKING_SPEC = 71  -- Arms Warrior
    local NO_KICK_SPEC = 257 -- Holy Priest

    before_each(function()
        mock.install()
        local modules = helpers.installAddonShim()
        helpers.loadModule("Modules/Dungeons/FocusMarker.lua", { Print = function() end })
        FM = modules["FocusMarker"]
    end)

    -- args: specID, inGroup, inRaid, inCombat, chatLocked
    it("refuses when any one condition blocks", function()
        local rows = {
            { name = "no-kick spec", args = { NO_KICK_SPEC, true, false, false, false } },
            { name = "no group", args = { KICKING_SPEC, false, false, false, false } },
            { name = "raid", args = { KICKING_SPEC, true, true, false, false } },
            { name = "combat", args = { KICKING_SPEC, true, false, true, false } },
            { name = "chat locked", args = { KICKING_SPEC, true, false, false, true } },
        }
        for _, row in ipairs(rows) do
            assert.is_false(FM.AnnounceAllowed(unpack(row.args)), row.name)
        end
    end)

    it("allows when nothing blocks", function()
        local rows = {
            { name = "a kicking spec", specID = KICKING_SPEC },
            { name = "an unread spec", specID = nil },
        }
        for _, row in ipairs(rows) do
            assert.is_true(FM.AnnounceAllowed(row.specID, true, false, false, false), row.name)
        end
    end)
end)

describe("FocusMarker marker and kick macro rules", function()
    local FM
    local ANY_SPEC = 71 -- a spec with no override

    before_each(function()
        mock.install()
        local modules = helpers.installAddonShim()
        helpers.loadModule("Modules/Dungeons/FocusMarker.lua", { Print = function() end })
        FM = modules["FocusMarker"]
    end)

    local function markerDB(fromClass, classMarkers)
        return { MarkerFromClass = fromClass, SelectedMarker = "Skull", ClassMarkers = classMarkers }
    end

    local function knownSet(ids)
        local set = {}
        for _, id in ipairs(ids) do set[id] = true end
        return function(id) return set[id] == true end
    end

    local function kickDB(overrides)
        local db = {
            KickMouseover = false,
            KickTargetFallback = false,
            KickStopCasting = false,
            KickMarkFocus = false,
        }
        for key, value in pairs(overrides) do db[key] = value end
        return db
    end

    it("uses the selected marker while Marker From Class is off", function()
        assert.are.equal("Skull", FM.ResolveMarker(markerDB(false, { ROGUE = "Star" }), "ROGUE"))
    end)

    it("uses the class entry while Marker From Class is on", function()
        assert.are.equal("Star", FM.ResolveMarker(markerDB(true, { ROGUE = "Star" }), "ROGUE"))
    end)

    it("falls back to the selected marker when the class entry cannot be used", function()
        local db = markerDB(true, { ROGUE = "Star", PRIEST = "Sparkle" })
        local rows = {
            { name = "class unread" },
            { name = "class unmapped", class = "MAGE" },
            { name = "entry is not a marker", class = "PRIEST" },
        }
        for _, row in ipairs(rows) do
            assert.are.equal("Skull", FM.ResolveMarker(db, row.class), row.name)
        end
    end)

    it("picks the first known candidate in list order", function()
        local candidates = { { id = 11 }, { id = 22 } }
        local rows = {
            { name = "first known", known = { 11 }, want = 11 },
            { name = "only the second known", known = { 22 }, want = 22 },
            { name = "both known", known = { 11, 22 }, want = 11 },
        }
        for _, row in ipairs(rows) do
            assert.are.equal(row.want, FM.PickKickSpell(ANY_SPEC, candidates, knownSet(row.known)), row.name)
        end
    end)

    it("picks from the override list for an override spec", function()
        local isKnown = knownSet({ 78675, 11 })
        assert.are.equal(78675, FM.PickKickSpell(102, nil, isKnown), "no shared list")
        assert.are.equal(78675, FM.PickKickSpell(102, { { id = 11 } }, isKnown), "shared list ignored")
        assert.is_nil(FM.PickKickSpell(102, { { id = 11 } }, knownSet({ 11 })), "no fallback to the shared list")
    end)

    it("returns nil when there is nothing to cast", function()
        local rows = {
            { name = "no candidate list" },
            { name = "empty candidate list", candidates = {} },
            { name = "nothing known", candidates = { { id = 11 } } },
        }
        for _, row in ipairs(rows) do
            assert.is_nil(FM.PickKickSpell(ANY_SPEC, row.candidates, knownSet({})), row.name)
        end
    end)

    it("writes exactly the lines each option asks for", function()
        local rows = {
            {
                name = "all off",
                opts = {},
                want = "#showtooltip Kick\n/cast [@focus,harm,nodead] Kick",
            },
            {
                name = "mouseover",
                opts = { KickMouseover = true },
                want = "#showtooltip Kick\n/cast [@focus,harm,nodead][@mouseover,harm,nodead] Kick",
            },
            {
                name = "target fallback",
                opts = { KickTargetFallback = true },
                want = "#showtooltip Kick\n/cast [@focus,harm,nodead][] Kick",
            },
            {
                name = "stop casting",
                opts = { KickStopCasting = true },
                want = "#showtooltip Kick\n/stopcasting\n/cast [@focus,harm,nodead] Kick",
            },
            {
                name = "mark focus",
                opts = { KickMarkFocus = true },
                want = "#showtooltip Kick\n/cast [@focus,harm,nodead] Kick\n/tm [@focus] ~8",
            },
            {
                name = "all on",
                opts = {
                    KickMouseover = true,
                    KickTargetFallback = true,
                    KickStopCasting = true,
                    KickMarkFocus = true,
                },
                want = "#showtooltip Kick\n/stopcasting\n/cast [@focus,harm,nodead][@mouseover,harm,nodead][] Kick"
                    .. "\n/tm [@focus] ~8",
            },
        }
        for _, row in ipairs(rows) do
            assert.are.equal(row.want, FM.BuildKickBody("Kick", kickDB(row.opts), 8), row.name)
        end
    end)

    it("omits the mark line when there is no marker", function()
        local db = kickDB({ KickMarkFocus = true })
        local rows = { { name = "None", idx = 0 }, { name = "unset" } }
        for _, row in ipairs(rows) do
            assert.are.equal("#showtooltip Kick\n/cast [@focus,harm,nodead] Kick",
                FM.BuildKickBody("Kick", db, row.idx), row.name)
        end
    end)

    it("refuses a body it cannot write", function()
        local db = kickDB({})
        local rows = {
            { name = "no spell name" },
            { name = "empty spell name", spell = "" },
            { name = "longer than 255 characters", spell = string.rep("x", 250) },
        }
        for _, row in ipairs(rows) do
            assert.is_nil(FM.BuildKickBody(row.spell, db, 0), row.name)
        end
    end)

    it("edits, creates or refuses by slot count", function()
        -- args: found, numCharacter, maxCharacter
        local rows = {
            { name = "found, every slot used", args = { true, 30, 30 }, want = "edit" },
            { name = "missing, a slot free", args = { false, 29, 30 }, want = "create" },
            { name = "missing, every slot used", args = { false, 30, 30 }, want = "full" },
            { name = "missing, count over the cap", args = { false, 31, 30 }, want = "full" },
        }
        for _, row in ipairs(rows) do
            assert.are.equal(row.want, FM.KickSlotAction(unpack(row.args)), row.name)
        end
    end)

    it("skips, defers or runs a kick refresh", function()
        -- args: enabled, kickOn, inCombat
        local rows = {
            { name = "module disabled", args = { false, true, false }, want = "skip" },
            { name = "kick macro off", args = { true, false, false }, want = "skip" },
            { name = "in combat", args = { true, true, true }, want = "defer" },
            { name = "out of combat", args = { true, true, false }, want = "run" },
        }
        for _, row in ipairs(rows) do
            assert.are.equal(row.want, FM.KickRefreshAction(unpack(row.args)), row.name)
        end
    end)

    it("places a name-lookup hit against the writer's own range", function()
        -- args: index, first, last
        local rows = {
            { name = "not found (nil)", args = { nil, 121, 150 }, want = "miss" },
            { name = "not found (0)", args = { 0, 1, 120 }, want = "miss" },
            { name = "first index of the range", args = { 121, 121, 150 }, want = "own" },
            { name = "last index of the range", args = { 120, 1, 120 }, want = "own" },
            { name = "below the range", args = { 120, 121, 150 }, want = "other" },
            { name = "above the range", args = { 121, 1, 120 }, want = "other" },
        }
        for _, row in ipairs(rows) do
            assert.are.equal(row.want, FM.ClassifyMacroHit(row.args[1], row.args[2], row.args[3]), row.name)
        end
    end)
end)

