local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local CreateFrame = CreateFrame

local function Skin()
    local frame = _G.TradeFrame
    if not frame then return end
    S.Frame(frame)
    if frame.RecipientOverlay then
        if frame.RecipientOverlay.portrait then frame.RecipientOverlay.portrait:SetAlpha(0) end
        if frame.RecipientOverlay.portraitFrame then frame.RecipientOverlay.portraitFrame:SetAlpha(0) end
    end
    if _G.TradeFrameTradeButton then S.Button(_G.TradeFrameTradeButton) end
    if _G.TradeFrameCancelButton then S.Button(_G.TradeFrameCancelButton) end
    for _, name in next, { "TradeRecipientItemsInset", "TradePlayerItemsInset",
        "TradePlayerInputMoneyInset", "TradePlayerEnchantInset",
        "TradeRecipientEnchantInset", "TradeRecipientMoneyInset", "TradeRecipientMoneyBg" } do
        if _G[name] then S.Inset(_G[name]) end
    end

    for i = 1, (_G.MAX_TRADE_ITEMS or 7) do
        for _, side in next, { "TradePlayerItem", "TradeRecipientItem" } do
            local button = _G[side .. i .. "ItemButton"]
            local row = _G[side .. i]
            local nameFrame = _G[side .. i .. "NameFrame"]
            if button and row then
                S.StripTextures(button)
                S.StripTextures(row)
                local icon = _G[side .. i .. "ItemButtonIconTexture"]
                if icon then
                    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
                    icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
                end
                S.Backdrop(button)
                S.Hover(button)

                button:SetFrameLevel(math.max(0, button:GetFrameLevel() - 1))
                if button.IconBorder then S.IconBorder(button.IconBorder, S.GetBackdrop(button)) end
                if nameFrame and not S.data(button).rowBG then
                    local bg = CreateFrame("Frame", nil, button)
                    S.Backdrop(bg)
                    bg:SetPoint("TOPLEFT", button, "TOPRIGHT", 4, 0)
                    bg:SetPoint("BOTTOMRIGHT", nameFrame, "BOTTOMRIGHT", 0, 14)
                    bg:SetFrameLevel(math.max(0, button:GetFrameLevel() - 2))
                    S.data(button).rowBG = bg
                end
            end
        end
    end
end

S:RegisterEarly(Skin, "Trade")
