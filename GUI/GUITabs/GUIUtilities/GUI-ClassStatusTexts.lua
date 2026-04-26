-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-ClassStatusTexts.lua                                ║
-- ║  GUI: Class Status Texts                                 ║
-- ║  Purpose: Configuration panel for the ClassStatusTexts   ║
-- ║  module.                                                 ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame

local activeTab = "PetStatusText"

GUIFrame:RegisterContent("ClassStatusTexts", function(scrollChild, yOffset)
    local _, newOffset = GUIFrame:CreateSubTabs(scrollChild, yOffset, {
        tabs = {
            { id = "PetStatusText",   label = "Pet Status" },
            { id = "StanceText",      label = "Stance" },
            { id = "NoMovementAlert", label = "Movement" },
            { id = "DispelCursor",    label = "Dispel" },
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
