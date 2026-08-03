local KE = select(2, ...)
local S = KE.Skins
local _G = _G

local function Skin()
    local f = _G.TutorialFrame
    if not f then return end
    f:DisableDrawLayer("BORDER")
    S.Template(f, "Window")
    local bg = _G.TutorialFrameBackground
    if bg then
        bg:Hide()

        bg:SetAlpha(0)
        hooksecurefunc(bg, "Show", function(b) b:Hide() end)
    end
    S.CloseButton(_G.TutorialFrameCloseButton)
    S.Button(_G.TutorialFrameOkayButton)
    S.ArrowButton(_G.TutorialFramePrevButton, "left")
    S.ArrowButton(_G.TutorialFrameNextButton, "right")
end

S:RegisterEarly(Skin, "TutorialFrame")
