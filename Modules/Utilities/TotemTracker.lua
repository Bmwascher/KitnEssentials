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

-- Remaining functions populated in subsequent tasks.
