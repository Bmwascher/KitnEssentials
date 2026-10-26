-- ╔══════════════════════════════════════════════════════════╗
-- ║  CombatCrossForever.lua                                  ║
-- ║  Purpose: The Forever client's range spells for the      ║
-- ║           Player Crosshair, and which one applies.       ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local CAT_FORM, BEAR_FORM, DIRE_BEAR_FORM = 1, 5, 8

-- Rank 1 of each spell: a rank's range is rank 1's. A melee list is tried
-- in order and its last id is the fallback; defaultMelee answers for a
-- character with no talent points spent.
local RANGE_SPELLS = {
    WARRIOR = { melee = { 78 }, defaultMelee = true },                        -- Heroic Strike
    ROGUE   = { melee = { 1752 }, defaultMelee = true },                      -- Sinister Strike
    PALADIN = { melee = { 679, 20271 }, healer = 635, defaultMelee = true },  -- Holy Strike, else 20271 (10 yd); Holy Light
    SHAMAN  = { melee = { 17364, 403 }, ranged = 403, healer = 331 },         -- Stormstrike, Lightning Bolt; Healing Wave
    DRUID   = { cat = 1082, bear = 6807, ranged = 5176, healer = 5185 },      -- Claw, Maul, Wrath, Healing Touch
    HUNTER  = { ranged = 75 },                                                -- Auto Shot
    MAGE    = { ranged = 133 },                                               -- Fireball
    WARLOCK = { ranged = 686 },                                               -- Shadow Bolt
    PRIEST  = { ranged = 585, healer = 2050 },                                -- Smite; Lesser Heal
}

local function PickMelee(list, isKnown)
    for i = 1, #list - 1 do
        if isKnown(list[i]) then return list[i] end
    end
    return list[#list]
end

-- The range spell and its type ("melee" or "ranged") for a class, the
-- library's role and position and the shapeshift form; nil for a class
-- with no row.
local function PickRange(classFile, role, position, formID, isKnown)
    if KE:IsSecretValue(formID) then formID = nil end
    local spells = RANGE_SPELLS[classFile]
    if not spells then return nil end
    if classFile == "DRUID" then
        if formID == CAT_FORM then return spells.cat, "melee" end
        if formID == BEAR_FORM or formID == DIRE_BEAR_FORM then return spells.bear, "melee" end
    end
    if role == "HEALER" and spells.healer then return spells.healer, "ranged" end
    local wantMelee = classFile ~= "DRUID"
        and (position == "MELEE" or (position == nil and spells.defaultMelee == true))
    if (wantMelee or not spells.ranged) and spells.melee then
        return PickMelee(spells.melee, isKnown), "melee"
    end
    return spells.ranged, "ranged"
end

KE.CombatCrossForever = {
    RANGE_SPELLS = RANGE_SPELLS,
    PickRange = PickRange,
}
