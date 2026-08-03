local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local next = next

local function Skin()
    local frame = _G.GuildRegistrarFrame
    if not frame then return end
    if S.data(frame).skinned then return end

    S.Frame(frame)
    S.TrimScrollBar(frame.ScrollBar)

    local editBox = _G.GuildRegistrarFrameEditBox
    if _G.GuildRegistrarGreetingFrame then S.StripTextures(_G.GuildRegistrarGreetingFrame) end
    if _G.GuildRegistrarFrameGoodbyeButton then S.Button(_G.GuildRegistrarFrameGoodbyeButton) end
    if _G.GuildRegistrarFrameCancelButton then S.Button(_G.GuildRegistrarFrameCancelButton) end
    if _G.GuildRegistrarFramePurchaseButton then S.Button(_G.GuildRegistrarFramePurchaseButton) end
    if editBox then

        S.EditBox(editBox)

        for _, region in next, { editBox:GetRegions() } do
            if region.IsObjectType and region:IsObjectType("Texture")
                and region.GetDrawLayer and region:GetDrawLayer() == "BACKGROUND" then
                S.KillTexture(region)
            end
        end
        editBox:SetHeight(20)
    end

    for i = 1, 2 do
        local b = _G["GuildRegistrarButton" .. i]
        local fs = b and b.GetFontString and b:GetFontString()
        if fs then fs:SetTextColor(1, 1, 1) end
    end

    if _G.GuildRegistrarPurchaseText then _G.GuildRegistrarPurchaseText:SetTextColor(1, 1, 1) end
    if _G.AvailableServicesText then _G.AvailableServicesText:SetTextColor(1, 1, 0) end
end

S:RegisterEarly(Skin, "GuildRegistrar")
