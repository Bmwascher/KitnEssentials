local KE = select(2, ...)
local S = KE.Skins
local _G = _G

local function Skin()
    local frame = _G.MerchantFrame
    if not frame then return end
    S.Frame(frame)
    S.Tabs("MerchantFrameTab", 2)

    for i = 1, 12 do
        local row = _G["MerchantItem" .. i]
        if row then
            S.StripTextures(row)
            S.Backdrop(row)
        end
        local slot = _G["MerchantItem" .. i .. "SlotTexture"]
        if slot and slot.SetAlpha then slot:SetAlpha(0) end
        S.ItemButton(_G["MerchantItem" .. i .. "ItemButton"])
    end

    local bb = _G.MerchantBuyBackItem
    if bb then
        S.StripTextures(bb)
        S.Backdrop(bb)
    end
    S.ItemButton(_G.MerchantBuyBackItemItemButton)

    for _, name in ipairs({
        "MerchantExtraCurrencyInset", "MerchantExtraCurrencyBg",
        "MerchantMoneyBg", "MerchantMoneyInset",
    }) do
        if _G[name] then S.StripTextures(_G[name]) end
    end

    local function SkinRepairIcon(button)
        if not button or S.data(button).skinned then return end
        local icon = button.Icon
        local atlas = icon and icon.GetAtlas and icon:GetAtlas()

        for _, region in ipairs({ button:GetRegions() }) do
            if region ~= icon and region.IsObjectType and region:IsObjectType("Texture") then
                region:SetAlpha(0)
            end
        end
        S.Backdrop(button)
        local bd = S.GetBackdrop(button)
        if bd then bd:SetFrameLevel(math.max(0, button:GetFrameLevel() - 1)) end
        if icon then
            if atlas then icon:SetAtlas(atlas) end
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            icon:SetDrawLayer("ARTWORK")
            icon:ClearAllPoints()
            icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
            icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
        end
        S.Hover(button)
        S.data(button).skinned = true
    end
    for _, name in ipairs({ "MerchantRepairItemButton", "MerchantRepairAllButton",
        "MerchantGuildBankRepairButton", "MerchantSellAllJunkButton" }) do
        SkinRepairIcon(_G[name])
    end

    if _G.MerchantPrevPageButton then S.ArrowButton(_G.MerchantPrevPageButton, "left") end
    if _G.MerchantNextPageButton then S.ArrowButton(_G.MerchantNextPageButton, "right") end
    if _G.MerchantPageText then S.SetFont(_G.MerchantPageText) end

    local function SkinTokens()
        local i = 1
        while true do
            local token = _G["MerchantToken" .. i]
            if not token then break end
            if not S.data(token).skinned then
                local icon = token.Icon or token.icon
                if icon then
                    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    S.Icon(icon, true)
                end
                local count = token.Count or token.count
                if count then S.SetFont(count) end
                S.data(token).skinned = true
            end
            i = i + 1
        end
    end
    SkinTokens()
    if _G.MerchantFrame_UpdateCurrencies and not S.skinIndex.__merchantTokenHook then
        S.skinIndex.__merchantTokenHook = true
        hooksecurefunc("MerchantFrame_UpdateCurrencies", SkinTokens)
    end
    if frame.FilterDropdown then S.DropDown(frame.FilterDropdown) end

    for i = 1, 12 do
        local item = _G["MerchantItem" .. i]
        if item then item:SetSize(155, 45) end
        local slot = _G["MerchantItem" .. i .. "SlotTexture"]
        if item and item.Name and slot then
            item.Name:SetPoint("LEFT", slot, "RIGHT", -5, 5)
            item.Name:SetSize(110, 30)
        end
        local button = _G["MerchantItem" .. i .. "ItemButton"]
        if button and item then
            button:SetPoint("TOPLEFT", item, "TOPLEFT", 4, -4)
        end
    end

    if _G.MerchantFrame_UpdateRepairButtons and not S.skinIndex.__merchantHooks then
        S.skinIndex.__merchantHooks = true
        hooksecurefunc("MerchantFrame_UpdateRepairButtons", function()
            if _G.MerchantRepairAllButton then
                _G.MerchantRepairAllButton:ClearAllPoints()
                _G.MerchantRepairAllButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", 90, 32)
            end
            if _G.MerchantRepairItemButton and _G.MerchantRepairAllButton then
                _G.MerchantRepairItemButton:ClearAllPoints()
                _G.MerchantRepairItemButton:SetPoint("RIGHT", _G.MerchantRepairAllButton, "LEFT", -5, 0)
            end
            if _G.MerchantSellAllJunkButton and _G.MerchantRepairAllButton then
                _G.MerchantSellAllJunkButton:ClearAllPoints()
                _G.MerchantSellAllJunkButton:SetPoint("RIGHT", _G.MerchantRepairAllButton, "LEFT", 117, 0)
            end
        end)
        if _G.MerchantFrame_UpdateMerchantInfo then
            hooksecurefunc("MerchantFrame_UpdateMerchantInfo", function()
                for i = 1, (_G.MERCHANT_ITEMS_PER_PAGE or 10) do
                    local button = _G["MerchantItem" .. i .. "ItemButton"]
                    local money = _G["MerchantItem" .. i .. "MoneyFrame"]
                    local currency = _G["MerchantItem" .. i .. "AltCurrencyFrame"]
                    if button and money and currency then
                        money:ClearAllPoints()
                        money:SetPoint("BOTTOMLEFT", button, "BOTTOMRIGHT", 5, -3)
                        currency:ClearAllPoints()
                        if button.price and button.extendedCost then
                            currency:SetPoint("LEFT", money, "RIGHT", -8, 0)
                        else
                            currency:SetPoint("BOTTOMLEFT", button, "BOTTOMRIGHT", 5, -3)
                        end
                    end
                end
            end)
        end
    end

    if _G.MerchantGuildBankRepairButton and _G.MerchantRepairAllButton then
        _G.MerchantGuildBankRepairButton:SetPoint("LEFT", _G.MerchantRepairAllButton, "RIGHT", 5, 0)
    end
    if _G.MerchantBuyBackItem and _G.MerchantItem10 then
        _G.MerchantBuyBackItem:SetPoint("TOPLEFT", _G.MerchantItem10, "BOTTOMLEFT", 0, -50)
    end
    if _G.UndoFrame and _G.UndoFrame.Arrow and _G.MerchantBuyBackItemItemButton then
        _G.UndoFrame.Arrow:SetPoint("CENTER", _G.MerchantBuyBackItemItemButton)
    end

    local bbBtn = _G.MerchantBuyBackItemItemButton
    if bbBtn and bbBtn.Count and not S.data(bbBtn).countArmed then
        S.data(bbBtn).countArmed = true
        bbBtn.Count:SetScale(1)
        bbBtn.Count:ClearAllPoints()
        bbBtn.Count:SetPoint("BOTTOMRIGHT", 0, 1)
        if bbBtn.SetItemButtonScale then
            hooksecurefunc(bbBtn, "SetItemButtonScale", function(b, scale)
                if b.Count and scale ~= 1 then b.Count:SetScale(1) end
            end)
        end
        if bbBtn.SetItemButtonAnchorPoint then
            hooksecurefunc(bbBtn, "SetItemButtonAnchorPoint", function(b, point, x, y)
                if b.Count and (point ~= "BOTTOMRIGHT" or x ~= 0 or y ~= 1) then
                    b.Count:ClearAllPoints()
                    b.Count:SetPoint("BOTTOMRIGHT", 0, 1)
                end
            end)
        end
    end
end

S:RegisterEarly(Skin, "Merchant")
