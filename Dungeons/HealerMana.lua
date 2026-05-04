-- ╔══════════════════════════════════════════════════════════╗
-- ║  HealerMana.lua                                          ║
-- ║  Module: Healer Mana Tracker                             ║
-- ║  Purpose: Displays the current party healer's mana %     ║
-- ║           with their name and spec icon.                 ║
-- ║  Note: Party-only (hidden in raid).                      ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class HealerMana: AceModule, AceEvent-3.0, AceTimer-3.0
local HM = KitnEssentials:NewModule("HealerMana", "AceEvent-3.0", "AceTimer-3.0")

local DEBUG_HM = false

local CreateFrame = CreateFrame
local UnitExists = UnitExists
local UnitIsConnected = UnitIsConnected
local UnitClass = UnitClass
local UnitName = UnitName
local UnitPowerPercent = UnitPowerPercent
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local GetSpecializationInfoByID = GetSpecializationInfoByID
local IsInRaid = IsInRaid
local IsInGroup = IsInGroup
local pairs = pairs
local wipe = wipe

-- LibSpecialization: passive group spec/role tracking via addon comms.
-- Replaces our prior GetInspectSpecialization-only lookup which never resolved
-- Disc-vs-Holy priest icons for cross-realm pugs (no shared inspect data).
-- Optional load — module degrades to class-default healer icons if lib absent.
local LibSpec = LibStub("LibSpecialization", true)

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
-- Healing spec icon fallbacks by class (used when inspect spec is not available yet)
local HEALER_SPEC_ICONS = {
    DRUID   = 136041,  -- Restoration
    MONK    = 608952,  -- Mistweaver
    PALADIN = 135920,  -- Holy
    PRIEST  = 135940,  -- Discipline
    SHAMAN  = 136052,  -- Restoration
    EVOKER  = 4622476, -- Preservation
}

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------
HM.healerFrames = {}
HM.containerFrame = nil
HM.updateTimer = nil
HM.currentHealer = nil
HM.isPreview = false
HM.libSpecCache = {}  -- [playerName] = specID, fed by LibSpec.RegisterGroup callback

---------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------
local function GetSpecIcon(specID)
    if not specID or specID == 0 then return nil end
    local _, _, _, icon = GetSpecializationInfoByID(specID)
    return icon
end

local function IsHealer(unit)
    return UnitGroupRolesAssigned(unit) == "HEALER"
end

local function DisplayManaPercent(fontString, unit)
    local pct = UnitPowerPercent(unit, Enum.PowerType.Mana, true, CurveConstants.ScaleTo100)
    fontString:SetFormattedText("%.0f%%", pct)
end

-- Single point of truth for the mana % vs OFFLINE display state. Called from
-- UpdateHealerFrame (initial draw / healer change) and UpdateMana (1Hz tick).
-- Connected: restore HighManaColor + full-bright icon, render mana %.
-- Disconnected: grey text + label "OFFLINE", grey icon vertex color.
function HM:UpdateManaDisplay(frame, unit, connected)
    if connected then
        local mc = self.db.HighManaColor
        frame.mana:SetTextColor(
            (mc and mc[1]) or 1,
            (mc and mc[2]) or 1,
            (mc and mc[3]) or 1
        )
        frame.icon:SetVertexColor(1, 1, 1)
        DisplayManaPercent(frame.mana, unit)
    else
        frame.mana:SetTextColor(0.5, 0.5, 0.5)
        frame.mana:SetText("OFFLINE")
        frame.icon:SetVertexColor(0.4, 0.4, 0.4)
    end
end

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function HM:UpdateDB()
    if KE.db and KE.db.profile then
        self.db = KE.db.profile.Dungeons and KE.db.profile.Dungeons.HealerMana
    end
end

function HM:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

---------------------------------------------------------------------------------
-- Frame Creation
---------------------------------------------------------------------------------
function HM:CreateHealerFrame(index)
    local frame = CreateFrame("Frame", "KE_HealerMana_" .. index, self.containerFrame)
    frame:SetSize(self.db.FrameWidth, self.db.IconSize)

    -- Icon (standard KE: AddIconBorders + ApplyIconZoom from Core/Widgets.lua)
    frame.iconFrame = CreateFrame("Frame", nil, frame)
    frame.iconFrame:SetSize(self.db.IconSize, self.db.IconSize)
    frame.iconFrame:SetPoint("LEFT", frame, "LEFT", 0, 0)
    KE:AddIconBorders(frame.iconFrame)

    frame.icon = frame.iconFrame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetAllPoints(frame.iconFrame)
    KE:ApplyIconZoom(frame.icon)

    -- Name
    local fontPath = KE:GetFontPath(self.db.FontFace)
    local fontOutline = self.db.FontOutline or "OUTLINE"
    local useSoftOutline = fontOutline == "SOFTOUTLINE"
    local actualOutline = useSoftOutline and "" or (fontOutline == "NONE" and "" or fontOutline)

    frame.name = frame:CreateFontString(nil, "OVERLAY")
    frame.name:SetFont(fontPath, self.db.NameFontSize, actualOutline)
    frame.name:SetPoint("LEFT", frame.iconFrame, "RIGHT", self.db.NameXOffset, self.db.NameYOffset)
    frame.name:SetJustifyH("LEFT")

    if useSoftOutline and KE.CreateSoftOutline then
        frame.nameSoftOutline = KE:CreateSoftOutline(frame.name, { size = 2 })
    end

    local manaOutline = (fontOutline == "NONE") and "" or "OUTLINE"
    frame.mana = frame:CreateFontString(nil, "OVERLAY")
    frame.mana:SetFont(fontPath, self.db.ManaFontSize, manaOutline)
    frame.mana:SetPoint("LEFT", frame.iconFrame, "RIGHT", self.db.ManaXOffset, self.db.ManaYOffset)
    frame.mana:SetJustifyH("LEFT")

    frame:Hide()
    return frame
end

function HM:GetHealerFrame(index)
    if not self.healerFrames[index] then
        self.healerFrames[index] = self:CreateHealerFrame(index)
    end
    return self.healerFrames[index]
end

function HM:UpdateFrameAppearance(frame)
    local fontPath = KE:GetFontPath(self.db.FontFace)
    local fontOutline = self.db.FontOutline
    local useSoftOutline = fontOutline == "SOFTOUTLINE"
    local actualOutline = useSoftOutline and "" or (fontOutline == "NONE" and "" or fontOutline)
    local manaOutline = (fontOutline == "NONE") and "" or "OUTLINE"

    frame:SetSize(self.db.FrameWidth, self.db.IconSize)
    frame.iconFrame:SetSize(self.db.IconSize, self.db.IconSize)
    frame.name:SetFont(fontPath, self.db.NameFontSize, actualOutline)
    frame.name:ClearAllPoints()
    frame.name:SetPoint("LEFT", frame.iconFrame, "RIGHT", self.db.NameXOffset, self.db.NameYOffset)
    frame.mana:SetFont(fontPath, self.db.ManaFontSize, manaOutline)
    frame.mana:ClearAllPoints()
    frame.mana:SetPoint("LEFT", frame.iconFrame, "RIGHT", self.db.ManaXOffset, self.db.ManaYOffset)
end

function HM:CreateContainer()
    if self.containerFrame then return self.containerFrame end

    local frame = CreateFrame("Frame", "KE_HealerMana_Container", UIParent)
    frame:SetSize(self.db.FrameWidth, self.db.IconSize)
    frame:SetFrameStrata(self.db.Strata or "HIGH")

    KE:ApplyFramePositionWithSnap(frame, self.db.Position, self.db)

    self.containerFrame = frame
    return frame
end

function HM:PositionFrame()
    local frame = self.healerFrames[1]
    if frame then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", self.containerFrame, "TOPLEFT", 0, 0)
    end
    self.containerFrame:SetSize(self.db.FrameWidth, self.db.IconSize)
end

-- Centralized "no live healer" state. Used by FindHealer's early-return
-- branches and the HidePreview no-FindHealer fallback path. Idempotent.
-- Does NOT wipe healerFrames or containerFrame themselves (those persist
-- across hide/show cycles so we don't reallocate frames). Refresh/OnDisable
-- handle the full-lifecycle teardown.
function HM:HideFrame()
    self.currentHealer = nil
    if self.healerFrames[1] then self.healerFrames[1]:Hide() end
    if self.containerFrame then self.containerFrame:Hide() end
end

-- LibSpec group callback: fires per-member when their spec/role is reported
-- via addon comms. We only care about HEALER role here; cache by playerName
-- (always plain cstring from comms, never secret) and re-FindHealer so the
-- icon updates from class-default to actual spec icon (Disc vs Holy on Priest).
function HM:OnLibSpecGroupUpdate(specID, role, _, playerName)
    if role ~= "HEALER" then return end
    if not specID or specID == 0 or not playerName then return end
    self.libSpecCache[playerName] = specID
    if self.db and self.db.Enabled and not self.isPreview then
        self:FindHealer()
    end
end

---------------------------------------------------------------------------------
-- Core Logic
---------------------------------------------------------------------------------
function HM:FindHealer()
    if DEBUG_HM then KE:Print("[HM] FindHealer entry isPreview=" .. tostring(self.isPreview) .. " enabled=" .. tostring(self.db and self.db.Enabled)) end
    if not self.db or not self.db.Enabled then return end

    -- Hide entirely when the player is a healer themselves, if the toggle is on
    if self.db.DisableOnHealer and KE:IsPlayerHealerSpec() then
        if DEBUG_HM then KE:Print("[HM] FindHealer hide: DisableOnHealer + player is healer spec") end
        if self.isPreview then return end
        self:HideFrame()
        return
    end

    local inGroup = IsInGroup()
    local inRaid = IsInRaid()

    -- Party only — keep canned preview alive when out of valid group
    if not inGroup or inRaid then
        if DEBUG_HM then KE:Print("[HM] FindHealer hide: inGroup=" .. tostring(inGroup) .. " inRaid=" .. tostring(inRaid)) end
        if self.isPreview then return end
        self:HideFrame()
        return
    end

    local healerUnit
    if IsHealer("player") then
        healerUnit = "player"
    else
        -- Drop UnitIsConnected filter so disconnected healers are
        -- still tracked. Connection state is captured separately below
        -- and routed to UpdateManaDisplay for the OFFLINE label path.
        for i = 1, 4 do
            local unit = "party" .. i
            if UnitExists(unit) and IsHealer(unit) then
                healerUnit = unit
                break
            end
        end
    end

    if not healerUnit then
        if DEBUG_HM then KE:Print("[HM] FindHealer no healer in party") end
        if self.isPreview then return end
        self:HideFrame()
        return
    end

    local _, class = UnitClass(healerUnit)
    local displayName = KE:GetNicknameOrName(healerUnit)
    -- UnitIsConnected("player") always returns true, so this is safe across
    -- both the player-self and party-member paths.
    local healerConnected = UnitIsConnected(healerUnit)

    -- Spec lookup via LibSpec name cache. UnitName CAN return secret in
    -- restricted contexts; only use as cache key when safe. If no spec is
    -- known yet (lib not loaded, comms not arrived, secret name), specID
    -- stays nil and UpdateHealerFrame falls back to HEALER_SPEC_ICONS[class].
    local rawName = UnitName(healerUnit)
    local cachedSpecID
    if KE:IsSafeValue(rawName) then
        cachedSpecID = self.libSpecCache[rawName]
    end

    if DEBUG_HM then KE:Print("[HM] FindHealer found unit=" .. healerUnit .. " name=" .. tostring(displayName) .. " class=" .. tostring(class) .. " connected=" .. tostring(healerConnected) .. " specID=" .. tostring(cachedSpecID)) end
    -- Live healer found — switch out of canned preview mode
    self.isPreview = false
    self.currentHealer = {
        unit = healerUnit,
        name = displayName,
        specID = cachedSpecID,
        class = class,
        classColor = KE:GetClassColor(class),
        connected = healerConnected,
    }

    self:UpdateHealerFrame()
end

function HM:UpdateHealerFrame()
    local healer = self.currentHealer
    if not healer then return end

    local frame = self:GetHealerFrame(1)

    -- Icon: spec or class, depending on IconType setting
    local iconType = self.db.IconType or "spec"
    if iconType == "class" and healer.class then
        frame.icon:SetAtlas("classicon-" .. healer.class)
    else
        local icon = GetSpecIcon(healer.specID) or HEALER_SPEC_ICONS[healer.class]
        if icon then
            frame.icon:SetTexture(icon)
            KE:ApplyIconZoom(frame.icon)
        end
    end

    -- Name with class color
    frame.name:SetText(healer.name)
    local cc = healer.classColor
    frame.name:SetTextColor(cc[1], cc[2], cc[3])

    -- Mana value: preview uses canned text + restored colors; real healer
    -- routes through UpdateManaDisplay which handles connected vs OFFLINE.
    if self.isPreview then
        local mc = self.db.HighManaColor
        frame.mana:SetTextColor(
            (mc and mc[1]) or 1,
            (mc and mc[2]) or 1,
            (mc and mc[3]) or 1
        )
        frame.icon:SetVertexColor(1, 1, 1)
        frame.mana:SetText("100%")
    else
        self:UpdateManaDisplay(frame, healer.unit, healer.connected)
    end

    self:PositionFrame()
    frame:Show()
    self.containerFrame:Show()
end

function HM:UpdateMana()
    if self.isPreview then return end
    local healer = self.currentHealer
    if not healer then return end

    local frame = self.healerFrames[1]
    if not frame or not frame:IsShown() then return end

    -- Re-check connection each tick so reconnect/disconnect transitions are
    -- caught without waiting for GROUP_ROSTER_UPDATE. UnitIsConnected is cheap.
    local connected = UnitIsConnected(healer.unit)
    healer.connected = connected
    self:UpdateManaDisplay(frame, healer.unit, connected)
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
function HM:ApplySettings()
    self:UpdateDB()
    if not self.db then return end
    if not self.db.Enabled and not self.isPreview then
        if self.containerFrame then self.containerFrame:Hide() end
        return
    end

    self:CreateContainer()
    KE:ApplyFramePositionWithSnap(self.containerFrame, self.db.Position, self.db)
    self.containerFrame:SetFrameStrata(self.db.Strata or "HIGH")

    -- Apply font/size/offset changes to already-created frames so live edits
    -- take effect without a Refresh()/reload.
    for _, frame in pairs(self.healerFrames) do
        self:UpdateFrameAppearance(frame)
    end

    if self.isPreview then
        self:UpdateHealerFrame()
    else
        self:FindHealer()
    end
end

function HM:Refresh()
    local wasPreview = self.isPreview

    self.currentHealer = nil
    for _, frame in pairs(self.healerFrames) do frame:Hide() end
    wipe(self.healerFrames)

    if self.containerFrame then
        self.containerFrame:Hide()
        self.containerFrame = nil
        self.editModeRegistered = false
    end

    self:ApplySettings()
    if wasPreview then self:ShowPreview() end
end

function HM:StartUpdates()
    if self.updateTimer then return end
    self.updateTimer = self:ScheduleRepeatingTimer("UpdateMana", 1)
end

function HM:StopUpdates()
    if self.updateTimer then
        self:CancelTimer(self.updateTimer)
        self.updateTimer = nil
    end
end

---------------------------------------------------------------------------------
-- EditMode
---------------------------------------------------------------------------------
function HM:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered and self.containerFrame then
        KE.EditMode:RegisterElement({
            key = "HealerMana", displayName = "Healer Mana", frame = self.containerFrame,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos)
                self.db.Position = pos
                KE:ApplyFramePositionWithSnap(self.containerFrame, self.db.Position, self.db)
            end,
            getParentFrame = function() return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame) end,
            guiPath = "HealerMana",
        })
        self.editModeRegistered = true
    end
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------
function HM:ShowPreview()
    if DEBUG_HM then KE:Print("[HM] ShowPreview entry") end
    self:UpdateDB()
    if not self.db then return end

    self:CreateContainer()
    KE:ApplyFramePositionWithSnap(self.containerFrame, self.db.Position, self.db)
    self.containerFrame:SetFrameStrata(self.db.Strata or "HIGH")
    self:RegWithEditMode()

    -- Prefer live healer if one exists in the actual party.
    -- Skip self as the live healer if DisableOnHealer is on.
    if self.db.Enabled and IsInGroup() and not IsInRaid() then
        local playerIsHealerSelf = IsHealer("player") and not (self.db.DisableOnHealer and KE:IsPlayerHealerSpec())
        local liveUnit = playerIsHealerSelf and "player" or nil
        if not liveUnit then
            for i = 1, 4 do
                local unit = "party" .. i
                if UnitExists(unit) and UnitIsConnected(unit) and IsHealer(unit) then
                    liveUnit = unit
                    break
                end
            end
        end
        if liveUnit then
            if DEBUG_HM then KE:Print("[HM] ShowPreview deferring to live healer on " .. liveUnit) end
            self.isPreview = false
            self:FindHealer()
            return
        end
    end

    -- No live healer — show canned preview (Holy Priest)
    self.isPreview = true
    self.currentHealer = {
        unit = "player",
        name = "Healer",
        specID = 257, -- Holy Priest
        class = "PRIEST",
        classColor = KE:GetClassColor("PRIEST"),
    }
    self:UpdateHealerFrame()
end

function HM:HidePreview()
    if DEBUG_HM then KE:Print("[HM] HidePreview entry, will FindHealer if enabled") end
    self.isPreview = false
    -- Need both db.Enabled AND a live containerFrame. On profile change the
    -- AceModule may not yet have been enabled (so OnEnable→ApplySettings→
    -- CreateContainer hasn't run), but db.Enabled is already true under the
    -- new profile — driving FindHealer here would crash on a nil container.
    if self.db and self.db.Enabled and self.containerFrame then
        self:FindHealer()
    else
        self:HideFrame()
    end
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function HM:OnEnable()
    self:UpdateDB()
    if not self.db or not self.db.Enabled then return end
    self:ApplySettings()
    self:RegWithEditMode()
    self:StartUpdates()
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "FindHealer")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "FindHealer")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "FindHealer")
    if LibSpec then
        LibSpec.RegisterGroup(self, function(specID, role, position, playerName)
            HM:OnLibSpecGroupUpdate(specID, role, position, playerName)
        end)
    end
end

function HM:OnDisable()
    self:StopUpdates()
    self:UnregisterAllEvents()
    if LibSpec then LibSpec.UnregisterGroup(self) end
    wipe(self.libSpecCache)
    self.currentHealer = nil
    self.isPreview = false
    if self.containerFrame then self.containerFrame:Hide() end
    for _, frame in pairs(self.healerFrames) do frame:Hide() end
end
