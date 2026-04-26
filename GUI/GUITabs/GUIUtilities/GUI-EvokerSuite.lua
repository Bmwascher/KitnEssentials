-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-EvokerSuite.lua                                     ║
-- ║  GUI: Evoker Suite                                       ║
-- ║  Purpose: Configuration panel for the EvokerSuite module.║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame

local activeTab = "DisintegrateTicks"

GUIFrame:RegisterContent("EvokerSuite", function(scrollChild, yOffset)
    local _, newOffset = GUIFrame:CreateSubTabs(scrollChild, yOffset, {
        tabs = {
            { id = "DisintegrateTicks", label = "Disintegrate" },
            { id = "StasisTracker",     label = "Stasis" },
            { id = "EbonMightHelper",   label = "Ebon Might" },
            { id = "PrescienceTracker", label = "Prescience" },
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
