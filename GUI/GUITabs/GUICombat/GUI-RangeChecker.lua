-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-RangeChecker.lua                                    ║
-- ║  GUI: Range Display                                      ║
-- ║  Purpose: Configuration panel for the RangeChecker       ║
-- ║  module.                                                 ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
    return KitnEssentials:GetModule("RangeChecker", true)
end

GUIFrame:RegisterContent("RangeChecker", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.RangeChecker
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local mod = GetModule()
    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        if mod and mod.ApplySettings then mod:ApplySettings() end
    end

    local function ApplyPosition()
        if mod and mod.ApplyPosition then mod:ApplyPosition() end
    end

    local function ApplyModuleState(enabled)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("RangeChecker")
        else
            KitnEssentials:DisableModule("RangeChecker")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Range Checker Text", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Range Checker Text", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Range Checker Text",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, Theme.rowHeightLast, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: General Settings
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "General Settings", yOffset)
    manager:Register(card2, "all")

    local row2a = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local combatOnlyCheck = GUIFrame:CreateCheckbox(row2a, "Show In Combat Only", {
        value = db.CombatOnly ~= false,
        callback = function(checked) db.CombatOnly = checked; ApplySettings() end,
    })
    row2a:AddWidget(combatOnlyCheck, 1)
    manager:Register(combatOnlyCheck, "all")
    card2:AddRow(row2a, Theme.rowHeight)

    local rowSep = GUIFrame:CreateRow(card2.content, Theme.rowHeightSeparator)
    local sep1 = GUIFrame:CreateSeparator(rowSep)
    rowSep:AddWidget(sep1, 1)
    manager:Register(sep1, "all")
    card2:AddRow(rowSep, Theme.rowHeightSeparator)

    local row2b = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local throttleSlider = GUIFrame:CreateSlider(row2b, "Update Throttle", {
        min = 0, max = 1, step = 0.05,
        value = db.UpdateThrottle or 0.1,
        callback = function(val) db.UpdateThrottle = val; ApplySettings() end,
    })
    row2b:AddWidget(throttleSlider, 1)
    manager:Register(throttleSlider, "all")
    card2:AddRow(row2b, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

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
        onChangeCallback = ApplyPosition,
    })

    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "all")
    end
    manager:Register(posCard, "all")
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 4: Font Settings
    ----------------------------------------------------------------
    local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            fontFace = "FontFace",
            fontSize = "FontSize",
            fontOutline = "FontOutline",
        },
        includeSoftOutline = true,
        onChangeCallback = ApplySettings,
    })
    manager:Register(fontCard, "all")
    if fontWidgets then
        manager:RegisterGroup(fontWidgets, "all")
    end
    yOffset = fontOffset

    ----------------------------------------------------------------
    -- Card 5: Color Settings
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Color Settings", yOffset)
    manager:Register(card5, "all")

    local row5a = GUIFrame:CreateRow(card5.content, Theme.rowHeight)
    local colorFourPicker = GUIFrame:CreateColorPicker(row5a, "0-10 Yards", {
        color = db.ColorFour or { 0, 1, 0, 1 },
        callback = function(r, g, b, a)
            db.ColorFour = { r, g, b, a }
            ApplySettings()
        end,
    })
    row5a:AddWidget(colorFourPicker, 0.5)
    manager:Register(colorFourPicker, "all")

    local colorTwoPicker = GUIFrame:CreateColorPicker(row5a, "20-40 Yards", {
        color = db.ColorTwo or { 1, 0.42, 0, 1 },
        callback = function(r, g, b, a)
            db.ColorTwo = { r, g, b, a }
            ApplySettings()
        end,
    })
    row5a:AddWidget(colorTwoPicker, 0.5)
    manager:Register(colorTwoPicker, "all")
    card5:AddRow(row5a, Theme.rowHeight)

    local row5b = GUIFrame:CreateRow(card5.content, Theme.rowHeightLast)
    local colorThreePicker = GUIFrame:CreateColorPicker(row5b, "10-20 Yards", {
        color = db.ColorThree or { 1, 0.82, 0, 1 },
        callback = function(r, g, b, a)
            db.ColorThree = { r, g, b, a }
            ApplySettings()
        end,
    })
    row5b:AddWidget(colorThreePicker, 0.5)
    manager:Register(colorThreePicker, "all")

    local colorOnePicker = GUIFrame:CreateColorPicker(row5b, "40+ Yards", {
        color = db.ColorOne or { 1, 0, 0, 1 },
        callback = function(r, g, b, a)
            db.ColorOne = { r, g, b, a }
            ApplySettings()
        end,
    })
    row5b:AddWidget(colorOnePicker, 0.5)
    manager:Register(colorOnePicker, "all")
    card5:AddRow(row5b, Theme.rowHeightLast, 0)

    yOffset = card5:GetNextOffset()

    RefreshStates()
    return yOffset
end)
