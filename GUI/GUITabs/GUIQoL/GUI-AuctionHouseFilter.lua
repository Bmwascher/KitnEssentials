-- ╔══════════════════════════════════════════════════════════╗
-- ║  GUI-AuctionHouseFilter.lua                              ║
-- ║  GUI: Auction House Filter                               ║
-- ║  Purpose: Configuration panel for the                    ║
-- ║           AuctionHouseFilter module.                     ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme

local function GetModule()
    if KitnEssentials then
        return KitnEssentials:GetModule("AuctionHouseFilter", true)
    end
    return nil
end

GUIFrame:RegisterContent("AuctionHouseFilter", function(scrollChild, yOffset)
    local db = KE.db and KE.db.profile.AuctionHouseFilter
    if not db then return yOffset end

    local AHF = GetModule()
    local manager = GUIFrame:CreateWidgetStateManager()

    local function ApplyModuleState(enabled)
        if not AHF then return end
        db.Enabled = enabled
        if enabled then KitnEssentials:EnableModule("AuctionHouseFilter")
        else KitnEssentials:DisableModule("AuctionHouseFilter") end
    end

    local function RefreshStates()
        manager:UpdateAll(db.Enabled ~= false)
    end

    ----------------------------------------------------------------
    -- Card 1: Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Auction House Filter", yOffset)

    local row1 = GUIFrame:CreateRow(card1.content, Theme.rowHeightLast)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Auction House Filter", {
        value = db.Enabled ~= false,
        callback = function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            RefreshStates()
        end,
        msgPopup = true,
        msgText = "Auction House Filter",
        msgOn = "On",
        msgOff = "Off",
    })
    row1:AddWidget(enableCheck, 0.5)
    card1:AddRow(row1, Theme.rowHeightLast, 0)

    yOffset = card1:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 2: Blizzard Auction House
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Blizzard Auction House", yOffset)
    manager:Register(card2, "all")

    local row2 = GUIFrame:CreateRow(card2.content, Theme.rowHeightLast)
    local ahExpansionCheck = GUIFrame:CreateCheckbox(row2, "Current Expansion Only", {
        value = db.AuctionHouse.CurrentExpansion ~= false,
        callback = function(checked) db.AuctionHouse.CurrentExpansion = checked end,
    })
    row2:AddWidget(ahExpansionCheck, 0.5)
    manager:Register(ahExpansionCheck, "all")

    local ahFocusCheck = GUIFrame:CreateCheckbox(row2, "Focus Search Bar", {
        value = db.AuctionHouse.FocusSearchBar == true,
        callback = function(checked) db.AuctionHouse.FocusSearchBar = checked end,
    })
    row2:AddWidget(ahFocusCheck, 0.5)
    manager:Register(ahFocusCheck, "all")
    card2:AddRow(row2, Theme.rowHeightLast, 0)

    yOffset = card2:GetNextOffset()

    ----------------------------------------------------------------
    -- Card 3: Craft Orders
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Craft Orders", yOffset)
    manager:Register(card3, "all")

    local row3 = GUIFrame:CreateRow(card3.content, Theme.rowHeightLast)
    local coExpansionCheck = GUIFrame:CreateCheckbox(row3, "Current Expansion Only", {
        value = db.CraftOrders.CurrentExpansion ~= false,
        callback = function(checked) db.CraftOrders.CurrentExpansion = checked end,
    })
    row3:AddWidget(coExpansionCheck, 0.5)
    manager:Register(coExpansionCheck, "all")

    local coFocusCheck = GUIFrame:CreateCheckbox(row3, "Focus Search Bar", {
        value = db.CraftOrders.FocusSearchBar == true,
        callback = function(checked) db.CraftOrders.FocusSearchBar = checked end,
    })
    row3:AddWidget(coFocusCheck, 0.5)
    manager:Register(coFocusCheck, "all")
    card3:AddRow(row3, Theme.rowHeightLast, 0)

    yOffset = card3:GetNextOffset()

    RefreshStates()
    return yOffset
end)
