-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/ClassUtilities/ShamanProcRules.lua              ║
-- ║  Purpose: the pure rules of Shaman Proc Cooldowns.       ║
-- ║           No WoW API, no frames.                         ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local string_format = string.format
local type = type

local Rules = {}
KE.ShamanProcRules = Rules

-- Display order. `talent` is the talent's spell id; `dbKey` is its Tracked
-- Talents box.
Rules.TRACKERS = {
    { key = "NaturesGuardian", talent = 30884, name = "Nature's Guardian", dbKey = "TrackNaturesGuardian" },
    { key = "ThunderousPaws", talent = 378075, name = "Thunderous Paws", dbKey = "TrackThunderousPaws" },
}

Rules.NATURAL_HARMONY = 443442

-- Seconds after zoning in, or after the trackers turn on, in which every
-- announcement is ignored: the game re-announces cooldowns in a burst then.
Rules.ZONE_IN_IGNORE = 2

-- The hidden spells each talent casts when it fires. Their cooldown
-- announcement is the only proc signal readable in combat; Nature's Guardian
-- announces both of its ids on one proc.
local TRIGGERS = {
    [31616] = "NaturesGuardian",
    [445698] = "NaturesGuardian",
    [378076] = "ThunderousPaws",
}

-- Natural Harmony takes 15 s off Nature's Guardian, and 10 s in PvP.
local NG_BASE, NG_HARMONY, NG_HARMONY_PVP = 45, 30, 35
local PAWS_LENGTH = 20

-- An unreadable talent (nil) counts as not known.
function Rules.ActiveTrackers(class, db, isKnown)
    local out = {}
    if class ~= "SHAMAN" or type(db) ~= "table" then return out end
    for i = 1, #Rules.TRACKERS do
        local tracker = Rules.TRACKERS[i]
        if db[tracker.dbKey] == true and isKnown(tracker.talent) == true then
            out[#out + 1] = tracker.key
        end
    end
    return out
end

function Rules.IsPvPInstance(instanceType)
    return instanceType == "arena" or instanceType == "pvp"
end

-- The spec event fires for every group member. A unit flagged secret is never
-- compared and could be the player, so it counts as the player's own.
function Rules.IsOwnSpecChange(unit, unitSecret)
    if unitSecret then return true end
    return unit == "player"
end

function Rules.Length(key, hasHarmony, inPvP)
    if key == "ThunderousPaws" then return PAWS_LENGTH end
    if not hasHarmony then return NG_BASE end
    if inPvP then return NG_HARMONY_PVP end
    return NG_HARMONY
end

-- An id flagged secret is skipped without being compared; the base id is the
-- fallback.
function Rules.TrackerForPing(spellID, spellSecret, baseSpellID, baseSecret)
    if not spellSecret and spellID ~= nil then
        local key = TRIGGERS[spellID]
        if key then return key end
    end
    if not baseSecret and baseSpellID ~= nil then
        return TRIGGERS[baseSpellID]
    end
    return nil
end

-- A second announcement while the clock runs is the same proc (Nature's
-- Guardian sends two ids), so it never restarts the count.
function Rules.AcceptPing(now, ignoreUntil, startedAt, length)
    if ignoreUntil and now < ignoreUntil then return false end
    if startedAt and length and now - startedAt < length then return false end
    return true
end

function Rules.Remaining(now, startedAt, length)
    if not (startedAt and length) then return nil end
    local left = length - (now - startedAt)
    if left <= 0 then return nil end
    return left
end

function Rules.FormatTime(remaining)
    if remaining >= 1 then return string_format("%d", remaining) end
    return string_format("%.1f", remaining)
end
