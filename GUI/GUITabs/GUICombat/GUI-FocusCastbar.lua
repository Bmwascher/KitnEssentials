-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)

-- Localization
local table_insert = table.insert
local ipairs = ipairs
local pairs = pairs

-- Helper to get module
local function GetModule()
    return KitnEssentials:GetModule("FocusCastbar", true)
end

-- Focus Castbar Tab Content
GUIFrame:RegisterContent("FocusCastbar", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.FocusCastbar
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return yOffset + errorCard:GetContentHeight() + Theme.paddingMedium
    end

    local mod = GetModule()
    local allWidgets = {}

    local function ApplySettings()
        if mod and mod.ApplySettings then
            mod:ApplySettings()
        end
    end

    local function ApplyPosition()
        if mod and mod.ApplyPosition then
            mod:ApplyPosition()
        end
    end

    local function ApplyModuleState(enabled)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("FocusCastbar")
        else
            KitnEssentials:DisableModule("FocusCastbar")
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

    -- Build LSM lists
    local fontList = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do fontList[name] = name end
    else
        fontList["Friz Quadrata TT"] = "Friz Quadrata TT"
    end

    local statusbarList = {}
    if LSM then
        for name in pairs(LSM:HashTable("statusbar")) do statusbarList[name] = name end
    else
        statusbarList["Blizzard"] = "Blizzard"
    end

    ----------------------------------------------------------------
    -- Card 1: Focus Castbar (Enable)
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Focus Castbar", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Focus Castbar", db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            UpdateAllWidgetStates()
        end,
        true, "Focus Castbar", "On", "Off"
    )
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, 36)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 2: General Settings (Width, Height, Bar Texture)
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "General Settings", yOffset)
    table_insert(allWidgets, card2)

    local row2a = GUIFrame:CreateRow(card2.content, 40)
    local widthSlider = GUIFrame:CreateSlider(row2a, "Width", 100, 600, 1, db.Width or 200, nil,
        function(val)
            db.Width = val
            ApplySettings()
        end)
    row2a:AddWidget(widthSlider, 0.5)
    table_insert(allWidgets, widthSlider)

    local heightSlider = GUIFrame:CreateSlider(row2a, "Height", 5, 60, 1, db.Height or 18, nil,
        function(val)
            db.Height = val
            ApplySettings()
        end)
    row2a:AddWidget(heightSlider, 0.5)
    table_insert(allWidgets, heightSlider)
    card2:AddRow(row2a, 40)

    local row2b = GUIFrame:CreateRow(card2.content, 36)
    local statusbarDropdown = GUIFrame:CreateDropdown(row2b, "Bar Texture", statusbarList,
        db.StatusBarTexture or "KitnUI", 70,
        function(key)
            db.StatusBarTexture = key
            ApplySettings()
        end)
    row2b:AddWidget(statusbarDropdown, 1)
    table_insert(allWidgets, statusbarDropdown)
    card2:AddRow(row2b, 36)

    yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 3: Position Settings
    ----------------------------------------------------------------
    local card3, newYOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
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
        onChangeCallback = ApplyPosition,
    })

    if card3.positionWidgets then
        for _, widget in ipairs(card3.positionWidgets) do
            table_insert(allWidgets, widget)
        end
    end
    table_insert(allWidgets, card3)
    yOffset = newYOffset

    ----------------------------------------------------------------
    -- Card 4: Font Settings
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Font Settings", yOffset)
    table_insert(allWidgets, card4)

    local row4a = GUIFrame:CreateRow(card4.content, 40)
    local fontDropdown = GUIFrame:CreateDropdown(row4a, "Font", fontList,
        db.FontFace or "Expressway", 30,
        function(key)
            db.FontFace = key
            ApplySettings()
        end)
    row4a:AddWidget(fontDropdown, 0.5)
    table_insert(allWidgets, fontDropdown)

    local outlineList = {
        { key = "NONE", text = "None" },
        { key = "OUTLINE", text = "Outline" },
        { key = "THICKOUTLINE", text = "Thick" },
        { key = "SOFTOUTLINE", text = "Soft" },
    }
    local outlineDropdown = GUIFrame:CreateDropdown(row4a, "Outline", outlineList,
        db.FontOutline or "OUTLINE", 45,
        function(key)
            db.FontOutline = key
            ApplySettings()
        end)
    row4a:AddWidget(outlineDropdown, 0.5)
    table_insert(allWidgets, outlineDropdown)
    card4:AddRow(row4a, 40)

    local row4b = GUIFrame:CreateRow(card4.content, 36)
    local fontSizeSlider = GUIFrame:CreateSlider(row4b, "Font Size", 8, 24, 1,
        db.FontSize or 11, nil,
        function(val)
            db.FontSize = val
            ApplySettings()
        end)
    row4b:AddWidget(fontSizeSlider, 1)
    table_insert(allWidgets, fontSizeSlider)
    card4:AddRow(row4b, 36)

    yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 5: Target Names
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Target Names", yOffset)
    table_insert(allWidgets, card5)

    if not db.TargetNames then
        db.TargetNames = {
            Anchor = "RIGHT",
            XOffset = 0,
            YOffset = 14,
            FontSize = 12,
        }
    end

    local anchorList = {
        { key = "LEFT", text = "Left" },
        { key = "CENTER", text = "Center" },
        { key = "RIGHT", text = "Right" },
    }

    -- Anchor + Font Size
    local row5a = GUIFrame:CreateRow(card5.content, 40)
    local anchorDropdown = GUIFrame:CreateDropdown(row5a, "Anchor", anchorList,
        db.TargetNames.Anchor or "RIGHT", 50,
        function(key)
            db.TargetNames.Anchor = key
            ApplySettings()
        end)
    row5a:AddWidget(anchorDropdown, 0.5)
    table_insert(allWidgets, anchorDropdown)

    local targetFontSlider = GUIFrame:CreateSlider(row5a, "Font Size", 6, 18, 1,
        db.TargetNames.FontSize or 12, nil,
        function(val)
            db.TargetNames.FontSize = val
            ApplySettings()
        end)
    row5a:AddWidget(targetFontSlider, 0.5)
    table_insert(allWidgets, targetFontSlider)
    card5:AddRow(row5a, 40)

    -- X + Y Offset
    local row5b = GUIFrame:CreateRow(card5.content, 40)
    local targetXSlider = GUIFrame:CreateSlider(row5b, "X Offset", -100, 100, 1,
        db.TargetNames.XOffset or 0, nil,
        function(val)
            db.TargetNames.XOffset = val
            ApplySettings()
        end)
    row5b:AddWidget(targetXSlider, 0.5)
    table_insert(allWidgets, targetXSlider)

    local targetYSlider = GUIFrame:CreateSlider(row5b, "Y Offset", -50, 100, 1,
        db.TargetNames.YOffset or 14, nil,
        function(val)
            db.TargetNames.YOffset = val
            ApplySettings()
        end)
    row5b:AddWidget(targetYSlider, 0.5)
    table_insert(allWidgets, targetYSlider)
    card5:AddRow(row5b, 40)

    yOffset = yOffset + card5:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 6: Colors
    ----------------------------------------------------------------
    local card7 = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    table_insert(allWidgets, card7)

    -- Casting + Channeling
    local row7a = GUIFrame:CreateRow(card7.content, 40)
    local castingPicker = GUIFrame:CreateColorPicker(row7a, "Casting", db.CastingColor or { 1, 0.7, 0, 1 },
        function(r, g, b, a)
            db.CastingColor = { r, g, b, a }
            ApplySettings()
        end)
    row7a:AddWidget(castingPicker, 0.5)
    table_insert(allWidgets, castingPicker)

    local channelingPicker = GUIFrame:CreateColorPicker(row7a, "Channeling", db.ChannelingColor or { 0, 0.7, 1, 1 },
        function(r, g, b, a)
            db.ChannelingColor = { r, g, b, a }
            ApplySettings()
        end)
    row7a:AddWidget(channelingPicker, 0.5)
    table_insert(allWidgets, channelingPicker)
    card7:AddRow(row7a, 40)

    -- Empowering + Not Interruptible
    local row7b = GUIFrame:CreateRow(card7.content, 40)
    local empoweringPicker = GUIFrame:CreateColorPicker(row7b, "Empowering", db.EmpoweringColor or { 0.8, 0.4, 1, 1 },
        function(r, g, b, a)
            db.EmpoweringColor = { r, g, b, a }
            ApplySettings()
        end)
    row7b:AddWidget(empoweringPicker, 0.5)
    table_insert(allWidgets, empoweringPicker)

    local notInterruptPicker = GUIFrame:CreateColorPicker(row7b, "Not Interruptible", db.NotInterruptibleColor or { 0.7, 0.7, 0.7, 1 },
        function(r, g, b, a)
            db.NotInterruptibleColor = { r, g, b, a }
            ApplySettings()
        end)
    row7b:AddWidget(notInterruptPicker, 0.5)
    table_insert(allWidgets, notInterruptPicker)
    card7:AddRow(row7b, 40)

    -- Hide Non-Interruptible
    local row7c = GUIFrame:CreateRow(card7.content, 36)
    local hideNotInterruptCheck = GUIFrame:CreateCheckbox(row7c, "Hide Non-Interruptible Casts",
        db.HideNotInterruptible == true,
        function(checked)
            db.HideNotInterruptible = checked
        end,
        true, "Hide", "On", "Off"
    )
    row7c:AddWidget(hideNotInterruptCheck, 1)
    table_insert(allWidgets, hideNotInterruptCheck)
    card7:AddRow(row7c, 36)

    -- Separator
    local rowSep1 = GUIFrame:CreateRow(card7.content, 8)
    local sep1 = GUIFrame:CreateSeparator(rowSep1)
    rowSep1:AddWidget(sep1, 1)
    card7:AddRow(rowSep1, 8)

    -- Text Color
    local row7d = GUIFrame:CreateRow(card7.content, 40)
    local textPicker = GUIFrame:CreateColorPicker(row7d, "Text", db.TextColor or { 1, 1, 1, 1 },
        function(r, g, b, a)
            db.TextColor = { r, g, b, a }
            ApplySettings()
        end)
    row7d:AddWidget(textPicker, 0.5)
    table_insert(allWidgets, textPicker)
    card7:AddRow(row7d, 40)

    -- Separator
    local rowSep2 = GUIFrame:CreateRow(card7.content, 8)
    local sep2 = GUIFrame:CreateSeparator(rowSep2)
    rowSep2:AddWidget(sep2, 1)
    card7:AddRow(rowSep2, 8)

    -- Background + Border
    local row7e = GUIFrame:CreateRow(card7.content, 36)
    local bgPicker = GUIFrame:CreateColorPicker(row7e, "Background", db.BackdropColor or { 0, 0, 0, 0.8 },
        function(r, g, b, a)
            db.BackdropColor = { r, g, b, a }
            ApplySettings()
        end)
    row7e:AddWidget(bgPicker, 0.5)
    table_insert(allWidgets, bgPicker)

    local borderPicker = GUIFrame:CreateColorPicker(row7e, "Border", db.BorderColor or { 0, 0, 0, 1 },
        function(r, g, b, a)
            db.BorderColor = { r, g, b, a }
            ApplySettings()
        end)
    row7e:AddWidget(borderPicker, 0.5)
    table_insert(allWidgets, borderPicker)
    card7:AddRow(row7e, 36)

    yOffset = yOffset + card7:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 8: Hold Timer
    ----------------------------------------------------------------
    local card8 = GUIFrame:CreateCard(scrollChild, "Hold Timer", yOffset)
    table_insert(allWidgets, card8)

    local holdTimerWidgets = {}

    local function UpdateHoldTimerWidgetStates()
        local holdEnabled = db.HoldTimer and db.HoldTimer.Enabled ~= false
        for _, widget in ipairs(holdTimerWidgets) do
            if widget.SetEnabled then
                widget:SetEnabled(holdEnabled)
            end
        end
    end

    if not db.HoldTimer then
        db.HoldTimer = {
            Enabled = true,
            Duration = 0.5,
            InterruptedColor = { 0.1, 0.8, 0.1, 1 },
            SuccessColor = { 0.8, 0.1, 0.1, 1 },
        }
    end

    local row8a = GUIFrame:CreateRow(card8.content, 40)
    local holdEnableCheck = GUIFrame:CreateCheckbox(row8a, "Enable Hold Timer", db.HoldTimer.Enabled ~= false,
        function(checked)
            db.HoldTimer.Enabled = checked
            UpdateHoldTimerWidgetStates()
        end,
        true, "Hold Timer", "On", "Off"
    )
    row8a:AddWidget(holdEnableCheck, 0.5)

    local holdSlider = GUIFrame:CreateSlider(row8a, "Hold Duration", 0, 2, 0.1,
        db.HoldTimer.Duration or 0.5, nil,
        function(val)
            db.HoldTimer.Duration = val
        end)
    row8a:AddWidget(holdSlider, 0.5)
    table_insert(holdTimerWidgets, holdSlider)
    card8:AddRow(row8a, 40)

    -- Separator
    local rowSep3 = GUIFrame:CreateRow(card8.content, 8)
    local sep3 = GUIFrame:CreateSeparator(rowSep3)
    rowSep3:AddWidget(sep3, 1)
    card8:AddRow(rowSep3, 8)

    -- Interrupted + Success Colors
    local row8b = GUIFrame:CreateRow(card8.content, 36)
    local interruptedPicker = GUIFrame:CreateColorPicker(row8b, "Interrupted", db.HoldTimer.InterruptedColor or { 0.1, 0.8, 0.1, 1 },
        function(r, g, b, a)
            db.HoldTimer.InterruptedColor = { r, g, b, a }
        end)
    row8b:AddWidget(interruptedPicker, 0.5)
    table_insert(holdTimerWidgets, interruptedPicker)

    local successPicker = GUIFrame:CreateColorPicker(row8b, "Cast Success", db.HoldTimer.SuccessColor or { 0.8, 0.1, 0.1, 1 },
        function(r, g, b, a)
            db.HoldTimer.SuccessColor = { r, g, b, a }
        end)
    row8b:AddWidget(successPicker, 0.5)
    table_insert(holdTimerWidgets, successPicker)
    card8:AddRow(row8b, 36)

    yOffset = yOffset + card8:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 9: Kick Indicator
    ----------------------------------------------------------------
    local card9 = GUIFrame:CreateCard(scrollChild, "Kick Indicator", yOffset)
    table_insert(allWidgets, card9)

    local kickIndicatorWidgets = {}

    local function UpdateKickIndicatorWidgetStates()
        local kickEnabled = db.KickIndicator and db.KickIndicator.Enabled ~= false
        for _, widget in ipairs(kickIndicatorWidgets) do
            if widget.SetEnabled then
                widget:SetEnabled(kickEnabled)
            end
        end
    end

    local row9a = GUIFrame:CreateRow(card9.content, 40)
    local kickEnableCheck = GUIFrame:CreateCheckbox(row9a, "Enable Kick Indicator", db.KickIndicator.Enabled ~= false,
        function(checked)
            db.KickIndicator.Enabled = checked
            UpdateKickIndicatorWidgetStates()
        end,
        true, "Kick Indicator", "On", "Off"
    )
    row9a:AddWidget(kickEnableCheck, 1)
    card9:AddRow(row9a, 40)

    -- Separator
    local rowSepKick = GUIFrame:CreateRow(card9.content, 8)
    local sepKick = GUIFrame:CreateSeparator(rowSepKick)
    rowSepKick:AddWidget(sepKick, 1)
    card9:AddRow(rowSepKick, 8)

    -- Ready + Not Ready Colors
    local row9b = GUIFrame:CreateRow(card9.content, 40)
    local readyPicker = GUIFrame:CreateColorPicker(row9b, "Kick Ready", db.KickIndicator.ReadyColor or { 0.1, 0.8, 0.1, 1 },
        function(r, g, b, a)
            db.KickIndicator.ReadyColor = { r, g, b, a }
            ApplySettings()
        end)
    row9b:AddWidget(readyPicker, 0.5)
    table_insert(kickIndicatorWidgets, readyPicker)

    local notReadyPicker = GUIFrame:CreateColorPicker(row9b, "Kick Not Ready", db.KickIndicator.NotReadyColor or { 0.5, 0.5, 0.5, 1 },
        function(r, g, b, a)
            db.KickIndicator.NotReadyColor = { r, g, b, a }
            ApplySettings()
        end)
    row9b:AddWidget(notReadyPicker, 0.5)
    table_insert(kickIndicatorWidgets, notReadyPicker)
    card9:AddRow(row9b, 40)

    -- Tick Color
    local row9c = GUIFrame:CreateRow(card9.content, 36)
    local tickPicker = GUIFrame:CreateColorPicker(row9c, "Kick Ready Tick", db.KickIndicator.TickColor or { 1, 1, 1, 1 },
        function(r, g, b, a)
            db.KickIndicator.TickColor = { r, g, b, a }
            ApplySettings()
        end)
    row9c:AddWidget(tickPicker, 0.5)
    table_insert(kickIndicatorWidgets, tickPicker)
    card9:AddRow(row9c, 36)

    yOffset = yOffset + card9:GetContentHeight() + Theme.paddingSmall

    -- Apply initial widget states
    UpdateAllWidgetStates()
    UpdateHoldTimerWidgetStates()
    UpdateKickIndicatorWidgetStates()
    yOffset = yOffset - Theme.paddingSmall
    return yOffset
end)
