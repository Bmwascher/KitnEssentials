-- derive-training-data.lua: write KitnEssentials_Data/TrainingClass<id>.lua and
-- TrainingRoute.lua from game-data (DB2) tables saved by fetch-db2.ps1 and from
-- local Lua tables named on the command line, read only as plain text. The rules are in
-- _training_derive.lua, the text reader in _lua_text.lua, the stored form in
-- _data_source.lua.
--
-- Run from the repo root with the local Lua 5.1 interpreter:
--   lua dev/scripts/derive-training-data.lua --db2 <dir> --spells-a <file>
--       --weapons-a <file> --towns-a <file> --input-b <folder> --build <client build>
--       --out KitnEssentials_Data [--check]
--
-- <dir> holds SpellName, SpellLevels, SkillLineAbility and ChrRaces as <Table>.csv.
-- <folder> holds one <Class>.lua per class and QuestSpells.lua. Every argument is
-- required and has no default. Each class's totals, each untrainable id an input
-- held, and each disagreement on which spells replace a rank, print for reading and
-- block nothing. --check writes nothing and exits 0 only when every file equals the
-- generated text. A refusal, a missing table or column, or an unreadable input
-- exits 1 naming its cause.

local _script = (arg[0] or ""):gsub("/", "\\")
local _dir = _script:match("^(.*\\)[^\\]+$") or ".\\dev\\scripts\\"
local CSV = dofile(_dir .. "_db2_csv.lua")
local Derive = dofile(_dir .. "_training_derive.lua")
local Text = dofile(_dir .. "_lua_text.lua")
local Source = dofile(_dir .. "_data_source.lua")
local Lists = dofile(_dir .. "_training_lists.lua")
local FileMatches = dofile(_dir .. "_scout_spells_derive.lua").FileMatches

local GENERATED_BY = "dev/scripts/derive-training-data.lua"
local REQUIRED = { "--db2", "--spells-a", "--weapons-a", "--towns-a", "--input-b", "--build", "--out" }
local CLASSES = {
    { 1, "WARRIOR", "Warrior" }, { 2, "PALADIN", "Paladin" }, { 3, "HUNTER", "Hunter" },
    { 4, "ROGUE", "Rogue" }, { 5, "PRIEST", "Priest" }, { 7, "SHAMAN", "Shaman" },
    { 8, "MAGE", "Mage" }, { 9, "WARLOCK", "Warlock" }, { 11, "DRUID", "Druid" },
}

local function Fail(message)
    print("FAIL " .. message)
    os.exit(1)
end

local options, check = {}, false
for i, value in ipairs(arg) do
    if value == "--check" then
        check = true
    elseif value:sub(1, 2) == "--" then
        options[value] = arg[i + 1]
    end
end
for _, name in ipairs(REQUIRED) do
    if not options[name] then Fail("missing " .. name) end
end

local function ReadFile(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local text = file:read("*a")
    file:close()
    return text
end

local function ReadInputTable(path, marker)
    local text = ReadFile(path)
    if not text then Fail("cannot read " .. path) end
    local ok, data = pcall(Text.ReadTable, text, marker)
    if not ok then Fail(path .. ": " .. tostring(data)) end
    return data
end

local function LoadCsv(name, columns)
    local ok, rows = pcall(CSV.read, options["--db2"] .. "/" .. name .. ".csv", columns)
    if not ok then Fail(tostring(rows)) end
    return rows
end

local client = Derive.Client({
    SpellName = LoadCsv("SpellName", { "ID", "Name_lang" }),
    SpellLevels = LoadCsv("SpellLevels", { "SpellID", "DifficultyID", "SpellLevel" }),
    SkillLineAbility = LoadCsv("SkillLineAbility",
        { "Spell", "ClassMask", "RaceMasks_0", "RaceMasks_1", "SupercedesSpell" }),
    ChrRaces = LoadCsv("ChrRaces", { "ID", "PlayableRaceBit" }),
}, CSV.num)

local folder = options["--input-b"]
local allQuest = ReadInputTable(folder .. "/QuestSpells.lua", "local QuestSpells")
local inputs = {
    spellsA = ReadInputTable(options["--spells-a"], "ns.TrainingData"),
    weaponsA = ReadInputTable(options["--weapons-a"], "ns.TrainingWeapons"),
    levelsB = {},
    questB = {},
}
for _, class in ipairs(CLASSES) do
    inputs.levelsB[class[1]] = ReadInputTable(folder .. "/" .. class[3] .. ".lua", "class.spellsByLevel")
    inputs.questB[class[1]] = allQuest[class[2]] or {}
end
local townsPath = options["--towns-a"]
local towns = {
    capitals = ReadInputTable(townsPath, "ns.TownCapitals"),
    npcs = ReadInputTable(townsPath, "ns.TownNPCs"),
}

local build = options["--build"]
local files, leftOutTotal = {}, 0

local function AddFile(name, sourceLines)
    local ok, lines = pcall(Source.Wrap, name, GENERATED_BY, sourceLines)
    if not ok then Fail(tostring(lines)) end
    files[#files + 1] = { path = options["--out"] .. "/" .. name .. ".lua", lines = lines }
end

for _, class in ipairs(CLASSES) do
    local id = class[1]
    local ok, rows, leftOut, removed = pcall(Derive.ClassRows, id, inputs, client, Lists)
    if not ok then Fail(class[3] .. ": " .. tostring(rows)) end
    local weaponsOk, weapons, weaponsRemoved = pcall(Derive.Weapons, id, inputs, client, Lists)
    if not weaponsOk then Fail(class[3] .. ": " .. tostring(weapons)) end
    leftOutTotal = leftOutTotal + leftOut
    for _, list in ipairs({ removed, weaponsRemoved }) do
        for _, spellId in ipairs(list) do
            print(("%-8s removed untrainable %d"):format(class[3], spellId))
        end
    end
    local replaced = Derive.Replaced(id, rows, client)
    local replacedCount = 0
    for _ in pairs(replaced) do replacedCount = replacedCount + 1 end
    for _, line in ipairs(Derive.ReplacedCheck(inputs.spellsA[id], rows, replaced)) do
        print(("%-8s replaced check: %s"):format(class[3], line))
    end
    local totals = Derive.Totals(rows)
    print(("%-8s rows %d, seed %.2fg, quest %d, talent %d, maybe %d, weapons %d, replaced %d"):format(class[3],
        totals.count, totals.copper / 10000, totals.quest, totals.talent, totals.maybe, #weapons, replacedCount))
    AddFile("TrainingClass" .. id, Derive.ClassSource(rows, weapons, build, replaced))
end
print(("level rows left out by the row set: %d"):format(leftOutTotal))
AddFile("TrainingRoute", Derive.RouteSource(towns, build))

if check then
    local failed = Derive.Check(files, ReadFile, FileMatches)
    for _, path in ipairs(failed) do print("DIFFERS " .. path) end
    if #failed > 0 then os.exit(1) end
    print(("OK %d files are the derived tables"):format(#files))
    os.exit(0)
end

for _, file in ipairs(files) do
    local out = io.open(file.path, "wb")
    if not out then Fail("cannot write " .. file.path) end
    out:write(table.concat(file.lines, "\n"), "\n")
    out:close()
end
print(("wrote %d files"):format(#files))
