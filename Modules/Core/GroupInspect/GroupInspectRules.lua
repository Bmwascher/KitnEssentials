-- ╔══════════════════════════════════════════════════════════╗
-- ║  GroupInspectRules.lua                                   ║
-- ║  Purpose: pure decision logic for the shared inspect     ║
-- ║           queue. No WoW API, no frames -- so it is       ║
-- ║           testable headlessly.                           ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local ipairs = ipairs
local pairs = pairs
local type = type

local Rules = {}
KE.GroupInspectRules = Rules

Rules.INSPECT_GAP = 2
Rules.TIMEOUT = 5
Rules.MAX_TRIES = 12
Rules.STALE_TRIES = 3
Rules.TRY_WAIT = 30
-- Seconds after another addon's inspect request in which nobody is asked and
-- no answer is cleared: that request may still be reading the data.
Rules.FOREIGN_GAP = 3
-- Failed walks of one spec's tree before walks stop until a refresh.
Rules.MAX_MISSES = 3

-- Blizzard's Inspect window, or its talent view of another player, reads the
-- inspect data too: nothing is asked for or cleared then.
function Rules.InspectInUse(inspectShown, talentsInspecting)
    return inspectShown == true or talentsInspecting == true
end

-- Whether another addon's inspect request, made at foreignAt, may still be in
-- use.
function Rules.ForeignBusy(now, foreignAt)
    if type(foreignAt) ~= "number" then return false end
    return now - foreignAt < Rules.FOREIGN_GAP
end

-- Whether a request made at lastRequest has gone unanswered too long.
function Rules.TimedOut(now, lastRequest)
    return now - lastRequest >= Rules.TIMEOUT
end

-- At most one queue record per call, and none while an inspect view is in
-- use, in combat, within INSPECT_GAP seconds of the last request or within
-- FOREIGN_GAP seconds of another addon's. An offline GUID never answers, and
-- asking it would hold back everyone behind it.
function Rules.NextInspect(state, entries)
    if Rules.InspectInUse(state.inspectShown, state.talentsInspecting) or state.inCombat then return nil end
    if state.lastRequest and state.now - state.lastRequest < Rules.INSPECT_GAP then return nil end
    if Rules.ForeignBusy(state.now, state.foreignAt) then return nil end
    for _, e in ipairs(entries) do
        if not e.done and e.canInspect and not e.offline and not (e.waitUntil and state.now < e.waitUntil) then
            return e
        end
    end
    return nil
end

-- A request with no answer is a try; MAX_TRIES of them rest the GUID, or
-- STALE_TRIES when every answer it is wanted for is in hand and only stale.
function Rules.CountTry(e, now, stale)
    e.tries = (e.tries or 0) + 1
    if e.tries >= (stale and Rules.STALE_TRIES or Rules.MAX_TRIES) then
        e.tries, e.waitUntil = 0, now + Rules.TRY_WAIT
    end
end

-- An owner hears answers while it has demand and is not released.
function Rules.Receives(owner)
    return owner ~= nil and owner.released ~= true and owner.demand ~= nil
end

-- call(owner) for each owner, in subscription order, that still receives at
-- its turn: one released by an earlier call is skipped.
function Rules.Dispatch(owners, call)
    for i = 1, #owners do
        local owner = owners[i]
        if Rules.Receives(owner) then call(owner) end
    end
end

function Rules.AnyActive(owners)
    for _, owner in ipairs(owners) do
        if Rules.Receives(owner) then return true end
    end
    return false
end

-- The queue records of every GUID the active owners list, in subscription
-- order and then list order, each once. A record keeps the first listing's
-- entry and reads its GUID and unit from it when used; nothing is written to
-- an entry.
function Rules.Union(owners, queue)
    local out, seen = {}, {}
    for _, owner in ipairs(owners) do
        if Rules.Receives(owner) then
            for _, e in ipairs(owner.demand) do
                local guid = e.guid
                if guid ~= nil and not seen[guid] then
                    seen[guid] = true
                    local record = queue[guid]
                    if not record then
                        record = {}
                        queue[guid] = record
                    end
                    record.entry = e
                    out[#out + 1] = record
                end
            end
        end
    end
    return out
end

-- The owners asked about guid: the active ones listing it, or every active
-- one when none does, since an answer can arrive after a roster change
-- emptied the lists. A new list per call: an owner's callback may call back
-- into the service while the caller walks this one.
function Rules.Askers(owners, guid)
    local out = {}
    for _, owner in ipairs(owners) do
        if Rules.Receives(owner) and owner.has and owner.has[guid] then out[#out + 1] = owner end
    end
    if #out == 0 then
        for _, owner in ipairs(owners) do
            if Rules.Receives(owner) then out[#out + 1] = owner end
        end
    end
    return out
end

function Rules.Wanted(owners, guid)
    for _, owner in ipairs(Rules.Askers(owners, guid)) do
        if owner.callbacks.Wants(guid) == true then return true end
    end
    return false
end

local function Stale(owner, guid)
    local fn = owner.callbacks.OnlyStale
    return fn ~= nil and fn(guid) == true
end

-- Only stale when every asker that wants guid says so; when none wants it,
-- when every asker says so.
function Rules.OnlyStale(owners, guid)
    local askers = Rules.Askers(owners, guid)
    local wanting = false
    for _, owner in ipairs(askers) do
        if owner.callbacks.Wants(guid) == true then
            wanting = true
            if not Stale(owner, guid) then return false end
        end
    end
    if wanting then return true end
    for _, owner in ipairs(askers) do
        if not Stale(owner, guid) then return false end
    end
    return #askers > 0
end

-- A node's entry list, or nil when the node or its list is not a table: a
-- node skipped there would read its talents as 0. An empty list is readable.
function Rules.NodeEntries(node)
    if type(node) ~= "table" or type(node.entryIDs) ~= "table" then return nil end
    return node.entryIDs
end

-- A failed walk adds a miss to its spec. Inside one inspect answer (answer
-- set) every owner reads the same data, so the spec takes one miss however
-- many owners' reads walked it; counted keeps the answer that took it.
function Rules.CountMiss(misses, counted, specID, answer)
    if answer ~= nil then
        if counted[specID] == answer then return end
        counted[specID] = answer
    end
    misses[specID] = (misses[specID] or 0) + 1
end

-- What a rank read does: "read" from a covering index, "walk" the tree first,
-- "miss" (the loadout is not of the requested spec, cached index included,
-- or the spec's walks are spent) or "skip" (a walk due in combat waits
-- without a miss).
function Rules.WalkPlan(spent, specID, loadoutSpec, inCombat, covered)
    if specID == nil or loadoutSpec ~= specID then return "miss" end
    if covered then return "read" end
    if spent then return "miss" end
    if inCombat then return "skip" end
    return "walk"
end

-- Whether an index entry was built for every ID in want.
function Rules.Covers(entry, want)
    if type(entry) ~= "table" then return false end
    for id in pairs(want) do
        if not entry.covered[id] then return false end
    end
    return true
end

-- Whether a read reports id: skip names the IDs it leaves unread.
function Rules.Kept(skip, id)
    return not (skip and skip[id])
end

-- A finished read's ranks: a kept, covered talent the tree lacks reads 0. An
-- uncovered one stays unread, never 0.
function Rules.FillAbsent(out, want, skip, found, covered)
    for id in pairs(want) do
        if out[id] == nil and Rules.Kept(skip, id) and covered[id] and not found[id] then
            out[id] = 0
        end
    end
    return out
end
