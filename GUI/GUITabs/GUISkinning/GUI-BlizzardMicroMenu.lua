-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local table_insert = table.insert
local ipairs = ipairs

-- Helper to get MicroMenu module
local function GetMicroMenuModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("SkinBlizzardMicroMenu", true)
    end
    return nil
end

GUIFrame:RegisterContent("SkinMicroMenu", function(scrollChild, yOffset)
    if KE:ShouldNotLoadModule() then return end
    local db = KE.db and KE.db.profile.Skinning.MicroMenu
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return yOffset + errorCard:GetContentHeight() + Theme.paddingMedium
    end

    local MM = GetMicroMenuModule()

    -- Track widgets for enable/disable logic
    local allWidgets = {}
    local bgWidgets = {}
    local mouseOverWidgets = {}

    local function ApplySettings()
        if MM then MM:UpdateMicroBar() end
    end

    local function UpdateAlphaState()
        if MM then MM:UpdateAlpha() end
    end

    local function ApplyMicroMenuState(enabled)
        if not MM then return end
        MM.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("SkinBlizzardMicroMenu")
        else
            KitnEssentials:DisableModule("SkinBlizzardMicroMenu")
        end
    end

    -- Comprehensive widget state update
    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false
        local bgEnabled = db.ShowBackdrop ~= false
        local mouseOverEnabled = db.Mouseover and db.Mouseover.Enabled ~= false

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
            for _, widget in ipairs(mouseOverWidgets) do
                if widget.SetEnabled then
                    widget:SetEnabled(mouseOverEnabled)
                end
            end
        end
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Micro Menu Skinning", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Micro Menu Skinning", db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplyMicroMenuState(checked)
            UpdateAllWidgetStates()
            KE:CreateReloadPrompt("Enabling/Disabling this UI element requires a reload to take full effect.")
        end,
        true,
        "Micro Menu Skinning",
        "On",
        "Off"
    )
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, 36)

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
    -- Card 3: Mouseover Settings
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Mouseover Settings", yOffset)
    table_insert(allWidgets, card3)

    local mouseOverDB = db.Mouseover

    -- Enable mouseover
    local row2 = GUIFrame:CreateRow(card3.content, 40)
    local mouseOverEnableCheck = GUIFrame:CreateCheckbox(row2, "Enable Micro Menu Mouseover",
        mouseOverDB.Enabled ~= false,
        function(checked)
            mouseOverDB.Enabled = checked
            UpdateAlphaState()
            UpdateAllWidgetStates()
        end)
    row2:AddWidget(mouseOverEnableCheck, 0.5)
    table_insert(allWidgets, mouseOverEnableCheck)

    -- Alpha when not hovered
    local nonMouseoverAlpha = GUIFrame:CreateSlider(row2, "Alpha When No Mouseover", 0, 1, 0.1,
        mouseOverDB.Alpha, _,
        function(val)
            mouseOverDB.Alpha = val
            ApplySettings()
        end)
    row2:AddWidget(nonMouseoverAlpha, 0.5)
    table_insert(allWidgets, nonMouseoverAlpha)
    table_insert(mouseOverWidgets, nonMouseoverAlpha)

    card3:AddRow(row2, 40)

    -- Fade durations
    local row3 = GUIFrame:CreateRow(card3.content, 36)
    local fadeInSlider = GUIFrame:CreateSlider(row3, "Fade In Duration", 0, 10, 0.1,
        mouseOverDB.FadeInDuration, _,
        function(val)
            mouseOverDB.FadeInDuration = val
        end)
    row3:AddWidget(fadeInSlider, 0.5)
    table_insert(allWidgets, fadeInSlider)
    table_insert(mouseOverWidgets, fadeInSlider)

    local fadeOutSlider = GUIFrame:CreateSlider(row3, "Fade Out Duration", 0, 10, 0.1,
        mouseOverDB.FadeOutDuration, _,
        function(val)
            mouseOverDB.FadeOutDuration = val
        end)
    row3:AddWidget(fadeOutSlider, 0.5)
    table_insert(allWidgets, fadeOutSlider)
    table_insert(mouseOverWidgets, fadeOutSlider)

    card3:AddRow(row3, 36)

    yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 4: Button Settings
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Button Settings", yOffset)
    table_insert(allWidgets, card4)

    -- Width and Height
    local row4 = GUIFrame:CreateRow(card4.content, 40)
    local buttonWidthSlider = GUIFrame:CreateSlider(row4, "Button Width", 5, 50, 1,
        db.ButtonWidth, _,
        function(val)
            db.ButtonWidth = val
            ApplySettings()
        end)
    row4:AddWidget(buttonWidthSlider, 0.5)
    table_insert(allWidgets, buttonWidthSlider)

    local buttonHeightSlider = GUIFrame:CreateSlider(row4, "Button Height", 5, 50, 1,
        db.ButtonHeight, _,
        function(val)
            db.ButtonHeight = val
            ApplySettings()
        end)
    row4:AddWidget(buttonHeightSlider, 0.5)
    table_insert(allWidgets, buttonHeightSlider)
    card4:AddRow(row4, 40)

    -- Spacing
    local row5 = GUIFrame:CreateRow(card4.content, 39)
    local buttonSpacingSlider = GUIFrame:CreateSlider(row5, "Button Spacing", -20, 20, 1,
        db.ButtonSpacing, _,
        function(val)
            db.ButtonSpacing = val
            ApplySettings()
        end)
    row5:AddWidget(buttonSpacingSlider, 1)
    table_insert(allWidgets, buttonSpacingSlider)
    card4:AddRow(row5, 39)

    yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 5: Backdrop Settings
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Backdrop Settings", yOffset)
    table_insert(allWidgets, card5)

    -- Backdrop toggle
    local row6 = GUIFrame:CreateRow(card5.content, 39)
    local backdropCheck = GUIFrame:CreateCheckbox(row6, "Enable Backdrop", db.ShowBackdrop ~= false,
        function(checked)
            db.ShowBackdrop = checked
            ApplySettings()
            UpdateAllWidgetStates()
        end)
    row6:AddWidget(backdropCheck, 1)
    table_insert(allWidgets, backdropCheck)
    card5:AddRow(row6, 39)

    -- Backdrop color
    local row7 = GUIFrame:CreateRow(card5.content, 39)
    local backdropColor = GUIFrame:CreateColorPicker(row7, "Backdrop Color", db.BackdropColor,
        function(r, g, b, a)
            db.BackdropColor = { r, g, b, a }
            ApplySettings()
        end)
    row7:AddWidget(backdropColor, 1)
    table_insert(allWidgets, backdropColor)
    table_insert(bgWidgets, backdropColor)
    card5:AddRow(row7, 39)

    -- Border color
    local row8 = GUIFrame:CreateRow(card5.content, 39)
    local borderColor = GUIFrame:CreateColorPicker(row8, "Backdrop Border Color", db.BackdropBorderColor,
        function(r, g, b, a)
            db.BackdropBorderColor = { r, g, b, a }
            ApplySettings()
        end)
    row8:AddWidget(borderColor, 1)
    table_insert(allWidgets, borderColor)
    table_insert(bgWidgets, borderColor)
    card5:AddRow(row8, 39)

    yOffset = yOffset + card5:GetContentHeight() + Theme.paddingSmall

    -- Apply initial widget states
    UpdateAllWidgetStates()
    yOffset = yOffset - (Theme.paddingSmall * 4)
    return yOffset
end)
