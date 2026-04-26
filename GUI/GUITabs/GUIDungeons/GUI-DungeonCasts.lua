-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-DungeonCasts.lua                                    ║
-- ║  GUI: Dungeon Casts                                      ║
-- ║  Purpose: Configuration panel for the DungeonCasts       ║
-- ║           module.                                        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme    = KE.Theme
local LSM      = KE.LSM or LibStub("LibSharedMedia-3.0", true)
local pairs = pairs
local table_insert = table.insert

---------------------------------------------------------------------------------
-- Content Registration
---------------------------------------------------------------------------------

GUIFrame:RegisterContent("DungeonCasts", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.Dungeons.DungeonCasts
    if not db then return yOffset end

    local DC = KitnEssentials and KitnEssentials:GetModule("DungeonCasts", true) or nil

    -- Track widgets for enable/disable logic
    local allWidgets = {}

    -- Build statusbar list from LSM
    local statusbarList = {}
    if LSM then
        for name in pairs(LSM:HashTable("statusbar")) do
            statusbarList[name] = name
        end
    else
        statusbarList["Blizzard"] = "Blizzard"
    end

    -- Build font list from LSM
    local fontList = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do
            fontList[name] = name
        end
    else
        fontList["Friz Quadrata TT"] = "Friz Quadrata TT"
    end

    -- Helper to apply settings changes
    local function ApplySettings()
        if DC and DC.ApplySettings then
            DC:ApplySettings()
        end
    end

    -- Helper to apply position changes
    local function ApplyPosition()
        if DC and DC.ApplyPosition then
            DC:ApplyPosition()
        end
    end

    -- Helper to apply new state
    local function ApplyModuleState(enabled)
        if not KitnEssentials then return end
        db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("DungeonCasts")
        else
            KitnEssentials:DisableModule("DungeonCasts")
        end
    end

    -- Widget state update
    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false
        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then
                widget:SetEnabled(mainEnabled)
            end
        end
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Dungeon Casts", yOffset)

    local row1a = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1a, "Enable Dungeon Casts", db.Enabled ~= false,
        function(checked)
            ApplyModuleState(checked)
            UpdateAllWidgetStates()
            ApplySettings()
            KE:CreateReloadPrompt("Enabling/Disabling this module requires a reload to take full effect.")
        end,
        true, "Dungeon Casts", "On", "Off"
    )
    row1a:AddWidget(enableCheck, 1)
    card1:AddRow(row1a, 36)

    card1:AddLabel("|cff888888Displays enemy nameplate casts in a configurable stack.\nOnly active in M+ dungeons.|r")

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 2: Position Settings
    ----------------------------------------------------------------
    local _, newYOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        db = db.Frame,
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
    yOffset = newYOffset

    ----------------------------------------------------------------
    -- Card 3: Frame Settings
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Frame Settings", yOffset)

    local row3a = GUIFrame:CreateRow(card3.content, 36)
    local widthSlider = GUIFrame:CreateSlider(row3a, "Bar Width", 100, 400, 1,
        db.Frame.Width or 220, nil,
        function(value)
            db.Frame.Width = value
            ApplySettings()
        end)
    row3a:AddWidget(widthSlider, 0.5)
    table_insert(allWidgets, widthSlider)

    local heightSlider = GUIFrame:CreateSlider(row3a, "Bar Height", 16, 40, 1,
        db.Frame.Height or 24, nil,
        function(value)
            db.Frame.Height = value
            ApplySettings()
        end)
    row3a:AddWidget(heightSlider, 0.5)
    table_insert(allWidgets, heightSlider)
    card3:AddRow(row3a, 36)

    local row3b = GUIFrame:CreateRow(card3.content, 36)
    local maxBarsSlider = GUIFrame:CreateSlider(row3b, "Max Bars", 1, 10, 1,
        db.Frame.MaxBars or 5, nil,
        function(value)
            db.Frame.MaxBars = value
            ApplySettings()
        end)
    row3b:AddWidget(maxBarsSlider, 0.5)
    table_insert(allWidgets, maxBarsSlider)

    local spacingSlider = GUIFrame:CreateSlider(row3b, "Spacing", 0, 10, 1,
        db.Frame.Spacing or 2, nil,
        function(value)
            db.Frame.Spacing = value
            ApplySettings()
        end)
    row3b:AddWidget(spacingSlider, 0.5)
    table_insert(allWidgets, spacingSlider)
    card3:AddRow(row3b, 36)

    local row3c = GUIFrame:CreateRow(card3.content, 36)
    local growthOptions = { DOWN = "Down", UP = "Up" }
    local growthDropdown = GUIFrame:CreateDropdown(row3c, "Growth Direction", growthOptions,
        db.Frame.GrowthDirection or "DOWN", 70,
        function(selected)
            db.Frame.GrowthDirection = selected
            ApplySettings()
        end)
    row3c:AddWidget(growthDropdown, 1)
    table_insert(allWidgets, growthDropdown)
    card3:AddRow(row3c, 36)

    yOffset = yOffset + card3:GetContentHeight() + (Theme.paddingMedium or 10)

    ----------------------------------------------------------------
    -- Card 4: Bar Appearance
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Bar Appearance", yOffset)

    local row4a = GUIFrame:CreateRow(card4.content, 36)
    local textureDropdown = GUIFrame:CreateDropdown(row4a, "Bar Texture", statusbarList,
        db.BarDisplay.StatusBarTexture or "KitnUI", 70,
        function(selected)
            db.BarDisplay.StatusBarTexture = selected
            ApplySettings()
        end)
    row4a:AddWidget(textureDropdown, 1)
    table_insert(allWidgets, textureDropdown)
    card4:AddRow(row4a, 36)

    local row4b = GUIFrame:CreateRow(card4.content, 36)
    local fontDropdown = GUIFrame:CreateDropdown(row4b, "Font", fontList,
        db.BarDisplay.FontFace or "Expressway", 70,
        function(selected)
            db.BarDisplay.FontFace = selected
            ApplySettings()
        end, true)
    row4b:AddWidget(fontDropdown, 0.5)
    table_insert(allWidgets, fontDropdown)

    local fontSizeSlider = GUIFrame:CreateSlider(row4b, "Font Size", 8, 24, 1,
        db.BarDisplay.FontSize or 12, nil,
        function(value)
            db.BarDisplay.FontSize = value
            ApplySettings()
        end)
    row4b:AddWidget(fontSizeSlider, 0.5)
    table_insert(allWidgets, fontSizeSlider)
    card4:AddRow(row4b, 36)

    local row4c = GUIFrame:CreateRow(card4.content, 36)
    local outlineOptions = { NONE = "None", OUTLINE = "Outline", THICKOUTLINE = "Thick Outline" }
    local outlineDropdown = GUIFrame:CreateDropdown(row4c, "Font Outline", outlineOptions,
        db.BarDisplay.FontOutline or "OUTLINE", 70,
        function(selected)
            db.BarDisplay.FontOutline = selected
            ApplySettings()
        end)
    row4c:AddWidget(outlineDropdown, 1)
    table_insert(allWidgets, outlineDropdown)
    card4:AddRow(row4c, 36)

    -- Separator
    local rowSep4 = GUIFrame:CreateRow(card4.content, 8)
    local sep4 = GUIFrame:CreateSeparator(rowSep4)
    rowSep4:AddWidget(sep4, 1)
    table_insert(allWidgets, sep4)
    card4:AddRow(rowSep4, 8)

    local row4d = GUIFrame:CreateRow(card4.content, 36)
    local iconCheck = GUIFrame:CreateCheckbox(row4d, "Show Spell Icon", db.Icon.Enabled ~= false, function(checked)
        db.Icon.Enabled = checked
        ApplySettings()
    end)
    row4d:AddWidget(iconCheck, 0.5)
    table_insert(allWidgets, iconCheck)

    local sparkCheck = GUIFrame:CreateCheckbox(row4d, "Show Spark", db.BarDisplay.SparkEnabled ~= false, function(checked)
        db.BarDisplay.SparkEnabled = checked
        ApplySettings()
    end)
    row4d:AddWidget(sparkCheck, 0.5)
    table_insert(allWidgets, sparkCheck)
    card4:AddRow(row4d, 36)

    local row4e = GUIFrame:CreateRow(card4.content, 36)
    local raidIconCheck = GUIFrame:CreateCheckbox(row4e, "Show Raid Target Icon", db.RaidIcon.Enabled ~= false, function(checked)
        db.RaidIcon.Enabled = checked
        ApplySettings()
    end)
    row4e:AddWidget(raidIconCheck, 0.5)
    table_insert(allWidgets, raidIconCheck)

    local showTimeCheck = GUIFrame:CreateCheckbox(row4e, "Show Cast Time", db.Text.ShowTime ~= false, function(checked)
        db.Text.ShowTime = checked
        ApplySettings()
    end)
    row4e:AddWidget(showTimeCheck, 0.5)
    table_insert(allWidgets, showTimeCheck)
    card4:AddRow(row4e, 36)

    local row4f = GUIFrame:CreateRow(card4.content, 36)
    local raidIconSizeSlider = GUIFrame:CreateSlider(row4f, "Raid Icon Size", 12, 40, 1,
        db.RaidIcon.Size or 20, nil,
        function(value)
            db.RaidIcon.Size = value
            ApplySettings()
        end)
    row4f:AddWidget(raidIconSizeSlider, 0.5)
    table_insert(allWidgets, raidIconSizeSlider)
    card4:AddRow(row4f, 36)

    yOffset = yOffset + card4:GetContentHeight() + (Theme.paddingMedium or 10)

    ----------------------------------------------------------------
    -- Card 5: Colors
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)

    card5:AddLabel("|cff888888Cast bar status colors|r")

    local row5a = GUIFrame:CreateRow(card5.content, 36)
    local castingColorPicker = GUIFrame:CreateColorPicker(row5a, "Casting", db.CastingColor, function(r, g, b, a)
        db.CastingColor = { r, g, b, a }
        ApplySettings()
    end)
    row5a:AddWidget(castingColorPicker, 0.33)
    table_insert(allWidgets, castingColorPicker)

    local channelingColorPicker = GUIFrame:CreateColorPicker(row5a, "Channeling", db.ChannelingColor, function(r, g, b, a)
        db.ChannelingColor = { r, g, b, a }
        ApplySettings()
    end)
    row5a:AddWidget(channelingColorPicker, 0.33)
    table_insert(allWidgets, channelingColorPicker)

    local shieldedColorPicker = GUIFrame:CreateColorPicker(row5a, "Shielded", db.NotInterruptibleColor, function(r, g, b, a)
        db.NotInterruptibleColor = { r, g, b, a }
        ApplySettings()
    end)
    row5a:AddWidget(shieldedColorPicker, 0.34)
    table_insert(allWidgets, shieldedColorPicker)
    card5:AddRow(row5a, 36)

    -- Separator
    local rowSep5 = GUIFrame:CreateRow(card5.content, 8)
    local sep5 = GUIFrame:CreateSeparator(rowSep5)
    rowSep5:AddWidget(sep5, 1)
    table_insert(allWidgets, sep5)
    card5:AddRow(rowSep5, 8)

    card5:AddLabel("|cff888888Frame colors|r")

    local row5b = GUIFrame:CreateRow(card5.content, 36)
    local bgColorPicker = GUIFrame:CreateColorPicker(row5b, "Background", db.BackgroundColor, function(r, g, b, a)
        db.BackgroundColor = { r, g, b, a }
        ApplySettings()
    end)
    row5b:AddWidget(bgColorPicker, 0.33)
    table_insert(allWidgets, bgColorPicker)

    local borderColorPicker = GUIFrame:CreateColorPicker(row5b, "Border", db.BorderColor, function(r, g, b, a)
        db.BorderColor = { r, g, b, a }
        ApplySettings()
    end)
    row5b:AddWidget(borderColorPicker, 0.33)
    table_insert(allWidgets, borderColorPicker)

    local textColorPicker = GUIFrame:CreateColorPicker(row5b, "Text", db.Text.TextColor, function(r, g, b, a)
        db.Text.TextColor = { r, g, b, a }
        ApplySettings()
    end)
    row5b:AddWidget(textColorPicker, 0.34)
    table_insert(allWidgets, textColorPicker)
    card5:AddRow(row5b, 36)

    yOffset = yOffset + card5:GetContentHeight() + (Theme.paddingMedium or 10)

    ----------------------------------------------------------------
    -- Card 6: Target Settings
    ----------------------------------------------------------------
    local card6 = GUIFrame:CreateCard(scrollChild, "Target Settings", yOffset)

    local row6a = GUIFrame:CreateRow(card6.content, 36)
    local targetCheck = GUIFrame:CreateCheckbox(row6a, "Show Cast Target", db.Target and db.Target.Enabled ~= false, function(checked)
        db.Target.Enabled = checked
        ApplySettings()
    end)
    row6a:AddWidget(targetCheck, 0.5)
    table_insert(allWidgets, targetCheck)

    local classColorCheck = GUIFrame:CreateCheckbox(row6a, "Use Class Colors", db.Target and db.Target.ShowClassColor ~= false, function(checked)
        db.Target.ShowClassColor = checked
        ApplySettings()
    end)
    row6a:AddWidget(classColorCheck, 0.5)
    table_insert(allWidgets, classColorCheck)
    card6:AddRow(row6a, 36)

    local row6b = GUIFrame:CreateRow(card6.content, 36)
    local positionOptions = { LEFT = "Left", RIGHT = "Right" }
    local positionDropdown = GUIFrame:CreateDropdown(row6b, "Target Position", positionOptions,
        (db.Target and db.Target.Position) or "RIGHT", 70,
        function(selected)
            db.Target.Position = selected
            ApplySettings()
        end)
    row6b:AddWidget(positionDropdown, 0.5)
    table_insert(allWidgets, positionDropdown)

    local separatorOptions = {
        ["\194\187"] = "\194\187",
        ["-"] = "-",
        [">"] = ">",
        [">>"] = ">>",
        ["\226\128\162"] = "\226\128\162",
        ["None"] = "None",
    }
    local separatorDropdown = GUIFrame:CreateDropdown(row6b, "Separator", separatorOptions,
        (db.Target and db.Target.Separator) or "\194\187", 70,
        function(selected)
            db.Target.Separator = selected
            ApplySettings()
        end)
    row6b:AddWidget(separatorDropdown, 0.5)
    table_insert(allWidgets, separatorDropdown)
    card6:AddRow(row6b, 36)

    card6:AddLabel("|cff888888Show the target of enemy casts on the cast bar.|r")

    yOffset = yOffset + card6:GetContentHeight() + (Theme.paddingMedium or 10)

    -- Apply initial widget states
    UpdateAllWidgetStates()

    return yOffset
end)
