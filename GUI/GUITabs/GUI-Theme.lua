-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-Theme.lua                                           ║
-- ║  GUI: Addon Theme                                        ║
-- ║  Purpose: Configuration panel for addon theme —          ║
-- ║  presets, class color, custom colors.                    ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local CreateFrame = CreateFrame

GUIFrame:RegisterContent("Theme", function(scrollChild, yOffset)
    local db = KE.db and KE.db.global and KE.db.global.Theme
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local manager = GUIFrame:CreateWidgetStateManager()
    local currentMode = db.Mode or "preset"
    local presetSelector

    manager:SetCondition("preset", function() return currentMode == "preset" end)
    manager:SetCondition("class", function() return currentMode == "class" end)
    manager:SetCondition("custom", function() return currentMode == "custom" end)

    local function RefreshStates()
        manager:UpdateAll(true)
        if presetSelector then presetSelector:SetEnabled(currentMode == "preset") end
    end

    ----------------------------------------------------------------
    -- Card 1: Theme Mode
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Theme Mode", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local modeDropdown = GUIFrame:CreateDropdown(row1, "Color Mode", {
        options = KE.ThemeModeOptions,
        value = currentMode,
        callback = function(key)
            currentMode = key
            KE:SetThemeMode(key)
            RefreshStates()
        end,
    })
    row1:AddWidget(modeDropdown, 0.5)
    card1:AddRow(row1, Theme.rowHeightLast, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Preset Themes
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Preset Themes", yOffset)
    manager:Register(card2, "preset")

    presetSelector = GUIFrame:CreatePresetSwatches(card2.content, {
        value = db.Preset or "KitnUI",
        callback = function(presetName)
            KE:SetThemePreset(presetName)
        end,
    })
    local selectorHeight = presetSelector:GetHeight() + 4
    local row2 = GUIFrame:CreateRow(card2.content, selectorHeight)
    presetSelector:SetParent(row2)
    presetSelector:SetPoint("TOPLEFT", row2, "TOPLEFT", 0, 0)
    presetSelector:SetPoint("TOPRIGHT", row2, "TOPRIGHT", 0, 0)
    card2:AddRow(row2, selectorHeight, 0)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Class Color Info
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Class Color", yOffset)
    manager:Register(card3, "class")

    local row3 = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local classColor = KE:GetPlayerClassColor()

    local classSwatchFrame = CreateFrame("Frame", nil, row3, "BackdropTemplate")
    classSwatchFrame:SetSize(24, 24)
    classSwatchFrame:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 1,
    })
    classSwatchFrame:SetBackdropColor(classColor[1], classColor[2], classColor[3], 1)
    classSwatchFrame:SetBackdropBorderColor(0, 0, 0, 1)
    row3:AddWidget(classSwatchFrame, 0.1)

    local classLabel = GUIFrame:CreateText(row3,
        "Your class color will be used as the theme accent.",
        "Background colors remain dark.",
        Theme.rowHeightLast, "hide")
    row3:AddWidget(classLabel, 0.9)
    card3:AddRow(row3, Theme.rowHeightLast, 0)

    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Custom Colors
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Custom Colors", yOffset)
    manager:Register(card4, "custom")

    local row4a = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local accentPicker = GUIFrame:CreateColorPicker(row4a, "Accent Color", {
        color = (db.Custom and db.Custom.accent) or KE.ThemeDefaults.accent,
        callback = function(r, g, b, a) KE:SetCustomColor("accent", r, g, b, a) end,
    })
    row4a:AddWidget(accentPicker, 0.5)
    manager:Register(accentPicker, "custom")

    local accentDimPicker = GUIFrame:CreateColorPicker(row4a, "Accent Dim", {
        color = (db.Custom and db.Custom.accentDim) or KE.ThemeDefaults.accentDim,
        callback = function(r, g, b, a) KE:SetCustomColor("accentDim", r, g, b, a) end,
    })
    row4a:AddWidget(accentDimPicker, 0.5)
    manager:Register(accentDimPicker, "custom")
    card4:AddRow(row4a, Theme.rowHeight)

    local row4b = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local selectedBgPicker = GUIFrame:CreateColorPicker(row4b, "Selected Background", {
        color = (db.Custom and db.Custom.selectedBg) or KE.ThemeDefaults.selectedBg,
        callback = function(r, g, b, a) KE:SetCustomColor("selectedBg", r, g, b, a) end,
    })
    row4b:AddWidget(selectedBgPicker, 0.5)
    manager:Register(selectedBgPicker, "custom")

    local selectedTextPicker = GUIFrame:CreateColorPicker(row4b, "Selected Text", {
        color = (db.Custom and db.Custom.selectedText) or KE.ThemeDefaults.selectedText,
        callback = function(r, g, b, a) KE:SetCustomColor("selectedText", r, g, b, a) end,
    })
    row4b:AddWidget(selectedTextPicker, 0.5)
    manager:Register(selectedTextPicker, "custom")
    card4:AddRow(row4b, Theme.rowHeight)

    local row4sep = GUIFrame:CreateRow(card4.content, Theme.rowHeightSeparator)
    local sep = GUIFrame:CreateSeparator(row4sep)
    row4sep:AddWidget(sep, 1)
    card4:AddRow(row4sep, Theme.rowHeightSeparator)

    local row4c = GUIFrame:CreateRow(card4.content, Theme.rowHeightLast)
    local copyBtn = GUIFrame:CreateButton(row4c, "Copy From Current Preset", {
        callback = function()
            KE:CopyPresetToCustom()
            KE:RefreshTheme()
        end,
    })
    row4c:AddWidget(copyBtn, 0.5)
    manager:Register(copyBtn, "custom")

    local resetBtn = GUIFrame:CreateButton(row4c, "Reset Theme", {
        callback = function()
            KE:ResetTheme()
        end,
    })
    row4c:AddWidget(resetBtn, 0.5)
    manager:Register(resetBtn, "custom")
    card4:AddRow(row4c, Theme.rowHeightLast, 0)

    yOffset = card4:GetNextOffset()

    RefreshStates()
    return yOffset
end)
