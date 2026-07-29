local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local next = next
local pairs = pairs -- luacheck: ignore 211/pairs
local CreateFrame = CreateFrame
local hooksecurefunc = hooksecurefunc

local INVITE_RESTRICTION_NONE = 9
local SUMMON_ICON = 136222
local HOVER = S.palette.hover

local function OnBNetEnter(button)
    local bd = S.GetBackdrop(button)
    local c = _G.FRIENDS_BNET_NAME_COLOR
    if bd and c then bd:SetBackdropBorderColor(c.r, c.g, c.b) end
end

local function OnBNetLeave(button)
    local bd = S.GetBackdrop(button)
    if bd then bd:SetBackdropBorderColor(S.borderColor[1], S.borderColor[2], S.borderColor[3], S.borderColor[4]) end
end

local function OnBNetClick()
    local f = _G.FriendsFrameBattlenetFrame
    if f and f.BroadcastFrame and f.BroadcastFrame.ToggleFrame then f.BroadcastFrame:ToggleFrame() end
end

local function RecruitRewardBorder(button)
    if not (button and button.Icon and button.item) then return end
    local ok, quality = pcall(button.item.GetItemQuality, button.item)
    local color = ok and quality and _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality]
    local bd = S.GetBackdrop(button.Icon)
    if color and bd then bd:SetBackdropBorderColor(color.r, color.g, color.b) end
end

local function SkinRecruitRewards()
    local raf = _G.RecruitAFriendFrame
    local claiming = raf and raf.RewardClaiming
    if claiming and claiming.NextRewardButton and claiming.NextRewardButton.Icon then
        claiming.NextRewardButton.Icon:SetDesaturation(0)
    end
    local rewardsFrame = _G.RecruitAFriendRewardsFrame
    if not rewardsFrame then return end
    if rewardsFrame.rewardTabPool then
        for tab in rewardsFrame.rewardTabPool:EnumerateActive() do
            if not S.data(tab).skinned then
                S.Backdrop(tab)
                S.Hover(tab)
                if tab.Tab then tab.Tab:Hide() end
                local _, relativeTo = tab:GetPoint()
                if relativeTo and relativeTo == rewardsFrame and tab.AdjustPointsOffset then
                    tab:AdjustPointsOffset(2, 0)
                end
                S.data(tab).skinned = true
            end
        end
    end
    if rewardsFrame.rewardPool then
        for reward in rewardsFrame.rewardPool:EnumerateActive() do
            local button = reward.Button
            if button then
                S.RowHover(button)
                if button.IconOverlay then button.IconOverlay:SetAlpha(0) end
                if button.IconBorder then button.IconBorder:SetAlpha(0) end
                if button.Icon then
                    button.Icon:SetDesaturation(0)
                    S.Icon(button.Icon, true)
                end
                RecruitRewardBorder(button)
            end
            if reward.Months then reward.Months:SetTextColor(1, 1, 1) end
        end
    end
end

local InviteAtlas = {
    ["friendslist-invitebutton-horde-normal"] = [[Interface\FriendsFrame\PlusManz-Horde]],
    ["friendslist-invitebutton-alliance-normal"] = [[Interface\FriendsFrame\PlusManz-Alliance]],
    ["friendslist-invitebutton-default-normal"] = [[Interface\FriendsFrame\PlusManz-PlusManz]],
}

-- Blizzard swaps the invite button's atlas to signal state; we mirror that onto
-- our own icon. The link lives in S.data rather than as a field on Blizzard's
-- texture -- we do not write onto their objects.
local function MirrorInviteAtlas(normalTexture, atlas)
    local icon = S.data(normalTexture).aeIcon
    local file = InviteAtlas[atlas]

    if icon and file then icon:SetTexture(file) end
end

local function SkinFriendRow(button)
    if S.data(button).skinned then return end
    S.data(button).skinned = true

    local summon = button.summonButton
    if summon then
        S.Backdrop(summon)
        summon:SetSize(24, 24)

        for _, tex in next, { summon:GetHighlightTexture(), summon.PushedTexture, summon.NormalTexture } do
            if tex then
                tex:SetTexture(SUMMON_ICON)
                tex:SetTexCoord(0.12, 0.88, 0.12, 0.88)
                tex:ClearAllPoints()
                tex:SetPoint("TOPLEFT", summon, "TOPLEFT", 1, -1)
                tex:SetPoint("BOTTOMRIGHT", summon, "BOTTOMRIGHT", -1, 1)
            end
        end

        if summon.PushedTexture then
            summon.PushedTexture:SetBlendMode("ADD")
            summon.PushedTexture:SetColorTexture(0.9, 0.8, 0.1, 0.3)
        end

        S.Vanish(summon, { "SlotBackground", "SlotArt" })
    end

    local invite = button.travelPassButton
    if invite then
        invite:SetSize(24, 24)
        invite:ClearAllPoints()
        invite:SetPoint("TOPRIGHT", -4, -5)
        S.Backdrop(invite)
        S.Vanish(invite, { "NormalTexture", "PushedTexture", "DisabledTexture" })
        if invite.HighlightTexture then
            invite.HighlightTexture:SetColorTexture(HOVER[1], HOVER[2], HOVER[3], HOVER[4])
            invite.HighlightTexture:SetAllPoints()
        end

        local icon = invite:CreateTexture(nil, "ARTWORK")
        icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        icon:SetAllPoints()
        S.data(button).inviteIcon = icon

        if invite.NormalTexture then
            S.data(invite.NormalTexture).aeIcon = icon
            hooksecurefunc(invite.NormalTexture, "SetAtlas", MirrorInviteAtlas)
        end
    end

    local gameIcon = button.gameIcon
    if gameIcon then
        gameIcon:SetSize(26, 26)
        gameIcon:SetTexCoord(0, 1, 0, 1)
        if invite then
            gameIcon:ClearAllPoints()
            gameIcon:SetPoint("RIGHT", invite, "LEFT", -6, 0)
        end
    end

    -- Name, note and location. nil size keeps Blizzard's per-line sizing and
    -- only adds the outline; colours are untouched, so class and status
    -- colouring still comes through.
    S.FontStringsDeep(button, nil, "OUTLINE")

    button:SetHighlightTexture([[Interface\Buttons\WHITE8x8]])
    local bhl = button:GetHighlightTexture()
    if bhl then bhl:SetVertexColor(HOVER[1], HOVER[2], HOVER[3], HOVER[4]) end
end

-- The invite icon dims when the account cannot currently be invited.
local function OnFriendRowUpdate(button)
    if button.gameIcon then SkinFriendRow(button) end

    local icon = S.data(button).inviteIcon
    if not icon or button.buttonType ~= _G.FRIENDS_BUTTON_TYPE_BNET then return end
    if not _G.FriendsFrame_GetInviteRestriction then return end

    local open = _G.FriendsFrame_GetInviteRestriction(button.id) == INVITE_RESTRICTION_NONE
    local shade = open and 1 or 0.5

    icon:SetVertexColor(shade, shade, shade)
end

local function SkinInviteRow(button)
    if not S.data(button).skinned then
        S.Button(button.AcceptButton)
        S.Button(button.DeclineButton)
        S.data(button).skinned = true
    end
end

local function SkinInviteHeader(button)
    if not S.data(button).skinned then
        button:DisableDrawLayer("BACKGROUND")
        local bd = S.Backdrop(button, 2)
        local highlight = button:GetHighlightTexture()
        if highlight then
            highlight:SetColorTexture(HOVER[1], HOVER[2], HOVER[3], HOVER[4])
            if bd then
                highlight:ClearAllPoints()
                highlight:SetPoint("TOPLEFT", bd, "TOPLEFT", 1, -1)
                highlight:SetPoint("BOTTOMRIGHT", bd, "BOTTOMRIGHT", -1, 1)
            end
        end
        S.data(button).skinned = true
    end
end

-- The tab row is deliberately moved below the frame rather than sitting inside
-- it, so the anchors here are ours by intent, not a fight with Blizzard.
local TAB_ROW_OFFSET_X, TAB_ROW_OFFSET_Y = -3, -32
local TAB_OVERLAP = -5

local function SkinTabRow()
    local previous

    for index = 1, math.huge do
        local tab = _G["FriendsFrameTab" .. index]
        if not tab then break end

        S.Tab(tab)
        tab:ClearAllPoints()

        if previous then
            tab:SetPoint("TOPLEFT", previous, "TOPRIGHT", TAB_OVERLAP, 0)
        else
            tab:SetPoint("BOTTOMLEFT", _G.FriendsFrame, "BOTTOMLEFT",
                TAB_ROW_OFFSET_X, TAB_ROW_OFFSET_Y)
        end

        previous = tab
    end
end

local function Skin()
    local frame = _G.FriendsFrame
    if not frame then return end

    for _, sb in next, {
        _G.FriendsListFrame and _G.FriendsListFrame.ScrollBar,
        _G.RecentAlliesFrame and _G.RecentAlliesFrame.List and _G.RecentAlliesFrame.List.ScrollBar,
        _G.WhoFrame and _G.WhoFrame.ScrollBar,
        _G.FriendsFriendsFrame and _G.FriendsFriendsFrame.ScrollBar,
        _G.QuickJoinFrame and _G.QuickJoinFrame.ScrollBar,
    } do
        S.TrimScrollBar(sb)
    end

    for _, name in next, { "FriendsFrameAddFriendButton", "FriendsFrameSendMessageButton",
        "WhoFrameWhoButton", "WhoFrameAddFriendButton", "WhoFrameGroupInviteButton",
        "AddFriendEntryFrameAcceptButton", "AddFriendEntryFrameCancelButton" } do
        if _G[name] then S.Button(_G[name]) end
    end

    for _, name in next, { "WhoFrameColumnHeader1", "WhoFrameColumnHeader2",
        "WhoFrameColumnHeader3", "WhoFrameColumnHeader4", "AddFriendFrame" } do
        if _G[name] then S.StripTextures(_G[name]) end
    end

    S.Frame(frame)
    if _G.FriendsFrameIcon then _G.FriendsFrameIcon:Hide() end
    if _G.FriendsFrameStatusDropdown then
        S.DropDown(_G.FriendsFrameStatusDropdown)

        _G.FriendsFrameStatusDropdown:SetWidth(70)
    end

    local bnet = _G.FriendsFrameBattlenetFrame
    if bnet then
        S.StripTextures(bnet)
        S.Backdrop(bnet)
        if bnet.ContactsMenuButton then
            S.Button(bnet.ContactsMenuButton)
            bnet.ContactsMenuButton:SetSize(31, 31)
        end

        local bnetColor = _G.FRIENDS_BNET_BACKGROUND_COLOR
        local bar = CreateFrame("Button", nil, bnet)
        bar:SetPoint("TOPLEFT", bnet, "TOPLEFT")
        bar:SetPoint("BOTTOMRIGHT", bnet, "BOTTOMRIGHT")
        local barBD = S.Backdrop(bar)
        if barBD and bnetColor then
            barBD:SetBackdropColor(bnetColor.r, bnetColor.g, bnetColor.b, bnetColor.a)
        end
        bar:SetScript("OnClick", OnBNetClick)
        bar:SetScript("OnEnter", OnBNetEnter)
        bar:SetScript("OnLeave", OnBNetLeave)

        local unavailable = bnet.UnavailableInfoFrame
        if unavailable then
            if unavailable.Bg then unavailable.Bg:SetTexture(nil) end
            S.Backdrop(unavailable)
            unavailable:ClearAllPoints()
            unavailable:SetPoint("TOPLEFT", frame, "TOPRIGHT", 1, -18)
        end

        local broadcast = bnet.BroadcastFrame
        if broadcast then
            S.StripTextures(broadcast)
            S.Backdrop(broadcast)
            broadcast:ClearAllPoints()
            broadcast:SetPoint("TOPLEFT", frame, "TOPRIGHT", 3, -1)
            if broadcast.UpdateButton then S.Button(broadcast.UpdateButton) end
            if broadcast.CancelButton then S.Button(broadcast.CancelButton) end
            local edit = broadcast.EditBox
            if edit then
                for _, name in next, { "BottomBorder", "BottomLeftBorder", "BottomRightBorder",
                    "LeftBorder", "MiddleBorder", "RightBorder", "TopBorder", "TopLeftBorder",
                    "TopRightBorder" } do
                    if edit[name] then edit[name]:Hide() end
                end
                S.EditBox(edit)
            end
        end
    end

    if _G.AddFriendNameEditBox then S.EditBox(_G.AddFriendNameEditBox) end
    if _G.AddFriendFrame then S.Backdrop(_G.AddFriendFrame) end

    if _G.FriendsFrame_UpdateFriendButton then hooksecurefunc("FriendsFrame_UpdateFriendButton", OnFriendRowUpdate) end
    if _G.FriendsFrame_UpdateFriendInviteButton then hooksecurefunc("FriendsFrame_UpdateFriendInviteButton", SkinInviteRow) end
    if _G.FriendsFrame_UpdateFriendInviteHeaderButton then hooksecurefunc("FriendsFrame_UpdateFriendInviteHeaderButton", SkinInviteHeader) end

    local ignore = frame.IgnoreListWindow
    if ignore then
        S.StripTextures(ignore)
        S.Backdrop(ignore)
        if ignore.ScrollBar then S.TrimScrollBar(ignore.ScrollBar) end
        if ignore.UnignorePlayerButton then S.Button(ignore.UnignorePlayerButton) end
        if ignore.CloseButton then S.CloseButton(ignore.CloseButton) end
    end

    if _G.WhoFrame then S.StripTextures(_G.WhoFrame) end
    if _G.WhoFrameListInset then
        S.StripTextures(_G.WhoFrameListInset)
        if _G.WhoFrameListInset.NineSlice then _G.WhoFrameListInset.NineSlice:Hide() end
    end
    local whoEdit = _G.WhoFrameEditBox
    if whoEdit then

        local wb = whoEdit.Backdrop
        if wb then
            if wb.IsObjectType and wb:IsObjectType("Texture") then
                S.KillTexture(wb)
            else
                S.StripTextures(wb)
                if wb.SetBackdrop then wb:SetBackdrop(nil) end
            end
        end
        S.EditBox(whoEdit)
    end
    if _G.WhoFrameColumn_SetWidth and _G.WhoFrameColumnHeader3 then
        _G.WhoFrameColumn_SetWidth(_G.WhoFrameColumnHeader3, 37)
    end
    for i = 1, 17 do
        local level = _G["WhoFrameButton" .. i .. "Level"]
        if level then level:SetWidth(level:GetWidth() + 5) end
    end
    if _G.WhoFrameDropdown then
        S.DropDown(_G.WhoFrameDropdown)
        _G.WhoFrameDropdown:SetWidth(90)
    end

    SkinTabRow()
    if _G.FriendsTabHeader and _G.FriendsTabHeader.TabSystem then
        for _, tab in next, { _G.FriendsTabHeader.TabSystem:GetChildren() } do
            S.Tab(tab)
        end
    end

    local fff = _G.FriendsFriendsFrame
    if fff then
        if fff.ScrollFrameBorder then fff.ScrollFrameBorder:Hide() end
        S.StripTextures(fff)
        S.Backdrop(fff)
        if _G.FriendsFriendsFrameDropdown then
            S.DropDown(_G.FriendsFriendsFrameDropdown)
            _G.FriendsFriendsFrameDropdown:SetWidth(150)
        end
        if fff.SendRequestButton then S.Button(fff.SendRequestButton) end
        if fff.CloseButton then S.Button(fff.CloseButton) end
    end

    local qj = _G.QuickJoinFrame
    if qj and qj.JoinQueueButton then
        S.Button(qj.JoinQueueButton)
        qj.JoinQueueButton:SetSize(131, 21)
        qj.JoinQueueButton:ClearAllPoints()
        qj.JoinQueueButton:SetPoint("BOTTOMRIGHT", qj, "BOTTOMRIGHT", -6, 4)
    end
    local qjRole = _G.QuickJoinRoleSelectionFrame
    if qjRole then
        S.StripTextures(qjRole)
        S.Backdrop(qjRole)
        if qjRole.AcceptButton then S.Button(qjRole.AcceptButton) end
        if qjRole.CancelButton then S.Button(qjRole.CancelButton) end
        if qjRole.CloseButton then S.CloseButton(qjRole.CloseButton) end
        for _, key in next, { "RoleButtonTank", "RoleButtonHealer", "RoleButtonDPS" } do
            local rb = qjRole[key]
            if rb and rb.CheckButton then S.CheckBox(rb.CheckButton) end
        end
    end

    local raf = _G.RecruitAFriendFrame
    if raf then
        if raf.RecruitmentButton then S.Button(raf.RecruitmentButton) end

        local splash = raf.SplashFrame
        if splash then
            if splash.OKButton then S.Button(splash.OKButton) end

            if splash.Background then
                splash.Background:SetColorTexture(S.borderColor[1], S.borderColor[2], S.borderColor[3])
            end
            for _, key in next, { "PictureFrame", "Bracket_TopLeft", "Bracket_TopRight",
                "Bracket_BottomRight", "Bracket_BottomLeft", "PictureFrame_Bracket_TopLeft",
                "PictureFrame_Bracket_TopRight", "PictureFrame_Bracket_BottomRight",
                "PictureFrame_Bracket_BottomLeft" } do
                if splash[key] then splash[key]:Hide() end
            end
        end

        local claiming = raf.RewardClaiming
        if claiming then
            S.StripTextures(claiming)
            S.Backdrop(claiming)
            claiming:SetPoint("TOPLEFT", 4, -84)
            if claiming.Background then claiming.Background:SetAlpha(0) end
            if claiming.Watermark then claiming.Watermark:SetAlpha(0) end
            if claiming.ClaimOrViewRewardButton then S.Button(claiming.ClaimOrViewRewardButton) end
            local nextReward = claiming.NextRewardButton
            if nextReward then
                if nextReward.Icon then S.Icon(nextReward.Icon, true) end
                if nextReward.CircleMask then nextReward.CircleMask:Hide() end
                if nextReward.IconBorder then nextReward.IconBorder:SetAlpha(0) end
                if nextReward.IconOverlay then nextReward.IconOverlay:SetAlpha(0) end
                RecruitRewardBorder(nextReward)
            end
        end

        local recruits = raf.RecruitList
        if recruits then
            if recruits.Header then S.StripTextures(recruits.Header) end
            if recruits.ScrollFrameInset then
                S.StripTextures(recruits.ScrollFrameInset)
                S.Backdrop(recruits.ScrollFrameInset)
            end
            if recruits.ScrollBar then S.TrimScrollBar(recruits.ScrollBar) end
        end
    end

    local recruitment = _G.RecruitAFriendRecruitmentFrame
    if recruitment then
        S.StripTextures(recruitment)
        S.Backdrop(recruitment)
        if recruitment.EditBox then S.EditBox(recruitment.EditBox) end
        if recruitment.GenerateOrCopyLinkButton then S.Button(recruitment.GenerateOrCopyLinkButton) end
        if recruitment.CloseButton then S.CloseButton(recruitment.CloseButton) end
    end

    local rewardsFrame = _G.RecruitAFriendRewardsFrame
    if rewardsFrame then
        S.StripTextures(rewardsFrame)
        S.Backdrop(rewardsFrame)
        if rewardsFrame.Background then rewardsFrame.Background:SetAlpha(0) end
        if rewardsFrame.Watermark then rewardsFrame.Watermark:SetAlpha(0) end
        if rewardsFrame.CloseButton then S.CloseButton(rewardsFrame.CloseButton) end
        hooksecurefunc(rewardsFrame, "UpdateRewards", SkinRecruitRewards)
        SkinRecruitRewards()
    end
end

S:RegisterEarly(Skin, "Friends")
