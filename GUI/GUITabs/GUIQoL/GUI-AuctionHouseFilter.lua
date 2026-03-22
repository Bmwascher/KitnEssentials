-- KitnEssentials namespace
---@class KE
local KE = select(2, ...)
local GUIFrame = KE.GUIFrame
local Theme = KE.Theme
local table_insert = table.insert
local ipairs = ipairs

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
    local allWidgets = {}

    local function ApplyModuleState(enabled)
        if not AHF then return end
        db.Enabled = enabled
        if enabled then KitnEssentials:EnableModule("AuctionHouseFilter")
        else KitnEssentials:DisableModule("AuctionHouseFilter") end
    end

    local function UpdateAllWidgetStates()
        local mainEnabled = db.Enabled ~= false
        for _, widget in ipairs(allWidgets) do
            if widget.SetEnabled then widget:SetEnabled(mainEnabled) end
        end
    end

    ----------------------------------------------------------------
    -- Card 1: Master Enable
    ----------------------------------------------------------------
    local card1 = GUIFrame:CreateCard(scrollChild, "Auction House Filter", yOffset)
    local row1 = GUIFrame:CreateRow(card1.content, 36)
    local enableCheck = GUIFrame:CreateCheckbox(row1, "Enable Auction House Filter", db.Enabled ~= false,
        function(checked)
            db.Enabled = checked
            ApplyModuleState(checked)
            UpdateAllWidgetStates()
        end,
        true, "Auction House Filter", "On", "Off")
    row1:AddWidget(enableCheck, 0.5)
    card1:AddRow(row1, 36)
    yOffset = yOffset + card1:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 2: Blizzard Auction House
    ----------------------------------------------------------------
    local card2 = GUIFrame:CreateCard(scrollChild, "Blizzard Auction House", yOffset)
    table_insert(allWidgets, card2)

    local row2 = GUIFrame:CreateRow(card2.content, 40)

    local ahExpansionCheck = GUIFrame:CreateCheckbox(row2, "Current Expansion Only",
        db.AuctionHouse.CurrentExpansion ~= false,
        function(checked) db.AuctionHouse.CurrentExpansion = checked end)
    row2:AddWidget(ahExpansionCheck, 0.5)
    table_insert(allWidgets, ahExpansionCheck)

    local ahFocusCheck = GUIFrame:CreateCheckbox(row2, "Focus Search Bar",
        db.AuctionHouse.FocusSearchBar == true,
        function(checked) db.AuctionHouse.FocusSearchBar = checked end)
    row2:AddWidget(ahFocusCheck, 0.5)
    table_insert(allWidgets, ahFocusCheck)

    card2:AddRow(row2, 40)
    yOffset = yOffset + card2:GetContentHeight() + Theme.paddingSmall

    ----------------------------------------------------------------
    -- Card 3: Craft Orders
    ----------------------------------------------------------------
    local card3 = GUIFrame:CreateCard(scrollChild, "Craft Orders", yOffset)
    table_insert(allWidgets, card3)

    local row3 = GUIFrame:CreateRow(card3.content, 40)

    local coExpansionCheck = GUIFrame:CreateCheckbox(row3, "Current Expansion Only",
        db.CraftOrders.CurrentExpansion ~= false,
        function(checked) db.CraftOrders.CurrentExpansion = checked end)
    row3:AddWidget(coExpansionCheck, 0.5)
    table_insert(allWidgets, coExpansionCheck)

    local coFocusCheck = GUIFrame:CreateCheckbox(row3, "Focus Search Bar",
        db.CraftOrders.FocusSearchBar == true,
        function(checked) db.CraftOrders.FocusSearchBar = checked end)
    row3:AddWidget(coFocusCheck, 0.5)
    table_insert(allWidgets, coFocusCheck)

    card3:AddRow(row3, 40)
    yOffset = yOffset + card3:GetContentHeight() + Theme.paddingSmall

    -- Apply initial widget states
    UpdateAllWidgetStates()
    yOffset = yOffset - (Theme.paddingSmall * 2)
    return yOffset
end)
