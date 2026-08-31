-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/Combat/AuraEngine/Rules.lua                     ║
-- ║  Purpose: pure decision logic for the aura engine.       ║
-- ║  No WoW API, no frames -- so it is testable headlessly.  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local table_concat = table.concat
local table_insert = table.insert
local table_sort = table.sort

local Rules = {}
KE.AuraRules = Rules

-- Ordered so the emitted string does not depend on table iteration order.
-- INCLUDE_NAME_PLATE_ONLY is deliberately absent: it is handled separately
-- below because it does not follow the negation rule.
local NEGATABLE_FILTERS = {
    "RAID",
    "CROWD_CONTROL",
    "IMPORTANT",
    "RAID_PLAYER_DISPELLABLE",
}

-- Each enabled checkbox means "remove auras matching this", so an enabled
-- filter becomes a NEGATED token.
--
-- INCLUDE_NAME_PLATE_ONLY inverts, and cannot be negated at all: the game
-- documents negation on it as ignored, and IsValidFilterString accepts the
-- negated form without complaint. Its absence already excludes nameplate-only
-- auras, so "hide them" is the token's absence and "show them" is its
-- positive presence. Getting this backwards fails silently.
function Rules.BuildDebuffFilter(filters)
    filters = filters or {}

    local parts = { "HARMFUL" }

    for i = 1, #NEGATABLE_FILTERS do
        local key = NEGATABLE_FILTERS[i]
        if filters[key] then
            table_insert(parts, "!" .. key)
        end
    end

    if not filters.INCLUDE_NAME_PLATE_ONLY then
        table_insert(parts, "INCLUDE_NAME_PLATE_ONLY")
    end

    return table_concat(parts, "|")
end

local math_ceil = math.ceil
local math_floor = math.floor

-- Applied unconditionally to every group, regardless of the user's own
-- blocklist. These are the never-secret nuisance auras the reference filters;
-- spell-ID filtering only works at all for never-secret spells, which is why
-- the list cannot be opened up to arbitrary boss debuffs.
Rules.HARDCODED_BLOCKLIST = {
    57723,   -- Exhaustion
    390435,  -- Exhaustion
    57724,   -- Sated
    264689,  -- Fatigued
    160455,  -- Fatigued
    95809,   -- Insanity
    80354,   -- Time Warp
    26013,   -- Deserter
    71041,   -- Dungeon Deserter
    206151,  -- Challenger's Burden
    1313593, -- Deserter
    124255,  -- Stagger
}

-- Saved blocklist entries are RECORDS with an enabled flag, not a boolean
-- set, so a disabled row must not filter. The hardcoded entries are added after
-- the user's rows and therefore override a disabled row for the same id --
-- the GUI shows those rows as always-on for exactly this reason.
--
-- MERGE OR ALIAS, and never an unconditional fresh table: the constants merge
-- INTO the user's set when the user has entries, and the shared constant set is
-- returned BY REFERENCE when
-- they have none. Nothing may then mutate the returned table. A defensive
-- copy here would violate the merge-or-alias rule above: it makes the
-- no-entries case an unconditional fresh table.
Rules.HARDCODED_BLOCKLIST_SET = {}
for i = 1, #Rules.HARDCODED_BLOCKLIST do
    Rules.HARDCODED_BLOCKLIST_SET[Rules.HARDCODED_BLOCKLIST[i]] = true
end

function Rules.BuildExcludeSpellIDs(saved)
    local set

    if saved then
        for spellID, record in pairs(saved) do
            if type(record) == "table" and record.enabled ~= false then
                set = set or {}
                set[spellID] = true
            end
        end
    end

    if not set then
        return Rules.HARDCODED_BLOCKLIST_SET
    end

    for i = 1, #Rules.HARDCODED_BLOCKLIST do
        set[Rules.HARDCODED_BLOCKLIST[i]] = true
    end

    return set
end

local function IsPositiveInteger(value)
    return type(value) == "number" and value > 0 and value == math_floor(value)
end

-- Saved allowlist entries are RECORDS with an enabled flag, matching the
-- blocklist's shape, so a disabled row must not admit its spell.
--
-- ALWAYS A TABLE, never nil. A nil includeSpellIDs means "no whitelist", and a
-- group filtering plain HELPFUL with no whitelist shows every buff on the
-- player. That failure is silent and reads as a flood rather than an error.
--
-- A FRESH table every call, unlike the exclude builder: there is no shared
-- constant set to alias here, so there is nothing to protect from mutation and
-- nothing to be gained by returning one.
function Rules.BuildIncludeSpellIDs(saved)
    local set = {}

    if saved then
        for spellID, record in pairs(saved) do
            if IsPositiveInteger(spellID)
                and type(record) == "table" and record.enabled ~= false then
                set[spellID] = true
            end
        end
    end

    return set
end

-- resolveEnabled overrides the enabled state only: label and the default flag
-- stay seed-owned, so a restore action cannot drift a shipped row's shape.
function Rules.RestoreAllowlistDefaults(saved, defaults, resolveEnabled)
    if type(saved) ~= "table" or type(defaults) ~= "table" then return false end

    for spellID, seed in pairs(defaults) do
        if IsPositiveInteger(spellID) and type(seed) == "table" then
            local enabled = seed.enabled ~= false
            if resolveEnabled then
                enabled = resolveEnabled(spellID, seed) and true or false
            end

            saved[spellID] = {
                label = seed.label,
                enabled = enabled,
                default = true,
            }
        end
    end

    return true
end

-- Three-valued on purpose, and the middle value is the trap. `false` drops the
-- auras you and your pet applied, absent filters nothing, and `true` would show
-- ONLY your own -- the exact opposite of what the setting reads as. So the
-- stored boolean is never passed through.
function Rules.SelfCastFilterValue(hideSelfCast)
    if hideSelfCast then return false end
    return nil
end

-- Whole seconds, 0 to 10, where 0 means no decimals. A fractional threshold on
-- a one-decimal display has no meaning, so anything else -- nil, unconvertible,
-- NaN, infinite, fractional, out of range -- resolves to 0 rather than to a
-- clamp: the safe answer is the feature switched off. Shared so the formatter,
-- the preview and the sliders cannot disagree about what a stored value means.
function Rules.NormalizeDecimalThreshold(value)
    local threshold = tonumber(value)
    if not threshold
        or threshold ~= threshold
        or threshold ~= math_floor(threshold)
        or threshold < 0
        or threshold > 10 then
        return 0
    end

    return threshold
end

-- The sound registry takes one spell id per registration, so it needs the
-- allowlist as an ordered array rather than the set the container filter
-- wants. Sorted because the array also serves as the registry's change
-- signature: an unsorted `pairs` walk would reorder after a rehash and force
-- a retire-and-rebuild that changed nothing.
function Rules.BuildSoundSpellIDs(saved)
    local ids = {}

    for spellID in pairs(Rules.BuildIncludeSpellIDs(saved)) do
        -- The Add New Entry button reserves a NEGATIVE id until the user types
        -- a real one, and it reserves it enabled. The container simply matches
        -- no aura on such an id, but the sound API is asked to register it, and
        -- one nil return there rolls the whole registry back to silence -- so
        -- pressing Add would mute every external until the id was filled in.
        if type(spellID) == "number" and spellID > 0 then
            ids[#ids + 1] = spellID
        end
    end
    table_sort(ids)

    return ids
end

-- maxFrameCount is per group and unused capacity cannot cross a group
-- boundary, so the limit is divided rather than shared. The remainder goes to
-- externals: they are the reason the module exists, and a single slot showing
-- a personal cooldown instead of an external would be the wrong one.
function Rules.SplitExternalsLimit(total, showBig)
    total = tonumber(total) or 0
    if total < 0 then total = 0 end

    if not showBig then
        return { external = total, big = 0 }
    end

    return {
        external = math_ceil(total / 2),
        big      = math_floor(total / 2),
    }
end

-- One timing rule for every display. Both halves come from the same source
-- so the phase and the duration cannot drift apart.
function Rules.PreviewTiming(index)
    local duration = 10 + ((index * 5) % 30)
    local offset   = duration * (0.2 + (index % 5) * 0.1)
    return duration, offset
end

-- The mixed preview is BLOCKED, not alternating, and reserves capacity the
-- same way the live display does. A preview that filled every slot with
-- externals would show a fuller display than the user actually gets.
function Rules.BuildExternalsPreview(icons, iconsBig, total, showBig)
    local split   = Rules.SplitExternalsLimit(total, showBig)
    local entries = {}

    -- Each source cycles from ITS OWN start. Indexing by the running entry
    -- total would make the big block begin at whatever offset the external
    -- quota happened to leave, so the same settings would show different big
    -- icons depending on how many externals fit.
    local function append(source, count, groupKey)
        if not source or #source == 0 then return end
        for i = 1, count do
            local icon = source[((i - 1) % #source) + 1]
            table_insert(entries, {
                icon     = icon,
                groupKey = groupKey,
                count    = (i % 4 == 1 and 2) or (i % 4 == 2 and 5) or 0,
            })
        end
    end

    append(icons,    split.external, "external")
    append(iconsBig, split.big,      "big")

    return entries
end

-- Two inputs and no more. There are no "load conditions" here -- that is
-- the reference's concept for its user-created displays, and neither KE module
-- has any such setting.
--
-- vehicleDisabled is a stored flag the event handlers maintain, NOT a live
-- query: the API that answers it is unreliable at the moment the entry event
-- fires.
--
-- TWO outputs from the same inputs, and the asymmetry between them IS the
-- rule. The container hides in a vehicle; the sound keeps playing. Returning
-- them together is what makes that difference assertable -- two separate
-- functions could drift apart and no test would notice.
function Rules.ComputeState(enabled, vehicleDisabled)
    return {
        container = (enabled and not vehicleDisabled) and true or false,
        sound     = enabled and true or false,
    }
end

-- The display this replaces named a growth direction with two tokens: the
-- axis that fills first, then where new lines go. The engine splits that into
-- a direction per axis plus which axis fills first, so every one of the eight
-- values converts exactly and nothing is approximated.
--
-- The fallback matches the shipped default rather than the engine's, so a
-- profile carrying a value this table does not know still comes up looking
-- like the display it replaced.
local GROWTH_CONVERSION = {
    RIGHT_DOWN = { "RIGHT", "DOWN", "HORIZONTAL" },
    RIGHT_UP   = { "RIGHT", "UP",   "HORIZONTAL" },
    LEFT_DOWN  = { "LEFT",  "DOWN", "HORIZONTAL" },
    LEFT_UP    = { "LEFT",  "UP",   "HORIZONTAL" },
    DOWN_RIGHT = { "RIGHT", "DOWN", "VERTICAL" },
    DOWN_LEFT  = { "LEFT",  "DOWN", "VERTICAL" },
    UP_RIGHT   = { "RIGHT", "UP",   "VERTICAL" },
    UP_LEFT    = { "LEFT",  "UP",   "VERTICAL" },
}

function Rules.ConvertGrowthDirection(value)
    local out = GROWTH_CONVERSION[value] or GROWTH_CONVERSION.LEFT_DOWN
    return out[1], out[2], out[3]
end

-- Decides whether an allowlist row may be re-keyed onto another spell ID.
--
-- Two refusals, and neither is reachable through the Delete button, so this is
-- the only place they can live. Re-keying a shipped row would carry its
-- `default` flag onto an ID that was never shipped, and the delete guard refuses
-- exactly that flag -- the row becomes permanently undeletable. Re-keying onto an
-- occupied ID deletes whatever was there, which is a shipped-row deletion by
-- another route.
function Rules.CanRekeyAllowlistEntry(saved, fromID, toID)
    if type(saved) ~= "table" then return false end
    if type(fromID) ~= "number" or not IsPositiveInteger(toID) then return false end
    if fromID == toID then return false end

    local entry = saved[fromID]
    if type(entry) ~= "table" then return false end
    if entry.default then return false end

    return saved[toID] == nil
end
