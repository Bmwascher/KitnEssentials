-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-Recuperate.lua                                      ║
-- ║  GUI: Recuperate Button                                  ║
-- ║  Purpose: Configuration panel for the Recuperate module. ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("Recuperate", true)
    end
    return nil
end

GUIFrame:RegisterContent("Recuperate", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.Recuperate
    if not db then return yOffset end

    local REC = GetModule()
    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        if REC then REC:ApplySettings() end
    end

    local function ApplyState(enabled)
        if not REC then return end
        db.Enabled = enabled
        if enabled then KitnEssentials:EnableModule("Recuperate")
        else KitnEssentials:DisableModule("Recuperate") end
    end

    local function UpdateStateDriver()
        if REC and REC.UpdateStateDriver then REC:UpdateStateDriver() end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Recuperate Button", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Recuperate Button", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyState(checked)
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Recuperate Button",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, Theme.rowHeight)

    local noteRow = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Visible out of combat in selected group types. Fades based on missing health.",
        Theme.rowHeight, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, Theme.rowHeight, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: General Settings
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "General Settings", yOffset)
    manager:Register(card2, "all")

    local row2a = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local loadInRaid = GUIFrame:CreateCheckbox(row2a, "Load in Raid", {
        value = db.LoadInRaid ~= false,
        callback = function(checked) db.LoadInRaid = checked; UpdateStateDriver() end,
        msgPopup = true,
        msgText = "Load in Raid",
        msgOn = "On",
        msgOff = "Off",
    })
    row2a:AddWidget(loadInRaid, 0.5)
    manager:Register(loadInRaid, "all")

    local loadInParty = GUIFrame:CreateCheckbox(row2a, "Load in Party", {
        value = db.LoadInParty == true,
        callback = function(checked) db.LoadInParty = checked; UpdateStateDriver() end,
        msgPopup = true,
        msgText = "Load in Party",
        msgOn = "On",
        msgOff = "Off",
    })
    row2a:AddWidget(loadInParty, 0.5)
    manager:Register(loadInParty, "all")
    card2:AddRow(row2a, Theme.rowHeight)

    local row2b = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local sizeSlider = GUIFrame:CreateSlider(row2b, "Button Size", {
        min = 1, max = 1000, step = 1,
        value = db.Size or 40,
        callback = function(val) db.Size = val; ApplySettings() end,
    })
    row2b:AddWidget(sizeSlider, 1)
    manager:Register(sizeSlider, "all")
    card2:AddRow(row2b, Theme.rowHeightLast, 0)

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

    RefreshStates()
    return yOffset
end)
