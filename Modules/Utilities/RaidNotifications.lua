-- ╔══════════════════════════════════════════════════════════╗
-- ║  RaidNotifications.lua                                   ║
-- ║  Module: Raid Notifications                              ║
-- ║  Purpose: Multi-alert raid utility notifications —       ║
-- ║           Gateway, ResetBoss, LootBoss, Bench, and       ║
-- ║           Voidcore, with per-alert toggles.              ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class RaidNotifications: AceModule, AceEvent-3.0
---@field _subActive table? subscription-active map; nil between OnDisable and OnEnable
---@field _eventRefcount table? per-event refcount map; nil between OnDisable and OnEnable
local RN = KitnEssentials:NewModule("RaidNotifications", "AceEvent-3.0")

local C_Item = C_Item
local C_Timer = C_Timer
local C_UnitAuras = C_UnitAuras
local IsUsableItem = C_Item.IsUsableItem
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local GetInstanceInfo = GetInstanceInfo
local C_CurrencyInfo = C_CurrencyInfo
local C_ChallengeMode = C_ChallengeMode
local C_Map = C_Map
local UnitName = UnitName
local IsInInstance = IsInInstance
local IsInRaid = IsInRaid
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
-- Location trigger).
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
-- Subscription Orchestrator
---------------------------------------------------------------------------------
-- Two-layer model: module-level always-on events drive
-- _UpdateSubscriptions() which registers/unregisters per-alert events based on
-- each alert's shouldSubscribe() gate. Sub-gated events are refcount-managed
-- so multiple alerts can share an event (PLAYER_REGEN_* shared by ResetBoss +
-- Voidcore) without AceEvent handler conflicts.

local MODULE_ALWAYS_ON_EVENTS = {
    PLAYER_ENTERING_WORLD = true,
    ZONE_CHANGED_NEW_AREA = true,
    GROUP_ROSTER_UPDATE   = true,
}

-- Forward declaration; SUBSYSTEMS table is defined further down in the file
-- after the new handler methods exist (Task 4).
local SUBSYSTEMS

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------
RN.frame = nil
RN.rows = {}
RN.activeAlerts = {}
RN.isPreview = false
RN.editModeRegistered = false
RN.resetBossGen = 0
RN.lootBossGen = 0
-- Voidcore: set true on CHALLENGE_MODE_START, cleared when leaving a
-- seasonal zone. Once a key is active the player cannot meaningfully act
-- on the alert (no leaving the run to buy cores), so suppress display
-- until the next zone change.
RN._voidcoreKeyActive = false

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
-- Orchestrator Implementation
---------------------------------------------------------------------------------

--- Runs a hook field that may be a function, a method name, or nil.
function RN:_RunHook(hook)
    if not hook then return end
    if type(hook) == "string" then
        self[hook](self)
    else
        hook(self)
    end
end

--- Adjusts sub-gated event registration refcounts on subscription change.
--- Events in MODULE_ALWAYS_ON_EVENTS are skipped (already permanently
--- registered to _OnAlwaysOnEvent).
function RN:_ApplySubscriptionDelta(sub, becomingActive)
    for event in pairs(sub.handlers) do
        if not MODULE_ALWAYS_ON_EVENTS[event] then
            -- Floor at 0: the _subActive idempotency guard in _UpdateSubscriptions
            -- prevents double-unsubscribes in normal flow, but a programming error
            -- (or future re-entrancy) should not silently leak a permanently-
            -- registered event by storing a negative refcount.
            local count = math.max(0, (self._eventRefcount[event] or 0)
                                    + (becomingActive and 1 or -1))
            if count == 1 and becomingActive then
                self:RegisterEvent(event, "_OnSubGatedEvent")
            elseif count == 0 then
                self:UnregisterEvent(event)
            end
            self._eventRefcount[event] = count
        end
    end
end

--- Re-evaluates every subsystem's shouldSubscribe; on transitions, updates
--- event refcounts and runs onScopeEnter/onScopeExit hooks. Idempotent.
function RN:_UpdateSubscriptions()
    if not self:IsEnabled() then return end
    -- Defensive: IsEnabled() can briefly disagree with our own state during
    -- the Ace3 disable→state-flip window, and external callers (HidePreview,
    -- ApplySettings) can hit that gap. _subActive is the authoritative signal
    -- that OnEnable has completed and OnDisable hasn't started.
    if not self._subActive then return end
    for key, sub in pairs(SUBSYSTEMS) do
        local shouldBe = sub.shouldSubscribe(self) and true or false
        if shouldBe ~= self._subActive[key] then
            self._subActive[key] = shouldBe
            if shouldBe then
                self:_ApplySubscriptionDelta(sub, true)
                self:_RunHook(sub.onScopeEnter)
            else
                self:_RunHook(sub.onScopeExit)
                self:_ApplySubscriptionDelta(sub, false)
            end
        end
    end
end

--- Always-on event dispatcher. Defers 1 frame so APIs (GetInstanceInfo,
--- C_Map.GetBestMapForUnit) return populated data after a zone transition.
--- After subscription re-eval, dispatches the event to any active subsystem
--- that declared it in handlers.
function RN:_OnAlwaysOnEvent(event, ...)
    local args = { ... }
    C_Timer.After(0, function()
        if not self:IsEnabled() then return end
        self:_UpdateSubscriptions()
        for key, sub in pairs(SUBSYSTEMS) do
            if self._subActive[key] then
                local method = sub.handlers[event]
                if method then
                    self[method](self, event, unpack(args))
                end
            end
        end
    end)
end

--- Sub-gated event dispatcher. Single handler for any refcount-managed event.
--- Iterates active subsystems and routes to each one's declared handler.
function RN:_OnSubGatedEvent(event, ...)
    if not self._subActive then return end
    for key, sub in pairs(SUBSYSTEMS) do
        if self._subActive[key] then
            local method = sub.handlers[event]
            if method then
                self[method](self, event, ...)
            end
        end
    end
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
    for _, row in pairs(self.activeAlerts) do
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
-- combat events is zone-conditional (managed by the subscription orchestrator
-- via the Voidcore subsystem's shouldSubscribe gate) so we don't pay
-- event-dispatch overhead while the player is outside the relevant 11 instances.
function RN:OnChallengeModeStart()
    self._voidcoreKeyActive = true
    self:HideAlert("Voidcore")
end

function RN:EvaluateVoidcore()
    -- Preview mode drives visibility directly via ApplySettings's force-show
    -- loop. Bail out so the natural eval path doesn't hide the preview-shown
    -- alert based on out-of-game-zone state. Mirrors the isPreview gate in
    -- _SyncResetBossFromExistingSated / _OnResetBossCombatStart /
    -- _OnResetBossCombatEnd / OnEncounterEnd.
    if self.isPreview then return end
    if not self.db.VoidcoreEnabled then self:HideAlert("Voidcore"); return end
    -- _voidcoreKeyActive is set on CHALLENGE_MODE_START, but that event does
    -- NOT re-fire on /reload into an already-active key, and onScopeEnter
    -- resets the flag to false. Query the live challenge-mode state too, so a
    -- mid-key /reload doesn't re-show "BONUS ROLLS MISSING" inside the dungeon.
    if self._voidcoreKeyActive
        or (C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive()) then
        self:HideAlert("Voidcore"); return
    end
    if InCombatLockdown() then self:HideAlert("Voidcore"); return end
    if not IsInSeasonalZone() then self:HideAlert("Voidcore"); return end
    local info = C_CurrencyInfo.GetCurrencyInfo(VOIDCORE_CURRENCY_ID)
    -- discovered=false on characters who've never interacted with the currency
    -- system (verified via /dump on a fresh 90: discovered=false flips to true
    -- after the first NPC purchase). Without this gate, a fresh alt walking
    -- into a seasonal dungeon would see "BONUS ROLLS MISSING" despite having
    -- no way to engage with the currency yet.
    if not info or not info.discovered then self:HideAlert("Voidcore"); return end
    -- Voidcore is season-capped: cap is on lifetime earnings (totalEarned) up
    -- to maxQuantity, which grows by 2 each week of the season. The weekly-
    -- quantity fields (quantityEarnedThisWeek / maxWeeklyQuantity) are both 0
    -- and unused by this currency model.
    if info.totalEarned < info.maxQuantity then
        self:ShowAlert("Voidcore")
    else
        self:HideAlert("Voidcore")
    end
end

--- Direct hide rather than going through EvaluateVoidcore. PLAYER_REGEN_DISABLED
--- fires fractionally before InCombatLockdown() returns true, so the eval's
--- lockdown gate could fall through and re-show the alert.
function RN:_OnVoidcoreCombatStart()
    if self.isPreview then return end
    self:HideAlert("Voidcore")
end

---------------------------------------------------------------------------------
-- Gateway Logic
---------------------------------------------------------------------------------
--- AE-pattern Gateway evaluator. IsUsableItem(GATEWAY_ITEM_ID) already filters:
---   (a) item present in bags
---   (b) a warlock-in-range has deployed a gate
--- So we just check it and Show/Hide accordingly. Idempotent — ShowAlert
--- and HideAlert no-op when the alert is already in the desired state.
function RN:_CheckGatewayUsable()
    if self.isPreview then return end
    if not self.db.GatewayEnabled then return end
    if IsUsableItem(GATEWAY_ITEM_ID) then
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

--- BLT-pattern edge-triggered aura handler. Fires on a freshly-added sated
--- debuff, and clears on removal (a sated debuff falling off means the alert's
--- reason to exist is gone). The shouldSubscribe gate already confirmed we're
--- in a raid instance.
function RN:_OnResetBossAura(_, unit, updateInfo)
    if unit ~= "player" then return end
    if not updateInfo then return end
    if self.isPreview then return end

    if updateInfo.addedAuras then
        for _, info in pairs(updateInfo.addedAuras) do
            if info and info.auraInstanceID then
                local data = C_UnitAuras.GetAuraDataByAuraInstanceID("player", info.auraInstanceID)
                if data and data.spellId and not issecretvalue(data.spellId) then
                    for _, sated in ipairs(SATED_DEBUFFS) do
                        if data.spellId == sated then
                            self:_FireResetBoss()
                            return
                        end
                    end
                end
            end
        end
    end

    -- A sated/exhaustion debuff falling off (e.g. the boss reset that clears
    -- Bloodlust fatigue between pulls) should hide "RESET BOSS" immediately
    -- instead of leaving it up for the rest of the 40s auto-hide window.
    -- Removals arrive as removedAuraInstanceIDs with no spellId to match, so
    -- re-poll the live debuff state and clear if none remain. The resetBossGen
    -- bump cancels the pending auto-hide timer from _FireResetBoss.
    if (updateInfo.removedAuraInstanceIDs or updateInfo.isFullUpdate)
        and self.activeAlerts.ResetBoss and not self:HasLustDebuff() then
        self.resetBossGen = self.resetBossGen + 1
        self:HideAlert("ResetBoss")
    end
end

--- PEW sync: on entering a raid instance, check for an existing sated debuff
--- and fire the alert if one is present (handles /reload mid-debuff).
--- Mirrors BLT's SyncFromExistingAura pattern.
function RN:_SyncResetBossFromExistingSated()
    if self.isPreview then return end
    if InCombatLockdown() or UnitIsDeadOrGhost("player") then return end
    if self:HasLustDebuff() then
        self:_FireResetBoss()
    end
end

--- Shows the ResetBoss alert and starts the 40s auto-hide timer with
--- generation counter (so a subsequent fire invalidates pending hides).
function RN:_FireResetBoss()
    -- Only ever show out of combat (and while alive). Lust/Heroism is cast
    -- during the pull, so the sated aura is added mid-combat and the
    -- _OnResetBossAura edge-trigger would otherwise show "RESET BOSS" in
    -- combat. The combat-end path (_OnResetBossCombatEnd ->
    -- _SyncResetBossFromExistingSated) re-fires once the pull ends. This
    -- restores the gate the pre-refactor CheckResetBoss had inline.
    if InCombatLockdown() or UnitIsDeadOrGhost("player") then return end
    self:ShowAlert("ResetBoss")
    self.resetBossGen = self.resetBossGen + 1
    local gen = self.resetBossGen
    C_Timer.After(self.db.AlertDuration or 40, function()
        if self.resetBossGen == gen then
            self:HideAlert("ResetBoss")
        end
    end)
end

--- Hide ResetBoss on combat start. The 40s post-lust window only stays
--- visible out-of-combat; combat tag means the raid is no longer in
--- "between pulls" state, so the prompt is no longer actionable.
function RN:_OnResetBossCombatStart()
    if self.isPreview then return end
    self:HideAlert("ResetBoss")
end

function RN:_OnResetBossCombatEnd()
    if self.isPreview then return end
    -- 0.2s settle so aura events that fire alongside combat-end land first.
    -- IsEnabled() guards against the module being disabled mid-defer (e.g.
    -- profile switch); db.Enabled is the user-intent flag and doesn't flip
    -- until OnDisable runs, so we check the live module state instead.
    C_Timer.After(0.2, function()
        if not self:IsEnabled() then return end
        self:_SyncResetBossFromExistingSated()
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

    -- Mythic-only gate is now in BenchAlert.shouldSubscribe via GetInstanceInfo;
    -- CheckBench only runs when the subsystem is in scope (= mythic raid).

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

    KE:ApplyFramePosition(self.frame, self.db.Position, self.db)

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

    -- Re-evaluate subscriptions so live-toggling alert-enable flags from the
    -- GUI takes effect without /reload. Cheap when no toggles changed (the
    -- orchestrator's idempotency guard short-circuits unchanged subsystems).
    if self:IsEnabled() then
        self:_UpdateSubscriptions()
    end
end

---------------------------------------------------------------------------------
-- EditMode
---------------------------------------------------------------------------------
function RN:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "RaidNotifications", displayName = "Raid Notifications", frame = self.frame,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos) self.db.Position = pos; KE:ApplyFramePosition(self.frame, self.db.Position, self.db) end,
            getParentFrame = function() return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame) end,
            -- No sidebar row of its own anymore -- guiTab lands Open
            -- Settings on this module's tab of the Utilities page.
            guiPath = "Utilities",
            guiTab = "RaidNotifications",
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
    -- HideAllAlerts + orchestrator re-eval on every non-utilities section
    -- navigation.
    if not self.isPreview then return end

    self.isPreview = false
    self:HideAllAlerts()

    -- Only re-evaluate live state if the AceModule is actually enabled.
    -- During profile change, db.Enabled may flip true under the new profile
    -- before OnEnable fires — driving the orchestrator before frames
    -- exist would crash on nil indexing.
    if self.db.Enabled and self:IsEnabled() then
        self:_UpdateSubscriptions()
    end
end

---------------------------------------------------------------------------------
-- Subsystem Definitions
---------------------------------------------------------------------------------
-- Resolves the forward declaration at the top of the file. See spec doc for
-- contract: each entry has shouldSubscribe (pure boolean gate function),
-- handlers (event-to-method-name map), and optional onScopeEnter/onScopeExit
-- hooks (function or method-name string).

SUBSYSTEMS = {

    -------------------------------------------------------------------------
    Gateway = {
        shouldSubscribe = function(self)
            if not self.db.GatewayEnabled then return false end
            local _, instanceType = IsInInstance()
            return instanceType == "raid" or instanceType == "party"
        end,
        handlers = {
            ACTIONBAR_UPDATE_USABLE = "_CheckGatewayUsable",
        },
        onScopeEnter = "_CheckGatewayUsable",
        onScopeExit  = function(self) self:HideAlert("Gateway") end,
    },

    -------------------------------------------------------------------------
    ResetBoss = {
        shouldSubscribe = function(self)
            if not self.db.ResetBossEnabled then return false end
            return select(2, IsInInstance()) == "raid"
        end,
        handlers = {
            UNIT_AURA             = "_OnResetBossAura",
            PLAYER_REGEN_DISABLED = "_OnResetBossCombatStart",
            PLAYER_REGEN_ENABLED  = "_OnResetBossCombatEnd",
        },
        onScopeEnter = "_SyncResetBossFromExistingSated",
        onScopeExit  = function(self)
            self:HideAlert("ResetBoss")
            self.resetBossGen = self.resetBossGen + 1
        end,
    },

    -------------------------------------------------------------------------
    LootBoss = {
        shouldSubscribe = function(self)
            if not self.db.LootBossEnabled then return false end
            return select(2, IsInInstance()) == "raid"
        end,
        handlers = {
            ENCOUNTER_END    = "OnEncounterEnd",
            LOOT_OPENED      = "ClearLootBoss",
            CHAT_MSG_MONEY   = "ClearLootBoss",
            ENCOUNTER_START  = "ClearLootBoss",
        },
        onScopeEnter = nil,
        onScopeExit  = function(self)
            self:HideAlert("LootBoss")
            self.lootBossGen = self.lootBossGen + 1
        end,
    },

    -------------------------------------------------------------------------
    BenchAlert = {
        shouldSubscribe = function(self)
            if not self.db.BenchEnabled then return false end
            -- Single GetInstanceInfo call gives us both instanceType and
            -- difficultyID — cheaper than IsInInstance() + GetInstanceInfo().
            local _, instanceType, difficultyID = GetInstanceInfo()
            if instanceType ~= "raid" then return false end
            return difficultyID == 16  -- mythic raid only
        end,
        handlers = {
            -- GROUP_ROSTER_UPDATE is in MODULE_ALWAYS_ON_EVENTS — orchestrator
            -- routes here when BenchAlert is subscribed without re-registering.
            GROUP_ROSTER_UPDATE = "CheckBench",
        },
        onScopeEnter = "CheckBench",
        onScopeExit  = function(self) self:HideAlert("BenchAlert") end,
    },

    -------------------------------------------------------------------------
    Voidcore = {
        shouldSubscribe = function(self)
            return self.db.VoidcoreEnabled and IsInSeasonalZone()
        end,
        handlers = {
            CURRENCY_DISPLAY_UPDATE = "EvaluateVoidcore",
            CHALLENGE_MODE_START    = "OnChallengeModeStart",
            PLAYER_REGEN_DISABLED   = "_OnVoidcoreCombatStart",
            PLAYER_REGEN_ENABLED    = "EvaluateVoidcore",
        },
        onScopeEnter = function(self)
            self._voidcoreKeyActive = false
            self:EvaluateVoidcore()
        end,
        onScopeExit = function(self)
            self:HideAlert("Voidcore")
            self._voidcoreKeyActive = false
        end,
    },
}

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function RN:OnInitialize()
    self:UpdateDB()
    self:MigrateFromGatewayAlert()
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

    -- Initialize orchestrator state
    self._subActive = {}
    self._eventRefcount = {}

    -- Register the 3 always-on lifecycle events to the orchestrator dispatcher.
    -- Per-alert events get registered dynamically by _UpdateSubscriptions via
    -- the refcount mechanism in _ApplySubscriptionDelta.
    for event in pairs(MODULE_ALWAYS_ON_EVENTS) do
        self:RegisterEvent(event, "_OnAlwaysOnEvent")
    end

    -- Initial subscription eval. Deferred 1 frame so APIs return fresh data
    -- after a /reload (same reason _OnAlwaysOnEvent defers).
    C_Timer.After(0, function()
        if not self:IsEnabled() then return end
        self:_UpdateSubscriptions()
    end)
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

    -- Wipe orchestrator state so the next OnEnable rebuilds from zero
    self._subActive = nil
    self._eventRefcount = nil

    -- Wipe legacy/alert state
    self.isPreview = false
    self._voidcoreKeyActive = false
    self.resetBossGen = self.resetBossGen + 1
    self.lootBossGen = self.lootBossGen + 1
end
