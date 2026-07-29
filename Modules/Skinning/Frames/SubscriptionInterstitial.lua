local KE = select(2, ...)
local S = KE.Skins
local _G = _G

local function Skin()
    local frame = _G.SubscriptionInterstitialFrame
    if not frame or S.data(frame).skinned then return end
    S.StripTextures(frame)
    S.Backdrop(frame)
    if frame.ShadowOverlay then frame.ShadowOverlay:Hide() end
    if frame.CloseButton then S.CloseButton(frame.CloseButton) end
    if frame.ClosePanelButton then S.Button(frame.ClosePanelButton) end
    S.data(frame).skinned = true
end

S:Register("Blizzard_SubscriptionInterstitialUI", Skin, "SubscriptionInterstitial")
