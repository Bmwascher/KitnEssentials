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
    db.KickIndicator = db.KickIndicator or {}

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

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Focus Castbar", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Focus Castbar",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, Theme.rowHeightLast, 0)

    yOffset = card1:GetNextOffset()

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

    local row2b = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local statusbarDropdown = GUIFrame:CreateDropdown(row2b, "Bar Texture", {
        options = statusbarList,
        value = db.StatusBarTexture or "KitnUI",
        callback = function(key) db.StatusBarTexture = key; ApplySettings() end,
        searchable = true,
    })
    row2b:AddWidget(statusbarDropdown, 1)
    manager:Register(statusbarDropdown, "all")
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
    -- Card 6: Colors
    ----------------------------------------------------------------
    local cardColors = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    manager:Register(cardColors, "all")

    local row6a = GUIFrame:CreateRow(cardColors.content, Theme.rowHeight)
    local castingPicker = GUIFrame:CreateColorPicker(row6a, "Casting", {
        color = db.CastingColor or { 1, 0.7, 0, 1 },
        callback = function(r, g, b, a)
            db.CastingColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row6a:AddWidget(castingPicker, 0.5)
    manager:Register(castingPicker, "all")

    local channelingPicker = GUIFrame:CreateColorPicker(row6a, "Channeling", {
        color = db.ChannelingColor or { 0, 0.7, 1, 1 },
        callback = function(r, g, b, a)
            db.ChannelingColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row6a:AddWidget(channelingPicker, 0.5)
    manager:Register(channelingPicker, "all")
    cardColors:AddRow(row6a, Theme.rowHeight)

    local row6b = GUIFrame:CreateRow(cardColors.content, Theme.rowHeight)
    local empoweringPicker = GUIFrame:CreateColorPicker(row6b, "Empowering", {
        color = db.EmpoweringColor or { 0.8, 0.4, 1, 1 },
        callback = function(r, g, b, a)
            db.EmpoweringColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row6b:AddWidget(empoweringPicker, 0.5)
    manager:Register(empoweringPicker, "all")

    local notInterruptPicker = GUIFrame:CreateColorPicker(row6b, "Not Interruptible", {
        color = db.NotInterruptibleColor or { 0.7, 0.7, 0.7, 1 },
        callback = function(r, g, b, a)
            db.NotInterruptibleColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row6b:AddWidget(notInterruptPicker, 0.5)
    manager:Register(notInterruptPicker, "all")
    cardColors:AddRow(row6b, Theme.rowHeight)

    local row6c = GUIFrame:CreateRow(cardColors.content, Theme.rowHeight)
    local hideNotInterruptCheck = GUIFrame:CreateCheckbox(row6c, "Hide Non-Interruptible Casts", {
        value = db.HideNotInterruptible == true,
        callback = function(checked) db.HideNotInterruptible = checked end,
        msgPopup = true,
        msgText = "Hide",
        msgOn = "On",
        msgOff = "Off",
    })
    row6c:AddWidget(hideNotInterruptCheck, 1)
    manager:Register(hideNotInterruptCheck, "all")
    cardColors:AddRow(row6c, Theme.rowHeight)

    local rowSep1 = GUIFrame:CreateRow(cardColors.content, Theme.rowHeightSeparator)
    local sep1 = GUIFrame:CreateSeparator(rowSep1)
    rowSep1:AddWidget(sep1, 1)
    manager:Register(sep1, "all")
    cardColors:AddRow(rowSep1, Theme.rowHeightSeparator)

    local row6d = GUIFrame:CreateRow(cardColors.content, Theme.rowHeight)
    local textPicker = GUIFrame:CreateColorPicker(row6d, "Text", {
        color = db.TextColor or { 1, 1, 1, 1 },
        callback = function(r, g, b, a)
            db.TextColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row6d:AddWidget(textPicker, 0.5)
    manager:Register(textPicker, "all")
    cardColors:AddRow(row6d, Theme.rowHeight)

    local rowSep2 = GUIFrame:CreateRow(cardColors.content, Theme.rowHeightSeparator)
    local sep2 = GUIFrame:CreateSeparator(rowSep2)
    rowSep2:AddWidget(sep2, 1)
    manager:Register(sep2, "all")
    cardColors:AddRow(rowSep2, Theme.rowHeightSeparator)

    local row6e = GUIFrame:CreateRow(cardColors.content, Theme.rowHeightLast)
    local bgPicker = GUIFrame:CreateColorPicker(row6e, "Background", {
        color = db.BackdropColor or { 0, 0, 0, 0.8 },
        callback = function(r, g, b, a)
            db.BackdropColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row6e:AddWidget(bgPicker, 0.5)
    manager:Register(bgPicker, "all")

    local borderPicker = GUIFrame:CreateColorPicker(row6e, "Border", {
        color = db.BorderColor or { 0, 0, 0, 1 },
        callback = function(r, g, b, a)
            db.BorderColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row6e:AddWidget(borderPicker, 0.5)
    manager:Register(borderPicker, "all")
    cardColors:AddRow(row6e, Theme.rowHeightLast, 0)

    yOffset = cardColors:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 7: Sound Settings
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

    local rowSndNote = GUIFrame:CreateRow(cardSound.content, 50)
    local sndNote = GUIFrame:CreateText(rowSndNote,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Plays when your focus target starts casting.\n" ..
        KE:ColorTextByTheme("-") .. " Cannot filter by interruptible casts (WoW secret value), but can filter by your kick cooldown.",
        50, "hide")
    rowSndNote:AddWidget(sndNote, 1)
    manager:Register(sndNote, "all")
    cardSound:AddRow(rowSndNote, 50, 0)

    yOffset = cardSound:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 8: Hold Timer
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
    -- Card 9: Kick Indicator
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
