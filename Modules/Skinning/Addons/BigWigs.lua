local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local next = next
local ipairs = ipairs
local pcall = pcall
local format = format
local hooksecurefunc = hooksecurefunc

-- The bar's PARENT is LFGDungeonReadyPopup, the outer container that holds
-- BOTH the status box and the dialog box and is resized when they swap. Anchor
-- to whichever box is actually shown instead, or the bar detaches from the
-- thing it is timing.
local queueTimer
local AnchorQueueTimer
local function HookQueueBox(box)
    if not box or S.data(box).keQueueAnchorHook then return end
    S.data(box).keQueueAnchorHook = true
    box:HookScript("OnShow", function() AnchorQueueTimer() end)
end

function AnchorQueueTimer()
    local f = queueTimer
    if not f then return end
    local status = _G.LFGDungeonReadyStatus
    local dialog = _G.LFGDungeonReadyDialog
    local target = (status and status:IsShown() and status)
        or (dialog and dialog:IsShown() and dialog)
        or dialog
    if not target then return end

    f:ClearAllPoints()
    -- Height only. The two anchors size the bar to whichever box it is on;
    -- a width copied from the container would be the wrong width now.
    f:SetHeight(10)
    -- 1px in each side keeps the bar inside the box's border art; the 5px drop
    -- is the gap beneath it.
    f:SetPoint("TOPLEFT", target, "BOTTOMLEFT", 1, -5)
    f:SetPoint("TOPRIGHT", target, "BOTTOMRIGHT", -1, -5)

    -- Installed from here, not at file scope: the two boxes need not exist
    -- when this file runs, but by the time a queue bar exists the popup is up.
    HookQueueBox(status)
    HookQueueBox(dialog)
end

local function SkinQueueTimer()
    if not _G.BigWigsLoader or not _G.BigWigsLoader.RegisterMessage then return end
    _G.BigWigsLoader.RegisterMessage("KitnEssentials", "BigWigs_FrameCreated", function(_, frame, name)
        if name ~= "QueueTimer" then return end
        S.StripTextures(frame)

        S.StatusBar(frame)
        S.ProgressFill(frame)
        queueTimer = frame
        AnchorQueueTimer()
        if frame.text then
            frame.text.SetFormattedText = function(tf, _, time) tf:SetText(format("%d", time)) end
            S.SetFont(frame.text, 15, "OUTLINE")
            frame.text:ClearAllPoints()
            frame.text:SetPoint("TOP", frame, "TOP", 0, 0)
        end
    end)
end

-- Never hardcode the accent here: read the palette table (mutated in
-- place by S.RefreshPalette) so it tracks the live theme.
local BRAND = S.palette.brand

local function SkinKeystoneTabs(frame)
    local NOOP = function() end
    local tabs = {}
    for _, tab in next, { frame:GetChildren() } do
        if tab.IsObjectType and tab:IsObjectType("Button") and tab.TabTextures then
            S.Tab(tab)
            tab:SetHeight(32)

            local txt = tab.Text
            if txt then
                if not S.data(frame).aeTabFont then
                    local f = _G.CreateFont("KE_BigWigsKeystoneTabFont")
                    local face, size, flags = txt:GetFont()
                    if face then f:SetFont(face, size or 12, flags or "") end
                    f:SetTextColor(1, 1, 1)
                    S.data(frame).aeTabFont = f
                end
                local fo = S.data(frame).aeTabFont
                tab:SetNormalFontObject(fo)
                tab:SetHighlightFontObject(fo)
                tab:SetDisabledFontObject(fo)
                tab.SetDisabledFontObject = NOOP
                txt:ClearAllPoints()
                txt:SetPoint("CENTER", tab, "CENTER", 0, 0)

                txt.ClearAllPoints = NOOP
                txt.SetPoint = NOOP
            end

            S.TabSetSelected(tab)
            if not S.data(tab).aeBWTabHooks then
                S.data(tab).aeBWTabHooks = true
                hooksecurefunc(tab, "Disable", function(t) S.TabSetSelected(t, true) end)
                hooksecurefunc(tab, "Enable", function(t) S.TabSetSelected(t, false) end)
            end
            tabs[#tabs + 1] = tab
        end
    end

    for i, tab in ipairs(tabs) do
        tab:ClearAllPoints()
        if i == 1 then
            tab:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", -2, 1)
        else
            tab:SetPoint("LEFT", tabs[i - 1], "RIGHT", -3, 0)
        end
    end
end

local function BrandCastFilter(tex)
    if not tex or S.data(tex).aeBrandCast then return end
    S.data(tex).aeBrandCast = true
    local orig = tex.SetColorTexture
    tex.SetColorTexture = function(t, r, g, b, a)
        if r == 0 and g == 0 and b == 1 then
            return orig(t, BRAND[1], BRAND[2], BRAND[3], a)
        end
        return orig(t, r, g, b, a)
    end
end

-- the re-assert ticker is gone. It only existed while KillTexture was
-- state-only, which let BigWigs' re-dressed
-- tiles came back. S.KillTexture now carries permanent Kill semantics,
-- so one pass holds -- no ticker, no per-frame cost.
local function SkinKeystoneTeleports(frame)
    BrandCastFilter(frame.teleportBar)
    for _, child in next, { frame:GetChildren() } do
        if child.IsObjectType and child:IsObjectType("ScrollFrame") and child.GetScrollChild then
            local sc = child:GetScrollChild()
            if sc then
                for _, btn in next, { sc:GetChildren() } do
                    if btn.cdbar and btn.spellID and not S.data(btn).aeTile then
                        S.data(btn).aeTile = true
                        BrandCastFilter(btn.cdbar)
                        local icon, cdbar = btn.icon, btn.cdbar
                        for _, r in next, { btn:GetRegions() } do
                            if r ~= icon and r ~= cdbar and r.IsObjectType and r:IsObjectType("Texture") then
                                S.KillTexture(r) -- permanent again (ElvUI Kill)
                            end
                        end
                        local bd = S.Backdrop(btn)
                        if bd then
                            bd:ClearAllPoints()
                            bd:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
                            bd:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
                            bd:SetBackdropColor(S.controlBg[1], S.controlBg[2], S.controlBg[3], S.controlBg[4])
                        end
                    end
                end
            end
        end
    end
end

local function SkinKeystone()
    local api = _G.BigWigsAPI
    local L = api and api.GetLocale and api:GetLocale("BigWigs")
    local titleText = L and L.keystoneTitle
    if not titleText then return end

    local tries = 0
    local function scan()
        tries = tries + 1
        for _, frame in next, { _G.UIParent:GetChildren() } do
            local tc = frame and frame.TitleContainer
            local tt = tc and tc.TitleText
            if tt and tt.GetText and not S.data(frame).kchecked then
                local ok, result = pcall(tt.GetText, tt)
                if ok and result == titleText then
                    S.data(frame).kchecked = true
                    if frame.NineSlice then S.StripTextures(frame.NineSlice) end
                    if frame.PortraitContainer then frame.PortraitContainer:Hide() end
                    if frame.TopTileStreaks then frame.TopTileStreaks:Hide() end
                    if frame.Bg then frame.Bg:Hide() end
                    S.StripTextures(frame); S.Backdrop(frame)
                    if frame.CloseButton then S.CloseButton(frame.CloseButton) end
                    for _, child in next, { frame:GetChildren() } do
                        if child.ScrollBar then S.TrimScrollBar(child.ScrollBar) end
                    end
                    SkinKeystoneTabs(frame)
                    SkinKeystoneTeleports(frame)
                    return
                end
            end
        end
        -- was 0.5s per try -- half a second of unskinned
        -- keystone/queue frames every time. Per-frame, same patience.
        if tries < 1800 and _G.C_Timer then _G.C_Timer.After(0, scan) end
    end
    if _G.C_Timer then _G.C_Timer.After(0, scan) end
end

local function SkinTooltip()
    if _G.BigWigsTooltip then
        S.StripTextures(_G.BigWigsTooltip)
        S.Backdrop(_G.BigWigsTooltip)
    end
end

local function Skin()
    SkinQueueTimer()
    SkinKeystone()
    SkinTooltip()
end

S:Register("BigWigs", Skin, "BigWigs")
