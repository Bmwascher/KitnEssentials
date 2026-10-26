-- derive-forever-cc.lua: print the Forever CC Tracker list of
-- Modules/DungeonTools/KicksCasts/CCTrackerForever.lua from game-data (DB2)
-- tables saved by fetch-db2.ps1. The rules are in _forever_cc_derive.lua
-- beside it.
--
-- Run from the repo root with the local Lua 5.1 interpreter:
--   lua dev/scripts/derive-forever-cc.lua <dir>
--   lua dev/scripts/derive-forever-cc.lua <dir> --check Modules/DungeonTools/KicksCasts/CCTrackerForever.lua
--
-- <dir> holds SpellName, SkillLineAbility, SpellEffect, SpellCategories and
-- SpellLevels as <Table>.csv. The first form prints KE.CC_TRACKER_SEEDS, to
-- be pasted into CCTrackerForever.lua as printed. --check exits 0 when the
-- file holds that text exactly; otherwise it prints the text and exits 1. A
-- refusal of the rules, a missing table or a missing column exits 1 naming
-- its cause.

local _script = (arg[0] or ""):gsub("/", "\\")
local _dir = _script:match("^(.*\\)[^\\]+$") or ".\\dev\\scripts\\"
local CSV = dofile(_dir .. "_db2_csv.lua")
local Derive = dofile(_dir .. "_forever_cc_derive.lua")

local dir, checkPath = arg[1], nil
if arg[2] == "--check" then checkPath = arg[3] end
if not dir or (arg[2] and not checkPath) then
    io.stderr:write("usage: lua dev/scripts/derive-forever-cc.lua <dir> [--check <file>]\n")
    os.exit(2)
end

local function fail(msg)
    io.stderr:write("FAIL " .. msg .. "\n")
    os.exit(1)
end

local PALADIN, HUNTER, ROGUE, PRIEST, MAGE, WARLOCK, DRUID = 2, 3, 4, 5, 8, 9, 11

-- Skill lines whose rows carry ClassMask 0, by the class they belong to.
local CLASSLESS_SKILL_LINES = {
    [205] = WARLOCK,  -- Succubus: Seduction
}

-- The retail list's long crowd controls that Forever has, under the retail
-- keys and defaults, labeled by their Forever names. Mechanics: 1 charm,
-- 2 disorient, 5 fear, 7 root, 10 sleep, 13 freeze, 14 knockout,
-- 17 polymorph, 18 banish, 20 shackle, 23 turn. Freezing Trap's casts place
-- a trap and apply nothing, so its entry names the trap's debuffs.
local ENTRIES = {
    { key = "POLYMORPH", label = "Polymorph (all)", group = "MAGE", class = MAGE,
      names = { "Polymorph", "Polymorph: Cow" }, mechanic = 17, default = true },
    { key = "REPENTANCE", label = "Repentance", group = "PALADIN", class = PALADIN,
      names = { "Repentance" }, mechanic = 14, default = true },
    { key = "TURN_EVIL", label = "Turn Undead", group = "PALADIN", class = PALADIN,
      names = { "Turn Undead" }, mechanic = 23, default = true },
    { key = "FREEZING_TRAP", label = "Freezing Trap", group = "HUNTER", class = HUNTER,
      names = { "Freezing Trap" }, mechanic = 13, default = true, debuffs = { 3355, 14308, 14309 } },
    { key = "SCARE_BEAST", label = "Scare Beast", group = "HUNTER", class = HUNTER,
      names = { "Scare Beast" }, mechanic = 5, default = true },
    { key = "SAP", label = "Sap", group = "ROGUE", class = ROGUE,
      names = { "Sap" }, mechanic = 14, default = true },
    { key = "BLIND", label = "Blind", group = "ROGUE", class = ROGUE,
      names = { "Blind" }, mechanic = 2, default = true },
    { key = "BANISH", label = "Banish", group = "WARLOCK", class = WARLOCK,
      names = { "Banish" }, mechanic = 18, default = true },
    { key = "FEAR", label = "Fear", group = "WARLOCK", class = WARLOCK,
      names = { "Fear" }, mechanic = 5, default = true },
    { key = "SEDUCTION", label = "Seduction", group = "WARLOCK", class = WARLOCK,
      names = { "Seduction" }, mechanic = 1, default = true },
    { key = "HIBERNATE", label = "Hibernate", group = "DRUID", class = DRUID,
      names = { "Hibernate" }, mechanic = 10, default = true },
    { key = "ENTANGLING_ROOTS", label = "Entangling Roots", group = "DRUID", class = DRUID,
      names = { "Entangling Roots" }, mechanic = 7, default = false },
    { key = "SHACKLE_HORROR", label = "Shackle Undead", group = "PRIEST", class = PRIEST,
      names = { "Shackle Undead" }, mechanic = 20, default = true },
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
    SpellEffect = loadTable("SpellEffect",
        { "SpellID", "DifficultyID", "Effect", "EffectMechanic", "EffectTriggerSpell" }),
    SpellCategories = loadTable("SpellCategories", { "SpellID", "DifficultyID", "Mechanic" }),
    SpellLevels = loadTable("SpellLevels", { "SpellID", "DifficultyID", "BaseLevel" }),
}

local ok, lines = pcall(Derive.Run, tables, {
    entries = ENTRIES,
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
        print("OK " .. checkPath .. " holds the derived list")
        os.exit(0)
    end
    io.write(out)
    fail(checkPath .. " does not hold the list above exactly")
end
io.write(out)
