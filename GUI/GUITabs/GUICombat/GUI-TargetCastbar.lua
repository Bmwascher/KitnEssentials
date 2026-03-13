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
    return KitnEssentials:GetModule("TargetCastbar", true)
end

-- Target Castbar Tab Content
GUIFrame:RegisterContent("TargetCastbar", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.TargetCastbar
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
            KitnEssentials:EnableModule("TargetCastbar")
        else
            KitnEssentials:DisableModule("TargetCastbar")
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
    -- Card 1: Target Castbar (Enable)
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Target Castbar", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Target Castbar", db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            UpdateAllWidgetStates()
        end,
        true, "Target Castbar", "On", "Off"
    )
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, 36)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 2: General Settings (Width, Height, Bar Texture)
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "General Settings", yOffset)
    table_insert(allWidgets, card2)

    -- Width + Height
    local row2a = GUIFrame:CreateRow(card2.content, 40)
    local widthSlider = GUIFrame:CreateSlider(row2a, "Width", 100, 600, 1, db.Width or 250, nil,
        function(val)
            db.Width = val
            ApplySettings()
        end)
    row2a:AddWidget(widthSlider, 0.5)
    table_insert(allWidgets, widthSlider)

    local heightSlider = GUIFrame:CreateSlider(row2a, "Height", 5, 60, 1, db.Height or 20, nil,
        function(val)
            db.Height = val
            ApplySettings()
        end)
    row2a:AddWidget(heightSlider, 0.5)
    table_insert(allWidgets, heightSlider)
    card2:AddRow(row2a, 40)

    -- Bar Texture
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

    -- Font Face + Outline
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

    -- Font Size
    local row4b = GUIFrame:CreateRow(card4.content, 36)
    local fontSizeSlider = GUIFrame:CreateSlider(row4b, "Font Size", 8, 24, 1,
        db.FontSize or 12, nil,
        function(val)
            db.FontSize = val
            ApplySettings()
        end)
    row4b:AddWidget(fontSizeSlider, 1)
    table_insert(allWidgets, fontSizeSlider)
    card4:AddRow(row4b, 36)

    yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 5: Colors
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    table_insert(allWidgets, card5)

    -- Casting + Channeling
    local row5a = GUIFrame:CreateRow(card5.content, 40)
    local castingPicker = GUIFrame:CreateColorPicker(row5a, "Casting", db.CastingColor or { 1, 0.7, 0, 1 },
        function(r, g, b, a)
            db.CastingColor = { r, g, b, a }
            ApplySettings()
        end)
    row5a:AddWidget(castingPicker, 0.5)
    table_insert(allWidgets, castingPicker)

    local channelingPicker = GUIFrame:CreateColorPicker(row5a, "Channeling", db.ChannelingColor or { 0, 0.7, 1, 1 },
        function(r, g, b, a)
            db.ChannelingColor = { r, g, b, a }
            ApplySettings()
        end)
    row5a:AddWidget(channelingPicker, 0.5)
    table_insert(allWidgets, channelingPicker)
    card5:AddRow(row5a, 40)

    -- Empowering + Not Interruptible
    local row5b = GUIFrame:CreateRow(card5.content, 40)
    local empoweringPicker = GUIFrame:CreateColorPicker(row5b, "Empowering", db.EmpoweringColor or { 0.8, 0.4, 1, 1 },
        function(r, g, b, a)
            db.EmpoweringColor = { r, g, b, a }
            ApplySettings()
        end)
    row5b:AddWidget(empoweringPicker, 0.5)
    table_insert(allWidgets, empoweringPicker)

    local notInterruptPicker = GUIFrame:CreateColorPicker(row5b, "Not Interruptible", db.NotInterruptibleColor or { 0.7, 0.7, 0.7, 1 },
        function(r, g, b, a)
            db.NotInterruptibleColor = { r, g, b, a }
            ApplySettings()
        end)
    row5b:AddWidget(notInterruptPicker, 0.5)
    table_insert(allWidgets, notInterruptPicker)
    card5:AddRow(row5b, 40)

    -- Hide Non-Interruptible Toggle
    local row5c = GUIFrame:CreateRow(card5.content, 36)
    local hideNotInterruptCheck = GUIFrame:CreateCheckbox(row5c, "Hide Non-Interruptible Casts",
        db.HideNotInterruptible == true,
        function(checked)
            db.HideNotInterruptible = checked
        end,
        true, "Hide", "On", "Off"
    )
    row5c:AddWidget(hideNotInterruptCheck, 1)
    table_insert(allWidgets, hideNotInterruptCheck)
    card5:AddRow(row5c, 36)

    -- Separator
    local rowSep1 = GUIFrame:CreateRow(card5.content, 8)
    local sep1 = GUIFrame:CreateSeparator(rowSep1)
    rowSep1:AddWidget(sep1, 1)
    card5:AddRow(rowSep1, 8)

    -- Text Color
    local row5d = GUIFrame:CreateRow(card5.content, 40)
    local textPicker = GUIFrame:CreateColorPicker(row5d, "Text", db.TextColor or { 1, 1, 1, 1 },
        function(r, g, b, a)
            db.TextColor = { r, g, b, a }
            ApplySettings()
        end)
    row5d:AddWidget(textPicker, 0.5)
    table_insert(allWidgets, textPicker)
    card5:AddRow(row5d, 40)

    -- Separator
    local rowSep2 = GUIFrame:CreateRow(card5.content, 8)
    local sep2 = GUIFrame:CreateSeparator(rowSep2)
    rowSep2:AddWidget(sep2, 1)
    card5:AddRow(rowSep2, 8)

    -- Background + Border
    local row5e = GUIFrame:CreateRow(card5.content, 36)
    local bgPicker = GUIFrame:CreateColorPicker(row5e, "Background", db.BackdropColor or { 0, 0, 0, 0.8 },
        function(r, g, b, a)
            db.BackdropColor = { r, g, b, a }
            ApplySettings()
        end)
    row5e:AddWidget(bgPicker, 0.5)
    table_insert(allWidgets, bgPicker)

    local borderPicker = GUIFrame:CreateColorPicker(row5e, "Border", db.BorderColor or { 0, 0, 0, 1 },
        function(r, g, b, a)
            db.BorderColor = { r, g, b, a }
            ApplySettings()
        end)
    row5e:AddWidget(borderPicker, 0.5)
    table_insert(allWidgets, borderPicker)
    card5:AddRow(row5e, 36)

    yOffset = yOffset + card5:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 6: Hold Timer
    ----------------------------------------------------------------
    local card6 = GUIFrame:CreateCard(scrollChild, "Hold Timer", yOffset)
    table_insert(allWidgets, card6)

    -- Track hold timer widgets for sub-toggle
    local holdTimerWidgets = {}

    local function UpdateHoldTimerWidgetStates()
        local holdEnabled = db.HoldTimer and db.HoldTimer.Enabled ~= false
        for _, widget in ipairs(holdTimerWidgets) do
            if widget.SetEnabled then
                widget:SetEnabled(holdEnabled)
            end
        end
    end

    -- Initialize HoldTimer db if needed
    if not db.HoldTimer then
        db.HoldTimer = {
            Enabled = true,
            Duration = 0.5,
            InterruptedColor = { 0.1, 0.8, 0.1, 1 },
            SuccessColor = { 0.8, 0.1, 0.1, 1 },
        }
    end

    -- Enable + Duration
    local row6a = GUIFrame:CreateRow(card6.content, 40)
    local holdEnableCheck = GUIFrame:CreateCheckbox(row6a, "Enable Hold Timer", db.HoldTimer.Enabled ~= false,
        function(checked)
            db.HoldTimer.Enabled = checked
            UpdateHoldTimerWidgetStates()
        end,
        true, "Hold Timer", "On", "Off"
    )
    row6a:AddWidget(holdEnableCheck, 0.5)

    local holdSlider = GUIFrame:CreateSlider(row6a, "Hold Duration", 0, 2, 0.1,
        db.HoldTimer.Duration or 0.5, nil,
        function(val)
            db.HoldTimer.Duration = val
        end)
    row6a:AddWidget(holdSlider, 0.5)
    table_insert(holdTimerWidgets, holdSlider)
    card6:AddRow(row6a, 40)

    -- Separator
    local rowSep3 = GUIFrame:CreateRow(card6.content, 8)
    local sep3 = GUIFrame:CreateSeparator(rowSep3)
    rowSep3:AddWidget(sep3, 1)
    card6:AddRow(rowSep3, 8)

    -- Interrupted + Success Colors
    local row6b = GUIFrame:CreateRow(card6.content, 36)
    local interruptedPicker = GUIFrame:CreateColorPicker(row6b, "Interrupted", db.HoldTimer.InterruptedColor or { 0.1, 0.8, 0.1, 1 },
        function(r, g, b, a)
            db.HoldTimer.InterruptedColor = { r, g, b, a }
        end)
    row6b:AddWidget(interruptedPicker, 0.5)
    table_insert(holdTimerWidgets, interruptedPicker)

    local successPicker = GUIFrame:CreateColorPicker(row6b, "Cast Success", db.HoldTimer.SuccessColor or { 0.8, 0.1, 0.1, 1 },
        function(r, g, b, a)
            db.HoldTimer.SuccessColor = { r, g, b, a }
        end)
    row6b:AddWidget(successPicker, 0.5)
    table_insert(holdTimerWidgets, successPicker)
    card6:AddRow(row6b, 36)

    yOffset = yOffset + card6:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 7: Kick Indicator
    ----------------------------------------------------------------
    local card7 = GUIFrame:CreateCard(scrollChild, "Kick Indicator", yOffset)
    table_insert(allWidgets, card7)

    -- Track kick indicator widgets for sub-toggle
    local kickIndicatorWidgets = {}

    local function UpdateKickIndicatorWidgetStates()
        local kickEnabled = db.KickIndicator and db.KickIndicator.Enabled ~= false
        for _, widget in ipairs(kickIndicatorWidgets) do
            if widget.SetEnabled then
                widget:SetEnabled(kickEnabled)
            end
        end
    end

    -- Enable Toggle
    local row7a = GUIFrame:CreateRow(card7.content, 40)
    local kickEnableCheck = GUIFrame:CreateCheckbox(row7a, "Enable Kick Indicator", db.KickIndicator.Enabled ~= false,
        function(checked)
            db.KickIndicator.Enabled = checked
            UpdateKickIndicatorWidgetStates()
        end,
        true, "Kick Indicator", "On", "Off"
    )
    row7a:AddWidget(kickEnableCheck, 1)
    card7:AddRow(row7a, 40)

    -- Separator
    local rowSepKick = GUIFrame:CreateRow(card7.content, 8)
    local sepKick = GUIFrame:CreateSeparator(rowSepKick)
    rowSepKick:AddWidget(sepKick, 1)
    card7:AddRow(rowSepKick, 8)

    -- Ready + Not Ready Colors
    local row7b = GUIFrame:CreateRow(card7.content, 40)
    local readyPicker = GUIFrame:CreateColorPicker(row7b, "Kick Ready", db.KickIndicator.ReadyColor or { 0.1, 0.8, 0.1, 1 },
        function(r, g, b, a)
            db.KickIndicator.ReadyColor = { r, g, b, a }
            ApplySettings()
        end)
    row7b:AddWidget(readyPicker, 0.5)
    table_insert(kickIndicatorWidgets, readyPicker)

    local notReadyPicker = GUIFrame:CreateColorPicker(row7b, "Kick Not Ready", db.KickIndicator.NotReadyColor or { 0.5, 0.5, 0.5, 1 },
        function(r, g, b, a)
            db.KickIndicator.NotReadyColor = { r, g, b, a }
            ApplySettings()
        end)
    row7b:AddWidget(notReadyPicker, 0.5)
    table_insert(kickIndicatorWidgets, notReadyPicker)
    card7:AddRow(row7b, 40)

    -- Tick Color
    local row7c = GUIFrame:CreateRow(card7.content, 36)
    local tickPicker = GUIFrame:CreateColorPicker(row7c, "Kick Ready Tick", db.KickIndicator.TickColor or { 1, 1, 1, 1 },
        function(r, g, b, a)
            db.KickIndicator.TickColor = { r, g, b, a }
            ApplySettings()
        end)
    row7c:AddWidget(tickPicker, 0.5)
    table_insert(kickIndicatorWidgets, tickPicker)
    card7:AddRow(row7c, 36)

    yOffset = yOffset + card7:GetContentHeight() + Theme.paddingSmall

    -- Apply initial widget states
    UpdateAllWidgetStates()
    UpdateHoldTimerWidgetStates()
    UpdateKickIndicatorWidgetStates()
    yOffset = yOffset - Theme.paddingSmall
    return yOffset
end)
