local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local hooksecurefunc = hooksecurefunc

local function SkinExtraButton(button)
    if not button or S.data(button).skinned then return end

    if button.style then
        button.style:SetAlpha(0)

    end
    if button.NormalTexture then button.NormalTexture:SetAlpha(0) end

    local icon = button.icon or button.Icon
    if icon then
        if button.IconMask and icon.RemoveMaskTexture then
            icon:RemoveMaskTexture(button.IconMask)
        end
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetDrawLayer("ARTWORK", -1)

        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    end

    S.Backdrop(button)
    S.Hover(button)
    S.Pressed(button)

    local hotkey = button.HotKey
    if hotkey then
        S.SetFont(hotkey, 15, "OUTLINE")
        local function pin()
            if S.data(hotkey).pinning then return end
            S.data(hotkey).pinning = true
            hotkey:ClearAllPoints()
            hotkey:SetPoint("TOPRIGHT", icon or button, "TOPRIGHT", 0, -2)
            S.data(hotkey).pinning = nil
        end
        pin()
        hooksecurefunc(hotkey, "SetPoint", function(_, point, _, _, x, y)
            if point == "TOPRIGHT" and x == 0 and y == -2 then return end
            pin()
        end)
    end
    if button.Count then S.SetFont(button.Count, 15, "OUTLINE") end

    if button.cooldown and icon then button.cooldown:SetAllPoints(icon) end
    if button.Cooldown and icon then button.Cooldown:SetAllPoints(icon) end

    S.data(button).skinned = true
end

-- The vehicle exit button. Same family as the buttons above, but it carries no
-- .icon: the art IS its normal texture, so it needs its own pass. The crop
-- trims the ring on top of the 0.140625..0.859375 Blizzard applies in XML.
--
-- Styling only. The button inherits EditModeVehicleLeaveButtonSystemTemplate,
-- so where it sits and when it shows stay with their owners.
local VEHICLE_CROP = { 0.220625, 0.799375, 0.220625, 0.779375 }

local function SkinVehicleLeaveButton()
    local button = _G.MainMenuBarVehicleLeaveButton
    if not button or S.data(button).skinned then return end
    S.data(button).skinned = true

    local normal = button.GetNormalTexture and button:GetNormalTexture()
    if normal then
        normal:SetTexCoord(VEHICLE_CROP[1], VEHICLE_CROP[2], VEHICLE_CROP[3], VEHICLE_CROP[4])
        normal:ClearAllPoints()
        normal:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
        normal:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    end

    -- Blizzard's square ADD highlight would sit on top of our hover wash and
    -- read as a second, brighter frame.
    if button.Highlight then button.Highlight:SetAlpha(0) end

    local bd = S.Backdrop(button)
    S.Hover(button, bd)
    S.Pressed(button)
end

local function SkinZoneButtons()
    local zone = _G.ZoneAbilityFrame
    if not zone then return end
    if zone.Style then zone.Style:SetAlpha(0) end
    if zone.SpellButtonContainer and zone.SpellButtonContainer.EnumerateActive then
        for spellButton in zone.SpellButtonContainer:EnumerateActive() do
            SkinExtraButton(spellButton)
        end
    end
end

local function Skin()
    SkinVehicleLeaveButton()

    if _G.ExtraActionButton1 then SkinExtraButton(_G.ExtraActionButton1) end

    local bar = _G.ExtraActionBarFrame
    if bar and not S.data(bar).hooked then
        bar:HookScript("OnShow", function()
            if _G.ExtraActionButton1 then
                SkinExtraButton(_G.ExtraActionButton1)
                local b = _G.ExtraActionButton1
                if b.style then b.style:SetAlpha(0) end
            end
        end)
        S.data(bar).hooked = true
    end

    local zone = _G.ZoneAbilityFrame
    if zone and not S.data(zone).hooked then
        SkinZoneButtons()
        if zone.UpdateDisplayedZoneAbilities then
            hooksecurefunc(zone, "UpdateDisplayedZoneAbilities", SkinZoneButtons)
        else
            zone:HookScript("OnShow", SkinZoneButtons)
        end
        S.data(zone).hooked = true
    end
end

S:RegisterEarly(Skin, "ExtraButtons")
