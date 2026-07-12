-- ╔══════════════════════════════════════════════════════════╗
-- ║  TrashCache.lua                                          ║
-- ║  Nameplate-flicker recovery for DungeonTrash.            ║
-- ║                                                          ║
-- ║  A plate that blips out (render churn, brief LoS) and    ║
-- ║  returns gets a FRESH unit token and a blank runtime —   ║
-- ║  losing the mob's resolved identity, cast anchors and    ║
-- ║  live countdowns. This module holds a removed, resolved  ║
-- ║  runtime for a short window; when a NEW virgin plate     ║
-- ║  independently re-resolves to the same npcID inside the  ║
-- ║  window, the cached runtime is adopted wholesale and its ║
-- ║  central alerts re-key to the new unit — bars keep       ║
-- ║  counting straight through the flicker.                  ║
-- ║                                                          ║
-- ║  Port of the reference's trash cache (both reference     ║
-- ║  addons ship byte-identical cache logic); KE wires the   ║
-- ║  UNION of their event feeds: the UNIT_HEALTH death guard ║
-- ║  (one reference) AND the UNIT_FLAGS fresh-combat guard   ║
-- ║  (the other — inert upstream in the first). One          ║
-- ║  documented adaptation: the reference deep-copies its    ║
-- ║  snapshot into the new runtime table and then re-points  ║
-- ║  every live scheduler timer old→new; KE's deferred       ║
-- ║  alerts capture the runtime TABLE in their closures, so  ║
-- ║  adopting the cached table as the new unit's runtime IS  ║
-- ║  that rebind, with no timer walking. Extends the         ║
-- ║  DungeonTrash module.                                    ║
-- ╚══════════════════════════════════════════════════════════╝

if not KitnEssentials then return end

local DTrash = KitnEssentials:GetModule("DungeonTrash", true)
if not DTrash then return end

local GetTime = GetTime
local C_Timer = C_Timer
local UnitIsDead = UnitIsDead
local UnitAffectingCombat = UnitAffectingCombat
local issecretvalue = issecretvalue
local pcall = pcall
local tonumber = tonumber
local table_remove = table.remove
local pairs = pairs
local wipe = wipe

-- Constants verbatim from the reference cache module.
local RESTORE_WINDOW = 5.0          -- how long a removed runtime stays restorable
local NEW_COMBAT_BLOCK_WINDOW = 1.0 -- plate that entered combat this soon after
                                    -- appearing = a genuinely NEW pull, no restore
local RECENT_DEAD_WINDOW = 1.0      -- a unit seen dead this recently is not cached
local MAX_PENDING = 24              -- pending-row cap (oldest evicted first)

DTrash._trashPending = {}      -- array of pending rows { npcID, rt, sourceUnit, removedAt, expiresAt }
DTrash._plateMeta = {}         -- [unit] = { addedAt, firstCombatFlagAt } (fresh-combat guard)
DTrash._recentDeadByUnit = {}  -- [unit] = GetTime() of last observed death

-- Cache lines ride the module's DEBUG_DTRASH flag via the hook DungeonTrash.lua
-- exports (DTrash._dprint) — one debug flag for the whole trash engine.
local function dprint(msg)
    if DTrash._dprint then DTrash._dprint("[cache] " .. msg) end
end

local function safeIsDead(unit)
    local ok, v = pcall(UnitIsDead, unit)
    if not ok then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v == true
end

local function safeInCombat(unit)
    local ok, v = pcall(UnitAffectingCombat, unit)
    if not ok then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v == true
end

-- Ownership gate for a dropped row's alert sweep. The sweep key is a
-- token+npcID prefix, and a recycled token can host a LIVE same-npcID
-- successor whose bars share that exact prefix — clean starts are reachable
-- two mundane ways: the fresh-combat guard blocks the restore for a genuinely
-- new add, and a Layer2-first confirm (FinishCast) resolves without ever
-- consulting the cache. The npcID scope isolates different-npcID mobs only;
-- the reference cannot cross-kill here at all (its expiry cancels via the
-- cached runtime OBJECT), so skip the sweep whenever a DIFFERENT live runtime
-- resolved to the same npcID owns the prefix now.
local function sweepOwnedByRow(self, row)
    local live = self.tracked[row.sourceUnit]
    if live and live ~= row.rt and tonumber(live.matchedNPCID) == row.npcID then
        return false
    end
    return true
end

-- Lazy expiry (the reference runs the same cleanup at add/remove/restore). KE
-- addition over the reference: sweeping an EXPIRED row here also sweeps its
-- still-counting alerts — upstream leaves that solely to the per-row timer,
-- which no-ops if this prune won the race and the teardown flag then leaks.
-- HideUnitAlerts is idempotent, so timer + prune can both fire safely.
function DTrash:PruneTrashCache(now)
    local pending = self._trashPending
    for i = #pending, 1, -1 do
        local row = pending[i]
        if now >= (row.expiresAt or 0) then
            table_remove(pending, i)
            if row.rt then row.rt._cachePending = nil end
            -- npcID-scoped AND ownership-gated: the recycled token may
            -- already host a NEW mob's live bars, which this expired row
            -- must not touch — even when that mob shares the npcID.
            if self.HideUnitAlerts and sweepOwnedByRow(self, row) then
                self:HideUnitAlerts(row.sourceUnit, row.npcID)
            end
        end
    end
    for unit, deadAt in pairs(self._recentDeadByUnit) do
        if now - deadAt > RECENT_DEAD_WINDOW then
            self._recentDeadByUnit[unit] = nil
        end
    end
end

-- ── Event feeds ─────────────────────────────────────────────────────────────

-- Plate appeared: start its fresh-combat meta row and clear any stale
-- recent-dead mark for the recycled token (mirrors the reference's
-- plate-added handling).
function DTrash:NoteNameplateAddedForCache(unit)
    self._plateMeta[unit] = { addedAt = GetTime() }
    self._recentDeadByUnit[unit] = nil
    self:PruneTrashCache(GetTime())
end

-- UNIT_FLAGS: record the first moment the unit is seen in combat after its
-- plate appeared (the fresh-combat guard's input). Wired in one reference
-- only; the cache logic consuming it is shipped in both. The same flip is
-- also the cleanest ENGAGE signal for a mob that hasn't acted yet — it feeds
-- MarkEngaged so a resolved mob's first-cast timers seed the moment it is
-- actually pulled.
function DTrash:OnUnitFlags(_, unit)
    local rt = unit and self.tracked[unit]
    if not rt then return end
    local meta = self._plateMeta[unit]
    if not meta then
        meta = { addedAt = GetTime() }
        self._plateMeta[unit] = meta
    end
    local inCombat = safeInCombat(unit)
    if meta.firstCombatFlagAt == nil and inCombat == true then
        meta.firstCombatFlagAt = GetTime()
    end
    -- Per-unit combat FLIP → reset the target-state sampler (the reference
    -- resets its sampler on every transition): re-entering combat
    -- re-seeds the presence baseline; leaving (evade/wipe) clears it so a
    -- stale exists→gone can't log a false clear on the re-pull. MarkEngaged
    -- covers the FIRST entry; this covers every later flip.
    if inCombat ~= nil and meta.lastInCombat ~= nil and inCombat ~= meta.lastInCombat then
        self:ResetTargetState(rt, inCombat)
    end
    if inCombat ~= nil then meta.lastInCombat = inCombat end
    if meta.firstCombatFlagAt then
        self:MarkEngaged(rt, meta.firstCombatFlagAt)
    end
end

-- UNIT_HEALTH → death: mark the token recently-dead (blocks caching), purge
-- pending rows sourced from it, and untrack the plate immediately — the
-- reference unregisters a dead plate through its normal removal path, whose
-- cache write is then skipped by the recent-dead mark, so the mob's alerts
-- tear down NOW instead of counting on for a corpse.
function DTrash:OnUnitHealth(_, unit)
    if not unit or not self.tracked[unit] then return end
    if safeIsDead(unit) ~= true then return end
    local now = GetTime()
    self._recentDeadByUnit[unit] = now
    self._plateMeta[unit] = nil
    local pending = self._trashPending
    for i = #pending, 1, -1 do
        local row = pending[i]
        if row.sourceUnit == unit then
            table_remove(pending, i)
            -- Mirror the prune's drop hygiene (this purge was the one removal
            -- path without it): the row's expiry closure can no longer find
            -- it and no-ops, so the flag would leak forever — and a leaked
            -- _cachePending is an affirmative liveness credential at
            -- ScheduleAlert's deferred-reveal gate (a phantom bar + cast cue
            -- for a mob whose restore just became impossible, fireable even
            -- after monitor stop because ResetTrashCache clears flags by
            -- iterating rows). Sweep the row's still-counting alerts too.
            if row.rt then row.rt._cachePending = nil end
            if self.HideUnitAlerts and sweepOwnedByRow(self, row) then
                self:HideUnitAlerts(row.sourceUnit, row.npcID)
            end
        end
    end
    dprint("dead " .. unit)
    self:OnNameplateRemoved(nil, unit)
end

-- ── Write path (called from OnNameplateRemoved) ─────────────────────────────

-- Hold a removed, resolved runtime for RESTORE_WINDOW. Returns true when the
-- runtime was cached — the caller then SKIPS the immediate alert teardown
-- (the reference's deferred cancel: central bars keep counting through the
-- window; the per-row timer below does the real sweep if no restore lands).
function DTrash:CacheRemovedRuntime(unit, rt)
    local now = GetTime()
    self:PruneTrashCache(now)
    local npcID = tonumber(rt and rt.matchedNPCID)
    if not npcID then return false end
    local deadAt = self._recentDeadByUnit[unit]
    if deadAt and (now - deadAt) <= RECENT_DEAD_WINDOW then
        dprint("remove-skip " .. unit .. " reason=recent-dead")
        return false
    end
    local row = {
        npcID = npcID,
        rt = rt,
        sourceUnit = unit,
        removedAt = now,
        expiresAt = now + RESTORE_WINDOW,
    }
    local pending = self._trashPending
    pending[#pending + 1] = row
    while #pending > MAX_PENDING do
        local evicted = table_remove(pending, 1)
        if evicted then
            if evicted.rt then evicted.rt._cachePending = nil end
            -- Same drop hygiene as prune/expiry (the eviction predated that
            -- invariant): an evicted mob's still-counting bars otherwise run
            -- to zero and fire the onHide "cast moment" cue — violating the
            -- despawn-never-fakes-a-cue contract — during exactly the
            -- mass-despawn wipes that overflow the cap.
            if self.HideUnitAlerts and sweepOwnedByRow(self, evicted) then
                self:HideUnitAlerts(evicted.sourceUnit, evicted.npcID)
            end
        end
    end
    -- Pending-recovery mark (the reference carries an equivalent flag): while
    -- set, the deferred-alert cancel gate in ScheduleAlert lets a reveal
    -- maturing INSIDE the flicker gap fire on schedule — restore and expiry
    -- below own the real cancel.
    rt._cachePending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(RESTORE_WINDOW, function()
            local p = self._trashPending
            for i = #p, 1, -1 do
                if p[i] == row then
                    table_remove(p, i)
                    row.rt._cachePending = nil
                    -- Never restored: the deferred cancel lands now, scoped
                    -- to the cached mob's own keys AND ownership-gated (a
                    -- recycled token may host a NEW mob's live bars — even a
                    -- same-npcID twin's).
                    if self.HideUnitAlerts and sweepOwnedByRow(self, row) then
                        self:HideUnitAlerts(row.sourceUnit, row.npcID)
                    end
                    dprint("expire " .. row.sourceUnit .. " npc=" .. npcID)
                    break
                end
            end
        end)
    end
    dprint("cache " .. unit .. " npc=" .. npcID)
    return true
end

-- ── Restore path (called from ResolveMob, pre-assignment) ───────────────────

-- A virgin runtime (never resolved, never restored) that independently
-- re-resolved to a cached npcID inside the window adopts the cached runtime
-- wholesale: identity, castConfirmed seniority, anchors, predictions and the
-- live alerts all carry over; only the unit token, the fresh identity read
-- and the fresh Layer1 candidates come from the new plate. Returns the
-- adopted runtime (now installed in self.tracked) or nil.
function DTrash:TryRestoreCachedRuntime(rt, npcID)
    local pending = self._trashPending
    if #pending == 0 then return nil end
    local now = GetTime()
    self:PruneTrashCache(now)
    -- Fresh-combat guard: a plate that entered combat within the block window
    -- of appearing is a genuinely new pull — restoring would hand it a stale
    -- schedule (and, with KE's castConfirmed stickiness, a PERMANENT wrong
    -- lock), so it starts clean instead.
    local meta = self._plateMeta[rt.unit]
    if meta and meta.addedAt and meta.firstCombatFlagAt
        and meta.firstCombatFlagAt >= meta.addedAt
        and (meta.firstCombatFlagAt - meta.addedAt) <= NEW_COMBAT_BLOCK_WINDOW then
        dprint("restore-skip " .. rt.unit .. " reason=fresh-combat")
        return nil
    end
    -- Newest matching row wins; consumed immediately (reference semantics).
    -- KE addition: a row sourced from THIS token outranks newer rows from
    -- other tokens — restoring it makes the alert re-key a same-unit no-op,
    -- so it can never land on a destination key another same-npcID twin's
    -- live frames already occupy (the RekeyUnitAlerts clobber class).
    local bestIndex, bestAt, bestSame = nil, nil, false
    for i = 1, #pending do
        local row = pending[i]
        if row.npcID == npcID then
            local same = (row.sourceUnit == rt.unit)
            if (same and not bestSame)
                or (same == bestSame and (bestAt == nil or (row.removedAt or 0) > bestAt)) then
                bestAt = row.removedAt or 0
                bestIndex = i
                bestSame = same
            end
        end
    end
    if not bestIndex then return nil end
    local row = table_remove(pending, bestIndex)
    local cached = row.rt
    local newUnit = rt.unit
    local oldUnit = row.sourceUnit

    -- Adopt the cached table as the unit's runtime (see header: this IS the
    -- reference's timer rebind). The new plate contributes its unit token,
    -- its fresh identity snapshot and its fresh Layer1 candidate list; an
    -- active cast measurement survives — a cast begun before the flicker can
    -- legitimately STOP after it, and the castBarID correlation still pairs.
    cached.unit = newUnit
    cached.obs = rt.obs or cached.obs
    cached.candidates = rt.candidates or cached.candidates
    cached._cacheRestoredAt = now
    cached._cachePending = nil
    self.tracked[newUnit] = cached

    -- Live alerts follow the identity: same frames, same stack slots, new
    -- unit-prefixed keys — scoped to the restored mob's npcID (a recycled
    -- old token may already carry a DIFFERENT live mob's bars; they stay).
    if self.RekeyUnitAlerts then self:RekeyUnitAlerts(oldUnit, newUnit, npcID) end
    -- Deferred alert timers captured OLD-unit keys; kill them via their token
    -- table and re-arm from each anchor's predicted next start (the shared
    -- DTrash:ReArmFromAnchors — it skips anchors whose bar is ALREADY
    -- counting under the re-keyed name: ShowAlert's refresh-in-place would
    -- reset totalDuration to the remaining lead and snap the fill back to
    -- 100% mid-count, the exact "counts straight through the flicker"
    -- contract this module exists for). Predictions rode the table, so no
    -- plate repaint here — UpdateNameplateMarker below owns that.
    if cached._alertTokens then wipe(cached._alertTokens) end
    self:ReArmFromAnchors(cached, false, now)
    -- On-plate icons: predictions rode along in the table; repaint them
    -- against the new plate.
    if cached.predictions and next(cached.predictions) and self.UpdateNameplateMarker then
        self:UpdateNameplateMarker(newUnit)
        if self.EnsureMarkerTicker then self:EnsureMarkerTicker() end
    end
    dprint("restore " .. oldUnit .. " -> " .. newUnit .. " npc=" .. npcID)
    return cached
end

-- Full wipe (monitor stop — the reference resets its cache at the same
-- lifecycle point: tracker stop / leaving the instance).
function DTrash:ResetTrashCache()
    -- Clear pending-recovery marks first: a leftover mark would let a dead
    -- runtime's deferred reveal fire after the monitor stopped.
    for i = 1, #self._trashPending do
        local r = self._trashPending[i].rt
        if r then r._cachePending = nil end
    end
    wipe(self._trashPending)
    wipe(self._plateMeta)
    wipe(self._recentDeadByUnit)
end

return DTrash
