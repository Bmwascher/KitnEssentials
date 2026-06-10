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

-- Exported for the run-identity stamp on MPT.db._activeRunSplits (core file's
-- UpdateObjectives): a persisted in-flight cache must only restore into the
-- exact run ("mapID:level") that wrote it.
MPT.BuildSplitKey = BuildKey

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
    local rec, srcLvl = MPT:ResolvePB(run.mapID, run.level, run.affixIDs)
    -- Cache once per run. false = "resolved, nothing found" (nil = not yet resolved).
    run.pbRec = rec or false
    run.pbSourceLevel = rec and srcLvl or nil  -- key level the record came from (HUD fallback tag)
    run.bestOverall = rec and rec.overall or nil
end

---------------------------------------------------------------------------------
-- ResolvePBFrom / ResolvePB — pure fallback resolver (busted-testable)
---------------------------------------------------------------------------------

-- Pure resolver: given the whole store table, return the best PB record for
-- (mapID, level, affixIDs) using the fallback chain:
--   1. Exact key "mapID:level"
--   2. +affix scope (documented passthrough — level-keyed store has no affix data)
--   3. Dungeon scope: another level for this map, picked by `mode`
--      (db.PBFallbackMode; WD fallbackSplitBehavior parity + symmetric CLOSEST):
--        CLOSEST (default)  nearest |delta| either direction; equidistant tie
--                           breaks deterministically toward the LOWER level
--        CLOSEST_LOWER      nearest level below; none below -> nearest above
--        CLOSEST_HIGHER     nearest level above; none above -> nearest below
--        HIGHEST / LOWEST   extreme recorded level for this map
--        OFF                exact level only (WD's "none")
-- Returns (record, sourceLevel) — record is { [criteriaIndex]=sec, overall=sec }
-- or nil; sourceLevel is the key level the record came from (== level on an
-- exact hit) so the HUD can tag fallback targets ("PB 25:30 [11]").
-- This function is pure (no WoW API, no upvalue access) so it is busted-testable.
function MPT.ResolvePBFrom(store, mapID, level, _affixIDs, mode)
    if not store or not mapID then return nil end
    mode = mode or "CLOSEST"

    -- 1. Exact "mapID:level".
    local exact = store[BuildKey(mapID, level)]
    if exact and exact.best then return exact.best, level end

    -- 2. +affix scope: prefer a same-level record carrying matching affixes.
    --    Reserved for a future affix-keyed store; with level-keyed storage,
    --    exact already covers level. _affixIDs is threaded through so the
    --    signature requires no change when affix-keyed storage lands.
    --    Fall through to dungeon scope.
    if mode == "OFF" then return nil end

    -- 3. Dungeon scope: collect recorded levels for this map (sorted ascending
    -- so every mode below is deterministic — pairs() order never leaks).
    local prefix = tostring(mapID) .. ":"
    local levels, recs = {}, {}
    for key, rec in pairs(store) do
        if rec.best and key:sub(1, #prefix) == prefix then
            local lvl = tonumber(key:match(":(%d+)$")) or 0
            levels[#levels + 1] = lvl
            recs[lvl] = rec
        end
    end
    if #levels == 0 then return nil end
    table.sort(levels)

    local cur = level or 0
    local pick
    if mode == "HIGHEST" then
        pick = levels[#levels]
    elseif mode == "LOWEST" then
        pick = levels[1]
    elseif mode == "CLOSEST_LOWER" or mode == "CLOSEST_HIGHER" then
        local below, above
        for i = 1, #levels do
            local l = levels[i]
            if l < cur then below = l end                   -- last below = nearest below
            if l > cur and not above then above = l end     -- first above = nearest above
        end
        if mode == "CLOSEST_LOWER" then
            pick = below or above
        else
            pick = above or below
        end
    else -- CLOSEST
        local bestDelta
        for i = 1, #levels do
            local delta = abs(levels[i] - cur)
            -- Strict < over the ascending list keeps the LOWER level on
            -- equidistant ties (e.g. records at 10 and 12 for an 11 key).
            if not bestDelta or delta < bestDelta then
                bestDelta, pick = delta, levels[i]
            end
        end
    end
    if pick and recs[pick] then return recs[pick].best, pick end
    return nil
end

-- Public wrapper: reads the live store + configured fallback mode and
-- delegates to the pure core. Returns (record, sourceLevel).
function MPT:ResolvePB(mapID, level, affixIDs)
    return MPT.ResolvePBFrom(GetStore(), mapID, level, affixIDs,
        self.db and self.db.PBFallbackMode)
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
        local resolved, srcLvl = MPT:ResolvePB(run.mapID, run.level, run.affixIDs)
        rec = resolved or false
        run.pbRec = rec
        run.pbSourceLevel = resolved and srcLvl or nil
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
-- improve the stored record. Called after the final UpdateObjectives (whose
-- tail runs UpdateSplits) so run.bestOverall still holds the PRE-run record
-- for completion-screen deltas.
-- ORDERING CONTRACT: must be called AFTER UpdateSplits (which reads the
-- pre-run record). CompleteRun: UpdateObjectives (tail-calls UpdateSplits)
-- -> CommitSplits. Committing first would zero the completion-screen delta.
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
    -- GetCurrentSeason returns -1 while the API isn't ready; stamping that
    -- would clobber a valid season and permanently exempt the record from
    -- PurgeStaleSplits (which ignores entries with lastSeenSeason <= 0).
    if season and season > 0 then
        entry.lastSeenSeason = season
    end
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
