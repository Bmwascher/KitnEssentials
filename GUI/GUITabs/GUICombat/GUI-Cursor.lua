-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-Cursor.lua                                          ║
-- ║  GUI: Cursor (unified)                                   ║
-- ║  Purpose: Configuration panel for the Cursor module      ║
-- ║  (cursor circle + GCD ring + cast circle + trail + dispel)║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

-- Visual texture selector: grid of clickable texture-preview buttons.
-- Ported from the legacy CursorCircle GUI; the texture name string isn't intuitive,
-- so users pick from the actual ring TGA preview instead.
local function CreateTextureSelector(parent, textures, textureOrder, currentTexture, getColorFunc, onSelect, labelText)
    local container = CreateFrame("Frame", nil, parent)

    local buttons = {}
    local buttonSize = 58
    local minSpacing = 6
    local maxColumns = 6
    local rowSpacing = 6
    local labelOffset = 0

    -- Optional header label rendered above the button row. White text to match
    -- the other widget labels (Size, Color Mode, etc), not gold.
    if labelText and labelText ~= "" then
        local label = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
        label:SetText(labelText)
        label:SetTextColor(1, 1, 1)
        labelOffset = 16
    end

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
            if getColorFunc then r, g, b, a = getColorFunc() end

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

        -- Tooltip label: strip "ring_" prefix + Title-case; special-case "circle".
        local tooltipLabel = textureName
        if tooltipLabel == "circle" then
            tooltipLabel = "Soft Glow"
        elseif tooltipLabel:find("^ring_") then
            tooltipLabel = tooltipLabel:sub(6):gsub("^%l", string.upper)
        end
        btn:SetScript("OnEnter", function(self)
            self.hover = true
            UpdateVisuals()
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(tooltipLabel, 1, 0.82, 0)
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
            for _, b in ipairs(buttons) do b.UpdateVisuals() end
            if onSelect then onSelect(self.textureName) end
        end)

        UpdateVisuals()
        buttons[#buttons + 1] = btn
    end

    local numButtons = #buttons
    local numRows = math.ceil(numButtons / maxColumns)
    container:SetHeight(numRows * buttonSize + (numRows - 1) * rowSpacing + labelOffset)
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
            local y = -(labelOffset + row * (buttonSize + rowSpacing))
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
        for _, btn in ipairs(buttons) do btn.UpdateVisuals() end
    end
    function container:RefreshColors()
        for _, btn in ipairs(buttons) do btn.UpdateVisuals() end
    end

    container.buttons = buttons
    return container
end

local function GetModule()
    if not KitnEssentials then return nil end
    return KitnEssentials:GetModule("Cursor", true)
end

local function RefreshModule()
    local C = GetModule()
    if C and C.Refresh then C:Refresh() end
end

local function ApplyModuleState(enabled)
    if not KitnEssentials then return end
    local mod = GetModule()
    if not mod then return end
    mod.db.Enabled = enabled
    if enabled then
        KitnEssentials:EnableModule("Cursor")
    else
        KitnEssentials:DisableModule("Cursor")
    end
end

GUIFrame:RegisterContent("Cursor", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.Cursor
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    -- Defensive defaults in case profile predates Cursor schema
    db.GCD    = db.GCD    or {}
    db.Cast   = db.Cast   or {}
    db.Trail  = db.Trail  or {}
    db.Dispel = db.Dispel or {}

    local manager = GUIFrame:CreateWidgetStateManager()
    manager:SetCondition("gcdEnabled", function()
        return db.GCD.Enabled == true
    end)
    manager:SetCondition("gcdSeparate", function()
        return db.GCD.Enabled == true and (db.GCD.Mode or "integrated") == "separate"
    end)
    manager:SetCondition("castEnabled", function()
        return db.Cast.Enabled == true
    end)
    manager:SetCondition("trailEnabled", function()
        return db.Trail.Enabled == true
    end)
    manager:SetCondition("dispelEnabled", function()
        return db.Dispel.Enabled == true
    end)
    manager:SetCondition("cursorCustomColor", function()
        return db.Enabled ~= false and (db.ColorMode or "class") == "custom"
    end)
    manager:SetCondition("gcdRingCustom", function()
        return db.GCD.Enabled == true
            and (db.GCD.Mode or "integrated") == "separate"
            and (db.GCD.RingColorMode or "theme") == "custom"
    end)
    manager:SetCondition("gcdSwipeCustom", function()
        return db.GCD.Enabled == true and (db.GCD.SwipeColorMode or "custom") == "custom"
    end)
    manager:SetCondition("castRingCustom", function()
        return db.Cast.Enabled == true and (db.Cast.RingColorMode or "class") == "custom"
    end)
    manager:SetCondition("castSwipeCustom", function()
        return db.Cast.Enabled == true and (db.Cast.SwipeColorMode or "theme") == "custom"
    end)
    manager:SetCondition("trailCustomColor", function()
        return db.Trail.Enabled == true and db.Trail.ColorInherit == false
    end)

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Cursor (Enable + Master Visibility)
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Cursor", yOffset)

    local row1a = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1a, "Enable Cursor", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Cursor",
        msgOn = "On",
        msgOff = "Off",
    })
    row1a:AddWidget(enableCheck, 1)
    card1:AddRow(row1a, Theme.rowHeight)

    local row1sep = GUIFrame:CreateRow(card1.content, Theme.rowHeightSeparator)
    local sep1 = GUIFrame:CreateSeparator(row1sep)
    row1sep:AddWidget(sep1, 1)
    manager:Register(sep1, "all")
    card1:AddRow(row1sep, Theme.rowHeightSeparator)

    local row1b = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local visDropdown = GUIFrame:CreateDropdown(row1b, "Visibility State", {
        options = (GetModule() and GetModule().VISIBILITY_MODES) or {},
        value = db.Visibility or "always",
        callback = function(key) db.Visibility = key; RefreshModule() end,
    })
    row1b:AddWidget(visDropdown, 1)
    manager:Register(visDropdown, "all")
    card1:AddRow(row1b, Theme.rowHeightLast, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Cursor Style (Size + Texture + Color)
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Cursor Style", yOffset)
    manager:Register(card2, "all")

    local C = GetModule()

    -- Visual texture selector (grid of TGA previews) — placed FIRST so the texture
    -- is the most prominent setting in the card. Forward-declared so the Color
    -- Mode + Color Picker callbacks can refresh its tint.
    local textureSelector
    local function GetCursorColor()
        return KE:GetAccentColor(db.ColorMode or "class", db.Color or { 1, 1, 1, 1 })
    end

    local row2a = GUIFrame:CreateRow(card2.content, 82)  -- 58px buttons + 16px label + padding
    textureSelector = CreateTextureSelector(
        row2a,
        (C and C.RING_TEXTURES) or {},
        (C and C.TEXTURE_ORDER) or {},
        db.Texture or "ring_normal",
        GetCursorColor,
        function(textureName)
            db.Texture = textureName
            RefreshModule()
        end,
        "Texture"
    )
    textureSelector:SetParent(row2a)
    textureSelector:SetPoint("TOPLEFT", row2a, "TOPLEFT", 0, 0)
    textureSelector:SetPoint("TOPRIGHT", row2a, "TOPRIGHT", 0, 0)
    manager:Register(textureSelector, "all")
    card2:AddRow(row2a, 82)

    local row2b = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local sizeSlider = GUIFrame:CreateSlider(row2b, "Size", {
        min = 16, max = 200, step = 1,
        value = db.Size or 50,
        callback = function(val) db.Size = val; RefreshModule() end,
    })
    row2b:AddWidget(sizeSlider, 1)
    manager:Register(sizeSlider, "all")
    card2:AddRow(row2b, Theme.rowHeight)

    local row2c = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local colorModeDropdown = GUIFrame:CreateDropdown(row2c, "Color Mode", {
        options = KE.ColorModeOptions,
        value = db.ColorMode or "class",
        callback = function(key)
            db.ColorMode = key
            RefreshModule()
            RefreshStates()  -- toggle Custom Color picker disabled state
            if textureSelector and textureSelector.RefreshColors then textureSelector:RefreshColors() end
        end,
    })
    row2c:AddWidget(colorModeDropdown, 0.5)
    manager:Register(colorModeDropdown, "all")

    local colorPicker = GUIFrame:CreateColorPicker(row2c, "Custom Color", {
        color = db.Color or { 1, 1, 1, 1 },
        callback = function(r, g, b, a)
            db.Color = { r, g, b, a }
            RefreshModule()
            if textureSelector and textureSelector.RefreshColors then textureSelector:RefreshColors() end
        end,
    })
    row2c:AddWidget(colorPicker, 0.5)
    manager:Register(colorPicker, "cursorCustomColor")
    card2:AddRow(row2c, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: GCD Ring
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "GCD Ring", yOffset)
    manager:Register(card3, "all")

    local row3a = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local gcdEnable = GUIFrame:CreateCheckbox(row3a, "Enable GCD Ring", {
        value = db.GCD.Enabled ~= false,
        callback = function(checked)
            db.GCD.Enabled = checked
            RefreshModule()
            RefreshStates()
        end,
    })
    row3a:AddWidget(gcdEnable, 1)
    manager:Register(gcdEnable, "all")
    card3:AddRow(row3a, Theme.rowHeight)

    local row3sep = GUIFrame:CreateRow(card3.content, Theme.rowHeightSeparator)
    local sep3 = GUIFrame:CreateSeparator(row3sep)
    row3sep:AddWidget(sep3, 1)
    manager:Register(sep3, "all")
    card3:AddRow(row3sep, Theme.rowHeightSeparator)

    local row3b = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local gcdMode = GUIFrame:CreateDropdown(row3b, "Mode", {
        options = (C and C.GCD_MODE_OPTIONS) or {},
        value = db.GCD.Mode or "integrated",
        callback = function(key)
            db.GCD.Mode = key
            RefreshModule()
            RefreshStates()
        end,
    })
    row3b:AddWidget(gcdMode, 1)
    manager:Register(gcdMode, "gcdEnabled")
    card3:AddRow(row3b, Theme.rowHeight)

    local row3c = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    -- GCD texture selector placed FIRST (separate-mode only; integrated forces cursor texture).
    local gcdTextureSelector
    local function GetGCDColor()
        return KE:GetAccentColor(db.GCD.RingColorMode or "theme", db.GCD.RingColor or { 1, 1, 1, 1 })
    end
    local row3cTex = GUIFrame:CreateRow(card3.content, 82)
    gcdTextureSelector = CreateTextureSelector(
        row3cTex,
        (C and C.RING_TEXTURES) or {},
        (C and C.TEXTURE_ORDER) or {},
        db.GCD.Texture or "ring_light",
        GetGCDColor,
        function(textureName)
            db.GCD.Texture = textureName
            RefreshModule()
        end,
        "Texture"
    )
    gcdTextureSelector:SetParent(row3cTex)
    gcdTextureSelector:SetPoint("TOPLEFT", row3cTex, "TOPLEFT", 0, 0)
    gcdTextureSelector:SetPoint("TOPRIGHT", row3cTex, "TOPRIGHT", 0, 0)
    manager:Register(gcdTextureSelector, "gcdSeparate")
    card3:AddRow(row3cTex, 82)

    local gcdSize = GUIFrame:CreateSlider(row3c, "Size (separate mode)", {
        min = 16, max = 200, step = 1,
        value = db.GCD.Size or 50,
        callback = function(val) db.GCD.Size = val; RefreshModule() end,
    })
    row3c:AddWidget(gcdSize, 1)
    manager:Register(gcdSize, "gcdSeparate")
    card3:AddRow(row3c, Theme.rowHeight)

    -- Sub-separator between shape (Mode/Size/Texture) and color sections
    local row3midSep = GUIFrame:CreateRow(card3.content, Theme.rowHeightSeparator)
    local sep3mid = GUIFrame:CreateSeparator(row3midSep)
    row3midSep:AddWidget(sep3mid, 1)
    manager:Register(sep3mid, "gcdEnabled")
    card3:AddRow(row3midSep, Theme.rowHeightSeparator)

    -- Ring color: Mode + Picker (Mode + Picker only meaningful in separate mode)
    local row3dRing = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local gcdRingMode = GUIFrame:CreateDropdown(row3dRing, "Ring Color Mode", {
        options = KE.ColorModeOptions,
        value = db.GCD.RingColorMode or "theme",
        callback = function(key)
            db.GCD.RingColorMode = key
            RefreshModule()
            RefreshStates()
            if gcdTextureSelector and gcdTextureSelector.RefreshColors then gcdTextureSelector:RefreshColors() end
        end,
    })
    row3dRing:AddWidget(gcdRingMode, 0.5)
    manager:Register(gcdRingMode, "gcdSeparate")

    local gcdRingColor = GUIFrame:CreateColorPicker(row3dRing, "Ring Color", {
        color = db.GCD.RingColor or { 1, 1, 1, 1 },
        callback = function(r, g, b, a)
            db.GCD.RingColor = { r, g, b, a }
            RefreshModule()
            if gcdTextureSelector and gcdTextureSelector.RefreshColors then gcdTextureSelector:RefreshColors() end
        end,
    })
    row3dRing:AddWidget(gcdRingColor, 0.5)
    manager:Register(gcdRingColor, "gcdRingCustom")
    card3:AddRow(row3dRing, Theme.rowHeight)

    -- Swipe color: Mode + Picker
    local row3dSwipe = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local gcdSwipeMode = GUIFrame:CreateDropdown(row3dSwipe, "Swipe Color Mode", {
        options = KE.ColorModeOptions,
        value = db.GCD.SwipeColorMode or "custom",
        callback = function(key)
            db.GCD.SwipeColorMode = key
            RefreshModule()
            RefreshStates()
        end,
    })
    row3dSwipe:AddWidget(gcdSwipeMode, 0.5)
    manager:Register(gcdSwipeMode, "gcdEnabled")

    local gcdSwipeColor = GUIFrame:CreateColorPicker(row3dSwipe, "Swipe Color", {
        color = db.GCD.SwipeColor or { 1, 1, 1, 0.8 },
        callback = function(r, g, b, a)
            db.GCD.SwipeColor = { r, g, b, a }
            RefreshModule()
        end,
    })
    row3dSwipe:AddWidget(gcdSwipeColor, 0.5)
    manager:Register(gcdSwipeColor, "gcdSwipeCustom")
    card3:AddRow(row3dSwipe, Theme.rowHeightLast, 0)

    -- "Reverse Swipe" removed: Blizzard's Cooldown reverse flag doesn't behave
    -- predictably with our ring textures + circular-edge swipe combo.
    -- "Instance Only" removed: VisibilityOverride below covers "in_instance" semantics.
    -- "Visibility Override" disabled for v1 — adds complexity without clear use cases.
    -- Backing field (db.GCD.VisibilityOverride) still honored by code if set externally.
    --[[
    local row3f = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local visOverrideOptions = { { key = "inherit", text = "Inherit Master" } }
    if C and C.VISIBILITY_MODES then
        for _, m in ipairs(C.VISIBILITY_MODES) do
            visOverrideOptions[#visOverrideOptions + 1] = { key = m.key, text = m.text }
        end
    end
    local gcdVisOverride = GUIFrame:CreateDropdown(row3f, "Visibility Override", {
        options = visOverrideOptions,
        value = db.GCD.VisibilityOverride or "inherit",
        callback = function(key)
            db.GCD.VisibilityOverride = (key == "inherit") and nil or key
            RefreshModule()
        end,
    })
    row3f:AddWidget(gcdVisOverride, 1)
    manager:Register(gcdVisOverride, "gcdEnabled")
    card3:AddRow(row3f, Theme.rowHeightLast, 0)
    ]]--

    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Cast Circle
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Cast Circle", yOffset)
    manager:Register(card4, "all")

    local row4a = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local castEnable = GUIFrame:CreateCheckbox(row4a, "Enable Cast Circle", {
        value = db.Cast.Enabled == true,
        callback = function(checked)
            db.Cast.Enabled = checked
            RefreshModule()
            RefreshStates()
        end,
    })
    row4a:AddWidget(castEnable, 1)
    manager:Register(castEnable, "all")
    card4:AddRow(row4a, Theme.rowHeight)

    local row4sep = GUIFrame:CreateRow(card4.content, Theme.rowHeightSeparator)
    local sep4 = GUIFrame:CreateSeparator(row4sep)
    row4sep:AddWidget(sep4, 1)
    manager:Register(sep4, "all")
    card4:AddRow(row4sep, Theme.rowHeightSeparator)

    -- Cast texture selector placed FIRST.
    local castTextureSelector
    local function GetCastColor()
        return KE:GetAccentColor(db.Cast.RingColorMode or "class", db.Cast.RingColor or { 1, 1, 1, 1 })
    end
    local row4bTex = GUIFrame:CreateRow(card4.content, 82)
    castTextureSelector = CreateTextureSelector(
        row4bTex,
        (C and C.RING_TEXTURES) or {},
        (C and C.TEXTURE_ORDER) or {},
        db.Cast.Texture or "ring_normal",
        GetCastColor,
        function(textureName)
            db.Cast.Texture = textureName
            RefreshModule()
        end,
        "Texture"
    )
    castTextureSelector:SetParent(row4bTex)
    castTextureSelector:SetPoint("TOPLEFT", row4bTex, "TOPLEFT", 0, 0)
    castTextureSelector:SetPoint("TOPRIGHT", row4bTex, "TOPRIGHT", 0, 0)
    manager:Register(castTextureSelector, "castEnabled")
    card4:AddRow(row4bTex, 82)

    local row4b = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local castSize = GUIFrame:CreateSlider(row4b, "Size", {
        min = 16, max = 200, step = 1,
        value = db.Cast.Size or 72,
        callback = function(val) db.Cast.Size = val; RefreshModule() end,
    })
    row4b:AddWidget(castSize, 1)
    manager:Register(castSize, "castEnabled")
    card4:AddRow(row4b, Theme.rowHeight)

    -- Sub-separator between shape (Size/Texture) and color sections
    local row4midSep = GUIFrame:CreateRow(card4.content, Theme.rowHeightSeparator)
    local sep4mid = GUIFrame:CreateSeparator(row4midSep)
    row4midSep:AddWidget(sep4mid, 1)
    manager:Register(sep4mid, "castEnabled")
    card4:AddRow(row4midSep, Theme.rowHeightSeparator)

    -- Ring color: Mode + Picker + Show Spark (Spark grouped with cast visuals)
    local row4cRing = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local castRingMode = GUIFrame:CreateDropdown(row4cRing, "Ring Color Mode", {
        options = KE.ColorModeOptions,
        value = db.Cast.RingColorMode or "class",
        callback = function(key)
            db.Cast.RingColorMode = key
            RefreshModule()
            RefreshStates()
            if castTextureSelector and castTextureSelector.RefreshColors then castTextureSelector:RefreshColors() end
        end,
    })
    row4cRing:AddWidget(castRingMode, 0.4)
    manager:Register(castRingMode, "castEnabled")

    local castRingColor = GUIFrame:CreateColorPicker(row4cRing, "Ring Color", {
        color = db.Cast.RingColor or { 1, 1, 1, 1 },
        callback = function(r, g, b, a)
            db.Cast.RingColor = { r, g, b, a }
            RefreshModule()
            if castTextureSelector and castTextureSelector.RefreshColors then castTextureSelector:RefreshColors() end
        end,
    })
    row4cRing:AddWidget(castRingColor, 0.4)
    manager:Register(castRingColor, "castRingCustom")

    local castSpark = GUIFrame:CreateCheckbox(row4cRing, "Show Spark", {
        value = db.Cast.SparkEnabled ~= false,
        callback = function(checked) db.Cast.SparkEnabled = checked; RefreshModule() end,
    })
    row4cRing:AddWidget(castSpark, 0.2)
    manager:Register(castSpark, "castEnabled")
    card4:AddRow(row4cRing, Theme.rowHeight)

    -- Swipe color: Mode + Picker
    local row4cSwipe = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local castSwipeMode = GUIFrame:CreateDropdown(row4cSwipe, "Swipe Color Mode", {
        options = KE.ColorModeOptions,
        value = db.Cast.SwipeColorMode or "theme",
        callback = function(key)
            db.Cast.SwipeColorMode = key
            RefreshModule()
            RefreshStates()
        end,
    })
    row4cSwipe:AddWidget(castSwipeMode, 0.5)
    manager:Register(castSwipeMode, "castEnabled")

    local castSwipeColor = GUIFrame:CreateColorPicker(row4cSwipe, "Swipe Color", {
        color = db.Cast.SwipeColor or { 1, 1, 1, 0.7 },
        callback = function(r, g, b, a)
            db.Cast.SwipeColor = { r, g, b, a }
            RefreshModule()
        end,
    })
    row4cSwipe:AddWidget(castSwipeColor, 0.5)
    manager:Register(castSwipeColor, "castSwipeCustom")
    card4:AddRow(row4cSwipe, Theme.rowHeightLast, 0)

    yOffset = card4:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Cursor Trail (EUI parity — single toggle + Density)
    -- DotDuration / DotBaseSize / ColorInherit / Color stay DB-only.
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Cursor Trail", yOffset)
    manager:Register(card5, "all")

    local row5a = GUIFrame:CreateRow(card5.content, Theme.rowHeight)
    local trailEnable = GUIFrame:CreateCheckbox(row5a, "Enable Trail", {
        value = db.Trail.Enabled == true,
        callback = function(checked)
            db.Trail.Enabled = checked
            RefreshModule()
            RefreshStates()
        end,
    })
    row5a:AddWidget(trailEnable, 1)
    manager:Register(trailEnable, "all")
    card5:AddRow(row5a, Theme.rowHeight)

    local row5sep = GUIFrame:CreateRow(card5.content, Theme.rowHeightSeparator)
    local sep5 = GUIFrame:CreateSeparator(row5sep)
    row5sep:AddWidget(sep5, 1)
    manager:Register(sep5, "all")
    card5:AddRow(row5sep, Theme.rowHeightSeparator)

    -- Density slider 1-100, where 100 = densest. Mapping uses LOG of spawn rate
    -- (1/density) so equal slider increments produce equal *perceptual* density
    -- changes. Linear-density felt 0-50 barely moves and 50-100 jumps a lot
    -- because rate scales as 1/d.
    local RATE_MIN, RATE_MAX = 20, 250  -- spawns/sec at slider=1 vs slider=100
    local function densityToSlider(d)
        local rate = 1 / (d or 0.016)
        rate = math.max(RATE_MIN, math.min(RATE_MAX, rate))
        local fraction = math.log(rate / RATE_MIN) / math.log(RATE_MAX / RATE_MIN)
        return math.floor(1 + fraction * 99 + 0.5)
    end
    local function sliderToDensity(s)
        local fraction = (s - 1) / 99
        local rate = RATE_MIN * (RATE_MAX / RATE_MIN) ^ fraction
        return 1 / rate
    end

    local row5b = GUIFrame:CreateRow(card5.content, Theme.rowHeight)
    local trailDensity = GUIFrame:CreateSlider(row5b, "Trail Intensity", {
        min = 1, max = 100, step = 1,
        value = densityToSlider(db.Trail.Density),
        callback = function(val) db.Trail.Density = sliderToDensity(val) end,
    })
    row5b:AddWidget(trailDensity, 1)
    manager:Register(trailDensity, "trailEnabled")
    card5:AddRow(row5b, Theme.rowHeight)

    -- Trail color: Mode (Inherit Cursor / Custom) + Custom Color picker
    local row5c = GUIFrame:CreateRow(card5.content, Theme.rowHeightLast)
    local trailColorMode = GUIFrame:CreateDropdown(row5c, "Color Mode", {
        options = {
            { key = "inherit", text = "Inherit Cursor Color" },
            { key = "custom",  text = "Custom" },
        },
        value = (db.Trail.ColorInherit == false) and "custom" or "inherit",
        callback = function(key)
            db.Trail.ColorInherit = (key == "inherit")
            RefreshModule()
            RefreshStates()
        end,
    })
    row5c:AddWidget(trailColorMode, 0.5)
    manager:Register(trailColorMode, "trailEnabled")

    local trailColorPicker = GUIFrame:CreateColorPicker(row5c, "Custom Color", {
        color = db.Trail.Color or { 1, 1, 1, 1 },
        callback = function(r, g, b, a)
            db.Trail.Color = { r, g, b, a }
            RefreshModule()
        end,
    })
    row5c:AddWidget(trailColorPicker, 0.5)
    manager:Register(trailColorPicker, "trailCustomColor")
    card5:AddRow(row5c, Theme.rowHeightLast, 0)

    yOffset = card5:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 6: Dispel Countdown
    ----------------------------------------------------------------
    local card6 = GUIFrame:CreateCard(scrollChild, "Dispel Countdown", yOffset)
    manager:Register(card6, "all")

    local row6a = GUIFrame:CreateRow(card6.content, Theme.rowHeight)
    local dispelEnable = GUIFrame:CreateCheckbox(row6a, "Enable Dispel Countdown", {
        value = db.Dispel.Enabled == true,
        callback = function(checked)
            db.Dispel.Enabled = checked
            RefreshModule()
            RefreshStates()
        end,
    })
    row6a:AddWidget(dispelEnable, 0.6)
    manager:Register(dispelEnable, "all")

    -- Test button: 7-second preview so users can verify placement without
    -- waiting for a real dispel cooldown. Always enabled (works with feature off too).
    local dispelTest = GUIFrame:CreateButton(row6a, "Test (7s countdown)", {
        height = 30,
        callback = function()
            local mod = GetModule()
            if mod and mod.DispelPreview then mod:DispelPreview() end
        end,
    })
    row6a:AddWidget(dispelTest, 0.4)
    manager:Register(dispelTest, "all")
    card6:AddRow(row6a, Theme.rowHeight)

    local row6sep = GUIFrame:CreateRow(card6.content, Theme.rowHeightSeparator)
    local sep6 = GUIFrame:CreateSeparator(row6sep)
    row6sep:AddWidget(sep6, 1)
    manager:Register(sep6, "all")
    card6:AddRow(row6sep, Theme.rowHeightSeparator)

    local row6b = GUIFrame:CreateRow(card6.content, Theme.rowHeight)
    local dispelAnchor = GUIFrame:CreateDropdown(row6b, "Anchor Point", {
        options = {
            { key = "TOP",    text = "Top" },
            { key = "BOTTOM", text = "Bottom" },
            { key = "LEFT",   text = "Left" },
            { key = "RIGHT",  text = "Right" },
            { key = "CENTER", text = "Center" },
        },
        value = db.Dispel.AnchorPoint or "BOTTOM",
        callback = function(key) db.Dispel.AnchorPoint = key; RefreshModule() end,
    })
    row6b:AddWidget(dispelAnchor, 1)
    manager:Register(dispelAnchor, "dispelEnabled")
    card6:AddRow(row6b, Theme.rowHeight)

    local row6c = GUIFrame:CreateRow(card6.content, Theme.rowHeight)
    local dispelX = GUIFrame:CreateSlider(row6c, "X Offset", {
        min = -50, max = 50, step = 1,
        value = db.Dispel.XOffset or 10,
        callback = function(val) db.Dispel.XOffset = val; RefreshModule() end,
    })
    row6c:AddWidget(dispelX, 0.5)
    manager:Register(dispelX, "dispelEnabled")

    local dispelY = GUIFrame:CreateSlider(row6c, "Y Offset", {
        min = -50, max = 50, step = 1,
        value = db.Dispel.YOffset or 10,
        callback = function(val) db.Dispel.YOffset = val; RefreshModule() end,
    })
    row6c:AddWidget(dispelY, 0.5)
    manager:Register(dispelY, "dispelEnabled")
    card6:AddRow(row6c, Theme.rowHeight)

    local row6d = GUIFrame:CreateRow(card6.content, Theme.rowHeightLast)
    local dispelFontSize = GUIFrame:CreateSlider(row6d, "Font Size", {
        min = 8, max = 48, step = 1,
        value = db.Dispel.FontSize or 18,
        callback = function(val) db.Dispel.FontSize = val; RefreshModule() end,
    })
    row6d:AddWidget(dispelFontSize, 0.5)
    manager:Register(dispelFontSize, "dispelEnabled")

    local dispelTextColor = GUIFrame:CreateColorPicker(row6d, "Text Color", {
        color = db.Dispel.TextColor or { 1, 1, 1, 1 },
        callback = function(r, g, b, a)
            db.Dispel.TextColor = { r, g, b, a }
            RefreshModule()
        end,
    })
    row6d:AddWidget(dispelTextColor, 0.5)
    manager:Register(dispelTextColor, "dispelEnabled")
    card6:AddRow(row6d, Theme.rowHeightLast, 0)

    yOffset = card6:GetNextOffset()

    RefreshStates()
    return yOffset
end)
