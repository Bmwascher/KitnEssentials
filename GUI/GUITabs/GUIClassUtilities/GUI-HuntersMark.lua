-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-HuntersMark.lua                                     ║
-- ║  GUI: Hunter's Mark Missing                              ║
-- ║  Purpose: Configuration panel for the                    ║
-- ║           HuntersMark module.                            ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("HuntersMark", true)
    end
    return nil
end

GUIFrame:RegisterContent("HuntersMark", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.HuntersMark
    if not db then return yOffset end

    local HM = GetModule()
    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        if HM then HM:ApplySettings() end
    end

    local function ApplyState(enabled)
        if not HM then return end
        db.Enabled = enabled
        if enabled then KitnEssentials:EnableModule("HuntersMark")
        else KitnEssentials:DisableModule("HuntersMark") end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Hunter's Mark Tracking", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Hunter's Mark Tracking", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyState(checked)
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Hunter's Mark Tracking",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, Theme.rowHeight)

    local noteRow = GUIFrame:CreateRow(card1.content, 40)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " This module only works inside raid instances and while out of combat.",
        40, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, 40, 0)

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
        showAnchorFrameType = false,
        showStrata = true,
        onChangeCallback = ApplySettings,
    })

    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "all")
    end
    manager:Register(posCard, "all")
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 3: Font Settings
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
    -- Card 4: Colors
    ----------------------------------------------------------------
    local card4 = GUIFrame:CreateCard(scrollChild, "Colors", yOffset)
    manager:Register(card4, "all")

    local row4 = GUIFrame:CreateRow(card4.content, Theme.rowHeightLast)
    local colorPicker = GUIFrame:CreateColorPicker(row4, "Alert Color", {
        color = db.Color or { 1, 0.82, 0, 1 },
        callback = function(r, g, b, a) db.Color = { r, g, b, a }; ApplySettings() end,
    })
    row4:AddWidget(colorPicker, 1)
    manager:Register(colorPicker, "all")
    card4:AddRow(row4, Theme.rowHeightLast, 0)

    yOffset = card4:GetNextOffset()

    RefreshStates()
    return yOffset
end)
