-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-CombatCross.lua                                     ║
-- ║  GUI: Player Crosshair                                   ║
-- ║  Purpose: Configuration panel for the CombatCross module.║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local table_insert = table.insert

GUIFrame:RegisterContent("CombatCross", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.CombatCross
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return yOffset + errorCard:GetContentHeight() + Theme.paddingMedium
    end

    local CC = KitnEssentials and KitnEssentials:GetModule("CombatCross", true)

    local allWidgets = {}
    local colorModeWidgets = {}
    local rangeColorWidgets = {}

    local function ApplySettings()
        if CC then CC:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not CC then return end
        CC.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("CombatCross")
        else
            KitnEssentials:DisableModule("CombatCross")
        end
    end

    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false
        local isCustomColor = (db.ColorMode or "custom") == "custom"
        local isRangeEnabled = db.RangeColorMeleeEnabled == true or db.RangeColorRangedEnabled == true

        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then
                widget:SetEnabled(mainEnabled)
            end
        end

        if mainEnabled then
            for _, widget in ipairs(colorModeWidgets) do
                if widget.SetEnabled then
                    widget:SetEnabled(isCustomColor)
                end
            end
            for _, widget in ipairs(rangeColorWidgets) do
                if widget.SetEnabled then
                    widget:SetEnabled(isRangeEnabled)
                end
            end
        end
    end

    ---------------------------------------------------------------------------------
    -- Card 1: Combat Cross (Enable + Thickness + Outline)
    ---------------------------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Combat Cross", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Combat Cross", db.Enabled ~= false, function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            UpdateAllWidgetStates()
        end,
        true,
        "Combat Cross",
        "On",
        "Off"
    )
    row1:AddWidget(enableCheck, 0.5)
    card1:AddRow(row1, 36)

    -- Info note
    local noteRow = GUIFrame:CreateRow(card1.content, 40)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " This is a static crosshair overlay and will not adjust with camera panning.",
        40, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, 40)

    -- Separator
    local row1sep = GUIFrame:CreateRow(card1.content, 8)
    local sep1 = GUIFrame:CreateSeparator(row1sep)
    row1sep:AddWidget(sep1, 1)
    table_insert(allWidgets, sep1)
    card1:AddRow(row1sep, 8)

    local row1b = GUIFrame:CreateRow(card1.content, 36)
    local thicknessSlider = GUIFrame:CreateSlider(row1b, "Size", 8, 72, 1, db.Thickness or 22, 60,
        function(val)
            db.Thickness = val
            ApplySettings()
        end)
    row1b:AddWidget(thicknessSlider, 0.5)
    table_insert(allWidgets, thicknessSlider)

    local outlineCheck = GUIFrame:CreateCheckbox(row1b, "Font Outline", db.Outline ~= false,
        function(checked)
            db.Outline = checked
            ApplySettings()
        end)
    row1b:AddWidget(outlineCheck, 0.5)
    table_insert(allWidgets, outlineCheck)
    card1:AddRow(row1b, 36)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 2: Position Settings
    ---------------------------------------------------------------------------------
    local card2, newOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            anchorFrameType = "anchorFrameType",
            anchorFrameFrame = "ParentFrame",
            selfPoint = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset = "XOffset",
            yOffset = "YOffset",
            strata = "Strata",
        },
        showAnchorFrameType = true,
        showStrata = true,
        onChangeCallback = ApplySettings,
    })

    if card2.positionWidgets then
        for _, widget in ipairs(card2.positionWidgets) do
            table_insert(allWidgets, widget)
        end
    end
    table_insert(allWidgets, card2)
    yOffset = newOffset

    ---------------------------------------------------------------------------------
    -- Card 3: Colors
    ---------------------------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    table_insert(allWidgets, card3)

    local row3 = GUIFrame:CreateRow(card3.content, 36)
    local colorModeDropdown = GUIFrame:CreateDropdown(row3, "Color Mode", KE.ColorModeOptions,
        db.ColorMode or "custom", 70,
        function(key)
            db.ColorMode = key
            ApplySettings()
            UpdateAllWidgetStates()
        end)
    row3:AddWidget(colorModeDropdown, 0.5)
    table_insert(allWidgets, colorModeDropdown)

    local colorPicker = GUIFrame:CreateColorPicker(row3, "Custom Color", db.Color or { 0, 1, 0.169, 1 },
        function(r, g, b, a)
            db.Color = { r, g, b, a }
            ApplySettings()
        end)
    row3:AddWidget(colorPicker, 0.5)
    table_insert(allWidgets, colorPicker)
    table_insert(colorModeWidgets, colorPicker)
    card3:AddRow(row3, 36)

    yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 4: Range Warning
    ---------------------------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Range Warning", yOffset)

    local row4a = GUIFrame:CreateRow(card4.content, 40)
    local meleeRangeCheck = GUIFrame:CreateCheckbox(row4a, "Enable for melee specs", db.RangeColorMeleeEnabled == true,
        function(checked)
            db.RangeColorMeleeEnabled = checked
            ApplySettings()
            UpdateAllWidgetStates()
        end)
    row4a:AddWidget(meleeRangeCheck, 0.5)

    local rangedRangeCheck = GUIFrame:CreateCheckbox(row4a, "Enable for ranged specs", db.RangeColorRangedEnabled == true,
        function(checked)
            db.RangeColorRangedEnabled = checked
            ApplySettings()
            UpdateAllWidgetStates()
        end)
    row4a:AddWidget(rangedRangeCheck, 0.5)
    card4:AddRow(row4a, 40)

    local row4c = GUIFrame:CreateRow(card4.content, 36)
    local outOfRangeColorPicker = GUIFrame:CreateColorPicker(row4c, "Out of Range Color",
        db.OutOfRangeColor or { 1, 0, 0, 1 },
        function(r, g, b, a)
            db.OutOfRangeColor = { r, g, b, a }
            if CC then CC.lastInRange = nil end
        end)
    row4c:AddWidget(outOfRangeColorPicker, 1)
    table_insert(rangeColorWidgets, outOfRangeColorPicker)
    card4:AddRow(row4c, 36)

    yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

    -- Apply initial widget states
    UpdateAllWidgetStates()
    yOffset = yOffset - (Theme.paddingSmall * 3)
    return yOffset
end)
