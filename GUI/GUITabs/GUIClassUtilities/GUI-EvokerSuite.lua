-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-EvokerSuite.lua                                     ║
-- ║  GUI: Evoker Suite — four modules on one page. The       ║
-- ║  per-module builders stay registered under their own ids ║
-- ║  and are dispatched here as tabs.                        ║
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
