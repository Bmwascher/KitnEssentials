-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-ReadyCheckConsumables.lua                           ║
-- ║  GUI: Ready Check Consumables                            ║
-- ║  Purpose: Configuration panel for the                    ║
-- ║           ReadyCheckConsumables module.                  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local UnitClass = UnitClass

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("ReadyCheckConsumables", true)
    end
    return nil
end

GUIFrame:RegisterContent("ReadyCheckConsumables", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.ReadyCheckConsumables
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local mod = GetModule()
    local _, playerClass = UnitClass("player")

    local manager = GUIFrame:CreateWidgetStateManager()
    manager:SetCondition("customPosition", function() return db.PositionMode == "custom" end)

    local function ApplySettings()
        if mod and mod.ApplySettings then mod:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("ReadyCheckConsumables")
        else
            KitnEssentials:DisableModule("ReadyCheckConsumables")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Ready Check Consumables", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Ready Check Consumables", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Ready Check Consumables",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, Theme.rowHeight)

    local noteRow = GUIFrame:CreateRow(card1.content, 35)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Clickable consumable icons attached to the ready check popup.",
        35, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, 35, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: General Settings
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "General Settings", yOffset)
    manager:Register(card2, "all")

    local row2a = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local iconSizeSlider = GUIFrame:CreateSlider(row2a, "Icon Size", {
        min = 16, max = 64, step = 1,
        value = db.IconSize or 32,
        callback = function(val) db.IconSize = val; ApplySettings() end,
    })
    row2a:AddWidget(iconSizeSlider, 0.5)
    manager:Register(iconSizeSlider, "all")

    local iconSpacingSlider = GUIFrame:CreateSlider(row2a, "Icon Spacing", {
        min = 0, max = 16, step = 1,
        value = db.IconSpacing or 4,
        callback = function(val) db.IconSpacing = val; ApplySettings() end,
    })
    row2a:AddWidget(iconSpacingSlider, 0.5)
    manager:Register(iconSpacingSlider, "all")
    card2:AddRow(row2a, Theme.rowHeight)

    local row2sep = GUIFrame:CreateRow(card2.content, Theme.rowHeightSeparator)
    local sep2 = GUIFrame:CreateSeparator(row2sep)
    row2sep:AddWidget(sep2, 1)
    manager:Register(sep2, "all")
    card2:AddRow(row2sep, Theme.rowHeightSeparator)

    local row2b = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local hideStarterCheck = GUIFrame:CreateCheckbox(row2b, "Hide when I initiate the ready check", {
        value = db.HideForStarter,
        callback = function(checked) db.HideForStarter = checked; ApplySettings() end,
    })
    row2b:AddWidget(hideStarterCheck, 0.5)
    manager:Register(hideStarterCheck, "all")

    local hideMockCheck = GUIFrame:CreateCheckbox(row2b, "Hide Preview Box (GUI only)", {
        value = db.HidePreviewMock,
        callback = function(checked) db.HidePreviewMock = checked; ApplySettings() end,
    })
    row2b:AddWidget(hideMockCheck, 0.5)
    manager:Register(hideMockCheck, "all")
    card2:AddRow(row2b, Theme.rowHeight)

    local row2c = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local cauldronOnlyCheck = GUIFrame:CreateCheckbox(row2c, "Use flasks only from raid cauldron", {
        value = db.CauldronFlasksOnly,
        callback = function(checked) db.CauldronFlasksOnly = checked; ApplySettings() end,
    })
    row2c:AddWidget(cauldronOnlyCheck, 0.5)
    manager:Register(cauldronOnlyCheck, "all")

    local unlimitedRuneCheck = GUIFrame:CreateCheckbox(row2c, "Use only unlimited augment rune", {
        value = db.UnlimitedRunesOnly,
        callback = function(checked) db.UnlimitedRunesOnly = checked; ApplySettings() end,
    })
    row2c:AddWidget(unlimitedRuneCheck, 0.5)
    manager:Register(unlimitedRuneCheck, "all")
    card2:AddRow(row2c, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Visible Consumables
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Visible Consumables", yOffset)
    manager:Register(card3, "all")

    local row3a = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local foodCheck = GUIFrame:CreateCheckbox(row3a, "Food", {
        value = db.ShowFood ~= false,
        callback = function(checked) db.ShowFood = checked; ApplySettings() end,
    })
    row3a:AddWidget(foodCheck, 1/3)
    manager:Register(foodCheck, "all")

    local flaskCheck = GUIFrame:CreateCheckbox(row3a, "Flask", {
        value = db.ShowFlask ~= false,
        callback = function(checked) db.ShowFlask = checked; ApplySettings() end,
    })
    row3a:AddWidget(flaskCheck, 1/3)
    manager:Register(flaskCheck, "all")

    local runeCheck = GUIFrame:CreateCheckbox(row3a, "Augment Rune", {
        value = db.ShowAugmentRune ~= false,
        callback = function(checked) db.ShowAugmentRune = checked; ApplySettings() end,
    })
    row3a:AddWidget(runeCheck, 1/3)
    manager:Register(runeCheck, "all")
    card3:AddRow(row3a, Theme.rowHeight)

    local lastConsumableRowIsClass = playerClass == "WARLOCK"
    local row3b = GUIFrame:CreateRow(card3.content, lastConsumableRowIsClass and Theme.rowHeight or Theme.rowHeightLast)
    local oilCheck = GUIFrame:CreateCheckbox(row3b, "Weapon Enchant (MH)", {
        value = db.ShowWeaponOil ~= false,
        callback = function(checked) db.ShowWeaponOil = checked; ApplySettings() end,
    })
    row3b:AddWidget(oilCheck, 1/3)
    manager:Register(oilCheck, "all")

    local oilOHCheck = GUIFrame:CreateCheckbox(row3b, "Weapon Enchant (OH)", {
        value = db.ShowOffHandOil ~= false,
        callback = function(checked) db.ShowOffHandOil = checked; ApplySettings() end,
    })
    row3b:AddWidget(oilOHCheck, 1/3)
    manager:Register(oilOHCheck, "all")

    local hsCheck = GUIFrame:CreateCheckbox(row3b, "Healthstone", {
        value = db.ShowHealthstone ~= false,
        callback = function(checked) db.ShowHealthstone = checked; ApplySettings() end,
    })
    row3b:AddWidget(hsCheck, 1/3)
    manager:Register(hsCheck, "all")
    if lastConsumableRowIsClass then
        card3:AddRow(row3b, Theme.rowHeight)

        local row3c = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
        local classCheck = GUIFrame:CreateCheckbox(row3c, "Class Action (Soulstone)", {
            value = db.ShowClassItem ~= false,
            callback = function(checked) db.ShowClassItem = checked; ApplySettings() end,
        })
        row3c:AddWidget(classCheck, 1)
        manager:Register(classCheck, "all")
        card3:AddRow(row3c, Theme.rowHeightLast)
    else
        card3:AddRow(row3b, Theme.rowHeightLast)
    end

    local row3note = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local note3 = GUIFrame:CreateText(row3note,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Weapon Enchant (OH) also requires an off-hand weapon equipped. Healthstone also requires a Warlock in your group.",
        Theme.rowHeight, "hide")
    row3note:AddWidget(note3, 1)
    manager:Register(note3, "all")
    card3:AddRow(row3note, Theme.rowHeight, 0)

    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Position Settings (custom auto/custom mode — manual)
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Position Settings", yOffset)
    manager:Register(card4, "all")

    local row4a = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local posModeDropdown = GUIFrame:CreateDropdown(row4a, "Position Mode", {
        options = {
            { key = "auto",   text = "Auto (anchor to ready check popup)" },
            { key = "custom", text = "Custom (manual position)" },
        },
        value = db.PositionMode or "auto",
        callback = function(key)
            db.PositionMode = key
            ApplySettings()
            RefreshStates()
        end,
    })
    row4a:AddWidget(posModeDropdown, 1)
    manager:Register(posModeDropdown, "all")
    card4:AddRow(row4a, Theme.rowHeight)

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

    local row4b = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local selfPointDropdown = GUIFrame:CreateDropdown(row4b, "Self Point", {
        options = anchorPoints,
        value = db.SelfPoint or "BOTTOM",
        callback = function(key) db.SelfPoint = key; ApplySettings() end,
    })
    row4b:AddWidget(selfPointDropdown, 0.5)
    manager:Register(selfPointDropdown, "customPosition")

    local anchorPointDropdown = GUIFrame:CreateDropdown(row4b, "Anchor Point", {
        options = anchorPoints,
        value = db.AnchorPoint or "CENTER",
        callback = function(key) db.AnchorPoint = key; ApplySettings() end,
    })
    row4b:AddWidget(anchorPointDropdown, 0.5)
    manager:Register(anchorPointDropdown, "customPosition")
    card4:AddRow(row4b, Theme.rowHeight)

    local row4c = GUIFrame:CreateRow(card4.content, Theme.rowHeightLast)
    local xOffsetSlider = GUIFrame:CreateSlider(row4c, "X Offset", {
        min = -1000, max = 1000, step = 1,
        value = db.XOffset or 0,
        callback = function(val) db.XOffset = val; ApplySettings() end,
    })
    row4c:AddWidget(xOffsetSlider, 0.5)
    manager:Register(xOffsetSlider, "customPosition")

    local yOffsetSlider = GUIFrame:CreateSlider(row4c, "Y Offset", {
        min = -1000, max = 1000, step = 1,
        value = db.YOffset or 100,
        callback = function(val) db.YOffset = val; ApplySettings() end,
    })
    row4c:AddWidget(yOffsetSlider, 0.5)
    manager:Register(yOffsetSlider, "customPosition")
    card4:AddRow(row4c, Theme.rowHeightLast, 0)

    yOffset = card4:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Font Settings
    ----------------------------------------------------------------
    local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            fontFace = "FontFace",
            fontSize = "FontSize",
            fontOutline = "FontOutline",
        },
        fontSizeRange = { 6, 32 },
        includeSoftOutline = true,
        onChangeCallback = ApplySettings,
    })
    manager:Register(fontCard, "all")
    if fontWidgets then
        manager:RegisterGroup(fontWidgets, "all")
    end
    yOffset = fontOffset

    ----------------------------------------------------------------
    -- Card 6: Colors
    ----------------------------------------------------------------
    local card6 = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    manager:Register(card6, "all")

    local row6note = GUIFrame:CreateRow(card6.content, 50)
    local note6 = GUIFrame:CreateText(row6note,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Duration Text is the base color for the timer/count above each icon.\n" ..
        KE:ColorTextByTheme("-") .. " Hearty Food Text replaces it on the food slot when your active food persists through death.",
        50, "hide")
    row6note:AddWidget(note6, 1)
    manager:Register(note6, "all")
    card6:AddRow(row6note, 50)

    local row6 = GUIFrame:CreateRow(card6.content, Theme.rowHeightLast)
    local durationColorPicker = GUIFrame:CreateColorPicker(row6, "Duration Text", {
        color = db.DurationColor or { 1, 1, 1, 1 },
        callback = function(r, g, b, a) db.DurationColor = { r, g, b, a }; ApplySettings() end,
    })
    row6:AddWidget(durationColorPicker, 0.5)
    manager:Register(durationColorPicker, "all")

    local heartyColorPicker = GUIFrame:CreateColorPicker(row6, "Hearty Food Text", {
        color = db.HeartyFoodColor or { 0.2, 1.0, 0.2, 1.0 },
        callback = function(r, g, b, a) db.HeartyFoodColor = { r, g, b, a }; ApplySettings() end,
    })
    row6:AddWidget(heartyColorPicker, 0.5)
    manager:Register(heartyColorPicker, "all")
    card6:AddRow(row6, Theme.rowHeightLast, 0)

    yOffset = card6:GetNextOffset()

    RefreshStates()
    return yOffset
end)
