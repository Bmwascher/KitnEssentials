-- ╔══════════════════════════════════════════════════════════╗
-- ║  Context.lua                                              ║
-- ║  Module: KE.Context                                       ║
-- ║  Purpose: Shared context gate. Reads the context facts    ║
-- ║           on each edge and tells every subscriber when    ║
-- ║           it enters or leaves the place it applies to.    ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

-- Loaded before Main.lua creates the addon object, so this file must not
-- return early on its absence.

local setmetatable = setmetatable
local pairs = pairs
local next = next
local type = type
local pcall = pcall
local xpcall = xpcall

local SPEC_EVENT = "PLAYER_SPECIALIZATION_CHANGED"

-- IsInInstance can still describe the previous zone just after a zone edge,
-- so the facts are read again this long after the last one.
local SETTLE_DELAY = 1

local GROUPS = {
    zone  = { events = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }, settles = true },
    group = { events = { "GROUP_ROSTER_UPDATE" } },
    key   = { events = { "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_RESET" } },
    -- Its one event is unit-filtered and shared with the spec listeners.
    spec  = { events = {} },
}

local EVENT_GROUP = {}
for name, group in pairs(GROUPS) do
    for i = 1, #group.events do
        EVENT_GROUP[group.events[i]] = name
    end
end

local UNKNOWN_ANSWER = { open = true, closed = false }

-- Stock Lua 5.1's xpcall, which the specs run on, passes no arguments, so
-- predicates and spec listeners run through these without a closure per call.
-- Each reads its upvalues before it starts, so a nested run cannot disturb it.
---@type fun(facts: KE.ContextFacts): boolean?
local runPredicate
---@type KE.ContextFacts
local runFacts
local function CallPredicate()
    return runPredicate(runFacts)
end

---@type fun(event: string, unit: string)
local runSpecListener
local function CallSpecListener()
    runSpecListener(SPEC_EVENT, "player")
end

---------------------------------------------------------------------------------
-- Facts
---------------------------------------------------------------------------------

-- An error, a secret or a value of the wrong type all read as nil.
local function Usable(isSecret, value, kind)
    if isSecret(value) or type(value) ~= kind then return nil end
    return value
end

local function ReadOne(deps, fn, kind)
    local ok, value = pcall(fn)
    if not ok then return nil end
    return Usable(deps.issecretvalue, value, kind)
end

local READERS = {
    zone = function(deps, facts)
        local ok, inInstance, instanceType = pcall(deps.isInInstance)
        if ok then
            facts.inInstance = Usable(deps.issecretvalue, inInstance, "boolean")
            facts.instanceType = Usable(deps.issecretvalue, instanceType, "string")
        else
            facts.inInstance, facts.instanceType = nil, nil
        end
        local infoOk, _, _, difficultyID = pcall(deps.getInstanceInfo)
        facts.difficultyID = infoOk and Usable(deps.issecretvalue, difficultyID, "number") or nil
    end,
    group = function(deps, facts)
        facts.inGroup = ReadOne(deps, deps.isInGroup, "boolean")
        facts.inRaid = ReadOne(deps, deps.isInRaid, "boolean")
    end,
    key = function(deps, facts)
        facts.keyActive = ReadOne(deps, deps.isChallengeModeActive, "boolean")
    end,
    spec = function(deps, facts)
        facts.specID = ReadOne(deps, deps.specID, "number")
    end,
}

---------------------------------------------------------------------------------
-- Machine
---------------------------------------------------------------------------------

---@class KE.Context
local Context = {}
Context.__index = Context

--- deps:
---   isInInstance()           inInstance, instanceType
---   getInstanceInfo()        the third return is the difficulty ID
---   isInGroup(), isInRaid()  boolean
---   isChallengeModeActive()  boolean
---   specID()                 the player's spec ID
---   issecretvalue(v)         boolean
---   newTimer(sec, fn)        one-shot handle with :Cancel()
---   createFrame()            the frame the edge events register on
---   geterrorhandler()        the handler callback errors are reported through
function Context.New(deps)
    local self = setmetatable({}, Context)
    self.deps = deps
    self.facts = {}
    self.subs = {}
    self.specListeners = {}
    self.refs = { zone = 0, group = 0, key = 0, spec = 0 }
    self.frame = nil
    self.specRegistered = false
    self.settleHandle = nil
    self.onSettle = function()
        self.settleHandle = nil
        self:_EvaluateAll()
    end
    return self
end

function Context:_Frame()
    local frame = self.frame
    if not frame then
        frame = self.deps.createFrame()
        frame:SetScript("OnEvent", function(_, event, unit) self:_OnEvent(event, unit) end)
        self.frame = frame
    end
    return frame
end

function Context:_Call(fn)
    if fn then xpcall(fn, self.deps.geterrorhandler()) end
end

function Context:_SyncSpecEvent()
    local want = self.refs.spec > 0 or next(self.specListeners) ~= nil
    if want == self.specRegistered then return end
    self.specRegistered = want
    if want then
        self:_Frame():RegisterUnitEvent(SPEC_EVENT, "player")
    else
        self:_Frame():UnregisterEvent(SPEC_EVENT)
    end
end

function Context:_AddRef(name)
    local refs = self.refs
    refs[name] = refs[name] + 1
    if refs[name] > 1 then return end
    local events = GROUPS[name].events
    for i = 1, #events do
        self:_Frame():RegisterEvent(events[i])
    end
    if name == "spec" then self:_SyncSpecEvent() end
end

-- Outside an edge the snapshot can be stale (a zone read waiting for its
-- settle, or a group nobody kept current), so a subscriber deciding on its
-- own reads the game afresh.
function Context:_ReadNeeds(sub)
    local deps, facts, needs = self.deps, self.facts, sub.needs
    for i = 1, #needs do
        READERS[needs[i]](deps, facts)
    end
end

function Context:_DropRef(name)
    local refs = self.refs
    refs[name] = refs[name] - 1
    if refs[name] > 0 then return end
    local events = GROUPS[name].events
    for i = 1, #events do
        self:_Frame():UnregisterEvent(events[i])
    end
    if name == "spec" then self:_SyncSpecEvent() end
end

function Context:_CancelSettleIfIdle()
    if next(self.subs) ~= nil then return end
    local settle = self.settleHandle
    if settle then settle:Cancel() end
    self.settleHandle = nil
end

-- Called once the subscription is out of the table, so a leave callback that
-- subscribes the same key installs a fresh one instead of reviving this one.
function Context:_Teardown(sub)
    if sub.active then
        sub.active = false
        self:_Call(sub.onLeave)
    end
    local needs = sub.needs
    for i = 1, #needs do
        self:_DropRef(needs[i])
    end
end

function Context:_Run(sub)
    runPredicate, runFacts = sub.predicate, self.facts
    -- A throwing predicate is a code defect, not an unreadable place: it is
    -- reported, and the subscriber's own answer for "cannot tell" applies.
    local ok, answer = xpcall(CallPredicate, self.deps.geterrorhandler())
    local inside
    if not ok or answer == nil then
        inside = sub.unknownAnswer
    else
        inside = answer and true or false
    end
    if inside == sub.active then return end
    sub.active = inside
    if inside then
        self:_Call(sub.onEnter)
    else
        self:_Call(sub.onLeave)
    end
end

function Context:_EvaluateAll()
    local deps, facts = self.deps, self.facts
    for name, count in pairs(self.refs) do
        if count > 0 then READERS[name](deps, facts) end
    end
    local pass = {}
    for _, sub in pairs(self.subs) do
        pass[#pass + 1] = sub
    end
    for i = 1, #pass do
        local sub = pass[i]
        -- A callback earlier in this pass may have removed or replaced it.
        if self.subs[sub.key] == sub then self:_Run(sub) end
    end
end

-- Restarted by every zone edge, so the settled read follows the last one.
function Context:_RestartSettle()
    local settle = self.settleHandle
    if settle then settle:Cancel() end
    self.settleHandle = self.deps.newTimer(SETTLE_DELAY, self.onSettle)
end

function Context:_DispatchSpec()
    READERS.spec(self.deps, self.facts)
    local keys = {}
    for key in pairs(self.specListeners) do
        keys[#keys + 1] = key
    end
    local handler = self.deps.geterrorhandler()
    for i = 1, #keys do
        local fn = self.specListeners[keys[i]]
        if fn then
            runSpecListener = fn
            xpcall(CallSpecListener, handler)
        end
    end
    if self.refs.spec > 0 then self:_EvaluateAll() end
end

function Context:_OnEvent(event, unit)
    if event == SPEC_EVENT then
        -- RegisterUnitEvent already limits this to the player; the check keeps
        -- another unit's change from reaching a listener if one arrives.
        if unit ~= "player" then return end
        self:_DispatchSpec()
        return
    end
    local name = EVENT_GROUP[event]
    if not name then return end
    if GROUPS[name].settles then self:_RestartSettle() end
    -- On the event itself: a subscriber entering a frame later would miss
    -- its own events that fire in between, such as a cast and its interrupt.
    self:_EvaluateAll()
end

---------------------------------------------------------------------------------
-- Public surface
---------------------------------------------------------------------------------

-- Refused rather than defaulted: without onUnknown the helper would be
-- choosing between fail-open and fail-closed for the subscriber.
function Context:Subscribe(key, options)
    if type(key) ~= "string" or type(options) ~= "table"
        or type(options.predicate) ~= "function" or type(options.needs) ~= "table"
        or UNKNOWN_ANSWER[options.onUnknown] == nil then
        return false
    end
    local needs = {}
    for i = 1, #options.needs do
        local name = options.needs[i]
        if not GROUPS[name] then return false end
        needs[i] = name
    end
    local sub = {
        key = key,
        needs = needs,
        predicate = options.predicate,
        onEnter = options.onEnter,
        onLeave = options.onLeave,
        unknownAnswer = UNKNOWN_ANSWER[options.onUnknown],
        active = false,
    }
    local old = self.subs[key]
    self.subs[key] = sub
    for i = 1, #needs do
        self:_AddRef(needs[i])
    end
    self:_ReadNeeds(sub)
    -- The replacement holds its references before the old one drops its own,
    -- so a group both need stays registered. The old leave callback may
    -- replace or remove the new subscription; it then does not run here.
    if old then self:_Teardown(old) end
    if self.subs[key] == sub then self:_Run(sub) end
    return true
end

function Context:Unsubscribe(key)
    local sub = self.subs[key]
    if not sub then return end
    self.subs[key] = nil
    self:_Teardown(sub)
    self:_CancelSettleIfIdle()
end

function Context:IsActive(key)
    local sub = self.subs[key]
    return sub ~= nil and sub.active
end

function Context:Evaluate(key)
    local sub = self.subs[key]
    if not sub then return end
    self:_ReadNeeds(sub)
    self:_Run(sub)
end

function Context:SubscribeSpec(key, fn)
    if type(key) ~= "string" or type(fn) ~= "function" then return false end
    self.specListeners[key] = fn
    self:_SyncSpecEvent()
    return true
end

function Context:UnsubscribeSpec(key)
    if self.specListeners[key] == nil then return end
    self.specListeners[key] = nil
    self:_SyncSpecEvent()
end

---------------------------------------------------------------------------------
-- Live adapter
---------------------------------------------------------------------------------

-- Each global resolves when called: KE:GetPlayerSpecId is defined by
-- Globals.lua, which loads after this file.
KE.Context = Context.New({
    isInInstance = function() return IsInInstance() end,
    getInstanceInfo = function() return GetInstanceInfo() end,
    isInGroup = function() return IsInGroup() end,
    isInRaid = function() return IsInRaid() end,
    isChallengeModeActive = function() return C_ChallengeMode.IsChallengeModeActive() end,
    specID = function() return KE:GetPlayerSpecId() end,
    issecretvalue = function(value) return issecretvalue(value) end,
    newTimer = function(seconds, fn) return C_Timer.NewTimer(seconds, fn) end,
    createFrame = function() return CreateFrame("Frame") end,
    geterrorhandler = function() return geterrorhandler() end,
})
