-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)
local table_insert = table.insert
local table_sort = table.sort

GUIFrame:RegisterContent("CombatRes", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.CombatRes
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return yOffset + errorCard:GetContentHeight() + Theme.paddingMedium
    end

    local allWidgets = {}
    local bgWidgets = {}

    local function ApplySettings()
        if KitnEssentials then
            local mod = KitnEssentials:GetModule("CombatRes", true)
            if mod and mod.ApplySettings then mod:ApplySettings() end
        end
    end

    local function ApplyModuleState(enabled)
        if not KitnEssentials then return end
        local mod = KitnEssentials:GetModule("CombatRes", true)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("CombatRes")
        else
            KitnEssentials:DisableModule("CombatRes")
        end
    end

    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false
        local bgEnabled = db.Backdrop and db.Backdrop.Enabled == true

        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then
                widget:SetEnabled(mainEnabled)
            end
        end

        if mainEnabled then
            for _, widget in ipairs(bgWidgets) do
                if widget.SetEnabled then
                    widget:SetEnabled(bgEnabled)
                end
            end
        end
    end

    ----------------------------------------------------------------
    -- Card 1: Combat Res Tracker (Enable + Formatting Options)
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Combat Res Tracker", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, 40)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Combat Res Tracker", db.Enabled ~= false, function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            UpdateAllWidgetStates()
        end,
        true,
        "Combat Res Tracker",
        "On",
        "Off"
    )
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, 40)

    -- Separator
    local row1sep = GUIFrame:CreateRow(card1.content, 8)
    local sep1 = GUIFrame:CreateSeparator(row1sep)
    row1sep:AddWidget(sep1, 1)
    table_insert(allWidgets, sep1)
    card1:AddRow(row1sep, 8)

    local row1b = GUIFrame:CreateRow(card1.content, 39)
    local sepInput = GUIFrame:CreateEditBox(row1b, "Separator Character", db.Separator or "|", function(val)
        db.Separator = val
        ApplySettings()
    end)
    row1b:AddWidget(sepInput, 0.5)
    table_insert(allWidgets, sepInput)

    local sepChargeInput = GUIFrame:CreateEditBox(row1b, "Charge Prefix", db.SeparatorCharges or "CR:", function(val)
        db.SeparatorCharges = val
        ApplySettings()
    end)
    row1b:AddWidget(sepChargeInput, 0.5)
    table_insert(allWidgets, sepChargeInput)
    card1:AddRow(row1b, 39)

    local row1c = GUIFrame:CreateRow(card1.content, 36)
    local bracketList = { ["square"] = "[ ]", ["round"] = "( )", ["none"] = "None" }
    local bracketDropdown = GUIFrame:CreateDropdown(row1c, "Bracket Style", bracketList, db.BracketStyle or "square", 50,
        function(key)
            db.BracketStyle = key
            ApplySettings()
        end)
    row1c:AddWidget(bracketDropdown, 0.5)
    table_insert(allWidgets, bracketDropdown)
    card1:AddRow(row1c, 36)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 2: Position Settings
    ----------------------------------------------------------------
    local card2, newOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            anchorFrameType = "anchorFrameType",
            anchorFrameFrame = "ParentFrame",
            selfPoint = "AnchorFrom",
            anchorPoint = "AnchorTo",
            xOffset = "XOffset",
            yOffset = "YOffset",
            strata = "Strata",
        },
        showAnchorFrameType = true,
        showStrata = true,
        onChangeCallback = ApplySettings,
    })

    if card2.positionWidgets then
        for _, widget in ipairs(card2.positionWidgets) do
            table_insert(allWidgets, widget)
        end
    end
    table_insert(allWidgets, card2)
    yOffset = newOffset

    ----------------------------------------------------------------
    -- Card 3: Font Settings
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Font Settings", yOffset)
    table_insert(allWidgets, card3)

    local fontList = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do
            table_insert(fontList, { key = name, text = name })
        end
        table_sort(fontList, function(a, b) return a.text < b.text end)
    else
        table_insert(fontList, { key = "Friz Quadrata TT", text = "Friz Quadrata TT" })
    end

    local outlineList = {
        { key = "NONE",         text = "None" },
        { key = "OUTLINE",      text = "Outline" },
        { key = "THICKOUTLINE", text = "Thick" },
        { key = "SOFTOUTLINE",  text = "Soft" },
    }

    local growthList = {
        { key = "LEFT",  text = "Left" },
        { key = "RIGHT", text = "Right" },
    }

    -- Font and Outline
    local row3a = GUIFrame:CreateRow(card3.content, 40)
    local fontDropdown = GUIFrame:CreateDropdown(row3a, "Font", fontList, db.FontFace or "Friz Quadrata TT", 30,
        function(key)
            db.FontFace = key
            ApplySettings()
        end)
    row3a:AddWidget(fontDropdown, 0.5)
    table_insert(allWidgets, fontDropdown)

    local outlineDropdown = GUIFrame:CreateDropdown(row3a, "Outline", outlineList, db.FontOutline or "OUTLINE", 45,
        function(key)
            db.FontOutline = key
            ApplySettings()
        end)
    row3a:AddWidget(outlineDropdown, 0.5)
    table_insert(allWidgets, outlineDropdown)
    card3:AddRow(row3a, 40)

    -- Font Size and Text Spacing
    local row3b = GUIFrame:CreateRow(card3.content, 40)
    local fontSizeSlider = GUIFrame:CreateSlider(row3b, "Font Size", 8, 36, 1, db.FontSize or 16, 60,
        function(val)
            db.FontSize = val
            ApplySettings()
        end)
    row3b:AddWidget(fontSizeSlider, 0.5)
    table_insert(allWidgets, fontSizeSlider)

    local spacingSlider = GUIFrame:CreateSlider(row3b, "Text Spacing", 0, 20, 1, db.TextSpacing or 4, 80,
        function(val)
            db.TextSpacing = val
            ApplySettings()
        end)
    row3b:AddWidget(spacingSlider, 0.5)
    table_insert(allWidgets, spacingSlider)
    card3:AddRow(row3b, 40)

    -- Growth Direction
    local row3c = GUIFrame:CreateRow(card3.content, 40)
    local growthDropdown = GUIFrame:CreateDropdown(row3c, "Growth Direction", growthList,
        db.GrowthDirection or "RIGHT", 100,
        function(key)
            db.GrowthDirection = key
            ApplySettings()
        end)
    row3c:AddWidget(growthDropdown, 1)
    table_insert(allWidgets, growthDropdown)
    card3:AddRow(row3c, 40)

    yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 4: Colors
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    table_insert(allWidgets, card4)

    -- Separator and Timer colors
    local row4a = GUIFrame:CreateRow(card4.content, 39)
    local sepColor = GUIFrame:CreateColorPicker(row4a, "Separator Color", db.SeparatorColor or { 1, 1, 1, 1 },
        function(r, g, b, a)
            db.SeparatorColor = { r, g, b, a }
            ApplySettings()
        end)
    row4a:AddWidget(sepColor, 0.5)
    table_insert(allWidgets, sepColor)

    local timerColor = GUIFrame:CreateColorPicker(row4a, "Timer Text Color", db.TimerColor or { 1, 1, 1, 1 },
        function(r, g, b, a)
            db.TimerColor = { r, g, b, a }
            ApplySettings()
        end)
    row4a:AddWidget(timerColor, 0.5)
    table_insert(allWidgets, timerColor)
    card4:AddRow(row4a, 39)

    -- Charge colors
    local row4b = GUIFrame:CreateRow(card4.content, 39)
    local chargeAvailColor = GUIFrame:CreateColorPicker(row4b, "Charges Available",
        db.ChargeAvailableColor or { 0.3, 1, 0.3, 1 },
        function(r, g, b, a)
            db.ChargeAvailableColor = { r, g, b, a }
            ApplySettings()
        end)
    row4b:AddWidget(chargeAvailColor, 0.5)
    table_insert(allWidgets, chargeAvailColor)

    local chargeUnavailColor = GUIFrame:CreateColorPicker(row4b, "Charges Unavailable",
        db.ChargeUnavailableColor or { 1, 0.3, 0.3, 1 },
        function(r, g, b, a)
            db.ChargeUnavailableColor = { r, g, b, a }
            ApplySettings()
        end)
    row4b:AddWidget(chargeUnavailColor, 0.5)
    table_insert(allWidgets, chargeUnavailColor)
    card4:AddRow(row4b, 39)

    yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 5: Backdrop
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Backdrop", yOffset)
    table_insert(allWidgets, card5)
    db.Backdrop = db.Backdrop or {}

    local row5a = GUIFrame:CreateRow(card5.content, 39)
    local backdropCheck = GUIFrame:CreateCheckbox(row5a, "Enable Backdrop", db.Backdrop.Enabled ~= false,
        function(checked)
            db.Backdrop.Enabled = checked
            ApplySettings()
            UpdateAllWidgetStates()
        end)
    row5a:AddWidget(backdropCheck, 1)
    table_insert(allWidgets, backdropCheck)
    card5:AddRow(row5a, 39)

    local row5b = GUIFrame:CreateRow(card5.content, 39)
    local bgWidth = GUIFrame:CreateSlider(row5b, "Backdrop Width", 1, 600, 1, db.Backdrop.bgWidth or 100, 0,
        function(val)
            db.Backdrop.bgWidth = val
            ApplySettings()
        end)
    row5b:AddWidget(bgWidth, 0.4)
    table_insert(allWidgets, bgWidth)
    table_insert(bgWidgets, bgWidth)

    local bgHeight = GUIFrame:CreateSlider(row5b, "Backdrop Height", 1, 600, 1, db.Backdrop.bgHeight or 40, 0,
        function(val)
            db.Backdrop.bgHeight = val
            ApplySettings()
        end)
    row5b:AddWidget(bgHeight, 0.39)
    table_insert(allWidgets, bgHeight)
    table_insert(bgWidgets, bgHeight)

    local bgColor = GUIFrame:CreateColorPicker(row5b, "Backdrop Color", db.Backdrop.Color or { 0, 0, 0, 0.6 },
        function(r, g, b, a)
            db.Backdrop.Color = { r, g, b, a }
            ApplySettings()
        end)
    row5b:AddWidget(bgColor, 0.21)
    table_insert(allWidgets, bgColor)
    table_insert(bgWidgets, bgColor)
    card5:AddRow(row5b, 39)

    -- Separator
    local row5sep = GUIFrame:CreateRow(card5.content, 8)
    local sepBg = GUIFrame:CreateSeparator(row5sep)
    row5sep:AddWidget(sepBg, 1)
    table_insert(allWidgets, sepBg)
    table_insert(bgWidgets, sepBg)
    card5:AddRow(row5sep, 8)

    local row5c = GUIFrame:CreateRow(card5.content, 39)
    local borderSize = GUIFrame:CreateSlider(row5c, "Border Size", 1, 10, 1, db.Backdrop.BorderSize or 1, 0,
        function(val)
            db.Backdrop.BorderSize = val
            ApplySettings()
        end)
    row5c:AddWidget(borderSize, 0.79)
    table_insert(allWidgets, borderSize)
    table_insert(bgWidgets, borderSize)

    local borderColor = GUIFrame:CreateColorPicker(row5c, "Border Color",
        db.Backdrop.BorderColor or { 0, 0, 0, 1 },
        function(r, g, b, a)
            db.Backdrop.BorderColor = { r, g, b, a }
            ApplySettings()
        end)
    row5c:AddWidget(borderColor, 0.21)
    table_insert(allWidgets, borderColor)
    table_insert(bgWidgets, borderColor)
    card5:AddRow(row5c, 39)

    yOffset = yOffset + card5:GetContentHeight() + Theme.paddingSmall

    -- Apply initial widget states
    UpdateAllWidgetStates()
    yOffset = yOffset - (Theme.paddingSmall * 3)
    return yOffset
end)
