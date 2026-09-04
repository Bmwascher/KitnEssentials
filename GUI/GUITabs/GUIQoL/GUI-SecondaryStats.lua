-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-SecondaryStats.lua                                  ║
-- ║  GUI: Secondary Stats                                    ║
-- ║  Purpose: Configuration panel for the                    ║
-- ║           SecondaryStats module.                         ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local STAT_KEYS = { "crit", "haste", "mastery", "vers", "leech", "avoidance", "speed" }
local STAT_TEXT = {
    crit = "Crit", haste = "Haste", mastery = "Mastery", vers = "Versatility",
    leech = "Leech", avoidance = "Avoidance", speed = "Speed",
}

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("SecondaryStats", true)
    end
    return nil
end

GUIFrame:RegisterContent("SecondaryStats", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.SecondaryStats
    if not db then return yOffset end

    local SS = GetModule()
    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        if SS then SS:ApplySettings() end
    end

    local function ApplyState(enabled)
        if not SS then return end
        db.Enabled = enabled
        if enabled then KitnEssentials:EnableModule("SecondaryStats")
        else KitnEssentials:DisableModule("SecondaryStats") end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Secondary Stats", yOffset)
    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        ApplyState(checked)
        KE:Print("Secondary Stats: " .. (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
    end)

    local noteRow = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Shows your secondary and tertiary stats on screen.",
        40, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, Theme.rowHeight, 0)

    yOffset = card1:GetNextOffset()

    if db.Enabled == false then return yOffset end

    ----------------------------------------------------------------
    -- Card 2: Position Settings
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Position Settings",
        db = db,
        dbKeys = {
            selfPoint = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset = "XOffset",
            yOffset = "YOffset",
        },
        showAnchorFrameType = true,
        showStrata = true,
        onChangeCallback = ApplySettings,
    })

    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "all")
    end
    manager:Register(posCard, "all")
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 3: Font Settings
    ----------------------------------------------------------------
    local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            fontFace = "FontFace",
            fontSize = "FontSize",
            fontOutline = "FontOutline",
        },
        fontSizeRange = { 8, 32 },
        onChangeCallback = ApplySettings,
    })
    manager:Register(fontCard, "all")
    if fontWidgets then
        manager:RegisterGroup(fontWidgets, "all")
    end
    yOffset = fontOffset

    ----------------------------------------------------------------
    -- Card 4: Stats to Show
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Stats to Show", yOffset)
    manager:Register(card4, "all")

    -- Ordered arrays, not maps: the dropdown sorts a map by key, which would
    -- list Both before Percent and put None first in the separator list.
    local modeList = {
        { key = "percent", text = "Percent" },
        { key = "rating", text = "Rating" },
        { key = "both", text = "Both" },
    }

    local labelStyleList = {
        { key = "full", text = "Full Word" },
        { key = "short", text = "Single Letter" },
        { key = "hidden", text = "No Label" },
    }

    local separatorList = {
        { key = ":", text = "Colon" },
        { key = "-", text = "Dash" },
        { key = "/", text = "Slash" },
        { key = "|", text = "Pipe" },
        { key = "", text = "None" },
    }

    local colorModeList = {
        { key = "palette", text = "One Per Stat" },
        { key = "class", text = "Class Color" },
        { key = "custom", text = "Custom" },
    }

    local tertiaryModeList = {
        { key = "class", text = "Class Color" },
        { key = "custom", text = "Custom" },
    }

    for index = 1, #STAT_KEYS do
        local key = STAT_KEYS[index]
        local isLast = index == #STAT_KEYS
        local rowHeight = isLast and Theme.rowHeightLast or Theme.rowHeight
        local row = GUIFrame:CreateRow(card4.content, rowHeight)

        local shownCheck = GUIFrame:CreateCheckbox(row, STAT_TEXT[key], {
            value = db.Stats[key].Shown == true,
            callback = function(checked)
                db.Stats[key].Shown = checked
                ApplySettings()
            end,
        })
        row:AddWidget(shownCheck, 0.5)
        manager:Register(shownCheck, "all")

        local modeDropdown = GUIFrame:CreateDropdown(row, "Show As", {
            options = modeList,
            value = db.Stats[key].ValueMode or "percent",
            callback = function(selected)
                db.Stats[key].ValueMode = selected
                ApplySettings()
            end,
        })
        row:AddWidget(modeDropdown, 0.5)
        manager:Register(modeDropdown, "all")

        card4:AddRow(row, rowHeight, isLast and 0 or nil)
    end

    yOffset = card4:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Text
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Text", yOffset)
    manager:Register(card5, "all")

    local row5a = GUIFrame:CreateRow(card5.content, Theme.rowHeight)
    local labelDropdown = GUIFrame:CreateDropdown(row5a, "Label Style", {
        options = labelStyleList,
        value = db.LabelStyle or "full",
        callback = function(selected)
            db.LabelStyle = selected
            ApplySettings()
        end,
    })
    row5a:AddWidget(labelDropdown, 0.5)
    manager:Register(labelDropdown, "all")

    local sepDropdown = GUIFrame:CreateDropdown(row5a, "Separator", {
        options = separatorList,
        value = db.Separator or ":",
        callback = function(selected)
            db.Separator = selected
            ApplySettings()
        end,
    })
    row5a:AddWidget(sepDropdown, 0.5)
    manager:Register(sepDropdown, "all")
    card5:AddRow(row5a, Theme.rowHeight)

    local row5b = GUIFrame:CreateRow(card5.content, Theme.rowHeight)
    local decimalSlider = GUIFrame:CreateSlider(row5b, "Decimal Places", {
        min = 0, max = 3, step = 1,
        value = db.Decimals or 2,
        callback = function(val)
            db.Decimals = val
            ApplySettings()
        end,
    })
    row5b:AddWidget(decimalSlider, 0.5)
    manager:Register(decimalSlider, "all")

    local scaleSlider = GUIFrame:CreateSlider(row5b, "Scale", {
        min = 0.5, max = 2.0, step = 0.05,
        value = db.Scale or 1.0,
        callback = function(val)
            db.Scale = val
            ApplySettings()
        end,
    })
    row5b:AddWidget(scaleSlider, 0.5)
    manager:Register(scaleSlider, "all")
    card5:AddRow(row5b, Theme.rowHeight)

    local row5c = GUIFrame:CreateRow(card5.content, Theme.rowHeightLast)
    local gapSlider = GUIFrame:CreateSlider(row5c, "Row Spacing", {
        min = 0, max = 12, step = 1,
        value = db.RowGap or 3,
        callback = function(val)
            db.RowGap = val
            ApplySettings()
        end,
    })
    row5c:AddWidget(gapSlider, 1)
    manager:Register(gapSlider, "all")
    card5:AddRow(row5c, Theme.rowHeightLast, 0)

    yOffset = card5:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 6: Colors
    ----------------------------------------------------------------
    local card6 = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    manager:Register(card6, "all")

    local row6a = GUIFrame:CreateRow(card6.content, Theme.rowHeight)
    local colorDropdown = GUIFrame:CreateDropdown(row6a, "Label Color", {
        options = colorModeList,
        value = db.ColorMode or "palette",
        callback = function(selected)
            db.ColorMode = selected
            ApplySettings()
        end,
    })
    row6a:AddWidget(colorDropdown, 0.5)
    manager:Register(colorDropdown, "all")

    local customPicker = GUIFrame:CreateColorPicker(row6a, "Custom Label Color", {
        color = db.CustomColor,
        callback = function(r, g, b)
            db.CustomColor = { r, g, b }
            ApplySettings()
        end,
    })
    row6a:AddWidget(customPicker, 0.5)
    manager:Register(customPicker, "all")
    card6:AddRow(row6a, Theme.rowHeight)

    local row6b = GUIFrame:CreateRow(card6.content, Theme.rowHeight)
    local tertDropdown = GUIFrame:CreateDropdown(row6b, "Leech / Avoidance / Speed Color", {
        options = tertiaryModeList,
        value = db.TertiaryColorMode or "class",
        callback = function(selected)
            db.TertiaryColorMode = selected
            ApplySettings()
        end,
    })
    row6b:AddWidget(tertDropdown, 0.5)
    manager:Register(tertDropdown, "all")

    local tertPicker = GUIFrame:CreateColorPicker(row6b, "Custom Tertiary Color", {
        color = db.TertiaryColor,
        callback = function(r, g, b)
            db.TertiaryColor = { r, g, b }
            ApplySettings()
        end,
    })
    row6b:AddWidget(tertPicker, 0.5)
    manager:Register(tertPicker, "all")
    card6:AddRow(row6b, Theme.rowHeight)

    local row6c = GUIFrame:CreateRow(card6.content, Theme.rowHeightLast)
    local coloredCheck = GUIFrame:CreateCheckbox(row6c, "Color the Numbers Too", {
        value = db.ColoredValues == true,
        callback = function(checked)
            db.ColoredValues = checked
            ApplySettings()
        end,
    })
    row6c:AddWidget(coloredCheck, 1)
    manager:Register(coloredCheck, "all")
    card6:AddRow(row6c, Theme.rowHeightLast, 0)

    yOffset = card6:GetNextOffset()

    RefreshStates()
    return yOffset
end)
