-- ╔══════════════════════════════════════════════════════════╗
-- ║  ChatHistory.lua                                         ║
-- ║  Module: Persistent Chat History                         ║
-- ║  Purpose: Keep covered chat lines per character and      ║
-- ║           replay them at login with their own timestamps ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local CH = KitnEssentials:NewModule("ChatHistory", "AceEvent-3.0")

-- The chat skin installs the AddMessage override that honours the replay
-- marker, so this module stands down when the skin is off.
local CHAT = KitnEssentials:GetModule("Chat", true)

-- `strfind` through `_G` because it is NOT in the project's .luacheckrc
-- read_globals list, unlike `strsub` and `strlen` beside it. Every sibling in
-- this folder does the same; a bare `strfind` is an undefined-global warning
-- and Step 7 expects zero.
--
-- This block holds ONLY what this task's code uses. Task 4 extends it.
local _G = _G
local pairs, pcall, select, type = pairs, pcall, select, type
local tinsert, tremove, wipe = tinsert, tremove, wipe
local strfind = _G.strfind
local IsInInstance = IsInInstance
local GetServerTime = GetServerTime
local time = time

-- Event to chat type. The type is what the user's per-type toggle keys off; an
-- event absent from this map is not covered and is never stored.
--
-- CHAT_MSG_GUILD_ACHIEVEMENT is deliberately absent. The message handler routes
-- achievement chat types into a branch that takes neither the history marker
-- nor its timestamp, and hands the line to the achievement merge cache.
local HISTORY_TYPES = {
    CHAT_MSG_WHISPER              = "WHISPER",
    CHAT_MSG_WHISPER_INFORM       = "WHISPER",
    CHAT_MSG_BN_WHISPER           = "WHISPER",
    CHAT_MSG_BN_WHISPER_INFORM    = "WHISPER",
    CHAT_MSG_GUILD                = "GUILD",
    CHAT_MSG_OFFICER              = "OFFICER",
    CHAT_MSG_PARTY                = "PARTY",
    CHAT_MSG_PARTY_LEADER         = "PARTY",
    CHAT_MSG_RAID                 = "RAID",
    CHAT_MSG_RAID_LEADER          = "RAID",
    CHAT_MSG_RAID_WARNING         = "RAID",
    CHAT_MSG_INSTANCE_CHAT        = "INSTANCE",
    CHAT_MSG_INSTANCE_CHAT_LEADER = "INSTANCE",
    CHAT_MSG_CHANNEL              = "CHANNEL",
    CHAT_MSG_SAY                  = "SAY",
    CHAT_MSG_YELL                 = "YELL",
    CHAT_MSG_EMOTE                = "EMOTE",
}
CH.HISTORY_TYPES = HISTORY_TYPES

-- The handler replays at most seventeen positional arguments. The eighteenth is
-- a Blizzard structure whose string fields cannot be checked with
-- issecretvalue, so it is neither stored nor replayed.
local MAX_ARGS = 17

-- The chat skin's edit box keeps fifty lines of Up/Down recall; the saved half
-- keeps the same number so the two cannot disagree about what "the last fifty"
-- means.
local TYPING_CAP = 50

function CH:UpdateDB()
    self.db = KE.db.profile.Skinning.ChatHistory
end

local function Store()
    local char = KE.db and KE.db.char
    if not char then return nil end
    if type(char.ChatHistory) ~= "table" then char.ChatHistory = {} end
    return char.ChatHistory
end
CH.Store = Store

-- Nothing received inside an instance is written to disk. The upstream this
-- feature is modelled on has no such rule; it is the phase's own requirement.
--
-- ASKED AT THE MOMENT OF THE DECISION, not cached. A cache would have to assume
-- something about which events fire at an instance boundary and in what order
-- relative to a chat message, and none of that is established anywhere this
-- project can read. An unverifiable assumption is not an acceptable foundation
-- for the one rule this phase exists to keep, and the call it replaces is a
-- trivial C function -- far cheaper than the string work already on this path.
--
-- It fails CLOSED, which is the opposite of how a cosmetic caller would write
-- it: a throw, a nil, or a return that cannot be read all count as "inside".
-- Only an explicit, readable false is open world. The cost of being wrong in
-- the other direction is a permanent write of something that should never have
-- left memory.
function CH:InsideInstance()
    local ok, inInstance = pcall(IsInInstance)
    -- issecretvalue is first contact, before the nil comparison: comparing a
    -- secret is the thing that throws.
    if not ok or KE:IsSecretValue(inInstance) or inInstance == nil then
        if not self._warnedInstanceState then
            self._warnedInstanceState = true
            KE:Print("Chat History: cannot tell whether you are in an instance, so nothing is being saved.")
        end
        return true
    end
    self._warnedInstanceState = nil
    return inInstance ~= false
end

-- Cheaper than the reference's gsub and strictly wider: any |K refuses, even
-- one with no closing |k. Wider and cheaper is the right trade for a rule about
-- writing to disk, and unlike the gsub it allocates nothing per message.
local function BodyIsUnsafe(body)
    if KE:IsSecretValue(body) then return true end
    if type(body) ~= "string" or body == "" then return true end
    return strfind(body, "|K", 1, true) ~= nil
end
CH.BodyIsUnsafe = BodyIsUnsafe

function CH:ShouldStore(event)
    if not self.db or not self.db.Enabled then return false end

    -- The cheap refusals first, so an unwanted message never reaches the two
    -- calls below.
    local historyType = HISTORY_TYPES[event]
    if not historyType then return false end

    local showTypes = self.db.ShowTypes
    if showTypes and showTypes[historyType] == false then return false end

    return self:IsPersistenceActive()
end

-- Packs the event arguments into a dense array of scalars, truncated at the
-- last one that carries anything. A nil hole, and anything that is not a
-- string, number or boolean, becomes false.
--
-- Every field is tested with issecretvalue, not just the body: a message can
-- arrive with plain text and a secret sender. One secret field anywhere refuses
-- the whole row. KE:HasSecretValues does NOT do this -- it calls a method only
-- Blizzard payload objects have, so on a plain table it returns nil and the row
-- would be stored.
function CH:PackRow(event, ...)
    local count = select("#", ...)
    if count > MAX_ARGS then count = MAX_ARGS end
    if count == 0 then return nil end

    -- Refuse before allocating: a rejected message costs one substring scan and
    -- no table.
    if BodyIsUnsafe((select(1, ...))) then return nil end

    local row = {}
    local last = 0
    for i = 1, count do
        local value = select(i, ...)
        if KE:IsSecretValue(value) then return nil end

        local kind = type(value)
        if kind == "string" or kind == "number" or kind == "boolean" then
            row[i] = value
            if value ~= false then last = i end
        else
            row[i] = false
        end
    end

    -- Trailing dead arguments are dropped. How much that saves is not known
    -- and may be nothing: CHAT_MSG_SAY declares all seventeen of its payload
    -- fields non-nilable, so a real line can fill every slot. A truncated tail
    -- reads back as nil, which every consumer treats the same as the false it
    -- replaces.
    for i = count, last + 1, -1 do row[i] = nil end
    if last == 0 then return nil end

    -- No issecretvalue on `event`: it cannot be secret here. ShouldStore has
    -- already hash-matched it against a HISTORY_TYPES literal key, which a
    -- secret value cannot do, and RowIsReplayable checks it again on the way
    -- back out. Every other packed scalar is checked in the loop above.
    row.event = event

    -- The timestamp is STORED, so it is checked like everything else that is
    -- stored: issecretvalue before type, and no `and/or` around either return.
    -- `GetServerTime and GetServerTime() or time()` truth-tests the return
    -- value, and a truth test is a read. Whether this API can return a secret
    -- is UNVERIFIED; a row that cannot be stamped with a plain number is
    -- refused rather than persisted and sorted out at replay time.
    local stamp
    if GetServerTime then stamp = GetServerTime() end
    if KE:IsSecretValue(stamp) then return nil end
    if type(stamp) ~= "number" then
        -- Fallback only. The checks are nested rather than repeated flat, so a
        -- normal message pays ONE issecretvalue on its timestamp, not two.
        if not time then return nil end
        stamp = time()
        if KE:IsSecretValue(stamp) then return nil end
        if type(stamp) ~= "number" then return nil end
    end
    row.time = stamp

    return row
end

function CH:SaveChatHistory(event, ...)
    if not self:ShouldStore(event) then return end

    local data = Store()
    if not data then return end

    local row = self:PackRow(event, ...)
    if not row then return end

    tinsert(data, row)

    -- `>` not `>=`: the slider's number is the number of rows kept.
    local cap = self.db.Size or 100
    while #data > cap do
        tremove(data, 1)
    end
end

-- The typed-line half of the store. It lives on this module rather than inline
-- in the chat skin's hook so the guard is one function with its own tests: the
-- hook calls this and does nothing else about persistence.
function CH:RecordTypedLine(text)
    -- issecretvalue before anything reads the value, `#text` included: taking
    -- the length is itself a read. Whether an edit box can hold a secret is
    -- UNVERIFIED, and a fail-closed design does not persist an unverified value
    -- to find out.
    if KE:IsSecretValue(text) then return false end
    if type(text) ~= "string" or text == "" then return false end
    if not self:IsPersistenceActive() then return false end

    local char = KE.db and KE.db.char
    if not char then return false end
    if type(char.ChatTypingHistory) ~= "table" then char.ChatTypingHistory = {} end

    tinsert(char.ChatTypingHistory, text)
    while #char.ChatTypingHistory > TYPING_CAP do
        tremove(char.ChatTypingHistory, 1)
    end

    return true
end

function CH:ClearHistory()
    local data = Store()
    if data then wipe(data) end

    local char = KE.db and KE.db.char
    if char and type(char.ChatTypingHistory) == "table" then wipe(char.ChatTypingHistory) end

    -- The live list too, or the button throws away the saved copy while every
    -- edit box still recalls the same lines. CHAT.TypingHistory is the table
    -- the edit boxes point at.
    if CHAT and type(CHAT.TypingHistory) == "table" then wipe(CHAT.TypingHistory) end
end

-- Only the wanted events are registered. A type the user switched off should
-- cost nothing at all, not be filtered per message.
function CH:RegisterHistoryEvents()
    local showTypes = self.db and self.db.ShowTypes
    for event, historyType in pairs(HISTORY_TYPES) do
        if not (showTypes and showTypes[historyType] == false) then
            self:RegisterEvent(event, "SaveChatHistory")
        end
    end

end

-- Called whenever the set of wanted events may have changed. It asks only
-- whether the module should be LISTENING, never where the player is: an
-- instance is a per-message refusal, not a reason to tear down registrations
-- that would then have to be rebuilt on the way out.
--
-- Idempotent by construction — it unregisters everything and rebuilds from the
-- current db — which is what lets ApplySettings below call it freely.
function CH:RefreshEvents()
    self:UnregisterAllEvents()
    if not self.db or not self.db.Enabled then return end
    self:RegisterHistoryEvents()
end

-- The house hook for "settings may have changed under you". Without it a
-- profile switch that leaves this module ENABLED under both profiles keeps the
-- OLD profile's registrations: ProfileManager refreshes db and flips enable
-- state only on a mismatch, and calls ApplySettings on everything else. A type
-- the new profile turns on would go uncaptured until a reload, and a type it
-- turns off would keep paying dispatch for a message this module then refuses.
function CH:ApplySettings()
    self:RefreshEvents()
end

-- The single predicate everything asks before writing anything to disk. Fail
-- closed: every unknown answers no.
--
-- ChatSkinActive is asked HERE, live, rather than once at OnEnable. Module
-- enable order is `pairs()` order, so this module can start before the chat
-- skin does, and the skin can be switched off later while this module is still
-- running. Asking at the moment of the decision covers both, and it is the same
-- reason InsideInstance is not cached.
function CH:IsPersistenceActive()
    -- IsEnabled first and cheapest: an Ace-disabled module with db.Enabled still
    -- true would otherwise authorise the typing writes in Chat.lua, which do not
    -- go through this module's own event handlers.
    if self.IsEnabled and not self:IsEnabled() then return false end
    if not self.db or not self.db.Enabled then return false end
    if not self:ChatSkinActive() then return false end
    if self:InsideInstance() then return false end
    return true
end

-- The replay marker is honoured by the chat skin's AddMessage override, which
-- only exists while that module runs. Without it every replayed line would be
-- stamped with the login time instead of its own.
function CH:ChatSkinActive()
    return CHAT and CHAT.IsEnabled and CHAT:IsEnabled() and true or false
end

function CH:OnInitialize()
    self:UpdateDB()
    -- Literal false: without it AceAddon auto-enables the module and KE's own
    -- login pass then runs against a module the user has switched off.
    self:SetEnabledState(false)
end

function CH:ScheduleReplay() end

-- Deliberately NOT gated on the chat skin here. Module enable order is
-- `pairs()` order, so this can run before the Chat module does, and AceAddon
-- does not re-run OnEnable when a sibling starts later. The skin check lives in
-- IsPersistenceActive, which every write asks.
function CH:OnEnable()
    if not self.db then self:UpdateDB() end
    if not self.db.Enabled then return end

    self:RegisterHistoryEvents()
    self:ScheduleReplay()
end

function CH:OnDisable()
    self:UnregisterAllEvents()
end
