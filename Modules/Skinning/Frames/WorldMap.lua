local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local next, ipairs = next, ipairs
local hooksecurefunc = hooksecurefunc

local function RestyleRowHighlight(button)

    local hl = button.GetHighlightTexture and button:GetHighlightTexture()
    if hl then
        hl:SetTexture("Interface\\Buttons\\WHITE8x8")
        hl:SetVertexColor(S.palette.hover[1], S.palette.hover[2], S.palette.hover[3], 0.15)
    end
end

local function BumpFS(fs)
    if not fs or not fs.GetFont then return end
    local f, sz, fl = fs:GetFont()
    if f and sz then fs:SetFont(f, sz + 1, fl) end
end

local function StyleQuestLog()
    local qsf = _G.QuestScrollFrame
    if not qsf then return end

    if qsf.headerFramePool and qsf.headerFramePool.EnumerateActive then
        for button in qsf.headerFramePool:EnumerateActive() do
            local d = S.data(button)
            if button.ButtonText and not d.aeRow then
                S.StripTextures(button)
                S.Backdrop(button)
                S.SetFont(button.ButtonText, 15, "OUTLINE")
                RestyleRowHighlight(button)
                d.aeRow = true
            end
            if button.CollapseButton then S.Collapse(button.CollapseButton) end
        end
    end

    if qsf.campaignHeaderFramePool and qsf.campaignHeaderFramePool.EnumerateActive then
        for header in qsf.campaignHeaderFramePool:EnumerateActive() do
            local d = S.data(header)
            if not d.aeRow then

                if header.Text then S.SetFont(header.Text, 16, "OUTLINE") end
                if header.Progress then S.SetFont(header.Progress, 13, "OUTLINE") end
                d.aeRow = true
            end
            if header.CollapseButton then S.Collapse(header.CollapseButton) end
        end
    end
    if qsf.campaignHeaderMinimalFramePool and qsf.campaignHeaderMinimalFramePool.EnumerateActive then
        for header in qsf.campaignHeaderMinimalFramePool:EnumerateActive() do
            local d = S.data(header)
            if header.CollapseButton and not d.aeRow then
                S.StripTextures(header)
                if header.Background then S.Backdrop(header.Background) end
                if header.Highlight then
                    header.Highlight:SetColorTexture(S.palette.hover[1], S.palette.hover[2], S.palette.hover[3], 0.15)
                end
                d.aeRow = true
            end
            if header.CollapseButton then S.Collapse(header.CollapseButton) end
        end
    end
    if qsf.objectiveFramePool and qsf.objectiveFramePool.EnumerateActive then
        for obj in qsf.objectiveFramePool:EnumerateActive() do
            local d = S.data(obj)
            if not d.aeFont then
                BumpFS(obj.Text)
                d.aeFont = true
            end
        end
    end
    if qsf.titleFramePool and qsf.titleFramePool.EnumerateActive then
        for button in qsf.titleFramePool:EnumerateActive() do
            local d = S.data(button)
            if not d.aeFont then
                BumpFS(button.Text)
                BumpFS(button.ButtonText)
                d.aeFont = true
            end
            if button.Checkbox and not d.aeRow then
                S.StripTextures(button.Checkbox)
                local bd = S.Backdrop(button.Checkbox)

                local mark = button.Checkbox.CheckMark
                if bd and mark then
                    local function sync()
                        bd:SetShown(mark:IsShown() or (button.IsMouseOver and button:IsMouseOver()))
                    end
                    hooksecurefunc(mark, "Show", sync)
                    hooksecurefunc(mark, "Hide", sync)
                    hooksecurefunc(mark, "SetShown", sync)
                    button:HookScript("OnEnter", sync)
                    button:HookScript("OnLeave", sync)
                    sync()
                end
                d.aeRow = true
            end
        end
    end
end

local function SkinStoryHeader(header)
    if not header then return end
    local d = S.data(header)
    if d.aeHeader then return end
    if header.Background then header.Background:SetAlpha(0.7) end
    if header.TopFiligree then header.TopFiligree:Hide() end
    if header.Divider then header.Divider:Hide() end
    if header.HighlightTexture then
        header.HighlightTexture:SetTexture("Interface\\Buttons\\WHITE8x8")
        header.HighlightTexture:SetVertexColor(S.palette.hover[1], S.palette.hover[2], S.palette.hover[3], 0.15)
        if header.Background then header.HighlightTexture:SetAllPoints(header.Background) end
    end
    if header.CollapseButton then S.Collapse(header.CollapseButton) end
    d.aeHeader = true
end

local function HandleSideTabs(qmf)

    S.SideTab(qmf.QuestsTab, _G.WorldMapFrame, nil, 22)
    S.SideTab(qmf.EventsTab, nil, qmf.QuestsTab, 22)
    S.SideTab(qmf.MapLegendTab, nil, qmf.EventsTab, 22)
end

local function SkinFloorDropdown(f)
    if f and not S.data(f).aeOverlay then
        S.DropDown(f, true)
        S.data(f).aeOverlay = true
    end
end

local function SkinTrackingOptions(f)
    if f and f.Icon and not S.data(f).aeOverlay then
        S.StripTextures(f)
        f.Icon:SetTexture(136460)
        if f.SetHighlightTexture then
            f:SetHighlightTexture(136460, "ADD")
            local hl = f:GetHighlightTexture()
            if hl then hl:SetAllPoints(f.Icon) end
        end
        S.data(f).aeOverlay = true
    end
end

local function SkinPinToggle(f)
    if f and f.Icon and f.ActiveTexture and not S.data(f).aeOverlay then
        S.StripTextures(f)
        f.Icon:SetAtlas("Waypoint-MapPin-Untracked")
        f.ActiveTexture:SetAtlas("Waypoint-MapPin-Tracked")
        f.ActiveTexture:SetAllPoints(f.Icon)
        if f.SetHighlightTexture then
            f:SetHighlightTexture(3500068, "ADD")
            local hl = f:GetHighlightTexture()
            if hl then
                hl:SetAllPoints(f.Icon)
                hl:SetTexCoord(0.3203125, 0.5546875, 0.015625, 0.484375)
            end
        end
        S.data(f).aeOverlay = true
    end
end

local OVERLAY_TEMPLATE_SKINS = {
    WorldMapFloorNavigationFrameTemplate = SkinFloorDropdown,
    WorldMapTrackingOptionsButtonTemplate = SkinTrackingOptions,
    WorldMapTrackingPinButtonTemplate = SkinPinToggle,
}

local function HandleOverlayFrames(frame)
    local o = frame.overlayFrames
    if not o then return end
    SkinFloorDropdown(o[1])
    SkinTrackingOptions(o[2])
    SkinPinToggle(o[3])
end

local function UpdateExecuteCommandAtlases(qsm, command)
    local btn = qsm.ExecuteSessionCommand
    if not btn or not S.data(btn).sessionIcon then return end
    for _, m in next, { "SetNormalTexture", "SetPushedTexture", "SetDisabledTexture" } do
        local tex = btn["Get" .. m:sub(4)]
        tex = tex and tex(btn)
        if tex then tex:SetAlpha(0) end
    end
    local atlas = command == (_G.Enum and _G.Enum.QuestSessionCommand and _G.Enum.QuestSessionCommand.Stop)
        and "QuestSharing-Stop-DialogIcon" or "QuestSharing-DialogIcon"
    S.data(btn).sessionIcon:SetAtlas(atlas)
end

local questHooked = false
local navHooked = false

local function Skin()
    local frame = _G.WorldMapFrame
    if not frame then return end

    S.Frame(frame, true)
    if frame.ScrollContainer then
        S.Backdrop(frame.ScrollContainer, 0, true)
    end

    -- min/max flips the map between 1.1 and 1.0; scale changes
    -- fire no OnSizeChanged on descendants, but the map ITSELF resizes,
    -- so hook that (script hook: our execution, after Blizzard's
    -- handler, touches only our own backdrop frames) and re-fit every
    -- border under it. Debounced to the next frame.
    if not S.data(frame).aeEdgeHook then
        S.data(frame).aeEdgeHook = true
        frame:HookScript("OnSizeChanged", function()
            local d = S.data(frame)
            if d.aeEdgePending then return end
            d.aeEdgePending = true
            C_Timer.After(0, function()
                d.aeEdgePending = nil
                S.RefreshEdgesUnder(frame)
            end)
        end)
    end

    local nav = frame.NavBar
    if nav then
        S.StripTextures(nav, true)
        if nav.overlay then S.StripTextures(nav.overlay, true) end
        local nbd = S.Backdrop(nav)
        if nbd then
            nbd:ClearAllPoints()
            nbd:SetPoint("TOPLEFT", nav, "TOPLEFT", -2, 0)
            nbd:SetPoint("BOTTOMRIGHT", nav, "BOTTOMRIGHT", 0, 0)
        end
        S.NavCrumb(nav.home or nav.homeButton)

        local overflow = nav.overflowButton or nav.overflow or _G.WorldMapFrameOverflowButton
        if overflow then
            S.NavCrumb(overflow)

            if not S.data(overflow).aeArrow then
                local t = overflow:CreateTexture(nil, "OVERLAY")
                t:SetPoint("CENTER")
                S.ArrowTexture(t, "left", 14)
                t:SetAlpha(1)
                S.data(overflow).aeArrow = t
            end
        end
        if nav.navList then
            for _, btn in ipairs(nav.navList) do S.NavCrumb(btn) end
        end
        if not navHooked and _G.NavBar_AddButton then
            hooksecurefunc("NavBar_AddButton", function(navBar)
                if navBar == frame.NavBar and navBar.navList then
                    S.NavCrumb(navBar.navList[#navBar.navList])

                    local ofb = navBar.overflowButton or navBar.overflow or _G.WorldMapFrameOverflowButton
                    if ofb and not S.data(ofb).aeArrow then
                        local t = ofb:CreateTexture(nil, "OVERLAY")
                        t:SetPoint("CENTER")
                        S.ArrowTexture(t, "left", 14)
                        t:SetAlpha(1)
                        S.data(ofb).aeArrow = t
                    end
                end
            end)
            navHooked = true
        end
    end

    local qsf = _G.QuestScrollFrame
    if qsf then
        S.Backdrop(qsf)
        if qsf.Edge and qsf.Edge.SetAlpha then qsf.Edge:SetAlpha(0) end
        if qsf.BorderFrame and qsf.BorderFrame.SetAlpha then qsf.BorderFrame:SetAlpha(0) end
        if qsf.Background and qsf.Background.SetAlpha then qsf.Background:SetAlpha(0) end
        if qsf.Contents and qsf.Contents.Separator and qsf.Contents.Separator.SetAlpha then
            qsf.Contents.Separator:SetAlpha(0)
        end
        if qsf.Contents and qsf.Contents.StoryHeader then SkinStoryHeader(qsf.Contents.StoryHeader) end
        if qsf.SearchBox then S.EditBox(qsf.SearchBox) end
        if qsf.ScrollBar then S.ScrollBar(qsf.ScrollBar) end
    end
    StyleQuestLog()
    if not questHooked and _G.QuestLogQuests_Update then
        hooksecurefunc("QuestLogQuests_Update", StyleQuestLog)
        questHooked = true
    end

    local qmf = _G.QuestMapFrame
    if qmf then
        if qmf.VerticalSeparator and qmf.VerticalSeparator.Hide then qmf.VerticalSeparator:Hide() end
        if qmf.Background then qmf.Background:SetAlpha(0) end

        local d = qmf.DetailsFrame
        if d then
            S.StripTextures(d, true)
            if d.BorderFrame then d.BorderFrame:SetAlpha(0) end
            if d.SealMaterialBG then d.SealMaterialBG:SetAlpha(0) end
            if d.BackFrame then
                S.StripTextures(d.BackFrame)
                if d.BackFrame.BackButton then
                    S.Button(d.BackFrame.BackButton)
                    d.BackFrame.BackButton:SetFrameLevel(5)
                end
            end
            local bd = S.Backdrop(d)
            if bd then
                bd:ClearAllPoints()
                bd:SetPoint("TOPLEFT", d, "TOPLEFT", -3, 5)

                bd:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", 1, -5)
            end
            if d.RewardsFrameContainer and d.RewardsFrameContainer.RewardsFrame then
                S.StripTextures(d.RewardsFrameContainer.RewardsFrame)
            end
            for _, b in next, { d.AbandonButton, d.ShareButton, d.TrackButton } do
                if b then
                    S.StripTextures(b)
                    S.Button(b)
                    b:SetFrameLevel(5)
                end
            end
            if d.TrackButton then d.TrackButton:SetWidth(95) end

            if d.ShareButton and d.AbandonButton and d.TrackButton then
                local sibs = {
                    [d.AbandonButton] = true,
                    [d.ShareButton] = true,
                    [d.TrackButton] = true,
                }
                for b in next, sibs do
                    if not S.data(b).aeSeamed then
                        for i = 1, b:GetNumPoints() do
                            local point, rel, relPoint, x, y = b:GetPoint(i)
                            if rel and sibs[rel] then
                                local nx = x or 0
                                if point:find("LEFT", 1, true) and relPoint:find("RIGHT", 1, true) then
                                    nx = nx + 1
                                elseif point:find("RIGHT", 1, true) and relPoint:find("LEFT", 1, true) then
                                    nx = nx - 1
                                end
                                if nx ~= (x or 0) then
                                    b:SetPoint(point, rel, relPoint, nx, y or 0)
                                end
                            end
                        end
                        S.data(b).aeSeamed = true
                    end
                end
            end
        end

        local overview = qmf.QuestsFrame and qmf.QuestsFrame.CampaignOverview
        if overview then
            if overview.ScrollFrame and overview.ScrollFrame.ScrollBar then
                S.TrimScrollBar(overview.ScrollFrame.ScrollBar)
            end
            if overview.BorderFrame then overview.BorderFrame:SetAlpha(0) end
            S.StripTextures(overview)
            S.Backdrop(overview)
        end

        local qsm = qmf.QuestSessionManagement
        if qsm then
            S.StripTextures(qsm)
            local cmd = qsm.ExecuteSessionCommand
            if cmd and not S.data(cmd).sessionIcon then
                S.Backdrop(cmd)
                S.Hover(cmd)
                local icon = cmd:CreateTexture(nil, "ARTWORK")
                icon:SetPoint("TOPLEFT", 1, -1)
                icon:SetPoint("BOTTOMRIGHT", -1, 1)
                S.data(cmd).sessionIcon = icon
                hooksecurefunc(qsm, "UpdateExecuteCommandAtlases", UpdateExecuteCommandAtlases)
                UpdateExecuteCommandAtlases(qsm)
            end
        end

        local legend = qmf.MapLegend
        if legend then
            if legend.TitleText then S.SetFont(legend.TitleText, 15, "OUTLINE") end
            if legend.BorderFrame then legend.BorderFrame:SetAlpha(0) end
            local ls = legend.ScrollFrame
            if ls then
                S.StripTextures(ls)
                S.Backdrop(ls)
                if ls.Background then ls.Background:SetAlpha(0) end
                if ls.ScrollBar then S.TrimScrollBar(ls.ScrollBar) end
            end
        end

        local events = qmf.EventsFrame
        if events then
            if events.TitleText then S.SetFont(events.TitleText, 15, "OUTLINE") end
            if events.BorderFrame then events.BorderFrame:SetAlpha(0) end
            local box = events.ScrollBox
            if box then
                S.StripTextures(box)
                S.Backdrop(box)
                if box.Background then box.Background:SetAlpha(0) end
            end
            for _, region in next, { events:GetRegions() } do
                if region:IsObjectType("Texture") then
                    region:Hide()
                    break
                end
            end
            if events.ScrollBar then S.TrimScrollBar(events.ScrollBar) end
        end

        if _G.QuestMapDetailsScrollFrame and _G.QuestMapDetailsScrollFrame.ScrollBar then
            S.TrimScrollBar(_G.QuestMapDetailsScrollFrame.ScrollBar)
        end

        HandleSideTabs(qmf)
    end

    if frame.SidePanelToggle then
        if frame.SidePanelToggle.CloseButton then S.ArrowButton(frame.SidePanelToggle.CloseButton, "left") end
        if frame.SidePanelToggle.OpenButton then S.ArrowButton(frame.SidePanelToggle.OpenButton, "right") end
    end

    local bf = frame.BorderFrame
    if bf then
        S.StripTextures(bf)
        bf:SetFrameStrata(frame:GetFrameStrata())
        if bf.NineSlice then bf.NineSlice:SetAlpha(0) end
        if bf.CloseButton then S.CloseButton(bf.CloseButton) end
        if bf.MaximizeMinimizeFrame then S.MaxMinFrame(bf.MaximizeMinimizeFrame) end
    end

    HandleOverlayFrames(frame)
    if not S.skinIndex.__mapOverlayHook then
        S.skinIndex.__mapOverlayHook = true
        hooksecurefunc(frame, "AddOverlayFrame", function(f, templateName)
            local skin = templateName and OVERLAY_TEMPLATE_SKINS[templateName]
            if skin and f.overlayFrames then
                skin(f.overlayFrames[#f.overlayFrames])
            end
        end)
    end
end

S:RegisterEarly(Skin, "WorldMap")
