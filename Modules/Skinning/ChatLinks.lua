-- ╔══════════════════════════════════════════════════════════╗
-- ║  ChatLinks.lua                                           ║
-- ║  Module: Chat Link Decoration                            ║
-- ║  Purpose: Prepend an icon to chat hyperlinks and render  ║
-- ║           the profession quality tier as a coloured digit║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

local CL = KitnEssentials:NewModule("ChatLinks", "AceEvent-3.0")

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------

function CL:UpdateDB()
    self.db = KE.db.profile.Skinning.ChatLinks
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------

function CL:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function CL:OnEnable()
    if not self.db then self:UpdateDB() end
end

function CL:OnDisable()
end
