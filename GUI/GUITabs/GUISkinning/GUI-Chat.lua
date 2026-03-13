-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame

GUIFrame:RegisterContent("SkinChat", function(scrollChild, yOffset)
    if KE:ShouldNotLoadModule() then return end
    -- TODO: build Chat skinning settings tab
end)
