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

---------------------------------------------------------------------------------
-- Pairing a KICK message with a nameplate record
---------------------------------------------------------------------------------
-- Records are anonymous (the kicker's name may be secret), so a pairing is
-- made only when exactly one candidate sits on the other side of the window.
-- Both tables are keyed by teammate and kick, so a mirrored or repeated
-- message pairs once while a teammate's second, different kick still pairs.
local function dropOlder(map, now, window)
    for key, at in pairs(map) do
        if now - at > window then map[key] = nil end
    end
end

function KT.PairComm(pairing, records, key, now, window)
    dropOlder(pairing.claims, now, window)
    dropOlder(pairing.paired, now, window)
    if pairing.claims[key] or pairing.paired[key] then return "duplicate" end

    local found, count = nil, 0
    for i = 1, #records do
        if now - records[i].startTime <= window then
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

-- True when the record about to be created is the kick an open claim
-- announced; the claim is used up.
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
    return true
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

-- A teammate row needs messages to stay true, so feed mode keeps only the
-- player's own row.
function KT.RowShown(member, mode)
    if not member.interruptData or not member.kickVerified then return false end
    return member.unit == "player" or mode ~= "feed"
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

-- "start" the full cooldown, "set" a remaining time, "ready", or "keep".
function KT.CooldownFromMessage(verb, remaining)
    if verb == "KICK" then return "start" end
    if remaining == nil then return "keep" end
    if remaining <= 0 then return "ready" end
    return "set"
end

-- Once a message has set or cleared a teammate's kick, their kick comes only
-- from their messages; spec data never re-guesses it, a respec included.
function KT.KeepsMessageKick(member)
    return member.kickFromMessage == true
end

-- What a message does to the sender's main kick: "set" when it names one (a
-- positive spell and cooldown that is not a talent-added kick), "clear" for a
-- KE HELLO naming spell 0 (the sender has no kick now), nil to keep it. A
-- BliZzi HELLO or a KICK carrying 0 never clears.
function KT.KickFromMessage(verb, isKE, sid, cd, extra)
    if extra then return nil end
    if sid and sid > 0 and cd and cd > 0 then return "set" end
    if verb == "HELLO" and isKE and sid == 0 then return "clear" end
    return nil
end

-- How to answer a KE HELLO, from its reply flag (field 6): "0" asks for an
-- answer, sent even inside the throttle; "1" is a reply and gets none. A
-- HELLO without the flag comes from an older client, which cannot mark its
-- own replies, so it is answered only under the throttle: answering it at once
-- would let two clients answer each other every throttle period.
function KT.HelloReplyMode(replyFlag)
    if replyFlag == "0" then return "force" end
    if replyFlag == "1" then return nil end
    return "throttled"
end

---------------------------------------------------------------------------------
-- Record marker
---------------------------------------------------------------------------------
-- A record is a kick no synced teammate claimed. The mark is its own text
-- after the name, so no string is built from a name that may be secret.
function KT.MarkerFor(isRecord, showName)
    if isRecord and showName then return "*" end
    return ""
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



