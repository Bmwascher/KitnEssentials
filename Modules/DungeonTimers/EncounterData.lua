-- ╔══════════════════════════════════════════════════════════╗
-- ║  EncounterData.lua                                       ║
-- ║  Curated cast-duration table for the new DungeonTimers   ║
-- ║  module. Keyed by encounterID, then BigWigs spellID.     ║
-- ║                                                          ║
-- ║  Schema:                                                 ║
-- ║    KE.EncounterData[encounterID] = {                     ║
-- ║        name    = "Boss display name",                    ║
-- ║        dungeon = "DungeonKey",                           ║
-- ║        spells  = {                                       ║
-- ║            [spellID] = {                                 ║
-- ║                name            = "Spell display name",   ║
-- ║                castType        = "begincast"|"cast"|     ║
-- ║                                  "channel",              ║
-- ║                castDuration    = <seconds>,  -- optional ║
-- ║                channelDuration = <seconds>,  -- optional ║
-- ║                role            = "tank"|"heal"|          ║
-- ║                                  "mechanic"|"other",     ║
-- ║            },                                            ║
-- ║            ...                                           ║
-- ║        },                                                ║
-- ║    }                                                     ║
-- ║                                                          ║
-- ║  Cast durations + role classifications cross-referenced  ║
-- ║  against EXBossData (C:\...\AddOns\EXBossData\            ║
-- ║  EncounterData.lua). EXBoss eventType is Chinese:        ║
-- ║  坦克=tank, 治疗=heal, 机制=mechanic, 其他=other.            ║
-- ║                                                          ║
-- ║  Lookup at BigWigs_Timer time: O(1) by encounterID +     ║
-- ║  spellID. The BigWigs spellId we receive matches         ║
-- ║  EXBoss's `evenSpellID`, NOT its `spellID` field (which  ║
-- ║  is the actual hostile-cast spellId — different in some  ║
-- ║  cases like Barrage 1260643 vs. 1260648 cast).           ║
-- ║                                                          ║
-- ║  N3 seed: MaisaraCaverns only. Other dungeons land as    ║
-- ║  separate passes once the layering is proven.            ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

KE.EncounterData = KE.EncounterData or {}

-- ╔══════════════════════════════════════════════════════════╗
-- ║  MaisaraCaverns                                          ║
-- ╚══════════════════════════════════════════════════════════╝

KE.EncounterData[3212] = {
    name = "Muro'jin and Nekraxx",
    dungeon = "MaisaraCaverns",
    spells = {
        [1266480] = { name = "Flanking Spear",   castType = "begincast", castDuration = 2.5, role = "tank", display = "bar" },
        [1243900] = { name = "Fetid Quillstorm", castType = "begincast", castDuration = 3,   role = "other" },
        [1260731] = { name = "Freezing Trap",    castType = "begincast", castDuration = 2,   role = "mechanic" },
        [1260643] = { name = "Barrage",          castType = "cast",      channelDuration = 5, role = "heal" },
        [1246666] = { name = "Infected Pinions", castType = "begincast", castDuration = 1.5, role = "heal" },
        [1249479] = { name = "Carrion Swoop",    castType = "begincast", castDuration = 4.5, role = "mechanic" },
    },
}

KE.EncounterData[3213] = {
    name = "Vordaza",
    dungeon = "MaisaraCaverns",
    spells = {
        -- TODO: fill in English `name` fields after engaging this boss in-game
        [1251554] = { castType = "begincast", castDuration = 1,   channelDuration = 4,   role = "tank" },
        [1252054] = { castType = "begincast", castDuration = 2.5, channelDuration = 4.5, role = "other" },
        [1251204] = { castType = "cast",                          channelDuration = 4,   role = "mechanic" },
        [1250708] = { castType = "channel",                       channelDuration = 60,  role = "heal" },
        -- 1251775 omitted: EXBoss has channelDuration=604800 ("until killed" sentinel); not a real cast
        -- 1251996 omitted: EXBoss has castType=nil (passive/aura, no cast bar)
    },
}

KE.EncounterData[3214] = {
    name = "Raktul, the Soulvessel",
    dungeon = "MaisaraCaverns",
    spells = {
        -- TODO: fill in English `name` fields after engaging this boss in-game
        [1251023] = { castType = "channel",                       channelDuration = 4.5, role = "tank" },
        [1252676] = { castType = "begincast", castDuration = 4.5,                        role = "heal" },
        [1253788] = { castType = "begincast", castDuration = 3,                          role = "mechanic" },
    },
}
