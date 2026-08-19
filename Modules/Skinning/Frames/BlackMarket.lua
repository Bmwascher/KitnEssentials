local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local next = next
local hooksecurefunc = hooksecurefunc

local function SkinColumn(tab)
    if not tab then return end
    for _, k in next, { "Left", "Middle", "Right" } do
        if tab[k] then tab[k]:SetAlpha(0) end
    end
end

local function ScrollChild(button)
    if not button or S.data(button).skinned then return end
    if button.Item then
        S.ItemButton(button.Item)
        if button.Item.IconBorder then S.IconBorder(button.Item.IconBorder) end
    end
    S.StripTextures(button)

    S.RowHover(button)
    if button.Selection then button.Selection:SetColorTexture(S.palette.brand[1], S.palette.brand[2], S.palette.brand[3], 0.18) end
    S.data(button).skinned = true
end

local function Skin()
    local frame = _G.BlackMarketFrame
    if not frame then return end
    S.StripTextures(frame)
    S.Backdrop(frame)
    if frame.Inset then S.StripTextures(frame.Inset) S.Backdrop(frame.Inset) end
    if frame.CloseButton then S.CloseButton(frame.CloseButton) end
    if frame.ScrollBar then S.TrimScrollBar(frame.ScrollBar) end
    for _, c in next, { "ColumnName", "ColumnLevel", "ColumnType", "ColumnDuration",
        "ColumnHighBidder", "ColumnCurrentBid" } do
        SkinColumn(frame[c])
    end
    if frame.MoneyFrameBorder then S.StripTextures(frame.MoneyFrameBorder) end
    local bidGold = _G.BlackMarketBidPriceGold
    if bidGold then
        S.EditBox(bidGold)

        local bd = S.GetBackdrop(bidGold)
        if bd then
            bd:ClearAllPoints()
            bd:SetPoint("TOPLEFT", bidGold, "TOPLEFT", -2, 0)
            bd:SetPoint("BOTTOMRIGHT", bidGold, "BOTTOMRIGHT", -2, 0)
        end
    end
    if frame.BidButton then S.Button(frame.BidButton) end

    if frame.ColumnName and frame.TopLeftCorner then
        frame.ColumnName:ClearAllPoints()
        frame.ColumnName:SetPoint("TOPLEFT", frame.TopLeftCorner, 25, -50)
    end
    for _, region in next, { frame:GetRegions() } do
        if region.IsObjectType and region:IsObjectType("FontString") and region:GetText() == _G.BLACK_MARKET_TITLE then
            region:ClearAllPoints()
            region:SetPoint("TOP", frame, "TOP", 0, -4)
        end
    end
    if _G.BlackMarketScrollFrame_Update and frame.ScrollBox then
        hooksecurefunc("BlackMarketScrollFrame_Update", function()
            if frame.ScrollBox.ForEachFrame then frame.ScrollBox:ForEachFrame(ScrollChild) end
        end)
    end
    if frame.HotDeal then
        S.StripTextures(frame.HotDeal)
        S.Backdrop(frame.HotDeal)
        if frame.HotDeal.Item then
            S.ItemButton(frame.HotDeal.Item)
            if frame.HotDeal.Item.IconBorder then S.IconBorder(frame.HotDeal.Item.IconBorder) end
        end
    end

    if _G.BlackMarketFrame_UpdateHotItem then
        hooksecurefunc("BlackMarketFrame_UpdateHotItem", function(item)
            local deal = item.HotDeal
            local link = deal and deal.Name and deal:IsShown() and deal.itemLink
            if not link then return end
            local quality = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(link)
            local color = quality and _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality]
            if color then deal.Name:SetTextColor(color.r, color.g, color.b) end
        end)
    end
end

S:Register("Blizzard_BlackMarketUI", Skin, "BlackMarket")
