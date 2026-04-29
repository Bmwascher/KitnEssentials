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

GUIFrame:RegisterContent("DungeonCasts", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.Dungeons.DungeonCasts
    if not db then return yOffset end

    local DC = KitnEssentials and KitnEssentials:GetModule("DungeonCasts", true) or nil

    local manager = GUIFrame:CreateWidgetStateManager()

    local statusbarList = {}
    if LSM then
        for name in pairs(LSM:HashTable("statusbar")) do statusbarList[name] = name end
    else
        statusbarList["Blizzard"] = "Blizzard"
    end

    local function ApplySettings()
        if DC and DC.ApplySettings then DC:ApplySettings() end
    end

    -- Visual-only changes (color/font/texture/icon toggle) refresh existing
    -- bars in place so the cast progress doesn't reset on every slider tweak.
    -- ApplySettings is reserved for structural changes (e.g. MaxBars).
    local function ApplyVisuals()
        if DC and DC.UpdateFrameVisuals then
            DC:UpdateFrameVisuals()
        elseif DC and DC.ApplySettings then
            DC:ApplySettings()
        end
    end

    local function ApplyPosition()
        if DC and DC.ApplyPosition then DC:ApplyPosition() end
    end

    local function ApplyModuleState(enabled)
        if not KitnEssentials then return end
        db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("DungeonCasts")
        else
            KitnEssentials:DisableModule("DungeonCasts")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Dungeon Casts", yOffset)

    local row1a = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1a, "Enable Dungeon Casts", {
        value = db.Enabled ~= false,
        callback = function(checked)
            ApplyModuleState(checked)
            RefreshStates()
            ApplySettings()
            KE:CreateReloadPrompt("Enabling/Disabling this module requires a reload to take full effect.")
        end,
        msgPopup = true,
        msgText = "Dungeon Casts",
        msgOn = "On",
        msgOff = "Off",
    })
    row1a:AddWidget(enableCheck, 1)
    card1:AddRow(row1a, Theme.rowHeight)

    local noteRow = GUIFrame:CreateRow(card1.content, 50)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Displays enemy nameplate casts in a configurable stack.\n" ..
        KE:ColorTextByTheme("-") .. " Only active in M+ dungeons.",
        50, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, 50, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Position Settings
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
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
    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "all")
    end
    manager:Register(posCard, "all")
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 3: Frame Settings
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Frame Settings", yOffset)
    manager:Register(card3, "all")

    local row3a = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local widthSlider = GUIFrame:CreateSlider(row3a, "Bar Width", {
        min = 100, max = 400, step = 1,
        value = db.Frame.Width or 220,
        callback = function(value) db.Frame.Width = value; ApplyVisuals() end,
    })
    row3a:AddWidget(widthSlider, 0.5)
    manager:Register(widthSlider, "all")

    local heightSlider = GUIFrame:CreateSlider(row3a, "Bar Height", {
        min = 16, max = 40, step = 1,
        value = db.Frame.Height or 24,
        callback = function(value) db.Frame.Height = value; ApplyVisuals() end,
    })
    row3a:AddWidget(heightSlider, 0.5)
    manager:Register(heightSlider, "all")
    card3:AddRow(row3a, Theme.rowHeight)

    local row3b = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local maxBarsSlider = GUIFrame:CreateSlider(row3b, "Max Bars", {
        min = 1, max = 10, step = 1,
        value = db.Frame.MaxBars or 5,
        callback = function(value) db.Frame.MaxBars = value; ApplySettings() end,
    })
    row3b:AddWidget(maxBarsSlider, 0.5)
    manager:Register(maxBarsSlider, "all")

    local spacingSlider = GUIFrame:CreateSlider(row3b, "Spacing", {
        min = 0, max = 10, step = 1,
        value = db.Frame.Spacing or 2,
        callback = function(value) db.Frame.Spacing = value; ApplyVisuals() end,
    })
    row3b:AddWidget(spacingSlider, 0.5)
    manager:Register(spacingSlider, "all")
    card3:AddRow(row3b, Theme.rowHeight)

    local row3c = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local growthDropdown = GUIFrame:CreateDropdown(row3c, "Growth Direction", {
        options = { { key = "DOWN", text = "Down" }, { key = "UP", text = "Up" } },
        value = db.Frame.GrowthDirection or "DOWN",
        callback = function(key) db.Frame.GrowthDirection = key; ApplyVisuals() end,
    })
    row3c:AddWidget(growthDropdown, 1)
    manager:Register(growthDropdown, "all")
    card3:AddRow(row3c, Theme.rowHeightLast, 0)

    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Bar Appearance (texture + icons + spark + time)
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Bar Appearance", yOffset)
    manager:Register(card4, "all")

    local row4a = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local textureDropdown = GUIFrame:CreateDropdown(row4a, "Bar Texture", {
        options = statusbarList,
        value = db.BarDisplay.StatusBarTexture or "KitnUI",
        callback = function(key) db.BarDisplay.StatusBarTexture = key; ApplyVisuals() end,
        searchable = true,
    })
    row4a:AddWidget(textureDropdown, 1)
    manager:Register(textureDropdown, "all")
    card4:AddRow(row4a, Theme.rowHeight)

    local row4b = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local iconCheck = GUIFrame:CreateCheckbox(row4b, "Show Spell Icon", {
        value = db.Icon.Enabled ~= false,
        callback = function(checked) db.Icon.Enabled = checked; ApplyVisuals() end,
    })
    row4b:AddWidget(iconCheck, 0.5)
    manager:Register(iconCheck, "all")

    local sparkCheck = GUIFrame:CreateCheckbox(row4b, "Show Spark", {
        value = db.BarDisplay.SparkEnabled ~= false,
        callback = function(checked) db.BarDisplay.SparkEnabled = checked; ApplyVisuals() end,
    })
    row4b:AddWidget(sparkCheck, 0.5)
    manager:Register(sparkCheck, "all")
    card4:AddRow(row4b, Theme.rowHeight)

    local row4c = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local raidIconCheck = GUIFrame:CreateCheckbox(row4c, "Show Raid Target Icon", {
        value = db.RaidIcon.Enabled ~= false,
        callback = function(checked) db.RaidIcon.Enabled = checked; ApplyVisuals() end,
    })
    row4c:AddWidget(raidIconCheck, 0.5)
    manager:Register(raidIconCheck, "all")

    local showTimeCheck = GUIFrame:CreateCheckbox(row4c, "Show Cast Time", {
        value = db.Text.ShowTime ~= false,
        callback = function(checked) db.Text.ShowTime = checked; ApplyVisuals() end,
    })
    row4c:AddWidget(showTimeCheck, 0.5)
    manager:Register(showTimeCheck, "all")
    card4:AddRow(row4c, Theme.rowHeight)

    local row4d = GUIFrame:CreateRow(card4.content, Theme.rowHeightLast)
    local raidIconSizeSlider = GUIFrame:CreateSlider(row4d, "Raid Icon Size", {
        min = 12, max = 40, step = 1,
        value = db.RaidIcon.Size or 20,
        callback = function(value) db.RaidIcon.Size = value; ApplyVisuals() end,
    })
    row4d:AddWidget(raidIconSizeSlider, 1)
    manager:Register(raidIconSizeSlider, "all")
    card4:AddRow(row4d, Theme.rowHeightLast, 0)

    yOffset = card4:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Font Settings
    ----------------------------------------------------------------
    local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        db = db.BarDisplay,
        dbKeys = {
            fontFace = "FontFace",
            fontSize = "FontSize",
            fontOutline = "FontOutline",
        },
        fontSizeRange = { 8, 24 },
        includeSoftOutline = false,
        onChangeCallback = ApplyVisuals,
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

    card6:AddLabel("|cff888888Cast bar status colors|r")

    local row6a = GUIFrame:CreateRow(card6.content, Theme.rowHeight)
    local castingColorPicker = GUIFrame:CreateColorPicker(row6a, "Casting", {
        color = db.CastingColor,
        callback = function(r, g, b, a)
            db.CastingColor = { r, g, b, a }
            ApplyVisuals()
        end,
    })
    row6a:AddWidget(castingColorPicker, 0.33)
    manager:Register(castingColorPicker, "all")

    local channelingColorPicker = GUIFrame:CreateColorPicker(row6a, "Channeling", {
        color = db.ChannelingColor,
        callback = function(r, g, b, a)
            db.ChannelingColor = { r, g, b, a }
            ApplyVisuals()
        end,
    })
    row6a:AddWidget(channelingColorPicker, 0.33)
    manager:Register(channelingColorPicker, "all")

    local shieldedColorPicker = GUIFrame:CreateColorPicker(row6a, "Shielded", {
        color = db.NotInterruptibleColor,
        callback = function(r, g, b, a)
            db.NotInterruptibleColor = { r, g, b, a }
            ApplyVisuals()
        end,
    })
    row6a:AddWidget(shieldedColorPicker, 0.34)
    manager:Register(shieldedColorPicker, "all")
    card6:AddRow(row6a, Theme.rowHeight)

    local rowSep = GUIFrame:CreateRow(card6.content, Theme.rowHeightSeparator)
    local sep = GUIFrame:CreateSeparator(rowSep)
    rowSep:AddWidget(sep, 1)
    manager:Register(sep, "all")
    card6:AddRow(rowSep, Theme.rowHeightSeparator)

    card6:AddLabel("|cff888888Frame colors|r")

    local row6b = GUIFrame:CreateRow(card6.content, Theme.rowHeightLast)
    local bgColorPicker = GUIFrame:CreateColorPicker(row6b, "Background", {
        color = db.BackgroundColor,
        callback = function(r, g, b, a)
            db.BackgroundColor = { r, g, b, a }
            ApplyVisuals()
        end,
    })
    row6b:AddWidget(bgColorPicker, 0.33)
    manager:Register(bgColorPicker, "all")

    local borderColorPicker = GUIFrame:CreateColorPicker(row6b, "Border", {
        color = db.BorderColor,
        callback = function(r, g, b, a)
            db.BorderColor = { r, g, b, a }
            ApplyVisuals()
        end,
    })
    row6b:AddWidget(borderColorPicker, 0.33)
    manager:Register(borderColorPicker, "all")

    local textColorPicker = GUIFrame:CreateColorPicker(row6b, "Text", {
        color = db.Text.TextColor,
        callback = function(r, g, b, a)
            db.Text.TextColor = { r, g, b, a }
            ApplyVisuals()
        end,
    })
    row6b:AddWidget(textColorPicker, 0.34)
    manager:Register(textColorPicker, "all")
    card6:AddRow(row6b, Theme.rowHeightLast, 0)

    yOffset = card6:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 7: Target Settings
    ----------------------------------------------------------------
    local card7 = GUIFrame:CreateCard(scrollChild, "Target Settings", yOffset)
    manager:Register(card7, "all")

    local row7a = GUIFrame:CreateRow(card7.content, Theme.rowHeight)
    local targetCheck = GUIFrame:CreateCheckbox(row7a, "Show Cast Target", {
        value = db.Target and db.Target.Enabled ~= false,
        callback = function(checked) db.Target.Enabled = checked; ApplyVisuals() end,
    })
    row7a:AddWidget(targetCheck, 0.5)
    manager:Register(targetCheck, "all")

    local classColorCheck = GUIFrame:CreateCheckbox(row7a, "Use Class Colors", {
        value = db.Target and db.Target.ShowClassColor ~= false,
        callback = function(checked) db.Target.ShowClassColor = checked; ApplyVisuals() end,
    })
    row7a:AddWidget(classColorCheck, 0.5)
    manager:Register(classColorCheck, "all")
    card7:AddRow(row7a, Theme.rowHeight)

    local row7b = GUIFrame:CreateRow(card7.content, Theme.rowHeightLast)
    local positionDropdown = GUIFrame:CreateDropdown(row7b, "Target Position", {
        options = { { key = "LEFT", text = "Left" }, { key = "RIGHT", text = "Right" } },
        value = (db.Target and db.Target.Position) or "RIGHT",
        callback = function(key) db.Target.Position = key; ApplyVisuals() end,
    })
    row7b:AddWidget(positionDropdown, 0.5)
    manager:Register(positionDropdown, "all")

    local separatorOptions = {
        { key = "\194\187",       text = "\194\187"       },
        { key = "-",              text = "-"              },
        { key = ">",              text = ">"              },
        { key = ">>",             text = ">>"             },
        { key = "\226\128\162",   text = "\226\128\162"   },
        { key = "None",           text = "None"           },
    }
    local separatorDropdown = GUIFrame:CreateDropdown(row7b, "Separator", {
        options = separatorOptions,
        value = (db.Target and db.Target.Separator) or "\194\187",
        callback = function(key) db.Target.Separator = key; ApplyVisuals() end,
    })
    row7b:AddWidget(separatorDropdown, 0.5)
    manager:Register(separatorDropdown, "all")
    card7:AddRow(row7b, Theme.rowHeightLast, 0)

    card7:AddLabel("|cff888888Show the target of enemy casts on the cast bar.|r")

    yOffset = card7:GetNextOffset()

    RefreshStates()
    return yOffset
end)
