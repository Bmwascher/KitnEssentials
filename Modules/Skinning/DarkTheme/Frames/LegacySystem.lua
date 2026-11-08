local KE = select(2, ...)
local S = KE.Skins
local _G = _G

local function Skin()
    local frame = _G.LegacySystemFrame
    if not frame then return S.Skip("LegacySystemFrame missing") end
    if S.data(frame).skinned then return end
    -- True leaves each page's art to that page's own skin.
    S.Frame(frame, true)
    S.FontStrings(frame.TitleContainer)
    S.SideTabsInPlace(frame.Tabs)
    -- Each page's controls wait for that page's first show: skinning a scroll
    -- box before its first layout taints it.
    S.Defer(S.LegacyRewardTrackPage, frame.RewardTrackPage)
    S.Defer(S.LegacyChallengesPage, frame.ChallengesPage)
    S.Defer(S.LegacyTreePage, frame.TreePage)
end

S:Register("Blizzard_LegacySystem", Skin, "LegacySystem")
