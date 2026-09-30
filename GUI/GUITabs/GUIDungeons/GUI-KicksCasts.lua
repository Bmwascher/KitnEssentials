-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-KicksCasts.lua                                      ║
-- ║  GUI: Kicks & Casts. Interrupt and enemy cast pages.     ║
-- ║  The per-module builders stay registered under their own ║
-- ║  ids and are dispatched here as tabs.                    ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame

GUIFrame:RegisterTabbedContent("KicksCasts", {
    { id = "FocusMarker",  label = "Focus Marker" },
    { id = "KickTracker",  label = "Interrupt Tracker" },
    { id = "DungeonCasts", label = "Dungeon Casts" },
})
