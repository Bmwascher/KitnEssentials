-- ╔══════════════════════════════════════════════════════════╗
-- ║  SecondaryStatsForever.lua                               ║
-- ║  Purpose: The Forever client's stat catalog for the      ║
-- ║           Secondary Stats display, and which rows show.  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local _G = _G
local select = select
local ipairs = ipairs
local type = type
local math_floor = math.floor

-- Forever has no ratings, so the block shows the character pane's own stats.
-- Getters are looked up at call time and a missing one reads nil ("?").
local function Call(name, ...)
    local fn = _G[name]
    if fn then return fn(...) end
end

-- A combined figure does arithmetic or a comparison, which a secret refuses,
-- so it reads nil while any operand is secret or missing: a missing operand
-- counted as 0 would show a plausible wrong number instead of "?". A
-- single-getter row forwards its value untouched and still renders.
local function Sum(...)
    local count = select("#", ...)
    if count == 0 then return nil end
    local total = 0
    for i = 1, count do
        local v = select(i, ...)
        if v == nil or KE:IsSecretValue(v) then return nil end
        total = total + v
    end
    return total
end

local function Scaled(value, factor)
    if value == nil or KE:IsSecretValue(value) then return nil end
    return value * factor
end

local function One(name)
    return function() return (Call(name)) end
end

local function SchoolPower(school)
    return function() return (Call("GetSpellBonusDamage", school)) end
end

local function Resist(school)
    return function() return (select(2, Call("UnitResistance", "player", school))) end
end

local function BestSchoolPower()
    local best
    for school = 2, 7 do
        local v = Call("GetSpellBonusDamage", school)
        if v == nil or KE:IsSecretValue(v) then return nil end
        if best == nil or v > best then best = v end
    end
    return best
end

local PCT, NUM = "percent", "number"

local function Row(key, label, short, hex, kind, get)
    return { key = key, label = label, short = short, hex = hex, kind = kind, get = get }
end

local GROUPS = {
    { title = "Offensive", stats = {
        Row("ap", "Attack Power", "AP", "ff8c42", NUM, function() return Sum(Call("UnitAttackPower", "player")) end),
        Row("rap", "Ranged AP", "RAP", "ff8c42", NUM, function() return Sum(Call("UnitRangedAttackPower", "player")) end),
        Row("mcrit", "Melee Crit", "M.Crit", "ffd100", PCT, One("GetCritChance")),
        Row("rcrit", "Ranged Crit", "R.Crit", "ffd100", PCT, One("GetRangedCritChance")),
        Row("mhaste", "Melee Haste", "M.Haste", "7fe3d4", PCT, One("GetMeleeHaste")),
        -- Base and ammo haste, as the character pane adds them.
        Row("rhaste", "Ranged Haste", "R.Haste", "7fe3d4", PCT, function() return Sum(Call("GetRangedHaste")) end),
        Row("mhit", "Melee Hit", "Hit", "ffa94d", PCT, One("GetHitModifier")),
        Row("rhit", "Ranged Hit", "R.Hit", "ffa94d", PCT, One("GetRangedHitModifier")),
        Row("ohit", "Off-hand Hit", "OH Hit", "ffa94d", PCT, One("GetOffhandHitModifier")),
    } },
    { title = "Spell", stats = {
        -- The highest school's bonus, so school-specific gear counts.
        Row("sp", "Spell Power", "SP", "c77dff", NUM, BestSchoolPower),
        Row("healing", "Healing Power", "Heal", "4ec9b0", NUM, One("GetSpellBonusHealing")),
        Row("scrit", "Spell Crit", "S.Crit", "ffd100", PCT, One("GetSpellCritChance")),
        Row("shaste", "Spell Haste", "S.Haste", "7fe3d4", PCT, function() return (Call("UnitSpellHaste", "player")) end),
        Row("shit", "Spell Hit", "S.Hit", "ffa94d", PCT, One("GetSpellHitModifier")),
        Row("spen", "Spell Pen", "S.Pen", "b39ddb", NUM, One("GetSpellPenetration")),
    } },
    { title = "Spell Power / School", stats = {
        Row("sp_holy", "Holy SP", "Holy", "fff2b0", NUM, SchoolPower(2)),
        Row("sp_fire", "Fire SP", "Fire", "ff6b35", NUM, SchoolPower(3)),
        Row("sp_frost", "Frost SP", "Frost", "3fc7eb", NUM, SchoolPower(5)),
        Row("sp_nature", "Nature SP", "Nature", "4caf50", NUM, SchoolPower(4)),
        Row("sp_shadow", "Shadow SP", "Shadow", "a335ee", NUM, SchoolPower(6)),
        Row("sp_arcane", "Arcane SP", "Arcane", "ff7eb6", NUM, SchoolPower(7)),
    } },
    { title = "Defensive", stats = {
        Row("armor", "Armor", "Armor", "b0bec5", NUM, function() return (select(2, Call("UnitArmor", "player"))) end),
        Row("defense", "Defense", "Def", "b0bec5", NUM, function() return Sum(Call("UnitDefenseSkill", "player")) end),
        Row("dodge", "Dodge", "Dodge", "64b5f6", PCT, One("GetDodgeChance")),
        Row("parry", "Parry", "Parry", "64b5f6", PCT, One("GetParryChance")),
        Row("block", "Block", "Block", "64b5f6", PCT, One("GetBlockChance")),
        Row("blockval", "Block Value", "Blk V", "64b5f6", NUM, One("GetShieldBlock")),
    } },
    { title = "Resistances", stats = {
        Row("res_fire", "Fire Resist", "Fire R", "ff6b35", NUM, Resist(2)),
        Row("res_frost", "Frost Resist", "Frost R", "3fc7eb", NUM, Resist(4)),
        Row("res_nature", "Nature Resist", "Nat R", "4caf50", NUM, Resist(3)),
        Row("res_shadow", "Shadow Resist", "Shad R", "a335ee", NUM, Resist(5)),
        Row("res_arcane", "Arcane Resist", "Arc R", "ff7eb6", NUM, Resist(6)),
    } },
    { title = "Regen & Utility", stats = {
        Row("mp5", "Mana Regen", "MP5", "4fc3f7", NUM, function()
            local v = Scaled(Call("GetManaRegen"), 5)
            return v and math_floor(v)
        end),
        Row("hp5", "Health Regen", "HP5", "e57373", NUM, function()
            local v = Scaled(Call("GetHealthRegen"), 5)
            return v and math_floor(v)
        end),
        -- Run speed against the base 7 yards a second.
        Row("movespeed", "Movement Speed", "MS", "81c784", PCT, function()
            return Scaled(select(2, Call("GetUnitSpeed", "player")), 100 / 7)
        end),
    } },
}

-- Unit events that move these stats, for the player only. Every one is
-- registered by the client's own character pane.
local EVENTS = {
    "UNIT_ATTACK_SPEED", "UNIT_RANGEDDAMAGE", "UNIT_RANGED_ATTACK_POWER",
    "UNIT_ATTACK", "UNIT_DAMAGE", "UNIT_RESISTANCES", "UNIT_AURA",
}

local CASTER_CORE = { sp = true, scrit = true, shit = true }
local CLASS_CORE = {
    MAGE = CASTER_CORE,
    PRIEST = CASTER_CORE,
    WARLOCK = CASTER_CORE,
    HUNTER = { rap = true, rcrit = true, rhit = true },
}
local MELEE_CORE = { ap = true, mcrit = true, mhit = true }

-- A row the player ticked or unticked keeps that choice on every character of
-- the profile; a row never touched shows when it is one of the class's core
-- three. A nil class takes the melee three.
local function IsShown(key, saved, classFile)
    if type(saved) == "table" and type(saved.Shown) == "boolean" then return saved.Shown end
    local core = (classFile and CLASS_CORE[classFile]) or MELEE_CORE
    return core[key] == true
end

local byKey, order = {}, {}
for _, group in ipairs(GROUPS) do
    for _, row in ipairs(group.stats) do
        byKey[row.key] = row
        order[#order + 1] = row.key
    end
end

KE.SecondaryStatsForever = {
    groups = GROUPS,
    byKey = byKey,
    order = order,
    events = EVENTS,
    IsShown = IsShown,
}
