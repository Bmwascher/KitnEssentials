local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local next = next

local function Skin()
    local frame = _G.ArchaeologyFrame
    if not frame or S.data(frame).ported then return end

    S.Frame(frame)

    local artifactPage = frame.artifactPage
    if artifactPage then
        if artifactPage.solveFrame and artifactPage.solveFrame.solveButton then S.Button(artifactPage.solveFrame.solveButton) end
        if artifactPage.backButton then S.Button(artifactPage.backButton) end
    end

    local raceFilter = _G.ArchaeologyFrameRaceFilter
    if raceFilter then
        S.DropDown(raceFilter)
        if raceFilter.Text then
            raceFilter.Text:ClearAllPoints()
            raceFilter.Text:SetPoint("LEFT", raceFilter, "LEFT", 4, 0)
        end
    end

    if _G.ArchaeologyFrameBgLeft then S.KillTexture(_G.ArchaeologyFrameBgLeft) end
    if _G.ArchaeologyFrameBgRight then S.KillTexture(_G.ArchaeologyFrameBgRight) end
    if frame.completedPage and frame.completedPage.infoText then frame.completedPage.infoText:SetTextColor(1, 1, 1) end
    if frame.helpPage and frame.helpPage.titleText then frame.helpPage.titleText:SetTextColor(1, 1, 0) end
    if _G.ArchaeologyFrameHelpPageDigTitle then _G.ArchaeologyFrameHelpPageDigTitle:SetTextColor(1, 1, 0) end
    if _G.ArchaeologyFrameHelpPageHelpScrollHelpText then _G.ArchaeologyFrameHelpPageHelpScrollHelpText:SetTextColor(1, 1, 1) end
    if artifactPage and artifactPage.historyTitle then artifactPage.historyTitle:SetTextColor(1, 1, 0) end
    if _G.ArchaeologyFrameArtifactPageHistoryScrollChildText then _G.ArchaeologyFrameArtifactPageHistoryScrollChildText:SetTextColor(1, 1, 1) end

    for i = 1, (_G.ARCHAEOLOGY_MAX_RACES or 0) do
        local race = frame.summaryPage and frame.summaryPage["race" .. i]
        local artifact = frame.completedPage and frame.completedPage["artifact" .. i]
        if race and race.raceName then race.raceName:SetTextColor(1, 1, 1) end
        if artifact then
            if artifact.icon then S.Icon(artifact.icon, true) end
            if artifact.border then artifact.border:SetTexture(nil) end
            if artifact.artifactName then artifact.artifactName:SetTextColor(1, 0.8, 0.1) end
            if artifact.artifactSubText then artifact.artifactSubText:SetTextColor(0.6, 0.6, 0.6) end
        end
    end

    for _, page in next, { frame.completedPage, frame.summaryPage } do
        if page then
            for _, region in next, { page:GetRegions() } do
                if region.IsObjectType and region:IsObjectType("FontString") then
                    region:SetTextColor(1, 0.8, 0.1)
                end
            end
        end
    end

    local helpScroll = _G.ArchaeologyFrameHelpPageHelpScroll
    if helpScroll and helpScroll.ScrollBar then S.TrimScrollBar(helpScroll.ScrollBar) end

    for _, page in next, { frame.summaryPage, frame.completedPage } do
        if page then
            if page.prevPageButton then S.ArrowButton(page.prevPageButton, "left") end
            if page.nextPageButton then S.ArrowButton(page.nextPageButton, "right") end
        end
    end

    if frame.rankBar then
        S.StripTextures(frame.rankBar)
        S.StatusBar(frame.rankBar)
        S.ProgressFill(frame.rankBar)
    end
    if artifactPage and artifactPage.solveFrame and artifactPage.solveFrame.statusBar then
        local bar = artifactPage.solveFrame.statusBar
        S.StripTextures(bar)
        S.StatusBar(bar)
        S.ProgressFill(bar)
    end
    if _G.ArchaeologyFrameArtifactPageIcon then S.Icon(_G.ArchaeologyFrameArtifactPageIcon) end

    local digsite = _G.ArcheologyDigsiteProgressBar
    if digsite then
        S.StripTextures(digsite)
        if digsite.BarTitle then S.SetFont(digsite.BarTitle, nil, "OUTLINE") end
        if digsite.FillBar then
            S.StatusBar(digsite.FillBar)
            S.ProgressFill(digsite.FillBar)
        end
    end
    S.data(frame).ported = true
end

S:Register("Blizzard_ArchaeologyUI", Skin, "Archaeology")
