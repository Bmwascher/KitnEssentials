-- ╔══════════════════════════════════════════════════════════╗
-- ║  Interrupts.lua                                          ║
-- ║  Purpose: Single source of truth for spec interrupt data ║
-- ║           (primary kick for CD bars + announce spell     ║
-- ║           sets for interrupt text notifications).        ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- Data shape per spec:
--   primary        - { id, cd } for the spec's tracked kick (CD bar). Nil for
--                    specs that have no tracked interrupt (e.g. Balance Druid).
--   announceExtras - optional array of additional spell IDs that should count
--                    as interrupts for announce purposes but not CD tracking
--                    (e.g. Prot Pal Avenger's Shield, Warlock pet variants).
--
-- Accessors:
--   KE:GetInterruptForSpec(specID)  -> { id, cd } or nil  (for castbars)
--   KE:GetInterruptSpellSet(specID) -> { [id]=true, ... } or nil  (for CombatTexts)

---@class KE
local KE = select(2, ...)

local ipairs = ipairs
local pairs = pairs

local INTERRUPTS = {
    -- Warrior: Pummel 15s (+ Prot Disrupting Shout for announce)
    [71]   = { primary = { id = 6552,  cd = 15 } },
    [72]   = { primary = { id = 6552,  cd = 15 } },
    [73]   = { primary = { id = 6552,  cd = 15 }, announceExtras = { 386071 } },
    -- Paladin: Rebuke 15s (Prot/Ret). Prot also announces Divine Toll + Avenger's Shield.
    [66]   = { primary = { id = 96231, cd = 15 }, announceExtras = { 375576, 31935 } },
    [70]   = { primary = { id = 96231, cd = 15 } },
    -- Hunter: Counter Shot 24s (BM/MM), Muzzle 15s (SV)
    [253]  = { primary = { id = 147362, cd = 24 } },
    [254]  = { primary = { id = 147362, cd = 24 } },
    [255]  = { primary = { id = 187707, cd = 15 } },
    -- Rogue: Kick 15s
    [259]  = { primary = { id = 1766, cd = 15 } },
    [260]  = { primary = { id = 1766, cd = 15 } },
    [261]  = { primary = { id = 1766, cd = 15 } },
    -- Priest: Silence 30s (Shadow only)
    [258]  = { primary = { id = 15487, cd = 30 } },
    -- Death Knight: Mind Freeze 12s
    [250]  = { primary = { id = 47528, cd = 12 } },
    [251]  = { primary = { id = 47528, cd = 12 } },
    [252]  = { primary = { id = 47528, cd = 12 } },
    -- Shaman: Wind Shear 12s (Ele/Enh), 30s (Resto)
    [262]  = { primary = { id = 57994, cd = 12 } },
    [263]  = { primary = { id = 57994, cd = 12 } },
    [264]  = { primary = { id = 57994, cd = 30 } },
    -- Mage: Counterspell 20s
    [62]   = { primary = { id = 2139, cd = 20 } },
    [63]   = { primary = { id = 2139, cd = 20 } },
    [64]   = { primary = { id = 2139, cd = 20 } },
    -- Warlock: Spell Lock 24s (Aff/Destro), 30s (Demo). Pet variants announce only.
    [265]  = { primary = { id = 19647, cd = 24 }, announceExtras = { 119910, 132409 } },
    [266]  = { primary = { id = 19647, cd = 30 }, announceExtras = { 119910, 119914 } },
    [267]  = { primary = { id = 19647, cd = 24 }, announceExtras = { 119910, 132409 } },
    -- Monk: Spear Hand Strike 15s (Brew/WW only)
    [268]  = { primary = { id = 116705, cd = 15 } },
    [269]  = { primary = { id = 116705, cd = 15 } },
    -- Druid: Skull Bash 15s (Feral/Guardian). Balance announces Solar Beam only.
    [102]  = { primary = nil, announceExtras = { 78675 } },
    [103]  = { primary = { id = 106839, cd = 15 } },
    [104]  = { primary = { id = 106839, cd = 15 } },
    -- Demon Hunter: Disrupt 15s
    [577]  = { primary = { id = 183752, cd = 15 } },
    [581]  = { primary = { id = 183752, cd = 15 } },
    [1480] = { primary = { id = 183752, cd = 15 } },
    -- Evoker: Quell 20s (Dev) / 18s (Aug)
    [1467] = { primary = { id = 351338, cd = 20 } },
    [1473] = { primary = { id = 351338, cd = 18 } },
}

-- Precompute announce set per spec (primary.id + announceExtras) at file load time.
for _, entry in pairs(INTERRUPTS) do
    local set = {}
    if entry.primary and entry.primary.id then
        set[entry.primary.id] = true
    end
    if entry.announceExtras then
        for _, id in ipairs(entry.announceExtras) do
            set[id] = true
        end
    end
    entry.announceSet = set
end

---------------------------------------------------------------------------------
-- Accessors
---------------------------------------------------------------------------------

-- Returns { id = spellID, cd = seconds } for the spec's tracked kick, or nil.
function KE:GetInterruptForSpec(specID)
    local d = INTERRUPTS[specID]
    if not d then return nil end
    return d.primary
end

-- Returns { [spellID] = true, ... } — union of primary and announce extras. Nil if spec unknown.
function KE:GetInterruptSpellSet(specID)
    local d = INTERRUPTS[specID]
    if not d then return nil end
    return d.announceSet
end
