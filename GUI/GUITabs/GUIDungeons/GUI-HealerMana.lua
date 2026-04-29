-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-HealerMana.lua                                      ║
-- ║  GUI: Healer Mana                                        ║
-- ║  Purpose: Configuration panel for the HealerMana module. ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

GUIFrame:RegisterContent("HealerMana", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile and KE.db.profile.Dungeons and KE.db.profile.Dungeons.HealerMana
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local manager = GUIFrame:CreateWidgetStateManager()

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

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Healer Mana Tracker", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Healer Mana Tracker", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Healer Mana",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, Theme.rowHeightLast, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Appearance (icon size, icon type, mana color, hide on healer)
    ----------------------------------------------------------------
    local cardAppearance = GUIFrame:CreateCard(scrollChild, "Appearance", yOffset)
    manager:Register(cardAppearance, "all")

    local rowAppearance1 = GUIFrame:CreateRow(cardAppearance.content, Theme.rowHeight)
    local iconSlider = GUIFrame:CreateSlider(rowAppearance1, "Icon Size", {
        min = 16, max = 64, step = 1,
        value = db.IconSize or 24,
        callback = function(value) db.IconSize = value; Refresh() end,
    })
    rowAppearance1:AddWidget(iconSlider, 0.5)
    manager:Register(iconSlider, "all")

    local iconTypeDropdown = GUIFrame:CreateDropdown(rowAppearance1, "Icon Type", {
        options = {
            { key = "spec",  text = "Spec Icon" },
            { key = "class", text = "Class Icon" },
        },
        value = db.IconType or "spec",
        callback = function(key) db.IconType = key; Refresh() end,
    })
    rowAppearance1:AddWidget(iconTypeDropdown, 0.5)
    manager:Register(iconTypeDropdown, "all")
    cardAppearance:AddRow(rowAppearance1, Theme.rowHeight)

    local rowAppearance2 = GUIFrame:CreateRow(cardAppearance.content, Theme.rowHeightLast)
    local manaColorPicker = GUIFrame:CreateColorPicker(rowAppearance2, "Mana Text Color", {
        color = db.HighManaColor or { 1, 1, 1, 1 },
        callback = function(r, g, b, a)
            db.HighManaColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    rowAppearance2:AddWidget(manaColorPicker, 0.5)
    manager:Register(manaColorPicker, "all")

    local disableOnHealerCheck = GUIFrame:CreateCheckbox(rowAppearance2, "Hide when my spec is a healer", {
        value = db.DisableOnHealer == true,
        callback = function(checked) db.DisableOnHealer = checked; Refresh() end,
    })
    rowAppearance2:AddWidget(disableOnHealerCheck, 0.5)
    manager:Register(disableOnHealerCheck, "all")
    cardAppearance:AddRow(rowAppearance2, Theme.rowHeightLast, 0)

    yOffset = cardAppearance:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Position Settings
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
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
        showPixelSnap = true,
        onChangeCallback = ApplySettings,
    })

    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "all")
    end
    manager:Register(posCard, "all")
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 4: Font Settings (font face / outline + per-text sizes)
    ----------------------------------------------------------------
    local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            fontFace = "FontFace",
            fontOutline = "FontOutline",
        },
        fontSizes = {
            { label = "Name Size", dbKey = "NameFontSize" },
            { label = "Mana Size", dbKey = "ManaFontSize" },
        },
        fontSizeRange = { 8, 44 },
        includeSoftOutline = true,
        onChangeCallback = Refresh,
    })
    manager:Register(fontCard, "all")
    if fontWidgets then
        manager:RegisterGroup(fontWidgets, "all")
    end
    yOffset = fontOffset

    ----------------------------------------------------------------
    -- Card 5: Name Text Position
    ----------------------------------------------------------------
    local cardName = GUIFrame:CreateCard(scrollChild, "Name Text Position", yOffset)
    manager:Register(cardName, "all")

    local rowName = GUIFrame:CreateRow(cardName.content, Theme.rowHeightLast)
    local nameXSlider = GUIFrame:CreateSlider(rowName, "X Offset", {
        min = -40, max = 40, step = 1,
        value = db.NameXOffset or 0,
        callback = function(value) db.NameXOffset = value; Refresh() end,
    })
    rowName:AddWidget(nameXSlider, 0.5)
    manager:Register(nameXSlider, "all")

    local nameYSlider = GUIFrame:CreateSlider(rowName, "Y Offset", {
        min = -40, max = 40, step = 1,
        value = db.NameYOffset or 0,
        callback = function(value) db.NameYOffset = value; Refresh() end,
    })
    rowName:AddWidget(nameYSlider, 0.5)
    manager:Register(nameYSlider, "all")
    cardName:AddRow(rowName, Theme.rowHeightLast, 0)

    yOffset = cardName:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 6: Mana Text Position
    ----------------------------------------------------------------
    local cardMana = GUIFrame:CreateCard(scrollChild, "Mana Text Position", yOffset)
    manager:Register(cardMana, "all")

    local rowMana = GUIFrame:CreateRow(cardMana.content, Theme.rowHeightLast)
    local manaXSlider = GUIFrame:CreateSlider(rowMana, "X Offset", {
        min = -40, max = 40, step = 1,
        value = db.ManaXOffset or 0,
        callback = function(value) db.ManaXOffset = value; Refresh() end,
    })
    rowMana:AddWidget(manaXSlider, 0.5)
    manager:Register(manaXSlider, "all")

    local manaYSlider = GUIFrame:CreateSlider(rowMana, "Y Offset", {
        min = -40, max = 40, step = 1,
        value = db.ManaYOffset or 0,
        callback = function(value) db.ManaYOffset = value; Refresh() end,
    })
    rowMana:AddWidget(manaYSlider, 0.5)
    manager:Register(manaYSlider, "all")
    cardMana:AddRow(rowMana, Theme.rowHeightLast, 0)

    yOffset = cardMana:GetNextOffset()

    RefreshStates()
    return yOffset
end)
