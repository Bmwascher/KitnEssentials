-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-ClassTools.lua                                      ║
-- ║  GUI: Class Tools — six class-gated modules on one page. ║
-- ║  The per-module builders stay registered under their own ║
-- ║  ids and are dispatched here as tabs.                    ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame

GUIFrame:RegisterTabbedContent("ClassTools", {
    { id = "DisintegrateTicks", label = "Disintegrate" },
    { id = "HavocTracker",      label = "Havoc Tracker" },
    { id = "HuntersMark",       label = "Hunter's Mark" },
    { id = "StanceText",        label = "Missing Forms" },
    { id = "StasisTracker",     label = "Stasis" },
})
