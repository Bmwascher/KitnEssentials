local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local next = next
local hooksecurefunc = hooksecurefunc

local function SkinModelControls(controlFrame)
    if not controlFrame or S.data(controlFrame).skinned then return end
    for _, child in next, { controlFrame:GetChildren() } do
        if child:IsObjectType("Button") then S.Hover(child) end
    end
    S.data(controlFrame).skinned = true
end

-- A slot borrows its border from the item name's colour, which Blizzard has
-- already set to the quality colour. Empty, hidden and stateful slots have no
-- item to take a colour from and fall back to the neutral border.
local function TintSlotBorder(slot)
    local bd = slot.Icon and S.GetBackdrop(slot.Icon)
    if not bd then return end

    local named = slot.transmogID and slot.Name
        and not slot.slotState and not slot.isHiddenVisual

    if named then
        bd:SetBackdropBorderColor(slot.Name:GetTextColor())
    else
        bd:SetBackdropBorderColor(S.borderColor[1], S.borderColor[2], S.borderColor[3])
    end
end

local function OnDetailsRefreshed(panel)
    if not panel.slotPool then return end
    for slot in panel.slotPool:EnumerateActive() do
        if slot.Icon and not S.data(slot.Icon).skinned then
            S.Icon(slot.Icon, true)
            if slot.IconBorder then slot.IconBorder:SetAlpha(0) end
            S.data(slot.Icon).skinned = true
        end
        TintSlotBorder(slot)
    end
end

local function OnDressUpResized(frame, isMinimized)
    local details = frame.CustomSetDetailsPanel
    if details then
        details:ClearAllPoints()
        details:SetPoint("TOPLEFT", frame, "TOPRIGHT", 4, 0)
    end
    local dd = frame.OutfitDropdown
    if dd then
        dd:ClearAllPoints()
        dd:SetPoint("TOP", -(isMinimized and 42 or 28), -32)
        dd:SetWidth(isMinimized and 140 or 190)
    end
end

local SET_SELECTED_ALPHA = 0.25

local function DressSetButton(button)
    if S.data(button).skinned then return end
    S.data(button).skinned = true

    S.SlotIcon(button.Icon, button.IconBorder)
    S.Vanish(button, { "BackgroundTexture" })

    local brand, hover = S.palette.brand, S.palette.hover
    if button.SelectedTexture then
        button.SelectedTexture:SetColorTexture(brand[1], brand[2], brand[3], SET_SELECTED_ALPHA)
    end
    if button.HighlightTexture then
        button.HighlightTexture:SetColorTexture(hover[1], hover[2], hover[3], hover[4])
    end
end

local function SetSelectionRows(box)
    if box.ForEachFrame and box.view then
        box:ForEachFrame(DressSetButton)
    end
end

local function Skin()
    local duf = _G.DressUpFrame
    if not duf then return end
    S.Frame(duf)
    if duf.MaximizeMinimizeFrame then S.MaxMinFrame(duf.MaximizeMinimizeFrame) end
    if _G.DressUpFrameResetButton then S.Button(_G.DressUpFrameResetButton) end
    if _G.DressUpFrameCancelButton then S.Button(_G.DressUpFrameCancelButton) end
    if duf.LinkButton then S.Button(duf.LinkButton) end
    if duf.ModelScene and duf.ModelScene.ControlFrame then
        SkinModelControls(duf.ModelScene.ControlFrame)
    end

    local toggle = duf.ToggleCustomSetDetailsButton
    if toggle then
        S.Button(toggle, "killIcon")
        local icon = toggle:CreateTexture()
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetPoint("TOPLEFT", toggle, "TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", toggle, "BOTTOMRIGHT", -1, 1)
        icon:SetTexture(1392954)
    end

    local sel = duf.SetSelectionPanel
    if sel then
        S.StripTextures(sel)
        S.Backdrop(sel)
        if sel.ScrollBar then S.TrimScrollBar(sel.ScrollBar) end
        if sel.ScrollBox and not S.data(sel.ScrollBox).hooked then
            hooksecurefunc(sel.ScrollBox, "Update", SetSelectionRows)
            S.data(sel.ScrollBox).hooked = true
        end
    end

    if duf.ModelBackground then duf.ModelBackground:SetDrawLayer("BACKGROUND", 1) end
    if duf.LinkButton then
        duf.LinkButton:SetSize(110, 22)
        duf.LinkButton:ClearAllPoints()
        duf.LinkButton:SetPoint("BOTTOMLEFT", 4, 4)
    end
    if _G.DressUpFrameCancelButton then
        _G.DressUpFrameCancelButton:SetPoint("BOTTOMRIGHT", -4, 4)
    end
    if _G.DressUpFrameResetButton and _G.DressUpFrameCancelButton then
        _G.DressUpFrameResetButton:SetPoint("RIGHT", _G.DressUpFrameCancelButton, "LEFT", -3, 0)
    end

    local csd = duf.CustomSetDropdown
    if csd then
        S.DropDown(csd, true)
        if csd.SaveButton then S.Button(csd.SaveButton) end
    end

    local details = duf.CustomSetDetailsPanel
    if details then
        details:DisableDrawLayer("BACKGROUND")
        details:DisableDrawLayer("OVERLAY")
        S.Backdrop(details)
        if details.ClassBackground then details.ClassBackground:SetAllPoints() end
        if details.Refresh then hooksecurefunc(details, "Refresh", OnDetailsRefreshed) end
    end

    hooksecurefunc(duf, "ConfigureSize", OnDressUpResized)
end

S:RegisterEarly(Skin, "DressingRoom")
