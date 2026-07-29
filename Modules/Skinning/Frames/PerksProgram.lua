local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local next = next
local math_max = math.max
local hooksecurefunc = hooksecurefunc

local function QualityRGB(quality)
    local c = _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality or 1]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function LowerPlate(host, below, offset)
    local bd = S.GetBackdrop(host)
    if bd and below then
        bd:SetFrameLevel(math_max(0, below:GetFrameLevel() + (offset or -10)))
    end
    return bd
end

local function SkinSetButton(button)
    if not button or not button.Icon then return end
    if not S.data(button.Icon).skinned then
        S.SlotIcon(button.Icon, button.IconBorder)
        S.data(button.Icon).skinned = true
    end
    if button.BackgroundTexture then button.BackgroundTexture:SetAlpha(0) end
    if button.HighlightTexture then
        button.HighlightTexture:SetColorTexture(1, 1, 1, 0.25)
        button.HighlightTexture:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
        button.HighlightTexture:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    end
end

local function DetailRows(frame)
    if frame.ForEachFrame and frame.view then frame:ForEachFrame(SkinSetButton) end
end

local function SkinCartToggle(button)
    local text = S.data(button).text
    if not text then return end
    text:SetText(button.itemInCart and "-" or "+")
    if button.itemInCart then
        text:SetTextColor(1, 0.3, 0.3)
    else
        text:SetTextColor(0.3, 1, 0.3)
    end
end

local function SkinRewardRow(child)
    local container = child.ContentsContainer
    if not container then return end

    if container.Icon and not S.data(container.Icon).skinned then
        S.Icon(container.Icon)
        if container.IconMask then container.IconMask:Hide() end
        S.data(container.Icon).skinned = true
    end
    if container.PriceIcon and not S.data(container.PriceIcon).skinned then
        S.Icon(container.PriceIcon)
        S.data(container.PriceIcon).skinned = true
    end

    local cartButton = container.CartToggleButton
    if cartButton and not S.data(cartButton).text then
        S.StripTextures(cartButton)
        S.Backdrop(cartButton)
        S.Hover(cartButton)
        local text = cartButton:CreateFontString(nil, "ARTWORK")
        S.SetFont(text, 30, "OUTLINE")
        text:SetPoint("CENTER")
        text:SetTextColor(0.3, 1, 0.3)
        S.data(cartButton).text = text
        SkinCartToggle(cartButton)
        if cartButton.UpdateCartState then
            hooksecurefunc(cartButton, "UpdateCartState", SkinCartToggle)
        end
    end
end

local function RewardRows(frame)
    if frame.ForEachFrame and frame.view then frame:ForEachFrame(SkinRewardRow) end
end

local function SkinCartRow(button)
    if not button then return end

    if button.RemoveFromCartItemButton and button.RemoveFromCartItemButton.RemoveFromListButton then
        S.CloseButton(button.RemoveFromCartItemButton.RemoveFromListButton)
    end

    local d = S.data(button)
    if not d.bgSetTexture then
        d.bgSetTexture = button:CreateTexture(nil, "BACKGROUND")
        d.bgSetTexture:SetTexture("Interface\\Buttons\\WHITE8x8")
        d.bgSetTexture:SetPoint("TOPLEFT", button, "TOPLEFT", -10, 4)
        d.bgSetTexture:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 10, -4)
    end

    if button.BackgroundTexture then
        if not S.data(button.BackgroundTexture).skinned then
            S.data(button.BackgroundTexture).skinned = true
        end
        local ed = button.elementData
        local r, g, b = QualityRGB(ed and ed.itemQuality)
        d.bgSetTexture:SetVertexColor(r, g, b, (ed and ed.isSetItem) and 0.2 or 0)
    else
        d.bgSetTexture:SetVertexColor(0, 0, 0, 0.25)
    end

    if button.TopBraceTexture then S.StripTextures(button.TopBraceTexture) end
    if button.BottomBraceTexture then S.StripTextures(button.BottomBraceTexture) end
    if button.HighlightTexture then
        button.HighlightTexture:SetColorTexture(1, 1, 1, 0.25)
    end
    if button.PriceIcon and not S.data(button.PriceIcon).skinned then
        S.Icon(button.PriceIcon)
        S.data(button.PriceIcon).skinned = true
    end
end

local function CartRows(frame)
    if frame.ForEachFrame and frame.view then frame:ForEachFrame(SkinCartRow) end
end

-- Two states crossed with hover. Green when the purchase can go through,
-- gold when it can't; both brighten under the cursor.
local PURCHASE_LABEL = {
    [true]  = { rest = { 0.3, 0.8, 0.3 }, hover = { 0.3, 1, 0.3 } },
    [false] = { rest = { 1, 0.8, 0 },     hover = { 1, 1, 1 } },
}

local function TintPurchaseLabel(button, hovering)
    local label = button:GetFontString()
    if not label then return end

    local perks = _G.PerksProgramFrame
    local footer = perks and perks.FooterFrame
    local pair = PURCHASE_LABEL[not not (footer and footer.purchaseButtonEnabled)]
    local c = hovering and pair.hover or pair.rest

    label:SetTextColor(c[1], c[2], c[3], 1)
end

local function OnPurchaseGlow(factory, target, show)
    local perks = _G.PerksProgramFrame
    local footer = perks and perks.FooterFrame
    local button = footer and footer.PurchaseButton
    if not button or target ~= button then return end
    if show then factory:Hide(target) end
    TintPurchaseLabel(target, target:IsMouseOver())
end

local function SkinSortLabel(button)
    if button and button.Label then S.SetFont(button.Label) end
end

local function SkinCarouselArrow(button, dir)
    if not button or S.data(button).skinned then return end
    S.ArrowButton(button, dir)
    button:SetScript("OnMouseUp", nil)
    button:SetScript("OnMouseDown", nil)
    S.data(button).skinned = true
end

local function SkinToggle(box)
    if not box then return end
    S.CheckBox(box)
    if box.Text then S.SetFont(box.Text) end
end

-- The cart's clear button has no art of its own, so it gets a cart glyph
-- and a slash drawn over it.
local function SkinCartPane(cart)
    S.StripTextures(cart)
    S.Backdrop(cart)
    if cart.CloseButton then S.CloseButton(cart.CloseButton) end
    if cart.PurchaseCartButton then S.Button(cart.PurchaseCartButton) end
    if cart.ClearCartButton and not S.data(cart.ClearCartButton).text then
        S.Button(cart.ClearCartButton)
        local tex = cart.ClearCartButton:CreateTexture(nil, "ARTWORK")
        tex:SetAtlas("Perks-ShoppingCart")
        tex:SetPoint("TOPLEFT", cart.ClearCartButton, "TOPLEFT", 8, -8)
        tex:SetPoint("BOTTOMRIGHT", cart.ClearCartButton, "BOTTOMRIGHT", -8, 8)
        local text = cart.ClearCartButton:CreateFontString(nil, "ARTWORK")
        S.SetFont(text, 40, "OUTLINE")
        text:SetPoint("CENTER")
        text:SetTextColor(1, 0.3, 0.3)
        text:SetText("/")
        S.data(cart.ClearCartButton).text = text
    end
    if cart.ItemList then
        if cart.ItemList.ScrollBar then S.TrimScrollBar(cart.ItemList.ScrollBar) end
        if cart.ItemList.ScrollBox and not S.data(cart.ItemList.ScrollBox).hooked then
            hooksecurefunc(cart.ItemList.ScrollBox, "Update", CartRows)
            S.data(cart.ItemList.ScrollBox).hooked = true
        end
    end
end

-- Hooking a ScrollBox twice would double every row pass, so each is stamped
-- the first time through.
local function HookScrollBox(container, handler)
    local box = container and container.ScrollBox
    if not box or S.data(box).hooked then return end

    S.data(box).hooked = true
    hooksecurefunc(box, "Update", handler)
end

local function SkinCurrency(currency)
    if currency.Icon then
        S.Icon(currency.Icon, true)
        currency.Icon:SetSize(30, 30)
    end
    if currency.Text then S.SetFont(currency.Text, 30) end
end

local function SkinFilter(filter)
    S.Button(filter)
    if filter.ResetButton then S.CloseButton(filter.ResetButton) end
end

local function SkinDetailsPane(details)
    if details.Border then details.Border:Hide() end
    S.Backdrop(details)
    LowerPlate(details, details.Border, -10)

    local list = details.SetDetailsScrollBoxContainer
    if list then
        if list.ScrollBar then S.TrimScrollBar(list.ScrollBar) end
        HookScrollBox(list, DetailRows)
    end

    local carousel = details.CarouselFrame
    if carousel and carousel.IncrementButton then
        SkinCarouselArrow(carousel.IncrementButton, "right")
        SkinCarouselArrow(carousel.DecrementButton, "left")
    end
end

local function SkinProductList(container)
    S.StripTextures(container)
    S.Backdrop(container)
    LowerPlate(container, container.Border, -10)

    if container.ScrollBar then S.TrimScrollBar(container.ScrollBar) end

    local hold = container.PerksProgramHoldFrame
    if hold then
        S.StripTextures(hold)
        S.Backdrop(hold)
    end

    S.Each(container, SkinSortLabel, "NameSortButton", "PriceSortButton")
    HookScrollBox(container, RewardRows)
end

local function SkinProductsPane(products)
    S.Apply(products, {
        PerksProgramFilter                       = SkinFilter,
        PerksProgramCurrencyFrame                = SkinCurrency,
        PerksProgramProductDetailsContainerFrame = SkinDetailsPane,
        ProductsScrollBoxContainer               = SkinProductList,
        PerksProgramShoppingCartFrame            = SkinCartPane,
    })
end

local function Skin()
    local frame = _G.PerksProgramFrame
    if not frame then return end

    if frame.ThemeContainer then frame.ThemeContainer:SetAlpha(0) end

    S.Apply(frame, { ProductsFrame = SkinProductsPane })

    local footer = frame.FooterFrame
    if footer then
        SkinToggle(footer.ToggleAttackAnimation)
        SkinToggle(footer.TogglePlayerPreview)
        SkinToggle(footer.ToggleMountSpecial)
        SkinToggle(footer.ToggleHideArmor)

        local purchase = footer.PurchaseButton
        if purchase then
            for _, key in next, { "LeaveButton", "RefundButton", "PurchaseButton",
                "ViewCartButton", "AddToCartButton", "RemoveFromCartButton" } do
                if footer[key] then S.Button(footer[key]) end
            end

            local viewCart = footer.ViewCartButton
            if viewCart and not S.data(viewCart).texture then
                if viewCart.ItemCountBG then S.StripTextures(viewCart.ItemCountBG) end
                if viewCart.ItemCountText then
                    viewCart.ItemCountText:ClearAllPoints()
                    viewCart.ItemCountText:SetPoint("BOTTOMLEFT", 4, 2)
                end
                local tex = viewCart:CreateTexture(nil, "ARTWORK")
                tex:SetAtlas("Perks-ShoppingCart")
                tex:SetPoint("TOPLEFT", viewCart, "TOPLEFT", 8, -8)
                tex:SetPoint("BOTTOMRIGHT", viewCart, "BOTTOMRIGHT", -8, 8)
                S.data(viewCart).texture = tex
            end

            purchase:HookScript("OnEnter", function(b) TintPurchaseLabel(b, true) end)
            purchase:HookScript("OnLeave", function(b) TintPurchaseLabel(b) end)

            if _G.GlowEmitterFactory and not S.skinIndex.__perksGlowHook then
                S.skinIndex.__perksGlowHook = true
                hooksecurefunc(_G.GlowEmitterFactory, "Show", function(f, t)
                    OnPurchaseGlow(f, t, true)
                end)
                hooksecurefunc(_G.GlowEmitterFactory, "Hide", function(f, t)
                    OnPurchaseGlow(f, t)
                end)
            end
        end

        local rotate = footer.RotateButtonContainer
        if rotate and rotate.RotateLeftButton then
            S.Button(rotate.RotateLeftButton)
            S.Button(rotate.RotateRightButton)
        end
    end
end

S:Register("Blizzard_PerksProgram", Skin, "PerksProgram")
