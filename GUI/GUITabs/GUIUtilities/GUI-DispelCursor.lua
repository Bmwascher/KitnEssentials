-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-DispelCursor.lua                                    ║
-- ║  GUI: Dispel CD on Cursor                                ║
-- ║  Purpose: Configuration panel for the DispelCursor       ║
-- ║  module.                                                 ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("DispelCursor", true)
    end
    return nil
end

GUIFrame:RegisterContent("DispelCursor", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.DispelCursor
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local DC = GetModule()
    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        if DC then DC:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not DC then return end
        DC.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("DispelCursor")
        else
            KitnEssentials:DisableModule("DispelCursor")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Dispel on Cursor", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Dispel on Cursor", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Dispel on Cursor",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, Theme.rowHeight)

    local noteRow = GUIFrame:CreateRow(card1.content, 50)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Shows your dispel cooldown timer following your cursor.\n" ..
        KE:ColorTextByTheme("-") .. " Auto-detects your class dispel spell.",
        50, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, 50, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Display Settings
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Display Settings", yOffset)
    manager:Register(card2, "all")

    local row2a = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local fontSizeSlider = GUIFrame:CreateSlider(row2a, "Font Size", {
        min = 8, max = 36, step = 1,
        value = db.FontSize or 18,
        callback = function(val) db.FontSize = val; ApplySettings() end,
    })
    row2a:AddWidget(fontSizeSlider, 0.5)
    manager:Register(fontSizeSlider, "all")

    local colorPicker = GUIFrame:CreateColorPicker(row2a, "Text Color", {
        color = db.TextColor or { 1, 1, 1, 1 },
        callback = function(r, g, b, a)
            db.TextColor = { r, g, b, a }
            ApplySettings()
        end,
    })
    row2a:AddWidget(colorPicker, 0.5)
    manager:Register(colorPicker, "all")
    card2:AddRow(row2a, Theme.rowHeight)

    local row2b = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local xSlider = GUIFrame:CreateSlider(row2b, "X Offset from Cursor", {
        min = -50, max = 50, step = 1,
        value = db.XOffset or 10,
        callback = function(val) db.XOffset = val end,
    })
    row2b:AddWidget(xSlider, 0.5)
    manager:Register(xSlider, "all")

    local ySlider = GUIFrame:CreateSlider(row2b, "Y Offset from Cursor", {
        min = -50, max = 50, step = 1,
        value = db.YOffset or 10,
        callback = function(val) db.YOffset = val end,
    })
    row2b:AddWidget(ySlider, 0.5)
    manager:Register(ySlider, "all")
    card2:AddRow(row2b, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    RefreshStates()
    return yOffset
end)
