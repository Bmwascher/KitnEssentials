-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-QualityOfLife.lua                                   ║
-- ║  GUI: Quality of Life                                    ║
-- ║  Purpose: One sidebar entry over four small, unrelated   ║
-- ║           modules that each cost a row of their own.     ║
-- ║           Every tab is an existing page, unchanged.      ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame

-- No header card: each page owns its own master toggle inside itself, so a
-- shared one here would be a second switch for nothing.
GUIFrame:RegisterTabbedContent("QualityOfLife", {
    { id = "SpellAlerts",   label = "Spell Alert Opacity" },
    { id = "MoveFrames",    label = "Move Frames" },
    { id = "CopyAnything",  label = "Copy Anything" },
    { id = "SlashCommands", label = "Slash Commands" },
})
