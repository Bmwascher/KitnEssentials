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

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("BloodlustTracker", true)
    end
    return nil
end

GUIFrame:RegisterContent("BloodlustTracker", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.BloodlustTracker
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local BLT = GetModule()
    local manager = GUIFrame:CreateWidgetStateManager()
    manager:SetCondition("pedro", function() return db.Mode == "pedro" end)
    manager:SetCondition("icon",  function() return db.Mode ~= "pedro" end)

    local function ApplySettings()
        if BLT and BLT.ApplySettings then BLT:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not BLT then return end
        BLT.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("BloodlustTracker")
        else
            KitnEssentials:DisableModule("BloodlustTracker")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable + Mode + Filters
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Bloodlust Tracker", yOffset)

    local row1a = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1a, "Enable Bloodlust Tracker", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Bloodlust Tracker",
        msgOn = "On",
        msgOff = "Off",
    })
    row1a:AddWidget(enableCheck, 1)
    card1:AddRow(row1a, Theme.rowHeight)

    local noteRow = GUIFrame:CreateRow(card1.content, 50)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Animated overlay or icon alert on Bloodlust, Heroism, and Time Warp.\n" ..
        KE:ColorTextByTheme("-") .. " Detected via sated debuffs.",
        50, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, 50)

    local row1b = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local modeDropdown = GUIFrame:CreateDropdown(row1b, "Mode", {
        options = {
            { key = "pedro", text = "Pedro Animated" },
            { key = "icon",  text = "Static Icon + Countdown" },
        },
        value = db.Mode or "pedro",
        callback = function(key)
            db.Mode = key
            ApplySettings()
            RefreshStates()
        end,
    })
    row1b:AddWidget(modeDropdown, 0.5)
    manager:Register(modeDropdown, "all")

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
    manager:Register(testBtn, "all")
    card1:AddRow(row1b, Theme.rowHeight)

    local rowSep = GUIFrame:CreateRow(card1.content, Theme.rowHeightSeparator)
    local sep1 = GUIFrame:CreateSeparator(rowSep)
    rowSep:AddWidget(sep1, 1)
    manager:Register(sep1, "all")
    card1:AddRow(rowSep, Theme.rowHeightSeparator)

    local row1c = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local instanceCheck = GUIFrame:CreateCheckbox(row1c, "Instance Only", {
        value = db.InstanceOnly == true,
        callback = function(checked) db.InstanceOnly = checked end,
    })
    row1c:AddWidget(instanceCheck, 0.5)
    manager:Register(instanceCheck, "all")

    local combatCheck = GUIFrame:CreateCheckbox(row1c, "Combat Only", {
        value = db.CombatOnly == true,
        callback = function(checked) db.CombatOnly = checked end,
    })
    row1c:AddWidget(combatCheck, 0.5)
    manager:Register(combatCheck, "all")
    card1:AddRow(row1c, Theme.rowHeightLast, 0)

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
        showAnchorFrameType = true,
        showStrata = true,
        onChangeCallback = ApplySettings,
    })

    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "all")
    end
    manager:Register(posCard, "all")
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 3: Pedro Overlay Settings
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Pedro Overlay Settings", yOffset)
    manager:Register(card3, "pedro")

    local row3a = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local scaleSlider = GUIFrame:CreateSlider(row3a, "Overlay Scale", {
        min = 0.25, max = 3.0, step = 0.05,
        value = db.Scale or 0.5,
        callback = function(val) db.Scale = val; ApplySettings() end,
    })
    row3a:AddWidget(scaleSlider, 1)
    manager:Register(scaleSlider, "pedro")
    card3:AddRow(row3a, Theme.rowHeight)

    local row3b = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local soundCheck = GUIFrame:CreateCheckbox(row3b, "Enable Sound", {
        value = db.SoundEnabled ~= false,
        callback = function(checked) db.SoundEnabled = checked end,
    })
    row3b:AddWidget(soundCheck, 0.5)
    manager:Register(soundCheck, "pedro")

    local channelDropdown = GUIFrame:CreateDropdown(row3b, "Sound Channel", {
        options = {
            { key = "Master", text = "Master" },
            { key = "SFX", text = "SFX" },
            { key = "Music", text = "Music" },
            { key = "Ambience", text = "Ambience" },
            { key = "Dialog", text = "Dialog" },
        },
        value = db.SoundChannel or "Master",
        callback = function(key) db.SoundChannel = key end,
    })
    row3b:AddWidget(channelDropdown, 0.5)
    manager:Register(channelDropdown, "pedro")
    card3:AddRow(row3b, Theme.rowHeightLast, 0)

    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Icon Mode — Font Settings
    ----------------------------------------------------------------
    local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        title = "Icon Mode — Font",
        db = db,
        dbKeys = {
            fontFace = "FontFace",
            fontSize = "FontSize",
            fontOutline = "FontOutline",
        },
        includeSoftOutline = true,
        onChangeCallback = ApplySettings,
    })
    manager:Register(fontCard, "icon")
    if fontWidgets then
        manager:RegisterGroup(fontWidgets, "icon")
    end
    yOffset = fontOffset

    ----------------------------------------------------------------
    -- Card 5: Icon Mode — Display
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Icon Mode — Display", yOffset)
    manager:Register(card5, "icon")

    local row5a = GUIFrame:CreateRow(card5.content, Theme.rowHeight)
    local iconSizeSlider = GUIFrame:CreateSlider(row5a, "Icon Size", {
        min = 16, max = 128, step = 1,
        value = db.BasicIconSize or 48,
        callback = function(val) db.BasicIconSize = val; ApplySettings() end,
    })
    row5a:AddWidget(iconSizeSlider, 1)
    manager:Register(iconSizeSlider, "icon")
    card5:AddRow(row5a, Theme.rowHeight)

    local row5b = GUIFrame:CreateRow(card5.content, Theme.rowHeightLast)
    local colorPicker = GUIFrame:CreateColorPicker(row5b, "Countdown Text Color", {
        color = db.CountdownColor or { 1, 1, 1, 1 },
        callback = function(r, g, b, a)
            db.CountdownColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row5b:AddWidget(colorPicker, 1)
    manager:Register(colorPicker, "icon")
    card5:AddRow(row5b, Theme.rowHeightLast, 0)

    yOffset = card5:GetNextOffset()

    RefreshStates()
    return yOffset
end)
