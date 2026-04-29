-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-FontSettingsCard.lua                                ║
-- ║  Purpose: Font face / size / outline / shadow card.      ║
-- ║  Reusable across all text-displaying modules.            ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)

local table_insert = table.insert
local pairs = pairs
local ipairs = ipairs

---Font face, size, outline settings card.
---Font shadow is intentionally NOT supported: KE GUI pages do not expose font
---shadow controls (project convention — see MEMORY.md). For visible halo
---behavior, modules should use SOFTOUTLINE instead, which the user opts into
---via the outline dropdown when `includeSoftOutline = true`.
function GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, config)
    config = config or {}
    local title = config.title or "Font Settings"
    local db = config.db
    local dbKeys = config.dbKeys or {}
    local onChange = config.onChangeCallback
    local fontSizeRange = config.fontSizeRange or { 8, 72 }
    local fontSizes = config.fontSizes
    local searchable = config.searchable ~= false
    local includeSoftOutline = config.includeSoftOutline == true

    local keys = {
        fontFace = dbKeys.fontFace or "FontFace",
        fontSize = dbKeys.fontSize or "FontSize",
        fontOutline = dbKeys.fontOutline or "FontOutline",
    }

    local function getValue(key, default)
        if key:find("%.") then
            local parts = { strsplit(".", key) }
            local current = db
            for _, part in ipairs(parts) do
                if current[part] == nil then return default end
                current = current[part]
            end
            return current
        end
        if db[key] ~= nil then return db[key] end
        return default
    end

    local function setValue(key, val)
        if key:find("%.") then
            local parts = { strsplit(".", key) }
            local current = db
            for i = 1, #parts - 1 do
                current = current[parts[i]]
            end
            current[parts[#parts]] = val
        else
            db[key] = val
        end
        if onChange then onChange() end
    end

    local widgets = {}

    local card = GUIFrame:CreateCard(scrollChild, title, yOffset)

    local fontList = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do
            fontList[name] = name
        end
    else
        fontList["Friz Quadrata TT"] = "Friz Quadrata TT"
    end

    local row1 = GUIFrame:CreateRow(card.content, Theme.rowHeight)

    local fontDropdown = GUIFrame:CreateDropdown(row1, "Font", {
        options = fontList,
        value = getValue(keys.fontFace, "Friz Quadrata TT"),
        callback = function(key)
            setValue(keys.fontFace, key)
        end,
        searchable = searchable,
        isFontPreview = true
    })
    row1:AddWidget(fontDropdown, 0.5)
    table_insert(widgets, fontDropdown)

    local outlineOptions = {
        { key = "NONE", text = "None" },
        { key = "OUTLINE", text = "Outline" },
        { key = "THICKOUTLINE", text = "Thick" },
    }
    if includeSoftOutline then
        table_insert(outlineOptions, { key = "SOFTOUTLINE", text = "Soft" })
    end

    local outlineDropdown = GUIFrame:CreateDropdown(row1, "Outline", {
        options = outlineOptions,
        value = getValue(keys.fontOutline, "OUTLINE"),
        callback = function(key)
            setValue(keys.fontOutline, key)
        end
    })
    row1:AddWidget(outlineDropdown, 0.5)
    table_insert(widgets, outlineDropdown)
    card:AddRow(row1, Theme.rowHeight)

    if fontSizes and #fontSizes > 0 then
        local maxPerRow = 2
        local lastBatchStart = math.floor((#fontSizes - 1) / maxPerRow) * maxPerRow + 1
        for i = 1, #fontSizes, maxPerRow do
            local isLast = i == lastBatchStart
            local rowHeight = isLast and Theme.rowHeightLast or Theme.rowHeight
            local row = GUIFrame:CreateRow(card.content, rowHeight)
            local countInRow = math.min(maxPerRow, #fontSizes - i + 1)
            local widthPct = 1 / countInRow
            for j = i, math.min(i + maxPerRow - 1, #fontSizes) do
                local sizeConfig = fontSizes[j]
                local sizeSlider = GUIFrame:CreateSlider(row, sizeConfig.label or "Size", {
                    min = fontSizeRange[1],
                    max = fontSizeRange[2],
                    step = 1,
                    value = getValue(sizeConfig.dbKey, 18),
                    callback = function(val)
                        setValue(sizeConfig.dbKey, val)
                    end
                })
                row:AddWidget(sizeSlider, widthPct)
                table_insert(widgets, sizeSlider)
            end
            if isLast then
                card:AddRow(row, rowHeight, 0)
            else
                card:AddRow(row, rowHeight)
            end
        end
    else
        local extraSlider = config.extraSlider
        local row2 = GUIFrame:CreateRow(card.content, Theme.rowHeightLast)
        local fontSizeSlider = GUIFrame:CreateSlider(row2, "Font Size", {
            min = fontSizeRange[1],
            max = fontSizeRange[2],
            step = 1,
            value = getValue(keys.fontSize, 18),
            labelWidth = 60,
            callback = function(val)
                setValue(keys.fontSize, val)
            end
        })
        row2:AddWidget(fontSizeSlider, extraSlider and 0.5 or 1)
        table_insert(widgets, fontSizeSlider)

        if extraSlider then
            local extra = GUIFrame:CreateSlider(row2, extraSlider.label or "Slider", {
                min = extraSlider.min or 0,
                max = extraSlider.max or 100,
                step = extraSlider.step or 1,
                value = getValue(extraSlider.dbKey, extraSlider.default or 0),
                labelWidth = extraSlider.labelWidth,
                callback = function(val)
                    setValue(extraSlider.dbKey, val)
                end
            })
            row2:AddWidget(extra, 0.5)
            table_insert(widgets, extra)
        end

        card:AddRow(row2, Theme.rowHeightLast, 0)
    end

    card.fontWidgets = widgets

    function card:SetEnabled(enabled)
        if enabled then
            self:SetAlpha(1)
            if self.header then self.header:SetAlpha(1) end
            if self.titleText then self.titleText:SetAlpha(1) end
        else
            self:SetAlpha(0.5)
            if self.header then self.header:SetAlpha(0.5) end
            if self.titleText then self.titleText:SetAlpha(0.5) end
        end

        for _, widget in ipairs(self.fontWidgets) do
            if widget.SetEnabled then
                widget:SetEnabled(enabled)
            end
        end
    end

    return card, card:GetNextOffset(), widgets
end
