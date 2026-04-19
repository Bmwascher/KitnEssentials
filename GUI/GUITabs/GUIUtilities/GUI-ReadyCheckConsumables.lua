-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-ReadyCheckConsumables.lua                           ║
-- ║  GUI: Ready Check Consumables                            ║
-- ║  Purpose: Configuration panel for the                    ║
-- ║           ReadyCheckConsumables module.                  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme    = KE.Theme
local LSM      = KE.LSM or LibStub("LibSharedMedia-3.0", true)
local table_insert = table.insert
local ipairs = ipairs
local pairs = pairs
local UnitClass = UnitClass

GUIFrame:RegisterContent("ReadyCheckConsumables", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.ReadyCheckConsumables
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return yOffset + errorCard:GetContentHeight() + Theme.paddingMedium
    end

    local allWidgets = {}
    local customPositionWidgets = {}
    local _, playerClass = UnitClass("player")

    local function ApplySettings()
        local mod = KitnEssentials and KitnEssentials:GetModule("ReadyCheckConsumables", true)
        if mod and mod.ApplySettings then mod:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not KitnEssentials then return end
        local mod = KitnEssentials:GetModule("ReadyCheckConsumables", true)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("ReadyCheckConsumables")
        else
            KitnEssentials:DisableModule("ReadyCheckConsumables")
        end
    end

    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false
        local isCustomPos = (db.PositionMode == "custom")

        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then widget:SetEnabled(mainEnabled) end
        end
        if mainEnabled then
            for _, widget in ipairs(customPositionWidgets) do
                if widget.SetEnabled then widget:SetEnabled(isCustomPos) end
            end
        end
    end

    ---------------------------------------------------------------------------------
    -- Card 1: Ready Check Consumables — Enable only
    ---------------------------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Ready Check Consumables", yOffset)

    local row1a = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1a,
        "Enable Ready Check Consumables", db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            UpdateAllWidgetStates()
        end,
        true, "Ready Check Consumables", "On", "Off"
    )
    row1a:AddWidget(enableCheck, 1)
    card1:AddRow(row1a, 36)

    card1:AddLabel("|cff888888Clickable consumable icons attached to the ready check popup.|r")

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 2: General Settings (icon sizing + behavior)
    ---------------------------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "General Settings", yOffset)
    table_insert(allWidgets, card2)

    local row2a = GUIFrame:CreateRow(card2.content, 40)
    local iconSizeSlider = GUIFrame:CreateSlider(row2a, "Icon Size",
        16, 64, 1, db.IconSize or 32, 60,
        function(val)
            db.IconSize = val
            ApplySettings()
        end)
    row2a:AddWidget(iconSizeSlider, 0.5)
    table_insert(allWidgets, iconSizeSlider)

    local iconSpacingSlider = GUIFrame:CreateSlider(row2a, "Icon Spacing",
        0, 16, 1, db.IconSpacing or 4, 60,
        function(val)
            db.IconSpacing = val
            ApplySettings()
        end)
    row2a:AddWidget(iconSpacingSlider, 0.5)
    table_insert(allWidgets, iconSpacingSlider)
    card2:AddRow(row2a, 40)

    -- 2x2 toggle grid: pair "hide" options on row 1, "filter" options on row 2.
    local row2b = GUIFrame:CreateRow(card2.content, 36)
    local hideStarterCheck = GUIFrame:CreateCheckbox(row2b,
        "Hide when I initiate the ready check", db.HideForStarter,
        function(checked)
            db.HideForStarter = checked
            ApplySettings()
        end
    )
    row2b:AddWidget(hideStarterCheck, 0.5)
    table_insert(allWidgets, hideStarterCheck)

    local hideMockCheck = GUIFrame:CreateCheckbox(row2b,
        "Hide Preview Box (GUI only)", db.HidePreviewMock,
        function(checked)
            db.HidePreviewMock = checked
            ApplySettings()
        end
    )
    row2b:AddWidget(hideMockCheck, 0.5)
    table_insert(allWidgets, hideMockCheck)
    card2:AddRow(row2b, 36)

    local row2c = GUIFrame:CreateRow(card2.content, 36)
    local cauldronOnlyCheck = GUIFrame:CreateCheckbox(row2c,
        "Use flasks only from raid cauldron", db.CauldronFlasksOnly,
        function(checked)
            db.CauldronFlasksOnly = checked
            ApplySettings()
        end
    )
    row2c:AddWidget(cauldronOnlyCheck, 0.5)
    table_insert(allWidgets, cauldronOnlyCheck)

    local unlimitedRuneCheck = GUIFrame:CreateCheckbox(row2c,
        "Use only unlimited augment rune", db.UnlimitedRunesOnly,
        function(checked)
            db.UnlimitedRunesOnly = checked
            ApplySettings()
        end
    )
    row2c:AddWidget(unlimitedRuneCheck, 0.5)
    table_insert(allWidgets, unlimitedRuneCheck)
    card2:AddRow(row2c, 36)

    yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 3: Visible Consumables (per-category toggles)
    ---------------------------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Visible Consumables", yOffset)
    table_insert(allWidgets, card3)

    -- Row 1: Food, Flask, Augment Rune
    local row3a = GUIFrame:CreateRow(card3.content, 36)
    local foodCheck = GUIFrame:CreateCheckbox(row3a, "Food", db.ShowFood ~= false,
        function(checked) db.ShowFood = checked; ApplySettings() end)
    row3a:AddWidget(foodCheck, 1/3)
    table_insert(allWidgets, foodCheck)

    local flaskCheck = GUIFrame:CreateCheckbox(row3a, "Flask", db.ShowFlask ~= false,
        function(checked) db.ShowFlask = checked; ApplySettings() end)
    row3a:AddWidget(flaskCheck, 1/3)
    table_insert(allWidgets, flaskCheck)

    local runeCheck = GUIFrame:CreateCheckbox(row3a, "Augment Rune", db.ShowAugmentRune ~= false,
        function(checked) db.ShowAugmentRune = checked; ApplySettings() end)
    row3a:AddWidget(runeCheck, 1/3)
    table_insert(allWidgets, runeCheck)
    card3:AddRow(row3a, 36)

    -- Row 2: Weapon Enchants MH/OH, Healthstone
    local row3b = GUIFrame:CreateRow(card3.content, 36)
    local oilCheck = GUIFrame:CreateCheckbox(row3b, "Weapon Enchant (MH)", db.ShowWeaponOil ~= false,
        function(checked) db.ShowWeaponOil = checked; ApplySettings() end)
    row3b:AddWidget(oilCheck, 1/3)
    table_insert(allWidgets, oilCheck)

    local oilOHCheck = GUIFrame:CreateCheckbox(row3b, "Weapon Enchant (OH)", db.ShowOffHandOil ~= false,
        function(checked) db.ShowOffHandOil = checked; ApplySettings() end)
    row3b:AddWidget(oilOHCheck, 1/3)
    table_insert(allWidgets, oilOHCheck)

    local hsCheck = GUIFrame:CreateCheckbox(row3b, "Healthstone", db.ShowHealthstone ~= false,
        function(checked) db.ShowHealthstone = checked; ApplySettings() end)
    row3b:AddWidget(hsCheck, 1/3)
    table_insert(allWidgets, hsCheck)
    card3:AddRow(row3b, 36)

    -- Row 3: Class Action — Warlock only (hidden entirely for other classes to
    -- avoid a dead toggle). Preview + runtime logic already gate this row.
    if playerClass == "WARLOCK" then
        local row3c = GUIFrame:CreateRow(card3.content, 36)
        local classCheck = GUIFrame:CreateCheckbox(row3c,
            "Class Action (Soulstone)", db.ShowClassItem ~= false,
            function(checked) db.ShowClassItem = checked; ApplySettings() end)
        row3c:AddWidget(classCheck, 1)
        table_insert(allWidgets, classCheck)
        card3:AddRow(row3c, 36)
    end

    card3:AddLabel("|cff888888Weapon Enchant (OH) also requires an off-hand weapon equipped. Healthstone also requires a Warlock in your group.|r")

    yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 4: Position Settings
    ---------------------------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Position Settings", yOffset)
    table_insert(allWidgets, card4)

    local row4a = GUIFrame:CreateRow(card4.content, 40)
    local posModeList = {
        { key = "auto",   text = "Auto (anchor to ready check popup)" },
        { key = "custom", text = "Custom (manual position)" },
    }
    local posModeDropdown = GUIFrame:CreateDropdown(row4a, "Position Mode", posModeList,
        db.PositionMode or "auto", 70,
        function(key)
            db.PositionMode = key
            ApplySettings()
            UpdateAllWidgetStates()
        end)
    row4a:AddWidget(posModeDropdown, 1)
    table_insert(allWidgets, posModeDropdown)
    card4:AddRow(row4a, 40)

    -- Custom-position widgets — greyed out when Auto is selected. Framework
    -- doesn't support dynamic row collapse, so we disable-in-place rather
    -- than hide the rows (which would leave an empty gap anyway).
    local anchorPoints = {
        { key = "TOP",         text = "Top" },
        { key = "TOPLEFT",     text = "Top Left" },
        { key = "TOPRIGHT",    text = "Top Right" },
        { key = "BOTTOM",      text = "Bottom" },
        { key = "BOTTOMLEFT",  text = "Bottom Left" },
        { key = "BOTTOMRIGHT", text = "Bottom Right" },
        { key = "LEFT",        text = "Left" },
        { key = "RIGHT",       text = "Right" },
        { key = "CENTER",      text = "Center" },
    }

    local row4b = GUIFrame:CreateRow(card4.content, 40)
    local selfPointDropdown = GUIFrame:CreateDropdown(row4b, "Self Point", anchorPoints,
        db.SelfPoint or "BOTTOM", 45,
        function(key)
            db.SelfPoint = key
            ApplySettings()
        end)
    row4b:AddWidget(selfPointDropdown, 0.5)
    table_insert(allWidgets, selfPointDropdown)
    table_insert(customPositionWidgets, selfPointDropdown)

    local anchorPointDropdown = GUIFrame:CreateDropdown(row4b, "Anchor Point", anchorPoints,
        db.AnchorPoint or "CENTER", 45,
        function(key)
            db.AnchorPoint = key
            ApplySettings()
        end)
    row4b:AddWidget(anchorPointDropdown, 0.5)
    table_insert(allWidgets, anchorPointDropdown)
    table_insert(customPositionWidgets, anchorPointDropdown)
    card4:AddRow(row4b, 40)

    local row4c = GUIFrame:CreateRow(card4.content, 40)
    local xOffsetSlider = GUIFrame:CreateSlider(row4c, "X Offset",
        -1000, 1000, 1, db.XOffset or 0, 60,
        function(val)
            db.XOffset = val
            ApplySettings()
        end)
    row4c:AddWidget(xOffsetSlider, 0.5)
    table_insert(allWidgets, xOffsetSlider)
    table_insert(customPositionWidgets, xOffsetSlider)

    local yOffsetSlider = GUIFrame:CreateSlider(row4c, "Y Offset",
        -1000, 1000, 1, db.YOffset or 100, 60,
        function(val)
            db.YOffset = val
            ApplySettings()
        end)
    row4c:AddWidget(yOffsetSlider, 0.5)
    table_insert(allWidgets, yOffsetSlider)
    table_insert(customPositionWidgets, yOffsetSlider)
    card4:AddRow(row4c, 40)

    yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 5: Font Settings (duration + count text)
    ---------------------------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Font Settings", yOffset)
    table_insert(allWidgets, card5)

    local fontList = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do fontList[name] = name end
    else
        fontList["Friz Quadrata TT"] = "Friz Quadrata TT"
    end

    local row5a = GUIFrame:CreateRow(card5.content, 40)
    local fontDropdown = GUIFrame:CreateDropdown(row5a, "Font", fontList,
        db.FontFace or "Expressway", 30,
        function(key) db.FontFace = key; ApplySettings() end)
    row5a:AddWidget(fontDropdown, 0.5)
    table_insert(allWidgets, fontDropdown)

    local fontSizeSlider = GUIFrame:CreateSlider(row5a, "Font Size", 6, 32, 1,
        db.FontSize or 11, 60,
        function(val) db.FontSize = val; ApplySettings() end)
    row5a:AddWidget(fontSizeSlider, 0.5)
    table_insert(allWidgets, fontSizeSlider)
    card5:AddRow(row5a, 40)

    local row5b = GUIFrame:CreateRow(card5.content, 37)
    local outlineList = {
        { key = "NONE",         text = "None"    },
        { key = "OUTLINE",      text = "Outline" },
        { key = "THICKOUTLINE", text = "Thick"   },
        { key = "SOFTOUTLINE",  text = "Soft"    },
    }
    local outlineDropdown = GUIFrame:CreateDropdown(row5b, "Outline", outlineList,
        db.FontOutline or "OUTLINE", 45,
        function(key) db.FontOutline = key; ApplySettings() end)
    row5b:AddWidget(outlineDropdown, 1)
    table_insert(allWidgets, outlineDropdown)
    card5:AddRow(row5b, 37)

    yOffset = yOffset + card5:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 6: Colors
    ---------------------------------------------------------------------------------
    local card6 = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    table_insert(allWidgets, card6)

    card6:AddLabel("|cff888888Duration Text is the base color for the timer/count above each icon. Hearty Food Text replaces it on the food slot when your active food persists through death.|r")

    local row6a = GUIFrame:CreateRow(card6.content, 40)
    local durationColorPicker = GUIFrame:CreateColorPicker(row6a, "Duration Text",
        db.DurationColor or { 1, 1, 1, 1 },
        function(r, g, b, a)
            db.DurationColor = { r, g, b, a }
            ApplySettings()
        end)
    row6a:AddWidget(durationColorPicker, 0.5)
    table_insert(allWidgets, durationColorPicker)

    local heartyColorPicker = GUIFrame:CreateColorPicker(row6a, "Hearty Food Text",
        db.HeartyFoodColor or { 0.2, 1.0, 0.2, 1.0 },
        function(r, g, b, a)
            db.HeartyFoodColor = { r, g, b, a }
            ApplySettings()
        end)
    row6a:AddWidget(heartyColorPicker, 0.5)
    table_insert(allWidgets, heartyColorPicker)
    card6:AddRow(row6a, 40)

    yOffset = yOffset + card6:GetContentHeight() + Theme.paddingSmall

    UpdateAllWidgetStates()
    yOffset = yOffset - (Theme.paddingSmall * 3)
    return yOffset
end)
