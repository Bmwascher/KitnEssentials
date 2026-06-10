-- ╔══════════════════════════════════════════════════════════╗
-- ║  MythicPlusTimer_Overlay.lua                             ║
-- ║  Folded enemy overlay (ex-WarpDepleteForces):           ║
-- ║  per-mob nameplate forces % + enemy-tooltip count via   ║
-- ║  C_ScenarioInfo.GetUnitCriteriaProgressValues (12.0.5). ║
-- ║  Decoupled from the external WarpDeplete addon — keys   ║
-- ║  off this module's run-state / IsChallengeModeActive.   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end
local MPT = KitnEssentials:GetModule("MythicPlusTimer")

-- Local references
local CreateFrame = CreateFrame
local UnitExists = UnitExists
local UnitIsDead = UnitIsDead
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitCanAttack = UnitCanAttack
local UnitAffectingCombat = UnitAffectingCombat
local UIParent = UIParent
local C_ChallengeMode = C_ChallengeMode
local C_ScenarioInfo = C_ScenarioInfo
local C_NamePlate = C_NamePlate
local C_Timer = C_Timer
local format = string.format
local pairs = pairs
local table_remove = table.remove

---------------------------------------------------------------------------------
-- API Gate
---------------------------------------------------------------------------------

-- Feature-gate: a no-op if the 12.0.5 per-unit API is unavailable.
local HasProgressAPI = C_ScenarioInfo and C_ScenarioInfo.GetUnitCriteriaProgressValues
local GetProgress = HasProgressAPI and C_ScenarioInfo.GetUnitCriteriaProgressValues

local function IsInChallengeMode()
    return C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
        and C_ChallengeMode.IsChallengeModeActive()
end

---------------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------------

local tooltipHooked = false

local function SetupTooltip()
    if tooltipHooked or not GetProgress then return end
    tooltipHooked = true
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
        if not MPT.db or not MPT.db.OverlayTooltipEnabled then return end
        if not IsInChallengeMode() then return end

        -- Read progress off the mouseover token Blizzard's tooltip resolves
        -- against. Truthy check ONLY — no numeric comparison/arithmetic, which
        -- crash on secret values. format() tolerates secret numeric args
        -- (proven in the retired WDF path / BigWigs Keystones).
        local value, percent = GetProgress("mouseover")
        if not value or not percent then return end

        local themeHex = KE:GetThemeColorHex()
        tooltip:AddLine(format("|TInterface\\AddOns\\KitnEssentials\\Media\\Icon\\KitnUI:0:0|t|cff%sCount:|r |cffffffff+%d | %.2f%%|r",
            themeHex, value, percent))
        tooltip:Show()
    end)
end

---------------------------------------------------------------------------------
-- Legacy DB Migration (Task 4.2 — carried forward from Phase-0 stub)
---------------------------------------------------------------------------------

-- One-time migration: carry retired WarpDepleteForces overlay settings into
-- this module's flat Overlay* keys. Guarded by a persistent OverlayMigrated
-- flag — NOT by the old table being nil, because AceDB/FillProfileDefaults
-- resurrect profile.Dungeons.WarpDepleteForces (with default values) on
-- every login until Task 4.8 removes the Core/Defaults.lua block.
-- Maps old WDF key -> new MPT Overlay* key. Death-log persistence is dropped
-- (the new module keeps deaths transient in MPT.run.deathLog).
function MPT:MigrateLegacyOverlayDB()
    if self.db.OverlayMigrated then return end
    self.db.OverlayMigrated = true   -- unconditional set: fresh installs are marked done too

    local profile = KE.db and KE.db.profile
    local old = profile and profile.Dungeons and profile.Dungeons.WarpDepleteForces
    if not old then return end

    local map = {
        Tooltip              = "OverlayTooltipEnabled",
        NameplatePercent     = "OverlayNameplateEnabled",
        NameplateCombatOnly  = "OverlayCombatOnly",
        NameplateFontFace    = "OverlayFontFace",
        NameplateFontSize    = "OverlayFontSize",
        NameplateFontOutline = "OverlayFontOutline",
        NameplateColorMode   = "OverlayColorMode",
        NameplateColor       = "OverlayColor",
        NameplateAnchor      = "OverlayAnchor",
        NameplateXOffset     = "OverlayXOffset",
        NameplateYOffset     = "OverlayYOffset",
    }
    for oldKey, newKey in pairs(map) do
        if old[oldKey] ~= nil then
            self.db[newKey] = old[oldKey]
        end
    end

    -- Old table is fully retired (Instance Reset Announcer + DeathLog drop with it).
    -- Deliberately NOT nil-ing profile.Dungeons.WarpDepleteForces here: the live
    -- WDF module re-binds self.db to that slot on every profile switch
    -- (ProfileManager duck-types UpdateDB) and would crash on a nil section.
    -- Task 4.8 removes the WDF module + its Defaults.lua block; the slot dies there.
end

---------------------------------------------------------------------------------
-- Nameplate % Overlay
-- Shows each mob's forces contribution as a floating text on its nameplate.
-- Follows BigWigs' text-pool pattern — reusable Frame + FontString objects
-- recycled when a nameplate leaves, so we don't churn frames on busy pulls.
-- All style/position updates flow through RefreshOverlayStyle so the GUI
-- can live-refresh without a reload.
---------------------------------------------------------------------------------

local activeTexts = {}   -- [unitToken] = textObj
local storedTexts = {}   -- object pool
local nameplateTicker = nil

local function CreateNameplateTextObject()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(1, 1)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(6200)
    frame:Hide()
    local fs = frame:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("CENTER")
    return { frame = frame, fs = fs }
end

local function ApplyNameplateStyle(obj)
    local db = MPT.db
    if not db then return end
    local fontPath = KE:GetFontPath(db.OverlayFontFace) or KE.FONT
    local size = db.OverlayFontSize or 12
    local outline = db.OverlayFontOutline or "OUTLINE"
    if outline == "NONE" then outline = "" end
    obj.fs:SetFont(fontPath, size, outline)
    local r, g, b, a = KE:GetAccentColor(db.OverlayColorMode or "theme", db.OverlayColor)
    obj.fs:SetTextColor(r, g, b, a or 1)
end

local function AttachNameplateText(obj, unit)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then return false end
    local db = MPT.db
    obj.frame:ClearAllPoints()
    obj.frame:SetParent(plate)
    obj.frame:SetPoint("CENTER", plate, db.OverlayAnchor or "TOPRIGHT",
        db.OverlayXOffset or -20, db.OverlayYOffset or 2)
    obj.frame:Show()
    return true
end

local function AcquireNameplateText()
    local obj = table_remove(storedTexts)
    if not obj then obj = CreateNameplateTextObject() end
    ApplyNameplateStyle(obj)
    return obj
end

local function ReleaseNameplateText(unit)
    local obj = activeTexts[unit]
    if not obj then return end
    obj.frame:Hide()
    obj.frame:ClearAllPoints()
    obj.frame:SetParent(UIParent)
    activeTexts[unit] = nil
    storedTexts[#storedTexts + 1] = obj
end

local function UpdateNameplateTextFor(unit)
    local db = MPT.db
    if not db or not db.OverlayNameplateEnabled then return end
    if not GetProgress then return end
    if not IsInChallengeMode() then
        ReleaseNameplateText(unit)
        return
    end
    if not UnitExists(unit) or UnitIsDead(unit) or not UnitCanAttack("player", unit) then
        ReleaseNameplateText(unit)
        return
    end
    if db.OverlayCombatOnly then
        if not UnitAffectingCombat(unit) then
            ReleaseNameplateText(unit)
            return
        end
        if UnitIsDeadOrGhost("player") then
            ReleaseNameplateText(unit)
            return
        end
    end

    -- Truthy check only — percent may be a secret value; no comparison/arithmetic.
    local _, percent = GetProgress(unit)
    if not percent then
        ReleaseNameplateText(unit)
        return
    end

    local obj = activeTexts[unit]
    if not obj then
        obj = AcquireNameplateText()
        activeTexts[unit] = obj
    end
    if not AttachNameplateText(obj, unit) then
        ReleaseNameplateText(unit)
        return
    end
    obj.fs:SetText(format(db.OverlayFormat or "%.2f%%", percent))
end

local function UpdateAllNameplateTexts()
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) then
            UpdateNameplateTextFor(unit)
        end
    end
    for unit in pairs(activeTexts) do
        if not UnitExists(unit) then
            ReleaseNameplateText(unit)
        end
    end
end

local function ReleaseAllNameplateTexts()
    for unit in pairs(activeTexts) do
        ReleaseNameplateText(unit)
    end
end

local function RefreshAllNameplateStyle()
    for _, obj in pairs(activeTexts) do ApplyNameplateStyle(obj) end
    for _, obj in pairs(storedTexts) do ApplyNameplateStyle(obj) end
end

local function RefreshAllNameplatePositions()
    for unit, obj in pairs(activeTexts) do
        AttachNameplateText(obj, unit)
    end
end

local function StartNameplateTicker()
    if nameplateTicker then return end
    if not MPT.db or not MPT.db.OverlayNameplateEnabled then return end
    if not IsInChallengeMode() then return end
    nameplateTicker = C_Timer.NewTicker(0.5, UpdateAllNameplateTexts)
end

local function StopNameplateTicker()
    if nameplateTicker then
        nameplateTicker:Cancel()
        nameplateTicker = nil
    end
end

---------------------------------------------------------------------------------
-- Overlay API (public — InitOverlay / SetOverlayActive added in Task 4.5)
---------------------------------------------------------------------------------

-- Internal: install the tooltip post-call if overlay is being activated.
-- Called from SetOverlayActive (Task 4.5).
function MPT:_SetupOverlayTooltip()
    SetupTooltip()
end

-- Called from Task 4.5's SetOverlayActive (nameplate arm on/off).
function MPT:_StartNameplateTicker()
    StartNameplateTicker()
end

function MPT:_StopNameplateTicker()
    StopNameplateTicker()
end

function MPT:_ReleaseAllNameplateTexts()
    ReleaseAllNameplateTexts()
end

function MPT:_UpdateAllNameplateTexts()
    UpdateAllNameplateTexts()
end

-- Event handlers wired by Task 4.6.
function MPT:NAME_PLATE_UNIT_ADDED(_, unit)
    UpdateNameplateTextFor(unit)
end

function MPT:NAME_PLATE_UNIT_REMOVED(_, unit)
    ReleaseNameplateText(unit)
end

-- GUI live-refresh entry point (Task 5.9 calls this on every style/position change).
function MPT:RefreshOverlayStyle()
    RefreshAllNameplateStyle()
    RefreshAllNameplatePositions()
end
