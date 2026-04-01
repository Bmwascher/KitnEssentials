-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)
local table_insert = table.insert

GUIFrame:RegisterContent("AugBuffsTracker", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.AugBuffsTracker
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return yOffset + errorCard:GetContentHeight() + Theme.paddingMedium
    end

    local allWidgets = {}

    local function ApplySettings()
        if KitnEssentials then
            local mod = KitnEssentials:GetModule("AugBuffsTracker", true)
            if mod and mod.ApplySettings then mod:ApplySettings() end
        end
    end

    local function ApplyModuleState(enabled)
        if not KitnEssentials then return end
        local mod = KitnEssentials:GetModule("AugBuffsTracker", true)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("AugBuffsTracker")
        else
            KitnEssentials:DisableModule("AugBuffsTracker")
        end
    end

    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false
        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then widget:SetEnabled(mainEnabled) end
        end
    end

    local a = Theme.accent
    local accentDash = string.format("|cff%02x%02x%02x—|r", a[1]*255, a[2]*255, a[3]*255)

    ----------------------------------------------------------------
    -- Card 1: Aug Buffs Tracker (Enable + Buff Toggles)
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Aug Buffs Tracker", yOffset)

    local row1a = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1a, "Enable Aug Buffs Tracker", db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            UpdateAllWidgetStates()
        end,
        true, "Aug Buffs Tracker", "On", "Off"
    )
    row1a:AddWidget(enableCheck, 1)
    card1:AddRow(row1a, 36)

    -- Buff toggles
    local row1b = GUIFrame:CreateRow(card1.content, 36)
    local presCheck = GUIFrame:CreateCheckbox(row1b, "Prescience", db.ShowPrescience ~= false,
        function(checked)
            db.ShowPrescience = checked
            ApplySettings()
        end)
    row1b:AddWidget(presCheck, 0.5)
    table_insert(allWidgets, presCheck)

    local sandCheck = GUIFrame:CreateCheckbox(row1b, "Shifting Sands", db.ShowShiftingSands == true,
        function(checked)
            db.ShowShiftingSands = checked
            ApplySettings()
        end)
    row1b:AddWidget(sandCheck, 0.5)
    table_insert(allWidgets, sandCheck)
    card1:AddRow(row1b, 36)

    local noteHeight = 50
    local noteRow = GUIFrame:CreateRow(card1.content, noteHeight)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Tracks Prescience and Shifting Sands on party/raid members.\n" .. KE:ColorTextByTheme("-") .. " Only active for Augmentation Evoker.",
        noteHeight, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, noteHeight)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 2: Position Settings
    ----------------------------------------------------------------
    local card2, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
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
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 3: Display Settings
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Display Settings", yOffset)
    table_insert(allWidgets, card3)

    -- Growth Direction + Max Entries
    local row3a = GUIFrame:CreateRow(card3.content, 40)
    local growthOptions = {
        { key = "DOWN", text = "Down" },
        { key = "UP", text = "Up" },
        { key = "RIGHT", text = "Right" },
        { key = "LEFT", text = "Left" },
    }
    local growthDropdown = GUIFrame:CreateDropdown(row3a, "Growth Direction", growthOptions, db.GrowthDirection or "DOWN", 45,
        function(key)
            db.GrowthDirection = key
            ApplySettings()
        end)
    row3a:AddWidget(growthDropdown, 0.5)
    table_insert(allWidgets, growthDropdown)

    local maxSlider = GUIFrame:CreateSlider(row3a, "Max Entries", 1, 20, 1, db.MaxEntries or 6, 50,
        function(val)
            db.MaxEntries = val
            ApplySettings()
        end)
    row3a:AddWidget(maxSlider, 0.5)
    table_insert(allWidgets, maxSlider)
    card3:AddRow(row3a, 40)

    -- Icon Size + Spacing
    local row3c = GUIFrame:CreateRow(card3.content, 40)
    local iconSlider = GUIFrame:CreateSlider(row3c, "Icon Size", 16, 64, 2, db.IconSize or 32, 50,
        function(val)
            db.IconSize = val
            ApplySettings()
        end)
    row3c:AddWidget(iconSlider, 0.5)
    table_insert(allWidgets, iconSlider)

    local spacingSlider = GUIFrame:CreateSlider(row3c, "Spacing", 0, 20, 1, db.Spacing or 4, 50,
        function(val)
            db.Spacing = val
            ApplySettings()
        end)
    row3c:AddWidget(spacingSlider, 0.5)
    table_insert(allWidgets, spacingSlider)
    card3:AddRow(row3c, 40)

    -- Show Role Icons + Role Icon Scale
    local row3d = GUIFrame:CreateRow(card3.content, 40)
    local roleCheck = GUIFrame:CreateCheckbox(row3d, "Show Role Icons", db.ShowRoleIcon ~= false,
        function(checked)
            db.ShowRoleIcon = checked
            ApplySettings()
        end)
    row3d:AddWidget(roleCheck, 0.4)
    table_insert(allWidgets, roleCheck)

    local roleScaleSlider = GUIFrame:CreateSlider(row3d, "Role Icon Scale", 0.5, 3.0, 0.1, db.RoleIconScale or 1.0, 50,
        function(val)
            db.RoleIconScale = val
            ApplySettings()
        end)
    row3d:AddWidget(roleScaleSlider, 0.6)
    table_insert(allWidgets, roleScaleSlider)
    card3:AddRow(row3d, 40)

    yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 4: Name Text Settings
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Name Text", yOffset)
    table_insert(allWidgets, card4)

    local fontList = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do fontList[name] = name end
    else
        fontList["Friz Quadrata TT"] = "Friz Quadrata TT"
    end

    local outlineList = {
        { key = "NONE", text = "None" },
        { key = "OUTLINE", text = "Outline" },
        { key = "THICKOUTLINE", text = "Thick" },
        { key = "SOFTOUTLINE", text = "Soft" },
    }

    -- Show Names toggle + Max Length
    local row4a = GUIFrame:CreateRow(card4.content, 40)
    local nameCheck = GUIFrame:CreateCheckbox(row4a, "Show Names", db.ShowNames ~= false,
        function(checked)
            db.ShowNames = checked
            ApplySettings()
        end)
    row4a:AddWidget(nameCheck, 0.4)
    table_insert(allWidgets, nameCheck)

    local maxLenSlider = GUIFrame:CreateSlider(row4a, "Max Characters", 0, 12, 1, db.NameMaxLength or 0, 50,
        function(val)
            db.NameMaxLength = val
            ApplySettings()
        end)
    row4a:AddWidget(maxLenSlider, 0.6)
    table_insert(allWidgets, maxLenSlider)
    card4:AddRow(row4a, 40)

    local row4b = GUIFrame:CreateRow(card4.content, 40)
    local nameFontDropdown = GUIFrame:CreateDropdown(row4b, "Font", fontList, db.NameFontFace or "Expressway", 30,
        function(key)
            db.NameFontFace = key
            ApplySettings()
        end)
    row4b:AddWidget(nameFontDropdown, 0.5)
    table_insert(allWidgets, nameFontDropdown)

    local nameFontSizeSlider = GUIFrame:CreateSlider(row4b, "Font Size", 8, 32, 1, db.NameFontSize or 12, 50,
        function(val)
            db.NameFontSize = val
            ApplySettings()
        end)
    row4b:AddWidget(nameFontSizeSlider, 0.5)
    table_insert(allWidgets, nameFontSizeSlider)
    card4:AddRow(row4b, 40)

    local row4c = GUIFrame:CreateRow(card4.content, 37)
    local nameOutlineDropdown = GUIFrame:CreateDropdown(row4c, "Outline", outlineList, db.NameFontOutline or "OUTLINE", 45,
        function(key)
            db.NameFontOutline = key
            ApplySettings()
        end)
    row4c:AddWidget(nameOutlineDropdown, 1)
    table_insert(allWidgets, nameOutlineDropdown)
    card4:AddRow(row4c, 37)

    yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 5: Timer Text Settings
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Timer Text", yOffset)
    table_insert(allWidgets, card5)

    local row5a = GUIFrame:CreateRow(card5.content, 40)
    local timerFontDropdown = GUIFrame:CreateDropdown(row5a, "Font", fontList, db.TimerFontFace or "Expressway", 30,
        function(key)
            db.TimerFontFace = key
            ApplySettings()
        end)
    row5a:AddWidget(timerFontDropdown, 0.5)
    table_insert(allWidgets, timerFontDropdown)

    local timerFontSizeSlider = GUIFrame:CreateSlider(row5a, "Font Size", 8, 32, 1, db.TimerFontSize or 14, 50,
        function(val)
            db.TimerFontSize = val
            ApplySettings()
        end)
    row5a:AddWidget(timerFontSizeSlider, 0.5)
    table_insert(allWidgets, timerFontSizeSlider)
    card5:AddRow(row5a, 40)

    local row5b = GUIFrame:CreateRow(card5.content, 37)
    local timerOutlineDropdown = GUIFrame:CreateDropdown(row5b, "Outline", outlineList, db.TimerFontOutline or "OUTLINE", 45,
        function(key)
            db.TimerFontOutline = key
            ApplySettings()
        end)
    row5b:AddWidget(timerOutlineDropdown, 1)
    table_insert(allWidgets, timerOutlineDropdown)
    card5:AddRow(row5b, 37)

    yOffset = yOffset + card5:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 6: Colors
    ----------------------------------------------------------------
    local card6 = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    table_insert(allWidgets, card6)

    -- Class Color Names toggle
    local row6a = GUIFrame:CreateRow(card6.content, 36)
    local nameColorWidget  -- forward declare for conditional enable
    local classColorCheck = GUIFrame:CreateCheckbox(row6a, "Class Color Names", db.ClassColorNames == true,
        function(checked)
            db.ClassColorNames = checked
            ApplySettings()
            if nameColorWidget and nameColorWidget.SetEnabled then
                nameColorWidget:SetEnabled(not checked)
            end
        end)
    row6a:AddWidget(classColorCheck, 1)
    table_insert(allWidgets, classColorCheck)
    card6:AddRow(row6a, 36)

    -- Color pickers
    local row6b = GUIFrame:CreateRow(card6.content, 40)
    local namePicker = GUIFrame:CreateColorPicker(row6b, "Name Color", db.NameColor or { 1, 1, 1, 1 },
        function(r, g, b, a2)
            db.NameColor = { r, g, b, a2 }
            ApplySettings()
        end)
    row6b:AddWidget(namePicker, 0.33)
    table_insert(allWidgets, namePicker)
    nameColorWidget = namePicker

    local timerPicker = GUIFrame:CreateColorPicker(row6b, "Timer Color", db.TimerColor or { 1, 1, 1, 1 },
        function(r, g, b, a2)
            db.TimerColor = { r, g, b, a2 }
            ApplySettings()
        end)
    row6b:AddWidget(timerPicker, 0.33)
    table_insert(allWidgets, timerPicker)

    local critPicker = GUIFrame:CreateColorPicker(row6b, "Crit Color", db.CritColor or { 1, 0, 1, 1 },
        function(r, g, b, a2)
            db.CritColor = { r, g, b, a2 }
            ApplySettings()
        end)
    row6b:AddWidget(critPicker, 0.34)
    table_insert(allWidgets, critPicker)
    card6:AddRow(row6b, 40)

    -- Disable Name Color picker when Class Color Names is on
    if db.ClassColorNames then
        if nameColorWidget and nameColorWidget.SetEnabled then
            nameColorWidget:SetEnabled(false)
        end
    end

    card6:AddLabel(accentDash .. " |cff888888Crit color applies to Prescience when it has a critical strike bonus.|r")

    yOffset = yOffset + card6:GetContentHeight() + Theme.paddingSmall

    UpdateAllWidgetStates()
    yOffset = yOffset - (Theme.paddingSmall * 3)
    return yOffset
end)
