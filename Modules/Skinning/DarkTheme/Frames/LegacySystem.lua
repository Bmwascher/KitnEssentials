local KE = select(2, ...)
local S = KE.Skins
local _G = _G

local function SkinTreePage()
    local page = _G.LegacySystemFrame and _G.LegacySystemFrame.TreePage
    if not page or S.data(page).skinned then return end
    S.FontStrings(page)
    local traits = page.LegacyTreeTraitPanel
    if traits then
        S.Button(traits.ApplyButton)
        S.EditBox(traits.SearchBox)
    end
    S.data(page).skinned = true
end

local function Skin()
    local frame = _G.LegacySystemFrame
    if not frame then return S.Skip("LegacySystemFrame missing") end
    if S.data(frame).skinned then return end
    -- True keeps each page's Background: the page art stays as Blizzard
    -- draws it.
    S.Frame(frame, true)
    S.FontStrings(frame.TitleContainer)
    S.SideTabsInPlace(frame.Tabs)
    -- Each page's controls wait for that page's first show: skinning a scroll
    -- box before its first layout taints it.
    S.Defer(S.LegacyRewardTrackPage, frame.RewardTrackPage)
    S.Defer(S.LegacyChallengesPage, frame.ChallengesPage)
    S.Defer(SkinTreePage, frame.TreePage)
end

S:Register("Blizzard_LegacySystem", Skin, "LegacySystem")
