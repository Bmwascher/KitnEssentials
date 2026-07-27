-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-TotemTracker.lua                                    ║
-- ║  GUI: Totem Tracker                                      ║
-- ║  Purpose: Configuration panel for the TotemTracker       ║
-- ║           module.                                         ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local InCombatLockdown    = InCombatLockdown
local GetMacroIndexByName = GetMacroIndexByName
local GetNumMacros        = GetNumMacros
local CreateMacro         = CreateMacro

local function GetModule()
    return KitnEssentials and KitnEssentials:GetModule("TotemTracker", true)
end

GUIFrame:RegisterContent("TotemTracker", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.TotemTracker
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local manager = GUIFrame:CreateWidgetStateManager()

    manager:SetCondition("swipeOn", function() return db.Swipe end)
    manager:SetCondition("timerOn", function() return db.ShowTimer end)

    local function ApplySettings()
        local TT = GetModule()
        if TT and TT.ApplySettings then TT:ApplySettings() end
    end
    local function UpdateAllWidgetStates() manager:UpdateAll(db.Enabled ~= false) end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Totem Tracker", yOffset)
    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        local TT = GetModule()
        if TT then
            if checked then KitnEssentials:EnableModule("TotemTracker")
            else KitnEssentials:DisableModule("TotemTracker") end
        end
        KE:Print("Totem Tracker: " .. (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
    end)

    yOffset = card1:GetNextOffset()

    -- Lone header bar: a disabled module shows its switch and nothing else.
    if db.Enabled == false then return yOffset end

    local cardPreview = GUIFrame:CreateCard(scrollChild, "Preview", yOffset)
    local rowPreview = GUIFrame:CreateRow(cardPreview.content, Theme.rowHeightLast)
    local previewBtn
    previewBtn = GUIFrame:CreateButton(rowPreview, "Show Preview", {
        height = 30,
        callback = function()
            local TT = GetModule()
            if TT and TT.TogglePreview then
                local isActive = TT:TogglePreview()
                previewBtn:SetLabel(isActive and "Hide Preview" or "Show Preview")
            end
        end,
    })
    rowPreview:AddWidget(previewBtn, 1)
    local TT = GetModule()
    if TT and TT.IsPreviewActive and TT:IsPreviewActive() then
        previewBtn:SetLabel("Hide Preview")
    end
    cardPreview:AddRow(rowPreview, Theme.rowHeightLast, 0)

    yOffset = cardPreview:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Destroy All Totems (Macro)
    ----------------------------------------------------------------
    local macroCard = GUIFrame:CreateCard(scrollChild, "Destroy All Totems", yOffset)

    local macroName = "!KEDestroyTotem"
    local macroIcon = "Boss_odunrunes_orange"
    local macroText =
        "/click KE_DestroyTotem1\n/click KE_DestroyTotem2\n/click KE_DestroyTotem3\n/click KE_DestroyTotem4\n/click KE_DestroyTotem5"

    local infoHeight = 36
    local infoRow = GUIFrame:CreateRow(macroCard.content, infoHeight)
    local infoText = GUIFrame:CreateText(infoRow,
        KE:ColorTextByTheme("Macro Info"),
        "Click the button below to create a macro that instantly destroys all active totems.",
        infoHeight, "hide")
    infoRow:AddWidget(infoText, 1)
    macroCard:AddRow(infoRow, infoHeight)

    local infoRowSep = GUIFrame:CreateRow(macroCard.content, Theme.rowHeightSeparator)
    local infoSep = GUIFrame:CreateSeparator(infoRowSep)
    infoRowSep:AddWidget(infoSep, 1)
    macroCard:AddRow(infoRowSep, Theme.rowHeightSeparator)

    local btnRow = GUIFrame:CreateRow(macroCard.content, Theme.rowHeightLast)
    local createBtn = GUIFrame:CreateButton(btnRow, "Create Macro", {
        height = 30,
        callback = function()
            if InCombatLockdown() then
                KE:Print("Cannot create macros during combat.")
                return
            end

            local existingIndex = GetMacroIndexByName(macroName)
            if existingIndex and existingIndex > 0 then
                KE:Print("Macro '" .. macroName .. "' already exists.")
                return
            end

            local numGlobal = GetNumMacros()
            if numGlobal >= MAX_ACCOUNT_MACROS then
                KE:Print("No free macro slots available.")
                return
            end

            CreateMacro(macroName, macroIcon, macroText, false)
            KE:Print("Macro '" .. macroName .. "' created! Drag it to your action bar.")
        end,
    })
    btnRow:AddWidget(createBtn, 1)
    macroCard:AddRow(btnRow, Theme.rowHeightLast, 0)

    yOffset = macroCard:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Position
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        db = db,
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
    -- Card 4: Timer Font
    ----------------------------------------------------------------
    local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        title = "Timer Font",
        db = db,
        dbKeys = {
            fontFace    = "FontFace",
            fontSize    = "TimerFontSize",
            fontOutline = "FontOutline",
        },
        fontSizeRange = { 8, 32 },
        includeSoftOutline = true,
        onChangeCallback = ApplySettings,
    })
    manager:Register(fontCard, "all")
    if fontWidgets then manager:RegisterGroup(fontWidgets, "all") end
    yOffset = fontOffset

    ----------------------------------------------------------------
    -- Card 5: Display Settings (Layout)
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Display Settings", yOffset)
    manager:Register(card5, "all")

    local row5a = GUIFrame:CreateRow(card5.content, Theme.rowHeight)
    local sizeSlider = GUIFrame:CreateSlider(row5a, "Icon Size", {
        min = 20, max = 200, step = 1,
        value = db.IconSize,
        callback = function(val) db.IconSize = val; ApplySettings() end,
    })
    row5a:AddWidget(sizeSlider, 0.5)
    manager:Register(sizeSlider, "all")

    local spacingSlider = GUIFrame:CreateSlider(row5a, "Icon Spacing", {
        min = -40, max = 20, step = 1,
        value = db.IconSpacing,
        callback = function(val) db.IconSpacing = val; ApplySettings() end,
    })
    row5a:AddWidget(spacingSlider, 0.5)
    manager:Register(spacingSlider, "all")
    card5:AddRow(row5a, Theme.rowHeight)

    local row5b = GUIFrame:CreateRow(card5.content, Theme.rowHeight)
    local showTimerCheck = GUIFrame:CreateCheckbox(row5b, "Show Timer", {
        value = db.ShowTimer,
        callback = function(checked)
            db.ShowTimer = checked
            ApplySettings()
            UpdateAllWidgetStates()
        end,
    })
    row5b:AddWidget(showTimerCheck, 0.5)
    manager:Register(showTimerCheck, "all")

    local growDropdown = GUIFrame:CreateDropdown(row5b, "Growth Direction", {
        options = {
            { key = "RIGHT", text = "Right" },
            { key = "LEFT",  text = "Left" },
            { key = "UP",    text = "Up" },
            { key = "DOWN",  text = "Down" },
        },
        value = db.GrowDirection,
        callback = function(key) db.GrowDirection = key; ApplySettings() end,
    })
    row5b:AddWidget(growDropdown, 0.5)
    manager:Register(growDropdown, "all")
    card5:AddRow(row5b, Theme.rowHeight)

    local row5c = GUIFrame:CreateRow(card5.content, Theme.rowHeight)
    local decimalSlider = GUIFrame:CreateSlider(row5c, "Show Decimals Below (sec)", {
        min = 0, max = 10, step = 1,
        value = db.DecimalThreshold,
        callback = function(val) db.DecimalThreshold = val; ApplySettings() end,
    })
    row5c:AddWidget(decimalSlider, 0.5)
    manager:Register(decimalSlider, "timerOn")
    card5:AddRow(row5c, Theme.rowHeight)

    local rowSep5 = GUIFrame:CreateRow(card5.content, Theme.rowHeightSeparator)
    local sep5 = GUIFrame:CreateSeparator(rowSep5)
    rowSep5:AddWidget(sep5, 1)
    manager:Register(sep5, "all")
    card5:AddRow(rowSep5, Theme.rowHeightSeparator)

    local rowSwipe = GUIFrame:CreateRow(card5.content, Theme.rowHeightLast)
    local swipeCheck = GUIFrame:CreateCheckbox(rowSwipe, "Enable Swipe", {
        value = db.Swipe,
        callback = function(checked)
            db.Swipe = checked
            ApplySettings()
            UpdateAllWidgetStates()
        end,
    })
    rowSwipe:AddWidget(swipeCheck, 0.5)
    manager:Register(swipeCheck, "all")

    local reverseCheck = GUIFrame:CreateCheckbox(rowSwipe, "Reverse Swipe", {
        value = db.Reverse,
        callback = function(checked) db.Reverse = checked; ApplySettings() end,
    })
    rowSwipe:AddWidget(reverseCheck, 0.5)
    manager:Register(reverseCheck, "swipeOn")
    card5:AddRow(rowSwipe, Theme.rowHeightLast, 0)

    yOffset = card5:GetNextOffset()

    UpdateAllWidgetStates()
    return yOffset
end)
