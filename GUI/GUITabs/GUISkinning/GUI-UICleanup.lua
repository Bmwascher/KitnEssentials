-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

-- Localization Setup
local table_insert = table.insert
local ipairs = ipairs

-- Helper to get UICleanup module
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

    -- Track widgets for enable/disable logic
    local allWidgets = {}

    local function ApplyUICleanupState(enabled)
        if not UIC then return end
        UIC.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("SkinUICleanup")
        else
            KitnEssentials:DisableModule("SkinUICleanup")
        end
    end

    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false
        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then
                widget:SetEnabled(mainEnabled)
            end
        end
    end

    ----------------------------------------------------------------
    -- Card 1: UICleanup Toggle
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "General UI Cleanup", yOffset)

    -- Enable Checkbox
    local row1 = GUIFrame:CreateRow(card1.content, 40)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable UI Cleanup", db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplyUICleanupState(checked)
            UpdateAllWidgetStates()
            if not checked then
                KE:CreateReloadPrompt("Enabling Blizzard UI elements requires a reload to take full effect.")
            end
        end,
        true,
        "UI Cleanup",
        "On",
        "Off"
    )
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, 40)

    -- Separator
    local row1sep = GUIFrame:CreateRow(card1.content, 8)
    local sepWidget = GUIFrame:CreateSeparator(row1sep)
    row1sep:AddWidget(sepWidget, 1)
    table_insert(allWidgets, sepWidget)
    card1:AddRow(row1sep, 8)

    -- Info text listing hidden elements
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
    local rowHeight = 165
    local row2 = GUIFrame:CreateRow(card1.content, rowHeight)
    local textWidget = GUIFrame:CreateText(
        row2,
        KE:ColorTextByTheme("Hides The Following Frames"),
        function()
            return hiddenNames
        end,
        rowHeight,
        "hide"
    )
    row2:AddWidget(textWidget, 1)
    table_insert(allWidgets, textWidget)
    card1:AddRow(row2, rowHeight)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    -- Apply initial widget states
    UpdateAllWidgetStates()
    yOffset = yOffset - Theme.paddingSmall
    return yOffset
end)
