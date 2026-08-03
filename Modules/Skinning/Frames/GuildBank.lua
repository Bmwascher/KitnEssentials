local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local next = next

local NUM_SLOTS = 14
local NUM_COLUMNS = 7

local function SkinIconPopup(popup)
    if not popup or S.data(popup).skinned then return end
    S.StripTextures(popup)
    S.Backdrop(popup)
    if popup.BorderBox then
        S.StripTextures(popup.BorderBox)
        local eb = popup.BorderBox.IconSelectorEditBox
        if eb then S.EditBox(eb) end
        for _, key in next, { "OkayButton", "CancelButton" } do
            if popup.BorderBox[key] then S.Button(popup.BorderBox[key]) end
        end
    end
    if popup.ScrollBar then S.TrimScrollBar(popup.ScrollBar) end
    S.data(popup).skinned = true
end

local function Skin()
    local frame = _G.GuildBankFrame
    if not frame then return end
    S.StripTextures(frame)
    S.Backdrop(frame)
    if frame.CloseButton then S.CloseButton(frame.CloseButton) end
    if frame.Emblem then S.KillTexture(frame.Emblem) end
    if frame.MoneyFrameBG then S.StripTextures(frame.MoneyFrameBG) end
    if frame.DepositButton then S.Button(frame.DepositButton) end
    if frame.WithdrawButton then
        S.Button(frame.WithdrawButton)
        if frame.DepositButton then frame.WithdrawButton:SetPoint("RIGHT", frame.DepositButton, "LEFT", -2, 0) end
    end
    if _G.GuildBankInfoSaveButton then S.Button(_G.GuildBankInfoSaveButton) end
    if frame.BuyInfo and frame.BuyInfo.PurchaseButton then S.Button(frame.BuyInfo.PurchaseButton) end

    if _G.GuildBankInfoScrollFrame then
        S.StripTextures(_G.GuildBankInfoScrollFrame)
        if _G.GuildBankInfoScrollFrame.ScrollBar then S.TrimScrollBar(_G.GuildBankInfoScrollFrame.ScrollBar) end
    end
    if frame.BlackBG then S.Backdrop(frame.BlackBG) end
    if frame.Log and frame.Log.ScrollBar then S.TrimScrollBar(frame.Log.ScrollBar) end

    for i = 1, (_G.MAX_GUILDBANK_TABS or 8) do
        local tab = _G["GuildBankTab" .. i]
        if tab then
            S.StripTextures(tab)
            local button = tab.Button
            if button then
                local icon = button.IconTexture
                local tex = icon and icon:GetTexture()
                S.StripTextures(button)
                S.Backdrop(button)
                if icon then
                    if tex then icon:SetTexture(tex) end
                    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
                    icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
                end
            end
        end
    end

    for i = 1, NUM_COLUMNS do
        local column = frame["Column" .. i]
        if column then
            S.StripTextures(column)
            for x = 1, NUM_SLOTS do
                local button = column["Button" .. x]
                if button then
                    S.ItemButton(button)
                end
            end
        end
    end

    S.Tabs("GuildBankFrameTab", 4)

    local search = _G.GuildItemSearchBox
    if search then
        if search.Left then S.KillTexture(search.Left) end
        if search.Middle then S.KillTexture(search.Middle) end
        if search.Right then S.KillTexture(search.Right) end
        if search.searchIcon then S.KillTexture(search.searchIcon) end
        S.EditBox(search)
    end

    if frame.PopupFrame then frame.PopupFrame:HookScript("OnShow", SkinIconPopup) end
end

S:Register("Blizzard_GuildBankUI", Skin, "GuildBank")
