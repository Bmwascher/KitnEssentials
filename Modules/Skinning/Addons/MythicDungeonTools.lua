local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local ipairs = ipairs
local hooksecurefunc = hooksecurefunc
local C_Timer = C_Timer
local WHITE = "Interface\\Buttons\\WHITE8x8"
local ARROW_TEX = "Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\collapse.png"
local BUTTON_SIZE = 40
-- MDT creates its window in a build coroutine on its first open and offers no
-- callback for it; the skin only has to catch the window once. Another addon
-- can load the window addon long before any open, so the look slows after its
-- first ten seconds instead of running fast all session.
local FAST_LOOK_INTERVAL = 0.25
local FAST_LOOKS = 40
local SLOW_LOOK_INTERVAL = 1

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

local function InsetRegion(region, button)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    region:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
end

local function ReskinDungeonButton(button, idx, main)
    S.Backdrop(button)
    if button.texture then
        button.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        InsetRegion(button.texture, button)
    end
    if button.highlightTexture then
        button.highlightTexture:SetTexture(WHITE)
        button.highlightTexture:SetVertexColor(S.palette.hover[1], S.palette.hover[2], S.palette.hover[3], S.palette.hover[4])
        InsetRegion(button.highlightTexture, button)
    end
    if button.selectedTexture then
        button.selectedTexture:SetTexture(WHITE)
        S.PaintBrand(button.selectedTexture, "SetVertexColor", S.palette.selectedA)
        InsetRegion(button.selectedTexture, button)
    end
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", main, "TOPLEFT", (idx - 1) * (BUTTON_SIZE + 1) + 2, -2)
end

-- MDT keeps its dungeon list private and creates these buttons in order, so
-- the walk stops at the first missing name.
local function ReskinDungeonButtons(main)
    local idx = 1
    local button = _G["MDTDungeonButton" .. idx]
    while button do
        if not S.data(button).skinned then
            S.data(button).skinned = true
            ReskinDungeonButton(button, idx, main)
        end
        idx = idx + 1
        button = _G["MDTDungeonButton" .. idx]
    end
end

local function ReskinProgressBar(progressBar)
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

local function BumpButtonFont()
    local mf = _G.MDTButtonFont
    if mf and mf.GetFont and not S.data(mf).aeBumped then
        S.data(mf).aeBumped = true
        local face, _, flags = mf:GetFont()
        if face then mf:SetFont(face, 12, flags or "") end
    end
end

local function InsetSideButtons(main)
    for _, key in ipairs(SIDE_BUTTONS) do
        local w = main[key]
        local btn = w and w.frame
        local bd = btn and S.GetBackdrop(btn)
        if bd then
            bd:ClearAllPoints()
            bd:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
            bd:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
        end
    end
end

local function RestyleToggle(tog, toolbar)
    local tex = tog.GetNormalTexture and tog:GetNormalTexture()
    if not tex then return end
    tex:SetTexture(ARROW_TEX)
    tex:SetTexCoord(0, 1, 0, 1)
    tex:ClearAllPoints()
    tex:SetPoint("CENTER")

    tex:SetSize(16, 16)
    tex:SetVertexColor(1, 1, 1)

    tex:SetRotation(toolbar:IsShown() and 1.5708 or -1.5708)
end

local function SkinToolbarToggle(main)
    local toolbar = main.toolbar
    local tog = toolbar and toolbar.toggleButton
    if not tog or S.data(tog).skinned then return end
    S.data(tog).skinned = true
    RestyleToggle(tog, toolbar)
    tog:HookScript("OnClick", function() RestyleToggle(tog, toolbar) end)
end

-- MDT creates and updates the dungeon buttons in an update that ends with this
-- list call, and on the first open that update can finish after the window
-- shows.
local function HookDungeonButtons(main)
    local group = main.sublevelSelectionGroup
    local dropdown = group and group.sublevelDropdown
    if not (dropdown and dropdown.SetList) then return end
    hooksecurefunc(dropdown, "SetList", function() ReskinDungeonButtons(main) end)
end

local function SkinOnce(main)
    if main.closeButton then S.CloseButton(main.closeButton) end
    S.MaxMinFrame(main.maximizeButton)
    BumpButtonFont()
    InsetSideButtons(main)
    ReskinTooltip(_G.MDTModelTooltip)
    ReskinTooltip(_G.MDTPullTooltip)
    SkinToolbarToggle(main)
    ReskinProgressBar(main.sidePanel and main.sidePanel.ProgressBar)
    HookDungeonButtons(main)
end

-- MDT shows the window only once it is fully built, so every other part exists
-- by the first OnShow. The per-show walk covers dungeon buttons built before
-- the list hook went in.
local function Pass(main)
    local d = S.data(main)
    if not d.keSkinned then
        d.keSkinned = true
        SkinOnce(main)
    end
    ReskinDungeonButtons(main)
end

local attached = false
local looker
local looks = 0

local function Attach()
    if attached then return true end
    local main = _G.MDTFrame
    if not (main and main.HookScript) then return false end
    attached = true
    main:HookScript("OnShow", Pass)
    if main:IsShown() then Pass(main) end
    return true
end

local function Look()
    if Attach() then
        if looker then
            looker:Cancel()
            looker = nil
        end
        return
    end
    looks = looks + 1
    if looks == FAST_LOOKS and looker then
        looker:Cancel()
        looker = C_Timer.NewTicker(SLOW_LOOK_INTERVAL, Look)
    end
end

local function Skin()
    if Attach() or looker or not C_Timer then return end
    looker = C_Timer.NewTicker(FAST_LOOK_INTERVAL, Look)
end

S:Register("MythicDungeonTools_UI", Skin, "MythicDungeonTools")
