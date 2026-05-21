-- ╔══════════════════════════════════════════════════════════╗
-- ║  TotemTracker.lua                                        ║
-- ║  Module: Totem Tracker (Shaman)                          ║
-- ║  Purpose: Custom totem icon bar with cooldown swipes,    ║
-- ║           timer text, and a destroy-all-totems macro.    ║
-- ║  Credit: Ported from NorskenUI v3.13 TotemTracker.       ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class TotemTracker: AceModule, AceEvent-3.0
local TT = KitnEssentials:NewModule("TotemTracker", "AceEvent-3.0")

local CreateFrame = CreateFrame
local ipairs = ipairs
local GetTotemInfo = GetTotemInfo
local GetTime = GetTime
local UIParent = UIParent
local GetTotemDuration = GetTotemDuration
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer

local MAX_TOTEMS = MAX_TOTEMS
local TOTEM_PRIORITIES = STANDARD_TOTEM_PRIORITIES

local containerFrame = nil
local totemButtons = {}
local destroyButtons = {}
local isPreviewActive = false

local PREVIEW_ICONS = {
    [1] = 136098, -- Healing Stream Totem
    [2] = 136024, -- Capacitor Totem
    [3] = 136114, -- Tremor Totem
    [4] = 136013, -- Earthbind Totem
}

function TT:UpdateDB()
    self.db = KE.db.profile.TotemTracker
end

function TT:OnInitialize()
    self:UpdateDB()
    self:CreateDestroyButtons()
    self:SetEnabledState(false)
end

function TT:CreateDestroyButtons()
    if destroyButtons[1] then return end
    if InCombatLockdown() then
        -- AceEvent-3.0 closure callbacks receive (event, ...args), NOT (self, ...).
        -- Capture the module table via an upvalue.
        local module = self
        self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
            module:UnregisterEvent("PLAYER_REGEN_ENABLED")
            module:CreateDestroyButtons()
        end)
        return
    end

    for slot = 1, MAX_TOTEMS do
        local btn = CreateFrame("Button", "KE_DestroyTotem" .. slot, UIParent, "SecureActionButtonTemplate")
        btn:SetAttribute("type",                "destroytotem")
        btn:SetAttribute("typerelease",         "destroytotem")
        btn:SetAttribute("totem-slot",          slot)
        btn:SetAttribute("pressAndHoldAction",  1)
        btn:RegisterForClicks("AnyUp", "AnyDown")
        btn:Hide()
        destroyButtons[slot] = btn
    end
end

local function ApplyCooldownTextStyle(cooldown, db)
    if not cooldown then return end

    for _, region in ipairs({ cooldown:GetRegions() }) do
        if region:GetObjectType() == "FontString" then
            KE:ApplyFontToText(region, db.FontFace, db.TimerFontSize, db.FontOutline)
            region:SetShadowOffset(0, 0)
            region:ClearAllPoints()
            region:SetPoint("CENTER", cooldown, "CENTER", 0, 0)
        end
    end
end

function TT:CreateTotemButton(slot)
    local db = self.db

    local btn = CreateFrame("Button", "KE_TotemButton" .. slot, containerFrame)
    btn:SetSize(db.IconSize, db.IconSize)
    btn:SetID(slot)

    btn:SetScript("OnEnter", function(frame)
        if GameTooltip:IsForbidden() or not frame:IsVisible() then return end
        GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
        GameTooltip:SetTotem(frame:GetID())
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        if GameTooltip:IsForbidden() then return end
        GameTooltip:Hide()
    end)

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints(btn)
    KE:ApplyIconZoom(btn.icon, 0.08)

    KE:AddIconBorders(btn, { 0, 0, 0, 1 })

    btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    btn.highlight:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    btn.highlight:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    btn.highlight:SetColorTexture(1, 1, 1, 0.2)
    btn.highlight:SetBlendMode("ADD")

    btn.cooldown = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    btn.cooldown:SetAllPoints(btn)
    btn.cooldown:SetDrawEdge(false)
    btn.cooldown:SetDrawSwipe(db.Swipe)
    btn.cooldown:SetReverse(db.Reverse)
    btn.cooldown:SetDrawBling(false)
    btn.cooldown:SetHideCountdownNumbers(not db.ShowTimer)

    btn:Hide()

    return btn
end

function TT:CreateContainer()
    if containerFrame then return end

    containerFrame = CreateFrame("Frame", "KE_TotemTracker", UIParent)
    containerFrame:SetSize(200, 50)
    containerFrame:SetClampedToScreen(true)

    for slot = 1, MAX_TOTEMS do
        totemButtons[slot] = self:CreateTotemButton(slot)
    end
end

function TT:UpdateButtonSettings(btn)
    local db = self.db
    btn:SetSize(db.IconSize, db.IconSize)
    btn.cooldown:SetDrawSwipe(db.Swipe)
    btn.cooldown:SetReverse(db.Reverse)
    btn.cooldown:SetHideCountdownNumbers(not db.ShowTimer)
    ApplyCooldownTextStyle(btn.cooldown, db)
end

function TT:UpdateContainerPosition()
    if not containerFrame then return end

    local db = self.db
    local position = db.Position
    local parent = KE:ResolveAnchorFrame(db.anchorFrameType, db.ParentFrame)
    if not parent then return end

    containerFrame:SetParent(parent)
    containerFrame:ClearAllPoints()

    local direction = db.GrowDirection
    if direction == "RIGHT" then
        containerFrame:SetPoint("LEFT", parent, position.AnchorTo, position.XOffset, position.YOffset)
    elseif direction == "LEFT" then
        containerFrame:SetPoint("RIGHT", parent, position.AnchorTo, position.XOffset, position.YOffset)
    elseif direction == "UP" then
        containerFrame:SetPoint("BOTTOM", parent, position.AnchorTo, position.XOffset, position.YOffset)
    elseif direction == "DOWN" then
        containerFrame:SetPoint("TOP", parent, position.AnchorTo, position.XOffset, position.YOffset)
    else
        containerFrame:SetPoint(position.AnchorFrom, parent, position.AnchorTo, position.XOffset, position.YOffset)
    end

    containerFrame:SetFrameStrata(db.Strata)

    -- Honor opt-in pixel-snap toggle. We can't use KE:ApplyFramePositionWithSnap
    -- here because it does its own SetPoint (CENTER/CENTER) which would override
    -- our growth-direction-aware anchoring. Instead, call SnapFrameToPixels
    -- directly after the directional SetPoint has been applied.
    if db.SnapToPixelGrid and KE.SnapFrameToPixels then
        KE:SnapFrameToPixels(containerFrame)
    end
end

function TT:LayoutButtons(visibleButtons)
    if not containerFrame then return end

    local db = self.db
    local direction = db.GrowDirection
    local spacing = db.IconSpacing
    local size = db.IconSize

    local buttonsToLayout = visibleButtons or totemButtons
    local numVisible = #buttonsToLayout
    if numVisible == 0 then numVisible = 1 end

    local totalWidth, totalHeight
    if direction == "RIGHT" or direction == "LEFT" then
        totalWidth  = (size * numVisible) + (spacing * (numVisible - 1))
        totalHeight = size
    else
        totalWidth  = size
        totalHeight = (size * numVisible) + (spacing * (numVisible - 1))
    end
    containerFrame:SetSize(totalWidth, totalHeight)

    for i, btn in ipairs(buttonsToLayout) do
        btn:ClearAllPoints()

        if direction == "RIGHT" then
            local xOffset = (i - 1) * (size + spacing)
            btn:SetPoint("LEFT", containerFrame, "LEFT", xOffset, 0)
        elseif direction == "LEFT" then
            local xOffset = -((i - 1) * (size + spacing))
            btn:SetPoint("RIGHT", containerFrame, "RIGHT", xOffset, 0)
        elseif direction == "UP" then
            local yOffset = (i - 1) * (size + spacing)
            btn:SetPoint("BOTTOM", containerFrame, "BOTTOM", 0, yOffset)
        elseif direction == "DOWN" then
            local yOffset = -((i - 1) * (size + spacing))
            btn:SetPoint("TOP", containerFrame, "TOP", 0, yOffset)
        end
    end
end

---@param btn table
---@param totem table
function TT:UpdateButton(btn, totem)
    if not (btn and totem) then return end
    if not totem.slot then return end

    local slot = totem.slot
    local haveTotem, _, _, _, icon = GetTotemInfo(slot)

    if haveTotem then
        btn.icon:SetTexture(icon)
        btn.cooldown:SetCooldownFromDurationObject(GetTotemDuration(slot))
        btn:Show()
    else
        btn.cooldown:Clear()
        btn:Hide()
    end
end

function TT:UpdateTotems()
    if not self.db or not self.db.Enabled then return end

    if isPreviewActive then
        local currentTime = GetTime()
        local visibleButtons = {}
        for slot = 1, MAX_TOTEMS do
            local btn = totemButtons[slot]
            if btn then
                btn.icon:SetTexture(PREVIEW_ICONS[slot] or PREVIEW_ICONS[1])
                btn.cooldown:SetCooldown(currentTime - (slot * 10), 120)
                btn:Show()
                visibleButtons[#visibleButtons + 1] = btn
            end
        end
        self:LayoutButtons(visibleButtons)
        return
    end

    for i = 1, MAX_TOTEMS do
        local btn = totemButtons[i]
        if btn then btn:Hide() end
    end

    local visibleButtons = {}
    if TotemFrame and TotemFrame.totemPool then
        for totem in TotemFrame.totemPool:EnumerateActive() do
            local priorityIndex = TOTEM_PRIORITIES[totem.layoutIndex]
            if priorityIndex then
                local btn = totemButtons[priorityIndex]
                self:UpdateButton(btn, totem)
                if btn and btn:IsShown() then
                    visibleButtons[#visibleButtons + 1] = btn
                end
            end
        end
    end

    self:LayoutButtons(visibleButtons)
end

function TT:OnTotemUpdate()
    if self.db and self.db.Enabled then self:UpdateTotems() end
end

function TT:ApplySettings()
    self:UpdateDB()
    self:UpdateContainerPosition()

    for slot = 1, MAX_TOTEMS do
        if totemButtons[slot] then self:UpdateButtonSettings(totemButtons[slot]) end
    end

    self:UpdateTotems()
end

-- Remaining functions populated in subsequent tasks.
