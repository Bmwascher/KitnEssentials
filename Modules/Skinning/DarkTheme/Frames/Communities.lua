local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local unpack = unpack

local mixinHooked = false

local WHITE = "Interface\\Buttons\\WHITE8x8"

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

local function FlattenSelection(frame, anchor)
    if frame.Selection then
        if frame.Selection.SetAtlas then frame.Selection:SetAtlas(nil) end
        frame.Selection:SetTexture(WHITE)
        S.PaintBrand(frame.Selection, "SetVertexColor", S.palette.selectedA)
        if anchor then S.InsetToEdge(frame.Selection, anchor) end
    end
    if frame.GetHighlightTexture then
        local hl = frame:GetHighlightTexture()
        if hl then
            hl:SetTexture(WHITE); hl:SetVertexColor(1, 1, 1, 0.12)
            if anchor then S.InsetToEdge(hl, anchor) end
        end
    end
end

local function SectionBox(parent, flag, tlx, tly, brx, bry)
    if S.data(parent)[flag] then return end
    local box = CreateFrame("Frame", nil, parent)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", tlx, tly)
    box:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", brx, bry)
    S.RelevelPlate(parent, box)
    S.Backdrop(box)
    S.data(parent)[flag] = box
end

local function StyleReward(child)
    if not child or S.data(child).keRow then return end
    if child.Icon then S.Icon(child.Icon, true) end
    S.StripTextures(child)
    S.Backdrop(child)
    S.data(child).keRow = true
end

local function StyleListEntry(child)

    if not child then return end
    if child.Background and child.Background.Hide then child.Background:Hide() end
    if child.CircleMask and child.CircleMask.Hide then child.CircleMask:Hide() end
    if child.IconRing and child.IconRing.Hide then child.IconRing:Hide() end
    if child.IconBorder and child.IconBorder.Hide then child.IconBorder:Hide() end
    if not S.data(child).keRow then

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
        S.data(child).keRow = true
    end
    FlattenSelection(child, S.GetBackdrop(child))
end

local function StyleMemberRow(child)
    if not child then return end
    FlattenSelection(child)
    if S.data(child).keMemberRow then return end

    S.FontStringsDeep(child, 12, "OUTLINE", 2)
    S.data(child).keMemberRow = true
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
                local accent = KE.GetSkinBrandColor and KE:GetSkinBrandColor()
                if checked and accent then
                    checked:SetVertexColor(accent[1], accent[2], accent[3])
                end
            end
        end
    end
    if cf.ClubFinderSearchTab then S.ItemButton(cf.ClubFinderSearchTab) end
    if cf.ClubFinderPendingTab then S.ItemButton(cf.ClubFinderPendingTab) end
    S.data(cf).skinned = true
end

-- Chat text takes the Chat module's size, but only while that module is the
-- thing driving chat fonts. With it off the frame already carries a size
-- Blizzard derived, and nil tells S.SetFont to keep that baseline.
local function ChatPaneFontSize()
    local chat = KE.db and KE.db.profile and KE.db.profile.Skinning
        and KE.db.profile.Skinning.Chat
    if not chat or not chat.Enabled then return nil end
    -- Keep Blizzard's size rather than let S.SetFont clamp a non-positive
    -- one to 8. The GUI bounds this 8-24, so it only arrives hand-edited.
    local size = tonumber(chat.FontSize)
    if not size or size <= 0 then return nil end
    return size
end

-- Blizzard leaves 31 between the community list and the chat pane and 15
-- between the pane and its scroll bar, room for art the skin strips. Pull the
-- pane out to the dropdown above it and bring the bar in; its other corner is
-- left alone, so this widens rather than shifts. Maximized only -- the
-- minimized layout anchors the pane to the window and hides the inset, which
-- is what tells the two apart.
local function LayoutChat(frame)
    local chat = frame.Chat
    local inset = chat and chat.InsetFrame
    if not (inset and inset:IsShown()) then return end
    if not frame.CommunitiesList then return end

    chat:SetPoint("TOPLEFT", frame.CommunitiesList, "TOPRIGHT", 25, -44)

    local sb, mf = chat.ScrollBar, chat.MessageFrame
    if sb and mf then
        -- Blizzard's two left anchors sit 5 apart and cannot both hold; the
        -- top one wins. Match them so the gap is the number written here.
        sb:ClearAllPoints()
        sb:SetPoint("TOPLEFT", mf, "TOPRIGHT", 8, 1)
        sb:SetPoint("BOTTOMLEFT", mf, "BOTTOMRIGHT", 8, -25)
    end
end

local AVATAR_CROP = 0.08

-- Avatar textures this skin squared. Weak keys: a released pool frame's
-- icon must not be held.
local avatarIcons = setmetatable({}, { __mode = "k" })
local avatarHooked = false

-- Absolute coordinates, so a repeat call cannot shrink the art.
local function CropAvatar(icon)
    if icon then icon:SetTexCoord(AVATAR_CROP, 1 - AVATAR_CROP, AVATAR_CROP, 1 - AVATAR_CROP) end
end

-- Every dialog sets its avatar again on each open or change, and that call
-- can reset the crop. One hook covers every call site.
local function HookAvatarTexture()
    local club = _G.C_Club
    if avatarHooked or not (club and club.SetAvatarTexture) then return end
    avatarHooked = true
    hooksecurefunc(club, "SetAvatarTexture", function(icon)
        if avatarIcons[icon] then CropAvatar(icon) end
    end)
end

local function AvatarBorder(icon, owner)
    S.PixelSnap(icon)
    local border = S.Backdrop(icon, -1, true)
    if border then border:SetFrameLevel(owner:GetFrameLevel() + 1) end
    return border
end

local function SquareAvatar(owner, icon, mask, ring)
    if not icon or avatarIcons[icon] then return end
    avatarIcons[icon] = true
    -- A mask left on would clip the square's corners.
    if mask then icon:RemoveMaskTexture(mask) end
    -- Re-atlased or re-shown on every open; the alpha survives both.
    if ring then ring:SetAlpha(0) end
    CropAvatar(icon)
    local border = AvatarBorder(icon, owner)
    if not border then return end
    -- The border is a frame on the owner, so it would outlive a hidden icon:
    -- a guild's finder card hides the icon and shows its banner there.
    local function follow() border:SetShown(icon:IsShown()) end
    follow()
    hooksecurefunc(icon, "Show", follow)
    hooksecurefunc(icon, "Hide", follow)
    hooksecurefunc(icon, "SetShown", follow)
end

-- Whole draw layers, for art that is partly keyless: popup border pieces and
-- card backgrounds.
local function HideLayers(frame, a, b)
    for _, r in ipairs({ frame:GetRegions() }) do
        if not issecretvalue(r) and r.IsObjectType and r:IsObjectType("Texture") then
            local layer = r:GetDrawLayer()
            if layer == a or layer == b then r:SetAlpha(0) end
        end
    end
end

local function Buttons(frame, keys)
    for _, key in ipairs(keys) do
        if frame[key] then S.Button(frame[key]) end
    end
end

local function ScrollInput(sf)
    if not sf then return end
    S.EditBox(sf)
    local eb = sf.EditBox
    if eb then
        S.SetFont(eb, 12, "")
        if eb.Instructions then S.SetFont(eb.Instructions, 12, "") end
    end
    if sf.ScrollBar then S.ScrollBar(sf.ScrollBar) end
end

-- Dialogs whose border and fill all live on a DialogBorderDark BG. Never
-- S.StripTextures on the dialog itself: an avatar can be one of its regions.
local function DarkDialog(d)
    if d.BG then S.StripTextures(d.BG) end
    S.Backdrop(d)
end

-- The club finder listing controls, shared by the guild recruitment dialog and
-- Community Settings.
local function ClubFinderOptions(d)
    for _, key in ipairs({ "ShouldListClub", "AutoAcceptApplications", "MaxLevelOnly", "MinIlvlOnly" }) do
        local row = d[key]
        if row and row.Button then S.CheckBox(row.Button) end
    end
    if d.MinIlvlOnly and d.MinIlvlOnly.EditBox then S.EditBox(d.MinIlvlOnly.EditBox) end
    for _, key in ipairs({ "ClubFocusDropdown", "LookingForDropdown", "LanguageDropdown" }) do
        if d[key] then S.DropDown(d[key]) end
    end
end

local function SkinSettingsDialog()
    local d = _G.CommunitiesSettingsDialog
    if not d or S.data(d).skinned then return end
    S.data(d).skinned = true
    DarkDialog(d)
    SquareAvatar(d, d.IconPreview, d.CircleMask, d.IconPreviewRing)

    if d.NameEdit then S.EditBox(d.NameEdit) end
    if d.ShortNameEdit then S.EditBox(d.ShortNameEdit) end
    ScrollInput(d.Description)
    ScrollInput(d.MessageOfTheDay)

    if d.CrossFactionToggle and d.CrossFactionToggle.CheckButton then
        S.CheckBox(d.CrossFactionToggle.CheckButton)
    end
    ClubFinderOptions(d)
    Buttons(d, { "ChangeAvatarButton", "Accept", "Delete", "Cancel" })
end

local function StyleTicketRow(row)
    if not row or S.data(row).keTicketRow then return end
    S.data(row).keTicketRow = true
    if row.CopyLinkButton then S.Button(row.CopyLinkButton) end
    if row.RevokeButton then S.Button(row.RevokeButton) end
end

local function SkinTicketDialog()
    local d = _G.CommunitiesTicketManagerDialog
    if not d or S.data(d).skinned then return end
    S.data(d).skinned = true
    -- The icon and the separator line sit on ARTWORK, the ring on OVERLAY.
    HideLayers(d, "BORDER", "BACKGROUND")
    S.Backdrop(d)
    SquareAvatar(d, d.Icon, d.CircleMask, d.IconRing)

    Buttons(d, { "LinkToChat", "Copy", "Close", "GenerateLinkButton" })
    if d.ExpiresDropdown then S.DropDown(d.ExpiresDropdown) end
    if d.UsesDropdown then S.DropDown(d.UsesDropdown) end

    local expand = d.MaximizeButton
    if expand then
        S.Button(expand)
        if expand.icon then S.ArrowTexture(expand.icon, "down", 12) end
    end

    local im = d.InviteManager
    if im then
        if im.ArtOverlay then im.ArtOverlay:SetAlpha(0) end
        if im.ScrollBox then
            if im.ScrollBox.Background then im.ScrollBox.Background:SetAlpha(0) end
            S.HookScrollBox(im.ScrollBox, StyleTicketRow)
        end
        if im.ScrollBar then
            if im.ScrollBar.Background then im.ScrollBar.Background:SetAlpha(0) end
            S.ScrollBar(im.ScrollBar)
        end
        local col = im.ColumnDisplay
        if col then
            S.StripTextures(col)
            for _, header in ipairs({ col:GetChildren() }) do
                S.StripTextures(header)
                S.Backdrop(header)
            end
        end
    end
end

local function StyleAvatarTile(tile)
    if not tile then return end
    local d = S.data(tile)
    if not d.keAvatarTile then
        d.keAvatarTile = true
        if tile.Selected then tile.Selected:SetAlpha(0) end
        local hl = tile.GetHighlightTexture and tile:GetHighlightTexture()
        if hl then hl:SetTexture(WHITE); hl:SetVertexColor(1, 1, 1, 0.12) end
        if tile.Icon then
            avatarIcons[tile.Icon] = true
            CropAvatar(tile.Icon)
            d.keBorder = AvatarBorder(tile.Icon, tile)
        end
    end
    -- Selection shows on the border: Blizzard's selected frame is hidden.
    local border = d.keBorder
    if not border then return end
    local selected = tile.Selected and tile.Selected:IsShown() or false
    if d.keSelected == selected then return end
    d.keSelected = selected
    if selected then
        S.PaintBrand(border, "SetBackdropBorderColor", 1)
    else
        S.ForgetBrand(border)
        border:SetBackdropBorderColor(unpack(S.borderColor))
    end
end

local function SkinAvatarPicker()
    local d = _G.CommunitiesAvatarPickerDialog
    if not d or S.data(d).skinned then return end
    S.data(d).skinned = true
    HideLayers(d, "BACKGROUND")
    local sel = d.Selector
    if sel then
        S.StripTextures(sel)
        Buttons(sel, { "OkayButton", "CancelButton" })
    end
    S.Backdrop(d)
    if d.ScrollBar then S.ScrollBar(d.ScrollBar) end
    if d.ScrollBox then S.HookScrollBox(d.ScrollBox, StyleAvatarTile) end
end

local function SkinEditStreamDialog(d)
    if not d or S.data(d).skinned then return end
    S.data(d).skinned = true
    DarkDialog(d)
    if d.NameEdit then S.EditBox(d.NameEdit) end
    ScrollInput(d.Description)
    if d.TypeCheckbox then S.CheckBox(d.TypeCheckbox) end
    Buttons(d, { "Accept", "Delete", "Cancel" })
end

local function StyleStreamEntry(row)
    if S.data(row).keStreamRow then return end
    S.data(row).keStreamRow = true
    if row.HideNotificationsButton then S.CheckBox(row.HideNotificationsButton) end
    if row.ShowNotificationsButton then S.CheckBox(row.ShowNotificationsButton) end
end

local function SkinNotificationDialog(d)
    if not d or S.data(d).skinned then return end
    S.data(d).skinned = true
    if d.BG then d.BG:SetAlpha(0) end
    local sel = d.Selector
    if sel then
        S.StripTextures(sel)
        Buttons(sel, { "OkayButton", "CancelButton" })
    end
    S.Backdrop(d)
    if d.CommunitiesListDropdown then S.DropDown(d.CommunitiesListDropdown) end
    local sf = d.ScrollFrame
    if sf then
        if sf.ScrollBar then S.ScrollBar(sf.ScrollBar) end
        local child = sf.Child
        if child then
            if child.QuickJoinButton then S.CheckBox(child.QuickJoinButton) end
            Buttons(child, { "NoneButton", "AllButton" })
        end
    end
    -- Stream rows come from a pool that Refresh fills on every open.
    if d.Refresh and d.buttonPool then
        hooksecurefunc(d, "Refresh", function(self)
            for row in self.buttonPool:EnumerateActive() do StyleStreamEntry(row) end
        end)
    end
end

-- The community and club finder invitation cards, and the invite link card.
local function SkinInvitation(f)
    if not f or S.data(f).skinned then return end
    S.data(f).skinned = true
    -- The wide card art; a guild's banner art sits on BORDER and ARTWORK.
    HideLayers(f, "BACKGROUND")
    if f.InsetFrame then
        S.StripTextures(f.InsetFrame)
        S.Backdrop(f.InsetFrame)
    end
    SquareAvatar(f, f.Icon, f.CircleMask, f.IconRing)
    Buttons(f, { "AcceptButton", "DeclineButton", "ApplyButton" })

    local wd = f.WarningDialog
    if wd then
        DarkDialog(wd)
        Buttons(wd, { "Accept", "Cancel" })
    end
end

local function SkinPreferredPlay(pp)
    if not pp or S.data(pp).skinned then return end
    S.data(pp).skinned = true
    if pp.LocaleDropdown then S.DropDown(pp.LocaleDropdown) end
    if pp.DatacenterDropdown then S.DropDown(pp.DatacenterDropdown) end
    Buttons(pp, { "LocaleApplyButton", "DatacenterApplyButton" })
end

local function Skin()
    local frame = _G.CommunitiesFrame
    if not frame then return S.Skip("CommunitiesFrame missing") end
    S.Frame(frame)

    HideDecorations(frame)
    if not S.data(frame).keDecoHook then
        frame:HookScript("OnShow", HideDecorations)
        S.data(frame).keDecoHook = true
    end

    if frame.CloseButton then S.CloseButton(frame.CloseButton) end
    if frame.StreamDropdown then S.DropDown(frame.StreamDropdown) end

    local mmf = frame.MaximizeMinimizeFrame
    if mmf then
        S.MaxMinFrame(mmf)

        if not S.data(mmf).keDecoHook then
            for _, bn in ipairs({ "MaximizeButton", "MinimizeButton" }) do
                local b = mmf[bn]
                if b then
                    b:HookScript("OnClick", function()
                        HideDecorations(frame)
                    end)
                end
            end
            -- The maximize callback re-points both, and runs unclicked when
            -- the window first restores its saved state -- after the skin.
            -- Hooking the button instead leaves every fresh login on
            -- Blizzard's spacing.
            hooksecurefunc(mmf, "Maximize", function()
                LayoutChat(frame)
            end)

            S.data(mmf).keDecoHook = true
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

    for _, name in ipairs({ "ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab",
        "GuildPreferredPlaySettingsTab" }) do
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
                    S.SetFont(body, 13, "")
                    if body.GetRegions then
                        for _, r in ipairs({ body:GetRegions() }) do
                            if r.IsObjectType and r:IsObjectType("FontString") then
                                S.SetFont(r, 13, "")
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

        SectionBox(info, "keBox1", 14, -22, 0, 200)
        SectionBox(info, "keBox2", 14, -158, 0, 118)
        SectionBox(info, "keBox3", 14, -236, -7, 1)
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

        SectionBox(news, "keBox4", 7, -22, -13, 1)
    end
    if _G.CommunitiesGuildNewsFiltersFrame then
        S.StripTextures(_G.CommunitiesGuildNewsFiltersFrame)
        S.Backdrop(_G.CommunitiesGuildNewsFiltersFrame)
    end
    if frame.GuildLogButton then S.Button(frame.GuildLogButton) end

    -- Guild Message of the Day editor -- same shape as the Guild Log
    -- below; this frame was simply never skinned.
    local motd = _G.CommunitiesGuildTextEditFrame
    if motd and not S.data(motd).keMotd then
        S.data(motd).keMotd = true
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
        -- select(4, frame:GetChildren()) is the Cancel button along the
        -- bottom, which has no global name.
        local cancel = select(4, motd:GetChildren())
        if cancel and cancel.IsObjectType and cancel:IsObjectType("Button") then
            S.Button(cancel)
        end
        if _G.CommunitiesGuildTextEditFrameCloseButton then
            S.CloseButton(_G.CommunitiesGuildTextEditFrameCloseButton)
        end
    end

    local log = _G.CommunitiesGuildLogFrame
    if log and not S.data(log).keLog then
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
        S.data(log).keLog = true
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
        if not S.data(frame.MemberList).keColHook and frame.MemberList.RefreshListDisplay then
            hooksecurefunc(frame.MemberList, "RefreshListDisplay", function(ml)
                local cd = ml.ColumnDisplay
                if not cd then return end
                for _, child in ipairs({ cd:GetChildren() }) do
                    if not S.data(child).keCol then
                        S.StripTextures(child)
                        S.Backdrop(child)
                        S.data(child).keCol = true
                    end
                end
            end)
            S.data(frame.MemberList).keColHook = true
        end

        local wm = frame.MemberList.WatermarkFrame
        if wm and wm.SetAlpha then wm:SetAlpha(0) end
        if not S.data(frame.MemberList).keWmHook then
            frame.MemberList:HookScript("OnShow", function(self)
                if self.WatermarkFrame and self.WatermarkFrame.SetAlpha then
                    self.WatermarkFrame:SetAlpha(0)
                end
            end)
            S.data(frame.MemberList).keWmHook = true
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
            -- The inset hangs 28 below the pane, where its overhang now draws
            -- a second panel behind the input. Anchor to the pane instead: 7
            -- keeps the inset's headroom above the messages, 9 stops a pixel
            -- short of the input's backdrop, which starts 10 down -- 4 for
            -- Blizzard's gap, 6 for its own inset.
            local ibd = S.GetBackdrop(frame.Chat.InsetFrame)
            if ibd then
                ibd:ClearAllPoints()
                ibd:SetPoint("TOPLEFT", frame.Chat, "TOPLEFT", 0, 7)
                ibd:SetPoint("BOTTOMRIGHT", frame.Chat, "BOTTOMRIGHT", 0, -9)
            end
        end

        local csb = frame.Chat.ScrollBar
            or (frame.Chat.MessageFrame and frame.Chat.MessageFrame.ScrollBar)
        if csb then S.ScrollBar(csb) end

        if frame.Chat.MessageFrame then
            S.SetFont(frame.Chat.MessageFrame, ChatPaneFontSize(), "OUTLINE")
        end

        LayoutChat(frame)
    end

    if frame.ChatEditBox then
        local box = frame.ChatEditBox
        S.EditBox(box)
        -- The box is 32 tall and hangs 4 past the chat pane on the left and 3
        -- on the right, sized for a bevel that overhung it. Inset the backdrop
        -- rather than re-anchor the box, which Blizzard re-points from the
        -- maximize and minimize callbacks.
        local bd = S.GetBackdrop(box)
        if bd then
            bd:ClearAllPoints()
            bd:SetPoint("TOPLEFT", box, "TOPLEFT", 4, -6)
            bd:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -3, 6)
        end
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
        ClubFinderOptions(rd)
        local msg = rd.RecruitmentMessageFrame
        if msg then
            S.StripTextures(msg)
            if msg.RecruitmentMessageInput then
                S.EditBox(msg.RecruitmentMessageInput)
                if msg.RecruitmentMessageInput.ScrollBar then S.ScrollBar(msg.RecruitmentMessageInput.ScrollBar) end
            end
        end
        if rd.Accept then S.Button(rd.Accept) end
        if rd.Cancel then S.Button(rd.Cancel) end
        S.data(rd).skinned = true
    end

    HookAvatarTexture()
    SkinSettingsDialog()
    SkinTicketDialog()
    SkinAvatarPicker()
    SkinEditStreamDialog(frame.EditStreamDialog)
    SkinNotificationDialog(frame.NotificationSettingsDialog)
    SkinInvitation(frame.InvitationFrame)
    SkinInvitation(frame.TicketFrame)
    SkinInvitation(frame.ClubFinderInvitationFrame)
    SkinPreferredPlay(frame.GuildPreferredPlaySettingsFrame)
end

S:Register("Blizzard_Communities", Skin, "Communities")
