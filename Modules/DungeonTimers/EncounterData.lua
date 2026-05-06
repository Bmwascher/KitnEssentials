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
-- ║                disabled        = true,                   ║
-- ║                                  -- curator-default      ║
-- ║                                  -- hard-disable. The    ║
-- ║                                  -- bar never renders    ║
-- ║                                  -- unless the user      ║
-- ║                                  -- explicitly enables   ║
-- ║                                  -- via the GUI (which   ║
-- ║                                  -- stores false in      ║
-- ║                                  -- db.SpellDisabled).   ║
-- ║                                  -- Use for spammable    ║
-- ║                                  -- abilities (kicks,    ║
-- ║                                  -- DoT-tick spells)     ║
-- ║                                  -- that would clutter   ║
-- ║                                  -- the screen by        ║
-- ║                                  -- default.             ║
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
-- ║  Optional `bossOrder` field on an encounter overrides    ║
-- ║  the default encounterID-ascending sort. Use when an     ║
-- ║  older dungeon's encounterIDs don't reflect in-dungeon   ║
-- ║  boss order (e.g. Pit of Saron: 1999/2001/2000 sorts to  ║
-- ║  Garfrost/Tyrannus/Ick&Krick but actual order is         ║
-- ║  Garfrost/Ick&Krick/Tyrannus).                           ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

KE.EncounterData = KE.EncounterData or {}

-- ╔══════════════════════════════════════════════════════════╗
-- ║  AlgetharAcademy                                         ║
-- ╚══════════════════════════════════════════════════════════╝

KE.EncounterData[2562] = {
    name = "Vexamus",
    dungeon = "AlgetharAcademy",
    spells = {
        -- 386544 vs EXBoss 387691 — LittleWigs ID wins (BigWigs Timer key); EXBoss had no cast data for either ID
        [386544] = { name = "Arcane Orbs",       castType = "cast",                                          role = "other"    },
        [385958] = { name = "Arcane Expulsion",  castType = "begincast", castDuration = 4,                   role = "tank",     display = "bar", displayText = "TANK HIT" },
        [386173] = { name = "Mana Bombs",        castType = "begincast", castDuration = 2.5,                 role = "heal"     },
        [388537] = { name = "Arcane Fissure",    castType = "begincast", castDuration = 3,                   role = "mechanic" },
    },
}

KE.EncounterData[2563] = {
    name = "Overgrown Ancient",
    dungeon = "AlgetharAcademy",
    spells = {
        [388544] = { name = "Barkbreaker",  castType = "begincast", castDuration = 1,                      role = "tank",     display = "bar", displayText = "TANK HIT" },
        [388796] = { name = "Germinate",    castType = "cast",                       channelDuration = 4,  role = "other"    },
        [388623] = { name = "Branch Out",   castType = "begincast", castDuration = 2.5,                    role = "mechanic" },
        [388923] = { name = "Burst Forth",  castType = "begincast", castDuration = 3,                      role = "mechanic" },
    },
}

KE.EncounterData[2564] = {
    name = "Crawth",
    dungeon = "AlgetharAcademy",
    spells = {
        [376997] = { name = "Savage Peck",       castType = "begincast", castDuration = 3,                   role = "tank",     display = "bar", displayText = "TANK HIT" },
        [377004] = { name = "Deafening Screech", castType = "begincast", castDuration = 2.5,                 role = "heal"     },
        [377034] = { name = "Overpowering Gust", castType = "begincast", castDuration = 4,                   role = "other"    },
    },
}

KE.EncounterData[2565] = {
    name = "Echo of Doragosa",
    dungeon = "AlgetharAcademy",
    spells = {
        -- 373326 vs EXBoss 373325 — LittleWigs ID wins (BigWigs fires Timer with the LittleWigs one)
        [373326]  = { name = "Arcane Missiles", castType = "cast",                                           role = "other"    },
        [1282251] = { name = "Astral Blast",    castType = "begincast", castDuration = 3,                    role = "tank",     display = "bar", displayText = "TANK HIT" },
        -- 374343 vs EXBoss 374350 — LittleWigs ID wins (BigWigs Timer key); cast data assumed same as 374350
        [374343]  = { name = "Energy Bomb",     castType = "begincast", castDuration = 1.5,                  role = "heal"     },
        [388822]  = { name = "Power Vacuum",    castType = "begincast", castDuration = 4,                    role = "other"    },
    },
}

-- ╔══════════════════════════════════════════════════════════╗
-- ║  MagistersTerrace                                        ║
-- ╚══════════════════════════════════════════════════════════╝

KE.EncounterData[3071] = {
    name = "Arcanotron Custos",
    dungeon = "MagistersTerrace",
    spells = {
        [474496]  = { name = "Repulsing Slam",     castType = "begincast", castDuration = 2.5,                     role = "tank",     display = "bar", displayText = "TANK HIT" },
        [1214081] = { name = "Arcane Expulsion",   castType = "begincast", castDuration = 3,                       role = "other"    },
        [1214032] = { name = "Ethereal Shackles",  castType = "cast",                                              role = "heal"     },
        -- Refueling Protocol is the intermission/phase-transition ability
        -- (LittleWigs flags it as CASTBAR; EXBoss voice = "转阶段" / phase change).
        -- DANCE displayText (aliased to INTERMISSION color), role = "other" for everyone-visibility.
        [474345]  = { name = "Refueling Protocol", castType = "begincast", castDuration = 3,   channelDuration = 20, role = "other",                displayText = "DANCE"    },
    },
}

KE.EncounterData[3072] = {
    name = "Seranel Sunlash",
    dungeon = "MagistersTerrace",
    spells = {
        -- 1225787 vs EXBoss 1225792 — LittleWigs ID wins (BigWigs Timer key); cast data assumed same as 1225792
        [1225787] = { name = "Runic Mark",         castType = "begincast", castDuration = 3,                       role = "heal"     },
        [1224903] = { name = "Suppression Zone",   castType = "begincast", castDuration = 3,                       role = "mechanic" },
        [1248689] = { name = "Hastening Ward",     castType = "cast",                                              role = "tank",     display = "bar", displayText = "TANK HIT" },
        [1225193] = { name = "Wave of Silence",    castType = "begincast", castDuration = 5,                       role = "mechanic" },
    },
}

KE.EncounterData[3073] = {
    name = "Gemellus",
    dungeon = "MagistersTerrace",
    spells = {
        [1223847] = { name = "Triplicate",         castType = "begincast", castDuration = 2.5,                     role = "mechanic" },
        [1284954] = { name = "Cosmic Sting",       castType = "begincast", castDuration = 4,                       role = "heal"     },
        [1253709] = { name = "Neural Link",        castType = "begincast", castDuration = 2,                       role = "mechanic" },
        [1224299] = { name = "Astral Grasp",       castType = "begincast", castDuration = 4,   channelDuration = 8, role = "heal"     },
    },
}

KE.EncounterData[3074] = {
    name = "Degentrius",
    dungeon = "MagistersTerrace",
    spells = {
        [1280113] = { name = "Hulking Fragment",      castType = "begincast", castDuration = 3,                    role = "tank",     display = "bar", displayText = "TANK HIT" },
        -- 1215897 vs EXBoss 1215893 — LittleWigs ID wins (BigWigs Timer key); cast data assumed same as 1215893
        [1215897] = { name = "Devouring Entropy",     castType = "cast",                                           role = "heal"     },
        [1215087] = { name = "Unstable Void Essence", castType = "begincast", castDuration = 2.5,                  role = "other"    },
    },
}

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

-- ╔══════════════════════════════════════════════════════════╗
-- ║  NexusPointXenas                                         ║
-- ╚══════════════════════════════════════════════════════════╝

KE.EncounterData[3328] = {
    name = "Chief Corewright Kasreth",
    dungeon = "NexusPointXenas",
    spells = {
        -- 1251579 vs EXBoss 1251183 — LittleWigs ID wins (BigWigs Timer key); EXBoss has no cast data for either ID
        [1251579] = { name = "Leyline Array",          castType = "cast",                                          role = "other"    },
        [1251772] = { name = "Reflux Charge",          castType = "begincast", castDuration = 2.1,                 role = "other"    },
        [1264048] = { name = "Flux Collapse",          castType = "cast",                                          role = "other"    },
        [1257509] = { name = "Corespark Detonation",   castType = "begincast", castDuration = 5,                   role = "heal"     },
    },
}

KE.EncounterData[3332] = {
    name = "Corewarden Nysarra",
    dungeon = "NexusPointXenas",
    spells = {
        [1247937] = { name = "Umbral Lash",           castType = "begincast", castDuration = 0.8,                   role = "tank",     display = "bar", displayText = "TANK HIT" },
        -- 1249014 vs EXBoss 1249027 — LittleWigs ID wins (BigWigs Timer key); cast data assumed same as 1249027
        [1249014] = { name = "Eclipsing Step",        castType = "begincast", castDuration = 2.5, channelDuration = 2, role = "heal"  },
        [1252703] = { name = "Null Vanguard",         castType = "cast",                                            role = "mechanic" },
        [1264439] = { name = "Lightscar Flare",       castType = "cast",                          castDuration = 4.2, role = "mechanic" },
        [1271684] = { name = "Devour the Unworthy",   castType = "begincast", castDuration = 3.4, channelDuration = 5, role = "other"   },
    },
}

KE.EncounterData[3333] = {
    name = "Lothraxion",
    dungeon = "NexusPointXenas",
    spells = {
        [1253950] = { name = "Searing Rend",         castType = "begincast", castDuration = 3,                     role = "tank",     display = "bar", displayText = "TANK HIT" },
        [1253855] = { name = "Brilliant Dispersion", castType = "begincast", castDuration = 4,                     role = "heal"     },
        [1255531] = { name = "Flicker",              castType = "cast",                                            role = "other"    },
        -- 1257595 vs EXBoss 1257601 — LittleWigs ID wins (BigWigs Timer key); cast data assumed same as 1257601.
        -- Divine Guile is an intermission/phase-transition (EXBoss voice = "转阶段", sentinel channelDuration);
        -- DANCE displayText (aliased to INTERMISSION color), role = "other" for everyone-visibility.
        [1257595] = { name = "Divine Guile",         castType = "begincast", castDuration = 0.5,                   role = "other",                  displayText = "DANCE"    },
    },
}

-- ╔══════════════════════════════════════════════════════════╗
-- ║  PitOfSaron                                              ║
-- ╚══════════════════════════════════════════════════════════╝

KE.EncounterData[1999] = {
    name = "Forgemaster Garfrost",
    dungeon = "PitOfSaron",
    bossOrder = 1,
    spells = {
        [1261299] = { name = "Throw Saronite",   castType = "begincast", castDuration = 2,   channelDuration = 6,   role = "other"    },
        [1261546] = { name = "Orebreaker",       castType = "begincast", castDuration = 4.5,                        role = "tank",     display = "bar", displayText = "TANK HIT" },
        [1262029] = { name = "Glacial Overload", castType = "begincast", castDuration = 5,   channelDuration = 3.5, role = "other"    },
        [1261847] = { name = "Cryostomp",        castType = "begincast", castDuration = 2.5,                        role = "heal"     },
    },
}

KE.EncounterData[2001] = {
    name = "Ick & Krick",
    dungeon = "PitOfSaron",
    bossOrder = 2,
    spells = {
        [1264287] = { name = "Blight Smash",     castType = "begincast", castDuration = 4,                          role = "tank",     display = "bar", displayText = "TANK HIT" },
        [1264336] = { name = "Plague Expulsion", castType = "begincast", castDuration = 2.5,                        role = "other"    },
        [1264027] = { name = "Shade Shift",      castType = "begincast", castDuration = 4,                          role = "mechanic" },
        [1264363] = { name = "Get 'Em, Ick!",    castType = "begincast", castDuration = 4,                          role = "mechanic" },
    },
}

KE.EncounterData[2000] = {
    name = "Scourgelord Tyrannus",
    dungeon = "PitOfSaron",
    bossOrder = 3,
    spells = {
        [1262745] = { name = "Rime Blast",          castType = "begincast", castDuration = 6,                       role = "mechanic" },
        [1262582] = { name = "Scourgelord's Brand", castType = "begincast", castDuration = 2.5,                     role = "tank",     display = "bar", displayText = "TANK HIT" },
        [1263756] = { name = "Death's Grasp",       castType = "cast",                          channelDuration = 6, role = "other"   },
        [1263406] = { name = "Army of the Dead",    castType = "begincast", castDuration = 5,                       role = "mechanic" },
        [1276948] = { name = "Ice Barrage",         castType = "cast",                          channelDuration = 4.5, role = "other" },
        [1276648] = { name = "Bone Infusion",       castType = "begincast", castDuration = 3,                       role = "heal"     },
    },
}

-- ╔══════════════════════════════════════════════════════════╗
-- ║  SeatOfTriumvirate                                       ║
-- ╚══════════════════════════════════════════════════════════╝

KE.EncounterData[2065] = {
    name = "Zuraal",
    dungeon = "SeatOfTriumvirate",
    spells = {
        [1263440] = { name = "Void Slash",     castType = "cast",                        channelDuration = 1.5, role = "tank",     display = "bar", displayText = "TANK HIT" },
        [1263282] = { name = "Decimate",       castType = "begincast", castDuration = 5,                        role = "mechanic" },
        [1268916] = { name = "Null Palm",      castType = "begincast", castDuration = 3.5,                      role = "other"    },
        [1263399] = { name = "Oozing Slam",    castType = "begincast", castDuration = 3,                        role = "heal"     },
        [1263297] = { name = "Crashing Void",  castType = "begincast", castDuration = 5,                        role = "mechanic" },
    },
}

KE.EncounterData[2066] = {
    name = "Saprish",
    dungeon = "SeatOfTriumvirate",
    spells = {
        -- 245742 vs EXBoss 245738 — LittleWigs ID wins (BigWigs Timer key); cast data assumed same as 245738 ("Shadow Strike")
        [245742]  = { name = "Shadow Pounce",  castType = "cast",                                          role = "heal"     },
        -- 1248219 vs EXBoss 247175 — LittleWigs ID wins (BigWigs Timer key); EXBoss had no cast data either way (passive)
        [1248219] = { name = "Void Bomb",      castType = "cast",                                          role = "other"    },
        -- 1280065 vs EXBoss 1263509 — LittleWigs ID wins (BigWigs Timer key); cast data assumed same as 1263509 ("Phase Charge")
        [1280065] = { name = "Phase Dash",     castType = "cast",                                          role = "mechanic" },
        [1263523] = { name = "Overload",       castType = "begincast", castDuration = 4,                   role = "heal"     },
    },
}

KE.EncounterData[2067] = {
    name = "Viceroy Nezhar",
    dungeon = "SeatOfTriumvirate",
    spells = {
        [244750]  = { name = "Mind Blast",          castType = "begincast", castDuration = 2,                   role = "other"    },
        [1277358] = { name = "Gates of the Abyss",  castType = "cast",                                          role = "other"    },
        [1263542] = { name = "Mass Void Infusion",  castType = "begincast", castDuration = 2, channelDuration = 5, role = "heal"  },
        [1263538] = { name = "Umbral Tentacles",    castType = "begincast", castDuration = 3,                   role = "heal"     },
        [1263528] = { name = "Repulse",             castType = "begincast", castDuration = 2,                   role = "mechanic" },
    },
}

KE.EncounterData[2068] = {
    name = "L'ura",
    dungeon = "SeatOfTriumvirate",
    spells = {
        [1265421] = { name = "Dirge of Despair",            castType = "begincast", castDuration = 4,                   role = "heal"     },
        [1264196] = { name = "Disintegrate",                castType = "begincast", castDuration = 3, channelDuration = 5, role = "other" },
        [1265463] = { name = "Discordant Beam",             castType = "begincast", castDuration = 7,                   role = "other"    },
        [1265689] = { name = "Grim Chorus",                 castType = "begincast", castDuration = 5.5,                 role = "other"    },
        -- Symphony of the Eternal Night is the intermission/phase-transition (EXBoss voice = "转阶段");
        -- DANCE displayText (aliased to INTERMISSION color), role = "other" for everyone-visibility.
        [1266003] = { name = "Symphony of the Eternal Night", castType = "begincast", castDuration = 10,                role = "other",                  displayText = "DANCE" },
        [1266001] = { name = "Backlash",                    castType = "cast",                                          role = "mechanic" },
    },
}

-- ╔══════════════════════════════════════════════════════════╗
-- ║  Skyreach                                                ║
-- ╚══════════════════════════════════════════════════════════╝

KE.EncounterData[1698] = {
    name = "Ranjit",
    dungeon = "Skyreach",
    spells = {
        [1252690] = { name = "Gale Surge",     castType = "begincast", castDuration = 3,                       role = "other",    displayText = "DROPS"   },
        [153757]  = { name = "Fan of Blades",  castType = "begincast", castDuration = 2,                       role = "mechanic", displayText = "AOE"     },
        [1258152] = { name = "Wind Chakram",   castType = "begincast", castDuration = 3,                       role = "other",    displayText = "FRONTAL" },
        [156793]  = { name = "Chakram Vortex", castType = "begincast", castDuration = 3,                       role = "mechanic", displayText = "DODGE"   },
    },
}

KE.EncounterData[1699] = {
    name = "Araknath",
    dungeon = "Skyreach",
    spells = {
        [154110] = { name = "Fiery Smash", castType = "begincast", castDuration = 3,                   role = "tank",     display = "bar", displayText = "TANK HIT" },
        -- Energize cast finishes ~7s before the soakable line actually spawns; extend the bar
        -- so it hits zero at line-spawn moment (the actionable cue), not at cast-end.
        [154162] = { name = "Energize",    castType = "cast",      castDuration = 7,                   role = "mechanic",                  displayText = "SOAK"     },
        [154135] = { name = "Supernova",   castType = "begincast", castDuration = 4,                   role = "other",                     displayText = "AOE"      },
    },
}

KE.EncounterData[1700] = {
    name = "Rukhran",
    dungeon = "Skyreach",
    spells = {
        [1253519] = { name = "Burning Claws",   castType = "begincast", castDuration = 3,                       role = "tank",     display = "bar", displayText = "TANK HIT" },
        [1253510] = { name = "Sunbreak",        castType = "begincast", castDuration = 3,                       role = "mechanic",                  displayText = "ADD"      },
        [159382]  = { name = "Searing Quills",  castType = "begincast", castDuration = 5,   channelDuration = 3, role = "mechanic",                  displayText = "HIDE"     },
    },
}

KE.EncounterData[1701] = {
    name = "High Sage Viryx",
    dungeon = "Skyreach",
    spells = {
        [1253538] = { name = "Scorching Ray",  castType = "cast",                                              role = "heal",                     displayText = "AOE"  },
        -- Solar Blast is a spammable interrupt — every ~12s on cooldown, more
        -- noise than signal for non-interrupters. Curated as disabled by default;
        -- user can flip the Enable toggle in GUI to opt in.
        [154396]  = { name = "Solar Blast",    castType = "begincast", castDuration = 3,                       role = "other",    disabled = true, displayText = "KICK" },
        [153954]  = { name = "Cast Down",      castType = "cast",                                              role = "mechanic",                  displayText = "ADD"  },
        [1253840] = { name = "Lens Flare",     castType = "begincast", castDuration = 3,                       role = "mechanic",                  displayText = "FEET" },
    },
}

-- ╔══════════════════════════════════════════════════════════╗
-- ║  Windrunner Spire                                        ║
-- ╚══════════════════════════════════════════════════════════╝

KE.EncounterData[3056] = {
    name = "Emberdawn",
    dungeon = "WindrunnerSpire",
    spells = {
        [466556] = { name = "Flaming Updraft", castType = "begincast", castDuration = 1.5,                       role = "heal",                   displayText = "DROPS" },
        [466064] = { name = "Searing Beak",    castType = "begincast", castDuration = 3,                         role = "tank",  display = "bar", displayText = "TANK HIT" },
        [465904] = { name = "Burning Gale",    castType = "begincast", castDuration = 3,   channelDuration = 18, role = "other",                  displayText = "DANCE" },
    },
}

KE.EncounterData[3057] = {
    name = "Derelict Duo",
    dungeon = "WindrunnerSpire",
    spells = {
        [472745] = { name = "Splattering Spew",    castType = "begincast", castDuration = 4,                      role = "other",                  displayText = "SPREAD"  },
        [472888] = { name = "Bone Hack",           castType = "begincast", castDuration = 2,  channelDuration = 3, role = "tank",  display = "bar", displayText = "TANK HIT" },
        [474105] = { name = "Curse of Darkness",   castType = "begincast", castDuration = 4,                      role = "heal",                   displayText = "ADDS"    },
        -- 472736 Debilitating Shriek's actual mechanic is the follow-on Heaving Yank (472793, 7s
        -- cast on the 2nd boss). BigWigs only fires Timer for Shriek, so we extend the bar by 7s
        -- so it hits 0 at the moment the hook actually pulls — the "now!" we want users to react
        -- to. role flipped to "other" so all 3 role filters see it. EXBoss's sentinel
        -- channelDuration=604800 deliberately omitted.
        [472736] = { name = "Debilitating Shriek", castType = "begincast", castDuration = 7,                      role = "other",                  displayText = "HOOK"    },
    },
}

KE.EncounterData[3058] = {
    name = "Commander Kroluk",
    dungeon = "WindrunnerSpire",
    spells = {
        [467620]  = { name = "Rampage",            castType = "begincast", castDuration = 2,   channelDuration = 5, role = "tank",     display = "bar", displayText = "TANK HIT" },
        -- 472081 vs EXBoss 472053 — LittleWigs ID wins (BigWigs Timer key); cast data assumed same as 472053
        [472081]  = { name = "Reckless Leap",      castType = "begincast", castDuration = 3,                        role = "heal",                     displayText = "FEET"     },
        [1253272] = { name = "Intimidating Shout", castType = "begincast", castDuration = 5,                        role = "mechanic",                 displayText = "STACK"    },
        -- 470963 vs EXBoss 1271676 — LittleWigs ID wins (BigWigs Timer key); cast data assumed same as 1271676
        [470963]  = { name = "Bladestorm",         castType = "begincast", castDuration = 3,                        role = "other",                    displayText = "DODGE"    },
    },
}

KE.EncounterData[3059] = {
    name = "Restless Heart",
    dungeon = "WindrunnerSpire",
    spells = {
        [472556]  = { name = "Arrow Rain",         castType = "channel",                          channelDuration = 2.5, role = "other",    extendByChannel = true, displayText = "FEET"     },
        [472662]  = { name = "Tempest Slash",      castType = "begincast", castDuration = 2.5,                           role = "tank",     display = "bar",        displayText = "TANK HIT" },
        [1253986] = { name = "Gust Shot",          castType = "cast",                                                    role = "mechanic",                         displayText = "CLEARS"   },
        [468429]  = { name = "Bullseye Windblast", castType = "begincast", castDuration = 7,                             role = "mechanic",                         displayText = "LEAP"     },
        [474528]  = { name = "Bolt Gale",          castType = "begincast", castDuration = 4,      channelDuration = 5,   role = "mechanic",                         displayText = "FRONTAL"  },
    },
}
