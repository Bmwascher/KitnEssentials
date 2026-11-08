-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-Campfire.lua                                        ║
-- ║  GUI: Campfire                                           ║
-- ║  Purpose: Configuration panel for the Campfire module.   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local SHAPE_OPTIONS = {
    { key = "ROUND", text = "Round" },
    { key = "SIMPLE", text = "Simple" },
}

local SIDE_OPTIONS = {
    { key = "RIGHT", text = "Right" },
    { key = "LEFT", text = "Left" },
}

local function GetModule()
    return KitnEssentials and KitnEssentials:GetModule("Campfire", true)
end

GUIFrame:RegisterContent("Campfire", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.Campfire
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local manager = GUIFrame:CreateWidgetStateManager()

    manager:SetCondition("grayOn", function() return db.ShowMissing end)
    manager:SetCondition("underOn", function() return not db.ShowAlways end)
    manager:SetCondition("alertOn", function() return db.AlertEnabled end)
    manager:SetCondition("round", function() return db.Shape == "ROUND" end)
    manager:SetCondition("simple", function() return db.Shape == "SIMPLE" end)
    manager:SetCondition("lapseOn", function() return db.LapseSoundEnabled end)
    manager:SetCondition("landOn", function() return db.LandSoundEnabled end)

    local function ApplySettings()
        local CF = GetModule()
        if CF and CF.ApplySettings then CF:ApplySettings() end
    end
    local function UpdateAllWidgetStates() manager:UpdateAll(db.Enabled ~= false) end

    local function Checkbox(row, label, key, group, width, gates)
        local check = GUIFrame:CreateCheckbox(row, label, {
            value = db[key] == true,
            callback = function(checked)
                db[key] = checked
                ApplySettings()
                if gates then UpdateAllWidgetStates() end
            end,
        })
        row:AddWidget(check, width)
        if group then manager:Register(check, group) end
        return check
    end

    local function Slider(row, label, key, min, max, step, group)
        local slider = GUIFrame:CreateSlider(row, label, {
            min = min, max = max, step = step,
            value = db[key],
            callback = function(val)
                db[key] = val
                ApplySettings()
            end,
        })
        row:AddWidget(slider, 0.5)
        if group then manager:Register(slider, group) end
        return slider
    end

    local function GridPick(label, key)
        return {
            label = label,
            config = {
                value = db[key] == true,
                callback = function(checked)
                    db[key] = checked
                    ApplySettings()
                end,
            },
        }
    end

    ----------------------------------------------------------------
    -- Card 1: Campfire
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Campfire", yOffset)
    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        if GetModule() then
            if checked then KitnEssentials:EnableModule("Campfire")
            else KitnEssentials:DisableModule("Campfire") end
        end
    end)
    card1:AddLabel("Shows, in the open world, what your camp buff is doing and whether a fire is worth stopping " ..
        "at. It stays hidden until the buff runs low, lights up at a fire, shows the time to landing while you " ..
        "sit, and offers your Sleeping Bag and camping kit. Nothing shows in a dungeon or raid.")
    yOffset = card1:GetNextOffset()

    -- A disabled module shows only this card: its switch and description.
    if db.Enabled == false then return yOffset end

    local shapeRow = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local shapeDropdown = GUIFrame:CreateDropdown(shapeRow, "Shape", {
        options = SHAPE_OPTIONS,
        value = db.Shape,
        callback = function(key)
            db.Shape = key
            ApplySettings()
            UpdateAllWidgetStates()
        end,
    })
    shapeRow:AddWidget(shapeDropdown, 0.5)
    local CF = GetModule()
    local previewDropdown = GUIFrame:CreateDropdown(shapeRow, "Preview", {
        options = CF and CF.PREVIEW_CHOICES or {},
        value = CF and CF.previewChoice or "Low",
        callback = function(key)
            local module = GetModule()
            if module then module:SetPreviewChoice(key) end
        end,
    })
    shapeRow:AddWidget(previewDropdown, 0.5)
    card1:AddRow(shapeRow, Theme.rowHeightLast, 0)
    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Show In
    ----------------------------------------------------------------
    local showInCard = GUIFrame:CreateCard(scrollChild, "Show In", yOffset)
    showInCard:AddLabel("Gray fire shows")
    manager:RegisterGroup(showInCard:AddCheckboxGrid({
        GridPick("In Rest Areas", "GrayInRestAreas"),
        GridPick("While Mounted", "GrayWhileMounted"),
    }), "grayOn")
    showInCard:AddLabel("Timer shows")
    showInCard:AddCheckboxGrid({
        GridPick("In Rest Areas", "TimerInRestAreas"),
        GridPick("While Mounted", "TimerWhileMounted"),
        GridPick("In Combat", "TimerInCombat"),
    })
    showInCard:AddLabel("Bonus list shows")
    showInCard:AddCheckboxGrid({
        GridPick("In Combat", "ListInCombat"),
    }, { isLast = true })
    yOffset = showInCard:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Reminder
    ----------------------------------------------------------------
    local reminderCard = GUIFrame:CreateCard(scrollChild, "Reminder", yOffset)

    local rowShow = GUIFrame:CreateRow(reminderCard.content, Theme.rowHeight)
    Checkbox(rowShow, "Show While Buff Is Up", "ShowAlways", nil, 0.5, true)
    Slider(rowShow, "Show Under (Minutes)", "ShowUnderMinutes", 1, 30, 1, "underOn")
    reminderCard:AddRow(rowShow, Theme.rowHeight)

    local rowGray = GUIFrame:CreateRow(reminderCard.content, Theme.rowHeight)
    Checkbox(rowGray, "Show Gray Fire", "ShowMissing", nil, 0.5, true)
    Checkbox(rowGray, "Click to Sit", "ClickToSit", nil, 0.5)
    reminderCard:AddRow(rowGray, Theme.rowHeight)

    local rowDim = GUIFrame:CreateRow(reminderCard.content, Theme.rowHeightLast)
    Checkbox(rowDim, "Dim Covered Bonuses", "DimCovered", nil, 0.5)
    reminderCard:AddRow(rowDim, Theme.rowHeightLast, 0)
    yOffset = reminderCard:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Camp Nearby
    ----------------------------------------------------------------
    local nearbyCard = GUIFrame:CreateCard(scrollChild, "Camp Nearby", yOffset)
    local rowAlert = GUIFrame:CreateRow(nearbyCard.content, Theme.rowHeightLast)
    Checkbox(rowAlert, "Show Alert", "AlertEnabled", nil, 0.5, true)
    Slider(rowAlert, "Alert Under (Minutes)", "AlertUnderMinutes", 1, 60, 1, "alertOn")
    nearbyCard:AddRow(rowAlert, Theme.rowHeightLast, 0)
    yOffset = nearbyCard:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: At the Fire
    ----------------------------------------------------------------
    local fireCard = GUIFrame:CreateCard(scrollChild, "At the Fire", yOffset)
    local rowChecks = GUIFrame:CreateRow(fireCard.content, Theme.rowHeight)
    Checkbox(rowChecks, "Checklist", "Checklist", nil, 0.5)
    Checkbox(rowChecks, "Sleeping Bag Button", "BagButton", nil, 0.5)
    fireCard:AddRow(rowChecks, Theme.rowHeight)
    local rowKit = GUIFrame:CreateRow(fireCard.content, Theme.rowHeightLast)
    Checkbox(rowKit, "Kit Button", "KitButton", "grayOn", 0.5)
    fireCard:AddRow(rowKit, Theme.rowHeightLast, 0)
    yOffset = fireCard:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 6: Display Settings
    ----------------------------------------------------------------
    local displayCard = GUIFrame:CreateCard(scrollChild, "Display Settings", yOffset)

    local rowRound = GUIFrame:CreateRow(displayCard.content, Theme.rowHeight)
    Slider(rowRound, "Round Size", "RoundSize", 24, 110, 1, "round")
    local sideDropdown = GUIFrame:CreateDropdown(rowRound, "Bonus List Side", {
        options = SIDE_OPTIONS,
        value = db.ListSide,
        callback = function(key)
            db.ListSide = key
            ApplySettings()
        end,
    })
    rowRound:AddWidget(sideDropdown, 0.5)
    manager:Register(sideDropdown, "round")
    displayCard:AddRow(rowRound, Theme.rowHeight)

    local rowSimple = GUIFrame:CreateRow(displayCard.content, Theme.rowHeight)
    Slider(rowSimple, "Simple Width", "SimpleWidth", 200, 480, 5, "simple")
    Slider(rowSimple, "Simple Height", "SimpleHeight", 20, 36, 1, "simple")
    displayCard:AddRow(rowSimple, Theme.rowHeight)

    local rowText = GUIFrame:CreateRow(displayCard.content, Theme.rowHeightLast)
    Slider(rowText, "Simple Text Size", "SimpleTextSize", 11, 16, 1, "simple")
    Slider(rowText, "Alert Text Size", "AlertTextSize", 12, 28, 1, "alertOn")
    displayCard:AddRow(rowText, Theme.rowHeightLast, 0)
    yOffset = displayCard:GetNextOffset()

    ----------------------------------------------------------------
    -- Cards 7 to 9: Positions, UIParent only so the secure buttons
    -- can compute their coordinates
    ----------------------------------------------------------------
    local roundCard, roundOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Round Position",
        db = db,
        positionKey = "RoundPosition",
        showAnchorFrameType = false,
        showStrata = true,
        onChangeCallback = ApplySettings,
    })
    if roundCard.positionWidgets then manager:RegisterGroup(roundCard.positionWidgets, "round") end
    manager:Register(roundCard, "round")
    yOffset = roundOffset

    local simpleCard, simpleOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Simple Position",
        db = db,
        positionKey = "SimplePosition",
        showAnchorFrameType = false,
        showStrata = true,
        onChangeCallback = ApplySettings,
    })
    if simpleCard.positionWidgets then manager:RegisterGroup(simpleCard.positionWidgets, "simple") end
    manager:Register(simpleCard, "simple")
    yOffset = simpleOffset

    local alertCard, alertOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Alert Position",
        db = db,
        positionKey = "AlertPosition",
        showAnchorFrameType = false,
        showStrata = true,
        onChangeCallback = ApplySettings,
    })
    if alertCard.positionWidgets then manager:RegisterGroup(alertCard.positionWidgets, "alertOn") end
    manager:Register(alertCard, "alertOn")
    yOffset = alertOffset

    ----------------------------------------------------------------
    -- Card 10: Font Settings
    ----------------------------------------------------------------
    local _, fontOffset = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        title = "Font Settings",
        db = db,
        dbKeys = {
            fontFace = "FontFace",
            fontSize = "ListTextSize",
            fontOutline = "FontOutline",
        },
        fontSizeRange = { 8, 24 },
        onChangeCallback = ApplySettings,
    })
    yOffset = fontOffset

    ----------------------------------------------------------------
    -- Card 11: Sound
    ----------------------------------------------------------------
    local soundCard = GUIFrame:CreateCard(scrollChild, "Sound", yOffset)

    local function SoundRow(label, enabledKey, soundKey, group, height, spacing)
        local row = GUIFrame:CreateRow(soundCard.content, height)
        Checkbox(row, label, enabledKey, nil, 0.5, true)
        local picker = GUIFrame:CreateDropdown(row, "Sound", {
            options = GUIFrame.BuildSoundOptions(),
            searchable = true,
            value = db[soundKey] or "None",
            callback = function(key) db[soundKey] = key end,
        })
        row:AddWidget(picker, 0.5)
        manager:Register(picker, group)
        soundCard:AddRow(row, height, spacing)
    end

    SoundRow("Sound on Lapse", "LapseSoundEnabled", "LapseSound", "lapseOn", Theme.rowHeight)
    SoundRow("Sound on Landing", "LandSoundEnabled", "LandSound", "landOn", Theme.rowHeightLast, 0)
    yOffset = soundCard:GetNextOffset()

    UpdateAllWidgetStates()
    return yOffset
end)
