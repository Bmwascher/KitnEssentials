-- ╔══════════════════════════════════════════════════════════╗
-- ║  SwingTimerTarget.lua                                    ║
-- ║  Module: Swing Timer                                     ║
-- ║  Purpose: The Target bar, an estimate from hits taken.   ║
-- ║           All of it is separable from the weapon bars.   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@type SwingTimer
local ST = KitnEssentials:GetModule("SwingTimer")
local R = KE.SwingTimerRules

local C_Timer = C_Timer
local GetTime = GetTime

local TARGET_LABEL = "TGT est"
local HATCH_TEXTURE = [[Interface\RaidFrame\Shield-Overlay]]

local function TargetIsLivingEnemy()
    local exists = UnitExists("target")
    if KE:IsSecretValue(exists) or not exists then return false end
    local canAttack = UnitCanAttack("player", "target")
    if KE:IsSecretValue(canAttack) or not canAttack then return false end
    local dead = UnitIsDeadOrGhost("target")
    if KE:IsSecretValue(dead) then return true end
    return not dead
end

function ST:BuildTargetBar()
    if self.targetBar then return self.targetBar end
    local row = self:BuildBar("TGT")
    row.isTarget = true
    row.name = TARGET_LABEL
    row.baseColor = "ColorTarget"
    -- Anchored to the fill texture, so the hatch moves with the engine's fill.
    local hatch = row.overlay:CreateTexture(nil, "ARTWORK")
    hatch:SetTexture(HATCH_TEXTURE, "REPEAT", "REPEAT")
    hatch:SetHorizTile(true)
    hatch:SetVertTile(true)
    hatch:SetAllPoints(row.bar:GetStatusBarTexture())
    self.targetBar = row
    return row
end

function ST:ApplyTargetShown(row)
    row.frame:SetShown(self.isPreview or TargetIsLivingEnemy())
end

function ST:EnableTarget()
    if not self:TargetEstimateOn() then
        self:DisableTarget()
        return
    end
    local row = self:BuildTargetBar()
    self.unitEvents:RegisterUnitEvent("UNIT_FLAGS", "target")
    self.unitEvents:RegisterUnitEvent("UNIT_FACTION", "target")
    self:ApplyTargetShown(row)
end

function ST:DisableTarget()
    if self.unitEvents then
        self.unitEvents:UnregisterEvent("UNIT_FLAGS")
        self.unitEvents:UnregisterEvent("UNIT_FACTION")
    end
    self.targetLearned, self.targetLastHit = nil, nil
    local row = self.targetBar
    if not row then return end
    self:CancelEdgeTimers(row)
    row.starts, row.ends, row.swingDuration = nil, nil, nil
    row.state = "empty"
    row.frame:Hide()
end

-- Takes the slot after the weapon bars and returns the last slot in use.
function ST:LayoutTarget(slot)
    local row = self.targetBar
    if not row or not self:TargetEstimateOn() then return slot - 1 end
    local db = self.db
    row.frame:ClearAllPoints()
    row.frame:SetPoint("TOP", self.frame, "TOP", 0, -(slot - 1) * (db.Height + db.Spacing))
    self:ApplyTargetShown(row)
    return slot
end

-- At its end the bar goes empty and never parks.
function ST:RefreshTarget(row)
    self:CancelEdgeTimers(row)
    self:PaintIdentity(row)
    local now = GetTime()
    if row.ends and now < row.ends then
        row.state = "running"
        self:StartFill(row, row.starts, row.swingDuration, self.db.Deplete)
        self:ShowCountdown(row, row.duration)
        row.endTimer = C_Timer.NewTimer(row.ends - now, row.onEdge)
    else
        row.state = "empty"
        row.ends = nil
        self:SetWord(row, nil)
        self:ParkBar(row, false)
    end
    self:PaintRange(row)
end

function ST:OnTargetChanged()
    local row = self.targetBar
    if not row or not self:TargetEstimateOn() then return end
    self.targetLearned, self.targetLastHit = nil, nil
    row.ends = nil
    self:ApplyTargetShown(row)
    self:RefreshBar(row)
end

function ST:OnTargetHit()
    local row = self.targetBar
    local now = GetTime()
    self.targetLearned = R.LearnInterval(self.targetLastHit, now, self.targetLearned)
    self.targetLastHit = now
    -- The target's speed reads secret in combat, and a hit only comes in combat.
    local duration = self.targetLearned
    if not duration then return end
    row.starts, row.ends, row.swingDuration = now, now + duration, duration
    self:RefreshBar(row)
end

function ST:OnTargetCombat(unit, action, school)
    local row = self.targetBar
    if not row or KE:IsSecretValue(school) then return end
    if unit == "target" then
        if action == "PARRY" then self:ShortenSwing(row) end
        return
    end
    if unit ~= "player" then return end
    local onMe = UnitIsUnit("targettarget", "player")
    if R.TargetHitCounts(action, school, not KE:IsSecretValue(onMe), onMe) then self:OnTargetHit() end
end

function ST:UNIT_FLAGS()
    if not self.targetBar then return end
    self:ApplyTargetShown(self.targetBar)
    self:UpdateHolder()
end

ST.UNIT_FACTION = ST.UNIT_FLAGS
