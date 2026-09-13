-- ╔══════════════════════════════════════════════════════════╗
-- ║  MythicPlusTimer_Pull.lua                                ║
-- ║  Live pull estimate for the forces bar: the forces      ║
-- ║  weight of the exposed, engaged nameplates, summed by   ║
-- ║  chained StatusBars so a secret per-unit count never    ║
-- ║  meets Lua arithmetic. Feeds the HUD's pull sinks with  ║
-- ║  an opaque endpoint (MythicPlusTimer_HUD.lua).           ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end
local MPT = KitnEssentials:GetModule("MythicPlusTimer")

local DEBUG_PULL = false

local CreateFrame = CreateFrame
local C_NamePlate = C_NamePlate
local C_ScenarioInfo = C_ScenarioInfo
local C_StringUtil = C_StringUtil
local C_Timer = C_Timer
local GetTime = GetTime
local UnitExists = UnitExists
local UnitCanAttack = UnitCanAttack
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitThreatSituation = UnitThreatSituation
local UnitPlayerControlled = UnitPlayerControlled
local AbbreviateNumbers = AbbreviateNumbers
local CreateAbbreviateConfig = CreateAbbreviateConfig
local issecretvalue = issecretvalue or function() return false end
local wipe = wipe
local strfind = string.find
local type = type

local GetProgress = C_ScenarioInfo and C_ScenarioInfo.GetUnitCriteriaProgressValues

-- Ten builds per second at most.
local BUILD_INTERVAL = 0.1

---------------------------------------------------------------------------------
-- Public predicates (pure over module state; the spec targets)
---------------------------------------------------------------------------------

function MPT.PullEligible(db, run, isPreview)
    if not db or not run then return false end
    if not db.Enabled or db.ShowForces == false or db.ShowPullOverlay ~= true then return false end
    if isPreview or not run.active or run.completed then return false end
    local fo = run.forces
    if not fo or fo.completed then return false end
    local total = fo.total
    return type(total) == "number" and total > 0
end

-- Engagement selector. A secret threat result never reaches the nil test;
-- an unresolved unit is admitted only by a readable true player-controlled
-- target (player-controlled, not proven party-controlled).
function MPT.PullAdmits(unit)
    if not UnitExists(unit) then return false end
    local dead = UnitIsDeadOrGhost(unit)
    if issecretvalue(dead) or dead then return false end
    local attackable = UnitCanAttack("player", unit)
    if issecretvalue(attackable) or not attackable then return false end
    local threat = UnitThreatSituation("player", unit)
    if not issecretvalue(threat) and threat ~= nil then return true end
    local controlled = UnitPlayerControlled(unit .. "target")
    return (not issecretvalue(controlled)) and controlled == true
end

-- Which sink format the pull label uses, from the public forces format only.
function MPT.PullTextFormat(forcesFormat)
    if forcesFormat == "COUNT" or forcesFormat == "REMAINING" then return "COUNT" end
    if forcesFormat == "COUNT_PERCENT" then return "COUNT_PERCENT" end
    return "PERCENT"
end

---------------------------------------------------------------------------------
-- Membership snapshot
---------------------------------------------------------------------------------

local seen = {}

local function PlateToken(plate)
    local unit = plate.unitToken
    if type(unit) ~= "string" then
        local uf = plate.UnitFrame
        unit = uf and uf.unit
    end
    if type(unit) == "string" then return unit end
end

-- Fills `out` with the admitted, deduplicated nameplate tokens.
local function CollectPullTokens(out)
    wipe(out)
    wipe(seen)
    local plates = C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates()
    if type(plates) ~= "table" then return out end
    for i = 1, #plates do
        local plate = plates[i]
        local unit = type(plate) == "table" and PlateToken(plate)
        if unit and not seen[unit] and MPT.PullAdmits(unit) then
            seen[unit] = true
            out[#out + 1] = unit
        end
    end
    return out
end

---------------------------------------------------------------------------------
-- Calculator pool
---------------------------------------------------------------------------------

-- Parentless bars: their coordinate space starts at screen left with scale
-- 1, so a bar of width `total` with range 0..total fills exactly `count`
-- units and the chained right edge reads as the sum. Never parent them to
-- the HUD or UIParent — a moved or scaled origin changes what the endpoint
-- means.
local bars, barsInUse = {}, 0

local function AcquireBar()
    barsInUse = barsInUse + 1
    local bar = bars[barsInUse]
    if not bar then
        bar = CreateFrame("StatusBar")
        bar:SetAlpha(0)
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        bars[barsInUse] = bar
    end
    return bar
end

local function ReleasePool()
    for i = 1, barsInUse do
        local bar = bars[i]
        bar:Hide()
        bar:ClearAllPoints()
        bar:SetValue(0)
    end
    barsInUse = 0
end

local abbrevTotal, abbrevConfig
local function PercentConfig(total)
    if abbrevTotal ~= total then
        abbrevTotal = total
        abbrevConfig = {
            config = CreateAbbreviateConfig({
                {
                    breakpoint = 0.00001,
                    abbreviation = "",
                    significandDivisor = total / 10000,
                    fractionDivisor = 100,
                    abbreviationIsGlobal = false,
                },
            }),
        }
    end
    return abbrevConfig
end

---------------------------------------------------------------------------------
-- Scheduler
---------------------------------------------------------------------------------

local listener = CreateFrame("Frame")
listener:Hide()
local LISTENER_EVENTS = {
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
    "UNIT_THREAT_LIST_UPDATE", "UNIT_TARGET", "UNIT_FLAGS",
}

local active = false         -- listener registered; builds permitted
local epoch = 0              -- bumped by ClearPullEstimate; a batch built under an older epoch is stale
local dirty = false
local buildTimer = nil       -- pending C_Timer.NewTimer handle
local lastBuild = -math.huge
local batch = nil            -- owns the pool from build until delivery or discard
local tokenGen = {}          -- [token] = add/remove generation while active
local batchTokens, checkTokens = {}, {}

local function IsPlateToken(unit)
    return type(unit) == "string" and strfind(unit, "^nameplate%d+$") ~= nil
end

-- The public state a batch was built from must still hold at delivery: same
-- epoch, eligibility, total and credited count, and the same admitted token
-- set with unchanged generations (a plate removed and re-added under the
-- same token fails here even though the plate count matches).
local function BatchStillValid(b)
    if b.epoch ~= epoch or not active then return false end
    local run = MPT.run
    if not MPT.PullEligible(MPT.db, run, MPT.isPreview) then return false end
    if run.forces.total ~= b.total or run.forces.current ~= b.credited then return false end
    CollectPullTokens(checkTokens)
    if #checkTokens ~= b.n then return false end
    for i = 1, #checkTokens do
        local unit = checkTokens[i]
        local gen = b.gens[unit]
        if gen == nil or gen ~= (tokenGen[unit] or 0) then return false end
    end
    return true
end

local function Deliver(b)
    if b ~= batch then return end
    batch = nil
    if not BatchStillValid(b) then
        ReleasePool()
        if DEBUG_PULL then KE:Print("[MPT pull] delivery refused: state moved") end
        if active then MPT:RequestPullEstimate() end
        return
    end
    -- The endpoint may be secret: classify first, never compare or store it.
    local endpoint = b.endpoint:GetRight()
    ReleasePool()
    if not issecretvalue(endpoint) and type(endpoint) ~= "number" then
        if MPT.ClearPullDisplay then MPT:ClearPullDisplay() end
    elseif MPT.SetPullDisplay then
        MPT:SetPullDisplay(endpoint,
            C_StringUtil.RoundToNearestString(endpoint),
            AbbreviateNumbers(endpoint, PercentConfig(b.total)))
    end
    if dirty then MPT:RequestPullEstimate() end
end

local function Build()
    dirty = false
    lastBuild = GetTime()
    local db, run = MPT.db, MPT.run
    if not MPT.PullEligible(db, run, MPT.isPreview) then
        MPT:ClearPullEstimate()
        return
    end
    local total, credited = run.forces.total, run.forces.current
    CollectPullTokens(batchTokens)
    ReleasePool()
    if #batchTokens == 0 then
        if MPT.ClearPullDisplay then MPT:ClearPullDisplay() end
        return
    end
    local origin = AcquireBar()
    origin:SetSize(total, 10)
    origin:SetPoint("LEFT")
    origin:SetMinMaxValues(0, total)
    origin:SetValue(0)
    origin:Show()
    local prevTex = origin:GetStatusBarTexture()
    local gens, accepted = {}, 0
    for i = 1, #batchTokens do
        local unit = batchTokens[i]
        gens[unit] = tokenGen[unit] or 0
        local count = GetProgress(unit)
        -- Truthy test only: the count may be secret and goes straight to its sink.
        if count then
            local bar = AcquireBar()
            bar:SetSize(total, 10)
            bar:SetPoint("LEFT", prevTex, "RIGHT", 0, 0)
            bar:SetMinMaxValues(0, total)
            bar:SetValue(count)
            bar:Show()
            prevTex = bar:GetStatusBarTexture()
            accepted = accepted + 1
        end
    end
    if accepted == 0 then
        ReleasePool()
        if MPT.ClearPullDisplay then MPT:ClearPullDisplay() end
        return
    end
    if DEBUG_PULL then KE:Print(("[MPT pull] build: %d admitted, %d counted, total %d"):format(#batchTokens, accepted, total)) end
    local b = { epoch = epoch, total = total, credited = credited, n = #batchTokens, gens = gens, endpoint = prevTex }
    batch = b
    -- Two deferred frames before the endpoint is read: the settlement the
    -- technique was observed to need, not a documented guarantee.
    C_Timer.After(0, function()
        C_Timer.After(0, function() Deliver(b) end)
    end)
end

local function _BuildFire()
    buildTimer = nil
    if not active or batch or not dirty then return end
    Build()
end

function MPT:RequestPullEstimate()
    if not active then return end
    dirty = true
    if batch or buildTimer then return end
    local wait = (lastBuild + BUILD_INTERVAL) - GetTime()
    if wait < 0 then wait = 0 end
    buildTimer = C_Timer.NewTimer(wait, _BuildFire)
end

listener:SetScript("OnEvent", function(_, event, unit)
    if not active or not IsPlateToken(unit) then return end
    if event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
        tokenGen[unit] = (tokenGen[unit] or 0) + 1
    end
    MPT:RequestPullEstimate()
end)

-- Reconcile public eligibility with the listener and request a sample.
-- Repeated calls with unchanged state do not restart an owned batch.
function MPT:SyncPullEstimate()
    if GetProgress and self.PullEligible(self.db, self.run, self.isPreview) then
        if not active then
            active = true
            wipe(tokenGen)
            for i = 1, #LISTENER_EVENTS do listener:RegisterEvent(LISTENER_EVENTS[i]) end
            if DEBUG_PULL then KE:Print("[MPT pull] active") end
        end
        self:RequestPullEstimate()
    elseif active or batch or buildTimer then
        self:ClearPullEstimate()
    end
end

-- Idempotent teardown: pending timer cancelled, in-flight settle callbacks
-- made inert, listener silent, pool released, display cleared.
function MPT:ClearPullEstimate()
    epoch = epoch + 1
    active = false
    dirty = false
    batch = nil
    if buildTimer then
        buildTimer:Cancel()
        buildTimer = nil
    end
    listener:UnregisterAllEvents()
    wipe(tokenGen)
    ReleasePool()
    if self.ClearPullDisplay then self:ClearPullDisplay() end
    if DEBUG_PULL then KE:Print("[MPT pull] cleared") end
end
