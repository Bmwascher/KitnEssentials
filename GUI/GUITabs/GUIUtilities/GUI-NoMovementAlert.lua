-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)
local table_insert = table.insert

GUIFrame:RegisterContent("NoMovementAlert", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.NoMovementAlert
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return yOffset + errorCard:GetContentHeight() + Theme.paddingMedium
    end

    local allWidgets = {}

    local function ApplySettings()
        if KitnEssentials then
            local mod = KitnEssentials:GetModule("NoMovementAlert", true)
            if mod and mod.ApplySettings then mod:ApplySettings() end
        end
    end

    local function ApplyModuleState(enabled)
        if not KitnEssentials then return end
        local mod = KitnEssentials:GetModule("NoMovementAlert", true)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("NoMovementAlert")
        else
            KitnEssentials:DisableModule("NoMovementAlert")
        end
    end

    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false
        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then widget:SetEnabled(mainEnabled) end
        end
    end

    ----------------------------------------------------------------
    -- Card 1: No Movement Alert (Enable)
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "No Movement Alert", yOffset)

    local row1a = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1a, "Enable No Movement Alert", db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            UpdateAllWidgetStates()
        end,
        true, "No Movement Alert", "On", "Off"
    )
    row1a:AddWidget(enableCheck, 1)
    card1:AddRow(row1a, 36)

    local a = Theme.accent
    local accentDash = string.format("|cff%02x%02x%02x—|r", a[1]*255, a[2]*255, a[3]*255)
    local noteHeight = 50
    local noteRow = GUIFrame:CreateRow(card1.content, noteHeight)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Shows remaining cooldown when your movement ability is unavailable.\n" .. KE:ColorTextByTheme("-") .. " Supports all classes. Auto-detects your highest priority movement spell.",
        noteHeight, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, noteHeight)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 2: Alert Settings
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Alert Settings", yOffset)
    table_insert(allWidgets, card2)

    -- Display Format
    local row2a = GUIFrame:CreateRow(card2.content, 40)
    local formatBox = GUIFrame:CreateEditBox(row2a, "Display Format", db.DisplayFormat or "NO %n (%t)",
        function(text)
            db.DisplayFormat = text
            ApplySettings()
        end)
    row2a:AddWidget(formatBox, 1)
    table_insert(allWidgets, formatBox)
    card2:AddRow(row2a, 40)

    card2:AddLabel(accentDash .. " |cff888888%n = spell name, %t = remaining time.|r")

    -- Max Cooldown threshold
    local row2b = GUIFrame:CreateRow(card2.content, 40)
    local maxCDSlider = GUIFrame:CreateSlider(row2b, "Max Cooldown", 5, 120, 1, db.MaxCooldown or 30, 60,
        function(val)
            db.MaxCooldown = val
        end)
    row2b:AddWidget(maxCDSlider, 1)
    table_insert(allWidgets, maxCDSlider)
    card2:AddRow(row2b, 40)

    card2:AddLabel(accentDash .. " |cff888888Only show alert when the spell's total cooldown is under this threshold (seconds).|r")

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
        onChangeCallback = ApplySettings,
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

    local fontList = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do fontList[name] = name end
    else
        fontList["Friz Quadrata TT"] = "Friz Quadrata TT"
    end

    local row4a = GUIFrame:CreateRow(card4.content, 40)
    local fontDropdown = GUIFrame:CreateDropdown(row4a, "Font", fontList, db.FontFace or "Expressway", 30,
        function(key)
            db.FontFace = key
            ApplySettings()
        end)
    row4a:AddWidget(fontDropdown, 0.5)
    table_insert(allWidgets, fontDropdown)

    local fontSizeSlider = GUIFrame:CreateSlider(row4a, "Font Size", 8, 72, 1, db.FontSize or 24, 60,
        function(val)
            db.FontSize = val
            ApplySettings()
        end)
    row4a:AddWidget(fontSizeSlider, 0.5)
    table_insert(allWidgets, fontSizeSlider)
    card4:AddRow(row4a, 40)

    local row4b = GUIFrame:CreateRow(card4.content, 37)
    local outlineList = {
        { key = "NONE", text = "None" },
        { key = "OUTLINE", text = "Outline" },
        { key = "THICKOUTLINE", text = "Thick" },
        { key = "SOFTOUTLINE", text = "Soft" },
    }
    local outlineDropdown = GUIFrame:CreateDropdown(row4b, "Outline", outlineList, db.FontOutline or "OUTLINE", 45,
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

    local colorPicker = GUIFrame:CreateColorPicker(row5a, "Custom Color", db.Color or { 1, 0.2, 0.2, 1 },
        function(r, g, b, a2)
            db.Color = { r, g, b, a2 }
            ApplySettings()
        end)
    row5a:AddWidget(colorPicker, 0.5)
    table_insert(allWidgets, colorPicker)
    table_insert(customColorWidgets, colorPicker)
    card5:AddRow(row5a, 40)

    if (db.ColorMode or "custom") ~= "custom" then
        for _, w in ipairs(customColorWidgets) do
            if w.SetEnabled then w:SetEnabled(false) end
        end
    end

    yOffset = yOffset + card5:GetContentHeight() + Theme.paddingSmall

    UpdateAllWidgetStates()
    yOffset = yOffset - (Theme.paddingSmall * 3)
    return yOffset
end)
