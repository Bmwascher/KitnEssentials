-- ╔══════════════════════════════════════════════════════════╗
-- ║  MythicPlusTimer_Splits.lua                              ║
-- ║  PB storage, fallback resolver, live deltas, purge.      ║
-- ╚══════════════════════════════════════════════════════════╝
---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end
local MPT = KitnEssentials:GetModule("MythicPlusTimer")

local abs = math.abs
local format = string.format

---------------------------------------------------------------------------------
-- Store accessors (file-local)
---------------------------------------------------------------------------------

-- Ensure the global splits table exists and return it.
local function GetStore()
    local g = KE.db.global
    g.MythicPlusTimerSplits = g.MythicPlusTimerSplits or {}
    return g.MythicPlusTimerSplits
end

-- Canonical key format: "mapID:level" (e.g. "375:15").
-- Single definition used by KeyFor, ResolvePBFrom, and any future store accessor.
local function BuildKey(mapID, level)
    return format("%s:%d", tostring(mapID), level or 0)
end

local function KeyFor(mapID, level)
    return BuildKey(mapID, level)
end

---------------------------------------------------------------------------------
-- LoadSplits — store-ensure + seed run.bestOverall (called from StartRun)
---------------------------------------------------------------------------------

-- Ensures the store exists and seeds run.bestOverall for the countdown preview.
-- Per-objective pbTime seeding is NOT done here — it is owned by UpdateSplits,
-- which the priming OnTimerTick triggers via UpdateObjectives.
-- Also caches run.pbRec (false = resolved but no record found) so UpdateSplits
-- does not re-scan the store on every tick.
function MPT:LoadSplits()
    local run = self.run
    if not run.mapID then return end
    local rec = MPT:ResolvePB(run.mapID, run.level, run.affixIDs)
    -- Cache once per run. false = "resolved, nothing found" (nil = not yet resolved).
    run.pbRec = rec or false
    run.bestOverall = rec and rec.overall or nil
end

---------------------------------------------------------------------------------
-- ResolvePBFrom / ResolvePB — pure fallback resolver (busted-testable)
---------------------------------------------------------------------------------

-- Pure resolver: given the whole store table, return the best PB record for
-- (mapID, level, affixIDs) using the fallback chain:
--   1. Exact key "mapID:level"
--   2. +affix scope (documented passthrough — level-keyed store has no affix data)
--   3. Dungeon scope: nearest level among all records for this map
-- Returns a record table { [criteriaIndex]=sec, overall=sec } or nil.
-- This function is pure (no WoW API, no upvalue access) so it is busted-testable.
function MPT.ResolvePBFrom(store, mapID, level, _affixIDs)
    if not store or not mapID then return nil end

    -- 1. Exact "mapID:level".
    local exact = store[BuildKey(mapID, level)]
    if exact and exact.best then return exact.best end

    -- 2. +affix scope: prefer a same-level record carrying matching affixes.
    --    Reserved for a future affix-keyed store; with level-keyed storage,
    --    exact already covers level. _affixIDs is threaded through so the
    --    signature requires no change when affix-keyed storage lands.
    --    Fall through to dungeon scope.

    -- 3. Dungeon scope: nearest level among all records for this map.
    local prefix = tostring(mapID) .. ":"
    local bestRec, bestDelta
    for key, rec in pairs(store) do
        if rec.best and key:sub(1, #prefix) == prefix then
            local lvl = tonumber(key:match(":(%d+)$")) or 0
            local delta = abs(lvl - (level or 0))
            if not bestDelta or delta < bestDelta then
                bestDelta, bestRec = delta, rec
            end
        end
    end
    return bestRec and bestRec.best or nil
end

-- Public wrapper: reads the live store and delegates to the pure core.
function MPT:ResolvePB(mapID, level, affixIDs)
    return MPT.ResolvePBFrom(GetStore(), mapID, level, affixIDs)
end

---------------------------------------------------------------------------------
-- UpdateSplits — refresh per-objective pbTime + run.bestOverall (live deltas)
---------------------------------------------------------------------------------

-- Called from the tail of UpdateObjectives (via SCENARIO_CRITERIA_UPDATE) and
-- from CompleteRun. Keeps pbTime targets live for all pending objective rows.
-- Uses run.pbRec cached by LoadSplits (false = no record; nil = LoadSplits
-- never ran, resolve once defensively and cache).
function MPT:UpdateSplits()
    local run = self.run
    if not run.mapID then return end
    -- Use the cached record. If nil (defensive: LoadSplits not yet called),
    -- resolve once and cache so subsequent ticks are free.
    local rec = run.pbRec
    if rec == nil then
        local resolved = MPT:ResolvePB(run.mapID, run.level, run.affixIDs)
        rec = resolved or false
        run.pbRec = rec
    end
    -- Normalise: false means no record; treat as nil for downstream logic.
    local r = rec or nil
    run.bestOverall = r and r.overall or run.bestOverall
    for i = 1, #run.objectives do
        local obj = run.objectives[i]
        -- pbTime drives both the cyan/red delta (completed rows) and the gold
        -- target time (pending rows). Resolve once per objective from the record.
        obj.pbTime = r and r[obj.criteriaIndex] or obj.pbTime
    end
end

---------------------------------------------------------------------------------
-- CommitSplits — persist best splits at run end (called from CompleteRun)
---------------------------------------------------------------------------------

-- Writes per-boss clear times and the overall run time, but only when they
-- improve the stored record. Called after the final UpdateObjectives + UpdateSplits
-- so run.bestOverall still holds the PRE-run record for completion-screen deltas.
-- ORDERING CONTRACT: must be called AFTER UpdateSplits (which reads the pre-run
-- record). CompleteRun: UpdateObjectives -> UpdateSplits -> CommitSplits.
-- Reversing CommitSplits/UpdateSplits would zero the completion-screen delta.
function MPT:CommitSplits()
    local run = self.run
    if not run.mapID then return end
    local store = GetStore()
    local key = KeyFor(run.mapID, run.level)
    local entry = store[key]
    if not entry then entry = { best = {} }; store[key] = entry end
    entry.best = entry.best or {}
    local seasonFn = C_MythicPlus and C_MythicPlus.GetCurrentSeason
    local season = seasonFn and seasonFn()
    entry.lastSeenSeason = season or entry.lastSeenSeason
    -- Per-boss: only write when this clear time beats the stored record.
    for i = 1, #run.objectives do
        local obj = run.objectives[i]
        if obj.completed and obj.clearTime and obj.clearTime > 0 then
            local prev = entry.best[obj.criteriaIndex]
            if not prev or obj.clearTime < prev then
                entry.best[obj.criteriaIndex] = obj.clearTime
            end
        end
    end
    -- Overall: only write when this run beats the stored record.
    if run.elapsed and run.elapsed > 0 then
        if not entry.best.overall or run.elapsed < entry.best.overall then
            entry.best.overall = run.elapsed
        end
    end
end

---------------------------------------------------------------------------------
-- PurgeStaleSplits — season-based purge (called from OnEnable, deferred 2s)
---------------------------------------------------------------------------------

-- Drops any stored record whose lastSeenSeason is set and older than the
-- current season. If the season cannot be determined, keep everything.
function MPT:PurgeStaleSplits()
    local seasonFn = C_MythicPlus and C_MythicPlus.GetCurrentSeason
    local season = seasonFn and seasonFn()
    if not season or season <= 0 then return end  -- season unknown -> keep everything
    local store = GetStore()
    for key, rec in pairs(store) do
        if rec.lastSeenSeason and rec.lastSeenSeason > 0 and rec.lastSeenSeason < season then
            store[key] = nil
        end
    end
end
