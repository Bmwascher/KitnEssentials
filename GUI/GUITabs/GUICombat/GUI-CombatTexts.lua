-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-CombatTexts.lua                                     ║
-- ║  GUI: Combat Texts                                       ║
-- ║  Purpose: Configuration panel for the CombatTexts module.║
-- ╚══════════════════════════════════════════════════════════╝

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
    local combatMsgWidgets = {}
    local noTargetWidgets = {}
    local durabilityWidgets = {}
    local interruptWidgets = {}

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
        local combatEnabled = db.EnterEnabled ~= false
        local noTargetEnabled = db.NoTargetEnabled == true
        local durabilityEnabled = db.DurabilityEnabled ~= false
        local interruptEnabled = db.InterruptEnabled ~= false

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
            for _, widget in ipairs(combatMsgWidgets) do
                if widget.SetEnabled then
                    widget:SetEnabled(combatEnabled)
                end
            end
            for _, widget in ipairs(noTargetWidgets) do
                if widget.SetEnabled then
                    widget:SetEnabled(noTargetEnabled)
                end
            end
            for _, widget in ipairs(durabilityWidgets) do
                if widget.SetEnabled then
                    widget:SetEnabled(durabilityEnabled)
                end
            end
            for _, widget in ipairs(interruptWidgets) do
                if widget.SetEnabled then
                    widget:SetEnabled(interruptEnabled)
                end
            end
        end
    end

    ---------------------------------------------------------------------------------
    -- Card 1: Combat Texts (Enable + Spacing)
    ---------------------------------------------------------------------------------
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
    local spacingSlider = GUIFrame:CreateSlider(row1b, "Message Spacing", 0, 20, 1, db.Spacing or 4, 100,
        function(val)
            db.Spacing = val
            ApplySettings()
        end)
    row1b:AddWidget(spacingSlider, 1)
    table_insert(allWidgets, spacingSlider)
    card1:AddRow(row1b, 40)

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
        showPixelSnap = true,
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
    -- Card 3: Font Settings
    ---------------------------------------------------------------------------------
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

    ---------------------------------------------------------------------------------
    -- Card 4: Combat Messages (combined Enter + Exit)
    ---------------------------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Combat Messages", yOffset)
    table_insert(allWidgets, card4)

    local row4en = GUIFrame:CreateRow(card4.content, 38)
    local combatEnableCheck = GUIFrame:CreateCheckbox(row4en, "Enabled", db.EnterEnabled ~= false,
        function(checked)
            db.EnterEnabled = checked
            db.ExitEnabled = checked
            ApplySettings()
            UpdateAllWidgetStates()
        end)
    row4en:AddWidget(combatEnableCheck, 1)
    table_insert(allWidgets, combatEnableCheck)
    card4:AddRow(row4en, 38)

    -- Separator
    local row4sep1 = GUIFrame:CreateRow(card4.content, 8)
    local sep4a = GUIFrame:CreateSeparator(row4sep1)
    row4sep1:AddWidget(sep4a, 1)
    table_insert(allWidgets, sep4a)
    table_insert(combatMsgWidgets, sep4a)
    card4:AddRow(row4sep1, 8)

    -- Enter Combat row
    local row4enter = GUIFrame:CreateRow(card4.content, 38)
    local enterColorPicker = GUIFrame:CreateColorPicker(row4enter, "Enter Color",
        db.EnterColor or { 1, 0.1, 0.1, 1 },
        function(r, g, b, a)
            db.EnterColor = { r, g, b, a }
            ApplySettings()
        end)
    row4enter:AddWidget(enterColorPicker, 0.3)
    table_insert(allWidgets, enterColorPicker)
    table_insert(combatMsgWidgets, enterColorPicker)

    local enterTextInput = GUIFrame:CreateEditBox(row4enter, "Enter Text", db.EnterCombatText or "+ Combat", function(val)
        db.EnterCombatText = val
        ApplySettings()
    end)
    row4enter:AddWidget(enterTextInput, 0.7)
    table_insert(allWidgets, enterTextInput)
    table_insert(combatMsgWidgets, enterTextInput)
    card4:AddRow(row4enter, 38)

    -- Exit Combat row
    local row4exit = GUIFrame:CreateRow(card4.content, 38)
    local exitColorPicker = GUIFrame:CreateColorPicker(row4exit, "Exit Color",
        db.ExitColor or { 0.1, 1, 0.1, 1 },
        function(r, g, b, a)
            db.ExitColor = { r, g, b, a }
            ApplySettings()
        end)
    row4exit:AddWidget(exitColorPicker, 0.3)
    table_insert(allWidgets, exitColorPicker)
    table_insert(combatMsgWidgets, exitColorPicker)

    local exitTextInput = GUIFrame:CreateEditBox(row4exit, "Exit Text", db.ExitCombatText or "- Combat", function(val)
        db.ExitCombatText = val
        ApplySettings()
    end)
    row4exit:AddWidget(exitTextInput, 0.7)
    table_insert(allWidgets, exitTextInput)
    table_insert(combatMsgWidgets, exitTextInput)
    card4:AddRow(row4exit, 38)

    -- Separator
    local row4sep2 = GUIFrame:CreateRow(card4.content, 8)
    local sep4b = GUIFrame:CreateSeparator(row4sep2)
    row4sep2:AddWidget(sep4b, 1)
    table_insert(allWidgets, sep4b)
    table_insert(combatMsgWidgets, sep4b)
    card4:AddRow(row4sep2, 8)

    -- Fade Duration
    local row4dur = GUIFrame:CreateRow(card4.content, 40)
    local combatDurationSlider = GUIFrame:CreateSlider(row4dur, "Fade Duration", 0.5, 5.0, 0.1,
        db.CombatDuration or 1.5, 90,
        function(val)
            db.CombatDuration = val
            ApplySettings()
        end)
    row4dur:AddWidget(combatDurationSlider, 1)
    table_insert(allWidgets, combatDurationSlider)
    table_insert(combatMsgWidgets, combatDurationSlider)
    card4:AddRow(row4dur, 40)

    yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 5: No Target Warning
    ---------------------------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "No Target Warning", yOffset)
    table_insert(allWidgets, card5)

    local row5nt = GUIFrame:CreateRow(card5.content, 38)
    local noTargetEnableCheck = GUIFrame:CreateCheckbox(row5nt, "Enabled", db.NoTargetEnabled == true,
        function(checked)
            db.NoTargetEnabled = checked
            ApplySettings()
            UpdateAllWidgetStates()
        end)
    row5nt:AddWidget(noTargetEnableCheck, 0.2)
    table_insert(allWidgets, noTargetEnableCheck)

    local noTargetColorPicker = GUIFrame:CreateColorPicker(row5nt, "Color",
        db.NoTargetColor or { 1, 0.8, 0, 1 },
        function(r, g, b, a)
            db.NoTargetColor = { r, g, b, a }
            ApplySettings()
        end)
    row5nt:AddWidget(noTargetColorPicker, 0.3)
    table_insert(allWidgets, noTargetColorPicker)
    table_insert(noTargetWidgets, noTargetColorPicker)

    local noTargetTextInput = GUIFrame:CreateEditBox(row5nt, "Text", db.NoTargetText or "NO TARGET", function(val)
        db.NoTargetText = val
        ApplySettings()
    end)
    row5nt:AddWidget(noTargetTextInput, 0.5)
    table_insert(allWidgets, noTargetTextInput)
    table_insert(noTargetWidgets, noTargetTextInput)
    card5:AddRow(row5nt, 38)

    card5:AddLabel("|cff888888Shows persistent warning when in combat with no target selected|r")

    yOffset = yOffset + card5:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 6: Interrupt Text
    ---------------------------------------------------------------------------------
    local card6 = GUIFrame:CreateCard(scrollChild, "Interrupt Text", yOffset)
    table_insert(allWidgets, card6)

    local row6a = GUIFrame:CreateRow(card6.content, 38)
    local intEnableCheck = GUIFrame:CreateCheckbox(row6a, "Enabled", db.InterruptEnabled ~= false,
        function(checked)
            db.InterruptEnabled = checked
            ApplySettings()
            UpdateAllWidgetStates()
        end)
    row6a:AddWidget(intEnableCheck, 0.2)
    table_insert(allWidgets, intEnableCheck)

    local intColorPicker = GUIFrame:CreateColorPicker(row6a, "Color",
        db.InterruptColor or { 1, 1, 1, 1 },
        function(r, g, b, a)
            db.InterruptColor = { r, g, b, a }
            ApplySettings()
        end)
    row6a:AddWidget(intColorPicker, 0.3)
    table_insert(allWidgets, intColorPicker)
    table_insert(interruptWidgets, intColorPicker)

    local intTextInput = GUIFrame:CreateEditBox(row6a, "Text", db.InterruptText or "Interrupted", function(val)
        db.InterruptText = val
        ApplySettings()
    end)
    row6a:AddWidget(intTextInput, 0.5)
    table_insert(allWidgets, intTextInput)
    table_insert(interruptWidgets, intTextInput)
    card6:AddRow(row6a, 38)

    -- Separator
    local row6sep = GUIFrame:CreateRow(card6.content, 8)
    local sep6 = GUIFrame:CreateSeparator(row6sep)
    row6sep:AddWidget(sep6, 1)
    table_insert(allWidgets, sep6)
    table_insert(interruptWidgets, sep6)
    card6:AddRow(row6sep, 8)

    local row6b = GUIFrame:CreateRow(card6.content, 40)
    local intDurationSlider = GUIFrame:CreateSlider(row6b, "Fade Duration", 0.5, 8.0, 0.1,
        db.InterruptDuration or 3.0, 90,
        function(val)
            db.InterruptDuration = val
            ApplySettings()
        end)
    row6b:AddWidget(intDurationSlider, 1)
    table_insert(allWidgets, intDurationSlider)
    table_insert(interruptWidgets, intDurationSlider)
    card6:AddRow(row6b, 40)

    card6:AddLabel("|cff888888Displays: [text] [spell icon] [spell name] on successful interrupt|r")

    yOffset = yOffset + card6:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 7: Low Durability Warning
    ---------------------------------------------------------------------------------
    local card7 = GUIFrame:CreateCard(scrollChild, "Low Durability Warning", yOffset)
    table_insert(allWidgets, card7)

    local row7a = GUIFrame:CreateRow(card7.content, 38)
    local durabilityEnableCheck = GUIFrame:CreateCheckbox(row7a, "Enabled", db.DurabilityEnabled ~= false,
        function(checked)
            db.DurabilityEnabled = checked
            ApplySettings()
            UpdateAllWidgetStates()
        end)
    row7a:AddWidget(durabilityEnableCheck, 0.2)
    table_insert(allWidgets, durabilityEnableCheck)

    local durabilityColorPicker = GUIFrame:CreateColorPicker(row7a, "Color",
        db.DurabilityColor or { 1, 0.3, 0.3, 1 },
        function(r, g, b, a)
            db.DurabilityColor = { r, g, b, a }
            ApplySettings()
        end)
    row7a:AddWidget(durabilityColorPicker, 0.3)
    table_insert(allWidgets, durabilityColorPicker)
    table_insert(durabilityWidgets, durabilityColorPicker)

    local durabilityTextInput = GUIFrame:CreateEditBox(row7a, "Text", db.DurabilityText or "LOW DURABILITY", function(val)
        db.DurabilityText = val
        ApplySettings()
    end)
    row7a:AddWidget(durabilityTextInput, 0.5)
    table_insert(allWidgets, durabilityTextInput)
    table_insert(durabilityWidgets, durabilityTextInput)
    card7:AddRow(row7a, 38)

    -- Separator
    local row7sep = GUIFrame:CreateRow(card7.content, 8)
    local sep7 = GUIFrame:CreateSeparator(row7sep)
    row7sep:AddWidget(sep7, 1)
    table_insert(allWidgets, sep7)
    table_insert(durabilityWidgets, sep7)
    card7:AddRow(row7sep, 8)

    -- Threshold slider
    local row7b = GUIFrame:CreateRow(card7.content, 40)
    local thresholdSlider = GUIFrame:CreateSlider(row7b, "Durability Threshold (%)", 5, 50, 1,
        db.DurabilityThreshold or 25, nil,
        function(val)
            db.DurabilityThreshold = val
            ApplySettings()
        end)
    row7b:AddWidget(thresholdSlider, 1)
    table_insert(allWidgets, thresholdSlider)
    table_insert(durabilityWidgets, thresholdSlider)
    card7:AddRow(row7b, 40)

    yOffset = yOffset + card7:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 8: Backdrop
    ---------------------------------------------------------------------------------
    local card8 = GUIFrame:CreateCard(scrollChild, "Backdrop", yOffset)
    table_insert(allWidgets, card8)
    db.Backdrop = db.Backdrop or {}

    local row8a = GUIFrame:CreateRow(card8.content, 39)
    local backdropCheck = GUIFrame:CreateCheckbox(row8a, "Enable Backdrop", db.Backdrop.Enabled ~= false,
        function(checked)
            db.Backdrop.Enabled = checked
            ApplySettings()
            UpdateAllWidgetStates()
        end)
    row8a:AddWidget(backdropCheck, 1)
    table_insert(allWidgets, backdropCheck)
    card8:AddRow(row8a, 39)

    local row8b = GUIFrame:CreateRow(card8.content, 39)
    local bgWidth = GUIFrame:CreateSlider(row8b, "Backdrop Width", 1, 600, 1, db.Backdrop.bgWidth or 100, 0,
        function(val)
            db.Backdrop.bgWidth = val
            ApplySettings()
        end)
    row8b:AddWidget(bgWidth, 0.4)
    table_insert(allWidgets, bgWidth)
    table_insert(bgWidgets, bgWidth)

    local bgHeight = GUIFrame:CreateSlider(row8b, "Backdrop Height", 1, 600, 1, db.Backdrop.bgHeight or 40, 0,
        function(val)
            db.Backdrop.bgHeight = val
            ApplySettings()
        end)
    row8b:AddWidget(bgHeight, 0.39)
    table_insert(allWidgets, bgHeight)
    table_insert(bgWidgets, bgHeight)

    local bgColor = GUIFrame:CreateColorPicker(row8b, "Backdrop Color", db.Backdrop.Color or { 0, 0, 0, 0.6 },
        function(r, g, b, a)
            db.Backdrop.Color = { r, g, b, a }
            ApplySettings()
        end)
    row8b:AddWidget(bgColor, 0.21)
    table_insert(allWidgets, bgColor)
    table_insert(bgWidgets, bgColor)
    card8:AddRow(row8b, 39)

    -- Separator
    local row8sep = GUIFrame:CreateRow(card8.content, 8)
    local sepBg = GUIFrame:CreateSeparator(row8sep)
    row8sep:AddWidget(sepBg, 1)
    table_insert(allWidgets, sepBg)
    table_insert(bgWidgets, sepBg)
    card8:AddRow(row8sep, 8)

    local row8c = GUIFrame:CreateRow(card8.content, 39)
    local borderSize = GUIFrame:CreateSlider(row8c, "Border Size", 1, 10, 1, db.Backdrop.BorderSize or 1, 0,
        function(val)
            db.Backdrop.BorderSize = val
            ApplySettings()
        end)
    row8c:AddWidget(borderSize, 0.79)
    table_insert(allWidgets, borderSize)
    table_insert(bgWidgets, borderSize)

    local borderColor = GUIFrame:CreateColorPicker(row8c, "Border Color",
        db.Backdrop.BorderColor or { 0, 0, 0, 1 },
        function(r, g, b, a)
            db.Backdrop.BorderColor = { r, g, b, a }
            ApplySettings()
        end)
    row8c:AddWidget(borderColor, 0.21)
    table_insert(allWidgets, borderColor)
    table_insert(bgWidgets, borderColor)
    card8:AddRow(row8c, 39)

    yOffset = yOffset + card8:GetContentHeight() + Theme.paddingSmall

    -- Apply initial widget states
    UpdateAllWidgetStates()
    yOffset = yOffset - (Theme.paddingSmall * 3)
    return yOffset
end)
