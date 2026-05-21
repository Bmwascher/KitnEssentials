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
        self:RegisterEvent("PLAYER_REGEN_ENABLED", function(selfRef)
            selfRef:UnregisterEvent("PLAYER_REGEN_ENABLED")
            selfRef:CreateDestroyButtons()
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
        destroyButtons[slot] = btn
    end
end

-- Remaining functions populated in subsequent tasks.
