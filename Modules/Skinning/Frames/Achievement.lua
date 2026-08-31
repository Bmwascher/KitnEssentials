local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local next = next
local select = select
local hooksecurefunc = hooksecurefunc
local function NOOP() end -- luacheck: ignore 211/NOOP

local BAR_TEX = "Interface\\Buttons\\WHITE8x8"

-- Blizzard paints criteria text black once the achievement itself is complete,
-- which vanishes against a dark backdrop. Its other two picks -- green for a
-- met criterion, grey for a pending one -- read fine and are left alone, so
-- the only thing to do is walk the frames it already built and lift the black.
local function Whiten(fontString)
    if not fontString then return end

    fontString:SetTextColor(1, 1, 1)
    fontString:SetShadowOffset(0, 0)
end

local function WhitenFinishedCriteria(objectivesFrame)
    if not objectivesFrame or not objectivesFrame.completed then return end

    for _, criteria in next, objectivesFrame.criterias or {} do
        Whiten(criteria.Name)
    end

    for _, meta in next, objectivesFrame.metas or {} do
        Whiten(meta.Label)
    end
end

local function DressHighlight(button, backdrop)
    if not button then return end
    button:SetHighlightTexture(BAR_TEX)
    local hl = button:GetHighlightTexture()

    hl:SetVertexColor(S.palette.hover[1], S.palette.hover[2], S.palette.hover[3], S.palette.hover[4])
    hl:ClearAllPoints()
    hl:SetPoint("TOPLEFT", backdrop or button, "TOPLEFT", 1, -1)
    hl:SetPoint("BOTTOMRIGHT", backdrop or button, "BOTTOMRIGHT", -1, 1)
end

local function SkinSearchButton(button)
    if not button then return end
    S.StripTextures(button)
    local bd = S.Backdrop(button)
    local icon = button.icon or button.Icon
    if icon then S.Icon(icon) end
    DressHighlight(button, bd)
end

local function GreenGradient(bar)
    if not bar then return end

    S.StripTextures(bar)
    S.StatusBar(bar)
    S.ProgressFill(bar)
end

local function OnObjectivesShown(frame)
    local objectives = frame:GetObjectiveFrame()
    if not objectives or not objectives.progressBars then return end

    -- Own flag: S.StatusBar guards on `skinned` itself, so setting that here
    -- made the call a no-op and the bars kept Blizzard's art.
    for _, bar in next, objectives.progressBars do
        if not S.data(bar).aeCriteriaBar then
            S.data(bar).aeCriteriaBar = true
            GreenGradient(bar)
        end
    end
end

local function OnPlusMinusChanged(button)
    if button.DateCompleted:IsShown() then
        if button.accountWide then
            button.Label:SetTextColor(0, 0.6, 1)
        else
            button.Label:SetTextColor(0.9, 0.9, 0.9)
        end
    elseif button.accountWide then
        button.Label:SetTextColor(0, 0.3, 0.5)
    else
        button.Label:SetTextColor(0.65, 0.65, 0.65)
    end
end

-- Blizzard's achievement plate: the plaque art, glow and icon ring all go, so
-- the row reads as a flat panel with just the icon on it.
local ACHIEVEMENT_PLATE = { "TitleBar", "Glow" }

local function StripPlate(button)
    button:DisableDrawLayer("BORDER")
    S.HideAll(button, ACHIEVEMENT_PLATE)
    if button.Icon then button.Icon.frame:Hide() end
end

local function FlattenPlate(frame)
    if frame.NineSlice then frame.NineSlice:SetAlpha(0) end
    if frame.SetBackdrop then frame:SetBackdrop(nil) end
end

local function SkinBar(bar)
    if not bar then return end
    GreenGradient(bar)
    local name = bar:GetName()
    if not name then return end
    local title = _G[name .. "Title"]
    if title then title:SetPoint("LEFT", 4, 0) end
    local label = _G[name .. "Label"]
    if label then label:SetPoint("LEFT", 4, 0) end
    local text = _G[name .. "Text"]
    if text then text:SetPoint("RIGHT", -4, 0) end
end

local function SkinSummaryBar(frame)
    S.StripTextures(frame)
    local bar = frame.StatusBar
    GreenGradient(bar)
    bar.Title:SetTextColor(1, 1, 1)
    bar.Title:SetPoint("LEFT", bar, "LEFT", 6, 0)
    bar.Text:SetPoint("RIGHT", bar, "RIGHT", -5, 0)
end

local function SkinCompareRow(button)
    FlattenPlate(button)
    button.Background:Hide()
    local bd = S.Backdrop(button)
    if bd then
        bd:ClearAllPoints()
        bd:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
        bd:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    end
    StripPlate(button)
    S.Icon(button.Icon.texture)
end

local function SkinResultRow(child)
    if S.data(child).skinned then return end
    S.data(child).skinned = true
    S.StripTextures(child)
    S.Icon(child.Icon)
    local bd = S.Backdrop(child)
    DressHighlight(child, bd)
end

local function ResultRows(frame)
    frame:ForEachFrame(SkinResultRow)
end

local function CategoriesScrollUpdateChild(child)
    local button = child.Button
    if button and not S.data(button).skinned then
        S.data(button).skinned = true
        S.StripTextures(button)
        local bd = S.Backdrop(button)
        if button.Background then button.Background:Hide() end
        DressHighlight(button, bd)
    end
end

local function CategoriesScrollUpdate(frame)
    frame:ForEachFrame(CategoriesScrollUpdateChild)
end

local function StatsScrollUpdateChild(child)
    if S.data(child).skinned then return end
    S.data(child).skinned = true
    S.StripTextures(child)

    DressHighlight(child, child)
end

local function StatsScrollUpdate(frame)
    frame:ForEachFrame(StatsScrollUpdateChild)
end

local function SkinComparisonRow(child)
    if S.data(child).skinned then return end
    S.data(child).skinned = true
    SkinCompareRow(child.Player)
    -- AUDIT: was SetTextColor = NOOP -- method surgery on a
    -- Blizzard object, the exact class that tainted the flyout for 13
    -- versions. Hook and re-assert instead.
    S.LockTextColor(child.Player.Description, 0.9, 0.9, 0.9)
    SkinCompareRow(child.Friend)
end

local function ComparisonRows(frame)
    frame:ForEachFrame(SkinComparisonRow)
end

local function SkinStatRow(child)
    if S.data(child).skinned then return end
    S.data(child).skinned = true
    S.StripTextures(child)
    S.Backdrop(child, 0, true)
end

local function StatRows(frame)
    frame:ForEachFrame(SkinStatRow)
end

local function SkinAchievementRow(child)
    if S.data(child).skinned then return end
    S.data(child).skinned = true
    S.StripTextures(child, true)
    child.Background:SetAlpha(0)

    if child.Highlight and child.Highlight.SetColorTexture then
        child.Highlight:SetColorTexture(S.palette.hover[1], S.palette.hover[2], S.palette.hover[3], S.palette.hover[4])
    elseif child.Highlight then
        child.Highlight:SetAlpha(0)
    end
    child.Icon.frame:Hide()
    S.LockTextColor(child.Description, 0.9, 0.9, 0.9)
    -- AUDIT: see above -- hook instead of owning the method.

    local bd = S.Backdrop(child)
    if bd then
        bd:ClearAllPoints()
        bd:SetPoint("TOPLEFT", child, "TOPLEFT", 1, -1)
        bd:SetPoint("BOTTOMRIGHT", child, "BOTTOMRIGHT", 0, 2)
        if child.Highlight and child.Highlight.SetColorTexture then
            child.Highlight:ClearAllPoints()
            child.Highlight:SetPoint("TOPLEFT", bd, "TOPLEFT", 1, -1)
            child.Highlight:SetPoint("BOTTOMRIGHT", bd, "BOTTOMRIGHT", -1, 1)
        end
    end
    S.Icon(child.Icon.texture, true)

    S.CheckBox(child.Tracked)
    child.Tracked:SetSize(20, 20)
    child.Check:SetAlpha(0)

    hooksecurefunc(child, "UpdatePlusMinusTexture", OnPlusMinusChanged)
    hooksecurefunc(child, "DisplayObjectives", OnObjectivesShown)
end

local function AchievementRows(frame)
    frame:ForEachFrame(SkinAchievementRow)
end

-- The search box and the filter dropdown share one row, and on a category page
-- -- where the filter appears -- the pair reaches far enough left to sit under
-- the achievement points. Lifting the search box above the filter clears it.
--
-- It cannot be done by size or by layoutIndex: HeaderDetails is only 38 tall
-- (Categories' top at -19 down to -57) and one control is 22 of that, so the
-- second row has to live in the band above, beside the close button.
--
-- Re-anchored from a post-hook on the layout rather than by setting
-- ignoreInLayout on Blizzard's frame. LayoutMixin re-points every child on each
-- pass, so ours has to be the last write -- and this way nothing of ours is
-- written into a Blizzard table. (Note this is NOT the ignoreInLayout that is
-- banned elsewhere: that one is read by the SECURE
-- UIParent_ManageFramePositions pass. This layout is an ordinary frame's. The
-- post-hook is still the better shape here.)
--
-- Only while the filter is SHOWN. Without it the row has all the space it
-- needs, and Blizzard's own placement is already right -- their next Layout()
-- puts the box back with no work from us.
local function StackSearch(filters)
    local search, filter = filters.SearchBox, filters.FilterDropdown
    if not (search and filter) then return end
    if not filter:IsShown() then return end

    search:ClearAllPoints()
    search:SetPoint("BOTTOMRIGHT", filter, "TOPRIGHT", 0, 2)
end

local function Skin()
    local frame = _G.AchievementFrame
    if not frame then return end
    S.Frame(frame)

    S.StripTextures(frame.Header)
    frame.Header.Title:Hide()
    frame.Header.Points:SetPoint("TOP", frame, 0, -3)

    -- 12.1 moved the search box and the filter dropdown into a new
    -- AchievementFrame.HeaderDetails.Filters, and dropped the
    -- AchievementFrameFilterDropdown global on the way. Reaching for the old
    -- field is a nil index, and that aborted the WHOLE achievement skin.
    --
    -- Filters is a HorizontalLayoutFrame, so Blizzard positions its children
    -- itself and a plain SetPoint is undone on the next layout pass -- hence
    -- the pre-12.1 geometry below is gated, and the one place we do move a
    -- child goes through StackSearch on a Layout post-hook. The search preview
    -- moves with the box (it is now a child of it) and is left where Blizzard
    -- puts it.
    local filters = frame.HeaderDetails and frame.HeaderDetails.Filters
    local search = (filters and filters.SearchBox) or frame.SearchBox
    local filter = (filters and filters.FilterDropdown) or _G.AchievementFrameFilterDropdown

    if search then
        S.EditBox(search)
        -- Blizzard anchors the magnifier at LEFT x=1, which sits it directly
        -- against our 1px border. The template's own left text inset is 16, so
        -- there is room to move it clear without the text meeting it.
        if search.searchIcon then
            search.searchIcon:ClearAllPoints()
            search.searchIcon:SetPoint("LEFT", search, "LEFT", 4, 0)
        end
        if filters then
            -- Matched to the filter dropdown beside it, which is 135x22
            -- (WowStyle1FilterDropdownTemplate with resizeToText off) against
            -- Blizzard's 107x30 search box. Size is the one thing the layout
            -- frame does not own -- it positions by layoutIndex and READS each
            -- child's size -- so this is safe where a SetPoint would be undone.
            -- topPadding is the same hint the dropdown carries, and is what
            -- keeps the box in line with the dropdown on the pages that have
            -- no filter and so leave it in the row.
            search:SetSize(135, 22)
            search.topPadding = 6
            StackSearch(filters)
            if filters.Layout then
                hooksecurefunc(filters, "Layout", StackSearch)
                pcall(filters.Layout, filters)
            end
        else
            search:ClearAllPoints()
            search:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -25, -2)
            search:SetPoint("BOTTOMLEFT", frame, "TOPRIGHT", -130, -20)
        end
    end

    -- 12.1's Back button: steps back through the achievement selection history,
    -- so it earns its place -- Blizzard only shows it when there is somewhere
    -- to go back to and disables it otherwise. Skinned, not hidden.
    if frame.HeaderDetails and frame.HeaderDetails.Back then
        S.Button(frame.HeaderDetails.Back)
    end

    if filter then
        pcall(S.DropDown, filter)
        if not filters and search then
            filter:ClearAllPoints()
            filter:SetPoint("RIGHT", search, "LEFT", -3, 0)
        end
    end

    for i = 1, 3 do
        S.Tab(_G["AchievementFrameTab" .. i])
    end

    local preview = (search and search.SearchPreviewContainer) or frame.SearchPreviewContainer
    if preview then
        local showAll = preview.ShowAllSearchResults
        S.StripTextures(preview)
        local pbd = S.Backdrop(preview)
        if not filters then
            preview:ClearAllPoints()
            preview:SetPoint("TOPLEFT", frame, "TOPRIGHT", 7, -2)
        end
        if pbd and showAll then
            pbd:SetPoint("BOTTOMRIGHT", showAll, 3, -3)
        end
        for i = 1, 5 do
            SkinSearchButton(preview["SearchPreview" .. i])
        end
        SkinSearchButton(showAll)
    end

    local result = frame.SearchResults
    if result then
        result:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 15, -1)
        S.StripTextures(result)
        S.Backdrop(result)
        S.ScrollBar(result.ScrollBar)
        hooksecurefunc(result.ScrollBox, "Update", ResultRows)
    end

    S.ScrollBar(_G.AchievementFrameCategories.ScrollBar)
    S.ScrollBar(_G.AchievementFrameAchievements.ScrollBar)

    _G.AchievementFrameSummaryAchievementsHeaderHeader:SetVertexColor(1, 1, 1, 0)
    _G.AchievementFrameSummaryCategoriesHeaderTexture:SetVertexColor(1, 1, 1, 0)
    _G.AchievementFrameWaterMark:SetAlpha(0)

    if _G.AchievementFrame_UpdateTabs then
        hooksecurefunc("AchievementFrame_UpdateTabs", function()
            for i = 1, 3 do
                local t = _G["AchievementFrameTab" .. i]
                if t then S.RecenterTabText(t) end
            end
        end)
    end

    hooksecurefunc("AchievementFrameSummary_UpdateAchievements", function()
        for i = 1, _G.ACHIEVEMENTUI_MAX_SUMMARY_ACHIEVEMENTS do
            local bu = _G["AchievementFrameSummaryAchievement" .. i]
            if bu then
                if bu.accountWide then
                    bu.Label:SetTextColor(0, 0.6, 1)
                else
                    bu.Label:SetTextColor(0.9, 0.9, 0.9)
                end
                if not S.data(bu).skinned then
                    S.data(bu).skinned = true
                    S.StripTextures(bu, true)
                    FlattenPlate(bu)

                    local bg = bu.Background
                    bg:SetTexture(BAR_TEX)
                    bg:SetVertexColor(0, 0, 0, 0.25)

                    StripPlate(bu)
                    bu.Highlight:SetAlpha(0)
                    S.Icon(bu.Icon.texture, true)

                    local bd = S.Backdrop(bu)
                    if bd then
                        bd:ClearAllPoints()
                        bd:SetPoint("TOPLEFT", bu, "TOPLEFT", 2, -2)
                        bd:SetPoint("BOTTOMRIGHT", bu, "BOTTOMRIGHT", -2, 2)
                    end
                end
                bu.Description:SetTextColor(0.9, 0.9, 0.9)
            end
        end
    end)

    S.StripTextures(_G.AchievementFrameAchievements)
    local achChild = select(3, _G.AchievementFrameAchievements:GetChildren())
    if achChild then achChild:Hide() end

    S.StripTextures(_G.AchievementFrameCategories)

    S.StripTextures(_G.AchievementFrameSummary)

    for _, sumChild in ipairs({ _G.AchievementFrameSummary:GetChildren() }) do
        S.StripTextures(sumChild)
    end

    hooksecurefunc(_G.AchievementFrameCategories.ScrollBox, "Update", CategoriesScrollUpdate)

    local statsChild = select(4, _G.AchievementFrameStats:GetChildren())
    if statsChild then statsChild:Hide() end
    hooksecurefunc(_G.AchievementFrameStats.ScrollBox, "Update", StatsScrollUpdate)

    local comparison = _G.AchievementFrameComparison
    hooksecurefunc(comparison.AchievementContainer.ScrollBox, "Update", ComparisonRows)
    S.StripTextures(comparison)
    local compChild = select(5, comparison:GetChildren())
    if compChild then compChild:Hide() end
    hooksecurefunc(comparison.StatContainer.ScrollBox, "Update", StatRows)

    for i = 1, 12 do
        local name = "AchievementFrameSummaryCategoriesCategory" .. i
        local bu = _G[name]
        if bu then
            GreenGradient(bu)
            bu.Label:SetTextColor(1, 1, 1)
            bu.Label:SetPoint("LEFT", bu, "LEFT", 6, 0)
            bu.Text:SetPoint("RIGHT", bu, "RIGHT", -5, 0)
            local hl = _G[name .. "ButtonHighlight"]
            if hl then hl:SetAlpha(0) end
        end
    end

    hooksecurefunc(_G.AchievementFrameAchievements.ScrollBox, "Update", AchievementRows)

    hooksecurefunc("AchievementObjectives_DisplayCriteria", WhitenFinishedCriteria)

    SkinBar(_G.AchievementFrameSummaryCategoriesStatusBar)

    if _G.AchievementFrame.Header and _G.AchievementFrame.Header.Points then
        local pts = _G.AchievementFrame.Header.Points
        -- Deliberately NOT fonted here. Forcing 16 was the last thing holding
        -- the points total outside the size bands; the font object it inherits
        -- is in the GlobalFonts sweep, so face and size both arrive from there.
        if _G.AchievementFrameAchievements then
            pts:ClearAllPoints()

            pts:SetPoint("BOTTOM", _G.AchievementFrameAchievements, "TOP", -4, 2)
        end
    end
    _G.AchievementFrameSummaryAchievementsEmptyText:SetText("")

    if _G.AchievementFrameStatsBG then _G.AchievementFrameStatsBG:Hide() end
    S.ScrollBar(_G.AchievementFrameStats.ScrollBar)

    _G.AchievementFrameComparisonHeaderBG:Hide()
    _G.AchievementFrameComparisonHeaderPortrait:Hide()
    _G.AchievementFrameComparisonHeaderPortraitBg:Hide()
    _G.AchievementFrameComparisonHeader:SetPoint("BOTTOMRIGHT", comparison, "TOPRIGHT", 39, 26)
    local chBD = S.Backdrop(_G.AchievementFrameComparisonHeader)
    if chBD then
        chBD:ClearAllPoints()
        chBD:SetPoint("TOPLEFT", _G.AchievementFrameComparisonHeader, "TOPLEFT", 20, -20)
        chBD:SetPoint("BOTTOMRIGHT", _G.AchievementFrameComparisonHeader, "BOTTOMRIGHT", -28, -5)
    end

    S.ScrollBar(comparison.AchievementContainer.ScrollBar)
    SkinSummaryBar(comparison.Summary.Player)
    SkinSummaryBar(comparison.Summary.Friend)
    S.ScrollBar(comparison.StatContainer.ScrollBar)
end

S:Register("Blizzard_AchievementUI", Skin, "Achievement")
