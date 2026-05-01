-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-TextFormatCard.lua                                  ║
-- ║  Purpose: Format string + justify + X/Y offset card.     ║
-- ║  Used by any module displaying configurable text.        ║
-- ║                                                          ║
-- ║  Pooled via KE.FramePool. Used twice per DungeonTimers   ║
-- ║  Display tab render (Text 1 + Text 2); pool grows to 2   ║
-- ║  on first render, both reused thereafter. Single shape — ║
-- ║  no config-dependent layout variants — so Configure just ║
-- ║  swaps closure slots (_db, _keys, _onChange) and sets    ║
-- ║  widget values silently.                                 ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local TEXT_JUSTIFY_OPTIONS = {
    { key = "LEFT",   text = "Left" },
    { key = "CENTER", text = "Center" },
    { key = "RIGHT",  text = "Right" },
}

---------------------------------------------------------------------------------
-- Kit factory: build one TextFormatCard's full widget set, kit-bound callbacks
---------------------------------------------------------------------------------

local function CreateTextFormatCardKit(holder)
    local kit = {}

    local card = GUIFrame:CreateCard(holder, "Text Format", 0)
    kit.card = card
    kit.row = card -- KE.FramePool reads kit.row as the root frame

    local row1 = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local formatInput = GUIFrame:CreateEditBox(row1, "Format", {
        value = "",
        callback = function(text)
            if not kit._db or not kit._keys then return end
            kit._db[kit._keys.format] = text
            if kit._onChange then kit._onChange() end
        end,
    })
    row1:AddWidget(formatInput, 0.5)

    local justifyDropdown = GUIFrame:CreateDropdown(row1, "Align", {
        options = TEXT_JUSTIFY_OPTIONS,
        value = "LEFT",
        callback = function(key)
            if not kit._db or not kit._keys then return end
            kit._db[kit._keys.justify] = key
            if kit._onChange then kit._onChange() end
        end,
    })
    row1:AddWidget(justifyDropdown, 0.5)
    card:AddRow(row1, Theme.rowHeight)

    local row2 = GUIFrame:CreateRow(card.content, Theme.rowHeightLast)
    local xSlider = GUIFrame:CreateSlider(row2, "X Offset", {
        min = -100, max = 100, step = 1, value = 0, labelWidth = 50,
        callback = function(val)
            if not kit._db or not kit._keys then return end
            kit._db[kit._keys.xOffset] = val
            if kit._onChange then kit._onChange() end
        end,
    })
    row2:AddWidget(xSlider, 0.5)

    local ySlider = GUIFrame:CreateSlider(row2, "Y Offset", {
        min = -20, max = 20, step = 1, value = 0, labelWidth = 50,
        callback = function(val)
            if not kit._db or not kit._keys then return end
            kit._db[kit._keys.yOffset] = val
            if kit._onChange then kit._onChange() end
        end,
    })
    row2:AddWidget(ySlider, 0.5)
    card:AddRow(row2, Theme.rowHeightLast, 0)

    kit.formatInput = formatInput
    kit.justifyDropdown = justifyDropdown
    kit.xSlider = xSlider
    kit.ySlider = ySlider

    -- Compatibility shim — original CreateTextFormatCard exposed
    -- card.textWidgets and card:SetEnabled walked it. The default
    -- card:SetEnabled now adds an alpha + click-blocker overlay; we keep
    -- the textWidgets shim for any consumer that reads it directly.
    local textWidgets = { formatInput, justifyDropdown, xSlider, ySlider }
    card.textWidgets = textWidgets

    -- Override card:SetEnabled to also walk text widgets so individual
    -- widget alpha/disabled state matches the card-level state. Default
    -- SetEnabled (alpha + click-blocker) is preserved by base call.
    local baseSetEnabled = card.SetEnabled
    function card:SetEnabled(enabled)
        if baseSetEnabled then baseSetEnabled(self, enabled) end
        for _, widget in ipairs(textWidgets) do
            if widget.SetEnabled then widget:SetEnabled(enabled) end
        end
    end

    return kit
end

local textFormatCardPool = KE.FramePool:New(CreateTextFormatCardKit)

GUIFrame:RegisterContentRebuildCallback("__TextFormatCardPool", function()
    textFormatCardPool:ReleaseAll()
end)

---------------------------------------------------------------------------------
-- Configure: re-anchor card, swap slots, set values silently
---------------------------------------------------------------------------------

local function ConfigureTextFormatCardKit(kit, scrollChild, yOffset, config)
    local T = Theme
    local card = kit.card

    local title = config.title or "Text Format"
    local db = config.db
    local dbKeys = config.dbKeys or {}
    local defaults = config.defaults or {}
    local onChange = config.onChangeCallback

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

    -- Swap kit slots BEFORE widget SetValue so factory-bound callbacks
    -- see the current consumer's db/keys if any silent path is bypassed.
    kit._db = db
    kit._keys = keys
    kit._onChange = onChange

    -- Re-anchor card. Acquire reparented kit.row to scrollChild but the
    -- TOPLEFT/RIGHT anchors still point at the pool's hidden holder.
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", T.paddingSmall, -(yOffset or 0) + T.paddingSmall)
    card:SetPoint("RIGHT", scrollChild, "RIGHT", -T.paddingSmall, 0)
    card._yOffset = yOffset or 0
    if card.titleText then card.titleText:SetText(title) end

    -- Set widget values without firing callbacks. EditBox.SetValue is
    -- silent (doesn't fire OnEnterPressed/OnEditFocusLost). Dropdown
    -- and Slider take a silent flag.
    kit.formatInput:SetValue(db[keys.format] or defaultValues.format)
    kit.justifyDropdown:SetValue(db[keys.justify] or defaultValues.justify, true)
    kit.xSlider:SetValue(db[keys.xOffset] or defaultValues.xOffset, true)
    kit.ySlider:SetValue(db[keys.yOffset] or defaultValues.yOffset, true)

    return card
end

---------------------------------------------------------------------------------
-- Public entry: CreateTextFormatCard
---------------------------------------------------------------------------------

function GUIFrame:CreateTextFormatCard(scrollChild, yOffset, config)
    config = config or {}
    local kit = textFormatCardPool:Acquire(scrollChild)
    ConfigureTextFormatCardKit(kit, scrollChild, yOffset, config)
    return kit.card, kit.card:GetNextOffset()
end
