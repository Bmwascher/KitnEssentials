-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-HealerTools.lua                                     ║
-- ║  GUI: Healer Utilities — three modules on one page.      ║
-- ║  The per-module builders stay registered under their own ║
-- ║  ids and are dispatched here as tabs.                    ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame

GUIFrame:RegisterTabbedContent("HealerTools", {
    { id = "InnervateTracker",   label = "Innervate Tracker" },
    { id = "MaintenanceTracker", label = "Maintenance Tracker" },
    { id = "HealerMana",         label = "Healer Mana" },
})
