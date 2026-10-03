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
    { id = "PotionReady",     label = "Combat Potion" },
    { id = "HealerMana",      label = "Healer Mana" },
    { id = "NoMovementAlert", label = "No Movement Alert" },
    { id = "PetStatusText",   label = "Pet Status" },
    { id = "PlayerAbsorbs",   label = "Player Absorbs" },
})
