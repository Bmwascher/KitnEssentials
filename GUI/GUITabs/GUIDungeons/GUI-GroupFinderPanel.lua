-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-GroupFinderPanel.lua                                ║
-- ║  GUI: Group Finder Panel                                 ║
-- ║  Purpose: Configuration panel for the GroupFinderPanel   ║
-- ║           module (quick-access side panel beside the     ║
-- ║           Group Finder).                                 ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame

GUIFrame:RegisterContent("GroupFinderPanel", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.GroupFinderPanel
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available.")
        return errorCard:GetNextOffset()
    end

    local function GetModule()
        return KitnEssentials and KitnEssentials:GetModule("GroupFinderPanel", true)
    end

    local function ApplyModuleState(enabled)
        if not GetModule() then return end
        if enabled then
            KitnEssentials:EnableModule("GroupFinderPanel")
        else
            KitnEssentials:DisableModule("GroupFinderPanel")
        end
    end

    local card1 = GUIFrame:CreateCard(scrollChild, "Group Finder Panel", yOffset)
    -- Order matters: db.Enabled is written FIRST. IsActive() reads it, and
    -- the module's teardown path depends on it already being false.
    card1:AddHeaderToggle(db.Enabled == true, function(checked)
        db.Enabled = checked
        ApplyModuleState(checked)
        local GFP = GetModule()
        if GFP and GFP.Refresh then GFP:Refresh() end
        KE:Print("Group Finder Panel: " .. (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
    end)

    -- Lone header bar: a disabled module shows its switch and nothing else.
    if db.Enabled ~= true then return card1:GetNextOffset() end

    -- Measured AFTER the label, not before: the label grows the card, so an
    -- offset read ahead of it puts the next card on top of this one.
    card1:AddLabel("Adds a panel beside the Group Finder with this week's affixes, one-click category searches, and your weekly Mythic+ run count. While browsing Mythic+ groups it becomes a filter pane: dungeon toggles, role filters and a minimum leader score. The filters are Blizzard's own, so turning this module off clears them. Steps aside automatically if Premade Groups Filter is installed.")

    return card1:GetNextOffset()
end)
