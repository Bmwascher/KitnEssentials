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

GUIFrame:RegisterContent("DeathNotifications", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.Dungeons.DeathNotifications
    if not db then return yOffset end

    db.PartyDeath = db.PartyDeath or {}
    db.FocusDeath = db.FocusDeath or {}

    local manager = GUIFrame:CreateWidgetStateManager()

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

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Death Notifications", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Death Notifications", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Death Notifications",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, Theme.rowHeightLast, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Activation Context
    ----------------------------------------------------------------
    local cardContext = GUIFrame:CreateCard(scrollChild, "Active In", yOffset)
    manager:Register(cardContext, "all")

    local cRow = GUIFrame:CreateRow(cardContext.content, Theme.rowHeightLast)
    local dungeonsCheck = GUIFrame:CreateCheckbox(cRow, "Dungeons (5-man)", {
        value = db.EnableInDungeons ~= false,
        callback = function(checked) db.EnableInDungeons = checked end,
        msgPopup = true,
        msgText = "Dungeons",
        msgOn = "On",
        msgOff = "Off",
    })
    cRow:AddWidget(dungeonsCheck, 0.5)
    manager:Register(dungeonsCheck, "all")

    local raidsCheck = GUIFrame:CreateCheckbox(cRow, "Raids", {
        value = db.EnableInRaids == true,
        callback = function(checked) db.EnableInRaids = checked end,
        msgPopup = true,
        msgText = "Raids",
        msgOn = "On",
        msgOff = "Off",
    })
    cRow:AddWidget(raidsCheck, 0.5)
    manager:Register(raidsCheck, "all")
    cardContext:AddRow(cRow, Theme.rowHeightLast, 0)

    yOffset = cardContext:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Position Settings
    ----------------------------------------------------------------
    local cardPos, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
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
        manager:RegisterGroup(cardPos.positionWidgets, "all")
    end
    manager:Register(cardPos, "all")
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 4: Party / Raid Death
    ----------------------------------------------------------------
    local cardPD = GUIFrame:CreateCard(scrollChild, "Party / Raid Death", yOffset)
    manager:Register(cardPD, "all")

    local pdRow1 = GUIFrame:CreateRow(cardPD.content, Theme.rowHeight)
    local pdEnableCheck = GUIFrame:CreateCheckbox(pdRow1, "Show Party Death", {
        value = db.PartyDeath.Enabled ~= false,
        callback = function(checked) db.PartyDeath.Enabled = checked; ApplySettings() end,
        msgPopup = true,
        msgText = "Party Death",
        msgOn = "On",
        msgOff = "Off",
    })
    pdRow1:AddWidget(pdEnableCheck, 0.5)
    manager:Register(pdEnableCheck, "all")

    local pdClassCheck = GUIFrame:CreateCheckbox(pdRow1, "Use Class Color for Name", {
        value = db.PartyDeath.UseClassColor ~= false,
        callback = function(checked) db.PartyDeath.UseClassColor = checked; ApplySettings() end,
        msgPopup = true,
        msgText = "Class Color",
        msgOn = "On",
        msgOff = "Off",
    })
    pdRow1:AddWidget(pdClassCheck, 0.5)
    manager:Register(pdClassCheck, "all")
    cardPD:AddRow(pdRow1, Theme.rowHeight)

    local pdRow2 = GUIFrame:CreateRow(cardPD.content, Theme.rowHeightLast)
    local pdFormatBox = GUIFrame:CreateEditBox(pdRow2, "Text Format (use %name)", {
        value = db.PartyDeath.TextFormat or "%name DIED",
        callback = function(value)
            db.PartyDeath.TextFormat = value
            ApplySettings()
        end,
    })
    pdRow2:AddWidget(pdFormatBox, 0.7)
    manager:Register(pdFormatBox, "all")

    local pdColorPicker = GUIFrame:CreateColorPicker(pdRow2, "Text Color", {
        color = db.PartyDeath.TextColor or { 1, 1, 1, 1 },
        callback = function(r, g, b, a)
            db.PartyDeath.TextColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    pdRow2:AddWidget(pdColorPicker, 0.3)
    manager:Register(pdColorPicker, "all")
    cardPD:AddRow(pdRow2, Theme.rowHeightLast, 0)

    yOffset = cardPD:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Focus Death
    ----------------------------------------------------------------
    local cardFD = GUIFrame:CreateCard(scrollChild, "Focus Death", yOffset)
    manager:Register(cardFD, "all")

    local fdRow1 = GUIFrame:CreateRow(cardFD.content, Theme.rowHeight)
    local fdEnableCheck = GUIFrame:CreateCheckbox(fdRow1, "Show Focus Death", {
        value = db.FocusDeath.Enabled ~= false,
        callback = function(checked) db.FocusDeath.Enabled = checked; ApplySettings() end,
        msgPopup = true,
        msgText = "Focus Death",
        msgOn = "On",
        msgOff = "Off",
    })
    fdRow1:AddWidget(fdEnableCheck, 1)
    manager:Register(fdEnableCheck, "all")
    cardFD:AddRow(fdRow1, Theme.rowHeight)

    local fdRow2 = GUIFrame:CreateRow(cardFD.content, Theme.rowHeightLast)
    local fdTextBox = GUIFrame:CreateEditBox(fdRow2, "Text", {
        value = db.FocusDeath.Text or "FOCUS DIED",
        callback = function(value)
            db.FocusDeath.Text = value
            ApplySettings()
        end,
    })
    fdRow2:AddWidget(fdTextBox, 0.7)
    manager:Register(fdTextBox, "all")

    local fdColorPicker = GUIFrame:CreateColorPicker(fdRow2, "Text Color", {
        color = db.FocusDeath.Color or { 1, 0.3, 0.3, 1 },
        callback = function(r, g, b, a)
            db.FocusDeath.Color = { r, g, b, a }
            ApplySettings()
        end,
    })
    fdRow2:AddWidget(fdColorPicker, 0.3)
    manager:Register(fdColorPicker, "all")
    cardFD:AddRow(fdRow2, Theme.rowHeightLast, 0)

    yOffset = cardFD:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 6: Font Settings
    ----------------------------------------------------------------
    local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            fontFace = "FontFace",
            fontSize = "FontSize",
            fontOutline = "FontOutline",
        },
        fontSizeRange = { 12, 64 },
        includeSoftOutline = true,
        onChangeCallback = ApplySettings,
    })
    manager:Register(fontCard, "all")
    if fontWidgets then
        manager:RegisterGroup(fontWidgets, "all")
    end
    yOffset = fontOffset

    ----------------------------------------------------------------
    -- Card 7: Display
    ----------------------------------------------------------------
    local cardDisplay = GUIFrame:CreateCard(scrollChild, "Display", yOffset)
    manager:Register(cardDisplay, "all")

    local dRow1 = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeight)
    local durationSlider = GUIFrame:CreateSlider(dRow1, "Duration (s)", {
        min = 1, max = 10, step = 1,
        value = db.Duration or 3,
        callback = function(val) db.Duration = val; ApplySettings() end,
    })
    dRow1:AddWidget(durationSlider, 0.5)
    manager:Register(durationSlider, "all")

    local spacingSlider = GUIFrame:CreateSlider(dRow1, "Spacing", {
        min = 0, max = 20, step = 1,
        value = db.Spacing or 4,
        callback = function(val) db.Spacing = val; ApplySettings() end,
    })
    dRow1:AddWidget(spacingSlider, 0.5)
    manager:Register(spacingSlider, "all")
    cardDisplay:AddRow(dRow1, Theme.rowHeight)

    local dRow2 = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeightLast)
    local growDropdown = GUIFrame:CreateDropdown(dRow2, "Grow Direction", {
        options = { { key = "DOWN", text = "Down" }, { key = "UP", text = "Up" } },
        value = db.Grow or "DOWN",
        callback = function(key) db.Grow = key; ApplySettings() end,
    })
    dRow2:AddWidget(growDropdown, 0.5)
    manager:Register(growDropdown, "all")

    local classIconCheck = GUIFrame:CreateCheckbox(dRow2, "Show Class Icon", {
        value = db.ShowClassIcon ~= false,
        callback = function(checked) db.ShowClassIcon = checked; ApplySettings() end,
        msgPopup = true,
        msgText = "Class Icon",
        msgOn = "On",
        msgOff = "Off",
    })
    dRow2:AddWidget(classIconCheck, 0.5)
    manager:Register(classIconCheck, "all")
    cardDisplay:AddRow(dRow2, Theme.rowHeightLast, 0)

    yOffset = cardDisplay:GetNextOffset()

    RefreshStates()
    return yOffset
end)
