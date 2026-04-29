-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-TimeSpiral.lua                                      ║
-- ║  GUI: Time Spiral Tracker                                ║
-- ║  Purpose: Configuration panel for the TimeSpiral module. ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("TimeSpiral", true)
    end
    return nil
end

GUIFrame:RegisterContent("TimeSpiral", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.TimeSpiral
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local TSP = GetModule()
    local manager = GUIFrame:CreateWidgetStateManager()
    manager:SetCondition("glow",  function() return db.GlowEnabled ~= false end)
    manager:SetCondition("text",  function() return db.ShowText    ~= false end)
    manager:SetCondition("timer", function() return db.ShowTimer   ~= false end)

    local function ApplySettings()
        if TSP and TSP.ApplySettings then TSP:ApplySettings() end
    end

    local function ApplyPosition()
        if TSP and TSP.ApplyPosition then TSP:ApplyPosition() end
    end

    local function ApplyModuleState(enabled)
        if not TSP then return end
        TSP.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("TimeSpiral")
        else
            KitnEssentials:DisableModule("TimeSpiral")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Time Spiral Tracker", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Time Spiral Tracker", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Time Spiral Tracker",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 0.5)
    card1:AddRow(row1, Theme.rowHeight)

    local noteRow = GUIFrame:CreateRow(card1.content, 50)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Works for all classes.\n" ..
        KE:ColorTextByTheme("-") .. " Tracks when your movement ability is available for free use from the Time Spiral buff.",
        50, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, 50, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Display & Glow Settings
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Display & Glow Settings", yOffset)
    manager:Register(card2, "all")

    local row2a = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local iconSizeSlider = GUIFrame:CreateSlider(row2a, "Icon Size", {
        min = 20, max = 100, step = 1,
        value = db.IconSize or 40,
        callback = function(val) db.IconSize = val; ApplySettings() end,
    })
    row2a:AddWidget(iconSizeSlider, 1)
    manager:Register(iconSizeSlider, "all")
    card2:AddRow(row2a, Theme.rowHeight)

    local rowSep = GUIFrame:CreateRow(card2.content, Theme.rowHeightSeparator)
    local sep1 = GUIFrame:CreateSeparator(rowSep)
    rowSep:AddWidget(sep1, 1)
    manager:Register(sep1, "all")
    card2:AddRow(rowSep, Theme.rowHeightSeparator)

    local row2b = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local enableGlowCheck = GUIFrame:CreateCheckbox(row2b, "Enable Glow Effect", {
        value = db.GlowEnabled ~= false,
        callback = function(checked)
            db.GlowEnabled = checked
            ApplySettings()
            RefreshStates()
        end,
    })
    row2b:AddWidget(enableGlowCheck, 0.5)
    manager:Register(enableGlowCheck, "all")
    card2:AddRow(row2b, Theme.rowHeight)

    local row2c = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local glowTypeDropdown = GUIFrame:CreateDropdown(row2c, "Glow Type", {
        options = {
            { key = "pixel",    text = "Pixel Border" },
            { key = "autocast", text = "Auto Cast" },
            { key = "button",   text = "Button Glow" },
            { key = "proc",     text = "Proc Glow" },
        },
        value = db.GlowType or "proc",
        callback = function(key) db.GlowType = key; ApplySettings() end,
    })
    row2c:AddWidget(glowTypeDropdown, 0.5)
    manager:Register(glowTypeDropdown, "glow")

    local glowColorPicker = GUIFrame:CreateColorPicker(row2c, "Glow Color", {
        color = db.GlowColor or { 0, 1, 0, 1 },
        callback = function(r, g, b, a)
            db.GlowColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row2c:AddWidget(glowColorPicker, 0.5)
    manager:Register(glowColorPicker, "glow")
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
        showPixelSnap = true,
        onChangeCallback = ApplyPosition,
    })

    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "all")
    end
    manager:Register(posCard, "all")
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 4: Label Text
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Label Text", yOffset)
    manager:Register(card4, "all")

    local row4a = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local showTextCheck = GUIFrame:CreateCheckbox(row4a, "Show Text Label", {
        value = db.ShowText ~= false,
        callback = function(checked)
            db.ShowText = checked
            ApplySettings()
            RefreshStates()
        end,
    })
    row4a:AddWidget(showTextCheck, 0.5)
    manager:Register(showTextCheck, "all")

    local textColorPicker = GUIFrame:CreateColorPicker(row4a, "Text Color", {
        color = db.TextColor or { 0, 1, 0, 1 },
        callback = function(r, g, b, a)
            db.TextColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row4a:AddWidget(textColorPicker, 0.5)
    manager:Register(textColorPicker, "text")
    card4:AddRow(row4a, Theme.rowHeight)

    local row4b = GUIFrame:CreateRow(card4.content, Theme.rowHeightLast)
    local textLabelEdit = GUIFrame:CreateEditBox(row4b, "Text Label", {
        value = db.TextLabel or "FREE",
        callback = function(text) db.TextLabel = text; ApplySettings() end,
    })
    row4b:AddWidget(textLabelEdit, 1)
    manager:Register(textLabelEdit, "text")
    card4:AddRow(row4b, Theme.rowHeightLast, 0)

    yOffset = card4:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Label Font
    ----------------------------------------------------------------
    local labelFontCard, labelFontOffset, labelFontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        title = "Label Font",
        db = db,
        dbKeys = {
            fontFace = "FontFace",
            fontSize = "FontSize",
            fontOutline = "FontOutline",
        },
        fontSizeRange = { 8, 36 },
        includeSoftOutline = true,
        onChangeCallback = ApplySettings,
    })
    manager:Register(labelFontCard, "text")
    if labelFontWidgets then
        manager:RegisterGroup(labelFontWidgets, "text")
    end
    yOffset = labelFontOffset

    ----------------------------------------------------------------
    -- Card 6: Timer Display
    ----------------------------------------------------------------
    local card6 = GUIFrame:CreateCard(scrollChild, "Timer Display", yOffset)
    manager:Register(card6, "all")

    local row6 = GUIFrame:CreateRow(card6.content, Theme.rowHeightLast)
    local showTimerCheck = GUIFrame:CreateCheckbox(row6, "Show Countdown Timer", {
        value = db.ShowTimer ~= false,
        callback = function(checked)
            db.ShowTimer = checked
            ApplySettings()
            RefreshStates()
        end,
    })
    row6:AddWidget(showTimerCheck, 0.5)
    manager:Register(showTimerCheck, "all")

    local timerColorPicker = GUIFrame:CreateColorPicker(row6, "Timer Color", {
        color = db.TimerTextColor or { 1, 1, 1, 1 },
        callback = function(r, g, b, a)
            db.TimerTextColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row6:AddWidget(timerColorPicker, 0.5)
    manager:Register(timerColorPicker, "timer")
    card6:AddRow(row6, Theme.rowHeightLast, 0)

    yOffset = card6:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 7: Timer Font
    ----------------------------------------------------------------
    local timerFontCard, timerFontOffset, timerFontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        title = "Timer Font",
        db = db,
        dbKeys = {
            fontFace = "TimerFontFace",
            fontSize = "TimerFontSize",
            fontOutline = "TimerFontOutline",
        },
        fontSizeRange = { 8, 36 },
        includeSoftOutline = true,
        onChangeCallback = ApplySettings,
    })
    manager:Register(timerFontCard, "timer")
    if timerFontWidgets then
        manager:RegisterGroup(timerFontWidgets, "timer")
    end
    yOffset = timerFontOffset

    RefreshStates()
    return yOffset
end)
