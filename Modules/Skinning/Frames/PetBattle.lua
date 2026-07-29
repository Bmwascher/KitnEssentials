local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local pairs = pairs
local CreateFrame = CreateFrame
local hooksecurefunc = hooksecurefunc

local ICON_CROP = { 0.08, 0.92, 0.08, 0.92 }

-- Blizzard art we blank rather than restyle, named per frame type.
local INFO_BAR_BLANK    = { "PetType", "LevelUnderlay" }
local SPEED_BLANK       = { "SpeedIcon", "SpeedUnderlay" }
local EXTRA_BAR_BLANK   = { "BorderAlive", "HealthBarBG", "HealthDivider" }
local WEATHER_HIDDEN    = { "Icon", "Name", "DurationShadow", "Label" }
local TRAILING_BUTTONS  = { "SwitchPetButton", "CatchButton", "ForfeitButton" }
local ACTIVE_BAR_BLANK  = { "Border", "Border2" }

-- Health fill reads green while the pet is up and red once it is dead.
local HEALTH_ALIVE = { 0.67, 0.84, 0.45 }
local HEALTH_DEAD  = { 0.77, 0.12, 0.24 }

-- The two bar sizes: the active pet's, and the reserve pets' mini bars.
local ACTIVE_BAR_WIDTH  = 300
local RESERVE_BAR_WIDTH = 40

-- Blizzard's stat-icon sheet supplies the first-attack arrow; the dead border
-- is a plain file with no atlas behind it.
local STAT_ICONS  = [[Interface\PetBattles\PetBattle-StatIcons]]
local DEAD_BORDER = 629739

-- The bar hosts the reparented ability buttons, so it sits under them while
-- still taking the mouse itself.
local BAR_LEVEL    = 2
local BUTTON_LEVEL = 4
local PET_SELECT_BLANK  = {
    "HealthBarBG", "HealthDivider", "ActualHealthBar", "SelectedTexture",
    "MouseoverHighlight", "Framing", "Icon", "Name", "DeadOverlay",
    "Level", "HealthText",
}

local function KillFrame(obj)
    if not obj then return end
    if obj.UnregisterAllEvents then obj:UnregisterAllEvents() end
    if obj.Hide then obj:Hide() end

    if obj.SetAlpha then obj:SetAlpha(0) end
    if obj.Show then hooksecurefunc(obj, "Show", function(o) o:Hide() end) end
end

local function SkinPetButton(frame, bf, bar) -- luacheck: ignore 212/bar
    if not frame then return end
    local d = S.data(frame)
    if not d.pbBackdrop then
        d.pbBackdrop = S.Backdrop(frame)
        if d.pbBackdrop then d.pbBackdrop:SetFrameStrata("LOW") end
    end
    local bd = d.pbBackdrop
    frame:SetNormalTexture(0)
    if frame.Icon then
        frame.Icon:SetTexCoord(ICON_CROP[1], ICON_CROP[2], ICON_CROP[3], ICON_CROP[4])
        if bd then
            frame.Icon:SetParent(bd)
            frame.Icon:SetDrawLayer("BORDER")
        end
    end
    S.Hover(frame)
    if frame.SelectedHighlight then frame.SelectedHighlight:SetAlpha(0) end
    if frame.pushed and bd then
        frame.pushed:ClearAllPoints()
        frame.pushed:SetPoint("TOPLEFT", bd, "TOPLEFT", 1, -1)
        frame.pushed:SetPoint("BOTTOMRIGHT", bd, "BOTTOMRIGHT", -1, 1)
    end
    if frame.hover and bd then
        frame.hover:ClearAllPoints()
        frame.hover:SetPoint("TOPLEFT", bd, "TOPLEFT", 1, -1)
        frame.hover:SetPoint("BOTTOMRIGHT", bd, "BOTTOMRIGHT", -1, 1)
    end
    frame:SetFrameStrata("LOW")

    if bf and frame == bf.SwitchPetButton then
        local spbc = frame:GetCheckedTexture()
        if spbc and bd then
            spbc:SetColorTexture(1, 1, 1, 0.3)
            spbc:ClearAllPoints()
            spbc:SetPoint("TOPLEFT", bd, "TOPLEFT", 1, -1)
            spbc:SetPoint("BOTTOMRIGHT", bd, "BOTTOMRIGHT", -1, 1)
        end
    end
end

local function Skin()
    local f = _G.PetBattleFrame
    if not f then return end
    local bf = f.BottomFrame
    local infoBars = { f.ActiveAlly, f.ActiveEnemy }
    local barTex = "Interface\\AddOns\\KitnEssentials\\Media\\Statusbars\\KitnEssentials"

    if _G.FloatingBattlePetTooltip then S.CloseButton(_G.FloatingBattlePetTooltip.CloseButton) end

    S.StripTextures(f)

    for index, infoBar in pairs(infoBars) do
        S.Vanish(infoBar, ACTIVE_BAR_BLANK)
        infoBar.healthBarWidth = ACTIVE_BAR_WIDTH

        local iconBD = S.Backdrop(infoBar.Icon)
        KillFrame(infoBar.BorderFlash)
        KillFrame(infoBar.HealthBarBG)
        KillFrame(infoBar.HealthBarFrame)

        infoBar.ActualHealthBar:SetTexCoord(0, 1, 0, 1)
        infoBar.ActualHealthBar:SetTexture(barTex)
        local hbBD = S.Backdrop(infoBar.ActualHealthBar)
        infoBar.ActualHealthBar:ClearAllPoints()
        if hbBD then hbBD:ClearAllPoints() end

        infoBar.PetTypeFrame = CreateFrame("Frame", nil, infoBar)
        infoBar.PetTypeFrame:SetSize(100, 23)
        infoBar.PetTypeFrame.text = infoBar.PetTypeFrame:CreateFontString(nil, "OVERLAY")
        S.SetFont(infoBar.PetTypeFrame.text, 12, "OUTLINE")
        infoBar.PetTypeFrame.text:SetText("")

        infoBar.Name:ClearAllPoints()
        infoBar.FirstAttack = infoBar:CreateTexture(nil, "ARTWORK")
        infoBar.FirstAttack:SetSize(30, 30)
        infoBar.FirstAttack:SetTexture(STAT_ICONS)

        if index == 1 then
            f.Ally2.iconPoint = iconBD or infoBar.Icon
            f.Ally3.iconPoint = iconBD or infoBar.Icon

            infoBar.ActualHealthBar:SetVertexColor(HEALTH_ALIVE[1], HEALTH_ALIVE[2], HEALTH_ALIVE[3])
            infoBar.ActualHealthBar:SetPoint("BOTTOMLEFT", infoBar.Icon, "BOTTOMRIGHT", 10, 0)
            if hbBD then
                hbBD:SetPoint("TOPLEFT", infoBar.ActualHealthBar, "TOPLEFT", -1, 1)
                hbBD:SetPoint("BOTTOMLEFT", infoBar.ActualHealthBar, "BOTTOMLEFT", -1, -1)
                hbBD:SetPoint("RIGHT", infoBar.ActualHealthBar, "LEFT", infoBar.healthBarWidth + 1, 0)
            end

            infoBar.Name:SetPoint("BOTTOMLEFT", infoBar.ActualHealthBar, "TOPLEFT", 0, 10)
            infoBar.PetTypeFrame:SetPoint("BOTTOMRIGHT", hbBD or infoBar.ActualHealthBar, "TOPRIGHT", 0, 4)
            infoBar.PetTypeFrame.text:SetPoint("RIGHT")

            infoBar.FirstAttack:SetPoint("LEFT", hbBD or infoBar.ActualHealthBar, "RIGHT", 5, 0)
            infoBar.FirstAttack:SetTexCoord(infoBar.SpeedIcon:GetTexCoord())
            infoBar.FirstAttack:SetVertexColor(0.1, 0.1, 0.1, 1)
        else
            f.Enemy2.iconPoint = iconBD or infoBar.Icon
            f.Enemy3.iconPoint = iconBD or infoBar.Icon

            infoBar.ActualHealthBar:SetVertexColor(HEALTH_DEAD[1], HEALTH_DEAD[2], HEALTH_DEAD[3])
            infoBar.ActualHealthBar:SetPoint("BOTTOMRIGHT", infoBar.Icon, "BOTTOMLEFT", -10, 0)
            if hbBD then
                hbBD:SetPoint("TOPRIGHT", infoBar.ActualHealthBar, "TOPRIGHT", 1, 1)
                hbBD:SetPoint("BOTTOMRIGHT", infoBar.ActualHealthBar, "BOTTOMRIGHT", 1, -1)
                hbBD:SetPoint("LEFT", infoBar.ActualHealthBar, "RIGHT", -(infoBar.healthBarWidth + 1), 0)
            end

            infoBar.Name:SetPoint("BOTTOMRIGHT", infoBar.ActualHealthBar, "TOPRIGHT", 0, 10)
            infoBar.PetTypeFrame:SetPoint("BOTTOMLEFT", hbBD or infoBar.ActualHealthBar, "TOPLEFT", 2, 4)
            infoBar.PetTypeFrame.text:SetPoint("LEFT")

            infoBar.FirstAttack:SetPoint("RIGHT", hbBD or infoBar.ActualHealthBar, "LEFT", -5, 0)
            infoBar.FirstAttack:SetTexCoord(0.5, 0, 0.5, 1)
            infoBar.FirstAttack:SetVertexColor(0.1, 0.1, 0.1, 1)
        end

        infoBar.HealthText:ClearAllPoints()
        infoBar.HealthText:SetPoint("CENTER", hbBD or infoBar.ActualHealthBar, "CENTER")

        infoBar.PetType:ClearAllPoints()
        infoBar.PetType:SetAllPoints(infoBar.PetTypeFrame)
        infoBar.PetType:SetFrameLevel(infoBar.PetTypeFrame:GetFrameLevel() + 2)
        S.Vanish(infoBar, INFO_BAR_BLANK)

        infoBar.Level:SetFontObject("NumberFont_Outline_Huge")
        infoBar.Level:ClearAllPoints()
        infoBar.Level:SetPoint("BOTTOMLEFT", infoBar.Icon, "BOTTOMLEFT", 2, 2)

        if infoBar.SpeedIcon then
            infoBar.SpeedIcon:ClearAllPoints()
            infoBar.SpeedIcon:SetPoint("CENTER")
            S.Vanish(infoBar, SPEED_BLANK)
        end
    end

    hooksecurefunc("PetBattleFrame_UpdateSpeedIndicators", function()
        if not f.ActiveAlly.SpeedIcon:IsShown() and not f.ActiveEnemy.SpeedIcon:IsShown() then
            f.ActiveAlly.FirstAttack:Hide()
            f.ActiveEnemy.FirstAttack:Hide()
            return
        end
        for _, infoBar in pairs(infoBars) do
            infoBar.FirstAttack:Show()
            if infoBar.SpeedIcon:IsShown() then
                infoBar.FirstAttack:SetVertexColor(0, 1, 0, 1)
            else
                infoBar.FirstAttack:SetVertexColor(0.8, 0, 0.3, 1)
            end
        end
    end)

    hooksecurefunc("PetBattleUnitFrame_UpdatePetType", function(frame)
        if frame.PetType and frame.PetTypeFrame then
            local petType = C_PetBattles.GetPetType(frame.petOwner, frame.petIndex)
            if petType then
                frame.PetTypeFrame.text:SetText(_G["BATTLE_PET_NAME_" .. petType])
            end
        end
    end)

    hooksecurefunc("PetBattleAuraHolder_Update", function(holder)
        if not (holder.petOwner and holder.petIndex) then return end
        local nextFrame = 1
        for i = 1, C_PetBattles.GetNumAuras(holder.petOwner, holder.petIndex) do
            local _, _, turnsRemaining, isBuff = C_PetBattles.GetAuraInfo(holder.petOwner, holder.petIndex, i)
            if (isBuff and holder.displayBuffs) or (not isBuff and holder.displayDebuffs) then
                local frame = holder.frames[nextFrame]
                frame.DebuffBorder:Hide()
                local d = S.data(frame)
                if not d.auraBD then
                    d.auraBD = S.Backdrop(frame)
                    if d.auraBD then
                        d.auraBD:ClearAllPoints()
                        d.auraBD:SetPoint("TOPLEFT", frame.Icon, "TOPLEFT", -1, 1)
                        d.auraBD:SetPoint("BOTTOMRIGHT", frame.Icon, "BOTTOMRIGHT", 1, -1)
                    end
                    frame.Icon:SetTexCoord(ICON_CROP[1], ICON_CROP[2], ICON_CROP[3], ICON_CROP[4])
                    if d.auraBD then frame.Icon:SetParent(d.auraBD) end
                end
                if d.auraBD then
                    if isBuff then
                        d.auraBD:SetBackdropBorderColor(0, 1, 0)
                    else
                        d.auraBD:SetBackdropBorderColor(1, 0, 0)
                    end
                end
                S.SetFont(frame.Duration, 12, "OUTLINE")
                frame.Duration:ClearAllPoints()
                frame.Duration:SetPoint("TOP", frame.Icon, "BOTTOM", 1, -4)
                if turnsRemaining > 0 then
                    frame.Duration:SetText(turnsRemaining)
                end
                nextFrame = nextFrame + 1
            end
        end
    end)

    hooksecurefunc("PetBattleWeatherFrame_Update", function(frame)
        local weather = C_PetBattles.GetAuraInfo(Enum.BattlePetOwner.Weather, _G.PET_BATTLE_PAD_INDEX, 1)
        if weather then
            S.HideAll(frame, WEATHER_HIDDEN)

            frame.BackgroundArt:ClearAllPoints()
            frame.BackgroundArt:SetPoint("TOP", frame, "TOP", 0, 14)
            frame.BackgroundArt:SetSize(200, 100)
            frame.Duration:ClearAllPoints()
            frame.Duration:SetPoint("TOP", frame, "TOP", 0, 10)
            frame:ClearAllPoints()
            frame:SetPoint("TOP", _G.UIParent, 0, -15)
        end
    end)

    hooksecurefunc("PetBattleUnitFrame_UpdateDisplay", function(frame)
        if frame.Icon then
            frame.Icon:SetTexCoord(ICON_CROP[1], ICON_CROP[2], ICON_CROP[3], ICON_CROP[4])
        end
        local bd = frame.Icon and S.GetBackdrop(frame.Icon)
        if frame.petOwner and frame.petIndex and bd and bd:IsShown() then
            local quality = C_PetBattles.GetBreedQuality(frame.petOwner, frame.petIndex)
            local qc = quality and _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality]
            if qc then bd:SetBackdropBorderColor(qc.r, qc.g, qc.b) end
        end
    end)

    f.TopVersusText:ClearAllPoints()
    f.TopVersusText:SetPoint("TOP", f, "TOP", 0, -35)

    local extraInfoBars = { f.Ally2, f.Ally3, f.Enemy2, f.Enemy3 }
    for _, infoBar in pairs(extraInfoBars) do
        infoBar:SetSize(40, 40)
        S.Template(infoBar, "Default")
        infoBar:ClearAllPoints()
        infoBar.healthBarWidth = RESERVE_BAR_WIDTH

        infoBar.BorderDead:SetTexture(DEAD_BORDER)
        infoBar.BorderDead:SetTexCoord(0, 1, 0, 1)
        infoBar.BorderDead:ClearAllPoints()
        infoBar.BorderDead:SetPoint("TOPLEFT", -3, 4)
        infoBar.BorderDead:SetPoint("BOTTOMRIGHT", 3, -2)

        S.Vanish(infoBar, EXTRA_BAR_BLANK)
        infoBar.Icon:SetDrawLayer("ARTWORK")
        local iconBD = S.Backdrop(infoBar.Icon)

        infoBar.ActualHealthBar:SetTexCoord(0, 1, 0, 1)
        infoBar.ActualHealthBar:SetTexture(barTex)
        infoBar.ActualHealthBar:ClearAllPoints()
        infoBar.ActualHealthBar:SetPoint("TOPLEFT", infoBar.Icon, "BOTTOMLEFT", 0, -1)

        local hbBD = S.Backdrop(infoBar.ActualHealthBar)
        if hbBD then
            hbBD:ClearAllPoints()
            hbBD:SetPoint("TOPLEFT", iconBD or infoBar.Icon, "BOTTOMLEFT", 0, 1)
            hbBD:SetPoint("TOPRIGHT", iconBD or infoBar.Icon, "BOTTOMRIGHT", 0, 1)
            hbBD:SetPoint("BOTTOMLEFT", infoBar.ActualHealthBar, 0, -1)
        end
    end

    f.Ally2:SetPoint("TOPRIGHT", f.Ally2.iconPoint, "TOPLEFT", -6, -2)
    f.Ally3:SetPoint("TOPRIGHT", f.Ally2, "TOPLEFT", -8, 0)
    f.Enemy2:SetPoint("TOPLEFT", f.Enemy2.iconPoint, "TOPRIGHT", 6, -2)
    f.Enemy3:SetPoint("TOPLEFT", f.Enemy2, "TOPRIGHT", 8, 0)

    local bar = CreateFrame("Frame", "KE_PetBattleActionBar", f)
    bar:SetSize(52 * 6 + 7 * 10, 52 + 10 * 2)
    bar:EnableMouse(true)
    S.Template(bar, "Window")
    bar:SetPoint("BOTTOM", _G.UIParent, "BOTTOM", 0, 4)
    bar:SetFrameLevel(BAR_LEVEL)
    bar:SetFrameStrata("BACKGROUND")

    S.StripTextures(bf)
    KillFrame(bf.MicroButtonFrame)
    S.StripTextures(bf.FlowFrame)
    S.StripTextures(bf.Delimiter)

    local turnTimer = bf.TurnTimer
    S.StripTextures(turnTimer)
    turnTimer.SkipButton:SetParent(bar)
    S.Button(turnTimer.SkipButton)

    hooksecurefunc(turnTimer.SkipButton, "SetPoint", function(btn, _, _, _, _, _, forced)
        if forced == true then return end
        btn:ClearAllPoints()
        btn:SetFrameLevel(BUTTON_LEVEL)
        btn:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 1, true)
        btn:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, 1, true)
        turnTimer:SetSize(turnTimer.SkipButton:GetSize())
    end)

    turnTimer:ClearAllPoints()
    turnTimer:SetPoint("TOP", _G.UIParent, "TOP", 0, -140)
    turnTimer.TimerText:SetPoint("CENTER")

    bf.xpBar:SetParent(bar)
    S.Backdrop(bf.xpBar)
    bf.xpBar:ClearAllPoints()
    bf.xpBar:SetPoint("BOTTOMLEFT", turnTimer.SkipButton, "TOPLEFT", 1, 2)
    bf.xpBar:SetPoint("BOTTOMRIGHT", turnTimer.SkipButton, "TOPRIGHT", -1, 2)
    bf.xpBar:SetScript("OnShow", function(frame)
        S.StripTextures(frame)
        frame:SetStatusBarTexture(barTex)
    end)

    for i = 1, 3 do
        S.Vanish(bf.PetSelectionFrame["Pet" .. i], PET_SELECT_BLANK)
    end

    hooksecurefunc("PetBattlePetSelectionFrame_Show", function()
        bf.PetSelectionFrame:ClearAllPoints()
        bf.PetSelectionFrame:SetPoint("BOTTOM", bf.xpBar, "TOP", 0, 8)
    end)

    hooksecurefunc("PetBattleFrame_UpdateActionBarLayout", function()
        for i = 1, _G.NUM_BATTLE_PET_ABILITIES do
            local b = bf.abilityButtons[i]
            SkinPetButton(b, bf, bar)
            b:SetParent(bar)
            b:ClearAllPoints()
            if i == 1 then
                b:SetPoint("BOTTOMLEFT", 10, 10)
            else
                b:SetPoint("LEFT", bf.abilityButtons[i - 1], "RIGHT", 10, 0)
            end
        end
        local prev = bf.abilityButtons[3]
        for _, key in ipairs(TRAILING_BUTTONS) do
            local button = bf[key]
            -- Catch and Forfeit were reparented to the bar and SwitchPet was
            -- not. Preserved as-is: moving it would change its layering.
            if key ~= "SwitchPetButton" then button:SetParent(bar) end
            button:ClearAllPoints()
            button:SetPoint("LEFT", prev, "RIGHT", 10, 0)
            SkinPetButton(button, bf, bar)
            prev = button
        end
    end)

    local queue = _G.PetBattleQueueReadyFrame
    if queue then
        S.StripTextures(queue)
        S.Template(queue, "Window")
        if queue.Art then queue.Art:SetTexture([[Interface\PetBattles\PetBattlesQueue]]) end
        S.Button(queue.AcceptButton)
        S.Button(queue.DeclineButton)
    end
end

S:RegisterEarly(Skin, "PetBattle")
