-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-BurningRush.lua                                     ║
-- ║  GUI: Burning Rush (Warlock)                             ║
-- ║  Purpose: Configuration panel for the BurningRush module.║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("BurningRush", true)
    end
    return nil
end

GUIFrame:RegisterContent("BurningRush", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.BurningRush
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local BURN = GetModule()
    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings() if BURN then BURN:ApplySettings() end end
    local function RefreshStates() manager:UpdateAll(db.Enabled ~= false) end

    ----------------------------------------------------------------
    -- Card 1: Enable & Preview
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Burning Rush", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Burning Rush", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            if checked then
                KitnEssentials:EnableModule("BurningRush")
            else
                KitnEssentials:DisableModule("BurningRush")
            end
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Burning Rush",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, (2 / 3))

    local previewBtn
    previewBtn = GUIFrame:CreateButton(row1, "Show Preview", {
        height = 30,
        callback = function()
            if BURN and BURN.TogglePreview then
                local active = BURN:TogglePreview()
                previewBtn:SetLabel(active and "Hide Preview" or "Show Preview")
            end
        end,
    })
    row1:AddWidget(previewBtn, (1 / 3), nil, 0, -6)
    if BURN and BURN.IsPreviewActive and BURN:IsPreviewActive() then
        previewBtn:SetLabel("Hide Preview")
    end
    card1:AddRow(row1, Theme.rowHeight)

    local noteRow = GUIFrame:CreateRow(card1.content, 36)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Warlock only. Shows a glowing icon while Burning Rush is active.",
        36, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, 36)

    local sepRow = GUIFrame:CreateRow(card1.content, Theme.rowHeightSeparator)
    local sep1 = GUIFrame:CreateSeparator(sepRow)
    sepRow:AddWidget(sep1, 1)
    card1:AddRow(sepRow, Theme.rowHeightSeparator)

    local row2 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local iconSizeSlider = GUIFrame:CreateSlider(row2, "Icon Size", {
        min = 20, max = 100, step = 1,
        value = db.IconSize or 40,
        callback = function(val) db.IconSize = val; ApplySettings() end,
    })
    row2:AddWidget(iconSizeSlider, 1)
    manager:Register(iconSizeSlider, "all")
    card1:AddRow(row2, Theme.rowHeightLast, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Glow Settings
    ----------------------------------------------------------------
    local glowCard, glowOffset = GUIFrame:CreateGlowSettingsCard(scrollChild, yOffset, {
        title = "Glow Settings",
        db = db,
        onChangeCallback = ApplySettings,
    })
    manager:Register(glowCard, "all")
    yOffset = glowOffset

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
        onChangeCallback = function() if BURN then BURN:ApplyPosition() end end,
    })
    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "all")
    end
    manager:Register(posCard, "all")
    yOffset = posOffset

    RefreshStates()
    return yOffset
end)
