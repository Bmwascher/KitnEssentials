local KE = select(2, ...)
local S = KE.Skins
local _G = _G

local function strip_bd(frame, close)
    if not frame or S.data(frame).skinned then return end
    S.StripTextures(frame)
    S.Backdrop(frame)
    if close and frame.CloseButton then S.CloseButton(frame.CloseButton) end
    S.data(frame).skinned = true
end


local BTN_GAP = 1

-- Protected buttons are left alone. Exit Game calls Quit(), which is
-- protected -- a tainted click is refused and the button silently stops
-- working (field report). Everything else is skinned:
-- restyling textures does not taint a button's click handler, which is
-- why every other UI pack skins this menu without issue.
local function SkinOneGameMenuButton(button)
    if S.data(button).skinned then return end

    if button.IsProtected and button:IsProtected() then
        S.data(button).skinned = true
        return
    end

    S.Button(button)
    S.FontStrings(button, 14, "")
    local bd = S.GetBackdrop(button)
    if bd then
        local half = BTN_GAP / 2
        bd:ClearAllPoints()
        bd:SetPoint("TOPLEFT", button, "TOPLEFT", 0, -half)
        bd:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, half)
    end
end

local function SkinGameMenuButtons(menu)
    if not menu then return end
    if menu.buttonPool and menu.buttonPool.EnumerateActive then
        for button in menu.buttonPool:EnumerateActive() do
            SkinOneGameMenuButton(button)
        end
    end
    -- Third-party addons (EllesmereUI) inject menu buttons as plain
    -- CHILDREN rather than through the pool; the skinned flag dedupes.
    for _, child in ipairs({ menu:GetChildren() }) do
        if child.IsObjectType and child:IsObjectType("Button")
            and child.GetText and child:GetText() and child:GetText() ~= "" then
            SkinOneGameMenuButton(child)
        end
    end
end

local function SkinGameMenu()
    local frame = _G.GameMenuFrame
    if not frame or S.data(frame).gameMenu then return end
    S.StripTextures(frame)
    S.Backdrop(frame)

    local header = frame.Header
    if header then
        S.StripTextures(header)
        header:ClearAllPoints()
        header:SetPoint("TOP", frame, "TOP", 0, 7)
        S.FontStringsDeep(header, 14, "OUTLINE", 2)

        local b = S.palette.brand
        for _, r in ipairs({ header:GetRegions() }) do
            if r.IsObjectType and r:IsObjectType("FontString") then
                r:SetTextColor(b[1], b[2], b[3])
            end
        end
        if header.Text then header.Text:SetTextColor(b[1], b[2], b[3]) end
    end

    if frame.InitButtons then
        hooksecurefunc(frame, "InitButtons", function(menu)
            -- EllesmereUI loads after us and creates its button in its
            -- own InitButtons hook, so defer one frame to catch it.
            SkinGameMenuButtons(menu)
            C_Timer.After(0, function() SkinGameMenuButtons(menu) end)
        end)
    end
    SkinGameMenuButtons(frame)

    S.data(frame).gameMenu = true
end

local function SkinMisc()
    strip_bd(_G.GhostFrame)
    strip_bd(_G.ItemTextFrame, true)
    strip_bd(_G.AddonCompartmentFrame)
    SkinGameMenu()

    if _G.ReadyCheckFrame and not S.data(_G.ReadyCheckFrame).skinned then
        -- On Midnight all the
        -- visible art lives on the ReadyCheckListenerFrame CHILD
        -- (setAllPoints over the bare ReadyCheckFrame container): .Bg
        -- dark tile, PortraitFrameTemplate .NineSlice border, the
        -- TitleContainer, and the portrait. The old block stripped and
        -- backdropped the empty container, so everything it painted sat
        -- invisible under the listener's opaque art -- the surviving-
        -- child doctrine, one level up. Buttons stay on their native
        -- parent (the listener) so they render above our backdrop.
        local listener = _G.ReadyCheckListenerFrame
        if _G.ReadyCheckPortrait then S.KillTexture(_G.ReadyCheckPortrait) end
        if listener then
            if listener.Bg then S.KillTexture(listener.Bg) end
            if listener.NineSlice and listener.NineSlice.SetAlpha then
                listener.NineSlice:SetAlpha(0)
                if listener.NineSlice.EnableMouse then listener.NineSlice:EnableMouse(false) end
            end
            S.StripTextures(listener)
            S.Backdrop(listener)
            local tc = listener.TitleContainer
            local title = tc and tc.TitleText
            if title then S.SetFont(title, 14, "OUTLINE") end
            -- Blizzard anchors the TitleContainer
            -- asymmetrically (TOPLEFT x=58 clearing the portrait,
            -- TOPRIGHT x=-24); with the portrait killed the title reads
            -- off-center right. Re-anchor symmetric.
            if tc then
                tc:ClearAllPoints()
                tc:SetPoint("TOPLEFT", listener, "TOPLEFT", 24, -1)
                tc:SetPoint("TOPRIGHT", listener, "TOPRIGHT", -24, -1)
            end
        else
            -- pre-Midnight fallback: art on the frame itself
            S.StripTextures(_G.ReadyCheckFrame)
            S.Backdrop(_G.ReadyCheckFrame)
        end
        if _G.ReadyCheckFrameYesButton then
            S.Button(_G.ReadyCheckFrameYesButton)
            _G.ReadyCheckFrameYesButton:ClearAllPoints()
            _G.ReadyCheckFrameYesButton:SetPoint("TOPRIGHT", _G.ReadyCheckFrame, "CENTER", -3, -5)
        end
        if _G.ReadyCheckFrameNoButton then
            S.Button(_G.ReadyCheckFrameNoButton)
            _G.ReadyCheckFrameNoButton:ClearAllPoints()
            _G.ReadyCheckFrameNoButton:SetPoint("TOPLEFT", _G.ReadyCheckFrame, "CENTER", 3, -5)
        end
        if _G.ReadyCheckFrameText then
            _G.ReadyCheckFrameText:ClearAllPoints()
            _G.ReadyCheckFrameText:SetPoint("TOP", 0, -30)
            _G.ReadyCheckFrameText:SetWidth(300)
        end
        S.data(_G.ReadyCheckFrame).skinned = true
    end

    if _G.LFDRoleCheckPopup and not S.data(_G.LFDRoleCheckPopup).skinned then
        S.StripTextures(_G.LFDRoleCheckPopup)
        S.Backdrop(_G.LFDRoleCheckPopup)
        if _G.LFDRoleCheckPopupAcceptButton then S.Button(_G.LFDRoleCheckPopupAcceptButton) end
        if _G.LFDRoleCheckPopupDeclineButton then S.Button(_G.LFDRoleCheckPopupDeclineButton) end
        for _, rb in ipairs({ _G.LFDRoleCheckPopupRoleButtonTank,
            _G.LFDRoleCheckPopupRoleButtonDPS, _G.LFDRoleCheckPopupRoleButtonHealer }) do
            if rb then
                local cb = rb.checkButton or rb.CheckButton
                if cb then S.CheckBox(cb) end
                if rb.DisableDrawLayer then rb:DisableDrawLayer("OVERLAY") end
            end
        end
        S.data(_G.LFDRoleCheckPopup).skinned = true
    end

    if _G.StackSplitFrame and not S.data(_G.StackSplitFrame).skinned then
        S.StripTextures(_G.StackSplitFrame)
        S.Backdrop(_G.StackSplitFrame)
        if _G.StackSplitFrame.OkayButton then S.Button(_G.StackSplitFrame.OkayButton) end
        if _G.StackSplitFrame.CancelButton then S.Button(_G.StackSplitFrame.CancelButton) end
        S.data(_G.StackSplitFrame).skinned = true
    end

    if _G.OpacityFrame and not S.data(_G.OpacityFrame).skinned then
        S.StripTextures(_G.OpacityFrame)
        S.Backdrop(_G.OpacityFrame)
        S.data(_G.OpacityFrame).skinned = true
    end

    local sdf = _G.SideDressUpFrame
    if sdf and not S.data(sdf).skinned then
        if _G.SideDressUpFrameCloseButton then S.CloseButton(_G.SideDressUpFrameCloseButton) end
        if sdf.ResetButton then S.Button(sdf.ResetButton) end
        S.StripTextures(sdf)
        S.Backdrop(sdf)
        if sdf.BGTopLeft then sdf.BGTopLeft:Hide() end
        if sdf.BGBottomLeft then sdf.BGBottomLeft:Hide() end
        S.data(sdf).skinned = true
    end

    local acb = _G.AutoCompleteBox
    if acb and not S.data(acb).skinned then
        S.StripTextures(acb)
        S.Backdrop(acb)

        local ov = CreateFrame("Frame", nil, acb)
        ov:SetAllPoints(acb)
        ov:SetFrameStrata(acb:GetFrameStrata())

        local lvl = (acb:GetFrameLevel() or 0) + 10
        ov:SetFrameLevel(lvl)
        local obd = S.Backdrop(ov, nil, true)
        if obd then obd:SetFrameLevel(lvl) end
        ov:EnableMouse(false)
        S.data(acb).skinned = true
    end

    for i = 1, 4 do
        local popup = _G["StaticPopup" .. i]
        if popup then
            S.StaticPopup(popup)
            if not S.data(popup).showHooked then
                popup:HookScript("OnShow", S.StaticPopup)
                S.data(popup).showHooked = true
            end
        end
    end

    local splash = _G.SplashFrame
    if splash and not S.data(splash).skinned then
        if splash.TopCloseButton then S.CloseButton(splash.TopCloseButton) end
        if splash.BottomCloseButton then
            S.Button(splash.BottomCloseButton)

            local bd = S.GetBackdrop(splash.BottomCloseButton)
            if bd then bd:SetFrameLevel(splash.BottomCloseButton:GetFrameLevel()) end
        end
        S.data(splash).skinned = true
    end
end

S:RegisterEarly(SkinMisc, "Misc")
