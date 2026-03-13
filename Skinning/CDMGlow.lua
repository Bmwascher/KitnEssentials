-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local SK = KitnEssentials:NewModule("SkinCDMGlow", "AceEvent-3.0", "AceHook-3.0")

function SK:UpdateDB()
    self.db = KE.db.profile.Skinning.CDMGlow
end

function SK:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function SK:ApplySettings()
    -- TODO: implement CDMGlow skinning
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
