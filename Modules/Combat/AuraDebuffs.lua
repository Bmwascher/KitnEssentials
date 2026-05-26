-- ╔══════════════════════════════════════════════════════════╗
-- ║  AuraDebuffs.lua                                         ║
-- ║  Module: Aura Debuffs                                    ║
-- ║  Purpose: Displays dispellable/important debuffs on the  ║
-- ║           player with dispel-type filtering, blocklist,  ║
-- ║           and visibility gating (boss/instance/always).  ║
-- ║  Subsumes: BossDebuffs (migrated then deleted).          ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class AuraDebuffs: AceModule, AceEvent-3.0
local AD = KitnEssentials:NewModule("AuraDebuffs", "AceEvent-3.0")

local C_UnitAuras        = C_UnitAuras
local CreateFrame        = CreateFrame
local UIParent           = UIParent
local GameTooltip        = GameTooltip
local IsInInstance       = IsInInstance
local UnitAffectingCombat = UnitAffectingCombat
local GetTime            = GetTime
local C_Timer            = C_Timer
local pairs, ipairs      = pairs, ipairs
local tinsert            = table.insert
local tsort              = table.sort
local tconcat            = table.concat
local math_min           = math.min
local math_floor         = math.floor
local string_gmatch      = string.gmatch

local UNIT = "player"

---------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------

-- Default blocklist entries (populated once on first enable).
-- These are non-boss Bloodlust variants the player never wants cluttering
-- the display. label = human-readable name; enabled = active by default.
local DEFAULT_BLOCKLIST = {
    [390435] = { label = "Frenzy (BL Hunter)",    enabled = true, default = true },
    [57723]  = { label = "Drums of the Maelstrom", enabled = true, default = true },
    [95809]  = { label = "Heroism (BL Hunter)",    enabled = true, default = true },
    [80354]  = { label = "Time Warp (BL Mage)",    enabled = true, default = true },
    [308312] = { label = "Time Trial",              enabled = true, default = true },
    [57724]  = { label = "Bloodlust (BL Shaman)",  enabled = true, default = true },
    [160455] = { label = "Primal Rage (BL Hunter)", enabled = true, default = true },
    [264689] = { label = "Primal Rage (BL Hunter 2)", enabled = true, default = true },
}

-- Dispel-type overlays using Blizzard's raid-frame atlases.
local DISPEL_ICON_ATLASES = {
    [Enum.DispelType.Magic]   = "RaidFrame-Icon-DebuffMagic",
    [Enum.DispelType.Curse]   = "RaidFrame-Icon-DebuffCurse",
    [Enum.DispelType.Disease] = "RaidFrame-Icon-DebuffDisease",
    [Enum.DispelType.Poison]  = "RaidFrame-Icon-DebuffPoison",
    [Enum.DispelType.Bleed]   = "RaidFrame-Icon-DebuffBleed",
}

-- Filter keys surfaced in the GUI (match Defaults.lua Filters sub-table).
local FILTER_KEYS = {
    "PLAYER", "RAID", "CANCELABLE", "NOT_CANCELABLE",
    "INCLUDE_NAME_PLATE_ONLY", "EXTERNAL_DEFENSIVE",
    "CROWD_CONTROL", "RAID_IN_COMBAT",
    "RAID_PLAYER_DISPELLABLE", "BIG_DEFENSIVE", "IMPORTANT",
}

-- Fake auras shown during GUI preview.
local PREVIEW_AURAS = {
    { spellId = 240443, icon = 1392954, duration = 8,  expirationTime = 0, count = 0, dispelType = "Magic",   dispelEnum = Enum.DispelType.Magic },
    { spellId = 396369, icon = 1391539, duration = 10, expirationTime = 0, count = 2, dispelType = "Curse",   dispelEnum = Enum.DispelType.Curse },
    { spellId = 240559, icon = 514016,  duration = 6,  expirationTime = 0, count = 0, dispelType = "Bleed",   dispelEnum = Enum.DispelType.Bleed },
}

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------

AD.buttons          = {}
AD.frame            = nil
AD.inEncounter      = false
AD.inCombat         = false
AD.inInstance       = false
AD.encounterID      = nil
AD.encounterBlacklist = {}
AD.isPreview        = false
AD.editModeRegistered = false
AD.durationTicker   = nil

---------------------------------------------------------------------------------
-- One-shot Migration: BossDebuffs → AuraDebuffs
---------------------------------------------------------------------------------

local function MigrateFromBossDebuffs(profile)
    local oldBD = profile.BossDebuffs
    local ad    = profile.AuraDebuffs
    if not oldBD or not ad or ad._migratedFromBD then return end
    ad._migratedFromBD = true

    if oldBD.Enabled                   then ad.Enabled           = true end
    ad.VisibilityMode     = oldBD.VisibilityMode     or ad.VisibilityMode
    ad.EncounterBlacklist = oldBD.EncounterBlacklist or ad.EncounterBlacklist
    ad.Position           = oldBD.Position           or ad.Position
    ad.anchorFrameType    = oldBD.anchorFrameType    or ad.anchorFrameType
    ad.IconSize           = oldBD.IconSize           or ad.IconSize
    ad.Strata             = oldBD.Strata             or ad.Strata
end

---------------------------------------------------------------------------------
-- DB Helpers
---------------------------------------------------------------------------------

function AD:UpdateDB()
    self.db = KE.db.profile.AuraDebuffs
end

-- Seed the persistent blocklist with any DEFAULT_BLOCKLIST entries that are
-- not yet present (preserves user overrides on already-present entries).
function AD:ApplyDefaultBlocklist()
    local bl = self.db.Blocklist
    if not bl then self.db.Blocklist = {}; bl = self.db.Blocklist end
    for sid, entry in pairs(DEFAULT_BLOCKLIST) do
        if bl[sid] == nil then
            bl[sid] = { label = entry.label, enabled = entry.enabled, default = entry.default }
        end
    end
end

-- Parse a comma-separated string of encounter IDs into a set table.
local function ParseEncounterBlacklist(str)
    local result = {}
    if not str or str == "" then return result end
    for id in string_gmatch(str, "[^,]+") do
        local trimmed = id:match("^%s*(.-)%s*$")
        local num = tonumber(trimmed)
        if num then result[num] = true end
    end
    return result
end

function AD:RefreshEncounterBlacklist()
    self.encounterBlacklist = ParseEncounterBlacklist(self.db.EncounterBlacklist)
end

-- Build the GetAuraDataByIndex filter string from the active Filters sub-table.
-- Returns at minimum "HARMFUL"; appends pipe-separated active filter tokens.
function AD:BuildFilterString()
    local db = self.db
    local parts = {}
    for _, key in ipairs(FILTER_KEYS) do
        if db.Filters and db.Filters[key] then
            tinsert(parts, key)
        end
    end
    if #parts > 0 then
        return "HARMFUL|" .. tconcat(parts, "|")
    end
    return "HARMFUL"
end

---------------------------------------------------------------------------------
-- Visibility Logic
---------------------------------------------------------------------------------

function AD:ShouldShow()
    if not self.db.Enabled then return false end
    if self.isPreview      then return true  end

    local mode = self.db.VisibilityMode or "boss"

    if mode == "boss" then
        if self.encounterID and self.encounterBlacklist[self.encounterID] then
            return false
        end
        return self.inEncounter
    elseif mode == "instance" then
        return self.inCombat and self.inInstance
    elseif mode == "always" then
        return self.inCombat
    end

    return false
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------

function AD:OnInitialize()
    MigrateFromBossDebuffs(KE.db.profile)
    self:UpdateDB()
    self:ApplyDefaultBlocklist()
    self:RefreshEncounterBlacklist()
    self:SetEnabledState(false)
end

function AD:OnEnable()
    self:UpdateDB()
    self:RefreshEncounterBlacklist()
    if not self.frame then self:CreateContainer() end

    self:RegisterEvent("UNIT_AURA",              "OnUnitAura")
    self:RegisterEvent("ENCOUNTER_START",         "OnEncounterStart")
    self:RegisterEvent("ENCOUNTER_END",           "OnEncounterEnd")
    self:RegisterEvent("PLAYER_REGEN_ENABLED",    "OnRegenEnabled")
    self:RegisterEvent("PLAYER_REGEN_DISABLED",   "OnRegenDisabled")
    self:RegisterEvent("PLAYER_ENTERING_WORLD",   "OnEnteringWorld")

    -- Seed combat/instance state so the first Refresh has correct visibility.
    self.inCombat = UnitAffectingCombat("player") and true or false
    local _, instanceType = IsInInstance()
    self.inInstance = (instanceType == "raid" or instanceType == "party")

    self:Refresh()
    self:StartDurationTicker()
end

function AD:OnDisable()
    self:UnregisterAllEvents()
    self:StopDurationTicker()
    if self.frame then self.frame:Hide() end
    for _, b in pairs(self.buttons) do
        b._expirationTime = nil
        b._duration = nil
        b.timer:SetText("")
        b:Hide()
    end
end

function AD:ApplySettings()
    self:UpdateDB()
    self:RefreshEncounterBlacklist()
    self:ApplyDefaultBlocklist()
    if self.frame then
        KE:ApplyFramePositionWithSnap(self.frame, self.db.Position, self.db)
        self.frame:SetFrameStrata(self.db.Strata or "MEDIUM")
    end
    self:Refresh()
end

---------------------------------------------------------------------------------
-- Event Handlers
---------------------------------------------------------------------------------

function AD:OnEncounterStart(_, encounterID)
    self.inEncounter = true
    self.encounterID = encounterID
    self:Refresh()
end

function AD:OnEncounterEnd()
    self.inEncounter = false
    self.encounterID = nil
    self:Refresh()
end

function AD:OnRegenEnabled()
    self.inCombat = false
    self:Refresh()
end

function AD:OnRegenDisabled()
    self.inCombat = true
    self:Refresh()
end

function AD:OnEnteringWorld()
    local _, instanceType = IsInInstance()
    self.inInstance = (instanceType == "raid" or instanceType == "party")
    self:Refresh()
end

function AD:OnUnitAura(_, unit)
    if unit ~= UNIT then return end
    self:Refresh()
end

---------------------------------------------------------------------------------
-- Container + EditMode
---------------------------------------------------------------------------------

function AD:CreateContainer()
    if self.frame then return end
    local frame = CreateFrame("Frame", "KE_AuraDebuffs", UIParent)
    frame:SetSize(1, 1)
    frame:SetFrameStrata(self.db.Strata or "MEDIUM")
    self.frame = frame
    KE:ApplyFramePositionWithSnap(frame, self.db.Position, self.db)
    self:RegWithEditMode()
end

function AD:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key         = "AuraDebuffs",
            displayName = "Aura Debuffs",
            frame       = self.frame,
            getPosition = function()
                return self.db.Position
            end,
            setPosition = function(pos)
                self.db.Position = pos
                KE:ApplyFramePositionWithSnap(self.frame, self.db.Position, self.db)
            end,
            getParentFrame = function()
                return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame)
            end,
            guiPath = "AuraDebuffs",
        })
        self.editModeRegistered = true
    end
end

---------------------------------------------------------------------------------
-- Button Factory
---------------------------------------------------------------------------------

local function OnButtonEnter(button)
    if not button.auraInstanceID then return end
    GameTooltip:SetOwner(button, "ANCHOR_BOTTOMLEFT")
    GameTooltip:SetUnitAuraByAuraInstanceID(UNIT, button.auraInstanceID)
    GameTooltip:Show()
end

local function OnButtonLeave()
    GameTooltip:Hide()
end

-- Creates a raw button frame with all child widgets wired. Font anchors are
-- intentionally NOT set here — UpdateButtonAppearance handles those every Refresh.
local function CreateButton(parent, db)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(db.IconSize, db.IconSize)
    b:EnableMouse(true)
    b:SetScript("OnEnter", OnButtonEnter)
    b:SetScript("OnLeave", OnButtonLeave)

    -- Icon texture
    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(b)
    KE:ApplyIconZoom(tex, db.IconZoom)
    b.icon = tex

    -- 1px pixel-perfect borders
    KE:AddIconBorders(b, db.BorderColor)

    -- Cooldown spiral
    local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    cd:SetAllPoints(b)
    cd:SetDrawEdge(false)
    cd:SetReverse(db.Reverse)
    cd:SetHideCountdownNumbers(true)
    b.cooldown = cd

    -- Dispel-type atlas overlay (top-right corner, ~40% of icon size)
    local dispelTex = b:CreateTexture(nil, "OVERLAY")
    local dispelSize = math_floor(db.IconSize * 0.40)
    dispelTex:SetSize(dispelSize, dispelSize)
    b.dispelTex = dispelTex

    -- Timer FontString — font/anchor set per-Refresh by UpdateButtonAppearance
    local timer = b:CreateFontString(nil, "OVERLAY")
    b.timer = timer

    -- Stack count FontString — font/anchor set per-Refresh by UpdateButtonAppearance
    local stack = b:CreateFontString(nil, "OVERLAY")
    b.stack = stack

    b.auraInstanceID = nil
    return b
end

function AD:GetOrCreateButton(index)
    local b = self.buttons[index]
    if b then return b end
    b = CreateButton(self.frame, self.db)
    self.buttons[index] = b
    return b
end

-- Re-apply font + anchor for timer/stack on every visible button, and
-- reapply icon zoom + dispel overlay size. Called after aura data is set,
-- before LayoutButtons, so anchors are stable before positions are computed.
function AD:UpdateButtonAppearance(count)
    local db = self.db
    local tp = db.TimerPosition
    local sp = db.StackPosition

    for i = 1, count do
        local b = self.buttons[i]
        if b then
            -- Icon zoom
            if b.icon then
                KE:ApplyIconZoom(b.icon, db.IconZoom)
            end

            -- Timer
            if b.timer then
                KE:ApplyFontToText(b.timer, db.FontFace, db.TimerFontSize, db.FontOutline)
                b.timer:ClearAllPoints()
                b.timer:SetPoint(tp.AnchorFrom, b, tp.AnchorTo, tp.XOffset, tp.YOffset)
            end

            -- Stack count
            if b.stack then
                KE:ApplyFontToText(b.stack, db.FontFace, db.FontSize, db.FontOutline)
                b.stack:ClearAllPoints()
                b.stack:SetPoint(sp.AnchorFrom, b, sp.AnchorTo, sp.XOffset, sp.YOffset)
            end

            -- Dispel overlay size (follows IconSize which may change in settings)
            if b.dispelTex then
                local dispelSize = math_floor(db.IconSize * 0.40)
                b.dispelTex:SetSize(dispelSize, dispelSize)
                b.dispelTex:ClearAllPoints()
                b.dispelTex:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
            end
        end
    end
end

---------------------------------------------------------------------------------
-- Aura Collection
---------------------------------------------------------------------------------

function AD:CollectAuras()
    local db       = self.db
    local list     = {}
    local filterStr = self:BuildFilterString()

    local i = 1
    while true do
        local data = C_UnitAuras.GetAuraDataByIndex(UNIT, i, filterStr)
        if not data then break end

        local sid     = data.spellId
        local blocked = sid and db.Blocklist and db.Blocklist[sid]
        if not (blocked and blocked.enabled) then
            local dt       = data.dispelName
            local typeEnum = dt and Enum.DispelType[dt]

            -- DispelTypes table: nil = show (default), false = hide.
            -- User can set db.DispelTypes["Magic"] = false to suppress a type.
            if not db.DispelTypes or db.DispelTypes[dt] ~= false then
                tinsert(list, {
                    auraInstanceID = data.auraInstanceID,
                    spellId        = sid,
                    icon           = data.icon,
                    duration       = data.duration,
                    expirationTime = data.expirationTime,
                    count          = data.applications,
                    dispelType     = dt,
                    dispelEnum     = typeEnum,
                })
            end
        end
        i = i + 1
    end

    -- Sort by dispel type (alphabetical), then by expiration time (soonest first)
    tsort(list, function(a, b)
        local da = a.dispelType or ""
        local db_ = b.dispelType or ""
        if da ~= db_ then return da < db_ end
        return (a.expirationTime or 0) < (b.expirationTime or 0)
    end)

    return list
end

---------------------------------------------------------------------------------
-- Refresh + Layout
---------------------------------------------------------------------------------

function AD:Refresh()
    if not self.frame then return end

    if not self:ShouldShow() then
        for _, b in pairs(self.buttons) do b:Hide() end
        self.frame:Hide()
        return
    end
    self.frame:Show()

    local db    = self.db
    local auras = self.isPreview and PREVIEW_AURAS or self:CollectAuras()
    local cap   = math_min(#auras, (db.IconsPerRow or 8) * (db.MaxRows or 1))

    for i = 1, cap do
        local aura = auras[i]
        local b    = self:GetOrCreateButton(i)
        b.auraInstanceID = aura.auraInstanceID
        b.icon:SetTexture(aura.icon)

        if aura.duration and aura.duration > 0 and aura.expirationTime then
            b.cooldown:SetCooldown(aura.expirationTime - aura.duration, aura.duration)
            b._expirationTime = aura.expirationTime
            b._duration = aura.duration
        else
            b.cooldown:Clear()
            b._expirationTime = nil
            b._duration = nil
        end

        b.stack:SetText((aura.count and aura.count > 1) and tostring(aura.count) or "")

        local atlas = aura.dispelEnum and DISPEL_ICON_ATLASES[aura.dispelEnum] or nil
        if atlas then
            b.dispelTex:SetAtlas(atlas)
            b.dispelTex:Show()
        else
            b.dispelTex:Hide()
        end

        b:Show()
    end

    for i = cap + 1, #self.buttons do
        self.buttons[i]:Hide()
    end

    self:UpdateButtonAppearance(cap)
    self:UpdateTimerText()  -- immediate update so first paint isn't blank
    self:LayoutButtons(cap)
end

function AD:LayoutButtons(count)
    local db     = self.db
    local dx     = (db.IconSize + db.IconSpacing) * (db.GrowHorizontal == "LEFT" and -1 or 1)
    local dy     = (db.IconSize + db.IconSpacing) * (db.GrowVertical == "UP" and 1 or -1)
    local perRow = db.IconsPerRow or 8

    for i = 1, count do
        local b   = self.buttons[i]
        local row = math_floor((i - 1) / perRow)
        local col = (i - 1) % perRow
        b:ClearAllPoints()
        b:SetPoint("CENTER", self.frame, "CENTER", col * dx, row * dy)
    end
end

---------------------------------------------------------------------------------
-- Duration text ticker
---------------------------------------------------------------------------------

-- Format a time-remaining number to a short human-readable string.
local function FormatDuration(remaining)
    if remaining <= 0 then return "" end
    if remaining < 10 then
        return ("%.1f"):format(remaining)
    elseif remaining < 60 then
        return ("%d"):format(remaining)
    elseif remaining < 3600 then
        return ("%dm"):format(remaining / 60)
    else
        return ("%dh"):format(remaining / 3600)
    end
end

function AD:UpdateTimerText()
    local now = GetTime()
    for _, b in pairs(self.buttons) do
        if b:IsShown() then
            if b.auraInstanceID and b._expirationTime and b._duration and b._duration > 0 then
                local remaining = b._expirationTime - now
                if remaining > 0 then
                    b.timer:SetText(FormatDuration(remaining))
                else
                    b.timer:SetText("")
                end
            else
                b.timer:SetText("")
            end
        end
    end
end

function AD:StartDurationTicker()
    if self.durationTicker then return end
    self.durationTicker = C_Timer.NewTicker(0.1, function() AD:UpdateTimerText() end)
end

function AD:StopDurationTicker()
    if self.durationTicker then
        self.durationTicker:Cancel()
        self.durationTicker = nil
    end
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------

function AD:ShowPreview()
    self.isPreview = true
    if not self.frame then self:CreateContainer() end
    self:Refresh()
end

function AD:HidePreview()
    self.isPreview = false
    self:Refresh()
    if not self.db.Enabled and self.frame then
        self.frame:Hide()
    end
end
