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
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local GetInstanceInfo = GetInstanceInfo
local C_CurrencyInfo = C_CurrencyInfo
local C_Map = C_Map
local UnitClass = UnitClass
local UnitName = UnitName
local IsInInstance = IsInInstance
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local GetNumGroupMembers = GetNumGroupMembers
local GetRaidDifficultyID = GetRaidDifficultyID
local GetRaidRosterInfo = GetRaidRosterInfo

local function IsInRaidInstance()
    local difficultyID = select(3, GetInstanceInfo()) or 0
    return difficultyID >= 14 and difficultyID <= 16
end

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
local GATEWAY_ITEM_ID = 188152

-- Nebulous Voidcore — 12.0 Midnight Season 1 currency for bonus rolls in
-- seasonal dungeons + raids. Bought from an NPC; no over-cap possible.
local VOIDCORE_CURRENCY_ID = 3418

-- Seasonal zone detection uses uiMapIDs and uiMapGroupIDs (matching the
-- identifier scheme that WeakAuras' Player Location feature exposes). The
-- player is "in a seasonal zone" if their current uiMapID — or any ancestor
-- in the parent-map chain — appears in either table, OR if any ancestor's
-- mapGroupID appears in VOIDCORE_MAP_GROUPS.
--
-- Single-floor dungeons / raids use a uiMapID directly. Multi-floor zones
-- use a mapGroupID umbrella. The "Keystone Dungeons" entry (2266) covers
-- all 8 active M+ rotation dungeons via the keystone-eligibility umbrella.
-- Individual dungeon entries are kept alongside it for belt-and-suspenders
-- coverage when the player walks in via Heroic / Find Group rather than
-- via an active keystone.
--
-- Source: in-game player-location IDs (verified via WeakAuras' Player
-- Location trigger 2026-05-06).
local VOIDCORE_UI_MAPS = {
    [2266] = true,  -- Keystone Dungeons (umbrella for all 8 active M+ rotation maps)
    [2501] = true,  -- Maisara Caverns
    [2556] = true,  -- Nexus-Point Xenas
    [184]  = true,  -- Pit of Saron
    [903]  = true,  -- Seat of the Triumvirate
}

local VOIDCORE_MAP_GROUPS = {
    [469] = true,  -- Magister's Terrace
    [465] = true,  -- Windrunner Spire
    [433] = true,  -- Algeth'ar Academy
    [226] = true,  -- Skyreach
    [468] = true,  -- The Dreamfit (raid)
    [466] = true,  -- The Voidspire (raid)
    [467] = true,  -- March on Quel'Danas (raid)
}

-- Walks the player's current uiMap parent chain. Returns true on the first
-- match against either VOIDCORE_UI_MAPS (direct uiMapID) or VOIDCORE_MAP_GROUPS
-- (the uiMap's group). Sub-area maps within a dungeon (different rooms,
-- different floors) inherit the dungeon's identity through this walk.
local function IsInSeasonalZone()
    local cur = C_Map.GetBestMapForUnit("player")
    while cur and cur > 0 do
        if VOIDCORE_UI_MAPS[cur] then return true end
        local groupID = C_Map.GetMapGroupID(cur)
        if groupID and VOIDCORE_MAP_GROUPS[groupID] then return true end
        local info = C_Map.GetMapInfo(cur)
        cur = info and info.parentMapID
    end
    return false
end

local SATED_DEBUFFS = {
    57723,  -- Exhaustion (Heroism)
    57724,  -- Sated (Bloodlust)
    80354,  -- Temporal Displacement (Time Warp)
    264689, -- Fatigued (Primal Rage)
    390435, -- Exhaustion (Fury of the Aspects)
}

-- Alerts may set `icon = nil` to render text-only. The display layer
-- (ShowAlert + ApplyRowVisuals) hides the left/right icon holders for
-- nil-icon alerts regardless of the global ShowIcons toggle.
local ALERT_DEFS = {
    { key = "Gateway",    text = "GATE USABLE", icon = 607513,  enableKey = "GatewayEnabled" },
    { key = "ResetBoss",  text = "RESET BOSS",  icon = 136090,  enableKey = "ResetBossEnabled" },  -- Spell_Nature_Exhaustion
    { key = "LootBoss",   text = "LOOT BOSS",   icon = "Interface\\AddOns\\KitnEssentials\\Media\\Icon\\Cat_Head.png", enableKey = "LootBossEnabled" },
    { key = "BenchAlert", text = "BENCHED",     icon = 134414, enableKey = "BenchEnabled" },  -- INV_Misc_Rune_01
    { key = "Voidcore",   text = "BONUS ROLLS MISSING", icon = 7658128, enableKey = "VoidcoreEnabled" },
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
    -- def.icon may be nil for text-only alerts (e.g. BenchAlert). The icon
    -- holders are still positioned around the text, but ApplyRowVisuals
    -- hides them when def.icon is nil. SetTexture(nil) is harmless.
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

    -- Icon visibility = global ShowIcons toggle AND this alert has an icon
    -- defined. Text-only alerts (def.icon == nil) always render without
    -- icon holders, regardless of the global toggle.
    local def = row.alertKey and ALERT_BY_KEY[row.alertKey]
    local rowHasIcon = def and def.icon ~= nil
    local showIcons = db.ShowIcons ~= false and rowHasIcon
    row.leftIcon:SetShown(showIcons)
    row.rightIcon:SetShown(showIcons)
    if showIcons then
        local iconSize = db.FontSize or 16
        row.leftIcon:SetSize(iconSize, iconSize)
        row.rightIcon:SetSize(iconSize, iconSize)
    end
end

---------------------------------------------------------------------------------
-- Voidcore — seasonal currency cap alert
---------------------------------------------------------------------------------
-- Fires while the player is inside a seasonal instance (dungeon/raid) AND
-- has earned less than the weekly cap of Nebulous Voidcore. Hides during
-- combat to avoid mid-pull screen clutter. Subscription to the currency +
-- combat events is zone-conditional (managed by VoidcoreUpdateSubscriptions)
-- so we don't pay event-dispatch overhead while the player is outside the
-- relevant 11 instances.
function RN:EvaluateVoidcore()
    if not self.db.VoidcoreEnabled then self:HideAlert("Voidcore"); return end
    if InCombatLockdown() then self:HideAlert("Voidcore"); return end
    if not IsInSeasonalZone() then self:HideAlert("Voidcore"); return end
    local info = C_CurrencyInfo.GetCurrencyInfo(VOIDCORE_CURRENCY_ID)
    if info and info.quantityEarnedThisWeek < info.maxWeeklyQuantity then
        self:ShowAlert("Voidcore")
    else
        self:HideAlert("Voidcore")
    end
end

function RN:VoidcoreUpdateSubscriptions()
    local shouldSubscribe = self.db.VoidcoreEnabled and IsInSeasonalZone()
    if shouldSubscribe and not self._voidcoreSubscribed then
        self:RegisterEvent("CURRENCY_DISPLAY_UPDATE", "EvaluateVoidcore")
        self:RegisterEvent("PLAYER_REGEN_DISABLED",   "EvaluateVoidcore")
        self:RegisterEvent("PLAYER_REGEN_ENABLED",    "EvaluateVoidcore")
        self._voidcoreSubscribed = true
    elseif not shouldSubscribe and self._voidcoreSubscribed then
        self:UnregisterEvent("CURRENCY_DISPLAY_UPDATE")
        self:UnregisterEvent("PLAYER_REGEN_DISABLED")
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        self._voidcoreSubscribed = false
    end
    self:EvaluateVoidcore()
end

---------------------------------------------------------------------------------
-- Zone Change
---------------------------------------------------------------------------------
function RN:OnZoneChange()
    self:GatewayFullUpdate()
    self:CheckBench()
    self:VoidcoreUpdateSubscriptions()
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
    self:CheckBench()
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
-- Bench Alert Logic
---------------------------------------------------------------------------------
-- Mythic raid is fixed 20 active players in a roster supporting up to 30 across
-- 8 subgroups. There is no Blizzard API for "is this player benched" — the
-- detection is convention-based. Subgroups 1-4 hold the active 20 (5 per group)
-- across most raid teams; 5-6 are typically left empty as buffer; 7-8 are the
-- two conventional bench groups. We treat subgroup 7 OR 8 as benched.
function RN:CheckBench()
    if self.isPreview then return end
    if not self.db or not self.db.Enabled then return end
    if self.db.BenchEnabled == false then
        self:HideAlert("BenchAlert")
        return
    end

    if not IsInRaid() then
        self:HideAlert("BenchAlert")
        return
    end

    local inInstance, instanceType = IsInInstance()
    if not inInstance or instanceType ~= "raid" then
        self:HideAlert("BenchAlert")
        return
    end

    -- Difficulty 16 = Mythic raid. Heroic/Normal raids cap at 30 players, no
    -- bench mechanic. Only Mythic supports the 20-player active + bench split.
    if GetRaidDifficultyID() ~= 16 then
        self:HideAlert("BenchAlert")
        return
    end

    local playerName = UnitName("player")
    if not playerName then
        self:HideAlert("BenchAlert")
        return
    end

    -- Walk the raid roster (max 40 slots) to find the player's subgroup.
    -- GetRaidRosterInfo returns nil for empty slots. Convention: subgroups
    -- 7 and 8 are the bench (1-4 active 20, 5-6 buffer/unused, 7-8 bench).
    for i = 1, 40 do
        local name, _, subgroup = GetRaidRosterInfo(i)
        if name and name == playerName then
            if subgroup == 7 or subgroup == 8 then
                self:ShowAlert("BenchAlert")
            else
                self:HideAlert("BenchAlert")
            end
            return
        end
    end

    self:HideAlert("BenchAlert")
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

    self:VoidcoreUpdateSubscriptions()
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
    -- Idempotent guard: bail when preview is already active. Prevents
    -- PreviewManager's per-section-navigation ShowSectionPreviews from
    -- redundantly re-applying fonts/colors/sizes to all rows on every
    -- transition. The GUI's per-toggle onChangeCallback calls
    -- ApplySettings directly, so live edits still propagate.
    if self.isPreview then return end

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
    -- Idempotent guard: bail if preview was already off. Avoids redundant
    -- HideAllAlerts + GatewayCheckUsable + CheckResetBoss on every
    -- non-utilities section navigation.
    if not self.isPreview then return end

    self.isPreview = false
    self:HideAllAlerts()

    -- Only re-evaluate live state if the AceModule is actually enabled.
    -- During profile change, db.Enabled may flip true under the new profile
    -- before OnEnable fires — driving Gateway/Reset checks before frames
    -- exist would crash on nil indexing.
    if self.db.Enabled and self:IsEnabled() then
        self.wasUsable = nil
        self:GatewayCheckUsable()
        self:CheckResetBoss()
        self:CheckBench()
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

    -- Bench Alert: re-evaluate when raid leader switches difficulty mid-session
    -- (PLAYER_ENTERING_WORLD + GROUP_ROSTER_UPDATE already routed via
    -- OnZoneChange + OnGroupChanged above for the other lifecycle events).
    self:RegisterEvent("PLAYER_DIFFICULTY_CHANGED", "CheckBench")

    self:GatewayFullUpdate()
    self:CheckBench()
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
    -- Clear isPreview so a future OnEnable starts from a known-good state.
    -- Without this, a GUI-open disable→re-enable cycle could leave isPreview
    -- stuck true, which would make CheckResetBoss + GatewayUpdateState +
    -- OnEncounterEnd silently skip real-combat alerts (they all early-return
    -- on `if self.isPreview then return end`).
    self.isPreview = false
    self.hasItem = false
    self.hasWarlockInGroup = false
    self.isPreview = false
    self._voidcoreSubscribed = false
    self.resetBossGen = self.resetBossGen + 1
    self.lootBossGen = self.lootBossGen + 1
end
