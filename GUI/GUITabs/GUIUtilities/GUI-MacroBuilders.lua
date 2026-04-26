-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-MacroBuilders.lua                                   ║
-- ║  GUI: Macro Builders                                     ║
-- ║  Purpose: Configuration panel for the MacroBuilders      ║
-- ║  module.                                                 ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame

local activeTab = "FocusMarker"

GUIFrame:RegisterContent("MacroBuilders", function(scrollChild, yOffset)
    local _, newOffset = GUIFrame:CreateSubTabs(scrollChild, yOffset, {
        tabs = {
            { id = "FocusMarker",    label = "Focus Marker" },
            { id = "PIMacroBuilder", label = "Power Infusion" },
        },
        activeId = activeTab,
        onSwitch = function(newId) activeTab = newId end,
        fill = true,
    })
    yOffset = newOffset

    local builder = GUIFrame.registeredContent[activeTab]
    if builder then
        return builder(scrollChild, yOffset)
    end
    return yOffset
end)
