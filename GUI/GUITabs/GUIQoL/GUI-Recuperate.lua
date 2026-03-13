-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local table_insert = table.insert
local ipairs = ipairs

local function GetRecuperateModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("Recuperate", true)
    end
    return nil
end

GUIFrame:RegisterContent("Recuperate", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.Recuperate
    if not db then return yOffset end

    local REC = GetRecuperateModule()
    local allWidgets = {}

    local function ApplySettings()
        if REC then REC:ApplySettings() end
    end

    local function ApplyState(enabled)
        if not REC then return end
        db.Enabled = enabled
        if enabled then KitnEssentials:EnableModule("Recuperate")
        else KitnEssentials:DisableModule("Recuperate") end
    end

    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false
        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then widget:SetEnabled(mainEnabled) end
        end
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Recuperate Button", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, 40)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Recuperate Button", db.Enabled ~= false,
        function(checked) db.Enabled = checked; ApplyState(checked); UpdateAllWidgetStates() end,
        true, "Recuperate Button", "On", "Off")
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, 40)

    local noteHeight = 40
    local noteRow = GUIFrame:CreateRow(card1.content, noteHeight)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        "Visible while in a raid group and out of combat. Fades based on missing health.",
        noteHeight, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, noteHeight)

    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 2: Size Settings
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Size Settings", yOffset)
    table_insert(allWidgets, card2)

    local row2 = GUIFrame:CreateRow(card2.content, 40)
    local sizeSlider = GUIFrame:CreateSlider(card2.content, "Button Size", 1, 1000, 1, db.Size or 40, 60,
        function(val)
            db.Size = val
            ApplySettings()
        end)
    row2:AddWidget(sizeSlider, 1)
    table_insert(allWidgets, sizeSlider)
    card2:AddRow(row2, 40)

    yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 3: Position Settings
    ----------------------------------------------------------------
    local card3, newOffset = GUIFrame:CreatePositionCard(scrollChild, yOffset, {
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

    if card3.positionWidgets then
        for _, widget in ipairs(card3.positionWidgets) do
            table_insert(allWidgets, widget)
        end
    end
    table_insert(allWidgets, card3)

    yOffset = newOffset

    UpdateAllWidgetStates()
    yOffset = yOffset - Theme.paddingSmall
    return yOffset
end)
