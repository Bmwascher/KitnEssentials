-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-NoMovementAlert.lua                                 ║
-- ║  GUI: No Movement Alert                                  ║
-- ║  Purpose: Configuration panel for the NoMovementAlert    ║
-- ║  module.                                                 ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("NoMovementAlert", true)
    end
    return nil
end

GUIFrame:RegisterContent("NoMovementAlert", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.NoMovementAlert
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local mod = GetModule()
    local manager = GUIFrame:CreateWidgetStateManager()
    manager:SetCondition("customColor", function()
        return (db.ColorMode or "custom") == "custom"
    end)

    local function ApplySettings()
        if mod and mod.ApplySettings then mod:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("NoMovementAlert")
        else
            KitnEssentials:DisableModule("NoMovementAlert")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "No Movement Alert", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable No Movement Alert", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "No Movement Alert",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, Theme.rowHeight)

    local noteRow = GUIFrame:CreateRow(card1.content, 50)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Shows remaining cooldown when your movement ability is unavailable.\n" ..
        KE:ColorTextByTheme("-") .. " Supports all classes. Auto-detects your highest priority movement spell.",
        50, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, 50, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Alert Settings
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Alert Settings", yOffset)
    manager:Register(card2, "all")

    local row2a = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local formatBox = GUIFrame:CreateEditBox(row2a, "Display Format", {
        value = db.DisplayFormat or "NO %n (%t)",
        callback = function(text) db.DisplayFormat = text; ApplySettings() end,
    })
    row2a:AddWidget(formatBox, 1)
    manager:Register(formatBox, "all")
    card2:AddRow(row2a, Theme.rowHeight)

    local row2note = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local note2 = GUIFrame:CreateText(row2note,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " %n = spell name, %t = remaining time.",
        Theme.rowHeight, "hide")
    row2note:AddWidget(note2, 1)
    manager:Register(note2, "all")
    card2:AddRow(row2note, Theme.rowHeight)

    local row2sep = GUIFrame:CreateRow(card2.content, Theme.rowHeightSeparator)
    local sep2 = GUIFrame:CreateSeparator(row2sep)
    row2sep:AddWidget(sep2, 1)
    manager:Register(sep2, "all")
    card2:AddRow(row2sep, Theme.rowHeightSeparator)

    local row2b = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local maxCDSlider = GUIFrame:CreateSlider(row2b, "Max Cooldown", {
        min = 5, max = 120, step = 1,
        value = db.MaxCooldown or 30,
        callback = function(val) db.MaxCooldown = val end,
    })
    row2b:AddWidget(maxCDSlider, 1)
    manager:Register(maxCDSlider, "all")
    card2:AddRow(row2b, Theme.rowHeight)

    local row2cdnote = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local cdnote = GUIFrame:CreateText(row2cdnote,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Only show alert when the spell's total cooldown is under this threshold (seconds).",
        Theme.rowHeight, "hide")
    row2cdnote:AddWidget(cdnote, 1)
    manager:Register(cdnote, "all")
    card2:AddRow(row2cdnote, Theme.rowHeight, 0)

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
        onChangeCallback = ApplySettings,
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
        includeSoftOutline = true,
        onChangeCallback = ApplySettings,
    })
    manager:Register(fontCard, "all")
    if fontWidgets then
        manager:RegisterGroup(fontWidgets, "all")
    end
    yOffset = fontOffset

    ----------------------------------------------------------------
    -- Card 5: Colors
    ----------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    manager:Register(card5, "all")

    local row5 = GUIFrame:CreateRow(card5.content, Theme.rowHeightLast)
    local colorModeDropdown = GUIFrame:CreateDropdown(row5, "Color Mode", {
        options = KE.ColorModeOptions,
        value = db.ColorMode or "custom",
        callback = function(key)
            db.ColorMode = key
            ApplySettings()
            RefreshStates()
        end,
    })
    row5:AddWidget(colorModeDropdown, 0.5)
    manager:Register(colorModeDropdown, "all")

    local colorPicker = GUIFrame:CreateColorPicker(row5, "Custom Color", {
        color = db.Color or { 1, 0.2, 0.2, 1 },
        callback = function(r, g, b, a)
            db.Color = { r, g, b, a }
            ApplySettings()
        end,
    })
    row5:AddWidget(colorPicker, 0.5)
    manager:Register(colorPicker, "customColor")
    card5:AddRow(row5, Theme.rowHeightLast, 0)

    yOffset = card5:GetNextOffset()

    RefreshStates()
    return yOffset
end)
