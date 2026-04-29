-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-TextFormatCard.lua                                  ║
-- ║  Purpose: Format string + justify + X/Y offset card.     ║
-- ║  Used by any module displaying configurable text.        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local table_insert = table.insert

local TEXT_JUSTIFY_OPTIONS = {
    { key = "LEFT",   text = "Left" },
    { key = "CENTER", text = "Center" },
    { key = "RIGHT",  text = "Right" },
}

function GUIFrame:CreateTextFormatCard(scrollChild, yOffset, config)
    config = config or {}
    local title = config.title or "Text Format"
    local db = config.db
    local dbKeys = config.dbKeys or {}
    local onChange = config.onChangeCallback
    local defaults = config.defaults or {}

    local keys = {
        format = dbKeys.format or "textFormat",
        justify = dbKeys.justify or "textJustify",
        xOffset = dbKeys.xOffset or "textXOffset",
        yOffset = dbKeys.yOffset or "textYOffset",
    }

    local defaultValues = {
        format = defaults.format or "%n",
        justify = defaults.justify or "LEFT",
        xOffset = defaults.xOffset or 4,
        yOffset = defaults.yOffset or 0,
    }

    local widgets = {}
    local card = GUIFrame:CreateCard(scrollChild, title, yOffset)

    local row1 = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local formatInput = GUIFrame:CreateEditBox(row1, "Format", {
        value = db[keys.format] or defaultValues.format,
        callback = function(text)
            db[keys.format] = text
            if onChange then onChange() end
        end
    })
    row1:AddWidget(formatInput, 0.5)
    table_insert(widgets, formatInput)

    local justifyDropdown = GUIFrame:CreateDropdown(row1, "Align", {
        options = TEXT_JUSTIFY_OPTIONS,
        value = db[keys.justify] or defaultValues.justify,
        callback = function(key)
            db[keys.justify] = key
            if onChange then onChange() end
        end
    })
    row1:AddWidget(justifyDropdown, 0.5)
    table_insert(widgets, justifyDropdown)
    card:AddRow(row1, Theme.rowHeight)

    local row2 = GUIFrame:CreateRow(card.content, Theme.rowHeightLast)
    local xSlider = GUIFrame:CreateSlider(row2, "X Offset", {
        min = -100,
        max = 100,
        step = 1,
        value = db[keys.xOffset] or defaultValues.xOffset,
        labelWidth = 50,
        callback = function(val)
            db[keys.xOffset] = val
            if onChange then onChange() end
        end
    })
    row2:AddWidget(xSlider, 0.5)
    table_insert(widgets, xSlider)

    local ySlider = GUIFrame:CreateSlider(row2, "Y Offset", {
        min = -20,
        max = 20,
        step = 1,
        value = db[keys.yOffset] or defaultValues.yOffset,
        labelWidth = 50,
        callback = function(val)
            db[keys.yOffset] = val
            if onChange then onChange() end
        end
    })
    row2:AddWidget(ySlider, 0.5)
    table_insert(widgets, ySlider)
    card:AddRow(row2, Theme.rowHeightLast, 0)

    card.textWidgets = widgets

    function card:SetEnabled(enabled)
        if enabled then
            self:SetAlpha(1)
        else
            self:SetAlpha(0.5)
        end
        for _, widget in ipairs(self.textWidgets) do
            if widget.SetEnabled then
                widget:SetEnabled(enabled)
            end
        end
    end

    return card, card:GetNextOffset()
end
