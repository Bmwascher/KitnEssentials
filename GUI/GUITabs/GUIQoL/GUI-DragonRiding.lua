-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM

local table_insert = table.insert
local pairs, ipairs = pairs, ipairs

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

    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false
        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then widget:SetEnabled(mainEnabled) end
        end
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Skyriding UI", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Skyriding UI", db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplyDragonRidingState(checked)
            UpdateAllWidgetStates()
        end,
        true, "Skyriding UI", "On", "Off")
    row1:AddWidget(enableCheck, 0.5)

    local groundedCheck = GUIFrame:CreateCheckbox(row1, "Hide When Grounded", db.HideWhenGrounded == true,
        function(checked)
            db.HideWhenGrounded = checked
            if not checked and DR and DR.container then
                DR.container:Show()
            end
        end,
        true, "Hide Grounded", "On", "Off")
    row1:AddWidget(groundedCheck, 0.5)
    table_insert(allWidgets, groundedCheck)
    card1:AddRow(row1, 36)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 2: Size Settings
    ----------------------------------------------------------------
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

    ----------------------------------------------------------------
    -- Card 3: Colors
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    table_insert(allWidgets, card3)

    db.Colors = db.Colors or {}

    local row5 = GUIFrame:CreateRow(card3.content, 36)
    local vigorPicker = GUIFrame:CreateColorPicker(row5, "Vigor",
        db.Colors.Vigor or { 0.898, 0.063, 0.224, 1 },
        function(r, g, b, a) db.Colors.Vigor = { r, g, b, a }; ApplySettings() end)
    row5:AddWidget(vigorPicker, 0.5)
    table_insert(allWidgets, vigorPicker)
    card3:AddRow(row5, 36)

    local row6 = GUIFrame:CreateRow(card3.content, 36)
    local thrillPicker = GUIFrame:CreateColorPicker(row6, "Vigor (Thrill)",
        db.Colors.VigorThrill or { 0.2, 0.8, 0.2, 1 },
        function(r, g, b, a) db.Colors.VigorThrill = { r, g, b, a }; ApplySettings() end)
    row6:AddWidget(thrillPicker, 0.5)
    table_insert(allWidgets, thrillPicker)
    card3:AddRow(row6, 36)

    local row7 = GUIFrame:CreateRow(card3.content, 36)
    local surgePicker = GUIFrame:CreateColorPicker(row7, "Whirling Surge",
        db.Colors.WhirlingSurge or { 0.6, 0.4, 0.9, 1 },
        function(r, g, b, a) db.Colors.WhirlingSurge = { r, g, b, a }; ApplySettings() end)
    row7:AddWidget(surgePicker, 0.5)
    table_insert(allWidgets, surgePicker)
    local surgeCDPicker = GUIFrame:CreateColorPicker(row7, "Whirling Surge (CD)",
        db.Colors.WhirlingSurgeCD or { 0.3, 0.3, 0.3, 1 },
        function(r, g, b, a) db.Colors.WhirlingSurgeCD = { r, g, b, a }; ApplySettings() end)
    row7:AddWidget(surgeCDPicker, 0.5)
    table_insert(allWidgets, surgeCDPicker)
    card3:AddRow(row7, 36)

    local row8 = GUIFrame:CreateRow(card3.content, 36)
    local swPicker = GUIFrame:CreateColorPicker(row8, "Second Wind",
        db.Colors.SecondWind or { 0.3, 0.7, 1, 1 },
        function(r, g, b, a) db.Colors.SecondWind = { r, g, b, a }; ApplySettings() end)
    row8:AddWidget(swPicker, 0.5)
    table_insert(allWidgets, swPicker)
    local swCDPicker = GUIFrame:CreateColorPicker(row8, "Second Wind (CD)",
        db.Colors.SecondWindCD or { 0.3, 0.3, 0.3, 1 },
        function(r, g, b, a) db.Colors.SecondWindCD = { r, g, b, a }; ApplySettings() end)
    row8:AddWidget(swCDPicker, 0.5)
    table_insert(allWidgets, swCDPicker)
    card3:AddRow(row8, 36)

    yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 4: Position Settings
    ----------------------------------------------------------------
    local card4, newOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
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

    if card4.positionWidgets then
        for _, widget in ipairs(card4.positionWidgets) do
            table_insert(allWidgets, widget)
        end
    end
    table_insert(allWidgets, card4)

    yOffset = newOffset

    UpdateAllWidgetStates()
    yOffset = yOffset - Theme.paddingSmall
    return yOffset
end)
