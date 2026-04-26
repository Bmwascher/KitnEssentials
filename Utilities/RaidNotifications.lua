-- ╔══════════════════════════════════════════════════════════╗
-- ║  RaidNotifications.lua                                   ║
-- ║  Module: Raid Notifications                              ║
-- ║  Purpose: Gateway usability, reset boss reminder, and    ║
-- ║           loot boss reminder with per-alert toggles.     ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class RaidNotifications: AceModule, AceEvent-3.0
local RN = KitnEssentials:NewModule("RaidNotifications", "AceEvent-3.0")

local C_Item = C_Item
local C_Timer = C_Timer
local C_UnitAuras = C_UnitAuras
local IsUsableItem = C_Item.IsUsableItem
local GetItemCount = C_Item.GetItemCount
local GetItemInfo = C_Item.GetItemInfo
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local GetInstanceInfo = GetInstanceInfo
local UnitClass = UnitClass
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local GetNumGroupMembers = GetNumGroupMembers

local function IsInRaidInstance()
    local difficultyID = select(3, GetInstanceInfo()) or 0
    return difficultyID >= 14 and difficultyID <= 16
end

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
local GATEWAY_ITEM_ID = 188152

local SATED_DEBUFFS = {
    57723,  -- Exhaustion (Heroism)
    57724,  -- Sated (Bloodlust)
    80354,  -- Temporal Displacement (Time Warp)
    264689, -- Fatigued (Primal Rage)
    390435, -- Exhaustion (Fury of the Aspects)
}

local ALERT_DEFS = {
    { key = "Gateway",   text = "GATE USABLE", icon = 607513,  enableKey = "GatewayEnabled" },
    { key = "ResetBoss", text = "RESET BOSS",  icon = 136090,  enableKey = "ResetBossEnabled" },  -- Spell_Nature_Exhaustion
    { key = "LootBoss",  text = "LOOT BOSS",   icon = "Interface\\AddOns\\KitnEssentials\\Media\\Icon\\Cat_Head.png", enableKey = "LootBossEnabled" },
}

local ALERT_BY_KEY = {}
for _, def in ipairs(ALERT_DEFS) do
    ALERT_BY_KEY[def.key] = def
end

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------
RN.frame = nil
RN.rows = {}
RN.activeAlerts = {}
RN.isPreview = false
RN.editModeRegistered = false
RN.hasItem = false
RN.hasWarlockInGroup = false
RN.wasUsable = nil
RN.resetBossGen = 0
RN.lootBossGen = 0

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function RN:UpdateDB()
    self.db = KE.db.profile.RaidNotifications
end

function RN:MigrateFromGatewayAlert()
    local oldGA = KE.db.profile.GatewayAlert
    if not oldGA or KE.db.profile._RaidNotifMigrated then return end

    local keys = { "Enabled", "Strata", "anchorFrameType", "ParentFrame",
                   "FontSize", "FontFace", "FontOutline", "ColorMode", "Color", "ShowIcons" }
    for _, key in ipairs(keys) do
        if oldGA[key] ~= nil then
            self.db[key] = oldGA[key]
        end
    end
    if oldGA.Position then
        self.db.Position = oldGA.Position
    end
    KE.db.profile._RaidNotifMigrated = true
end

---------------------------------------------------------------------------------
-- Display System
---------------------------------------------------------------------------------
local function CreateIcon(parent, anchor, point, relPoint, xOff, iconSize)
    local holder = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    holder:SetSize(iconSize, iconSize)
    holder:SetPoint(point, anchor, relPoint, xOff, 0)
    holder:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    holder:SetBackdropColor(0, 0, 0, 0.8)
    holder:SetBackdropBorderColor(0, 0, 0, 1)

    local tex = holder:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", 1, -1)
    tex:SetPoint("BOTTOMRIGHT", -1, 1)
    KE:ApplyIconZoom(tex)
    holder.tex = tex
    KE:AddIconBorders(holder)
    return holder
end

function RN:CreateAlertRow(index)
    local row = CreateFrame("Frame", "KE_RaidNotifRow" .. index, self.frame)
    row:SetSize(300, 40)

    local text = row:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER", row, "CENTER", 0, 0)
    row.text = text

    local iconSize = self.db.FontSize or 16
    local leftIcon = CreateIcon(row, text, "RIGHT", "LEFT", -4, iconSize)
    local rightIcon = CreateIcon(row, text, "LEFT", "RIGHT", 4, iconSize)

    row.leftIcon = leftIcon
    row.rightIcon = rightIcon
    row.alertKey = nil
    row:Hide()
    return row
end

function RN:CreateFrames()
    if self.frame then return end

    local frame = CreateFrame("Frame", "KE_RaidNotificationsFrame", UIParent)
    frame:SetSize(1, 1)
    self.frame = frame

    -- Pre-create row pool (3 for current alerts, expandable)
    for i = 1, #ALERT_DEFS do
        self.rows[i] = self:CreateAlertRow(i)
    end
end

function RN:GetFreeRow()
    for _, row in ipairs(self.rows) do
        if not row.alertKey then
            return row
        end
    end
    -- Expand pool if needed
    local newRow = self:CreateAlertRow(#self.rows + 1)
    self.rows[#self.rows + 1] = newRow
    return newRow
end

function RN:ShowAlert(key)
    if self.activeAlerts[key] then return end -- already shown

    local def = ALERT_BY_KEY[key]
    if not def then return end

    -- Check per-alert enable
    if not self.isPreview and self.db[def.enableKey] == false then return end

    local row = self:GetFreeRow()
    row.alertKey = key
    row.text:SetText(def.text)
    row.leftIcon.tex:SetTexture(def.icon)
    row.rightIcon.tex:SetTexture(def.icon)
    row:Show()

    self.activeAlerts[key] = row
    self:ApplyRowVisuals(row)
    self:LayoutRows()
end

function RN:HideAlert(key)
    local row = self.activeAlerts[key]
    if not row then return end

    row:Hide()
    row.alertKey = nil
    self.activeAlerts[key] = nil
    self:LayoutRows()
end

function RN:HideAllAlerts()
    for key, row in pairs(self.activeAlerts) do
        row:Hide()
        row.alertKey = nil
    end
    wipe(self.activeAlerts)
end

function RN:LayoutRows()
    local yOff = 0
    local spacing = self.db.RowSpacing or 4
    local count = 0
    local maxWidth = 0

    -- Stack in ALERT_DEFS order
    for _, def in ipairs(ALERT_DEFS) do
        local row = self.activeAlerts[def.key]
        if row and row:IsShown() then
            row:ClearAllPoints()
            row:SetPoint("TOP", self.frame, "TOP", 0, -yOff)
            yOff = yOff + row:GetHeight() + spacing
            local rowWidth = row.text:GetStringWidth() + (self.db.FontSize or 16) * 2 + 16
            if rowWidth > maxWidth then maxWidth = rowWidth end
            count = count + 1
        end
    end

    -- Resize container to encompass all rows (for EditMode dragging)
    local totalHeight = count > 0 and (yOff - spacing) or 40
    self.frame:SetSize(math.max(maxWidth, 200), math.max(totalHeight, 40))
end

function RN:ApplyRowVisuals(row)
    if not row then return end

    local db = self.db
    KE:ApplyFontToText(row.text, db.FontFace, db.FontSize, db.FontOutline)

    local r, g, b, a = KE:GetAccentColor(db.ColorMode, db.Color)
    row.text:SetTextColor(r, g, b, a)

    local showIcons = db.ShowIcons ~= false
    row.leftIcon:SetShown(showIcons)
    row.rightIcon:SetShown(showIcons)
    if showIcons then
        local iconSize = db.FontSize or 16
        row.leftIcon:SetSize(iconSize, iconSize)
        row.rightIcon:SetSize(iconSize, iconSize)
    end
end

---------------------------------------------------------------------------------
-- Zone Change
---------------------------------------------------------------------------------
function RN:OnZoneChange()
    self:GatewayFullUpdate()
end

---------------------------------------------------------------------------------
-- Gateway Logic
---------------------------------------------------------------------------------
-- Gates can only be placed by Warlocks. If no Warlock is in the group (and the
-- player isn't one), the alert is meaningless — suppress it.
function RN:CheckGroupForWarlock()
    local _, _, playerClassID = UnitClass("player")
    if playerClassID == 9 then
        self.hasWarlockInGroup = true
        return true
    end

    if not IsInGroup() then
        self.hasWarlockInGroup = false
        return false
    end

    local numMembers = GetNumGroupMembers() or 0
    local prefix = IsInRaid() and "raid" or "party"
    local maxCheck = IsInRaid() and numMembers or (numMembers - 1)

    for i = 1, maxCheck do
        local _, _, classID = UnitClass(prefix .. i)
        if classID == 9 then
            self.hasWarlockInGroup = true
            return true
        end
    end

    self.hasWarlockInGroup = false
    return false
end

function RN:OnGroupChanged()
    self:CheckGroupForWarlock()
    self:GatewayCheckUsable()
end

function RN:GatewayFullUpdate()
    C_Timer.After(0.5, function()
        if not self.db or not self.db.Enabled then return end
        self:CheckGroupForWarlock()
        local count = GetItemCount(GATEWAY_ITEM_ID)
        self.hasItem = count and count > 0
        if self.hasItem then
            self:GatewayCheckUsable()
        else
            self:GatewayUpdateState(false)
        end
    end)
end

function RN:GatewayCheckUsable()
    if not self.hasItem or not self.hasWarlockInGroup then
        self:GatewayUpdateState(false)
        return
    end
    self:GatewayUpdateState(IsUsableItem(GATEWAY_ITEM_ID) and true or false)
end

function RN:GatewayUpdateState(isUsable)
    if self.isPreview then return end
    if self.db.GatewayEnabled == false then
        self:HideAlert("Gateway")
        return
    end
    if isUsable == self.wasUsable then return end
    self.wasUsable = isUsable

    if isUsable then
        self:ShowAlert("Gateway")
    else
        self:HideAlert("Gateway")
    end
end

---------------------------------------------------------------------------------
-- Reset Boss Logic
---------------------------------------------------------------------------------
local GetPlayerAuraBySpellID = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID

function RN:HasLustDebuff()
    if not GetPlayerAuraBySpellID then return false end
    for _, spellID in ipairs(SATED_DEBUFFS) do
        if GetPlayerAuraBySpellID(spellID) then
            return true
        end
    end
    return false
end

function RN:CheckResetBoss()
    if self.isPreview then return end
    if self.db.ResetBossEnabled == false then
        self:HideAlert("ResetBoss")
        return
    end

    -- Only show in raid groups
    if not IsInRaidInstance() then
        self:HideAlert("ResetBoss")
        return
    end

    if InCombatLockdown() or UnitIsDeadOrGhost("player") then
        self:HideAlert("ResetBoss")
        return
    end

    if self:HasLustDebuff() then
        self:ShowAlert("ResetBoss")

        -- Start auto-hide timer with generation counter
        self.resetBossGen = self.resetBossGen + 1
        local gen = self.resetBossGen
        C_Timer.After(self.db.AlertDuration or 40, function()
            if self.resetBossGen == gen then
                self:HideAlert("ResetBoss")
            end
        end)
    else
        self:HideAlert("ResetBoss")
    end
end

function RN:OnUnitAura(_, unit)
    if unit ~= "player" then return end
    if not self.db.Enabled or self.isPreview then return end
    self:CheckResetBoss()
end

function RN:OnCombatStart()
    if not self.db.Enabled or self.isPreview then return end
    self:HideAlert("ResetBoss")
end

function RN:OnCombatEnd()
    if not self.db.Enabled or self.isPreview then return end
    -- Small delay to let aura events settle
    C_Timer.After(0.2, function()
        if not self.db or not self.db.Enabled then return end
        self:CheckResetBoss()
    end)
end

---------------------------------------------------------------------------------
-- Loot Boss Logic
---------------------------------------------------------------------------------
function RN:OnEncounterEnd(_, encounterID, encounterName, difficultyID, groupSize, success)
    if not self.db.Enabled or self.isPreview then return end
    if self.db.LootBossEnabled == false then return end
    if success ~= 1 then return end
    if not IsInRaidInstance() then return end

    self:ShowAlert("LootBoss")

    -- Start auto-hide timer with generation counter
    self.lootBossGen = self.lootBossGen + 1
    local gen = self.lootBossGen
    C_Timer.After(self.db.AlertDuration or 40, function()
        if self.lootBossGen == gen then
            self:HideAlert("LootBoss")
        end
    end)
end

function RN:ClearLootBoss()
    if not self.db.Enabled then return end
    self.lootBossGen = self.lootBossGen + 1  -- invalidate any pending timer
    self:HideAlert("LootBoss")
end

---------------------------------------------------------------------------------
-- Apply Settings
---------------------------------------------------------------------------------
function RN:ApplySettings()
    if not self.frame then return end

    KE:ApplyFramePositionWithSnap(self.frame, self.db.Position, self.db)

    if self.db.Strata then
        self.frame:SetFrameStrata(self.db.Strata)
    end

    -- Sync preview alerts with per-alert toggles
    if self.isPreview then
        for _, def in ipairs(ALERT_DEFS) do
            if self.db[def.enableKey] ~= false then
                self:ShowAlert(def.key)
            else
                self:HideAlert(def.key)
            end
        end
    end

    -- Update all existing rows (both active and pooled)
    for _, row in ipairs(self.rows) do
        self:ApplyRowVisuals(row)
        if self.db.Strata then
            row:SetFrameStrata(self.db.Strata)
        end
    end

    self:LayoutRows()
end

---------------------------------------------------------------------------------
-- EditMode
---------------------------------------------------------------------------------
function RN:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "RaidNotifications", displayName = "Raid Notifications", frame = self.frame,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos) self.db.Position = pos; KE:ApplyFramePositionWithSnap(self.frame, self.db.Position, self.db) end,
            getParentFrame = function() return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame) end,
            guiPath = "RaidNotifications",
        })
        self.editModeRegistered = true
    end
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------
function RN:ShowPreview()
    if not self.frame then
        self:CreateFrames()
    end
    self:RegWithEditMode()

    self.isPreview = true
    self:ApplySettings()
    -- Show only enabled alerts as preview
    for _, def in ipairs(ALERT_DEFS) do
        if self.db[def.enableKey] ~= false then
            self:ShowAlert(def.key)
        else
            self:HideAlert(def.key)
        end
    end
end

function RN:HidePreview()
    self.isPreview = false
    self:HideAllAlerts()

    if self.db.Enabled then
        -- Re-evaluate real state
        self.wasUsable = nil
        self:GatewayCheckUsable()
        self:CheckResetBoss()
        -- LootBoss is event-driven only, no re-check needed
    end
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function RN:OnInitialize()
    self:UpdateDB()
    self:MigrateFromGatewayAlert()
    self.wasUsable = nil
    self.hasItem = false
    self:SetEnabledState(false)
end

function RN:OnEnable()
    if not self.db.Enabled then return end

    self:CreateFrames()
    self:RegWithEditMode()
    C_Timer.After(0.5, function()
        if not self.db or not self.db.Enabled then return end
        self:ApplySettings()
    end)

    -- Zone change: update gateway + cache saved encounters
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnZoneChange")
    self:RegisterEvent("BAG_UPDATE", "GatewayFullUpdate")
    self:RegisterEvent("SPELL_UPDATE_USABLE", "GatewayCheckUsable")
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnGroupChanged")

    -- Reset Boss events
    self:RegisterEvent("UNIT_AURA", "OnUnitAura")
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatStart")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnd")

    -- Loot Boss events
    self:RegisterEvent("ENCOUNTER_END", "OnEncounterEnd")
    self:RegisterEvent("LOOT_OPENED", "ClearLootBoss")
    self:RegisterEvent("CHAT_MSG_MONEY", "ClearLootBoss")
    self:RegisterEvent("ENCOUNTER_START", "ClearLootBoss")

    self:GatewayFullUpdate()
end

function RN:OnThemeChanged()
    if not self.db or not self.db.Enabled then return end
    if (self.db.ColorMode or "custom") == "theme" and self.rows then
        local r, g, b, a = KE:GetAccentColor(self.db.ColorMode, self.db.Color)
        for _, row in ipairs(self.rows) do
            if row.text then
                row.text:SetTextColor(r, g, b, a)
            end
        end
    end
end

function RN:OnDisable()
    self:UnregisterAllEvents()
    self:HideAllAlerts()
    self.wasUsable = nil
    self.hasItem = false
    self.hasWarlockInGroup = false
    self.isPreview = false
    self.resetBossGen = self.resetBossGen + 1
    self.lootBossGen = self.lootBossGen + 1
end
