-- derive-scout-spells.lua: print KitnEssentials_Data/ScoutSpells.lua from
-- game-data (DB2) tables saved by fetch-db2.ps1 and the spell ids in
-- KitnEssentials_Data/ScoutMobs.lua. The rules are in _scout_spells_derive.lua
-- beside it, and the stored form in _data_source.lua.
--
-- Run from the repo root with the local Lua 5.1 interpreter:
--   lua dev/scripts/derive-scout-spells.lua <dir> > KitnEssentials_Data/ScoutSpells.lua
--   lua dev/scripts/derive-scout-spells.lua <dir> --check KitnEssentials_Data/ScoutSpells.lua
--
-- <dir> holds SpellName, SpellCategories, SpellEffect, SpellMisc and SpellRange
-- as <Table>.csv. The counts go to stderr, so they stay out of the file.
-- --check exits 0 when the whole file, line ends aside, is that text; otherwise
-- it prints the text and exits 1. A refusal, a missing table or a missing column
-- exits 1 naming its cause.

local _script = (arg[0] or ""):gsub("/", "\\")
local _dir = _script:match("^(.*\\)[^\\]+$") or ".\\dev\\scripts\\"
local CSV = dofile(_dir .. "_db2_csv.lua")
local Derive = dofile(_dir .. "_scout_spells_derive.lua")
local Source = dofile(_dir .. "_data_source.lua")

local MOBS_FILE = "KitnEssentials_Data/ScoutMobs.lua"

local dir, checkPath = arg[1], nil
if arg[2] == "--check" then checkPath = arg[3] end
if not dir or (arg[2] and not checkPath) then
    io.stderr:write("usage: lua dev/scripts/derive-scout-spells.lua <dir> [--check <file>]\n")
    os.exit(2)
end

local function fail(msg)
    io.stderr:write("FAIL " .. msg .. "\n")
    os.exit(1)
end

local function loadTable(name, columns)
    local ok, rows = pcall(CSV.read, dir .. "/" .. name .. ".csv", columns)
    if not ok then fail(tostring(rows)) end
    return rows
end

local function loadSpellIds()
    local mobs, err = Source.Read(MOBS_FILE, "ScoutMobs")
    if not mobs then fail(err) end
    local seen, ids = {}, {}
    for _, list in pairs(mobs.abilities) do
        for _, id in ipairs(list) do
            if not seen[id] then
                seen[id] = true
                ids[#ids + 1] = id
            end
        end
    end
    return ids
end

local tables = {
    SpellName = loadTable("SpellName", { "ID", "Name_lang" }),
    SpellCategories = loadTable("SpellCategories", { "SpellID", "DifficultyID", "Mechanic" }),
    SpellEffect = loadTable("SpellEffect",
        { "SpellID", "DifficultyID", "EffectIndex", "EffectMechanic", "ImplicitTarget_0", "ImplicitTarget_1" }),
    SpellMisc = loadTable("SpellMisc", { "SpellID", "DifficultyID", "RangeIndex" }),
    SpellRange = loadTable("SpellRange", { "ID", "RangeMax_0" }),
}

local ok, lines, words, scopes = pcall(Derive.Run, tables, { spellIds = loadSpellIds(), num = CSV.num, wrap = Source.Wrap })
if not ok then fail(tostring(lines)) end

local wordCount, aroundCount, coneCount = 0, 0, 0
for _ in pairs(words) do wordCount = wordCount + 1 end
for _, scope in pairs(scopes) do
    if scope == "Cone" then coneCount = coneCount + 1 else aroundCount = aroundCount + 1 end
end
io.stderr:write(("words %d, around it %d, cone %d\n"):format(wordCount, aroundCount, coneCount))

local out = table.concat(lines, "\n") .. "\n"
if checkPath then
    local f = io.open(checkPath, "rb")
    if not f then fail("cannot read " .. checkPath) end
    local text = f:read("*a")
    f:close()
    if Derive.FileMatches(text, lines) then
        print("OK " .. checkPath .. " is the derived table")
        os.exit(0)
    end
    io.write(out)
    fail(checkPath .. " is not the table above exactly")
end
io.write(out)
