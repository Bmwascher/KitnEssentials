-- Tier 1: the rules of Scout's spell table derivation
-- (dev/scripts/_scout_spells_derive.lua), on rows built here. The shipped
-- table is never pinned; --check holds it to these rules against game data.
local Derive = dofile("dev/scripts/_scout_spells_derive.lua")
local CSV = dofile("dev/scripts/_db2_csv.lua")
local Source = dofile("dev/scripts/_data_source.lua")

local RANGE_ZERO, RANGE_THIRTY = "1", "2"

local function run(fields)
    local spellIds, names, misc = {}, {}, {}
    for _, id in ipairs(fields.ids) do
        spellIds[#spellIds + 1] = id
        names[#names + 1] = { ID = tostring(id), Name_lang = "Spell" }
        misc[#misc + 1] = { SpellID = tostring(id), DifficultyID = "0", RangeIndex = fields.range or RANGE_ZERO }
    end
    return Derive.Run({
        SpellName = fields.names or names,
        SpellCategories = fields.categories or {},
        SpellEffect = fields.effects or {},
        SpellMisc = misc,
        SpellRange = {
            { ID = RANGE_ZERO, RangeMax_0 = "0" },
            { ID = RANGE_THIRTY, RangeMax_0 = "30" },
        },
    }, { spellIds = spellIds, num = CSV.num, wrap = Source.Wrap })
end

local function category(mechanic, difficulty)
    return { SpellID = "100", DifficultyID = difficulty or "0", Mechanic = mechanic }
end

local function effect(index, mechanic, target0, target1, difficulty)
    return {
        SpellID = "100", DifficultyID = difficulty or "0", EffectIndex = index, EffectMechanic = mechanic,
        ImplicitTarget_0 = target0 or "0", ImplicitTarget_1 = target1 or "0",
    }
end

describe("Scout spell table derivation", function()
    it("takes the word from categories, then effects in index order, skipping unmapped ids", function()
        for _, row in ipairs({
            { name = "categories first", categories = { category("12") }, effects = { effect("0", "5") }, want = "Stun" },
            { name = "effect index order", effects = { effect("1", "5"), effect("0", "7") }, want = "Root" },
            { name = "unmapped ids skipped", categories = { category("4") },
              effects = { effect("0", "15"), effect("1", "9") }, want = "Silence" },
            { name = "mechanic 8 is Slow", effects = { effect("0", "8") }, want = "Slow" },
            { name = "mechanic 11 is Slow", effects = { effect("0", "11") }, want = "Slow" },
            { name = "other difficulties ignored", categories = { category("12", "1") }, effects = { effect("0", "5", "0", "0", "2") } },
            { name = "nothing mapped", effects = { effect("0", "0") } },
        }) do
            local _, words = run({ ids = { 100 }, categories = row.categories, effects = row.effects })
            assert.equals(row.want, words[100], row.name)
        end
    end)

    it("gives a range-0 spell its scope, and any other spell none", function()
        for _, row in ipairs({
            { name = "cone in the first target", t0 = "24", want = "Cone" },
            { name = "cone in the second target", t0 = "22", t1 = "24", want = "Cone" },
            { name = "22 with 15", t0 = "22", t1 = "15", want = "Around it" },
            { name = "22 with 30", t0 = "22", t1 = "30", want = "Around it" },
            { name = "22 with 7", t0 = "22", t1 = "7", want = "Around it" },
            { name = "15 alone", t0 = "15", want = "Around it" },
            { name = "30 alone", t0 = "30", want = "Around it" },
            { name = "self prints no row", t0 = "1" },
            { name = "above range 0", t0 = "24", range = RANGE_THIRTY },
        }) do
            local _, _, scopes = run({ ids = { 100 }, range = row.range, effects = { effect("0", "0", row.t0, row.t1) } })
            assert.equals(row.want, scopes[100], row.name)
        end
    end)

    it("prints both tables in id order, as a stored source that builds with no mob table present", function()
        local lines = run({
            ids = { 300, 100 },
            categories = { category("12"), { SpellID = "300", DifficultyID = "0", Mechanic = "5" } },
            effects = {
                effect("0", "0", "24"),
                { SpellID = "300", DifficultyID = "0", EffectIndex = "0", EffectMechanic = "0",
                  ImplicitTarget_0 = "15", ImplicitTarget_1 = "0" },
            },
        })
        local text = table.concat(lines, "\n")
        assert.truthy(text:find('words={\n    [100]="Stun",\n    [300]="Fear",\n},', 1, true))
        assert.truthy(text:find('scopes={\n    [100]="Cone",\n    [300]="Around it",\n},', 1, true))
        local ns = {}
        local chunk = assert(loadstring(text))
        setfenv(chunk, { KitnEssentials = { GetNamespace = function() return ns end } })
        chunk()
        local spells = assert(loadstring(ns.DataSources.ScoutSpells))()
        assert.equals("Stun", spells.words[100])
        assert.equals("Around it", spells.scopes[300])
    end)

    it("Wrap refuses a source holding the closing long-bracket, naming the table", function()
        local ok, err = pcall(Source.Wrap, "ScoutSpells", "a script", { "return {", "x]==]y", "}" })
        assert.is_false(ok)
        assert.truthy(tostring(err):find("ScoutSpells", 1, true))
    end)

    it("FileMatches takes the whole file, line ends aside", function()
        local lines = { "a", "b" }
        for _, row in ipairs({
            { name = "exact", text = "a\nb\n", want = true },
            { name = "CRLF", text = "a\r\nb\r\n", want = true },
            { name = "a line added after", text = "a\nb\nc\n", want = false },
            { name = "a line added before", text = "c\na\nb\n", want = false },
            { name = "a line changed", text = "a\nc\n", want = false },
        }) do
            assert.equals(row.want, Derive.FileMatches(row.text, lines), row.name)
        end
    end)

    it("refuses a spell id with no name, naming it", function()
        local ok, err = pcall(run, { ids = { 100 }, names = {} })
        assert.is_false(ok)
        assert.truthy(tostring(err):find("100", 1, true))
    end)
end)
