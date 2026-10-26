-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/DungeonTools/KicksCasts/PartyStopsData.lua      ║
-- ║  Purpose: the crowd-control stops Party Stops tracks.    ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- Keyed by the stop's spell ID. debuffs land on the enemy; lag is how many
-- seconds after the cast they land, and a start is backdated by it; cast
-- lists other spell IDs the player's own cast can carry. need and mods name
-- talent spell IDs: a member whose every need talent reads untaken gets no
-- icon. spec limits a stop to one spec, or to role while the spec is unread.
-- hold marks a stop long enough to be up already on a newly watched enemy.

---@class KE
local KE = select(2, ...)

local Data = {}
KE.PartyStopsData = Data

Data.STOPS = {
    [119381] = { class = "MONK", cd = 60, debuffs = { 119381 }, mods = { { 344359, add = -5 } } },
    [179057] = { class = "DEMONHUNTER", cd = 45, debuffs = { 179057 }, need = { 179057 } },
    [30283] = { class = "WARLOCK", cd = 60, debuffs = { 30283 }, need = { 30283 }, mods = { { 1270255, add = -15 } } },
    [192058] = { class = "SHAMAN", cd = 60, debuffs = { 118905 }, lag = 2, need = { 192058 },
        mods = { { 381867, add = -5 }, { 265046, add = -10 }, { 445027, add = -5 } } },
    [46968] = { class = "WARRIOR", cd = 40, debuffs = { 132168 }, need = { 46968 },
        mods = { { 275339, add = -15 }, { 440992, add = -5 } } },
    [109248] = { class = "HUNTER", cd = 45, debuffs = { 117405, 117526 }, need = { 109248 } },
    [853] = { class = "PALADIN", cd = 45, debuffs = { 853 }, mods = { { 234299, add = -15 } } },
    [19577] = { class = "HUNTER", cd = 60, debuffs = { 24394, 474421 }, cast = { 474421 }, need = { 19577, 474421 },
        mods = { { 459507, add = -20 } } },
    [207167] = { class = "DEATHKNIGHT", cd = 60, debuffs = { 207167 }, need = { 207167 } },
    [115750] = { class = "PALADIN", cd = 90, debuffs = { 105421 }, need = { 115750 }, mods = { { 469325, add = -15 } } },
    [8122] = { class = "PRIEST", cd = 40, debuffs = { 8122 }, need = { 8122 }, mods = { { 196704, add = -10 } } },
    [99] = { class = "DRUID", cd = 30, debuffs = { 99 }, need = { 99 } },
    [5246] = { class = "WARRIOR", cd = 90, debuffs = { 5246 }, need = { 5246 }, mods = { { 424742, add = -15 } } },
    [207684] = { class = "DEMONHUNTER", cd = 120, debuffs = { 207685 }, lag = 2, cast = { 389813 }, need = { 207684 },
        mods = { { 320418, add = -30 }, { 389718, pct = -15 } } },
    [202138] = { class = "DEMONHUNTER", cd = 60, debuffs = { 204843 }, lag = 2, cast = { 389807 }, spec = 581,
        role = "TANK", need = { 202138 }, mods = { { 389718, pct = -15 } } },
    [108199] = { class = "DEATHKNIGHT", cd = 90, debuffs = { 374776 }, spec = 250, role = "TANK", need = { 108199 } },
    [102793] = { class = "DRUID", cd = 60, debuffs = { 127797 }, need = { 102793 } },
    [132469] = { class = "DRUID", cd = 30, debuffs = { 61391 }, need = { 132469 }, mods = { { 400140, add = -5 } } },
    [2094] = { class = "ROGUE", cd = 120, debuffs = { 2094 }, hold = true, need = { 2094 },
        mods = { { 200733, pct = -50 }, { 256165, pct = -25 }, { 441415, pct = -10 } } },
}

-- The stuns first, then the fears, knockbacks and grips.
Data.ORDER = {
    119381, 179057, 30283, 192058, 46968, 109248, 853, 19577,
    207167, 115750, 8122, 99, 5246, 207684, 202138, 108199, 102793, 132469, 2094,
}

Data.CLASS_NAMES = {
    DEATHKNIGHT = "Death Knight", DEMONHUNTER = "Demon Hunter", DRUID = "Druid", HUNTER = "Hunter",
    MONK = "Monk", PALADIN = "Paladin", PRIEST = "Priest", ROGUE = "Rogue", SHAMAN = "Shaman",
    WARLOCK = "Warlock", WARRIOR = "Warrior",
}
