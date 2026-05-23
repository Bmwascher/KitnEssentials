-- ╔══════════════════════════════════════════════════════════╗
-- ║  InspectPanel.lua                                        ║
-- ║  Module: Inspect Panel                                   ║
-- ║  Purpose: Inspect-side overlays (warnings, slot details, ║
-- ║           track indicators, item level). Shares render   ║
-- ║           helpers with CharacterPanel; owns the inspect  ║
-- ║           event lifecycle and per-target dirty cache.    ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class InspectPanel: AceModule, AceEvent-3.0, AceHook-3.0
local InspectPanel = KitnEssentials:NewModule("InspectPanel", "AceEvent-3.0", "AceHook-3.0")

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function InspectPanel:OnInitialize()
    -- Cache the CharacterPanel module reference; InspectPanel reuses CP's
    -- shared render helpers and FFD accessor. If CharacterPanel was removed
    -- via custom .toc editing, degrade silently.
    self.CP = KitnEssentials:GetModule("CharacterPanel", true)
    if not self.CP then
        KE:Print("InspectPanel disabled: CharacterPanel module not found.")
        self:SetEnabledState(false)
        return
    end
    -- Enabled by CharacterPanel:OnEnable cascade (added in Task 5).
    self:SetEnabledState(false)
end

function InspectPanel:OnEnable()
    if not self.CP or not self.CP.db or not self.CP.db.Enabled then return end
    -- Inspect orchestration moves in from CharacterPanel in Task 5.
end

function InspectPanel:OnDisable()
    -- Inspect teardown moves in from CharacterPanel in Task 5.
end
