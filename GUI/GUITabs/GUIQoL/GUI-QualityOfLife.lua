-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-QualityOfLife.lua                                   ║
-- ║  GUI: Quality of Life                                    ║
-- ║  Purpose: One sidebar entry over three small, unrelated  ║
-- ║           modules that each cost a row of their own.     ║
-- ║           Every tab is an existing page, unchanged.      ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame

-- No header card: each of the three owns its own master toggle inside its page,
-- so a shared one here would be a second switch for nothing.
GUIFrame:RegisterTabbedContent("QualityOfLife", {
    { id = "SpellAlerts",  label = "Spell Alert Opacity" },
    { id = "MoveFrames",   label = "Move Frames" },
    { id = "CopyAnything", label = "Copy Anything" },
})
