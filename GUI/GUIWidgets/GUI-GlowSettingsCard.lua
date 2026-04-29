-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-GlowSettingsCard.lua                                ║
-- ║  Purpose: LibCustomGlow settings (type, color, speed,    ║
-- ║  per-type controls). Used by TimeSpiral and any glow     ║
-- ║  feature that exposes its config.                        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local table_insert = table.insert
local ipairs = ipairs
local pairs = pairs

local GLOW_TYPES = {
    { key = "pixel",    text = "Pixel" },
    { key = "autocast", text = "Autocast" },
    { key = "button",   text = "Button" },
    { key = "proc",     text = "Proc" },
}

function GUIFrame:CreateGlowSettingsCard(scrollChild, yOffset, config)
    config = config or {}
    local title = config.title or "Glow Settings"
    local db = config.db
    local dbKeys = config.dbKeys or {}
    local onChange = config.onChangeCallback
    local onHeightChange = config.onHeightChange

    local keys = {
        enabled = dbKeys.enabled or "GlowEnabled",
        type = dbKeys.type or "GlowType",
        color = dbKeys.color or "GlowColor",
        lines = dbKeys.lines or "GlowLines",
        frequency = dbKeys.frequency or "GlowFrequency",
        length = dbKeys.length or "GlowLength",
        thickness = dbKeys.thickness or "GlowThickness",
        border = dbKeys.border or "GlowBorder",
        scale = dbKeys.scale or "GlowScale",
        startAnim = dbKeys.startAnim or "GlowStartAnim",
        duration = dbKeys.duration or "GlowDuration",
    }

    local widgets = {}
    local typeOnlyRows = {
        pixel = {},
        autocast = {},
        proc = {},
    }
    local frequencyRow

    local function setValue(key, val)
        db[key] = val
        if onChange then onChange() end
    end

    local card = GUIFrame:CreateCard(scrollChild, title, yOffset)

    local row1 = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Glow", {
        value = db[keys.enabled],
        callback = function(checked)
            setValue(keys.enabled, checked)
            card.updateTypeVisibility()
        end
    })
    row1:AddWidget(enableCheck, 0.5)
    table_insert(widgets, enableCheck)

    local typeDropdown = GUIFrame:CreateDropdown(row1, "Type", {
        options = GLOW_TYPES,
        value = db[keys.type],
        callback = function(val)
            setValue(keys.type, val)
            card.updateTypeVisibility()
        end
    })
    row1:AddWidget(typeDropdown, 0.5)
    table_insert(widgets, typeDropdown)
    card:AddRow(row1, Theme.rowHeight)

    local separator = GUIFrame:CreateSeparator(card.content)
    card:AddRow(separator, Theme.rowHeightSeparator)

    local row2 = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local colorPicker = GUIFrame:CreateColorPicker(row2, "Color", {
        color = db[keys.color],
        callback = function(r, g, b, a)
            db[keys.color] = { r, g, b, a }
            if onChange then onChange() end
        end
    })
    row2:AddWidget(colorPicker, 1)
    table_insert(widgets, colorPicker)
    card:AddRow(row2, Theme.rowHeight)

    local rowFreq = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local freqSlider = GUIFrame:CreateSlider(rowFreq, "Speed", {
        min = 0.05,
        max = 1,
        step = 0.05,
        value = db[keys.frequency],
        callback = function(val) setValue(keys.frequency, val) end
    })
    rowFreq:AddWidget(freqSlider, 1)
    table_insert(widgets, freqSlider)
    card:AddRow(rowFreq, Theme.rowHeight)
    frequencyRow = rowFreq

    local rowPixel1 = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local linesSlider = GUIFrame:CreateSlider(rowPixel1, "Lines", {
        min = 1,
        max = 16,
        step = 1,
        value = db[keys.lines],
        callback = function(val) setValue(keys.lines, val) end
    })
    rowPixel1:AddWidget(linesSlider, 0.5)
    table_insert(widgets, linesSlider)

    local lengthSlider = GUIFrame:CreateSlider(rowPixel1, "Length", {
        min = 1,
        max = 20,
        step = 1,
        value = db[keys.length],
        callback = function(val) setValue(keys.length, val) end
    })
    rowPixel1:AddWidget(lengthSlider, 0.5)
    table_insert(widgets, lengthSlider)
    card:AddRow(rowPixel1, Theme.rowHeight)
    table_insert(typeOnlyRows.pixel, rowPixel1)

    local rowPixel2 = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local thicknessSlider = GUIFrame:CreateSlider(rowPixel2, "Thickness", {
        min = 1,
        max = 8,
        step = 1,
        value = db[keys.thickness],
        callback = function(val) setValue(keys.thickness, val) end
    })
    rowPixel2:AddWidget(thicknessSlider, 0.5)
    table_insert(widgets, thicknessSlider)

    local borderCheck = GUIFrame:CreateCheckbox(rowPixel2, "Border", {
        value = db[keys.border],
        callback = function(checked) setValue(keys.border, checked) end
    })
    rowPixel2:AddWidget(borderCheck, 0.5)
    table_insert(widgets, borderCheck)
    card:AddRow(rowPixel2, Theme.rowHeight)
    table_insert(typeOnlyRows.pixel, rowPixel2)

    local rowAutocast = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local particlesSlider = GUIFrame:CreateSlider(rowAutocast, "Particles", {
        min = 1,
        max = 16,
        step = 1,
        value = db[keys.lines],
        callback = function(val) setValue(keys.lines, val) end
    })
    rowAutocast:AddWidget(particlesSlider, 0.5)
    table_insert(widgets, particlesSlider)

    local scaleSlider = GUIFrame:CreateSlider(rowAutocast, "Scale", {
        min = 0.5,
        max = 3,
        step = 0.1,
        value = db[keys.scale],
        callback = function(val) setValue(keys.scale, val) end
    })
    rowAutocast:AddWidget(scaleSlider, 0.5)
    table_insert(widgets, scaleSlider)
    card:AddRow(rowAutocast, Theme.rowHeight)
    table_insert(typeOnlyRows.autocast, rowAutocast)

    local rowProc = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local startAnimCheck = GUIFrame:CreateCheckbox(rowProc, "Start Animation", {
        value = db[keys.startAnim],
        callback = function(checked) setValue(keys.startAnim, checked) end
    })
    rowProc:AddWidget(startAnimCheck, 0.5)
    table_insert(widgets, startAnimCheck)

    local durationSlider = GUIFrame:CreateSlider(rowProc, "Duration", {
        min = 0.5,
        max = 5,
        step = 0.1,
        value = db[keys.duration],
        callback = function(val) setValue(keys.duration, val) end
    })
    rowProc:AddWidget(durationSlider, 0.5)
    table_insert(widgets, durationSlider)
    card:AddRow(rowProc, Theme.rowHeight)
    table_insert(typeOnlyRows.proc, rowProc)

    card.glowWidgets = widgets
    card.typeOnlyRows = typeOnlyRows
    card.frequencyRow = frequencyRow
    card._initialized = false

    function card.updateTypeVisibility()
        local glowType = db[keys.type]
        local enabled = db[keys.enabled]

        local baseHeight = card.headerHeight + Theme.paddingSmall * 2
        local currentY = (Theme.rowHeight + Theme.paddingSmall) * 2 + Theme.rowHeightSeparator + Theme.paddingSmall

        local showFrequency = (glowType == "pixel" or glowType == "autocast" or glowType == "button")
        frequencyRow:SetShown(showFrequency)
        if showFrequency then
            frequencyRow:ClearAllPoints()
            frequencyRow:SetPoint("TOPLEFT", card.content, "TOPLEFT", 0, -currentY)
            frequencyRow:SetPoint("TOPRIGHT", card.content, "TOPRIGHT", 0, -currentY)
            currentY = currentY + Theme.rowHeight + Theme.paddingSmall
        end

        for typeName, rows in pairs(typeOnlyRows) do
            local show = (typeName == glowType)
            for _, row in ipairs(rows) do
                row:SetShown(show)
                if show then
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", card.content, "TOPLEFT", 0, -currentY)
                    row:SetPoint("TOPRIGHT", card.content, "TOPRIGHT", 0, -currentY)
                    currentY = currentY + Theme.rowHeight + Theme.paddingSmall
                end
            end
        end

        card.content:SetHeight(currentY)
        local newHeight = baseHeight + currentY
        local heightChanged = card.contentHeight ~= newHeight
        card.contentHeight = newHeight
        card:SetHeight(newHeight)

        for _, widget in ipairs(widgets) do
            if widget ~= enableCheck and widget.SetEnabled then
                widget:SetEnabled(enabled)
            end
        end

        if heightChanged and onHeightChange and card._initialized then
            onHeightChange()
        end
    end

    function card:SetEnabled(cardEnabled)
        self:SetAlpha(cardEnabled and 1 or 0.5)
        if cardEnabled then
            self.updateTypeVisibility()
        else
            for _, widget in ipairs(self.glowWidgets) do
                if widget.SetEnabled then widget:SetEnabled(false) end
            end
        end
    end

    card.updateTypeVisibility()
    card._initialized = true

    return card, card:GetNextOffset(), widgets
end
