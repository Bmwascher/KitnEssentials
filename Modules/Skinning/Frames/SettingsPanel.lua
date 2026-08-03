local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local ipairs, pairs = ipairs, pairs -- luacheck: ignore 211/pairs

local function BumpFonts(frame, delta)
    if not frame or not frame.GetRegions then return end
    for _, r in ipairs({ frame:GetRegions() }) do
        if r.IsObjectType and r:IsObjectType("FontString") then
            local _, cur = r:GetFont()
            S.SetFont(r, (cur or 12) + delta)
        end
    end
end

local function SkinCategoryChild(child)
    local d = S.data(child)
    if d.skinned then return end
    d.skinned = true

    BumpFonts(child, 1)
    if child.Background then
        child.Background:SetAlpha(0)
        local bd = S.Backdrop(child.Background)
        if bd then
            bd:ClearAllPoints()
            bd:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -4)
            bd:SetPoint("BOTTOMRIGHT", child, "BOTTOMRIGHT", -4, 0)
        end
    end
end

local function CategoryScrollUpdate(box)

    if box.ForEachFrame and box.view then box:ForEachFrame(SkinCategoryChild) end
end

local function SkinSettingDropdown(option)
    if not option or S.data(option).skinned then return end
    local main = option.Dropdown or option.Button or option.Control
    if main then
        if main.Arrow then S.DropDown(main) else S.Button(main) end

        local mbd = S.GetBackdrop(main)
        if mbd then
            mbd:ClearAllPoints()
            mbd:SetPoint("TOPLEFT", main, "TOPLEFT", 0, -2)
            mbd:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", 0, 2)
        end
    end
    if option.DecrementButton then S.ArrowButton(option.DecrementButton, "left") end
    if option.IncrementButton then S.ArrowButton(option.IncrementButton, "right") end
    S.data(option).skinned = true
end

local BRAND = S.palette.brand
local function HookBindListening(btn)
    if not btn or not btn.SetSelected or S.data(btn).bindHook then return end
    S.data(btn).bindHook = true
    hooksecurefunc(btn, "SetSelected", function(b, selected)
        local bd = S.GetBackdrop(b)
        if not bd then return end
        if selected then
            bd:SetBackdropBorderColor(BRAND[1], BRAND[2], BRAND[3], 1)
        else
            bd:SetBackdropBorderColor(S.borderColor[1], S.borderColor[2], S.borderColor[3], S.borderColor[4])
        end
    end)
end

local function SweepBindingsPool(header)
    if not header or not header.bindingsPool then return end
    for panel in header.bindingsPool:EnumerateActive() do
        if not S.data(panel).skinned then
            for _, key in ipairs({ "Button1", "Button2", "CustomButton" }) do
                local b = panel[key]
                if b then
                    S.Button(b)
                    HookBindListening(b)
                end
            end
            S.data(panel).skinned = true
        end
    end
end

local COLLAPSE_ATLAS = "Soulbinds_Collection_CategoryHeader_Collapse"
local EXPAND_ATLAS = "Soulbinds_Collection_CategoryHeader_Expand"
local function UpdateHeaderExpand(child, expanded)
    if child.collapseTex then
        child.collapseTex:SetAtlas(expanded and COLLAPSE_ATLAS or EXPAND_ATLAS, true)
    end
    SweepBindingsPool(child)
end

local function SkinSettingsChild(child)
    local d = S.data(child)
    if d.skinned then return end
    d.skinned = true

    if child.NineSlice then
        child.NineSlice:SetAlpha(0)
    end

    if child.Checkbox then S.CheckBox(child.Checkbox) end
    if child.Dropdown then SkinSettingDropdown(child.Dropdown) end
    if child.Control and child.Control.Dropdown then SkinSettingDropdown(child.Control) end
    if child.ColorBlindFilterDropDown then SkinSettingDropdown(child.ColorBlindFilterDropDown) end
    if child.SliderWithSteppers then S.StepSlider(child.SliderWithSteppers) end

    if child.Button1 then S.Button(child.Button1); HookBindListening(child.Button1) end
    if child.Button2 then S.Button(child.Button2); HookBindListening(child.Button2) end
    if child.PushToTalkKeybindButton then S.Button(child.PushToTalkKeybindButton); HookBindListening(child.PushToTalkKeybindButton) end
    if child.ToggleTest then S.Button(child.ToggleTest) end

    local button = child.Button
    if button and not button.New then
        S.StripTextures(button)
        for _, key in ipairs({ "Left", "Middle", "Right" }) do
            if button[key] and button[key].SetAlpha then button[key]:SetAlpha(0) end
        end
        local hbd = S.Backdrop(button)
        if hbd then
            hbd:ClearAllPoints()
            hbd:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -1)
            hbd:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 3)
            S.Hover(button, hbd)
            if not child.collapseTex then
                child.collapseTex = hbd:CreateTexture(nil, "OVERLAY")
                child.collapseTex:SetPoint("RIGHT", -10, 0)
            end
        end
        UpdateHeaderExpand(child, false)
        if child.EvaluateVisibility and not S.data(child).bindPoolHook then
            hooksecurefunc(child, "EvaluateVisibility", UpdateHeaderExpand)
            S.data(child).bindPoolHook = true
        end
    elseif button then
        S.Button(button)
    end

    for _, tabKey in ipairs({ "BaseTab", "RaidTab" }) do
        local tab = child[tabKey]
        if tab and not S.data(tab).skinned then
            S.StripTextures(tab)
            local tbd = S.Backdrop(tab)
            if tbd then
                tbd:ClearAllPoints()
                tbd:SetPoint("TOPLEFT", tab, "TOPLEFT", 3, -12)
                tbd:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -3, -2)
                tbd:SetBackdropColor(S.controlBg[1], S.controlBg[2], S.controlBg[3], S.controlBg[4])
            end
            S.FontStrings(tab, 12, "")
            S.Hover(tab, tbd)
            S.data(tab).skinned = true
        end
    end
    for _, groupKey in ipairs({ "BaseQualityControls", "RaidQualityControls" }) do
        local group = child[groupKey]
        if group then
            for _, sub in ipairs({ group:GetChildren() }) do
                if sub.SliderWithSteppers then S.StepSlider(sub.SliderWithSteppers) end
                if sub.Checkbox then S.CheckBox(sub.Checkbox) end
                if sub.Control then SkinSettingDropdown(sub.Control) end
            end
        end
    end

    if child.Controls then
        for i = 1, #child.Controls do
            local control = child.Controls[i]
            if control.SliderWithSteppers then S.StepSlider(control.SliderWithSteppers) end
        end
    end
end

local function SettingsScrollUpdate(box)

    if box.ForEachFrame and box.view then box:ForEachFrame(SkinSettingsChild) end
end

local function Skin()
    local frame = _G.SettingsPanel
    if not frame or S.data(frame).skinned then return end

    S.Frame(frame)
    if frame.Bg then frame.Bg:Hide() end

    if frame.ClosePanelButton then S.CloseButton(frame.ClosePanelButton) end
    if frame.SearchBox then S.EditBox(frame.SearchBox) end
    if frame.ApplyButton then S.Button(frame.ApplyButton) end
    if frame.CloseButton then
        S.Button(frame.CloseButton)

        local cbd = S.GetBackdrop(frame.CloseButton) or S.Backdrop(frame.CloseButton)
        if cbd then
            cbd:SetBackdropColor(S.controlBg[1], S.controlBg[2], S.controlBg[3], S.controlBg[4])
        end

        if frame.CloseButton.SetText then
            local label = frame.CloseButton.GetText and frame.CloseButton:GetText()
            if not label or label == "" then
                frame.CloseButton:SetText(_G.CLOSE or "Close")
            end
        end
        S.FontStrings(frame.CloseButton, 13, "")
    end

    -- v3.5.873 ("these headers for the game/addons tab get blizzard
    -- skins after hovering"): StripTextures alone could never hold here.
    -- These tabs re-atlas Left/Middle/Right in place on every state change
    -- (SelectableButton in a RadioButtonGroup -> Options_Tab_Active_*), so
    -- the first hover put the art straight back. Lock the three art regions
    -- stripped; the hook re-clears and self-terminates.
    for _, tab in ipairs({ frame.GameTab, frame.AddOnsTab }) do
        if tab then
            S.StripTextures(tab)
            for _, key in ipairs({ "Left", "Middle", "Right" }) do
                S.LockStripped(tab[key])
            end
            BumpFonts(tab, 2)
        end
    end

    local list = frame.CategoryList
    if list then

        S.Backdrop(list)
        if list.ScrollBar then S.TrimScrollBar(list.ScrollBar) end
        if list.ScrollBox and list.ScrollBox.Update then
            hooksecurefunc(list.ScrollBox, "Update", CategoryScrollUpdate)
            CategoryScrollUpdate(list.ScrollBox)
        end
    end

    local container = frame.Container
    local settings = container and container.SettingsList
    if container then S.Backdrop(container) end
    if settings then
        if settings.Header and settings.Header.DefaultsButton then
            S.Button(settings.Header.DefaultsButton)
        end
        if settings.ScrollBar then S.TrimScrollBar(settings.ScrollBar) end
        if settings.ScrollBox and settings.ScrollBox.Update then
            hooksecurefunc(settings.ScrollBox, "Update", SettingsScrollUpdate)
            SettingsScrollUpdate(settings.ScrollBox)
        end
    end

    S.data(frame).skinned = true
end

S:RegisterEarly(Skin, "SettingsPanel")
