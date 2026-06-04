-- ╔══════════════════════════════════════════════════════════╗
-- ║  DamageMeter/Core.lua                                    ║
-- ║  Module: Damage Meter                                    ║
-- ║  Purpose: In-client damage/healing/threat meter with a   ║
-- ║           configurable dock, per-segment history, and    ║
-- ║           death log.                                     ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class DamageMeter: AceModule, AceEvent-3.0, AceConsole-3.0
local DM = KitnEssentials:NewModule("DamageMeter", "AceEvent-3.0", "AceConsole-3.0")

KE.DamageMeter = DM

local DEBUG_DM = false

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------

function DM:UpdateDB()
    self.db = KE.db.profile.DamageMeter
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------

function DM:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function DM:OnEnable()
    if not self.db or not self.db.Enabled then return end

    self.enabled = true

    if DEBUG_DM then
        KE:Print("[DM] OnEnable: module active")
    end
end

function DM:OnDisable()
    self.enabled = false

    if self.dock and self.dock.Hide then
        self.dock:Hide()
    end

    if DEBUG_DM then
        KE:Print("[DM] OnDisable: module inactive")
    end
end
