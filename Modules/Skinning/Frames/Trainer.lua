local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local next = next
local hooksecurefunc = hooksecurefunc

local function ScrollChild(button)
    if not button or S.data(button).skinned then return end
    if button.icon then S.Icon(button.icon, true) end
    local bd = S.Backdrop(button)
    if bd and button.icon then
        bd:ClearAllPoints()
        bd:SetPoint("TOPLEFT", button.icon, "TOPRIGHT", 1, 0)
        bd:SetPoint("BOTTOMRIGHT", button.icon, "BOTTOMRIGHT", 253, 0)
    end
    if button.name and bd then
        button.name:SetParent(bd)
        button.name:SetPoint("TOPLEFT", button.icon, "TOPRIGHT", 6, -2)
        local _, nsz = button.name:GetFont()
        S.SetFont(button.name, (tonumber(nsz) or 12) + 1)
    end
    if button.subText and bd then
        button.subText:SetParent(bd)
        local _, ssz = button.subText:GetFont()
        S.SetFont(button.subText, (tonumber(ssz) or 11) + 1)
    end
    if button.money and bd then button.money:SetParent(bd) button.money:SetPoint("TOPRIGHT", button, "TOPRIGHT", 5, -8) end
    if button.SetNormalTexture then button:SetNormalTexture(0) end
    if button.SetHighlightTexture then button:SetHighlightTexture(0) end
    if button.disabledBG then button.disabledBG:SetTexture(nil) end

    if button.selectedTex then
        button.selectedTex:SetColorTexture(S.palette.brand[1], S.palette.brand[2], S.palette.brand[3], 0.25)
        if bd then
            button.selectedTex:ClearAllPoints()
            button.selectedTex:SetPoint("TOPLEFT", bd, "TOPLEFT", 1, -1)
            button.selectedTex:SetPoint("BOTTOMRIGHT", bd, "BOTTOMRIGHT", -1, 1)
        end
    end

    if bd then S.Hover(button, bd) end
    S.data(button).skinned = true
end

local function ScrollUpdate(frame)
    if frame.ForEachFrame and frame.view then frame:ForEachFrame(ScrollChild) end
end

local function Skin()
    local frame = _G.ClassTrainerFrame
    if not frame then return end
    for _, o in next, { _G.ClassTrainerFrameSkillStepButton, _G.ClassTrainerFrameBottomInset } do
        if o then S.StripTextures(o) end
    end
    if _G.ClassTrainerFramePortrait then S.KillTexture(_G.ClassTrainerFramePortrait) end
    if _G.ClassTrainerTrainButton then
        S.StripTextures(_G.ClassTrainerTrainButton)
        S.Button(_G.ClassTrainerTrainButton)
    end

    -- also targets a Train All button, if one exists. Both
    -- names below are third-party globals -- KitnEssentials has no
    -- Train All button of its own. The OnShow hook and the S.WaitFor
    -- poll below catch a button created after this skin already ran.
    local function SkinEUIButton()
        for _, name in ipairs({ "EUI_TrainAllButton", "AES_TrainAllButton" }) do
            local b = _G[name]
            if b and not S.data(b).skinned then
                S.StripTextures(b)
                S.Button(b)
                S.data(b).skinned = true
            end
        end
    end
    SkinEUIButton()
    -- EllesmereUI's button appears late; a fixed retry delay leaves it
    -- unskinned until that delay expires. Poll per frame until it exists.
    S.WaitFor(function()
        return _G.EUI_TrainAllButton ~= nil or _G.AES_TrainAllButton ~= nil
    end, SkinEUIButton, 300)
    if not S.data(frame).euiHooked then
        frame:HookScript("OnShow", SkinEUIButton)
        S.data(frame).euiHooked = true
    end
    S.Frame(frame)
    if frame.ScrollBox then
        hooksecurefunc(frame.ScrollBox, "Update", ScrollUpdate)

        if frame.ScrollBox.Shadows then
            if frame.ScrollBox.Shadows.Lower then frame.ScrollBox.Shadows.Lower:SetAlpha(0) end
            if frame.ScrollBox.Shadows.Upper then frame.ScrollBox.Shadows.Upper:SetAlpha(0) end
            frame.ScrollBox.Shadows:SetAlpha(0)
        end
    end
    if frame.ScrollBar then S.TrimScrollBar(frame.ScrollBar) end
    if frame.FilterDropdown then S.DropDown(frame.FilterDropdown) end
    local step = _G.ClassTrainerFrameSkillStepButton
    if step then
        local sbd = S.Backdrop(step)
        if step.icon then step.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end

        if step.selectedTex then
            step.selectedTex:SetColorTexture(0.851, 0.851, 0.851, 0.15)
            if sbd then
                step.selectedTex:ClearAllPoints()
                step.selectedTex:SetPoint("TOPLEFT", sbd, "TOPLEFT", 1, -1)
                step.selectedTex:SetPoint("BOTTOMRIGHT", sbd, "BOTTOMRIGHT", -1, 1)
            end
        end
        if sbd then
            S.Hover(step, sbd)
        end
    end
    local bar = _G.ClassTrainerStatusBar
    if bar then
        S.StripTextures(bar)
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        S.Backdrop(bar)
        if bar.rankText then bar.rankText:ClearAllPoints() bar.rankText:SetPoint("CENTER") end
    end
end

S:Register("Blizzard_TrainerUI", Skin, "Trainer")
