-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-FriendlyAutoMarker.lua                              ║
-- ║  GUI: Friendly Auto Marker                               ║
-- ║  Purpose: Configuration panel for the FriendlyAutoMarker ║
-- ║           module.                                         ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local MARKER_OPTIONS = {
    { key = 1, text = "Star" },
    { key = 2, text = "Circle" },
    { key = 3, text = "Diamond" },
    { key = 4, text = "Triangle" },
    { key = 5, text = "Moon" },
    { key = 6, text = "Square" },
    { key = 7, text = "Cross" },
    { key = 8, text = "Skull" },
}

GUIFrame:RegisterContent("FriendlyAutoMarker", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.FriendlyAutoMarker
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplySettings()
        local mod = KitnEssentials and KitnEssentials:GetModule("FriendlyAutoMarker", true)
        if mod and mod.ApplySettings then mod:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not KitnEssentials then return end
        local mod = KitnEssentials:GetModule("FriendlyAutoMarker", true)
        if not mod then return end
        mod.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("FriendlyAutoMarker")
        else
            KitnEssentials:DisableModule("FriendlyAutoMarker")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Friendly Auto Marker", yOffset)

    local row1a = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1a, "Enable Friendly Auto Marker", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Friendly Auto Marker",
        msgOn = "On",
        msgOff = "Off",
    })
    row1a:AddWidget(enableCheck, 1)
    card1:AddRow(row1a, Theme.rowHeight)

    local noteRow = GUIFrame:CreateRow(card1.content, 50)
    local noteText = GUIFrame:CreateText(noteRow,
        KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " Auto-marks the group's tank and healer when entering a dungeon, on M+ start, or when group composition changes.\n" ..
        KE:ColorTextByTheme("-") .. " Uses LibSpecialization for spec-derived role detection.",
        50, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, 50, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Mark Settings
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Mark Settings", yOffset)
    manager:Register(card2, "all")

    local row2a = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local markTankCheck = GUIFrame:CreateCheckbox(row2a, "Mark Tank", {
        value = db.MarkTank ~= false,
        callback = function(checked) db.MarkTank = checked; ApplySettings() end,
    })
    row2a:AddWidget(markTankCheck, 0.5)
    manager:Register(markTankCheck, "all")

    local markHealerCheck = GUIFrame:CreateCheckbox(row2a, "Mark Healer", {
        value = db.MarkHealer ~= false,
        callback = function(checked) db.MarkHealer = checked; ApplySettings() end,
    })
    row2a:AddWidget(markHealerCheck, 0.5)
    manager:Register(markHealerCheck, "all")
    card2:AddRow(row2a, Theme.rowHeight)

    local row2b = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local instanceOnlyCheck = GUIFrame:CreateCheckbox(row2b, "Instances Only (Dungeon/Raid)", {
        value = db.InstanceOnly ~= false,
        callback = function(checked) db.InstanceOnly = checked; ApplySettings() end,
    })
    row2b:AddWidget(instanceOnlyCheck, 1)
    manager:Register(instanceOnlyCheck, "all")
    card2:AddRow(row2b, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Icons
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Icons", yOffset)
    manager:Register(card3, "all")

    local row3 = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local tankDropdown = GUIFrame:CreateDropdown(row3, "Tank Icon", {
        options = MARKER_OPTIONS,
        value = db.TankIcon or 6,
        callback = function(val) db.TankIcon = val; ApplySettings() end,
    })
    row3:AddWidget(tankDropdown, 0.5)
    manager:Register(tankDropdown, "all")

    local healerDropdown = GUIFrame:CreateDropdown(row3, "Healer Icon", {
        options = MARKER_OPTIONS,
        value = db.HealerIcon or 1,
        callback = function(val) db.HealerIcon = val; ApplySettings() end,
    })
    row3:AddWidget(healerDropdown, 0.5)
    manager:Register(healerDropdown, "all")
    card3:AddRow(row3, Theme.rowHeightLast, 0)

    yOffset = card3:GetNextOffset()

    RefreshStates()
    return yOffset
end)
