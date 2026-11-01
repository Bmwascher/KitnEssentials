-- Tier 1: the refusals and the merge rule of the Forever CC Tracker list
-- derivation (dev/scripts/_forever_cc_derive.lua). The real extracts
-- trigger none of the refusals, so only these rows see one stop working.
-- The rows are built here.
local Derive = dofile("dev/scripts/_forever_cc_derive.lua")
local CSV = dofile("dev/scripts/_db2_csv.lua")

-- Spell 100 "Hold" is a Mage rank (class 8 is ClassMask bit 7) whose
-- debuff carries mechanic 17. Spell 200 "Trap" is a Hunter rank (class 3,
-- bit 2) that applies nothing; spell 201 "Trap" is its debuff, mechanic 13;
-- spell 202 "Snare" is another debuff with mechanic 13; spell 203 "Trap"
-- carries mechanic 13 and applies no aura.
local function baseTables()
    return {
        SpellName = {
            { ID = "100", Name_lang = "Hold" },
            { ID = "200", Name_lang = "Trap" },
            { ID = "201", Name_lang = "Trap" },
            { ID = "202", Name_lang = "Snare" },
            { ID = "203", Name_lang = "Trap" },
        },
        SkillLineAbility = {
            { SkillLine = "10", Spell = "100", ClassMask = "128", SupercedesSpell = "0", AcquireMethod = "0", RaceMasks_0 = "0" },
            { SkillLine = "20", Spell = "200", ClassMask = "4", SupercedesSpell = "0", AcquireMethod = "0", RaceMasks_0 = "0" },
        },
        SpellEffect = {
            { SpellID = "100", DifficultyID = "0", Effect = "6", EffectMechanic = "0", EffectTriggerSpell = "0" },
            { SpellID = "200", DifficultyID = "0", Effect = "104", EffectMechanic = "0", EffectTriggerSpell = "0" },
            { SpellID = "201", DifficultyID = "0", Effect = "6", EffectMechanic = "0", EffectTriggerSpell = "0" },
            { SpellID = "202", DifficultyID = "0", Effect = "6", EffectMechanic = "0", EffectTriggerSpell = "0" },
            { SpellID = "203", DifficultyID = "0", Effect = "104", EffectMechanic = "0", EffectTriggerSpell = "0" },
        },
        SpellCategories = {
            { SpellID = "100", DifficultyID = "0", Mechanic = "17" },
            { SpellID = "201", DifficultyID = "0", Mechanic = "13" },
            { SpellID = "202", DifficultyID = "0", Mechanic = "13" },
            { SpellID = "203", DifficultyID = "0", Mechanic = "13" },
        },
        SpellLevels = {},
    }
end

local function entry(fields)
    local e = { key = "K", label = "L", group = "G", default = true }
    for k, v in pairs(fields) do e[k] = v end
    return e
end

local function run(tables, entries)
    return pcall(Derive.Run, tables, { entries = entries, classless = {}, num = CSV.num })
end

describe("Forever CC list derivation", function()
    it("refuses a rank, a debuff or an entry that breaks a rule, naming the cause", function()
        for _, row in ipairs({
            { name = "second name without a rank",
              entries = { entry({ class = 8, names = { "Hold", "Freeze" }, mechanic = 17 }) },
              want = "no rank of Freeze for class 8" },
            { name = "rank with no aura and no trigger",
              entries = { entry({ class = 3, names = { "Trap" }, mechanic = 13 }) },
              want = "200 Trap applies no aura and triggers none" },
            { name = "rank debuff without the mechanic",
              entries = { entry({ class = 8, names = { "Hold" }, mechanic = 5 }) },
              want = "100 Hold lacks mechanic 5" },
            { name = "listed debuff with another name",
              entries = { entry({ class = 3, names = { "Trap" }, mechanic = 13, debuffs = { 202 } }) },
              want = "202 is not Trap" },
            { name = "listed debuff with no aura",
              entries = { entry({ class = 3, names = { "Trap" }, mechanic = 13, debuffs = { 203 } }) },
              want = "203 Trap applies no aura" },
            { name = "listed debuff without the mechanic",
              entries = { entry({ class = 3, names = { "Trap" }, mechanic = 5, debuffs = { 201 } }) },
              want = "201 Trap lacks mechanic 5" },
            { name = "one id from two entries",
              entries = {
                  entry({ class = 8, names = { "Hold" }, mechanic = 17 }),
                  entry({ class = 8, names = { "Hold" }, mechanic = 17 }),
              },
              want = "100 is produced by two entries" },
        }) do
            local ok, err = run(baseTables(), row.entries)
            assert.is_false(ok, row.name)
            assert.equals(row.want, err, row.name)
        end
    end)

    -- Spells 110 and 111 are two "Grip" ranks that apply nothing and both
    -- trigger spell 112, the "Grip" debuff with mechanic 7.
    it("prints a debuff two ranks of one entry trigger once", function()
        local tables = baseTables()
        local function add(list, row) list[#list + 1] = row end
        add(tables.SpellName, { ID = "110", Name_lang = "Grip" })
        add(tables.SpellName, { ID = "111", Name_lang = "Grip" })
        add(tables.SpellName, { ID = "112", Name_lang = "Grip" })
        add(tables.SkillLineAbility, { SkillLine = "10", Spell = "110", ClassMask = "128", SupercedesSpell = "0", AcquireMethod = "0", RaceMasks_0 = "0" })
        add(tables.SkillLineAbility, { SkillLine = "10", Spell = "111", ClassMask = "128", SupercedesSpell = "110", AcquireMethod = "0", RaceMasks_0 = "0" })
        add(tables.SpellEffect, { SpellID = "110", DifficultyID = "0", Effect = "64", EffectMechanic = "0", EffectTriggerSpell = "112" })
        add(tables.SpellEffect, { SpellID = "111", DifficultyID = "0", Effect = "64", EffectMechanic = "0", EffectTriggerSpell = "112" })
        add(tables.SpellEffect, { SpellID = "112", DifficultyID = "0", Effect = "6", EffectMechanic = "7", EffectTriggerSpell = "0" })
        local ok, lines = run(tables, {
            { key = "GRIP", label = "Grip", group = "MAGE", class = 8, names = { "Grip" }, mechanic = 7, default = false },
        })
        assert.is_true(ok, tostring(lines))
        assert.same({
            "KE.CC_TRACKER_SEEDS = {",
            '    { key = "GRIP", label = "Grip", group = "MAGE", default = false, ids = {',
            "        112,",
            "    } },",
            "}",
        }, lines)
    end)
end)
