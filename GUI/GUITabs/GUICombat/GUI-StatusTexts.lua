-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-StatusTexts.lua                                     ║
-- ║  GUI: Status Texts — five readout modules on one page.   ║
-- ║  The per-module builders stay registered under their own ║
-- ║  ids and are dispatched here as tabs.                    ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame

GUIFrame:RegisterTabbedContent("StatusTexts", {
    { id = "PetStatusText", label = "Pet Status" },
    { id = "StanceText",    label = "Missing Forms" },
    { id = "HuntersMark",   label = "Hunter's Mark" },
    { id = "HealerMana",    label = "Healer Mana" },
    { id = "HavocTracker",  label = "Havoc Tracker" },
})
