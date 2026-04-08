-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-Battlenet.lua                                       ║
-- ║  GUI: Battle.net Toast                                   ║
-- ║  Purpose: Configuration panel for the Battlenet module.  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame

---------------------------------------------------------------------------------
-- Content Registration
---------------------------------------------------------------------------------
GUIFrame:RegisterContent("SkinBattlenet", function(scrollChild, yOffset)
    if KE:ShouldNotLoadModule() then return end
    -- TODO: build Battlenet skinning settings tab
end)
