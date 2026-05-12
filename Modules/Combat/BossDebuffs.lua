-- ╔══════════════════════════════════════════════════════════╗
-- ║  BossDebuffs.lua                                         ║
-- ║  Module: Boss Debuffs                                    ║
-- ║  Purpose: Displays icons for harmful auras on the player ║
-- ║           that were NOT self-cast. Designed for tracking ║
-- ║           boss mechanics with cooldown spirals and       ║
-- ║           encounter/instance visibility gating.          ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class BossDebuffs: AceModule, AceEvent-3.0
local BD = KitnEssentials:NewModule("BossDebuffs", "AceEvent-3.0")

local C_UnitAuras    = C_UnitAuras
local C_Timer        = C_Timer
local CreateFrame    = CreateFrame
local IsInInstance   = IsInInstance
local GameTooltip    = GameTooltip
local GetTime        = GetTime
local wipe           = wipe
local table_insert   = table.insert
local string_gmatch  = string.gmatch

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------
BD.frame              = nil     -- container frame KE_BossDebuffs
BD.icons              = {}      -- table of icon frames (up to 5)
BD.debuffs            = {}      -- active debuff data { auraInstanceID, expirationTime, duration, icon }
BD.inEncounter        = false
BD.inCombat           = false
BD.inInstance         = false
BD.encounterID        = nil
BD.encounterBlacklist = {}      -- parsed set of blacklisted encounterIDs
BD.isPreview          = false
BD.editModeRegistered = false
BD.durationTicker     = nil

local PREVIEW_ICONS = {
    7636525,
    7636520,
    4914671,
    5764909,
    7554223,
}

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function BD:UpdateDB()
    self.db = KE.db.profile.BossDebuffs
end

---------------------------------------------------------------------------------
-- Blacklist Parsing
---------------------------------------------------------------------------------
local function ParseBlacklist(str)
    local result = {}
    if not str or str == "" then return result end
    for id in string_gmatch(str, "[^,]+") do
        local trimmed = id:match("^%s*(.-)%s*$")
        local num = tonumber(trimmed)
        if num then
            result[num] = true
        end
    end
    return result
end

function BD:RefreshBlacklist()
    self.encounterBlacklist = ParseBlacklist(self.db.EncounterBlacklist)
end

---------------------------------------------------------------------------------
-- Visibility Logic
---------------------------------------------------------------------------------
function BD:ShouldShow()
    if not self.db.Enabled then return false end
    if self.isPreview then return true end

    local mode = self.db.VisibilityMode or "boss"

    if mode == "boss" then
        return self.inEncounter
    elseif mode == "instance" then
        return self.inCombat and self.inInstance
    elseif mode == "always" then
        return self.inCombat
    end

    return false
end

---------------------------------------------------------------------------------
-- Frame Creation
---------------------------------------------------------------------------------
function BD:CreateFrames()
    if self.frame then return end

    local container = CreateFrame("Frame", "KE_BossDebuffs", UIParent)
    container:SetSize(1, 1)
    container:SetFrameStrata(self.db.Strata or "HIGH")
    container:Hide()
    self.frame = container

    -- Pre-create up to 5 icon frames
    for i = 1, 5 do
        local icon = CreateFrame("Frame", nil, container)
        icon:SetSize(self.db.IconSize or 32, self.db.IconSize or 32)

        local tex = icon:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints(icon)
        KE:ApplyIconZoom(tex)
        icon.texture = tex

        -- Pixel-perfect borders
        KE:AddIconBorders(icon)

        -- Cooldown spiral for duration display
        local cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
        cd:SetAllPoints(icon)
        cd:SetDrawEdge(false)
        cd:SetReverse(false)
        cd:SetHideCountdownNumbers(true)
        icon.cooldown = cd

        -- Duration text overlay
        local durationText = icon:CreateFontString(nil, "OVERLAY")
        durationText:SetPoint("CENTER", icon, "CENTER", 0, 0)
        KE:ApplyFont(durationText, "Expressway", 12, "OUTLINE")
        durationText:SetTextColor(1, 1, 1, 1)
        icon.durationText = durationText

        icon.auraInstanceID = nil
        icon:Hide()
        self.icons[i] = icon
    end
end

---------------------------------------------------------------------------------
-- Icon Layout
---------------------------------------------------------------------------------
function BD:LayoutIcons()
    if not self.frame then return end

    local db         = self.db
    local iconSize   = db.IconSize or 32
    local spacing    = db.Spacing or 4
    local maxDebuffs = db.MaxDebuffs or 3
    local growth     = db.GrowthDirection or "RIGHT"
    local step       = iconSize + spacing

    local count = math.min(#self.debuffs, maxDebuffs)

    for i = 1, 5 do
        local icon = self.icons[i]
        local data = self.debuffs[i]

        if i <= count and data then
            icon:ClearAllPoints()
            icon:SetSize(iconSize, iconSize)
            icon.texture:SetTexture(data.icon)

            -- Position relative to container
            local offset = (i - 1) * step
            if growth == "RIGHT" then
                icon:SetPoint("TOPLEFT", self.frame, "TOPLEFT", offset, 0)
            elseif growth == "LEFT" then
                icon:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -offset, 0)
            elseif growth == "DOWN" then
                icon:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, -offset)
            elseif growth == "UP" then
                icon:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 0, offset)
            end

            -- Cooldown spiral (skip when values are secret — can't do arithmetic)
            if db.ShowDuration and KE:IsSafeValue(data.expirationTime) and KE:IsSafeValue(data.duration) then
                icon.cooldown:SetCooldown(data.expirationTime - data.duration, data.duration)
                icon.cooldown:Show()
            else
                icon.cooldown:Hide()
            end

            -- Tooltip
            icon:EnableMouse(db.ShowTooltip ~= false)
            icon.auraInstanceID = data.auraInstanceID

            if not icon:GetScript("OnEnter") then
                icon:SetScript("OnEnter", function(iconFrame)
                    if not iconFrame.auraInstanceID then return end
                    GameTooltip:SetOwner(iconFrame, "ANCHOR_RIGHT")
                    GameTooltip:SetUnitDebuffByAuraInstanceID("player", iconFrame.auraInstanceID)
                    GameTooltip:Show()
                end)
                icon:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)
            end

            -- Duration text sizing
            if icon.durationText then
                local fontSize = math.max(10, math.floor(iconSize * 0.38))
                KE:ApplyFont(icon.durationText, "Expressway", fontSize, "OUTLINE")
                if not db.ShowDurationText then
                    icon.durationText:Hide()
                end
            end

            icon:Show()
        else
            icon:Hide()
            icon.auraInstanceID = nil
        end
    end

    -- Resize container to fit visible icons
    local visCount = math.max(count, 1)
    if growth == "RIGHT" or growth == "LEFT" then
        self.frame:SetSize(visCount * step - spacing, iconSize)
    else
        self.frame:SetSize(iconSize, visCount * step - spacing)
    end
end

---------------------------------------------------------------------------------
-- Debuff Detection
---------------------------------------------------------------------------------
function BD:ScanDebuffs()
    if self.isPreview then return end
    wipe(self.debuffs)

    if not self:ShouldShow() then
        self:HideAllIcons()
        return
    end

    -- Build self-cast lookup set
    local selfCastIDs = C_UnitAuras.GetUnitAuraInstanceIDs("player", "HARMFUL|PLAYER")
    local selfSet = {}
    if selfCastIDs then
        for _, id in ipairs(selfCastIDs) do
            if KE:IsSafeValue(id) then
                selfSet[id] = true
            end
        end
    end

    -- Collect all harmful aura IDs on player
    local allIDs = C_UnitAuras.GetUnitAuraInstanceIDs("player", "HARMFUL")
    if not allIDs then
        self:LayoutIcons()
        return
    end

    local maxDebuffs = self.db.MaxDebuffs or 3

    for _, instanceID in ipairs(allIDs) do
        if KE:IsSafeValue(instanceID) then
            -- Skip self-cast
            if not selfSet[instanceID] then
                local aura = C_UnitAuras.GetAuraDataByAuraInstanceID("player", instanceID)
                if aura then
                    -- auraData for player's own harmful auras (received from others)
                    -- icon, expirationTime, duration fields are clean for self-received auras
                    local icon = aura.icon
                    local expTime = aura.expirationTime
                    local dur = aura.duration

                    -- icon/expirationTime/duration may be secret but SetTexture and
                    -- SetCooldown are AllowedWhenTainted — pass through directly
                    if icon then
                        table_insert(self.debuffs, {
                            auraInstanceID  = instanceID,
                            icon            = icon,
                            expirationTime  = expTime,
                            duration        = dur,
                        })
                    end

                    if #self.debuffs >= maxDebuffs then break end
                end
            end
        end
    end

    self:LayoutIcons()

    if #self.debuffs > 0 then
        self.frame:Show()
        if self.db.ShowDurationText then
            self:StartDurationTicker()
        end
    else
        self.frame:Hide()
        self:StopDurationTicker()
    end
end

function BD:HideAllIcons()
    for i = 1, 5 do
        if self.icons[i] then
            self.icons[i]:Hide()
            self.icons[i].auraInstanceID = nil
            if self.icons[i].durationText then
                self.icons[i].durationText:Hide()
            end
        end
    end
    if self.frame then self.frame:Hide() end
    self:StopDurationTicker()
end

---------------------------------------------------------------------------------
-- Duration Text
---------------------------------------------------------------------------------
local function FormatDuration(remaining)
    if remaining >= 60 then
        return string.format("%dm", math.floor(remaining / 60))
    elseif remaining >= 10 then
        return string.format("%d", math.floor(remaining))
    else
        return string.format("%.1f", remaining)
    end
end

function BD:UpdateDurationTexts()
    if not self.db.ShowDurationText then return end
    local now = GetTime()
    local anyVisible = false

    for i = 1, 5 do
        local icon = self.icons[i]
        local data = self.debuffs[i]
        if icon and icon:IsShown() and data
            and KE:IsSafeValue(data.expirationTime)
            and KE:IsSafeValue(data.duration) then
            local remaining = data.expirationTime - now
            if remaining > 0 then
                icon.durationText:SetText(FormatDuration(remaining))
                icon.durationText:Show()
                anyVisible = true
            else
                icon.durationText:Hide()
            end
        elseif icon and icon.durationText then
            icon.durationText:Hide()
        end
    end

    if not anyVisible then
        self:StopDurationTicker()
    end
end

function BD:StartDurationTicker()
    if self.durationTicker then return end
    self.durationTicker = C_Timer.NewTicker(0.1, function()
        if not self.db or not self.db.Enabled then
            self:StopDurationTicker()
            return
        end
        self:UpdateDurationTexts()
    end)
end

function BD:StopDurationTicker()
    if self.durationTicker then
        self.durationTicker:Cancel()
        self.durationTicker = nil
    end
end

---------------------------------------------------------------------------------
-- Event Handlers
---------------------------------------------------------------------------------
function BD:OnUnitAura(_, unit)
    if unit ~= "player" then return end
    self:ScanDebuffs()
end

function BD:OnEncounterStart(_, encounterID)
    if self.encounterBlacklist[encounterID] then
        self.inEncounter = false
        return
    end
    self.inEncounter = true
    self.encounterID = encounterID
    self:ScanDebuffs()
end

function BD:OnEncounterEnd()
    self.inEncounter = false
    self.encounterID = nil
    wipe(self.debuffs)
    self:HideAllIcons()
end

function BD:OnCombatEnter()
    self.inCombat = true
    if (self.db.VisibilityMode or "boss") ~= "boss" then
        self:ScanDebuffs()
    end
end

function BD:OnCombatLeave()
    self.inCombat = false
    if (self.db.VisibilityMode or "boss") ~= "boss" then
        wipe(self.debuffs)
        self:HideAllIcons()
    end
end

function BD:OnPlayerEnteringWorld()
    self.inEncounter = false
    self.encounterID = nil
    self.inCombat = UnitAffectingCombat("player") and true or false

    local _, instanceType = IsInInstance()
    self.inInstance = (instanceType == "raid" or instanceType == "party" or
                       instanceType == "arena" or instanceType == "pvp" or
                       instanceType == "scenario")

    wipe(self.debuffs)
    self:HideAllIcons()
end

---------------------------------------------------------------------------------
-- Apply Settings
---------------------------------------------------------------------------------
function BD:ApplySettings()
    if not self.frame then return end

    KE:ApplyFramePosition(self.frame, self.db.Position, self.db)

    if self.db.Strata then
        self.frame:SetFrameStrata(self.db.Strata)
    end

    self:RefreshBlacklist()
    self:LayoutIcons()
end

---------------------------------------------------------------------------------
-- EditMode
---------------------------------------------------------------------------------
function BD:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key         = "BossDebuffs",
            displayName = "Boss Debuffs",
            frame       = self.frame,
            getPosition = function()
                return self.db.Position
            end,
            setPosition = function(pos)
                self.db.Position = pos
                KE:ApplyFramePosition(self.frame, self.db.Position, self.db)
            end,
            getParentFrame = function()
                return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame)
            end,
            guiPath = "BossDebuffs",
        })
        self.editModeRegistered = true
    end
end

---------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------
function BD:ShowPreview()
    if not self.frame then
        self:CreateFrames()
    end
    self:RegWithEditMode()

    self.isPreview = true

    -- Populate debuffs table with mock data
    wipe(self.debuffs)
    local maxDebuffs = self.db.MaxDebuffs or 3
    for i = 1, math.min(maxDebuffs, #PREVIEW_ICONS) do
        table_insert(self.debuffs, {
            auraInstanceID = 800000 + i,
            icon           = PREVIEW_ICONS[i],
            expirationTime = GetTime() + 30,
            duration       = 30,
        })
    end

    self:LayoutIcons()

    -- Show position numbers on preview icons
    for i = 1, maxDebuffs do
        local icon = self.icons[i]
        if icon and icon.durationText then
            icon.durationText:SetText(tostring(i))
            icon.durationText:Show()
        end
    end

    self.frame:SetAlpha(1)
    self.frame:Show()
    self:ApplySettings()
end

function BD:HidePreview()
    self.isPreview = false
    wipe(self.debuffs)
    self:HideAllIcons()

    if self.db.Enabled and self:ShouldShow() then
        self:ScanDebuffs()
    end
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function BD:OnInitialize()
    self:UpdateDB()
    self:RefreshBlacklist()
    self:SetEnabledState(false)
end

function BD:OnEnable()
    if not self.db.Enabled then return end

    self:CreateFrames()
    self:RegWithEditMode()

    self:RegisterEvent("UNIT_AURA",             "OnUnitAura")
    self:RegisterEvent("ENCOUNTER_START",        "OnEncounterStart")
    self:RegisterEvent("ENCOUNTER_END",          "OnEncounterEnd")
    self:RegisterEvent("PLAYER_REGEN_DISABLED",  "OnCombatEnter")
    self:RegisterEvent("PLAYER_REGEN_ENABLED",   "OnCombatLeave")
    self:RegisterEvent("PLAYER_ENTERING_WORLD",  "OnPlayerEnteringWorld")

    -- Initialize state from current conditions
    local _, instanceType = IsInInstance()
    self.inInstance = (instanceType == "raid" or instanceType == "party" or
                       instanceType == "arena" or instanceType == "pvp" or
                       instanceType == "scenario")
    self.inCombat = UnitAffectingCombat("player") and true or false

    C_Timer.After(0.3, function()
        if not self.db or not self.db.Enabled then return end
        self:ApplySettings()
        self:ScanDebuffs()
    end)
end

function BD:OnDisable()
    self:UnregisterAllEvents()
    wipe(self.debuffs)
    self.inEncounter = false
    self.inCombat    = false
    self.isPreview   = false
    self:HideAllIcons()
end
