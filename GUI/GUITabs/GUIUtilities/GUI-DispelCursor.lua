-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-DispelCursor.lua                                    ║
-- ║  GUI: Dispel CD on Cursor                                ║
-- ║  Purpose: Configuration panel for the DispelCursor       ║
-- ║  module.                                                 ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local ipairs = ipairs
local table_insert = table.insert

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("DispelCursor", true)
    end
    return nil
end

GUIFrame:RegisterContent("DispelCursor", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.DispelCursor
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return yOffset + errorCard:GetContentHeight() + Theme.paddingMedium
    end

    local DC = GetModule()
    local allWidgets = {}

    local function ApplySettings()
        if DC then DC:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not DC then return end
        DC.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("DispelCursor")
        else
            KitnEssentials:DisableModule("DispelCursor")
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

    ---------------------------------------------------------------------------------
    -- Card 1: Enable
    ---------------------------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Dispel on Cursor", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Dispel on Cursor", db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            UpdateAllWidgetStates()
        end,
        true, "Dispel on Cursor", "On", "Off"
    )
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, 36)

    local noteHeight = 50
    local noteRow = GUIFrame:CreateRow(card1.content, noteHeight)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Shows your dispel cooldown timer following your cursor.\n" .. KE:ColorTextByTheme("-") .. " Auto-detects your class dispel spell.",
        noteHeight, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, noteHeight)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 2: Display Settings
    ---------------------------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Display Settings", yOffset)
    table_insert(allWidgets, card2)

    local row2a = GUIFrame:CreateRow(card2.content, 40)
    local fontSizeSlider = GUIFrame:CreateSlider(row2a, "Font Size", 8, 36, 1, db.FontSize or 18, 60,
        function(val)
            db.FontSize = val
            ApplySettings()
        end)
    row2a:AddWidget(fontSizeSlider, 0.5)
    table_insert(allWidgets, fontSizeSlider)

    local colorPicker = GUIFrame:CreateColorPicker(row2a, "Text Color", db.TextColor or { 1, 1, 1, 1 },
        function(r, g, b, a)
            db.TextColor = { r, g, b, a }
            ApplySettings()
        end)
    row2a:AddWidget(colorPicker, 0.5)
    table_insert(allWidgets, colorPicker)
    card2:AddRow(row2a, 40)

    local row2b = GUIFrame:CreateRow(card2.content, 40)
    local xSlider = GUIFrame:CreateSlider(row2b, "X Offset from Cursor", -50, 50, 1, db.XOffset or 10, 60,
        function(val)
            db.XOffset = val
        end)
    row2b:AddWidget(xSlider, 0.5)
    table_insert(allWidgets, xSlider)

    local ySlider = GUIFrame:CreateSlider(row2b, "Y Offset from Cursor", -50, 50, 1, db.YOffset or 10, 60,
        function(val)
            db.YOffset = val
        end)
    row2b:AddWidget(ySlider, 0.5)
    table_insert(allWidgets, ySlider)
    card2:AddRow(row2b, 40)

    yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

    UpdateAllWidgetStates()
    yOffset = yOffset - (Theme.paddingSmall * 3)
    return yOffset
end)
