-- ╔══════════════════════════════════════════════════════════╗
-- ║  CombatState.lua                                          ║
-- ║  Module: KE.CombatState                                   ║
-- ║  Purpose: One shared combat clock/liveness machine, fed   ║
-- ║           by a private event frame, that the Combat Timer ║
-- ║           and the Damage Meter both read instead of each  ║
-- ║           keeping (and disagreeing on) their own state.   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

-- This file is loaded by Core/Core.xml before Main.lua creates the
-- `KitnEssentials` AceAddon global. Only the addon-private `KE` namespace
-- and bare WoW globals are used here. Do NOT add an
-- `if not KitnEssentials then return end` guard: that is a module-file
-- pattern, and this file sits above Main.lua in the manifest, so the guard
-- would early-return and leave `KE.CombatState` nil for the whole session.

local CreateFrame = CreateFrame
local GetTime = GetTime
local UnitAffectingCombat = UnitAffectingCombat
local IsInInstance = IsInInstance
local IsInRaid = IsInRaid
local IsInGroup = IsInGroup
local GetNumGroupMembers = GetNumGroupMembers
local issecretvalue = issecretvalue
local setmetatable = setmetatable
local pairs = pairs
local next = next
local select = select
local type = type
local pcall = pcall
local math_max = math.max
local math_min = math.min

-- Pre-built group unit tokens. UNIT_FLAGS can fire dozens of times per
-- second during a pull, and the poll ticker reads these every 0.25s;
-- building "raid"..i / "party"..i inline on each call would churn garbage.
local RAID_UNITS, PARTY_UNITS = {}, {}
for i = 1, 40 do RAID_UNITS[i] = "raid" .. i end
for i = 1, 4 do PARTY_UNITS[i] = "party" .. i end

-- StartFight sentinels. Internal only; never exposed on the public surface.
local PLAYER, GROUP = "PLAYER", "GROUP"

-- StartFight span mode. Internal only; the one caller that begins a new
-- underlying session passes it.
local SPAN_CARRY = "SPAN_CARRY"

---@class KE.CombatState
local CombatState = {}
CombatState.__index = CombatState

--- deps:
---   now()              seconds (GetTime); tenths smoothing only
---   playerInCombat()   boolean (UnitAffectingCombat("player"))
---   groupInCombat()    boolean
---   inInstance()       boolean (IsInInstance)
---   sessionDuration()  ok, raw -- the pcall'd C_DamageMeter read, unfiltered
---   after(sec, fn)     one-shot handle with :Cancel()
---   ticker(sec, fn)    recurring handle with :Cancel()
function CombatState.New(deps)
    local self = setmetatable({}, CombatState)
    self.deps = deps
    self.listeners = {}
    self.fineKeys = {}

    self.playerCombat = false
    self.groupOnly = false
    self.inEncounter = false
    self.pin = 0
    self.engagementBase = 0
    self.frozen = false
    self.generation = 0
    self.watching = false
    self.clearTicks = 0
    self.pvpBlocked = false
    self.finalizePending = false
    self.pendingGen = nil
    self.playerJoined = false
    self.fineBase = nil
    self.fineAnchor = nil

    self.clockHandle = nil
    self.pollHandle = nil

    return self
end

---------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------

function CombatState:IsLive()
    return self.playerCombat or self.groupOnly
end

-- The only place that reads the API, besides Freeze. The secrecy test comes
-- BEFORE type(): type() does not filter secret values, so a secret number
-- reaching the > 0 comparison throws.
function CombatState:Sample()
    local ok, raw = self.deps.sessionDuration()
    if not ok then return nil end
    if issecretvalue(raw) then return nil end
    if raw == nil then return nil end
    if type(raw) ~= "number" then return nil end
    if raw <= 0 then return nil end
    return raw
end

function CombatState:Duration()
    if self.pin > 0 then return self.pin end
    return nil
end

function CombatState:_CancelClock()
    if self.clockHandle then
        self.clockHandle:Cancel()
        self.clockHandle = nil
    end
end

function CombatState:_ClockCadence()
    if next(self.fineKeys) then return 0.1 end
    return 0.5
end

-- Cancel-before-start, per the paint contract: neither ticker can be doubled.
function CombatState:_StartClock()
    self:_CancelClock()
    local cadence = self:_ClockCadence()
    self.clockCadence = cadence
    self.clockHandle = self.deps.ticker(cadence, function()
        self:ClockTick()
    end)
end

function CombatState:_CancelPoll()
    if self.pollHandle then
        self.pollHandle:Cancel()
        self.pollHandle = nil
    end
end

function CombatState:_ArmPoll()
    self:_CancelPoll()
    self.pollHandle = self.deps.ticker(0.25, function()
        self:PollTick()
    end)
end

function CombatState:_Broadcast(event, a, b)
    for _, callbacks in pairs(self.listeners) do
        local fn = callbacks[event]
        if fn then fn(a, b) end
    end
end

---------------------------------------------------------------------------------
-- Freeze
---------------------------------------------------------------------------------

function CombatState:Freeze(reason)
    if not self:IsLive() then return end          -- inert: touches nothing at all
    local d = self:Sample()
    if d and d >= self.pin then self.pin = d end   -- keep the larger; Current may have rolled
    self.frozen = true
    self.playerCombat = false
    self.groupOnly = false
    self.clearTicks = 0
    self.finalizePending = false
    self.pendingGen = nil
    self:_CancelClock()
    self:_CancelPoll()
    self.watching = false
    self:_Broadcast("OnClockTick", self:Duration(), 0)    -- both surfaces land on the final value
    self:_Broadcast("OnStop", reason)
    if reason ~= "pvp" and self.deps.groupInCombat() then
        self.watching = true
        self:_ArmPoll()
    end
end

---------------------------------------------------------------------------------
-- Start and promote
---------------------------------------------------------------------------------

function CombatState:StartFight(which, span)
    local wasLive = self:IsLive()
    self:_CancelPoll()
    self:_CancelClock()
    self.frozen = false
    -- Only a start that begins a NEW session folds the outgoing fight in. A
    -- live start that re-asserts the fight already running would double-count:
    -- the pin is about to be re-sampled from the same session it was read from.
    local carried = wasLive and span == SPAN_CARRY
    if carried then
        self.engagementBase = self.engagementBase + (self.pin or 0)
    else
        self.engagementBase = 0
    end
    self.pin = 0
    self.fineBase = nil
    self.fineAnchor = nil
    self.clearTicks = 0
    self.finalizePending = false
    self.pendingGen = nil
    self.watching = false
    self.generation = self.generation + 1
    self.playerCombat = (which == PLAYER)      -- both assigned, never one
    self.groupOnly = (which == GROUP)
    -- Participation follows the span. A carried start continues one engagement,
    -- and the chat line it will report covers the seconds before this start, so
    -- a player who fought them has joined it even if the boss opened as GROUP.
    self.playerJoined = (which == PLAYER) or (carried and self.playerJoined) or false
    if self.groupOnly then self:_ArmPoll() end
    self:_StartClock()
    -- Fired only on a fresh start (not a live-to-live chain pull): otherwise a
    -- boss chain-pulled out of trash blanks both surfaces for up to 0.5s.
    -- OnStart first: it is where a consumer clears whatever it was holding, and
    -- a blank paint arriving before that can be routed by stale consumer state.
    -- Both still land in this one dispatch, so nothing is drawn in between.
    if not wasLive then
        self:_Broadcast("OnStart")
        self:_Broadcast("OnClockTick", nil, 0)
    end
end

-- The player joins a fight already running.
function CombatState:Promote()
    self.groupOnly = false
    self.playerCombat = true
    self.playerJoined = true
    -- The player entering combat disproves that the group stayed continuously
    -- clear, so a part-spent dwell must not carry over and cut the next drop short.
    self.clearTicks = 0
    self:_CancelPoll()
    -- pin, generation, fineBase and fineAnchor all SURVIVE: this is the same
    -- fight, so resetting them would rewind a clock already on screen.
end

---------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------

function CombatState:OnRegenDisabled()
    self.pvpBlocked = false
    if self:IsLive() and self.groupOnly then
        self:Promote()
        return
    end
    self:StartFight(PLAYER)
end

-- Always a segment boundary.
function CombatState:OnEncounterStart()
    self.inEncounter = true
    self:StartFight(self.deps.playerInCombat() and PLAYER or GROUP, SPAN_CARRY)
end

-- Cheap bails first; this fires constantly.
function CombatState:OnUnitFlags(unit)
    if self:IsLive() then return end
    if self.pvpBlocked then return end
    if not self.deps.inInstance() then return end
    if not unit or not (unit:match("^raid%d") or unit:match("^party%d")) then return end
    if not self.deps.groupInCombat() then return end   -- the up-to-41-unit scan, last
    self:StartFight(GROUP)
end

function CombatState:OnRegenEnabled()
    -- Captured before anything clears a flag, and never cleared before Freeze:
    -- Freeze is inert on a machine that is not live and clears both flags
    -- itself, so clearing here makes an ordinary solo fight never stop.
    local wasLive = self:IsLive()
    if not wasLive then
        -- pvpBlocked, or the 4 Hz scan restarts after a match on combat flags
        -- that stay stuck, undoing the suppression the PvP freeze just applied.
        if self.deps.groupInCombat() and not self.pvpBlocked then
            self.watching = true
            self:_ArmPoll()
        else
            self:_CancelPoll()
            self.watching = false
            self:_Broadcast("OnGroupClear")
        end
        return
    end
    if self.finalizePending then                -- a non-kill end owns the next freeze
        self.playerCombat = false
        self.groupOnly = true
        self:_ArmPoll()
        return
    end
    if not self.deps.groupInCombat() and not self.inEncounter then
        self:Freeze("combat")
        return
    end
    self.playerCombat = false
    self.groupOnly = true
    self:_ArmPoll()
end

function CombatState:OnEncounterEnd(success)
    self.inEncounter = false
    if not self:IsLive() then return end
    if success == 1 then
        self:Freeze("encounterEnd")
        return
    end
    self.finalizePending = true
    self.pendingGen = (self.pendingGen or 0) + 1
    -- CLOSURE-LOCAL, both of them. Comparing a shared field with itself
    -- always passes: callback A would read the token fight B had just
    -- written and pass its own check, then erase B's ownership.
    local myGen = self.generation
    local myPending = self.pendingGen
    self.deps.after(0.5, function()
        if myGen ~= self.generation then return end
        if myPending ~= self.pendingGen then return end
        self.finalizePending = false
        if self.frozen or not self:IsLive() then return end
        if self.deps.groupInCombat() then
            -- Do not demote a player who was rezzed and re-entered combat
            -- inside this 0.5s window back to groupOnly.
            if self.deps.playerInCombat() then
                self.playerCombat, self.groupOnly = true, false
            else
                self.playerCombat, self.groupOnly = false, true
            end
            self:_ArmPoll()
        else
            self:Freeze("encounterEndDelayed")
        end
    end)
end

function CombatState:OnPvPMatchComplete()
    self.inEncounter = false
    self.pvpBlocked = true
    self.finalizePending = false
    self.pendingGen = nil
    if self:IsLive() then
        self:Freeze("pvp")                     -- exempt from the watch re-arm
    else
        self:_CancelPoll()                     -- cancel a watch armed earlier,
        self.watching = false                  -- which an inert Freeze would not reach
    end
end

-- Re-derives rather than blindly resetting: the game does not re-fire
-- PLAYER_REGEN_DISABLED after a load screen.
function CombatState:OnEnteringWorld()
    self.finalizePending = false
    self.pendingGen = nil                      -- invalidate any pending callback
    if self.deps.playerInCombat() then
        if self:IsLive() and self.groupOnly then
            -- A world entry ends the engagement on BOTH arrival branches, not
            -- just the one that starts a fight. The fight itself survives here,
            -- so the pin stands and the clock does not rewind past it; what the
            -- screen ends is everything before it.
            self.engagementBase = 0
            self:Promote()
        else
            self:StartFight(PLAYER)
        end
    elseif self.deps.groupInCombat() and self.deps.inInstance() then
        self:StartFight(GROUP)
    else
        if self:IsLive() then self:Freeze("reset") end
        self.inEncounter = false
        self.pvpBlocked = false
        self.watching = false
        self.frozen = false                    -- so a surviving pinned clock is not dimmed after a zone change
        self:_CancelPoll()
        self:_CancelClock()
        -- pin SURVIVES: it is the Combat Timer's out-of-combat readout
    end
end

---------------------------------------------------------------------------------
-- The two tickers
---------------------------------------------------------------------------------

-- 0.5s, or 0.1s while a fine cadence is wanted.
function CombatState:ClockTick()
    local d = self:Sample()
    if d then
        self.pin = d
        if d ~= self.fineBase then             -- re-anchor only on a CHANGE: the API
            self.fineBase = d                  -- moves in whole seconds
            self.fineAnchor = self.deps.now()
        end
    end
    local frac = 0
    if self.fineAnchor then
        -- nil duration and frac 0 until the first usable sample: no anchor
        -- arithmetic ever happens without an anchor.
        frac = math_max(0, math_min(self.deps.now() - self.fineAnchor, 0.9))
    end
    self:_Broadcast("OnClockTick", self:Duration(), frac)
end

-- 0.25s.
function CombatState:PollTick()
    if not (self.groupOnly or self.watching) then
        self:_CancelPoll()
        return
    end
    if self.deps.groupInCombat() then
        self.clearTicks = 0
        return
    end
    if self.watching and not self:IsLive() then
        self:_CancelPoll()
        self.watching = false
        self:_Broadcast("OnGroupClear")
        return
    end
    if self.finalizePending then return end    -- the deferred callback owns the freeze
    if not self.inEncounter then
        self:Freeze("combat")
        return
    end
    self.clearTicks = self.clearTicks + 1
    if self.clearTicks >= 20 then              -- 5 seconds
        self.inEncounter = false
        self:Freeze("wedgeGuard")
    end
end

---------------------------------------------------------------------------------
-- Reading surface
---------------------------------------------------------------------------------

function CombatState:IsFrozen()
    return self.frozen
end

function CombatState:GetDuration()
    return self:Duration()
end

-- The engagement, not the fight. Non-nil where Duration() is nil once anything
-- has accumulated: the warm-up gap after a carry would otherwise blank a clock
-- that has a known span behind it.
function CombatState:GetEngagementDuration()
    if self.engagementBase > 0 then
        return self.engagementBase + (self:Duration() or 0)
    end
    return self:Duration()
end

-- True once playerCombat has been set at any point in the current engagement;
-- cleared at each start that opens a new one.
function CombatState:PlayerJoined()
    return self.playerJoined
end

function CombatState:GroupInCombat()
    return self.deps.groupInCombat()
end

function CombatState:Generation()
    return self.generation
end

-- Replaces a running clock ticker and samples at once, so a cadence change
-- cannot leave both surfaces stale for the length of the old interval.
function CombatState:_RestartClock()
    if not self.clockHandle then return end
    -- Idempotent: registering and dropping cadence keys happens in pairs around
    -- a module's enable and disable, and a restart that changes nothing would
    -- spend a session read and a repaint for each one.
    if self:_ClockCadence() == self.clockCadence then return end
    self:_StartClock()
    self:ClockTick()
end

-- Recording a preference must never start a ticker on an idle machine, or a
-- 10 Hz sampler runs forever between fights.
function CombatState:SetFineCadence(key, wanted)
    if wanted then
        self.fineKeys[key] = true
    else
        self.fineKeys[key] = nil
    end
    self:_RestartClock()
end

-- Keyed, so a module enabling and disabling repeatedly cannot stack
-- duplicates: registering an existing key replaces it.
function CombatState:RegisterListener(key, callbacks)
    self.listeners[key] = callbacks
end

function CombatState:UnregisterListener(key)
    self.listeners[key] = nil
    self.fineKeys[key] = nil
    self:_RestartClock()
end

---------------------------------------------------------------------------------
-- Live adapter
---------------------------------------------------------------------------------

local function LiveNow()
    return GetTime()
end

local function LivePlayerInCombat()
    return UnitAffectingCombat("player")
end

-- The player fast-path uses UnitAffectingCombat("player") rather than
-- InCombatLockdown(): InCombatLockdown() drops the moment the player dies or
-- feign-deaths mid-pull, while the unit flag stays true while they are still
-- tagged into the fight.
local function LiveGroupInCombat()
    if UnitAffectingCombat("player") then return true end

    if IsInRaid() then
        local n = GetNumGroupMembers()
        for i = 1, n do
            if UnitAffectingCombat(RAID_UNITS[i]) then return true end
        end
    elseif IsInGroup() then
        -- Party units exclude the player, so iterate one fewer than the count.
        local n = GetNumGroupMembers() - 1
        for i = 1, n do
            if UnitAffectingCombat(PARTY_UNITS[i]) then return true end
        end
    end

    return false
end

local function LiveInInstance()
    local inInstance = IsInInstance()
    return inInstance and true or false
end

-- pcall'd: SecretArguments is AllowedWhenUntainted, so the call itself can
-- reject. Returns the RAW result; every secrecy, type and range check lives
-- in the machine's Sample().
local SESSION_CURRENT = Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Current

local function LiveSessionDuration()
    -- The enum is part of the availability guard, not an argument built inside
    -- the pcall: indexing an absent Enum table is a hard error the pcall around
    -- the call itself would not catch, and this runs on every clock tick.
    if not (SESSION_CURRENT and C_DamageMeter and C_DamageMeter.GetSessionDurationSeconds) then
        return false, nil
    end
    local ok, dur = pcall(C_DamageMeter.GetSessionDurationSeconds, SESSION_CURRENT)
    return ok, dur
end

local function LiveAfter(sec, fn)
    return C_Timer.NewTimer(sec, fn)
end

local function LiveTicker(sec, fn)
    return C_Timer.NewTicker(sec, fn)
end

KE.CombatState = CombatState.New({
    now = LiveNow,
    playerInCombat = LivePlayerInCombat,
    groupInCombat = LiveGroupInCombat,
    inInstance = LiveInInstance,
    sessionDuration = LiveSessionDuration,
    after = LiveAfter,
    ticker = LiveTicker,
})

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("ENCOUNTER_START")
eventFrame:RegisterEvent("ENCOUNTER_END")
eventFrame:RegisterEvent("UNIT_FLAGS")
eventFrame:RegisterEvent("PVP_MATCH_COMPLETE")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_REGEN_DISABLED" then
        KE.CombatState:OnRegenDisabled()
    elseif event == "PLAYER_REGEN_ENABLED" then
        KE.CombatState:OnRegenEnabled()
    elseif event == "ENCOUNTER_START" then
        KE.CombatState:OnEncounterStart()
    elseif event == "ENCOUNTER_END" then
        -- success is the FIFTH vararg: (encounterID, name, difficulty, size, success).
        -- Getting this index wrong makes every boss kill read as a wipe.
        local success = select(5, ...)
        KE.CombatState:OnEncounterEnd(success)
    elseif event == "UNIT_FLAGS" then
        local unit = ...
        KE.CombatState:OnUnitFlags(unit)
    elseif event == "PVP_MATCH_COMPLETE" then
        KE.CombatState:OnPvPMatchComplete()
    elseif event == "PLAYER_ENTERING_WORLD" then
        KE.CombatState:OnEnteringWorld()
    end
end)
