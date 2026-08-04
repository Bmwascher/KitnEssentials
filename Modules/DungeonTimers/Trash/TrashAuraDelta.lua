-- ╔══════════════════════════════════════════════════════════╗
-- ║  TrashAuraDelta.lua                                      ║
-- ║  Party harmful-aura delta sampler for DungeonTrash.      ║
-- ║                                                          ║
-- ║  Caches each GROUP unit's (player + party1-4) HARMFUL    ║
-- ║  aura instance IDs and records every NEW application in  ║
-- ║  a short ring. The castStartAuraDelta fingerprint asks   ║
-- ║  "did a fresh debuff land on the party right at cast     ║
-- ║  start?" — the discriminator that lets Vicious Ambush's  ║
-- ║  CAST_START anchor advance at its observed start without ║
-- ║  cross-anchoring on its mob's other casts.               ║
-- ║                                                          ║
-- ║  Reads FRIENDLY-unit debuffs only, never the plate's     ║
-- ║  auras — outside the hostile-nameplate secret set.       ║
-- ║  DungeonTrash gates enablement on                        ║
-- ║  C_Secrets.ShouldAurasBeSecret() == false (the shipped   ║
-- ║  Guidance check's proven gate) and routes UNIT_AURA /    ║
-- ║  GROUP_ROSTER_UPDATE here only while its monitor runs.   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local UnitExists = UnitExists
local GetTime = GetTime
local C_UnitAuras = C_UnitAuras
local pcall = pcall
local tonumber = tonumber
local type = type
local pairs = pairs
local table_remove = table.remove
local wipe = wipe

local TAD = {}
KE.TrashAuraDelta = TAD

-- The check's DELAY/PRE/POST windows all equal DungeonTrash's
-- TARGET_SAMPLE_DELAY (0.10s), so the existing +0.10s fingerprint sampler owns
-- the scheduling — this file holds only the cache/ring machinery.
local MAX_AURAS = 40             -- per-unit scan bound
local RECENT_KEEP_SECONDS = 1.0  -- recent-application ring retention

TAD.enabled = false
TAD.seeded = false
TAD.auraCache = {}   -- [unit] = { [auraInstanceID] = true }
TAD.recentAdds = {}  -- array of { unit, id, at }, front-trimmed to the last second

-- The five units whose incoming debuffs the fingerprint watches: player +
-- party1-4. Nameplate tokens never enter here.
local function isTrackedUnit(unit)
    if unit == "player" then return true end
    return type(unit) == "string" and unit:match("^party[1-4]$") ~= nil
end
TAD.IsTrackedUnit = isTrackedUnit

local TRACKED_UNITS = { "player", "party1", "party2", "party3", "party4" }

-- One unit's current HARMFUL aura instance-ID set. Reads are pcall-guarded
-- and the ID goes through tonumber — under
-- the ShouldAurasBeSecret()==false enable gate the field is plain, and if
-- that gate is ever wrong tonumber on a secret degrades to nil (probe-
-- pinned) and the aura is simply skipped.
local function harmfulAuraIDs(unit)
    local ids = {}
    if not (UnitExists and UnitExists(unit)) then return ids end
    local fn = C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex
    if type(fn) ~= "function" then return ids end
    for index = 1, MAX_AURAS do
        local ok, aura = pcall(fn, unit, index, "HARMFUL")
        if not ok or type(aura) ~= "table" then break end
        local okID, id = pcall(function() return aura.auraInstanceID end)
        id = okID and tonumber(id) or nil
        if id then ids[id] = true end
    end
    return ids
end

local function trimRecentAdds(now)
    local keepAfter = now - RECENT_KEEP_SECONDS
    local recent = TAD.recentAdds
    for i = #recent, 1, -1 do
        if (tonumber(recent[i] and recent[i].at) or 0) < keepAfter then
            table_remove(recent, i)
        end
    end
end

-- Diff a unit's aura set against the cache; every NEW instance ID is a
-- fresh application recorded in the ring. seedOnly = baseline write with no
-- ring entries (enable / roster reseed — pre-existing debuffs are not
-- "new"). A refresh of an existing aura keeps its instance ID, so DoT
-- ticks/refreshes never enter the ring — only genuine applications.
function TAD.RefreshUnit(unit, seedOnly)
    if TAD.enabled ~= true then return end
    if not isTrackedUnit(unit) or not (UnitExists and UnitExists(unit)) then
        TAD.auraCache[unit] = nil
        return
    end
    local now = GetTime()
    local old = TAD.auraCache[unit] or {}
    local current = harmfulAuraIDs(unit)
    TAD.auraCache[unit] = current
    if seedOnly then return end
    trimRecentAdds(now)
    for id in pairs(current) do
        if not old[id] then
            TAD.recentAdds[#TAD.recentAdds + 1] = { unit = unit, id = id, at = now }
        end
    end
end

function TAD.RefreshGroup(seedOnly)
    for i = 1, #TRACKED_UNITS do
        TAD.RefreshUnit(TRACKED_UNITS[i], seedOnly == true)
    end
    if seedOnly then TAD.seeded = true end
end

function TAD.SetEnabled(enabled)
    enabled = enabled == true
    if TAD.enabled == enabled then
        if enabled and not TAD.seeded then TAD.RefreshGroup(true) end
        return
    end
    TAD.enabled = enabled
    wipe(TAD.auraCache)
    wipe(TAD.recentAdds)
    TAD.seeded = false
    if enabled then TAD.RefreshGroup(true) end
end

-- Was any fresh HARMFUL application recorded inside [startAt, endAt]?
-- Returns the ring row or nil — the fingerprint only needs existence.
function TAD.FindRecentAdd(startAt, endAt)
    if TAD.enabled ~= true then return nil end
    local startTime = tonumber(startAt)
    local endTime = tonumber(endAt) or GetTime()
    if not startTime then return nil end
    trimRecentAdds(endTime)
    local recent = TAD.recentAdds
    for i = #recent, 1, -1 do
        local row = recent[i]
        local at = tonumber(row and row.at)
        if at and at >= startTime and at <= endTime and row.unit and row.id then
            return row
        end
    end
    return nil
end

-- Event feeds, routed from DungeonTrash: UNIT_AURA is registered only while
-- the monitor runs AND the sampler is live (see StartMonitor); the roster
-- edge rides the module's always-on handler, gated on enabled here. The roster
-- handler wipes and reseeds: party unit tokens re-key on every roster change,
-- so the old baselines are meaningless.
function TAD.OnUnitAura(unit)
    if TAD.enabled ~= true then return end
    if not isTrackedUnit(unit) then return end
    TAD.RefreshUnit(unit, false)
end

function TAD.OnRosterChanged()
    if TAD.enabled ~= true then return end
    wipe(TAD.auraCache)
    wipe(TAD.recentAdds)
    TAD.seeded = false
    TAD.RefreshGroup(true)
end

return TAD
