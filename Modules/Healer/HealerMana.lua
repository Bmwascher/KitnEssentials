-- ╔══════════════════════════════════════════════════════════╗
-- ║  HealerMana.lua                                          ║
-- ║  Module: Healer Mana Tracker                             ║
-- ║  Purpose: Displays healer mana. Dungeon Mode shows       ║
-- ║           the single party/M+ healer; Raid Mode          ║
-- ║           shows all raid healers, stacked.               ║
-- ║  Note: Mode auto-switches on instance type.              ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class HealerSnapshot
---@field unit string
---@field name string
---@field specID number?
---@field class string
---@field classColor any
---@field connected boolean

---@class HealerMana: AceModule, AceEvent-3.0, AceTimer-3.0
---@field currentHealers HealerSnapshot[]
local HM = KitnEssentials:NewModule("HealerMana", "AceEvent-3.0", "AceTimer-3.0")

local DEBUG_HM = false

local CreateFrame = CreateFrame
local UnitExists = UnitExists
local UnitIsConnected = UnitIsConnected
local UnitIsPlayer = UnitIsPlayer
local UnitClass = UnitClass
local UnitName = UnitName
local UnitPowerPercent = UnitPowerPercent
local UnitPowerMax = UnitPowerMax
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local GetSpecializationInfoByID = GetSpecializationInfoByID
local IsInRaid = IsInRaid
local IsInGroup = IsInGroup
local GetNumGroupMembers = GetNumGroupMembers
local GetRaidRosterInfo = GetRaidRosterInfo
local C_Timer = C_Timer
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
HM.currentHealers = {}
HM._lastMode = nil
HM.mode = "DUNGEON"     -- held mode; only RefreshMode writes it
HM.previewContext = nil  -- "RAID" | "DUNGEON" | nil (set by GUI preview switch)
HM.guiConfigContext = nil  -- "RAID" | "DUNGEON" | nil (which context the GUI edits)
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
    if UnitGroupRolesAssigned(unit) ~= "HEALER" then return false end
    -- Filter delve companion NPCs that don't have a real mana pool. Valeera
    -- Sanguinar in Midnight delves returns max=1 (sentinel placeholder)
    -- rather than true 0. Threshold 100 is well below any real healer
    -- class's max mana (tens of thousands minimum). Real player healers
    -- (including disconnected ones — UnitIsPlayer stays true across
    -- disconnect) and any mana-using NPC follower (Cylestia in follower
    -- dungeons) still pass through.
    if not UnitIsPlayer(unit) then
        local maxMana = UnitPowerMax(unit, Enum.PowerType.Mana)
        -- UnitPowerMax is SECRET in restricted party-power contexts (delves /
        -- follower dungeons) — the very places this NPC branch runs. A `< 100`
        -- relational compare on a secret number throws (truthiness is fine, but
        -- comparison is not). Only apply the delve-companion sentinel filter
        -- when maxMana is a safe number; when it's secret, let the unit through
        -- (UnitGroupRolesAssigned already confirmed HEALER role above).
        if KE:IsSafeValue(maxMana) and maxMana < 100 then return false end
    end
    return true
end

local function DisplayManaPercent(fontString, unit)
    -- In delves Blizzard restricts party-member power queries — pct comes
    -- back as a secret token. Do NOT branch on it (issecretvalue → "—"
    -- fallback is a regression: addon code can't read the value, but the
    -- display layer is server-trusted and will render the underlying
    -- number when the secret is passed to SetFormattedText. Forward it
    -- directly; same pattern SinStats uses to display Intellect in
    -- raid encounters. SetFormattedText is a display call, not arithmetic,
    -- so no taint propagates back into addon Lua.
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
-- Mode + Position resolution
---------------------------------------------------------------------------------
-- Group-type driven: a raid group (+ EnableInRaid) = Raid Mode (all healers);
-- party, solo or EnableInRaid off = Dungeon Mode (single healer).
--
-- The answer is HELD, not queried: a reader resolving it per call can get a
-- different answer mid-layout and swap the active position table under itself.
-- Only RefreshMode writes it.
function HM:RefreshMode()
    local previous = self.mode
    local mode = "DUNGEON"
    if self.db and self.db.EnableInRaid and IsInRaid() then
        mode = "RAID"
    end
    self.mode = mode
    return mode ~= previous
end

function HM:GetMode()
    return self.mode or "DUNGEON"
end

-- Which DB position table is live right now. Single source of truth so the
-- reader (GetActivePosition / EditMode getPosition) and the writer (EditMode
-- setPosition) never disagree. Split off = shared "Position"; split on + Raid
-- Mode (or a Raid GUI preview) = "RaidPosition".
function HM:GetActivePositionKey()
    if not self.db then return "Position" end
    if self.isPreview and self.previewContext and self.db.SplitPositioning then
        return (self.previewContext == "RAID") and "RaidPosition" or "Position"
    end
    if self.db.SplitPositioning and self:GetMode() == "RAID" then
        return "RaidPosition"
    end
    return "Position"
end

-- Active position table, resolved via GetActivePositionKey.
function HM:GetActivePosition()
    if not self.db then return nil end
    return self.db[self:GetActivePositionKey()] or self.db.Position
end

-- Anchor config (anchorFrameType / ParentFrame) for the active context. Raid
-- has its own root keys so it can anchor to a different frame than Dungeon;
-- Strata is shared. Returns a table shaped for KE:ApplyFramePosition's Config
-- arg. Dungeon returns self.db directly (its keys live at the root).
function HM:GetActiveAnchorConfig()
    if not self.db then return {} end
    if self:GetActivePositionKey() == "RaidPosition" then
        return {
            anchorFrameType = self.db.RaidAnchorFrameType,
            ParentFrame = self.db.RaidParentFrame,
            Strata = self.db.Strata,
        }
    end
    return self.db
end

-- EditMode overlay label. When split is on, name the mode being edited so the
-- overlay makes it obvious which position table a drag will write to.
function HM:GetEditModeLabel()
    if self.db and self.db.SplitPositioning then
        return (self:GetActivePositionKey() == "RaidPosition")
            and "Healer Mana (Raid)" or "Healer Mana (Dungeon)"
    end
    return "Healer Mana"
end

-- Rewrites the container's vertical anchor edge so the stack grows away from
-- a stable edge: DOWN pins the TOP, UP pins the BOTTOM. Horizontal component
-- preserved.
function HM:GetGrowAnchor(anchor)
    anchor = anchor or "CENTER"
    local growDown = self.db.GrowDirection == "DOWN"
    local verticalTarget = growDown and "TOP" or "BOTTOM"
    local verticalOpposite = growDown and "BOTTOM" or "TOP"
    if anchor:find(verticalOpposite) then
        return (anchor:gsub(verticalOpposite, verticalTarget))
    elseif anchor:find(verticalTarget) then
        return anchor
    elseif anchor == "LEFT" then
        return verticalTarget .. "LEFT"
    elseif anchor == "RIGHT" then
        return verticalTarget .. "RIGHT"
    else
        return verticalTarget
    end
end

---------------------------------------------------------------------------------
-- Frame Creation
---------------------------------------------------------------------------------
function HM:CreateHealerFrame()
    -- Anonymous (nil name): Refresh() recreates these per font/outline rebuild;
    -- a global name would silently clobber the prior frame's _G slot and orphan
    -- it. Nothing references these by name (the container holds them as children
    -- and EditMode anchors via frame reference, not name).
    local frame = CreateFrame("Frame", nil, self.containerFrame)
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

    frame.name = frame:CreateFontString(nil, "OVERLAY")
    frame.name:SetFont(fontPath, self.db.NameFontSize, KE:GetFontOutline(fontOutline))
    frame.name:SetPoint("LEFT", frame.iconFrame, "RIGHT", self.db.NameXOffset, self.db.NameYOffset)
    frame.name:SetJustifyH("LEFT")

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
        self.healerFrames[index] = self:CreateHealerFrame()
    end
    return self.healerFrames[index]
end

function HM:UpdateFrameAppearance(frame)
    local fontPath = KE:GetFontPath(self.db.FontFace)
    local fontOutline = self.db.FontOutline
    local manaOutline = (fontOutline == "NONE") and "" or "OUTLINE"

    frame:SetSize(self.db.FrameWidth, self.db.IconSize)
    frame.iconFrame:SetSize(self.db.IconSize, self.db.IconSize)
    frame.name:SetFont(fontPath, self.db.NameFontSize, KE:GetFontOutline(fontOutline))
    frame.name:ClearAllPoints()
    frame.name:SetPoint("LEFT", frame.iconFrame, "RIGHT", self.db.NameXOffset, self.db.NameYOffset)
    frame.mana:SetFont(fontPath, self.db.ManaFontSize, manaOutline)
    frame.mana:ClearAllPoints()
    frame.mana:SetPoint("LEFT", frame.iconFrame, "RIGHT", self.db.ManaXOffset, self.db.ManaYOffset)
end

function HM:CreateContainer()
    if self.containerFrame then return self.containerFrame end

    -- Anonymous: Refresh() nils + recreates the container; a fixed global name
    -- would clobber/orphan the prior one. EditMode tracks it by frame reference.
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(self.db.FrameWidth, self.db.IconSize)
    frame:SetFrameStrata(self.db.Strata or "HIGH")

    self.containerFrame = frame
    self:ApplyContainerPosition()
    return frame
end

-- Container height = stacked icons + gaps. Single healer (Dungeon) = one icon.
function HM:UpdateContainerSize()
    if not self.containerFrame then return end
    local count = #self.currentHealers
    if count == 0 then
        self.containerFrame:SetSize(self.db.FrameWidth, self.db.IconSize)
        return
    end
    local totalHeight = (self.db.IconSize * count) + (self.db.FrameSpacing * (count - 1))
    self.containerFrame:SetSize(self.db.FrameWidth, totalHeight)
end

-- Stack each healer frame within the container per GrowDirection.
function HM:PositionFrames()
    local growDown = self.db.GrowDirection == "DOWN"
    local spacing = self.db.FrameSpacing
    local iconSize = self.db.IconSize
    for i = 1, #self.currentHealers do
        local frame = self.healerFrames[i]
        if frame then
            frame:ClearAllPoints()
            local yOffset = (i - 1) * (iconSize + spacing)
            if growDown then
                frame:SetPoint("TOPLEFT", self.containerFrame, "TOPLEFT", 0, -yOffset)
            else
                frame:SetPoint("BOTTOMLEFT", self.containerFrame, "BOTTOMLEFT", 0, yOffset)
            end
        end
    end
end

-- Position the container via the active position table, with the grow-adjusted
-- anchor edge. Adjustment is display-only (not persisted). Uses KE's pixel-
-- perfect ApplyFramePosition (snaps the container once; children use integer
-- offsets so no per-child re-snap, avoiding the buggy-grid issue).
-- The anchor edge the container is ACTUALLY hanging by right now, condition
-- included. Only rewritten when actually stacking (>1 healer): a single healer
-- keeps the user's configured anchor so existing positions don't shift on
-- upgrade (default AnchorFrom is "CENTER"). Edit Mode asks this too, so a drag
-- measures from the same edge the applier used.
function HM:GetActiveAnchorFrom()
    local pos = self:GetActivePosition()
    if #self.currentHealers > 1 then
        return self:GetGrowAnchor(pos.AnchorFrom)
    end
    return pos.AnchorFrom
end

function HM:ApplyContainerPosition()
    if not self.containerFrame then return end
    local pos = self:GetActivePosition()
    local anchorFrom = self:GetActiveAnchorFrom()
    local adjusted = {
        AnchorFrom = anchorFrom,
        AnchorTo = pos.AnchorTo,
        XOffset = pos.XOffset,
        YOffset = pos.YOffset,
    }
    KE:ApplyFramePosition(self.containerFrame, adjusted, self:GetActiveAnchorConfig())
end

-- Centralized "no live healers" state. Idempotent. Does NOT wipe healerFrames
-- or containerFrame themselves (persist across hide/show cycles).
function HM:HideFrames()
    wipe(self.currentHealers)
    for _, frame in pairs(self.healerFrames) do frame:Hide() end
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
        self:FindHealers()
    end
end

---------------------------------------------------------------------------------
-- Core Logic
---------------------------------------------------------------------------------
-- Build one healer snapshot (class/name/connection/spec) using KE's LibSpec
-- name-keyed cache. UnitName can be secret in restricted contexts; only use as
-- cache key when safe. specID stays nil if unknown -> class-default icon.
function HM:BuildHealerSnapshot(unit)
    local _, class = UnitClass(unit)
    local displayName = KE:GetNicknameOrName(unit)
    local connected = UnitIsConnected(unit)
    local rawName = UnitName(unit)
    local cachedSpecID
    if KE:IsSafeValue(rawName) then
        cachedSpecID = self.libSpecCache[rawName]
    end
    return {
        unit = unit,
        name = displayName,
        specID = cachedSpecID,
        class = class,
        classColor = KE:GetClassColor(class),
        connected = connected,
    }
end

function HM:FindHealers()
    if DEBUG_HM then KE:Print("[HM] FindHealers entry isPreview=" .. tostring(self.isPreview) .. " enabled=" .. tostring(self.db and self.db.Enabled)) end
    if not self.db or not self.db.Enabled then return end

    local mode = self:GetMode()

    -- Clear stale frames when crossing the dungeon<->raid boundary so a smaller
    -- new set doesn't leave orphaned frames visible.
    if mode ~= self._lastMode then
        self._lastMode = mode
        for _, frame in pairs(self.healerFrames) do frame:Hide() end
        self:RefreshEditMode()  -- keep the overlay label in sync if mode flipped
    end

    -- DisableOnHealer only suppresses Dungeon Mode (Raid shows you as a healer).
    if mode == "DUNGEON" and self.db.DisableOnHealer and KE:IsPlayerHealerSpec() then
        if DEBUG_HM then KE:Print("[HM] FindHealers hide: DisableOnHealer + player healer (Dungeon)") end
        if self.isPreview then return end
        self:HideFrames()
        return
    end

    if not IsInGroup() then
        if DEBUG_HM then KE:Print("[HM] FindHealers hide: not in group") end
        if self.isPreview then return end
        self:HideFrames()
        return
    end

    wipe(self.currentHealers)

    if mode == "RAID" then
        local maxHealers = self.db.MaxHealers or 6
        local excludeBench = self.db.ExcludeBenchGroups
        local count = 0
        local n = GetNumGroupMembers()
        for i = 1, n do
            if count >= maxHealers then break end
            local unit = "raid" .. i  -- includes the player naturally
            if UnitExists(unit) and IsHealer(unit) then
                -- Skip bench-group healers when enabled. The raid index i maps
                -- 1:1 to GetRaidRosterInfo(i); its subgroup return is a plain
                -- number (NOT secret — RaidNotifications:CheckBench compares it
                -- directly with no issecretvalue guard), so == is safe.
                -- Convention: subgroups 1-4 active, 5-6 buffer, 7-8 bench
                -- (mirrors the Bench Alert in RaidNotifications.lua).
                local benched = false
                if excludeBench then
                    local _, _, subgroup = GetRaidRosterInfo(i)
                    benched = (subgroup == 7 or subgroup == 8)
                end
                if not benched then
                    count = count + 1
                    self.currentHealers[count] = self:BuildHealerSnapshot(unit)
                end
            end
        end
    else
        -- Dungeon Mode: single healer, self-case first then party1..4.
        local healerUnit
        if IsHealer("player") then
            healerUnit = "player"
        else
            for i = 1, 4 do
                local unit = "party" .. i
                if UnitExists(unit) and IsHealer(unit) then
                    healerUnit = unit
                    break
                end
            end
        end
        if healerUnit then
            self.currentHealers[1] = self:BuildHealerSnapshot(healerUnit)
        end
    end

    if #self.currentHealers == 0 then
        if DEBUG_HM then KE:Print("[HM] FindHealers no healer found mode=" .. mode) end
        if self.isPreview then return end
        self:HideFrames()
        return
    end

    if DEBUG_HM then KE:Print("[HM] FindHealers mode=" .. mode .. " count=" .. #self.currentHealers) end
    self.isPreview = false
    self:UpdateHealerFrames()
end

-- Render one frame's icon/name/mana for a healer snapshot (no positioning/show).
function HM:UpdateOneHealerFrame(frame, healer)
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

    frame.name:SetText(healer.name)
    local cc = healer.classColor
    frame.name:SetTextColor(cc[1], cc[2], cc[3])

    if self.isPreview then
        local mc = self.db.HighManaColor
        frame.mana:SetTextColor((mc and mc[1]) or 1, (mc and mc[2]) or 1, (mc and mc[3]) or 1)
        frame.icon:SetVertexColor(1, 1, 1)
        frame.mana:SetText("100%")
    else
        self:UpdateManaDisplay(frame, healer.unit, healer.connected)
    end
end

-- Draw all current healers, hide surplus frames, size + position the stack.
function HM:UpdateHealerFrames()
    local count = #self.currentHealers
    if count == 0 then return end

    for i = 1, count do
        local frame = self:GetHealerFrame(i)
        self:UpdateOneHealerFrame(frame, self.currentHealers[i])
        frame:Show()
    end

    for i = count + 1, #self.healerFrames do
        if self.healerFrames[i] then self.healerFrames[i]:Hide() end
    end

    self:UpdateContainerSize()
    self:PositionFrames()
    self:ApplyContainerPosition()
    self.containerFrame:Show()
end

function HM:UpdateMana()
    if self.isPreview then return end
    local count = #self.currentHealers
    if count == 0 then return end
    for i = 1, count do
        local healer = self.currentHealers[i]
        local frame = self.healerFrames[i]
        if frame and frame:IsShown() then
            -- Re-check connection each tick so reconnect/disconnect transitions
            -- are caught without waiting for GROUP_ROSTER_UPDATE.
            local connected = UnitIsConnected(healer.unit)
            healer.connected = connected
            self:UpdateManaDisplay(frame, healer.unit, connected)
        end
    end
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
function HM:ApplySettings()
    self:UpdateDB()
    if not self.db then return end
    self:RefreshMode()
    if not self.db.Enabled and not self.isPreview then
        if self.containerFrame then self.containerFrame:Hide() end
        return
    end

    self:CreateContainer()
    self:ApplyContainerPosition()
    self.containerFrame:SetFrameStrata(self.db.Strata or "HIGH")

    -- Apply font/size/offset changes to already-created frames so live edits
    -- take effect without a Refresh()/reload.
    for _, frame in pairs(self.healerFrames) do
        self:UpdateFrameAppearance(frame)
    end

    if self.isPreview then
        self:UpdateHealerFrames()
    else
        self:FindHealers()
    end
end

function HM:Refresh()
    local wasPreview = self.isPreview

    wipe(self.currentHealers)
    self._lastMode = nil
    for _, frame in pairs(self.healerFrames) do frame:Hide() end
    wipe(self.healerFrames)

    if self.containerFrame then
        if KE.EditMode and KE.EditMode.UnregisterElement then
            KE.EditMode:UnregisterElement("HealerMana")
        end
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
            key = "HealerMana", displayName = self:GetEditModeLabel(), frame = self.containerFrame,
            module = self,
            getPosition = function() return self:GetActivePosition() end,
            setPosition = function(pos)
                -- Write to the SAME table getPosition reads (no get/set drift).
                self.db[self:GetActivePositionKey()] = pos
                self:ApplyContainerPosition()
            end,
            getAnchorFrom = function() return self:GetActiveAnchorFrom() end,
            getParentFrame = function()
                local cfg = self:GetActiveAnchorConfig()
                return KE:ResolveAnchorFrame(cfg.anchorFrameType, cfg.ParentFrame)
            end,
            guiPath = "StatusTexts",
            guiTab = "HealerMana",
        })
        self.editModeRegistered = true
    end
end

-- Re-register so the overlay label reflects the current mode/context. Cheap and
-- only meaningful when split is on (label is constant otherwise). Called when
-- the GUI Configure For dropdown changes or the live mode crosses a boundary.
function HM:RefreshEditMode()
    if not (KE.EditMode and self.containerFrame) then return end
    if not (self.db and self.db.SplitPositioning) then return end
    if KE.EditMode.UnregisterElement then KE.EditMode:UnregisterElement("HealerMana") end
    self.editModeRegistered = false
    self:RegWithEditMode()
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------
function HM:ShowPreview()
    if DEBUG_HM then KE:Print("[HM] ShowPreview entry") end
    self:UpdateDB()
    if not self.db then return end

    self:CreateContainer()
    self:ApplyContainerPosition()
    self.containerFrame:SetFrameStrata(self.db.Strata or "HIGH")
    self:RegWithEditMode()

    -- Prefer a live healer when actually grouped and NOT previewing raid context.
    if self.db.Enabled and IsInGroup() and self.previewContext ~= "RAID" and not IsInRaid() then
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
            self.isPreview = false
            self:FindHealers()
            return
        end
    end

    -- Canned preview. Raid context -> MaxHealers fake healers; else one.
    self.isPreview = true
    wipe(self.currentHealers)
    local previewCount = (self.previewContext == "RAID") and (self.db.MaxHealers or 6) or 1
    -- Sample healer specs (drive only the icon/class color in the preview).
    -- Names are generic "Healer N"; only the spec/class is read here.
    local CANNED = {
        { specID = 257,  class = "PRIEST" },   -- Holy Priest
        { specID = 105,  class = "DRUID" },    -- Restoration
        { specID = 270,  class = "MONK" },     -- Mistweaver
        { specID = 65,   class = "PALADIN" },  -- Holy
        { specID = 264,  class = "SHAMAN" },   -- Restoration
        { specID = 1468, class = "EVOKER" },   -- Preservation
    }
    for i = 1, previewCount do
        local c = CANNED[((i - 1) % #CANNED) + 1]
        -- Top row uses the real player name so the preview feels personal; the
        -- rest are generic "Healer N" sample rows.
        -- GetNicknameOrName honors a nickname (own name is never secret).
        local name = (i == 1) and KE:GetNicknameOrName("player") or ("Healer " .. i)
        self.currentHealers[i] = {
            unit = "player",
            name = name,
            specID = c.specID,
            class = c.class,
            classColor = KE:GetClassColor(c.class),
            connected = true,
        }
    end
    self:UpdateHealerFrames()
end

function HM:HidePreview()
    if DEBUG_HM then KE:Print("[HM] HidePreview entry, will FindHealers if enabled") end
    self.isPreview = false
    -- Need both db.Enabled AND a live containerFrame. On profile change the
    -- AceModule may not yet have been enabled (so OnEnable→ApplySettings→
    -- CreateContainer hasn't run), but db.Enabled is already true under the
    -- new profile — driving FindHealer here would crash on a nil container.
    if self.db and self.db.Enabled and self.containerFrame then
        self:FindHealers()
    else
        self:HideFrames()
    end
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
-- A mode flip changes sizes as well as position, so the frames are re-dressed
-- before FindHealers redraws them. Not the only refresh point: EnableInRaid is
-- half the mode predicate and the GUI writes it without a roster event, so
-- ApplySettings refreshes too.
function HM:OnGroupChanged()
    if not self.db or not self.db.Enabled then return end
    if self:RefreshMode() then
        for _, frame in pairs(self.healerFrames) do
            self:UpdateFrameAppearance(frame)
        end
    end
    -- No reposition here: FindHealers -> UpdateHealerFrames sizes the container
    -- and then positions it. Repositioning first would hang the container at
    -- the new mode's anchor with the old mode's row count, which is the mixed
    -- frame this change exists to remove.
    self:FindHealers()
end

function HM:OnEnable()
    self:UpdateDB()
    if not self.db or not self.db.Enabled then return end
    self:RefreshMode()
    self:ApplySettings()
    C_Timer.After(0.5, function()
        if HM.containerFrame and HM.db then HM:ApplyContainerPosition() end
    end)
    self:RegWithEditMode()
    self:StartUpdates()
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnGroupChanged")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnGroupChanged")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "FindHealers")
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
    wipe(self.currentHealers)
    self.isPreview = false
    if self.containerFrame then self.containerFrame:Hide() end
    for _, frame in pairs(self.healerFrames) do frame:Hide() end
end
