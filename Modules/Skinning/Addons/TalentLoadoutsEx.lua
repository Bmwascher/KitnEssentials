local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local pairs = pairs
local select = select
local hooksecurefunc = hooksecurefunc

-- Never hardcode the accent here: read the palette table (mutated in
-- place by S.RefreshPalette) so it tracks the live theme.
local BRAND = S.palette.brand

-- Crop fraction per side, NOT the same scale as KE:ApplyIconZoom's `zoom`
-- argument: that helper turns its 0.3 default into a 0.075 crop. The
-- 0.075 here matches the centralized helper exactly (0.20 would crop ~2.7x
-- harder than every other KE icon). We keep this file's own
-- routine rather than calling the helper because TLX resets its texcoords on
-- every scroll update, so the crop must be re-applied from stored base
-- coords instead of compounding.
local ICON_ZOOM = 0.075
local abs = math.abs
local function ZoomTexture(tex, zoom)
    if not tex or not tex.GetTexCoord then return end
    -- GetTexCoord returns eight values; LLx and URy are positional
    -- placeholders we must name to reach LLy and URx.
    local ULx, ULy, LLx, LLy, URx, URy = tex:GetTexCoord() -- luacheck: ignore 211/LLx 211/URy
    if not (ULx and URx and ULy and LLy) then return end
    local d = S.data(tex)

    local za = d.zoomApplied
    local ours = za and abs(za[1] - ULx) < 0.0001 and abs(za[2] - URx) < 0.0001
        and abs(za[3] - ULy) < 0.0001 and abs(za[4] - LLy) < 0.0001
    if not ours then d.baseCoords = { ULx, URx, ULy, LLy } end
    local l, r = d.baseCoords[1], d.baseCoords[2]
    local t, b = d.baseCoords[3], d.baseCoords[4]
    local w, h = r - l, b - t
    local zl, zr, zt, zb = l + w * zoom, r - w * zoom, t + h * zoom, b - h * zoom
    tex:SetTexCoord(zl, zr, zt, zb)
    d.zoomApplied = { zl, zr, zt, zb }
end

local function ClearMasks(tex)
    if not tex or not tex.GetNumMaskTextures or not tex.RemoveMaskTexture then return end
    for i = tex:GetNumMaskTextures(), 1, -1 do
        local m = tex:GetMaskTexture(i)
        if m then tex:RemoveMaskTexture(m) end
    end
end

-- KitnCustomCrossv3 is a PLUS glyph -- KE draws it as an X by rotating 45
-- degrees, and rests it at GUI white, so this hand-rolled close button reads
-- as the same button as S.CloseButton and KE's own panel X.
local CLOSE_TEX = "Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\KitnCustomCrossv3.png"
local CLOSE_ROT = math.rad(45)
local CLOSE_REST = { 1, 1, 1 }

local function ReskinChildButtons(parent)
    for _, child in pairs({ parent:GetChildren() }) do
        if child.GetObjectType and child:GetObjectType() == "Button"
            and child.Left and child.Middle and child.Right and child.Text then
            S.Button(child)

            child:SetSize((child:GetWidth() or 50) + 10, (child:GetHeight() or 18) + 4)

            child:SetNormalFontObject(_G.GameFontNormal)
            child:SetHighlightFontObject(_G.GameFontHighlight)
            child:SetDisabledFontObject(_G.GameFontDisable)

            local bd = S.GetBackdrop(child)
            if bd then
                bd:ClearAllPoints()
                bd:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
                bd:SetPoint("BOTTOMRIGHT", child, "BOTTOMRIGHT", -1, 1)
            end
            local hv = S.data(child).hover
            if hv and bd then
                hv:ClearAllPoints()
                hv:SetPoint("TOPLEFT", bd, "TOPLEFT", 1, -1)
                hv:SetPoint("BOTTOMRIGHT", bd, "BOTTOMRIGHT", -1, 1)
            end
        end
    end
end

local function SkinListButton(button)
    if not S.data(button).skinned then
        S.data(button).skinned = true
        if button.DisableDrawLayer then button:DisableDrawLayer("BACKGROUND") end
        if button.Check and button.Check.SetAtlas then button.Check:SetAtlas("checkmark-minimal") end
        if button.Icon then

            ClearMasks(button.Icon)
            ZoomTexture(button.Icon, ICON_ZOOM)
            local ibd = S.Backdrop(button.Icon)
            if ibd then
                ibd:SetBackdropColor(S.controlBg[1], S.controlBg[2], S.controlBg[3], S.controlBg[4])
                ibd:ClearAllPoints()
                ibd:SetPoint("TOPLEFT", button.Icon, "TOPLEFT", -1, 1)
                ibd:SetPoint("BOTTOMRIGHT", button.Icon, "BOTTOMRIGHT", 1, -1)
            end
        end
        if button.ToggleButton then
            S.StripTextures(button.ToggleButton)
            local pt = button.ToggleButton.GetPushedTexture and button.ToggleButton:GetPushedTexture()
            if pt then pt:SetAlpha(0) end
        end
        local bd = S.Backdrop(button)
        if bd then bd:SetAllPoints(button) end
        if button.SelectedBar then
            button.SelectedBar:SetColorTexture(BRAND[1], BRAND[2], BRAND[3], 0.25)
            if bd then button.SelectedBar:ClearAllPoints(); button.SelectedBar:SetPoint("TOPLEFT", bd, 1, -1); button.SelectedBar:SetPoint("BOTTOMRIGHT", bd, -1, 1) end
        end
        local hl = button.GetHighlightTexture and button:GetHighlightTexture()
        if hl then
            hl:SetColorTexture(1, 1, 1, 0.25)
            if bd then hl:ClearAllPoints(); hl:SetPoint("TOPLEFT", bd, 1, -1); hl:SetPoint("BOTTOMRIGHT", bd, -1, 1) end
        end
    end
    if button.Icon then ZoomTexture(button.Icon, ICON_ZOOM) end
    local bd = S.GetBackdrop(button)
    local isLoadout = not not (button.data and not button.data.text)
    if bd then bd:SetShown(isLoadout) end
end

local function ReskinPopupFrame(frame)
    if frame.Border then S.StripTextures(frame.Border) end
    if frame.Header then S.StripTextures(frame.Header) end
    if frame.Main then S.StripTextures(frame.Main) end
    S.StripTextures(frame)
    S.Backdrop(frame)

    if not frame.aeClose then
        local close = CreateFrame("Button", nil, frame)
        close:SetSize(16, 16)
        close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
        close:SetFrameLevel(frame:GetFrameLevel() + 5)
        local tex = close:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexture(CLOSE_TEX)
        tex:SetRotation(CLOSE_ROT)
        tex:SetVertexColor(CLOSE_REST[1], CLOSE_REST[2], CLOSE_REST[3])
        close:SetScript("OnEnter", function() tex:SetVertexColor(BRAND[1], BRAND[2], BRAND[3]) end)
        close:SetScript("OnLeave", function() tex:SetVertexColor(CLOSE_REST[1], CLOSE_REST[2], CLOSE_REST[3]) end)
        close:SetScript("OnClick", function() frame:Hide() end)
        frame.aeClose = close
    end
end

local function SkinIconGridButton(child)
    if not child or S.data(child).skinned then return end
    S.data(child).skinned = true
    if child.DisableDrawLayer then child:DisableDrawLayer("BACKGROUND") end
    local icon = child.Icon or child.icon
    if icon then
        ClearMasks(icon)
        ZoomTexture(icon, ICON_ZOOM)
        local ibd = S.Backdrop(icon)
        if ibd then
            ibd:SetBackdropColor(S.controlBg[1], S.controlBg[2], S.controlBg[3], S.controlBg[4])
            ibd:ClearAllPoints()
            ibd:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
            ibd:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
        end
    end
    if child.SelectedTexture then
        child.SelectedTexture:SetColorTexture(BRAND[1], BRAND[2], BRAND[3], 0.5)
        if icon then child.SelectedTexture:SetAllPoints(icon) end
    end
end

local function SkinEditPopup(popup)
    if not popup or S.data(popup).skinned then return end
    S.data(popup).skinned = true
    S.StripTextures(popup)
    S.Backdrop(popup)
    ReskinPopupFrame(popup)

    local bb = popup.BorderBox or popup.Main
    if bb then
        S.StripTextures(bb)
        local dropdown = bb.IconTypeDropdown
            or (bb.IconTypeDropDown and bb.IconTypeDropDown.DropDownMenu)
            or popup.IconTypeDropdown
        if dropdown then S.DropDown(dropdown, true) end
        local selBtn = bb.SelectedIconArea and bb.SelectedIconArea.SelectedIconButton
        if selBtn then
            if selBtn.DisableDrawLayer then selBtn:DisableDrawLayer("BACKGROUND") end
            SkinIconGridButton(selBtn)
        end
        local eb = bb.IconSelectorEditBox or bb.EditBox or popup.EditBox
        if eb then
            if eb.DisableDrawLayer then eb:DisableDrawLayer("BACKGROUND") end
            S.EditBox(eb, true)
        end
        local okay = bb.OkayButton or popup.OkayButton
        local cancel = bb.CancelButton or popup.CancelButton
        if okay then S.Button(okay) end
        if cancel then S.Button(cancel) end
    end

    local selector = popup.IconSelector
    if selector then
        if selector.ScrollBar then S.TrimScrollBar(selector.ScrollBar) end
        if selector.ScrollBox then
            if selector.ScrollBox.ForEachFrame and selector.ScrollBox.view then
                selector.ScrollBox:ForEachFrame(SkinIconGridButton)
            end
        end
    end
end

local function SkinMainFrame()
    local frame = _G.TalentLoadoutExMainFrame
    if not frame or S.data(frame).skinned then return end
    S.data(frame).skinned = true

    S.StripTextures(frame)
    S.Backdrop(frame)
    if _G.PlayerSpellsFrame then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", _G.PlayerSpellsFrame, "TOPRIGHT", 1, 0)
        frame:SetPoint("BOTTOMLEFT", _G.PlayerSpellsFrame, "BOTTOMRIGHT", 1, 0)

        frame:SetWidth((frame:GetWidth() or 200) + 30)
    end
    if frame.ScrollBar then S.TrimScrollBar(frame.ScrollBar) end
    ReskinChildButtons(frame)

    if frame.ScrollBox then
        if frame.ScrollBox.EnumerateFrames then
            for _, button in frame.ScrollBox:EnumerateFrames() do SkinListButton(button) end
        end
        hooksecurefunc(frame.ScrollBox, "Update", function(box) box:ForEachFrame(SkinListButton) end)
    end

    local popup = frame.EditPopupFrame
    if popup then
        SkinEditPopup(popup)
        if popup.IconSelector and popup.IconSelector.ScrollBox then
            hooksecurefunc(popup.IconSelector.ScrollBox, "Update", function(sb)
                if not sb.ScrollTarget then return end
                for i = 1, sb.ScrollTarget:GetNumChildren() do
                    local child = select(i, sb.ScrollTarget:GetChildren())
                    if child then SkinIconGridButton(child) end
                end
            end)
        end
        local textFrame = popup.TalentTextFrame
        if textFrame then
            S.StripTextures(textFrame); S.Backdrop(textFrame)
            if textFrame.Main then S.StripTextures(textFrame.Main) end
            -- border children TLX keys outside
            -- .NineSlice stack a second ring on our backdrop.
            local tfB = textFrame.Border
            if tfB and tfB.GetNumChildren and tfB:GetNumChildren() == 0 then
                S.StripTextures(tfB); tfB:Hide()
            end
            local eb = textFrame.Main and textFrame.Main.EditBox
            if eb then
                S.EditBox(eb, true)
                if eb.SetTextInsets then eb:SetTextInsets(6, 6, 2, 2) end
            end
            -- the paste bar opened overlapping the
            -- icon-picker dialog. Pin it cleanly ABOVE the popup with a
            -- 4px gap (height preserved -- only bottom edge anchored).
            textFrame:ClearAllPoints()
            textFrame:SetPoint("BOTTOMLEFT", popup, "TOPLEFT", 0, 4)
            textFrame:SetPoint("BOTTOMRIGHT", popup, "TOPRIGHT", 0, 4)
        end
        local listFrame = popup.IconListFrame
        if listFrame then
            S.StripTextures(listFrame)
            S.Backdrop(listFrame)
            -- An earlier pass hid .Border
            -- unconditionally and re-anchored via a SINGLE point after
            -- ClearAllPoints -- if the frame was sized by two points
            -- (TOPLEFT+BOTTOMRIGHT), that deleted its size and it
            -- rendered zero-area. Now: .Border only hidden when it is a
            -- childless decoration, and the spacing nudge reapplies
            -- EVERY point, offsetting only top-side ones.
            local border = listFrame.Border
            if border and border.GetNumChildren and border:GetNumChildren() == 0 then
                S.StripTextures(border); border:Hide()
            end
            if listFrame.NineSlice and listFrame.NineSlice.SetAlpha then listFrame.NineSlice:SetAlpha(0) end
            if not S.data(listFrame).aeNudged then
                S.data(listFrame).aeNudged = true
                local pts = {}
                for i = 1, listFrame:GetNumPoints() do
                    pts[i] = { listFrame:GetPoint(i) }
                end
                if #pts > 0 then
                    listFrame:ClearAllPoints()
                    for _, pt in ipairs(pts) do
                        local p, rel, rp, x, y = pt[1], pt[2], pt[3], pt[4], pt[5]
                        if p and tostring(p):find("TOP") then y = (y or 0) - 6 end
                        listFrame:SetPoint(p, rel, rp, x or 0, y or 0)
                    end
                end
            end

            local function SkinProvidedIcon(child)
                if S.data(child).skinned then
                    local tex = child.texture or child.Icon
                    if tex then ZoomTexture(tex, ICON_ZOOM) end
                    return
                end
                local tex = child.texture or child.Icon
                if not tex and child.GetRegions then

                    local best, bestArea = nil, 0
                    for _, r in pairs({ child:GetRegions() }) do
                        if r.IsObjectType and r:IsObjectType("Texture") then
                            local w, h = r:GetSize()
                            local area = (w or 0) * (h or 0)
                            if area > bestArea then best, bestArea = r, area end
                        end
                    end
                    tex = best
                end
                if not tex then return end
                S.data(child).skinned = true
                ClearMasks(tex)

                ZoomTexture(tex, ICON_ZOOM)
                local tbd = S.Backdrop(tex)
                if tbd then
                    tbd:SetBackdropColor(S.controlBg[1], S.controlBg[2], S.controlBg[3], S.controlBg[4])
                    tbd:ClearAllPoints()
                    tbd:SetPoint("TOPLEFT", tex, "TOPLEFT", -1, 1)
                    tbd:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT", 1, -1)
                end
                local hl = child.GetHighlightTexture and child:GetHighlightTexture()
                if hl then
                    hl:SetColorTexture(1, 1, 1, 0.25)
                    hl:SetAllPoints(tex)
                end
            end
            local function WalkProvided()
                for _, child in pairs({ listFrame:GetChildren() }) do
                    SkinProvidedIcon(child)
                end
            end
            WalkProvided()
            listFrame:HookScript("OnShow", WalkProvided)
        end
    end

    local textPopup = frame.TextPopupFrame and frame.TextPopupFrame.Main
    if textPopup then
        ReskinPopupFrame(frame.TextPopupFrame)
        -- this dialog originally straddled whatever
        -- else was up, so it was pinned ABOVE the TLX panel.
        -- (Import/Export opens off-screen): pinning
        -- above breaks when the panel sits at the screen's top edge --
        -- the 400px dialog leaves the screen entirely. It now opens to
        -- the LEFT of the panel, top-aligned, at its designed 500x400
        -- (the old two-point anchor also squeezed it to panel width).
        -- SetClampedToScreen guarantees visibility for ANY panel
        -- position, and the header is a drag handle so users can put
        -- it wherever they like for the session.
        local tpf = frame.TextPopupFrame
        tpf:ClearAllPoints()
        tpf:SetPoint("TOPRIGHT", frame, "TOPLEFT", -4, 0)
        tpf:SetClampedToScreen(true)
        if not tpf.aeDraggable then
            tpf.aeDraggable = true
            tpf:SetMovable(true)
            local handle = tpf.Header or tpf
            handle:EnableMouse(true)
            handle:RegisterForDrag("LeftButton")
            handle:SetScript("OnDragStart", function() tpf:StartMoving() end)
            handle:SetScript("OnDragStop", function() tpf:StopMovingOrSizing() end)
        end
        local tpfB = tpf.Border
        if tpfB and tpfB.GetNumChildren and tpfB:GetNumChildren() == 0 then
            S.StripTextures(tpfB); tpfB:Hide()
        end
        local tpMB = textPopup.Border
        if tpMB and tpMB.GetNumChildren and tpMB:GetNumChildren() == 0 then
            S.StripTextures(tpMB); tpMB:Hide()
        end
        if textPopup.EditBox then
            S.EditBox(textPopup.EditBox, true)
            if textPopup.EditBox.SetTextInsets then textPopup.EditBox:SetTextInsets(6, 6, 2, 2) end
        end
        if textPopup.ScrollFrame then
            S.StripTextures(textPopup.ScrollFrame); S.Backdrop(textPopup.ScrollFrame)
            if textPopup.ScrollFrame.ScrollBar then S.ScrollBar(textPopup.ScrollFrame.ScrollBar) end
        end
        ReskinChildButtons(textPopup)
    end

    local presetPopup = frame.PresetPopupFrame and frame.PresetPopupFrame.Main
    if presetPopup then
        ReskinPopupFrame(frame.PresetPopupFrame)
        -- same off-screen guarantee as the Import/Export
        -- dialog (its XML anchor is panel-relative too).
        frame.PresetPopupFrame:SetClampedToScreen(true)
        if presetPopup.AddonDropDownMenu then S.DropDown(presetPopup.AddonDropDownMenu) end
        local cfg = presetPopup.AddonConfigFrame1
        if cfg then
            if cfg.ModeOptionFrame and cfg.ModeOptionFrame.DropDownMenu then S.DropDown(cfg.ModeOptionFrame.DropDownMenu) end
            if cfg.CombineOptionFrame and cfg.CombineOptionFrame.CheckButton then S.CheckBox(cfg.CombineOptionFrame.CheckButton) end
        end
    end

    local pvp = frame.PvpFrame
    if pvp then
        S.StripTextures(pvp)
        if pvp.CheckButton then S.CheckBox(pvp.CheckButton); pvp.CheckButton:SetSize(24, 24) end
    end
end

local function Skin()
    -- (TLX visibly skins in after opening): this polled
    -- for TalentLoadoutExMainFrame every 0.25s -- and never checked
    -- before the first wait -- so even when the frame already existed
    -- we sat unskinned for a quarter second. That IS the flash.
    -- Now: skin immediately if it exists, otherwise poll every FRAME
    -- (After(0)) so the worst case is one frame instead of 250ms. Same
    -- ~10s total patience for a slow-loading TLX.
    if _G.TalentLoadoutExMainFrame then SkinMainFrame(); return end
    local tries = 0
    local function poll()
        tries = tries + 1
        if _G.TalentLoadoutExMainFrame then
            SkinMainFrame()
        elseif tries < 600 and _G.C_Timer then
            _G.C_Timer.After(0, poll)
        end
    end
    if _G.C_Timer then _G.C_Timer.After(0, poll) end
end

S:Register("Blizzard_PlayerSpells", Skin, "TalentLoadoutsEx")
S:Register("TalentLoadoutsEx", Skin, "TalentLoadoutsEx")
