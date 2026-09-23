local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local pairs = pairs

local function OpenSack()
    local f = _G.BugSackFrame
    if not f or S.data(f).skinned then return end
    S.data(f).skinned = true
    S.StripTextures(f)
    S.Backdrop(f)

    for _, child in pairs({ f:GetChildren() }) do
        local n = child.GetNumRegions and child:GetNumRegions()
        if n == 1 then
            local text = child:GetRegions()
            if text and text.GetObjectType and text:GetObjectType() == "FontString" then
                S.SetFont(text)
            end
        elseif n == 4 then
            S.CloseButton(child)
        end
    end

    local sb = _G.BugSackScrollScrollBar
        or (_G.BugSackScroll and (_G.BugSackScroll.ScrollBar or _G.BugSackScroll.scrollBar))
    if sb then
        if sb.Back or sb.Forward then S.TrimScrollBar(sb) else S.ScrollBar(sb) end
    end
    if _G.BugSackScrollText then
        for _, region in pairs({ _G.BugSackScrollText:GetRegions() }) do
            if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                S.SetFont(region, 13, "")
            end
        end
    end

    local nextB, prevB, sendB = _G.BugSackNextButton, _G.BugSackPrevButton, _G.BugSackSendButton
    if nextB and prevB and sendB then
        local w = sendB:GetWidth()
        sendB:SetSize(w - 8, 32)
        nextB:SetHeight(32); prevB:SetHeight(32)
        sendB:ClearAllPoints()
        sendB:SetPoint("LEFT", prevB, "RIGHT", 4, 0)
        sendB:SetPoint("RIGHT", nextB, "LEFT", -4, 0)
        S.Button(nextB); S.Button(prevB); S.Button(sendB)
    end

    local tabs = { _G.BugSackTabAll, _G.BugSackTabSession, _G.BugSackTabLast }
    for i = 1, 3 do
        if tabs[i] then S.Tab(tabs[i]) end
    end

    for i = 1, 3 do
        if tabs[i] then S.TabSetSelected(tabs[i]) end
    end
    -- The row hangs from the window's bottom edge by the first tab's top,
    -- whatever anchor the tab was created with; only its x inset is kept.
    local function RepositionTabs()
        local prev
        for i = 1, 3 do
            local tab = tabs[i]
            if tab and tab:IsShown() then
                if not prev then
                    local _, _, _, x = tab:GetPoint(1)
                    tab:ClearAllPoints()
                    tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", x or 0, 1)
                else
                    tab:ClearAllPoints()
                    tab:SetPoint("LEFT", prev, "RIGHT", -3, 0)
                end
                prev = tab
            end
        end
    end
    RepositionTabs()

    for i = 1, 3 do
        local tab = tabs[i]
        if tab and tab.HookScript then
            tab:HookScript("OnClick", RepositionTabs)
        end
    end
end

local function Skin()
    if not _G.BugSack then return end
    if _G.BugSack.OpenSack then hooksecurefunc(_G.BugSack, "OpenSack", OpenSack) end

    local sp = _G.SettingsPanel
    local box = sp and sp.Container and sp.Container.SettingsList and sp.Container.SettingsList.ScrollBox
    if box and box.Update then
        hooksecurefunc(box, "Update", function(scrollBox)
            scrollBox:ForEachFrame(function(frame)
                if frame.soundDropdown and frame.soundDropdown.intrinsic == "DropdownButton" then
                    S.DropDown(frame.soundDropdown)
                end
            end)
        end)
    end
end

S:Register("BugSack", Skin, "BugSack")
