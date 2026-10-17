local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local next = next
local hooksecurefunc = hooksecurefunc

local function SkinLFG()
    local frame = _G.LookingForGuildFrame
    if not frame or S.data(frame).ported then return end

    S.Frame(frame)

    for _, name in next, { "LookingForGuildPvPButton", "LookingForGuildWeekendsButton",
        "LookingForGuildWeekdaysButton", "LookingForGuildRPButton", "LookingForGuildRaidButton",
        "LookingForGuildQuestButton", "LookingForGuildDungeonButton" } do
        if _G[name] then S.CheckBox(_G[name]) end
    end
    for _, name in next, { "LookingForGuildTankButton", "LookingForGuildHealerButton",
        "LookingForGuildDamagerButton" } do
        local b = _G[name]
        if b and b.checkButton then S.CheckBox(b.checkButton) end
    end

    if _G.LookingForGuildBrowseFrameContainerScrollBar then S.ScrollBar(_G.LookingForGuildBrowseFrameContainerScrollBar) end
    if _G.LookingForGuildBrowseButton then S.Button(_G.LookingForGuildBrowseButton) end
    if _G.LookingForGuildRequestButton then S.Button(_G.LookingForGuildRequestButton) end

    if _G.LookingForGuildCommentInputFrame then
        S.StripTextures(_G.LookingForGuildCommentInputFrame)
        S.Backdrop(_G.LookingForGuildCommentInputFrame)
    end

    for i = 1, 3 do
        local tab = _G["LookingForGuildFrameTab" .. i]
        if tab then S.Tab(tab) end
    end

    local membership = _G.GuildFinderRequestMembershipFrame
    if membership then
        S.StripTextures(membership, true)
        S.Backdrop(membership)
        if _G.GuildFinderRequestMembershipFrameAcceptButton then S.Button(_G.GuildFinderRequestMembershipFrameAcceptButton) end
        if _G.GuildFinderRequestMembershipFrameCancelButton then S.Button(_G.GuildFinderRequestMembershipFrameCancelButton) end
        if _G.GuildFinderRequestMembershipFrameInputFrame then
            S.StripTextures(_G.GuildFinderRequestMembershipFrameInputFrame)
            S.Backdrop(_G.GuildFinderRequestMembershipFrameInputFrame)
        end
    end
    S.data(frame).ported = true
end

local function Skin()
    if _G.LookingForGuildFrame then
        SkinLFG()
    elseif _G.LookingForGuildFrame_CreateUIElements then
        hooksecurefunc("LookingForGuildFrame_CreateUIElements", SkinLFG)
    end
end

S:Register("Blizzard_LookingForGuildUI", Skin, "LFGuild")
