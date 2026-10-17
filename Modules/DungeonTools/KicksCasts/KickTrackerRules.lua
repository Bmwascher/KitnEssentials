-- ╔══════════════════════════════════════════════════════════╗
-- ║  KickTrackerRules.lua                                    ║
-- ║  Module: Interrupt Tracker                               ║
-- ║  Purpose: the tracker's pure decisions (sending, sync,   ║
-- ║           pairing, row state). No WoW API calls.         ║
-- ╚══════════════════════════════════════════════════════════╝

if not KitnEssentials then return end

---@type KickTracker
local KT = KitnEssentials:GetModule("KickTracker")

---------------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------------
local COMM_SUCCESS = Enum and Enum.SendAddonMessageResult
    and Enum.SendAddonMessageResult.Success or 0
local COMM_LOCKDOWN = Enum and Enum.SendAddonMessageResult
    and Enum.SendAddonMessageResult.AddOnMessageLockdown or 11

-- One message through the first channel that takes it. A lockdown refusal
-- blocks every channel, so nothing else is tried after one, and a known block
-- keeps later sends to a single attempt until one succeeds. sendFn(prefix,
-- msg, channel, target) returns pcall's ok and the send result.
function KT.TransmitComm(state, locked, sendFn, prefix, msg, inInstanceGroup, whisperTargets)
    if locked then return "locked" end
    local ok, ret = sendFn(prefix, msg, inInstanceGroup and "INSTANCE_CHAT" or "PARTY")
    if ok and ret == COMM_SUCCESS then
        state.commBlocked = nil
        return "sent"
    end
    if ok and ret == COMM_LOCKDOWN then state.commBlocked = true end
    if state.commBlocked then return "refused" end

    -- Non-lockdown failure: PARTY (premade groups inside instances), then a
    -- whisper to each member.
    if inInstanceGroup then
        ok, ret = sendFn(prefix, msg, "PARTY")
        if ok and ret == COMM_SUCCESS then return "sent" end
        if ok and ret == COMM_LOCKDOWN then
            state.commBlocked = true
            return "refused"
        end
    end
    for i = 1, #whisperTargets do
        local wok, wret = sendFn(prefix, msg, "WHISPER", whisperTargets[i])
        if wok and wret == COMM_LOCKDOWN then
            state.commBlocked = true
            return "refused"
        end
    end
    return "fanout"
end

-- The throttle damps HELLO reply loops. A forced HELLO (the lock lifting)
-- passes it; nothing passes the lock.
function KT.HelloAllowed(locked, lastSent, now, force, throttle)
    if locked then return false end
    if force or lastSent == nil then return true end
    return now - lastSent >= throttle
end

-- Fields 7-8 carry the player's talent-added kick (0 for none) and its
-- remaining time after the reply flag, so older clients, which split a fixed
-- number of fields, never read them.
function KT.EncodeHello(id, cd, remaining, noAnswer, extra, now)
    local extraID, extraRemaining = 0, 0
    if extra then
        extraID = extra.id
        if extra.kickStart and extra.kickDuration then
            extraRemaining = math.max(0, extra.kickStart + extra.kickDuration - now)
        end
    end
    return "1;HELLO;" .. id .. ";" .. cd .. ";" .. string.format("%.1f", remaining)
        .. ";" .. (noAnswer and "1" or "0")
        .. ";" .. extraID .. ";" .. string.format("%.1f", extraRemaining)
end

-- A new main kick or spec asks teammates to answer; a change to the
-- talent-added kick alone gives them nothing to answer.
function KT.OwnKickHello(mainChanged, specChanged, extrasChanged)
    if mainChanged or specChanged then return "ask" end
    if extrasChanged then return "tell" end
    return nil
end

---------------------------------------------------------------------------------
-- Pairing a KICK message with a nameplate interrupt
---------------------------------------------------------------------------------
-- Interrupts are anonymous (the kicker may be hidden), so a pairing is
-- made only when exactly one candidate sits on the other side of the window.
-- Both tables are keyed by teammate and kick, so a mirrored or repeated
-- message pairs once while a teammate's second, different kick still pairs.
local function dropOlder(map, now, window)
    for key, at in pairs(map) do
        if now - at > window then map[key] = nil end
    end
end

function KT.PairComm(pairing, entries, key, now, window)
    dropOlder(pairing.claims, now, window)
    dropOlder(pairing.paired, now, window)
    if pairing.claims[key] or pairing.paired[key] then return "duplicate" end

    local found, count = nil, 0
    for i = 1, #entries do
        if now - entries[i].startTime <= window then
            count = count + 1
            found = i
        end
    end
    if count == 1 then
        pairing.paired[key] = now
        return "claimed", found
    end
    if count == 0 then
        pairing.claims[key] = now
        return "opened"
    end
    pairing.paired[key] = now
    return "ambiguous"
end

-- True, and the claim's key, when the interrupt just arrived is the kick an
-- open claim announced; the claim is used up.
function KT.PairRecord(pairing, now, window)
    dropOlder(pairing.claims, now, window)
    dropOlder(pairing.paired, now, window)
    local only, count = nil, 0
    for key in pairs(pairing.claims) do
        count = count + 1
        only = key
    end
    if count ~= 1 then return false end
    pairing.paired[only] = pairing.claims[only]
    pairing.claims[only] = nil
    return true, only
end

-- Keys are guid..":"..kickID.
function KT.PairKeyGuid(key)
    return key:match("^(.*):[^:]*$")
end

---------------------------------------------------------------------------------
-- Sync or feed mode
---------------------------------------------------------------------------------
-- The new mode and what the switch requires: "start" on the first
-- evaluation, "enter-feed" / "enter-sync" on a switch, nil when unchanged.
function KT.CommModeStep(oldMode, locked)
    local mode = locked and "feed" or "sync"
    if oldMode == nil then return mode, "start" end
    if oldMode == mode then return mode, nil end
    return mode, (mode == "feed") and "enter-feed" or "enter-sync"
end

-- Every member with a kick has a row, in either mode.
function KT.RowShown(member)
    return member.interruptData ~= nil
end

---------------------------------------------------------------------------------
-- Sender identity
---------------------------------------------------------------------------------
-- The teammate an addon message came from. The realm-qualified key decides;
-- the short name is used only when exactly one teammate carries it, which
-- covers a realm whose display name and message name normalize differently.
-- fullKey and shortName are stored only when plain (RefreshPartyRoster).
function KT.MemberForSender(members, senderKey, shortName)
    local byShort, shortCount = nil, 0
    for guid, member in pairs(members) do
        if member.unit ~= "player" then
            if senderKey and member.fullKey == senderKey then
                return guid, member
            end
            if shortName and member.shortName == shortName then
                shortCount = shortCount + 1
                byShort = guid
            end
        end
    end
    if shortCount == 1 then return byShort, members[byShort] end
    return nil
end

---------------------------------------------------------------------------------
-- The player's true cooldown
---------------------------------------------------------------------------------
-- Flat seconds come off first, then multipliers apply; never below zero.
function KT.TalentedCooldown(baseCd, mods, isKnown)
    if not mods then return baseCd end
    local cd, mult = baseCd, 1
    for i = 1, #mods do
        local m = mods[i]
        if isKnown(m.talent) then
            if m.seconds then cd = cd - m.seconds end
            if m.multiplier then mult = mult * m.multiplier end
        end
    end
    cd = cd * mult
    if cd < 0 then cd = 0 end
    return cd
end

---------------------------------------------------------------------------------
-- Messages to row state
---------------------------------------------------------------------------------
-- The remaining-time field of HELLO: nil when absent or unreadable (the row
-- keeps its state), 0 when ready, otherwise capped at the cooldown.
function KT.ParseHelloRemaining(field, cd)
    if field == nil then return nil end
    local remaining = tonumber(field)
    if remaining == nil or remaining ~= remaining then return nil end
    if remaining <= 0 then return 0 end
    if cd and remaining > cd then return cd end
    return remaining
end

-- A message's bar: the cooldown it is sized by (the message's own, else the
-- row's) and the remaining time capped at that same cooldown, so the bar
-- never starts in the future.
function KT.MessageBarTimes(field, cd, rowCd)
    local duration = cd or rowCd
    return duration, KT.ParseHelloRemaining(field, duration)
end

-- "start" the full cooldown, "set" a remaining time, "ready", or "keep".
-- The second return is true when an R moved the row: that stamp makes a KICK
-- inside the window keep the shorter time instead of restarting it.
function KT.CooldownFromMessage(verb, remaining, reducedAt, now, window)
    if verb == "KICK" then
        if reducedAt and now - reducedAt <= window then return "keep", false end
        return "start", false
    end
    if remaining == nil then return "keep", false end
    local action = remaining <= 0 and "ready" or "set"
    return action, verb == "R"
end

-- Once a message has set or cleared a teammate's kick, their kick comes only
-- from their messages; spec data never re-guesses it, a respec included.
function KT.KeepsMessageKick(member)
    return member.kickFromMessage == true
end

-- What a message does to the sender's main kick: "set" when it names one (a
-- positive spell and cooldown that is not a talent-added kick), "clear" for a
-- KE HELLO naming spell 0 (the sender has no kick now), nil to keep it. A
-- BliZzi HELLO or a KICK carrying 0 never clears. An R only moves the timer of
-- the kick the row has; the KICK before it named that kick.
function KT.KickFromMessage(verb, isKE, sid, cd, extra)
    if extra or verb == "R" then return nil end
    if sid and sid > 0 and cd and cd > 0 then return "set" end
    if verb == "HELLO" and isKE and sid == 0 then return "clear" end
    return nil
end

-- How to answer a KE HELLO, from its reply flag (field 6): "0" asks for an
-- answer, sent even inside the throttle; "1" (a reply, or a change to the
-- talent-added kick alone) gets none. A HELLO without the flag comes from an
-- older client, which cannot mark its own replies, so it is answered only
-- under the throttle: answering it at once would let two clients answer each
-- other every throttle period.
function KT.HelloReplyMode(replyFlag)
    if replyFlag == "0" then return "force" end
    if replyFlag == "1" then return nil end
    return "throttled"
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
-- a talent-added kick is an entry in member.extraKicks. A teammate has at most
-- one: no spec has two talent-added kicks at once (the warrior throws are an
-- exclusive choice), so a different kick replaces the entry.
function KT.ExtraKick(member, kickID, cd)
    local list = member.extraKicks
    if list and list[1] and list[1].id == kickID then
        list[1].cd = cd
        return list[1]
    end
    local entry = { id = kickID, cd = cd }
    member.extraKicks = { entry }
    return entry
end

-- HELLO fields 7-8 on receive. An older sender has no field 7, and an ID that
-- is not a talent-added kick names nothing; both leave the entry. The
-- cooldown is the table's. Returns true when the entry was set or cleared.
function KT.HelloExtras(member, extraField, remField, getExtra, now)
    if extraField == nil then return false end
    local id = tonumber(extraField)
    if not id or id % 1 ~= 0 then return false end
    if id == 0 then
        local had = member.extraKicks ~= nil
        member.extraKicks = nil
        return had
    end
    local known = getExtra(id)
    if not known then return false end
    local entry = KT.ExtraKick(member, id, known.cd)
    local remaining = KT.ParseHelloRemaining(remField, known.cd)
    if remaining == 0 then
        entry.kickStart, entry.kickDuration = nil, nil
    elseif remaining then
        entry.kickStart, entry.kickDuration = now - (known.cd - remaining), known.cd
    end
    return true
end

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

-- What only a teammate's messages keep true: verification, talent-added
-- kicks and reduction stamps. Dropped whenever their messages cannot
-- arrive: a ready talent-added kick kept past them would read Ready over a
-- cooldown the game credited (KT.PickRowKick). The player's own stay.
function KT.DropMessageState(members)
    for _, member in pairs(members) do
        if member.unit ~= "player" then
            member.kickVerified = nil
            member.extraKicks = nil
            member.reducedAt = nil
        end
    end
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

-- A talented cooldown is never above the table cooldown, so the cap removes
-- only bad input; an unknown kick gets a flat 60 s.
function KT.WireCooldownCap(cd, tableCap)
    local limit = tableCap or 60
    if cd > limit then return limit end
    return cd
end

-- Wire numbers are untrusted. A spell ID must be a whole number (x % 1 is NaN
-- for NaN and infinity) and a cooldown above zero, or the field reads as
-- absent. A KICK or R needs both or is dropped; a HELLO is kept, since spell 0
-- is its "no kick" and a bad cooldown falls back to the row's own.
function KT.CleanWireKick(verb, sid, cd)
    if sid and sid % 1 ~= 0 then sid = nil end
    if cd and (cd ~= cd or cd <= 0) then cd = nil end
    if verb ~= "HELLO" and not (sid and sid > 0 and cd) then return false end
    return true, sid, cd
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

-- The player's kick cast and an interrupt whose kicker the game hid are one
-- kick when the interrupt lands inside the window. The claim is used up either
-- way, so one cast never claims two interrupts.
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
-- Who kicked, from the Damage Meter's interrupt list
---------------------------------------------------------------------------------
local function shortOf(name)
    return (name:gsub("%-.*$", ""))
end

-- A plain name, without its realm, is the key; when the name is secret, the
-- class, spec icon and local flag stand in for it. A repeated key gets "#n":
-- it names a position, not a person.
function KT.KeyMeterEntries(list)
    local seen = {}
    for i = 1, #list do
        local entry = list[i]
        local base = entry.name and shortOf(entry.name)
            or (entry.class .. ":" .. tostring(entry.icon) .. (entry.me and ":me" or ""))
        seen[base] = (seen[base] or 0) + 1
        entry.key = (seen[base] > 1) and (base .. "#" .. seen[base]) or base
    end
    return list
end

-- One kick updates the Current session once, so a second Current update in
-- one burst means more than one kick, even when a rollover gives it a new ID,
-- and one read cannot tell which added the new entry. seen holds the burst's
-- state. The Overall session (ID 0) updates beside every Current update, so
-- it never counts; an unreadable ID may be either, so it counts.
function KT.SessionRepeats(seen, sessionID, idSecret)
    if not idSecret and sessionID == 0 then return false end
    local repeated = seen.current == true
    seen.current = true
    return repeated
end

-- The list's order is readable in combat, its amounts are not: a kick adds
-- its kicker to the list or moves them up. A one-entry list names its entry;
-- else one newcomer names its kicker, else one climber does, else nobody.
function KT.DiffMeter(old, list)
    if #list == 1 then return list[1] end
    if not old then return nil end
    local oldIndex = {}
    for i = 1, #old do oldIndex[old[i].key] = i end
    local newcomer, climber, newCount, climbCount = nil, nil, 0, 0
    for i = 1, #list do
        local entry = list[i]
        local was = oldIndex[entry.key]
        if not was then
            newcomer, newCount = entry, newCount + 1
        elseif i < was then
            climber, climbCount = entry, climbCount + 1
        end
    end
    if newCount == 1 then return newcomer end
    if newCount == 0 and climbCount == 1 then return climber end
    return nil
end

-- Adds to out every member this meter entry could be and returns how many it
-- added. A spec icon rules out only a member whose spec is known; iconOf
-- gives that spec's icon, or nil.
function KT.MatchMember(entry, members, iconOf, out)
    local added = 0
    for guid, member in pairs(members) do
        local isPlayer = member.unit == "player"
        local ok
        if entry.me == true then
            ok = isPlayer
        else
            ok = member.matchClass == entry.class and (entry.me == nil or entry.me == isPlayer)
            if ok and entry.name and member.shortName then
                ok = shortOf(entry.name) == member.shortName
            end
            if ok and entry.icon and member.specID and member.specID > 0 then
                local icon = iconOf(member.specID)
                if icon and icon ~= entry.icon then ok = false end
            end
        end
        if ok and not out[guid] then
            out[guid] = true
            added = added + 1
        end
    end
    return added
end

-- Who one read names. reads holds, Current then Overall, each list's diffed
-- entry (nil when it named nobody) and the list (nil when unreadable). An
-- entry matching one member names them. Otherwise the first entry matching
-- several narrows the candidates to those; until then each list without an
-- entry widens them by every member its entries match. A shared read (two
-- kicks in one read) names nobody and only widens. Returns the owner's guid
-- or nil, then the candidate set or nil.
function KT.MeterKicker(reads, members, iconOf, shared)
    local cands, narrowed = {}, false
    for i = 1, #reads do
        local read = reads[i]
        local entry = not shared and read.entry or nil
        if entry then
            local mine = {}
            if KT.MatchMember(entry, members, iconOf, mine) == 1 then
                return next(mine), mine
            end
            if next(mine) and not narrowed then
                cands, narrowed = mine, true
            end
        elseif read.list and not narrowed then
            for j = 1, #read.list do
                KT.MatchMember(read.list[j], members, iconOf, cands)
            end
        end
    end
    if not next(cands) then return nil, nil end
    return nil, cands
end

-- Interrupts and meter reports pair oldest first, a report with an interrupt
-- within window of it. A report older than that has no interrupt left and
-- goes; an interrupt older than that has no report and is dropped; either one
-- past expire goes unpaired. A report with extra > 0 pairs that many more
-- interrupts. onPair(entry, hit) and onDrop(entry) are told.
function KT.PairKicks(pendings, hits, now, expire, window, onPair, onDrop)
    while pendings[1] and now - pendings[1].startTime > expire do
        onDrop(table.remove(pendings, 1))
    end
    while hits[1] and now - hits[1].at > expire do table.remove(hits, 1) end
    while pendings[1] and hits[1] do
        local entry, hit = pendings[1], hits[1]
        local gap = entry.startTime - hit.at
        if gap > window then
            table.remove(hits, 1)
        elseif gap < -window then
            onDrop(table.remove(pendings, 1))
        else
            table.remove(pendings, 1)
            if (hit.extra or 0) > 0 then
                hit.extra = hit.extra - 1
                hit.paired = true
            else
                table.remove(hits, 1)
            end
            onPair(entry, hit)
        end
    end
end

-- A read's report shares itself only among interrupts already waiting. Once
-- that pass ends, a report that paired leaves with its spare capacity, or a
-- later interrupt would take it before its own report; one that paired
-- nothing waits as a single report.
function KT.SettleReport(hits, hit)
    if hit.paired then
        for i = 1, #hits do
            if hits[i] == hit then
                table.remove(hits, i)
                return
            end
        end
        return
    end
    hit.extra = 0
end

local function partyIndex(member)
    return tonumber(member.unit and member.unit:match("^party(%d)$")) or 99
end

local function busyUntil(member, now)
    local start, duration = member.kickStart, member.kickDuration
    if start and duration and now - start < duration then return start + duration end
    return nil
end

local function guessBefore(a, b, now)
    local untilA, untilB = busyUntil(a, now), busyUntil(b, now)
    if (untilA ~= nil) ~= (untilB ~= nil) then return untilB ~= nil end
    if untilA then
        if untilA ~= untilB then return untilA < untilB end
    else
        local cdA, cdB = a.interruptData.cd, b.interruptData.cd
        if cdA ~= cdB then return cdA < cdB end
    end
    return partyIndex(a) < partyIndex(b)
end

-- While a synced teammate's messages can arrive, they drive the row
-- (KT.RowTakesKick), so a guess never lands there.
function KT.GuessKicker(members, cands, allowBusy, now, heard)
    local best, bestMember
    for guid, member in pairs(members) do
        if member.unit ~= "player" and KT.RowTakesKick(member, heard)
            and (not cands or cands[guid])
            and (allowBusy or not busyUntil(member, now))
            and (not bestMember or guessBefore(member, bestMember, now)) then
            best, bestMember = guid, member
        end
    end
    return best
end

-- Returns the guessed guid and its tier (1 to 3), or nil. The meter's
-- candidates outrank the ready-or-busy bookkeeping: a busy candidate beats a
-- ready outsider.
function KT.GuessTarget(members, cands, now, heard)
    local guid = KT.GuessKicker(members, cands, false, now, heard)
    if guid then return guid, 1 end
    if not cands then return nil end
    guid = KT.GuessKicker(members, cands, true, now, heard)
    if guid then return guid, 2 end
    guid = KT.GuessKicker(members, nil, false, now, heard)
    if guid then return guid, 3 end
    return nil
end

-- What a claim (a teammate's KICK or the player's cast) does beyond moving
-- the kicked spell: "hold" an interrupt still waiting for its meter report,
-- so it is never charged; "handback" a guess placed on another row.
function KT.ClaimEffect(entry, claimerGuid)
    if entry.state == "pending" then return "hold" end
    if entry.state == "guessed" and entry.guess and entry.guess.guid ~= claimerGuid then
        return "handback"
    end
    return nil
end

-- Restores a guessed row only while it still holds the guess's charge. Two
-- backdated charges in one frame share a start time, so the charge number
-- decides too. Returns true when it restored.
function KT.HandBackGuess(member, guess)
    if not member or not guess then return false end
    if member.kickStart ~= guess.start or member.chargeID ~= guess.charge then return false end
    local prior = guess.prior
    member.kickStart, member.kickDuration, member.kicked = prior.kickStart, prior.kickDuration, prior.kicked
    member.chargeID = prior.chargeID
    return true
end

-- The interrupt came first: the newest claimable interrupt with a hidden
-- kicker inside the window is the player's own kick, unless the meter already
-- put it on a teammate's row. Entries are in time order.
function KT.OwnInterruptIndex(entries, now, window)
    for i = #entries, 1, -1 do
        local entry = entries[i]
        if now - entry.startTime > window then return nil end
        if entry.hidden and entry.claimable and entry.state ~= "fold" then return i end
    end
    return nil
end

-- A teammate's row takes a kick the game or the meter credits to them when
-- they have a kick, unless they sync and their messages can arrive: their
-- messages then drive the row.
function KT.RowTakesKick(member, messagesHeard)
    return member.interruptData ~= nil and not (member.kickVerified and messagesHeard)
end

