local KE = select(2, ...)
local S = KE.Skins

local _G = _G
local ipairs = ipairs

local function SkinSelectorChild(button)
    if button.Icon and not S.data(button).skinned then
        S.ItemButton(button)
        S.data(button).skinned = true
    end
end

local function SelectorScrollUpdate(box)

    if box.ForEachFrame and box.view then box:ForEachFrame(SkinSelectorChild) end
end

local function SkinMacroPopup(popup)
    if S.data(popup).skinned then return end
    S.StripTextures(popup)
    S.Backdrop(popup)
    if popup.BorderBox then
        S.StripTextures(popup.BorderBox)
        local edit = popup.BorderBox.IconSelectorEditBox
        if edit then

            if edit.DisableDrawLayer then edit:DisableDrawLayer("BACKGROUND") end
            S.EditBox(edit)
        end

        local dd = popup.BorderBox.IconTypeDropdown
            or (popup.BorderBox.IconTypeDropDown and popup.BorderBox.IconTypeDropDown.DropDownMenu)
        if dd then S.DropDown(dd, true) end
        if popup.BorderBox.OkayButton then S.Button(popup.BorderBox.OkayButton) end
        if popup.BorderBox.CancelButton then S.Button(popup.BorderBox.CancelButton) end
        local sel = popup.BorderBox.SelectedIconArea
        local selBtn = sel and sel.SelectedIconButton
        if selBtn then S.ItemButton(selBtn) end
    end
    if popup.IconSelector then
        if popup.IconSelector.ScrollBar then S.TrimScrollBar(popup.IconSelector.ScrollBar) end
        if popup.IconSelector.ScrollBox and popup.IconSelector.ScrollBox.Update then
            hooksecurefunc(popup.IconSelector.ScrollBox, "Update", SelectorScrollUpdate)
        end
    end
    S.data(popup).skinned = true
end

local function SkinMacroUI()
    local frame = _G.MacroFrame
    if not frame or S.data(frame).skinned then return end

    S.Frame(frame)

    for _, key in ipairs({ "Border", "RaisedBorder", "BorderFrame", "TitleContainer" }) do
        local child = frame[key]
        if child then
            S.StripTextures(child)
            if child.NineSlice and child.NineSlice.SetAlpha then child.NineSlice:SetAlpha(0) end
        end
    end
    local inset = frame.Inset or _G.MacroFrameInset
    if inset then S.Inset(inset) end

    local close = frame.CloseButton or _G.MacroFrameCloseButton
    if close then S.CloseButton(close) end

    local selector = frame.MacroSelector
    if selector then
        if selector.ScrollBox then
            S.StripTextures(selector.ScrollBox)

            S.Backdrop(selector.ScrollBox)
            if selector.ScrollBox.Update then
                hooksecurefunc(selector.ScrollBox, "Update", SelectorScrollUpdate)
                SelectorScrollUpdate(selector.ScrollBox)
            end
        end
        if selector.ScrollBar then S.TrimScrollBar(selector.ScrollBar) end
    end

    local selected = _G.MacroFrameSelectedMacroButton
    if selected then S.ItemButton(selected) end
    if _G.MacroFrameSelectedMacroBackground then
        S.StripTextures(_G.MacroFrameSelectedMacroBackground)
    end

    local textBg = _G.MacroFrameTextBackground
    if textBg then
        if textBg.NineSlice then textBg.NineSlice:SetAlpha(0) end
        S.StripTextures(textBg)
        S.Backdrop(textBg, -2)
    end
    if _G.MacroFrameText then S.Backdrop(_G.MacroFrameText, -2) end
    local textScroll = _G.MacroFrameScrollFrame
    if textScroll and textScroll.ScrollBar then S.TrimScrollBar(textScroll.ScrollBar) end

    local buttons = {
        "MacroNewButton", "MacroEditButton", "MacroDeleteButton",
        "MacroSaveButton", "MacroCancelButton", "MacroExitButton",
    }
    for _, name in ipairs(buttons) do
        if _G[name] then S.Button(_G[name]) end
    end

    if _G.MacroNewButton and _G.MacroFrame then
        _G.MacroNewButton:ClearAllPoints()
        _G.MacroNewButton:SetPoint("BOTTOMRIGHT", _G.MacroFrame, "BOTTOMRIGHT", -86, 4)
    end

    for i = 1, 2 do
        local tab = _G["MacroFrameTab" .. i]
        if tab then S.Tab(tab) end
    end

    local tab1 = _G.MacroFrameTab1
    if tab1 and not S.data(tab1).xArmor then
        S.data(tab1).xArmor = true
        local function PinTabX(t, _, _, _, x, y)
            if x ~= 2 then
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", _G.MacroFrame, "TOPLEFT", 2, y or -28)
            end
        end
        PinTabX(tab1, nil, nil, nil, select(4, tab1:GetPoint(1)), select(5, tab1:GetPoint(1)))
        hooksecurefunc(tab1, "SetPoint", PinTabX)
    end

    if _G.MacroPopupFrame then
        _G.MacroPopupFrame:HookScript("OnShow", SkinMacroPopup)
    end

    S.data(frame).skinned = true
end

S:Register("Blizzard_MacroUI", SkinMacroUI, "Macro")
