local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local hooksecurefunc = hooksecurefunc

-- barbershop/customization rebuilt on Blizzard_CustomizationUI
-- (CustomizationFrameBaseMixin). selectionPopoutPool is gone from the
-- live client; every option is now dropdownPool
-- (CustomizationDropdownWithSteppersAndLabelTemplate) or sliderPool.
-- Checkbox pool template renamed CharCustomizeOptionCheckButtonTemplate
-- -> CustomizationOptionCheckButtonTemplate.
local function OnCategorySelected(list)
    if list.dropdownPool then
        for option in list.dropdownPool:EnumerateActive() do
            if not S.data(option).skinned then
                local dropdown = option.Dropdown
                if dropdown then
                    -- Dropdown.SelectionDetails is Blizzard's managed
                    -- display area for the current choice: ColorSwatch1/2
                    -- + glows get re-atlased ("charactercreate-customize-
                    -- palette"), vertex-colored and Show()n per selection
                    -- (CustomizationOptionTemplates.lua:594+). S.Button's
                    -- child sweep was Show->Hide-killing them, so every
                    -- Blizzard Show() executed Hide -- blank box next to
                    -- color options. Protect the whole display area.
                    local details = dropdown.SelectionDetails
                    if details then
                        for _, region in ipairs({ details:GetRegions() }) do
                            if region.IsObjectType and region:IsObjectType("Texture") then
                                S.Protect(region)
                            end
                        end
                    end
                    S.Button(dropdown)
                end
                if option.DecrementButton then S.Button(option.DecrementButton) end
                if option.IncrementButton then S.Button(option.IncrementButton) end
                if option.Label then S.SetFont(option.Label) end
                S.data(option).skinned = true
            end
        end
    end

    if list.sliderPool then
        for slider in list.sliderPool:EnumerateActive() do
            if not S.data(slider).skinned then
                S.StepSlider(slider)
                S.data(slider).skinned = true
            end
        end
    end

    local pool = list.pools and list.pools.GetPool
        and list.pools:GetPool("CustomizationOptionCheckButtonTemplate")
    if pool then
        for frame in pool:EnumerateActive() do
            if not S.data(frame).skinned then
                if frame.Button then S.CheckBox(frame.Button) end
                if frame.Label then S.SetFont(frame.Label) end
                S.data(frame).skinned = true
            end
        end
    end
end

local function SkinCharCustomize()
    local frame = _G.CharCustomizeFrame
    if not frame or S.data(frame).skinned then return end

    if frame.AddMissingOptions then
        hooksecurefunc(frame, "AddMissingOptions", OnCategorySelected)
    end
    S.data(frame).skinned = true
end

local function SkinBarber()
    local frame = _G.BarberShopFrame
    if not frame or S.data(frame).skinned then return end

    if frame.ResetButton then S.Button(frame.ResetButton) end
    if frame.CancelButton then S.Button(frame.CancelButton) end
    if frame.AcceptButton then S.Button(frame.AcceptButton) end
    S.data(frame).skinned = true
end

local function Skin()
    SkinBarber()
    SkinCharCustomize()
end

S:Register("Blizzard_BarbershopUI", Skin, "Barber")
S:Register("Blizzard_CharacterCustomize", Skin, "Barber")
