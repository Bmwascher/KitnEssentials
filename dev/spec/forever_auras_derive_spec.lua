-- Tier 1: refusal rules of the Forever aura list derivation
-- (dev/scripts/_forever_auras_derive.lua). The real extracts hold none of
-- these inputs, so a refusal that stopped firing would leave the derived
-- lists unchanged; only these rows see it. The rows are built here.
local Derive = dofile("dev/scripts/_forever_auras_derive.lua")
local CSV = dofile("dev/scripts/_db2_csv.lua")

local LISTS = { { key = "a", name = "A" } }
local SHIELD = { list = "a", class = 2, name = "Shield", enabled = true }

-- Spell 100 "Shield" is a Paladin rank (class 2 is ClassMask bit 1) that
-- applies an aura. Item 900 gives spell 200, which applies one; spell 201
-- applies one too and spell 300 none.
local function baseTables()
    return {
        SpellName = {
            { ID = "100", Name_lang = "Shield" },
            { ID = "101", Name_lang = "Shield" },
            { ID = "200", Name_lang = "Stone" },
            { ID = "201", Name_lang = "Stone" },
            { ID = "300", Name_lang = "Bare" },
        },
        SkillLineAbility = {
            { SkillLine = "10", Spell = "100", ClassMask = "2", SupercedesSpell = "0", AcquireMethod = "0", RaceMasks_0 = "0" },
        },
        SpellEffect = {
            { SpellID = "100", DifficultyID = "0", Effect = "6", EffectTriggerSpell = "0" },
            { SpellID = "101", DifficultyID = "0", Effect = "6", EffectTriggerSpell = "0" },
            { SpellID = "200", DifficultyID = "0", Effect = "6", EffectTriggerSpell = "0" },
            { SpellID = "201", DifficultyID = "0", Effect = "6", EffectTriggerSpell = "0" },
            { SpellID = "300", DifficultyID = "0", Effect = "3", EffectTriggerSpell = "0" },
        },
        SpellLevels = {},
        ItemEffect = { { ID = "1", SpellID = "200" } },
        ItemXItemEffect = { { ItemEffectID = "1", ItemID = "900" } },
    }
end

local function run(tables, entries)
    return pcall(Derive.Run, tables, { entries = entries, lists = LISTS, classless = {}, num = CSV.num })
end

describe("Forever aura derivation: refusals", function()
    it("refuses an input it cannot derive, naming the cause", function()
        for _, row in ipairs({
            { name = "no rank", entries = { { list = "a", class = 2, name = "Missing", enabled = true } },
              want = "no rank of Missing for class 2" },
            { name = "no aura, no trigger", entries = { { list = "a", class = 2, name = "Bare", enabled = true } },
              edit = function(t)
                  t.SkillLineAbility[2] = { SkillLine = "10", Spell = "300", ClassMask = "2", SupercedesSpell = "0", AcquireMethod = "0", RaceMasks_0 = "0" }
              end,
              want = "300 Bare applies no aura and triggers none" },
            { name = "item with no aura", entries = { { list = "a", item = 901, itemName = "Pebble", enabled = true } },
              want = "item 901 Pebble gives no aura" },
            { name = "item with two auras", entries = { { list = "a", item = 900, itemName = "Rock", enabled = true } },
              edit = function(t)
                  t.ItemEffect[2] = { ID = "2", SpellID = "201" }
                  t.ItemXItemEffect[2] = { ItemEffectID = "2", ItemID = "900" }
              end,
              want = "item 900 Rock gives more than one aura" },
            { name = "id from two entries", entries = { SHIELD, SHIELD },
              want = "100 is produced by two entries" },
        }) do
            local tables = baseTables()
            if row.edit then row.edit(tables) end
            local ok, err = run(tables, row.entries)
            assert.is_false(ok, row.name)
            assert.equals(row.want, err, row.name)
        end
    end)

    -- Spell 101 shares the rank's name and class; each row breaks one guard.
    it("leaves out a row with no trainer, a race mask or an unmapped classless line", function()
        for _, row in ipairs({
            { name = "no trainer",              field = "AcquireMethod", value = "3" },
            { name = "race mask",               field = "RaceMasks_0",   value = "1" },
            { name = "unmapped classless line", field = "ClassMask",     value = "0" },
        }) do
            local tables = baseTables()
            local extra = { SkillLine = "99", Spell = "101", ClassMask = "2", SupercedesSpell = "0", AcquireMethod = "0", RaceMasks_0 = "0" }
            extra[row.field] = row.value
            tables.SkillLineAbility[2] = extra
            local ok, lines = run(tables, { SHIELD })
            assert.is_true(ok, row.name)
            assert.same({
                "local A = {",
                "    [100] = { enabled = true, default = true },  -- Shield",
                "}",
            }, lines, row.name)
        end
    end)
end)
