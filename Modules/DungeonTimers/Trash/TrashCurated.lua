-- ╔══════════════════════════════════════════════════════════╗
-- ║  TrashCurated.lua                                        ║
-- ║  HAND-MAINTAINED curation overlay for the Dungeon Trash  ║
-- ║  Tracker. NOT auto-generated — this file is SAFE to edit ║
-- ║  by hand and survives re-runs of                         ║
-- ║  dev/scripts/extract-trash-data.lua (which owns the      ║
-- ║  auto-generated TrashData.lua and would clobber any hand ║
-- ║  edits there).                                           ║
-- ║                                                          ║
-- ║  Layers KE's own shipped defaults OVER the extracted     ║
-- ║  KE.TrashData, per spell:                                ║
-- ║    • label   — the alert text. A DISPLAY_PRESETS name    ║
-- ║                (SOAK, DODGE, FRONTAL, STACK, SPREAD,     ║
-- ║                PULL, DANCE, AOE, ADD, …) drives the      ║
-- ║                alert COLOUR automatically, just like a   ║
-- ║                boss timer; any other text renders        ║
-- ║                verbatim in the flat default colour.      ║
-- ║    • display — "bar" or "text". Omit to inherit the      ║
-- ║                shipped default (currently "text").       ║
-- ║                                                          ║
-- ║  Resolution order (renderer + GUI both honour it):       ║
-- ║    user GUI override → THIS overlay → shipped default.   ║
-- ║  A user's own per-spell choices always win over this.    ║
-- ║                                                          ║
-- ║  Shape (flat, hand-editable — keyed mapID → npcID →      ║
-- ║  spellID, matching the override key):                    ║
-- ║    KE.TrashCurated[mapID] = {                            ║
-- ║        [npcID] = {                                       ║
-- ║          [spellID] = { label = "SOAK", display = "bar" },║
-- ║        },                                                ║
-- ║    }                                                     ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

-- A per-spell entry may also carry `roles = { tank=, healer=, dps= }` to ship a
-- role restriction (e.g. healer-only); omit it to inherit the upstream/all-roles
-- default. A user's Visibility-tab role toggles still win over this.
--
-- `colorKey = "<PRESET>"` pins the alert colour to a preset independent of the
-- label, so a spell can keep its real name yet borrow a preset's colour (e.g. an
-- interrupt kept as "Fire Spit" but coloured KICK red). An explicit user colour
-- override still wins.
--
-- `castSound = "<LSM sound name>"` ships a default for the ability's Cast
-- Start sound slot — it plays the moment the mob's real cast bar is observed,
-- the same curated-voice model the boss timers use on their On Show slot.
-- The user's own Cast Start pick still wins, and selecting "None" in the GUI
-- mutes the default. Names must match a registered LSM sound (Core/Globals.lua
-- registers KE's voice pack; the .ogg filename is the name).
KE.TrashCurated = {
    -- ── Pit of Saron (658) ──────────────────────────────────────────────────
    [658] = {
        [252563] = {  -- Dreadpulse Lich
            [1258820] = { label = "SUCC",     display = "bar"  },                          -- Torrent of Misery (→ AOE yellow; no cast sound)
        },
        [252564] = {  -- Glacieth
            [1259188] = { label = "SPREAD",   display = "text", castSound = "Spread" },    -- Cryoburst (→ orange)
            [1259226] = { label = "SHIELD",   display = "text" },                          -- Focused Guard (→ VULN green; no cast sound)
        },
        [252606] = {  -- Plungetalon Gargoyle
            [1258997] = { label = "Add Grip", display = "bar"  },                          -- Plungegrip (→ ADD pink; no cast sound)
        },
        [252610] = {  -- Ymirjar Graveblade
            [1258439] = { label = "TANK HIT", display = "bar"  },                          -- Frostbane Slash (→ red; no cast sound)
            [1278963] = { label = "FEET",     display = "text", castSound = "Feet" },      -- Dark Rupture (→ orange)
        },
        [257190] = {  -- Iceborn Proto-Drake
            [1278986] = { label = "FRONTAL",  display = "text", castSound = "Frontal" },   -- Frost Breath (→ red)
        },
    },

    -- ── Skyreach (1209) ─────────────────────────────────────────────────────
    [1209] = {
        [76087] = {  -- Solar Construct
            [1253446] = { label = "SUCC",      display = "bar"  },                        -- Solar Flame (→ AOE yellow; no cast sound)
            [1253448] = { label = "FEET",      display = "text", castSound = "Move" },    -- Solar Nova (→ orange)
        },
        [76149] = {  -- Dread Raven
            [1254566] = { label = "AOE",       display = "text", castSound = "AoE" },     -- Dire Screech (→ yellow)
            [1258174] = { label = "BIG HIT",   display = "bar"  },                        -- Dread Wind (→ TANK red; no cast sound)
        },
        [76154] = {  -- Suntalon Tamer
            [1254686] = { label = "Fixates",   display = "bar"  },                        -- Mark of Death (→ FRONTAL red; no cast sound)
        },
        [78933] = {  -- Solar Elemental
            [1254355] = { label = "Orb Spawn", display = "bar",  castSound = "Add" },     -- Solar Orb (→ ADD pink)
            [1258217] = { label = "FEET",      display = "text", castSound = "Feet" },    -- Solar Fire (→ orange)
        },
        [79303] = {  -- Adorned Bladetalon
            [1254380] = { label = "TANK HIT",  display = "bar"  },                        -- Shear (→ red; no cast sound)
            [1254460] = { label = "AOE",       display = "bar",  castSound = "AoE" },     -- Blade Rush (→ yellow)
        },
    },

    -- ── Seat of the Triumvirate (1753) ──────────────────────────────────────
    [1753] = {
        [122421] = {  -- Umbral War-Adept
            [1280326] = { label = "TANK HIT",    display = "bar"  },                          -- Void Bash (→ red; no cast sound)
        },
        [122423] = {  -- Grand Shadow-Weaver
            [1262508] = { label = "SUCC",        display = "text" },                          -- Void Infusion (→ AOE yellow; no cast sound)
            [1264286] = { label = "DODGE",       display = "text", castSound = "Move" },      -- Gate of the Abyss (→ orange)
        },
        [122571] = {  -- Rift Warden
            [1264499] = { label = "AOE",         display = "bar",  castSound = "AoE" },       -- Rift Tear (→ yellow)
            [1280330] = { label = "DISPEL",      display = "text",     -- Rift Essence (→ CLEAR white)
                          castSound = "Dispell",
                          roles = { tank = false, healer = true, dps = false } },  -- healer only
        },
        [124171] = {  -- Merciless Subjugator
            [1262506] = { label = "Heal Absorb", display = "bar"  },                          -- Leeching Void (→ CLEAR white; no cast sound)
            [1262509] = { label = "CHAINS",      display = "text" },                          -- Chains of Subjugation (→ AOE yellow; no cast sound)
        },
        [252756] = {  -- Void-Infused Destroyer
            [1262335] = { label = "FRONTAL",     display = "text", castSound = "Frontal" },   -- Void Cleave (→ red)
            [1262429] = { label = "BIG HIT",     display = "bar"  },                          -- Eruption (→ TANK red; no cast sound)
        },
    },

    -- ── Algeth'ar Academy (2526) ────────────────────────────────────────────
    [2526] = {
        [192333] = {  -- Alpha Eagle
            [377383] = { label = "FRONTAL",   display = "text", castSound = "Frontal" },  -- Gust (→ red)
            [377389] = { label = "AOE",       display = "text", castSound = "AoE" },      -- Raging Screech (→ yellow)
        },
        [192680] = {  -- Guardian Sentry
            [377912] = { label = "HIDE",      display = "text", castSound = "Hide" },     -- Expel Intruders (→ cyan)
            [377991] = { label = "TANK HIT",  display = "bar"  },                         -- Storm Slash (→ red; no cast sound)
            [378003] = { label = "FEET",      display = "bar",  castSound = "Feet" },     -- Deadly Winds (→ orange)
        },
        [196200] = {  -- Algeth'ar Echoknight
            [1270356] = { label = "AOE",      display = "bar",  castSound = "AoE" },      -- Arcane Smash (→ yellow)
        },
        [196671] = {  -- Vicious Ravager
            [388942] = { label = "BAIT",      display = "text" },                         -- Vicious Ambush (→ PULL cyan; no cast sound)
            [388976] = { label = "FRONTAL",   display = "text", castSound = "Frontal" },  -- Riftbreath (→ red)
        },
        [197219] = {  -- Vile Lasher
            [1282244] = { label = "TANK HIT", display = "bar"  },                         -- Vile Bite (→ red; no cast sound)
        },
    },

    -- ── Windrunner Spire (2805) ─────────────────────────────────────────────
    [2805] = {
        [232056] = {  -- Territorial Dragonhawk
            [1216848] = { display = "text", colorKey = "KICK", castSound = "Interrupt" },  -- Fire Spit (interrupt — keeps name, → KICK red)
        },
        [232063] = {  -- Apex Lynx
            [1216985] = { label = "TANK HIT", display = "bar"  },                          -- Puncturing Bite (→ red; no cast sound)
            [1217010] = { label = "LEAPS",    display = "text", castSound = "Spread" },    -- Ferocious Pounce (→ LEAP/PULL cyan)
        },
        [232113] = {  -- Spellguard Magus
            [1216250] = { label = "AOE",      display = "bar"  },                          -- Arcane Salvo (→ yellow; no cast sound)
        },
        [232122] = {  -- Phalanx Breaker
            [471643] = { label = "AOE",       display = "text", castSound = "Stop Casting" },  -- Interrupting Screech (→ yellow)
            [471648] = { label = "DODGE",     display = "text", castSound = "Dodge" },     -- Break Ranks (→ orange)
        },
        [232146] = {  -- Phantasmal Mystic
            [1270618] = { label = "AOE",      display = "text", castSound = "AoE" },       -- Flame Nova (→ yellow)
        },
        [232175] = {  -- Devoted Woebringer
            [473672] = { label = "AOE",       display = "bar",  castSound = "AoE" },       -- Pulsing Shriek (→ yellow)
        },
        [232176] = {  -- Flesh Behemoth
            [473776] = { label = "AOE",       display = "bar",  castSound = "AoE" },       -- Fetid Spew (→ yellow)
            [1277799] = { label = "TANK HIT", display = "bar"  },                          -- Brutal Chop (→ red; no cast sound)
        },
        [236894] = {  -- Bloated Lasher
            [1216963] = { label = "AOE",      display = "bar",  castSound = "AoE" },       -- Spore Dispersal (→ yellow)
        },
    },

    -- ── Magisters' Terrace (2811) ───────────────────────────────────────────
    [2811] = {
        [234062] = {  -- Arcane Sentry
            [473258]  = { label = "AOE",      display = "text", castSound = "AoE" },      -- Crowd Dispersal (→ yellow)
            [1282050] = { label = "SUCC",     display = "bar"  },                         -- Arcane Beam (→ AOE yellow; no cast sound)
            [1282055] = { label = "DISPEL",   display = "text",     -- Ethereal Shackles (→ CLEAR white)
                          castSound = "Dispell",
                          roles = { tank = false, healer = true, dps = false } },  -- healer only
        },
        [234066] = {  -- Devouring Tyrant
            [1264687] = { label = "TANK HIT", display = "bar"  },                         -- Devouring Strike (→ red; no cast sound)
        },
        [234068] = {  -- Shadowrift Voidcaller
            [1255462] = { label = "ADDS",     display = "bar",  castSound = "Adds" },     -- Call of the Void (→ ADD pink)
            [1265977] = { label = "AOE",      display = "text", castSound = "AoE" },      -- Consuming Shadows (→ yellow)
        },
        [240973] = {  -- Runed Spellbreaker
            [1244907] = { label = "BIG HIT",  display = "bar"  },                         -- Runic Glaive (→ TANK red; no cast sound)
            [1283901] = { label = "FEET",     display = "text", castSound = "Feet" },     -- Shield Slam (→ orange)
        },
        [251861] = {  -- Blazing Pyromancer
            [1254301] = { label = "FEET",     display = "text", castSound = "Feet" },     -- Flamestrike (→ orange)
            [1254336] = { label = "AOE",      display = "text", castSound = "AoE" },      -- Ignition (→ yellow)
        },
    },

    -- ── Maisara Caverns (2874) ──────────────────────────────────────────────
    [2874] = {
        [248678] = {  -- Hulking Juggernaut
            [1256047] = { label = "AOE",      display = "text", castSound = "Stop Casting" },  -- Deafening Roar (→ yellow)
            [1256059] = { label = "TANK HIT", display = "bar"  },                              -- Rending Gore (→ red; no cast sound)
        },
        [248686] = {  -- Dread Souleater
            [1257155] = { label = "FEET",     display = "text", castSound = "Feet" },          -- Rain of Toads (→ orange)
        },
        [249020] = {  -- Hexbound Eagle
            [1257781] = { label = "DODGE",    display = "bar",  castSound = "Move" },          -- Shredding Talons (→ orange)
        },
        [249024] = {  -- Hollow Soulrender
            [1259677] = { label = "DODGE",    display = "bar"  },                              -- Rend Souls (→ orange; no cast sound)
            [1271623] = { label = "DISPEL",   display = "text",     -- Frost Nova (→ CLEAR white)
                          castSound = "Dispell",
                          roles = { tank = false, healer = true, dps = false } },  -- healer only
        },
        [249025] = {  -- Bound Defender
            [1257546] = { label = "SHIELD",   display = "bar"  },                              -- Vigilant Defense (→ VULN green; no cast sound)
            [1259651] = { label = "DODGE",    display = "bar"  },                              -- Soulstorms (→ orange; no cast sound)
        },
        [249030] = {  -- Restless Gnarldin
            [1257895] = { label = "DODGE",    display = "bar",  castSound = "Move" },          -- Ancestral Crush (→ orange)
            [1259631] = { label = "TANK HIT", display = "bar"  },                              -- Staggering Blow (→ red; no cast sound)
        },
        [253302] = {  -- Hex Guardian
            [1258475] = { label = "FRONTAL",  display = "text", castSound = "Frontal" },       -- Magma Surge (→ red)
            [1258806] = { label = "DISPEL",   display = "text",     -- Ritual Firebrand (→ CLEAR white)
                          castSound = "Dispell",
                          roles = { tank = false, healer = true, dps = false } },  -- healer only
        },
        [253683] = {  -- Rokh'zal
            [1259786] = { display = "bar" },                       -- Ritual Sacrifice (keep name, default colour; no cast sound)
            [1262241] = { label = "BAIT",     display = "text" },  -- Invoke Shadow (→ PULL cyan; no cast sound)
        },
    },

    -- ── Nexus-Point Xenas (2915) ────────────────────────────────────────────
    -- Circuit Seer's Energy Overflow (1262720) is intentionally uncurated: the
    -- upstream data carries no first-cast/cd, so the tracker can never schedule
    -- a predicted countdown for it — no overlay entry needed to "skip" it.
    [2915] = {
        [241642] = {  -- Lingering Image
            [1257701] = { label = "TANK HIT", display = "bar"  },                            -- Searing Rend (→ red; no cast sound)
            [1264354] = { label = "FRONTAL",  display = "text", castSound = "Frontal" },     -- Luciferin Flare (→ red)
            [1281657] = { label = "BIG HIT",  display = "bar"  },                            -- Blistering Smite (→ TANK red; no cast sound)
        },
        [241660] = {  -- Duskfright Herald
            [1252062] = { label = "SUCC",     display = "bar"  },                            -- Entropic Leech (→ AOE yellow; no cast sound)
            [1252076] = { label = "DODGE",    display = "text", castSound = "Move" },        -- Dark Beckoning (→ orange)
        },
        [248373] = {  -- Circuit Seer
            [1249801] = { label = "AOE",      display = "text", castSound = "AoE" },         -- Arcing Mana (→ yellow)
            -- 1262720 Energy Overflow: skipped (no first/cd → never scheduled).
        },
        [248502] = {  -- Null Sentinel
            [1252406] = { label = "AOE",      display = "text", castSound = "AoE" },         -- Dreadbellow (→ yellow)
            [1252417] = { label = "TANK HIT", display = "bar"  },                            -- Nullwark Blast (→ red; no cast sound)
        },
        [248506] = {  -- Dreadflail
            [1252436] = { label = "FRONTAL",  display = "text", castSound = "Frontal" },     -- Void Lash (→ red)
            [1252622] = { label = "DODGE",    display = "text" },                            -- Flailstorm (→ orange; no cast sound)
        },
    },
}

-- Forced cast SEQUENCES (ported from the upstream Windrunner Spire trash
-- overlay): a mob whose casts are fingerprint-identical on every sampled axis
-- but follow a FIXED order is named by POSITION — consulted before any
-- duration/schedule inference (DungeonTrash's creditFinishedCast). Keyed
-- npcID → array of spellIDs, one entry per observed cast start; casts beyond
-- the array fall back to normal inference. Phalanx Breaker's two 5s casts
-- (Break Ranks 471648 / Interrupting Screech 471643) are the shipped case.
KE.TrashForcedCastSequences = {
    [232122] = { 471648, 471643, 471648, 471648, 471643 },
}
