-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-ChatLinks.lua                                       ║
-- ║  GUI: Chat Links                                         ║
-- ║  Purpose: Configuration panel for the ChatLinks module.   ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

-- No ShouldNotLoadModule gate: this module does not stand down for ElvUI, and
-- the sidebar entry is alwaysEnabled to match.
GUIFrame:RegisterContent("ChatLinks", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.Skinning.ChatLinks
    if not db then
        local errorCard = GUIFrame:CreateCard(scrollChild, "Error", yOffset)
        errorCard:AddLabel("Database not available")
        return errorCard:GetNextOffset()
    end

    local card = GUIFrame:CreateCard(scrollChild, "Chat Links", yOffset)
    card:AddHeaderToggle(db.Enabled == true, function(checked)
        db.Enabled = checked
        if checked then
            KitnEssentials:EnableModule("ChatLinks")
        else
            KitnEssentials:DisableModule("ChatLinks")
        end
        KE:Print("Chat Link Decoration: " .. (checked and "|cff4DCC66On|r" or "|cffE64D4DOff|r"))
    end)

    card:AddLabel("Puts the icon in front of items, currencies, spells, achievements, keystones and PvP talents linked in chat.")

    local rowIcon = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    rowIcon:AddWidget(GUIFrame:CreateCheckbox(rowIcon, "Show Link Icons", {
        value = db.Icon == true,
        tooltip = "Turn off to keep the quality tier number without any icons.",
        callback = function(checked) db.Icon = checked end,
    }), 1)
    card:AddRow(rowIcon, Theme.rowHeight)

    local rowH = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    rowH:AddWidget(GUIFrame:CreateSlider(rowH, "Icon Height", {
        min = 8, max = 32, step = 1, value = db.IconHeight or 14,
        callback = function(val) db.IconHeight = val end,
    }), 1)
    card:AddRow(rowH, Theme.rowHeight)

    local rowW = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    rowW:AddWidget(GUIFrame:CreateSlider(rowW, "Icon Width", {
        min = 8, max = 32, step = 1, value = db.IconWidth or 14,
        callback = function(val) db.IconWidth = val end,
    }), 1)
    card:AddRow(rowW, Theme.rowHeight)

    local rowRatio = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    rowRatio:AddWidget(GUIFrame:CreateCheckbox(rowRatio, "Keep Icon Aspect Ratio", {
        value = db.KeepRatio == true,
        tooltip = "Cuts the icon to fit a non-square size instead of stretching it.",
        callback = function(checked) db.KeepRatio = checked end,
    }), 1)
    card:AddRow(rowRatio, Theme.rowHeight)

    local rowTier = GUIFrame:CreateRow(card.content, Theme.rowHeight)
    rowTier:AddWidget(GUIFrame:CreateCheckbox(rowTier, "Quality Tier As A Number", {
        value = db.NumericalQualityTier == true,
        tooltip = "Shows the crafting quality as a coloured number instead of the small gem.",
        callback = function(checked) db.NumericalQualityTier = checked end,
    }), 1)
    card:AddRow(rowTier, Theme.rowHeightLast, 0)

    return card:GetNextOffset()
end)
