local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local next = next
local hooksecurefunc = hooksecurefunc

local SCROLL_CONTAINERS = {
    { "CalendarViewEventInviteList" },
    { "CalendarCreateEventInviteList" },
    { "CalendarViewEventDescriptionContainer", "CalendarViewEventDescriptionScrollFrame" },
    { "CalendarCreateEventDescriptionContainer", "CalendarCreateEventDescriptionScrollFrame" },
}

local function SkinScrollPane(frame, container)
    if not frame then return end
    if frame.NineSlice then S.StripTextures(frame.NineSlice) frame.NineSlice:SetAlpha(0) end
    local child = container or frame.scrollFrame
    if child then S.Backdrop(child) end
end

local EVENT_HEADERS = {
    { "CalendarViewEventTitle", "CalendarViewEventIcon" },
    { "CalendarCreateEventDateLabel", "CalendarCreateEventIcon" },
}

local function DressEventIcon(icon)
    if not icon or S.data(icon).skinned then return end
    icon:SetSize(54, 54)
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", _G.CalendarViewEventFrame.HeaderFrame, "TOPLEFT", 15, -20)
    S.Icon(icon, true)
    S.data(icon).skinned = true
end

local function Skin()
    local cal = _G.CalendarFrame
    if not cal then return end
    cal:DisableDrawLayer("BORDER")
    S.Backdrop(cal)

    if cal.FilterButton then S.Button(cal.FilterButton) end
    if _G.CalendarCloseButton then
        S.CloseButton(_G.CalendarCloseButton)
        _G.CalendarCloseButton:SetPoint("TOPRIGHT", cal, "TOPRIGHT", -4, -4)
    end

    for i = 1, 7 do
        local bg = _G["CalendarWeekday" .. i .. "Background"]
        if bg then bg:SetAlpha(0) end
    end

    -- Invite lists hold their own scrollFrame; description panes keep theirs
    -- in a sibling, so those name it explicitly.
    for _, pair in next, SCROLL_CONTAINERS do
        SkinScrollPane(_G[pair[1]], pair[2] and _G[pair[2]])
    end

    for _, name in next, {
        "CalendarCreateEventFrameButtonBackground", "CalendarCreateEventMassInviteButtonBorder",
        "CalendarCreateEventCreateButtonBorder", "CalendarEventPickerFrameButtonBackground",
        "CalendarEventPickerCloseButtonBorder", "CalendarCreateEventRaidInviteButtonBorder",
        "CalendarTexturePickerFrameButtonBackground", "CalendarTexturePickerAcceptButtonBorder",
        "CalendarTexturePickerCancelButtonBorder", "CalendarClassTotalsButtonBackgroundTop",
        "CalendarClassTotalsButtonBackgroundMiddle", "CalendarClassTotalsButtonBackgroundBottom",
        "CalendarViewEventDivider", "CalendarCreateEventDivider",
    } do
        if _G[name] then _G[name]:Hide() end
    end
    if _G.CalendarMonthBackground then _G.CalendarMonthBackground:SetAlpha(0) end
    if _G.CalendarYearBackground then _G.CalendarYearBackground:SetAlpha(0) end
    if _G.CalendarFrameModalOverlay then _G.CalendarFrameModalOverlay:SetAlpha(0.25) end

    if _G.CalendarPrevMonthButton then S.ArrowButton(_G.CalendarPrevMonthButton, "left") end
    if _G.CalendarNextMonthButton then S.ArrowButton(_G.CalendarNextMonthButton, "right") end

    for i = 1, 42 do
        local bu = _G["CalendarDayButton" .. i]
        if bu and not S.data(bu).skinned then

            S.Backdrop(bu, nil, true)
            S.data(bu).skinned = true
        end
    end

    if _G.CalendarWeekdaySelectedTexture then
        _G.CalendarWeekdaySelectedTexture:SetDesaturated(true)
        _G.CalendarWeekdaySelectedTexture:SetVertexColor(1, 1, 1, 0.6)
    end
    if _G.CalendarTodayTexture then _G.CalendarTodayTexture:Hide() end
    if _G.CalendarTodayTextureGlow then _G.CalendarTodayTextureGlow:Hide() end
    if _G.CalendarTodayFrame then
        S.Backdrop(_G.CalendarTodayFrame)
        local tbd = S.GetBackdrop(_G.CalendarTodayFrame)
        if tbd then
            local c = _G.NORMAL_FONT_COLOR
            if c then tbd:SetBackdropBorderColor(c.r, c.g, c.b) end
            if tbd.SetBackdropColor then tbd:SetBackdropColor(0, 0, 0, 0) end
        end
        _G.CalendarTodayFrame:SetScript("OnUpdate", nil)
        if _G.CalendarFrame_SetToday then
            hooksecurefunc("CalendarFrame_SetToday", function()
                _G.CalendarTodayFrame:SetAllPoints()
            end)
        end
    end

    local create = _G.CalendarCreateEventFrame
    if create then
        S.StripTextures(create)
        S.Backdrop(create)
        create:SetPoint("TOPLEFT", cal, "TOPRIGHT", 3, -24)
        if create.Header then S.StripTextures(create.Header) end
        if _G.CalendarCreateEventInviteList and _G.CalendarCreateEventInviteList.ScrollBar then
            S.TrimScrollBar(_G.CalendarCreateEventInviteList.ScrollBar)
        end
        for _, name in next, { "CalendarCreateEventCreateButton", "CalendarCreateEventMassInviteButton",
            "CalendarCreateEventInviteButton", "CalendarCreateEventRaidInviteButton" } do
            if _G[name] then S.Button(_G[name]) end
        end
        if _G.CalendarCreateEventInviteButton and _G.CalendarCreateEventInviteEdit then
            _G.CalendarCreateEventInviteButton:SetPoint("TOPLEFT", _G.CalendarCreateEventInviteEdit, "TOPRIGHT", 4, 1)
            _G.CalendarCreateEventInviteEdit:SetWidth(_G.CalendarCreateEventInviteEdit:GetWidth() - 2)
        end
        if _G.CalendarCreateEventInviteEdit then S.EditBox(_G.CalendarCreateEventInviteEdit) end
        if _G.CalendarCreateEventTitleEdit then S.EditBox(_G.CalendarCreateEventTitleEdit) end
        for name, width in next, { EventTypeDropdown = 120, HourDropdown = 52,
            MinuteDropdown = 52, AMPMDropdown = 57, DifficultyOptionDropdown = 80 } do
            local dd = create[name]
            if dd then
                S.DropDown(dd, true)
                dd:SetWidth(width)
            end
        end
        if create.DifficultyOptionDropdown then
            create.DifficultyOptionDropdown:ClearAllPoints()
            create.DifficultyOptionDropdown:SetPoint("TOPLEFT", create, "TOPLEFT", 220, -114)
        end
        if _G.CalendarCreateEventCloseButton then S.CloseButton(_G.CalendarCreateEventCloseButton) end
        if _G.CalendarCreateEventLockEventCheck then S.CheckBox(_G.CalendarCreateEventLockEventCheck) end
    end

    -- Both event panes put a label to the right of the icon; only the field
    -- names differ between the view and create versions.
    for _, pair in next, EVENT_HEADERS do
        local label, icon = _G[pair[1]], _G[pair[2]]
        if label and icon then
            label:ClearAllPoints()
            label:SetPoint("TOPLEFT", icon, "TOPRIGHT", 5, 0)
            DressEventIcon(icon)
        end
    end

    if _G.CalendarClassButton1 and _G.CalendarClassButtonContainer then
        _G.CalendarClassButton1:SetPoint("TOPLEFT", _G.CalendarClassButtonContainer, "TOPLEFT", 3, 0)
    end
    local lastClassButton
    for i, class in next, (_G.CLASS_SORT_ORDER or {}) do
        local button = _G["CalendarClassButton" .. i]
        local count = _G["CalendarClassButton" .. i .. "Count"]
        if button then
            local normal = button:GetNormalTexture()
            local coords = _G.CLASS_ICON_TCOORDS and _G.CLASS_ICON_TCOORDS[class]
            if normal and coords then
                normal:SetTexCoord(coords[1] + 0.015, coords[2] - 0.02, coords[3] + 0.018, coords[4] - 0.02)
            end
            local r1 = button:GetRegions()
            if r1 and r1 ~= normal and r1.Hide then r1:Hide() end
            S.Backdrop(button)
            button:SetSize(28, 28)
            if count then
                S.SetFont(count)
                count:ClearAllPoints()
                count:SetPoint("BOTTOMRIGHT", 0, 1)
            end
            if lastClassButton then
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", lastClassButton, "BOTTOMLEFT", 0, -8)
            end
            lastClassButton = button
        end
    end
    if _G.CalendarClassTotalsButton then
        S.StripTextures(_G.CalendarClassTotalsButton)
        S.Backdrop(_G.CalendarClassTotalsButton)
        _G.CalendarClassTotalsButton:SetSize(28, 18)
    end

    local function SidePanel(frame, anchorToCal)
        if not frame then return end
        S.StripTextures(frame, true)
        S.Backdrop(frame)
        if frame.Header then S.StripTextures(frame.Header) end
        if anchorToCal then
            frame:SetPoint("TOPLEFT", cal, "TOPRIGHT", 3, -24)
        end
    end
    SidePanel(_G.CalendarViewRaidFrame, true)
    if _G.CalendarViewRaidCloseButton then S.CloseButton(_G.CalendarViewRaidCloseButton) end
    SidePanel(_G.CalendarViewHolidayFrame, true)
    if _G.CalendarViewHolidayFrameModalOverlay then _G.CalendarViewHolidayFrameModalOverlay:SetAlpha(0) end
    if _G.CalendarViewHolidayCloseButton then S.CloseButton(_G.CalendarViewHolidayCloseButton) end
    SidePanel(_G.CalendarViewEventFrame, true)
    if _G.CalendarViewEventInviteListSection then S.StripTextures(_G.CalendarViewEventInviteListSection) end
    if _G.CalendarViewEventCloseButton then S.CloseButton(_G.CalendarViewEventCloseButton) end
    for _, name in next, { "CalendarViewEventAcceptButton", "CalendarViewEventTentativeButton",
        "CalendarViewEventRemoveButton", "CalendarViewEventDeclineButton" } do
        if _G[name] then S.Button(_G[name]) end
    end

    SidePanel(_G.CalendarTexturePickerFrame)
    if _G.CalendarTexturePickerFrame and _G.CalendarTexturePickerFrame.ScrollBar then
        S.TrimScrollBar(_G.CalendarTexturePickerFrame.ScrollBar)
    end
    for _, name in next, { "CalendarTexturePickerAcceptButton", "CalendarTexturePickerCancelButton" } do
        if _G[name] then S.Button(_G[name]) end
    end

    SidePanel(_G.CalendarMassInviteFrame)
    if _G.CalendarMassInviteFrame then
        if _G.CalendarMassInviteFrame.CommunityDropdown then
            S.DropDown(_G.CalendarMassInviteFrame.CommunityDropdown, true)
            _G.CalendarMassInviteFrame.CommunityDropdown:SetWidth(200)
        end
        if _G.CalendarMassInviteFrame.RankDropdown then
            S.DropDown(_G.CalendarMassInviteFrame.RankDropdown, true)
            _G.CalendarMassInviteFrame.RankDropdown:SetWidth(140)
        end
    end
    if _G.CalendarMassInviteMinLevelEdit then S.EditBox(_G.CalendarMassInviteMinLevelEdit) end
    if _G.CalendarMassInviteMaxLevelEdit then S.EditBox(_G.CalendarMassInviteMaxLevelEdit) end
    if _G.CalendarMassInviteCloseButton then S.CloseButton(_G.CalendarMassInviteCloseButton) end
    if _G.CalendarMassInviteAcceptButton then S.Button(_G.CalendarMassInviteAcceptButton) end

    SidePanel(_G.CalendarEventPickerFrame)
    if _G.CalendarEventPickerFrame and _G.CalendarEventPickerFrame.ScrollBar then
        S.TrimScrollBar(_G.CalendarEventPickerFrame.ScrollBar)
    end
    if _G.CalendarEventPickerCloseButton then S.Button(_G.CalendarEventPickerCloseButton) end
end

S:Register("Blizzard_Calendar", Skin, "Calendar")
