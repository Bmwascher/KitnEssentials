-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-EvokerSuite.lua                                     ║
-- ║  GUI: Evoker Suite                                       ║
-- ║  Purpose: Configuration panel for the EvokerSuite module.║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame

GUIFrame:RegisterTabbedContent("EvokerSuite", {
    { id = "DisintegrateTicks", label = "Disintegrate" },
    { id = "StasisTracker",     label = "Stasis" },
    { id = "EbonMightHelper",   label = "Ebon Might" },
    { id = "PrescienceTracker", label = "Prescience" },
})
