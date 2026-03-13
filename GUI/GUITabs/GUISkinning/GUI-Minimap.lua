-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame

GUIFrame:RegisterContent("SkinMinimap", function(scrollChild, yOffset)
    if KE:ShouldNotLoadModule() then return end
    -- TODO: build Minimap skinning settings tab
end)
