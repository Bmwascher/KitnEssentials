local KE = select(2, ...)
local S = KE.Skins
local _G = _G

local GOLD = { 1, 0.8, 0 }

local function SkinNPE()
    if _G.KeyboardMouseConfirmButton then S.Button(_G.KeyboardMouseConfirmButton) end

    local frame = _G.NPE_TutorialWalk_Frame
    local container = frame and frame.ContainerFrame
    if container then
        for _, key in ipairs({ "TURNLEFT", "TURNRIGHT", "MOVEFORWARD", "MOVEBACKWARD" }) do
            local entry = container[key]
            if entry and entry.KeyBind then entry.KeyBind:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) end
        end
    end

    local singleKey = _G.NPE_TutorialSingleKey_Frame
    local singleContainer = singleKey and singleKey.ContainerFrame
    if singleContainer and singleContainer.KeyBind and singleContainer.KeyBind.KeyBind then
        singleContainer.KeyBind.KeyBind:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    end
end

local function SkinGuide()
    local frame = _G.GuideFrame
    if not frame or S.data(frame).ported then return end

    S.Frame(frame)
    if frame.Title then frame.Title:SetTextColor(1, 1, 1) end

    local scrollFrame = frame.ScrollFrame
    if scrollFrame then
        if scrollFrame.ScrollBar then S.TrimScrollBar(scrollFrame.ScrollBar) end
        if scrollFrame.ConfirmationButton then S.Button(scrollFrame.ConfirmationButton) end
        local scrollChild = scrollFrame.Child
        if scrollChild then
            if scrollChild.ObjectivesFrame then
                S.StripTextures(scrollChild.ObjectivesFrame)
                S.Backdrop(scrollChild.ObjectivesFrame)
            end
            if scrollChild.Text then scrollChild.Text:SetTextColor(1, 1, 1) end
        end
    end
    S.data(frame).ported = true
end

S:Register("Blizzard_NewPlayerExperience", SkinNPE, "Guide")
S:Register("Blizzard_NewPlayerExperienceGuide", SkinGuide, "Guide")
