-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)
local table_insert = table.insert

GUIFrame:RegisterContent("BloodlustTracker", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.BloodlustTracker
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return yOffset + errorCard:GetContentHeight() + Theme.paddingMedium
    end

    local BLT = KitnEssentials and KitnEssentials:GetModule("BloodlustTracker", true)
    local allWidgets = {}
    local animatedOnlyWidgets = {}
    local basicOnlyWidgets = {}

    local function ApplySettings()
        if BLT and BLT.ApplySettings then BLT:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not KitnEssentials then return end
        local mod = KitnEssentials:GetModule("BloodlustTracker", true)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("BloodlustTracker")
        else
            KitnEssentials:DisableModule("BloodlustTracker")
        end
    end

    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false
        local isAnimated = db.DisplayMode == "animated"

        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then widget:SetEnabled(mainEnabled) end
        end
        for _, widget in ipairs(animatedOnlyWidgets) do
            if widget.SetEnabled then widget:SetEnabled(mainEnabled and isAnimated) end
        end
        for _, widget in ipairs(basicOnlyWidgets) do
            if widget.SetEnabled then widget:SetEnabled(mainEnabled and not isAnimated) end
        end
    end

    ----------------------------------------------------------------
    -- Card 1: Bloodlust Tracker (Enable + Display + Preset + Scale + Test)
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Bloodlust Tracker", yOffset)

    -- Enable toggle
    local row1a = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1a, "Enable Bloodlust Tracker", db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            UpdateAllWidgetStates()
        end,
        true, "Bloodlust Tracker", "On", "Off"
    )
    row1a:AddWidget(enableCheck, 1)
    card1:AddRow(row1a, 36)

    card1:AddLabel("|cff888888Animated overlay or icon alert on Bloodlust, Heroism, and Time Warp. Detected via sated debuffs.|r")

    -- Display Mode + Preset side by side
    local row1b = GUIFrame:CreateRow(card1.content, 40)
    local displayModeList = {
        { key = "animated", text = "Animated Overlay" },
        { key = "basic", text = "Basic Icon + Countdown" },
    }
    local displayDropdown = GUIFrame:CreateDropdown(row1b, "Display Mode", displayModeList, db.DisplayMode or "animated", 30,
        function(key)
            db.DisplayMode = key
            ApplySettings()
            UpdateAllWidgetStates()
        end)
    row1b:AddWidget(displayDropdown, 0.5)
    table_insert(allWidgets, displayDropdown)

    local presetList = {}
    if BLT and BLT.PRESET_ORDER then
        for _, presetId in ipairs(BLT.PRESET_ORDER) do
            local preset = BLT.PRESETS[presetId]
            if preset then
                table_insert(presetList, { key = presetId, text = preset.label })
            end
        end
    end
    local presetDropdown = GUIFrame:CreateDropdown(row1b, "Preset", presetList, db.Preset or "pedro", 30,
        function(key)
            db.Preset = key
            ApplySettings()
        end)
    row1b:AddWidget(presetDropdown, 0.5)
    table_insert(allWidgets, presetDropdown)
    table_insert(animatedOnlyWidgets, presetDropdown)
    card1:AddRow(row1b, 40)

    -- Overlay Scale + Test button side by side
    local row1c = GUIFrame:CreateRow(card1.content, 40)
    local scaleSlider = GUIFrame:CreateSlider(row1c, "Overlay Scale", 0.25, 3.0, 0.05, db.Scale or 0.5, 60,
        function(val)
            db.Scale = val
            ApplySettings()
        end)
    row1c:AddWidget(scaleSlider, 0.5)
    table_insert(allWidgets, scaleSlider)
    table_insert(animatedOnlyWidgets, scaleSlider)

    local testBtn = GUIFrame:CreateButton(row1c, "Test", {
        callback = function()
            if BLT then
                if not BLT.frame then BLT:CreateFrames() end
                BLT:ToggleTestMode()
            end
        end,
        width = 80,
    })
    row1c:AddWidget(testBtn, 0.5)
    table_insert(allWidgets, testBtn)
    table_insert(animatedOnlyWidgets, testBtn)
    card1:AddRow(row1c, 40)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 2: Position Settings
    ----------------------------------------------------------------
    local card2, newOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
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
    yOffset = newOffset

    ----------------------------------------------------------------
    -- Card 3: Sound Settings
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Sound Settings", yOffset)
    table_insert(allWidgets, card3)
    table_insert(animatedOnlyWidgets, card3)

    local row3a = GUIFrame:CreateRow(card3.content, 36)
    local soundCheck = GUIFrame:CreateCheckbox(row3a, "Enable Sound", db.SoundEnabled ~= false,
        function(checked)
            db.SoundEnabled = checked
        end)
    row3a:AddWidget(soundCheck, 0.5)
    table_insert(allWidgets, soundCheck)
    table_insert(animatedOnlyWidgets, soundCheck)

    local channelList = {
        { key = "Master", text = "Master" },
        { key = "SFX", text = "SFX" },
        { key = "Music", text = "Music" },
        { key = "Ambience", text = "Ambience" },
        { key = "Dialog", text = "Dialog" },
    }
    local channelDropdown = GUIFrame:CreateDropdown(row3a, "Sound Channel", channelList, db.SoundChannel or "Master", 30,
        function(key)
            db.SoundChannel = key
        end)
    row3a:AddWidget(channelDropdown, 0.5)
    table_insert(allWidgets, channelDropdown)
    table_insert(animatedOnlyWidgets, channelDropdown)
    card3:AddRow(row3a, 36)

    yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 4: Basic Mode Settings (Font + Icon Size + Colors)
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Basic Mode Settings", yOffset)
    table_insert(allWidgets, card4)
    table_insert(basicOnlyWidgets, card4)

    local fontList = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do fontList[name] = name end
    else
        fontList["Friz Quadrata TT"] = "Friz Quadrata TT"
    end

    -- Font Face + Font Size
    local row4a = GUIFrame:CreateRow(card4.content, 40)
    local fontDropdown = GUIFrame:CreateDropdown(row4a, "Font", fontList, db.FontFace or "Expressway", 30,
        function(key)
            db.FontFace = key
            ApplySettings()
        end)
    row4a:AddWidget(fontDropdown, 0.5)
    table_insert(allWidgets, fontDropdown)
    table_insert(basicOnlyWidgets, fontDropdown)

    local fontSizeSlider = GUIFrame:CreateSlider(row4a, "Font Size", 8, 72, 1, db.FontSize or 22, 60,
        function(val)
            db.FontSize = val
            ApplySettings()
        end)
    row4a:AddWidget(fontSizeSlider, 0.5)
    table_insert(allWidgets, fontSizeSlider)
    table_insert(basicOnlyWidgets, fontSizeSlider)
    card4:AddRow(row4a, 40)

    -- Font Outline + Icon Size
    local row4b = GUIFrame:CreateRow(card4.content, 40)
    local outlineList = {
        { key = "NONE", text = "None" },
        { key = "OUTLINE", text = "Outline" },
        { key = "THICKOUTLINE", text = "Thick" },
        { key = "SOFTOUTLINE", text = "Soft" },
    }
    local outlineDropdown = GUIFrame:CreateDropdown(row4b, "Outline", outlineList, db.FontOutline or "SOFTOUTLINE", 45,
        function(key)
            db.FontOutline = key
            ApplySettings()
        end)
    row4b:AddWidget(outlineDropdown, 0.5)
    table_insert(allWidgets, outlineDropdown)
    table_insert(basicOnlyWidgets, outlineDropdown)

    local iconSizeSlider = GUIFrame:CreateSlider(row4b, "Icon Size", 16, 128, 1, db.BasicIconSize or 48, 60,
        function(val)
            db.BasicIconSize = val
            ApplySettings()
        end)
    row4b:AddWidget(iconSizeSlider, 0.5)
    table_insert(allWidgets, iconSizeSlider)
    table_insert(basicOnlyWidgets, iconSizeSlider)
    card4:AddRow(row4b, 40)

    -- Countdown Color
    local row4c = GUIFrame:CreateRow(card4.content, 40)
    local colorPicker = GUIFrame:CreateColorPicker(row4c, "Countdown Text Color", db.CountdownColor or { 1, 1, 1, 1 },
        function(r, g, b, a)
            db.CountdownColor = { r, g, b, a }
            ApplySettings()
        end)
    row4c:AddWidget(colorPicker, 1)
    table_insert(allWidgets, colorPicker)
    table_insert(basicOnlyWidgets, colorPicker)
    card4:AddRow(row4c, 40)

    yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 5: Detection Settings
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Detection Settings", yOffset)
    table_insert(allWidgets, card5)

    card5:AddLabel("|cff888888" .. KE:ColorTextByTheme("-") .. " Haste fallback uses spell haste polling when debuff detection is unreliable.\n" .. KE:ColorTextByTheme("-") .. " Instance Only restricts detection to dungeons and raids.|r")

    local row5a = GUIFrame:CreateRow(card5.content, 36)
    local hasteCheck = GUIFrame:CreateCheckbox(row5a, "Haste Approximation Fallback", db.HasteApproxEnabled == true,
        function(checked)
            db.HasteApproxEnabled = checked
            if BLT then BLT:ReschedulePollTimer() end
        end)
    row5a:AddWidget(hasteCheck, 0.5)
    table_insert(allWidgets, hasteCheck)

    local instanceCheck = GUIFrame:CreateCheckbox(row5a, "Instance Only", db.InstanceOnly == true,
        function(checked)
            db.InstanceOnly = checked
        end)
    row5a:AddWidget(instanceCheck, 0.5)
    table_insert(allWidgets, instanceCheck)
    card5:AddRow(row5a, 36)

    yOffset = yOffset + card5:GetContentHeight() + Theme.paddingSmall

    -- Apply initial widget states
    UpdateAllWidgetStates()
    yOffset = yOffset - (Theme.paddingSmall * 3)
    return yOffset
end)
