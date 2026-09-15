-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-BonusRoll.lua                                       ║
-- ║  GUI: Bonus Roll                                         ║
-- ║  Purpose: Configuration panel for the BonusRoll module.  ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local ipairs = ipairs
local CreateFrame = CreateFrame

local BR = KitnEssentials and KitnEssentials:GetModule("BonusRoll", true)

-- One content family per row: its name in the first column, each difficulty
-- in one of five equal columns, so the boxes line up down the card.
local AUTO_PASS_GROUPS = {
    { header = "Open World", buckets = {
        { key = "OpenWorld", label = "Open World" },
    } },
    { header = "Delves & Scenarios", buckets = {
        { key = "Delves",    label = "Delves" },
        { key = "Scenarios", label = "Other Scenarios" },
    } },
    { header = "Dungeons", buckets = {
        { key = "DungeonTimewalking",  label = "Timewalking" },
        { key = "DungeonNormalHeroic", label = "Normal / Heroic" },
        { key = "DungeonMythic",       label = "Mythic / Mythic+" },
    } },
    { header = "Raids", buckets = {
        { key = "RaidTimewalking", label = "Timewalking" },
        { key = "RaidLFR",         label = "LFR" },
        { key = "RaidNormal",      label = "Normal" },
        { key = "RaidHeroic",      label = "Heroic" },
        { key = "RaidMythic",      label = "Mythic" },
    } },
}
local LABEL_W, COLS = 0.18, 5
local COL_W = (1 - LABEL_W) / COLS
local CELL_H = 24
local CELL_SPACING = 2

GUIFrame:RegisterContent("BonusRoll", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.BonusRoll
    if not db then return yOffset end

    local manager = GUIFrame:CreateWidgetStateManager()
    manager:SetCondition("confirm", function() return db.Confirm ~= false end)

    local function ApplySettings()
        if BR and BR.ApplySettings then BR:ApplySettings() end
    end

    local function ApplyModuleState(enabled)
        if not BR then return end
        db.Enabled = enabled
        if enabled then KitnEssentials:EnableModule("BonusRoll")
        else KitnEssentials:DisableModule("BonusRoll") end
    end

    ---------------------------------------------------------------------------
    -- Card 1: Bonus Roll (enable)
    ---------------------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Bonus Roll", yOffset)
    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeight)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Bonus Roll", {
        value = db.Enabled == true,
        callback = function(checked)
            ApplyModuleState(checked)
            manager:UpdateAll(checked)
        end,
        msgPopup = true,
        msgText = "Bonus Roll",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 1)
    card1:AddRow(row1, Theme.rowHeight)

    local noteHeight = 50
    local noteRow = GUIFrame:CreateRow(card1.content, noteHeight)
    local noteText = GUIFrame:CreateText(noteRow, KE:ColorTextByTheme("Note"),
        KE:ColorTextByTheme("-") .. " A confirmation before a bonus roll coin is spent, and an automatic pass in the content you choose.\n"
            .. KE:ColorTextByTheme("-") .. " Every decision it makes is printed in chat.",
        noteHeight, "hide")
    noteRow:AddWidget(noteText, 1)
    card1:AddRow(noteRow, noteHeight, 0)
    yOffset = card1:GetNextOffset()

    ---------------------------------------------------------------------------
    -- Card 2: Confirmation
    ---------------------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Confirmation", yOffset)
    manager:Register(card2, "all")

    local row2a = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local confirmCheck = GUIFrame:CreateCheckbox(row2a, "Confirm Before Spending a Coin", {
        value = db.Confirm ~= false,
        callback = function(checked)
            db.Confirm = checked
            ApplySettings()
            manager:UpdateAll(db.Enabled == true)
        end,
        tooltip = "Clicking the dice opens a Spend / Pass dialog naming the loot spec the roll will award for, instead of spending on the spot.\n\nSpend presses the game's own dice for you; Pass presses its Pass. Closing the dialog with the X (or Escape) does neither: the game's prompt stays up with its timer.",
    })
    row2a:AddWidget(confirmCheck, 0.5)
    manager:Register(confirmCheck, "all")

    local passCheck = GUIFrame:CreateCheckbox(row2a, "Also Confirm Passing", {
        value = db.ConfirmPass == true,
        callback = function(checked) db.ConfirmPass = checked; ApplySettings() end,
        tooltip = "Also ask before the game's Pass button. A pass keeps the coin but gives up the chance to use it on that boss.",
    })
    row2a:AddWidget(passCheck, 0.5)
    manager:Register(passCheck, "confirm")
    card2:AddRow(row2a, Theme.rowHeight)

    local row2b = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local preview = GUIFrame:CreateButton(row2b, "Preview the Prompt", {
        width = 200,
        height = 28,
        tooltip = "Shows the confirmation as it will appear. Nothing is spent from here.",
        callback = function() if BR then BR:PreviewPrompt() end end,
    })
    row2b:AddWidget(preview, 1)
    manager:Register(preview, "all")
    card2:AddRow(row2b, Theme.rowHeightLast, 0)
    yOffset = card2:GetNextOffset()

    ---------------------------------------------------------------------------
    -- Card 3: Automatically Pass In (by the content the game reports)
    ---------------------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Automatically Pass In", yOffset)
    manager:Register(card3, "all")
    for g, group in ipairs(AUTO_PASS_GROUPS) do
        local row = GUIFrame:CreateRow(card3.content, CELL_H)
        local labelHost = CreateFrame("Frame", nil, row)
        labelHost:SetHeight(CELL_H)
        local label = labelHost:CreateFontString(nil, "OVERLAY")
        KE:ApplyThemeFont(label, "normal")
        label:SetPoint("LEFT", labelHost, "LEFT", 2, 0)
        label:SetJustifyH("LEFT")
        label:SetText(group.header)
        label:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
        row:AddWidget(labelHost, LABEL_W)
        for _, bucket in ipairs(group.buckets) do
            local key = bucket.key
            local cb = GUIFrame:CreateCompactCheckbox(row, bucket.label, {
                value = db.AutoPass[key] == true,
                callback = function(checked) db.AutoPass[key] = checked; ApplySettings() end,
            })
            row:AddWidget(cb, COL_W)
            manager:Register(cb, "all")
        end
        card3:AddRow(row, CELL_H, g == #AUTO_PASS_GROUPS and 0 or CELL_SPACING)
    end
    yOffset = card3:GetNextOffset()

    manager:UpdateAll(db.Enabled == true)
    return yOffset
end)
