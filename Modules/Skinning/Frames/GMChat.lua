---@class KE
local KE = select(2, ...)
local S = KE.Skins
local _G = _G

local function Skin()
    local frame = _G.GMChatFrame
    if not frame or S.data(frame).skinned then return end
    frame:SetClampRectInsets(0, 0, 0, 0)
    S.StripTextures(frame)
    S.Backdrop(frame)
    if frame.buttonFrame then frame.buttonFrame:Hide() end

    if frame.ScrollBar then
        frame.ScrollBar:ClearAllPoints()
        frame.ScrollBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -6)
        frame.ScrollBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 6)
    end

    local editbox = frame.editBox
    if editbox then
        editbox:SetAltArrowKeyMode(false)

        S.EditBox(editbox, true)
        editbox:ClearAllPoints()
        editbox:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -5)
        editbox:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, -32)
    end

    for _, name in ipairs({ "GMChatFrameEditBoxRight", "GMChatFrameEditBoxLeft",
        "GMChatFrameEditBoxMid", "GMChatFrameEditBoxFocusRight",
        "GMChatFrameEditBoxFocusLeft", "GMChatFrameEditBoxFocusMid" }) do
        if _G[name] then _G[name]:SetAlpha(0) end
    end

    local lang = _G.GMChatFrameEditBoxLanguage
    if lang and editbox then
        local region = lang:GetRegions()
        if region and region.SetAlpha then region:SetAlpha(0) end
        lang:ClearAllPoints()
        lang:SetPoint("TOPLEFT", editbox, "TOPRIGHT", 3, 0)
        lang:SetPoint("BOTTOMRIGHT", editbox, "BOTTOMRIGHT", 28, 0)
    end

    local tab = _G.GMChatTab
    if tab then
        S.StripTextures(tab)
        local bd = S.Backdrop(tab)
        if bd then bd:SetBackdropColor(0, 0.6, 1, 0.3) end
        tab:ClearAllPoints()
        tab:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2)
        tab:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 28)
    end
    if _G.GMChatTabIcon then _G.GMChatTabIcon:SetTexture([[Interface\ChatFrame\UI-ChatIcon-Blizz]]) end

    local close = _G.GMChatFrameCloseButton
    if close and tab then
        close:ClearAllPoints()
        close:SetPoint("RIGHT", tab, -5, 0)
        S.CloseButton(close)
    end
    S.data(frame).skinned = true
end

S:Register("Blizzard_GMChatUI", Skin, "GMChat")
