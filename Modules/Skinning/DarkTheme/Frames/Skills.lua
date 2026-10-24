local KE = select(2, ...)
local S = KE.Skins
local _G = _G

local function SkinPage()
    local frame = _G.SkillsFrame
    if not frame or S.data(frame).skinned then return end
    S.CharacterListPage(frame)
    local detail = frame.SkillDetailFrame
    if detail then
        S.CharacterSidePane(detail)
        if detail.RankBar then S.ColoredBar(detail.RankBar) end
    end
    S.data(frame).skinned = true
end

local function Skin()
    local frame = _G.SkillsFrame
    if not frame then return S.Skip("SkillsFrame missing") end
    -- Waits for the page's first show: skinning a scroll box before its first
    -- layout taints it.
    S.Defer(SkinPage, frame)
end

S:Register("Blizzard_UIPanels_Game", Skin, "Skills")
