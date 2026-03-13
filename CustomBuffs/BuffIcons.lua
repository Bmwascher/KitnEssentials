-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class BuffIcons: AceModule, AceEvent-3.0
local BI = KitnEssentials:NewModule("BuffIcons", "AceEvent-3.0")

-- Localization
local CreateFrame = CreateFrame
local GetTime = GetTime
local GetItemSpell = GetItemSpell
local unpack = unpack
local pairs = pairs
local ipairs = ipairs
local next = next
local C_Spell = C_Spell
local C_Item = C_Item
local C_Timer = C_Timer
local _G = _G

-- Inline helpers
local function ApplyZoom(tex, zoom)
    local lo = 0.25 * zoom
    local hi = 1 - lo
    tex:SetTexCoord(lo, hi, lo, hi)
end

-- Module state
BI.trackerFrames = {}
BI.containerFrame = nil
BI.activeTimers = {}

function BI:UpdateDB()
    self.db = KE.db.profile.BuffIcons
end

function BI:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function BI:GetDefaults()
    return self.db and self.db.Defaults or {}
end

function BI:GetTrackerConfig(tracker)
    local defaults = self:GetDefaults()
    return {
        SpellID = tracker.SpellID,
        Type = tracker.Type or "Spell",
        Enabled = tracker.Enabled ~= false,
        Duration = tracker.Duration or 10,
        UseCustomTexture = tracker.UseCustomTexture or false,
        CustomTexture = tracker.CustomTexture or nil,
        IconSize = defaults.IconSize or 40,
        ShowCooldownText = defaults.ShowCooldownText ~= false,
        CountdownSize = defaults.CountdownSize or 18,
        BorderColor = defaults.BorderColor or { 0, 0, 0, 1 },
        BorderSize = defaults.BorderSize or 1,
    }
end

function BI:GetAnchorFrame()
    return KE:ResolveAnchorFrame(self.db and self.db.anchorFrameType, self.db and self.db.ParentFrame)
end

function BI:CreateContainerFrame()
    if self.containerFrame then return self.containerFrame end
    local db = self.db
    if not db then return nil end

    self.containerFrame = CreateFrame("Frame", "KE_BuffIcons_Container", UIParent)
    self.containerFrame:SetSize(1, 1)
    self.containerFrame:SetFrameStrata("MEDIUM")

    local parentFrame = self:GetAnchorFrame()
    KE:ApplyFramePosition(self.containerFrame, db.Position, db)

    return self.containerFrame
end

function BI:CreateTrackerFrame(trackerIndex, config)
    local frame = CreateFrame("Frame", "KE_BuffIcon_" .. trackerIndex, self.containerFrame or UIParent)
    frame:SetSize(config.IconSize, config.IconSize)
    frame:SetFrameStrata("MEDIUM")
    frame:Hide()

    -- Border
    frame.border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.border:SetAllPoints()
    frame.border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = config.BorderSize,
    })
    frame.border:SetBackdropBorderColor(unpack(config.BorderColor))

    -- Icon texture
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetAllPoints()
    ApplyZoom(frame.icon, 0.3)

    local iconTexture
    if config.UseCustomTexture and config.CustomTexture then
        iconTexture = config.CustomTexture
    elseif config.Type == "Item" then
        iconTexture = C_Item.GetItemIconByID(config.SpellID)
    else
        local spellInfo = C_Spell.GetSpellInfo(config.SpellID)
        iconTexture = spellInfo and spellInfo.iconID
    end
    if iconTexture then
        frame.icon:SetTexture(iconTexture)
    end

    -- Cooldown frame
    frame.cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    frame.cooldown:SetAllPoints()
    frame.cooldown:SetDrawEdge(false)
    frame.cooldown:SetDrawBling(false)
    frame.cooldown:SetSwipeColor(0, 0, 0, 0.6)
    frame.cooldown:SetReverse(true)

    if config.ShowCooldownText then
        frame.cooldown:SetHideCountdownNumbers(false)
        local region = frame.cooldown:GetRegions()
        if region and region.SetFont then
            region:SetFont(STANDARD_TEXT_FONT, config.CountdownSize, "OUTLINE")
            region:SetShadowOffset(0, 0)
            region:SetShadowColor(0, 0, 0, 0)
        end
    else
        frame.cooldown:SetHideCountdownNumbers(true)
    end

    frame.config = config
    frame.trackerIndex = trackerIndex

    return frame
end

function BI:LayoutIcons()
    local db = self.db
    if not db or not self.containerFrame then return end

    local direction = db.GrowthDirection or "RIGHT"
    local spacing = db.Spacing or 2

    local visibleFrames = {}
    for index, frame in pairs(self.trackerFrames) do
        if frame:IsShown() then
            table.insert(visibleFrames, { index = index, frame = frame })
        end
    end
    table.sort(visibleFrames, function(a, b) return a.index < b.index end)

    local totalCount = #visibleFrames
    if totalCount == 0 then
        self.containerFrame:SetSize(1, 1)
        return
    end

    local defaults = self:GetDefaults()
    local iconSize = defaults.IconSize or 40

    local containerWidth, containerHeight
    if direction == "LEFT" or direction == "RIGHT" or direction == "CENTER" then
        containerWidth = (totalCount * iconSize) + ((totalCount - 1) * spacing)
        containerHeight = iconSize
    else
        containerWidth = iconSize
        containerHeight = (totalCount * iconSize) + ((totalCount - 1) * spacing)
    end

    self.containerFrame:SetSize(containerWidth, containerHeight)

    for i, entry in ipairs(visibleFrames) do
        local frame = entry.frame
        local offset = (i - 1) * (iconSize + spacing)

        frame:ClearAllPoints()
        if direction == "RIGHT" then
            frame:SetPoint("LEFT", self.containerFrame, "LEFT", offset, 0)
        elseif direction == "LEFT" then
            frame:SetPoint("RIGHT", self.containerFrame, "RIGHT", -offset, 0)
        elseif direction == "DOWN" then
            frame:SetPoint("TOP", self.containerFrame, "TOP", 0, -offset)
        elseif direction == "UP" then
            frame:SetPoint("BOTTOM", self.containerFrame, "BOTTOM", 0, offset)
        elseif direction == "CENTER" then
            frame:SetPoint("LEFT", self.containerFrame, "LEFT", offset, 0)
        end
    end
end

function BI:ShowTracker(trackerIndex, isPreview)
    local frame = self.trackerFrames[trackerIndex]
    if not frame then return end
    if not isPreview and not frame.config.Enabled then return end

    local config = frame.config

    if self.activeTimers[trackerIndex] then
        self.activeTimers[trackerIndex]:Cancel()
        self.activeTimers[trackerIndex] = nil
    end

    frame.cooldown:SetCooldown(GetTime(), config.Duration)
    frame:Show()
    self:LayoutIcons()

    self.activeTimers[trackerIndex] = C_Timer.NewTimer(config.Duration, function()
        self.activeTimers[trackerIndex] = nil
        if frame then
            frame:Hide()
            self:LayoutIcons()
        end
    end)
end

function BI:OnSpellCast(event, unit, _, spellID)
    if unit ~= "player" then return end
    if not self.db or not self.db.Enabled or not self.db.Trackers then return end

    for index, tracker in pairs(self.db.Trackers) do
        if tracker.Enabled ~= false and tracker.SpellID then
            local shouldTrigger = false

            if tracker.Type == "Item" then
                local _, itemSpellID = GetItemSpell(tracker.SpellID)
                if itemSpellID and itemSpellID == spellID then
                    shouldTrigger = true
                end
            else
                if tracker.SpellID == spellID then
                    shouldTrigger = true
                end
            end

            if shouldTrigger then
                self:ShowTracker(index)
            end
        end
    end
end

function BI:CreateAllTrackers()
    for _, timer in pairs(self.activeTimers) do timer:Cancel() end
    self.activeTimers = {}

    for _, frame in pairs(self.trackerFrames) do
        frame:Hide()
        frame:SetParent(nil)
    end
    self.trackerFrames = {}

    if self.containerFrame then
        self.containerFrame:Hide()
        self.containerFrame:SetParent(nil)
        self.containerFrame = nil
    end

    local db = self.db
    if not db or not db.Trackers then return end

    self:CreateContainerFrame()
    if not self.containerFrame then return end

    for index, tracker in pairs(db.Trackers) do
        if tracker.SpellID then
            local config = self:GetTrackerConfig(tracker)
            self.trackerFrames[index] = self:CreateTrackerFrame(index, config)
        end
    end
end

function BI:ApplyPosition()
    if not self.containerFrame then return end
    local db = self.db
    if not db then return end
    KE:ApplyFramePosition(self.containerFrame, db.Position, db)
end

function BI:OnEnable()
    if not self.db.Enabled then return end
    self:CreateAllTrackers()
    self:RegWithEditMode()
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnSpellCast")
end

function BI:OnDisable()
    for _, timer in pairs(self.activeTimers) do timer:Cancel() end
    self.activeTimers = {}
    for _, frame in pairs(self.trackerFrames) do frame:Hide() end
    self:UnregisterAllEvents()
end

function BI:Refresh()
    self:CreateAllTrackers()
end

function BI:ApplySettings()
    self.db = KE.db.profile.BuffIcons
    if self.db and self.db.Enabled then
        if not self:IsEnabled() then
            KitnEssentials:EnableModule("BuffIcons")
        else
            self:CreateAllTrackers()
        end
    else
        if self:IsEnabled() then
            KitnEssentials:DisableModule("BuffIcons")
        end
    end
end

function BI:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "BuffIcons", displayName = "Buff Icons", frame = self.containerFrame,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos) self.db.Position = pos; KE:ApplyFramePosition(self.containerFrame, self.db.Position, self.db) end,
            getParentFrame = function() return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame) end,
            guiPath = "BuffIcons",
        })
        self.editModeRegistered = true
    end
end

function BI:PreviewAll()
    if not next(self.trackerFrames) then
        self:CreateAllTrackers()
    end
    self:RegWithEditMode()
    for index, _ in pairs(self.trackerFrames) do
        self:ShowTracker(index, true)
    end
end

function BI:HideAll()
    for _, timer in pairs(self.activeTimers) do timer:Cancel() end
    self.activeTimers = {}
    for _, frame in pairs(self.trackerFrames) do frame:Hide() end
end
