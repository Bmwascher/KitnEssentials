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
        helpers.loadModule("Modules/DungeonTools/KicksCasts/FocusMarker.lua", { Print = function() end })
        FM = modules["FocusMarker"]
    end)

    -- args: specID, inGroup, inRaid, inCombat, chatLocked, knowsKick
    it("refuses when any one condition blocks", function()
        local rows = {
            { name = "no-kick spec", args = { NO_KICK_SPEC, true, false, false, false } },
            { name = "no group", args = { KICKING_SPEC, false, false, false, false } },
            { name = "raid", args = { KICKING_SPEC, true, true, false, false } },
            { name = "combat", args = { KICKING_SPEC, true, false, true, false } },
            { name = "chat locked", args = { KICKING_SPEC, true, false, false, true } },
            { name = "no kick known", args = { KICKING_SPEC, true, false, false, false, false } },
        }
        for _, row in ipairs(rows) do
            assert.is_false(FM.AnnounceAllowed(unpack(row.args)), row.name)
        end
    end)

    it("allows when nothing blocks", function()
        local rows = {
            { name = "a kicking spec", specID = KICKING_SPEC },
            { name = "an unread spec", specID = nil },
            { name = "a known kick", specID = KICKING_SPEC, knowsKick = true },
        }
        for _, row in ipairs(rows) do
            assert.is_true(FM.AnnounceAllowed(row.specID, true, false, false, false, row.knowsKick), row.name)
        end
    end)
end)

describe("FocusMarker marker and kick macro rules", function()
    local FM

    before_each(function()
        mock.install()
        local modules = helpers.installAddonShim()
        helpers.loadModule("Modules/DungeonTools/KicksCasts/FocusMarker.lua", { Print = function() end })
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
            assert.are.equal(row.want, FM.PickKickSpell(candidates, nil, knownSet(row.known)), row.name)
        end
    end)

    it("uses the tracker kick only when the spec has no candidate list", function()
        local tracker = { id = 78675 }
        local rows = {
            { name = "no candidate list", known = { 78675 }, want = 78675 },
            { name = "a known candidate", candidates = { { id = 11 } }, known = { 11, 78675 }, want = 11 },
            { name = "no candidate known", candidates = { { id = 11 } }, known = { 78675 } },
        }
        for _, row in ipairs(rows) do
            assert.are.equal(row.want, FM.PickKickSpell(row.candidates, tracker, knownSet(row.known)), row.name)
        end
    end)

    it("returns nil when there is nothing to cast", function()
        local rows = {
            { name = "no candidate list, no tracker kick" },
            { name = "no candidate list, tracker kick unknown", tracker = { id = 78675 } },
            { name = "empty candidate list", candidates = {} },
            { name = "nothing known", candidates = { { id = 11 } } },
        }
        for _, row in ipairs(rows) do
            assert.is_nil(FM.PickKickSpell(row.candidates, row.tracker, knownSet({})), row.name)
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

    it("counts the kick macro switch only where Focus Kick is admitted", function()
        -- args: db, admitted
        local rows = {
            { name = "admitted, on", args = { { KickMacroEnabled = true }, true }, want = true },
            { name = "withheld, on", args = { { KickMacroEnabled = true }, false }, want = false },
            { name = "admitted, off", args = { { KickMacroEnabled = false }, true }, want = false },
        }
        for _, row in ipairs(rows) do
            assert.are.equal(row.want, FM.KickOn(unpack(row.args)), row.name)
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

describe("FocusMarker forever kick clauses", function()
    local FM

    before_each(function()
        mock.install()
        local modules = helpers.installAddonShim()
        helpers.loadModule("Modules/DungeonTools/KicksCasts/FocusMarker.lua", { Print = function() end })
        FM = modules["FocusMarker"]
    end)

    -- Fixtures in the Forever rows' shape: Pummel needs Berserker Stance
    -- (form 19), Shield Bash Battle or Defensive (17, 18) and a shield.
    -- Skull Bash allows Cat, Bear and Dire Bear (1, 5, 8), Feral Charge
    -- (Bear) Bear or Dire Bear, Feral Charge all three.
    local WARRIOR = {
        { id = 6554, forms = { 19 } }, { id = 6552, forms = { 19 } },
        { id = 1672, forms = { 17, 18 }, shield = true }, { id = 72, forms = { 17, 18 }, shield = true },
    }
    local DRUID = {
        { id = 410176, forms = { 1, 5, 8 } },
        { id = 16979, forms = { 5, 8 } },
        { id = 1238122, forms = { 1, 5, 8 } },
    }
    local CANON = { [6554] = 6552, [1672] = 72 }
    local STANCES = { [17] = 1, [18] = 2, [19] = 3 }  -- Battle, Defensive, Berserker
    local FORMS = { [5] = 1, [1] = 2 }  -- Bear Form on 1, Cat Form on 2

    local function canonOf(id) return CANON[id] or id end

    -- The row's clauses as "id:indices[:shield]", one string per row.
    local function clauseText(row)
        local known = {}
        for _, id in ipairs(row.known) do known[id] = true end
        local clauses = FM.ForeverKickClauses(row.list, function(id) return known[id] == true end, canonOf,
            row.forms, row.size, row.fixed, row.shield)
        local parts = {}
        for i, c in ipairs(clauses) do
            parts[i] = c.id .. ":" .. (c.indices and table.concat(c.indices, "/") or "-") .. (c.shield and ":shield" or "")
        end
        return table.concat(parts, " ")
    end

    it("leaves out unknown kicks, later ranks of a kick taken and kicks with no form on the bar", function()
        local rows = {
            { name = "a later rank of a kick taken", list = WARRIOR, known = { 6554, 6552, 1672, 72 },
              forms = STANCES, size = 3, fixed = true, shield = true, want = "6554:3 1672:-:shield" },
            { name = "an unknown rank: the next one", list = WARRIOR, known = { 6552, 1672 },
              forms = STANCES, size = 3, fixed = true, shield = true, want = "6552:3 1672:-:shield" },
            { name = "no Berserker Stance on the bar", list = WARRIOR, known = { 6554, 1672 },
              forms = { [17] = 1, [18] = 2 }, size = 2, fixed = true, shield = true, want = "1672:-:shield" },
        }
        for _, row in ipairs(rows) do
            assert.are.equal(row.want, clauseText(row), row.name)
        end
    end)

    it("drops a kick earlier unshielded clauses cover, keeps only uncovered indices, and lets no shield clause cover", function()
        local rows = {
            { name = "Skull Bash covers both forms", list = DRUID, known = { 410176, 16979, 1238122 },
              forms = FORMS, size = 2, fixed = false, shield = true, want = "410176:1/2" },
            { name = "each Feral Charge keeps its own form", list = DRUID, known = { 16979, 1238122 },
              forms = FORMS, size = 2, fixed = false, shield = true, want = "16979:1 1238122:2" },
            { name = "a shield clause covers nothing",
              list = { { id = 72, forms = { 17, 18 }, shield = true }, { id = 6552, forms = { 17, 18 } } },
              known = { 72, 6552 }, forms = STANCES, size = 3, fixed = true, shield = true,
              want = "72:1/2:shield 6552:1/2" },
            { name = "a kick with no form covers every state",
              list = { { id = 1766 }, { id = 6552, forms = { 19 } } },
              known = { 1766, 6552 }, forms = STANCES, size = 3, fixed = true, shield = true, want = "1766:-" },
        }
        for _, row in ipairs(rows) do
            assert.are.equal(row.want, clauseText(row), row.name)
        end
    end)

    it("omits the stance condition only when every bar index is covered and every bar form is fixed", function()
        local rows = {
            { name = "three fixed stances: omitted", size = 3, fixed = true, want = "6552:3 72:-:shield" },
            { name = "a form that can be left: kept", size = 3, fixed = false, want = "6552:3 72:1/2:shield" },
            { name = "a fourth index no kick names: kept", size = 4, fixed = true, want = "6552:3 72:1/2:shield" },
        }
        for _, row in ipairs(rows) do
            row.list, row.known, row.forms, row.shield = WARRIOR, { 6552, 72 }, STANCES, true
            assert.are.equal(row.want, clauseText(row), row.name)
        end
    end)

    it("gives a shield kick no clause without a shield name", function()
        local row = { list = WARRIOR, known = { 6552, 72 }, forms = STANCES, size = 3, fixed = true, shield = false }
        assert.are.equal("6552:3", clauseText(row))
    end)

    it("writes exactly the lines each option asks for", function()
        local allOn = { KickStopCasting = true, KickMouseover = true, KickTargetFallback = true, KickMarkFocus = true }
        local rows = {
            {
                name = "a warrior, every option on",
                clauses = { { id = 6552, indices = { 3 } }, { id = 72, shield = true } },
                names = { "Pummel", "Shield Bash" }, db = allOn,
                want = "#showtooltip\n/stopcasting\n/cast [@focus,harm,nodead,stance:3][@mouseover,harm,nodead,stance:3]"
                    .. "[stance:3] Pummel; [@focus,harm,nodead,equipped:Shields][@mouseover,harm,nodead,equipped:Shields]"
                    .. "[equipped:Shields] Shield Bash\n/tm [@focus] ~8",
            },
            {
                name = "two stance indices, every option off",
                clauses = { { id = 410176, indices = { 1, 2 } } },
                names = { "Skull Bash" }, db = {},
                want = "#showtooltip\n/cast [@focus,harm,nodead,stance:1/2] Skull Bash",
            },
            {
                name = "one clause with no condition, every option off",
                clauses = { { id = 1766 } },
                names = { "Kick" }, db = {},
                want = "#showtooltip\n/cast [@focus,harm,nodead] Kick",
            },
        }
        for _, row in ipairs(rows) do
            assert.are.equal(row.want, FM.BuildForeverKickBody(row.clauses, row.names, "Shields", row.db, 8), row.name)
        end
    end)

    it("refuses a body over 255 characters", function()
        assert.is_nil(FM.BuildForeverKickBody({ { id = 1766 } }, { string.rep("x", 240) }, "Shields", {}, 0))
    end)
end)

