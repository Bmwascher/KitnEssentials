-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local table_insert = table.insert
local CreateFrame = CreateFrame
local ipairs = ipairs

-- Helper: Create Texture Selector (auto-width based on container)
local function CreateTextureSelector(parent, textures, textureOrder, currentTexture, getColorFunc, onSelect)
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(80)

    local buttons = {}
    local buttonSize = 70
    local minSpacing = 8

    for i, textureName in ipairs(textureOrder) do
        local texturePath = textures[textureName]

        local btn = CreateFrame("Button", nil, container, "BackdropTemplate")
        btn:SetSize(buttonSize, buttonSize)

        btn:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeSize = 1,
        })
        btn:SetBackdropColor(Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], 1)

        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetPoint("TOPLEFT", 8, -8)
        tex:SetPoint("BOTTOMRIGHT", -8, 8)
        tex:SetTexture(texturePath)
        btn.tex = tex
        btn.textureName = textureName

        local function UpdateVisuals()
            local isSelected = currentTexture == btn.textureName
            local r, g, b, a = 1, 1, 1, 1
            if getColorFunc then
                r, g, b, a = getColorFunc()
            end

            if btn.disabled then
                btn:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 0.6)
                tex:SetVertexColor(r * 0.3, g * 0.3, b * 0.3)
                tex:SetAlpha(0.5)
            elseif isSelected then
                btn:SetBackdropBorderColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
                tex:SetVertexColor(r, g, b)
                tex:SetAlpha(a)
            elseif btn.hover then
                btn:SetBackdropBorderColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
                tex:SetVertexColor(r * 0.8, g * 0.8, b * 0.8)
                tex:SetAlpha(a * 0.9)
            else
                btn:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
                tex:SetVertexColor(r * 0.6, g * 0.6, b * 0.6)
                tex:SetAlpha(a * 0.8)
            end
        end
        btn.UpdateVisuals = UpdateVisuals

        btn:SetScript("OnEnter", function(self)
            self.hover = true
            UpdateVisuals()
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(textureName, 1, 0.82, 0)
            GameTooltip:Show()
        end)

        btn:SetScript("OnLeave", function(self)
            self.hover = false
            UpdateVisuals()
            GameTooltip:Hide()
        end)

        btn:SetScript("OnClick", function(self)
            if self.disabled then return end
            currentTexture = self.textureName
            for _, b in ipairs(buttons) do
                b.UpdateVisuals()
            end
            if onSelect then
                onSelect(self.textureName)
            end
        end)

        UpdateVisuals()
        table_insert(buttons, btn)
    end

    container.lastWidth = 0

    container:SetScript("OnSizeChanged", function(self, width)
        if not width or width <= 0 then return end

        local flooredWidth = math.floor(width)
        if math.abs(flooredWidth - (self.lastWidth or 0)) < 2 then return end
        self.lastWidth = flooredWidth

        local numButtons = #buttons
        if numButtons == 0 then return end

        local totalButtonWidth = numButtons * buttonSize
        local availableSpacing = flooredWidth - totalButtonWidth - Theme.paddingSmall
        local spacing = math.max(minSpacing, math.floor(availableSpacing / (numButtons - 1)))

        if spacing < minSpacing then
            spacing = minSpacing
        end

        for i, btn in ipairs(buttons) do
            btn:ClearAllPoints()
            if i == 1 then
                btn:SetPoint("LEFT", self, "LEFT", 0, 0)
            else
                btn:SetPoint("LEFT", buttons[i - 1], "RIGHT", spacing, 0)
            end
        end
    end)

    function container:SetEnabled(enabled)
        for _, btn in ipairs(buttons) do
            btn.disabled = not enabled
            btn:EnableMouse(enabled)
            btn.UpdateVisuals()
        end
    end

    function container:SetValue(textureName)
        currentTexture = textureName
        for _, btn in ipairs(buttons) do
            btn.UpdateVisuals()
        end
    end

    function container:RefreshColors()
        for _, btn in ipairs(buttons) do
            btn.UpdateVisuals()
        end
    end

    container.buttons = buttons
    return container
end

-- Register Cursor Circle Tab
GUIFrame:RegisterContent("CursorCircle", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.CursorCircle
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return yOffset + errorCard:GetContentHeight() + Theme.paddingMedium
    end

    local CC
    if KitnEssentials then
        CC = KitnEssentials:GetModule("CursorCircle", true)
    end

    -- Track all widgets for main toggle control
    local allWidgets = {}
    local colorModeWidgets = {}
    local throttleWidgets = {}
    local gcdWidgets = {}
    local gcdSeparateWidgets = {}
    local gcdRingColorModeWidgets = {}
    local gcdSwipeColorModeWidgets = {}
    local textureSelector = nil
    local gcdTextureSelector = nil

    local function ApplySettings()
        if CC and CC.ApplySettings then CC:ApplySettings() end
        if textureSelector and textureSelector.RefreshColors then
            textureSelector:RefreshColors()
        end
        if gcdTextureSelector and gcdTextureSelector.RefreshColors then
            gcdTextureSelector:RefreshColors()
        end
    end

    local function ApplyModuleState(enabled)
        if not KitnEssentials then return end
        local mod = KitnEssentials:GetModule("CursorCircle", true)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("CursorCircle")
        else
            KitnEssentials:DisableModule("CursorCircle")
        end
    end

    -- Comprehensive widget state update
    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled == true

        -- Priority 1: Main toggle controls ALL widgets
        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then
                widget:SetEnabled(mainEnabled)
            end
        end
        if textureSelector then
            textureSelector:SetEnabled(mainEnabled)
        end

        -- Priority 2: If main is enabled, apply conditional states
        if mainEnabled then
            -- ColorMode widgets
            local isCustomColor = (db.ColorMode or "theme") == "custom"
            for _, widget in ipairs(colorModeWidgets) do
                if widget.SetEnabled then widget:SetEnabled(isCustomColor) end
            end

            -- Throttle widgets
            local throttleEnabled = db.UseUpdateInterval == true
            for _, widget in ipairs(throttleWidgets) do
                if widget.SetEnabled then widget:SetEnabled(throttleEnabled) end
            end

            -- GCD widgets
            local gcdMode = db.GCD and db.GCD.Mode or "integrated"
            local gcdEnabled = gcdMode ~= "disabled"
            for _, widget in ipairs(gcdWidgets) do
                if widget.SetEnabled then widget:SetEnabled(gcdEnabled) end
            end
            if gcdTextureSelector then
                gcdTextureSelector:SetEnabled(gcdEnabled and gcdMode == "separate")
            end

            -- GCD Separate widgets
            local isSeparateMode = gcdMode == "separate"
            for _, widget in ipairs(gcdSeparateWidgets) do
                if widget.SetEnabled then widget:SetEnabled(gcdEnabled and isSeparateMode) end
            end

            -- GCD Ring ColorMode widgets
            local isGCDRingCustomColor = (db.GCD and db.GCD.RingColorMode or "theme") == "custom"
            for _, widget in ipairs(gcdRingColorModeWidgets) do
                if widget.SetEnabled then widget:SetEnabled(gcdEnabled and isSeparateMode and isGCDRingCustomColor) end
            end

            -- GCD Swipe ColorMode widgets
            local isGCDSwipeCustomColor = (db.GCD and db.GCD.SwipeColorMode or "custom") == "custom"
            for _, widget in ipairs(gcdSwipeColorModeWidgets) do
                if widget.SetEnabled then widget:SetEnabled(gcdEnabled and isGCDSwipeCustomColor) end
            end
        else
            if gcdTextureSelector then
                gcdTextureSelector:SetEnabled(false)
            end
        end
    end

    -- Get effective color for texture preview
    local function GetEffectiveColor()
        return KE:GetAccentColor(db.ColorMode or "theme", db.Color)
    end

    -- Ensure GCD settings exist
    if not db.GCD then
        db.GCD = {
            Mode = "integrated",
            Size = 25,
            Texture = "Circle 5",
            SwipeColorMode = "custom",
            SwipeColor = { 1, 1, 1, 1 },
            Reverse = true,
            HideOutOfCombat = false,
            RingColorMode = "theme",
            RingColor = { 1, 1, 1, 1 },
        }
    end
    local gcd = db.GCD

    ----------------------------------------------------------------
    -- Card 1: Cursor Circle (Enable + GCD Mode + Throttle)
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Cursor Circle", yOffset)

    -- Enable checkbox
    local row1 = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Cursor Circle", db.Enabled == true,
        function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            UpdateAllWidgetStates()
        end,
        true, "Cursor Circle", "On", "Off"
    )
    row1:AddWidget(enableCheck, 0.5)
    card1:AddRow(row1, 36)

    -- Separator
    local row1sep = GUIFrame:CreateRow(card1.content, 8)
    local sep1 = GUIFrame:CreateSeparator(row1sep)
    row1sep:AddWidget(sep1, 1)
    table_insert(allWidgets, sep1)
    card1:AddRow(row1sep, 8)

    -- GCD Mode dropdown
    local row1b = GUIFrame:CreateRow(card1.content, 40)
    local gcdModeDropdown = GUIFrame:CreateDropdown(row1b, "GCD Mode", CC and CC.GCDModeOptions or {},
        gcd.Mode or "integrated", 120,
        function(key)
            gcd.Mode = key
            ApplySettings()
            UpdateAllWidgetStates()
        end)
    row1b:AddWidget(gcdModeDropdown, 1)
    table_insert(allWidgets, gcdModeDropdown)
    card1:AddRow(row1b, 40)

    -- Throttle toggle + Interval
    local row1c = GUIFrame:CreateRow(card1.content, 37)
    local throttleCheck = GUIFrame:CreateCheckbox(row1c, "Limit Update Rate (Saves CPU)",
        db.UseUpdateInterval == true, function(checked)
            db.UseUpdateInterval = checked
            UpdateAllWidgetStates()
        end)
    row1c:AddWidget(throttleCheck, 0.5)
    table_insert(allWidgets, throttleCheck)

    local intervalSlider = GUIFrame:CreateSlider(row1c, "Update Interval (sec)", 0.01, 0.1, 0.001,
        db.UpdateInterval or 0.016, 80,
        function(val)
            db.UpdateInterval = val
        end)
    row1c:AddWidget(intervalSlider, 0.5)
    table_insert(allWidgets, intervalSlider)
    table_insert(throttleWidgets, intervalSlider)
    card1:AddRow(row1c, 37)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 2: Main Ring Settings
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Main Ring Settings", yOffset)
    table_insert(allWidgets, card2)

    -- Size slider + Visibility Mode
    local row2a = GUIFrame:CreateRow(card2.content, 39)
    local sizeSlider = GUIFrame:CreateSlider(row2a, "Size", 20, 150, 1, db.Size or 40, 60,
        function(val)
            db.Size = val
            ApplySettings()
        end)
    row2a:AddWidget(sizeSlider, 0.5)
    table_insert(allWidgets, sizeSlider)

    local visModeDropdown = GUIFrame:CreateDropdown(row2a, "Visibility", CC and CC.VisibilityModeOptions or {},
        db.VisibilityMode or "always", 120,
        function(key)
            db.VisibilityMode = key
            ApplySettings()
        end)
    row2a:AddWidget(visModeDropdown, 0.5)
    table_insert(allWidgets, visModeDropdown)
    card2:AddRow(row2a, 39)

    -- Color Mode + Custom Color
    local row2b = GUIFrame:CreateRow(card2.content, 37)
    local colorModeDropdown = GUIFrame:CreateDropdown(row2b, "Color Mode", KE.ColorModeOptions,
        db.ColorMode or "theme", 70,
        function(key)
            db.ColorMode = key
            ApplySettings()
            UpdateAllWidgetStates()
        end)
    row2b:AddWidget(colorModeDropdown, 0.5)
    table_insert(allWidgets, colorModeDropdown)

    local colorPicker = GUIFrame:CreateColorPicker(row2b, "Custom Color", db.Color or { 1, 1, 1, 1 },
        function(r, g, b, a)
            db.Color = { r, g, b, a }
            ApplySettings()
        end)
    row2b:AddWidget(colorPicker, 0.5)
    table_insert(allWidgets, colorPicker)
    table_insert(colorModeWidgets, colorPicker)
    card2:AddRow(row2b, 37)

    yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 3: Main Ring Texture
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Main Ring Texture", yOffset)
    table_insert(allWidgets, card3)

    local row3 = GUIFrame:CreateRow(card3.content, 71)

    textureSelector = CreateTextureSelector(
        row3,
        CC and CC.Textures or {},
        CC and CC.TextureOrder or {},
        db.Texture or "Circle 3",
        GetEffectiveColor,
        function(textureName)
            db.Texture = textureName
            ApplySettings()
        end
    )
    textureSelector:SetPoint("TOPLEFT", row3, "TOPLEFT", 0, 3)
    textureSelector:SetPoint("TOPRIGHT", row3, "TOPRIGHT", 0, 0)
    textureSelector:SetEnabled(db.Enabled == true)
    card3:AddRow(row3, 71)

    yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 4: GCD Swipe Settings
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "GCD Swipe Settings", yOffset)
    table_insert(allWidgets, card4)
    table_insert(gcdWidgets, card4)

    -- Swipe Color Mode + Custom Color
    local row4a = GUIFrame:CreateRow(card4.content, 39)
    local gcdSwipeColorModeDropdown = GUIFrame:CreateDropdown(row4a, "Color Mode", KE.ColorModeOptions,
        gcd.SwipeColorMode or "custom", 70,
        function(key)
            gcd.SwipeColorMode = key
            ApplySettings()
            UpdateAllWidgetStates()
        end)
    row4a:AddWidget(gcdSwipeColorModeDropdown, 0.5)
    table_insert(allWidgets, gcdSwipeColorModeDropdown)
    table_insert(gcdWidgets, gcdSwipeColorModeDropdown)

    local gcdSwipeColorPicker = GUIFrame:CreateColorPicker(row4a, "Custom Color",
        gcd.SwipeColor or { 1, 1, 1, 1 },
        function(r, g, b, a)
            gcd.SwipeColor = { r, g, b, a }
            ApplySettings()
        end)
    row4a:AddWidget(gcdSwipeColorPicker, 0.5)
    table_insert(allWidgets, gcdSwipeColorPicker)
    table_insert(gcdWidgets, gcdSwipeColorPicker)
    table_insert(gcdSwipeColorModeWidgets, gcdSwipeColorPicker)
    card4:AddRow(row4a, 39)

    -- Reverse + Hide OOC
    local row4b = GUIFrame:CreateRow(card4.content, 37)
    local reverseCheck = GUIFrame:CreateCheckbox(row4b, "Reverse Swipe Direction",
        gcd.Reverse == true, function(checked)
            gcd.Reverse = checked
            ApplySettings()
        end)
    row4b:AddWidget(reverseCheck, 0.5)
    table_insert(allWidgets, reverseCheck)
    table_insert(gcdWidgets, reverseCheck)

    local hideOOCCheck = GUIFrame:CreateCheckbox(row4b, "Only Show In Combat",
        gcd.HideOutOfCombat == true, function(checked)
            gcd.HideOutOfCombat = checked
            ApplySettings()
        end)
    row4b:AddWidget(hideOOCCheck, 0.5)
    table_insert(allWidgets, hideOOCCheck)
    table_insert(gcdWidgets, hideOOCCheck)
    card4:AddRow(row4b, 37)

    yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 5: GCD Ring Texture (separate mode only)
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "GCD Ring Texture", yOffset)
    table_insert(allWidgets, card5)
    table_insert(gcdWidgets, card5)
    table_insert(gcdSeparateWidgets, card5)

    local row5 = GUIFrame:CreateRow(card5.content, 71)

    local function GetGCDEffectiveColor()
        return KE:GetAccentColor(gcd.RingColorMode or "theme", gcd.RingColor)
    end

    gcdTextureSelector = CreateTextureSelector(
        row5,
        CC and CC.GCDRingTextures or {},
        CC and CC.GCDRingTextureOrder or {},
        gcd.Texture or "Circle 5",
        GetGCDEffectiveColor,
        function(textureName)
            gcd.Texture = textureName
            ApplySettings()
        end
    )
    gcdTextureSelector:SetPoint("TOPLEFT", row5, "TOPLEFT", 0, 3)
    gcdTextureSelector:SetPoint("TOPRIGHT", row5, "TOPRIGHT", 0, 0)
    card5:AddRow(row5, 71)

    yOffset = yOffset + card5:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 6: GCD Ring Background (separate mode only)
    ----------------------------------------------------------------
    local card6 = GUIFrame:CreateCard(scrollChild, "GCD Ring Background", yOffset)
    table_insert(allWidgets, card6)
    table_insert(gcdWidgets, card6)
    table_insert(gcdSeparateWidgets, card6)

    -- Ring Size
    local row6a = GUIFrame:CreateRow(card6.content, 37)
    local gcdSizeSlider = GUIFrame:CreateSlider(row6a, "Ring Size", 10, 150, 1, gcd.Size or 25, 60,
        function(val)
            gcd.Size = val
            ApplySettings()
        end)
    row6a:AddWidget(gcdSizeSlider, 1)
    table_insert(allWidgets, gcdSizeSlider)
    table_insert(gcdWidgets, gcdSizeSlider)
    table_insert(gcdSeparateWidgets, gcdSizeSlider)
    card6:AddRow(row6a, 37)

    -- Ring Color Mode + Custom Color
    local row6b = GUIFrame:CreateRow(card6.content, 37)
    local gcdRingColorModeDropdown = GUIFrame:CreateDropdown(row6b, "Color Mode", KE.ColorModeOptions,
        gcd.RingColorMode or "theme", 70,
        function(key)
            gcd.RingColorMode = key
            ApplySettings()
            if gcdTextureSelector and gcdTextureSelector.RefreshColors then
                gcdTextureSelector:RefreshColors()
            end
            UpdateAllWidgetStates()
        end)
    row6b:AddWidget(gcdRingColorModeDropdown, 0.5)
    table_insert(allWidgets, gcdRingColorModeDropdown)
    table_insert(gcdWidgets, gcdRingColorModeDropdown)
    table_insert(gcdSeparateWidgets, gcdRingColorModeDropdown)

    local gcdRingColorPicker = GUIFrame:CreateColorPicker(row6b, "Custom Color",
        gcd.RingColor or { 1, 1, 1, 1 },
        function(r, g, b, a)
            gcd.RingColor = { r, g, b, a }
            ApplySettings()
            if gcdTextureSelector and gcdTextureSelector.RefreshColors then
                gcdTextureSelector:RefreshColors()
            end
        end)
    row6b:AddWidget(gcdRingColorPicker, 0.5)
    table_insert(allWidgets, gcdRingColorPicker)
    table_insert(gcdWidgets, gcdRingColorPicker)
    table_insert(gcdSeparateWidgets, gcdRingColorPicker)
    table_insert(gcdRingColorModeWidgets, gcdRingColorPicker)
    card6:AddRow(row6b, 37)

    yOffset = yOffset + card6:GetContentHeight() + Theme.paddingSmall

    -- Apply initial widget states
    UpdateAllWidgetStates()
    yOffset = yOffset - (Theme.paddingSmall * 9)
    return yOffset
end)
