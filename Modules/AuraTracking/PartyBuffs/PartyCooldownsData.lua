-- ╔══════════════════════════════════════════════════════════╗
-- ║  PartyCooldownsData.lua                                  ║
-- ║  Purpose: the per-spec cooldown list Party Cooldowns     ║
-- ║           shows for each party member.                   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local pairs = pairs

local Data = {}
KE.PartyCooldownsData = Data

-- Keyed by cast. kind colors the border; buffs are what the sensor and the
-- overlay match, the cast when absent; a proc copy of the buff lasts at most
-- short seconds and starts no cooldown. swap is a talent that changes the
-- icon only: id is drawn when it is taken, likely until talents are read,
-- and specs limits it to those specs. needs is a talent the row requires: it
-- shows while the talent is taken, and before talents are read only if likely.
-- lengthNeeds is a talent a spec's paired seconds need: a member read without
-- it counts the cast's own cd.
Data.SPELLS = {
    [49028]   = { kind = "offensive", cd = 120, buffs = { 81256 } },
    [48792]   = { kind = "defensive", cd = 120 },
    [48707]   = { kind = "defensive", cd = 60, buffs = { 48707, 444741 } },
    [51271]   = { kind = "offensive", cd = 45 },
    [42650]   = { kind = "offensive", cd = 90 },

    [191427]  = { kind = "offensive", cd = 120, buffs = { 162264 }, short = 10 },
    [198589]  = { kind = "defensive", cd = 60, buffs = { 212800 } },

    [194223]  = { kind = "offensive", cd = 180, buffs = { 194223, 102560, 390414 } },
    [106951]  = { kind = "offensive", cd = 180, buffs = { 106951, 102543 } },
    [22812]   = { kind = "defensive", cd = 60 },
    [61336]   = { kind = "defensive", cd = 180 },

    [375087]  = { kind = "offensive", cd = 120 },
    [403631]  = { kind = "offensive", cd = 120 },
    [363916]  = { kind = "defensive", cd = 90 },

    [19574]   = { kind = "offensive", cd = 90, buffs = { 19574, 186254, 1235388, 1285912 } },
    [288613]  = { kind = "offensive", cd = 120 },
    [1250646] = { kind = "offensive", cd = 90, buffs = { 1250646, 1251703 } },
    [186265]  = { kind = "defensive", cd = 180 },
    [264735]  = { kind = "defensive", cd = 90 },

    [365350]  = { kind = "offensive", cd = 90, buffs = { 365350, 365362 } },
    [190319]  = { kind = "offensive", cd = 120, short = 8 },
    [45438]   = { kind = "defensive", cd = 240, buffs = { 45438, 414658 },
                  swap = { id = 414658, talents = { [414659] = true, [414658] = true }, likely = true } },
    [342245]  = { kind = "defensive", cd = 60, buffs = { 342246 } },

    [132578]  = { kind = "offensive", cd = 120 },
    -- Seen through Celestial Conduit, which every Xuen caster has.
    [123904]  = { kind = "offensive", cd = 120, buffs = { 1248992 } },
    [115203]  = { kind = "defensive", cd = 360, buffs = { 115203, 120954 } },
    [122783]  = { kind = "defensive", cd = 90 },
    [122470]  = { kind = "defensive", cd = 90, buffs = { 125174 } },

    [31884]   = { kind = "offensive", cd = 120, buffs = { 31884, 231895, 454351, 216331, 389539 },
                  swap = { id = 389539, talents = { [389539] = true }, likely = true, specs = { [66] = true } } },
    [642]     = { kind = "defensive", cd = 300 },
    [498]     = { kind = "defensive", cd = 60, buffs = { 498, 403876 } },
    [31850]   = { kind = "defensive", cd = 90 },

    [200183]  = { kind = "offensive", cd = 120 },
    [228260]  = { kind = "offensive", cd = 120, buffs = { 194249 } },
    [19236]   = { kind = "defensive", cd = 90 },
    [47585]   = { kind = "defensive", cd = 120 },

    [360194]  = { kind = "offensive", cd = 120, buffs = { 1249810 } },
    [121471]  = { kind = "offensive", cd = 90 },
    [31224]   = { kind = "defensive", cd = 120 },
    [5277]    = { kind = "defensive", cd = 120 },

    [114050]  = { kind = "offensive", cd = 180, buffs = { 114050, 1219480 }, short = 10 },
    [114051]  = { kind = "offensive", cd = 180, short = 10 },
    [108271]  = { kind = "defensive", cd = 120 },
    -- Seen only through Primordial Bond, so a read without it hides the row.
    [198103]  = { kind = "defensive", cd = 180, buffs = { 381755 },
                  needs = { talents = { [1279819] = true }, likely = true } },

    [265187]  = { kind = "offensive", cd = 60, buffs = { 1276767 } },
    [104773]  = { kind = "defensive", cd = 180 },
    [108416]  = { kind = "defensive", cd = 60 },
    -- Seen only through Crashing Chaos, so a read without it hides the row.
    -- Destruction's 90 s needs Inferno.
    [1122]    = { kind = "offensive", cd = 120, buffs = { 417282 },
                  needs = { talents = { [417234] = true }, likely = true },
                  lengthNeeds = { talents = { [1280483] = true } } },

    [1719]    = { kind = "offensive", cd = 90 },
    [118038]  = { kind = "defensive", cd = 120 },
    [184364]  = { kind = "defensive", cd = 120 },
    -- Two charges; each use reads as the whole cooldown.
    [23920]   = { kind = "defensive", cd = 25 },

    -- Healer externals, in no spec list: HEALER_SPECS picks them by spec.
    [33206]   = { kind = "external", cd = 180 }, -- Pain Suppression
    [47788]   = { kind = "external", cd = 180 }, -- Guardian Spirit
    [102342]  = { kind = "external", cd = 90 },  -- Ironbark
    [116849]  = { kind = "external", cd = 120 }, -- Life Cocoon
    [6940]    = { kind = "external", cd = 120 }, -- Blessing of Sacrifice
    [357170]  = { kind = "external", cd = 60 },  -- Time Dilation

    -- Racials, in no spec list: RACIALS picks one by race.
    [20594]   = { kind = "defensive", cd = 120, buffs = { 65116 } },
    [265221]  = { kind = "offensive", cd = 120, buffs = { 265226, 273104 } },
    [58984]   = { kind = "defensive", cd = 120 },
}
for castID, spell in pairs(Data.SPELLS) do
    spell.id = castID
    spell.buffs = spell.buffs or { castID }
end

-- Per spec, in display order. A pair is { cast, the spec's talented seconds }.
Data.SPECS = {
    [250]  = { { 49028, 90 }, 48792 },
    [251]  = { 51271, 48792, { 48707, 40 } },
    [252]  = { 42650, 48792, { 48707, 40 } },
    [577]  = { 191427, 198589 },
    [1480] = { 198589 },
    [102]  = { { 194223, 120 }, 22812 },
    [103]  = { { 106951, 90 }, 22812, 61336 },
    [104]  = { { 22812, 34 }, { 61336, 137 } },
    [105]  = { 22812 },
    [1467] = { 375087, 363916 },
    [1468] = { 363916 },
    [1473] = { 403631, 363916 },
    [253]  = { { 19574, 30 }, { 186265, 120 }, 264735 },
    [254]  = { 288613, { 186265, 120 }, 264735 },
    [255]  = { 1250646, { 186265, 120 }, 264735 },
    [62]   = { 365350, { 45438, 150 }, { 342245, 55 } },
    [63]   = { { 190319, 60 }, { 45438, 150 }, { 342245, 50 } },
    [64]   = { { 45438, 120 }, { 342245, 50 } },
    [268]  = { 132578 },
    [269]  = { 123904, 122470, { 115203, 90 } },
    [270]  = { { 115203, 90 }, 122783 },
    [65]   = { { 31884, 60 }, { 642, 210 }, { 498, 42 } },
    [66]   = { { 31884, 60 }, { 31850, 63 } },
    [70]   = { { 31884, 60 }, { 642, 210 }, { 498, 63 } },
    [256]  = { 19236 },
    [257]  = { 200183, { 19236, 70 } },
    [258]  = { 228260, 47585, { 19236, 70 } },
    [259]  = { 360194, 31224, 5277 },
    [260]  = { 31224, 5277 },
    [261]  = { 121471, 31224, 5277 },
    [262]  = { { 114050, 120 }, { 108271, 90 }, 198103 },
    [263]  = { { 114051, 120 }, { 108271, 90 }, 198103 },
    [264]  = { { 108271, 90 }, 198103 },
    [265]  = { 104773, { 108416, 45 } },
    [266]  = { 265187, 104773, { 108416, 45 } },
    [267]  = { { 1122, 90 }, 104773, { 108416, 45 } },
    [71]   = { { 118038, 108 }, { 23920, 23 } },
    [72]   = { 1719, { 184364, 108 }, { 23920, 23 } },
    [73]   = { { 23920, 23 } },
}

-- Only roles a class fills with a single spec.
Data.ROLE_SPEC = {
    DEATHKNIGHT = { TANK = 250 },
    DEMONHUNTER = { TANK = 581 },
    DRUID       = { TANK = 104, HEALER = 105 },
    EVOKER      = { HEALER = 1468 },
    MONK        = { TANK = 268, HEALER = 270 },
    PALADIN     = { TANK = 66, HEALER = 65 },
    SHAMAN      = { HEALER = 264 },
    WARRIOR     = { TANK = 73 },
}

-- Healer specs whose external the healer externals box shows, with the class
-- each belongs to.
Data.HEALER_SPECS = {
    [256]  = { class = "PRIEST",  casts = { 33206 } },
    [257]  = { class = "PRIEST",  casts = { 47788 } },
    [105]  = { class = "DRUID",   casts = { 102342 } },
    [270]  = { class = "MONK",    casts = { 116849 } },
    [65]   = { class = "PALADIN", casts = { 6940 } },
    [1468] = { class = "EVOKER",  casts = { 357170 } },
}

-- Race token to racial, in editor order; raceID names the race on the
-- settings page.
Data.RACIALS = {
    { race = "Dwarf",         raceID = 3,  id = 20594 },
    { race = "DarkIronDwarf", raceID = 34, id = 265221 },
    { race = "NightElf",      raceID = 4,  id = 58984 },
}
