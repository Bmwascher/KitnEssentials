-- ╔══════════════════════════════════════════════════════════╗
-- ║  FocusCastbar.lua                                        ║
-- ║  Module: Focus Castbar                                   ║
-- ║  Purpose: Repositionable focus cast bar with kick        ║
-- ║           indicators, target name, color settings,       ║
-- ║           and cast sound alert.                          ║
-- ║                                                          ║
-- ║  Shared logic lives in Combat/CastbarHelpers.lua (KE.H). ║
-- ║  This file owns focus-specific events, FC-only sound     ║
-- ║  hook, and config-bearing opts tables.                   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class FocusCastbar: AceModule, AceEvent-3.0
local FC = KitnEssentials:NewModule("FocusCastbar", "AceEvent-3.0")
local H = KE.CastbarHelpers

local PlaySoundFile = PlaySoundFile
local C_Timer = C_Timer

local UNIT = "focus"
local FRAME_OPTS = {
    frameName = "KE_FocusCastbarFrame",
    defaultWidth = 200,
    defaultHeight = 18,
    defaultYOffset = 200,
}
local SETTINGS_OPTS = { defaultWidth = 200 }
local EDITMODE_OPTS = {
    key = "FocusCastbar",
    displayName = "Focus Castbar",
    guiPath = "FocusCastbar",
}
local PREVIEW_OPTS = { previewText = "Focus Castbar" }

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function FC:UpdateDB()
    self.db = KE.db.profile.FocusCastbar
end

function FC:OnInitialize()
    self.unit = UNIT
    self:UpdateDB()
    self:SetEnabledState(false)
end

function FC:OnEnable()
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

    self:RegisterEvent("PLAYER_FOCUS_CHANGED")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "CacheInterruptId")
    self:RegisterEvent("LOADING_SCREEN_DISABLED", "CacheInterruptId")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "CacheInterruptId")
    self:RegisterEvent("SPELLS_CHANGED", "CacheInterruptId")
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnPlayerCastSucceeded")

    H.EnsureOnUpdate(self)
    self:CacheInterruptId()
end

function FC:OnDisable()
    if self.frame then
        self.frame:SetScript("OnUpdate", nil)
        self.frame:Hide()
    end
    if self.holdTimer then
        self.holdTimer:Cancel()
        self.holdTimer = nil
    end
    if self.kickCDTimer then
        self.kickCDTimer:Cancel()
        self.kickCDTimer = nil
    end
    self.kickOnCD = false
    H.HideTargetNames(self)
    H.ResetCastState(self)
    self.isPreview = false
    self:UnregisterAllEvents()
end

---------------------------------------------------------------------------------
-- Public methods (called from GUI / EditMode / helpers)
---------------------------------------------------------------------------------
function FC:CreateFrame()
    H.CreateFrame(self, FRAME_OPTS)
end

function FC:ApplySettings()
    H.ApplySettings(self, SETTINGS_OPTS)
end

function FC:ApplyPosition()
    if not self.frame then return end
    KE:ApplyFramePosition(self.frame, self.db.Position, self.db)
end

function FC:RegWithEditMode()
    H.RegWithEditMode(self, EDITMODE_OPTS)
end

function FC:ShowPreview()
    H.ShowPreview(self, PREVIEW_OPTS)
end

function FC:HidePreview()
    H.HidePreview(self)
end

---------------------------------------------------------------------------------
-- Event handlers (Ace3 dispatches by method name)
---------------------------------------------------------------------------------
function FC:CacheInterruptId()
    H.CacheInterruptId(self)
end

function FC:OnCastEvent(event, unit, ...)
    H.OnCastEvent(self, event, unit, ...)
end

function FC:PLAYER_FOCUS_CHANGED()
    H.OnUnitChanged(self)
end

---------------------------------------------------------------------------------
-- FC-only: cast-sound alert with kick-CD muting
---------------------------------------------------------------------------------
-- Tracks interrupt cooldown via UNIT_SPELLCAST_SUCCEEDED because
-- C_Spell.GetSpellCooldownDuration can return secret values during combat.
function FC:OnPlayerCastSucceeded(_, unit, _, spellID)
    if unit ~= "player" and unit ~= "pet" then return end
    if not self.interruptId or spellID ~= self.interruptId then return end
    self.kickOnCD = true
    if self.kickCDTimer then self.kickCDTimer:Cancel() end
    self.kickCDTimer = C_Timer.NewTimer(self.interruptCD or 15, function()
        self.kickOnCD = false
        self.kickCDTimer = nil
    end)
end

function FC:PlayCastSound()
    if not self.db.SoundEnabled then return end
    if self.isPreview then return end
    if self.db.MuteSoundOnKickCD and self.kickOnCD then return end
    local soundFile = self.db.SoundFile
    if not soundFile or soundFile == "None" then return end
    local LSM = LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local path = LSM:Fetch("sound", soundFile)
        if path then
            PlaySoundFile(path, self.db.SoundChannel or "SFX")
        end
    end
end
