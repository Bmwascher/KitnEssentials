-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class BuffBars: AceModule, AceEvent-3.0
local BB = KitnEssentials:NewModule("BuffBars", "AceEvent-3.0")

-- Localization
local CreateFrame = CreateFrame
local GetTime = GetTime
local GetItemSpell = GetItemSpell
local unpack = unpack
local floor = math.floor
local pairs = pairs
local ipairs = ipairs
local next = next
local C_Spell = C_Spell
local C_Item = C_Item
local _G = _G

-- Constants
local BAR_UPDATE_THRESHOLD = 0.1

-- Inline helpers
local function ApplyZoom(tex, zoom)
    local lo = 0.25 * zoom
    local hi = 1 - lo
    tex:SetTexCoord(lo, hi, lo, hi)
end

-- Module state
BB.trackerFrames = {}
BB.updateFrame = nil
BB.containerFrame = nil

function BB:UpdateDB()
    self.db = KE.db.profile.BuffBars
end

function BB:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function BB:GetDefaults()
    return self.db and self.db.Defaults or {}
end

function BB:GetStatusBarTexture()
    local defaults = self:GetDefaults()
    return defaults.StatusBarTexture or "Blizzard"
end

function BB:GetTrackerConfig(tracker)
    local defaults = self:GetDefaults()
    return {
        SpellID = tracker.SpellID,
        Type = tracker.Type or "Spell",
        Enabled = tracker.Enabled ~= false,
        Duration = tracker.Duration or 10,
        SpellText = tracker.SpellText or "",
        BarWidth = tracker.BarWidth or defaults.BarWidth or 200,
        BarHeight = tracker.BarHeight or defaults.BarHeight or 20,
        IconSize = tracker.IconSize or defaults.IconSize or 20,
        ShowIcon = tracker.ShowIcon ~= false and (defaults.ShowIcon ~= false),
        ShowTimeText = tracker.ShowTimeText ~= false and (defaults.ShowTimeText ~= false),
        ShowSpellText = tracker.ShowSpellText ~= false and (defaults.ShowSpellText ~= false),
        FontSize = tracker.FontSize or defaults.FontSize or 12,
        BarColor = tracker.BarColor or defaults.BarColor or { 0.65, 0.65, 0.65, 1 },
        BackgroundColor = tracker.BackgroundColor or defaults.BackgroundColor or { 0, 0, 0, 0.8 },
        BorderColor = tracker.BorderColor or defaults.BorderColor or { 0, 0, 0, 1 },
        Reverse = tracker.Reverse or defaults.Reverse or false,
    }
end

function BB:GetAnchorFrame()
    return KE:ResolveAnchorFrame(self.db and self.db.anchorFrameType, self.db and self.db.ParentFrame)
end

function BB:CreateContainerFrame()
    if self.containerFrame then return self.containerFrame end
    local db = self.db
    if not db then return nil end

    self.containerFrame = CreateFrame("Frame", "KE_BuffBars_Container", UIParent)
    self.containerFrame:SetSize(1, 1)
    self.containerFrame:SetFrameStrata("MEDIUM")

    KE:ApplyFramePosition(self.containerFrame, db.Position, db)

    return self.containerFrame
end

function BB:CreateTrackerFrame(trackerIndex, config)
    local iconSize = config.ShowIcon and config.BarHeight or 0
    local frame = CreateFrame("Frame", "KE_BuffBar_" .. trackerIndex, self.containerFrame or UIParent,
        "BackdropTemplate")
    frame:SetSize(config.BarWidth, config.BarHeight)
    frame:SetFrameStrata("MEDIUM")
    frame:Hide()

    frame.totalWidth = config.BarWidth

    -- Bar container with border
    frame.barContainer = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.barContainer:SetAllPoints()
    frame.barContainer:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame.barContainer:SetBackdropColor(unpack(config.BackgroundColor))
    frame.barContainer:SetBackdropBorderColor(unpack(config.BorderColor))

    -- StatusBar texture
    local statusbarTexture = KE:GetStatusbarPath(self:GetStatusBarTexture())

    -- StatusBar
    frame.bar = CreateFrame("StatusBar", nil, frame.barContainer)
    frame.bar:SetPoint("TOPLEFT", 1, -1)
    frame.bar:SetPoint("BOTTOMRIGHT", -1, 1)
    frame.bar:SetStatusBarTexture(statusbarTexture)
    frame.bar:SetStatusBarColor(unpack(config.BarColor))
    frame.bar:SetMinMaxValues(0, config.Duration)
    frame.bar:SetValue(config.Duration)

    -- Icon
    if config.ShowIcon then
        frame.iconFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        frame.iconFrame:SetSize(iconSize, iconSize)
        frame.iconFrame:SetPoint("LEFT", frame, "LEFT", 0, 0)
        frame.iconFrame:SetFrameLevel(frame.bar:GetFrameLevel() + 2)

        frame.iconFrame:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        frame.iconFrame:SetBackdropBorderColor(unpack(config.BorderColor))

        frame.iconFrame.bg = frame.iconFrame:CreateTexture(nil, "BACKGROUND")
        frame.iconFrame.bg:SetAllPoints()
        frame.iconFrame.bg:SetColorTexture(0, 0, 0, 1)

        frame.icon = frame.iconFrame:CreateTexture(nil, "ARTWORK")
        frame.icon:SetPoint("TOPLEFT", 1, -1)
        frame.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        ApplyZoom(frame.icon, 0.3)

        local iconTexture
        if config.Type == "Item" then
            iconTexture = C_Item.GetItemIconByID(config.SpellID)
        else
            local spellInfo = C_Spell.GetSpellInfo(config.SpellID)
            iconTexture = spellInfo and spellInfo.iconID
        end
        if iconTexture then
            frame.icon:SetTexture(iconTexture)
        end
    end

    -- Time text
    if config.ShowTimeText then
        frame.timeText = frame.bar:CreateFontString(nil, "OVERLAY")
        frame.timeText:SetFont(STANDARD_TEXT_FONT, config.FontSize, "OUTLINE")
        frame.timeText:SetPoint("RIGHT", frame.bar, "RIGHT", -2, 0)
        frame.timeText:SetTextColor(1, 1, 1, 1)
        frame.timeText:SetShadowOffset(0, 0)
    end

    -- Spell text
    if config.ShowSpellText then
        frame.spellText = frame.bar:CreateFontString(nil, "OVERLAY")
        frame.spellText:SetFont(STANDARD_TEXT_FONT, config.FontSize, "OUTLINE")
        local textOffset = config.ShowIcon and (iconSize + 4) or 2
        frame.spellText:SetPoint("LEFT", frame.bar, "LEFT", textOffset, 0)
        frame.spellText:SetTextColor(1, 1, 1, 1)
        frame.spellText:SetShadowOffset(0, 0)
        frame.spellText:SetText(config.SpellText)
    end

    frame.config = config
    frame.trackerIndex = trackerIndex
    frame.endTime = 0
    frame.lastBarValue = 0

    return frame
end

function BB:LayoutBars()
    local db = self.db
    if not db or not self.containerFrame then return end

    local direction = db.GrowthDirection or "DOWN"
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
    local barWidth = defaults.BarWidth or 200
    local barHeight = defaults.BarHeight or 20

    local containerWidth, containerHeight
    if direction == "LEFT" or direction == "RIGHT" or direction == "CENTER" then
        containerWidth = (totalCount * barWidth) + ((totalCount - 1) * spacing)
        containerHeight = barHeight
    else
        containerWidth = barWidth
        containerHeight = (totalCount * barHeight) + ((totalCount - 1) * spacing)
    end

    self.containerFrame:SetSize(containerWidth, containerHeight)

    for i, entry in ipairs(visibleFrames) do
        local frame = entry.frame
        local offset

        frame:ClearAllPoints()
        if direction == "RIGHT" then
            offset = (i - 1) * (barWidth + spacing)
            frame:SetPoint("LEFT", self.containerFrame, "LEFT", offset, 0)
        elseif direction == "LEFT" then
            offset = (i - 1) * (barWidth + spacing)
            frame:SetPoint("RIGHT", self.containerFrame, "RIGHT", -offset, 0)
        elseif direction == "DOWN" then
            offset = (i - 1) * (barHeight + spacing)
            frame:SetPoint("TOP", self.containerFrame, "TOP", 0, -offset)
        elseif direction == "UP" then
            offset = (i - 1) * (barHeight + spacing)
            frame:SetPoint("BOTTOM", self.containerFrame, "BOTTOM", 0, offset)
        elseif direction == "CENTER" then
            offset = (i - 1) * (barWidth + spacing)
            frame:SetPoint("LEFT", self.containerFrame, "LEFT", offset, 0)
        end
    end
end

function BB:OnUpdate(elapsed)
    local now = GetTime()
    local anyActive = false
    local needsLayout = false

    for _, frame in pairs(self.trackerFrames) do
        if frame:IsShown() then
            local remaining = frame.endTime - now
            if remaining <= 0 then
                frame:Hide()
                needsLayout = true
            else
                anyActive = true
                local config = frame.config
                local value = config.Reverse and (config.Duration - remaining) or remaining

                if math.abs(value - frame.lastBarValue) >= BAR_UPDATE_THRESHOLD then
                    frame.lastBarValue = value
                    frame.bar:SetValue(value, Enum.StatusBarInterpolation.ExponentialEaseOut)
                end

                if config.ShowTimeText and frame.timeText then
                    if remaining >= 1 then
                        frame.timeText:SetText(floor(remaining + 0.5))
                    else
                        frame.timeText:SetFormattedText("%.1f", remaining)
                    end
                end
            end
        end
    end

    if needsLayout then
        self:LayoutBars()
    end
    if not anyActive and self.updateFrame then
        self.updateFrame:SetScript("OnUpdate", nil)
    end
end

function BB:ShowTracker(trackerIndex, isPreview)
    local frame = self.trackerFrames[trackerIndex]
    if not frame then return end
    if not isPreview and not frame.config.Enabled then return end

    local config = frame.config
    frame.endTime = GetTime() + config.Duration

    frame.bar:SetMinMaxValues(0.0, config.Duration)
    if config.Reverse then
        frame.bar:SetValue(0.0, Enum.StatusBarInterpolation.Immediate)
        frame.lastBarValue = 0.0
    else
        frame.bar:SetValue(config.Duration, Enum.StatusBarInterpolation.Immediate)
        frame.lastBarValue = config.Duration
    end
    frame.bar:SetToTargetValue()
    frame:Show()

    self:LayoutBars()

    if not self.updateFrame then
        self.updateFrame = CreateFrame("Frame")
    end
    self.updateFrame:SetScript("OnUpdate", function(_, elapsed)
        self:OnUpdate(elapsed)
    end)
end

function BB:OnSpellCast(event, unit, _, spellID)
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

function BB:CreateAllTrackers()
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

function BB:ApplyPosition()
    if not self.containerFrame then return end
    local db = self.db
    if not db then return end
    KE:ApplyFramePosition(self.containerFrame, db.Position, db)
end

function BB:OnEnable()
    if not self.db.Enabled then return end
    self:CreateAllTrackers()
    self:RegWithEditMode()
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnSpellCast")
end

function BB:OnDisable()
    for _, frame in pairs(self.trackerFrames) do frame:Hide() end
    if self.updateFrame then self.updateFrame:SetScript("OnUpdate", nil) end
    self:UnregisterAllEvents()
end

function BB:Refresh()
    self:CreateAllTrackers()
end

function BB:ApplySettings()
    self.db = KE.db.profile.BuffBars
    if self.db and self.db.Enabled then
        if not self:IsEnabled() then
            KitnEssentials:EnableModule("BuffBars")
        else
            self:CreateAllTrackers()
        end
    else
        if self:IsEnabled() then
            KitnEssentials:DisableModule("BuffBars")
        end
    end
end

function BB:RegWithEditMode()
    if KE.EditMode and not self.editModeRegistered then
        KE.EditMode:RegisterElement({
            key = "BuffBars", displayName = "Buff Bars", frame = self.containerFrame,
            getPosition = function() return self.db.Position end,
            setPosition = function(pos) self.db.Position = pos; KE:ApplyFramePosition(self.containerFrame, self.db.Position, self.db) end,
            getParentFrame = function() return KE:ResolveAnchorFrame(self.db.anchorFrameType, self.db.ParentFrame) end,
            guiPath = "BuffBars",
        })
        self.editModeRegistered = true
    end
end

function BB:PreviewAll()
    if not next(self.trackerFrames) then
        self:CreateAllTrackers()
    end
    self:RegWithEditMode()
    for index, _ in pairs(self.trackerFrames) do
        self:ShowTracker(index, true)
    end
end

function BB:HideAll()
    for _, frame in pairs(self.trackerFrames) do frame:Hide() end
    if self.updateFrame then self.updateFrame:SetScript("OnUpdate", nil) end
end
