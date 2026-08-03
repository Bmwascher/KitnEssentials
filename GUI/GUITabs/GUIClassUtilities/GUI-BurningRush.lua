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
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Warlock: Burning Rush", yOffset)
    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        if checked then
            KitnEssentials:EnableModule("BurningRush")
        else
            KitnEssentials:DisableModule("BurningRush")
        end
        KE:Print("Burning Rush: " .. (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
    end)

    local noteRow = GUIFrame:CreateRow(card1.content, 40)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Warlock only. Shows a glowing icon while Burning Rush is active.",
        40, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, 40, 0)

    yOffset = card1:GetNextOffset()

    -- Lone header bar: a disabled module shows its switch and nothing else.
    if db.Enabled == false then return yOffset end

    local cardDisplay = GUIFrame:CreateCard(scrollChild, "Display Settings", yOffset)
    manager:Register(cardDisplay, "all")

    local row2 = GUIFrame:CreateRow(cardDisplay.content, Theme.rowHeightLast)
    local iconSizeSlider = GUIFrame:CreateSlider(row2, "Icon Size", {
        min = 20, max = 100, step = 1,
        value = db.IconSize or 40,
        callback = function(val) db.IconSize = val; ApplySettings() end,
    })
    row2:AddWidget(iconSizeSlider, 1)
    manager:Register(iconSizeSlider, "all")
    cardDisplay:AddRow(row2, Theme.rowHeightLast, 0)

    yOffset = cardDisplay:GetNextOffset()

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
        onChangeCallback = function() if BURN then BURN:ApplyPosition() end end,
    })
    if posCard.positionWidgets then
        manager:RegisterGroup(posCard.positionWidgets, "all")
    end
    manager:Register(posCard, "all")
    yOffset = posOffset

    ----------------------------------------------------------------
    -- Card 3: Glow Settings
    ----------------------------------------------------------------
    local glowCard, glowOffset = GUIFrame:CreateGlowSettingsCard(scrollChild, yOffset, {
        title = "Glow Settings",
        db = db,
        onChangeCallback = ApplySettings,
    })
    manager:Register(glowCard, "all")
    yOffset = glowOffset

    RefreshStates()
    return yOffset
end)
