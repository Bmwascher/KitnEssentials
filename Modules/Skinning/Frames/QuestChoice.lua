local KE = select(2, ...)
local S = KE.Skins
local _G = _G

local function SkinQuestChoice()
    local frame = _G.QuestChoiceFrame
    if not frame or S.data(frame).skinned then return end
    S.StripTextures(frame)
    S.Backdrop(frame)
    if frame.CloseButton then S.CloseButton(frame.CloseButton) end
    S.data(frame).skinned = true
end

S:Register("Blizzard_QuestChoice", SkinQuestChoice, "QuestChoice")
