-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-DeathNotifications.lua                              ║
-- ║  GUI: Death Notifications                                ║
-- ║  Purpose: Configuration panel for the                    ║
-- ║           DeathNotifications module.                     ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme    = KE.Theme
local LSM      = KE.LSM or LibStub("LibSharedMedia-3.0", true)

local table_insert = table.insert
local ipairs, pairs = ipairs, pairs

GUIFrame:RegisterContent("DeathNotifications", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.Dungeons.DeathNotifications
    if not db then return yOffset end

    local allWidgets = {}

    local function GetModule()
        return KitnEssentials and KitnEssentials:GetModule("DeathNotifications", true)
    end

    local function ApplySettings()
        local mod = GetModule()
        if mod and mod.ApplySettings then mod:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not KitnEssentials then return end
        local mod = GetModule()
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("DeathNotifications")
        else
            KitnEssentials:DisableModule("DeathNotifications")
        end
    end

    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false
        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then widget:SetEnabled(mainEnabled) end
        end
    end

    db.PartyDeath = db.PartyDeath or {}
    db.FocusDeath = db.FocusDeath or {}

    ---------------------------------------------------------------------------------
    -- Card 1: Enable
    ---------------------------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Death Notifications", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Death Notifications",
        db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            UpdateAllWidgetStates()
        end,
        true, "Death Notifications", "On", "Off")
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, 36)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 2: Activation Context
    ---------------------------------------------------------------------------------
    local cardContext = GUIFrame:CreateCard(scrollChild, "Active In", yOffset)
    table_insert(allWidgets, cardContext)

    local cRow = GUIFrame:CreateRow(cardContext.content, 36)
    local dungeonsCheck = GUIFrame:CreateCheckbox(cRow, "Dungeons (5-man)",
        db.EnableInDungeons ~= false,
        function(checked) db.EnableInDungeons = checked end,
        true, "Dungeons", "On", "Off")
    cRow:AddWidget(dungeonsCheck, 0.5)
    table_insert(allWidgets, dungeonsCheck)

    local raidsCheck = GUIFrame:CreateCheckbox(cRow, "Raids", db.EnableInRaids == true,
        function(checked) db.EnableInRaids = checked end,
        true, "Raids", "On", "Off")
    cRow:AddWidget(raidsCheck, 0.5)
    table_insert(allWidgets, raidsCheck)
    cardContext:AddRow(cRow, 36)

    yOffset = yOffset + cardContext:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 3: Party / Raid Death
    ---------------------------------------------------------------------------------
    local cardPD = GUIFrame:CreateCard(scrollChild, "Party / Raid Death", yOffset)
    table_insert(allWidgets, cardPD)

    local pdRow1 = GUIFrame:CreateRow(cardPD.content, 36)
    local pdEnableCheck = GUIFrame:CreateCheckbox(pdRow1, "Show Party Death",
        db.PartyDeath.Enabled ~= false,
        function(checked) db.PartyDeath.Enabled = checked; ApplySettings() end,
        true, "Party Death", "On", "Off")
    pdRow1:AddWidget(pdEnableCheck, 0.5)
    table_insert(allWidgets, pdEnableCheck)

    local pdClassCheck = GUIFrame:CreateCheckbox(pdRow1, "Use Class Color for Name",
        db.PartyDeath.UseClassColor ~= false,
        function(checked) db.PartyDeath.UseClassColor = checked; ApplySettings() end,
        true, "Class Color", "On", "Off")
    pdRow1:AddWidget(pdClassCheck, 0.5)
    table_insert(allWidgets, pdClassCheck)
    cardPD:AddRow(pdRow1, 36)

    local pdRow2 = GUIFrame:CreateRow(cardPD.content, 40)
    local pdFormatBox = GUIFrame:CreateEditBox(pdRow2, "Text Format (use %name)",
        db.PartyDeath.TextFormat or "%name DIED",
        function(value)
            db.PartyDeath.TextFormat = value
            ApplySettings()
        end)
    pdRow2:AddWidget(pdFormatBox, 0.7)
    table_insert(allWidgets, pdFormatBox)

    local pdColorPicker = GUIFrame:CreateColorPicker(pdRow2, "Text Color",
        db.PartyDeath.TextColor or { 1, 1, 1, 1 },
        function(r, g, b, a)
            db.PartyDeath.TextColor = { r, g, b, a }
            ApplySettings()
        end)
    pdRow2:AddWidget(pdColorPicker, 0.3)
    table_insert(allWidgets, pdColorPicker)
    cardPD:AddRow(pdRow2, 40)

    yOffset = yOffset + cardPD:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 4: Focus Death
    ---------------------------------------------------------------------------------
    local cardFD = GUIFrame:CreateCard(scrollChild, "Focus Death", yOffset)
    table_insert(allWidgets, cardFD)

    local fdRow1 = GUIFrame:CreateRow(cardFD.content, 36)
    local fdEnableCheck = GUIFrame:CreateCheckbox(fdRow1, "Show Focus Death",
        db.FocusDeath.Enabled ~= false,
        function(checked) db.FocusDeath.Enabled = checked; ApplySettings() end,
        true, "Focus Death", "On", "Off")
    fdRow1:AddWidget(fdEnableCheck, 1)
    table_insert(allWidgets, fdEnableCheck)
    cardFD:AddRow(fdRow1, 36)

    local fdRow2 = GUIFrame:CreateRow(cardFD.content, 40)
    local fdTextBox = GUIFrame:CreateEditBox(fdRow2, "Text",
        db.FocusDeath.Text or "FOCUS DIED",
        function(value)
            db.FocusDeath.Text = value
            ApplySettings()
        end)
    fdRow2:AddWidget(fdTextBox, 0.7)
    table_insert(allWidgets, fdTextBox)

    local fdColorPicker = GUIFrame:CreateColorPicker(fdRow2, "Text Color",
        db.FocusDeath.Color or { 1, 0.3, 0.3, 1 },
        function(r, g, b, a)
            db.FocusDeath.Color = { r, g, b, a }
            ApplySettings()
        end)
    fdRow2:AddWidget(fdColorPicker, 0.3)
    table_insert(allWidgets, fdColorPicker)
    cardFD:AddRow(fdRow2, 40)

    yOffset = yOffset + cardFD:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 5: Font Settings
    ---------------------------------------------------------------------------------
    local cardFont = GUIFrame:CreateCard(scrollChild, "Font Settings", yOffset)
    table_insert(allWidgets, cardFont)

    local fontList = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do fontList[name] = name end
    else
        fontList["Friz Quadrata TT"] = "Friz Quadrata TT"
    end

    local fRow1 = GUIFrame:CreateRow(cardFont.content, 40)
    local fontDropdown = GUIFrame:CreateDropdown(fRow1, "Font", fontList,
        db.FontFace or "Expressway", 30,
        function(key) db.FontFace = key; ApplySettings() end)
    fRow1:AddWidget(fontDropdown, 0.5)
    table_insert(allWidgets, fontDropdown)

    local outlineList = {
        { key = "NONE",         text = "None" },
        { key = "OUTLINE",      text = "Outline" },
        { key = "THICKOUTLINE", text = "Thick" },
        { key = "SOFTOUTLINE",  text = "Soft" },
    }
    local outlineDropdown = GUIFrame:CreateDropdown(fRow1, "Outline", outlineList,
        db.FontOutline or "SOFTOUTLINE", 45,
        function(key) db.FontOutline = key; ApplySettings() end)
    fRow1:AddWidget(outlineDropdown, 0.5)
    table_insert(allWidgets, outlineDropdown)
    cardFont:AddRow(fRow1, 40)

    local fRow2 = GUIFrame:CreateRow(cardFont.content, 37)
    local fontSizeSlider = GUIFrame:CreateSlider(fRow2, "Font Size", 12, 64, 1,
        db.FontSize or 18, 60,
        function(val) db.FontSize = val; ApplySettings() end)
    fRow2:AddWidget(fontSizeSlider, 1)
    table_insert(allWidgets, fontSizeSlider)
    cardFont:AddRow(fRow2, 37)

    yOffset = yOffset + cardFont:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 6: Display
    ---------------------------------------------------------------------------------
    local cardDisplay = GUIFrame:CreateCard(scrollChild, "Display", yOffset)
    table_insert(allWidgets, cardDisplay)

    local dRow1 = GUIFrame:CreateRow(cardDisplay.content, 40)
    local durationSlider = GUIFrame:CreateSlider(dRow1, "Duration (s)", 1, 10, 1,
        db.Duration or 3, nil,
        function(val) db.Duration = val; ApplySettings() end)
    dRow1:AddWidget(durationSlider, 0.5)
    table_insert(allWidgets, durationSlider)

    local spacingSlider = GUIFrame:CreateSlider(dRow1, "Spacing", 0, 20, 1,
        db.Spacing or 4, nil,
        function(val) db.Spacing = val; ApplySettings() end)
    dRow1:AddWidget(spacingSlider, 0.5)
    table_insert(allWidgets, spacingSlider)
    cardDisplay:AddRow(dRow1, 40)

    local dRow2 = GUIFrame:CreateRow(cardDisplay.content, 40)
    local growDropdown = GUIFrame:CreateDropdown(dRow2, "Grow Direction",
        { { value = "DOWN", text = "Down" }, { value = "UP", text = "Up" } },
        db.Grow or "DOWN",
        function(value) db.Grow = value; ApplySettings() end)
    dRow2:AddWidget(growDropdown, 0.5)
    table_insert(allWidgets, growDropdown)

    local classIconCheck = GUIFrame:CreateCheckbox(dRow2, "Show Class Icon",
        db.ShowClassIcon ~= false,
        function(checked) db.ShowClassIcon = checked; ApplySettings() end,
        true, "Class Icon", "On", "Off")
    dRow2:AddWidget(classIconCheck, 0.5)
    table_insert(allWidgets, classIconCheck)
    cardDisplay:AddRow(dRow2, 40)

    yOffset = yOffset + cardDisplay:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 6: Position
    ---------------------------------------------------------------------------------
    local cardPos, newOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            anchorFrameType = "anchorFrameType",
            anchorFrameFrame = "ParentFrame",
            selfPoint = nil,
            anchorPoint = "AnchorTo",
            xOffset = "XOffset",
            yOffset = "YOffset",
            strata = "Strata",
        },
        positionTable = db.Position,
        showAnchorFrameType = false,
        showStrata = true,
        showPixelSnap = true,
        onChangeCallback = ApplySettings,
    })

    if cardPos.positionWidgets then
        for _, widget in ipairs(cardPos.positionWidgets) do
            table_insert(allWidgets, widget)
        end
    end
    table_insert(allWidgets, cardPos)
    yOffset = newOffset

    UpdateAllWidgetStates()
    yOffset = yOffset - Theme.paddingSmall
    return yOffset
end)
