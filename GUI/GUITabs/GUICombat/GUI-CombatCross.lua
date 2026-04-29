-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-CombatCross.lua                                     ║
-- ║  GUI: Player Crosshair                                   ║
-- ║  Purpose: Configuration panel for the CombatCross module.║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

GUIFrame:RegisterContent("CombatCross", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.CombatCross
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local CC = KitnEssentials and KitnEssentials:GetModule("CombatCross", true)

    local manager = GUIFrame:CreateWidgetStateManager()
    manager:SetCondition("customColor", function()
        return (db.ColorMode or "custom") == "custom"
    end)
    manager:SetCondition("rangeColor", function()
        return db.RangeColorMeleeEnabled == true or db.RangeColorRangedEnabled == true
    end)

    local function ApplySettings()
        if CC then CC:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not CC then return end
        CC.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("CombatCross")
        else
            KitnEssentials:DisableModule("CombatCross")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Combat Cross", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Combat Cross", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Combat Cross",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, Theme.rowHeight)

    local noteRow = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " This is a static crosshair overlay and will not adjust with camera panning.",
        Theme.rowHeight, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, Theme.rowHeight, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: General Settings (Size + Font Outline)
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "General Settings", yOffset)
    manager:Register(card2, "all")

    local row2 = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local thicknessSlider = GUIFrame:CreateSlider(row2, "Size", {
        min = 8, max = 72, step = 1,
        value = db.Thickness or 22,
        callback = function(val) db.Thickness = val; ApplySettings() end,
    })
    row2:AddWidget(thicknessSlider, 0.5)
    manager:Register(thicknessSlider, "all")

    local outlineCheck = GUIFrame:CreateCheckbox(row2, "Font Outline", {
        value = db.Outline ~= false,
        callback = function(checked) db.Outline = checked; ApplySettings() end,
    })
    row2:AddWidget(outlineCheck, 0.5)
    manager:Register(outlineCheck, "all")
    card2:AddRow(row2, Theme.rowHeightLast, 0)

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
        onChangeCallback = ApplySettings,
    })

    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "all")
    end
    manager:Register(posCard, "all")
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 4: Colors
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    manager:Register(card3, "all")

    local row3 = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local colorModeDropdown = GUIFrame:CreateDropdown(row3, "Color Mode", {
        options = KE.ColorModeOptions,
        value = db.ColorMode or "custom",
        callback = function(key)
            db.ColorMode = key
            ApplySettings()
            RefreshStates()
        end,
    })
    row3:AddWidget(colorModeDropdown, 0.5)
    manager:Register(colorModeDropdown, "all")

    local colorPicker = GUIFrame:CreateColorPicker(row3, "Custom Color", {
        color = db.Color or { 0, 1, 0.169, 1 },
        callback = function(r, g, b, a)
            db.Color = { r, g, b, a }
            ApplySettings()
        end,
    })
    row3:AddWidget(colorPicker, 0.5)
    manager:Register(colorPicker, "customColor")
    card3:AddRow(row3, Theme.rowHeightLast, 0)

    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 5: Range Warning (1×3: melee | ranged | color)
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Range Warning", yOffset)
    manager:Register(card4, "all")

    local row4a = GUIFrame:CreateRow(card4.content, Theme.rowHeightLast)
    local meleeRangeCheck = GUIFrame:CreateCheckbox(row4a, "Enable for melee specs", {
        value = db.RangeColorMeleeEnabled == true,
        callback = function(checked)
            db.RangeColorMeleeEnabled = checked
            ApplySettings()
            RefreshStates()
        end,
    })
    row4a:AddWidget(meleeRangeCheck, 1/3)
    manager:Register(meleeRangeCheck, "all")

    local rangedRangeCheck = GUIFrame:CreateCheckbox(row4a, "Enable for ranged specs", {
        value = db.RangeColorRangedEnabled == true,
        callback = function(checked)
            db.RangeColorRangedEnabled = checked
            ApplySettings()
            RefreshStates()
        end,
    })
    row4a:AddWidget(rangedRangeCheck, 1/3)
    manager:Register(rangedRangeCheck, "all")

    local outOfRangeColorPicker = GUIFrame:CreateColorPicker(row4a, "Out of Range Color", {
        color = db.OutOfRangeColor or { 1, 0, 0, 1 },
        callback = function(r, g, b, a)
            db.OutOfRangeColor = { r, g, b, a }
            if CC then CC.lastInRange = nil end
        end,
    })
    row4a:AddWidget(outOfRangeColorPicker, 1/3)
    manager:Register(outOfRangeColorPicker, "rangeColor")
    card4:AddRow(row4a, Theme.rowHeightLast, 0)

    yOffset = card4:GetNextOffset()

    RefreshStates()
    return yOffset
end)
