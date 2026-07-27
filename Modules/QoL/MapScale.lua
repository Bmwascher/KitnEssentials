-- ╔══════════════════════════════════════════════════════════╗
-- ║  MapScale.lua                                            ║
-- ║  Module: Map Scale                                       ║
-- ║  Purpose: Adjustable world map scale. Extracted from the ║
-- ║           former WorldMap module when the rest of it     ║
-- ║           (coordinates, city pins) was retired.          ║
-- ║  Configured from the QoL > CVars page.                   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@class MapScale: AceModule, AceEvent-3.0
local MS = KitnEssentials:NewModule("MapScale", "AceEvent-3.0")

local C_Timer = C_Timer
local EventRegistry = EventRegistry

---------------------------------------------------------------------------------
-- Module State
---------------------------------------------------------------------------------
MS.scaleCallbacksRegistered = false

---------------------------------------------------------------------------------
-- DB Helper
---------------------------------------------------------------------------------
function MS:UpdateDB()
    self.db = KE.db.profile.MapScale
end

---------------------------------------------------------------------------------
-- Core Logic
---------------------------------------------------------------------------------
function MS:ApplyScale()
    if not self.db or not self.db.Enabled then
        self:RevertScale()
        return
    end
    if not WorldMapFrame then return end

    WorldMapFrame:SetClampedToScreen(true)
    WorldMapFrame:SetScale(self.db.Scale or 1.2)

    -- Module-level guard so the callbacks register exactly once.
    if not self.scaleCallbacksRegistered then
        EventRegistry:RegisterCallback("WorldMapMinimized", function()
            if self.db and self.db.Enabled then
                WorldMapFrame:SetScale(self.db.Scale or 1.2)
            end
        end, self)
        EventRegistry:RegisterCallback("WorldMapMaximized", function()
            WorldMapFrame:SetScale(1)
        end, self)
        self.scaleCallbacksRegistered = true
    end
end

function MS:RevertScale()
    if WorldMapFrame then
        WorldMapFrame:SetScale(1)
    end
    if self.scaleCallbacksRegistered then
        EventRegistry:UnregisterCallback("WorldMapMinimized", self)
        EventRegistry:UnregisterCallback("WorldMapMaximized", self)
        self.scaleCallbacksRegistered = false
    end
end

---------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------
function MS:OnInitialize()
    self:UpdateDB()
    self:SetEnabledState(false)
end

function MS:OnEnable()
    if not self.db or not self.db.Enabled then return end

    -- Blizzard_WorldMap / Blizzard_MapCanvas may not be loaded at login.
    self:RegisterEvent("ADDON_LOADED", function(_, addonName)
        if addonName == "Blizzard_WorldMap" or addonName == "Blizzard_MapCanvas" then
            self:ApplyScale()
        end
    end)

    C_Timer.After(0, function()
        self:ApplyScale()
    end)
end

function MS:OnDisable()
    self:RevertScale()
    self:UnregisterAllEvents()
end
