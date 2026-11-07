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
    card:AddLabel("Adds KE's text under RestedXP's own waypoint arrow. Its place on screen stays yours: drag it in " ..
        "RestedXP as you do today.")

    local sizeRow = GUIFrame:CreateRow(card.content, Theme.rowHeightLast)
    local sizeSlider = GUIFrame:CreateSlider(sizeRow, "Size, percent of RestedXP's arrow", {
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
    card:AddRow(sizeRow, Theme.rowHeightLast, 0)
    yOffset = card:GetNextOffset()

    local textCard = GUIFrame:CreateCard(scrollChild, "Arrow Text", yOffset)
    manager:Register(textCard, "arrow")

    local wordsRow = GUIFrame:CreateRow(textCard.content, Theme.rowHeight)
    local wordsCheck = GUIFrame:CreateCheckbox(wordsRow, "Show the Objective's Words", {
        value = db.ArrowWords ~= false,
        callback = page.Setter("ArrowWords"),
    })
    wordsRow:AddWidget(wordsCheck, 1 / 2)
    manager:Register(wordsCheck, "arrow")
    local textSize = GUIFrame:CreateSlider(wordsRow, "Text Size", {
        min = 8, max = 24, step = 1,
        value = db.ArrowTextSize or 14,
        callback = page.Setter("ArrowTextSize"),
    })
    wordsRow:AddWidget(textSize, 1 / 2)
    manager:Register(textSize, "arrow")
    textCard:AddRow(wordsRow, Theme.rowHeight)

    local fontRow = GUIFrame:CreateRow(textCard.content, Theme.rowHeightLast)
    local fontCheck = GUIFrame:CreateCheckbox(fontRow, "Use the Addon Font", {
        value = db.ArrowAddonFont ~= false,
        callback = page.Setter("ArrowAddonFont"),
    })
    fontRow:AddWidget(fontCheck, 1 / 2)
    manager:Register(fontCheck, "arrow")
    local distanceCheck = GUIFrame:CreateCheckbox(fontRow, "Show the Distance", {
        value = db.ArrowDistance ~= false,
        callback = page.Setter("ArrowDistance"),
    })
    fontRow:AddWidget(distanceCheck, 1 / 2)
    manager:Register(distanceCheck, "arrow")
    textCard:AddRow(fontRow, Theme.rowHeightLast, 0)
    return textCard:GetNextOffset()
end
