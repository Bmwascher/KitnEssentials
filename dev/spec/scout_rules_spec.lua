-- Tier 1: Scout's pure rules (Modules/QoL/Scout/ScoutRules.lua). Secret cases
-- declare a value secret through the injected predicate: they prove the
-- branching, not the game's secret-value behavior, which only a smoke can.
-- The shipped word tables and the mob table get no case of their own.
local helpers = require("dev.spec._helpers")

local Rules = helpers.loadModule("Modules/QoL/Scout/ScoutRules.lua").ScoutRules

local DOT = " \194\183 "
local SECRET = {}

local function isSecret(value)
    return value == SECRET
end

local function paint(key, text)
    if key == "muted" then return text end
    return "<" .. key .. ":" .. text .. ">"
end

describe("Scout rules", function()
    it("NpcId tests the predicate before any string use, then parses Creature and Vehicle only", function()
        local exploding = setmetatable({}, { __index = function() error("string use") end })
        assert.is_nil(Rules.NpcId(exploding, function() return true end))
        for _, row in ipairs({
            { guid = "Creature-0-1465-0-2437-2605-000043F59F", want = 2605 },
            { guid = "Vehicle-0-1465-0-2437-5-000043F59F", want = 5 },
            { guid = "Player-970-0002FD64" },
            { guid = "Pet-0-1465-0-2437-165189-0100D5B1C0" },
            { guid = "Creature-x" },
            { guid = "junk" },
            {},
        }) do
            assert.equals(row.want, Rules.NpcId(row.guid, isSecret), tostring(row.guid))
        end
    end)

    it("PickUnit and PlainTrue take only plain values", function()
        for _, row in ipairs({
            { token = "target", mouseover = false, want = "target" },
            { token = SECRET, mouseover = true, want = "mouseover" },
            { token = SECRET, mouseover = false },
            { token = SECRET, mouseover = SECRET },
            { mouseover = true, want = "mouseover" },
            { mouseover = false },
        }) do
            assert.equals(row.want, Rules.PickUnit(row.token, isSecret, row.mouseover))
        end
        assert.is_true(Rules.PlainTrue(true, isSecret))
        for _, value in ipairs({ false, SECRET }) do
            assert.is_false(Rules.PlainTrue(value, isSecret))
        end
        assert.is_false(Rules.PlainTrue(nil, isSecret))
    end)

    it("PickUnit asks the predicate about the token before any truth test", function()
        -- A real secret errors on a truth test, which no sentinel can do, so
        -- this pins the order with a false token a truth test would skip.
        local asked = {}
        Rules.PickUnit(false, function(value)
            asked[#asked + 1] = tostring(value)
            return false
        end, nil)
        assert.equals("false", asked[1])
    end)

    it("DataComplete needs all six tables", function()
        local function full(change)
            local data = { abilities = {}, stats = {}, tame = {}, armor = {}, words = {}, scopes = {} }
            for k, v in pairs(change or {}) do data[k] = v end
            return data
        end
        assert.is_true(Rules.DataComplete(full()))
        for _, name in ipairs({ "abilities", "stats", "tame", "armor", "words", "scopes" }) do
            assert.is_false(Rules.DataComplete(full({ [name] = 1 })), name)
            local missing = full()
            missing[name] = nil
            assert.is_false(Rules.DataComplete(missing), name)
        end
        assert.is_false(Rules.DataComplete(nil))
    end)

    it("ShownHere needs each state's box, and refuses a state whose box is absent", function()
        local WORLD = { key = "W", state = "world" }
        local INSTANCE = { key = "I", state = "instance" }
        local COMBAT = { key = "C", state = "combat" }
        local ALL = { WORLD, INSTANCE, COMBAT }
        for _, row in ipairs({
            { name = "world on", db = { W = true }, want = true },
            { name = "world off", db = { W = false, I = true }, want = false },
            { name = "instance on", db = { W = false, I = true }, instance = true, want = true },
            { name = "instance off", db = { W = true, I = false }, instance = true, want = false },
            { name = "world combat, box off", db = { W = true, C = false }, combat = true, want = false },
            { name = "world combat, box on", db = { W = true, C = true }, combat = true, want = true },
            { name = "instance combat, combat off", db = { I = true, C = false }, instance = true, combat = true, want = false },
            { name = "instance combat, instance off", db = { I = false, C = true }, instance = true, combat = true, want = false },
            { name = "instance combat, both on", db = { I = true, C = true }, instance = true, combat = true, want = true },
            { name = "instance box absent", db = { W = true, I = true, C = true }, instance = true, boxes = { WORLD, COMBAT }, want = false },
            { name = "combat box absent", db = { W = true, C = true }, combat = true, boxes = { WORLD, INSTANCE }, want = false },
        }) do
            assert.equals(row.want, Rules.ShownHere(row.db, row.instance, row.combat, row.boxes or ALL), row.name)
        end
    end)

    it("ImmunityWords decodes masks in order, without Physical", function()
        local schools, mechanics = Rules.ImmunityWords(1 + 4 + 64, 2 ^ 29 + 2 ^ 11 + 2 ^ 4)
        assert.same({ "Fire", "Arcane" }, schools)
        assert.same({ "Stun", "Fear", "Sap" }, mechanics)
        local noSchools, noMechanics = Rules.ImmunityWords(0, 0)
        assert.same({}, noSchools)
        assert.same({}, noMechanics)
    end)

    it("ImmunityLine puts your words first and collapses past five", function()
        local six = { "Fire", "Stun", "Fear", "Polymorph", "Sap", "Bleed" }
        local noneOfMine = { "Stun", "Fear", "Sap", "Bleed", "Knockout", "Horror" }
        for _, row in ipairs({
            { name = "none", words = {} },
            { name = "five or fewer", words = { "Stun", "Fire", "Polymorph" },
              line = "Immune: <red:Fire>, <red:Polymorph>, Stun" },
            { name = "collapsed, some yours", words = six,
              line = "Immune: <red:Fire>, <red:Polymorph>, + 4 more",
              full = "Immune: Fire, Stun, Fear, Polymorph, Sap, Bleed" },
            { name = "collapsed, none yours", words = noneOfMine,
              line = "Immune: 6 effects, none of yours",
              full = "Immune: Stun, Fear, Sap, Bleed, Knockout, Horror" },
        }) do
            local line, full = Rules.ImmunityLine(row.words, "MAGE", paint)
            assert.equals(row.line, line, row.name)
            assert.equals(row.full, full, row.name)
        end
    end)

    it("ResistsLine prints points above 0 and paints your schools", function()
        for _, row in ipairs({
            { name = "bare armor row", stats = 500 },
            { name = "trimmed zeros", stats = { 10, 0, 0, 0, 30 }, want = "Resists: <red:Fire 30>" },
            { name = "mixed", stats = { 10, 0, 0, 15, 30 }, want = "Resists: Holy 15, <red:Fire 30>" },
        }) do
            local _, _, _, resists = Rules.UnpackStats(row.stats)
            assert.equals(row.want, Rules.ResistsLine(resists, "MAGE", paint), row.name)
        end
    end)

    it("RangeLabel takes the first matching row", function()
        for _, row in ipairs({
            { max = 0, want = "Self" },
            { max = 0, scope = "Cone", want = "Cone" },
            { max = 5, want = "Melee" },
            { max = 100, want = "Any range" },
            { max = 50000, want = "Any range" },
            { min = 8, max = 30, want = "8-30 yd" },
            { min = 0, max = 30, want = "30 yd" },
        }) do
            assert.equals(row.want, Rules.RangeLabel(row.min, row.max, row.scope))
        end
    end)

    it("AbilityMeta adds a cast above 0 and the word when asked", function()
        local cast = { minRange = 0, maxRange = 30, castTime = 2500, word = "Stun" }
        local instant = { minRange = 0, maxRange = 30, castTime = 0, word = "Stun" }
        for _, row in ipairs({
            { view = cast, show = true, want = "30 yd" .. DOT .. "2.5s cast" .. DOT .. "<amber:Stun>" },
            { view = cast, show = false, want = "30 yd" .. DOT .. "2.5s cast" },
            { view = instant, show = true, want = "30 yd" .. DOT .. "<amber:Stun>" },
            { view = instant, show = false, want = "30 yd" },
        }) do
            assert.equals(row.want, Rules.AbilityMeta(row.view, row.show, paint))
        end
    end)

    it("ArmorInput uses the mob's own armor, else estimates from the level table", function()
        local byLevel = {}
        for level = 1, 20 do byLevel[level] = level * 10 end
        for _, row in ipairs({
            { name = "bare number row", stats = 500, level = 2, armor = 500, estimated = false },
            { name = "table row", stats = { 700, 4 }, level = 2, armor = 700, estimated = false },
            { name = "armor 0 row", stats = { 0, 4 }, level = 2, armor = 20, estimated = true },
            { name = "no row", level = 2, armor = 20, estimated = true },
            { name = "physical immune", stats = { 500, 1 }, level = 2 },
            { name = "known level clamps", level = 99, armor = 200, estimated = true },
            { name = "world boss", level = -1, class = "worldboss", armor = 200, estimated = true },
            { name = "unknown level", level = -1, player = 3, armor = 130, estimated = true },
            { name = "unknown level clamps", level = -1, player = 15, armor = 200, estimated = true },
            { name = "secret level, no armor of its own" },
            { name = "secret level, own armor", stats = 500, armor = 500, estimated = false },
        }) do
            local armor, estimated = Rules.ArmorInput(row.stats, row.level, row.class, row.player or 10, byLevel)
            assert.equals(row.armor, armor, row.name)
            assert.equals(row.estimated, estimated, row.name)
        end
    end)

    it("ArmorLine formats the game's effectiveness, and leaves the right side off without a number", function()
        for _, row in ipairs({
            { estimated = false, value = 0.255, left = "<accent:Armor> <gold:544>", right = "Your physical <gold:-25.5%>" },
            { estimated = true, value = 0.255, left = "<accent:Armor> <gold:~544>", right = "Your physical <gold:-25.5%>" },
            { estimated = false, left = "<accent:Armor> <gold:544>" },
        }) do
            local left, right = Rules.ArmorLine(544, row.estimated, row.value, paint)
            assert.equals(row.left, left)
            assert.equals(row.right, right)
        end
    end)

    it("FamilyLine names each tame state, and gives nothing for a secret level", function()
        for _, row in ipairs({
            { tame = true, level = 10, text = "Wolf" .. DOT .. "Tameable", color = "green" },
            { tame = false, level = 10, text = "Wolf" .. DOT .. "Untameable", color = "red" },
            { tame = true, level = 12, text = "Wolf" .. DOT .. "Untameable until level 12", color = "red" },
            { tame = true, level = -1, text = "Wolf" .. DOT .. "Untameable at your level", color = "red" },
            { tame = true },
        }) do
            local text, color = Rules.FamilyLine("Wolf", row.tame, row.level, 10)
            assert.equals(row.text, text)
            assert.equals(row.color, color)
        end
    end)

    it("TameKnown takes a tame flag or a stats row, and never abilities alone", function()
        local data = { stats = { [1] = 544 }, tame = { [2] = true }, abilities = { [3] = { 100 } } }
        for _, row in ipairs({
            { id = 1, want = true },
            { id = 2, want = true },
            { id = 3, want = false },
            { id = 4, want = false },
        }) do
            assert.equals(row.want, Rules.TameKnown(data, row.id), tostring(row.id))
        end
    end)

    it("IsScriptSpell answers for a listed id and no other", function()
        assert.is_true(Rules.IsScriptSpell(23159))
        assert.is_false(Rules.IsScriptSpell(1))
        assert.is_false(Rules.IsScriptSpell(nil))
    end)

    describe("BuildLines", function()
        local FAMILY, HEADER, ROW = "Pet family", "<accent:Abilities>", "<white:Bite>"
        local ARMOR, IMMUNE, RESIST = "<accent:Armor> <gold:544>", "Immune: Fire, Stun", "Resists: Fire 30"

        local function baseView(change)
            local view = {
                tameKnown = true, family = "Wolf", tameable = true, mobLevel = 10, playerLevel = 10,
                abilities = { { name = "Bite", minRange = 0, maxRange = 5, castTime = 0, word = "Stun" } },
                armor = 544, estimated = false, effectiveness = 0.255,
                schoolMask = 4, mechanicMask = 2 ^ 11, resists = { 0, 30, 0, 0, 0, 0 },
            }
            for k, v in pairs(change or {}) do view[k] = v end
            return view
        end

        local function baseOpts(change)
            local opts = {
                abilities = true, controlWords = true, armor = true, immunities = true,
                petFamily = true, keyHint = true, class = "HUNTER", keyName = "Ctrl",
            }
            for k, v in pairs(change or {}) do opts[k] = v end
            return opts
        end

        local function lefts(lines)
            local out = {}
            for i, line in ipairs(lines) do out[i] = line.left end
            return out
        end

        it("keeps the order, and each switch removes only its own lines", function()
            for _, row in ipairs({
                { name = "all on", want = { FAMILY, HEADER, ROW, ARMOR, IMMUNE, RESIST } },
                { name = "family box off", opts = { petFamily = false }, want = { HEADER, ROW, ARMOR, IMMUNE, RESIST } },
                { name = "abilities box off", opts = { abilities = false }, want = { FAMILY, ARMOR, IMMUNE, RESIST } },
                { name = "armor box off", opts = { armor = false }, want = { FAMILY, HEADER, ROW, IMMUNE, RESIST } },
                { name = "immunities box off", opts = { immunities = false }, want = { FAMILY, HEADER, ROW, ARMOR } },
                { name = "not a hunter", opts = { class = "PRIEST" }, want = { HEADER, ROW, ARMOR, IMMUNE, RESIST } },
                { name = "beast the table cannot answer for", view = { tameKnown = false }, want = { HEADER, ROW, ARMOR, IMMUNE, RESIST } },
                { name = "secret mob level", view = { mobLevel = false }, want = { HEADER, ROW, ARMOR, IMMUNE, RESIST } },
                { name = "no armor reading", view = { armor = false }, want = { FAMILY, HEADER, ROW, IMMUNE, RESIST } },
                { name = "no ability left", view = { abilities = {} }, want = { FAMILY, ARMOR, IMMUNE, RESIST } },
            }) do
                local view = baseView(row.view)
                if view.mobLevel == false then view.mobLevel = nil end
                if view.armor == false then view.armor = nil end
                assert.same(row.want, lefts(Rules.BuildLines(view, baseOpts(row.opts), paint)), row.name)
            end
        end)

        it("gives a mob not in the table its armor estimate only", function()
            local lines = Rules.BuildLines({
                tameKnown = false, abilities = {}, mobLevel = 10, playerLevel = 10,
                armor = 544, estimated = true, effectiveness = 0.2,
                schoolMask = 0, mechanicMask = 0, resists = { 0, 0, 0, 0, 0, 0 },
            }, baseOpts(), paint)
            assert.same({ "<accent:Armor> <gold:~544>" }, lefts(lines))
        end)

        it("caps the ability rows at 8", function()
            local abilities = {}
            for i = 1, 10 do abilities[i] = { name = "Spell " .. i, minRange = 0, maxRange = 5, castTime = 0 } end
            local lines = Rules.BuildLines(baseView({ abilities = abilities }),
                baseOpts({ petFamily = false, armor = false, immunities = false }), paint)
            assert.equals(9, #lines)
            assert.equals("<white:Spell 1>", lines[2].left)
            assert.equals("<white:Spell 8>", lines[9].left)
        end)

        it("writes the hint, the word and the icon on the ability lines", function()
            for _, row in ipairs({
                { opts = {}, hint = "Ctrl: details", meta = "Melee" .. DOT .. "<amber:Stun>" },
                { opts = { keyHint = false, controlWords = false }, meta = "Melee" },
            }) do
                local lines = Rules.BuildLines(baseView(), baseOpts(row.opts), paint)
                assert.equals(row.hint, lines[2].right)
                assert.equals(row.meta, lines[3].right)
            end
            local withIcon = baseView({ abilities = { { name = "Bite", icon = 123, minRange = 0, maxRange = 5, castTime = 0 } } })
            local left = Rules.BuildLines(withIcon, baseOpts(), paint)[3].left
            assert.truthy(left:find("|T123:", 1, true))
            assert.truthy(left:find("<white:Bite>", 1, true))
        end)

        it("returns the full immunity text only when the line collapsed, and wraps both text lines", function()
            local lines, full = Rules.BuildLines(baseView({ schoolMask = 126, mechanicMask = 0 }), baseOpts(), paint)
            assert.equals("Immune: Holy, Fire, Nature, Frost, Shadow, Arcane", full)
            assert.equals("Immune: <red:Nature>, <red:Arcane>, + 4 more", lines[5].left)
            assert.is_true(lines[5].wrap)
            assert.is_true(lines[6].wrap)
            local _, notCollapsed = Rules.BuildLines(baseView(), baseOpts(), paint)
            assert.is_nil(notCollapsed)
        end)
    end)

    it("DetailsBelow fits the block under the tooltip, and turns upward on a nil reading", function()
        for _, row in ipairs({
            { bottom = 300, height = 200, gap = 2, want = true },
            { bottom = 202, height = 200, gap = 2, want = true },
            { bottom = 100, height = 200, gap = 2, want = false },
            { height = 200, gap = 2, want = false },
            { bottom = 300, gap = 2, want = false },
            { bottom = 300, height = 200, want = false },
        }) do
            assert.equals(row.want, Rules.DetailsBelow(row.bottom, row.height, row.gap))
        end
    end)
end)

describe("Scout defaults", function()
    it("adds a block on a baseline load only, switched off", function()
        local retail = helpers.loadModule("Core/Defaults.lua")
        assert.is_nil(retail:GetDefaultDB().profile.Scout)
        local baseline = helpers.loadModule("Core/Defaults.lua", { BASELINE_LOAD = true })
        assert.is_false(baseline:GetDefaultDB().profile.Scout.Enabled)
    end)
end)
