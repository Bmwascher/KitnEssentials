local KE = select(2, ...)
local S = KE.Skins
local _G = _G

function S.LegacyRewardTrackPage()
    local page = _G.LegacySystemFrame and _G.LegacySystemFrame.RewardTrackPage
    if not page or S.data(page).skinned then return end
    S.FontStrings(page)
    local bar = page.LegacyRewardProgressBar
    if bar then S.SetFont(bar.Text) end
    S.data(page).skinned = true
end

function S.LegacyChallengesPage()
    local page = _G.LegacySystemFrame and _G.LegacySystemFrame.ChallengesPage
    if not page or S.data(page).skinned then return end
    S.FontStrings(page)
    local list = page.CategoryList
    if list then
        S.Button(list.FilterDropdown)
        if list.FilterDropdown then S.CloseButton(list.FilterDropdown.ResetButton) end
        S.EditBox(list.SearchBox)
        S.ScrollBar(list.ScrollBar)
        S.SetFont(list.NoResultsText)
    end
    if page.DetailPane then S.ScrollBar(page.DetailPane.ScrollBar) end
    S.data(page).skinned = true
end
