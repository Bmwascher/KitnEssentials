-- ╔══════════════════════════════════════════════════════════╗
-- ║  FocusCastbar.lua                                        ║
-- ║  Module: Focus Castbar                                   ║
-- ║  Purpose: Repositionable focus cast bar with kick        ║
-- ║           indicators, target name, color settings,       ║
-- ║           and cast sound alert.                          ║
-- ║                                                          ║
-- ║  Shared logic lives in CastbarHelpers.lua (KE.H).        ║
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
local CreateFrame = CreateFrame

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
    if not self.unitEventFrame then
        local f = CreateFrame("Frame")
        f:SetScript("OnEvent", function(_, event, ...)
            if event == "UNIT_SPELLCAST_SUCCEEDED" then
                self:OnPlayerCastSucceeded(event, ...)
            else
                self:OnCastEvent(event, ...)
            end
        end)
        self.unitEventFrame = f
    end
    for _, event in ipairs(castEvents) do
        self.unitEventFrame:RegisterUnitEvent(event, UNIT)
    end
    self.unitEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "pet")

    self:RegisterEvent("PLAYER_FOCUS_CHANGED")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "CacheInterruptId")
    self:RegisterEvent("LOADING_SCREEN_DISABLED", "CacheInterruptId")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "CacheInterruptId")
    self:RegisterEvent("SPELLS_CHANGED", "CacheInterruptId")
    self:RegisterEvent("UNIT_TARGET", "OnUnitTarget")
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnGroupRosterUpdate")
    -- Forever kicks depend on the stance or form and, for Shield Bash, on
    -- the off-hand, so a change of either re-picks the kick there.
    if KE.IS_FOREVER then
        self:RegisterEvent("UPDATE_SHAPESHIFT_FORM", "CacheInterruptId")
        self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", "OnEquipmentChanged")
    end

    H.EnsureOnUpdate(self)
    self:CacheInterruptId()
    self:ToggleTargetMarkerIntegration()
end

function FC:OnDisable()
    if self.unitEventFrame then self.unitEventFrame:UnregisterAllEvents() end
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
    -- Reparents: H.CreateFrame gives this frame the resolved anchor as its
    -- parent, so moving only the point would strand it on the old parent.
    KE:ApplyFramePosition(self.frame, self.db.Position, self.db, true)
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
-- PLAYER_SPECIALIZATION_CHANGED fires for every group member's spec change.
function FC:CacheInterruptId(_, unit)
    if unit and unit ~= "player" then return end
    H.CacheInterruptId(self)
end

-- Its own handler: CacheInterruptId reads its second argument as a unit,
-- and this event's is the slot.
function FC:OnEquipmentChanged(_, slot)
    if slot ~= INVSLOT_OFFHAND then return end
    H.CacheInterruptId(self)
end

function FC:OnCastEvent(event, unit, ...)
    H.OnCastEvent(self, event, unit, ...)
end

function FC:PLAYER_FOCUS_CHANGED()
    H.OnUnitChanged(self)
end

function FC:OnUnitTarget(event, unit)
    H.OnUnitTarget(self, event, unit)
end

function FC:OnGroupRosterUpdate()
    H.OnGroupRosterUpdate(self)
end

function FC:OnRaidTargetUpdate()
    H.UpdateTargetMarker(self)
end

-- Live-toggle helper for db.TargetMarker.Enabled. Called from OnEnable; can
-- also be called from a future GUI toggle without re-running OnEnable.
function FC:ToggleTargetMarkerIntegration()
    if self.db.TargetMarker and self.db.TargetMarker.Enabled then
        self:RegisterEvent("RAID_TARGET_UPDATE", "OnRaidTargetUpdate")
        H.UpdateTargetMarker(self)
    else
        self:UnregisterEvent("RAID_TARGET_UPDATE")
        H.HideTargetMarker(self)
    end
end

---------------------------------------------------------------------------------
-- FC-only: cast-sound alert with kick-CD muting
---------------------------------------------------------------------------------
-- The Interrupt Tracker's own-clock length for the kick just cast, from the
-- player's talents. No interrupt is confirmed at the cast, so a reduction that
-- needs one is not taken. A kick without a definition keeps the castbar's.
function FC:KickMuteSeconds(spellID)
    local fallback = self.interruptCD or 15
    ---@type KickTracker?
    local kt = KitnEssentials:GetModule("KickTracker", true)
    if not (kt and kt.OwnKickCooldown) then return fallback end
    return kt:OwnKickCooldown({ id = spellID, cd = fallback }, false)
end

-- Tracks interrupt cooldown via UNIT_SPELLCAST_SUCCEEDED because
-- C_Spell.GetSpellCooldownDuration can return secret values during combat.
function FC:OnPlayerCastSucceeded(_, unit, _, spellID)
    if unit ~= "player" and unit ~= "pet" then return end
    -- Set-membership match (not single-ID equality). CacheInterruptId's
    -- priority pick may not equal the spell actually cast when multiple
    -- pet-dependent variants are known (e.g. Demo Warlock with Spell Lock
    -- AND Axe Toss both accessible). Match against the full spec set.
    if not self.interruptSpellSet or not self.interruptSpellSet[spellID] then return end
    self.kickOnCD = true
    if self.kickCDTimer then self.kickCDTimer:Cancel() end
    self.kickCDTimer = C_Timer.NewTimer(self:KickMuteSeconds(spellID), function()
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
