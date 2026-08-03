local KE = select(2, ...)
local S = KE.Skins
local _G = _G

local function Skin()
    local frame = _G.PetitionFrame
    if not frame then return end
    if S.data(frame).skinned then return end

    S.Frame(frame)
    S.TrimScrollBar(frame.ScrollBar)

    if _G.PetitionFrameSignButton then S.Button(_G.PetitionFrameSignButton) end
    if _G.PetitionFrameRequestButton then S.Button(_G.PetitionFrameRequestButton) end
    if _G.PetitionFrameRenameButton then S.Button(_G.PetitionFrameRenameButton) end
    if _G.PetitionFrameCancelButton then S.Button(_G.PetitionFrameCancelButton) end

    local gold = { _G.PetitionFrameCharterTitle, _G.PetitionFrameMasterTitle, _G.PetitionFrameMemberTitle }
    for _, fs in ipairs(gold) do
        if fs then fs:SetTextColor(1, 1, 0) end
    end
    if _G.PetitionFrameCharterName then _G.PetitionFrameCharterName:SetTextColor(1, 1, 1) end
    if _G.PetitionFrameMasterName then _G.PetitionFrameMasterName:SetTextColor(1, 1, 1) end
    for i = 1, 9 do
        local fs = _G["PetitionFrameMemberName" .. i]
        if fs then fs:SetTextColor(1, 1, 1) end
    end
    if _G.PetitionFrameInstructions then _G.PetitionFrameInstructions:SetTextColor(1, 1, 1) end

    if _G.PetitionFrameRenameButton and _G.PetitionFrameRequestButton and _G.PetitionFrameCancelButton then
        _G.PetitionFrameRenameButton:SetPoint("LEFT", _G.PetitionFrameRequestButton, "RIGHT", 3, 0)
        _G.PetitionFrameRenameButton:SetPoint("RIGHT", _G.PetitionFrameCancelButton, "LEFT", -3, 0)
    end
end

S:RegisterEarly(Skin, "Petition")
