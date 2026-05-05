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
-- ║                display         = "bar"|"text",           ║
-- ║                displayText     = "DODGE"|...,  -- (N12)  ║
-- ║                                  -- short curated label  ║
-- ║                                  -- shown instead of the ║
-- ║                                  -- BigWigs spell name.  ║
-- ║                                  -- e.g. "TANK HIT",     ║
-- ║                                  -- "INTERRUPT",         ║
-- ║                                  -- "SPREAD". Fall back  ║
-- ║                                  -- to BigWigs name when ║
-- ║                                  -- absent.              ║
-- ║                extendByChannel = true,                   ║
-- ║                                  -- opt-in: extend the   ║
-- ║                                  -- bar by channelDuration║
-- ║                                  -- on top of castDuration║
-- ║                                  -- so the bar hits 0 at ║
-- ║                                  -- end-of-channel. Use  ║
-- ║                                  -- for spells whose     ║
-- ║                                  -- effect lands at the  ║
-- ║                                  -- END of the channel   ║
-- ║                                  -- (e.g. adds spawn     ║
-- ║                                  -- after a 4s channel   ║
-- ║                                  -- finishes), NOT the   ║
-- ║                                  -- start. Default off — ║
-- ║                                  -- channels normally    ║
-- ║                                  -- damage at zero.      ║
-- ║                showAtSeconds   = <seconds>,    -- (N13a) ║
-- ║                                  -- per-spell visibility ║
-- ║                                  -- override. Hides the  ║
-- ║                                  -- bar until last N sec ║
-- ║                                  -- of total lifetime.   ║
-- ║                                  -- Wins over the group  ║
-- ║                                  -- ShowAtSeconds slider.║
-- ║                                  -- 0 = force always     ║
-- ║                                  -- visible even when    ║
-- ║                                  -- group hides. Omit    ║
-- ║                                  -- to inherit group.    ║
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
        [1266480] = { name = "Flanking Spear",   castType = "begincast", castDuration = 2.5, role = "tank",     display = "bar", displayText = "TANK HIT" },
        [1243900] = { name = "Fetid Quillstorm", castType = "begincast", castDuration = 3,   role = "other",                     displayText = "FEET" },
        [1260731] = { name = "Freezing Trap",    castType = "begincast", castDuration = 2,   role = "mechanic",                  displayText = "FEET" },
        [1260643] = { name = "Barrage",          castType = "cast",      channelDuration = 5, role = "heal",                  displayText = "FRONTAL" },
        [1246666] = { name = "Infected Pinions", castType = "begincast", castDuration = 1.5,  role = "heal",                  displayText = "AOE"     },
        [1249479] = { name = "Carrion Swoop",    castType = "begincast", castDuration = 4.5,  role = "mechanic",              displayText = "DODGE"   },
    },
}

KE.EncounterData[3213] = {
    name = "Vordaza",
    dungeon = "MaisaraCaverns",
    spells = {
        [1251554] = { name = "Drain Soul",           castType = "begincast", castDuration = 1,   channelDuration = 4,   role = "tank",     display = "bar", displayText = "TANK HIT"     },
        [1252054] = { name = "Unmake",               castType = "begincast", castDuration = 2.5, channelDuration = 4.5, role = "other",                     displayText = "FRONTAL"      },
        [1251204] = { name = "Wrest Phantoms",       castType = "cast",                          channelDuration = 4,   role = "mechanic", extendByChannel = true, displayText = "ADDS" },
        [1250708] = { name = "Necrotic Convergence", castType = "channel",                       channelDuration = 60,  role = "other",                     displayText = "INTERMISSION" },
    },
}

KE.EncounterData[3214] = {
    name = "Rak'tul, Vessel of Souls",
    dungeon = "MaisaraCaverns",
    spells = {
        [1251023] = { name = "Spiritbreaker",      castType = "channel",                       channelDuration = 4.5, role = "tank",     display = "bar", displayText = "TANK HIT"     },
        [1252676] = { name = "Crush Souls",        castType = "begincast", castDuration = 4.5,                        role = "mechanic", displayText = "TOTEMS"       },
        [1253788] = { name = "Soulrending Roar",   castType = "begincast", castDuration = 3,                          role = "mechanic", displayText = "INTERMISSION" },
    },
}
