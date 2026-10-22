-- ╔══════════════════════════════════════════════════════════╗
-- ║  VersionCheck.lua                                        ║
-- ║  Module: Version Check                                   ║
-- ║  Purpose: Tells other copies in the guild and group our  ║
-- ║           version, and notices when a newer one is out.  ║
-- ║  Configured from the Home page General card.             ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class VersionCheck: AceModule, AceEvent-3.0
local VC = KitnEssentials:NewModule("VersionCheck", "AceEvent-3.0")

local type, tonumber = type, tonumber

local MAX_VERSION_LEN = 12
local REPLY_CHANNELS = { GUILD = true, PARTY = true, RAID = true, INSTANCE_CHAT = true }

-- Success and DuplicatePrefix both leave the prefix registered.
local PREFIX_RESULT = Enum and Enum.RegisterAddonMessagePrefixResult
local PREFIX_SUCCESS = PREFIX_RESULT and PREFIX_RESULT.Success or 0
local PREFIX_DUPLICATE = PREFIX_RESULT and PREFIX_RESULT.DuplicatePrefix or 1

---------------------------------------------------------------------------------
-- Decisions (pure; no WoW API)
---------------------------------------------------------------------------------

function VC.IsUsableVersion(v)
    return type(v) == "string" and #v <= MAX_VERSION_LEN
        and v:match("^%d[%d%.]*$") ~= nil
end

function VC.ParseMessage(text)
    if type(text) ~= "string" then return nil end
    return text:match("^V:(%d[%d%.]*)$")
end

-- A version more than one major ahead of ours is a forged or broken message.
function VC.IsPlausible(theirs, mine)
    if not VC.IsUsableVersion(theirs) or not VC.IsUsableVersion(mine) then return false end
    local theirsMajor = tonumber(theirs:match("^%d+")) or 0
    local mineMajor = tonumber(mine:match("^%d+")) or 0
    return theirsMajor <= mineMajor + 1
end

-- A checkout copy's own version runs ahead of every release, so it announces
-- the last release instead; nil means this copy stays silent.
function VC.SpokenVersion(isDevCopy, mine, lastRelease)
    local spoken = mine
    if isDevCopy then spoken = lastRelease end
    if VC.IsUsableVersion(spoken) then return spoken end
    return nil
end

function VC.CanSend(locked, spoken)
    return not locked and VC.IsUsableVersion(spoken)
end

-- Newer is judged against the installed version; replies and cancels against
-- the version this copy announces.
function VC.HeardAction(theirs, mine, spoken, channel)
    if KE:CompareVersions(theirs, mine) > 0 then
        return VC.IsPlausible(theirs, mine) and "newer" or "ignore"
    end
    if not spoken then return "ignore" end
    if KE:CompareVersions(theirs, spoken) >= 0 then return "cancel" end
    if REPLY_CHANNELS[channel] then return "reply" end
    return "ignore"
end

function VC.NewestAbove(mine, a, b)
    local best
    if VC.IsUsableVersion(a) then best = a end
    if VC.IsUsableVersion(b) and (not best or KE:CompareVersions(b, best) > 0) then best = b end
    if best and KE:CompareVersions(best, mine) > 0 then return best end
    return nil
end

function VC.GroupChannel(inHomeRaid, inHomeGroup, inInstanceGroup)
    if inHomeRaid then return "RAID" end
    if inHomeGroup then return "PARTY" end
    if inInstanceGroup then return "INSTANCE_CHAT" end
    return nil
end

function VC.ShouldNotify(notified, showNotice, newer)
    return not notified and showNotice == true and newer ~= nil
end

function VC.PrefixHeld(ok, result)
    return ok == true and (result == PREFIX_SUCCESS or result == PREFIX_DUPLICATE)
end
