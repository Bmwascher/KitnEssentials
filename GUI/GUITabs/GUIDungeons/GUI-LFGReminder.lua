-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-LFGReminder.lua                                     ║
-- ║  GUI: LFG Reminder                                       ║
-- ║  Purpose: Configuration panel for the LFGReminder module ║
-- ║           (teleport popup shown after joining a Group    ║
-- ║           Finder dungeon group).                         ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

GUIFrame:RegisterContent("LFGReminder", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.LFGReminder
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available.")
        return errorCard:GetNextOffset()
    end

    local manager = GUIFrame:CreateWidgetStateManager()

    local function GetModule()
        return KitnEssentials and KitnEssentials:GetModule("LFGReminder", true)
    end

    local function RefreshModule()
        local LR = GetModule()
        if LR and LR.RefreshVisuals then LR:RefreshVisuals() end
    end

    local function ApplyModuleState(enabled)
        if not KitnEssentials then return end
        local LR = GetModule()
        if not LR then return end
        LR.db.Enabled = enabled
        if enabled then
            KitnEssentials:EnableModule("LFGReminder")
        else
            KitnEssentials:DisableModule("LFGReminder")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- One card: the switch plus the popup settings it governs
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "LFG Reminder", yOffset)
    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        ApplyModuleState(checked)
    end)

    -- Lone header bar: a disabled module shows its switch and nothing else.
    if db.Enabled == false then return card1:GetNextOffset() end

    card1:AddLabel("Shown when you join a Group Finder group for a dungeon whose teleport you know. Drag the popup to move it; it hides when you enter the dungeon, leave the group, or enter combat. Also prompts the group leader once their own listing fills. With Show Role on, the popup also shows the role you were accepted as, in the Role Icon Style set on the Group Finder card under Skinning > Blizzard Frames.")

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local scale = GUIFrame:CreateSlider(row1, "Scale", {
        min = 0.5, max = 2, step = 0.05,
        value = db.Scale or 1.05,
        callback = function(val) db.Scale = val; RefreshModule() end,
    })
    row1:AddWidget(scale, 1)
    manager:Register(scale, "all")
    card1:AddRow(row1, Theme.rowHeight)

    local row2 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local showDisable = GUIFrame:CreateCheckbox(row2, "Show \"Disable Feature\" link", {
        value = db.ShowDisable ~= false,
        callback = function(checked) db.ShowDisable = checked; RefreshModule() end,
    })
    row2:AddWidget(showDisable, 0.5)
    manager:Register(showDisable, "all")

    local showRole = GUIFrame:CreateCheckbox(row2, "Show Role", {
        value = db.ShowRole ~= false,
        callback = function(checked) db.ShowRole = checked; RefreshModule() end,
    })
    row2:AddWidget(showRole, 0.5)
    manager:Register(showRole, "all")
    card1:AddRow(row2, Theme.rowHeightLast, 0)

    yOffset = card1:GetNextOffset()

    RefreshStates()
    return yOffset
end)
