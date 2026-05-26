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

-- Prefer C_CVar.SetCVar (12.0 forward path); fall back to the global only
-- if the namespaced version is missing.
local SetCVar = (C_CVar and C_CVar.SetCVar) or SetCVar
local GetSpecialization = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo

function SA:UpdateDB()
    self.db = KE.db.profile.SpellAlerts
end

function SA:OnInitialize()
    self:UpdateDB()
    -- Migration: legacy key was specIndex (1-4), ambiguous across classes.
    -- New key is global specID (>=62). Drop legacy keys once per profile.
    if self.db and self.db.EnabledSpecs and not self.db._specIDMigrated then
        for k in pairs(self.db.EnabledSpecs) do
            if type(k) == "number" and k < 62 then
                self.db.EnabledSpecs[k] = nil
            end
        end
        self.db._specIDMigrated = true
    end
    self:SetEnabledState(false)
end

function SA:ApplyForCurrentSpec()
    local specIndex = GetSpecialization()
    if not specIndex or not self.db then return end

    -- Per-spec opt-in for the activation overlay; default true for unconfigured specs.
    -- Key by global specID (>=62), not the 1-4 spec index which collides across classes.
    local specID = GetSpecializationInfo(specIndex)
    if not specID then return end
    local specs = self.db.EnabledSpecs
    local shown = (specs == nil) or (specs[specID] ~= false)
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
