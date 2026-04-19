-- ╔══════════════════════════════════════════════════════════╗
-- ║  TargetCastbar.lua                                       ║
-- ║  Module: Target Castbar                                  ║
-- ║  Purpose: Repositionable target cast bar with kick       ║
-- ║           indicators, target name, color settings.       ║
-- ║                                                          ║
-- ║  Shared logic lives in Combat/CastbarHelpers.lua (KE.H). ║
-- ║  This file owns target-specific events and config-       ║
-- ║  bearing opts tables. No cast sound (by design).         ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class TargetCastbar: AceModule, AceEvent-3.0
local TC = KitnEssentials:NewModule("TargetCastbar", "AceEvent-3.0")
local H = KE.CastbarHelpers

local C_Timer = C_Timer

local UNIT = "target"
local FRAME_OPTS = {
    frameName = "KE_TargetCastbarFrame",
    defaultWidth = 250,
    defaultHeight = 20,
    defaultYOffset = -200,
}
local SETTINGS_OPTS = { defaultWidth = 250 }
local EDITMODE_OPTS = {
    key = "TargetCastbar",
    displayName = "Target Castbar",
    guiPath = "TargetCastbar",
}
local PREVIEW_OPTS = { previewText = "Target Castbar" }

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function TC:UpdateDB()
    self.db = KE.db.profile.TargetCastbar
end

function TC:OnInitialize()
    self.unit = UNIT
    self:UpdateDB()
    self:SetEnabledState(false)
end

function TC:OnEnable()
    if not self.db.Enabled then return end
    H.CreateColorObjects(self)
    self:CreateFrame()
    self:RegWithEditMode()
    C_Timer.After(0.5, function() self:ApplyPosition() end)

    local castEvents = {
        "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_EMPOWER_START",
        "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_EMPOWER_STOP",
        "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
        "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
    }
    for _, event in ipairs(castEvents) do
        self:RegisterEvent(event, "OnCastEvent")
    end

    self:RegisterEvent("PLAYER_TARGET_CHANGED")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "CacheInterruptId")
    self:RegisterEvent("LOADING_SCREEN_DISABLED", "CacheInterruptId")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "CacheInterruptId")
    self:RegisterEvent("SPELLS_CHANGED", "CacheInterruptId")

    H.EnsureOnUpdate(self)
    self:CacheInterruptId()
end

function TC:OnDisable()
    if self.frame then
        self.frame:SetScript("OnUpdate", nil)
        self.frame:Hide()
    end
    if self.holdTimer then
        self.holdTimer:Cancel()
        self.holdTimer = nil
    end
    H.HideTargetNames(self)
    H.ResetCastState(self)
    self.isPreview = false
    self:UnregisterAllEvents()
end

---------------------------------------------------------------------------------
-- Public methods (called from GUI / EditMode / helpers)
---------------------------------------------------------------------------------
function TC:CreateFrame()
    H.CreateFrame(self, FRAME_OPTS)
end

function TC:ApplySettings()
    H.ApplySettings(self, SETTINGS_OPTS)
end

function TC:ApplyPosition()
    if not self.frame then return end
    KE:ApplyFramePosition(self.frame, self.db.Position, self.db)
end

function TC:RegWithEditMode()
    H.RegWithEditMode(self, EDITMODE_OPTS)
end

function TC:ShowPreview()
    H.ShowPreview(self, PREVIEW_OPTS)
end

function TC:HidePreview()
    H.HidePreview(self)
end

---------------------------------------------------------------------------------
-- Event handlers (Ace3 dispatches by method name)
---------------------------------------------------------------------------------
function TC:CacheInterruptId()
    H.CacheInterruptId(self)
end

function TC:OnCastEvent(event, unit, ...)
    H.OnCastEvent(self, event, unit, ...)
end

function TC:PLAYER_TARGET_CHANGED()
    H.OnUnitChanged(self)
end
