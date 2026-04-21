-- ╔══════════════════════════════════════════════════════════╗
-- ║  InstanceReset.lua                                       ║
-- ║  Module: Instance Reset Announcer                        ║
-- ║  Purpose: Announces to party/raid chat when the player   ║
-- ║           resets instances.                              ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class InstanceReset: AceModule, AceHook-3.0
local IR = KitnEssentials:NewModule("InstanceReset", "AceHook-3.0")

local SendChatMessage = SendChatMessage
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function IR:UpdateDB()
    if KE.db and KE.db.profile then
        self.db = KE.db.profile.Dungeons and KE.db.profile.Dungeons.InstanceReset
    end
end

function IR:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

---------------------------------------------------------------------------------
-- Hook Handler
---------------------------------------------------------------------------------
local function OnInstanceReset()
    if not IR.db or not IR.db.Enabled then return end

    local channel
    if IsInRaid() then
        channel = "RAID"
    elseif IsInGroup() then
        channel = "PARTY"
    end

    if channel then
        local message = IR.db.Message or "Instance reset!"
        SendChatMessage(message, channel)
    end
end

---------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------
function IR:ApplySettings()
    self:UpdateDB()
    if not self.db or not self.db.Enabled then return end

    if not self:IsHooked("ResetInstances") then
        self:SecureHook("ResetInstances", OnInstanceReset)
    end
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function IR:OnEnable()
    self:UpdateDB()
    if not self.db or not self.db.Enabled then return end
    self:ApplySettings()
end

function IR:OnDisable()
    self:UnhookAll()
end
