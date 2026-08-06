local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local ipairs = ipairs
local type = type
local pcall = pcall
local hooksecurefunc = hooksecurefunc
local function NOOP() end

local normalizePending = false
local function NormalizeRaidGrid(passes)
    if normalizePending then return end
    normalizePending = true
    _G.C_Timer.After(0, function()
        normalizePending = false
        local f2 = _G.BetterFriendsFrame
        local rf = f2 and f2.RaidFrame
        local cont = rf and (rf.GroupsContainer
            or (rf.GroupsInset and rf.GroupsInset.GroupsContainer))
        if not cont or not cont:IsVisible() then return end
        local _, phH = GetPhysicalScreenSize()
        for g = 1, 8 do
            local grp = cont["Group" .. g]
            if grp then
                local eff = grp:GetEffectiveScale()
                local toPhys = (eff and eff > 0) and (eff * (phH or 768) / 768) or 1
                local top = grp.GetTop and grp:GetTop()
                if top and grp.AdjustPointsOffset then
                    local tp = top * toPhys
                    local frac = tp - math.floor(tp + 0.5)
                    if math.abs(frac) > 0.01 then grp:AdjustPointsOffset(0, -frac / toPhys) end
                end
                for i = 1, 5 do
                    local sl = grp["Slot" .. i]
                    if sl and S.data(sl).bflSlotSkinned then
                        local st = sl.GetTop and sl:GetTop()
                        if st and sl.AdjustPointsOffset then
                            local sp = st * toPhys
                            local frac = sp - math.floor(sp + 0.5)
                            if math.abs(frac) > 0.01 then sl:AdjustPointsOffset(0, -frac / toPhys) end
                        end
                        local h = sl:GetHeight()
                        if h then
                            local snapped = math.floor(h * toPhys + 0.5) / toPhys
                            if math.abs(snapped - h) > 0.001 then sl:SetHeight(snapped) end
                        end
                        S.FixSubPixelEdge(sl)
                    end
                end
            end
        end
        if (passes or 1) > 1 then NormalizeRaidGrid(passes - 1) end
    end)
end

local TOOLTIP_FONT_BUMP = 1
local function FontBFLTooltipLines()
    local tip = _G.BFL_Tooltip
    if not tip or not tip.NumLines then return end
    for i = 1, tip:NumLines() do
        for _, side in ipairs({ "BFL_TooltipTextLeft", "BFL_TooltipTextRight" }) do
            local fs = _G[side .. i]
            if fs then
                local d = S.data(fs)
                if not d.bflTipBase then
                    local _, size = fs:GetFont()
                    d.bflTipBase = size or 12
                end
                S.SetFont(fs, d.bflTipBase + TOOLTIP_FONT_BUMP, "OUTLINE")
            end
        end
    end
end

local function FontFriendsTooltip()
    local tip = _G.FriendsTooltip
    if not tip or not tip.GetRegions then return end
    for _, r in ipairs({ tip:GetRegions() }) do
        if r.IsObjectType and r:IsObjectType("FontString") then
            local d = S.data(r)
            if not d.fttBase then
                local _, size = r:GetFont()
                d.fttBase = size or 10
            end

            local target = (d.fttBase >= 12) and (d.fttBase + 1) or 12
            S.SetFont(r, target, "OUTLINE")
        end
    end
end

local tooltipHooked = false
local function HookBFLTooltip()
    if tooltipHooked then return end
    local tip = _G.BFL_Tooltip
    if not tip or not tip.HookScript then return end
    tooltipHooked = true
    tip:HookScript("OnShow", FontBFLTooltipLines)
    FontBFLTooltipLines()
end

local function KillSearchPlates(box)
    if not box or not box.GetChildren then return end
    local ours = S.GetBackdrop(box)

    for _, child in ipairs({ box:GetChildren() }) do
        if child ~= ours and not (child.IsObjectType and child:IsObjectType("Button")) then
            if child.SetBackdrop then pcall(child.SetBackdrop, child, nil) end
            if child.SetAlpha then child:SetAlpha(0) end
        end
    end

    if box.GetRegions then
        local instr = box.Instructions
        local itext = instr and instr.GetText and instr:GetText()
        for _, r in ipairs({ box:GetRegions() }) do
            if r.IsObjectType and r:IsObjectType("Texture") then
                local layer = r.GetDrawLayer and r:GetDrawLayer()
                if layer ~= "OVERLAY" and layer ~= "HIGHLIGHT" then
                    S.KillTexture(r)
                end
            elseif r.IsObjectType and r:IsObjectType("FontString") and instr and r ~= instr then
                if itext and r.GetText and r:GetText() == itext then
                    r:SetAlpha(0)
                end
            end
        end
    end
end

local function SkinInset(inset)
    if not inset or S.data(inset).bflSkinned then return end
    S.data(inset).bflSkinned = true
    S.StripTextures(inset)

    local bd = S.Template(inset, "Transparent")
    if bd then
        bd:ClearAllPoints()
        bd:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
        bd:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -4, 4)
    end
    S.data(inset).aeBD = bd
end

local function SkinHeaderRow(button)
    if not button then return end
    if button.BG then
        button.BG:SetTexture(nil)
        button.BG:Hide()
    end
    if S.data(button).bflSkinned then return end
    S.data(button).bflSkinned = true
    S.Backdrop(button, 1)
end

local function InvitePlusPaint(tp)
    local plus = S.data(tp).invitePlus
    if not plus then return end
    if tp:IsEnabled() then
        plus:SetTextColor(1, 1, 1, 0.9)
    else
        plus:SetTextColor(0.4, 0.4, 0.4, 0.6)
    end
end

-- (BFL's original invite art comes back on top of ours
-- after clicking invite): this built once and then bailed on every
-- later call -- but we are hooked to UpdateFriendButton/InitializeEntry,
-- which is BFL RE-DRESSING the button. It re-set the button's art on
-- invite-state change and nothing re-cleared it, so the original + drew
-- over ours. Two changes:
--   * the art removal now re-asserts on every update instead of once.
--     We are already hooked to the re-dresser; we were just declining
--     to do anything with it.
--   * S.KillAllTextures -> StripTextures + ClearButtonArt. The kill was
--     `Show = Hide` slot surgery, which never stopped this anyway: BFL
--     re-dresses through SetNormalTexture/SetAtlas, and a button's state
--     art is drawn by the button, not by a :Show() we can intercept.
--     ClearButtonArt is ElvUI's permanence idiom (ClearTexture + hooked
--     setters that re-clear, self-terminating) and it survives re-dress
--     on its own -- the per-update re-assert covers plain regions too.
local function FlattenInviteButton(tp)
    if not tp then return end
    local d = S.data(tp)

    if not d.bflSkinned then
        d.bflSkinned = true
        local w, h = tp:GetSize()
        if w and h then tp:SetSize(math.floor(w + 0.5), math.floor(h + 0.5)) end
        local bd = S.Backdrop(tp, 4)
        local plus = tp:CreateFontString(nil, "OVERLAY")
        plus:SetPoint("CENTER", 0, 0)
        S.SetFont(plus, 16, "")
        plus:SetText("+")
        d.invitePlus = plus
        tp:HookScript("OnEnable", InvitePlusPaint)
        tp:HookScript("OnDisable", InvitePlusPaint)
        S.Hover(tp, bd)
    end

    S.StripTextures(tp)
    S.ClearButtonArt(tp)
    InvitePlusPaint(tp)
end

local function HookLazy(module, creatorNames, skinFn)
    -- Callers pass whatever GetModule or a namespace field returns, which is
    -- not always a table to hook onto.
    if type(module) ~= "table" then return end
    for _, name in ipairs(creatorNames) do
        if type(module[name]) == "function" then
            -- The checker infers this parameter from its call sites and cannot
            -- see the table guard above.
            ---@diagnostic disable-next-line: type-mismatch
            hooksecurefunc(module, name, function() pcall(skinFn) end)
        end
    end
    pcall(skinFn)
end

local function SkinRaidTools()
    local f = _G.BetterFriendlistRaidToolsFrame
    if not f or S.data(f).rtSkinned then return end
    S.data(f).rtSkinned = true

    S.StripTextures(f)
    for _, key in ipairs({ "NineSlice", "Bg", "Inset", "Background" }) do
        if f[key] then S.StripTextures(f[key], true) end
    end
    local bg = _G.BetterFriendlistRaidToolsFrameBg
    if bg and bg.SetAlpha then bg:SetAlpha(0) end
    S.Backdrop(f)
    if f.CloseButton then S.CloseButton(f.CloseButton) end
    if f.TitleContainer then S.FontStrings(f.TitleContainer, 13, "") end

    if _G.BFLRaidToolsSortMode then pcall(S.DropDown, _G.BFLRaidToolsSortMode) end
    if _G.BFLRaidToolsPreserveGroups then pcall(S.DropDown, _G.BFLRaidToolsPreserveGroups) end

    if _G.BFLRaidToolsBalanceDps then S.CheckBox(_G.BFLRaidToolsBalanceDps) end
    if _G.BFLRaidToolsResumeCheck then S.CheckBox(_G.BFLRaidToolsResumeCheck) end

    for _, key in ipairs({ "sortButton", "splitButton", "splitOddsButton", "promoteButton" }) do
        if f[key] then S.Button(f[key]) end
    end
end

local function SkinChangelog()
    local f = _G.BetterFriendlistChangelogFrame
    if not f or S.data(f).bflSkinned then return end
    S.data(f).bflSkinned = true
    S.Frame(f)
    SkinInset(f.MainInset)
    S.Button(f.DiscordButton)
    S.Button(f.GitHubButton)
    S.Button(f.KoFiButton)
    if f.ScrollBar then
        S.ScrollBar(f.ScrollBar)
    elseif f.ScrollFrame then
        for _, child in ipairs({ f.ScrollFrame:GetChildren() }) do
            if child:IsObjectType("Slider") then S.ScrollBar(child) end
        end
    end
end

local function SkinHelp()
    local f = _G.BetterFriendlistHelpFrame
    if not f or S.data(f).bflSkinned then return end
    S.data(f).bflSkinned = true
    S.Frame(f)
    SkinInset(f.Inset)
    if f.ScrollBar then
        S.ScrollBar(f.ScrollBar)
    elseif f.ScrollFrame then
        for _, child in ipairs({ f.ScrollFrame:GetChildren() }) do
            if child:IsObjectType("Slider") then S.ScrollBar(child) end
        end
    end
end

local function SkinLegacySettings()
    local f = _G.BetterFriendlistSettingsFrame
    if not f or S.data(f).bflSkinned then return end
    S.data(f).bflSkinned = true
    S.Frame(f)
    S.Tabs("BetterFriendlistSettingsFrameTab", 10)
    SkinInset(f.MainInset)
    if f.ContentScrollFrame then S.ScrollBar(f.ContentScrollFrame.ScrollBar) end
end

local function SkinSettingsShell(designer)
    local ok, f = pcall(function() return designer:GetFrame() end)
    if not ok or not f or S.data(f).bflSkinned then return end
    S.data(f).bflSkinned = true
    S.Frame(f)
    for _, key in ipairs({ "TopBar", "Sidebar", "ContentShell", "SearchShell" }) do
        local child = f[key]
        if child then
            S.StripTextures(child)
            S.Backdrop(child)
        end
    end
    if f.SearchBox then S.EditBox(f.SearchBox) end
    for _, key in ipairs({ "ResetButton", "LockButton", "DensityButton" }) do
        local btn = f[key]
        if btn and btn.GetObjectType and btn:GetObjectType() == "Button" then
            S.Button(btn)
        end
    end
end

local function SkinRAF(frame)
    local raf = frame.RecruitAFriendFrame
    if not raf or S.data(raf).bflSkinned then return end
    S.data(raf).bflSkinned = true
    if raf.Border then S.StripTextures(raf.Border) end
    if raf.Background then raf.Background:Hide() end
    local rc = raf.RewardClaiming
    if rc then
        if rc.Background then rc.Background:SetAlpha(0) end
        S.Backdrop(rc)
        S.Button(rc.ClaimOrViewRewardButton)
        SkinInset(rc.Inset)
        if rc.NextRewardButton then S.Backdrop(rc.NextRewardButton) end
    end
    local rl = raf.RecruitList
    if rl then
        SkinInset(rl.ScrollFrameInset)
        S.ScrollBar(rl.ScrollBar)
        if rl.Header then
            if rl.Header.Background then rl.Header.Background:Hide() end
            S.StripTextures(rl.Header)
            S.Backdrop(rl.Header)
        end
    end
    local sp = raf.SplashFrame
    if sp then
        S.StripTextures(sp)
        S.Backdrop(sp)
        if sp.Background then sp.Background:Hide() end
        if sp.PictureFrame then sp.PictureFrame:Hide() end
        if sp.Watermark then sp.Watermark:Hide() end
        for _, key in ipairs({ "Bracket_TopLeft", "Bracket_TopRight", "Bracket_BottomLeft", "Bracket_BottomRight" }) do
            if sp[key] then sp[key]:Hide() end
        end
        S.Button(sp.OKButton)
    end
end

local function StripPanelShell(frame)
    if not frame then return end
    if frame.NineSlice and frame.NineSlice.SetAlpha then frame.NineSlice:SetAlpha(0) end
    for _, key in ipairs({ "Bg", "TitleBg", "TopTileStreaks", "PortraitIcon", "PortraitMask" }) do
        local r = frame[key]
        if r and r.SetAlpha then r:SetAlpha(0) end
        if r and r.Hide then r:Hide() end
    end
    if frame.TitleContainer and frame.TitleContainer.TitleBg then
        frame.TitleContainer.TitleBg:SetAlpha(0)
    end
    local inset = frame.Inset
    if inset then
        if inset.Bg then inset.Bg:SetAlpha(0) end
        if inset.NineSlice and inset.NineSlice.SetAlpha then inset.NineSlice:SetAlpha(0) end
    end

    for _, target in ipairs({ frame, inset }) do
        local bd = target and S.GetBackdrop and S.GetBackdrop(target)
        if bd then
            bd:Show()
            bd:SetAlpha(1)
            local tone = (target == inset) and S.palette.panel or S.palette.window
            bd:SetBackdropColor(tone[1], tone[2], tone[3], tone[4])

        end
    end
    local close = frame.CloseButton
        or (frame.GetName and frame:GetName() and _G[frame:GetName() .. "CloseButton"])
    if close then

        local x = S.data(close).closeX
        if x then
            local blizz = { close:GetNormalTexture(), close:GetPushedTexture(),
                close:GetHighlightTexture(), close:GetDisabledTexture() }
            for i = 1, 4 do
                local t = blizz[i]
                if t and t.SetAlpha then t:SetAlpha(0) end
            end
            x:Show()
        end
    end
end

local function ReStrip()
    local frame = _G.BetterFriendsFrame
    if frame then
        StripPanelShell(frame)

        local hdr = frame.FriendsTabHeader
        local bnet = hdr and hdr.BattlenetFrame
        if bnet then
            for _, b in ipairs({ bnet.SettingsButton, bnet.ContactsMenuButton }) do
                if b then S.FixSubPixelEdge(b) end
            end
        end

        local ins = frame.Inset

        local ibd = ins and S.GetBackdrop and S.GetBackdrop(ins)
        if ibd then
            ibd:ClearAllPoints()
            ibd:SetPoint("TOPLEFT", ins, "TOPLEFT", 4, -4)
            ibd:SetPoint("BOTTOMRIGHT", ins, "BOTTOMRIGHT", -4, 4)
        end
    end
    StripPanelShell(_G.BetterFriendlistSettingsFrame)
end

local function Skin()
    local frame = _G.BetterFriendsFrame
    if not frame or S.data(frame).bflSkinned then return end
    S.data(frame).bflSkinned = true

    S.Frame(frame)
    StripPanelShell(frame)

    local pb = frame.PortraitButton
    if pb then
        pb:ClearAllPoints()
        pb:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
        pb:SetSize(26, 26)
        pb:SetFrameLevel(frame:GetFrameLevel() + 5)
        local bd = S.Backdrop(pb, 0)
        if not pb.Icon then
            pb.Icon = pb:CreateTexture(nil, "ARTWORK")
            pb.Icon:SetTexture("Interface\\AddOns\\BetterFriendlist\\Textures\\PortraitIcon")
        end
        pb.Icon:ClearAllPoints()
        pb.Icon:SetPoint("TOPLEFT", pb, "TOPLEFT", 1, -1)
        pb.Icon:SetPoint("BOTTOMRIGHT", pb, "BOTTOMRIGHT", -1, 1)
        pb.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        pb.Icon:Show()
        if pb.Glow then
            pb.Glow:ClearAllPoints()
            pb.Glow:SetPoint("TOPLEFT", pb, "TOPLEFT", 1, -1)
            pb.Glow:SetPoint("BOTTOMRIGHT", pb, "BOTTOMRIGHT", -1, 1)
            pb.Glow:SetDrawLayer("OVERLAY")
        end
        S.Hover(pb, bd)
    end

    local function CleanTabAnchors(tab)
        if tab:GetNumPoints() > 1 then
            local p, rel, rp, x, y = tab:GetPoint(1)
            if p then
                local relIsTab = rel and rel.GetObjectType and rel:GetObjectType() == "Button"
                    and tostring(rel:GetName() or ""):find("Tab")
                tab:ClearAllPoints()
                tab:SetPoint(p, rel, rp, relIsTab and -3 or x, y)
            end
        end
    end

    local function ArmBottomHeadY(tab)
        if S.data(tab).yArmor then return end
        S.data(tab).yArmor = true
        local function Pin(t, _, _, _, x, y)
            if y ~= -32 or x ~= -2 then
                local p, rel, rp = t:GetPoint(1)
                if p and rel == _G.BetterFriendsFrame then
                    t:ClearAllPoints()
                    t:SetPoint(p, rel, rp, -2, -32)
                end
            end
        end
        Pin(tab, nil, nil, nil, select(4, tab:GetPoint(1)), select(5, tab:GetPoint(1)))
        hooksecurefunc(tab, "SetPoint", Pin)
    end
    local function ArmAnchorShim(tab)
        if S.data(tab).anchorShim then return end
        S.data(tab).anchorShim = true
        local pending = false
        hooksecurefunc(tab, "SetPoint", function(t)
            if pending or t:GetNumPoints() <= 1 then return end
            pending = true
            _G.C_Timer.After(0, function()
                pending = false
                CleanTabAnchors(t)
            end)
        end)
        CleanTabAnchors(tab)
    end

    for i = 1, 4 do
        local tab = _G["BetterFriendsFrameTab" .. i]
        if tab then
            S.data(tab).noGeometry = true
            S.Tab(tab)
            ArmAnchorShim(tab)
        end
    end
    for i = 1, 4 do
        local tab = _G["BetterFriendsFrameBottomTab" .. i]
        if tab then
            S.data(tab).noGeometry = true
            S.Tab(tab)
            ArmAnchorShim(tab)
            if i == 1 then ArmBottomHeadY(tab) end
        end
    end

    SkinInset(frame.Inset)
    SkinInset(frame.ListInset)
    if frame.WhoFrame then SkinInset(frame.WhoFrame.ListInset) end
    if frame.RaidFrame then
        SkinInset(frame.RaidFrame.GroupsInset)
        SkinInset(frame.RaidFrame.ListInset)

        local container = frame.RaidFrame.GroupsContainer
            or (frame.RaidFrame.GroupsInset and frame.RaidFrame.GroupsInset.GroupsContainer)
        if container then
            for g = 1, 8 do
                local group = container["Group" .. g]
                if group then
                    if group.GroupTitle then S.SetFont(group.GroupTitle, 12, "") end
                    for i = 1, 5 do
                        local slot = group["Slot" .. i]
                        if slot and not S.data(slot).bflSlotSkinned then
                            S.data(slot).bflSlotSkinned = true

                            local bd = S.Backdrop(slot, 0, true)
                            S.FixSubPixelEdge(slot)

                            for _, key in ipairs({ "Name", "Level" }) do
                                if slot[key] then S.SetFont(slot[key], 12, "OUTLINE") end
                            end
                            if slot.EmptyText then S.SetFont(slot.EmptyText, 12, "") end
                            local bgTex = slot.Background
                            if bgTex then
                                bgTex:SetTexture("Interface\\Buttons\\WHITE8x8")
                                bgTex:SetTexCoord(0, 1, 0, 1)
                                bgTex:SetVertexColor(S.palette.control[1], S.palette.control[2], S.palette.control[3])

                                bgTex:ClearAllPoints()
                                bgTex:SetPoint("TOPLEFT", bd or slot, "TOPLEFT", 1, -1)
                                bgTex:SetPoint("BOTTOMRIGHT", bd or slot, "BOTTOMRIGHT", -1, 1)
                                bgTex.ClearAllPoints = NOOP
                                bgTex.SetPoint = NOOP
                            end
                        end
                    end
                end
            end
        end
    end
    if frame.QuickJoinFrame then SkinInset(frame.QuickJoinFrame.ContentInset) end

    S.ScrollBar(frame.MinimalScrollBar or frame.ScrollBar)
    if frame.RecentAlliesFrame then S.ScrollBar(frame.RecentAlliesFrame.ScrollBar) end
    if frame.WhoFrame then
        S.ScrollBar(frame.WhoFrame.ScrollBar
            or (frame.WhoFrame.ScrollBox and frame.WhoFrame.ScrollBox.ScrollBar))
    end
    if frame.RaidFrame then S.ScrollBar(frame.RaidFrame.ScrollBar) end
    if frame.QuickJoinFrame then
        S.ScrollBar(frame.QuickJoinFrame.ScrollBar
            or (frame.QuickJoinFrame.ScrollBoxContainer and frame.QuickJoinFrame.ScrollBoxContainer.ScrollBar))
        if frame.QuickJoinFrame.ContentInset then
            S.ScrollBar(frame.QuickJoinFrame.ContentInset.ScrollBar)
        end
    end

    S.Button(frame.AddFriendButton)
    S.Button(frame.SendMessageButton)
    S.Button(frame.RecruitmentButton)
    if frame.WhoFrame then
        S.Button(frame.WhoFrame.WhoButton)
        S.Button(frame.WhoFrame.AddFriendButton)
        S.Button(frame.WhoFrame.GroupInviteButton)
        S.EditBox(frame.WhoFrame.EditBox)

        KillSearchPlates(frame.WhoFrame.EditBox)
        S.Button(frame.WhoFrame.NameHeader)
        S.Button(frame.WhoFrame.LevelHeader)
        S.Button(frame.WhoFrame.ClassHeader)
        pcall(S.DropDown, frame.WhoFrame.ColumnDropdown, true)
    end
    if frame.RaidFrame then
        S.Button(frame.RaidFrame.ConvertToRaidButton)
        S.Button(frame.RaidFrame.RaidToolsButton)
        if frame.RaidFrame.ControlPanel then
            S.Button(frame.RaidFrame.ControlPanel.RaidInfoButton)

            S.Button(frame.RaidFrame.ControlPanel.ReadyCheckButton, frame.RaidFrame.ControlPanel.ReadyCheckButton.Icon)

            local cp = frame.RaidFrame.ControlPanel
            if cp.EveryoneAssistCheckbox then S.CheckBox(cp.EveryoneAssistCheckbox) end
            if cp.EveryoneAssistLabel then S.SetFont(cp.EveryoneAssistLabel, 12, "OUTLINE") end
            S.CheckBox(frame.RaidFrame.ControlPanel.EveryoneAssistCheckbox)
        end
    end
    if frame.QuickJoinFrame then
        S.Button(frame.QuickJoinFrame.JoinQueueButton)
        if frame.QuickJoinFrame.ContentInset then
            S.Button(frame.QuickJoinFrame.ContentInset.JoinQueueButton)
        end
    end

    HookBFLTooltip()
    if not tooltipHooked and _G.C_Timer then
        _G.C_Timer.After(0, HookBFLTooltip) -- was 2s
    end
    FontFriendsTooltip()
    if not S.data(frame).fttShowHook and frame.HookScript then
        S.data(frame).fttShowHook = true
        frame:HookScript("OnShow", FontFriendsTooltip)
    end

    local header = frame.FriendsTabHeader
    if header then
        S.EditBox(header.SearchBox)

        KillSearchPlates(header.SearchBox)
        pcall(S.DropDown, header.StatusDropdown, true)
        pcall(S.DropDown, header.QuickFilterDropdown, true)
        pcall(S.DropDown, header.PrimarySortDropdown, true)
        pcall(S.DropDown, header.SecondarySortDropdown, true)

        local bnet = header.BattlenetFrame
        if bnet then
            S.StripTextures(bnet)
            S.Backdrop(bnet)

            for _, b in ipairs({ bnet.SettingsButton, bnet.ContactsMenuButton }) do
                if b then
                    S.Button(b, b.Icon)

                    S.FixSubPixelEdge(b)
                end
            end

            if not S.data(frame).aeBnetDragHook and frame.HookScript then
                S.data(frame).aeBnetDragHook = true
                frame:HookScript("OnDragStop", function()
                    if bnet.SettingsButton then S.FixSubPixelEdge(bnet.SettingsButton) end
                    if bnet.ContactsMenuButton then S.FixSubPixelEdge(bnet.ContactsMenuButton) end
                    NormalizeRaidGrid(2)
                end)

                frame:HookScript("OnSizeChanged", function()
                    NormalizeRaidGrid(2)
                end)
            end
            if bnet.BroadcastFrame then
                S.StripTextures(bnet.BroadcastFrame)
                S.Backdrop(bnet.BroadcastFrame)
                S.Button(bnet.BroadcastFrame.UpdateButton)
                S.Button(bnet.BroadcastFrame.CancelButton)
                S.EditBox(bnet.BroadcastFrame.EditBox)
            end
            if bnet.UnavailableInfoFrame then
                S.StripTextures(bnet.UnavailableInfoFrame)
                S.Backdrop(bnet.UnavailableInfoFrame)
            end
        end
    end

    pcall(SkinRAF, frame)

    local ign = frame.IgnoreListWindow
    if ign then
        S.Frame(ign)
        SkinInset(ign.Inset)
        S.ScrollBar(ign.ScrollBar)
        S.Button(ign.UnignorePlayerButton)
    end

    local BFLNS = _G.BetterFriendlist
    if BFLNS and BFLNS.GetModule then
        local FriendsList = BFLNS:GetModule("FriendsList")
        if FriendsList then
            pcall(function()
                hooksecurefunc(FriendsList, "UpdateGroupHeaderButton", function(_, button)
                    SkinHeaderRow(button)
                end)
                hooksecurefunc(FriendsList, "UpdateInviteHeaderButton", function(_, button)
                    SkinHeaderRow(button)
                end)
                hooksecurefunc(FriendsList, "UpdateFriendButton", function(_, button)
                    FlattenInviteButton(button and button.travelPassButton)
                end)
                hooksecurefunc(FriendsList, "UpdateInviteButton", function(_, button)
                    if not button or S.data(button).bflSkinned then return end
                    S.data(button).bflSkinned = true
                    S.Button(button.AcceptButton)
                    S.Button(button.DeclineButton)
                end)
            end)
        end
        local RecentAllies = BFLNS:GetModule("RecentAllies")
        if RecentAllies then
            pcall(hooksecurefunc, RecentAllies, "InitializeEntry", function(_, button)
                FlattenInviteButton(button and button.PartyButton)
            end)
        end
        HookLazy(BFLNS:GetModule("Changelog"), { "CreateChangelogWindow" }, SkinChangelog)

        HookLazy(BFLNS:GetModule("RaidTools"), { "CreateFrame" }, SkinRaidTools)

        local RFM = BFLNS:GetModule("RaidFrame")
        if RFM and type(RFM.UpdateGroupLayout) == "function" then
            hooksecurefunc(RFM, "UpdateGroupLayout", function()
                NormalizeRaidGrid(2)
            end)
        end

        HookLazy(BFLNS.HelpFrame, { "CreateFrame", "Toggle" }, SkinHelp)
        pcall(SkinLegacySettings)
        local designer = BFLNS:GetModule("SettingsDesigner")
        if designer then
            if type(designer.Show) == "function" then
                hooksecurefunc(designer, "Show", function(d) pcall(SkinSettingsShell, d) end)
            end
            pcall(SkinSettingsShell, designer)
        end

        local function DeferredReStrip()
            _G.C_Timer.After(0, ReStrip)
        end
        local TM = BFLNS:GetModule("ThemeManager")
        if TM and type(TM.ApplyCurrentTheme) == "function" then
            hooksecurefunc(TM, "ApplyCurrentTheme", DeferredReStrip)
        end
        local DT = BFLNS:GetModule("DarkTheme")
        if DT and type(DT.Remove) == "function" then
            hooksecurefunc(DT, "Remove", DeferredReStrip)
        end

        DeferredReStrip()
    end
end

local function SkinAddFriendDialog()

    local af = _G.AddFriendFrame
    if not af or S.data(af).skinned then return end
    S.data(af).skinned = true
    if af.Border then af.Border:Hide() end
    S.StripTextures(af)
    S.Template(af, "Window")
    local entry = _G.AddFriendEntryFrame
    if entry then
        S.StripTextures(entry)
        S.FontStringsDeep(entry, 12, "OUTLINE", 2)
        local title = entry.TitleContainer and entry.TitleContainer.Title
        if title then S.SetFont(title, 14, "OUTLINE") end
    end
    if _G.AddFriendNameEditBox then S.EditBox(_G.AddFriendNameEditBox) end
    if _G.AddFriendEntryFrameAcceptButton then S.Button(_G.AddFriendEntryFrameAcceptButton) end
    if _G.AddFriendEntryFrameCancelButton then S.Button(_G.AddFriendEntryFrameCancelButton) end
    local close = af.CloseButton or _G.AddFriendFrameCloseButton
    if close then S.CloseButton(close) end

    af:HookScript("OnShow", function()
        C_Timer.After(0, function()
            S.FixSubPixelEdge(af)

            local entry = _G.AddFriendEntryFrame -- luacheck: ignore 431/entry
            if entry then
                S.FixSubPixelEdge(entry)
                if entry.EditBoxContainer then S.FixSubPixelEdge(entry.EditBoxContainer) end
            end

            if _G.AddFriendEntryFrameAcceptButton then S.FixSubPixelEdge(_G.AddFriendEntryFrameAcceptButton) end
            if _G.AddFriendEntryFrameCancelButton then S.FixSubPixelEdge(_G.AddFriendEntryFrameCancelButton) end
        end)
    end)
end

local function SkinAll()
    Skin()
    SkinAddFriendDialog()
end

S:Register("BetterFriendlist", SkinAll, "BetterFriendlist")
