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
local PlaySoundFile = PlaySoundFile

local function GetModule() return KitnEssentials and KitnEssentials:GetModule("AuraExternals", true) end

GUIFrame:RegisterContent("AuraExternals", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.AuraExternals
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local AX = GetModule()

    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        if AX and AX.ApplySettings then AX:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not KitnEssentials then return end
        local mod = KitnEssentials:GetModule("AuraExternals", true)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("AuraExternals")
        else
            KitnEssentials:DisableModule("AuraExternals")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    -- "Reverse Cooldown Direction" only matters when Swipe is on, so it's
    -- greyed out when Swipe is unchecked.
    manager:SetCondition("swipeOn", function() return db.Swipe ~= false end)

    ----------------------------------------------------------------
    -- Card 1: Enable
    --
    -- Two toggles: master Enable + "Include Defensives" (your own large
    -- defensive CDs alongside externally-applied ones).
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Aura Externals", yOffset)

    local row1a = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1a, "Enable Aura Externals", {
        value = db.Enabled ~= false,
        callback = function(checked)
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

    local row1b = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local defensivesCheck = GUIFrame:CreateCheckbox(row1b, "Include Defensives", {
        value = db.ShowBigDefensives ~= false,
        callback = function(checked) db.ShowBigDefensives = checked; ApplySettings() end,
        tooltip = "Include your own large defensive cooldowns (Shield Wall, Iron Bark, etc.) alongside externally-applied defensives.",
    })
    row1b:AddWidget(defensivesCheck, 1)
    manager:Register(defensivesCheck, "all")
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

    local spacingSlider = GUIFrame:CreateSlider(row3a, "Icon Spacing", {
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

    -- Separator between sliders and grow-direction dropdowns
    local row3sep1 = GUIFrame:CreateRow(card3.content, Theme.rowHeightSeparator)
    local sep3a = GUIFrame:CreateSeparator(row3sep1)
    row3sep1:AddWidget(sep3a, 1)
    manager:Register(sep3a, "all")
    card3:AddRow(row3sep1, Theme.rowHeightSeparator)

    local row3c = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
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

    local growVertDropdown = GUIFrame:CreateDropdown(row3c, "Grow Vertical", {
        options = {
            { key = "UP",   text = "Up" },
            { key = "DOWN", text = "Down" },
        },
        value = db.GrowVertical or "DOWN",
        callback = function(key) db.GrowVertical = key; ApplySettings() end,
    })
    row3c:AddWidget(growVertDropdown, 0.5)
    manager:Register(growVertDropdown, "all")
    card3:AddRow(row3c, Theme.rowHeight)

    -- Separator between grow-direction dropdowns and swipe/reverse checkboxes
    local row3sep2 = GUIFrame:CreateRow(card3.content, Theme.rowHeightSeparator)
    local sep3b = GUIFrame:CreateSeparator(row3sep2)
    row3sep2:AddWidget(sep3b, 1)
    manager:Register(sep3b, "all")
    card3:AddRow(row3sep2, Theme.rowHeightSeparator)

    local row3d = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local swipeCheck = GUIFrame:CreateCheckbox(row3d, "Swipe (Cooldown Spiral)", {
        value = db.Swipe ~= false,
        callback = function(checked)
            db.Swipe = checked
            ApplySettings()
            RefreshStates()  -- re-evaluate swipeOn condition for reverseCheck
        end,
    })
    row3d:AddWidget(swipeCheck, 0.5)
    manager:Register(swipeCheck, "all")

    local reverseCheck = GUIFrame:CreateCheckbox(row3d, "Reverse Cooldown Direction", {
        value = db.Reverse ~= false,
        callback = function(checked) db.Reverse = checked; ApplySettings() end,
    })
    row3d:AddWidget(reverseCheck, 0.5)
    manager:Register(reverseCheck, "swipeOn")
    card3:AddRow(row3d, Theme.rowHeightLast, 0)

    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Glow Settings
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
    -- Card 5: Sound (External Defensives Only)
    --
    -- External defensives applied to you (Pain Suppression, Iron Bark,
    -- etc.) play the configured sound on application. Self-applied big
    -- defensives are silent.
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Sound (External Defensives Only)", yOffset)
    manager:Register(card5, "all")

    local row5a = GUIFrame:CreateRow(card5.content, Theme.rowHeight)
    local soundEnabledCheck = GUIFrame:CreateCheckbox(row5a, "Enable Sound", {
        value = db.SoundEnabled ~= false,
        callback = function(checked) db.SoundEnabled = checked; ApplySettings() end,
    })
    row5a:AddWidget(soundEnabledCheck, 1)
    manager:Register(soundEnabledCheck, "all")
    card5:AddRow(row5a, Theme.rowHeight)

    -- Separator between Enable toggle and the sound dropdown/test row
    local row5sep = GUIFrame:CreateRow(card5.content, Theme.rowHeightSeparator)
    local sep5 = GUIFrame:CreateSeparator(row5sep)
    row5sep:AddWidget(sep5, 1)
    manager:Register(sep5, "all")
    card5:AddRow(row5sep, Theme.rowHeightSeparator)

    local soundList = {}
    if LSM then
        for name in pairs(LSM:HashTable("sound")) do
            soundList[name] = name
        end
    end
    soundList["None"] = "None"

    local row5b = GUIFrame:CreateRow(card5.content, Theme.rowHeightLast)
    local soundDropdown = GUIFrame:CreateDropdown(row5b, "On Application Sound", {
        options = soundList,
        value = db.SoundName or "None",
        searchable = true,
        callback = function(key) db.SoundName = key; ApplySettings() end,
    })
    row5b:AddWidget(soundDropdown, 0.5)
    manager:Register(soundDropdown, "all")

    -- Test button: plays whatever sound is currently selected. y=-12 places
    -- the 28px button center on the dropdown bar center (matches the pattern
    -- used in DungeonTimers detail panel).
    local soundTestBtn = GUIFrame:CreateButton(row5b, "Test", {
        height = 28,
        callback = function()
            local name = db.SoundName
            if not name or name == "None" or not LSM then return end
            local soundPath = LSM:Fetch("sound", name)
            if soundPath then PlaySoundFile(soundPath) end
        end,
    })
    row5b:AddWidget(soundTestBtn, 0.5, nil, 0, -12)
    manager:Register(soundTestBtn, "all")
    card5:AddRow(row5b, Theme.rowHeightLast, 0)

    yOffset = card5:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 6: Font Settings
    ----------------------------------------------------------------
    local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        title = "Font Settings",
        db = db,
        dbKeys = {
            fontFace    = "FontFace",
            fontOutline = "FontOutline",
        },
        fontSizes = {
            { label = "Count Size",  dbKey = "FontSize",      default = 14 },
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
    -- Card 7: Element Positions
    --
    -- One anchor per element (Timer text / Stack text) drives both
    -- AnchorFrom and AnchorTo — picking "CENTER" aligns the element's
    -- center with the button's center, picking "BOTTOMRIGHT" stacks them
    -- by bottom-right, etc. Mirrors AuraDebuffs' Element Positions card.
    ----------------------------------------------------------------
    local card7 = GUIFrame:CreateCard(scrollChild, "Element Positions", yOffset)
    manager:Register(card7, "all")

    local TEXT_ANCHOR_OPTIONS = {
        { key = "TOPLEFT",     text = "Top Left" },
        { key = "TOP",         text = "Top" },
        { key = "TOPRIGHT",    text = "Top Right" },
        { key = "LEFT",        text = "Left" },
        { key = "CENTER",      text = "Center" },
        { key = "RIGHT",       text = "Right" },
        { key = "BOTTOMLEFT",  text = "Bottom Left" },
        { key = "BOTTOM",      text = "Bottom" },
        { key = "BOTTOMRIGHT", text = "Bottom Right" },
    }

    db.TimerPosition = db.TimerPosition or {}
    db.StackPosition = db.StackPosition
        or { AnchorFrom = "BOTTOMRIGHT", AnchorTo = "BOTTOMRIGHT", XOffset = -1, YOffset = 1 }
    local tp, sp = db.TimerPosition, db.StackPosition

    -- Row: Timer Anchor + Timer X + Timer Y (each 1/3 width)
    local row7a = GUIFrame:CreateRow(card7.content, Theme.rowHeight)
    local timerAnchor = GUIFrame:CreateDropdown(row7a, "Timer Text Anchor", {
        options = TEXT_ANCHOR_OPTIONS,
        value   = tp.AnchorFrom or "CENTER",
        callback = function(key)
            tp.AnchorFrom = key
            tp.AnchorTo   = key
            ApplySettings()
        end,
    })
    row7a:AddWidget(timerAnchor, 1 / 3)
    manager:Register(timerAnchor, "all")

    local timerX = GUIFrame:CreateSlider(row7a, "Timer X", {
        min = -50, max = 50, step = 1,
        value = tp.XOffset or 0,
        callback = function(val) tp.XOffset = val; ApplySettings() end,
    })
    row7a:AddWidget(timerX, 1 / 3)
    manager:Register(timerX, "all")

    local timerY = GUIFrame:CreateSlider(row7a, "Timer Y", {
        min = -50, max = 50, step = 1,
        value = tp.YOffset or 0,
        callback = function(val) tp.YOffset = val; ApplySettings() end,
    })
    row7a:AddWidget(timerY, 1 / 3)
    manager:Register(timerY, "all")
    card7:AddRow(row7a, Theme.rowHeight)

    -- Separator between Timer and Stack rows
    local row7sep = GUIFrame:CreateRow(card7.content, Theme.rowHeightSeparator)
    local sep7 = GUIFrame:CreateSeparator(row7sep)
    row7sep:AddWidget(sep7, 1)
    manager:Register(sep7, "all")
    card7:AddRow(row7sep, Theme.rowHeightSeparator)

    -- Row: Stack Anchor + Stack X + Stack Y (each 1/3 width)
    local row7b = GUIFrame:CreateRow(card7.content, Theme.rowHeightLast)
    local stackAnchor = GUIFrame:CreateDropdown(row7b, "Stack Count Anchor", {
        options = TEXT_ANCHOR_OPTIONS,
        value   = sp.AnchorFrom or "BOTTOMRIGHT",
        callback = function(key)
            sp.AnchorFrom = key
            sp.AnchorTo   = key
            ApplySettings()
        end,
    })
    row7b:AddWidget(stackAnchor, 1 / 3)
    manager:Register(stackAnchor, "all")

    local stackX = GUIFrame:CreateSlider(row7b, "Stack X", {
        min = -50, max = 50, step = 1,
        value = sp.XOffset or -1,
        callback = function(val) sp.XOffset = val; ApplySettings() end,
    })
    row7b:AddWidget(stackX, 1 / 3)
    manager:Register(stackX, "all")

    local stackY = GUIFrame:CreateSlider(row7b, "Stack Y", {
        min = -50, max = 50, step = 1,
        value = sp.YOffset or 1,
        callback = function(val) sp.YOffset = val; ApplySettings() end,
    })
    row7b:AddWidget(stackY, 1 / 3)
    manager:Register(stackY, "all")
    card7:AddRow(row7b, Theme.rowHeightLast, 0)

    yOffset = card7:GetNextOffset()

    RefreshStates()
    return yOffset
end)
