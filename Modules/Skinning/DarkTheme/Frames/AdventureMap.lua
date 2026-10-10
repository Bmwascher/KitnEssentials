local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local hooksecurefunc = hooksecurefunc

local function DressAdventureRewards()
    local dlg = _G.AdventureMapQuestChoiceDialog
    local pool = dlg and dlg.rewardPool
    if not pool or not pool.EnumerateActive then return end
    for reward in pool:EnumerateActive() do
        if not S.data(reward).skinned then
            S.data(reward).skinned = true
            -- AdventureMapQuestRewardTemplate is a WIDE 135x41
            -- row (39px icon LEFT + ItemNameBG plate + Name), not a square
            -- tile. Default S.ItemButton fills the icon to the button rect
            -- -- stretched art, Name/plate pushed off-frame (the
            -- screenshot; Midnight reuses this dialog for world-map Prey
            -- hunt offers). An item button that never fills by default
            -- (backdrop:SetOutside(icon)) does not stretch -- our fill
            -- default is the gap, kept for the square-button skins that
            -- rely on it; keepAnchors is the row-shaped escape. Icon at
            -- the house 30px list-row size to match the delve reward rows.
            S.ItemButton(reward, "keepAnchors")
            if reward.Icon then
                reward.Icon:ClearAllPoints()
                reward.Icon:SetPoint("LEFT", reward, "LEFT", 4, 0)
                reward.Icon:SetSize(30, 30)
                reward.Icon:SetDrawLayer("OVERLAY")
            end
        end
    end
end

local function Skin()
    local dlg = _G.AdventureMapQuestChoiceDialog
    if not dlg then return end
    S.StripTextures(dlg)
    local bd = S.Backdrop(dlg)
    if bd then
        bd:ClearAllPoints()
        bd:SetPoint("TOPLEFT", dlg, "TOPLEFT", 0, -13)
        bd:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", 0, -3)
    end
    if dlg.Portrait then dlg.Portrait:SetDrawLayer("OVERLAY", 3) end
    if dlg.Background then dlg.Background:SetAlpha(0) end

    hooksecurefunc(dlg, "RefreshRewards", DressAdventureRewards)

    local child = dlg.Details and dlg.Details.Child
    if child then
        if child.TitleHeader then child.TitleHeader:SetTextColor(1, 1, 0) end
        if child.DescriptionText then child.DescriptionText:SetTextColor(1, 1, 1) end
        if child.ObjectivesHeader then child.ObjectivesHeader:SetTextColor(1, 1, 0) end
        if child.ObjectivesText then child.ObjectivesText:SetTextColor(1, 1, 1) end
    end

    S.CloseButton(dlg.CloseButton)
    if dlg.Details then S.ScrollBar(dlg.Details.ScrollBar) end
    S.Button(dlg.AcceptButton)
    S.Button(dlg.DeclineButton)
end

S:Register("Blizzard_AdventureMap", Skin, "AdventureMap")
