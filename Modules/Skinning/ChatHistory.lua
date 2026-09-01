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
-- this folder does the same; a bare `strfind` is an undefined-global warning.
local _G = _G
local pairs, pcall, select, type = pairs, pcall, select, type
local tinsert, tremove, wipe = tinsert, tremove, wipe
local strfind = _G.strfind
local IsInInstance = IsInInstance
local GetServerTime = GetServerTime
local time = time
local ipairs = ipairs
local gsub, strsub, strmatch = _G.gsub, strsub, strmatch
local C_Timer = C_Timer

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

    -- A Battle.net whisper's argument 2 is a session-scoped |K token, not a
    -- name: the client resolves the embedded id to a name at DRAW time, and
    -- that id stops resolving to the right person once the session ends.
    -- Resolving it now, against the id the session that received it can still
    -- read, is the only way to store something that means the same thing
    -- later. The type check is not optional -- the loop above coerces
    -- anything that is not a string, number or boolean to false, and
    -- strsub(false, 1, 2) throws -- and it runs after that loop on purpose, so
    -- the value it tests has already passed the secrecy check every other
    -- argument gets.
    if type(row[2]) == "string" and strsub(row[2], 1, 2) == "|K" then
        local senderID = row[13]
        -- First contact with argument 13 in this branch is the secrecy check,
        -- not the `> 0` comparison two lines down; comparing a secret throws.
        if KE:IsSecretValue(senderID) then return nil end
        if type(senderID) ~= "number" or senderID <= 0 then return nil end

        local accountInfo = _G.C_BattleNet.GetAccountInfoByID(senderID)
        local tag = accountInfo and accountInfo.battleTag
        if KE:IsSecretValue(tag) then return nil end
        -- battleTag is non-nilable but can be "". An empty tag is refused like
        -- any other failed lookup rather than stored and left to break the
        -- replay fallback.
        if type(tag) ~= "string" or tag == "" then return nil end

        -- One field, one name. Nothing derived from accountName is ever
        -- stored: it carries the same kind of token this branch exists to
        -- keep off disk. row[2] is OVERWRITTEN, not supplemented, so nothing
        -- beginning with |K survives into the row this function returns.
        row.bnTag = tag
        row[2] = tag
    end

    -- Trailing dead arguments are dropped. How much that saves is not known
    -- and may be nothing: CHAT_MSG_SAY declares eighteen payload fields and
    -- every one of them non-nilable, and seventeen of those are what this
    -- module packs, so a real line can fill every slot. A truncated tail reads
    -- back as nil, which every consumer treats the same as the false it
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

-- The chat frames are not styled yet at OnEnable. One deferred pass rather than
-- a retry loop: nothing in this replay path needs a warm cache, because no
-- coloured name is stored, and a frame that is still absent would be skipped
-- anyway.
function CH:ScheduleReplay()
    -- Once per session, not once per enable. The GUI toggle disables and
    -- re-enables this module, and without the latch an off/on cycle would print
    -- the whole stored history into chat a second time.
    if self.replayed then return end
    self.replayed = true
    C_Timer.After(0, function() CH:DisplayChatHistory() end)
end

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

-- A row was safe when it was stored. It is re-checked on the way out because
-- the user's per-type toggles can have changed since, and because a stored
-- value can read secret in a session that the session which stored it did not.
function CH:RowIsReplayable(row)
    -- The row itself, before type() reads it. Rows come from SavedVariables and
    -- should be ordinary tables, so this is breadth rather than a known hole --
    -- but the premise the field checks below rest on is that a stored value can
    -- read secret in a later session, and that premise cannot stop at the
    -- container.
    if KE:IsSecretValue(row) then return false end
    if type(row) ~= "table" then return false end

    local event = row.event
    -- issecretvalue before type(), because the type check is the first read.
    if KE:IsSecretValue(event) then return false end
    if type(event) ~= "string" then return false end

    local historyType = HISTORY_TYPES[event]
    if not historyType then return false end

    local showTypes = self.db and self.db.ShowTypes
    if showTypes and showTypes[historyType] == false then return false end

    if BodyIsUnsafe(row[1]) then return false end

    -- The whole row, not just the body, and that includes the three named
    -- fields. The premise above is that a stored value can read secret in a
    -- later session; if that holds it holds for the timestamp, the event name
    -- and the stored BattleTag too. Login-only cost.
    -- The timestamp must be a readable number. A missing one makes
    -- CHAT:AddMessageEdits fall back to the login clock, which is the one thing
    -- replay exists to avoid, and a table would reach BetterDate and throw.
    if KE:IsSecretValue(row.time) then return false end
    if type(row.time) ~= "number" then return false end
    if KE:IsSecretValue(row.bnTag) then return false end
    for i = 2, MAX_ARGS do
        if KE:IsSecretValue(row[i]) then return false end
    end

    -- Rows written before this change stored the |K token itself in row[2].
    -- Its embedded id is dead -- the session that could resolve it is gone --
    -- so the name is genuinely unrecoverable, and the row is refused rather
    -- than replayed with a stranger's name. The type check is not optional:
    -- row[2] can be false, a number, or nil, and strsub(false, 1, 2) throws.
    -- Placed after the loop above so first contact with row[2] is the
    -- secrecy check, matching the ordering PackRow's own version requires.
    if type(row[2]) == "string" and strsub(row[2], 1, 2) == "|K" then return false end

    return true
end

-- Matches a stored BattleTag against today's friend list, so a replayed
-- Battle.net line reads exactly as the live line did instead of carrying a
-- dead session-scoped token. On a match, returns that friend's current
-- display name and id. On no match -- the friend list is not yet populated,
-- or the sender was removed -- returns the truncated tag and a nil id, which
-- the message handler reads as "emit no link" rather than one pointing at the
-- wrong friend.
local function ResolveBNSender(bnTag)
    local numFriends = _G.BNGetNumFriends and _G.BNGetNumFriends() or 0
    for i = 1, numFriends do
        local info = _G.C_BattleNet.GetFriendAccountInfo(i)
        if info and info.battleTag == bnTag then
            return info.accountName, info.bnetAccountID
        end
    end
    return strmatch(bnTag, "([^#]+)"), nil
end
CH.ResolveBNSender = ResolveBNSender

-- Pushes each stored row back through the handler with the marker
-- CHAT:AddMessageEdits looks for, so a replayed line carries the timestamp it
-- was received with rather than the login clock.
-- Not IsPersistenceActive: replay is a read, not a disk write, so being inside
-- an instance is irrelevant to it. What IS relevant is the chat skin, because
-- without CHAT:AddMessage installed the marker is ignored and every replayed
-- line would be stamped with the login time.
function CH:DisplayChatHistory()
    if not self.db or not self.db.Enabled then return end
    if not self:ChatSkinActive() then return end

    local data = Store()
    if not data or #data == 0 then return end

    local CMH = KE.ChatMessageHandler
    if not CMH or not CMH.ChatFrame_MessageEventHandler then return end

    local frames = _G.CHAT_FRAMES
    if type(frames) ~= "table" then return end

    -- One prepass, so the per-row work happens once instead of once per chat
    -- frame. The per-frame loop below then does comparisons only.
    --
    -- The BattleTag resolve runs here too, and ONLY when row.bnTag is present
    -- -- gated on that and nothing else. Gating on the event type instead
    -- looks equivalent and is not: a legacy Battle.net row refused above has
    -- no row.bnTag either, and the event-type gate would still send it into
    -- this resolve, which has nothing to match against a token.
    local rows, types, bnArg2, bnArg13, n = {}, {}, {}, {}, 0
    for i = 1, #data do
        local row = data[i]
        if self:RowIsReplayable(row) then
            n = n + 1
            rows[n] = row
            -- row.event is a plain string this module wrote, so this match is
            -- never run against secret text.
            types[n] = gsub(strsub(row.event, 10), "_INFORM", "")
            if row.bnTag ~= nil then
                bnArg2[n], bnArg13[n] = ResolveBNSender(row.bnTag)
            end
        end
    end
    if n == 0 then return end

    -- The frames are resolved and VALIDATED here too, in the same prepass and
    -- for a different reason: everything below runs with CMH.replaying up, and
    -- anything that throws up there escapes with the flag stuck on, muting
    -- every live whisper sound, keyword sound, tab flash, client-icon flash,
    -- text-to-speech line and reply-target write until the next reload. The
    -- per-dispatch pcall does not cover a throw outside the dispatch.
    --
    -- Both checks are `type(x) == "table"`, not truthiness. CHAT_FRAMES is a
    -- Blizzard global any addon can append to, so `_G[frameName]` can be a
    -- number or a boolean, and indexing one of those throws before any check on
    -- the field itself could run.
    --
    -- The wanted types are COPIED, not referenced. Dispatch runs third-party
    -- message filters, and one of those can reconfigure a chat frame while the
    -- replay is still walking the others -- so a list that was a table when
    -- checked here is not guaranteed to still be one, and iterating it in the
    -- window would throw with the mute flag up. Copying also type-checks each
    -- entry once per frame instead of once per row, which is what made
    -- checking them look expensive.
    local targets, wantedTypes, t = {}, {}, 0
    for _, frameName in ipairs(frames) do
        local chat = _G[frameName]
        if type(chat) == "table" and type(chat.messageTypeList) == "table" then
            local wanted, w = {}, 0
            for _, chatType in pairs(chat.messageTypeList) do
                -- issecretvalue before type(), the same first-contact rule as
                -- everywhere else: the type check is itself a read.
                if not KE:IsSecretValue(chatType) and type(chatType) == "string" then
                    w = w + 1
                    wanted[w] = chatType
                end
            end
            if w > 0 then
                t = t + 1
                targets[t] = chat
                wantedTypes[t] = wanted
            end
        end
    end
    if t == 0 then return end

    -- Protected PER DISPATCH, not once around the pass. A single throwing row
    -- must not silently abort every later row, and it must still reach the error
    -- handler -- a swallowed failure would hide a real defect behind a short
    -- replay.
    --
    -- pcall with the callee's arguments, NOT xpcall: WoW's Lua accepts
    -- xpcall(f, handler, ...) but stock Lua 5.1 does not forward the extra
    -- arguments, and the headless suite runs stock 5.1. The handler is called by
    -- hand on failure so the error still surfaces.
    --
    -- Fetched BEFORE the flag goes up, with everything else that can throw.
    local handler = geterrorhandler()

    -- The flag is cleared on EVERY exit, a throw included, because the pass runs
    -- inside its own pcall. The invariant is built rather than argued: an
    -- argument that nothing below can raise has been wrong here more than once,
    -- and this shape does not depend on one being right.
    --
    -- The inner per-dispatch pcall stays as well, doing a different job: one bad
    -- row must not abort the rows after it, and it must still reach the error
    -- handler. The outer one covers what the inner one is not wrapped around --
    -- which is not nothing. Lua evaluates the dispatch's ARGUMENTS before pcall
    -- takes over, so every `row.event`, `row[1..17]` and `row.time` read below
    -- happens inside the window and outside the inner pcall. Rows are
    -- references into saved variables, so those reads are not this module's to
    -- guarantee.
    CMH.replaying = true
    local swept, sweepErr = pcall(function()
        for j = 1, t do
            local chat = targets[j]
            local messageTypes = wantedTypes[j]
            for i = 1, n do
                local row = rows[i]
                local chatType = types[i]
                for k = 1, #messageTypes do
                    if messageTypes[k] == chatType then
                        -- Resolved values stand in for row[2]/row[13] only on
                        -- a Battle.net row; every other row passes its stored
                        -- fields through unchanged.
                        local arg2, arg13 = row[2], row[13]
                        if row.bnTag ~= nil then
                            arg2, arg13 = bnArg2[i], bnArg13[i]
                        end
                        local ok, err = pcall(CMH.ChatFrame_MessageEventHandler,
                            CMH, chat, row.event,
                            row[1], arg2, row[3], row[4], row[5], row[6],
                            row[7], row[8], row[9], row[10], row[11], row[12],
                            arg13, row[14], row[15], row[16], row[17], false,
                            "KE_ChatHistory", row.time)
                        -- pcall on the HANDLER too: geterrorhandler returns
                        -- whatever an error-grabber addon installed, and a
                        -- throwing one would be reached only on this path --
                        -- inside the window, after a dispatch already failed.
                        if not ok and handler then pcall(handler, err) end
                        break
                    end
                end
            end
        end
    end)

    CMH.replaying = false
    -- Surfaced, never swallowed. A structural failure in the pass is a real
    -- defect and hiding it behind a short replay is how it would stay one.
    if not swept and handler then pcall(handler, sweepErr) end
end
