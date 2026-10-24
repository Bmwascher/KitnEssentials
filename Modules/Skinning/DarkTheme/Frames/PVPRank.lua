local KE = select(2, ...)
local S = KE.Skins
local _G = _G

-- The left pane is the rank emblem and its progress ring: content with no
-- counterpart on the list tabs, so it keeps Blizzard's art.
local function SkinPage()
    local frame = _G.PVPRankFrame
    if not frame or S.data(frame).skinned then return end
    S.StripTextures(frame)
    S.CharacterSidePane(frame.DetailFrame)
    S.data(frame).skinned = true
end

local function Skin()
    local frame = _G.PVPRankFrame
    if not frame then return S.Skip("PVPRankFrame missing") end
    S.Defer(SkinPage, frame)
end

S:Register("Blizzard_UIPanels_Game", Skin, "PVPRank")
