-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame

GUIFrame:RegisterContent("SkinBattlenet", function(scrollChild, yOffset)
    if KE:ShouldNotLoadModule() then return end
    -- TODO: build Battlenet skinning settings tab
end)
