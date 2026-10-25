-- derive-forever-consumables.lua: print the Forever tables of
-- Modules/QoL/GroupTools/ReadyCheckConsumablesForever.lua from game-data
-- (DB2) tables saved by fetch-db2.ps1. The rules are in
-- _forever_consumables_derive.lua beside it; the seeds below are the items
-- the module tracks.
--
-- Run from the repo root with the local Lua 5.1 interpreter:
--   lua dev/scripts/derive-forever-consumables.lua <dir>
--   lua dev/scripts/derive-forever-consumables.lua <dir> --check Modules/QoL/GroupTools/ReadyCheckConsumablesForever.lua
--
-- <dir> holds Item, ItemEffect, ItemXItemEffect, SpellName, SpellEffect,
-- SpellMisc, SpellDuration, SpellItemEnchantment, SkillLineAbility,
-- SpellEquippedItems and SpellLevels as <Table>.csv. ItemSparse is not read:
-- its multi-line fields defeat the CSV reader, so items are named at runtime.
-- The first form prints the tables, to be pasted into the data file as
-- printed. --check exits 0 when the file holds that text exactly; otherwise
-- it prints the text and exits 1. A refusal of the rules, a missing table or
-- a missing column exits 1 naming its cause.

local _script = (arg[0] or ""):gsub("/", "\\")
local _dir = _script:match("^(.*\\)[^\\]+$") or ".\\dev\\scripts\\"
local CSV = dofile(_dir .. "_db2_csv.lua")
local Derive = dofile(_dir .. "_forever_consumables_derive.lua")

local dir, checkPath = arg[1], nil
if arg[2] == "--check" then checkPath = arg[3] end
if not dir or (arg[2] and not checkPath) then
    io.stderr:write("usage: lua dev/scripts/derive-forever-consumables.lua <dir> [--check <file>]\n")
    os.exit(2)
end

local function fail(msg)
    io.stderr:write("FAIL " .. msg .. "\n")
    os.exit(1)
end

local SHAMAN, WARLOCK = 7, 9

-- The flask click's order when nothing is remembered.
local FLASKS = { 13512, 13511, 13510, 274273, 274274, 274275, 274276, 13513 }

-- Elixirs of 20 minutes or more that raise a combat stat.
local ELIXIRS = {
    2457, 3390, 8949, 9187, 13452, 250328,                          -- agility
    2454, 3391, 250349, 9206, 13453, 250350, 250351,                -- strength
    12820, 246948,                                                  -- attack power
    6373, 17708, 9264, 21546, 250343, 247754, 217398, 250342, 9155, 13454, 247755,  -- spell power
    250330, 250331, 250332, 250333,                                 -- healing
    3383, 250353, 250354, 9179, 13447, 250338, 250337, 250344, 250345, 250346, 250347, 250348,  -- intellect and spirit
    20007, 250339, 250340, 250341, 250336, 3382, 3388, 3826, 20004, -- mana and health regen
    5997, 1177, 3389, 8951, 13445, 2458, 3825, 250334, 250335, 250329,  -- defense
}

-- Stones and oils. Within a kind the higher rank is offered first; the
-- vs-undead items take rank 0, so they come last.
local ENHANCEMENTS = {
    { item = 2862,   kind = "stone",  family = "Sharpening Stone",             rank = 1 },
    { item = 287978, kind = "stone",  family = "Sharpening Stone",             rank = 1 },
    { item = 2863,   kind = "stone",  family = "Sharpening Stone",             rank = 2 },
    { item = 2871,   kind = "stone",  family = "Sharpening Stone",             rank = 3 },
    { item = 7964,   kind = "stone",  family = "Sharpening Stone",             rank = 4 },
    { item = 12404,  kind = "stone",  family = "Sharpening Stone",             rank = 5 },
    { item = 18262,  kind = "stone",  family = "Elemental Sharpening Stone",   rank = 6 },
    { item = 287980, kind = "stone",  family = "Elemental Sharpening Stone",   rank = 6 },
    { item = 3239,   kind = "stone",  family = "Weightstone",                  rank = 1 },
    { item = 3240,   kind = "stone",  family = "Weightstone",                  rank = 2 },
    { item = 3241,   kind = "stone",  family = "Weightstone",                  rank = 3 },
    { item = 7965,   kind = "stone",  family = "Weightstone",                  rank = 4 },
    { item = 12643,  kind = "stone",  family = "Weightstone",                  rank = 5 },
    { item = 23122,  kind = "stone",  family = "Consecrated Sharpening Stone", rank = 0 },
    { item = 20744,  kind = "wizard", family = "Wizard Oil",                   rank = 1 },
    { item = 20750,  kind = "wizard", family = "Wizard Oil",                   rank = 2 },
    { item = 20749,  kind = "wizard", family = "Wizard Oil",                   rank = 3 },
    { item = 23123,  kind = "wizard", family = "Blessed Wizard Oil",           rank = 0 },
    { item = 20745,  kind = "mana",   family = "Mana Oil",                     rank = 1 },
    { item = 20748,  kind = "mana",   family = "Mana Oil",                     rank = 2 },
    { item = 3824,   kind = "oil",    family = "Shadow Oil",                   rank = 1 },
    { item = 3829,   kind = "oil",    family = "Frost Oil",                    rank = 1 },
    { item = 232611, kind = "oil",    family = "Magnificent Trollshine",       rank = 1 },
}

-- The Rogue poison families; Effect 360 alone also matches Firestone and
-- other weapon imbues.
local POISON_FAMILIES = { "Crippling Poison", "Deadly Poison", "Instant Poison", "Mind-numbing Poison", "Wound Poison" }

-- The Shaman imbue click's order when nothing is remembered.
local IMBUE_FAMILIES = { "Windfury Weapon", "Flametongue Weapon", "Frostbrand Weapon", "Rockbiter Weapon" }

local HEALTHSTONES = {
    5512, 5511, 5509, 5510, 9421,
    19004, 19005, 19006, 19007, 19008, 19009, 19010, 19011, 19012, 19013,
}

-- Best first: the click uses the first one stocked.
local SOULSTONES = { 16896, 16895, 16893, 16892, 5232 }

local ICONS = {
    { key = "food",        item = 21023 },
    { key = "flask",       item = 13510 },
    { key = "oil",         item = 20749 },
    { key = "oiloh",       item = 12404 },
    { key = "elixir",      item = 13452 },
    { key = "healthstone", item = 9421 },
    { key = "class",       item = 16896 },
}

local function loadTable(name, columns)
    local ok, rows = pcall(CSV.read, dir .. "/" .. name .. ".csv", columns)
    if not ok then fail(tostring(rows)) end
    return rows
end

local tables = {
    Item = loadTable("Item", { "ID", "ClassID", "SubclassID", "IconFileDataID" }),
    ItemEffect = loadTable("ItemEffect", { "ID", "SpellID" }),
    ItemXItemEffect = loadTable("ItemXItemEffect", { "ItemEffectID", "ItemID" }),
    SpellName = loadTable("SpellName", { "ID", "Name_lang" }),
    SpellEffect = loadTable("SpellEffect", { "SpellID", "DifficultyID", "Effect", "EffectMiscValue_0", "EffectItemType" }),
    SpellMisc = loadTable("SpellMisc", { "SpellID", "DifficultyID", "DurationIndex" }),
    SpellDuration = loadTable("SpellDuration", { "ID", "Duration" }),
    SpellItemEnchantment = loadTable("SpellItemEnchantment", { "ID" }),
    SkillLineAbility = loadTable("SkillLineAbility",
        { "SkillLine", "Spell", "ClassMask", "SupercedesSpell", "AcquireMethod", "RaceMasks_0" }),
    SpellEquippedItems = loadTable("SpellEquippedItems", { "SpellID", "EquippedItemClass", "EquippedItemSubclass" }),
    SpellLevels = loadTable("SpellLevels", { "SpellID", "DifficultyID", "BaseLevel" }),
}

local ok, lines = pcall(Derive.Run, tables, {
    num = CSV.num,
    foodName = "Well Fed",
    foodExtra = { 25661 },
    flasks = FLASKS,
    elixirs = ELIXIRS,
    enhancements = ENHANCEMENTS,
    poisonFamilies = POISON_FAMILIES,
    imbueFamilies = IMBUE_FAMILIES,
    shamanClass = SHAMAN,
    healthstones = HEALTHSTONES,
    createHealthstone = "Create Healthstone",
    warlockClass = WARLOCK,
    soulstones = SOULSTONES,
    createSoulstone = "Create Soulstone",
    icons = ICONS,
})
if not ok then fail(tostring(lines)) end

local out = table.concat(lines, "\n") .. "\n"
if checkPath then
    local f = io.open(checkPath, "rb")
    if not f then fail("cannot read " .. checkPath) end
    local text = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    if text:find(out, 1, true) then
        print("OK " .. checkPath .. " holds the derived tables")
        os.exit(0)
    end
    io.write(out)
    fail(checkPath .. " does not hold the tables above exactly")
end
io.write(out)
