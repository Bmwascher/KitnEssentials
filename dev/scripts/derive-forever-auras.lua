-- derive-forever-auras.lua: print the Forever External Tracker and Movement
-- Buffs lists of Core/Defaults.lua from game-data (DB2) tables saved by
-- fetch-db2.ps1. The rules are in _forever_auras_derive.lua beside it.
--
-- Run from the repo root with the local Lua 5.1 interpreter:
--   lua dev/scripts/derive-forever-auras.lua <dir>
--   lua dev/scripts/derive-forever-auras.lua <dir> --check Core/Defaults.lua
--
-- <dir> holds SpellName, SkillLineAbility, SpellEffect, SpellLevels,
-- ItemEffect and ItemXItemEffect as <Table>.csv. ItemSparse is not read: its
-- multi-line fields defeat the CSV reader, so ENTRIES names items by id.
-- The first form prints FOREVER_EXTERNALS_ALLOWLIST and
-- FOREVER_MOVEMENT_ALLOWLIST, to be pasted into Core/Defaults.lua as printed.
-- --check exits 0 when the file holds that text exactly; otherwise it prints
-- the text and exits 1. A refusal of the rules, a missing table or a missing
-- column exits 1 naming its cause.

local _script = (arg[0] or ""):gsub("/", "\\")
local _dir = _script:match("^(.*\\)[^\\]+$") or ".\\dev\\scripts\\"
local CSV = dofile(_dir .. "_db2_csv.lua")
local Derive = dofile(_dir .. "_forever_auras_derive.lua")

local dir, checkPath = arg[1], nil
if arg[2] == "--check" then checkPath = arg[3] end
if not dir or (arg[2] and not checkPath) then
    io.stderr:write("usage: lua dev/scripts/derive-forever-auras.lua <dir> [--check <file>]\n")
    os.exit(2)
end

local function fail(msg)
    io.stderr:write("FAIL " .. msg .. "\n")
    os.exit(1)
end

local PALADIN, HUNTER, ROGUE, PRIEST, SHAMAN, MAGE, WARLOCK, DRUID = 2, 3, 4, 5, 7, 8, 9, 11

-- Skill lines whose rows carry ClassMask 0, by the class they belong to.
local CLASSLESS_SKILL_LINES = {
    [354] = WARLOCK,  -- Fel Domination
    [573] = DRUID,    -- Innervate
}

-- `enabled` copies the retail row of the same name; a Forever-only row is on.
local ENTRIES = {
    { list = "externals", class = PALADIN, name = "Blessing of Protection", enabled = true },
    { list = "externals", class = PALADIN, name = "Blessing of Sacrifice", enabled = true },
    { list = "externals", class = PALADIN, name = "Divine Intervention", enabled = true },
    { list = "externals", class = DRUID, name = "Tranquility", enabled = true },
    { list = "externals", class = DRUID, name = "Innervate", enabled = true },
    { list = "externals", class = PRIEST, name = "Power Infusion", enabled = true },
    { list = "movement", class = MAGE, name = "Slow Fall", enabled = true },
    { list = "movement", item = 10518, itemName = "Parachute Cloak", enabled = true },
    { list = "movement", class = PALADIN, name = "Blessing of Freedom", enabled = true },
    { list = "movement", class = ROGUE, name = "Stealth", enabled = false },
    { list = "movement", class = DRUID, name = "Dash", enabled = true },
    { list = "movement", class = SHAMAN, name = "Ghost Wolf", enabled = true },
    { list = "movement", class = ROGUE, name = "Sprint", enabled = true },
    { list = "movement", class = DRUID, name = "Prowl", enabled = true },
    { list = "movement", class = HUNTER, name = "Feign Death", enabled = true },
    { list = "movement", class = PRIEST, name = "Levitate", enabled = true },
    { list = "movement", class = HUNTER, name = "Aspect of the Cheetah", enabled = true },
    { list = "movement", class = HUNTER, name = "Aspect of the Pack", enabled = true },
    { list = "movement", class = WARLOCK, name = "Fel Domination", enabled = false },
    { list = "movement", item = 2459, itemName = "Swiftness Potion", enabled = true },
    { list = "movement", item = 2820, itemName = "Nifty Stopwatch", enabled = true },
    { list = "movement", item = 7189, itemName = "Goblin Rocket Boots", enabled = true },
    { list = "movement", item = 10724, itemName = "Gnomish Rocket Boots", enabled = true },
    { list = "movement", item = 4984, itemName = "Skull of Impending Doom", enabled = true },
    { list = "movement", item = 5634, itemName = "Free Action Potion", enabled = true },
    { list = "movement", item = 20008, itemName = "Living Action Potion", enabled = true },
}

local LISTS = {
    { key = "externals", name = "FOREVER_EXTERNALS_ALLOWLIST" },
    { key = "movement", name = "FOREVER_MOVEMENT_ALLOWLIST" },
}

local function loadTable(name, columns)
    local ok, rows = pcall(CSV.read, dir .. "/" .. name .. ".csv", columns)
    if not ok then fail(tostring(rows)) end
    return rows
end

local tables = {
    SpellName = loadTable("SpellName", { "ID", "Name_lang" }),
    SkillLineAbility = loadTable("SkillLineAbility",
        { "SkillLine", "Spell", "ClassMask", "SupercedesSpell", "AcquireMethod", "RaceMasks_0" }),
    SpellEffect = loadTable("SpellEffect", { "SpellID", "DifficultyID", "Effect", "EffectTriggerSpell" }),
    SpellLevels = loadTable("SpellLevels", { "SpellID", "DifficultyID", "BaseLevel" }),
    ItemEffect = loadTable("ItemEffect", { "ID", "SpellID" }),
    ItemXItemEffect = loadTable("ItemXItemEffect", { "ItemEffectID", "ItemID" }),
}

local ok, lines = pcall(Derive.Run, tables, {
    entries = ENTRIES,
    lists = LISTS,
    classless = CLASSLESS_SKILL_LINES,
    num = CSV.num,
})
if not ok then fail(tostring(lines)) end

local out = table.concat(lines, "\n") .. "\n"
if checkPath then
    local f = io.open(checkPath, "rb")
    if not f then fail("cannot read " .. checkPath) end
    local text = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    if text:find(out, 1, true) then
        print("OK " .. checkPath .. " holds the derived lists")
        os.exit(0)
    end
    io.write(out)
    fail(checkPath .. " does not hold the lists above exactly")
end
io.write(out)
