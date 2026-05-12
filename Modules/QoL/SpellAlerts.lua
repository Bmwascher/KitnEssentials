-- ╔══════════════════════════════════════════════════════════╗
-- ║  SpellAlerts.lua                                         ║
-- ║  Module: Spell Alert Opacity                             ║
-- ║  Purpose: Per-spec toggle for Blizzard's spell           ║
-- ║           activation overlay (proc flashes), plus        ║
-- ║           overlay opacity slider.                        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class SpellAlerts: AceModule, AceEvent-3.0
local SA = KitnEssentials:NewModule("SpellAlerts", "AceEvent-3.0")

local SetCVar = SetCVar or (C_CVar and C_CVar.SetCVar)
local GetSpecialization = GetSpecialization

function SA:UpdateDB()
    self.db = KE.db.profile.SpellAlerts
end

function SA:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function SA:ApplyForCurrentSpec()
    local specIndex = GetSpecialization()
    if not specIndex or not self.db then return end

    -- Per-spec opt-in for the activation overlay; default true for unconfigured specs.
    local specs = self.db.EnabledSpecs
    local shown = (specs == nil) or (specs[specIndex] ~= false)
    SetCVar("displaySpellActivationOverlays", shown and "1" or "0")
end

function SA:OnEnable()
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "ApplyForCurrentSpec")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "ApplyForCurrentSpec")
    self:ApplyForCurrentSpec()
end

function SA:OnDisable()
    self:UnregisterAllEvents()
    -- Restore overlays for all specs when the module is turned off.
    SetCVar("displaySpellActivationOverlays", "1")
end

function SA:ApplySettings()
    self:ApplyForCurrentSpec()
end
