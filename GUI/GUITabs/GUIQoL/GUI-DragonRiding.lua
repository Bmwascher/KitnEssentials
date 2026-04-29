-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-DragonRiding.lua                                    ║
-- ║  GUI: Skyriding UI                                       ║
-- ║  Purpose: Configuration panel for the                    ║
-- ║           DragonRiding module.                           ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("DragonRiding", true)
    end
    return nil
end

GUIFrame:RegisterContent("DragonRiding", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.DragonRiding
    if not db then return yOffset end

    local DR = GetModule()
    local manager = GUIFrame:CreateWidgetStateManager()
    manager:SetCondition("thrill",     function() return db.EnableThrillColor ~= false end)
    manager:SetCondition("manualSize", function() return db.SurgeIconAutoSize == false end)

    local function ApplySettings()
        if DR and DR.ApplySettings then DR:ApplySettings() end
    end

    local function ApplyLayout()
        if DR and DR.ApplyBarLayout then DR:ApplyBarLayout() end
        if DR and DR.ApplySurgeIcon then DR:ApplySurgeIcon() end
    end

    local function ApplySurgeIcon()
        if DR and DR.ApplySurgeIcon then DR:ApplySurgeIcon() end
    end

    local function ApplyState(enabled)
        if not DR then return end
        DR.db.Enabled = enabled
        if enabled then KitnEssentials:EnableModule("DragonRiding")
        else KitnEssentials:DisableModule("DragonRiding") end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Skyriding UI", yOffset)
    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Skyriding UI", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyState(checked)
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Skyriding UI",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, Theme.rowHeightLast, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Position Settings
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
        showAnchorFrameType = false,
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
    -- Card 3: Behavior
    ----------------------------------------------------------------
    local cardBehavior = GUIFrame:CreateCard(scrollChild, "Behavior", yOffset)
    manager:Register(cardBehavior, "all")

    local bRow1 = GUIFrame:CreateRow(cardBehavior.content, Theme.rowHeight)
    local groundedCheck = GUIFrame:CreateCheckbox(bRow1, "Hide When Grounded", {
        value = db.HideWhenGrounded == true,
        callback = function(checked)
            db.HideWhenGrounded = checked
            if not checked and DR and DR.container then DR.container:Show() end
        end,
        msgPopup = true,
        msgText = "Hide Grounded",
        msgOn = "On",
        msgOff = "Off",
    })
    bRow1:AddWidget(groundedCheck, 1/3)
    manager:Register(groundedCheck, "all")

    local fullCheck = GUIFrame:CreateCheckbox(bRow1, "Hide When Full", {
        value = db.HideWhenFull == true,
        callback = function(checked)
            db.HideWhenFull = checked
            if not checked and DR and DR.container then DR.container:Show() end
        end,
        msgPopup = true,
        msgText = "Hide Full",
        msgOn = "On",
        msgOff = "Off",
    })
    bRow1:AddWidget(fullCheck, 1/3)
    manager:Register(fullCheck, "all")

    local thrillCheck = GUIFrame:CreateCheckbox(bRow1, "Use Thrill Color", {
        value = db.EnableThrillColor ~= false,
        callback = function(checked)
            db.EnableThrillColor = checked
            ApplySettings()
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Thrill Color",
        msgOn = "On",
        msgOff = "Off",
    })
    bRow1:AddWidget(thrillCheck, 1/3)
    manager:Register(thrillCheck, "all")
    cardBehavior:AddRow(bRow1, Theme.rowHeight)

    local bRow2 = GUIFrame:CreateRow(cardBehavior.content, Theme.rowHeightLast)
    local secondWindCheck = GUIFrame:CreateCheckbox(bRow2, "Show Second Wind", {
        value = db.ShowSecondWind ~= false,
        callback = function(checked) db.ShowSecondWind = checked; ApplyLayout() end,
        msgPopup = true,
        msgText = "Second Wind",
        msgOn = "On",
        msgOff = "Off",
    })
    bRow2:AddWidget(secondWindCheck, 1/3)
    manager:Register(secondWindCheck, "all")

    local flipCheck = GUIFrame:CreateCheckbox(bRow2, "Flip Bar Order", {
        value = db.FlipBars == true,
        callback = function(checked) db.FlipBars = checked; ApplyLayout() end,
        msgPopup = true,
        msgText = "Flip Bars",
        msgOn = "On",
        msgOff = "Off",
    })
    bRow2:AddWidget(flipCheck, 1/3)
    manager:Register(flipCheck, "all")

    local speedTextCheck = GUIFrame:CreateCheckbox(bRow2, "Show Speed Text", {
        value = db.ShowSpeedText ~= false,
        callback = function(checked) db.ShowSpeedText = checked; ApplyLayout() end,
        msgPopup = true,
        msgText = "Speed Text",
        msgOn = "On",
        msgOff = "Off",
    })
    bRow2:AddWidget(speedTextCheck, 1/3)
    manager:Register(speedTextCheck, "all")
    cardBehavior:AddRow(bRow2, Theme.rowHeightLast, 0)

    yOffset = cardBehavior:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Size Settings
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Size Settings", yOffset)
    manager:Register(card4, "all")

    local row4a = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local widthSlider = GUIFrame:CreateSlider(row4a, "Width", {
        min = 100, max = 500, step = 1,
        value = db.Width or 252,
        callback = function(val) db.Width = val; ApplySettings() end,
    })
    row4a:AddWidget(widthSlider, 1)
    manager:Register(widthSlider, "all")
    card4:AddRow(row4a, Theme.rowHeight)

    local row4b = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local heightSlider = GUIFrame:CreateSlider(row4b, "Bar Height", {
        min = 1, max = 24, step = 1,
        value = db.BarHeight or 12,
        callback = function(val) db.BarHeight = val; ApplySettings() end,
    })
    row4b:AddWidget(heightSlider, 1)
    manager:Register(heightSlider, "all")
    card4:AddRow(row4b, Theme.rowHeight)

    local row4c = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local spacingSlider = GUIFrame:CreateSlider(row4c, "Row Spacing", {
        min = 0, max = 10, step = 1,
        value = db.Spacing or 1,
        callback = function(val) db.Spacing = val; ApplySettings() end,
    })
    row4c:AddWidget(spacingSlider, 1)
    manager:Register(spacingSlider, "all")
    card4:AddRow(row4c, Theme.rowHeight)

    local row4d = GUIFrame:CreateRow(card4.content, Theme.rowHeightLast)
    local speedFontSlider = GUIFrame:CreateSlider(row4d, "Speed Font Size", {
        min = 8, max = 24, step = 1,
        value = db.SpeedFontSize or 14,
        callback = function(val) db.SpeedFontSize = val; ApplySettings() end,
    })
    row4d:AddWidget(speedFontSlider, 1)
    manager:Register(speedFontSlider, "all")
    card4:AddRow(row4d, Theme.rowHeightLast, 0)

    yOffset = card4:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Surge Icon
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Whirling Surge Icon", yOffset)
    manager:Register(card5, "all")

    local sRow1 = GUIFrame:CreateRow(card5.content, Theme.rowHeight)
    local showSurgeCheck = GUIFrame:CreateCheckbox(sRow1, "Show Surge Icon", {
        value = db.ShowSurgeIcon ~= false,
        callback = function(checked) db.ShowSurgeIcon = checked; ApplySurgeIcon() end,
        msgPopup = true,
        msgText = "Surge Icon",
        msgOn = "On",
        msgOff = "Off",
    })
    sRow1:AddWidget(showSurgeCheck, 1/3)
    manager:Register(showSurgeCheck, "all")

    local leftSideCheck = GUIFrame:CreateCheckbox(sRow1, "Place on Left Side", {
        value = db.SurgeIconOnLeft == true,
        callback = function(checked) db.SurgeIconOnLeft = checked; ApplySurgeIcon() end,
        msgPopup = true,
        msgText = "Left Side",
        msgOn = "On",
        msgOff = "Off",
    })
    sRow1:AddWidget(leftSideCheck, 1/3)
    manager:Register(leftSideCheck, "all")

    local autoSizeCheck = GUIFrame:CreateCheckbox(sRow1, "Auto Size", {
        value = db.SurgeIconAutoSize ~= false,
        callback = function(checked)
            db.SurgeIconAutoSize = checked
            ApplySurgeIcon()
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Auto Size",
        msgOn = "On",
        msgOff = "Off",
    })
    sRow1:AddWidget(autoSizeCheck, 1/3)
    manager:Register(autoSizeCheck, "all")
    card5:AddRow(sRow1, Theme.rowHeight)

    local sRow2 = GUIFrame:CreateRow(card5.content, Theme.rowHeightLast)
    local gapSlider = GUIFrame:CreateSlider(sRow2, "Gap From Bars", {
        min = 0, max = 20, step = 1,
        value = db.SurgeIconGap or 4,
        callback = function(val) db.SurgeIconGap = val; ApplySurgeIcon() end,
    })
    sRow2:AddWidget(gapSlider, 0.5)
    manager:Register(gapSlider, "all")

    local sizeSlider = GUIFrame:CreateSlider(sRow2, "Icon Size", {
        min = 16, max = 64, step = 1,
        value = db.SurgeIconSize or 26,
        callback = function(val) db.SurgeIconSize = val; ApplySurgeIcon() end,
    })
    sRow2:AddWidget(sizeSlider, 0.5)
    manager:Register(sizeSlider, "manualSize")
    card5:AddRow(sRow2, Theme.rowHeightLast, 0)

    yOffset = card5:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 6: Colors
    ----------------------------------------------------------------
    local card6 = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    manager:Register(card6, "all")

    db.Colors = db.Colors or {}

    local row6 = GUIFrame:CreateRow(card6.content, Theme.rowHeightLast)
    local vigorPicker = GUIFrame:CreateColorPicker(row6, "Vigor", {
        color = db.Colors.Vigor or { 0.898, 0.063, 0.224, 1 },
        callback = function(r, g, b, a) db.Colors.Vigor = { r, g, b, a }; ApplySettings() end,
    })
    row6:AddWidget(vigorPicker, 1/3)
    manager:Register(vigorPicker, "all")

    local thrillPicker = GUIFrame:CreateColorPicker(row6, "Vigor (Thrill)", {
        color = db.Colors.VigorThrill or { 0.2, 0.8, 0.2, 1 },
        callback = function(r, g, b, a) db.Colors.VigorThrill = { r, g, b, a }; ApplySettings() end,
    })
    row6:AddWidget(thrillPicker, 1/3)
    manager:Register(thrillPicker, "thrill")

    local swPicker = GUIFrame:CreateColorPicker(row6, "Second Wind", {
        color = db.Colors.SecondWind or { 0.3, 0.7, 1, 1 },
        callback = function(r, g, b, a) db.Colors.SecondWind = { r, g, b, a }; ApplySettings() end,
    })
    row6:AddWidget(swPicker, 1/3)
    manager:Register(swPicker, "all")
    card6:AddRow(row6, Theme.rowHeightLast, 0)

    yOffset = card6:GetNextOffset()

    RefreshStates()
    return yOffset
end)
