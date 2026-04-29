-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-StasisTracker.lua                                   ║
-- ║  GUI: Stasis Tracker                                     ║
-- ║  Purpose: Configuration panel for the StasisTracker      ║
-- ║  module.                                                 ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("StasisTracker", true)
    end
    return nil
end

GUIFrame:RegisterContent("StasisTracker", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.StasisTracker
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local ST = GetModule()
    local manager = GUIFrame:CreateWidgetStateManager()
    manager:SetCondition("customColor", function()
        return (db.ColorMode or "custom") == "custom"
    end)

    local function ApplySettings()
        if ST and ST.ApplySettings then ST:ApplySettings() end
    end

    local function ApplyPosition()
        if ST and ST.ApplyPosition then ST:ApplyPosition() end
    end

    local function ApplyModuleState(enabled)
        if not ST then return end
        ST.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("StasisTracker")
        else
            KitnEssentials:DisableModule("StasisTracker")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Stasis Tracker", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Stasis Tracker", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Stasis Tracker",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 0.5)
    card1:AddRow(row1, Theme.rowHeight)

    local noteRow = GUIFrame:CreateRow(card1.content, 50)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Preservation Evoker only.\n" ..
        KE:ColorTextByTheme("-") .. " Shows stored spell icons and a 30-second countdown bar during Stasis.",
        50, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, 50, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Display Settings
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Display Settings", yOffset)
    manager:Register(card2, "all")

    local row2a = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local iconSizeSlider = GUIFrame:CreateSlider(row2a, "Icon Size", {
        min = 20, max = 60, step = 1,
        value = db.IconSize or 40,
        callback = function(val) db.IconSize = val; ApplySettings() end,
    })
    row2a:AddWidget(iconSizeSlider, 0.5)
    manager:Register(iconSizeSlider, "all")

    local iconSpacingSlider = GUIFrame:CreateSlider(row2a, "Icon Spacing", {
        min = -5, max = 10, step = 1,
        value = db.IconSpacing or 2,
        callback = function(val) db.IconSpacing = val; ApplySettings() end,
    })
    row2a:AddWidget(iconSpacingSlider, 0.5)
    manager:Register(iconSpacingSlider, "all")
    card2:AddRow(row2a, Theme.rowHeight)

    local row2b = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local growthDropdown = GUIFrame:CreateDropdown(row2b, "Growth Direction", {
        options = {
            { key = "Horizontal", text = "Horizontal" },
            { key = "Vertical",   text = "Vertical" },
        },
        value = db.GrowthDirection or "Horizontal",
        callback = function(key) db.GrowthDirection = key; ApplySettings() end,
    })
    row2b:AddWidget(growthDropdown, 0.5)
    manager:Register(growthDropdown, "all")

    local barSideDropdown = GUIFrame:CreateDropdown(row2b, "Bar Side", {
        options = {
            { key = "start", text = "Top / Left" },
            { key = "end",   text = "Bottom / Right" },
        },
        value = db.BarSide or "start",
        callback = function(key) db.BarSide = key; ApplySettings() end,
    })
    row2b:AddWidget(barSideDropdown, 0.5)
    manager:Register(barSideDropdown, "all")
    card2:AddRow(row2b, Theme.rowHeight)

    local row2c = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local barHeightSlider = GUIFrame:CreateSlider(row2c, "Bar Height", {
        min = 5, max = 30, step = 1,
        value = db.BarHeight or 15,
        callback = function(val) db.BarHeight = val; ApplySettings() end,
    })
    row2c:AddWidget(barHeightSlider, 1)
    manager:Register(barHeightSlider, "all")
    card2:AddRow(row2c, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Position Settings
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Position Settings",
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
        onChangeCallback = ApplyPosition,
    })

    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "all")
    end
    manager:Register(posCard, "all")
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 4: Font Settings (countdown text)
    ----------------------------------------------------------------
    local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            fontFace = "FontFace",
            fontSize = "FontSize",
            fontOutline = "FontOutline",
        },
        fontSizeRange = { 8, 36 },
        includeSoftOutline = true,
        onChangeCallback = ApplySettings,
    })
    manager:Register(fontCard, "all")
    if fontWidgets then
        manager:RegisterGroup(fontWidgets, "all")
    end
    yOffset = fontOffset

    ----------------------------------------------------------------
    -- Card 5: Colors
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    manager:Register(card5, "all")

    local row5a = GUIFrame:CreateRow(card5.content, Theme.rowHeight)
    local colorModeDropdown = GUIFrame:CreateDropdown(row5a, "Color Mode", {
        options = KE.ColorModeOptions,
        value = db.ColorMode or "custom",
        callback = function(key)
            db.ColorMode = key
            ApplySettings()
            RefreshStates()
        end,
    })
    row5a:AddWidget(colorModeDropdown, 0.5)
    manager:Register(colorModeDropdown, "all")

    local colorPicker = GUIFrame:CreateColorPicker(row5a, "Custom Color", {
        color = db.Color or { 0.2, 0.5, 0.4, 1 },
        callback = function(r, g, b, a)
            db.Color = { r, g, b, a }
            ApplySettings()
        end,
    })
    row5a:AddWidget(colorPicker, 0.5)
    manager:Register(colorPicker, "customColor")
    card5:AddRow(row5a, Theme.rowHeight)

    local statusbarList = {}
    if LSM then
        for name in pairs(LSM:HashTable("statusbar")) do statusbarList[name] = name end
    else
        statusbarList["Blizzard"] = "Blizzard"
    end

    local row5b = GUIFrame:CreateRow(card5.content, Theme.rowHeightLast)
    local bgColorPicker = GUIFrame:CreateColorPicker(row5b, "Bar Background", {
        color = db.BarBackgroundColor or { 0, 0, 0, 0.8 },
        callback = function(r, g, b, a)
            db.BarBackgroundColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row5b:AddWidget(bgColorPicker, 0.5)
    manager:Register(bgColorPicker, "all")

    local barTextureDropdown = GUIFrame:CreateDropdown(row5b, "Bar Texture", {
        options = statusbarList,
        value = db.BarTexture or "KitnUI",
        callback = function(key) db.BarTexture = key; ApplySettings() end,
    })
    row5b:AddWidget(barTextureDropdown, 0.5)
    manager:Register(barTextureDropdown, "all")
    card5:AddRow(row5b, Theme.rowHeightLast, 0)

    yOffset = card5:GetNextOffset()

    RefreshStates()
    return yOffset
end)
