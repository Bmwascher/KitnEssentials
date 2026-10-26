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

local type, tonumber, tostring = type, tonumber, tostring
local string_format = string.format
local math_random = math.random
local C_AddOns = C_AddOns
local C_ChatInfo = C_ChatInfo
local C_Timer = C_Timer
local IsInGuild, IsInGroup, IsInRaid = IsInGuild, IsInGroup, IsInRaid
local GetNumGroupMembers = GetNumGroupMembers
local LE_HOME = LE_PARTY_CATEGORY_HOME
local LE_INSTANCE = LE_PARTY_CATEGORY_INSTANCE

local DEBUG_VC = false

-- The version a checkout copy announces. Release commits set it, and the
-- commit-msg hook refuses any value that is not a released version.
local LAST_RELEASE = "4.15.1"

local PREFIX = "KEVersion"
local HELLO_DELAY = 10
local NOTICE_DELAY = 6
local REPLY_MIN = 2
local REPLY_SPREAD = 6
local MAX_VERSION_LEN = 12
local REPLY_CHANNELS = { GUILD = true, PARTY = true, RAID = true, INSTANCE_CHAT = true }
local SEND_LOCKDOWN = Enum and Enum.SendAddonMessageResult
    and Enum.SendAddonMessageResult.AddOnMessageLockdown or 11

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

---------------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------------

local sessionLatest
local helloTimer
local helloGuild = false
local replyTimers = {}
local groupSize = 0
local unlockArmed = false
local unlockCheckPending = false

local function Log(fmt, ...)
    if DEBUG_VC then KE:Print("VersionCheck: " .. string_format(fmt, ...)) end
end

---------------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------------

local ArmUnlockWatch

-- Returns true when the send was refused with AddOnMessageLockdown.
local function Send(channel)
    local locked = KE:IsChatMessagingLocked()
    if not VC.CanSend(locked, VC.spoken) then
        Log("send to %s refused (spoken: %s, locked: %s)", channel, tostring(VC.spoken), tostring(locked))
        return false
    end
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, "V:" .. VC.spoken, channel)
    Log("sent V:%s to %s (ok: %s, result: %s)", VC.spoken, channel, tostring(ok), tostring(result))
    if ok and result == SEND_LOCKDOWN then
        ArmUnlockWatch()
        return true
    end
    return false
end

local function Hello()
    if KE:IsChatMessagingLocked() then
        Log("hello deferred: chat locked")
        ArmUnlockWatch()
        return
    end
    -- A lockdown refusal keeps the guild flag, so the retry after the unlock
    -- still reaches guild for a player who is not grouped.
    if helloGuild and IsInGuild() and Send("GUILD") then return end
    helloGuild = false
    local channel = VC.GroupChannel(IsInRaid(LE_HOME), IsInGroup(LE_HOME), IsInGroup(LE_INSTANCE))
    if channel then Send(channel) end
end

local function HelloSoon(withGuild)
    helloGuild = helloGuild or withGuild
    if helloTimer then return end
    helloTimer = C_Timer.NewTimer(HELLO_DELAY, function()
        helloTimer = nil
        Hello()
    end)
end

-- Core/Secret.lua records the restriction change in its own handler, so the
-- lock is read a frame later. The Core restriction listener is not used: it
-- does not fire when only the Chat restriction changes.
local function OnRestrictionChanged()
    if unlockCheckPending then return end
    unlockCheckPending = true
    C_Timer.After(0, function()
        unlockCheckPending = false
        if not unlockArmed or KE:IsChatMessagingLocked() then return end
        unlockArmed = false
        VC:UnregisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
        Log("chat unlocked: hello scheduled")
        HelloSoon(false)
    end)
end

function ArmUnlockWatch()
    if unlockArmed then return end
    unlockArmed = true
    VC:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", OnRestrictionChanged)
end

local function CancelReply(channel)
    local timer = replyTimers[channel]
    if timer then
        timer:Cancel()
        replyTimers[channel] = nil
        Log("reply on %s canceled", tostring(channel))
    end
end

local function ReplySoon(channel)
    if replyTimers[channel] then return end
    local delay = REPLY_MIN + math_random() * REPLY_SPREAD
    replyTimers[channel] = C_Timer.NewTimer(delay, function()
        replyTimers[channel] = nil
        Send(channel)
    end)
    Log("reply on %s in %.1f s", tostring(channel), delay)
end

---------------------------------------------------------------------------------
-- Notice
---------------------------------------------------------------------------------

function KE:GetNewerVersion()
    if not VC.mine then return nil end
    local db = VC.db
    return VC.NewestAbove(VC.mine, sessionLatest, db and db.LatestHeard)
end

local function Notify()
    local db = VC.db
    local newer = KE:GetNewerVersion()
    if not newer then return end
    if not VC.ShouldNotify(VC.notified, db ~= nil and db.ShowNotice ~= false, newer) then return end
    VC.notified = true
    KE:Print("Version |cff7fff7f" .. newer .. "|r is available - you have |cffff7f7f"
        .. VC.mine .. "|r. Update through CurseForge or Wago.")
end

local function Remember(version)
    if not sessionLatest or KE:CompareVersions(version, sessionLatest) > 0 then
        sessionLatest = version
    end
    local db = VC.db
    if db and (not VC.IsUsableVersion(db.LatestHeard)
        or KE:CompareVersions(version, db.LatestHeard) > 0) then
        db.LatestHeard = version
    end
end

-- The Welcome card is built with the page, so Home rebuilds when it is the
-- selected page; RefreshContent only marks it dirty while the window is
-- hidden, and the next open replays it.
local function RefreshWindow()
    local gui = KE.GUIFrame
    if not gui then return end
    if gui.RefreshVersionText then gui:RefreshVersionText() end
    if gui.selectedSidebarItem == "HomePage" and gui.RefreshContent then gui:RefreshContent() end
end

local function LoginNotice()
    local db = VC.db
    if db and db.LatestHeard ~= nil and (not VC.IsUsableVersion(db.LatestHeard)
        or KE:CompareVersions(db.LatestHeard, VC.mine) <= 0) then
        db.LatestHeard = nil
    end
    Notify()
end

---------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------

function VC:OnAddonMessage(_, prefix, text, channel)
    if issecretvalue(prefix) or issecretvalue(text) or issecretvalue(channel) then return end
    if prefix ~= PREFIX then return end
    local theirs = VC.ParseMessage(text)
    if not theirs then return end
    local action = VC.HeardAction(theirs, self.mine, self.spoken, channel)
    Log("heard V:%s on %s: %s", theirs, tostring(channel), action)
    if action == "newer" then
        Remember(theirs)
        CancelReply(channel)
        Notify()
        RefreshWindow()
    elseif action == "reply" then
        ReplySoon(channel)
    elseif action == "cancel" then
        CancelReply(channel)
    end
end

function VC:OnGroupRosterUpdate()
    local n = GetNumGroupMembers()
    if n > 1 and n > groupSize then HelloSoon(false) end
    groupSize = n
end

function VC:OnPlayerEnteringWorld()
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    groupSize = GetNumGroupMembers()
    HelloSoon(true)
    C_Timer.After(NOTICE_DELAY, LoginNotice)
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------

-- Never disabled: the Home page switch hides only the chat notice, and the
-- version messages keep running with it off.
function VC:OnInitialize()
    self.db = KE.db and KE.db.global and KE.db.global.VersionCheck
    local raw = C_AddOns and C_AddOns.GetAddOnMetadata
        and C_AddOns.GetAddOnMetadata("KitnEssentials", "Version")
    self.isDevCopy = type(raw) ~= "string" or raw:find("@", 1, true) ~= nil
    self.mine = VC.IsUsableVersion(KE.Version) and KE.Version or nil
    self.spoken = VC.SpokenVersion(self.isDevCopy, self.mine, LAST_RELEASE)
end

function VC:OnEnable()
    if not self.mine then return end
    if not (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) then return end
    local ok, result = pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    if not VC.PrefixHeld(ok, result) then
        Log("prefix not registered (ok: %s, result: %s)", tostring(ok), tostring(result))
        return
    end
    self:RegisterEvent("CHAT_MSG_ADDON", "OnAddonMessage")
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnGroupRosterUpdate")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
end
