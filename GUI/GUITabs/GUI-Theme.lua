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
local table_insert = table.insert
local ipairs = ipairs
local math_floor = math.floor

local function CreatePresetSelector(parent, presets, presetOrder, currentPreset, onSelect)
    local container = CreateFrame("Frame", nil, parent)
    local buttons = {}
    local buttonWidth = 110
    local buttonHeight = 36
    local maxColumns = 4
    local rowSpacing = 4
    local colSpacing = 6

    for _, presetName in ipairs(presetOrder) do
        local preset = presets[presetName]
        if not preset then break end

        local btn = CreateFrame("Button", nil, container, "BackdropTemplate")
        btn:SetSize(buttonWidth, buttonHeight)
        btn:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeSize = 1,
        })
        btn:SetBackdropColor(Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], 1)
        btn.presetName = presetName

        local swatch = btn:CreateTexture(nil, "ARTWORK")
        swatch:SetSize(14, 14)
        swatch:SetPoint("LEFT", btn, "LEFT", 8, 0)
        swatch:SetTexture("Interface\\BUTTONS\\WHITE8X8")
        local ac = preset.accent
        swatch:SetVertexColor(ac[1], ac[2], ac[3], ac[4])
        btn.swatch = swatch

        local label = btn:CreateFontString(nil, "OVERLAY")
        label:SetPoint("LEFT", swatch, "RIGHT", 6, 0)
        label:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
        label:SetJustifyH("LEFT")
        KE:ApplyThemeFont(label, "small")
        label:SetText(presetName)
        btn.label = label

        local function UpdateVisuals()
            local isSelected = currentPreset == btn.presetName
            if btn.disabled then
                btn:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 0.6)
                label:SetTextColor(0.4, 0.4, 0.4, 1)
            elseif isSelected then
                local a = preset.accent
                btn:SetBackdropBorderColor(a[1], a[2], a[3], 1)
                label:SetTextColor(1, 1, 1, 1)
            elseif btn.hover then
                btn:SetBackdropBorderColor(Theme.accentDim[1], Theme.accentDim[2], Theme.accentDim[3], 1)
                label:SetTextColor(0.9, 0.9, 0.9, 1)
            else
                btn:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
                label:SetTextColor(0.7, 0.7, 0.7, 1)
            end
        end
        btn.UpdateVisuals = UpdateVisuals

        btn:SetScript("OnEnter", function(self)
            self.hover = true
            UpdateVisuals()
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(presetName, ac[1], ac[2], ac[3])
            GameTooltip:Show()
        end)

        btn:SetScript("OnLeave", function(self)
            self.hover = false
            UpdateVisuals()
            GameTooltip:Hide()
        end)

        btn:SetScript("OnClick", function(self)
            if self.disabled then return end
            currentPreset = self.presetName
            for _, b in ipairs(buttons) do b.UpdateVisuals() end
            if onSelect then onSelect(self.presetName) end
        end)

        UpdateVisuals()
        table_insert(buttons, btn)
    end

    local numButtons = #buttons
    local numRows = math.ceil(numButtons / maxColumns)
    container:SetHeight(numRows * buttonHeight + (numRows - 1) * rowSpacing)

    container:SetScript("OnSizeChanged", function(self, width)
        if not width or width <= 0 then return end
        local cols = math.min(maxColumns, numButtons)
        local totalBtnWidth = cols * buttonWidth
        local availSpacing = width - totalBtnWidth
        local spacing = math.max(colSpacing, math_floor(availSpacing / math.max(cols - 1, 1)))

        for i, btn in ipairs(buttons) do
            btn:ClearAllPoints()
            local col = (i - 1) % maxColumns
            local row = math_floor((i - 1) / maxColumns)
            local x = col * (buttonWidth + spacing)
            local y = -(row * (buttonHeight + rowSpacing))
            btn:SetPoint("TOPLEFT", self, "TOPLEFT", x, y)
        end
    end)

    function container:SetEnabled(enabled)
        for _, btn in ipairs(buttons) do
            btn.disabled = not enabled
            btn:EnableMouse(enabled)
            btn.UpdateVisuals()
        end
    end

    function container:SetValue(presetName)
        currentPreset = presetName
        for _, btn in ipairs(buttons) do btn.UpdateVisuals() end
    end

    container.buttons = buttons
    return container
end

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

    presetSelector = CreatePresetSelector(
        card2.content,
        KE.ThemePresets,
        KE.ThemePresetOrder,
        db.Preset or "KitnUI",
        function(presetName)
            KE:SetThemePreset(presetName)
        end
    )
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
