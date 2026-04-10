-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-BloodlustTracker.lua                                ║
-- ║  GUI: Bloodlust Tracker                                  ║
-- ║  Purpose: Configuration panel for the BloodlustTracker   ║
-- ║           module.                                        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)
local table_insert = table.insert
local ipairs = ipairs

GUIFrame:RegisterContent("BloodlustTracker", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.BloodlustTracker
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return yOffset + errorCard:GetContentHeight() + Theme.paddingMedium
    end

    local BLT = KitnEssentials and KitnEssentials:GetModule("BloodlustTracker", true)
    local allWidgets = {}
    local pedroOnlyWidgets = {}
    local iconOnlyWidgets = {}

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
        local isPedro = db.Mode == "pedro"

        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then widget:SetEnabled(mainEnabled) end
        end
        for _, widget in ipairs(pedroOnlyWidgets) do
            if widget.SetEnabled then widget:SetEnabled(mainEnabled and isPedro) end
        end
        for _, widget in ipairs(iconOnlyWidgets) do
            if widget.SetEnabled then widget:SetEnabled(mainEnabled and not isPedro) end
        end
    end

    ---------------------------------------------------------------------------------
    -- Card 1: Bloodlust Tracker
    ---------------------------------------------------------------------------------
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

    -- Mode + Test button
    local row1b = GUIFrame:CreateRow(card1.content, 40)
    local modeList = {
        { key = "pedro", text = "Pedro Animated" },
        { key = "icon", text = "Static Icon + Countdown" },
    }
    local modeDropdown = GUIFrame:CreateDropdown(row1b, "Mode", modeList, db.Mode or "pedro", 30,
        function(key)
            db.Mode = key
            ApplySettings()
            UpdateAllWidgetStates()
        end)
    row1b:AddWidget(modeDropdown, 0.5)
    table_insert(allWidgets, modeDropdown)

    local testBtn = GUIFrame:CreateButton(row1b, "Test", {
        callback = function()
            if BLT then
                if not BLT.frame then BLT:CreateFrames() end
                BLT:ToggleTestMode()
            end
        end,
        width = 80,
    })
    row1b:AddWidget(testBtn, 0.5)
    table_insert(allWidgets, testBtn)
    card1:AddRow(row1b, 40)

    -- Separator
    local row1sep = GUIFrame:CreateRow(card1.content, 8)
    local sep1 = GUIFrame:CreateSeparator(row1sep)
    row1sep:AddWidget(sep1, 1)
    card1:AddRow(row1sep, 8)

    -- Instance Only + Combat Only
    local row1c = GUIFrame:CreateRow(card1.content, 36)
    local instanceCheck = GUIFrame:CreateCheckbox(row1c, "Instance Only", db.InstanceOnly == true,
        function(checked)
            db.InstanceOnly = checked
        end)
    row1c:AddWidget(instanceCheck, 0.5)
    table_insert(allWidgets, instanceCheck)

    local combatCheck = GUIFrame:CreateCheckbox(row1c, "Combat Only", db.CombatOnly == true,
        function(checked)
            db.CombatOnly = checked
        end)
    row1c:AddWidget(combatCheck, 0.5)
    table_insert(allWidgets, combatCheck)
    card1:AddRow(row1c, 36)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 2: Position Settings
    ---------------------------------------------------------------------------------
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

    ---------------------------------------------------------------------------------
    -- Card 3: Pedro Overlay Settings
    ---------------------------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Pedro Overlay Settings", yOffset)
    table_insert(allWidgets, card3)
    table_insert(pedroOnlyWidgets, card3)

    -- Overlay Scale
    local row3a = GUIFrame:CreateRow(card3.content, 40)
    local scaleSlider = GUIFrame:CreateSlider(row3a, "Overlay Scale", 0.25, 3.0, 0.05, db.Scale or 0.5, 60,
        function(val)
            db.Scale = val
            ApplySettings()
        end)
    row3a:AddWidget(scaleSlider, 1)
    table_insert(allWidgets, scaleSlider)
    table_insert(pedroOnlyWidgets, scaleSlider)
    card3:AddRow(row3a, 40)

    -- Sound Enable + Channel
    local row3b = GUIFrame:CreateRow(card3.content, 36)
    local soundCheck = GUIFrame:CreateCheckbox(row3b, "Enable Sound", db.SoundEnabled ~= false,
        function(checked)
            db.SoundEnabled = checked
        end)
    row3b:AddWidget(soundCheck, 0.5)
    table_insert(allWidgets, soundCheck)
    table_insert(pedroOnlyWidgets, soundCheck)

    local channelList = {
        { key = "Master", text = "Master" },
        { key = "SFX", text = "SFX" },
        { key = "Music", text = "Music" },
        { key = "Ambience", text = "Ambience" },
        { key = "Dialog", text = "Dialog" },
    }
    local channelDropdown = GUIFrame:CreateDropdown(row3b, "Sound Channel", channelList, db.SoundChannel or "Master", 30,
        function(key)
            db.SoundChannel = key
        end)
    row3b:AddWidget(channelDropdown, 0.5)
    table_insert(allWidgets, channelDropdown)
    table_insert(pedroOnlyWidgets, channelDropdown)
    card3:AddRow(row3b, 36)

    yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 4: Icon Mode Settings
    ---------------------------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Icon Mode Settings", yOffset)
    table_insert(allWidgets, card4)
    table_insert(iconOnlyWidgets, card4)

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
    table_insert(iconOnlyWidgets, fontDropdown)

    local fontSizeSlider = GUIFrame:CreateSlider(row4a, "Font Size", 8, 72, 1, db.FontSize or 22, 60,
        function(val)
            db.FontSize = val
            ApplySettings()
        end)
    row4a:AddWidget(fontSizeSlider, 0.5)
    table_insert(allWidgets, fontSizeSlider)
    table_insert(iconOnlyWidgets, fontSizeSlider)
    card4:AddRow(row4a, 40)

    -- Outline + Icon Size
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
    table_insert(iconOnlyWidgets, outlineDropdown)

    local iconSizeSlider = GUIFrame:CreateSlider(row4b, "Icon Size", 16, 128, 1, db.BasicIconSize or 48, 60,
        function(val)
            db.BasicIconSize = val
            ApplySettings()
        end)
    row4b:AddWidget(iconSizeSlider, 0.5)
    table_insert(allWidgets, iconSizeSlider)
    table_insert(iconOnlyWidgets, iconSizeSlider)
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
    table_insert(iconOnlyWidgets, colorPicker)
    card4:AddRow(row4c, 40)

    yOffset = yOffset + card4:GetContentHeight() + Theme.paddingSmall

    -- Apply initial widget states
    UpdateAllWidgetStates()
    yOffset = yOffset - (Theme.paddingSmall * 3)
    return yOffset
end)
