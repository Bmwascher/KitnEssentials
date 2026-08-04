local KE = select(2, ...)
local S = KE.Skins
local _G = _G

local mixinHooked = false

local WHITE = "Interface\\Buttons\\WHITE8x8"
local BRAND = S.palette.brand

local function HideDecorations(frame)
    if frame.NineSlice and frame.NineSlice.SetAlpha then frame.NineSlice:SetAlpha(0) end
    if frame.PortraitOverlay and frame.PortraitOverlay.Hide then frame.PortraitOverlay:Hide() end

    for _, p in ipairs({ frame.portrait, frame.Portrait, _G.CommunitiesFramePortrait,
                         frame.PortraitContainer }) do
        if p and p.SetAlpha then p:SetAlpha(0) end
    end
    if frame.TopTileStreaks and frame.TopTileStreaks.SetAlpha then frame.TopTileStreaks:SetAlpha(0) end

    local mainInset = _G.CommunitiesFrameInset
    if mainInset and mainInset.Bg and mainInset.Bg.Hide then mainInset.Bg:Hide() end
    local list = frame.CommunitiesList or _G.CommunitiesFrameCommunitiesList
    if list then
        for _, k in ipairs({ "FilligreeOverlay", "TopFiligree", "BottomFiligree", "Bg" }) do
            if list[k] and list[k].Hide then list[k]:Hide() end
        end
        local inset = list.InsetFrame
        if inset and inset.NineSlice and inset.NineSlice.SetAlpha then inset.NineSlice:SetAlpha(0) end
    end
end

local function FlattenSelection(frame, alpha, anchor)
    if frame.Selection then
        if frame.Selection.SetAtlas then frame.Selection:SetAtlas(nil) end
        frame.Selection:SetTexture(WHITE)
        frame.Selection:SetVertexColor(BRAND[1], BRAND[2], BRAND[3], alpha or 0.30)
        if anchor then
            frame.Selection:ClearAllPoints()
            frame.Selection:SetPoint("TOPLEFT", anchor, "TOPLEFT", 1, -1)
            frame.Selection:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -1, 1)
        end
    end
    if frame.GetHighlightTexture then
        local hl = frame:GetHighlightTexture()
        if hl then
            hl:SetTexture(WHITE); hl:SetVertexColor(1, 1, 1, 0.12)
            if anchor then
                hl:ClearAllPoints()
                hl:SetPoint("TOPLEFT", anchor, "TOPLEFT", 1, -1)
                hl:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -1, 1)
            end
        end
    end
end

local function SectionBox(parent, flag, tlx, tly, brx, bry)
    if parent[flag] then return end
    local box = CreateFrame("Frame", nil, parent)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", tlx, tly)
    box:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", brx, bry)
    box:SetFrameLevel(math.max((parent:GetFrameLevel() or 1) - 1, 0))
    S.Backdrop(box)
    parent[flag] = box
end

local function StyleReward(child)
    if not child or child.aeRow then return end
    if child.Icon then S.Icon(child.Icon, true) end
    S.StripTextures(child)
    S.Backdrop(child)
    child.aeRow = true
end

local function StyleListEntry(child)

    if not child then return end
    if child.Background and child.Background.Hide then child.Background:Hide() end
    if child.CircleMask and child.CircleMask.Hide then child.CircleMask:Hide() end
    if child.IconRing and child.IconRing.Hide then child.IconRing:Hide() end
    if child.IconBorder and child.IconBorder.Hide then child.IconBorder:Hide() end
    if not child.aeRow then

        if child.Name then
            S.SetFont(child.Name, nil, "OUTLINE")
            child.Name:SetShadowColor(0, 0, 0, 0)
        end
        if child.Icon then S.Icon(child.Icon) end
        local bd = S.Backdrop(child)

        if bd then
            bd:ClearAllPoints()
            bd:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -13)
            bd:SetPoint("BOTTOMRIGHT", child, "BOTTOMRIGHT", -8, 8)
        end
        child.aeRow = true
    end
    FlattenSelection(child, 0.30, S.GetBackdrop(child))
end

local function StyleMemberRow(child)
    if not child then return end
    FlattenSelection(child, 0.30)
    if child.aeMemberRow then return end

    S.FontStringsDeep(child, 12, "OUTLINE", 2)
    child.aeMemberRow = true
end

local function SetEditBoxFontsDeep(frame, size, depth)
    if depth == nil then depth = 3 end
    if not frame or depth < 0 then return end
    if frame.GetObjectType and frame:GetObjectType() == "EditBox" then
        S.SetFont(frame, size)
    end
    if frame.GetChildren then
        for _, c in ipairs({ frame:GetChildren() }) do
            SetEditBoxFontsDeep(c, size, depth - 1)
        end
    end
end

local function SkinClubFinder(cf)
    if not cf or S.data(cf).skinned then return end
    S.StripTextures(cf)
    local ol = cf.OptionsList
    if ol then
        if ol.ClubFilterDropdown then S.DropDown(ol.ClubFilterDropdown) end
        if ol.SortByDropdown then S.DropDown(ol.SortByDropdown) end
        if ol.ClubSizeDropdown then S.DropDown(ol.ClubSizeDropdown) end

        if ol.SearchBox then
            S.EditBox(ol.SearchBox)
            if ol.SearchBox.SetSize then ol.SearchBox:SetSize(118, 20) end
        end
        if ol.Search then
            S.Button(ol.Search)
            if ol.Search.SetSize then ol.Search:SetSize(118, 20) end
            if ol.SearchBox then
                ol.Search:ClearAllPoints()
                ol.Search:SetPoint("TOP", ol.SearchBox, "BOTTOM", 1, -3)
            end
        end

        for _, rf in ipairs({ "TankRoleFrame", "HealerRoleFrame", "DpsRoleFrame" }) do
            local roleFrame = ol[rf]
            local cb = roleFrame and roleFrame.Checkbox
            if cb then
                S.ClearButtonArt(cb)
                local checked = cb.GetCheckedTexture and cb:GetCheckedTexture()
                if checked and KE.Theme and KE.Theme.accent then
                    checked:SetVertexColor(KE.Theme.accent[1], KE.Theme.accent[2], KE.Theme.accent[3])
                end
            end
        end
    end
    if cf.ClubFinderSearchTab then S.ItemButton(cf.ClubFinderSearchTab) end
    if cf.ClubFinderPendingTab then S.ItemButton(cf.ClubFinderPendingTab) end
    S.data(cf).skinned = true
end

local function Skin()
    local frame = _G.CommunitiesFrame
    if not frame then return end
    S.Frame(frame)

    HideDecorations(frame)
    if not frame.aeDecoHook then
        frame:HookScript("OnShow", HideDecorations)
        frame.aeDecoHook = true
    end

    if frame.CloseButton then S.CloseButton(frame.CloseButton) end
    if frame.StreamDropdown then S.DropDown(frame.StreamDropdown) end

    local mmf = frame.MaximizeMinimizeFrame
    if mmf then
        S.MaxMinFrame(mmf)

        if not S.data(mmf).aeDecoHook then
            for _, bn in ipairs({ "MaximizeButton", "MinimizeButton" }) do
                local b = mmf[bn]
                if b then
                    b:HookScript("OnClick", function()
                        HideDecorations(frame)
                    end)
                end
            end
            S.data(mmf).aeDecoHook = true
        end
    end

    local cf = _G.CommunitiesFrame
    if cf then
        if cf.InviteButton then S.Button(cf.InviteButton) end
        local ctrl = cf.CommunitiesControlFrame
        if ctrl then
            for _, key in ipairs({ "GuildRecruitmentButton", "GuildControlButton", "CommunitiesSettingsButton" }) do
                if ctrl[key] then S.Button(ctrl[key]) end
            end
        end
    end

    for _, name in ipairs({ "ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab" }) do
        if frame[name] then S.ItemButton(frame[name]) end
    end

    local gb = frame.GuildBenefitsFrame
    if gb then
        for _, name in ipairs({
            "InsetBorderLeft", "InsetBorderRight", "InsetBorderBottomRight",
            "InsetBorderBottomLeft", "InsetBorderTopRight", "InsetBorderTopLeft",
            "InsetBorderLeft2", "InsetBorderBottomLeft2", "InsetBorderTopLeft2",
        }) do
            if gb[name] and gb[name].Hide then gb[name]:Hide() end
        end
        if gb.Perks then
            if gb.Perks.TitleText then S.SetFont(gb.Perks.TitleText, 14, "OUTLINE") end
            S.StripTextures(gb.Perks)
            if gb.Perks.ScrollBox then S.HookScrollBox(gb.Perks.ScrollBox, StyleReward) end
            if gb.Perks.ScrollBar then S.ScrollBar(gb.Perks.ScrollBar) end
        end
        if gb.Rewards then
            if gb.Rewards.TitleText then S.SetFont(gb.Rewards.TitleText, 14, "OUTLINE") end
            if gb.Rewards.Bg and gb.Rewards.Bg.Hide then gb.Rewards.Bg:Hide() end
            if gb.Rewards.ScrollBox then S.HookScrollBox(gb.Rewards.ScrollBox, StyleReward) end
            if gb.Rewards.ScrollBar then S.ScrollBar(gb.Rewards.ScrollBar) end
        end
    end

    local details = _G.CommunitiesFrameGuildDetailsFrame
    if details then
        for _, name in ipairs({
            "InsetBorderLeft", "InsetBorderRight", "InsetBorderTopLeft", "InsetBorderTopRight",
            "InsetBorderBottomLeft", "InsetBorderBottomRight",
            "InsetBorderLeft2", "InsetBorderTopLeft2", "InsetBorderBottomLeft2",
        }) do
            if details[name] and details[name].Hide then details[name]:Hide() end
        end
    end
    local info = _G.CommunitiesFrameGuildDetailsFrameInfo
    if info then
        S.StripTextures(info)
        S.StripParchment(info)
        S.FontStringsDeep(info, 13, nil, 6)
        SetEditBoxFontsDeep(info, 13, 8)
        if info.TitleText then S.SetFont(info.TitleText, 14, "OUTLINE") end

        local function ForceInfoBodies()
            for _, key in ipairs({
                "CommunitiesFrameGuildDetailsFrameInfoMOTDScrollFrame",
                "CommunitiesFrameGuildDetailsFrameInfoGuildInformationScrollFrame",
            }) do
                local sf = _G[key]
                local body = sf and (sf.MOTD or sf.GuildInformation or sf.EditBox)
                if not body and sf and sf.GetScrollChild then body = sf:GetScrollChild() end
                if body then
                    if body.SetFont then KE:ApplyFont(body, KE.FONT, 13, "") end
                    if body.GetRegions then
                        for _, r in ipairs({ body:GetRegions() }) do
                            if r.IsObjectType and r:IsObjectType("FontString") then
                                KE:ApplyFont(r, KE.FONT, 13, "")
                            end
                        end
                    end
                end
            end
        end
        ForceInfoBodies()
        if not S.data(info).motdHook then
            info:HookScript("OnShow", ForceInfoBodies)
            S.data(info).motdHook = true
        end
        local df = info.DetailsFrame
        if df then
            S.StripTextures(df)
            S.FontStringsDeep(df, 13, nil, 3)
            if df.ScrollBar then S.ScrollBar(df.ScrollBar) end
        end

        SectionBox(info, "aeBox1", 14, -22, 0, 200)
        SectionBox(info, "aeBox2", 14, -158, 0, 118)
        SectionBox(info, "aeBox3", 14, -236, -7, 1)
    end
    local news = _G.CommunitiesFrameGuildDetailsFrameNews
    if news then
        S.StripTextures(news)
        S.StripParchment(news)
        if news.TitleText then S.SetFont(news.TitleText, 14, "OUTLINE") end
        if news.ScrollBar then S.ScrollBar(news.ScrollBar) end

        if news.Container then S.StripTextures(news.Container) end
        S.FontStringsDeep(news, 12, nil, 3)
        if news.ScrollBox then
            S.HookScrollBox(news.ScrollBox, function(row)
                S.StripTextures(row)
                S.FontStringsDeep(row, 12, nil, 2)
            end)
        end

        SectionBox(news, "aeBox4", 7, -22, -13, 1)
    end
    if _G.CommunitiesGuildNewsFiltersFrame then
        S.StripTextures(_G.CommunitiesGuildNewsFiltersFrame)
        S.Backdrop(_G.CommunitiesGuildNewsFiltersFrame)
    end
    if frame.GuildLogButton then S.Button(frame.GuildLogButton) end

    -- Guild Message of the Day editor (ElvUI's
    -- Communities.lua -- same shape as the Guild Log below,
    -- which we already had; this frame was simply never ported).
    local motd = _G.CommunitiesGuildTextEditFrame
    if motd and not S.data(motd).aeMotd then
        S.data(motd).aeMotd = true
        S.StripTextures(motd)
        S.Backdrop(motd)
        if motd.Container and motd.Container.NineSlice then
            S.StripTextures(motd.Container.NineSlice)
            S.Backdrop(motd.Container.NineSlice)
        end
        if motd.Container and motd.Container.ScrollFrame and motd.Container.ScrollFrame.ScrollBar then
            S.TrimScrollBar(motd.Container.ScrollFrame.ScrollBar)
        end
        if _G.CommunitiesGuildTextEditFrameAcceptButton then
            S.Button(_G.CommunitiesGuildTextEditFrameAcceptButton)
        end
        -- ElvUI: closeButton = select(4, frame:GetChildren()) -- the
        -- Cancel button along the bottom, which has no global name.
        local cancel = select(4, motd:GetChildren())
        if cancel and cancel.IsObjectType and cancel:IsObjectType("Button") then
            S.Button(cancel)
        end
        if _G.CommunitiesGuildTextEditFrameCloseButton then
            S.CloseButton(_G.CommunitiesGuildTextEditFrameCloseButton)
        end
    end

    local log = _G.CommunitiesGuildLogFrame
    if log and not S.data(log).aeLog then
        S.StripTextures(log)
        S.Backdrop(log)
        if log.Container and log.Container.NineSlice then
            S.StripTextures(log.Container.NineSlice)
            S.Backdrop(log.Container.NineSlice)
        end
        if log.Container and log.Container.ScrollFrame and log.Container.ScrollFrame.ScrollBar then
            S.TrimScrollBar(log.Container.ScrollFrame.ScrollBar)
        end
        if _G.CommunitiesGuildLogFrameCloseButton then
            S.CloseButton(_G.CommunitiesGuildLogFrameCloseButton)
        end
        local bottomClose = select(3, log:GetChildren())
        if bottomClose and bottomClose.IsObjectType and bottomClose:IsObjectType("Button") then
            S.Button(bottomClose)
        end
        S.data(log).aeLog = true
    end

    local list = frame.CommunitiesList or _G.CommunitiesFrameCommunitiesList
    if list then
        if list.InsetFrame then S.StripTextures(list.InsetFrame) end
        if list.ScrollBox then S.HookScrollBox(list.ScrollBox, StyleListEntry) end
        if list.ScrollBar then S.ScrollBar(list.ScrollBar) end
    end

    if not mixinHooked and _G.CommunitiesListEntryMixin then
        for _, m in ipairs({ "SetAddCommunity", "SetFindCommunity", "SetGuildFinder", "SetClubInfo" }) do
            if _G.CommunitiesListEntryMixin[m] then
                hooksecurefunc(_G.CommunitiesListEntryMixin, m, function(entry)
                    StyleListEntry(entry)
                end)
            end
        end
        mixinHooked = true
    end

    if frame.MemberList then
        S.StripTextures(frame.MemberList)
        local sob = frame.MemberList.ShowOfflineButton
        if sob then
            S.CheckBox(sob)

            S.FontStrings(sob, 12, "")
        end

        if frame.MemberList.InsetFrame and frame.MemberList.InsetFrame.Hide then
            frame.MemberList.InsetFrame:Hide()
        end

        local col = frame.MemberList.ColumnDisplay
        if col then
            S.StripTextures(col)
            for _, k in ipairs({ "InsetBorderLeft", "InsetBorderBottomLeft", "InsetBorderTopLeft", "InsetBorderTop" }) do
                if col[k] and col[k].Hide then col[k]:Hide() end
            end
        end
        if not frame.MemberList.aeColHook and frame.MemberList.RefreshListDisplay then
            hooksecurefunc(frame.MemberList, "RefreshListDisplay", function(ml)
                local cd = ml.ColumnDisplay
                if not cd then return end
                for _, child in ipairs({ cd:GetChildren() }) do
                    if not child.aeCol then
                        S.StripTextures(child)
                        S.Backdrop(child)
                        child.aeCol = true
                    end
                end
            end)
            frame.MemberList.aeColHook = true
        end

        local wm = frame.MemberList.WatermarkFrame
        if wm and wm.SetAlpha then wm:SetAlpha(0) end
        if not frame.MemberList.aeWmHook then
            frame.MemberList:HookScript("OnShow", function(self)
                if self.WatermarkFrame and self.WatermarkFrame.SetAlpha then
                    self.WatermarkFrame:SetAlpha(0)
                end
            end)
            frame.MemberList.aeWmHook = true
        end
        if frame.MemberList.ScrollBox then
            S.HookScrollBox(frame.MemberList.ScrollBox, StyleMemberRow)
        end
        if frame.MemberList.ScrollBar then S.ScrollBar(frame.MemberList.ScrollBar) end
    end

    if frame.GuildMemberListDropdown then
        S.DropDown(frame.GuildMemberListDropdown, true)
    end

    local detail = frame.GuildMemberDetailFrame
    if detail then
        if detail.Border then detail.Border:Hide() end
        S.StripTextures(detail)
        S.Template(detail, "Window")

        S.FontStringsDeep(detail, 12, "OUTLINE", 2)
        if detail.Name then S.SetFont(detail.Name, 14, "OUTLINE") end

        if detail.RankDropdown then detail.RankDropdown:SetHeight(24) end
        if not S.data(detail).snapHooked then
            S.data(detail).snapHooked = true
            detail:HookScript("OnShow", function()
                C_Timer.After(0, function()
                    S.FixSubPixelEdge(detail)
                end)
            end)
        end
        detail:ClearAllPoints()
        detail:SetPoint("TOPLEFT", frame, "TOPRIGHT", -1, -30)
        for _, nb in next, { detail.NoteBackground, detail.OfficerNoteBackground } do
            if nb then
                if nb.NineSlice then nb.NineSlice:SetAlpha(0) end
                S.Template(nb, "Default")
            end
        end
        if detail.CloseButton then S.CloseButton(detail.CloseButton) end
        if detail.GroupInviteButton then S.Button(detail.GroupInviteButton) end
        if detail.RemoveButton then
            S.Button(detail.RemoveButton)
            detail.RemoveButton:ClearAllPoints()
            detail.RemoveButton:SetPoint("BOTTOMLEFT", 10, 4)
        end
        if detail.RankDropdown then
            detail.RankDropdown:ClearAllPoints()
            detail.RankDropdown:SetPoint("LEFT", detail.RankLabel, "RIGHT", 0, -3)
            detail.RankDropdown:SetWidth(150)
            S.DropDown(detail.RankDropdown)
        end
    end
    if frame.Chat then
        S.StripTextures(frame.Chat)
        if frame.Chat.InsetFrame then

            S.StripTextures(frame.Chat.InsetFrame)
            S.Backdrop(frame.Chat.InsetFrame)
        end

        local csb = frame.Chat.ScrollBar
            or (frame.Chat.MessageFrame and frame.Chat.MessageFrame.ScrollBar)
        if csb then S.ScrollBar(csb) end

        if frame.Chat.MessageFrame then
            S.SetFont(frame.Chat.MessageFrame, nil, "OUTLINE")
        end
    end

    if frame.ChatEditBox then
        frame.ChatEditBox:SetAlpha(0)
        if frame.ChatEditBox.EnableMouse then frame.ChatEditBox:EnableMouse(false) end
    end

    if gb and gb.FactionFrame then
        S.StripTextures(gb.FactionFrame)
        S.FontStringsDeep(gb.FactionFrame, 12, nil, 2)
        local bar = gb.FactionFrame.Bar
        if bar then
            S.StripTextures(bar)
            S.StatusBar(bar)
        end
    end

    SkinClubFinder(_G.ClubFinderCommunityAndGuildFinderFrame)
    SkinClubFinder(_G.ClubFinderGuildFinderFrame)

    local rd = frame.RecruitmentDialog
    if rd and not S.data(rd).skinned then
        S.StripTextures(rd)

        if rd.BG then S.StripTextures(rd.BG) end
        S.Backdrop(rd)
        if rd.ShouldListClub and rd.ShouldListClub.Button then S.CheckBox(rd.ShouldListClub.Button) end
        if rd.ClubFocusDropdown then S.DropDown(rd.ClubFocusDropdown) end
        if rd.LookingForDropdown then S.DropDown(rd.LookingForDropdown) end
        if rd.LanguageDropdown then S.DropDown(rd.LanguageDropdown) end
        local msg = rd.RecruitmentMessageFrame
        if msg then
            S.StripTextures(msg)
            if msg.RecruitmentMessageInput then
                S.EditBox(msg.RecruitmentMessageInput)
                if msg.RecruitmentMessageInput.ScrollBar then S.ScrollBar(msg.RecruitmentMessageInput.ScrollBar) end
            end
        end
        if rd.MaxLevelOnly and rd.MaxLevelOnly.Button then S.CheckBox(rd.MaxLevelOnly.Button) end
        if rd.MinIlvlOnly then
            if rd.MinIlvlOnly.Button then S.CheckBox(rd.MinIlvlOnly.Button) end
            if rd.MinIlvlOnly.EditBox then S.EditBox(rd.MinIlvlOnly.EditBox) end
        end
        if rd.Accept then S.Button(rd.Accept) end
        if rd.Cancel then S.Button(rd.Cancel) end
        S.data(rd).skinned = true
    end

end

S:Register("Blizzard_Communities", Skin, "Communities")
