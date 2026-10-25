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
--                    Felguard). KE:ResolvePlayerInterrupt picks the first
--                    that is known in the player or pet spellbook. A
--                    candidate may carry `forms`, the shapeshift form ids
--                    (GetShapeshiftFormID) it needs; without it any form
--                    will do.
--   announceExtras - optional array of additional spell IDs that count as
--                    interrupts for announce purposes but not CD tracking.
--   tracked        - optional candidate id a cooldown tracker shows for a
--                    teammate, whose pet it cannot see.
--   trackerKick    - optional { id, cd } a cooldown tracker shows for a spec
--                    with no candidate. It is no candidate, so castbars give
--                    the spec no kick indicator.
--
-- Accessors:
--   KE:GetInterruptCandidatesForSpec(specID) -> list of { id, cd } in priority
--                                              order, or nil.
--   KE:GetInterruptSpellSet(specID) -> { [id]=true, ... } or nil.
--   KE:GetTrackedKickForSpec(specID) -> { id, cd } or nil.
--   KE:GetInterruptKickSpellSet() -> { [id]=true, ... } of every candidate and
--                                    tracker kick.
--   KE:SelectInterruptCandidate(candidates, isKnown, formID) -> the first
--                                    candidate isKnown accepts whose forms
--                                    allow formID, or nil.
--   KE:ResolvePlayerInterrupt(specID) -> that pick for the player's spellbook
--                                        and current form, or nil.
--   KE:GetKickDefinition(kickID) -> the Kick Tracker's definition of a
--                                   canonical kick, or nil.
--   KE:GetKickTalentDemand(specID) -> { [talentID]=true, ... } the tracker
--                                     inspects for the spec's kicks.
--
-- `cd` is the value castbars use; the Kick Tracker times kicks from the
-- definitions at the end of this file.

---@class KE
local KE = select(2, ...)

local ipairs = ipairs
local pairs = pairs

local INTERRUPT_ANNOUNCE_SET = {}
local KICK_SPELL_SET = {}
local KICK_CD_CAP = {}

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
    -- Druid: Skull Bash 15s (Feral/Guardian). Balance's only kick is Solar
    -- Beam 60s, an area silence with no castbar kick indicator.
    [102]  = { trackerKick = { id = 78675, cd = 60 } },
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

-- Kicks a talent adds beside a spec's main kick. `requires` is the talent
-- that makes the spell interrupt; without it the spell is not a kick.
local JAVELINEER = 1271948
local WARRIOR_THROWS = {
    { id = 384110, cd = 45,  requires = JAVELINEER },  -- Wrecking Throw
    { id = 64382,  cd = 180, requires = JAVELINEER },  -- Shattering Throw
}
local EXTRA_KICKS_BY_SPEC = {
    [71] = WARRIOR_THROWS,
    [72] = WARRIOR_THROWS,
    [73] = WARRIOR_THROWS,
}

-- Forever rows, as printed by dev/scripts/derive-forever-kicks.lua. Ranks are
-- listed highest first, so the first known one is the rank the trained spell
-- casts; `forms` lists the shapeshift form ids a kick needs.
local FOREVER_INTERRUPTS = {
    [1482] = {  -- Mage
        candidates = {
            { id = 2139, cd = 30 },  -- Counterspell
        },
    },
    [1484] = {  -- Druid
        candidates = {
            { id = 410176, cd = 10, forms = { 1, 5, 8 } },  -- Skull Bash
            { id = 16979, cd = 15, forms = { 5, 8 } },  -- Feral Charge (Bear)
            { id = 1238122, cd = 15, forms = { 1, 5, 8 } },  -- Feral Charge
        },
        announceExtras = { 19675, 414621 },
    },
    [1486] = {  -- Paladin
        candidates = {
            { id = 425609, cd = 15 },  -- Rebuke
        },
    },
    [1487] = {  -- Priest
        candidates = {
            { id = 15487, cd = 45 },  -- Silence
        },
    },
    [1488] = {  -- Rogue
        candidates = {
            { id = 1769, cd = 10 },  -- Kick
            { id = 1768, cd = 10 },  -- Kick
            { id = 1767, cd = 10 },  -- Kick
            { id = 1766, cd = 10 },  -- Kick
        },
        tracked = 1766,
    },
    [1489] = {  -- Shaman
        candidates = {
            { id = 10414, cd = 6 },  -- Earth Shock
            { id = 10413, cd = 6 },  -- Earth Shock
            { id = 10412, cd = 6 },  -- Earth Shock
            { id = 8046, cd = 6 },  -- Earth Shock
            { id = 8045, cd = 6 },  -- Earth Shock
            { id = 8044, cd = 6 },  -- Earth Shock
            { id = 8042, cd = 6 },  -- Earth Shock
        },
        tracked = 8042,
    },
    [1490] = {  -- Warlock
        candidates = {
            { id = 19647, cd = 30 },  -- Spell Lock
            { id = 19244, cd = 30 },  -- Spell Lock
        },
        tracked = 19244,
    },
    [1491] = {  -- Warrior
        candidates = {
            { id = 6554, cd = 10, forms = { 19 } },  -- Pummel
            { id = 6552, cd = 10, forms = { 19 } },  -- Pummel
            { id = 1672, cd = 12, forms = { 17, 18 } },  -- Shield Bash
            { id = 1671, cd = 12, forms = { 17, 18 } },  -- Shield Bash
            { id = 72, cd = 12, forms = { 17, 18 } },  -- Shield Bash
        },
        tracked = 6552,
    },
}
local FOREVER_KICK_ALIASES = {
    [1671] = 72,  -- Shield Bash
    [1672] = 72,  -- Shield Bash
    [1767] = 1766,  -- Kick
    [1768] = 1766,  -- Kick
    [1769] = 1766,  -- Kick
    [6554] = 6552,  -- Pummel
    [8044] = 8042,  -- Earth Shock
    [8045] = 8042,  -- Earth Shock
    [8046] = 8042,  -- Earth Shock
    [10412] = 8042,  -- Earth Shock
    [10413] = 8042,  -- Earth Shock
    [10414] = 8042,  -- Earth Shock
    [19647] = 19244,  -- Spell Lock
}

-- Each client sees only its own rows: Forever shares spell ids with retail
-- (Earth Shock 8042 is no retail kick, Counterspell's cooldown differs) and
-- has no talent kick data.
if KE.IS_FOREVER then
    INTERRUPTS = FOREVER_INTERRUPTS
    KICK_ALIASES = FOREVER_KICK_ALIASES
    EXTRA_KICKS_BY_SPEC = {}
end
local EXTRA_KICK_BY_ID = {}
for _, list in pairs(EXTRA_KICKS_BY_SPEC) do
    for _, e in ipairs(list) do
        EXTRA_KICK_BY_ID[e.id] = e
        KICK_CD_CAP[e.id] = e.cd
    end
end

-- Precompute per-spec:
--   entry.candidateList: normalized list of { id, cd } (primary becomes 1-entry list).
--   entry.announceSet:   { [spellID] = true } union of all candidate IDs, the
--                        tracker kick and announceExtras.
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
            local canon = KICK_ALIASES[c.id] or c.id
            if (KICK_CD_CAP[canon] or 0) < c.cd then KICK_CD_CAP[canon] = c.cd end
        end
    end
    local tk = entry.trackerKick
    if tk then
        set[tk.id] = true
        INTERRUPT_ANNOUNCE_SET[tk.id] = true
        KICK_SPELL_SET[tk.id] = true
        if (KICK_CD_CAP[tk.id] or 0) < tk.cd then KICK_CD_CAP[tk.id] = tk.cd end
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

-- Returns an ordered list of { id, cd } entries to try in priority order;
-- KE:ResolvePlayerInterrupt picks the player's kick from it. Returns nil if
-- spec is unknown or has no candidate (a tracker kick is none).
function KE:GetInterruptCandidatesForSpec(specID)
    local d = INTERRUPTS[specID]
    if not d then return nil end
    local list = d.candidateList
    if not list or #list == 0 then return nil end
    return list
end

-- Returns { [spellID] = true, ... } — union of all candidate IDs, the tracker
-- kick and announce extras.
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

-- The kick a cooldown tracker shows for a spec when it cannot see the pet,
-- or the spec's tracker kick when it has no candidate.
function KE:GetTrackedKickForSpec(specID)
    local d = INTERRUPTS[specID]
    if not d then return nil end
    local list = d.candidateList
    if not list or #list == 0 then return d.trackerKick end
    return self:PickTrackedKick(list, d.tracked)
end

-- Every spell that starts a kick cooldown: candidate and tracker-kick ids,
-- never the announce extras, which are not kicks.
function KE:GetInterruptKickSpellSet()
    return KICK_SPELL_SET
end

-- Pure: the caller supplies the known check and the form. A secret form is
-- treated as unknown, so it meets no `forms` list.
function KE:SelectInterruptCandidate(candidates, isKnown, formID)
    if self:IsSecretValue(formID) then formID = nil end
    for _, c in ipairs(candidates) do
        local forms = c.forms
        local formAllowed = not forms
        if forms and formID then
            for i = 1, #forms do
                if forms[i] == formID then
                    formAllowed = true
                    break
                end
            end
        end
        if formAllowed and isKnown(c.id) then return c end
    end
    return nil
end

local function isKnownToPlayerOrPet(spellID)
    local book = C_SpellBook
    if not (book and book.IsSpellKnownOrInSpellBook) then return false end
    return book.IsSpellKnownOrInSpellBook(spellID)
        or book.IsSpellKnownOrInSpellBook(spellID, Enum.SpellBookSpellBank.Pet)
end

function KE:ResolvePlayerInterrupt(specID)
    local candidates = self:GetInterruptCandidatesForSpec(specID)
    if not candidates then return nil end
    local getForm = GetShapeshiftFormID
    local formID
    if getForm then formID = getForm() end
    return self:SelectInterruptCandidate(candidates, isKnownToPlayerOrPet, formID)
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
    local tk = d and d.trackerKick
    if tk and tk.id == kickID then return tk.cd end
    return nil
end

-- A spec's talent-added kicks as { id, cd, requires }, or nil.
function KE:GetExtraKicksForSpec(specID)
    return EXTRA_KICKS_BY_SPEC[specID]
end

-- The { id, cd, requires } entry for a talent-added kick, or nil.
function KE:GetExtraKick(spellID)
    return EXTRA_KICK_BY_ID[spellID]
end

-- The largest table cooldown of a canonical kick ID, or nil when unknown.
function KE:GetKickCooldownCap(kickID)
    return KICK_CD_CAP[kickID]
end

---------------------------------------------------------------------------------
-- Kick definitions (the Kick Tracker's durations)
---------------------------------------------------------------------------------
-- One per canonical kick ID. `base` seconds, or `specBase[specID]`;
-- `modifiers` apply while their talent's rank is positive, `seconds` off or a
-- `multiplier` (the share kept). `success` comes off once, only for a cast
-- whose interrupt is confirmed.
local QUICK_WITTED = 382297
local COLDTHIRST = 378848
local LIGHT_OF_THE_SUN = 202918
local HONED_REFLEXES = 391271
local INTERWOVEN_THREADS = 412713

local KICK_DEFINITIONS = {
    [2139]   = { base = 25, modifiers = { { talent = QUICK_WITTED, seconds = 5 } } },  -- Counterspell
    [47528]  = { base = 15, success = { talent = COLDTHIRST, seconds = 3 } },  -- Mind Freeze
    [78675]  = { base = 60, success = { talent = LIGHT_OF_THE_SUN, seconds = 15 } },  -- Solar Beam
    [6552]   = { base = 15, modifiers = { { talent = HONED_REFLEXES, multiplier = 0.9 } } },  -- Pummel
    [351338] = { base = 20, modifiers = { { talent = INTERWOVEN_THREADS, multiplier = 0.9 } } },  -- Quell
    [57994]  = { base = 12, specBase = { [264] = 30 } },  -- Wind Shear
    [147362] = { base = 24 },  -- Counter Shot
    [187707] = { base = 15 },  -- Muzzle
    [19647]  = { base = 24 },  -- Spell Lock
    [89766]  = { base = 30 },  -- Axe Toss
    [96231]  = { base = 15 },  -- Rebuke
    [1766]   = { base = 15 },  -- Kick
    [15487]  = { base = 30 },  -- Silence
    [116705] = { base = 15 },  -- Spear Hand Strike
    [106839] = { base = 15 },  -- Skull Bash
    [183752] = { base = 15 },  -- Disrupt
}
if KE.IS_FOREVER then KICK_DEFINITIONS = {} end

-- The talents a kick's definition reads, added to set (made on the first).
local function AddKickTalents(set, kickID)
    local def = KICK_DEFINITIONS[KICK_ALIASES[kickID] or kickID]
    if not def then return set end
    if def.modifiers then
        for _, m in ipairs(def.modifiers) do
            set = set or {}
            set[m.talent] = true
        end
    end
    local s = def.success
    if s then
        set = set or {}
        set[s.talent] = true
    end
    return set
end

-- Per spec, the talents of every kick it can show: each candidate (a
-- warlock's demons both) and its tracker kick.
local EMPTY_DEMAND = {}
local TALENT_DEMAND = {}
for specID, entry in pairs(INTERRUPTS) do
    local set
    for _, c in ipairs(entry.candidateList) do set = AddKickTalents(set, c.id) end
    if entry.trackerKick then set = AddKickTalents(set, entry.trackerKick.id) end
    TALENT_DEMAND[specID] = set
end

function KE:GetKickDefinition(kickID)
    return KICK_DEFINITIONS[kickID]
end

-- Callers treat the returned set as read-only.
function KE:GetKickTalentDemand(specID)
    return TALENT_DEMAND[specID] or EMPTY_DEMAND
end
