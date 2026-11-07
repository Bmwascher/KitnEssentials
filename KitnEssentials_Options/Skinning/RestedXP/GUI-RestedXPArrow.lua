-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-RestedXPArrow.lua                                   ║
-- ║  GUI: RestedXP, Arrow tab                                ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = KitnEssentials:GetNamespace()
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

GUIFrame.RestedXPTabs = GUIFrame.RestedXPTabs or {}

function GUIFrame.RestedXPTabs.Arrow(scrollChild, yOffset, page)
    local db, manager = page.db, page.manager

    manager:SetCondition("arrow", function() return db.ArrowEnabled ~= false end)

    local card = GUIFrame:CreateCard(scrollChild, "Arrow", yOffset)
    manager:Register(card, "all")
    card:AddHeaderToggle(db.ArrowEnabled ~= false, function(checked)
        db.ArrowEnabled = checked
        page.Apply()
    end)
    page.Note(card, "RestedXP's own arrow, with KE's text under it. Drag it in RestedXP as you do today.")

    local sizeRow = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local sizeSlider = GUIFrame:CreateSlider(sizeRow, "Size, percent", {
        min = 60, max = 200, step = 5,
        value = db.ArrowSize or 100,
        callback = page.Setter("ArrowSize"),
    })
    sizeRow:AddWidget(sizeSlider, 1 / 2)
    manager:Register(sizeSlider, "arrow")
    local gapSlider = GUIFrame:CreateSlider(sizeRow, "Gap Under the Arrow", {
        min = 0, max = 20, step = 1,
        value = db.ArrowGap or 4,
        callback = page.Setter("ArrowGap"),
    })
    sizeRow:AddWidget(gapSlider, 1 / 2)
    manager:Register(gapSlider, "arrow")
    card:AddRow(sizeRow, Theme.rowHeight)
    page.Separator(card)

    local fontRow = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    local textSize = GUIFrame:CreateSlider(fontRow, "Text Size", {
        min = 8, max = 24, step = 1,
        value = db.ArrowTextSize or 14,
        callback = page.Setter("ArrowTextSize"),
    })
    fontRow:AddWidget(textSize, 1 / 2)
    manager:Register(textSize, "arrow")
    local fontCheck = GUIFrame:CreateCheckbox(fontRow, "Use the Addon Font", {
        value = db.ArrowAddonFont ~= false,
        callback = page.Setter("ArrowAddonFont"),
    })
    fontRow:AddWidget(fontCheck, 1 / 2)
    manager:Register(fontCheck, "arrow")
    card:AddRow(fontRow, Theme.rowHeight)

    local wordsRow = GUIFrame:CreateRow(card.content, Theme.rowHeightLast)
    local wordsCheck = GUIFrame:CreateCheckbox(wordsRow, "Show the Objective's Words", {
        value = db.ArrowWords ~= false,
        callback = page.Setter("ArrowWords"),
    })
    wordsRow:AddWidget(wordsCheck, 1 / 2)
    manager:Register(wordsCheck, "arrow")
    local distanceCheck = GUIFrame:CreateCheckbox(wordsRow, "Show the Distance", {
        value = db.ArrowDistance ~= false,
        callback = page.Setter("ArrowDistance"),
    })
    wordsRow:AddWidget(distanceCheck, 1 / 2)
    manager:Register(distanceCheck, "arrow")
    card:AddRow(wordsRow, Theme.rowHeightLast, 0)
    return card:GetNextOffset()
end
