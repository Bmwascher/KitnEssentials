-- ╔══════════════════════════════════════════════════════════╗
-- ║  Battlenet.lua                                           ║
-- ║  Module: Battle.net Toast                                ║
-- ║  Purpose: Reskins Battle.net notification toasts         ║
-- ║           with dark theme.                               ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local SK = KitnEssentials:NewModule("SkinBattlenet", "AceEvent-3.0", "AceHook-3.0")

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------

function SK:UpdateDB()
    self.db = KE.db.profile.Skinning.Battlenet
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------

function SK:ApplySettings()
    -- TODO: implement Battlenet skinning
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------

function SK:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function SK:OnEnable()
    if KE:ShouldNotLoadModule() then return end
    if not self.db.Enabled then return end
    self:ApplySettings()
end

function SK:OnDisable()
    self:UnregisterAllEvents()
    self:UnhookAll()
end
