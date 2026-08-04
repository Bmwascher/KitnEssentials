local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local next = next
local hooksecurefunc = hooksecurefunc

local function Skin()
    local frame = _G.TabardFrame
    if not frame then return end
    S.Frame(frame)
    if _G.TabardFrameCancelButton then S.Button(_G.TabardFrameCancelButton) end
    if _G.TabardFrameAcceptButton then S.Button(_G.TabardFrameAcceptButton) end

    if _G.TabardCharacterModelRotateLeftButton then S.RotateButton(_G.TabardCharacterModelRotateLeftButton, "left") end
    if _G.TabardCharacterModelRotateRightButton then S.RotateButton(_G.TabardCharacterModelRotateRightButton, "right") end
    if _G.TabardFrameCostFrame then S.StripTextures(_G.TabardFrameCostFrame) end
    if _G.TabardFrameCustomizationFrame then S.StripTextures(_G.TabardFrameCustomizationFrame) end

    if _G.TabardFrameMoneyInset then
        S.StripTextures(_G.TabardFrameMoneyInset)
        _G.TabardFrameMoneyInset:Hide()
    end
    if _G.TabardFrameMoneyBg then S.StripTextures(_G.TabardFrameMoneyBg) end

    local model = _G.TabardModel
    if model then S.Backdrop(model) end
    for _, emblem in next, { _G.TabardFrameEmblemTopRight, _G.TabardFrameEmblemBottomRight,
        _G.TabardFrameEmblemTopLeft, _G.TabardFrameEmblemBottomLeft } do
        if emblem and model then
            emblem:SetParent(model)
            -- "emblem.Show = nil" removed -- it only existed
            -- to undo KillTexture's old NOOP method surgery, gone as
            -- of v828. The re-Show alone is enough.
            emblem:Show()
        end
    end

    local i = 1
    local button, previous = _G["TabardFrameCustomization" .. i]
    while button do
        S.StripTextures(button)
        local left = _G["TabardFrameCustomization" .. i .. "LeftButton"]
        if left then S.ArrowButton(left, "left") end
        local right = _G["TabardFrameCustomization" .. i .. "RightButton"]
        if right then S.ArrowButton(right, "right") end
        if previous then
            button:ClearAllPoints()
            button:SetPoint("TOP", previous, "BOTTOM", 0, -6)
        end
        i = i + 1
        previous = button
        button = _G["TabardFrameCustomization" .. i]
    end
end

local function AnchorRotate()
    local btn, model = _G.TabardCharacterModelRotateLeftButton, _G.TabardModel
    if not (btn and model) then return end
    btn:ClearAllPoints()
    btn:SetPoint("BOTTOMLEFT", model, "BOTTOMLEFT", 4, 4)
    if not S.data(btn).aeAnchorArmor then
        hooksecurefunc(btn, "SetPoint", function(b, _, _, _, _, _, forced)
            if forced ~= true then
                b:ClearAllPoints()
                b.SetPoint(b, "BOTTOMLEFT", model, "BOTTOMLEFT", 4, 4, true)
            end
        end)
        S.data(btn).aeAnchorArmor = true
    end

    local rbtn = _G.TabardCharacterModelRotateRightButton
    if rbtn then
        rbtn:ClearAllPoints()
        rbtn:SetPoint("TOPLEFT", btn, "TOPRIGHT", 4, 0)
        if not S.data(rbtn).aeAnchorArmor then
            hooksecurefunc(rbtn, "SetPoint", function(b, _, _, _, _, _, forced)
                if forced ~= true then
                    b:ClearAllPoints()
                    b.SetPoint(b, "TOPLEFT", btn, "TOPRIGHT", 4, 0, true)
                end
            end)
            S.data(rbtn).aeAnchorArmor = true
        end
    end
end

local function SkinAll()
    Skin()
    AnchorRotate()
end

S:RegisterEarly(SkinAll, "Tabard")
