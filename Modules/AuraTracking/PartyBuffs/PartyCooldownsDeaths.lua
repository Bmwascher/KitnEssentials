-- ╔══════════════════════════════════════════════════════════╗
-- ║  PartyCooldownsDeaths.lua                                ║
-- ║  Purpose: each group member's death, for the cells an    ║
-- ║           ally's death cuts.                             ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- Both events only schedule a scan of the group's units: UNIT_DIED fires for
-- every unit, mobs included, and neither payload is read. The ticker scans
-- once a second as well, so a death no event reports is still seen.

---@class KE
local KE = select(2, ...)

local C_Timer = C_Timer
local CreateFrame = CreateFrame
local UnitExists = UnitExists
local UnitIsConnected = UnitIsConnected
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsFeignDeath = UnitIsFeignDeath
local ipairs = ipairs
local issecretvalue = issecretvalue
local pcall = pcall
local type = type
local wipe = wipe

local Rules = KE.PartyCooldownsRules
local Track = KE.PartyCooldownsSensor

local Deaths = {}
KE.PartyCooldownsDeaths = Deaths

local UNITS = { "player", "party1", "party2", "party3", "party4" }
local EVENTS = { "UNIT_DIED", "CHALLENGE_MODE_DEATH_COUNT_UPDATED" }

-- Token -> true (dead) or false (alive), from the last read that could tell.
Deaths.states = {}
Deaths.on = false
Deaths.seen, Deaths.cuts = 0, 0

-- The scheduled next-frame scan; Off cancels it, so no callback outlives the
-- watch that scheduled it.
local frame, onDeath, scanTimer

-- A seed scan forgets every state first and only records: a token can name
-- someone else after a roster change, even where its read cannot tell. A
-- token that names nobody forgets its state.
function Deaths.Scan(seed)
    if not Deaths.on then return end
    local states = Deaths.states
    if seed then wipe(states) end
    for _, token in ipairs(UNITS) do
        local okExists, exists = pcall(UnitExists, token)
        if okExists and not issecretvalue(exists) then
            if not exists then
                states[token] = nil
            else
                local okConn, conn = pcall(UnitIsConnected, token)
                local okDead, dead = pcall(UnitIsDeadOrGhost, token)
                local okFeign, feign = pcall(UnitIsFeignDeath, token)
                local read = Rules.DeathRead(okConn, conn, okDead, dead, okFeign, feign, issecretvalue)
                if Rules.NoteDeath(states, token, read) and not seed then
                    Deaths.seen = Deaths.seen + 1
                    -- A refused GUID read leaves the row match to the token.
                    local okGUID, guid = pcall(KE.GetSafeUnitGUID, KE, token)
                    local ok, cut = pcall(onDeath, token, okGUID and guid or nil)
                    if ok and type(cut) == "number" then Deaths.cuts = Deaths.cuts + cut end
                end
            end
        end
    end
end

local function RunScheduled()
    scanTimer = nil
    Deaths.Scan(false)
end

-- One scan for any number of deaths in a frame. The unit can still read alive
-- while the event dispatches.
local function OnEvent()
    if scanTimer then return end
    scanTimer = C_Timer.NewTimer(0, RunScheduled)
end

function Deaths.Second()
    Deaths.Scan(false)
end

-- The first scan only records: a member dead now died before the watch.
function Deaths.On(callback)
    onDeath = callback
    if Deaths.on then return end
    if not frame then
        frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", OnEvent)
    end
    for _, event in ipairs(EVENTS) do frame:RegisterEvent(event) end
    Deaths.on = true
    Track.onSecond = Deaths.Second
    Deaths.Scan(true)
end

function Deaths.Off()
    if not Deaths.on then return end
    Deaths.on = false
    if scanTimer then
        scanTimer:Cancel()
        scanTimer = nil
    end
    frame:UnregisterAllEvents()
    Track.onSecond = nil
    wipe(Deaths.states)
end
