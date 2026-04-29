-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-CombatTexts.lua                                     ║
-- ║  GUI: Combat Texts                                       ║
-- ║  Purpose: Configuration panel for the CombatTexts module.║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

GUIFrame:RegisterContent("CombatTexts", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.CombatTexts
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
    manager:SetCondition("combatMsg", function()
        return db.EnterEnabled ~= false
    end)
    manager:SetCondition("noTarget", function()
        return db.NoTargetEnabled == true
    end)
    manager:SetCondition("durability", function()
        return db.DurabilityEnabled ~= false
    end)
    manager:SetCondition("interrupt", function()
        return db.InterruptEnabled ~= false
    end)

    local function ApplySettings()
        if KitnEssentials then
            local mod = KitnEssentials:GetModule("CombatTexts", true)
            if mod and mod.ApplySettings then mod:ApplySettings() end
        end
    end

    local function ApplyModuleState(enabled)
        if not KitnEssentials then return end
        local mod = KitnEssentials:GetModule("CombatTexts", true)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("CombatTexts")
        else
            KitnEssentials:DisableModule("CombatTexts")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Combat Texts", yOffset)

    local row1a = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local enableCheck = GUIFrame:CreateCheckbox(row1a, "Enable Combat Texts", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Combat Texts",
        msgOn = "On",
        msgOff = "Off",
    })
    row1a:AddWidget(enableCheck, 1)
    card1:AddRow(row1a, Theme.rowHeightLast, 0)

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
    -- Card 3: Font Settings (Font Size shares row with Message Spacing)
    ----------------------------------------------------------------
    local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        db = db,
        dbKeys = {
            fontFace = "FontFace",
            fontSize = "FontSize",
            fontOutline = "FontOutline",
        },
        includeSoftOutline = true,
        extraSlider = {
            label = "Message Spacing",
            dbKey = "Spacing",
            min = 0, max = 20, step = 1,
            default = 4,
        },
        onChangeCallback = ApplySettings,
    })
    manager:Register(fontCard, "all")
    if fontWidgets then
        manager:RegisterGroup(fontWidgets, "all")
    end
    yOffset = fontOffset

    ----------------------------------------------------------------
    -- Card 4: Combat Messages (Enter + Exit)
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Combat Messages", yOffset)
    manager:Register(card4, "all")

    local row4en = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local combatEnableCheck = GUIFrame:CreateCheckbox(row4en, "Enabled", {
        value = db.EnterEnabled ~= false,
        callback = function(checked)
            db.EnterEnabled = checked
            db.ExitEnabled = checked
            ApplySettings()
            RefreshStates()
        end,
    })
    row4en:AddWidget(combatEnableCheck, 1)
    manager:Register(combatEnableCheck, "all")
    card4:AddRow(row4en, Theme.rowHeight)

    local row4sep1 = GUIFrame:CreateRow(card4.content, Theme.rowHeightSeparator)
    local sep4a = GUIFrame:CreateSeparator(row4sep1)
    row4sep1:AddWidget(sep4a, 1)
    manager:Register(sep4a, "combatMsg")
    card4:AddRow(row4sep1, Theme.rowHeightSeparator)

    local row4enter = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local enterColorPicker = GUIFrame:CreateColorPicker(row4enter, "Enter Color", {
        color = db.EnterColor or { 1, 0.1, 0.1, 1 },
        callback = function(r, g, b, a)
            db.EnterColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row4enter:AddWidget(enterColorPicker, 0.3)
    manager:Register(enterColorPicker, "combatMsg")

    local enterTextInput = GUIFrame:CreateEditBox(row4enter, "Enter Text", {
        value = db.EnterCombatText or "+ Combat",
        callback = function(val) db.EnterCombatText = val; ApplySettings() end,
    })
    row4enter:AddWidget(enterTextInput, 0.7)
    manager:Register(enterTextInput, "combatMsg")
    card4:AddRow(row4enter, Theme.rowHeight)

    local row4exit = GUIFrame:CreateRow(card4.content, Theme.rowHeight)
    local exitColorPicker = GUIFrame:CreateColorPicker(row4exit, "Exit Color", {
        color = db.ExitColor or { 0.1, 1, 0.1, 1 },
        callback = function(r, g, b, a)
            db.ExitColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row4exit:AddWidget(exitColorPicker, 0.3)
    manager:Register(exitColorPicker, "combatMsg")

    local exitTextInput = GUIFrame:CreateEditBox(row4exit, "Exit Text", {
        value = db.ExitCombatText or "- Combat",
        callback = function(val) db.ExitCombatText = val; ApplySettings() end,
    })
    row4exit:AddWidget(exitTextInput, 0.7)
    manager:Register(exitTextInput, "combatMsg")
    card4:AddRow(row4exit, Theme.rowHeight)

    local row4sep2 = GUIFrame:CreateRow(card4.content, Theme.rowHeightSeparator)
    local sep4b = GUIFrame:CreateSeparator(row4sep2)
    row4sep2:AddWidget(sep4b, 1)
    manager:Register(sep4b, "combatMsg")
    card4:AddRow(row4sep2, Theme.rowHeightSeparator)

    local row4dur = GUIFrame:CreateRow(card4.content, Theme.rowHeightLast)
    local combatDurationSlider = GUIFrame:CreateSlider(row4dur, "Fade Duration", {
        min = 0.5, max = 5.0, step = 0.1,
        value = db.CombatDuration or 1.5,
        callback = function(val) db.CombatDuration = val; ApplySettings() end,
    })
    row4dur:AddWidget(combatDurationSlider, 1)
    manager:Register(combatDurationSlider, "combatMsg")
    card4:AddRow(row4dur, Theme.rowHeightLast, 0)

    yOffset = card4:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: No Target Warning
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "No Target Warning", yOffset)
    manager:Register(card5, "all")

    local row5nt = GUIFrame:CreateRow(card5.content, Theme.rowHeightLast)
    local noTargetEnableCheck = GUIFrame:CreateCheckbox(row5nt, "Enabled", {
        value = db.NoTargetEnabled == true,
        callback = function(checked)
            db.NoTargetEnabled = checked
            ApplySettings()
            RefreshStates()
        end,
    })
    row5nt:AddWidget(noTargetEnableCheck, 0.2)
    manager:Register(noTargetEnableCheck, "all")

    local noTargetColorPicker = GUIFrame:CreateColorPicker(row5nt, "Color", {
        color = db.NoTargetColor or { 1, 0.8, 0, 1 },
        callback = function(r, g, b, a)
            db.NoTargetColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row5nt:AddWidget(noTargetColorPicker, 0.3)
    manager:Register(noTargetColorPicker, "noTarget")

    local noTargetTextInput = GUIFrame:CreateEditBox(row5nt, "Text", {
        value = db.NoTargetText or "NO TARGET",
        callback = function(val) db.NoTargetText = val; ApplySettings() end,
    })
    row5nt:AddWidget(noTargetTextInput, 0.5)
    manager:Register(noTargetTextInput, "noTarget")
    card5:AddRow(row5nt, Theme.rowHeightLast)

    local row5note = GUIFrame:CreateRow(card5.content, Theme.rowHeight)
    local note5 = GUIFrame:CreateText(row5note,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Shows persistent warning when in combat with no target selected.",
        Theme.rowHeight, "hide")
    row5note:AddWidget(note5, 1)
    manager:Register(note5, "noTarget")
    card5:AddRow(row5note, Theme.rowHeight, 0)

    yOffset = card5:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 6: Interrupt Text
    ----------------------------------------------------------------
    local card6 = GUIFrame:CreateCard(scrollChild, "Interrupt Text", yOffset)
    manager:Register(card6, "all")

    local row6a = GUIFrame:CreateRow(card6.content, Theme.rowHeight)
    local intEnableCheck = GUIFrame:CreateCheckbox(row6a, "Enabled", {
        value = db.InterruptEnabled ~= false,
        callback = function(checked)
            db.InterruptEnabled = checked
            ApplySettings()
            RefreshStates()
        end,
    })
    row6a:AddWidget(intEnableCheck, 0.2)
    manager:Register(intEnableCheck, "all")

    local intColorPicker = GUIFrame:CreateColorPicker(row6a, "Color", {
        color = db.InterruptColor or { 1, 1, 1, 1 },
        callback = function(r, g, b, a)
            db.InterruptColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row6a:AddWidget(intColorPicker, 0.3)
    manager:Register(intColorPicker, "interrupt")

    local intTextInput = GUIFrame:CreateEditBox(row6a, "Text", {
        value = db.InterruptText or "Interrupted",
        callback = function(val) db.InterruptText = val; ApplySettings() end,
    })
    row6a:AddWidget(intTextInput, 0.5)
    manager:Register(intTextInput, "interrupt")
    card6:AddRow(row6a, Theme.rowHeight)

    local row6sep = GUIFrame:CreateRow(card6.content, Theme.rowHeightSeparator)
    local sep6 = GUIFrame:CreateSeparator(row6sep)
    row6sep:AddWidget(sep6, 1)
    manager:Register(sep6, "interrupt")
    card6:AddRow(row6sep, Theme.rowHeightSeparator)

    local row6b = GUIFrame:CreateRow(card6.content, Theme.rowHeightLast)
    local intDurationSlider = GUIFrame:CreateSlider(row6b, "Fade Duration", {
        min = 0.5, max = 8.0, step = 0.1,
        value = db.InterruptDuration or 3.0,
        callback = function(val) db.InterruptDuration = val; ApplySettings() end,
    })
    row6b:AddWidget(intDurationSlider, 1)
    manager:Register(intDurationSlider, "interrupt")
    card6:AddRow(row6b, Theme.rowHeightLast)

    local row6note = GUIFrame:CreateRow(card6.content, Theme.rowHeight)
    local note6 = GUIFrame:CreateText(row6note,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Displays [text] [spell icon] [spell name] on successful interrupt.",
        Theme.rowHeight, "hide")
    row6note:AddWidget(note6, 1)
    manager:Register(note6, "interrupt")
    card6:AddRow(row6note, Theme.rowHeight, 0)

    yOffset = card6:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 7: Low Durability Warning
    ----------------------------------------------------------------
    local card7 = GUIFrame:CreateCard(scrollChild, "Low Durability Warning", yOffset)
    manager:Register(card7, "all")

    local row7a = GUIFrame:CreateRow(card7.content, Theme.rowHeight)
    local durabilityEnableCheck = GUIFrame:CreateCheckbox(row7a, "Enabled", {
        value = db.DurabilityEnabled ~= false,
        callback = function(checked)
            db.DurabilityEnabled = checked
            ApplySettings()
            RefreshStates()
        end,
    })
    row7a:AddWidget(durabilityEnableCheck, 0.2)
    manager:Register(durabilityEnableCheck, "all")

    local durabilityColorPicker = GUIFrame:CreateColorPicker(row7a, "Color", {
        color = db.DurabilityColor or { 1, 0.3, 0.3, 1 },
        callback = function(r, g, b, a)
            db.DurabilityColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row7a:AddWidget(durabilityColorPicker, 0.3)
    manager:Register(durabilityColorPicker, "durability")

    local durabilityTextInput = GUIFrame:CreateEditBox(row7a, "Text", {
        value = db.DurabilityText or "LOW DURABILITY",
        callback = function(val) db.DurabilityText = val; ApplySettings() end,
    })
    row7a:AddWidget(durabilityTextInput, 0.5)
    manager:Register(durabilityTextInput, "durability")
    card7:AddRow(row7a, Theme.rowHeight)

    local row7sep = GUIFrame:CreateRow(card7.content, Theme.rowHeightSeparator)
    local sep7 = GUIFrame:CreateSeparator(row7sep)
    row7sep:AddWidget(sep7, 1)
    manager:Register(sep7, "durability")
    card7:AddRow(row7sep, Theme.rowHeightSeparator)

    local row7b = GUIFrame:CreateRow(card7.content, Theme.rowHeightLast)
    local thresholdSlider = GUIFrame:CreateSlider(row7b, "Durability Threshold (%)", {
        min = 5, max = 50, step = 1,
        value = db.DurabilityThreshold or 25,
        callback = function(val) db.DurabilityThreshold = val; ApplySettings() end,
    })
    row7b:AddWidget(thresholdSlider, 1)
    manager:Register(thresholdSlider, "durability")
    card7:AddRow(row7b, Theme.rowHeightLast, 0)

    yOffset = card7:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 8: Backdrop
    ----------------------------------------------------------------
    local card8 = GUIFrame:CreateCard(scrollChild, "Backdrop", yOffset)
    manager:Register(card8, "all")

    local row8a = GUIFrame:CreateRow(card8.content, Theme.rowHeight)
    local backdropCheck = GUIFrame:CreateCheckbox(row8a, "Enable Backdrop", {
        value = db.Backdrop.Enabled ~= false,
        callback = function(checked)
            db.Backdrop.Enabled = checked
            ApplySettings()
            RefreshStates()
        end,
    })
    row8a:AddWidget(backdropCheck, 1)
    manager:Register(backdropCheck, "all")
    card8:AddRow(row8a, Theme.rowHeight)

    local row8b = GUIFrame:CreateRow(card8.content, Theme.rowHeight)
    local bgWidth = GUIFrame:CreateSlider(row8b, "Width", {
        min = 1, max = 600, step = 1,
        value = db.Backdrop.bgWidth or 100,
        callback = function(val) db.Backdrop.bgWidth = val; ApplySettings() end,
    })
    row8b:AddWidget(bgWidth, 0.4)
    manager:Register(bgWidth, "backdrop")

    local bgHeight = GUIFrame:CreateSlider(row8b, "Height", {
        min = 1, max = 600, step = 1,
        value = db.Backdrop.bgHeight or 40,
        callback = function(val) db.Backdrop.bgHeight = val; ApplySettings() end,
    })
    row8b:AddWidget(bgHeight, 0.4)
    manager:Register(bgHeight, "backdrop")

    local bgColor = GUIFrame:CreateColorPicker(row8b, "Color", {
        color = db.Backdrop.Color or { 0, 0, 0, 0.6 },
        callback = function(r, g, b, a)
            db.Backdrop.Color = { r, g, b, a }
            ApplySettings()
        end,
    })
    row8b:AddWidget(bgColor, 0.2)
    manager:Register(bgColor, "backdrop")
    card8:AddRow(row8b, Theme.rowHeight)

    local row8sep = GUIFrame:CreateRow(card8.content, Theme.rowHeightSeparator)
    local sepBg = GUIFrame:CreateSeparator(row8sep)
    row8sep:AddWidget(sepBg, 1)
    manager:Register(sepBg, "backdrop")
    card8:AddRow(row8sep, Theme.rowHeightSeparator)

    local row8c = GUIFrame:CreateRow(card8.content, Theme.rowHeightLast)
    local borderSize = GUIFrame:CreateSlider(row8c, "Border Size", {
        min = 1, max = 10, step = 1,
        value = db.Backdrop.BorderSize or 1,
        callback = function(val) db.Backdrop.BorderSize = val; ApplySettings() end,
    })
    row8c:AddWidget(borderSize, 0.8)
    manager:Register(borderSize, "backdrop")

    local borderColor = GUIFrame:CreateColorPicker(row8c, "Border Color", {
        color = db.Backdrop.BorderColor or { 0, 0, 0, 1 },
        callback = function(r, g, b, a)
            db.Backdrop.BorderColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row8c:AddWidget(borderColor, 0.2)
    manager:Register(borderColor, "backdrop")
    card8:AddRow(row8c, Theme.rowHeightLast, 0)

    yOffset = card8:GetNextOffset()

    RefreshStates()
    return yOffset
end)
