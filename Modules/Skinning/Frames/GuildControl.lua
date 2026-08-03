local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local hooksecurefunc = hooksecurefunc

local function SkinRanks()
    if not _G.GuildControlGetNumRanks then return end
    for i = 1, _G.GuildControlGetNumRanks() do
        local rf = _G["GuildControlUIRankOrderFrameRank" .. i]
        if rf and rf.nameBox and not S.data(rf.nameBox).skinned then
            S.EditBox(rf.nameBox)

            for _, b in next, { rf.downButton, rf.upButton, rf.deleteButton } do
                if b then
                    for _, getter in next, { "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" } do
                        local t = b[getter] and b[getter](b)
                        if t then S.KillTexture(t) end
                    end
                    S.Backdrop(b)
                    S.Hover(b)
                end
            end
            S.data(rf.nameBox).skinned = true
        end
    end
end

local function DressBankTabs()
    if not _G.GetNumGuildBankTabs then return end
    local numTabs = _G.GetNumGuildBankTabs()
    if numTabs < (_G.MAX_BUY_GUILDBANK_TABS or 8) then numTabs = numTabs + 1 end
    for i = 1, numTabs do
        local tab = _G["GuildControlBankTab" .. i]
        if not tab then break end
        if tab.buy and tab.buy.button and not S.data(tab.buy.button).skinned then
            S.Button(tab.buy.button)
            S.data(tab.buy.button).skinned = true
        end
        local owned = tab.owned
        if owned then
            if owned.tabIcon then owned.tabIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
            if owned.editBox and not S.data(owned.editBox).skinned then S.EditBox(owned.editBox) S.data(owned.editBox).skinned = true end
            if owned.viewCB and not S.data(owned.viewCB).skinned then S.CheckBox(owned.viewCB) S.data(owned.viewCB).skinned = true end
            if owned.depositCB and not S.data(owned.depositCB).skinned then S.CheckBox(owned.depositCB) S.data(owned.depositCB).skinned = true end
        end
    end
end

local function Skin()
    local frame = _G.GuildControlUI
    if not frame then return end
    S.StripTextures(frame)
    S.Backdrop(frame)
    if _G.GuildControlUIRankSettingsFrameGoldBox then

        local gb = _G.GuildControlUIRankSettingsFrameGoldBox
        for _, r in next, { gb:GetRegions() } do
            if r.IsObjectType and r:IsObjectType("Texture") then S.KillTexture(r) end
        end

        local bankBg = _G.GuildControlUIRankSettingsFrameBankBg
        if bankBg then
            if bankBg.IsObjectType and bankBg:IsObjectType("Texture") then
                S.KillTexture(bankBg)
            elseif bankBg.GetRegions then
                S.StripTextures(bankBg)
            end
        end
        S.EditBox(gb)
        local bd = S.GetBackdrop and S.GetBackdrop(gb)
        if bd then
            bd:ClearAllPoints()
            bd:SetPoint("TOPLEFT", gb, "TOPLEFT", -2, -4)
            bd:SetPoint("BOTTOMRIGHT", gb, "BOTTOMRIGHT", 2, 4)
        end
    end
    if _G.GuildControlUIRankOrderFrameNewButton then S.Button(_G.GuildControlUIRankOrderFrameNewButton) end
    if _G.GuildControlUICloseButton then S.CloseButton(_G.GuildControlUICloseButton) end
    for _, dd in next, { "GuildControlUIRankBankFrameRankDropdown", "GuildControlUINavigationDropdown",
        "GuildControlUIRankSettingsFrameRankDropdown" } do
        if _G[dd] then S.DropDown(_G[dd], true) end
    end
    if _G.GuildControlUIRankBankFrameInsetScrollFrame and _G.GuildControlUIRankBankFrameInsetScrollFrame.ScrollBar then
        S.TrimScrollBar(_G.GuildControlUIRankBankFrameInsetScrollFrame.ScrollBar)
    end
    for _, name in next, { "GuildControlUIRankBankFrame", "GuildControlUIRankBankFrameInset",
        "GuildControlUIRankBankFrameInsetScrollFrame", "GuildControlUIHbar" } do
        if _G[name] then S.StripTextures(_G[name]) end
    end
    if _G.GuildControlUIRankSettingsFrameOfficerCheckbox then S.CheckBox(_G.GuildControlUIRankSettingsFrameOfficerCheckbox) end
    for i = 1, (_G.NUM_RANK_FLAGS or 0) do
        local cb = _G["GuildControlUIRankSettingsFrameCheckbox" .. i]
        if cb then S.CheckBox(cb) end
    end
    if _G.GuildControlUIRankOrderFrameNewButton then
        _G.GuildControlUIRankOrderFrameNewButton:HookScript("OnClick", function()
            -- v3.5.853: was After(1) -- a brand new rank row sat
            -- unskinned for a full second after clicking New.
            if _G.C_Timer then _G.C_Timer.After(0, SkinRanks) end
        end)
    end
    if _G.GuildControlUI_BankTabPermissions_Update then hooksecurefunc("GuildControlUI_BankTabPermissions_Update", DressBankTabs) end
    if _G.GuildControlUI_RankOrder_Update then hooksecurefunc("GuildControlUI_RankOrder_Update", SkinRanks) end
end

S:Register("Blizzard_GuildControlUI", Skin, "GuildControl")
