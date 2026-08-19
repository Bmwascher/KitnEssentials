local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local pairs = pairs
local hooksecurefunc = hooksecurefunc
local WHITE = "Interface\\Buttons\\WHITE8x8"
local ARROW_TEX = "Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\collapse.tga"
-- Never hardcode the accent here: read the palette table (mutated in
-- place by S.RefreshPalette) so it tracks the live theme.
local BRAND = S.palette.brand

-- was a 0.1s poll (MDT skinned in visibly). Per-frame now.
local function WaitFor(check, run, tries)
    S.WaitFor(check, run, (tries or 20) * 30)
end

local function ReskinTooltip(tt)
    if not tt then return end
    S.StripTextures(tt); S.Backdrop(tt)
    if tt.backdrop and tt.backdrop.Hide then tt.backdrop:Hide() end
end

local function ReskinButtonTexture(texture, alpha)
    if not texture then return end
    texture:SetTexCoord(0, 1, 0, 1)
    if texture.SetInside then texture:SetInside() end
    texture:SetTexture(WHITE)
    if not S.data(texture).alphaHooked then
        S.data(texture).alphaHooked = true
        local orig = texture.SetVertexColor
        hooksecurefunc(texture, "SetVertexColor", function(self, r, g, b, a)
            if S.data(self).inHook then return end
            S.data(self).inHook = true
            orig(self, r, g, b, (a or 1) * alpha)
            S.data(self).inHook = false
        end)
        texture:SetVertexColor(texture:GetVertexColor())
    end
end

local function ReskinDungeonButtons(MDT)
    local db = MDT.GetDB and MDT:GetDB()
    local sel = db and db.selectedDungeonList
    local list = MDT.dungeonSelectionToIndex and sel and MDT.dungeonSelectionToIndex[sel]
    if not list then return end
    for idx = 1, #list do
        local button = _G["MDTDungeonButton" .. idx]
        if button and not S.data(button).skinned then
            S.data(button).skinned = true

            S.Backdrop(button)
            local function Inset(t)
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
                t:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
            end
            if button.texture then
                button.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                Inset(button.texture)
            end
            if button.highlightTexture then

                button.highlightTexture:SetTexture(WHITE)
                button.highlightTexture:SetVertexColor(S.palette.hover[1], S.palette.hover[2], S.palette.hover[3], 0.15)
                Inset(button.highlightTexture)
            end
            if button.selectedTexture then
                button.selectedTexture:SetTexture(WHITE)
                button.selectedTexture:SetVertexColor(BRAND[1], BRAND[2], BRAND[3], 0.24)
                Inset(button.selectedTexture)
            end
            local SIZE = 40
            if MDT.main_frame then
                button:ClearAllPoints()

                button:SetPoint("TOPLEFT", MDT.main_frame, "TOPLEFT", (idx - 1) * (SIZE + 1) + 2, -2)
            end
        end
    end
end

local function ReskinProgressBar(_, progressBar)
    local bar = progressBar and progressBar.Bar
    if not bar then return end

    S.StripTextures(bar)
    if not S.data(bar).aeShrunk then
        S.data(bar).aeShrunk = true
        local w, h = S.SafeSize(bar)
        if w and w > 4 then bar:SetSize(w - 2, h - 2) end
    end
    S.Backdrop(bar, -1, true)
    if bar.SetStatusBarTexture then bar:SetStatusBarTexture(WHITE) end
    if bar.Label then
        bar.Label:ClearAllPoints()
        bar.Label:SetPoint("CENTER", bar, 0, 0)

        S.SetFont(bar.Label, 12, "OUTLINE")
        bar.Label:SetShadowOffset(0, 0)
    end
end

local function ReskinMapPOI(frame)
    if not frame or S.data(frame).skinned or not frame.Texture then return end
    S.data(frame).skinned = true
    S.StripTextures(frame); S.Backdrop(frame)
    if frame.HighlightTexture then
        frame.HighlightTexture:SetTexture(WHITE)
        frame.HighlightTexture:SetVertexColor(1, 1, 1, 0.2)
    end
    if frame.Texture then frame.Texture:SetTexCoord(0, 1, 0, 1) end
end

local function SkinMDTWidget(widget)
    local t = widget and widget.type
    if t == "MDTPullButton" then
        ReskinButtonTexture(widget.frame and widget.frame.pickedGlow, 0.5)
        ReskinButtonTexture(widget.frame and widget.frame.highlight, 0.2)
        ReskinButtonTexture(widget.background, 0.3)
    elseif t == "MDTNewPullButton" then
        if widget.frame then S.StripTextures(widget.frame) end
        ReskinButtonTexture(widget.background, 0.2)
        if widget.background then widget.background:SetVertexColor(1, 1, 1, 0.4) end
        ReskinButtonTexture(widget.frame and widget.frame.highlight, 0.2)
    elseif t == "MDTSpellButton" then
        if widget.icon then S.Icon(widget.icon) end
        if widget.frame then
            if widget.frame.background then widget.frame.background:SetAlpha(0) end
            ReskinButtonTexture(widget.frame.highlight, 0.2)
            S.StripTextures(widget.frame); S.Backdrop(widget.frame)
        end
    end
end

if S.AceWidgetSkinners then
    S.AceWidgetSkinners[#S.AceWidgetSkinners + 1] = SkinMDTWidget
end

local SIDE_BUTTONS = {
    "sidePanelNewButton", "sidePanelRenameButton", "sidePanelDeleteButton",
    "sidePanelExportButton", "sidePanelImportButton",
}

local function Skin()
    local MDT = _G.MDT
    if not MDT then return end

    if MDT.Async then
        hooksecurefunc(MDT, "Async", function(_, _, name)
            if name ~= "showInterface" then return end
            WaitFor(function()
                return _G.MDTFrame and _G.MDTFrame.closeButton and true or false
            end, function()
                if _G.MDTFrame.closeButton then S.CloseButton(_G.MDTFrame.closeButton) end

                S.MaxMinFrame(_G.MDTFrame.maximizeButton)
            end, 10)

            WaitFor(function()
                return MDT.main_frame and MDT.main_frame.sidePanelNewButton and true or false
            end, function()

                local mf = _G.MDTButtonFont
                if mf and mf.GetFont and not S.data(mf).aeBumped then
                    S.data(mf).aeBumped = true
                    local face, _, flags = mf:GetFont()
                    if face then mf:SetFont(face, 12, flags or "") end
                end
                for _, key in pairs(SIDE_BUTTONS) do
                    local w = MDT.main_frame[key]
                    local btn = w and w.frame
                    local bd = btn and S.GetBackdrop(btn)
                    if bd then
                        bd:ClearAllPoints()
                        bd:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
                        bd:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
                    end
                end
            end, 20)
            WaitFor(function()
                return MDT.tooltip and MDT.pullTooltip and true or false
            end, function()
                ReskinTooltip(MDT.tooltip); ReskinTooltip(MDT.pullTooltip)
            end, 10)
        end)
    end
    if MDT.UpdateDungeonDropDown then hooksecurefunc(MDT, "UpdateDungeonDropDown", ReskinDungeonButtons) end

    if MDT.ShowEnemyInfoFrame then
        hooksecurefunc(MDT, "ShowEnemyInfoFrame", function(m)
            local f = m.enemyInfoFrame
            if not f then return end
            if S.AceSkinTabGroup then S.AceSkinTabGroup(f.tabGroup) end
            if S.AceFixPullout then S.AceFixPullout(f.enemyDropDown) end
        end)
    end

    if MDT.initToolbar then
        hooksecurefunc(MDT, "initToolbar", function(_, frame)
            local tb = frame and frame.toolbar
            local tog = tb and tb.toggleButton
            if not tog or S.data(tog).skinned then return end
            S.data(tog).skinned = true
            local function Restyle()
                local tex = tog.GetNormalTexture and tog:GetNormalTexture()
                if not tex then return end
                tex:SetTexture(ARROW_TEX)
                tex:SetTexCoord(0, 1, 0, 1)
                tex:ClearAllPoints()
                tex:SetPoint("CENTER")

                tex:SetSize(16, 16)
                tex:SetVertexColor(1, 1, 1)

                tex:SetRotation(tb:IsShown() and 1.5708 or -1.5708)
            end
            Restyle()
            tog:HookScript("OnClick", Restyle)
        end)
    end
    if MDT.SkinProgressBar then hooksecurefunc(MDT, "SkinProgressBar", ReskinProgressBar) end
    if MDT.POI_CreateFramePools then
        hooksecurefunc(MDT, "POI_CreateFramePools", function(m)
            for _, template in pairs({ "MapLinkPinTemplate", "DeathReleasePinTemplate", "VignettePinTemplate" }) do
                local pool = m.GetFramePool and m.GetFramePool(template)
                if pool and pool.Acquire then
                    hooksecurefunc(pool, "Acquire", function(p)
                        if p.active then
                            for _, frame in pairs(p.active) do
                                if frame and frame.Texture and not S.data(frame).poiHooked then
                                    S.data(frame).poiHooked = true
                                    hooksecurefunc(frame.Texture, "SetTexture", function() ReskinMapPOI(frame) end)
                                end
                            end
                        end
                    end)
                end
            end
        end)
    end
end

S:Register("MythicDungeonTools", Skin, "MythicDungeonTools")
