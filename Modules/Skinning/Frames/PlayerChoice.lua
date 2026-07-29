local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local pairs = pairs
local hooksecurefunc = hooksecurefunc

local TEXTURE_KITS = {
    jailerstower = true,
    cypherchoice = true,
    genericplayerchoice = true,
}

local function SetupButtons(buttons)
    if buttons and buttons.buttonFramePool then
        for buttonFrame in buttons.buttonFramePool:EnumerateActive() do
            if buttonFrame.Button and not S.data(buttonFrame).skinned then
                S.Button(buttonFrame.Button)
                S.data(buttonFrame).skinned = true
            end
        end
    end
end

local function SetupRewards(rewards)
    if rewards and rewards.rewardsPool then
        for reward in rewards.rewardsPool:EnumerateActive() do
            if reward.Name then reward.Name:SetTextColor(1, 1, 1) end
            local item = reward.itemButton
            if item and not S.data(item).skinned then
                S.ItemButton(item)
                if item.IconBorder then S.IconBorder(item.IconBorder) end
                S.data(item).skinned = true
            end
        end
    end
end

local function DressSpellWidget(spell)
    if spell.Icon and not S.data(spell.Icon).skinned then
        S.Icon(spell.Icon, true)
        S.data(spell.Icon).skinned = true
    end
    if spell.IconMask then spell.IconMask:Hide() end
    if spell.Border then spell.Border:SetAlpha(0) end
    if spell.Text then spell.Text:SetTextColor(1, 0.8, 0) end
end

local function SetupOptions(frame)
    if not S.data(frame).skinned then
        if frame.BlackBackground then frame.BlackBackground:SetAlpha(0) end
        if frame.Background then frame.Background:SetAlpha(0) end
        if frame.NineSlice then frame.NineSlice:SetAlpha(0) end
        if frame.BorderOverlay then frame.BorderOverlay:SetAlpha(0) end
        if frame.Title then
            frame.Title:DisableDrawLayer("BACKGROUND")
            if frame.Title.Text then frame.Title.Text:SetTextColor(1, 0.8, 0) end
        end
        if frame.CloseButton then S.CloseButton(frame.CloseButton) end
        S.data(frame).skinned = true
    end

    if frame.CloseButton and frame.CloseButton.Border then
        frame.CloseButton.Border:SetAlpha(0)
    end

    local kit = TEXTURE_KITS[frame.uiTextureKit]
    if not kit then
        S.Backdrop(frame)
    else
        local bd = S.GetBackdrop(frame)
        if bd then bd:Hide() end
    end

    if frame.optionFrameTemplate and frame.optionPools then
        for option in frame.optionPools:EnumerateActiveByTemplate(frame.optionFrameTemplate) do
            local header = option.Header
            local contents = header and header.Contents
            if contents and contents.Text then contents.Text:SetTextColor(1, 0.8, 0) end
            if header and header.Text then header.Text:SetTextColor(1, 0.8, 0) end
            if option.OptionText then option.OptionText:SetTextColor(1, 1, 1) end
            if not kit then
                if option.Background then option.Background:SetAlpha(0) end
                if header and header.Ribbon then header.Ribbon:SetAlpha(0) end
            end
            if option.Artwork and kit then option.Artwork:SetSize(64, 64) end

            SetupRewards(option.rewards)
            SetupButtons(option.buttons)

            local container = option.WidgetContainer
            if container and container.widgetFrames then
                for _, wf in pairs(container.widgetFrames) do
                    if wf.Text then wf.Text:SetTextColor(1, 1, 1) end
                    if wf.Label then wf.Label:SetTextColor(1, 1, 1) end
                    if wf.Spell then DressSpellWidget(wf.Spell) end
                end
            end
        end
    end
end

local function Skin()
    if _G.GenericPlayerChoiceToggleButton then
        S.Button(_G.GenericPlayerChoiceToggleButton)
    end
    if _G.PlayerChoiceFrame then
        hooksecurefunc(_G.PlayerChoiceFrame, "SetupOptions", SetupOptions)
    end
end

S:Register("Blizzard_PlayerChoice", Skin, "PlayerChoice")
