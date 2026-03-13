-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)

-- Localization
local table_insert = table.insert
local pairs, ipairs = pairs, ipairs

-- Helper to get module
local function GetModule()
    return KitnEssentials:GetModule("RangeChecker", true)
end

-- Range Checker Tab Content
GUIFrame:RegisterContent("RangeChecker", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.RangeChecker
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
            KitnEssentials:EnableModule("RangeChecker")
        else
            KitnEssentials:DisableModule("RangeChecker")
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
    -- Card 1: Range Checker Text (Enable)
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Range Checker Text", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Range Checker Text", db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            UpdateAllWidgetStates()
        end,
        true, "Range Checker Text", "On", "Off"
    )
    row1:AddWidget(enableCheck, 0.5)
    card1:AddRow(row1, 36)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 2: General Settings
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "General Settings", yOffset)
    table_insert(allWidgets, card2)

    local row2a = GUIFrame:CreateRow(card2.content, 40)
    local combatOnlyCheck = GUIFrame:CreateCheckbox(row2a, "Show In Combat Only", db.CombatOnly ~= false,
        function(checked)
            db.CombatOnly = checked
            ApplySettings()
        end)
    row2a:AddWidget(combatOnlyCheck, 0.5)
    table_insert(allWidgets, combatOnlyCheck)
    card2:AddRow(row2a, 40)

    -- Separator
    local rowSep1 = GUIFrame:CreateRow(card2.content, 8)
    local sep1 = GUIFrame:CreateSeparator(rowSep1)
    rowSep1:AddWidget(sep1, 1)
    card2:AddRow(rowSep1, 8)

    -- Update Throttle
    local row2b = GUIFrame:CreateRow(card2.content, 36)
    local throttleSlider = GUIFrame:CreateSlider(row2b, "Update Throttle", 0, 1, 0.05,
        db.UpdateThrottle or 0.1, nil,
        function(val)
            db.UpdateThrottle = val
            ApplySettings()
        end)
    row2b:AddWidget(throttleSlider, 1)
    table_insert(allWidgets, throttleSlider)
    card2:AddRow(row2b, 36)

    yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 3: Position Settings
    ----------------------------------------------------------------
    local card3, newOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
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
    yOffset = newOffset

    ----------------------------------------------------------------
    -- Card 4: Font Settings
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Font Settings", yOffset)
    table_insert(allWidgets, card4)

    -- Font lookup
    local fontList = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do fontList[name] = name end
    else
        fontList["Friz Quadrata TT"] = "Friz Quadrata TT"
    end

    -- Font Face + Font Size
    local row4a = GUIFrame:CreateRow(card4.content, 40)
    local fontDropdown = GUIFrame:CreateDropdown(row4a, "Font", fontList,
        db.FontFace or "Expressway", 30,
        function(key)
            db.FontFace = key
            ApplySettings()
        end)
    row4a:AddWidget(fontDropdown, 0.5)
    table_insert(allWidgets, fontDropdown)

    local fontSizeSlider = GUIFrame:CreateSlider(row4a, "Font Size", 8, 72, 1,
        db.FontSize or 24, nil,
        function(val)
            db.FontSize = val
            ApplySettings()
        end)
    row4a:AddWidget(fontSizeSlider, 0.5)
    table_insert(allWidgets, fontSizeSlider)
    card4:AddRow(row4a, 40)

    -- Font Outline
    local row4b = GUIFrame:CreateRow(card4.content, 37)
    local outlineList = {
        { key = "NONE",         text = "None" },
        { key = "OUTLINE",      text = "Outline" },
        { key = "THICKOUTLINE", text = "Thick" },
        { key = "SOFTOUTLINE",  text = "Soft" },
    }
    local outlineDropdown = GUIFrame:CreateDropdown(row4b, "Outline", outlineList,
        db.FontOutline or "SOFTOUTLINE", 45,
        function(key)
            db.FontOutline = key
            ApplySettings()
        end)
    row4b:AddWidget(outlineDropdown, 1)
    table_insert(allWidgets, outlineDropdown)
    card4:AddRow(row4b, 37)

    yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 5: Color Settings
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Color Settings", yOffset)
    table_insert(allWidgets, card5)

    -- 40+ Yards
    local row5a = GUIFrame:CreateRow(card5.content, 38)
    local colorOnePicker = GUIFrame:CreateColorPicker(row5a, "40+ Yards",
        db.ColorOne or { 1, 0, 0, 1 },
        function(r, g, b, a)
            db.ColorOne = { r, g, b, a }
            ApplySettings()
        end)
    row5a:AddWidget(colorOnePicker, 0.5)
    table_insert(allWidgets, colorOnePicker)
    card5:AddRow(row5a, 38)

    -- 20-40 Yards
    local row5b = GUIFrame:CreateRow(card5.content, 38)
    local colorTwoPicker = GUIFrame:CreateColorPicker(row5b, "20-40 Yards",
        db.ColorTwo or { 1, 0.42, 0, 1 },
        function(r, g, b, a)
            db.ColorTwo = { r, g, b, a }
            ApplySettings()
        end)
    row5b:AddWidget(colorTwoPicker, 0.5)
    table_insert(allWidgets, colorTwoPicker)
    card5:AddRow(row5b, 38)

    -- 10-20 Yards
    local row5c = GUIFrame:CreateRow(card5.content, 38)
    local colorThreePicker = GUIFrame:CreateColorPicker(row5c, "10-20 Yards",
        db.ColorThree or { 1, 0.82, 0, 1 },
        function(r, g, b, a)
            db.ColorThree = { r, g, b, a }
            ApplySettings()
        end)
    row5c:AddWidget(colorThreePicker, 0.5)
    table_insert(allWidgets, colorThreePicker)
    card5:AddRow(row5c, 38)

    -- 0-10 Yards
    local row5d = GUIFrame:CreateRow(card5.content, 38)
    local colorFourPicker = GUIFrame:CreateColorPicker(row5d, "0-10 Yards",
        db.ColorFour or { 0, 1, 0, 1 },
        function(r, g, b, a)
            db.ColorFour = { r, g, b, a }
            ApplySettings()
        end)
    row5d:AddWidget(colorFourPicker, 0.5)
    table_insert(allWidgets, colorFourPicker)
    card5:AddRow(row5d, 38)

    yOffset = yOffset + card5:GetContentHeight() + Theme.paddingSmall

    -- Apply initial widget states
    UpdateAllWidgetStates()
    yOffset = yOffset - (Theme.paddingSmall * 2)
    return yOffset
end)
