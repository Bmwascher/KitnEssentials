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

local function DressSituationDropdowns()
    local tf = _G.TransmogFrame
    local sit = tf and tf.WardrobeCollection and tf.WardrobeCollection.TabContent
        and tf.WardrobeCollection.TabContent.SituationsFrame
    local situations = sit and sit.Situations
    if not situations then return end
    for _, child in next, { situations:GetChildren() } do
        if child.Dropdown and not S.data(child.Dropdown).skinned then
            S.DropDown(child.Dropdown, true)
            child.Dropdown:SetWidth(300)
            S.data(child.Dropdown).skinned = true
        end
    end
end

local function OnPageControlsMoved(frame)
    if frame.PrevPageButton then
        frame.PrevPageButton:ClearAllPoints()
        frame.PrevPageButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 64, -6)
    end
    if frame.NextPageButton then
        frame.NextPageButton:ClearAllPoints()
        frame.NextPageButton:SetPoint("LEFT", frame.PrevPageButton, "RIGHT", 14, -1)
    end
end

local function HandlePagingControls(pc)
    if not pc or S.data(pc).skinned then return end
    if pc.PrevPageButton then S.ArrowButton(pc.PrevPageButton, "left") end
    if pc.NextPageButton then S.ArrowButton(pc.NextPageButton, "right") end
    if pc.ShouldClearOnUpdateAfterClean then
        hooksecurefunc(pc, "ShouldClearOnUpdateAfterClean", OnPageControlsMoved)
    end
    S.data(pc).skinned = true
end

local function OutfitPopup_OnShow(popup)
    if S.data(popup).skinned then return end
    S.StripTextures(popup)
    S.Backdrop(popup)
    if popup.BorderBox then
        S.StripTextures(popup.BorderBox)
        local eb = popup.BorderBox.IconSelectorEditBox
        if eb then S.EditBox(eb) end
    end
    for _, key in next, { "OkayButton", "CancelButton" } do
        local b = popup.BorderBox and popup.BorderBox[key] or popup[key]
        if b then S.Button(b) end
    end
    S.data(popup).skinned = true
end

local function Skin()
    local tf = _G.TransmogFrame
    if not tf then return end
    S.Frame(tf)

    local help = tf.HelpPlateButton
    if help then
        S.KillAllTextures(help)
        help:SetAlpha(0)
        if help.Ring then help.Ring:Hide() end
    end

    local oc = tf.OutfitCollection
    if oc then
        if oc.Background then oc.Background:Hide() end
        if oc.DividerBar then oc.DividerBar:Hide() end
        S.Backdrop(oc)
        if oc.GradientTop then oc.GradientTop:Hide() end
        if oc.GradientBottom then oc.GradientBottom:Hide() end
        if oc.OutfitList and oc.OutfitList.ScrollBar then S.TrimScrollBar(oc.OutfitList.ScrollBar) end
        if oc.SaveOutfitButton then S.Button(oc.SaveOutfitButton) end
        if oc.MoneyFrame then
            S.StripTextures(oc.MoneyFrame)
            S.Backdrop(oc.MoneyFrame)
        end
    end

    local cp = tf.CharacterPreview
    if cp then
        if cp.Background then cp.Background:Hide() end
        if cp.Gradients then cp.Gradients:Hide() end
        S.Backdrop(cp)
        local toggles = cp.ToggleOptions
        if toggles then
            for _, key in next, { "HideIgnoredToggle", "PreviewedWeaponToggle", "SheatheWeaponToggle" } do
                local t = toggles[key]
                if t and t.Checkbox then S.CheckBox(t.Checkbox) end
            end
        end
        if cp.ClearAllPendingButton then S.Button(cp.ClearAllPendingButton) end
        if cp.ModelScene and cp.ModelScene.ControlFrame then
            SkinModelControls(cp.ModelScene.ControlFrame)
        end
    end

    local wc = tf.WardrobeCollection
    if wc and wc.TabContent then
        if wc.TabContent.Border then wc.TabContent.Border:Hide() end
        if wc.TabContent.Background then wc.TabContent.Background:Hide() end
        if wc.Background then wc.Background:Hide() end
        S.Backdrop(wc)

        if wc.TabHeaders then
            for _, tab in next, { wc.TabHeaders:GetChildren() } do
                S.Tab(tab)
            end
        end

        local items = wc.TabContent.ItemsFrame
        if items then
            if items.SearchBox then S.EditBox(items.SearchBox) end
            if items.FilterButton then S.Button(items.FilterButton) end
            if items.WeaponDropdown then S.DropDown(items.WeaponDropdown, true) end
            if items.WeaponSheatheDropdown then S.DropDown(items.WeaponSheatheDropdown, true) end
            if items.PagedContent then HandlePagingControls(items.PagedContent.PagingControls) end
            if items.SecondaryAppearanceToggle and items.SecondaryAppearanceToggle.Checkbox then
                S.CheckBox(items.SecondaryAppearanceToggle.Checkbox)
            end
        end

        local sets = wc.TabContent.SetsFrame
        if sets then
            if sets.SearchBox then S.EditBox(sets.SearchBox) end
            if sets.FilterButton then S.Button(sets.FilterButton) end
            if sets.PagedContent then HandlePagingControls(sets.PagedContent.PagingControls) end
        end

        local custom = wc.TabContent.CustomSetsFrame
        if custom then
            if custom.NewCustomSetButton then S.Button(custom.NewCustomSetButton) end
            if custom.PagedContent then HandlePagingControls(custom.PagedContent.PagingControls) end
        end

        local sit = wc.TabContent.SituationsFrame
        if sit then
            if sit.Situations then
                if sit.Situations.Background then sit.Situations.Background:Hide() end
                S.Backdrop(sit.Situations)
            end
            if sit.DefaultsButton then S.Button(sit.DefaultsButton) end
            if sit.EnabledToggle and sit.EnabledToggle.Checkbox then S.CheckBox(sit.EnabledToggle.Checkbox) end
            if sit.ApplyButton then S.Button(sit.ApplyButton) end
            if sit.UndoButton then S.Button(sit.UndoButton) end
            if sit.Init then hooksecurefunc(sit, "Init", DressSituationDropdowns) end
            if sit.Refresh then hooksecurefunc(sit, "Refresh", DressSituationDropdowns) end
        end
    end

    if tf.OutfitPopup then
        tf.OutfitPopup:HookScript("OnShow", OutfitPopup_OnShow)
    end
end

S:Register("Blizzard_Transmog", Skin, "Transmog")
