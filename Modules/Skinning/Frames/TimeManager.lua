local KE = select(2, ...)
local S = KE.Skins
local _G = _G

local function Skin()
    local tmf = _G.TimeManagerFrame
    if tmf then S.Frame(tmf) end

    local alarm = _G.TimeManagerAlarmTimeFrame
    if alarm then
        if alarm.HourDropdown then pcall(S.DropDown, alarm.HourDropdown) end
        if alarm.MinuteDropdown then pcall(S.DropDown, alarm.MinuteDropdown) end
        if alarm.AMPMDropdown then pcall(S.DropDown, alarm.AMPMDropdown) end
    end

    if _G.TimeManagerAlarmMessageEditBox then S.EditBox(_G.TimeManagerAlarmMessageEditBox) end
    S.CheckBox(_G.TimeManagerAlarmEnabledButton)
    S.CheckBox(_G.TimeManagerMilitaryTimeCheck)
    S.CheckBox(_G.TimeManagerLocalTimeCheck)

    local swCheck = _G.TimeManagerStopwatchCheck
    if _G.TimeManagerStopwatchFrame then S.StripTextures(_G.TimeManagerStopwatchFrame) end
    if swCheck then
        S.Template(swCheck, "Default")
        local nt = swCheck:GetNormalTexture()
        if nt then
            nt:SetTexCoord(0, 1, 0, 1)
            nt:ClearAllPoints()
            nt:SetPoint("TOPLEFT", swCheck, "TOPLEFT", 1, -1)
            nt:SetPoint("BOTTOMRIGHT", swCheck, "BOTTOMRIGHT", -1, 1)
        end
        local hover = swCheck:CreateTexture()
        hover:SetColorTexture(1, 1, 1, 0.3)
        hover:SetPoint("TOPLEFT", swCheck, "TOPLEFT", 2, -2)
        hover:SetPoint("BOTTOMRIGHT", swCheck, "BOTTOMRIGHT", -2, 2)
        swCheck:SetHighlightTexture(hover)
    end

    local sw = _G.StopwatchFrame
    if sw then
        S.StripTextures(sw)
        local bd = S.Backdrop(sw)
        if bd then
            bd:ClearAllPoints()
            bd:SetPoint("TOPLEFT", sw, "TOPLEFT", 0, -17)
            bd:SetPoint("BOTTOMRIGHT", sw, "BOTTOMRIGHT", 0, 2)
        end
        if _G.StopwatchTabFrame then S.StripTextures(_G.StopwatchTabFrame) end
        S.CloseButton(_G.StopwatchCloseButton)

        local play = _G.StopwatchPlayPauseButton
        local reset = _G.StopwatchResetButton
        if play then
            S.Template(play, "Default")
            play:SetSize(12, 12)
            if reset then
                play:ClearAllPoints()
                play:SetPoint("RIGHT", reset, "LEFT", -4, 0)
            end
        end
        if reset then
            S.Button(reset)
            reset:SetSize(16, 16)
            reset:ClearAllPoints()
            reset:SetPoint("BOTTOMRIGHT", sw, "BOTTOMRIGHT", -4, 6)
        end

    end
end

S:Register("Blizzard_TimeManager", Skin, "TimeManager")
