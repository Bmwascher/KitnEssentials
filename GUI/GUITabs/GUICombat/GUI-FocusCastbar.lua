-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-FocusCastbar.lua                                    ║
-- ║  GUI: Focus Castbar                                      ║
-- ║  Purpose: Configuration panel for the FocusCastbar       ║
-- ║  module.                                                 ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)

local pairs = pairs

local function GetModule()
    return KitnEssentials:GetModule("FocusCastbar", true)
end

GUIFrame:RegisterContent("FocusCastbar", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.FocusCastbar
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    if not db.TargetNames then
        db.TargetNames = {
            Enabled = true,
            Anchor = "RIGHT",
            XOffset = 0,
            YOffset = 14,
            FontSize = 12,
        }
    end
    if not db.HoldTimer then
        db.HoldTimer = {
            Enabled = true,
            Duration = 0.5,
            InterruptedColor = { 0.1, 0.8, 0.1, 1 },
            SuccessColor = { 0.8, 0.1, 0.1, 1 },
        }
    end
    if not db.TargetMarker then
        db.TargetMarker = {
            Enabled = true,
            Size = 26,
            XOffset = -30,
            YOffset = 0,
            Anchor = "LEFT",
        }
    end
    db.KickIndicator = db.KickIndicator or {}
    db.ImportantGlow = db.ImportantGlow or { Enabled = false, GlowType = "pixel", Color = { 1, 0.85, 0.1, 1 } }
    db.ImportantGlow.GlowType = db.ImportantGlow.GlowType or "pixel"

    local mod = GetModule()
    local manager = GUIFrame:CreateWidgetStateManager()
    manager:SetCondition("holdTimer", function()
        return db.HoldTimer and db.HoldTimer.Enabled ~= false
    end)
    manager:SetCondition("kickIndicator", function()
        return db.KickIndicator and db.KickIndicator.Enabled ~= false
    end)

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
            KitnEssentials:EnableModule("FocusCastbar")
        else
            KitnEssentials:DisableModule("FocusCastbar")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    local statusbarList = {}
    if LSM then
        for name in pairs(LSM:HashTable("statusbar")) do statusbarList[name] = name end
    else
        statusbarList["Blizzard"] = "Blizzard"
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Focus Castbar", yOffset)
    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        ApplyModuleState(checked)
        KE:Print("Focus Castbar: " .. (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
    end)

    yOffset = card1:GetNextOffset()

    -- Lone header bar: a disabled module shows its switch and nothing else.
    if db.Enabled == false then return yOffset end

    ----------------------------------------------------------------
    -- Card 2: General Settings (Width, Height, Bar Texture)
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "General Settings", yOffset)
    manager:Register(card2, "all")

    local row2a = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local widthSlider = GUIFrame:CreateSlider(row2a, "Width", {
        min = 100, max = 600, step = 1,
        value = db.Width or 200,
        callback = function(val) db.Width = val; ApplySettings() end,
    })
    row2a:AddWidget(widthSlider, 0.5)
    manager:Register(widthSlider, "all")

    local heightSlider = GUIFrame:CreateSlider(row2a, "Height", {
        min = 5, max = 60, step = 1,
        value = db.Height or 18,
        callback = function(val) db.Height = val; ApplySettings() end,
    })
    row2a:AddWidget(heightSlider, 0.5)
    manager:Register(heightSlider, "all")
    card2:AddRow(row2a, Theme.rowHeight)

    local row2b = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local statusbarDropdown = GUIFrame:CreateDropdown(row2b, "Bar Texture", {
        options = statusbarList,
        value = db.StatusBarTexture or "KitnUI",
        callback = function(key) db.StatusBarTexture = key; ApplySettings() end,
        searchable = true,
    })
    row2b:AddWidget(statusbarDropdown, 1)
    manager:Register(statusbarDropdown, "all")
    card2:AddRow(row2b, Theme.rowHeight)

    local row2c = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local hideNotInterruptCheck = GUIFrame:CreateCheckbox(row2c, "Hide Non-Interruptible Casts", {
        value = db.HideNotInterruptible == true,
        callback = function(checked) db.HideNotInterruptible = checked end,
        msgPopup = true,
        msgText = "Hide",
        msgOn = "On",
        msgOff = "Off",
    })
    row2c:AddWidget(hideNotInterruptCheck, 1)
    manager:Register(hideNotInterruptCheck, "all")
    card2:AddRow(row2c, Theme.rowHeightLast, 0)

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
        fontSizeRange = { 8, 24 },
        includeSoftOutline = true,
        onChangeCallback = ApplySettings,
    })
    manager:Register(fontCard, "all")
    if fontWidgets then
        manager:RegisterGroup(fontWidgets, "all")
    end
    yOffset = fontOffset

    ----------------------------------------------------------------
    -- Card 5: Target Names
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Target Names", yOffset)
    manager:Register(card5, "all")

    local rowTnEnable = GUIFrame:CreateRow(card5.content, Theme.rowHeight)
    local tnEnableCheck = GUIFrame:CreateCheckbox(rowTnEnable, "Show Target Names", {
        value = db.TargetNames.Enabled ~= false,
        callback = function(checked)
            db.TargetNames.Enabled = checked
            ApplySettings()
        end,
        msgPopup = true,
        msgText = "Target Names",
        msgOn = "On",
        msgOff = "Off",
    })
    rowTnEnable:AddWidget(tnEnableCheck, 1)
    manager:Register(tnEnableCheck, "all")
    card5:AddRow(rowTnEnable, Theme.rowHeight)

    local row5a = GUIFrame:CreateRow(card5.content, Theme.rowHeight)
    local anchorDropdown = GUIFrame:CreateDropdown(row5a, "Anchor", {
        options = {
            { key = "LEFT",   text = "Left" },
            { key = "CENTER", text = "Center" },
            { key = "RIGHT",  text = "Right" },
        },
        value = db.TargetNames.Anchor or "RIGHT",
        callback = function(key) db.TargetNames.Anchor = key; ApplySettings() end,
    })
    row5a:AddWidget(anchorDropdown, 0.5)
    manager:Register(anchorDropdown, "all")

    local targetFontSlider = GUIFrame:CreateSlider(row5a, "Font Size", {
        min = 6, max = 18, step = 1,
        value = db.TargetNames.FontSize or 12,
        callback = function(val) db.TargetNames.FontSize = val; ApplySettings() end,
    })
    row5a:AddWidget(targetFontSlider, 0.5)
    manager:Register(targetFontSlider, "all")
    card5:AddRow(row5a, Theme.rowHeight)

    local row5b = GUIFrame:CreateRow(card5.content, Theme.rowHeightLast)
    local targetXSlider = GUIFrame:CreateSlider(row5b, "X Offset", {
        min = -100, max = 100, step = 1,
        value = db.TargetNames.XOffset or 0,
        callback = function(val) db.TargetNames.XOffset = val; ApplySettings() end,
    })
    row5b:AddWidget(targetXSlider, 0.5)
    manager:Register(targetXSlider, "all")

    local targetYSlider = GUIFrame:CreateSlider(row5b, "Y Offset", {
        min = -50, max = 100, step = 1,
        value = db.TargetNames.YOffset or 14,
        callback = function(val) db.TargetNames.YOffset = val; ApplySettings() end,
    })
    row5b:AddWidget(targetYSlider, 0.5)
    manager:Register(targetYSlider, "all")
    card5:AddRow(row5b, Theme.rowHeightLast, 0)

    yOffset = card5:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 6: Raid Marker
    ----------------------------------------------------------------
    local cardMarker = GUIFrame:CreateCard(scrollChild, "Raid Marker", yOffset)
    manager:Register(cardMarker, "all")

    local rowMarkerEnable = GUIFrame:CreateRow(cardMarker.content, Theme.rowHeight)
    local markerEnableCheck = GUIFrame:CreateCheckbox(rowMarkerEnable, "Show Raid Marker", {
        value = db.TargetMarker.Enabled ~= false,
        callback = function(checked)
            db.TargetMarker.Enabled = checked
            if mod and mod.ToggleTargetMarkerIntegration then
                mod:ToggleTargetMarkerIntegration()
            end
        end,
        msgPopup = true,
        msgText = "Raid Marker",
        msgOn = "On",
        msgOff = "Off",
    })
    rowMarkerEnable:AddWidget(markerEnableCheck, 1)
    manager:Register(markerEnableCheck, "all")
    cardMarker:AddRow(rowMarkerEnable, Theme.rowHeight)

    local rowMarkerA = GUIFrame:CreateRow(cardMarker.content, Theme.rowHeight)
    local markerAnchorDropdown = GUIFrame:CreateDropdown(rowMarkerA, "Anchor", {
        options = {
            { key = "LEFT",   text = "Left" },
            { key = "CENTER", text = "Center" },
            { key = "RIGHT",  text = "Right" },
        },
        value = db.TargetMarker.Anchor or "LEFT",
        callback = function(key) db.TargetMarker.Anchor = key; ApplySettings() end,
    })
    rowMarkerA:AddWidget(markerAnchorDropdown, 0.5)
    manager:Register(markerAnchorDropdown, "all")

    local markerSizeSlider = GUIFrame:CreateSlider(rowMarkerA, "Size", {
        min = 1, max = 100, step = 1,
        value = db.TargetMarker.Size or 26,
        callback = function(val) db.TargetMarker.Size = val; ApplySettings() end,
    })
    rowMarkerA:AddWidget(markerSizeSlider, 0.5)
    manager:Register(markerSizeSlider, "all")
    cardMarker:AddRow(rowMarkerA, Theme.rowHeight)

    local rowMarkerB = GUIFrame:CreateRow(cardMarker.content, Theme.rowHeightLast)
    local markerXSlider = GUIFrame:CreateSlider(rowMarkerB, "X Offset", {
        min = -100, max = 100, step = 1,
        value = db.TargetMarker.XOffset or -30,
        callback = function(val) db.TargetMarker.XOffset = val; ApplySettings() end,
    })
    rowMarkerB:AddWidget(markerXSlider, 0.5)
    manager:Register(markerXSlider, "all")

    local markerYSlider = GUIFrame:CreateSlider(rowMarkerB, "Y Offset", {
        min = -50, max = 100, step = 1,
        value = db.TargetMarker.YOffset or 0,
        callback = function(val) db.TargetMarker.YOffset = val; ApplySettings() end,
    })
    rowMarkerB:AddWidget(markerYSlider, 0.5)
    manager:Register(markerYSlider, "all")
    cardMarker:AddRow(rowMarkerB, Theme.rowHeightLast, 0)

    yOffset = cardMarker:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 7: Colors
    ----------------------------------------------------------------
    yOffset = GUIFrame:CreateColorsCard(scrollChild, yOffset, {
        db         = db,
        manager    = manager,
        onChange   = ApplySettings,
        stateGroup = "all",
        isLast     = true,
        colors     = {
            { label = "Casting", key = "CastingColor", default = { 1, 0.7, 0, 1 } },
            { label = "Channeling", key = "ChannelingColor", default = { 0, 0.7, 1, 1 } },
            { label = "Empowering", key = "EmpoweringColor", default = { 0.8, 0.4, 1, 1 } },
            { label = "Not Interruptible", key = "NotInterruptibleColor", default = { 0.7, 0.7, 0.7, 1 } },
            { label = "Text", key = "TextColor", default = { 1, 1, 1, 1 } },
            { label = "Background", key = "BackdropColor", default = { 0, 0, 0, 0.8 } },
            { label = "Border", key = "BorderColor", default = { 0, 0, 0, 1 } },
        },
    })

    ----------------------------------------------------------------
    -- Card 7.5: Range & Visibility
    ----------------------------------------------------------------
    local cardRange = GUIFrame:CreateCard(scrollChild, "Range & Visibility", yOffset)
    manager:Register(cardRange, "all")

    local rangeRow1 = GUIFrame:CreateRow(cardRange.content, Theme.rowHeight)
    local ignoreFriendlyCheck = GUIFrame:CreateCheckbox(rangeRow1, "Ignore Friendly Focus", {
        value = db.IgnoreFriendlies == true,
        callback = function(checked) db.IgnoreFriendlies = checked; ApplySettings() end,
        msgPopup = true,
        msgText = "Ignore Friendly",
        msgOn = "On",
        msgOff = "Off",
    })
    rangeRow1:AddWidget(ignoreFriendlyCheck, 0.5)
    manager:Register(ignoreFriendlyCheck, "all")

    local opacitySlider = GUIFrame:CreateSlider(rangeRow1, "Out-of-Range Opacity", {
        min = 0.1, max = 1, step = 0.05,
        value = db.OutOfRangeOpacity or 1,
        callback = function(val) db.OutOfRangeOpacity = val; ApplySettings() end,
    })
    rangeRow1:AddWidget(opacitySlider, 0.5)
    manager:Register(opacitySlider, "all")
    cardRange:AddRow(rangeRow1, Theme.rowHeight)

    local rangeNoteRow = GUIFrame:CreateRow(cardRange.content, Theme.rowHeightNote)
    local rangeNote = GUIFrame:CreateText(rangeNoteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Out-of-Range dims the bar when your interrupt can't reach the focus (1 = off).\n" ..
        KE:ColorTextByTheme("-") .. " Ignore Friendly hides the bar for a focus you can't attack.",
        50, "hide")
    rangeNoteRow:AddWidget(rangeNote, 1)
    manager:Register(rangeNote, "all")
    cardRange:AddRow(rangeNoteRow, Theme.rowHeightNote, 0)

    yOffset = cardRange:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 7.6: Important Cast Glow
    ----------------------------------------------------------------
    local cardGlow = GUIFrame:CreateCard(scrollChild, "Important Cast Glow", yOffset)
    manager:Register(cardGlow, "all")

    -- Row 1: Enable + Glow Type
    local glowRow1 = GUIFrame:CreateRow(cardGlow.content, Theme.rowHeight)
    local glowCheck = GUIFrame:CreateCheckbox(glowRow1, "Important Spell Glow", {
        value = db.ImportantGlow.Enabled == true,
        callback = function(checked) db.ImportantGlow.Enabled = checked; ApplySettings() end,
        msgPopup = true,
        msgText = "Important Glow",
        msgOn = "On",
        msgOff = "Off",
    })
    glowRow1:AddWidget(glowCheck, 0.5)
    manager:Register(glowCheck, "all")

    local glowTypeDropdown = GUIFrame:CreateDropdown(glowRow1, "Glow Type", {
        options = {
            { key = "pixel",    text = "Pixel" },
            { key = "autocast", text = "Autocast" },
        },
        value = db.ImportantGlow.GlowType or "pixel",
        callback = function(key) db.ImportantGlow.GlowType = key; ApplySettings() end,
    })
    glowRow1:AddWidget(glowTypeDropdown, 0.5)
    manager:Register(glowTypeDropdown, "all")
    cardGlow:AddRow(glowRow1, Theme.rowHeight)

    -- Row 2: Color + Lines (pixel: line count / autocast: particle count)
    local glowRow2 = GUIFrame:CreateRow(cardGlow.content, Theme.rowHeight)
    local glowColorPicker = GUIFrame:CreateColorPicker(glowRow2, "Glow Color", {
        color = db.ImportantGlow.Color or { 1, 0.85, 0.1, 1 },
        callback = function(r, g, b, a)
            db.ImportantGlow.Color = { r, g, b, a }
            ApplySettings()
        end,
    })
    glowRow2:AddWidget(glowColorPicker, 0.5)
    manager:Register(glowColorPicker, "all")

    local glowLinesSlider = GUIFrame:CreateSlider(glowRow2, "Glow Lines", {
        min = 1, max = 16, step = 1,
        value = db.ImportantGlow.GlowLines or 8,
        callback = function(val) db.ImportantGlow.GlowLines = val; ApplySettings() end,
    })
    glowRow2:AddWidget(glowLinesSlider, 0.5)
    manager:Register(glowLinesSlider, "all")
    cardGlow:AddRow(glowRow2, Theme.rowHeight)

    -- Row 3: Frequency + Thickness
    local glowRow3 = GUIFrame:CreateRow(cardGlow.content, Theme.rowHeight)
    local glowFreqSlider = GUIFrame:CreateSlider(glowRow3, "Glow Frequency", {
        min = 0.05, max = 1, step = 0.05,
        value = db.ImportantGlow.GlowFrequency or 0.25,
        callback = function(val) db.ImportantGlow.GlowFrequency = val; ApplySettings() end,
    })
    glowRow3:AddWidget(glowFreqSlider, 0.5)
    manager:Register(glowFreqSlider, "all")

    local glowThicknessSlider = GUIFrame:CreateSlider(glowRow3, "Glow Thickness", {
        min = 1, max = 8, step = 1,
        value = db.ImportantGlow.GlowThickness or 2,
        callback = function(val) db.ImportantGlow.GlowThickness = val; ApplySettings() end,
    })
    glowRow3:AddWidget(glowThicknessSlider, 0.5)
    manager:Register(glowThicknessSlider, "all")
    cardGlow:AddRow(glowRow3, Theme.rowHeight)

    -- Row 4: Length (pixel) + Scale (autocast)
    local glowRow4 = GUIFrame:CreateRow(cardGlow.content, Theme.rowHeight)
    local glowLengthSlider = GUIFrame:CreateSlider(glowRow4, "Glow Length", {
        min = 1, max = 20, step = 1,
        value = db.ImportantGlow.GlowLength or 8,
        callback = function(val) db.ImportantGlow.GlowLength = val; ApplySettings() end,
    })
    glowRow4:AddWidget(glowLengthSlider, 0.5)
    manager:Register(glowLengthSlider, "all")

    local glowScaleSlider = GUIFrame:CreateSlider(glowRow4, "Glow Scale", {
        min = 0.5, max = 3, step = 0.1,
        value = db.ImportantGlow.GlowScale or 1,
        callback = function(val) db.ImportantGlow.GlowScale = val; ApplySettings() end,
    })
    glowRow4:AddWidget(glowScaleSlider, 0.5)
    manager:Register(glowScaleSlider, "all")
    cardGlow:AddRow(glowRow4, Theme.rowHeight)

    -- Row 5: Border (pixel)
    local glowRow5 = GUIFrame:CreateRow(cardGlow.content, Theme.rowHeight)
    local glowBorderCheck = GUIFrame:CreateCheckbox(glowRow5, "Glow Border", {
        value = db.ImportantGlow.GlowBorder ~= false,
        callback = function(checked) db.ImportantGlow.GlowBorder = checked; ApplySettings() end,
        msgPopup = true,
        msgText = "Glow Border",
        msgOn = "On",
        msgOff = "Off",
    })
    glowRow5:AddWidget(glowBorderCheck, 0.5)
    manager:Register(glowBorderCheck, "all")
    cardGlow:AddRow(glowRow5, Theme.rowHeight)

    local glowNoteRow = GUIFrame:CreateRow(cardGlow.content, Theme.rowHeightNote)
    local glowNote = GUIFrame:CreateText(glowNoteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Fires only on casts Blizzard flags important; changes apply on the next cast.\n" ..
        KE:ColorTextByTheme("-") .. " Pixel uses Lines/Length/Thickness/Border. Autocast uses Lines/Scale.",
        50, "hide")
    glowNoteRow:AddWidget(glowNote, 1)
    manager:Register(glowNote, "all")
    cardGlow:AddRow(glowNoteRow, Theme.rowHeightNote, 0)

    yOffset = cardGlow:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 8: Sound Settings
    ----------------------------------------------------------------
    local cardSound = GUIFrame:CreateCard(scrollChild, "Sound Settings", yOffset)
    manager:Register(cardSound, "all")

    local soundList = { ["None"] = "None" }
    if LSM then
        for name in pairs(LSM:HashTable("sound")) do soundList[name] = name end
    end

    local rowSndA = GUIFrame:CreateRow(cardSound.content, Theme.rowHeight)
    local soundEnable = GUIFrame:CreateCheckbox(rowSndA, "Play Sound on Cast", {
        value = db.SoundEnabled == true,
        callback = function(checked) db.SoundEnabled = checked; ApplySettings() end,
    })
    rowSndA:AddWidget(soundEnable, 0.5)
    manager:Register(soundEnable, "all")

    local channelDropdown = GUIFrame:CreateDropdown(rowSndA, "Channel", {
        options = {
            { key = "Master",   text = "Master" },
            { key = "SFX",      text = "SFX" },
            { key = "Music",    text = "Music" },
            { key = "Ambience", text = "Ambience" },
            { key = "Dialog",   text = "Dialog" },
        },
        value = db.SoundChannel or "SFX",
        callback = function(key) db.SoundChannel = key; ApplySettings() end,
    })
    rowSndA:AddWidget(channelDropdown, 0.5)
    manager:Register(channelDropdown, "all")
    cardSound:AddRow(rowSndA, Theme.rowHeight)

    local rowSndB = GUIFrame:CreateRow(cardSound.content, Theme.rowHeight)
    local soundDropdown = GUIFrame:CreateDropdown(rowSndB, "Sound", {
        options = soundList,
        value = db.SoundFile or "None",
        callback = function(key)
            db.SoundFile = key
            -- Play preview
            if key ~= "None" and LSM then
                local path = LSM:Fetch("sound", key)
                if path then PlaySoundFile(path, db.SoundChannel or "SFX") end
            end
            ApplySettings()
        end,
        searchable = true,
    })
    rowSndB:AddWidget(soundDropdown, 1)
    manager:Register(soundDropdown, "all")
    cardSound:AddRow(rowSndB, Theme.rowHeight)

    local rowSndC = GUIFrame:CreateRow(cardSound.content, Theme.rowHeightLast)
    local muteCB = GUIFrame:CreateCheckbox(rowSndC, "Mute When Kick on CD", {
        value = db.MuteSoundOnKickCD ~= false,
        callback = function(checked) db.MuteSoundOnKickCD = checked; ApplySettings() end,
    })
    rowSndC:AddWidget(muteCB, 1)
    manager:Register(muteCB, "all")
    cardSound:AddRow(rowSndC, Theme.rowHeightLast)

    local rowSndNote = GUIFrame:CreateRow(cardSound.content, Theme.rowHeightNote)
    local sndNote = GUIFrame:CreateText(rowSndNote,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Plays when your focus target starts casting.\n" ..
        KE:ColorTextByTheme("-") .. " Cannot filter by interruptible casts (WoW secret value), but can filter by your kick cooldown.",
        50, "hide")
    rowSndNote:AddWidget(sndNote, 1)
    manager:Register(sndNote, "all")
    cardSound:AddRow(rowSndNote, Theme.rowHeightNote, 0)

    yOffset = cardSound:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 9: Hold Timer
    ----------------------------------------------------------------
    local cardHold = GUIFrame:CreateCard(scrollChild, "Hold Timer", yOffset)
    manager:Register(cardHold, "all")

    local row8a = GUIFrame:CreateRow(cardHold.content, Theme.rowHeight)
    local holdEnableCheck = GUIFrame:CreateCheckbox(row8a, "Enable Hold Timer", {
        value = db.HoldTimer.Enabled ~= false,
        callback = function(checked)
            db.HoldTimer.Enabled = checked
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Hold Timer",
        msgOn = "On",
        msgOff = "Off",
    })
    row8a:AddWidget(holdEnableCheck, 0.5)
    manager:Register(holdEnableCheck, "all")

    local holdSlider = GUIFrame:CreateSlider(row8a, "Hold Duration", {
        min = 0, max = 2, step = 0.1,
        value = db.HoldTimer.Duration or 0.5,
        callback = function(val) db.HoldTimer.Duration = val end,
    })
    row8a:AddWidget(holdSlider, 0.5)
    manager:Register(holdSlider, "holdTimer")
    cardHold:AddRow(row8a, Theme.rowHeight)

    local rowSep3 = GUIFrame:CreateRow(cardHold.content, Theme.rowHeightSeparator)
    local sep3 = GUIFrame:CreateSeparator(rowSep3)
    rowSep3:AddWidget(sep3, 1)
    manager:Register(sep3, "holdTimer")
    cardHold:AddRow(rowSep3, Theme.rowHeightSeparator)

    local row8b = GUIFrame:CreateRow(cardHold.content, Theme.rowHeightLast)
    local interruptedPicker = GUIFrame:CreateColorPicker(row8b, "Interrupted", {
        color = db.HoldTimer.InterruptedColor or { 0.1, 0.8, 0.1, 1 },
        callback = function(r, g, b, a) db.HoldTimer.InterruptedColor = { r, g, b, a } end,
    })
    row8b:AddWidget(interruptedPicker, 0.5)
    manager:Register(interruptedPicker, "holdTimer")

    local successPicker = GUIFrame:CreateColorPicker(row8b, "Cast Success", {
        color = db.HoldTimer.SuccessColor or { 0.8, 0.1, 0.1, 1 },
        callback = function(r, g, b, a) db.HoldTimer.SuccessColor = { r, g, b, a } end,
    })
    row8b:AddWidget(successPicker, 0.5)
    manager:Register(successPicker, "holdTimer")
    cardHold:AddRow(row8b, Theme.rowHeightLast, 0)

    yOffset = cardHold:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 10: Kick Indicator
    ----------------------------------------------------------------
    local cardKick = GUIFrame:CreateCard(scrollChild, "Kick Indicator", yOffset)
    manager:Register(cardKick, "all")

    local row9a = GUIFrame:CreateRow(cardKick.content, Theme.rowHeight)
    local kickEnableCheck = GUIFrame:CreateCheckbox(row9a, "Enable Kick Indicator", {
        value = db.KickIndicator.Enabled ~= false,
        callback = function(checked)
            db.KickIndicator.Enabled = checked
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Kick Indicator",
        msgOn = "On",
        msgOff = "Off",
    })
    row9a:AddWidget(kickEnableCheck, 1)
    manager:Register(kickEnableCheck, "all")
    cardKick:AddRow(row9a, Theme.rowHeight)

    local rowKickNote = GUIFrame:CreateRow(cardKick.content, Theme.rowHeight)
    local kickNote = GUIFrame:CreateText(rowKickNote,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " When enabled, bar color reflects kick readiness instead of cast type (Casting/Channeling colors).",
        Theme.rowHeight, "hide")
    rowKickNote:AddWidget(kickNote, 1)
    manager:Register(kickNote, "kickIndicator")
    cardKick:AddRow(rowKickNote, Theme.rowHeight)

    local rowSepKick = GUIFrame:CreateRow(cardKick.content, Theme.rowHeightSeparator)
    local sepKick = GUIFrame:CreateSeparator(rowSepKick)
    rowSepKick:AddWidget(sepKick, 1)
    manager:Register(sepKick, "kickIndicator")
    cardKick:AddRow(rowSepKick, Theme.rowHeightSeparator)

    local row9b = GUIFrame:CreateRow(cardKick.content, Theme.rowHeight)
    local readyPicker = GUIFrame:CreateColorPicker(row9b, "Kick Ready", {
        color = db.KickIndicator.ReadyColor or { 0.1, 0.8, 0.1, 1 },
        callback = function(r, g, b, a)
            db.KickIndicator.ReadyColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row9b:AddWidget(readyPicker, 0.5)
    manager:Register(readyPicker, "kickIndicator")

    local notReadyPicker = GUIFrame:CreateColorPicker(row9b, "Kick Not Ready", {
        color = db.KickIndicator.NotReadyColor or { 0.5, 0.5, 0.5, 1 },
        callback = function(r, g, b, a)
            db.KickIndicator.NotReadyColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row9b:AddWidget(notReadyPicker, 0.5)
    manager:Register(notReadyPicker, "kickIndicator")
    cardKick:AddRow(row9b, Theme.rowHeight)

    local row9c = GUIFrame:CreateRow(cardKick.content, Theme.rowHeightLast)
    local tickPicker = GUIFrame:CreateColorPicker(row9c, "Kick Ready Tick", {
        color = db.KickIndicator.TickColor or { 1, 1, 1, 1 },
        callback = function(r, g, b, a)
            db.KickIndicator.TickColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row9c:AddWidget(tickPicker, 0.5)
    manager:Register(tickPicker, "kickIndicator")
    cardKick:AddRow(row9c, Theme.rowHeightLast, 0)

    yOffset = cardKick:GetNextOffset()

    RefreshStates()
    return yOffset
end)
