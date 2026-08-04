-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-LFGQuickCreate.lua                                  ║
-- ║  GUI: LFG Quick Create                                   ║
-- ║  Purpose: Configuration panel for the LFGQuickCreate     ║
-- ║           module (season-dungeon buttons on the Group    ║
-- ║           Finder create form).                           ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

GUIFrame:RegisterContent("LFGQuickCreate", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.LFGQuickCreate
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available.")
        return errorCard:GetNextOffset()
    end

    local manager = GUIFrame:CreateWidgetStateManager()

    local function GetModule()
        return KitnEssentials and KitnEssentials:GetModule("LFGQuickCreate", true)
    end

    local function ApplySettings()
        local QC = GetModule()
        if QC and QC.ApplySettings then QC:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not GetModule() then return end
        if enabled then
            KitnEssentials:EnableModule("LFGQuickCreate")
        else
            KitnEssentials:DisableModule("LFGQuickCreate")
        end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled == true)
    end

    ----------------------------------------------------------------
    -- One card: the switch plus the buttons it governs
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "LFG Quick Create", yOffset)
    card1:AddHeaderToggle(db.Enabled == true, function(checked)
        db.Enabled = checked
        ApplyModuleState(checked)
        KE:Print("LFG Quick Create: " .. (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
    end)

    -- Lone header bar: a disabled module shows its switch and nothing else.
    if db.Enabled ~= true then return card1:GetNextOffset() end

    card1:AddLabel("Adds a row of season-dungeon buttons to the Group Finder's create form. One click lists a group for that dungeon using the Default Playstyle below. Your own keystone's dungeon glows gold with its key level; party members' keys glow blue.")

    -- Both switches share one row; they are short labels and the card read
    -- sparse with a line each.
    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local qcCheck = GUIFrame:CreateCheckbox(row1, "Quick Create Buttons", {
        value = db.QuickCreate ~= false,
        callback = function(checked) db.QuickCreate = checked; ApplySettings() end,
    })
    row1:AddWidget(qcCheck, 0.5)
    manager:Register(qcCheck, "all")

    local dcCheck = GUIFrame:CreateCheckbox(row1, "Double-Click Category to Start", {
        value = db.DoubleClickStart ~= false,
        callback = function(checked) db.DoubleClickStart = checked; ApplySettings() end,
        tooltip = "Double-clicking a category tile on the Premade Groups screen immediately opens Start a Group for that category.",
    })
    row1:AddWidget(dcCheck, 0.5)
    manager:Register(dcCheck, "all")
    card1:AddRow(row1, Theme.rowHeight)

    local row2 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    -- The ORDERED {key=,text=} form is required. The labels are this
    -- feature's own wording, not the enum's names -- the VALUES are what
    -- reach the listing payload and they match
    -- Enum.LFGEntryGeneralPlaystyle 1-4 exactly.
    local psDropdown = GUIFrame:CreateDropdown(row2, "Default Playstyle", {
        options = {
            { key = 1, text = "Learning" },
            { key = 2, text = "Relaxed" },
            { key = 3, text = "Competitive" },
            { key = 4, text = "Carry Offered" },
        },
        value = db.DefaultPlaystyle or 1,
        callback = function(key) db.DefaultPlaystyle = key; ApplySettings() end,
    })
    row2:AddWidget(psDropdown, 1)
    manager:Register(psDropdown, "all")
    card1:AddRow(row2, Theme.rowHeightLast, 0)

    yOffset = card1:GetNextOffset()

    RefreshStates()
    return yOffset
end)
