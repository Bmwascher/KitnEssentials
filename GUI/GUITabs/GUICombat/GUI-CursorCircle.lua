-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-CursorCircle.lua                                    ║
-- ║  GUI: Cursor Circle                                      ║
-- ║  Purpose: Configuration panel for the CursorCircle       ║
-- ║  module.                                                 ║
-- ╚══════════════════════════════════════════════════════════╝

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

    local buttons = {}
    local buttonSize = 58
    local minSpacing = 6
    local maxColumns = 6
    local rowSpacing = 6

    for _, textureName in ipairs(textureOrder) do
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

    local numButtons = #buttons
    local numRows = math.ceil(numButtons / maxColumns)
    container:SetHeight(numRows * buttonSize + (numRows - 1) * rowSpacing)

    container.lastWidth = 0

    container:SetScript("OnSizeChanged", function(self, width)
        if not width or width <= 0 then return end

        local flooredWidth = math.floor(width)
        if math.abs(flooredWidth - (self.lastWidth or 0)) < 2 then return end
        self.lastWidth = flooredWidth

        if numButtons == 0 then return end

        local cols = math.min(maxColumns, numButtons)
        local totalButtonWidth = cols * buttonSize
        local availableSpacing = flooredWidth - totalButtonWidth - Theme.paddingSmall
        local spacing = math.max(minSpacing, math.floor(availableSpacing / math.max(cols - 1, 1)))

        for i, btn in ipairs(buttons) do
            btn:ClearAllPoints()
            local col = (i - 1) % maxColumns
            local row = math.floor((i - 1) / maxColumns)
            local x = col * (buttonSize + spacing)
            local y = -(row * (buttonSize + rowSpacing))
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

GUIFrame:RegisterContent("CursorCircle", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.CursorCircle
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

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

    local CC
    if KitnEssentials then
        CC = KitnEssentials:GetModule("CursorCircle", true)
    end

    local textureSelector
    local gcdTextureSelector

    local manager = GUIFrame:CreateWidgetStateManager()
    manager:SetCondition("customColor", function()
        return (db.ColorMode or "theme") == "custom"
    end)
    manager:SetCondition("throttle", function()
        return db.UseUpdateInterval == true
    end)
    manager:SetCondition("gcd", function()
        return (gcd.Mode or "integrated") ~= "disabled"
    end)
    manager:SetCondition("gcdSeparate", function()
        return (gcd.Mode or "integrated") == "separate"
    end)
    manager:SetCondition("gcdRingCustomColor", function()
        return (gcd.Mode or "integrated") == "separate"
            and (gcd.RingColorMode or "theme") == "custom"
    end)
    manager:SetCondition("gcdSwipeCustomColor", function()
        return (gcd.Mode or "integrated") ~= "disabled"
            and (gcd.SwipeColorMode or "custom") == "custom"
    end)

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

    local function RefreshStates()
        manager:UpdateAll(db.Enabled == true)
    end

    local function GetEffectiveColor()
        return KE:GetAccentColor(db.ColorMode or "theme", db.Color)
    end

    local function GetGCDEffectiveColor()
        return KE:GetAccentColor(gcd.RingColorMode or "theme", gcd.RingColor)
    end

    ----------------------------------------------------------------
    -- Card 1: Cursor Circle (Enable + GCD Mode + Throttle)
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Cursor Circle", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Cursor Circle", {
        value = db.Enabled == true,
        callback = function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Cursor Circle",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, Theme.rowHeight)

    local row1sep = GUIFrame:CreateRow(card1.content, Theme.rowHeightSeparator)
    local sep1 = GUIFrame:CreateSeparator(row1sep)
    row1sep:AddWidget(sep1, 1)
    manager:Register(sep1, "all")
    card1:AddRow(row1sep, Theme.rowHeightSeparator)

    local row1b = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local gcdModeDropdown = GUIFrame:CreateDropdown(row1b, "GCD Mode", {
        options = CC and CC.GCDModeOptions or {},
        value = gcd.Mode or "integrated",
        callback = function(key)
            gcd.Mode = key
            ApplySettings()
            RefreshStates()
        end,
    })
    row1b:AddWidget(gcdModeDropdown, 1)
    manager:Register(gcdModeDropdown, "all")
    card1:AddRow(row1b, Theme.rowHeight)

    local row1c = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local throttleCheck = GUIFrame:CreateCheckbox(row1c, "Limit Update Rate (Saves CPU)", {
        value = db.UseUpdateInterval == true,
        callback = function(checked)
            db.UseUpdateInterval = checked
            RefreshStates()
        end,
    })
    row1c:AddWidget(throttleCheck, 0.5)
    manager:Register(throttleCheck, "all")

    local intervalSlider = GUIFrame:CreateSlider(row1c, "Update Interval (sec)", {
        min = 0.01, max = 0.1, step = 0.001,
        value = db.UpdateInterval or 0.016,
        callback = function(val) db.UpdateInterval = val end,
    })
    row1c:AddWidget(intervalSlider, 0.5)
    manager:Register(intervalSlider, "throttle")
    card1:AddRow(row1c, Theme.rowHeightLast, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Main Ring Settings
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Main Ring Settings", yOffset)
    manager:Register(card2, "all")

    local row2a = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local sizeSlider = GUIFrame:CreateSlider(row2a, "Size", {
        min = 20, max = 150, step = 1,
        value = db.Size or 40,
        callback = function(val) db.Size = val; ApplySettings() end,
    })
    row2a:AddWidget(sizeSlider, 0.5)
    manager:Register(sizeSlider, "all")

    local visModeDropdown = GUIFrame:CreateDropdown(row2a, "Visibility", {
        options = CC and CC.VisibilityModeOptions or {},
        value = db.VisibilityMode or "always",
        callback = function(key) db.VisibilityMode = key; ApplySettings() end,
    })
    row2a:AddWidget(visModeDropdown, 0.5)
    manager:Register(visModeDropdown, "all")
    card2:AddRow(row2a, Theme.rowHeight)

    local row2b = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local colorModeDropdown = GUIFrame:CreateDropdown(row2b, "Color Mode", {
        options = KE.ColorModeOptions,
        value = db.ColorMode or "theme",
        callback = function(key)
            db.ColorMode = key
            ApplySettings()
            RefreshStates()
        end,
    })
    row2b:AddWidget(colorModeDropdown, 0.5)
    manager:Register(colorModeDropdown, "all")

    local colorPicker = GUIFrame:CreateColorPicker(row2b, "Custom Color", {
        color = db.Color or { 1, 1, 1, 1 },
        callback = function(r, g, b, a)
            db.Color = { r, g, b, a }
            ApplySettings()
        end,
    })
    row2b:AddWidget(colorPicker, 0.5)
    manager:Register(colorPicker, "customColor")
    card2:AddRow(row2b, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Main Ring Texture
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Main Ring Texture", yOffset)
    manager:Register(card3, "all")

    textureSelector = CreateTextureSelector(
        card3.content,
        CC and CC.Textures or {},
        CC and CC.TextureOrder or {},
        db.Texture or "Circle 3",
        GetEffectiveColor,
        function(textureName)
            db.Texture = textureName
            ApplySettings()
        end
    )
    local texHeight = textureSelector:GetHeight() + 4
    local row3 = GUIFrame:CreateRow(card3.content, texHeight)
    textureSelector:SetParent(row3)
    textureSelector:SetPoint("TOPLEFT", row3, "TOPLEFT", 0, 0)
    textureSelector:SetPoint("TOPRIGHT", row3, "TOPRIGHT", 0, 0)
    manager:Register(textureSelector, "all")
    card3:AddRow(row3, texHeight, 0)

    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: GCD Swipe Settings
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "GCD Swipe Settings", yOffset)
    manager:Register(card4, "gcd")

    local row4a = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local gcdSwipeColorModeDropdown = GUIFrame:CreateDropdown(row4a, "Color Mode", {
        options = KE.ColorModeOptions,
        value = gcd.SwipeColorMode or "custom",
        callback = function(key)
            gcd.SwipeColorMode = key
            ApplySettings()
            RefreshStates()
        end,
    })
    row4a:AddWidget(gcdSwipeColorModeDropdown, 0.5)
    manager:Register(gcdSwipeColorModeDropdown, "gcd")

    local gcdSwipeColorPicker = GUIFrame:CreateColorPicker(row4a, "Custom Color", {
        color = gcd.SwipeColor or { 1, 1, 1, 1 },
        callback = function(r, g, b, a)
            gcd.SwipeColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row4a:AddWidget(gcdSwipeColorPicker, 0.5)
    manager:Register(gcdSwipeColorPicker, "gcdSwipeCustomColor")
    card4:AddRow(row4a, Theme.rowHeight)

    local row4b = GUIFrame:CreateRow(card4.content, Theme.rowHeightLast)
    local reverseCheck = GUIFrame:CreateCheckbox(row4b, "Reverse Swipe Direction", {
        value = gcd.Reverse == true,
        callback = function(checked) gcd.Reverse = checked; ApplySettings() end,
    })
    row4b:AddWidget(reverseCheck, 0.5)
    manager:Register(reverseCheck, "gcd")

    local hideOOCCheck = GUIFrame:CreateCheckbox(row4b, "Only Show In Combat", {
        value = gcd.HideOutOfCombat == true,
        callback = function(checked) gcd.HideOutOfCombat = checked; ApplySettings() end,
    })
    row4b:AddWidget(hideOOCCheck, 0.5)
    manager:Register(hideOOCCheck, "gcd")
    card4:AddRow(row4b, Theme.rowHeightLast, 0)

    yOffset = card4:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: GCD Ring Texture (separate mode only)
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "GCD Ring Texture", yOffset)
    manager:Register(card5, "gcdSeparate")

    gcdTextureSelector = CreateTextureSelector(
        card5.content,
        CC and CC.GCDRingTextures or {},
        CC and CC.GCDRingTextureOrder or {},
        gcd.Texture or "Circle 5",
        GetGCDEffectiveColor,
        function(textureName)
            gcd.Texture = textureName
            ApplySettings()
        end
    )
    local gcdTexHeight = gcdTextureSelector:GetHeight() + 4
    local row5 = GUIFrame:CreateRow(card5.content, gcdTexHeight)
    gcdTextureSelector:SetParent(row5)
    gcdTextureSelector:SetPoint("TOPLEFT", row5, "TOPLEFT", 0, 0)
    gcdTextureSelector:SetPoint("TOPRIGHT", row5, "TOPRIGHT", 0, 0)
    manager:Register(gcdTextureSelector, "gcdSeparate")
    card5:AddRow(row5, gcdTexHeight, 0)

    yOffset = card5:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 6: GCD Ring Background (separate mode only)
    ----------------------------------------------------------------
    local card6 = GUIFrame:CreateCard(scrollChild, "GCD Ring Background", yOffset)
    manager:Register(card6, "gcdSeparate")

    local row6a = GUIFrame:CreateRow(card6.content, Theme.rowHeight)
    local gcdSizeSlider = GUIFrame:CreateSlider(row6a, "Ring Size", {
        min = 10, max = 150, step = 1,
        value = gcd.Size or 25,
        callback = function(val) gcd.Size = val; ApplySettings() end,
    })
    row6a:AddWidget(gcdSizeSlider, 1)
    manager:Register(gcdSizeSlider, "gcdSeparate")
    card6:AddRow(row6a, Theme.rowHeight)

    local row6b = GUIFrame:CreateRow(card6.content, Theme.rowHeightLast)
    local gcdRingColorModeDropdown = GUIFrame:CreateDropdown(row6b, "Color Mode", {
        options = KE.ColorModeOptions,
        value = gcd.RingColorMode or "theme",
        callback = function(key)
            gcd.RingColorMode = key
            ApplySettings()
            if gcdTextureSelector and gcdTextureSelector.RefreshColors then
                gcdTextureSelector:RefreshColors()
            end
            RefreshStates()
        end,
    })
    row6b:AddWidget(gcdRingColorModeDropdown, 0.5)
    manager:Register(gcdRingColorModeDropdown, "gcdSeparate")

    local gcdRingColorPicker = GUIFrame:CreateColorPicker(row6b, "Custom Color", {
        color = gcd.RingColor or { 1, 1, 1, 1 },
        callback = function(r, g, b, a)
            gcd.RingColor = { r, g, b, a }
            ApplySettings()
            if gcdTextureSelector and gcdTextureSelector.RefreshColors then
                gcdTextureSelector:RefreshColors()
            end
        end,
    })
    row6b:AddWidget(gcdRingColorPicker, 0.5)
    manager:Register(gcdRingColorPicker, "gcdRingCustomColor")
    card6:AddRow(row6b, Theme.rowHeightLast, 0)

    yOffset = card6:GetNextOffset()

    RefreshStates()
    return yOffset
end)
