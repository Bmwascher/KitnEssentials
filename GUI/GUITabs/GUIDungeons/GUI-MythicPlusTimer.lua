-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-MythicPlusTimer.lua                                 ║
-- ║  GUI: Mythic+ Timer                                      ║
-- ║  Purpose: Configuration panel for the MythicPlusTimer    ║
-- ║           module.                                        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme -- luacheck: ignore 211
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)
local pairs = pairs

local activeTab = "Timer"

local function GetMPT()
    return KitnEssentials and KitnEssentials:GetModule("MythicPlusTimer", true)
end

local function ApplySettings() -- luacheck: ignore 211
    local M = GetMPT()
    if M and M.ApplySettings then M:ApplySettings() end
end

-- Builds an LSM media hash {name = name} for searchable dropdowns.
local function MediaList(kind, fallback) -- luacheck: ignore 211
    local out = {}
    if LSM then
        for name in pairs(LSM:HashTable(kind)) do out[name] = name end
    else
        out[fallback] = fallback
    end
    return out
end

-- Forward declarations — assigned in Tasks 5.5–5.10.
local BuildTimerTab, BuildForcesTab, BuildObjectivesTab, BuildDeathsTab, BuildOverlayTab, BuildGeneralTab -- luacheck: ignore 221

GUIFrame:RegisterContent("MythicPlusTimer", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.MythicPlusTimer
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local _, newOffset = GUIFrame:CreateSubTabs(scrollChild, yOffset, {
        tabs = {
            { id = "Timer",      label = "Timer" },
            { id = "Forces",     label = "Forces" },
            { id = "Objectives", label = "Objectives" },
            { id = "Deaths",     label = "Deaths" },
            { id = "Overlay",    label = "Enemy Overlay" },
            { id = "General",    label = "General" },
        },
        activeId = activeTab,
        onSwitch = function(newId) activeTab = newId end,
        fill = true,
    })
    yOffset = newOffset

    local manager = GUIFrame:CreateWidgetStateManager()

    if activeTab == "Timer" then
        yOffset = BuildTimerTab(scrollChild, yOffset, db, manager)
    elseif activeTab == "Forces" then
        yOffset = BuildForcesTab(scrollChild, yOffset, db, manager)
    elseif activeTab == "Objectives" then
        yOffset = BuildObjectivesTab(scrollChild, yOffset, db, manager)
    elseif activeTab == "Deaths" then
        yOffset = BuildDeathsTab(scrollChild, yOffset, db, manager)
    elseif activeTab == "Overlay" then
        yOffset = BuildOverlayTab(scrollChild, yOffset, db, manager)
    elseif activeTab == "General" then
        yOffset = BuildGeneralTab(scrollChild, yOffset, db, manager)
    end

    manager:UpdateAll(db.Enabled ~= false)
    return yOffset
end)
