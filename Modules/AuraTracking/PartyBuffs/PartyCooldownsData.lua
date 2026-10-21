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
-- hide is a talent that removes the row in specs: it hides while the talent
-- is taken, and before talents are read only if likely.
-- active is set on a summon seen only through a stand-in buff: its
-- cell's aura button never shows, and the cell shows the summon's own icon
-- with a timer for active seconds from the cast, then the cooldown. off
-- starts the row switched off in every spec's spell list.
Data.SPELLS = {
    [49028]   = { kind = "offensive", cd = 120, buffs = { 81256 } },
    [48792]   = { kind = "defensive", cd = 120 },
    [48707]   = { kind = "defensive", cd = 60, buffs = { 48707, 444741 } },
    [51271]   = { kind = "offensive", cd = 45 },
    [42650]   = { kind = "offensive", cd = 90 },
    [1233448] = { kind = "offensive", cd = 45, buffs = { 1235391 } },
    [1249658] = { kind = "offensive", cd = 90, needs = { talents = { [1249658] = true }, likely = true } },
    -- Seen only through Chosen of Frostbrood.
    [279302]  = { kind = "offensive", cd = 90, buffs = { 1265630 }, active = 12,
                  needs = { talents = { [279302] = true }, likely = true }, off = true },

    [191427]  = { kind = "offensive", cd = 120, buffs = { 162264 }, short = 10 },
    [198589]  = { kind = "defensive", cd = 60, buffs = { 212800 } },
    -- Vengeance's Metamorphosis; its cooldown and buff are from game data.
    [187827]  = { kind = "defensive", cd = 120 },

    -- With Whirling Stars it has two charges. Incarnation shares a choice node
    -- with Convoke the Spirits, the less common pick.
    [194223]  = { kind = "offensive", cd = 180, buffs = { 194223, 102560, 390414 },
                  swap = { id = 102560, talents = { [102560] = true }, likely = true } },
    -- Feral's 60 s needs Ashamane's Guidance, which most Ferals skip.
    [391528]  = { kind = "offensive", cd = 120,
                  needs = { talents = { [391528] = true }, likely = false } },
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
    -- Windwalker's 90 s needs Xuen's Bond.
    [123904]  = { kind = "offensive", cd = 120, buffs = { 1248992 }, active = 20 },
    [115203]  = { kind = "defensive", cd = 360, buffs = { 115203, 120954 } },
    [122783]  = { kind = "defensive", cd = 90 },
    [122470]  = { kind = "defensive", cd = 90, buffs = { 125174 } },

    [31884]   = { kind = "offensive", cd = 120, buffs = { 31884, 231895, 454351, 216331, 389539 },
                  swap = { id = 389539, talents = { [389539] = true }, likely = true, specs = { [66] = true } },
                  hide = { talents = { [458359] = true }, likely = false, specs = { [70] = true } } },
    [642]     = { kind = "defensive", cd = 300 },
    [498]     = { kind = "defensive", cd = 60, buffs = { 498, 403876 } },
    [31850]   = { kind = "defensive", cd = 90 },

    [200183]  = { kind = "offensive", cd = 120 },
    [228260]  = { kind = "offensive", cd = 120, buffs = { 194249 } },
    -- Seen on the priest only through Twins of the Sun Priestess.
    [10060]   = { kind = "offensive", cd = 120,
                  needs = { talents = { [373466] = true }, likely = true } },
    -- The 70 s needs Angel's Mercy.
    [19236]   = { kind = "defensive", cd = 90 },
    [47585]   = { kind = "defensive", cd = 120 },

    [360194]  = { kind = "offensive", cd = 120, buffs = { 1249810 } },
    [121471]  = { kind = "offensive", cd = 90 },
    [1856]    = { kind = "offensive", cd = 120, buffs = { 11327 } },
    [31224]   = { kind = "defensive", cd = 120 },
    [5277]    = { kind = "defensive", cd = 120 },

    -- Elemental's 120 s needs First Ascendant.
    [114050]  = { kind = "offensive", cd = 180, buffs = { 114050, 1219480 }, short = 10 },
    [114051]  = { kind = "offensive", cd = 180, short = 10 },
    [108271]  = { kind = "defensive", cd = 120 },
    -- Seen only through Primordial Bond, so a read without it hides the row.
    [198103]  = { kind = "defensive", cd = 180, buffs = { 381755 }, active = 30,
                  needs = { talents = { [1279819] = true }, likely = true } },

    [265187]  = { kind = "offensive", cd = 60, buffs = { 1276767 } },
    [104773]  = { kind = "defensive", cd = 180 },
    [108416]  = { kind = "defensive", cd = 60 },
    -- Seen only through Crashing Chaos, so a read without it hides the row.
    -- Destruction's 90 s needs Inferno.
    [1122]    = { kind = "offensive", cd = 120, buffs = { 417282 }, active = 30,
                  needs = { talents = { [417234] = true }, likely = true } },

    [1719]    = { kind = "offensive", cd = 90 },
    [118038]  = { kind = "defensive", cd = 120 },
    [184364]  = { kind = "defensive", cd = 120 },
    [23920]   = { kind = "defensive", cd = 25 },

    -- Healer externals, in no spec list: HEALER_SPECS picks them by spec.
    [33206]   = { kind = "external", cd = 180 }, -- Pain Suppression
    [47788]   = { kind = "external", cd = 180, buffs = { 47788, 255312 } }, -- Guardian Spirit
    [102342]  = { kind = "external", cd = 90 },  -- Ironbark
    [116849]  = { kind = "external", cd = 120 }, -- Life Cocoon
    [6940]    = { kind = "external", cd = 120 }, -- Blessing of Sacrifice
    [357170]  = { kind = "external", cd = 60 },  -- Time Dilation

    -- Box rows, in no spec list: BOX_ROWS picks them by class and spec.
    -- Blessing of Protection's cell shows Blessing of Spellwarding, which
    -- shares its cooldown, once that talent is read as taken.
    [1022]    = { kind = "external", cd = 300, buffs = { 1022, 204018 },
                  swap = { id = 204018, talents = { [204018] = true }, likely = false } },
    [53480]   = { kind = "external", cd = 120,
                  needs = { talents = { [53480] = true }, likely = false } },
    [29166]   = { kind = "external", cd = 180,
                  needs = { talents = { [29166] = true }, likely = true } },
    [406732]  = { kind = "external", cd = 180, buffs = { 406732, 406789 } },
    [196718]  = { kind = "external", cd = 300, buffs = { 209426 },
                  needs = { talents = { [196718] = true }, likely = true } },
    [51052]   = { kind = "external", cd = 240, buffs = { 145629 },
                  needs = { talents = { [51052] = true }, likely = true } },
    [97462]   = { kind = "external", cd = 180, buffs = { 97463 },
                  needs = { talents = { [97462] = true }, likely = true } },
    [374227]  = { kind = "external", cd = 120,
                  needs = { talents = { [374227] = true }, likely = true } },
    [31821]   = { kind = "external", cd = 180, buffs = { 31821, 317929 },
                  needs = { talents = { [31821] = true }, likely = true } },
    [740]     = { kind = "external", cd = 180, buffs = { 740, 157982, 1264623 },
                  needs = { talents = { [740] = true }, likely = true } },
    -- The game reports no base cooldown for it.
    [363534]  = { kind = "external", cd = 240,
                  needs = { talents = { [363534] = true }, likely = true } },
    [64843]   = { kind = "external", cd = 180, buffs = { 64843, 64844 },
                  needs = { talents = { [64843] = true }, likely = true } },
    [62618]   = { kind = "external", cd = 180, buffs = { 81782 },
                  needs = { talents = { [62618] = true }, likely = true } },
    -- The game reports no base cooldown for it.
    [98008]   = { kind = "external", cd = 180, buffs = { 325174 },
                  needs = { talents = { [98008] = true }, likely = true } },
    [359816]  = { kind = "external", cd = 120, buffs = { 359816, 362361 } },

    -- Racials, in no spec list: RACIALS picks one by race.
    [20594]   = { kind = "defensive", cd = 120, buffs = { 65116 } },
    [265221]  = { kind = "offensive", cd = 120, buffs = { 265226, 273104 } },
    [58984]   = { kind = "defensive", cd = 120 },
}
for castID, spell in pairs(Data.SPELLS) do
    spell.id = castID
    spell.buffs = spell.buffs or { castID }
end

-- Trinkets whose buff aura carries another ID than the item's use spell.
Data.TRINKET_BUFFS = {
    [1291894] = { 1307578 }, -- Soulcoiler Ritual Vessel
    [1254339] = { 1255200 }, -- Unstable Felheart Crystal
}

-- Talent changes to a cast's cooldown, per rank: add seconds or pct percent,
-- and spec limits one to a spec. A cell counts the length once every talent a
-- mod names is read.
local MODS = {
    [49028]   = { { 377637, add = -30 } },
    [48707]   = { { 205727, add = -20 }, { 457574, add = 20 } },
    [194223]  = { { 390378, add = -60 }, { 468743, add = -60 } },
    [106951]  = { { 391174, add = -60 }, { 391548, add = -30 } },
    [391528]  = { { 391548, spec = 103, add = -60 } },
    [22812]   = { { spec = 104, add = -15 }, { 203965, pct = -12 } },
    [61336]   = { { 203965, pct = -12 } },
    [102342]  = { { 382552, add = -20 } },
    [403631]  = { { 412713, pct = -10 } },
    [363916]  = { { 412713, pct = -10 } },
    [357170]  = { { 376204, add = -10 } },
    [19574]   = { { 231548, add = -60 } },
    [288613]  = { { 260404, add = -30 } },
    [1250646] = { { 1251790, add = -15 } },
    [186265]  = { { 266921, add = -15 }, { 1258485, add = -30 } },
    [190319]  = { { 1254194, add = -60 } },
    [45438]   = { { 382424, add = -30 }, { 1265517, add = -30 }, { 1244110, add = -30 } },
    [342245]  = { { 342249, add = -5 }, { 1255166, add = -10 } },
    [132578]  = { { 450989, add = -25 } },
    [123904]  = { { 392986, add = -30 } },
    [115203]  = { { spec = 269, add = -240 }, { spec = 270, add = -240 }, { 388813, add = -30 } },
    [116849]  = { { 202424, add = -45 } },
    [31884]   = { { spec = 70, add = -60 }, { 1241511, add = -30 }, { 204074, pct = -50 } },
    [642]     = { { 114154, pct = -30 }, { 378425, pct = -15 } },
    [498]     = { { spec = 70, add = 30 }, { 114154, pct = -30 } },
    [31850]   = { { 114154, pct = -30 } },
    [6940]    = { { 384820, add = -60 }, { 384820, spec = 65, add = 45 } },
    [19236]   = { { 238100, add = -20 } },
    [47585]   = { { 288733, add = -30 } },
    [114050]  = { { 462440, add = -60 } },
    [114051]  = { { 384444, add = -60 } },
    [108271]  = { { 381647, add = -30 } },
    [1122]    = { { 1280483, add = -30 } },
    [104773]  = { { 386659, add = -45 } },
    [108416]  = { { 386686, add = -15 } },
    [118038]  = { { 391271, pct = -10 } },
    [184364]  = { { 391271, pct = -10 } },
    [23920]   = { { spec = 73, add = -5 }, { 391271, pct = -10 } },
    [1022]    = { { 384909, add = -60 }, { 378425, pct = -15 } },
    [196718]  = { { 389783, add = -120 } },
    [51052]   = { { 374383, add = -60 } },
    [363534]  = { { 381922, add = -60 } },
}
for castID, mods in pairs(MODS) do Data.SPELLS[castID].mods = mods end

-- Talents that give a cast its second charge. A cell counts it once the
-- talent is read as taken; unread, it counts nothing.
local CHARGES = {
    [33206]  = { 373035 },   -- Pain Suppression: Protector of the Frail
    [357170] = { 376204 },   -- Time Dilation: Just in Time
    [194223] = { 468743 },   -- Celestial Alignment: Whirling Stars
    [45438]  = { 1244110 },  -- Ice Block: Glacial Bulwark
    [363916] = { 375406 },   -- Obsidian Scales: Obsidian Bulwark
    [198589] = { 1266307 },  -- Blur: Demonic Resilience
    [264735] = { 459450 },   -- Survival of the Fittest: Padded Armor
}
for castID, talents in pairs(CHARGES) do
    local spell = Data.SPELLS[castID]
    spell.mods = spell.mods or {}
    for _, talent in ipairs(talents) do spell.mods[#spell.mods + 1] = { talent, charges = 1 } end
end

-- Per spec, in display order. A pair is { cast, the spec's listed seconds },
-- with charges = n where the spec always has n charges.
Data.SPECS = {
    [250]  = { { 49028, 90 }, 48792 },
    [251]  = { 51271, 1249658, 279302, 48792, { 48707, 40 } },
    [252]  = { 42650, 1233448, 48792, { 48707, 40 } },
    [577]  = { 191427, 198589 },
    [581]  = { 187827 },
    [1480] = { 198589 },
    [102]  = { { 194223, 120 }, 391528, 22812 },
    [103]  = { { 106951, 90 }, 391528, 22812, 61336 },
    [104]  = { { 22812, 34 }, { 61336, 137, charges = 2 } },
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
    [269]  = { { 123904, 90 }, 122470, { 115203, 90 } },
    [270]  = { { 115203, 90 }, 122783 },
    [65]   = { { 31884, 90 }, { 642, 210 }, { 498, 42 } },
    [66]   = { { 31884, 60 }, { 642, 210 }, { 31850, 63 } },
    [70]   = { { 31884, 60 }, { 642, 210 }, { 498, 63 } },
    [256]  = { 10060, { 19236, 70 } },
    [257]  = { 200183, 10060, { 19236, 70 } },
    [258]  = { 228260, 10060, 47585, { 19236, 70 } },
    [259]  = { 360194, 1856, 31224, 5277 },
    [260]  = { 1856, 31224, 5277 },
    [261]  = { 121471, 1856, 31224, 5277 },
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

-- The raid cooldowns box's rows beyond the healer externals, in each
-- member's display order. specs lists the owning specs and roles the roles
-- they fill; an anySpec row shows from the class before the spec is known.
-- A target row's buff lands on whoever it was cast on, so every party unit
-- is watched; an owner row's appears on its caster, who alone is watched.
Data.BOX_ROWS = {
    { id = 1022,   class = "PALADIN",     specs = { [65] = true, [66] = true, [70] = true },
      anySpec = true, watch = "target" },
    { id = 53480,  class = "HUNTER",      specs = { [253] = true, [254] = true, [255] = true },
      anySpec = true, watch = "target" },
    { id = 29166,  class = "DRUID",       specs = { [102] = true, [103] = true, [104] = true, [105] = true },
      anySpec = true, watch = "target" },
    { id = 406732, class = "EVOKER",      specs = { [1473] = true }, roles = { DAMAGER = true }, watch = "target" },
    { id = 196718, class = "DEMONHUNTER", specs = { [577] = true, [581] = true, [1480] = true },
      anySpec = true, watch = "owner" },
    { id = 51052,  class = "DEATHKNIGHT", specs = { [250] = true, [251] = true, [252] = true },
      anySpec = true, watch = "owner" },
    { id = 97462,  class = "WARRIOR",     specs = { [71] = true, [72] = true, [73] = true },
      anySpec = true, watch = "owner" },
    { id = 374227, class = "EVOKER",      specs = { [1467] = true, [1468] = true, [1473] = true },
      anySpec = true, watch = "owner" },
    { id = 31821,  class = "PALADIN",     specs = { [65] = true },   roles = { HEALER = true }, watch = "owner" },
    { id = 740,    class = "DRUID",       specs = { [105] = true },  roles = { HEALER = true }, watch = "owner" },
    { id = 363534, class = "EVOKER",      specs = { [1468] = true }, roles = { HEALER = true }, watch = "owner" },
    { id = 64843,  class = "PRIEST",      specs = { [257] = true },  roles = { HEALER = true }, watch = "owner" },
    { id = 62618,  class = "PRIEST",      specs = { [256] = true },  roles = { HEALER = true }, watch = "owner" },
    { id = 98008,  class = "SHAMAN",      specs = { [264] = true },  roles = { HEALER = true }, watch = "owner" },
    { id = 359816, class = "EVOKER",      specs = { [1468] = true }, roles = { HEALER = true }, watch = "owner" },
}

-- Race token to racial, in editor order; raceID names the race on the
-- settings page.
Data.RACIALS = {
    { race = "Dwarf",         raceID = 3,  id = 20594 },
    { race = "DarkIronDwarf", raceID = 34, id = 265221 },
    { race = "NightElf",      raceID = 4,  id = 58984 },
}
