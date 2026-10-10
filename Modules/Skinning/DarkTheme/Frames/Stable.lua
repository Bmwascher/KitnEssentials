local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local next = next
local hooksecurefunc = hooksecurefunc

local function AbilitiesLayout(list)
    if not list.abilityPool then return end
    for frame in list.abilityPool:EnumerateActive() do
        if frame.Icon and not S.data(frame).skinned then
            S.Icon(frame.Icon)
            S.data(frame).skinned = true
        end
    end
end

local function SkinModelControls(controlFrame)
    if not controlFrame or S.data(controlFrame).skinned then return end
    for _, child in next, { controlFrame:GetChildren() } do
        if child:IsObjectType("Button") then S.Hover(child) end
    end
    S.data(controlFrame).skinned = true
end

local function Skin()
    local frame = _G.StableFrame
    if not frame or S.data(frame).ported then return end

    S.Frame(frame, true)
    if frame.MainHelpButton then frame.MainHelpButton:Hide() end
    if frame.StableTogglePetButton then S.Button(frame.StableTogglePetButton) end
    if frame.ReleasePetButton then S.Button(frame.ReleasePetButton) end

    local list = frame.StabledPetList
    if list then
        S.StripTextures(list)
        if list.ListName then S.SetFont(list.ListName, 32) end
        if list.ListCounter then
            S.StripTextures(list.ListCounter)
            S.Backdrop(list.ListCounter)
        end
        local filterBar = list.FilterBar
        if filterBar then
            if filterBar.SearchBox then S.EditBox(filterBar.SearchBox) end
            if filterBar.FilterDropdown then
                S.Button(filterBar.FilterDropdown)
                if filterBar.FilterDropdown.ResetButton then S.CloseButton(filterBar.FilterDropdown.ResetButton) end
            end
        end
        if list.ScrollBar then S.TrimScrollBar(list.ScrollBar) end
        if list.ScrollBox then
            S.HookScrollBoxIcons(list.ScrollBox, function(f) return f.Icon end, true)
        end
    end

    local modelScene = frame.PetModelScene
    if modelScene then
        local shadow = modelScene.PetModelSceneShadow
        if shadow then
            shadow:ClearAllPoints()
            shadow:SetPoint("TOPLEFT", 1, -1)
            shadow:SetPoint("BOTTOMRIGHT", -1, 1)
        end
        local inset = modelScene.Inset
        if inset then
            if inset.NineSlice then
                S.StripTextures(inset.NineSlice)
                S.Backdrop(inset.NineSlice)
            end
            if inset.Bg then inset.Bg:Hide() end
        end
        if modelScene.AbilitiesList then
            hooksecurefunc(modelScene.AbilitiesList, "Layout", AbilitiesLayout)
        end
        local petInfo = modelScene.PetInfo
        if petInfo then
            if petInfo.Type then hooksecurefunc(petInfo.Type, "SetText", S.ReplaceIconString) end
            if petInfo.Specialization then S.DropDown(petInfo.Specialization) end
        end
        if modelScene.ControlFrame then SkinModelControls(modelScene.ControlFrame) end
    end
    S.data(frame).ported = true
end

S:Register("Blizzard_StableUI", Skin, "Stable")
