-- ╔══════════════════════════════════════════════════════════╗
-- ║  KickTrackerRules.lua                                    ║
-- ║  Module: Interrupt Tracker                               ║
-- ║  Purpose: the tracker's pure decisions (row state, own   ║
-- ║           kicks, durations, meter naming, layers). No    ║
-- ║           WoW API calls.                                 ║
-- ╚══════════════════════════════════════════════════════════╝

if not KitnEssentials then return end

---@type KickTracker
local KT = KitnEssentials:GetModule("KickTracker")

---------------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------------
-- Every member with a kick has a row.
function KT.RowShown(member)
    return member.interruptData ~= nil
end

---------------------------------------------------------------------------------
-- The player's own kick
---------------------------------------------------------------------------------
-- The first candidate the player or the active demon knows.
function KT.PickOwnKick(candidates, isKnown)
    for i = 1, #candidates do
        if isKnown(candidates[i].id) then return candidates[i] end
    end
    return nil
end

-- A kick the player actually cast wins while its mark is set (until the demon
-- or the spec changes); the spellbook check decides only without one.
function KT.OwnKickFallback(picked, castKick)
    return castKick or picked
end

---------------------------------------------------------------------------------
-- Two-kick rows
---------------------------------------------------------------------------------
-- The main kick is member.interruptData with member.kickStart/kickDuration;
-- the player's talent-added kicks are entries in member.extraKicks.

-- The player's extra kicks after a talent check: a kick still wanted keeps
-- its entry and timer, a new one starts ready. The second return is true
-- when a kick was added or dropped.
function KT.SyncExtraKicks(current, wanted)
    local had = current and #current or 0
    if not wanted or #wanted == 0 then return nil, had > 0 end
    local list, kept = {}, 0
    for i = 1, #wanted do
        local w = wanted[i]
        local entry
        if current then
            for j = 1, #current do
                if current[j].id == w.id then
                    entry = current[j]
                    break
                end
            end
        end
        if entry then
            kept = kept + 1
        else
            entry = { id = w.id }
        end
        entry.cd = w.cd
        list[#list + 1] = entry
    end
    return list, kept ~= had or kept ~= #list
end

-- The spec's extra kicks the talents make real: the spell and its required
-- talent must both be known; without its talent the spell is not a kick.
function KT.WantedExtraKicks(list, isKnown)
    if not list then return nil end
    local wanted
    for i = 1, #list do
        local e = list[i]
        if isKnown(e.requires) and isKnown(e.id) then
            wanted = wanted or {}
            wanted[#wanted + 1] = e
        end
    end
    return wanted
end

-- The kick that drives the row, and whether the row reads Ready: the first
-- ready kick (main first), else the kick back soonest. nil means the main
-- kick. A start without a duration (the preview's mocks) counts as cooling.
function KT.PickRowKick(member, now)
    local start, duration = member.kickStart, member.kickDuration
    if not start or (duration and now - start >= duration) then return nil, true end
    local list = member.extraKicks
    if not list or not duration then return nil, false end
    local soonest, soonestRemaining = nil, start + duration - now
    for i = 1, #list do
        local e = list[i]
        if not e.kickStart or now - e.kickStart >= e.kickDuration then return e, true end
        local r = e.kickStart + e.kickDuration - now
        if r < soonestRemaining then soonest, soonestRemaining = e, r end
    end
    return soonest, false
end

---------------------------------------------------------------------------------
-- Own-kick success
---------------------------------------------------------------------------------
function KT.OwnKickMatched(kickAt, landedAt, window)
    if not kickAt or not landedAt then return false end
    local gap = kickAt - landedAt
    if gap < 0 then gap = -gap end
    return gap <= window
end

-- The player's kick cast and a readable own interrupt are one kick when the
-- interrupt lands inside the window. The claim is used up either way, so one
-- cast never claims two interrupts.
function KT.TakeOwnClaim(claim, now, window)
    local at = claim.at
    if not at then return false end
    claim.at = nil
    return now - at <= window
end

-- Every kick cooldown is far longer than the window, so the same kick again
-- inside it is one press reported twice, not a recast.
function KT.DuplicateOwnKick(lastID, lastAt, kickID, now, window)
    return lastID == kickID and lastAt ~= nil and now - lastAt <= window
end

-- The own row's remaining time after a success reduction; nil when the row
-- is not cooling.
function KT.ReducedRemaining(kickStart, kickDuration, now, seconds)
    if not kickStart or not kickDuration then return nil end
    local remaining = kickStart + kickDuration - now
    if remaining <= 0 then return nil end
    remaining = remaining - seconds
    if remaining < 0 then remaining = 0 end
    return remaining
end

-- Only the player's own units are an own kick. A teammate's token can be
-- plain too ("party1"), and that kick is the teammate's.
function KT.IsOwnKickToken(token)
    return token == "player" or token == "pet"
end

---------------------------------------------------------------------------------
-- Nameplate interrupt hygiene
---------------------------------------------------------------------------------
-- Only an answer read plainly as false refuses: a failed call or a secret
-- answer lets the event through. The secret flag is tested before the compare.
function KT.RefusesInterruptUnit(callOk, canAttack, answerSecret)
    if not callOk or answerSecret then return false end
    return canAttack == false
end

-- A stopped channel can be reported more than once on one nameplate in one
-- frame, with reports on other nameplates between; two nameplates are two
-- interrupts. lastByUnit holds each nameplate's last accepted event time.
function KT.SameInterrupt(lastByUnit, unit, now, window)
    local last = lastByUnit[unit]
    return last ~= nil and now - last < window
end

---------------------------------------------------------------------------------
-- Kick durations and teammate facts
---------------------------------------------------------------------------------
-- A kick's duration from its definition (KE:GetKickDefinition). rankOf(talent)
-- gives a rank, or nil when it is unknown; an unknown talent counts as not
-- selected, which gives the longest duration. Flat seconds come off first,
-- then multipliers; a success rule comes off once, after them, only for a
-- confirmed success and a known positive rank; a primaryOnly rule never.
function KT.KickDuration(def, specID, rankOf, succeeded)
    local duration = (def.specBase and def.specBase[specID]) or def.base
    local mods = def.modifiers
    if mods then
        local mult = 1
        for i = 1, #mods do
            local m = mods[i]
            local rank = rankOf(m.talent)
            if rank and rank > 0 then
                if m.seconds then duration = duration - m.seconds end
                if m.multiplier then mult = mult * m.multiplier end
            end
        end
        duration = duration * mult
    end
    local s = def.success
    if succeeded == true and s and not s.primaryOnly then
        local rank = rankOf(s.talent)
        if rank and rank > 0 then duration = duration - s.seconds end
    end
    if duration < 0 then duration = 0 end
    return duration
end

-- A teammate's rank for a talent from their inspect snapshot, or nil when it
-- is not known: no snapshot, a stale one, or a talent its read did not cover.
function KT.SnapshotRank(snap, talent)
    if not snap or snap.stale or not (snap.covered and snap.covered[talent]) then return nil end
    local rank = snap.ranks and snap.ranks[talent]
    if type(rank) ~= "number" then return nil end
    return rank
end

-- The class kick for a teammate not yet inspected: allRoles shows it for any
-- role; otherwise a DAMAGER or TANK role proves a kicking spec. A healer gets
-- it only with allRoles or healerCd. tankCd and healerCd replace cd for their
-- role. Returns the row's kick, marked as a fallback, or nil.
function KT.FallbackKick(fallback, role)
    if not fallback then return nil end
    if role == "HEALER" then
        if fallback.healerCd then
            return { id = fallback.id, cd = fallback.healerCd, role = "HEALER", fallback = true }
        end
        if fallback.allRoles then
            return { id = fallback.id, cd = fallback.cd, role = "HEALER", fallback = true }
        end
        return nil
    end
    if not fallback.allRoles and role ~= "DAMAGER" and role ~= "TANK" then return nil end
    local cd = fallback.cd
    if role == "TANK" and fallback.tankCd then cd = fallback.tankCd end
    return { id = fallback.id, cd = cd, role = (role == "TANK") and "TANK" or "DAMAGER", fallback = true }
end

-- A teammate's inspected facts. The row's kick follows the spec; a clock
-- already running keeps the duration it started with, so new talents count
-- from the next cast. Returns true when the row's kick changed.
function KT.LearnFacts(member, snap, row)
    local oldID = member.interruptData and member.interruptData.id
    member.inspect = snap
    member.interruptData = row
    return oldID ~= (row and row.id)
end

---------------------------------------------------------------------------------
-- Nameplate kicker
---------------------------------------------------------------------------------
-- Who a nameplate interrupt's kicker is, from pcall(UnitTokenFromGUID,
-- interruptedBy): "own" for the player or the pet; "member" and the party
-- index for a plain party1-4 or partypet1-4 token (a pet credits its owner),
-- even when the GUID is secret; "guid" for any other kicker whose token and
-- GUID read plain; "hidden" otherwise.
function KT.ClassifyKicker(callOk, token, tokenSecret, guidSecret)
    if not callOk or tokenSecret then return "hidden" end
    if type(token) == "string" then
        if KT.IsOwnKickToken(token) then return "own" end
        local index = token:match("^party([1-4])$") or token:match("^partypet([1-4])$")
        if index then return "member", tonumber(index) end
    end
    if guidSecret then return "hidden" end
    return "guid"
end

---------------------------------------------------------------------------------
-- The meter decision (who kicked when the game hides it)
---------------------------------------------------------------------------------
-- The group's units, and the meter's per-GUID slots: each member's own
-- source and each pet's. A pet's growth is its owner's.
KT.OWNERS = { "player", "party1", "party2", "party3", "party4" }
KT.SLOTS = { "player", "party1", "party2", "party3", "party4",
             "pet", "partypet1", "partypet2", "partypet3", "partypet4" }
local SLOT_OWNER = {
    player = "player", pet = "player",
    party1 = "party1", partypet1 = "party1",
    party2 = "party2", partypet2 = "party2",
    party3 = "party3", partypet3 = "party3",
    party4 = "party4", partypet4 = "party4",
}

function KT.SlotOwner(slot)
    return SLOT_OWNER[slot]
end

local function clear(t)
    for k in pairs(t) do t[k] = nil end
    return t
end

-- A meter row's key, "CLASS:specIcon", from plain values. A row with no
-- plain class or spec icon (a demon's row has no icon) and the player's own
-- row get NO_ROW, which matches nobody.
local NO_ROW = "-"
local rowKeys, rowParts = {}, {}
function KT.RowKey(class, icon, isLocal)
    if isLocal == true or type(class) ~= "string" or type(icon) ~= "number" then return NO_ROW end
    local byClass = rowKeys[class]
    if not byClass then
        byClass = {}
        rowKeys[class] = byClass
    end
    local key = byClass[icon]
    if not key then
        key = class .. ":" .. icon
        byClass[icon] = key
        rowParts[key] = { class = class, icon = icon }
    end
    return key
end

-- A slot whose read failed keeps its last count and total while its GUID is
-- the same, so a failed read is neither a shrink nor, when it reads again, a
-- growth. A failed row read keeps the last rows.
function KT.CarryCounts(read, last)
    for _, slot in ipairs(KT.SLOTS) do
        local guid = read.guid[slot]
        if read.n[slot] == nil and guid ~= nil and guid == last.guid[slot] then
            read.n[slot], read.a[slot] = last.n[slot], last.a[slot]
        end
    end
    if not read.rowsOk then
        clear(read.rows)
        for i = 1, #last.rows do read.rows[i] = last.rows[i] end
    end
end

-- The counts and totals a read is measured against: a slot whose GUID
-- changed (a roster or pet swap), or that has no usable count under its GUID
-- yet (its first read failed), starts from its own read, with no growth.
-- Fills and returns outN and outA.
function KT.BaselineCounts(read, last, outN, outA)
    for _, slot in ipairs(KT.SLOTS) do
        if read.guid[slot] ~= last.guid[slot] or last.n[slot] == nil then
            outN[slot], outA[slot] = read.n[slot], read.a[slot]
        else
            outN[slot], outA[slot] = last.n[slot], last.a[slot]
        end
    end
    return outN, outA
end

-- Whether a read shrank against its baseline: fewer rows, or a count that
-- fell, is a new fight.
function KT.ListsMoved(rows, n, prevRows, prevN)
    if #rows < #prevRows then return true end
    for _, slot in ipairs(KT.SLOTS) do
        if (n[slot] or 0) < (prevN[slot] or 0) then return true end
    end
    return false
end

-- Each owner's list growth over the baseline, and their entries, a pet's
-- counted for its owner. Fills growth and entries.
function KT.OwnerGrowth(n, prevN, growth, entries)
    for _, slot in ipairs(KT.SLOTS) do
        local count = n[slot]
        if count then
            local owner = SLOT_OWNER[slot]
            entries[owner] = (entries[owner] or 0) + count
            local d = count - (prevN[slot] or 0)
            if d > 0 then growth[owner] = (growth[owner] or 0) + d end
        end
    end
end

-- A member's growth less their readable kicks already charged: each adds one
-- expected count, at its time. One older than window is dropped first, since
-- a readable kick on a repeated spell grows no list and its count must not
-- take a later kick's growth. Returns the growth left unexplained, and
-- whether a readable kick inside the window was there, consumed or not.
function KT.TakeGrowth(expected, owner, growth, T, window)
    local e = expected[owner]
    if e and T - e.at > window then
        expected[owner] = nil
        e = nil
    end
    if not e then return growth, false end
    if growth <= 0 then return growth, true end
    local used = (e.n < growth) and e.n or growth
    e.n = e.n - used
    if e.n <= 0 then expected[owner] = nil end
    return growth - used, true
end

-- The row that is new (one more row) or moved (the first changed place),
-- and how: "new row" or "reorder"; nil when neither.
local leftScratch = {}
function KT.ChangedRow(rows, prevRows)
    if #rows > #prevRows then
        local left = clear(leftScratch)
        for i = 1, #prevRows do left[prevRows[i]] = (left[prevRows[i]] or 0) + 1 end
        local key
        for i = 1, #rows do
            local k = rows[i]
            if (left[k] or 0) > 0 then
                left[k] = left[k] - 1
            else
                key = k
            end
        end
        return key, "new row"
    end
    if #rows == #prevRows then
        for i = 1, #rows do
            if rows[i] ~= prevRows[i] then return rows[i], "reorder" end
        end
    end
    return nil, nil
end

-- The teammates a row key names: a kick row, the class matches, the spec is
-- known and its icon (iconOf) is the row's. Fills and returns out.
function KT.KeyMembers(key, byUnit, iconOf, out)
    clear(out)
    local parts = rowParts[key]
    if not parts then return out end
    for i = 2, #KT.OWNERS do
        local unit = KT.OWNERS[i]
        local m = byUnit[unit]
        if m and m.interruptData and m.matchClass == parts.class and type(m.specID) == "number"
            and m.specID > 0 and iconOf(m.specID) == parts.icon then
            out[#out + 1] = unit
        end
    end
    return out
end

-- How many of list have entries (a working read with one at least), and the
-- one when exactly one has: a kick that grew no list is nobody's first.
function KT.Entered(list, entries)
    local n, only = 0, nil
    for i = 1, #list do
        if (entries[list[i]] or 0) > 0 then n, only = n + 1, list[i] end
    end
    if n ~= 1 then only = nil end
    return n, only
end

-- The member's main kick is modeled as cooling at T.
function KT.MainCooling(member, T)
    local start, duration = member.kickStart, member.kickDuration
    return start ~= nil and duration ~= nil and T - start < duration
end

-- Who kicked, from one update's evidence, best first: a grown list, a new or
-- moved row, the player's cast a moment before, then elimination. e: grew
-- (units whose growth is unexplained), growthOf, entries, cooling,
-- candidates (teammates with a kick row), rowKey, rowHow, rowList (the row's
-- matches), ownPending, plates (the batch it takes). Returns who and how, and
-- the growers when several grew. A row with one match names them: the row is
-- the evidence, whether or not their per-GUID read works.
function KT.Decide(e)
    local grew = e.grew
    if #grew == 1 then
        local who = grew[1]
        if (e.growthOf[who] or 0) > 1 or e.plates > 1 then return nil, "mass", nil end
        if who == "player" then
            if not e.ownPending then return nil, "grip", nil end
        elseif e.cooling[who] then
            return nil, "grip", nil
        end
        return who, "breakdown", nil
    end
    if #grew > 1 then return nil, "several", grew end
    local list = e.rowKey and e.rowList or nil
    if list then
        if #list == 1 then return list[1], e.rowHow, nil end
        if #list < 2 then list = nil end
    end
    if not list and e.ownPending then return "player", "cast", nil end
    list = list or e.candidates
    local n, only = KT.Entered(list, e.entries)
    if n == 1 and #list > 1 then return only, "order", nil end
    return nil, "nobody", nil
end

-- Whether a credit of the player confirms the cast's success: a growth
-- credit does, the cast inside the own window; the own-cast claim does not.
function KT.OwnSuccessFrom(how, ownPending)
    return how == "breakdown" or (how == "several" and ownPending == true)
end

