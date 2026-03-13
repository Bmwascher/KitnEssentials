-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)
local table_insert = table.insert

GUIFrame:RegisterContent("CombatTexts", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.CombatTexts
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return yOffset + errorCard:GetContentHeight() + Theme.paddingMedium
    end

    local allWidgets = {}
    local bgWidgets = {}
    local enterWidgets = {}
    local exitWidgets = {}
    local durabilityWidgets = {}

    local function ApplySettings()
        if KitnEssentials then
            local mod = KitnEssentials:GetModule("CombatTexts", true)
            if mod and mod.ApplySettings then mod:ApplySettings() end
        end
    end

    local function ApplyModuleState(enabled)
        if not KitnEssentials then return end
        local mod = KitnEssentials:GetModule("CombatTexts", true)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("CombatTexts")
        else
            KitnEssentials:DisableModule("CombatTexts")
        end
    end

    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false
        local bgEnabled = db.Backdrop and db.Backdrop.Enabled == true
        local enterEnabled = db.EnterEnabled ~= false
        local exitEnabled = db.ExitEnabled ~= false
        local durabilityEnabled = db.DurabilityEnabled ~= false

        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then
                widget:SetEnabled(mainEnabled)
            end
        end

        if mainEnabled then
            for _, widget in ipairs(bgWidgets) do
                if widget.SetEnabled then
                    widget:SetEnabled(bgEnabled)
                end
            end
            for _, widget in ipairs(enterWidgets) do
                if widget.SetEnabled then
                    widget:SetEnabled(enterEnabled)
                end
            end
            for _, widget in ipairs(exitWidgets) do
                if widget.SetEnabled then
                    widget:SetEnabled(exitEnabled)
                end
            end
            for _, widget in ipairs(durabilityWidgets) do
                if widget.SetEnabled then
                    widget:SetEnabled(durabilityEnabled)
                end
            end
        end
    end

    ----------------------------------------------------------------
    -- Card 1: Combat Texts (Enable + Duration + Spacing)
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Combat Texts", yOffset)

    local row1a = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1a, "Enable Combat Texts", db.Enabled ~= false, function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            UpdateAllWidgetStates()
        end,
        true,
        "Combat Texts",
        "On",
        "Off"
    )
    row1a:AddWidget(enableCheck, 0.5)
    card1:AddRow(row1a, 36)

    -- Separator
    local row1sep = GUIFrame:CreateRow(card1.content, 8)
    local sep1 = GUIFrame:CreateSeparator(row1sep)
    row1sep:AddWidget(sep1, 1)
    table_insert(allWidgets, sep1)
    card1:AddRow(row1sep, 8)

    local row1b = GUIFrame:CreateRow(card1.content, 40)
    local durationSlider = GUIFrame:CreateSlider(row1b, "Fade Duration", 0.5, 5.0, 0.1, db.Duration or 1.5, 90,
        function(val)
            db.Duration = val
            ApplySettings()
        end)
    row1b:AddWidget(durationSlider, 0.5)
    table_insert(allWidgets, durationSlider)

    local spacingSlider = GUIFrame:CreateSlider(row1b, "Message Spacing", 0, 20, 1, db.Spacing or 4, 100,
        function(val)
            db.Spacing = val
            ApplySettings()
        end)
    row1b:AddWidget(spacingSlider, 0.5)
    table_insert(allWidgets, spacingSlider)
    card1:AddRow(row1b, 40)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 2: Position Settings
    ----------------------------------------------------------------
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

    ----------------------------------------------------------------
    -- Card 3: Font Settings
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Font Settings", yOffset)
    table_insert(allWidgets, card3)

    local fontList = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do fontList[name] = name end
    else
        fontList["Friz Quadrata TT"] = "Friz Quadrata TT"
    end

    local row3a = GUIFrame:CreateRow(card3.content, 40)
    local fontDropdown = GUIFrame:CreateDropdown(row3a, "Font", fontList, db.FontFace or "Expressway", 30,
        function(key)
            db.FontFace = key
            ApplySettings()
        end)
    row3a:AddWidget(fontDropdown, 0.5)
    table_insert(allWidgets, fontDropdown)

    local outlineList = {
        { key = "NONE",         text = "None" },
        { key = "OUTLINE",      text = "Outline" },
        { key = "THICKOUTLINE", text = "Thick" },
        { key = "SOFTOUTLINE",  text = "Soft" },
    }
    local outlineDropdown = GUIFrame:CreateDropdown(row3a, "Outline", outlineList, db.FontOutline or "SOFTOUTLINE", 45,
        function(key)
            db.FontOutline = key
            ApplySettings()
        end)
    row3a:AddWidget(outlineDropdown, 0.5)
    table_insert(allWidgets, outlineDropdown)
    card3:AddRow(row3a, 40)

    local row3b = GUIFrame:CreateRow(card3.content, 37)
    local fontSizeSlider = GUIFrame:CreateSlider(row3b, "Font Size", 8, 72, 1, db.FontSize or 16, 60,
        function(val)
            db.FontSize = val
            ApplySettings()
        end)
    row3b:AddWidget(fontSizeSlider, 1)
    table_insert(allWidgets, fontSizeSlider)
    card3:AddRow(row3b, 37)

    yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 4: Enter Combat Message
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Enter Combat Message", yOffset)
    table_insert(allWidgets, card4)

    local row4a = GUIFrame:CreateRow(card4.content, 38)
    local enterEnableCheck = GUIFrame:CreateCheckbox(row4a, "Enabled", db.EnterEnabled ~= false,
        function(checked)
            db.EnterEnabled = checked
            ApplySettings()
            UpdateAllWidgetStates()
        end)
    row4a:AddWidget(enterEnableCheck, 0.2)
    table_insert(allWidgets, enterEnableCheck)

    local enterColorPicker = GUIFrame:CreateColorPicker(row4a, "Color",
        db.EnterColor or { 1, 0.1, 0.1, 1 },
        function(r, g, b, a)
            db.EnterColor = { r, g, b, a }
            ApplySettings()
        end)
    row4a:AddWidget(enterColorPicker, 0.3)
    table_insert(allWidgets, enterColorPicker)
    table_insert(enterWidgets, enterColorPicker)

    local enterTextInput = GUIFrame:CreateEditBox(row4a, "Text", db.EnterCombatText or "+ Combat", function(val)
        db.EnterCombatText = val
        ApplySettings()
    end)
    row4a:AddWidget(enterTextInput, 0.5)
    table_insert(allWidgets, enterTextInput)
    table_insert(enterWidgets, enterTextInput)
    card4:AddRow(row4a, 38)

    yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 5: Exit Combat Message
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Exit Combat Message", yOffset)
    table_insert(allWidgets, card5)

    local row5a = GUIFrame:CreateRow(card5.content, 38)
    local exitEnableCheck = GUIFrame:CreateCheckbox(row5a, "Enabled", db.ExitEnabled ~= false,
        function(checked)
            db.ExitEnabled = checked
            ApplySettings()
            UpdateAllWidgetStates()
        end)
    row5a:AddWidget(exitEnableCheck, 0.2)
    table_insert(allWidgets, exitEnableCheck)

    local exitColorPicker = GUIFrame:CreateColorPicker(row5a, "Color",
        db.ExitColor or { 0.1, 1, 0.1, 1 },
        function(r, g, b, a)
            db.ExitColor = { r, g, b, a }
            ApplySettings()
        end)
    row5a:AddWidget(exitColorPicker, 0.3)
    table_insert(allWidgets, exitColorPicker)
    table_insert(exitWidgets, exitColorPicker)

    local exitTextInput = GUIFrame:CreateEditBox(row5a, "Text", db.ExitCombatText or "- Combat", function(val)
        db.ExitCombatText = val
        ApplySettings()
    end)
    row5a:AddWidget(exitTextInput, 0.5)
    table_insert(allWidgets, exitTextInput)
    table_insert(exitWidgets, exitTextInput)
    card5:AddRow(row5a, 38)

    yOffset = yOffset + card5:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 6: Low Durability Warning
    ----------------------------------------------------------------
    local card6 = GUIFrame:CreateCard(scrollChild, "Low Durability Warning", yOffset)
    table_insert(allWidgets, card6)

    local row6a = GUIFrame:CreateRow(card6.content, 38)
    local durabilityEnableCheck = GUIFrame:CreateCheckbox(row6a, "Enabled", db.DurabilityEnabled ~= false,
        function(checked)
            db.DurabilityEnabled = checked
            ApplySettings()
            UpdateAllWidgetStates()
        end)
    row6a:AddWidget(durabilityEnableCheck, 0.2)
    table_insert(allWidgets, durabilityEnableCheck)

    local durabilityColorPicker = GUIFrame:CreateColorPicker(row6a, "Color",
        db.DurabilityColor or { 1, 0.3, 0.3, 1 },
        function(r, g, b, a)
            db.DurabilityColor = { r, g, b, a }
            ApplySettings()
        end)
    row6a:AddWidget(durabilityColorPicker, 0.3)
    table_insert(allWidgets, durabilityColorPicker)
    table_insert(durabilityWidgets, durabilityColorPicker)

    local durabilityTextInput = GUIFrame:CreateEditBox(row6a, "Text", db.DurabilityText or "LOW DURABILITY", function(val)
        db.DurabilityText = val
        ApplySettings()
    end)
    row6a:AddWidget(durabilityTextInput, 0.5)
    table_insert(allWidgets, durabilityTextInput)
    table_insert(durabilityWidgets, durabilityTextInput)
    card6:AddRow(row6a, 38)

    -- Separator
    local row6sep = GUIFrame:CreateRow(card6.content, 8)
    local sep6 = GUIFrame:CreateSeparator(row6sep)
    row6sep:AddWidget(sep6, 1)
    table_insert(allWidgets, sep6)
    card6:AddRow(row6sep, 8)

    -- Threshold slider
    local row6b = GUIFrame:CreateRow(card6.content, 40)
    local thresholdSlider = GUIFrame:CreateSlider(row6b, "Durability Threshold (%)", 5, 50, 1,
        db.DurabilityThreshold or 25, nil,
        function(val)
            db.DurabilityThreshold = val
            ApplySettings()
        end)
    row6b:AddWidget(thresholdSlider, 1)
    table_insert(allWidgets, thresholdSlider)
    table_insert(durabilityWidgets, thresholdSlider)
    card6:AddRow(row6b, 40)

    yOffset = yOffset + card6:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 7: Backdrop
    ----------------------------------------------------------------
    local card7 = GUIFrame:CreateCard(scrollChild, "Backdrop", yOffset)
    table_insert(allWidgets, card7)
    db.Backdrop = db.Backdrop or {}

    local row7a = GUIFrame:CreateRow(card7.content, 39)
    local backdropCheck = GUIFrame:CreateCheckbox(row7a, "Enable Backdrop", db.Backdrop.Enabled ~= false,
        function(checked)
            db.Backdrop.Enabled = checked
            ApplySettings()
            UpdateAllWidgetStates()
        end)
    row7a:AddWidget(backdropCheck, 1)
    table_insert(allWidgets, backdropCheck)
    card7:AddRow(row7a, 39)

    local row7b = GUIFrame:CreateRow(card7.content, 39)
    local bgWidth = GUIFrame:CreateSlider(row7b, "Backdrop Width", 1, 600, 1, db.Backdrop.bgWidth or 100, 0,
        function(val)
            db.Backdrop.bgWidth = val
            ApplySettings()
        end)
    row7b:AddWidget(bgWidth, 0.4)
    table_insert(allWidgets, bgWidth)
    table_insert(bgWidgets, bgWidth)

    local bgHeight = GUIFrame:CreateSlider(row7b, "Backdrop Height", 1, 600, 1, db.Backdrop.bgHeight or 40, 0,
        function(val)
            db.Backdrop.bgHeight = val
            ApplySettings()
        end)
    row7b:AddWidget(bgHeight, 0.39)
    table_insert(allWidgets, bgHeight)
    table_insert(bgWidgets, bgHeight)

    local bgColor = GUIFrame:CreateColorPicker(row7b, "Backdrop Color", db.Backdrop.Color or { 0, 0, 0, 0.6 },
        function(r, g, b, a)
            db.Backdrop.Color = { r, g, b, a }
            ApplySettings()
        end)
    row7b:AddWidget(bgColor, 0.21)
    table_insert(allWidgets, bgColor)
    table_insert(bgWidgets, bgColor)
    card7:AddRow(row7b, 39)

    -- Separator
    local row7sep = GUIFrame:CreateRow(card7.content, 8)
    local sepBg = GUIFrame:CreateSeparator(row7sep)
    row7sep:AddWidget(sepBg, 1)
    table_insert(allWidgets, sepBg)
    table_insert(bgWidgets, sepBg)
    card7:AddRow(row7sep, 8)

    local row7c = GUIFrame:CreateRow(card7.content, 39)
    local borderSize = GUIFrame:CreateSlider(row7c, "Border Size", 1, 10, 1, db.Backdrop.BorderSize or 1, 0,
        function(val)
            db.Backdrop.BorderSize = val
            ApplySettings()
        end)
    row7c:AddWidget(borderSize, 0.79)
    table_insert(allWidgets, borderSize)
    table_insert(bgWidgets, borderSize)

    local borderColor = GUIFrame:CreateColorPicker(row7c, "Border Color",
        db.Backdrop.BorderColor or { 0, 0, 0, 1 },
        function(r, g, b, a)
            db.Backdrop.BorderColor = { r, g, b, a }
            ApplySettings()
        end)
    row7c:AddWidget(borderColor, 0.21)
    table_insert(allWidgets, borderColor)
    table_insert(bgWidgets, borderColor)
    card7:AddRow(row7c, 39)

    yOffset = yOffset + card7:GetContentHeight() + Theme.paddingSmall

    -- Apply initial widget states
    UpdateAllWidgetStates()
    yOffset = yOffset - (Theme.paddingSmall * 3)
    return yOffset
end)
