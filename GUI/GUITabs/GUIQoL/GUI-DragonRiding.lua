-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-DragonRiding.lua                                    ║
-- ║  GUI: Skyriding UI                                       ║
-- ║  Purpose: Configuration panel for the                    ║
-- ║           DragonRiding module.                           ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local table_insert = table.insert
local ipairs = ipairs

local function GetDragonRidingModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("DragonRiding", true)
    end
    return nil
end

GUIFrame:RegisterContent("DragonRiding", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.DragonRiding
    if not db then return yOffset end

    local DR = GetDragonRidingModule()
    local allWidgets = {}

    local function ApplySettings()
        if DR and DR.ApplySettings then DR:ApplySettings() end
    end

    local function ApplyDragonRidingState(enabled)
        if not DR then return end
        DR.db.Enabled = enabled
        if enabled then KitnEssentials:EnableModule("DragonRiding")
        else KitnEssentials:DisableModule("DragonRiding") end
    end

    local sizeSlider     -- forward-declared so the auto-size checkbox can toggle it
    local thrillPicker   -- forward-declared so the thrill toggle can grey it

    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false
        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then widget:SetEnabled(mainEnabled) end
        end
        -- Size slider only active when Auto Size is off (and the module is on).
        if sizeSlider and sizeSlider.SetEnabled then
            sizeSlider:SetEnabled(mainEnabled and db.SurgeIconAutoSize == false)
        end
        -- Thrill color picker only active when Thrill coloring is enabled.
        if thrillPicker and thrillPicker.SetEnabled then
            thrillPicker:SetEnabled(mainEnabled and db.EnableThrillColor ~= false)
        end
    end

    ---------------------------------------------------------------------------------
    -- Card 1: Enable
    ---------------------------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Skyriding UI", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Skyriding UI", db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplyDragonRidingState(checked)
            UpdateAllWidgetStates()
        end,
        true, "Skyriding UI", "On", "Off")
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, 36)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 2: Behavior
    ---------------------------------------------------------------------------------
    local cardBehavior = GUIFrame:CreateCard(scrollChild, "Behavior", yOffset)
    table_insert(allWidgets, cardBehavior)

    local function ApplyLayout()
        if DR and DR.ApplyBarLayout then DR:ApplyBarLayout() end
        if DR and DR.ApplySurgeIcon then DR:ApplySurgeIcon() end
    end

    local bRow1 = GUIFrame:CreateRow(cardBehavior.content, 36)
    local groundedCheck = GUIFrame:CreateCheckbox(bRow1, "Hide When Grounded", db.HideWhenGrounded == true,
        function(checked)
            db.HideWhenGrounded = checked
            if not checked and DR and DR.container then
                DR.container:Show()
            end
        end,
        true, "Hide Grounded", "On", "Off")
    bRow1:AddWidget(groundedCheck, 1 / 3)
    table_insert(allWidgets, groundedCheck)

    local fullCheck = GUIFrame:CreateCheckbox(bRow1, "Hide When Full", db.HideWhenFull == true,
        function(checked)
            db.HideWhenFull = checked
            if not checked and DR and DR.container then
                DR.container:Show()
            end
        end,
        true, "Hide Full", "On", "Off")
    bRow1:AddWidget(fullCheck, 1 / 3)
    table_insert(allWidgets, fullCheck)

    local thrillCheck = GUIFrame:CreateCheckbox(bRow1, "Use Thrill Color", db.EnableThrillColor ~= false,
        function(checked)
            db.EnableThrillColor = checked
            ApplySettings()
            UpdateAllWidgetStates()
        end,
        true, "Thrill Color", "On", "Off")
    bRow1:AddWidget(thrillCheck, 1 / 3)
    table_insert(allWidgets, thrillCheck)
    cardBehavior:AddRow(bRow1, 36)

    local bRow2 = GUIFrame:CreateRow(cardBehavior.content, 36)
    local secondWindCheck = GUIFrame:CreateCheckbox(bRow2, "Show Second Wind", db.ShowSecondWind ~= false,
        function(checked)
            db.ShowSecondWind = checked
            ApplyLayout()
        end,
        true, "Second Wind", "On", "Off")
    bRow2:AddWidget(secondWindCheck, 1 / 3)
    table_insert(allWidgets, secondWindCheck)

    local flipCheck = GUIFrame:CreateCheckbox(bRow2, "Flip Bar Order", db.FlipBars == true,
        function(checked)
            db.FlipBars = checked
            ApplyLayout()
        end,
        true, "Flip Bars", "On", "Off")
    bRow2:AddWidget(flipCheck, 1 / 3)
    table_insert(allWidgets, flipCheck)

    local speedTextCheck = GUIFrame:CreateCheckbox(bRow2, "Show Speed Text", db.ShowSpeedText ~= false,
        function(checked)
            db.ShowSpeedText = checked
            ApplyLayout()
        end,
        true, "Speed Text", "On", "Off")
    bRow2:AddWidget(speedTextCheck, 1 / 3)
    table_insert(allWidgets, speedTextCheck)
    cardBehavior:AddRow(bRow2, 36)

    yOffset = yOffset + cardBehavior:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 2: Size Settings
    ---------------------------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Size Settings", yOffset)
    table_insert(allWidgets, card2)

    local row2 = GUIFrame:CreateRow(card2.content, 40)
    local widthSlider = GUIFrame:CreateSlider(row2, "Width", 100, 500, 1,
        db.Width or 252, nil,
        function(val) db.Width = val; ApplySettings() end)
    row2:AddWidget(widthSlider, 1)
    table_insert(allWidgets, widthSlider)
    card2:AddRow(row2, 40)

    local row3 = GUIFrame:CreateRow(card2.content, 40)
    local heightSlider = GUIFrame:CreateSlider(row3, "Bar Height", 1, 24, 1,
        db.BarHeight or 12, nil,
        function(val) db.BarHeight = val; ApplySettings() end)
    row3:AddWidget(heightSlider, 1)
    table_insert(allWidgets, heightSlider)
    card2:AddRow(row3, 40)

    local row3b = GUIFrame:CreateRow(card2.content, 40)
    local spacingSlider = GUIFrame:CreateSlider(row3b, "Row Spacing", 0, 10, 1,
        db.Spacing or 1, nil,
        function(val) db.Spacing = val; ApplySettings() end)
    row3b:AddWidget(spacingSlider, 1)
    table_insert(allWidgets, spacingSlider)
    card2:AddRow(row3b, 40)

    local row4 = GUIFrame:CreateRow(card2.content, 40)
    local speedFontSlider = GUIFrame:CreateSlider(row4, "Speed Font Size", 8, 24, 1,
        db.SpeedFontSize or 14, nil,
        function(val) db.SpeedFontSize = val; ApplySettings() end)
    row4:AddWidget(speedFontSlider, 1)
    table_insert(allWidgets, speedFontSlider)
    card2:AddRow(row4, 40)

    yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 3: Colors
    ---------------------------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    table_insert(allWidgets, card3)

    db.Colors = db.Colors or {}

    local row5 = GUIFrame:CreateRow(card3.content, 36)
    local vigorPicker = GUIFrame:CreateColorPicker(row5, "Vigor",
        db.Colors.Vigor or { 0.898, 0.063, 0.224, 1 },
        function(r, g, b, a) db.Colors.Vigor = { r, g, b, a }; ApplySettings() end)
    row5:AddWidget(vigorPicker, 1 / 3)
    table_insert(allWidgets, vigorPicker)
    thrillPicker = GUIFrame:CreateColorPicker(row5, "Vigor (Thrill)",
        db.Colors.VigorThrill or { 0.2, 0.8, 0.2, 1 },
        function(r, g, b, a) db.Colors.VigorThrill = { r, g, b, a }; ApplySettings() end)
    row5:AddWidget(thrillPicker, 1 / 3)
    local swPicker = GUIFrame:CreateColorPicker(row5, "Second Wind",
        db.Colors.SecondWind or { 0.3, 0.7, 1, 1 },
        function(r, g, b, a) db.Colors.SecondWind = { r, g, b, a }; ApplySettings() end)
    row5:AddWidget(swPicker, 1 / 3)
    table_insert(allWidgets, swPicker)
    card3:AddRow(row5, 36)

    yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 4: Surge Icon
    ---------------------------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Whirling Surge Icon", yOffset)
    table_insert(allWidgets, card4)

    local sRow1 = GUIFrame:CreateRow(card4.content, 36)
    local showSurgeCheck = GUIFrame:CreateCheckbox(sRow1, "Show Surge Icon", db.ShowSurgeIcon ~= false,
        function(checked)
            db.ShowSurgeIcon = checked
            if DR and DR.ApplySurgeIcon then DR:ApplySurgeIcon() end
        end,
        true, "Surge Icon", "On", "Off")
    sRow1:AddWidget(showSurgeCheck, 1 / 3)
    table_insert(allWidgets, showSurgeCheck)

    local leftSideCheck = GUIFrame:CreateCheckbox(sRow1, "Place on Left Side", db.SurgeIconOnLeft == true,
        function(checked)
            db.SurgeIconOnLeft = checked
            if DR and DR.ApplySurgeIcon then DR:ApplySurgeIcon() end
        end,
        true, "Left Side", "On", "Off")
    sRow1:AddWidget(leftSideCheck, 1 / 3)
    table_insert(allWidgets, leftSideCheck)

    local autoSizeCheck = GUIFrame:CreateCheckbox(sRow1, "Auto Size", db.SurgeIconAutoSize ~= false,
        function(checked)
            db.SurgeIconAutoSize = checked
            if DR and DR.ApplySurgeIcon then DR:ApplySurgeIcon() end
            UpdateAllWidgetStates()
        end,
        true, "Auto Size", "On", "Off")
    sRow1:AddWidget(autoSizeCheck, 1 / 3)
    table_insert(allWidgets, autoSizeCheck)
    card4:AddRow(sRow1, 36)

    local sRow2 = GUIFrame:CreateRow(card4.content, 40)
    local gapSlider = GUIFrame:CreateSlider(sRow2, "Gap From Bars", 0, 20, 1,
        db.SurgeIconGap or 4, nil,
        function(val)
            db.SurgeIconGap = val
            if DR and DR.ApplySurgeIcon then DR:ApplySurgeIcon() end
        end)
    sRow2:AddWidget(gapSlider, 0.5)
    table_insert(allWidgets, gapSlider)
    -- Manual size override (only applied when Auto Size is off). Slider gets
    -- disabled in UpdateAllWidgetStates whenever Auto Size is on.
    sizeSlider = GUIFrame:CreateSlider(sRow2, "Icon Size", 16, 64, 1,
        db.SurgeIconSize or 26, nil,
        function(val)
            db.SurgeIconSize = val
            if DR and DR.ApplySurgeIcon then DR:ApplySurgeIcon() end
        end)
    sRow2:AddWidget(sizeSlider, 0.5)
    card4:AddRow(sRow2, 40)

    yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 5: Position Settings
    ---------------------------------------------------------------------------------
    local card5, newOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
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
        showAnchorFrameType = false,
        showStrata = true,
        onChangeCallback = ApplySettings,
    })

    if card5.positionWidgets then
        for _, widget in ipairs(card5.positionWidgets) do
            table_insert(allWidgets, widget)
        end
    end
    table_insert(allWidgets, card5)

    yOffset = newOffset

    UpdateAllWidgetStates()
    yOffset = yOffset - Theme.paddingSmall
    return yOffset
end)
