-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-LootFrame.lua                                        ║
-- ║  GUI: Loot Window                                         ║
-- ║  Purpose: Configuration panel for the                     ║
-- ║           LootFrame module.                                ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

GUIFrame:RegisterContent("SkinBlizzardFramesLootWindow", function(scrollChild, yOffset)
    if KE:ShouldNotLoadModule() then return end
    local db = KE.db and KE.db.profile.Skinning.Loot
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return yOffset + errorCard:GetContentHeight() + Theme.paddingMedium
    end

    local LF = KitnEssentials:GetModule("LootFrame", true)
    local manager = GUIFrame:CreateWidgetStateManager()

    local function Apply() if LF then LF:ApplySettings() end end
    local function UpdateAllWidgetStates() manager:UpdateAll(db.Enabled ~= false) end

    -- Card 1: Module
    local card1 = GUIFrame:CreateCard(scrollChild, "Loot Window", yOffset)

    card1:AddHeaderToggle(db.Enabled ~= false, function(checked)
        db.Enabled = checked
        if not checked then KE:SkinningReloadPrompt() end -- v3.5.548: restoring Blizzard loot window needs /reload
        if checked then
            KitnEssentials:EnableModule("LootFrame")
        else
            KitnEssentials:DisableModule("LootFrame")
        end
        UpdateAllWidgetStates()
    end)

    -- Disabled modules collapse to the header bar alone (v3.5.188).
    if db.Enabled == false then
        return yOffset + card1:GetContentHeight() + Theme.paddingSmall
    end
    card1:AddLabel("Replaces Blizzard's loot window with a compact one-row-per-item list at a fixed position. Item names are quality-colored. Turning this OFF requires a /reload to restore Blizzard's window.")

    yOffset = card1:GetNextOffset()

    -- Card 2: Display Settings
    local card2 = GUIFrame:CreateCard(scrollChild, "Display Settings", yOffset)
    manager:Register(card2, "all")

    local rowQ = GUIFrame:CreateRow(card2.content, Theme.rowHeight)
    local qualityCheck = GUIFrame:CreateCheckbox(rowQ, "Item-Quality Border Color", {
        value = db.QualityBorder ~= false,
        callback = function(checked)
            db.QualityBorder = checked
            Apply()
        end,
    })
    rowQ:AddWidget(qualityCheck, 1)
    manager:Register(qualityCheck, "all")
    card2:AddRow(rowQ, Theme.rowHeight)

    local rowW = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local widthSlider = GUIFrame:CreateSlider(rowW, "Minimum Width", {
        min = 100, max = 400, step = 10, value = db.MinWidth or 150,
        callback = function(val) db.MinWidth = val; Apply() end
    })
    rowW:AddWidget(widthSlider, 1)
    manager:Register(widthSlider, "all")
    card2:AddRow(rowW, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    -- Card 3: Position
    local card3 = GUIFrame:CreateCard(scrollChild, "Position Settings", yOffset)
    manager:Register(card3, "all")

    card3:AddLabel("Follows the position you set for Blizzard's loot window in Blizzard's Edit Mode. Drag it there and this window follows.")

    yOffset = card3:GetNextOffset()

    UpdateAllWidgetStates()

    return yOffset
end)
