-- ╔══════════════════════════════════════════════════════════╗
-- ║  TrashKingsRest.lua                                      ║
-- ║  Pure Kings' Rest wave core: the recent removal history  ║
-- ║  and the room batch (admission, ready check, summary).   ║
-- ║                                                          ║
-- ║  No WoW API and no timers. The caller passes each        ║
-- ║  event's time and a provider table, requests the batch   ║
-- ║  timers itself, and owns scope (map and room).           ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local type = type
local pairs = pairs
local ipairs = ipairs
local table_remove = table.remove

local KR = {}
KE.TrashKingsRest = KR

KR.LOOKBACK = 5.0       -- the cache's restore window: a removal this recent may return
KR.HISTORY_CAP = 24     -- the cache's pending cap
KR.JOIN_WINDOW = 0.50   -- admission bound after a batch's first add
KR.READY_DELAY = 0.85   -- ready-check request after a batch's first add

-- Owner fields this core sets on a generation owner record:
--   krDecision  nil (not a member), "held", "granted", "excluded", "released"
--   krReason    "non-wave" or "strictly-neutral" for an excluded member
--   krBatch     the member's batch
--   krCapture   { addedAt, entries, unknown }, immutable once taken
--   krDied      the generation's own death was confirmed
-- Provider table env:
--   holds(owner)        the generation owner check
--   resolve(owner)      ordinary resolve for a member whose hold ended
--   refresh(owner)      the ready read: one event read and one resolve pass
--   state(owner)        the snapshot and the recovery set (nil unjudged,
--                       empty settled)
--   compatible(obs)     the permanently compatible rows, as a set
--   waveRows            the group-field rows, as a set
--   familyGate          whether family presence is read and compared

-- history holds immutable entries { removedAt, set } or { removedAt,
-- unknown = true } in write order. incompleteUntil is the last add time whose
-- lookback may be missing a removal. batch is the open or last completed batch.
function KR.New()
    return { active = false, history = {}, incompleteUntil = nil, batch = nil, gen = 0 }
end

-- Observation starts or resumes: the history before now is missing, so
-- lookbacks ending within LOOKBACK of it are incomplete.
function KR.Start(st, now)
    st.active = true
    st.history = {}
    st.incompleteUntil = now + KR.LOOKBACK
end

local function prune(st, now)
    local h = st.history
    local cutoff = now - KR.LOOKBACK
    while h[1] and h[1].removedAt < cutoff do table_remove(h, 1) end
end

-- The possibility set of one ended generation: the rows its fresh snapshot
-- does not permanently reject, plus its resolved NPC (added, never
-- substituted). No snapshot gives an unknown entry; a known empty set gives
-- none, since it can never match a member.
function KR.EntryFor(obs, matchedNPCID, compatible)
    if obs == nil then return { unknown = true } end
    local set, any = {}, false
    for npcID in pairs(compatible or {}) do
        set[npcID] = true
        any = true
    end
    if matchedNPCID ~= nil then
        set[matchedNPCID] = true
        any = true
    end
    if not any then return nil end
    return { set = set }
end

-- Writes the entry of an ended generation at `now`, unless observation is
-- off or that generation's own death was confirmed. Past the cap the oldest
-- entry is dropped and history stays incomplete through its lookback end.
-- Returns whether an entry was written.
function KR.RecordRemoval(st, owner, now, obs, matchedNPCID, compatible)
    if not st.active or (type(owner) == "table" and owner.krDied) then return false end
    local entry = KR.EntryFor(obs, matchedNPCID, compatible)
    if not entry then return false end
    prune(st, now)
    entry.removedAt = now
    local h = st.history
    h[#h + 1] = entry
    if #h > KR.HISTORY_CAP then
        local edge = table_remove(h, 1).removedAt + KR.LOOKBACK
        if st.incompleteUntil == nil or edge > st.incompleteUntil then st.incompleteUntil = edge end
    end
    return true
end

-- A confirmed death of this generation: its removal writes no entry.
function KR.MarkDied(owner)
    owner.krDied = true
end

-- Entries with addedAt - LOOKBACK <= removedAt <= addedAt, inclusive, taken
-- after a prune at the same time, and whether the lookback is incomplete.
local function capture(st, now)
    prune(st, now)
    local entries = {}
    for _, e in ipairs(st.history) do
        if e.removedAt <= now then entries[#entries + 1] = e end
    end
    return { addedAt = now, entries = entries,
        unknown = st.incompleteUntil ~= nil and now <= st.incompleteUntil }
end

local function enroll(st, b, owner, now)
    b.members[#b.members + 1] = owner
    owner.krDecision, owner.krBatch = "held", b
    owner.krCapture = capture(st, now)
end

-- Releases every held member (terminal) and completes the batch; then each
-- released member whose owner still holds resolves by ordinary inference.
local function release(b, reason, env)
    b.phase, b.reason = "released", reason
    local freed = {}
    for _, owner in ipairs(b.members) do
        if owner.krDecision == "held" then
            owner.krDecision = "released"
            freed[#freed + 1] = owner
        end
    end
    for _, owner in ipairs(freed) do
        if env.holds(owner) then env.resolve(owner) end
    end
end

local function exclude(owner, reason, env)
    owner.krDecision, owner.krReason = "excluded", reason
    if env.holds(owner) then env.resolve(owner) end
end

-- The join close, applied once: membership closes and fewer than two members
-- releases the batch. `gen` is the requesting timer's batch generation.
-- Returns the batch phase after the call, or nil for a stale callback.
function KR.JoinClose(st, gen, env)
    local b = st.batch
    if not b or b.gen ~= gen then return nil end
    if b.phase == "joining" then
        b.phase = "waiting"
        if #b.members < 2 then release(b, "fewer-at-join", env) end
    end
    return b.phase
end

-- Applies a join close whose bound an add at `now` is past. The add handler
-- calls this before it creates the fresh runtime, so the releases never
-- resolve the arriving or a replaced generation.
function KR.ApplyOverdueClose(st, now, env)
    local b = st.batch
    if b and b.phase == "joining" and now > b.t0 + KR.JOIN_WINDOW then
        KR.JoinClose(st, b.gen, env)
    end
end

-- Classifies a fresh generation's add. Returns "opened" (the first member;
-- the caller requests the join close at JOIN_WINDOW and the ready check at
-- READY_DELAY for the returned generation), "joined", "late" (the batch is
-- waiting: ordinary inference, no new batch), or nil (outside the room,
-- observation off, or an owner already decided).
function KR.OnAdd(st, owner, now, inRoom, env)
    KR.ApplyOverdueClose(st, now, env)
    if not (st.active and inRoom) or owner.krDecision ~= nil then return nil end
    local b = st.batch
    if b and b.phase == "joining" then
        enroll(st, b, owner, now)
        return "joined", b.gen
    end
    if b and b.phase == "waiting" then return "late", b.gen end
    st.gen = st.gen + 1
    b = { gen = st.gen, t0 = now, phase = "joining", members = {} }
    st.batch = b
    enroll(st, b, owner, now)
    return "opened", b.gen
end

-- A held member's generation ended by removal or replacement; the caller
-- marked its owner dead first. Its batch is released. Returns whether it was.
function KR.MemberGone(st, owner, env)
    if type(owner) ~= "table" or owner.krDecision ~= "held" or owner.krBatch ~= st.batch then
        return false
    end
    release(owner.krBatch, "member-removed", env)
    return true
end

-- A member's return status from its capture, against its permanently
-- compatible rows at the ready check: "unknown-history", "possible-return"
-- (an unknown entry, or one sharing a row) or "clear".
function KR.MemberStatus(cap, rows)
    if cap.unknown then return "unknown-history" end
    for _, e in ipairs(cap.entries) do
        if e.unknown then return "possible-return" end
        for npcID in pairs(e.set) do
            if rows and rows[npcID] then return "possible-return" end
        end
    end
    return "clear"
end

-- How many captured entries are possible returns against `rows`, by the
-- MemberStatus rule: an unknown entry, or one sharing a row. For the dump.
function KR.CountPossibleReturns(entries, rows)
    local n = 0
    for _, e in ipairs(entries) do
        if e.unknown then
            n = n + 1
        else
            for npcID in pairs(e.set) do
                if rows and rows[npcID] then
                    n = n + 1
                    break
                end
            end
        end
    end
    return n
end

-- A known level other than 90 and no family presence (or no family axis):
-- the member sets no group flag, so leaving it out cannot change the summary.
function KR.StrictlyNeutral(obs, familyGate)
    if type(obs) ~= "table" or type(obs.level) ~= "number" or obs.level == 90 then return false end
    return not familyGate or obs.hasCreatureFamily == false
end

-- The group flags over the granted members' snapshots; an unseen value is
-- false. Family is summarized only while the family gate is on.
function KR.Summary(snapshots, familyGate)
    local s = { groupHasLevel90 = false, groupHasLevel90Power0 = false }
    if familyGate then s.groupHasCreatureFamily = false end
    for _, obs in ipairs(snapshots) do
        if obs.level == 90 then
            s.groupHasLevel90 = true
            if obs.power == 0 then s.groupHasLevel90Power0 = true end
        end
        if familyGate and obs.hasCreatureFamily == true then s.groupHasCreatureFamily = true end
    end
    return s
end

local function settled(pending)
    return type(pending) == "table" and pending[1] == nil
end

local function hasWaveRow(rows, waveRows)
    for npcID in pairs(rows or {}) do
        if waveRows[npcID] then return true end
    end
    return false
end

-- The ready check, in order: the ready read, settled identity, non-wave
-- exclusion, return history, minimum size, then grant and freeze. `gen` is
-- the requesting timer's batch generation. Returns the batch phase after the
-- check ("ready" or "released"), or nil for a stale callback. No member is
-- left held.
function KR.ReadyCheck(st, gen, env)
    local b = st.batch
    if not b or b.gen ~= gen then return nil end
    if b.phase == "joining" then KR.JoinClose(st, gen, env) end
    if b.phase ~= "waiting" then return b.phase end
    local members = {}
    for _, owner in ipairs(b.members) do
        if owner.krDecision == "held" then members[#members + 1] = owner end
    end
    for _, owner in ipairs(members) do
        local _, pending = env.state(owner)
        if not settled(pending) and env.holds(owner) then env.refresh(owner) end
    end
    local obsOf = {}
    for _, owner in ipairs(members) do
        local obs, pending = env.state(owner)
        if not settled(pending) then
            release(b, "pending-member", env)
            return b.phase
        end
        obsOf[owner] = obs
    end
    local remaining, rowsOf = {}, {}
    for _, owner in ipairs(members) do
        local rows = env.compatible(obsOf[owner])
        if hasWaveRow(rows, env.waveRows) then
            remaining[#remaining + 1] = owner
            rowsOf[owner] = rows
        else
            exclude(owner, "non-wave", env)
        end
    end
    -- Unknown history, or a possible return that could set a group flag,
    -- releases the batch; only then are strictly neutral returns set aside.
    local neutral = {}
    for _, owner in ipairs(remaining) do
        local status = KR.MemberStatus(owner.krCapture, rowsOf[owner])
        -- The dump's count, for a member whose entries this check judged.
        if status ~= "unknown-history" then
            owner.krPossibleReturns = KR.CountPossibleReturns(owner.krCapture.entries, rowsOf[owner])
        end
        if status == "unknown-history" then
            release(b, "unknown-history", env)
            return b.phase
        end
        if status == "possible-return" then
            if not KR.StrictlyNeutral(obsOf[owner], env.familyGate) then
                release(b, "possible-return", env)
                return b.phase
            end
            neutral[owner] = true
        end
    end
    local granted = {}
    for _, owner in ipairs(remaining) do
        if neutral[owner] then
            exclude(owner, "strictly-neutral", env)
        else
            granted[#granted + 1] = owner
        end
    end
    if #granted < 2 then
        release(b, "fewer-after-exclusions", env)
        return b.phase
    end
    local snapshots = {}
    for i, owner in ipairs(granted) do
        owner.krDecision = "granted"
        snapshots[i] = obsOf[owner]
    end
    b.summary = KR.Summary(snapshots, env.familyGate)
    b.phase = "ready"
    for _, owner in ipairs(granted) do
        if env.holds(owner) then env.resolve(owner) end
    end
    return b.phase
end

-- A room change, zone change, monitor stop or disable ends the batch
-- generation: held members are released, grants stand, the history stays.
function KR.ResetBatch(st, env)
    local b = st.batch
    if b and (b.phase == "joining" or b.phase == "waiting") then release(b, "room-reset", env) end
    st.batch = nil
end

-- Monitor stop, disable or leaving the map. The caller marks every owner dead
-- first, so no released member resolves.
function KR.Stop(st, env)
    KR.ResetBatch(st, env)
    st.active, st.history, st.incompleteUntil = false, {}, nil
end

-- A held member gets no identity assignment and consults no cache.
function KR.HoldsIdentity(owner)
    return type(owner) == "table" and owner.krDecision == "held"
end

-- The central adoption refusal: a held or granted owner never adopts.
function KR.RefusesAdoption(owner)
    local d = type(owner) == "table" and owner.krDecision
    return d == "held" or d == "granted"
end

-- The frozen summary that applies to an owner: only a granted contributor's.
function KR.SummaryFor(owner)
    if type(owner) ~= "table" or owner.krDecision ~= "granted" or not owner.krBatch then return nil end
    return owner.krBatch.summary
end

-- A row without group fields is not room-scoped and always survives; a room
-- row must match every summarized flag, false included.
function KR.SummaryKeeps(identity, summary)
    if type(identity) ~= "table" or identity.groupHasLevel90 == nil then return true end
    if identity.groupHasLevel90 ~= summary.groupHasLevel90 then return false end
    if identity.groupHasLevel90Power0 ~= summary.groupHasLevel90Power0 then return false end
    if summary.groupHasCreatureFamily ~= nil
        and identity.groupHasCreatureFamily ~= summary.groupHasCreatureFamily then
        return false
    end
    return true
end

-- Filters candidates through a summary; traitOf(npcID) returns the trait.
-- Returns the kept list and whether a candidate was removed. A nil summary
-- returns the list unchanged.
function KR.ApplySummary(candidates, summary, traitOf)
    if not summary then return candidates, false end
    local kept = {}
    for _, c in ipairs(candidates) do
        local trait = traitOf(c.npcID)
        if KR.SummaryKeeps(trait and trait.identity, summary) then kept[#kept + 1] = c end
    end
    return kept, #kept < #candidates
end

-- The wave-derived mark after a resolve to matchedNPCID: set when the summary
-- removed a candidate and a resolve without it gives no such NPC; cleared
-- only when a resolve without the summary gives the same NPC.
function KR.WaveDerivedAfter(previous, matchedNPCID, withoutSummary, summaryRemoved)
    if matchedNPCID == nil then return false end
    if withoutSummary ~= nil and withoutSummary == matchedNPCID then return false end
    if summaryRemoved then return true end
    return previous == true
end
