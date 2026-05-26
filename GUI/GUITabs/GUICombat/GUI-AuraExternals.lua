-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-AuraExternals.lua                                   ║
-- ║  GUI: Aura Externals                                     ║
-- ║  Purpose: Configuration panel for the AuraExternals      ║
-- ║           module (external defensives display).          ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme    = KE.Theme
local LSM      = KE.LSM or LibStub("LibSharedMedia-3.0", true)

local function GetModule() return KitnEssentials and KitnEssentials:GetModule("AuraExternals", true) end

GUIFrame:RegisterContent("AuraExternals", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.AuraExternals
    if not db then return yOffset end

    local AX = GetModule()

    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        if AX and AX.ApplySettings then AX:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not KitnEssentials then return end
        local mod = KitnEssentials:GetModule("AuraExternals", true)
        if not mod then return end
        db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("AuraExternals")
        else
            KitnEssentials:DisableModule("AuraExternals")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Aura Externals", yOffset)

    local row1a = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1a, "Enable Aura Externals", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Aura Externals",
        msgOn = "On",
        msgOff = "Off",
    })
    row1a:AddWidget(enableCheck, 1)
    card1:AddRow(row1a, Theme.rowHeight)

    local row1b = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local selfCastCheck = GUIFrame:CreateCheckbox(row1b, "Include Self-Cast", {
        value = db.IncludeSelfCast ~= false,
        callback = function(checked) db.IncludeSelfCast = checked; ApplySettings() end,
    })
    row1b:AddWidget(selfCastCheck, 0.5)
    manager:Register(selfCastCheck, "all")

    local bigDefCheck = GUIFrame:CreateCheckbox(row1b, "Show Big Defensives", {
        value = db.ShowBigDefensives ~= false,
        callback = function(checked) db.ShowBigDefensives = checked; ApplySettings() end,
    })
    row1b:AddWidget(bigDefCheck, 0.5)
    manager:Register(bigDefCheck, "all")
    card1:AddRow(row1b, Theme.rowHeightLast, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Position Settings
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            anchorFrameType  = "anchorFrameType",
            anchorFrameFrame = "ParentFrame",
            selfPoint        = "AnchorFrom",
            anchorPoint      = "AnchorTo",
            xOffset          = "XOffset",
            yOffset          = "YOffset",
            strata           = "Strata",
        },
        showAnchorFrameType = true,
        showStrata          = true,
        showPixelSnap       = true,
        onChangeCallback    = ApplySettings,
    })

    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "all")
    end
    manager:Register(posCard, "all")
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 3: Display
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Display", yOffset)
    manager:Register(card3, "all")

    local row3a = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local iconSizeSlider = GUIFrame:CreateSlider(row3a, "Icon Size", {
        min = 16, max = 64, step = 1,
        value = db.IconSize or 36,
        callback = function(val) db.IconSize = val; ApplySettings() end,
    })
    row3a:AddWidget(iconSizeSlider, 0.5)
    manager:Register(iconSizeSlider, "all")

    local spacingSlider = GUIFrame:CreateSlider(row3a, "Spacing", {
        min = 0, max = 10, step = 1,
        value = db.IconSpacing or 1,
        callback = function(val) db.IconSpacing = val; ApplySettings() end,
    })
    row3a:AddWidget(spacingSlider, 0.5)
    manager:Register(spacingSlider, "all")
    card3:AddRow(row3a, Theme.rowHeight)

    local row3b = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local iconsPerRowSlider = GUIFrame:CreateSlider(row3b, "Icons Per Row", {
        min = 1, max = 12, step = 1,
        value = db.IconsPerRow or 6,
        callback = function(val) db.IconsPerRow = val; ApplySettings() end,
    })
    row3b:AddWidget(iconsPerRowSlider, 0.5)
    manager:Register(iconsPerRowSlider, "all")

    local maxRowsSlider = GUIFrame:CreateSlider(row3b, "Max Rows", {
        min = 1, max = 3, step = 1,
        value = db.MaxRows or 1,
        callback = function(val) db.MaxRows = val; ApplySettings() end,
    })
    row3b:AddWidget(maxRowsSlider, 0.5)
    manager:Register(maxRowsSlider, "all")
    card3:AddRow(row3b, Theme.rowHeight)

    local row3c = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local iconZoomSlider = GUIFrame:CreateSlider(row3c, "Icon Zoom", {
        min = 0, max = 0.5, step = 0.05,
        value = db.IconZoom or 0.30,
        callback = function(val) db.IconZoom = val; ApplySettings() end,
    })
    row3c:AddWidget(iconZoomSlider, 0.5)
    manager:Register(iconZoomSlider, "all")

    local growHorizDropdown = GUIFrame:CreateDropdown(row3c, "Grow Horizontal", {
        options = {
            { key = "LEFT",  text = "Left" },
            { key = "RIGHT", text = "Right" },
        },
        value = db.GrowHorizontal or "RIGHT",
        callback = function(key) db.GrowHorizontal = key; ApplySettings() end,
    })
    row3c:AddWidget(growHorizDropdown, 0.5)
    manager:Register(growHorizDropdown, "all")
    card3:AddRow(row3c, Theme.rowHeight)

    local row3d = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local swipeCheck = GUIFrame:CreateCheckbox(row3d, "Swipe (Cooldown Spiral)", {
        value = db.Swipe ~= false,
        callback = function(checked) db.Swipe = checked; ApplySettings() end,
    })
    row3d:AddWidget(swipeCheck, 0.5)
    manager:Register(swipeCheck, "all")

    local growVertDropdown = GUIFrame:CreateDropdown(row3d, "Grow Vertical", {
        options = {
            { key = "UP",   text = "Up" },
            { key = "DOWN", text = "Down" },
        },
        value = db.GrowVertical or "DOWN",
        callback = function(key) db.GrowVertical = key; ApplySettings() end,
    })
    row3d:AddWidget(growVertDropdown, 0.5)
    manager:Register(growVertDropdown, "all")
    card3:AddRow(row3d, Theme.rowHeight)

    local row3e = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local reverseCheck = GUIFrame:CreateCheckbox(row3e, "Reverse Cooldown Direction", {
        value = db.Reverse ~= false,
        callback = function(checked) db.Reverse = checked; ApplySettings() end,
    })
    row3e:AddWidget(reverseCheck, 1)
    manager:Register(reverseCheck, "all")
    card3:AddRow(row3e, Theme.rowHeightLast, 0)

    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Border + Background
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Border & Background", yOffset)
    manager:Register(card4, "all")

    local row4a = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local borderColorPicker = GUIFrame:CreateColorPicker(row4a, "Border Color", {
        color = db.BorderColor or { 0, 0, 0, 1 },
        callback = function(r, g, b, a)
            db.BorderColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row4a:AddWidget(borderColorPicker, 0.5)
    manager:Register(borderColorPicker, "all")

    local bgColorPicker = GUIFrame:CreateColorPicker(row4a, "Background Color", {
        color = db.BackgroundColor or { 0, 0, 0, 0.3 },
        callback = function(r, g, b, a)
            db.BackgroundColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row4a:AddWidget(bgColorPicker, 0.5)
    manager:Register(bgColorPicker, "all")
    card4:AddRow(row4a, Theme.rowHeightLast, 0)

    yOffset = card4:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Glow Settings
    ----------------------------------------------------------------
    local glowCard, glowOffset, glowWidgets = GUIFrame:CreateGlowSettingsCard(scrollChild, yOffset, {
        title = "Glow Settings",
        db = db,
        dbKeys = {
            enabled   = "GlowEnabled",
            type      = "GlowType",
            color     = "GlowColor",
            lines     = "GlowLines",
            frequency = "GlowFrequency",
            length    = "GlowLength",
            thickness = "GlowThickness",
            border    = "GlowBorder",
            scale     = "GlowScale",
            startAnim = "GlowStartAnim",
            duration  = "GlowDuration",
        },
        onChangeCallback = ApplySettings,
    })
    manager:Register(glowCard, "all")
    if glowWidgets then
        manager:RegisterGroup(glowWidgets, "all")
    end
    yOffset = glowOffset

    ----------------------------------------------------------------
    -- Card 6: Sound Settings
    ----------------------------------------------------------------
    local card6 = GUIFrame:CreateCard(scrollChild, "Sound Settings", yOffset)
    manager:Register(card6, "all")

    local row6a = GUIFrame:CreateRow(card6.content, Theme.rowHeight)
    local soundEnabledCheck = GUIFrame:CreateCheckbox(row6a, "Enable Sound", {
        value = db.SoundEnabled ~= false,
        callback = function(checked) db.SoundEnabled = checked; ApplySettings() end,
    })
    row6a:AddWidget(soundEnabledCheck, 1)
    manager:Register(soundEnabledCheck, "all")
    card6:AddRow(row6a, Theme.rowHeight)

    local soundList = {}
    if LSM then
        for name in pairs(LSM:HashTable("sound")) do
            soundList[name] = name
        end
    end
    soundList["None"] = "None"

    local row6b = GUIFrame:CreateRow(card6.content, Theme.rowHeightLast)
    local soundDropdown = GUIFrame:CreateDropdown(row6b, "Sound", {
        options = soundList,
        value = db.SoundName or "None",
        searchable = true,
        callback = function(key) db.SoundName = key; ApplySettings() end,
    })
    row6b:AddWidget(soundDropdown, 1)
    manager:Register(soundDropdown, "all")
    card6:AddRow(row6b, Theme.rowHeightLast, 0)

    yOffset = card6:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 7: Font Settings
    ----------------------------------------------------------------
    local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        title = "Font Settings",
        db = db,
        dbKeys = {
            fontFace    = "FontFace",
            fontOutline = "FontOutline",
        },
        fontSizes = {
            { label = "Label Size",  dbKey = "FontSize",      default = 14 },
            { label = "Timer Size",  dbKey = "TimerFontSize", default = 18 },
        },
        fontSizeRange = { 8, 48 },
        includeSoftOutline = true,
        onChangeCallback = ApplySettings,
    })
    manager:Register(fontCard, "all")
    if fontWidgets then
        manager:RegisterGroup(fontWidgets, "all")
    end
    yOffset = fontOffset

    ----------------------------------------------------------------
    -- Timer Position sub-card (inside Font block conceptually,
    -- but a separate card so it can be toggled by the manager)
    ----------------------------------------------------------------
    local card8 = GUIFrame:CreateCard(scrollChild, "Timer Position", yOffset)
    manager:Register(card8, "all")

    local tp = db.TimerPosition or {}

    local row8a = GUIFrame:CreateRow(card8.content, Theme.rowHeight)
    local tpFromDropdown = GUIFrame:CreateDropdown(row8a, "Anchor From", {
        options = {
            { key = "TOPLEFT",     text = "Top Left" },
            { key = "TOP",         text = "Top" },
            { key = "TOPRIGHT",    text = "Top Right" },
            { key = "LEFT",        text = "Left" },
            { key = "CENTER",      text = "Center" },
            { key = "RIGHT",       text = "Right" },
            { key = "BOTTOMLEFT",  text = "Bottom Left" },
            { key = "BOTTOM",      text = "Bottom" },
            { key = "BOTTOMRIGHT", text = "Bottom Right" },
        },
        value = tp.AnchorFrom or "CENTER",
        callback = function(key) db.TimerPosition.AnchorFrom = key; ApplySettings() end,
    })
    row8a:AddWidget(tpFromDropdown, 0.5)
    manager:Register(tpFromDropdown, "all")

    local tpToDropdown = GUIFrame:CreateDropdown(row8a, "Anchor To", {
        options = {
            { key = "TOPLEFT",     text = "Top Left" },
            { key = "TOP",         text = "Top" },
            { key = "TOPRIGHT",    text = "Top Right" },
            { key = "LEFT",        text = "Left" },
            { key = "CENTER",      text = "Center" },
            { key = "RIGHT",       text = "Right" },
            { key = "BOTTOMLEFT",  text = "Bottom Left" },
            { key = "BOTTOM",      text = "Bottom" },
            { key = "BOTTOMRIGHT", text = "Bottom Right" },
        },
        value = tp.AnchorTo or "CENTER",
        callback = function(key) db.TimerPosition.AnchorTo = key; ApplySettings() end,
    })
    row8a:AddWidget(tpToDropdown, 0.5)
    manager:Register(tpToDropdown, "all")
    card8:AddRow(row8a, Theme.rowHeight)

    local row8b = GUIFrame:CreateRow(card8.content, Theme.rowHeightLast)
    local tpXSlider = GUIFrame:CreateSlider(row8b, "X Offset", {
        min = -200, max = 200, step = 1,
        value = tp.XOffset or 0,
        callback = function(val) db.TimerPosition.XOffset = val; ApplySettings() end,
    })
    row8b:AddWidget(tpXSlider, 0.5)
    manager:Register(tpXSlider, "all")

    local tpYSlider = GUIFrame:CreateSlider(row8b, "Y Offset", {
        min = -200, max = 200, step = 1,
        value = tp.YOffset or 0,
        callback = function(val) db.TimerPosition.YOffset = val; ApplySettings() end,
    })
    row8b:AddWidget(tpYSlider, 0.5)
    manager:Register(tpYSlider, "all")
    card8:AddRow(row8b, Theme.rowHeightLast, 0)

    yOffset = card8:GetNextOffset()

    RefreshStates()
    return yOffset
end)
