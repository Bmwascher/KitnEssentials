-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)

local table_insert = table.insert
local pairs, ipairs = pairs, ipairs

local function GetModule()
    return KitnEssentials:GetModule("StasisTracker", true)
end

GUIFrame:RegisterContent("StasisTracker", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.StasisTracker
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return yOffset + errorCard:GetContentHeight() + Theme.paddingMedium
    end

    local ST = GetModule()
    local allWidgets = {}

    local function ApplySettings()
        if ST and ST.ApplySettings then ST:ApplySettings() end
    end

    local function ApplyPosition()
        if ST and ST.ApplyPosition then ST:ApplyPosition() end
    end

    local function ApplyModuleState(enabled)
        if not ST then return end
        ST.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("StasisTracker")
        else
            KitnEssentials:DisableModule("StasisTracker")
        end
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
    local card1 = GUIFrame:CreateCard(scrollChild, "Stasis Tracker", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Stasis Tracker", db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            UpdateAllWidgetStates()
        end,
        true, "Stasis Tracker", "On", "Off"
    )
    row1:AddWidget(enableCheck, 0.5)
    card1:AddRow(row1, 36)

    -- Note
    local noteHeight = 50
    local noteRow = GUIFrame:CreateRow(card1.content, noteHeight)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Preservation Evoker only.\n" .. KE:ColorTextByTheme("-") .. " Shows stored spell icons and a 30-second countdown bar during Stasis.",
        noteHeight, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, noteHeight)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 2: Display Settings
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Display Settings", yOffset)
    table_insert(allWidgets, card2)

    -- Icon Size + Icon Spacing
    local row2a = GUIFrame:CreateRow(card2.content, 40)
    local iconSizeSlider = GUIFrame:CreateSlider(row2a, "Icon Size", 20, 60, 1,
        db.IconSize or 40, nil,
        function(val)
            db.IconSize = val
            ApplySettings()
        end)
    row2a:AddWidget(iconSizeSlider, 0.5)
    table_insert(allWidgets, iconSizeSlider)

    local iconSpacingSlider = GUIFrame:CreateSlider(row2a, "Icon Spacing", -5, 10, 1,
        db.IconSpacing or 2, nil,
        function(val)
            db.IconSpacing = val
            ApplySettings()
        end)
    row2a:AddWidget(iconSpacingSlider, 0.5)
    table_insert(allWidgets, iconSpacingSlider)
    card2:AddRow(row2a, 40)

    -- Growth Direction + Bar Side
    local row2b = GUIFrame:CreateRow(card2.content, 40)
    local growthList = {
        { key = "Horizontal", text = "Horizontal" },
        { key = "Vertical",   text = "Vertical" },
    }
    local growthDropdown = GUIFrame:CreateDropdown(row2b, "Growth Direction", growthList,
        db.GrowthDirection or "Horizontal", 60,
        function(key)
            db.GrowthDirection = key
            ApplySettings()
        end)
    row2b:AddWidget(growthDropdown, 0.5)
    table_insert(allWidgets, growthDropdown)

    local barSideList = {
        { key = "start", text = "Top / Left" },
        { key = "end",   text = "Bottom / Right" },
    }
    local barSideDropdown = GUIFrame:CreateDropdown(row2b, "Bar Side", barSideList,
        db.BarSide or "start", 60,
        function(key)
            db.BarSide = key
            ApplySettings()
        end)
    row2b:AddWidget(barSideDropdown, 0.5)
    table_insert(allWidgets, barSideDropdown)
    card2:AddRow(row2b, 40)

    -- Bar Height
    local row2c = GUIFrame:CreateRow(card2.content, 40)
    local barHeightSlider = GUIFrame:CreateSlider(row2c, "Bar Height", 5, 30, 1,
        db.BarHeight or 15, nil,
        function(val)
            db.BarHeight = val
            ApplySettings()
        end)
    row2c:AddWidget(barHeightSlider, 1)
    table_insert(allWidgets, barHeightSlider)
    card2:AddRow(row2c, 40)

    yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 3: Position
    ----------------------------------------------------------------
    local card3, newOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Position Settings",
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
    -- Card 4: Font Settings (countdown text)
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Font Settings", yOffset)
    table_insert(allWidgets, card4)

    local fontList = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do fontList[name] = name end
    else
        fontList["Friz Quadrata TT"] = "Friz Quadrata TT"
    end

    local row4a = GUIFrame:CreateRow(card4.content, 40)
    local fontDropdown = GUIFrame:CreateDropdown(row4a, "Font", fontList,
        db.FontFace or "Expressway", 30,
        function(key)
            db.FontFace = key
            ApplySettings()
        end)
    row4a:AddWidget(fontDropdown, 0.5)
    table_insert(allWidgets, fontDropdown)

    local fontSizeSlider = GUIFrame:CreateSlider(row4a, "Font Size", 8, 36, 1,
        db.FontSize or 14, nil,
        function(val)
            db.FontSize = val
            ApplySettings()
        end)
    row4a:AddWidget(fontSizeSlider, 0.5)
    table_insert(allWidgets, fontSizeSlider)
    card4:AddRow(row4a, 40)

    local row4b = GUIFrame:CreateRow(card4.content, 37)
    local outlineList = {
        { key = "NONE",         text = "None" },
        { key = "OUTLINE",      text = "Outline" },
        { key = "THICKOUTLINE", text = "Thick" },
        { key = "SOFTOUTLINE",  text = "Soft" },
    }
    local outlineDropdown = GUIFrame:CreateDropdown(row4b, "Outline", outlineList,
        db.FontOutline or "OUTLINE", 45,
        function(key)
            db.FontOutline = key
            ApplySettings()
        end)
    row4b:AddWidget(outlineDropdown, 1)
    table_insert(allWidgets, outlineDropdown)
    card4:AddRow(row4b, 37)

    yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 5: Colors
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    table_insert(allWidgets, card5)

    local customColorWidgets = {}

    local row5a = GUIFrame:CreateRow(card5.content, 40)
    local colorModeDropdown = GUIFrame:CreateDropdown(row5a, "Color Mode", KE.ColorModeOptions,
        db.ColorMode or "custom", 70,
        function(key)
            db.ColorMode = key
            ApplySettings()
            local isCustom = key == "custom"
            for _, w in ipairs(customColorWidgets) do
                if w.SetEnabled then w:SetEnabled(isCustom) end
            end
        end)
    row5a:AddWidget(colorModeDropdown, 0.5)
    table_insert(allWidgets, colorModeDropdown)

    local colorPicker = GUIFrame:CreateColorPicker(row5a, "Custom Color",
        db.Color or { 0.2, 0.5, 0.4, 1 },
        function(r, g, b, a)
            db.Color = { r, g, b, a }
            ApplySettings()
        end)
    row5a:AddWidget(colorPicker, 0.5)
    table_insert(allWidgets, colorPicker)
    table_insert(customColorWidgets, colorPicker)
    card5:AddRow(row5a, 40)

    -- Bar background + texture
    local statusbarList = {}
    if LSM then
        for name in pairs(LSM:HashTable("statusbar")) do statusbarList[name] = name end
    else
        statusbarList["Blizzard"] = "Blizzard"
    end

    local row5b = GUIFrame:CreateRow(card5.content, 40)
    local bgColorPicker = GUIFrame:CreateColorPicker(row5b, "Bar Background",
        db.BarBackgroundColor or { 0, 0, 0, 0.8 },
        function(r, g, b, a)
            db.BarBackgroundColor = { r, g, b, a }
            ApplySettings()
        end)
    row5b:AddWidget(bgColorPicker, 0.5)
    table_insert(allWidgets, bgColorPicker)

    local barTextureDropdown = GUIFrame:CreateDropdown(row5b, "Bar Texture", statusbarList,
        db.BarTexture or "KitnUI", 70,
        function(key)
            db.BarTexture = key
            ApplySettings()
        end)
    row5b:AddWidget(barTextureDropdown, 0.5)
    table_insert(allWidgets, barTextureDropdown)
    card5:AddRow(row5b, 40)

    yOffset = yOffset + card5:GetContentHeight() + Theme.paddingSmall

    -- Apply initial widget states
    UpdateAllWidgetStates()
    if (db.ColorMode or "custom") ~= "custom" then
        for _, w in ipairs(customColorWidgets) do
            if w.SetEnabled then w:SetEnabled(false) end
        end
    end
    yOffset = yOffset - (Theme.paddingSmall * 2)
    return yOffset
end)
