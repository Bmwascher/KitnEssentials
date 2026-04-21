-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-HealerMana.lua                                      ║
-- ║  GUI: Healer Mana                                        ║
-- ║  Purpose: Configuration panel for the HealerMana module. ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)
local table_insert = table.insert

GUIFrame:RegisterContent("HealerMana", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile and KE.db.profile.Dungeons and KE.db.profile.Dungeons.HealerMana
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return yOffset + errorCard:GetContentHeight() + Theme.paddingMedium
    end

    local allWidgets = {}

    local function GetModule()
        if KitnEssentials then
            return KitnEssentials:GetModule("HealerMana", true)
        end
        return nil
    end

    local function ApplySettings()
        local mod = GetModule()
        if mod and mod.ApplySettings then mod:ApplySettings() end
    end

    local function Refresh()
        local mod = GetModule()
        if mod and mod.Refresh then mod:Refresh() end
    end

    local function ApplyModuleState(enabled)
        if not KitnEssentials then return end
        local mod = GetModule()
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("HealerMana")
        else
            KitnEssentials:DisableModule("HealerMana")
        end
    end

    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false
        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then widget:SetEnabled(mainEnabled) end
        end
    end

    ---------------------------------------------------------------------------------
    -- Card 1: Enable + Icon Size
    ---------------------------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Healer Mana Tracker", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Healer Mana Tracker", db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            UpdateAllWidgetStates()
        end,
        true, "Healer Mana", "On", "Off"
    )
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, 36)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 2: Appearance (Icon Size, Icon Type, Mana Color)
    ---------------------------------------------------------------------------------
    local cardAppearance = GUIFrame:CreateCard(scrollChild, "Appearance", yOffset)
    table_insert(allWidgets, cardAppearance)

    -- Icon Size + Icon Type
    local rowAppearance1 = GUIFrame:CreateRow(cardAppearance.content, 36)
    local iconSlider = GUIFrame:CreateSlider(rowAppearance1, "Icon Size", 16, 64, 1, db.IconSize or 24, 30,
        function(value)
            db.IconSize = value
            Refresh()
        end)
    rowAppearance1:AddWidget(iconSlider, 0.5)
    table_insert(allWidgets, iconSlider)

    local iconTypeList = {
        { key = "spec",  text = "Spec Icon" },
        { key = "class", text = "Class Icon" },
    }
    local iconTypeDropdown = GUIFrame:CreateDropdown(rowAppearance1, "Icon Type", iconTypeList, db.IconType or "spec", 30,
        function(key)
            db.IconType = key
            Refresh()
        end)
    rowAppearance1:AddWidget(iconTypeDropdown, 0.5)
    table_insert(allWidgets, iconTypeDropdown)
    cardAppearance:AddRow(rowAppearance1, 36)

    -- Mana Text Color + Hide when healer spec
    local rowAppearance2 = GUIFrame:CreateRow(cardAppearance.content, 37)
    local manaColorPicker = GUIFrame:CreateColorPicker(rowAppearance2, "Mana Text Color",
        db.HighManaColor or { 1, 1, 1, 1 },
        function(r, g, b, a)
            db.HighManaColor = { r, g, b, a }
            ApplySettings()
        end)
    rowAppearance2:AddWidget(manaColorPicker, 0.5)
    table_insert(allWidgets, manaColorPicker)

    local disableOnHealerCheck = GUIFrame:CreateCheckbox(rowAppearance2, "Hide when my spec is a healer", db.DisableOnHealer == true,
        function(checked)
            db.DisableOnHealer = checked
            Refresh()
        end,
        false, nil, "On", "Off"
    )
    rowAppearance2:AddWidget(disableOnHealerCheck, 0.5)
    table_insert(allWidgets, disableOnHealerCheck)
    cardAppearance:AddRow(rowAppearance2, 37)

    yOffset = yOffset + cardAppearance:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 3: Position Settings
    ---------------------------------------------------------------------------------
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

    ---------------------------------------------------------------------------------
    -- Card 3: Font Settings
    ---------------------------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Font Settings", yOffset)
    table_insert(allWidgets, card3)

    local fontList = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do fontList[name] = name end
    else
        fontList["Friz Quadrata TT"] = "Friz Quadrata TT"
    end

    local rowFont = GUIFrame:CreateRow(card3.content, 40)
    local fontDropdown = GUIFrame:CreateDropdown(rowFont, "Font", fontList, db.FontFace or "Expressway", 30,
        function(key)
            db.FontFace = key
            Refresh()
        end)
    rowFont:AddWidget(fontDropdown, 0.5)
    table_insert(allWidgets, fontDropdown)

    local outlineList = {
        { key = "NONE",         text = "None" },
        { key = "OUTLINE",      text = "Outline" },
        { key = "THICKOUTLINE", text = "Thick" },
        { key = "SOFTOUTLINE",  text = "Soft" },
    }
    local outlineDropdown = GUIFrame:CreateDropdown(rowFont, "Outline", outlineList, db.FontOutline or "SOFTOUTLINE", 45,
        function(key)
            db.FontOutline = key
            Refresh()
        end)
    rowFont:AddWidget(outlineDropdown, 0.5)
    table_insert(allWidgets, outlineDropdown)
    card3:AddRow(rowFont, 40)

    yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 4: Name Text
    ---------------------------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Name Text", yOffset)
    table_insert(allWidgets, card4)

    local rowName1 = GUIFrame:CreateRow(card4.content, 36)
    local nameSizeSlider = GUIFrame:CreateSlider(rowName1, "Font Size", 8, 44, 1, db.NameFontSize or 14, 30,
        function(value)
            db.NameFontSize = value
            Refresh()
        end)
    rowName1:AddWidget(nameSizeSlider, 1)
    table_insert(allWidgets, nameSizeSlider)
    card4:AddRow(rowName1, 36)

    local rowName2 = GUIFrame:CreateRow(card4.content, 36)
    local nameXSlider = GUIFrame:CreateSlider(rowName2, "X Offset", -40, 40, 1, db.NameXOffset or 0, 30,
        function(value)
            db.NameXOffset = value
            Refresh()
        end)
    rowName2:AddWidget(nameXSlider, 0.5)
    table_insert(allWidgets, nameXSlider)

    local nameYSlider = GUIFrame:CreateSlider(rowName2, "Y Offset", -40, 40, 1, db.NameYOffset or 0, 30,
        function(value)
            db.NameYOffset = value
            Refresh()
        end)
    rowName2:AddWidget(nameYSlider, 0.5)
    table_insert(allWidgets, nameYSlider)
    card4:AddRow(rowName2, 36)

    yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 5: Mana Text
    ---------------------------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Mana Text", yOffset)
    table_insert(allWidgets, card5)

    local rowMana1 = GUIFrame:CreateRow(card5.content, 36)
    local manaSizeSlider = GUIFrame:CreateSlider(rowMana1, "Font Size", 8, 44, 1, db.ManaFontSize or 14, 30,
        function(value)
            db.ManaFontSize = value
            Refresh()
        end)
    rowMana1:AddWidget(manaSizeSlider, 1)
    table_insert(allWidgets, manaSizeSlider)
    card5:AddRow(rowMana1, 36)

    local rowMana2 = GUIFrame:CreateRow(card5.content, 36)
    local manaXSlider = GUIFrame:CreateSlider(rowMana2, "X Offset", -40, 40, 1, db.ManaXOffset or 0, 30,
        function(value)
            db.ManaXOffset = value
            Refresh()
        end)
    rowMana2:AddWidget(manaXSlider, 0.5)
    table_insert(allWidgets, manaXSlider)

    local manaYSlider = GUIFrame:CreateSlider(rowMana2, "Y Offset", -40, 40, 1, db.ManaYOffset or 0, 30,
        function(value)
            db.ManaYOffset = value
            Refresh()
        end)
    rowMana2:AddWidget(manaYSlider, 0.5)
    table_insert(allWidgets, manaYSlider)
    card5:AddRow(rowMana2, 36)

    yOffset = yOffset + card5:GetContentHeight() + Theme.paddingSmall

    UpdateAllWidgetStates()
    yOffset = yOffset - (Theme.paddingSmall * 3)
    return yOffset
end)
