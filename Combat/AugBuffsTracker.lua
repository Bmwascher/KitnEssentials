-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

-- Create module
---@class AugBuffsTracker: AceModule, AceEvent-3.0
local ABT = KitnEssentials:NewModule("AugBuffsTracker", "AceEvent-3.0")

-- Localization
local C_UnitAuras = C_UnitAuras
local C_Spell = C_Spell
local C_Timer = C_Timer
local CreateFrame = CreateFrame
local GetTime = GetTime
local GetNumGroupMembers = GetNumGroupMembers
local IsInRaid = IsInRaid
local UnitExists = UnitExists
local UnitName = UnitName
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local GetSpecialization = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo
local issecretvalue = issecretvalue
local string_format = string.format
local math_floor = math.floor
local table_insert = table.insert
local table_remove = table.remove
local wipe = wipe

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------
local PRESCIENCE_ID = 410089
local PRESCIENCE_ICON = 5199639
local SHIFTING_SANDS_ID = 413984
local SHIFTING_SANDS_ICON = 5199633
local AUG_SPEC_ID = 1473
local REFRESH_INTERVAL = 0.1

-- Buff definitions
local BUFF_DEFS = {
    [PRESCIENCE_ID] = { icon = PRESCIENCE_ICON, key = "ShowPrescience", label = "Prescience" },
    [SHIFTING_SANDS_ID] = { icon = SHIFTING_SANDS_ICON, key = "ShowShiftingSands", label = "Shifting Sands" },
}

-- Spell names cached at load (resolved once)
local SPELL_NAMES = {}

local ROLE_ATLASES = {
    DAMAGER = "groupfinder-icon-role-large-dps",
    TANK = "groupfinder-icon-role-large-tank",
    HEALER = "groupfinder-icon-role-large-heal",
}

---------------------------------------------------------------------------------
-- Module state
---------------------------------------------------------------------------------
ABT.containerFrame = nil
ABT.tickerFrame = nil
ABT.trackedBuffs = {}     -- [auraInstanceID] = { unit, name, spellID, expirationTime, role, isCrit }
ABT.activeEntries = {}    -- [auraInstanceID] = entryFrame
ABT.entryPool = {}        -- reusable display entries
ABT.sortedEntries = {}    -- ordered for layout
ABT.isAugSpec = false
ABT.isPreview = false
ABT.editModeRegistered = false
ABT.elapsed = 0

---------------------------------------------------------------------------------
-- UpdateDB
---------------------------------------------------------------------------------
function ABT:UpdateDB()
    self.db = KE.db.profile.AugBuffsTracker
end

---------------------------------------------------------------------------------
-- Spec Detection
---------------------------------------------------------------------------------
local function IsAugSpec()
    local specIndex = GetSpecialization()
    if not specIndex then return false end
    local specID = GetSpecializationInfo(specIndex)
    return specID == AUG_SPEC_ID
end

function ABT:OnSpecChanged()
    self.isAugSpec = IsAugSpec()
    if self.isPreview then return end

    if self.isAugSpec and self.db.Enabled then
        self:ScanAllUnits()
        self:LayoutEntries()
        if self.containerFrame then self.containerFrame:Show() end
    else
        self:ClearAllEntries()
        if self.containerFrame then self.containerFrame:Hide() end
    end
end

---------------------------------------------------------------------------------
-- Spell Name Resolution
---------------------------------------------------------------------------------
local function ResolveSpellNames()
    for spellID in pairs(BUFF_DEFS) do
        local name = C_Spell.GetSpellName(spellID)
        if name then
            SPELL_NAMES[spellID] = name
        end
    end
end

---------------------------------------------------------------------------------
-- Aura Detection
---------------------------------------------------------------------------------
function ABT:ScanUnit(unit)
    if not UnitExists(unit) then return end

    for spellID, def in pairs(BUFF_DEFS) do
        if self.db[def.key] ~= false then
            local spellName = SPELL_NAMES[spellID]
            if spellName then
                local aura = C_UnitAuras.GetAuraDataBySpellName(unit, spellName, "HELPFUL|PLAYER")
                if aura and aura.auraInstanceID then
                    -- Only track our own casts
                    if not aura.sourceUnit or aura.sourceUnit == "player" then
                        self:AddTrackedBuff(unit, aura, spellID)
                    end
                end
            end
        end
    end
end

function ABT:ScanAllUnits()
    -- Clear existing tracked data
    wipe(self.trackedBuffs)

    if not self.isAugSpec and not self.isPreview then return end

    self:ScanRoster()
    self:SyncEntries()
    self:LayoutEntries()
end

-- Additive re-scan: check all roster units without wiping existing data.
-- Matching reference FullRaidCheck: just scans and adds, safe to call in combat.
function ABT:RescanRoster()
    if not self.isAugSpec then return end
    self:ScanRoster()
    self:SyncEntries()
    self:LayoutEntries()
end

-- Shared roster iteration for both full and additive scans
function ABT:ScanRoster()
    self:ScanUnit("player")
    local size = GetNumGroupMembers()
    if size > 0 then
        local token = IsInRaid() and "raid" or "party"
        for i = 1, size do
            local unit = token .. i
            if UnitExists(unit) then
                self:ScanUnit(unit)
            end
        end
    end
end

function ABT:AddTrackedBuff(unit, aura, spellID)
    if not aura.auraInstanceID then return end

    -- Guard: if expirationTime is secret (API call in combat), skip — can't track timer
    if aura.expirationTime and issecretvalue(aura.expirationTime) then return end

    local name = UnitName(unit) or "?"
    local role = UnitGroupRolesAssigned(unit) or "NONE"
    local _, classToken = UnitClass(unit)

    -- Prescience crit detection (matching reference: aura.points[1] == 6)
    local isCrit = false
    if aura.points and not issecretvalue(aura.points) then
        isCrit = aura.points[1] == 6 and spellID == PRESCIENCE_ID
    end

    self.trackedBuffs[aura.auraInstanceID] = {
        unit = unit,
        name = name,
        spellID = spellID,
        expirationTime = aura.expirationTime or 0,
        duration = aura.duration or 0,
        role = role,
        classToken = classToken,
        isCrit = isCrit,
        icon = BUFF_DEFS[spellID] and BUFF_DEFS[spellID].icon or 134400,
    }
end

function ABT:RemoveTrackedBuff(auraInstanceID)
    self.trackedBuffs[auraInstanceID] = nil
    self:ReleaseEntry(auraInstanceID)
end

function ABT:OnUnitAura(_, unit, info)
    if not unit then return end
    if not self.db.Enabled or self.isPreview then return end
    if not self.isAugSpec then return end

    -- Skip non-party/raid units (nameplates, etc.)
    if unit ~= "player" and not unit:find("^party%d") and not unit:find("^raid%d") then return end

    -- Skip pet units
    if unit:find("pet") then return end

    if not info then return end

    local changed = false

    if info.isFullUpdate then
        if not InCombatLockdown() then
            for id, data in pairs(self.trackedBuffs) do
                if data.unit == unit then
                    self.trackedBuffs[id] = nil
                end
            end
            self:ScanUnit(unit)
            changed = true
        end
    else
        -- Incremental update: process event payload directly
        if info.addedAuras then
            for _, aura in ipairs(info.addedAuras) do
                if not issecretvalue(aura.applications) then
                    local def = BUFF_DEFS[aura.spellId]
                    if def and self.db[def.key] ~= false and aura.sourceUnit == "player" then
                        self:AddTrackedBuff(unit, aura, aura.spellId)
                        changed = true
                        break
                    end
                end
            end
        end

        if info.updatedAuraInstanceIDs then
            for _, instanceID in ipairs(info.updatedAuraInstanceIDs) do
                local tracked = self.trackedBuffs[instanceID]
                if tracked and tracked.unit == unit then
                    local aura = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, instanceID)
                    if aura then
                        if not issecretvalue(aura.expirationTime) then
                            tracked.expirationTime = aura.expirationTime
                            tracked.duration = aura.duration or 0
                            tracked.isCrit = aura.points and aura.points[1] == 6 and aura.spellId == PRESCIENCE_ID
                            changed = true
                        end
                    end
                end
            end
        end

        if info.removedAuraInstanceIDs then
            for _, instanceID in ipairs(info.removedAuraInstanceIDs) do
                -- Match reference: check BOTH instanceID AND unit before removing.
                -- Aura instance IDs are per-unit, not global — different units can share the same ID.
                local data = self.trackedBuffs[instanceID]
                if data and data.unit == unit then
                    self:RemoveTrackedBuff(instanceID)
                    changed = true
                end
            end
        end
    end

    if changed then
        self:SyncEntries()
        self:LayoutEntries()
    end
end

---------------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------------
function ABT:CreateFrames()
    if self.containerFrame then return end

    local frame = CreateFrame("Frame", "KE_AugBuffsTrackerFrame", UIParent)
    frame:SetSize(1, 1)
    frame:SetFrameStrata(self.db.Strata or "MEDIUM")
    self.containerFrame = frame
    frame:Hide()

    -- Ticker frame (always shown so OnUpdate fires)
    local ticker = CreateFrame("Frame", nil, UIParent)
    ticker:SetSize(1, 1)
    ticker:Show()
    self.tickerFrame = ticker
end

function ABT:CreateEntry()
    local db = self.db
    local entry = CreateFrame("Frame", nil, self.containerFrame)
    entry:SetSize(db.IconSize or 32, (db.IconSize or 32) + 20)

    -- Buff icon
    local icon = entry:CreateTexture(nil, "ARTWORK")
    icon:SetSize(db.IconSize or 32, db.IconSize or 32)
    icon:SetPoint("TOP", entry, "TOP", 0, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    entry.icon = icon

    -- Role badge (small overlay on icon)
    local roleBadge = entry:CreateTexture(nil, "OVERLAY")
    roleBadge:SetSize(12, 12)
    roleBadge:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
    entry.roleBadge = roleBadge

    -- Timer text (on icon)
    local timer = entry:CreateFontString(nil, "OVERLAY")
    timer:SetPoint("CENTER", icon, "CENTER", 0, 0)
    entry.timer = timer

    -- Name text (below icon)
    local name = entry:CreateFontString(nil, "OVERLAY")
    name:SetPoint("TOP", icon, "BOTTOM", 0, -2)
    entry.nameText = name

    entry:Hide()
    return entry
end

function ABT:GetOrCreateEntry(auraInstanceID)
    if self.activeEntries[auraInstanceID] then
        return self.activeEntries[auraInstanceID]
    end

    local entry = table_remove(self.entryPool)
    if not entry then
        entry = self:CreateEntry()
    end

    self.activeEntries[auraInstanceID] = entry
    return entry
end

function ABT:ReleaseEntry(auraInstanceID)
    local entry = self.activeEntries[auraInstanceID]
    if not entry then return end

    entry:Hide()
    self.activeEntries[auraInstanceID] = nil
    table_insert(self.entryPool, entry)
end

function ABT:ClearAllEntries()
    for id in pairs(self.activeEntries) do
        self:ReleaseEntry(id)
    end
    wipe(self.trackedBuffs)
    wipe(self.sortedEntries)
end

-- Sync display entries with tracked buffs
function ABT:SyncEntries()
    -- Release entries for buffs no longer tracked
    for id in pairs(self.activeEntries) do
        if not self.trackedBuffs[id] then
            self:ReleaseEntry(id)
        end
    end

    -- Create entries for newly tracked buffs
    for id, data in pairs(self.trackedBuffs) do
        local entry = self:GetOrCreateEntry(id)
        self:UpdateEntryVisuals(entry, data)
        entry:Show()
    end
end

function ABT:UpdateEntryVisuals(entry, data)
    local db = self.db

    -- Icon
    entry.icon:SetTexture(data.icon)
    entry.icon:SetSize(db.IconSize or 32, db.IconSize or 32)

    -- Role badge
    local showRole = db.ShowRoleIcon ~= false
    if showRole and ROLE_ATLASES[data.role] then
        local scale = db.RoleIconScale or 1.0
        local badgeSize = 12 * scale
        entry.roleBadge:SetSize(badgeSize, badgeSize)
        entry.roleBadge:SetAtlas(ROLE_ATLASES[data.role])
        entry.roleBadge:Show()
    else
        entry.roleBadge:Hide()
    end

    -- Name
    KE:ApplyFont(entry.nameText, db.NameFontFace, db.NameFontSize, db.NameFontOutline)
    if db.ShowNames ~= false then
        local displayName = data.name or ""
        local maxLen = db.NameMaxLength or 0
        if maxLen > 0 and #displayName > maxLen then
            displayName = displayName:sub(1, maxLen)
        end
        entry.nameText:SetText(displayName)
        if data.isCrit then
            local cc = db.CritColor
            entry.nameText:SetTextColor(cc[1], cc[2], cc[3], cc[4] or 1)
        elseif db.ClassColorNames and data.classToken then
            local color = C_ClassColor and C_ClassColor.GetClassColor(data.classToken)
            if color then
                entry.nameText:SetTextColor(color.r, color.g, color.b, 1)
            else
                local nc = db.NameColor
                entry.nameText:SetTextColor(nc[1], nc[2], nc[3], nc[4] or 1)
            end
        else
            local nc = db.NameColor
            entry.nameText:SetTextColor(nc[1], nc[2], nc[3], nc[4] or 1)
        end
        entry.nameText:Show()
    else
        entry.nameText:Hide()
    end

    -- Timer
    KE:ApplyFont(entry.timer, db.TimerFontFace, db.TimerFontSize, db.TimerFontOutline)
    local tc = data.isCrit and db.CritColor or db.TimerColor
    entry.timer:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)

    -- Entry size
    local iconSize = db.IconSize or 32
    local nameHeight = (db.ShowNames ~= false) and (db.NameFontSize + 4) or 0
    entry:SetSize(iconSize, iconSize + nameHeight)
end

function ABT:LayoutEntries()
    if not self.containerFrame then return end

    local db = self.db
    local spacing = db.Spacing or 4
    local maxEntries = db.MaxEntries or 6

    -- Build sorted list: Prescience first, then Shifting Sands
    wipe(self.sortedEntries)
    local presEntries = {}
    local sandEntries = {}

    for id, data in pairs(self.trackedBuffs) do
        local entry = self.activeEntries[id]
        if entry then
            if data.spellID == PRESCIENCE_ID then
                table_insert(presEntries, { id = id, entry = entry, data = data })
            else
                table_insert(sandEntries, { id = id, entry = entry, data = data })
            end
        end
    end

    -- Sort each group by remaining time (shortest first)
    local now = GetTime()
    local function sortByTime(a, b)
        return (a.data.expirationTime - now) < (b.data.expirationTime - now)
    end
    table.sort(presEntries, sortByTime)
    table.sort(sandEntries, sortByTime)

    for _, e in ipairs(presEntries) do table_insert(self.sortedEntries, e) end
    for _, e in ipairs(sandEntries) do table_insert(self.sortedEntries, e) end

    -- Growth direction — same pattern as KickTracker: entries anchor to the
    -- container's edge, container resizes to fit. Position system anchors from
    -- CENTER so the block shifts slightly when entry count changes — this is
    -- normal and matches KickTracker behavior.
    local growth = db.GrowthDirection or "DOWN"
    local iconSize = db.IconSize or 32
    local nameHeight = (db.ShowNames ~= false) and ((db.NameFontSize or 12) + 4) or 0
    local entryH = iconSize + nameHeight

    -- Position entries with offset from container edge
    local count = 0
    for i, sorted in ipairs(self.sortedEntries) do
        if i > maxEntries then
            sorted.entry:Hide()
        else
            sorted.entry:ClearAllPoints()
            local step = (i - 1) * (entryH + spacing)
            local stepH = (i - 1) * (iconSize + spacing)

            if growth == "DOWN" then
                sorted.entry:SetPoint("TOPLEFT", self.containerFrame, "TOPLEFT", 0, -step)
            elseif growth == "UP" then
                sorted.entry:SetPoint("BOTTOMLEFT", self.containerFrame, "BOTTOMLEFT", 0, step)
            elseif growth == "RIGHT" then
                sorted.entry:SetPoint("TOPLEFT", self.containerFrame, "TOPLEFT", stepH, 0)
            elseif growth == "LEFT" then
                sorted.entry:SetPoint("TOPRIGHT", self.containerFrame, "TOPRIGHT", -stepH, 0)
            end

            sorted.entry:Show()
            count = count + 1
        end
    end

    -- Resize container to fit content (EditMode overlay uses SetAllPoints)
    local visibleCount = math.max(count, 1)
    if growth == "DOWN" or growth == "UP" then
        self.containerFrame:SetSize(iconSize, visibleCount * (entryH + spacing) - spacing)
    else
        self.containerFrame:SetSize(visibleCount * (iconSize + spacing) - spacing, entryH)
    end
end

---------------------------------------------------------------------------------
-- OnUpdate Ticker
---------------------------------------------------------------------------------
function ABT:StartOnUpdate()
    if not self.tickerFrame then return end
    self.tickerFrame:SetScript("OnUpdate", function(_, dt)
        if self.isPreview then return end
        self.elapsed = self.elapsed + dt
        if self.elapsed < REFRESH_INTERVAL then return end
        self.elapsed = 0
        self:UpdateTimers()
    end)
end

function ABT:StopOnUpdate()
    if self.tickerFrame then
        self.tickerFrame:SetScript("OnUpdate", nil)
    end
    self.elapsed = 0
end

function ABT:UpdateTimers()
    if not self.isAugSpec or not self.db.Enabled then return end

    local now = GetTime()
    local anyExpired = false

    for id, data in pairs(self.trackedBuffs) do
        if data.expirationTime then
            local remaining = data.expirationTime - now
            if remaining < 0 then
                self:RemoveTrackedBuff(id)
                anyExpired = true
            else
                local entry = self.activeEntries[id]
                if entry and entry.timer then
                    if remaining > 6 then
                        entry.timer:SetText(string_format("%d", math_floor(remaining)))
                    else
                        entry.timer:SetText(string_format("%.1f", remaining))
                    end
                end
            end
        end
    end

    if anyExpired then
        self:LayoutEntries()
    end

    -- If no tracked buffs, try to re-detect via additive scan (doesn't wipe first).
    -- Matching reference: FullRaidCheck runs regardless of combat state.
    local hasAny = false
    for _ in pairs(self.trackedBuffs) do hasAny = true; break end
    if not hasAny then
        self:RescanRoster()
    end
end

---------------------------------------------------------------------------------
-- Apply Settings
---------------------------------------------------------------------------------
function ABT:ApplySettings()
    if not self.containerFrame then return end

    KE:ApplyFramePosition(self.containerFrame, self.db.Position, self.db)

    if self.db.Strata then
        self.containerFrame:SetFrameStrata(self.db.Strata)
    end

    -- Re-apply visuals to all active entries
    for id, entry in pairs(self.activeEntries) do
        local data = self.trackedBuffs[id]
        if data then
            self:UpdateEntryVisuals(entry, data)
        end
    end

    self:LayoutEntries()
end

---------------------------------------------------------------------------------
-- EditMode
---------------------------------------------------------------------------------
function ABT:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "AugBuffsTracker",
            displayName = "Aug Buffs Tracker",
            frame = self.containerFrame,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos)
                self.db.Position = pos
                KE:ApplyFramePosition(self.containerFrame, self.db.Position, self.db)
            end,
            getParentFrame = function()
                return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame)
            end,
            guiPath = "AugBuffsTracker",
        })
        self.editModeRegistered = true
    end
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------
function ABT:ShowPreview()
    if not self.containerFrame then
        self:CreateFrames()
    end
    self:RegWithEditMode()

    self.isPreview = true

    -- Create mock entries
    local mockData = {
        { name = "Mage", spellID = PRESCIENCE_ID, icon = PRESCIENCE_ICON, role = "DAMAGER", isCrit = false, remaining = 18, classToken = "MAGE" },
        { name = "Warrior", spellID = PRESCIENCE_ID, icon = PRESCIENCE_ICON, role = "DAMAGER", isCrit = true, remaining = 12, classToken = "WARRIOR" },
        { name = "Rogue", spellID = PRESCIENCE_ID, icon = PRESCIENCE_ICON, role = "DAMAGER", isCrit = false, remaining = 6, classToken = "ROGUE" },
    }

    -- Add Shifting Sands mock if enabled
    if self.db.ShowShiftingSands then
        table_insert(mockData, { name = "Hunter", spellID = SHIFTING_SANDS_ID, icon = SHIFTING_SANDS_ICON, role = "DAMAGER", isCrit = false, remaining = 9, classToken = "HUNTER" })
    end

    wipe(self.trackedBuffs)
    for i, mock in ipairs(mockData) do
        local fakeID = 900000 + i
        self.trackedBuffs[fakeID] = {
            unit = "player",
            name = mock.name,
            spellID = mock.spellID,
            expirationTime = GetTime() + mock.remaining,
            duration = 30,
            role = mock.role,
            classToken = mock.classToken,
            isCrit = mock.isCrit,
            icon = mock.icon,
        }
    end

    self:SyncEntries()

    -- Set mock timer text
    for id, data in pairs(self.trackedBuffs) do
        local entry = self.activeEntries[id]
        if entry and entry.timer then
            local remaining = data.expirationTime - GetTime()
            entry.timer:SetText(string_format("%d", math_floor(remaining)))
        end
    end

    self:LayoutEntries()
    self.containerFrame:SetAlpha(1)
    self.containerFrame:Show()
    self:ApplySettings()
end

function ABT:HidePreview()
    self.isPreview = false
    self:ClearAllEntries()

    if self.db.Enabled and self.isAugSpec then
        self:ScanAllUnits()
        self.containerFrame:Show()
    else
        if self.containerFrame then self.containerFrame:Hide() end
    end
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function ABT:OnInitialize()
    self:UpdateDB()
    self.isAugSpec = IsAugSpec()
    self:SetEnabledState(false)
end

function ABT:OnEnable()
    if not self.db.Enabled then return end

    ResolveSpellNames()
    self:CreateFrames()
    self:RegWithEditMode()
    self.isAugSpec = IsAugSpec()

    self:RegisterEvent("UNIT_AURA", "OnUnitAura")
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnRosterUpdate")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnZoneChange")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnSpecChanged")

    self:StartOnUpdate()

    C_Timer.After(0.5, function()
        if not self.db or not self.db.Enabled then return end
        self:ApplySettings()
        if self.isAugSpec then
            self:ScanAllUnits()
            self.containerFrame:Show()
        end
    end)
end

function ABT:OnRosterUpdate()
    -- Roster changes don't invalidate existing buff data.
    -- Out of combat: additive re-scan to pick up new members.
    -- In combat: skip — UNIT_AURA handles everything, API unreliable.
    if not InCombatLockdown() then
        self:RescanRoster()
    end
end

function ABT:OnZoneChange()
    if not self.db.Enabled then return end
    C_Timer.After(0.5, function()
        if not self.db or not self.db.Enabled then return end
        ResolveSpellNames()
        if self.isAugSpec then
            self:ScanAllUnits()
        end
    end)
end

function ABT:OnDisable()
    self:UnregisterAllEvents()
    self:StopOnUpdate()
    self:ClearAllEntries()
    self.isPreview = false
    if self.containerFrame then self.containerFrame:Hide() end
end
