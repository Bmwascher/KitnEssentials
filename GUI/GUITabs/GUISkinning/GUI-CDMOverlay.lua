-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame

GUIFrame:RegisterContent("SkinCDMOverlay", function(scrollChild, yOffset)
    if KE:ShouldNotLoadModule() then return end
    -- TODO: build CDMOverlay skinning settings tab
end)
