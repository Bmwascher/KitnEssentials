-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-DisintegrateTicks.lua                               ║
-- ║  GUI: Disintegrate Ticks                                 ║
-- ║  Purpose: Configuration panel for the DisintegrateTicks  ║
-- ║  module.                                                 ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("DisintegrateTicks", true)
    end
    return nil
end

GUIFrame:RegisterContent("DisintegrateTicks", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.DisintegrateTicks
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    if not db.ClipWarning then db.ClipWarning = {} end

    local DT = GetModule()
    local manager = GUIFrame:CreateWidgetStateManager()
    manager:SetCondition("clip", function()
        return db.ClipWarning and db.ClipWarning.Enabled ~= false
    end)

    local function ApplySettings()
        if DT and DT.ApplySettings then DT:ApplySettings() end
    end

    local function ApplyPosition()
        if DT and DT.ApplyPosition then DT:ApplyPosition() end
    end

    local function ApplyModuleState(enabled)
        if not DT then return end
        DT.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("DisintegrateTicks")
        else
            KitnEssentials:DisableModule("DisintegrateTicks")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Disintegrate Ticks", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Disintegrate Ticks", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Disintegrate Ticks",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 0.5)
    card1:AddRow(row1, Theme.rowHeight)

    local noteRow = GUIFrame:CreateRow(card1.content, 50)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Evoker only (Devastation / Preservation).\n" ..
        KE:ColorTextByTheme("-") .. " Displays tick marks on your cast bar during Disintegrate channels.",
        50, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, 50, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Tick Settings
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Tick Settings", yOffset)
    manager:Register(card2, "all")

    local row2 = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local tickColorPicker = GUIFrame:CreateColorPicker(row2, "Tick Color", {
        color = db.TickColor or { 1, 1, 1, 0.8 },
        callback = function(r, g, b, a)
            db.TickColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row2:AddWidget(tickColorPicker, 0.5)
    manager:Register(tickColorPicker, "all")

    local tickWidthSlider = GUIFrame:CreateSlider(row2, "Tick Width", {
        min = 1, max = 6, step = 1,
        value = db.TickWidth or 2,
        callback = function(val) db.TickWidth = val; ApplySettings() end,
    })
    row2:AddWidget(tickWidthSlider, 0.5)
    manager:Register(tickWidthSlider, "all")
    card2:AddRow(row2, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Mass Disintegrate Clip Warning
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Mass Disintegrate Clip Warning", yOffset)
    manager:Register(card3, "all")

    local row3a = GUIFrame:CreateRow(card3.content, Theme.rowHeight)
    local clipEnableCheck = GUIFrame:CreateCheckbox(row3a, "Enable Clip Warning", {
        value = db.ClipWarning.Enabled ~= false,
        callback = function(checked)
            db.ClipWarning.Enabled = checked
            ApplySettings()
            RefreshStates()
        end,
    })
    row3a:AddWidget(clipEnableCheck, 0.5)
    manager:Register(clipEnableCheck, "all")

    local clipColorPicker = GUIFrame:CreateColorPicker(row3a, "Warning Color", {
        color = db.ClipWarning.Color or { 1, 0, 0, 1 },
        callback = function(r, g, b, a)
            db.ClipWarning.Color = { r, g, b, a }
            ApplySettings()
        end,
    })
    row3a:AddWidget(clipColorPicker, 0.5)
    manager:Register(clipColorPicker, "clip")
    card3:AddRow(row3a, Theme.rowHeight)

    local row3b = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local clipTextEdit = GUIFrame:CreateEditBox(row3b, "Warning Text", {
        value = db.ClipWarning.Text or "DON'T CLIP",
        callback = function(text)
            db.ClipWarning.Text = text
            ApplySettings()
        end,
    })
    row3b:AddWidget(clipTextEdit, 1)
    manager:Register(clipTextEdit, "clip")
    card3:AddRow(row3b, Theme.rowHeightLast, 0)

    yOffset = card3:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 4: Warning Position
    ----------------------------------------------------------------
    local posCard, posOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
        title = "Warning Position",
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
        manager:RegisterGroup(posCard.positionWidgets, "clip")
    end
    manager:Register(posCard, "clip")
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 5: Warning Font Settings
    ----------------------------------------------------------------
    local fontCard, fontOffset, fontWidgets = GUIFrame:CreateFontSettingsCard(scrollChild, yOffset, {
        title = "Warning Font Settings",
        db = db,
        dbKeys = {
            fontFace = "ClipWarning.FontFace",
            fontSize = "ClipWarning.FontSize",
            fontOutline = "ClipWarning.FontOutline",
        },
        fontSizeRange = { 8, 36 },
        includeSoftOutline = true,
        onChangeCallback = ApplySettings,
    })
    manager:Register(fontCard, "clip")
    if fontWidgets then
        manager:RegisterGroup(fontWidgets, "clip")
    end
    yOffset = fontOffset

    RefreshStates()
    return yOffset
end)
