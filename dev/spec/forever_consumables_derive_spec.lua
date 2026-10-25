-- Tier 1: parse and refusal rules of the Forever consumables derivation
-- (dev/scripts/_forever_consumables_derive.lua). The real game data holds
-- none of these broken inputs, so a refusal that stopped firing would leave
-- the derived tables unchanged; only these rows see it. The rows are built
-- here.
local Derive = dofile("dev/scripts/_forever_consumables_derive.lua")
local CSV = dofile("dev/scripts/_db2_csv.lua")

-- Items: 900 a flask (use spell 100, an aura); 901 an elixir (101, 30
-- minutes); 902 a stone (102, enchant 7 on swords, mask 128); 903 and 904
-- two Wound Poison ranks whose use spells share one name (103 at level 40,
-- 104 at level 32); 905 a Firestone (105, an Effect 360 weapon enchant that
-- is not a poison); 906 a Soulstone (106, an aura). Spells with no item:
-- 107 a Shaman imbue rank, 108 a Warlock Create Soulstone rank making 906,
-- 109 a food buff.
local function baseTables()
    local function item(id, subclass, icon, effectID, spell)
        return { ID = id, ClassID = "0", SubclassID = subclass, IconFileDataID = icon },
            { ID = effectID, SpellID = spell }, { ItemEffectID = effectID, ItemID = id }
    end
    local t = {
        Item = {}, ItemEffect = {}, ItemXItemEffect = {},
        SpellName = {
            { ID = "100", Name_lang = "Supreme Power" },
            { ID = "101", Name_lang = "Agility" },
            { ID = "102", Name_lang = "Sharpen Blade" },
            { ID = "103", Name_lang = "Wound Poison" },
            { ID = "104", Name_lang = "Wound Poison" },
            { ID = "105", Name_lang = "Firestone" },
            { ID = "106", Name_lang = "Soulstone Resurrection" },
            { ID = "107", Name_lang = "Windfury Weapon" },
            { ID = "108", Name_lang = "Create Soulstone" },
            { ID = "109", Name_lang = "Well Fed" },
        },
        SpellEffect = {},
        SpellMisc = { { SpellID = "101", DifficultyID = "0", DurationIndex = "30" } },
        SpellDuration = { { ID = "30", Duration = "1800000" }, { ID = "31", Duration = "600000" } },
        SpellItemEnchantment = { { ID = "7" }, { ID = "8" }, { ID = "9" }, { ID = "10" }, { ID = "11" } },
        SkillLineAbility = {
            { Spell = "107", ClassMask = "64",  SupercedesSpell = "0", AcquireMethod = "0", RaceMasks_0 = "0" },
            { Spell = "108", ClassMask = "256", SupercedesSpell = "0", AcquireMethod = "0", RaceMasks_0 = "0" },
        },
        SpellEquippedItems = {
            { SpellID = "102", EquippedItemClass = "2", EquippedItemSubclass = "128" },
            { SpellID = "103", EquippedItemClass = "2", EquippedItemSubclass = "0" },
            { SpellID = "104", EquippedItemClass = "2", EquippedItemSubclass = "0" },
            { SpellID = "105", EquippedItemClass = "2", EquippedItemSubclass = "0" },
        },
        SpellLevels = {
            { SpellID = "103", DifficultyID = "0", BaseLevel = "40" },
            { SpellID = "104", DifficultyID = "0", BaseLevel = "32" },
        },
    }
    for _, row in ipairs({
        { "900", "3", "1", "1", "100" }, { "901", "2", "2", "2", "101" }, { "902", "8", "3", "3", "102" },
        { "903", "8", "4", "4", "103" }, { "904", "8", "5", "5", "104" }, { "905", "8", "6", "6", "105" },
        { "906", "8", "7", "7", "106" },
    }) do
        local itemRow, effectRow, linkRow = item(row[1], row[2], row[3], row[4], row[5])
        t.Item[#t.Item + 1] = itemRow
        t.ItemEffect[#t.ItemEffect + 1] = effectRow
        t.ItemXItemEffect[#t.ItemXItemEffect + 1] = linkRow
    end
    for _, e in ipairs({
        { "100", "6", "0", "0" }, { "101", "6", "0", "0" }, { "102", "54", "7", "0" },
        { "103", "360", "8", "0" }, { "104", "360", "9", "0" }, { "105", "360", "10", "0" },
        { "106", "6", "0", "0" }, { "107", "360", "11", "0" }, { "108", "24", "0", "906" },
        { "109", "6", "0", "0" },
    }) do
        t.SpellEffect[#t.SpellEffect + 1] = {
            SpellID = e[1], DifficultyID = "0", Effect = e[2], EffectMiscValue_0 = e[3], EffectItemType = e[4],
        }
    end
    return t
end

local function effectOf(t, spell)
    for _, e in ipairs(t.SpellEffect) do
        if e.SpellID == spell then return e end
    end
end

local function run(tables, cfg)
    cfg.num = CSV.num
    return pcall(Derive.Run, tables, cfg)
end

describe("Forever consumables derivation", function()
    it("reads a poison's family and numeral from its use spell's name", function()
        for _, row in ipairs({
            { name = "Instant Poison",          family = "Instant Poison",      numeral = 1 },
            { name = "Deadly Poison V",         family = "Deadly Poison",       numeral = 5 },
            { name = "Occult Poison I",         family = "Occult Poison",       numeral = 1 },
            { name = "Mind-numbing Poison III", family = "Mind-numbing Poison", numeral = 3 },
        }) do
            local family, numeral = Derive.PoisonFamily(row.name)
            assert.equals(row.family, family, row.name)
            assert.equals(row.numeral, numeral, row.name)
        end
    end)

    it("ranks a family's poisons by level when one name covers every rank", function()
        local ok, lines = run(baseTables(), { poisonFamilies = { "Wound Poison" } })
        assert.is_true(ok, tostring(lines))
        local text = table.concat(lines, "\n")
        assert.truthy(text:find('{ item = 904, enchant = 9, kind = "poison", family = "Wound Poison", rank = 1 }', 1, true))
        assert.truthy(text:find('{ item = 903, enchant = 8, kind = "poison", family = "Wound Poison", rank = 2 }', 1, true))
    end)

    it("prints no Effect 360 item outside the listed poison families", function()
        local ok, lines = run(baseTables(), { poisonFamilies = { "Wound Poison" } })
        assert.is_true(ok, tostring(lines))
        assert.falsy(table.concat(lines, "\n"):find("item = 905", 1, true))
    end)

    it("refuses an input it cannot derive, naming the item, spell or family", function()
        local STONE = { { item = 902, kind = "stone", family = "Sharpening Stone", rank = 1 } }
        for _, row in ipairs({
            { name = "flask whose spell applies no aura", cfg = { flasks = { 900 } },
              edit = function(t) effectOf(t, "100").Effect = "3" end,
              want = "item 900 gives no aura" },
            { name = "flask with two aura spells", cfg = { flasks = { 900 } },
              edit = function(t) t.ItemXItemEffect[#t.ItemXItemEffect + 1] = { ItemEffectID = "2", ItemID = "900" } end,
              want = "item 900 gives more than one aura" },
            { name = "flask of the wrong item class", cfg = { flasks = { 900 } },
              edit = function(t) t.Item[1].SubclassID = "2" end,
              want = "item 900 is not a flask" },
            { name = "item seeded twice", cfg = { flasks = { 900, 900 } },
              edit = function() end,
              want = "item 900 is seeded twice" },
            { name = "elixir under 20 minutes", cfg = { elixirs = { 901 } },
              edit = function(t) t.SpellMisc[1].DurationIndex = "31" end,
              want = "item 901 lasts under 20 minutes" },
            { name = "stone whose spell gives no enchant", cfg = { enhancements = STONE },
              edit = function(t) t.SpellItemEnchantment = {} end,
              want = "item 902 gives no enchant" },
            { name = "stone with no weapon requirement", cfg = { enhancements = STONE },
              edit = function(t) t.SpellEquippedItems = {} end,
              want = "item 902 has no weapon requirement" },
            { name = "listed poison family with no poison", cfg = { poisonFamilies = { "Deadly Poison" } },
              edit = function() end,
              want = "no poison of Deadly Poison" },
            { name = "item with two poison spells", cfg = { poisonFamilies = { "Wound Poison" } },
              edit = function(t) t.ItemXItemEffect[#t.ItemXItemEffect + 1] = { ItemEffectID = "4", ItemID = "904" } end,
              want = "item 904 gives more than one poison" },
            { name = "class spell with no rank", cfg = { imbueFamilies = { "Frostbrand Weapon" }, shamanClass = 7 },
              edit = function() end,
              want = "no rank of Frostbrand Weapon for class 7" },
            { name = "imbue rank with no enchant", cfg = { imbueFamilies = { "Windfury Weapon" }, shamanClass = 7 },
              edit = function(t) effectOf(t, "107").Effect = "6" end,
              want = "107 Windfury Weapon has no enchant" },
            { name = "Create Soulstone making an unlisted stone",
              cfg = { soulstones = { 906 }, createSoulstone = "Create Soulstone", warlockClass = 9 },
              edit = function(t) effectOf(t, "108").EffectItemType = "999" end,
              want = "108 Create Soulstone creates no listed soulstone" },
            { name = "food buff with no aura", cfg = { foodName = "Well Fed" },
              edit = function(t) effectOf(t, "109").Effect = "3" end,
              want = "109 Well Fed applies no aura" },
            { name = "icon item with no icon", cfg = { icons = { { key = "food", item = 900 } } },
              edit = function(t) t.Item[1].IconFileDataID = "0" end,
              want = "icon item 900 has no icon" },
            { name = "healthstone that is not a consumable", cfg = { healthstones = { 902 } },
              edit = function(t) t.Item[3].ClassID = "7" end,
              want = "item 902 is not a consumable" },
        }) do
            local tables = baseTables()
            row.edit(tables)
            local ok, err = run(tables, row.cfg)
            assert.is_false(ok, row.name)
            assert.equals(row.want, err, row.name)
        end
    end)
end)
