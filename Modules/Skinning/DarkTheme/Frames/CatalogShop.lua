local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local next = next

local function Skin()
    local frame = _G.CatalogShopFrame
    if not frame then return end
    S.StripTextures(frame)

    S.Backdrop(frame, nil, true)

    if frame.CloseButton then S.CloseButton(frame.CloseButton) end

    local title = frame.TitleContainer
    if title then
        local bd = S.Backdrop(title)
        if bd then
            bd:ClearAllPoints()
            bd:SetPoint("TOPLEFT", frame, "TOPLEFT")
            bd:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -30)
            bd:SetHeight((title:GetHeight() or 24) + 3)
        end
    end

    local header = frame.HeaderFrame
    if header and header.SearchBox then S.EditBox(header.SearchBox) end

    if frame.PortraitContainer then frame.PortraitContainer:SetAlpha(0) end
    if _G.CatalogShopFramePortrait then _G.CatalogShopFramePortrait:SetAlpha(0) end
    local ns = frame.NineSlice
    if ns and ns.TopLeftCorner then S.KillTexture(ns.TopLeftCorner) end

    local products = frame.ProductContainerFrame
    if products and products.ProductsScrollBoxContainer then
        local sb = products.ProductsScrollBoxContainer.ScrollBar
        if sb then S.TrimScrollBar(sb) end
    end

    local details = frame.CatalogShopDetailsFrame
    if details then
        if details.Border then details.Border:Hide() end
        S.StripTextures(details)
        S.Backdrop(details)
        local bc = details.ButtonContainer
        if bc then
            for _, button in next, { bc:GetChildren() } do
                if button and button.IsObjectType and button:IsObjectType("Button") then
                    S.Button(button)
                end
            end
        end
    end

    local pd = frame.ProductDetailsContainerFrame
    if pd then
        if pd.BackButton then S.Button(pd.BackButton) end
        local pc = pd.DetailsProductContainerFrame
        local psc = pc and pc.ProductsScrollBoxContainer
        if psc and psc.ScrollBar then S.TrimScrollBar(psc.ScrollBar) end
    end
end

S:Register("Blizzard_CatalogShop", Skin, "CatalogShop")
