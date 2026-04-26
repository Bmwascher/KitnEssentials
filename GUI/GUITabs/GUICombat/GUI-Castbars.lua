-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-Castbars.lua                                        ║
-- ║  GUI: Focus & Target Castbars                            ║
-- ║  Purpose: Configuration panel for the Castbars module.   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame

local activeTab = "TargetCastbar"

GUIFrame:RegisterContent("Castbars", function(scrollChild, yOffset)
    local _, newOffset = GUIFrame:CreateSubTabs(scrollChild, yOffset, {
        tabs = {
            { id = "TargetCastbar", label = "Target" },
            { id = "FocusCastbar",  label = "Focus" },
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
