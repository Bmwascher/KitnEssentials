local KE = select(2, ...)
local S = KE.Skins
local _G = _G

local function Skin()
    local frame = _G.GuildInviteFrame
    if not frame then return end
    S.Frame(frame)
    if _G.GuildInviteFrameJoinButton then S.Button(_G.GuildInviteFrameJoinButton) end
    if _G.GuildInviteFrameDeclineButton then S.Button(_G.GuildInviteFrameDeclineButton) end
end

S:RegisterEarly(Skin, "Guild")
