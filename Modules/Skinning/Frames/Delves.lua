local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local next = next
local hooksecurefunc = hooksecurefunc

local function HandleOptionButton(button)
    local d = S.data(button)
    if d.delveSkinned then return end
    if button.Border then button.Border:SetAlpha(0) end
    if button.Icon then S.Icon(button.Icon) end
    d.delveSkinned = true
end

-- flyout stays at Blizzard's stock anchor (ElvUI parity --
-- they never reposition; the opaque backdrop is the whole fix). The
-- v807 right-side experiment is retired.
local function HandleOptionSlot(slotFrame, skipHook)
    if not slotFrame or not slotFrame.OptionsList then return end
    local option = slotFrame.OptionsList
    S.StripTextures(option)
    -- v3.5.802 (flyout transparent, rows overlapping the
    -- panel): the list's ScrollBox is frameStrata="HIGH" while the
    -- OptionsList (and a backdrop childed to it) sits in the config
    -- panel's MEDIUM strata -- rows floated in HIGH above everything
    -- and the backdrop was buried under the panel. Parent the
    -- backdrop to the SCROLLBOX instead: HIGH strata, one level under
    -- the rows, above the panel.
    if option.ScrollBox then
        -- (still see-through): the standard window
        -- fill is 80% alpha -- fine for panels over the world, wrong
        -- for a dropdown sitting directly on other UI text. Opaque
        -- fill for this flyout (matches ElvUI's near-opaque template).
        local bd = S.Backdrop(option.ScrollBox)
        if bd then bd:SetBackdropColor(0.063, 0.063, 0.063, 1) end
        if not skipHook then
            S.HookScrollBox(option.ScrollBox, HandleOptionButton)
        end
    end
end

local function UpdatePaginatedButtonDisplay(frame)
    if not frame.buttons then return end
    for _, button in next, frame.buttons do
        local icon = button.Icon
        if icon and not S.GetBackdrop(icon) then
            S.Icon(icon, true)
        end
    end
end

local function SkinCompanionConfig()
    local config = _G.DelvesCompanionConfigurationFrame
    if config then
        if config.CloseButton then
            config.CloseButton:ClearAllPoints()
            config.CloseButton:SetPoint("TOPRIGHT", config, "TOPRIGHT", -3, -3)
        end
        S.Frame(config)
        if config.CompanionConfigShowAbilitiesButton then
            S.Button(config.CompanionConfigShowAbilitiesButton)
        end

        HandleOptionSlot(config.CompanionCombatRoleSlot, true)
        HandleOptionSlot(config.CompanionUtilityTrinketSlot)
        HandleOptionSlot(config.CompanionCombatTrinketSlot)
    end

    local abilityList = _G.DelvesCompanionAbilityListFrame
    if abilityList then
        S.Frame(abilityList)
        if abilityList.DelvesCompanionRoleDropdown then
            S.DropDown(abilityList.DelvesCompanionRoleDropdown)
        end
        local paging = abilityList.DelvesCompanionAbilityListPagingControls
        if paging then
            if paging.PrevPageButton then S.ArrowButton(paging.PrevPageButton, "left") end
            if paging.NextPageButton then S.ArrowButton(paging.NextPageButton, "right") end
        end
        hooksecurefunc(abilityList, "UpdatePaginatedButtonDisplay", UpdatePaginatedButtonDisplay)
    end
end

S:Register("Blizzard_DelvesCompanionConfiguration", SkinCompanionConfig, "Delves")

local function DressDelveRewards(rewardFrame)
    local d = S.data(rewardFrame)
    if d.delveSkinned then return end
    S.Backdrop(rewardFrame)
    if rewardFrame.NameFrame then rewardFrame.NameFrame:SetAlpha(0) end
    if rewardFrame.Icon then
        S.SlotIcon(rewardFrame.Icon, rewardFrame.IconBorder)
    end
    d.delveSkinned = true
end

local function SkinDifficultyPicker()
    local picker = _G.DelvesDifficultyPickerFrame
    if not picker then return end
    S.StripTextures(picker)
    S.Backdrop(picker)

    if picker.CloseButton then
        S.CloseButton(picker.CloseButton)
        picker.CloseButton:ClearAllPoints()
        picker.CloseButton:SetPoint("TOPRIGHT", picker, "TOPRIGHT", -3, -3)
    end
    if picker.Dropdown then S.DropDown(picker.Dropdown) end
    if picker.EnterDelveButton then S.Button(picker.EnterDelveButton) end

    if picker.DelveRewardsContainerFrame and picker.DelveRewardsContainerFrame.ScrollBox then
        S.HookScrollBox(picker.DelveRewardsContainerFrame.ScrollBox, DressDelveRewards)
    end
end

S:Register("Blizzard_DelvesDifficultyPicker", SkinDifficultyPicker, "Delves")

local function SkinDashboard()
    local dashboard = _G.DelvesDashboardFrame
    if not dashboard then return end
    if dashboard.DashboardBackground then dashboard.DashboardBackground:SetAlpha(0) end
    local panel = dashboard.ButtonPanelLayoutFrame
        and dashboard.ButtonPanelLayoutFrame.CompanionConfigButtonPanel
    if panel and panel.CompanionConfigButton then
        S.Button(panel.CompanionConfigButton)
    end
end

S:Register("Blizzard_DelvesDashboardUI", SkinDashboard, "Delves")
