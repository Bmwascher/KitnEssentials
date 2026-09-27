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
