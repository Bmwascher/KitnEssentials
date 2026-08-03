local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local next, pairs = next, pairs
local hooksecurefunc = hooksecurefunc

-- AuctionHouseFrameTabMixin:OnShow fits these tabs with padding 20 and a 70px
-- minimum. S.Tab's own fit uses padding 0, so the two produced different widths
-- and Blizzard won on its next OnShow -- the tab resized when clicked.
-- Refitting with Blizzard's numbers after our font lands makes both agree.
local TAB_PADDING, TAB_MIN_WIDTH = 20, 70

local function SkinPanelTab(tab)
    if not tab then return end

    S.Tab(tab)

    if _G.PanelTemplates_TabResize and tab.Text then
        pcall(_G.PanelTemplates_TabResize, tab, TAB_PADDING, nil, TAB_MIN_WIDTH)
    end
end

local function SkinFilterButton(button)

    S.Button(button)

    S.CloseButton(button.ClearFiltersButton, 9)
end

local function SkinSearchBar(frame)
    SkinFilterButton(frame.FilterButton)
    S.Button(frame.SearchButton)
    S.EditBox(frame.SearchBox)

    S.Button(frame.FavoritesSearchButton, frame.FavoritesSearchButton.Icon)
    frame.FavoritesSearchButton:SetSize(22, 22)
end

local function IconCells(frame)
    if not frame.tableBuilder then return end
    for i = 1, 22 do
        local row = frame.tableBuilder.rows[i]
        if row then
            for j = 1, 4 do
                local cell = row.cells and row.cells[j]
                if cell and cell.Icon and not S.data(cell).skinned then
                    S.data(cell).skinned = true
                    S.Icon(cell.Icon)
                    if cell.IconBorder then S.KillTexture(cell.IconBorder) end
                end
            end
        end
    end
end

local function SkinSummaryIcon(child)
    if child.Icon and not S.data(child).skinned then
        S.data(child).skinned = true
        S.Icon(child.Icon)
        if child.IconBorder then S.KillTexture(child.IconBorder) end
    end
end

local function SummaryIcons(frame)
    frame:ForEachFrame(SkinSummaryIcon)
end

local function SkinItemDisplay(frame)
    local ItemDisplay = frame.ItemDisplay
    if not ItemDisplay then return end
    S.StripTextures(ItemDisplay)
    local bd = S.Backdrop(ItemDisplay)
    if bd then
        bd:ClearAllPoints()
        bd:SetPoint("TOPLEFT", ItemDisplay, "TOPLEFT", 3, -3)
        bd:SetPoint("BOTTOMRIGHT", ItemDisplay, "BOTTOMRIGHT", -3, 0)
    end

    local ItemButton = ItemDisplay.ItemButton
    if ItemButton then
        if ItemButton.CircleMask then ItemButton.CircleMask:Hide() end
        S.SlotIcon(ItemButton.Icon, ItemButton.IconBorder)
        local hl = ItemButton:GetHighlightTexture()
        if hl then hl:Hide() end
    end
end

local function SkinHeaderRow(frame)
    local maxHeaders = frame.HeaderContainer:GetNumChildren()
    for i, header in next, { frame.HeaderContainer:GetChildren() } do
        if not S.data(header).skinned then
            S.data(header).skinned = true
            header:DisableDrawLayer("BACKGROUND")
            S.Backdrop(header)

            S.FontStrings(header, 12, "OUTLINE")
        end
        local bd = S.GetBackdrop(header)
        if bd then
            bd:SetPoint("BOTTOMRIGHT", i < maxHeaders and -5 or 0, -2)
        end
    end
    IconCells(frame)
end

local function SkinRefreshButton(button)

    S.Button(button, button.Icon)
    button:SetSize(22, 22)
end

-- The sell panel's item slot: Blizzard's round mask and empty-slot art go, and
-- the hover is clipped to the icon rather than the whole button.
local function SkinSellSlot(button)
    S.HideAll(button, { "IconMask", "EmptyBackground" })
    button:SetPushedTexture(0)

    if button.Highlight then
        button.Highlight:SetColorTexture(1, 1, 1, 0.25)
        button.Highlight:SetAllPoints(button.Icon)
    end

    S.SlotIcon(button.Icon, button.IconBorder)
end

local function SkinSellDisplay(display)
    if not display then return end

    S.StripTextures(display)
    S.Template(display, "Window")
    if display.ItemButton then SkinSellSlot(display.ItemButton) end
end

-- Gold and silver come as a pair on a MoneyInputFrame. Some frames hold one
-- under `.MoneyInputFrame`; BidFrame.BidAmount inherits the template directly,
-- so both shapes are accepted.
-- Two money-input templates are in play here. The large one keys its fields
-- GoldBox/SilverBox; MoneyInputFrameTemplate (which BidFrame.BidAmount
-- inherits directly) uses lowercase gold/silver/copper.
local MONEY_FIELDS = { "GoldBox", "SilverBox", "gold", "silver", "copper" }

local function SkinMoneyInput(holder)
    local money = holder and (holder.MoneyInputFrame or holder)
    if not money then return end

    for _, key in ipairs(MONEY_FIELDS) do
        if money[key] then S.EditBox(money[key]) end
    end
end

local function SkinBidFrame(bid)
    if not bid then return end

    SkinMoneyInput(bid.BidAmount)
    if bid.BidButton then S.Button(bid.BidButton) end
end

local function SkinSellPanel(frame)
    S.StripTextures(frame)

    SkinSellDisplay(frame.ItemDisplay)

    if frame.QuantityInput then
        S.EditBox(frame.QuantityInput.InputBox)
        S.Button(frame.QuantityInput.MaxButton)
    end

    SkinMoneyInput(frame.PriceInput)
    SkinMoneyInput(frame.SecondaryPriceInput)

    if frame.Duration then pcall(S.DropDown, frame.Duration.Dropdown) end

    if frame.PostButton then
        S.Button(frame.PostButton)
        S.FontStrings(frame.PostButton, 12, "OUTLINE")
    end

    if frame.BuyoutModeCheckButton then
        S.CheckBox(frame.BuyoutModeCheckButton)
        frame.BuyoutModeCheckButton:SetSize(20, 20)
    end
end

local function SkinTokenSellPanel(frame)
    S.StripTextures(frame)

    SkinSellDisplay(frame.ItemDisplay)

    S.Button(frame.PostButton)
    S.FontStrings(frame.PostButton, 12, "OUTLINE")
    SkinRefreshButton(frame.DummyRefreshButton)
    S.StripTextures(frame.DummyItemList)
    S.Template(frame.DummyItemList, "Window")
    S.ScrollBar(frame.DummyItemList.DummyScrollBar)
end

local function SkinResultsList(frame, hasHeader)
    S.StripTextures(frame)
    if frame.RefreshFrame then
        SkinRefreshButton(frame.RefreshFrame.RefreshButton)
    end
    S.ScrollBar(frame.ScrollBar)
    if hasHeader then
        S.Template(frame.ScrollBox, "Window")
        hooksecurefunc(frame, "RefreshScrollFrame", SkinHeaderRow)
    else
        hooksecurefunc(frame.ScrollBox, "Update", SummaryIcons)
    end
end

-- The auctions tabs all wear the same list: header row, a refresh button, and
-- on some of them a results caption that belongs inside the scroll frame.
-- dockResults stays explicit because not every list reparents it.
local function SkinAuctionList(list, hasHeader, dockResults)
    if not list then return end

    SkinResultsList(list, hasHeader)

    if list.RefreshFrame then S.Button(list.RefreshFrame.RefreshButton) end
    if dockResults and list.ResultsText then
        list.ResultsText:SetParent(list.ScrollFrame)
    end
end

local function Skin()
    local Frame = _G.AuctionHouseFrame
    if not Frame then return end
    S.Frame(Frame)

    for _, tab in next, { _G.AuctionHouseFrameBuyTab, _G.AuctionHouseFrameSellTab, _G.AuctionHouseFrameAuctionsTab } do
        SkinPanelTab(tab)
    end

    SkinSearchBar(Frame.SearchBar)
    if Frame.MoneyFrameBorder then S.StripTextures(Frame.MoneyFrameBorder) end
    if Frame.MoneyFrameInset then S.Inset(Frame.MoneyFrameInset) end

    local Categories = Frame.CategoriesList
    if Categories then
        S.StripTextures(Categories)
        if Categories.NineSlice then S.StripTextures(Categories.NineSlice, true) end
        S.Backdrop(Categories)
        S.ScrollBar(Categories.ScrollBar)
    end

    hooksecurefunc("AuctionHouseFilterButton_SetUp", function(button)

        if button.Text then S.SetFont(button.Text, 12, "OUTLINE") end
        button.NormalTexture:SetAlpha(0)
        button.SelectedTexture:SetColorTexture(S.palette.brand[1], S.palette.brand[2], S.palette.brand[3], 0.15)
        button.HighlightTexture:SetColorTexture(S.palette.hover[1], S.palette.hover[2], S.palette.hover[3], S.palette.hover[4])
    end)

    local Browse = Frame.BrowseResultsFrame
    if Browse and Browse.ItemList then
        local BrowseList = Browse.ItemList
        S.StripTextures(BrowseList)
        hooksecurefunc(BrowseList, "RefreshScrollFrame", SkinHeaderRow)
        S.ScrollBar(BrowseList.ScrollBar)
        S.Template(BrowseList, "Window")
    end

    local CommoditiesBuyFrame = Frame.CommoditiesBuyFrame
    if CommoditiesBuyFrame then
        S.StripTextures(CommoditiesBuyFrame.BuyDisplay)
        S.Button(CommoditiesBuyFrame.BackButton)

        local CommoditiesBuyList = CommoditiesBuyFrame.ItemList
        if CommoditiesBuyList then
            S.StripTextures(CommoditiesBuyList)
            S.Template(CommoditiesBuyList, "Window")
            S.Button(CommoditiesBuyList.RefreshFrame.RefreshButton)
            S.ScrollBar(CommoditiesBuyList.ScrollBar)
        end

        local BuyDisplay = CommoditiesBuyFrame.BuyDisplay
        if BuyDisplay then
            S.EditBox(BuyDisplay.QuantityInput.InputBox)
            S.Button(BuyDisplay.BuyButton)
            SkinItemDisplay(BuyDisplay)
        end
    end

    local ItemBuyFrame = Frame.ItemBuyFrame
    if ItemBuyFrame then
        S.Button(ItemBuyFrame.BackButton)
        S.Button(ItemBuyFrame.BuyoutFrame.BuyoutButton)
        SkinItemDisplay(ItemBuyFrame)

        local ItemBuyList = ItemBuyFrame.ItemList
        if ItemBuyList then
            S.StripTextures(ItemBuyList)
            S.Template(ItemBuyList, "Window")
            S.ScrollBar(ItemBuyList.ScrollBar)
            S.Button(ItemBuyList.RefreshFrame.RefreshButton)
            hooksecurefunc(ItemBuyList, "RefreshScrollFrame", SkinHeaderRow)
        end

        for _, box in pairs({ _G.AuctionHouseFrameGold, _G.AuctionHouseFrameSilver }) do
            if box then S.EditBox(box) end
        end

        SkinMoneyInput(ItemBuyFrame.BidFrame.BidAmount)
        S.Button(ItemBuyFrame.BidFrame.BidButton)
        ItemBuyFrame.BidFrame.BidButton:ClearAllPoints()
        ItemBuyFrame.BidFrame.BidButton:SetPoint("LEFT", ItemBuyFrame.BidFrame.BidAmount, "RIGHT", 2, -2)

        if _G.BidAmountGold then S.EditBox(_G.BidAmountGold) end
        if _G.BidAmountSilver then S.EditBox(_G.BidAmountSilver) end
    end

    if Frame.ItemSellFrame then
        SkinSellPanel(Frame.ItemSellFrame)
        S.Template(Frame.ItemSellFrame, "Window")
    end
    if Frame.ItemSellList then SkinResultsList(Frame.ItemSellList, true) end
    if Frame.CommoditiesSellFrame then SkinSellPanel(Frame.CommoditiesSellFrame) end
    if Frame.CommoditiesSellList then SkinResultsList(Frame.CommoditiesSellList, true) end
    if Frame.WoWTokenSellFrame then SkinTokenSellPanel(Frame.WoWTokenSellFrame) end

    local AuctionsFrame = _G.AuctionHouseFrameAuctionsFrame
    if AuctionsFrame then
        S.StripTextures(AuctionsFrame)
        SkinItemDisplay(AuctionsFrame)
        S.Button(AuctionsFrame.BuyoutFrame.BuyoutButton)

        local CommoditiesList = AuctionsFrame.CommoditiesList
        if CommoditiesList then
            SkinResultsList(CommoditiesList, true)
            S.Button(CommoditiesList.RefreshFrame.RefreshButton)
        end

        SkinAuctionList(AuctionsFrame.ItemList, true)

        for _, tab in pairs({
            _G.AuctionHouseFrameAuctionsFrameAuctionsTab,
            _G.AuctionHouseFrameAuctionsFrameBidsTab,
        }) do
            SkinPanelTab(tab)
        end

        local SummaryList = AuctionsFrame.SummaryList
        if SummaryList then
            SkinResultsList(SummaryList)
            S.Template(SummaryList, "Window")
        end
        S.Button(AuctionsFrame.CancelAuctionButton)

        local AllAuctionsList = AuctionsFrame.AllAuctionsList
        SkinAuctionList(AllAuctionsList, true, true)

        if SummaryList then
            SummaryList:SetPoint("BOTTOM", AuctionsFrame, "BOTTOM", 0, 0)
        end
        if AllAuctionsList then
            AuctionsFrame.CancelAuctionButton:ClearAllPoints()
            AuctionsFrame.CancelAuctionButton:SetPoint("TOPRIGHT", AllAuctionsList, "BOTTOMRIGHT", -6, 1)
        end

        SkinAuctionList(AuctionsFrame.BidsList, true, true)
        SkinBidFrame(AuctionsFrame.BidFrame)
    end

    local TokenFrame = Frame.WoWTokenResults
    if TokenFrame then
        S.StripTextures(TokenFrame)
        S.Button(TokenFrame.Buyout)
        S.ScrollBar(TokenFrame.DummyScrollBar)

        local Token = TokenFrame.TokenDisplay
        if Token then
            S.StripTextures(Token)
            S.Template(Token, "Window")
            local ItemButton = Token.ItemButton
            if ItemButton then
                S.Icon(ItemButton.Icon, true)

                local ibd = S.GetBackdrop(ItemButton.Icon)
                if ibd then ibd:SetBackdropBorderColor(0, 0.8, 1) end
                local hl = ItemButton:GetHighlightTexture()
                if hl then hl:Hide() end
                if ItemButton.CircleMask then ItemButton.CircleMask:Hide() end
                if ItemButton.IconBorder then ItemButton.IconBorder:SetAlpha(0) end
            end
        end

        local tut = TokenFrame.GameTimeTutorial
        if tut then
            if tut.NineSlice then tut.NineSlice:Hide() end
            S.Template(tut, "Window")
            S.CloseButton(tut.CloseButton)
            S.Button(tut.RightDisplay.StoreButton)
            if tut.Bg then tut.Bg:SetAlpha(0) end
            tut.LeftDisplay.Label:SetTextColor(1, 1, 1)
            tut.LeftDisplay.Tutorial1:SetTextColor(1, 0, 0)
            tut.RightDisplay.Label:SetTextColor(1, 1, 1)
            tut.RightDisplay.Tutorial1:SetTextColor(1, 0, 0)
        end
    end

    if Frame.BuyDialog then
        S.StripTextures(Frame.BuyDialog)
        S.Template(Frame.BuyDialog, "Window")
        S.Button(Frame.BuyDialog.BuyNowButton)
        S.Button(Frame.BuyDialog.CancelButton)
    end

    local multisellFrame = _G.AuctionHouseMultisellProgressFrame
    if multisellFrame then
        S.StripTextures(multisellFrame)
        S.Template(multisellFrame, "Window")

        local progressBar = multisellFrame.ProgressBar
        if progressBar then
            S.StripTextures(progressBar)
            S.StatusBar(progressBar)
            S.ProgressFill(progressBar)
            progressBar.Text:ClearAllPoints()
            progressBar.Text:SetPoint("BOTTOM", progressBar, "TOP", 0, 5)
            S.Icon(progressBar.Icon, true)
        end
        S.CloseButton(multisellFrame.CancelButton)
    end
end

S:Register("Blizzard_AuctionHouseUI", Skin, "AuctionHouse")
