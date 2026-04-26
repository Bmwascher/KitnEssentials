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
local LSM = KE.LSM or LibStub("LibSharedMedia-3.0", true)

local table_insert = table.insert
local pairs, ipairs = pairs, ipairs

local function GetModule()
    return KitnEssentials:GetModule("DisintegrateTicks", true)
end

GUIFrame:RegisterContent("DisintegrateTicks", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.DisintegrateTicks
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return yOffset + errorCard:GetContentHeight() + Theme.paddingMedium
    end

    local DT = GetModule()
    local allWidgets = {}
    local clipWidgets = {}

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

    local function UpdateClipWidgetStates()
        local cw = db.ClipWarning or {}
        local clipEnabled = cw.Enabled ~= false
        for _, widget in ipairs(clipWidgets) do
            if widget.SetEnabled then widget:SetEnabled(clipEnabled) end
        end
    end

    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false
        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then widget:SetEnabled(mainEnabled) end
        end
        if mainEnabled then
            UpdateClipWidgetStates()
        end
    end

    ---------------------------------------------------------------------------------
    -- Card 1: Enable
    ---------------------------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Disintegrate Ticks", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Disintegrate Ticks", db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            UpdateAllWidgetStates()
        end,
        true, "Disintegrate Ticks", "On", "Off"
    )
    row1:AddWidget(enableCheck, 0.5)
    card1:AddRow(row1, 36)

    -- Note
    local noteHeight = 50
    local noteRow = GUIFrame:CreateRow(card1.content, noteHeight)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Evoker only (Devastation / Preservation).\n" .. KE:ColorTextByTheme("-") .. " Displays tick marks on your cast bar during Disintegrate channels.",
        noteHeight, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, noteHeight)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 2: Tick Settings
    ---------------------------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Tick Settings", yOffset)
    table_insert(allWidgets, card2)

    -- Tick Color + Tick Width
    local row2a = GUIFrame:CreateRow(card2.content, 40)
    local tickColorPicker = GUIFrame:CreateColorPicker(row2a, "Tick Color",
        db.TickColor or { 1, 1, 1, 0.8 },
        function(r, g, b, a)
            db.TickColor = { r, g, b, a }
            ApplySettings()
        end)
    row2a:AddWidget(tickColorPicker, 0.5)
    table_insert(allWidgets, tickColorPicker)

    local tickWidthSlider = GUIFrame:CreateSlider(row2a, "Tick Width", 1, 6, 1,
        db.TickWidth or 2, nil,
        function(val)
            db.TickWidth = val
            ApplySettings()
        end)
    row2a:AddWidget(tickWidthSlider, 0.5)
    table_insert(allWidgets, tickWidthSlider)
    card2:AddRow(row2a, 40)

    yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 3: Clip Warning
    ---------------------------------------------------------------------------------
    local cw = db.ClipWarning or {}
    local card3 = GUIFrame:CreateCard(scrollChild, "Mass Disintegrate Clip Warning", yOffset)
    table_insert(allWidgets, card3)

    -- Enable clip warning
    local row3a = GUIFrame:CreateRow(card3.content, 40)
    local clipEnableCheck = GUIFrame:CreateCheckbox(row3a, "Enable Clip Warning", cw.Enabled ~= false,
        function(checked)
            if not db.ClipWarning then db.ClipWarning = {} end
            db.ClipWarning.Enabled = checked
            UpdateClipWidgetStates()
            ApplySettings()
        end)
    row3a:AddWidget(clipEnableCheck, 0.5)
    table_insert(allWidgets, clipEnableCheck)

    local clipColorPicker = GUIFrame:CreateColorPicker(row3a, "Warning Color",
        cw.Color or { 1, 0, 0, 1 },
        function(r, g, b, a)
            if not db.ClipWarning then db.ClipWarning = {} end
            db.ClipWarning.Color = { r, g, b, a }
            ApplySettings()
        end)
    row3a:AddWidget(clipColorPicker, 0.5)
    table_insert(allWidgets, clipColorPicker)
    table_insert(clipWidgets, clipColorPicker)
    card3:AddRow(row3a, 40)

    -- Warning Text EditBox
    local row3b = GUIFrame:CreateRow(card3.content, 40)
    local clipTextEdit = GUIFrame:CreateEditBox(row3b, "Warning Text", cw.Text or "DON'T CLIP",
        function(text)
            if not db.ClipWarning then db.ClipWarning = {} end
            db.ClipWarning.Text = text
            ApplySettings()
        end)
    row3b:AddWidget(clipTextEdit, 1)
    table_insert(allWidgets, clipTextEdit)
    table_insert(clipWidgets, clipTextEdit)
    card3:AddRow(row3b, 40)

    yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

    ---------------------------------------------------------------------------------
    -- Card 4: Warning Position
    ---------------------------------------------------------------------------------
    local card4, newOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
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
        onChangeCallback = ApplyPosition,
    })
    if card4.positionWidgets then
        for _, widget in ipairs(card4.positionWidgets) do
            table_insert(allWidgets, widget)
        end
    end
    table_insert(allWidgets, card4)
    yOffset = newOffset

    ---------------------------------------------------------------------------------
    -- Card 5: Warning Font Settings
    ---------------------------------------------------------------------------------
    local card5 = GUIFrame:CreateCard(scrollChild, "Warning Font Settings", yOffset)
    table_insert(allWidgets, card5)

    local fontList = {}
    if LSM then
        for name in pairs(LSM:HashTable("font")) do fontList[name] = name end
    else
        fontList["Friz Quadrata TT"] = "Friz Quadrata TT"
    end

    -- Font Face + Font Size
    local row5a = GUIFrame:CreateRow(card5.content, 40)
    local fontDropdown = GUIFrame:CreateDropdown(row5a, "Font", fontList,
        cw.FontFace or "Expressway", 30,
        function(key)
            if not db.ClipWarning then db.ClipWarning = {} end
            db.ClipWarning.FontFace = key
            ApplySettings()
        end)
    row5a:AddWidget(fontDropdown, 0.5)
    table_insert(allWidgets, fontDropdown)
    table_insert(clipWidgets, fontDropdown)

    local fontSizeSlider = GUIFrame:CreateSlider(row5a, "Font Size", 8, 36, 1,
        cw.FontSize or 16, nil,
        function(val)
            if not db.ClipWarning then db.ClipWarning = {} end
            db.ClipWarning.FontSize = val
            ApplySettings()
        end)
    row5a:AddWidget(fontSizeSlider, 0.5)
    table_insert(allWidgets, fontSizeSlider)
    table_insert(clipWidgets, fontSizeSlider)
    card5:AddRow(row5a, 40)

    -- Font Outline
    local row5b = GUIFrame:CreateRow(card5.content, 37)
    local outlineList = {
        { key = "NONE",         text = "None" },
        { key = "OUTLINE",      text = "Outline" },
        { key = "THICKOUTLINE", text = "Thick" },
        { key = "SOFTOUTLINE",  text = "Soft" },
    }
    local outlineDropdown = GUIFrame:CreateDropdown(row5b, "Outline", outlineList,
        cw.FontOutline or "SOFTOUTLINE", 45,
        function(key)
            if not db.ClipWarning then db.ClipWarning = {} end
            db.ClipWarning.FontOutline = key
            ApplySettings()
        end)
    row5b:AddWidget(outlineDropdown, 1)
    table_insert(allWidgets, outlineDropdown)
    table_insert(clipWidgets, outlineDropdown)
    card5:AddRow(row5b, 37)

    yOffset = yOffset + card5:GetContentHeight() + Theme.paddingSmall

    -- Apply initial widget states
    UpdateAllWidgetStates()
    yOffset = yOffset - (Theme.paddingSmall * 2)
    return yOffset
end)
