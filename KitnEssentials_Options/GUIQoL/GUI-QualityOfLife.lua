-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-QualityOfLife.lua                                   ║
-- ║  GUI: Quality of Life                                    ║
-- ║  Purpose: One sidebar entry over five small, unrelated   ║
-- ║           modules that each cost a row of their own.     ║
-- ║           Every tab is an existing page, unchanged.      ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame

-- No header card: each page owns its own master toggle inside itself, so a
-- shared one here would be a second switch for nothing.
GUIFrame:RegisterTabbedContent("QualityOfLife", {
    { id = "SpellAlerts",     label = "Spell Alert Opacity" },
    { id = "MoveFrames",      label = "Move Frames" },
    { id = "GreatVaultAlert", label = "Great Vault Alert" },
    { id = "CopyAnything",    label = "Copy Anything" },
    { id = "SlashCommands",   label = "Slash Commands" },
})
