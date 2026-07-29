local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local CreateFrame = CreateFrame
local hooksecurefunc = hooksecurefunc

local LABEL_SIZE = 20

-- All three labels get the same treatment and differ only in where they sit.
-- scrollTime is cleared because Blizzard scrolls these on a timer, which
-- fights the fixed position we just gave them.
local function LabelAt(label, parent, x, y)
    if not label then return end

    label:ClearAllPoints()
    label:SetPoint("BOTTOM", parent, x, y)
    S.SetFont(label, LABEL_SIZE, "OUTLINE")
    label.scrollTime = nil
end

local function DressLossDisplay(frame)
    if frame.Icon then
        frame.Icon:ClearAllPoints()
        frame.Icon:SetPoint("CENTER", frame, "CENTER", 0, 0)
    end
    LabelAt(frame.AbilityName, frame, 0, -28)

    local timeLeft = frame.TimeLeft
    if timeLeft then
        LabelAt(timeLeft.NumberText, frame, 4, -58)
        LabelAt(timeLeft.SecondsText, frame, 0, -80)
    end

    if frame.Anim and frame.Anim:IsPlaying() then frame.Anim:Stop() end
end

local function Skin()
    local frame = _G.LossOfControlFrame
    if not frame or S.data(frame).skinned then return end
    if frame.Icon then

        local ring = CreateFrame("Frame", nil, frame)
        ring:SetPoint("TOPLEFT", frame.Icon, "TOPLEFT", -1, 1)
        ring:SetPoint("BOTTOMRIGHT", frame.Icon, "BOTTOMRIGHT", 1, -1)
        ring:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
        local bd = S.Backdrop(ring)
        if bd then bd:SetFrameLevel(ring:GetFrameLevel()) end
        frame.Icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        frame:SetSize(frame.Icon:GetWidth() + 50, frame.Icon:GetWidth() + 50)
    end
    S.StripTextures(frame)
    if frame.AbilityName then frame.AbilityName:ClearAllPoints() end
    if frame.SetUpDisplay then hooksecurefunc(frame, "SetUpDisplay", DressLossDisplay) end
    S.data(frame).skinned = true
end

S:RegisterEarly(Skin, "LossControl")
