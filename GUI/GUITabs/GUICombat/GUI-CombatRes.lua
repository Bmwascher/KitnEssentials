-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-CombatRes.lua                                       ║
-- ║  GUI: Battle Res                                         ║
-- ║  Purpose: Configuration panel for the CombatRes module.  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

GUIFrame:RegisterContent("CombatRes", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.CombatRes
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    db.Backdrop = db.Backdrop or {}

    local manager = GUIFrame:CreateWidgetStateManager()
    manager:SetCondition("backdrop", function()
        return db.Backdrop and db.Backdrop.Enabled == true
    end)

    local function ApplySettings()
        if KitnEssentials then
            local mod = KitnEssentials:GetModule("CombatRes", true)
            if mod and mod.ApplySettings then mod:ApplySettings() end
        end
    end

    local function ApplyModuleState(enabled)
        if not KitnEssentials then return end
        local mod = KitnEssentials:GetModule("CombatRes", true)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("CombatRes")
        else
            KitnEssentials:DisableModule("CombatRes")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Combat Res Tracker", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Combat Res Tracker", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Combat Res Tracker",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, Theme.rowHeightLast, 0)

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
        showPixelSnap = true,
        onChangeCallback = ApplySettings,
    })

    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "all")
    end
    manager:Register(posCard, "all")
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 3: Format (Separator + Charge Prefix + Bracket Style)
    ----------------------------------------------------------------
    local cardFormat = GUIFrame:CreateCard(scrollChild, "Format", yOffset)
    manager:Register(cardFormat, "all")

    local rowF1 = GUIFrame:CreateRow(cardFormat.content, Theme.rowHeight)
    local sepInput = GUIFrame:CreateEditBox(rowF1, "Separator Character", {
        value = db.Separator or "|",
        callback = function(val) db.Separator = val; ApplySettings() end,
    })
    rowF1:AddWidget(sepInput, 0.5)
    manager:Register(sepInput, "all")

    local sepChargeInput = GUIFrame:CreateEditBox(rowF1, "Charge Prefix", {
        value = db.SeparatorCharges or "CR:",
        callback = function(val) db.SeparatorCharges = val; ApplySettings() end,
    })
    rowF1:AddWidget(sepChargeInput, 0.5)
    manager:Register(sepChargeInput, "all")
    cardFormat:AddRow(rowF1, Theme.rowHeight)

    local rowF2 = GUIFrame:CreateRow(cardFormat.content, Theme.rowHeightLast)
    local bracketDropdown = GUIFrame:CreateDropdown(rowF2, "Bracket Style", {
        options = {
            ["square"] = "[ ]",
            ["round"]  = "( )",
            ["none"]   = "None",
        },
        value = db.BracketStyle or "square",
        callback = function(key) db.BracketStyle = key; ApplySettings() end,
    })
    rowF2:AddWidget(bracketDropdown, 1)
    manager:Register(bracketDropdown, "all")
    cardFormat:AddRow(rowF2, Theme.rowHeightLast, 0)

    yOffset = cardFormat:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Font Settings (font + outline + size)
    ----------------------------------------------------------------
    local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
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
    manager:Register(fontCard, "all")
    if fontWidgets then
        manager:RegisterGroup(fontWidgets, "all")
    end
    yOffset = fontOffset

    ----------------------------------------------------------------
    -- Card 5: Layout (Text Spacing + Growth Direction)
    ----------------------------------------------------------------
    local cardLayout = GUIFrame:CreateCard(scrollChild, "Layout", yOffset)
    manager:Register(cardLayout, "all")

    local rowLayout = GUIFrame:CreateRow(cardLayout.content, Theme.rowHeightLast)
    local spacingSlider = GUIFrame:CreateSlider(rowLayout, "Text Spacing", {
        min = 0, max = 20, step = 1,
        value = db.TextSpacing or 4,
        callback = function(val) db.TextSpacing = val; ApplySettings() end,
    })
    rowLayout:AddWidget(spacingSlider, 0.5)
    manager:Register(spacingSlider, "all")

    local growthDropdown = GUIFrame:CreateDropdown(rowLayout, "Growth Direction", {
        options = {
            { key = "LEFT",  text = "Left" },
            { key = "RIGHT", text = "Right" },
        },
        value = db.GrowthDirection or "RIGHT",
        callback = function(key) db.GrowthDirection = key; ApplySettings() end,
    })
    rowLayout:AddWidget(growthDropdown, 0.5)
    manager:Register(growthDropdown, "all")
    cardLayout:AddRow(rowLayout, Theme.rowHeightLast, 0)

    yOffset = cardLayout:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 6: Colors
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    manager:Register(card4, "all")

    local row4a = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local sepColor = GUIFrame:CreateColorPicker(row4a, "Separator Color", {
        color = db.SeparatorColor or { 1, 1, 1, 1 },
        callback = function(r, g, b, a)
            db.SeparatorColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row4a:AddWidget(sepColor, 0.5)
    manager:Register(sepColor, "all")

    local timerColor = GUIFrame:CreateColorPicker(row4a, "Timer Text Color", {
        color = db.TimerColor or { 1, 1, 1, 1 },
        callback = function(r, g, b, a)
            db.TimerColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row4a:AddWidget(timerColor, 0.5)
    manager:Register(timerColor, "all")
    card4:AddRow(row4a, Theme.rowHeight)

    local row4b = GUIFrame:CreateRow(card4.content, Theme.rowHeightLast)
    local chargeAvailColor = GUIFrame:CreateColorPicker(row4b, "Charges Available", {
        color = db.ChargeAvailableColor or { 0.3, 1, 0.3, 1 },
        callback = function(r, g, b, a)
            db.ChargeAvailableColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row4b:AddWidget(chargeAvailColor, 0.5)
    manager:Register(chargeAvailColor, "all")

    local chargeUnavailColor = GUIFrame:CreateColorPicker(row4b, "Charges Unavailable", {
        color = db.ChargeUnavailableColor or { 1, 0.3, 0.3, 1 },
        callback = function(r, g, b, a)
            db.ChargeUnavailableColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row4b:AddWidget(chargeUnavailColor, 0.5)
    manager:Register(chargeUnavailColor, "all")
    card4:AddRow(row4b, Theme.rowHeightLast, 0)

    yOffset = card4:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 7: Backdrop
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Backdrop", yOffset)
    manager:Register(card5, "all")

    local row5a = GUIFrame:CreateRow(card5.content, Theme.rowHeight)
    local backdropCheck = GUIFrame:CreateCheckbox(row5a, "Enable Backdrop", {
        value = db.Backdrop.Enabled ~= false,
        callback = function(checked)
            db.Backdrop.Enabled = checked
            ApplySettings()
            RefreshStates()
        end,
    })
    row5a:AddWidget(backdropCheck, 1)
    manager:Register(backdropCheck, "all")
    card5:AddRow(row5a, Theme.rowHeight)

    local row5b = GUIFrame:CreateRow(card5.content, Theme.rowHeight)
    local bgWidth = GUIFrame:CreateSlider(row5b, "Width", {
        min = 1, max = 600, step = 1,
        value = db.Backdrop.bgWidth or 100,
        callback = function(val) db.Backdrop.bgWidth = val; ApplySettings() end,
    })
    row5b:AddWidget(bgWidth, 0.4)
    manager:Register(bgWidth, "backdrop")

    local bgHeight = GUIFrame:CreateSlider(row5b, "Height", {
        min = 1, max = 600, step = 1,
        value = db.Backdrop.bgHeight or 40,
        callback = function(val) db.Backdrop.bgHeight = val; ApplySettings() end,
    })
    row5b:AddWidget(bgHeight, 0.4)
    manager:Register(bgHeight, "backdrop")

    local bgColor = GUIFrame:CreateColorPicker(row5b, "Color", {
        color = db.Backdrop.Color or { 0, 0, 0, 0.6 },
        callback = function(r, g, b, a)
            db.Backdrop.Color = { r, g, b, a }
            ApplySettings()
        end,
    })
    row5b:AddWidget(bgColor, 0.2)
    manager:Register(bgColor, "backdrop")
    card5:AddRow(row5b, Theme.rowHeight)

    local row5sep = GUIFrame:CreateRow(card5.content, Theme.rowHeightSeparator)
    local sepBg = GUIFrame:CreateSeparator(row5sep)
    row5sep:AddWidget(sepBg, 1)
    manager:Register(sepBg, "backdrop")
    card5:AddRow(row5sep, Theme.rowHeightSeparator)

    local row5c = GUIFrame:CreateRow(card5.content, Theme.rowHeightLast)
    local borderSize = GUIFrame:CreateSlider(row5c, "Border Size", {
        min = 1, max = 10, step = 1,
        value = db.Backdrop.BorderSize or 1,
        callback = function(val) db.Backdrop.BorderSize = val; ApplySettings() end,
    })
    row5c:AddWidget(borderSize, 0.8)
    manager:Register(borderSize, "backdrop")

    local borderColor = GUIFrame:CreateColorPicker(row5c, "Border Color", {
        color = db.Backdrop.BorderColor or { 0, 0, 0, 1 },
        callback = function(r, g, b, a)
            db.Backdrop.BorderColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row5c:AddWidget(borderColor, 0.2)
    manager:Register(borderColor, "backdrop")
    card5:AddRow(row5c, Theme.rowHeightLast, 0)

    yOffset = card5:GetNextOffset()

    RefreshStates()
    return yOffset
end)
