local KE = select(2, ...)
local S = KE.Skins
local _G = _G

local function Skin()
    local frame = _G.ItemInteractionFrame
    if not frame or S.data(frame).ported then return end

    S.Frame(frame)

    local itemSlot = frame.ItemSlot
    if itemSlot then
        S.StripTextures(itemSlot)
        S.Backdrop(itemSlot)
        itemSlot:SetSize(58, 58)
        itemSlot:ClearAllPoints()
        itemSlot:SetPoint("TOPLEFT", 143, -97)
        if itemSlot.GlowOverlay then itemSlot.GlowOverlay:SetAlpha(0) end
        if itemSlot.Icon then
            itemSlot.Icon:ClearAllPoints()
            itemSlot.Icon:SetPoint("TOPLEFT", 1, -1)
            itemSlot.Icon:SetPoint("BOTTOMRIGHT", -1, 1)
            S.Icon(itemSlot.Icon)
        end
    end

    local buttonFrame = frame.ButtonFrame
    if buttonFrame then
        S.StripTextures(buttonFrame)
        if buttonFrame.ButtonBorder then buttonFrame.ButtonBorder:Hide() end
        if buttonFrame.ButtonBottomBorder then buttonFrame.ButtonBottomBorder:Hide() end
        if buttonFrame.MoneyFrameEdge then buttonFrame.MoneyFrameEdge:SetAlpha(0) end
        if buttonFrame.BlackBorder then buttonFrame.BlackBorder:SetAlpha(0) end
        if buttonFrame.Currency and buttonFrame.Currency.Icon then S.Icon(buttonFrame.Currency.Icon) end
        if buttonFrame.ActionButton then S.Button(buttonFrame.ActionButton) end
    end
    S.data(frame).ported = true
end

S:Register("Blizzard_ItemInteractionUI", Skin, "ItemInteraction")
