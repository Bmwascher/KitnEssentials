local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local hooksecurefunc = hooksecurefunc

local function Skin()
    local frame = _G.GenericTraitFrame
    if not frame or S.data(frame).skinned then return end
    if frame.Background then frame.Background:SetAlpha(0) end
    if frame.BorderOverlay then frame.BorderOverlay:SetAlpha(0) end
    if frame.NineSlice then
        frame.NineSlice:SetAlpha(0)

        if frame.NineSlice.EnableMouse then frame.NineSlice:EnableMouse(false) end
    end
    S.Backdrop(frame)
    if frame.CloseButton then S.CloseButton(frame.CloseButton) end

    local unspentCount = frame.Currency and frame.Currency.UnspentPointsCount
    if unspentCount then
        S.ReplaceIconString(unspentCount)
        hooksecurefunc(unspentCount, "SetText", S.ReplaceIconString)
    end
    S.data(frame).skinned = true
end

S:Register("Blizzard_GenericTraitUI", Skin, "GenericTrait")
