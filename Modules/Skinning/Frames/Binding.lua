local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local next = next
local hooksecurefunc = hooksecurefunc

local function HandleScrollChild(child)
    local icon = child.Icon
    if icon and not S.data(icon).skinned then
        S.Icon(icon)
        icon:SetPoint("LEFT", 3, 0)
        if child.Background then child.Background:Hide() end
        S.Backdrop(child)
        if child.DeleteButton then
            S.Button(child.DeleteButton)
            child.DeleteButton:SetSize(20, 20)

            if child.DeleteButton.SetFrameLevel then
                child.DeleteButton:SetFrameLevel((child:GetFrameLevel() or 1) + 5)
            end
        end
        if child.FrameHighlight then

            local bd = S.GetBackdrop(child)
            if bd then
                child.FrameHighlight:ClearAllPoints()
                child.FrameHighlight:SetPoint("TOPLEFT", bd, "TOPLEFT", 1, -1)
                child.FrameHighlight:SetPoint("BOTTOMRIGHT", bd, "BOTTOMRIGHT", -1, 1)
            end
            child.FrameHighlight:SetColorTexture(0.851, 0.851, 0.851, 0.15)
        end

        if icon then
            if icon.SetNormalTexture then icon:SetNormalTexture(0) end
            local ib = S.GetBackdrop(icon)
            if not ib then S.Backdrop(icon, nil, true) end
        end
        if child.NewOutline then child.NewOutline:SetTexture(nil); child.NewOutline:SetAlpha(0) end
        for _, r in ipairs({ child:GetRegions() }) do
            if r.IsObjectType and r:IsObjectType("Texture") then
                local a = r.GetAtlas and r:GetAtlas()
                if a and (a:find("newicon") or a:find("border") or a:find("Outline")) then
                    r:SetAlpha(0)
                end
            end
        end
        if child.BindingText then S.SetFont(child.BindingText) end
        S.data(icon).skinned = true
    end
end

local function BindingRows(frame)
    if frame.ForEachFrame and frame.view then frame:ForEachFrame(HandleScrollChild) end
end

-- The two side tabs carry a portrait each; Blizzard's art is replaced with a
-- plain spellbook / macro icon so they match the rest of the panel.
local TAB_PORTRAITS = {
    { "PlayerSpellsPortrait", 136830 },
    { "MacrosPortrait", 136377 },
}

local function DressTabPortrait(button, texture)
    if not button then return end
    S.StripTextures(button)
    if button.Portrait then
        button.Portrait:SetTexture(texture)
        S.Icon(button.Portrait, true)
    end
    if button.Highlight and button.Portrait then
        button.Highlight:SetColorTexture(0.851, 0.851, 0.851, 0.15)
    end
end

local function Skin()
    local frame = _G.ClickBindingFrame
    if not frame then return end
    S.Frame(frame)
    if frame.TutorialButton then
        if frame.TutorialButton.Ring then frame.TutorialButton.Ring:Hide() end
    end
    for _, v in next, { "ResetButton", "AddBindingButton", "SaveButton" } do
        if frame[v] then S.Button(frame[v]) end
    end

    if frame.AddBindingButton and frame.SaveButton then
        local pt, rel, relPt, _, y = frame.AddBindingButton:GetPoint(1)
        if rel == frame.SaveButton then
            frame.AddBindingButton:ClearAllPoints()
            frame.AddBindingButton:SetPoint(pt, rel, relPt, -2, y or 0)
        end
    end
    if frame.ScrollBar then S.TrimScrollBar(frame.ScrollBar) end
    if frame.ScrollBoxBackground then frame.ScrollBoxBackground:Hide() end
    if frame.ScrollBox then hooksecurefunc(frame.ScrollBox, "Update", BindingRows) end
    for _, portrait in ipairs(TAB_PORTRAITS) do
        DressTabPortrait(frame[portrait[1]], portrait[2])
    end
    if frame.EnableMouseoverCastCheckbox then
        S.CheckBox(frame.EnableMouseoverCastCheckbox)
        if frame.MouseoverCastKeyDropdown then S.DropDown(frame.MouseoverCastKeyDropdown, true) end
    end
end

S:Register("Blizzard_ClickBindingUI", Skin, "Binding")
