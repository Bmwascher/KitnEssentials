-- ╔══════════════════════════════════════════════════════════╗
-- ║  Interrupts.lua                                          ║
-- ║  Purpose: Single source of truth for spec interrupt data ║
-- ║           (primary kick for CD bars + announce spell     ║
-- ║           sets for interrupt text notifications).        ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- Data shape per spec (one of):
--   primary        - { id, cd } for the spec's single tracked kick.
--   candidates     - ordered list of { id, cd } entries to try in priority
--                    order (for pet-dependent specs where the available kick
--                    changes with active pet, e.g. Warlock Felhunter vs
--                    Felguard). CacheInterruptId iterates and picks the first
--                    that is actually known in the player or pet spellbook.
--   announceExtras - optional array of additional spell IDs that count as
--                    interrupts for announce purposes but not CD tracking.
--   tracked        - optional candidate id a cooldown tracker shows for a
--                    teammate, whose pet it cannot see.
--
-- Accessors:
--   KE:GetInterruptCandidatesForSpec(specID) -> list of { id, cd } in priority
--                                              order, or nil.
--   KE:GetInterruptSpellSet(specID) -> { [id]=true, ... } or nil.
--   KE:GetTrackedKickForSpec(specID) -> { id, cd } or nil.
--   KE:GetInterruptKickSpellSet() -> { [id]=true, ... } of every candidate.

---@class KE
local KE = select(2, ...)

local ipairs = ipairs
local pairs = pairs

local INTERRUPT_ANNOUNCE_SET = {}
local KICK_SPELL_SET = {}

local INTERRUPTS = {
    -- Warrior: Pummel 15s
    [71]   = { primary = { id = 6552,  cd = 15 } },
    [72]   = { primary = { id = 6552,  cd = 15 } },
    [73]   = { primary = { id = 6552,  cd = 15 } },
    -- Paladin: Rebuke 15s (Prot/Ret). Prot also announces Avenger's Shield
    -- (single-target projectile interrupt that lands as a confirmed kick).
    [66]   = { primary = { id = 96231, cd = 15 }, announceExtras = { 31935, 375576 } },
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
    -- Warlock: interrupt depends on active pet. Candidates in priority order:
    --   19647 Spell Lock (Felhunter) 24s, 89766 Axe Toss (Felguard) 30s,
    --   119910 Command Demon (player-cast meta), 132409 pet variant.
    --   With any other demon out there is no kick.
    [265]  = {
        candidates = {
            { id = 19647,  cd = 24 },
            { id = 89766,  cd = 30 },
            { id = 119910, cd = 24 },
            { id = 132409, cd = 24 },
        },
    },
    [266]  = {
        candidates = {
            { id = 19647,  cd = 24 },
            { id = 89766,  cd = 30 },
            { id = 119910, cd = 24 },
            { id = 119914, cd = 30 },
        },
        tracked = 89766,  -- the Felguard is the usual Demonology demon
    },
    [267]  = {
        candidates = {
            { id = 19647,  cd = 24 },
            { id = 89766,  cd = 30 },
            { id = 119910, cd = 24 },
            { id = 132409, cd = 24 },
        },
    },
    -- Monk: Spear Hand Strike 15s (Brew/WW only)
    [268]  = { primary = { id = 116705, cd = 15 } },
    [269]  = { primary = { id = 116705, cd = 15 } },
    -- Druid: Skull Bash 15s (Feral/Guardian). Balance has no single-target
    -- interrupt; Solar Beam is their only kick and is announce-worthy.
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

-- One kick can report under more than one spell ID (a player command and the
-- pet's own spell). Each maps to the ID a cooldown tracker keys that kick on.
local KICK_ALIASES = {
    [119910] = 19647,   -- Command Demon: Spell Lock
    [132409] = 19647,   -- Spell Lock (sacrificed Felhunter)
    [119914] = 89766,   -- Command Demon: Axe Toss
}

-- Precompute per-spec:
--   entry.candidateList: normalized list of { id, cd } (primary becomes 1-entry list).
--   entry.announceSet:   { [spellID] = true } union of all candidate IDs + announceExtras.
for _, entry in pairs(INTERRUPTS) do
    local list
    if entry.candidates then
        list = entry.candidates
    elseif entry.primary then
        list = { entry.primary }
    else
        list = {}
    end
    entry.candidateList = list

    local set = {}
    for _, c in ipairs(list) do
        if c.id then
            set[c.id] = true
            INTERRUPT_ANNOUNCE_SET[c.id] = true
            KICK_SPELL_SET[c.id] = true
        end
    end
    if entry.announceExtras then
        for _, id in ipairs(entry.announceExtras) do
            set[id] = true
            INTERRUPT_ANNOUNCE_SET[id] = true
        end
    end
    entry.announceSet = set
end

---------------------------------------------------------------------------------
-- Accessors
---------------------------------------------------------------------------------

-- Returns an ordered list of { id, cd } entries to try in priority order.
-- Caller iterates and picks the first entry whose id is actually known in the
-- player's or pet's spellbook. Returns nil if spec is unknown or has no kick.
function KE:GetInterruptCandidatesForSpec(specID)
    local d = INTERRUPTS[specID]
    if not d then return nil end
    local list = d.candidateList
    if not list or #list == 0 then return nil end
    return list
end

-- Returns { [spellID] = true, ... } — union of all candidate IDs + announce extras.
-- Nil if spec unknown.
function KE:GetInterruptSpellSet(specID)
    local d = INTERRUPTS[specID]
    if not d then return nil end
    return d.announceSet
end

function KE:GetInterruptAnnounceSpellSet()
    return INTERRUPT_ANNOUNCE_SET
end

-- The candidate named by trackedID, else the first candidate.
function KE:PickTrackedKick(candidates, trackedID)
    if trackedID then
        for _, c in ipairs(candidates) do
            if c.id == trackedID then return c end
        end
    end
    return candidates[1]
end

-- The kick a cooldown tracker shows for a spec when it cannot see the pet.
function KE:GetTrackedKickForSpec(specID)
    local d = INTERRUPTS[specID]
    if not d then return nil end
    local list = d.candidateList
    if not list or #list == 0 then return nil end
    return self:PickTrackedKick(list, d.tracked)
end

-- Every spell that starts a kick cooldown: candidate ids only, never the
-- announce extras, which are not kicks.
function KE:GetInterruptKickSpellSet()
    return KICK_SPELL_SET
end

-- Talents that change a kick's cooldown outright, keyed by kick spell ID.
-- Each entry names its talent and one change: `seconds` off the cooldown, or
-- `multiplier`, the share of the cooldown kept (10% off is 0.9).
local FLAT_KICK_TALENTS = {
    [2139] = { { talent = 382297, seconds = 5 } },       -- Counterspell: Quick Witted
    [6552] = { { talent = 391271, multiplier = 0.9 } },  -- Pummel: Honed Reflexes
}

function KE:GetFlatKickTalents(kickSpellID)
    return FLAT_KICK_TALENTS[kickSpellID]
end

function KE:GetCanonicalKickSpell(spellID)
    return KICK_ALIASES[spellID] or spellID
end

-- One kick's cooldown for a spec, alias-aware; nil when the spec lacks it.
function KE:GetKickCooldownForSpec(specID, kickID)
    local d = INTERRUPTS[specID]
    local list = d and d.candidateList
    if not list then return nil end
    for _, c in ipairs(list) do
        if (KICK_ALIASES[c.id] or c.id) == kickID then return c.cd end
    end
    return nil
end
