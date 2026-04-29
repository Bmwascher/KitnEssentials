-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-UICleanup.lua                                       ║
-- ║  GUI: General UI Clean Up                                ║
-- ║  Purpose: Configuration panel for the UICleanup module.  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetUICleanupModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("SkinUICleanup", true)
    end
    return nil
end

GUIFrame:RegisterContent("SkinUICleanup", function(scrollChild, yOffset)
    if KE:ShouldNotLoadModule() then return end
    local db = KE.db and KE.db.profile.Skinning.UICleanup
    if not db then return yOffset end

    local UIC = GetUICleanupModule()
    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplyUICleanupState(enabled)
        if not UIC then return end
        UIC.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("SkinUICleanup")
        else
            KitnEssentials:DisableModule("SkinUICleanup")
        end
    end

    ----------------------------------------------------------------
    -- Card 1: Enable + Description
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "General UI Cleanup", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable UI Cleanup", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyUICleanupState(checked)
            manager:UpdateAll(checked)
            if not checked then
                KE:CreateReloadPrompt("Enabling Blizzard UI elements requires a reload to take full effect.")
            end
        end,
        msgPopup = true,
        msgText = "UI Cleanup",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, Theme.rowHeight)

    local sepRow = GUIFrame:CreateRow(card1.content, Theme.rowHeightSeparator)
    local sepWidget = GUIFrame:CreateSeparator(sepRow)
    sepRow:AddWidget(sepWidget, 1)
    card1:AddRow(sepRow, Theme.rowHeightSeparator)

    local hiddenNames = {
        "Objective Tracker Background",
        "Quest Tracker Background",
        "World Quest Tracker Background",
        "Scenario Tracker Background",
        "Monthly Activities Tracker Background",
        "Bonus Objective Tracker Background",
        "Professions Tracker Background",
        "Achievement Tracker Background",
        "Campaign Tracker Background",
    }
    local infoRowHeight = 165
    local row2 = GUIFrame:CreateRow(card1.content, infoRowHeight)
    local textWidget = GUIFrame:CreateText(
        row2,
        KE:ColorTextByTheme("Hides The Following Frames"),
        function() return hiddenNames end,
        infoRowHeight,
        "hide"
    )
    row2:AddWidget(textWidget, 1)
    manager:Register(textWidget, "all")
    card1:AddRow(row2, infoRowHeight, 0)

    yOffset = card1:GetNextOffset()

    manager:UpdateAll(db.Enabled ~= false)
    return yOffset
end)
