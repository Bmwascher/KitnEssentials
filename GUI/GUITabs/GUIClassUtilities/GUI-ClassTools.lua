-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-ClassTools.lua                                      ║
-- ║  GUI: Class Tools. One tab per class that has tools,     ║
-- ║  plus All Classes; opens on the player's own class.      ║
-- ║  The per-module builders stay registered under their own ║
-- ║  ids and are dispatched here as tabs.                    ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame

local ipairs = ipairs
local UnitClass = UnitClass

-- Hunter and Warlock have one tool each, so their tab is that tool's page.
local CLASS_TAB = {
    EVOKER  = "ClassToolsEvoker",
    HUNTER  = "HuntersMark",
    PRIEST  = "ClassToolsPriest",
    WARLOCK = "HavocTracker",
}

function GUIFrame.ClassToolsTabForClass(classToken)
    return classToken and CLASS_TAB[classToken] or "ClassToolsAllClasses"
end

-- Edit Mode names a tool, not its class page; the owner map is how the outer
-- strip finds the page that holds it.
local function RegisterClassPage(pageId, tabs)
    local ids = {}
    for i, tab in ipairs(tabs) do ids[i] = tab.id end
    GUIFrame:RegisterNestedTabs(pageId, ids)
    GUIFrame:RegisterTabbedContent(pageId, tabs)
end

RegisterClassPage("ClassToolsAllClasses", {
    { id = "StanceText", label = "Missing Forms" },
    { id = "Recuperate", label = "Recuperate" },
    { id = "TimeSpiral", label = "Time Spiral" },
})

RegisterClassPage("ClassToolsEvoker", {
    { id = "DisintegrateTicks", label = "Disintegrate" },
    { id = "StasisTracker",     label = "Stasis" },
})

RegisterClassPage("ClassToolsPriest", {
    { id = "PIMacroBuilder", label = "PI Macro" },
    { id = "PIAssist",       label = "PI Assist" },
})

GUIFrame:RegisterTabbedContent("ClassTools", {
    { id = "ClassToolsAllClasses", label = "All Classes" },
    { id = "ClassToolsEvoker",     label = "Evoker" },
    { id = "HuntersMark",          label = "Hunter" },
    { id = "ClassToolsPriest",     label = "Priest" },
    { id = "HavocTracker",         label = "Warlock" },
}, {
    defaultTab = function()
        return GUIFrame.ClassToolsTabForClass(select(2, UnitClass("player")))
    end,
})
