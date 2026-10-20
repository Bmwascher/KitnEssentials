-- ╔══════════════════════════════════════════════════════════╗
-- ║  ShieldWarning.lua                                       ║
-- ║  Module: Dungeon Timers (shielded target warning)        ║
-- ║  Purpose: Center text while the player's target is the  ║
-- ║           boss of a shieldSwap pair that has the shield. ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class DungeonTimers
local DT = KitnEssentials:GetModule("DungeonTimers", true)
if not DT then return end

local Swap = KE._DungeonShieldSwapState

local pcall = pcall
local type = type
local issecretvalue = issecretvalue
local CreateFrame = CreateFrame
local GetInstanceInfo = GetInstanceInfo
local UIParent = UIParent
local UnitExists = UnitExists
local UnitIsDead = UnitIsDead
local UnitIsUnit = UnitIsUnit

local TEXT = "SHIELDED TARGET"
local FONT_SIZE = 40
local COLOR = { 1, 0.15, 0.15 }
local OFFSET_Y = 200

local function WarningSettings()
    local profile = KE.db and KE.db.profile
    local db = profile and profile.DungeonTimers
    return db and db.ShieldWarning
end

local function DifficultyId()
    if not GetInstanceInfo then return nil end
    return (select(3, GetInstanceInfo()))
end

local function OnEvent()
    DT:_ShieldWarningUpdate()
end

function DT:_ShieldWarningFrame()
    local frame = self._shieldWarningFrame
    if frame then return frame end
    frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetSize(FONT_SIZE * 9, FONT_SIZE + 8)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, OFFSET_Y)
    frame:EnableMouse(false)
    frame:Hide()
    local text = frame:CreateFontString(nil, "OVERLAY")
    KE:ApplyFontToText(text, "Expressway", FONT_SIZE, "OUTLINE")
    text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    text:SetTextColor(COLOR[1], COLOR[2], COLOR[3])
    text:SetText(TEXT)
    frame.text = text
    frame:SetScript("OnEvent", OnEvent)
    self._shieldWarningFrame = frame
    return frame
end

-- Runs after the encounter's swap state exists; the frame is made on the first
-- pull that wants it.
function DT:_ShieldWarningStart()
    self:_ShieldWarningStop()
    local swap = self._shieldSwap
    local db = WarningSettings()
    if not Swap.WarningWanted(db and db.Enabled, DifficultyId(), swap) then return end
    local frame = self:_ShieldWarningFrame()
    local units = swap.cfg.units
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    frame:RegisterUnitEvent("UNIT_FLAGS", units[1], units[2])
    self._shieldWarningActive = true
    self:_ShieldWarningUpdate()
end

function DT:_ShieldWarningStop()
    self._shieldWarningActive = false
    local frame = self._shieldWarningFrame
    if not frame then return end
    frame:UnregisterAllEvents()
    frame:Hide()
end

-- The text shows only while both bosses are up: once one dies the other loses
-- the shield.
function DT:_ShieldWarningUpdate()
    local frame = self._shieldWarningFrame
    local swap = self._shieldSwap
    if not (frame and self._shieldWarningActive and swap) then return end
    local units = swap.cfg.units
    for i = 1, 2 do
        local unit = units[i]
        if not UnitExists(unit) or UnitIsDead(unit) then
            frame:Hide()
            return
        end
    end
    -- A refused comparison returns nothing. A hidden answer is still a boolean,
    -- and the alpha takes it unread; a pcall around that sink can lose it.
    local ok, same = pcall(UnitIsUnit, "target", swap.shielded)
    if not ok or (not issecretvalue(same) and type(same) ~= "boolean") then
        frame:Hide()
        return
    end
    frame.text:SetAlphaFromBoolean(same, 1, 0)
    frame:Show()
end

function DT:ApplyShieldWarningSettings()
    if self._shieldSwap and self._activeEncounterId and self:IsEnabled() then
        self:_ShieldWarningStart()
    else
        self:_ShieldWarningStop()
    end
end
