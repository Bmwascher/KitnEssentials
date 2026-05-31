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
    -- Card 2: Position Mode (split toggle + configure-for context)
    ----------------------------------------------------------------
    -- Forward declarations so the toggle/dropdown callbacks can reference
    -- each other and the position card (all assigned before user interaction).
    local posCard, posOffset
    local configureForDropdown

    local cardPosMode = GUIFrame:CreateCard(scrollChild, "Position Mode", yOffset)
    manager:Register(cardPosMode, "all")
    local rowPosMode = GUIFrame:CreateRow(cardPosMode.content, Theme.rowHeightLast)

    local splitToggle = GUIFrame:CreateCheckbox(rowPosMode, "Split Positioning", {
        value = db.SplitPositioning == true,
        callback = function(checked)
            db.SplitPositioning = checked
            if not checked then
                -- Collapse back to the single (Dungeon) context.
                if configureForDropdown then configureForDropdown:SetValue("DUNGEON", true) end
                if posCard and posCard.SetActiveContext then posCard:SetActiveContext("Position") end
                local mod = GetModule()
                if mod then
                    mod.previewContext = "DUNGEON"
                    if mod.isPreview then mod:ShowPreview() end
                    if mod.RefreshEditMode then mod:RefreshEditMode() end
                end
            end
            ApplySettings()
            RefreshStates()  -- grey/ungrey the Configure For dropdown
        end,
    })
    rowPosMode:AddWidget(splitToggle, 0.5)
    manager:Register(splitToggle, "all")

    -- Configure For: switches which position table the card below edits, and
    -- moves the preview to that mode so you see what you're editing.
    configureForDropdown = GUIFrame:CreateDropdown(rowPosMode, "Configure For", {
        options = {
            { key = "DUNGEON", text = "Dungeon" },
            { key = "RAID",    text = "Raid" },
        },
        value = "DUNGEON",
        callback = function(key)
            local positionKey = (key == "RAID") and "RaidPosition" or "Position"
            if posCard and posCard.SetActiveContext then posCard:SetActiveContext(positionKey) end
            local mod = GetModule()
            if mod then
                mod.previewContext = key
                if mod.isPreview then mod:ShowPreview() end
                if mod.RefreshEditMode then mod:RefreshEditMode() end
            end
        end,
    })
    rowPosMode:AddWidget(configureForDropdown, 0.5)
    manager:Register(configureForDropdown, "splitConfig")  -- greyed when split off
    cardPosMode:AddRow(rowPosMode, Theme.rowHeight)

    -- Clarify the scope of these controls: they only affect Position Settings,
    -- not Appearance / Raid Mode / Font (those are shared across both modes).
    local posModeNoteRow = GUIFrame:CreateRow(cardPosMode.content, 50)
    local posModeNote = GUIFrame:CreateText(posModeNoteRow,
        KE:ColorTextByTheme("Note"),
        "These controls only affect the Position Settings below. Appearance, " ..
        "Raid Mode, and Font settings are shared between Dungeon and Raid.",
        50, "hide")
    posModeNoteRow:AddWidget(posModeNote, 1)
    cardPosMode:AddRow(posModeNoteRow, 50, 0)
    yOffset = cardPosMode:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Position Settings (single, full; context-driven by the dropdown)
    ----------------------------------------------------------------
    posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Position Settings",
        db = db,
        positionKey = "Position",
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
    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "all")
    end
    manager:Register(posCard, "all")
    yOffset = posOffset

    -- Configure For dropdown is only meaningful when split positioning is on.
    manager:SetCondition("splitConfig", function() return db.SplitPositioning == true end)

    ----------------------------------------------------------------
    -- Card 4: Appearance (icon size, icon type, mana color, hide on healer)
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
    cardAppearance:AddRow(rowAppearance2, Theme.rowHeight)

    -- Separator before text-offset settings
    local rowAppSep = GUIFrame:CreateRow(cardAppearance.content, Theme.rowHeightSeparator)
    GUIFrame:CreateSeparator(rowAppSep)
    cardAppearance:AddRow(rowAppSep, Theme.rowHeightSeparator)

    local rowNameOffset = GUIFrame:CreateRow(cardAppearance.content, Theme.rowHeight)
    local nameXSlider = GUIFrame:CreateSlider(rowNameOffset, "Name X Offset", {
        min = -40, max = 40, step = 1,
        value = db.NameXOffset or 0,
        callback = function(value) db.NameXOffset = value; Refresh() end,
    })
    rowNameOffset:AddWidget(nameXSlider, 0.5)
    manager:Register(nameXSlider, "all")
    local nameYSlider = GUIFrame:CreateSlider(rowNameOffset, "Name Y Offset", {
        min = -40, max = 40, step = 1,
        value = db.NameYOffset or 0,
        callback = function(value) db.NameYOffset = value; Refresh() end,
    })
    rowNameOffset:AddWidget(nameYSlider, 0.5)
    manager:Register(nameYSlider, "all")
    cardAppearance:AddRow(rowNameOffset, Theme.rowHeight)

    local rowManaOffset = GUIFrame:CreateRow(cardAppearance.content, Theme.rowHeightLast)
    local manaXSlider = GUIFrame:CreateSlider(rowManaOffset, "Mana X Offset", {
        min = -40, max = 40, step = 1,
        value = db.ManaXOffset or 0,
        callback = function(value) db.ManaXOffset = value; Refresh() end,
    })
    rowManaOffset:AddWidget(manaXSlider, 0.5)
    manager:Register(manaXSlider, "all")
    local manaYSlider = GUIFrame:CreateSlider(rowManaOffset, "Mana Y Offset", {
        min = -40, max = 40, step = 1,
        value = db.ManaYOffset or 0,
        callback = function(value) db.ManaYOffset = value; Refresh() end,
    })
    rowManaOffset:AddWidget(manaYSlider, 0.5)
    manager:Register(manaYSlider, "all")
    cardAppearance:AddRow(rowManaOffset, Theme.rowHeightLast, 0)

    yOffset = cardAppearance:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Raid Mode (stacking)
    ----------------------------------------------------------------
    local cardRaid = GUIFrame:CreateCard(scrollChild, "Raid Mode", yOffset)
    manager:Register(cardRaid, "all")

    local rowRaid1 = GUIFrame:CreateRow(cardRaid.content, Theme.rowHeight)
    local enableRaidCheck = GUIFrame:CreateCheckbox(rowRaid1, "Enable in Raid", {
        value = db.EnableInRaid ~= false,
        callback = function(checked) db.EnableInRaid = checked; ApplySettings() end,
    })
    rowRaid1:AddWidget(enableRaidCheck, 0.5)
    manager:Register(enableRaidCheck, "all")

    local maxHealersSlider = GUIFrame:CreateSlider(rowRaid1, "Max Healers", {
        min = 1, max = 8, step = 1,
        value = db.MaxHealers or 6,
        callback = function(value) db.MaxHealers = value; Refresh() end,
    })
    rowRaid1:AddWidget(maxHealersSlider, 0.5)
    manager:Register(maxHealersSlider, "all")
    cardRaid:AddRow(rowRaid1, Theme.rowHeight)

    local rowRaid2 = GUIFrame:CreateRow(cardRaid.content, Theme.rowHeightLast)
    local spacingSlider = GUIFrame:CreateSlider(rowRaid2, "Frame Spacing", {
        min = 0, max = 20, step = 1,
        value = db.FrameSpacing or 4,
        callback = function(value) db.FrameSpacing = value; Refresh() end,
    })
    rowRaid2:AddWidget(spacingSlider, 0.5)
    manager:Register(spacingSlider, "all")

    local growDropdown = GUIFrame:CreateDropdown(rowRaid2, "Grow Direction", {
        options = {
            { key = "DOWN", text = "Down" },
            { key = "UP",   text = "Up" },
        },
        value = db.GrowDirection or "DOWN",
        callback = function(key) db.GrowDirection = key; Refresh() end,
    })
    rowRaid2:AddWidget(growDropdown, 0.5)
    manager:Register(growDropdown, "all")
    cardRaid:AddRow(rowRaid2, Theme.rowHeightLast, 0)

    yOffset = cardRaid:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 6: Font Settings (font face / outline + per-text sizes)
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

    RefreshStates()
    return yOffset
end)
