-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-PrescienceTracker.lua                               ║
-- ║  GUI: Prescience Tracker                                 ║
-- ║  Purpose: Configuration panel for the PrescienceTracker  ║
-- ║  module.                                                 ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("PrescienceTracker", true)
    end
    return nil
end

GUIFrame:RegisterContent("PrescienceTracker", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.PrescienceTracker
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local mod = GetModule()
    local manager = GUIFrame:CreateWidgetStateManager()
    manager:SetCondition("nameColor", function() return not db.ClassColorNames end)

    local function ApplySettings()
        if mod and mod.ApplySettings then mod:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("PrescienceTracker")
        else
            KitnEssentials:DisableModule("PrescienceTracker")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Prescience Tracker", yOffset)
    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        ApplyModuleState(checked)
        KE:Print("Prescience Tracker: " .. (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
    end)

    local noteRow = GUIFrame:CreateRow(card1.content, Theme.rowHeightNote)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Tracks Prescience and Shifting Sands on party/raid members.\n" ..
        KE:ColorTextByTheme("-") .. " Only active for Augmentation Evoker.",
        50, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, Theme.rowHeightNote, 0)

    yOffset = card1:GetNextOffset()

    -- Lone header bar: a disabled module shows its switch and nothing else.
    if db.Enabled == false then return yOffset end

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
    -- Card 3: Display Settings
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Display Settings", yOffset)
    manager:Register(card3, "all")

    -- Tracked buffs
    local row3buffs = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local presCheck = GUIFrame:CreateCheckbox(row3buffs, "Prescience", {
        value = db.ShowPrescience ~= false,
        callback = function(checked) db.ShowPrescience = checked; ApplySettings() end,
    })
    row3buffs:AddWidget(presCheck, 0.5)
    manager:Register(presCheck, "all")

    local sandCheck = GUIFrame:CreateCheckbox(row3buffs, "Shifting Sands", {
        value = db.ShowShiftingSands == true,
        callback = function(checked) db.ShowShiftingSands = checked; ApplySettings() end,
    })
    row3buffs:AddWidget(sandCheck, 0.5)
    manager:Register(sandCheck, "all")
    card3:AddRow(row3buffs, Theme.rowHeight)

    local row3sep1 = GUIFrame:CreateRow(card3.content, Theme.rowHeightSeparator)
    local sep3a = GUIFrame:CreateSeparator(row3sep1)
    row3sep1:AddWidget(sep3a, 1)
    manager:Register(sep3a, "all")
    card3:AddRow(row3sep1, Theme.rowHeightSeparator)

    -- Layout
    local row3a = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local growthDropdown = GUIFrame:CreateDropdown(row3a, "Growth Direction", {
        options = {
            { key = "DOWN",  text = "Down" },
            { key = "UP",    text = "Up" },
            { key = "RIGHT", text = "Right" },
            { key = "LEFT",  text = "Left" },
        },
        value = db.GrowthDirection or "DOWN",
        callback = function(key) db.GrowthDirection = key; ApplySettings() end,
    })
    row3a:AddWidget(growthDropdown, 0.5)
    manager:Register(growthDropdown, "all")

    local maxSlider = GUIFrame:CreateSlider(row3a, "Max Entries", {
        min = 1, max = 20, step = 1,
        value = db.MaxEntries or 6,
        callback = function(val) db.MaxEntries = val; ApplySettings() end,
    })
    row3a:AddWidget(maxSlider, 0.5)
    manager:Register(maxSlider, "all")
    card3:AddRow(row3a, Theme.rowHeight)

    local row3b = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local iconSlider = GUIFrame:CreateSlider(row3b, "Icon Size", {
        min = 16, max = 64, step = 2,
        value = db.IconSize or 32,
        callback = function(val) db.IconSize = val; ApplySettings() end,
    })
    row3b:AddWidget(iconSlider, 0.5)
    manager:Register(iconSlider, "all")

    local spacingSlider = GUIFrame:CreateSlider(row3b, "Spacing", {
        min = 0, max = 20, step = 1,
        value = db.Spacing or 4,
        callback = function(val) db.Spacing = val; ApplySettings() end,
    })
    row3b:AddWidget(spacingSlider, 0.5)
    manager:Register(spacingSlider, "all")
    card3:AddRow(row3b, Theme.rowHeight)

    local row3sep2 = GUIFrame:CreateRow(card3.content, Theme.rowHeightSeparator)
    local sep3b = GUIFrame:CreateSeparator(row3sep2)
    row3sep2:AddWidget(sep3b, 1)
    manager:Register(sep3b, "all")
    card3:AddRow(row3sep2, Theme.rowHeightSeparator)

    -- Per-entry decorations
    local row3c = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local roleCheck = GUIFrame:CreateCheckbox(row3c, "Show Role Icons", {
        value = db.ShowRoleIcon ~= false,
        callback = function(checked) db.ShowRoleIcon = checked; ApplySettings() end,
    })
    row3c:AddWidget(roleCheck, 0.4)
    manager:Register(roleCheck, "all")

    local roleScaleSlider = GUIFrame:CreateSlider(row3c, "Role Icon Scale", {
        min = 0.5, max = 3.0, step = 0.1,
        value = db.RoleIconScale or 1.0,
        callback = function(val) db.RoleIconScale = val; ApplySettings() end,
    })
    row3c:AddWidget(roleScaleSlider, 0.6)
    manager:Register(roleScaleSlider, "all")
    card3:AddRow(row3c, Theme.rowHeight)

    local row3d = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local nameCheck = GUIFrame:CreateCheckbox(row3d, "Show Names", {
        value = db.ShowNames ~= false,
        callback = function(checked) db.ShowNames = checked; ApplySettings() end,
    })
    row3d:AddWidget(nameCheck, 0.4)
    manager:Register(nameCheck, "all")

    local maxLenSlider = GUIFrame:CreateSlider(row3d, "Max Characters", {
        min = 0, max = 12, step = 1,
        value = db.NameMaxLength or 0,
        callback = function(val) db.NameMaxLength = val; ApplySettings() end,
    })
    row3d:AddWidget(maxLenSlider, 0.6)
    manager:Register(maxLenSlider, "all")
    card3:AddRow(row3d, Theme.rowHeightLast, 0)

    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Name Font
    ----------------------------------------------------------------
    local nameFontCard, nameFontOffset, nameFontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        title = "Name Font",
        db = db,
        dbKeys = {
            fontFace = "NameFontFace",
            fontSize = "NameFontSize",
            fontOutline = "NameFontOutline",
        },
        fontSizeRange = { 8, 32 },
        onChangeCallback = ApplySettings,
    })
    manager:Register(nameFontCard, "all")
    if nameFontWidgets then
        manager:RegisterGroup(nameFontWidgets, "all")
    end
    yOffset = nameFontOffset

    ----------------------------------------------------------------
    -- Card 5: Timer Font
    ----------------------------------------------------------------
    local timerFontCard, timerFontOffset, timerFontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        title = "Timer Font",
        db = db,
        dbKeys = {
            fontFace = "TimerFontFace",
            fontSize = "TimerFontSize",
            fontOutline = "TimerFontOutline",
        },
        fontSizeRange = { 8, 32 },
        onChangeCallback = ApplySettings,
    })
    manager:Register(timerFontCard, "all")
    if timerFontWidgets then
        manager:RegisterGroup(timerFontWidgets, "all")
    end
    yOffset = timerFontOffset

    ----------------------------------------------------------------
    -- Card 6: Colors
    ----------------------------------------------------------------
    yOffset = GUIFrame:CreateColorsCard(scrollChild, yOffset, {
        db         = db,
        manager    = manager,
        onChange   = ApplySettings,
        stateGroup = "all",
        isLast     = true,
        sources = {
            { label = "Class Color Names", key = "ClassColorNames", default = false, onChange = RefreshStates },
        },
        colors = {
            { label = "Name Color", key = "NameColor", default = { 1, 1, 1, 1 }, group = "nameColor" },
            { label = "Timer Color", key = "TimerColor", default = { 1, 1, 1, 1 } },
            { label = "Crit Color", key = "CritColor", default = { 1, 0, 1, 1 } },
        },
        note = KE:ColorTextByTheme("-") .. " Crit color applies to Prescience when it has a critical strike bonus.",
    })

    RefreshStates()
    return yOffset
end)
