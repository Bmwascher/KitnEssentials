-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame

GUIFrame:RegisterContent("SkinCDMGlow", function(scrollChild, yOffset)
    if KE:ShouldNotLoadModule() then return end
    -- TODO: build CDMGlow skinning settings tab
end)
