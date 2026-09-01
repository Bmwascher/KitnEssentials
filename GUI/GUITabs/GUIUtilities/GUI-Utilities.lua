-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-Utilities.lua                                       ║
-- ║  GUI: six small utilities on one page. The per-module    ║
-- ║  builders stay registered under their own ids and are    ║
-- ║  dispatched here as tabs.                                ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame

GUIFrame:RegisterTabbedContent("Utilities", {
    { id = "PIMacroBuilder",        label = "Priest: PI Macro" },
    { id = "RaidNotifications",     label = "Raid Notifications" },
    { id = "ReadyCheckConsumables", label = "Ready Check" },
    { id = "Recuperate",            label = "Recuperate" },
    { id = "TimeSpiral",            label = "Time Spiral" },
    { id = "WorldMarkerCycler",     label = "World Markers" },
})
