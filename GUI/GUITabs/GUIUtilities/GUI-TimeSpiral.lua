-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-TimeSpiral.lua                                      ║
-- ║  GUI: Time Spiral Tracker                                ║
-- ║  Purpose: Configuration panel for the TimeSpiral module. ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)

local table_insert = table.insert
local pairs, ipairs = pairs, ipairs

local function GetModule()
    return KitnEssentials:GetModule("TimeSpiral", true)
end

-- Time Spiral Tab Content
GUIFrame:RegisterContent("TimeSpiral", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.TimeSpiral
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return yOffset + errorCard:GetContentHeight() + Theme.paddingMedium
    end

    local TSP = GetModule()
    local allWidgets = {}
    local glowWidgets = {}
    local textWidgets = {}
    local timerWidgets = {}

    local function ApplySettings()
        if TSP and TSP.ApplySettings then
            TSP:ApplySettings()
        end
    end

    local function ApplyPosition()
        if TSP and TSP.ApplyPosition then
            TSP:ApplyPosition()
        end
    end

    local function ApplyModuleState(enabled)
        if not TSP then return end
        TSP.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("TimeSpiral")
        else
            KitnEssentials:DisableModule("TimeSpiral")
        end
    end

    local function UpdateGlowWidgetStates()
        local glowEnabled = db.GlowEnabled ~= false
        for _, widget in ipairs(glowWidgets) do
            if widget.SetEnabled then
                widget:SetEnabled(glowEnabled)
            end
        end
    end

    local function UpdateTextWidgetStates()
        local textEnabled = db.ShowText ~= false
        for _, widget in ipairs(textWidgets) do
            if widget.SetEnabled then
                widget:SetEnabled(textEnabled)
            end
        end
    end

    local function UpdateTimerWidgetStates()
        local timerEnabled = db.ShowTimer ~= false
        for _, widget in ipairs(timerWidgets) do
            if widget.SetEnabled then
                widget:SetEnabled(timerEnabled)
            end
        end
    end

    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false

        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then
                widget:SetEnabled(mainEnabled)
            end
        end

        -- Update sub-toggles only if main is enabled
        if mainEnabled then
            UpdateGlowWidgetStates()
            UpdateTextWidgetStates()
            UpdateTimerWidgetStates()
        end
    end

    ---------------------------------------------------------------------------------
    -- Card 1: Time Spiral Enable
    ---------------------------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Time Spiral Tracker", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Time Spiral Tracker", db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            UpdateAllWidgetStates()
        end,
        true, "Time Spiral Tracker", "On", "Off"
    )
    row1:AddWidget(enableCheck, 0.5)
    card1:AddRow(row1, 36)

    -- Note
    local noteHeight = 50
    local noteRow = GUIFrame:CreateRow(card1.content, noteHeight)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Works for all classes. Tracks when your movement ability is\n  available for free use from the Time Spiral buff.",
        noteHeight, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, noteHeight)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 2: Display & Glow Settings
    ---------------------------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Display & Glow Settings", yOffset)
    table_insert(allWidgets, card2)

    -- Icon Size Slider
    local row2a = GUIFrame:CreateRow(card2.content, 40)
    local iconSizeSlider = GUIFrame:CreateSlider(row2a, "Icon Size", 20, 100, 1,
        db.IconSize or 40, nil,
        function(val)
            db.IconSize = val
            ApplySettings()
        end)
    row2a:AddWidget(iconSizeSlider, 1)
    table_insert(allWidgets, iconSizeSlider)
    card2:AddRow(row2a, 40)

    -- Separator
    local rowSep1 = GUIFrame:CreateRow(card2.content, 8)
    local sep1 = GUIFrame:CreateSeparator(rowSep1)
    rowSep1:AddWidget(sep1, 1)
    table_insert(allWidgets, sep1)
    card2:AddRow(rowSep1, 8)

    -- Enable Glow Checkbox
    local row2b = GUIFrame:CreateRow(card2.content, 40)
    local enableGlowCheck = GUIFrame:CreateCheckbox(row2b, "Enable Glow Effect", db.GlowEnabled ~= false,
        function(checked)
            db.GlowEnabled = checked
            UpdateGlowWidgetStates()
            ApplySettings()
        end)
    row2b:AddWidget(enableGlowCheck, 0.5)
    table_insert(allWidgets, enableGlowCheck)
    card2:AddRow(row2b, 40)

    -- Glow Type Dropdown and Glow Color Picker
    local row2c = GUIFrame:CreateRow(card2.content, 36)
    local glowTypeList = {
        { key = "pixel",    text = "Pixel Border" },
        { key = "autocast", text = "Auto Cast" },
        { key = "button",   text = "Button Glow" },
        { key = "proc",     text = "Proc Glow" },
    }
    local glowTypeDropdown = GUIFrame:CreateDropdown(row2c, "Glow Type", glowTypeList, db.GlowType or "proc", 45,
        function(key)
            db.GlowType = key
            ApplySettings()
        end)
    row2c:AddWidget(glowTypeDropdown, 0.5)
    table_insert(allWidgets, glowTypeDropdown)
    table_insert(glowWidgets, glowTypeDropdown)

    local glowColorPicker = GUIFrame:CreateColorPicker(row2c, "Glow Color",
        db.GlowColor or { 0, 1, 0, 1 },
        function(r, g, b, a)
            db.GlowColor = { r, g, b, a }
            ApplySettings()
        end)
    row2c:AddWidget(glowColorPicker, 0.5)
    table_insert(allWidgets, glowColorPicker)
    table_insert(glowWidgets, glowColorPicker)
    card2:AddRow(row2c, 36)

    yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 3: Position Settings
    ---------------------------------------------------------------------------------
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

    -- Font lookup (shared by label and timer cards)
    local fontList = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do fontList[name] = name end
    else
        fontList["Friz Quadrata TT"] = "Friz Quadrata TT"
    end

    ---------------------------------------------------------------------------------
    -- Card 4: Label Text
    ---------------------------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Label Text", yOffset)
    table_insert(allWidgets, card4)

    -- Show Text Checkbox and Text Color Picker
    local row4a = GUIFrame:CreateRow(card4.content, 40)
    local showTextCheck = GUIFrame:CreateCheckbox(row4a, "Show Text Label", db.ShowText ~= false,
        function(checked)
            db.ShowText = checked
            UpdateTextWidgetStates()
            ApplySettings()
        end)
    row4a:AddWidget(showTextCheck, 0.5)
    table_insert(allWidgets, showTextCheck)

    local textColorPicker = GUIFrame:CreateColorPicker(row4a, "Text Color",
        db.TextColor or { 0, 1, 0, 1 },
        function(r, g, b, a)
            db.TextColor = { r, g, b, a }
            ApplySettings()
        end)
    row4a:AddWidget(textColorPicker, 0.5)
    table_insert(allWidgets, textColorPicker)
    table_insert(textWidgets, textColorPicker)
    card4:AddRow(row4a, 40)

    -- Text Label EditBox
    local row4b = GUIFrame:CreateRow(card4.content, 40)
    local textLabelEdit = GUIFrame:CreateEditBox(row4b, "Text Label", db.TextLabel or "FREE",
        function(text)
            db.TextLabel = text
            ApplySettings()
        end)
    row4b:AddWidget(textLabelEdit, 1)
    table_insert(allWidgets, textLabelEdit)
    table_insert(textWidgets, textLabelEdit)
    card4:AddRow(row4b, 40)

    -- Separator
    local row4sep = GUIFrame:CreateRow(card4.content, 8)
    local sep4 = GUIFrame:CreateSeparator(row4sep)
    row4sep:AddWidget(sep4, 1)
    table_insert(allWidgets, sep4)
    table_insert(textWidgets, sep4)
    card4:AddRow(row4sep, 8)

    -- Font Face + Font Size
    local row4c = GUIFrame:CreateRow(card4.content, 40)
    local fontDropdown = GUIFrame:CreateDropdown(row4c, "Font", fontList,
        db.FontFace or "Expressway", 30,
        function(key)
            db.FontFace = key
            ApplySettings()
        end)
    row4c:AddWidget(fontDropdown, 0.5)
    table_insert(allWidgets, fontDropdown)
    table_insert(textWidgets, fontDropdown)

    local fontSizeSlider = GUIFrame:CreateSlider(row4c, "Font Size", 8, 36, 1,
        db.FontSize or 14, nil,
        function(val)
            db.FontSize = val
            ApplySettings()
        end)
    row4c:AddWidget(fontSizeSlider, 0.5)
    table_insert(allWidgets, fontSizeSlider)
    table_insert(textWidgets, fontSizeSlider)
    card4:AddRow(row4c, 40)

    -- Font Outline Dropdown
    local row4d = GUIFrame:CreateRow(card4.content, 37)
    local outlineList = {
        { key = "NONE",         text = "None" },
        { key = "OUTLINE",      text = "Outline" },
        { key = "THICKOUTLINE", text = "Thick" },
        { key = "SOFTOUTLINE",  text = "Soft" },
    }
    local outlineDropdown = GUIFrame:CreateDropdown(row4d, "Outline", outlineList,
        db.FontOutline or "SOFTOUTLINE", 45,
        function(key)
            db.FontOutline = key
            ApplySettings()
        end)
    row4d:AddWidget(outlineDropdown, 1)
    table_insert(allWidgets, outlineDropdown)
    table_insert(textWidgets, outlineDropdown)
    card4:AddRow(row4d, 37)

    yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 5: Timer Settings (countdown on icon)
    ---------------------------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Timer Settings", yOffset)
    table_insert(allWidgets, card5)

    -- Show Timer Checkbox and Timer Color Picker
    local row5ta = GUIFrame:CreateRow(card5.content, 40)
    local showTimerCheck = GUIFrame:CreateCheckbox(row5ta, "Show Countdown Timer", db.ShowTimer ~= false,
        function(checked)
            db.ShowTimer = checked
            UpdateTimerWidgetStates()
            ApplySettings()
        end)
    row5ta:AddWidget(showTimerCheck, 0.5)
    table_insert(allWidgets, showTimerCheck)

    local timerColorPicker = GUIFrame:CreateColorPicker(row5ta, "Timer Color",
        db.TimerTextColor or { 1, 1, 1, 1 },
        function(r, g, b, a)
            db.TimerTextColor = { r, g, b, a }
            ApplySettings()
        end)
    row5ta:AddWidget(timerColorPicker, 0.5)
    table_insert(allWidgets, timerColorPicker)
    table_insert(timerWidgets, timerColorPicker)
    card5:AddRow(row5ta, 40)

    -- Separator
    local rowSepT = GUIFrame:CreateRow(card5.content, 8)
    local sepT = GUIFrame:CreateSeparator(rowSepT)
    rowSepT:AddWidget(sepT, 1)
    table_insert(allWidgets, sepT)
    table_insert(timerWidgets, sepT)
    card5:AddRow(rowSepT, 8)

    -- Timer Font + Size
    local row5tb = GUIFrame:CreateRow(card5.content, 40)
    local timerFontDropdown = GUIFrame:CreateDropdown(row5tb, "Font", fontList,
        db.TimerFontFace or "Expressway", 30,
        function(key)
            db.TimerFontFace = key
            ApplySettings()
        end)
    row5tb:AddWidget(timerFontDropdown, 0.5)
    table_insert(allWidgets, timerFontDropdown)
    table_insert(timerWidgets, timerFontDropdown)

    local timerFontSizeSlider = GUIFrame:CreateSlider(row5tb, "Font Size", 8, 36, 1,
        db.TimerFontSize or 16, nil,
        function(val)
            db.TimerFontSize = val
            ApplySettings()
        end)
    row5tb:AddWidget(timerFontSizeSlider, 0.5)
    table_insert(allWidgets, timerFontSizeSlider)
    table_insert(timerWidgets, timerFontSizeSlider)
    card5:AddRow(row5tb, 40)

    -- Timer Outline
    local row5tc = GUIFrame:CreateRow(card5.content, 37)
    local timerOutlineList = {
        { key = "NONE",         text = "None" },
        { key = "OUTLINE",      text = "Outline" },
        { key = "THICKOUTLINE", text = "Thick" },
        { key = "SOFTOUTLINE",  text = "Soft" },
    }
    local timerOutlineDropdown = GUIFrame:CreateDropdown(row5tc, "Outline", timerOutlineList,
        db.TimerFontOutline or "OUTLINE", 45,
        function(key)
            db.TimerFontOutline = key
            ApplySettings()
        end)
    row5tc:AddWidget(timerOutlineDropdown, 1)
    table_insert(allWidgets, timerOutlineDropdown)
    table_insert(timerWidgets, timerOutlineDropdown)
    card5:AddRow(row5tc, 37)

    yOffset = yOffset + card5:GetContentHeight() + Theme.paddingSmall

    -- Apply initial widget states
    UpdateAllWidgetStates()
    yOffset = yOffset - (Theme.paddingSmall * 2)
    return yOffset
end)
