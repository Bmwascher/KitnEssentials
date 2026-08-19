local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local hooksecurefunc = hooksecurefunc

local function HeaderUpdate(header)
    if header.HighlightTexture then
        header.HighlightTexture:SetColorTexture(S.palette.brand[1], S.palette.brand[2], S.palette.brand[3], 0.15)
        header.HighlightTexture:ClearAllPoints()
        header.HighlightTexture:SetPoint("TOPLEFT", 1, -1)
        header.HighlightTexture:SetPoint("BOTTOMRIGHT", -1, 1)
    end
    if header.NormalTexture then header.NormalTexture:SetTexture() end
    if not S.data(header).skinned then
        S.Backdrop(header)
        S.data(header).skinned = true
    end
end

local function Skin()
    local channelFrame = _G.ChannelFrame
    if channelFrame and not S.data(channelFrame).ported then

        S.Frame(channelFrame)
        if channelFrame.SettingsButton then S.Button(channelFrame.SettingsButton) end
        if channelFrame.ChannelRoster and channelFrame.ChannelRoster.ScrollBar then
            S.TrimScrollBar(channelFrame.ChannelRoster.ScrollBar)
        end
        if channelFrame.NewButton then
            S.Button(channelFrame.NewButton)
            channelFrame.NewButton:ClearAllPoints()
            channelFrame.NewButton:SetPoint("BOTTOMLEFT", channelFrame, 4, 4)
        end
        local channelList = channelFrame.ChannelList
        if channelList and channelList.ScrollBar then
            S.TrimScrollBar(channelList.ScrollBar)
            channelList.ScrollBar:SetPoint("BOTTOMLEFT", channelList, "BOTTOMRIGHT", 0, 15)
        end
        S.data(channelFrame).ported = true
    end

    local popup = _G.CreateChannelPopup
    if popup and not S.data(popup).skinned then
        S.StripTextures(popup)
        S.Backdrop(popup)
        if popup.Header then S.StripTextures(popup.Header) end
        if popup.CloseButton then S.CloseButton(popup.CloseButton) end
        if popup.OKButton then S.Button(popup.OKButton) end
        if popup.CancelButton then S.Button(popup.CancelButton) end
        if popup.Name then S.EditBox(popup.Name) end
        if popup.Password then S.EditBox(popup.Password) end
        S.data(popup).skinned = true
    end

    local voicePrompt = _G.VoiceChatPromptActivateChannel
    if voicePrompt and not S.data(voicePrompt).skinned then
        S.StripTextures(voicePrompt)
        S.Backdrop(voicePrompt)
        if voicePrompt.AcceptButton then S.Button(voicePrompt.AcceptButton) end
        if voicePrompt.CloseButton then S.CloseButton(voicePrompt.CloseButton) end
        S.data(voicePrompt).skinned = true
    end

    if _G.ChannelButtonHeaderMixin and not S.data(_G.ChannelButtonHeaderMixin).hooked then
        hooksecurefunc(_G.ChannelButtonHeaderMixin, "Update", HeaderUpdate)
        S.data(_G.ChannelButtonHeaderMixin).hooked = true
    end
end

S:Register("Blizzard_Channels", Skin, "Channels")
