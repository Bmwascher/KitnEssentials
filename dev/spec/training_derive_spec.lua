-- Tier 1: the rules of What's Training's data script, on rows built here. The
-- shipped tables are never pinned; --check holds them to these rules.
local helpers = require("dev.spec._helpers")

local Derive = dofile("dev/scripts/_training_derive.lua")
local Text = dofile("dev/scripts/_lua_text.lua")
local CSV = dofile("dev/scripts/_db2_csv.lua")
local FileMatches = dofile("dev/scripts/_scout_spells_derive.lua").FileMatches

local TEMP_CSV = "dev/spec/.training_derive_temp.csv"

local RACES = {
    { ID = "1", PlayableRaceBit = "0" }, { ID = "2", PlayableRaceBit = "1" },
    { ID = "3", PlayableRaceBit = "2" }, { ID = "4", PlayableRaceBit = "3" },
    { ID = "5", PlayableRaceBit = "4" }, { ID = "6", PlayableRaceBit = "5" },
    { ID = "7", PlayableRaceBit = "6" }, { ID = "8", PlayableRaceBit = "7" },
    { ID = "95", PlayableRaceBit = "32" }, { ID = "96", PlayableRaceBit = "33" },
    { ID = "33", PlayableRaceBit = "-1" },
}

local function ability(id, classMask, mask0, mask1, supercedes)
    return {
        Spell = tostring(id), ClassMask = tostring(classMask), RaceMasks_0 = tostring(mask0),
        RaceMasks_1 = tostring(mask1), SupercedesSpell = tostring(supercedes or 0),
    }
end

local function client(ids, abilities, noLevel, noName)
    local names, levels = {}, {}
    for _, id in ipairs(ids) do
        if id ~= noName then names[#names + 1] = { ID = tostring(id), Name_lang = "Spell " .. id } end
        if id ~= noLevel then
            levels[#levels + 1] = { SpellID = tostring(id), DifficultyID = "0", SpellLevel = "10" }
        end
    end
    return Derive.Client({
        SpellName = names, SpellLevels = levels, SkillLineAbility = abilities or {}, ChrRaces = RACES,
    }, CSV.num)
end

local function rowsById(rows)
    local byId = {}
    for _, row in ipairs(rows) do byId[row[2]] = row end
    return byId
end

describe("What's Training data rules", function()
    it("_lua_text reads tables, nesting, comments and bare names, and refuses code", function()
        local data = Text.ReadTable(
            "local x = 1\nns.T = { [1] = { 10, \"a\", b = true, c = nil, -- note\n" ..
            "  d = bare, e = { 1.5, -2 }, --[[ more ]] nil, 7 }, [\"k\"] = 'v\\'s' }\nns.U = { 9 }", "ns.T")
        assert.equals(10, data[1][1])
        assert.equals("a", data[1][2])
        assert.is_true(data[1].b)
        assert.equals("bare", data[1].d)
        assert.equals(-2, data[1].e[2])
        assert.is_nil(data[1][3])
        assert.equals(7, data[1][4])
        assert.equals("v's", data.k)
        local listed = Text.ReadTable("ns.T = { [1] = { { 52, 11551, 39000, needs = 11550, replacedBy = 25289 } } }", "ns.T")
        assert.equals(25289, listed[1][1].replacedBy)
        for _, row in ipairs({
            { name = "a function", text = "ns.T = { a = function() end }" },
            { name = "a call", text = "ns.T = { a = call() }" },
            { name = "no such table", text = "ns.U = {}" },
            { name = "unterminated", text = "ns.T = { 1, " },
        }) do
            assert.is_false((pcall(Text.ReadTable, row.text, "ns.T")), row.name)
        end
    end)

    it("merges price, needs and level by source order", function()
        local c = client({ 100, 101, 102, 200, 300 }, { ability(300, 1, 0, 0, 299) })
        local rows = rowsById(Derive.ClassRows(1, {
            spellsA = { [1] = { { 10, 100, 500 }, { 10, 101, 500, needs = 100 }, { 10, 102, 700 } } },
            levelsB = { [1] = { [10] = { { id = 100, cost = 300 }, { id = 200, cost = 900, requiredIds = { 150, 151 } }, { id = 102 } } } },
            questB = { [1] = { [200] = {}, [300] = {} } },
        }, c, {}))
        for _, row in ipairs({
            { name = "the second source first", id = 100, cost = 300 },
            { name = "the first source where the second has no row", id = 101, cost = 500, needs = 100 },
            { name = "a row with no cost reads 0", id = 102, cost = 0 },
            { name = "a quest-table row takes its level row's first requirement", id = 200, cost = 900, needs = 150 },
            { name = "a quest-table row with no level row takes the client's chain", id = 300, cost = 0, needs = 299 },
        }) do
            assert.equals(row.cost, rows[row.id][3], row.name)
            assert.equals(row.needs, rows[row.id].needs, row.name)
            assert.equals(10, rows[row.id][1], row.name)
        end
    end)

    it("reads races from the client's masks, with no limit at 0/0, -1/-1 and all ten", function()
        for _, row in ipairs({
            { name = "low bits", mask0 = 5, mask1 = 0, want = { 1, 3 } },
            { name = "bits 32 and 33", mask0 = 0, mask1 = 3, want = { 95, 96 } },
            { name = "both words", mask0 = 1, mask1 = 2, want = { 1, 96 } },
            { name = "a signed low word", mask0 = -1, mask1 = 0, want = { 1, 2, 3, 4, 5, 6, 7, 8 } },
            { name = "0/0", mask0 = 0, mask1 = 0 },
            { name = "-1/-1", mask0 = -1, mask1 = -1 },
            { name = "all ten", mask0 = 255, mask1 = 3 },
            { name = "another class's row", classMask = 2, mask0 = 5, mask1 = 0 },
        }) do
            local c = client({ 100 }, { ability(100, row.classMask or 1, row.mask0, row.mask1) })
            assert.same(row.want, Derive.Races(c, 100, 1), row.name)
        end
    end)

    it("gives maybe where both hold a row and their flags differ, and a flag where one is silent or they agree", function()
        local c = client({ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 50, 60, 70 })
        local rows = rowsById(Derive.ClassRows(1, {
            spellsA = { [1] = {
                { 10, 1, 0, quest = true }, { 10, 2, 0, quest = true }, { 10, 3, 100 }, { 10, 5, 100 },
                { 10, 6, 100, talent = 50 }, { 10, 7, 100, talent = 50 }, { 10, 8, 100 }, { 10, 9, 100, talent = 50 },
                { 10, 11, 100, talent = 50 }, { 10, 12, 0, quest = true }, { 10, 13, 100 },
                { 10, 15, 100, talent = 99 }, { 10, 16, 100, talent = 99 },
            } },
            levelsB = { [1] = { [10] = {
                { id = 3, cost = 100 }, { id = 5, cost = 100 }, { id = 12, cost = 100 },
                { id = 6, cost = 100, requiredTalentId = 50 }, { id = 7, cost = 100 },
                { id = 8, cost = 100, requiredTalentId = 50 }, { id = 9, cost = 100, requiredTalentId = 60 },
                { id = 10, cost = 100, requiredTalentId = 70 }, { id = 11, cost = 100, requiredTalentId = 99 },
                { id = 13, cost = 100, requiredTalentId = 99 }, { id = 14, cost = 100, requiredTalentId = 99 },
                { id = 16, cost = 100, requiredTalentId = 50 },
            } } },
            questB = { [1] = { [1] = {}, [3] = {}, [4] = {}, [10] = {}, [14] = {} } },
        }, c, {}))
        for _, row in ipairs({
            { name = "both say quest", id = 1, quest = true },
            { name = "the first says quest and the second is silent on the row", id = 2, quest = true },
            { name = "the first says quest and the second sells it with no quest", id = 12, quest = "maybe" },
            { name = "the second says quest and the first holds it with none", id = 3, quest = "maybe" },
            { name = "only the second holds the row", id = 4, quest = true },
            { name = "neither says quest", id = 5 },
            { name = "same root", id = 6, talent = 50 },
            { name = "only the first has a root", id = 7, talent = "maybe" },
            { name = "only the second has a root", id = 8, talent = "maybe" },
            { name = "different roots", id = 9, talent = "maybe" },
            { name = "a root on a row only the second holds", id = 10, quest = true, talent = 70 },
            { name = "a second root the client cannot name", id = 11, talent = 50 },
            { name = "only an unnamed second root", id = 13 },
            { name = "an unnamed root on a row only the second holds", id = 14, quest = true },
            { name = "an unnamed root on a row only the first holds", id = 15 },
            { name = "an unnamed first root beside a named second", id = 16, talent = 50 },
        }) do
            assert.equals(row.quest, rows[row.id].quest, row.name)
            assert.equals(row.talent, rows[row.id].talent, row.name)
        end
    end)

    it("refuses a row with no client name or level, a missing column, and an unknown weapon", function()
        local inputs = { spellsA = { [1] = { { 10, 100, 500 } } }, levelsB = {}, questB = {} }
        for _, row in ipairs({
            { name = "no name", client = client({ 100 }, nil, nil, 100) },
            { name = "no level", client = client({ 100 }, nil, 100) },
        }) do
            local ok, err = pcall(Derive.ClassRows, 1, inputs, row.client, {})
            assert.is_false(ok, row.name)
            assert.truthy(tostring(err):find("100", 1, true), row.name)
        end

        local file = assert(io.open(TEMP_CSV, "wb"))
        file:write("ID\n1\n")
        file:close()
        local ok, err = pcall(CSV.read, TEMP_CSV, { "ID", "Name_lang" })
        os.remove(TEMP_CSV)
        assert.is_false(ok)
        assert.truthy(tostring(err):find("Name_lang", 1, true))

        local weaponOk, weaponErr = pcall(Derive.Weapons, 1, { weaponsA = { [1] = { { 1, 196, 0 } } } }, client({}))
        assert.is_false(weaponOk)
        assert.truthy(tostring(weaponErr):find("196", 1, true))
    end)

    it("ships no untrainable id, whichever input holds it, and keeps a talent that points at one", function()
        local c = client({ 1, 5, 6, 7, 197 })
        local lists = { untrainable = { 1, 2, 3, 4, 9, 196 } }
        local rows, leftOut, removed = Derive.ClassRows(1, {
            spellsA = { [1] = { { 10, 1, 100 }, { 10, 5, 100, needs = 1 }, { 10, 6, 100, talent = 1 } } },
            levelsB = { [1] = { [10] = { { id = 2, cost = 100 }, { id = 7, cost = 100, requiredIds = { 2 } } } } },
            questB = { [1] = { [3] = {}, [4] = {}, [7] = {} } },
        }, c, lists)
        local byId = rowsById(rows)
        assert.equals(3, #rows)
        assert.same({ 1, 2, 3, 4 }, removed)
        assert.equals(0, leftOut)
        assert.is_nil(byId[5].needs)
        assert.is_nil(byId[7].needs)
        assert.equals(1, byId[6].talent)

        local weapons, weaponsRemoved = Derive.Weapons(1, {
            weaponsA = { [1] = { { 1, 196, 0 }, { 1, 197, 0 } } },
        }, c, lists)
        assert.equals(1, #weapons)
        assert.equals(197, weapons[1][2])
        assert.same({ 196 }, weaponsRemoved)
    end)

    it("lists the spells that replace a row or an outside rank, and checks the first source's own list", function()
        local c = client({ 1, 2, 3, 6, 8, 30 }, {
            ability(2, 1, 0, 0, 1),
            ability(20, 1, 0, 0, 2), ability(21, 1, 0, 0, 20),
            ability(30, 1, 0, 0, 3),
            ability(50, 1, 0, 0, 5), ability(6, 1, 0, 0, 5),
            ability(32, 2, 0, 0, 8),
        })
        local spellsA = {
            { 10, 1, 100 }, { 10, 2, 100, needs = 1, replacedBy = 20 }, { 10, 3, 100, replacedBy = 99 },
            { 12, 30, 100 }, { 10, 6, 100, needs = 5 }, { 10, 8, 100 },
        }
        local rows = Derive.ClassRows(1, { spellsA = { [1] = spellsA }, levelsB = {}, questB = {} }, c, {})
        for _, row in ipairs(rows) do assert.is_nil(row.replacedBy) end
        local replaced = Derive.Replaced(1, rows, c)
        -- 1: its later rank needs it. 2: two outside spells in a chain. 3: a row that does
        -- not need it. 5: a needs rank outside the rows. 8: another class's spell.
        assert.same({ [2] = { 20, 21 }, [3] = { 30 }, [5] = { 50 } }, replaced)
        assert.same({ "3 replaced by 99 in the list, not in the client" }, Derive.ReplacedCheck(spellsA, rows, replaced))
        spellsA[2].replacedBy = nil
        assert.same({ "2 replaced by 20, 21 in the client, not in the list", "3 replaced by 99 in the list, not in the client" },
            Derive.ReplacedCheck(spellsA, rows, replaced))
    end)

    it("writes sources that build, and --check takes the whole file, line ends aside", function()
        local c = client({ 100, 196 }, { ability(100, 1, 5, 0) })
        local rows = Derive.ClassRows(1, { spellsA = { [1] = { { 10, 100, 500, quest = true } } }, levelsB = {}, questB = {} }, c, {})
        local weapons = Derive.Weapons(1, { weaponsA = { [1] = { { 1, 196, 0, masters = { "Mae" } }, { 20, 196, 0 } } } }, c)
        local class = assert(loadstring(table.concat(Derive.ClassSource(rows, weapons, "1.2.3", { [100] = { 900, 901 } }), "\n")))()
        assert.same({ 900, 901 }, class.replaced[100])
        local plain = assert(loadstring(table.concat(Derive.ClassSource(rows, weapons, "1.2.3", {}), "\n")))()
        assert.is_nil(plain.replaced)
        assert.equals("1.2.3", class.build)
        assert.equals(100, class.spells[1][2])
        assert.same({ 1, 3 }, class.spells[1].races)
        assert.is_true(class.spells[1].quest)
        assert.equals("Mae", class.weapons[1].masters[1])
        assert.is_nil(class.weapons[2].masters)

        local route = assert(loadstring(table.concat(Derive.RouteSource({
            capitals = { [9] = true },
            npcs = { [9] = {
                { 1.5, 2.5, "class", "Ann", "Mage Trainer", "MAGE", "A" },
                { 3, 4, "profession", "Bo", "Weapon Master", nil, "H" },
                { 5, 6, "vendor", "Cy", "General Goods", nil, "H" },
            } },
        }, "1.2.3"), "\n")))()
        assert.is_true(route.capitals[9])
        assert.equals(2, #route.npcs)
        assert.equals("MAGE", route.npcs[1][6])
        assert.is_false(route.npcs[2][6])
        assert.equals("H", route.npcs[2][7])

        local Rules = helpers.loadModule("Modules/QoL/WhatsTraining/TrainingRules.lua").TrainingRules
        assert.is_true(Rules.ClassDataValid(class))
        assert.is_true(Rules.RouteDataValid(route))

        local lines = { "a", "b" }
        for _, row in ipairs({
            { name = "exact", text = "a\nb\n", want = 0 },
            { name = "CRLF", text = "a\r\nb\r\n", want = 0 },
            { name = "a changed line", text = "a\nc\n", want = 1 },
            { name = "an extra line", text = "a\nb\nc\n", want = 1 },
            { name = "a missing file", want = 1 },
        }) do
            local failed = Derive.Check({ { path = "x", lines = lines } }, function() return row.text end, FileMatches)
            assert.equals(row.want, #failed, row.name)
        end
    end)
end)
