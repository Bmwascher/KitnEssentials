-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-GroupTools.lua                                      ║
-- ║  GUI: Group Tools. Raid and group helpers on one page.   ║
-- ║  The per-module builders stay registered under their own ║
-- ║  ids and are dispatched here as tabs.                    ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame

GUIFrame:RegisterTabbedContent("GroupTools", {
    { id = "RaidNotifications",     label = "Raid Notifications" },
    { id = "ReadyCheckConsumables", label = "Ready Check" },
    { id = "WorldMarkerCycler",     label = "World Markers" },
})
