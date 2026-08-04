local KE = select(2, ...)
local S = KE.Skins

local _G = _G
local next = next
local pcall = pcall
local ipairs = ipairs
local hooksecurefunc = hooksecurefunc
local rawset = rawset
local pairs = pairs
local getmetatable = getmetatable
local setmetatable = setmetatable

local CreateFrame = CreateFrame
local WHITE = "Interface\\Buttons\\WHITE8x8"
-- Never hardcode the accent here: read the palette table (mutated in
-- place by S.RefreshPalette) so it tracks the live theme.
local BRAND = S.palette.brand
local LevelLock

local function TabSetSelected(tab, selected)
    local d = S.data(tab)
    if not d.selTex then
        local bd = S.GetBackdrop(tab)
        if not bd then return end
        local t = tab:CreateTexture(nil, "ARTWORK")
        t:SetColorTexture(BRAND[1], BRAND[2], BRAND[3], 0.15)
        t:SetPoint("TOPLEFT", bd, "TOPLEFT", 1, -1)
        t:SetPoint("BOTTOMRIGHT", bd, "BOTTOMRIGHT", -1, 1)
        t:Hide()
        d.selTex = t
    end
    d.selTex:SetShown(selected and true or false)
end

local aceTabFont
local TABNOOP = function() end
local function SkinTab(tab)
    if not tab or S.data(tab).skinned then return end
    S.data(tab).skinned = true
    S.StripTextures(tab)

    S.KillAllTextures(tab)

    local bd = S.Template(tab, "Default")
    S.Hover(tab, bd)
    if bd then
        bd:ClearAllPoints()

        bd:SetPoint("TOPLEFT", tab, "TOPLEFT", 2, -3)
        bd:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -9, 0)
    end

    tab.deselectedTextX, tab.selectedTextX = -3, -3
    tab.deselectedTextY, tab.selectedTextY = -1, -1
    if tab.SetPushedTextOffset then tab:SetPushedTextOffset(0, 0) end
    if tab.text and tab.text.SetPoint then
        tab.text:ClearAllPoints()
        tab.text:SetPoint("CENTER", tab, "CENTER", -3, -1)
    end

    S.FontStrings(tab, 12, "OUTLINE")
    local fs = tab.GetFontString and tab:GetFontString()
    if fs then
        if not aceTabFont then
            local face = fs:GetFont()
            if face then
                local n = _G.CreateFont("KE_AceTabGroupFont")
                n:SetFont(face, 12, KE:GetFontOutline("OUTLINE"))
                n:SetTextColor(1, 0.82, 0)
                local d = _G.CreateFont("KE_AceTabGroupFontSel")
                d:SetFont(face, 12, KE:GetFontOutline("OUTLINE"))
                d:SetTextColor(1, 1, 1)
                aceTabFont = { normal = n, selected = d }
            end
        end
        if aceTabFont then
            if tab.SetNormalFontObject then tab:SetNormalFontObject(aceTabFont.normal) end
            if tab.SetHighlightFontObject then tab:SetHighlightFontObject(aceTabFont.selected) end
            if tab.SetDisabledFontObject then tab:SetDisabledFontObject(aceTabFont.selected) end
        end
        tab.SetNormalFontObject = TABNOOP
        tab.SetHighlightFontObject = TABNOOP
        tab.SetDisabledFontObject = TABNOOP

        if tab.GetText and tab.SetText then
            local txt = tab:GetText()
            if txt and txt ~= "" then tab:SetText(txt) end
        end
    end
    if tab.SetSelected then
        hooksecurefunc(tab, "SetSelected", TabSetSelected)

        TabSetSelected(tab, tab.selected)
    end

    if LevelLock then LevelLock(tab) end
end

local aceTreeFont
local TREENOOP = function() end
local function PinTreeButtonFont(button)
    if S.data(button).aeTreeFont then return end
    if not (button.SetNormalFontObject and button.text) then return end
    if not aceTreeFont then
        local face = button.text:GetFont()
        if not face then return end
        local f = _G.CreateFont("KE_AceTreeFont")
        f:SetFont(face, 13, KE:GetFontOutline("OUTLINE"))

        f:SetTextColor(1, 0.82, 0)
        aceTreeFont = f
    end
    S.data(button).aeTreeFont = true

    if button.SetPushedTextOffset then button:SetPushedTextOffset(0, 0) end
    button:SetNormalFontObject(aceTreeFont)
    if button.SetHighlightFontObject then button:SetHighlightFontObject(aceTreeFont) end
    button.SetNormalFontObject = TREENOOP
    button.SetHighlightFontObject = TREENOOP
end

local function RefreshTree(self, ...)
    if self.ae_oldRefreshTree then self.ae_oldRefreshTree(self, ...) end
    local buttons, lines = self.buttons, self.lines
    if not (buttons and lines) then return end
    local status = self.status or self.localstatus
    local offset = (status and status.scrollvalue) or 0

    local selected = status and status.selected
    for i = offset + 1, #lines do
        local button = buttons[i - offset]
        if button then
            local line = lines[i]
            if button.highlight then
                if not S.data(button).aeFlatHL then
                    S.data(button).aeFlatHL = true
                    button.highlight:SetTexture("Interface\\Buttons\\WHITE8X8")
                end
                local isSel = selected and line and line.uniquevalue == selected
                if isSel then

                    button.highlight:SetVertexColor(S.palette.brand[1], S.palette.brand[2], S.palette.brand[3], 0.25)
                else
                    button.highlight:SetVertexColor(S.palette.hover[1], S.palette.hover[2], S.palette.hover[3], 0.15)
                end
                if button.text and button.text.SetTextColor then
                    if isSel then
                        button.text:SetTextColor(1, 1, 1)
                    else
                        button.text:SetTextColor(1, 0.82, 0)
                    end
                end
            end
            PinTreeButtonFont(button)
        end
    end
end

local function AceEditBoxTextInsets(box, l, r, t, b)
    if l == 0 then box:SetTextInsets(3, r, t, b) end
end
local function AceEditBoxPoint(box, a, b, c, d, e)
    if d == 7 then box:SetPoint(a, b, c, 0, e) end
end
local function SkinAceEditBox(editbox, button)
    if not editbox then return end
    local fresh = not S.data(editbox).skinned
    S.EditBox(editbox, true)
    if fresh then
        hooksecurefunc(editbox, "SetTextInsets", AceEditBoxTextInsets)
        hooksecurefunc(editbox, "SetPoint", AceEditBoxPoint)
        local bd = S.GetBackdrop(editbox)
        if bd then
            bd:ClearAllPoints()
            bd:SetPoint("TOPLEFT", editbox, "TOPLEFT", 0, -2)
            bd:SetPoint("BOTTOMRIGHT", editbox, "BOTTOMRIGHT", -1, 1)
        end
    end
    if button then
        S.Button(button)
        local bd = S.GetBackdrop(editbox)
        if bd then
            button:ClearAllPoints()
            button:SetPoint("RIGHT", bd, "RIGHT", -2, 0)
        end
    end
end

local function MakeFontPin(size)
    return function(fs)
        local fontObject = fs.GetFontObject and fs:GetFontObject()
        local face = fontObject and fontObject.GetFont and fontObject:GetFont()
        if not face then face = fs:GetFont() end

        if face then fs:SetFont(face, size, KE:GetFontOutline("OUTLINE")) end
    end
end
local function HookFontBump(fs, size)
    if not fs or S.data(fs).aeFontBump then return end
    S.data(fs).aeFontBump = true
    local pin = MakeFontPin(size or 12)
    hooksecurefunc(fs, "SetFontObject", pin)
    pin(fs)
end

local function PaintControl(bd)
    if bd and bd.SetBackdropColor then
        local c = S.controlBg
        bd:SetBackdropColor(c[1], c[2], c[3], c[4])
    end
    return bd
end

local function SkinWidget(widget)
    if not widget or not widget.type then return end
    local t = widget.type
    local frame = widget.frame

    if t == "Button" or t == "Button-ElvUI" then
        if frame then
            S.Button(frame)
            local fs = frame.GetFontString and frame:GetFontString()
            if fs then S.SetFont(fs, 12, "OUTLINE") end
        end

    elseif t == "CheckBox" then

        HookFontBump(widget.text, 13)

        HookFontBump(widget.desc, 13)
        if widget.SetDescription and not S.data(widget).aeDescHook then
            S.data(widget).aeDescHook = true
            hooksecurefunc(widget, "SetDescription", function(w)
                HookFontBump(w.desc, 13)
            end)
        end

        if widget.SetType and not S.data(widget).aeTypeHook then
            S.data(widget).aeTypeHook = true
            hooksecurefunc(widget, "SetType", function(w, kind)
                if kind == "radio" and w.checkbg then w.checkbg:SetSize(20, 20) end
            end)
        end
        local check, checkbg, highlight = widget.check, widget.checkbg, widget.highlight
        if checkbg and not S.data(widget).checkSkinned then
            S.data(widget).checkSkinned = true
            S.KillTexture(checkbg)
            if highlight then S.KillTexture(highlight) end

            local bd = PaintControl(S.Backdrop(checkbg))

            if bd then
                bd:ClearAllPoints()
                bd:SetPoint("TOPLEFT", checkbg, "TOPLEFT", 5, -5)
                bd:SetPoint("BOTTOMRIGHT", checkbg, "BOTTOMRIGHT", -5, 5)
            end
            if check then

                check:SetTexture("Interface\\Buttons\\WHITE8x8")
                check:SetVertexColor(BRAND[1], BRAND[2], BRAND[3], S.palette.brandFillA)
                check:ClearAllPoints()

                check:SetPoint("TOPLEFT", (bd or checkbg), "TOPLEFT", 1, -1)
                check:SetPoint("BOTTOMRIGHT", (bd or checkbg), "BOTTOMRIGHT", -1, 1)

                check.SetTexture = function() end
            end
        end

    elseif t == "EditBox" or t == "EditBox-ElvUI" then
        SkinAceEditBox(widget.editbox, widget.button)

    elseif t == "MultiLineEditBox" or t == "MultiLineEditBox-ElvUI" then
        if widget.button then S.Button(widget.button) end
        if widget.scrollBar then S.ScrollBar(widget.scrollBar) end
        if widget.scrollBG then S.StripTextures(widget.scrollBG); PaintControl(S.Backdrop(widget.scrollBG)) end
        if widget.editbox then S.EnsureCaretRoom(widget.editbox) end

    elseif t == "Dropdown" or t == "Dropdown-ElvUI" or t == "LQDropdown" then
        local dd = widget.dropdown
        if dd then
            S.StripTextures(dd)
            local bd = PaintControl(S.Backdrop(dd))
            if bd then
                bd:ClearAllPoints()
                bd:SetPoint("TOPLEFT", dd, "TOPLEFT", 15, -2)
                bd:SetPoint("BOTTOMRIGHT", dd, "BOTTOMRIGHT", -21, 0)
            end
            if widget.button then S.ArrowButton(widget.button, "down") end
            HookFontBump(widget.label, 13)

            if S.AceFixPullout then S.AceFixPullout(widget) end

            if widget.text then S.SetFont(widget.text, 12, "") end
        end

    elseif t == "LSM30_Font" or t == "LSM30_Sound" or t == "LSM30_Border"
        or t == "LSM30_Background" or t == "LSM30_Statusbar" then
        if frame then
            S.StripTextures(frame)
            local bd = PaintControl(S.Backdrop(frame))
            if bd then
                bd:ClearAllPoints()
                bd:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -21)
                bd:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, -1)
            end
            local button = frame.dropButton
            if button then
                S.ArrowButton(button, "down")

                if not S.data(button).aeLSMHook then
                    S.data(button).aeLSMHook = true
                    button:HookScript("OnClick", function()
                        if _G.C_Timer then
                            _G.C_Timer.After(0, function()
                                if S.AceFixPullout then S.AceFixPullout(widget) end
                                local po = widget.pullout
                                local pf = po and (po.frame or po)
                                if pf then S.StripTextures(pf); S.Template(pf, "Default") end
                            end)
                        end
                    end)
                end
            end

            if t == "LSM30_Sound" and widget.soundbutton and bd then
                widget.soundbutton:SetParent(bd)
            end
            if t == "LSM30_Statusbar" and widget.bar and bd then
                widget.bar:ClearAllPoints()
                widget.bar:SetPoint("TOPLEFT", bd, "TOPLEFT", 1, -1)
                widget.bar:SetPoint("BOTTOMRIGHT", bd, "BOTTOMRIGHT", -1, 1)
            end
        end

    elseif t == "Slider" or t == "Slider-ElvUI" then

        local sl = widget.slider
        if sl and not S.data(sl).skinned then
            S.data(sl).skinned = true
            S.StripTextures(sl)
            local thumb = sl.GetThumbTexture and sl:GetThumbTexture()
            if thumb then
                thumb:SetTexture(WHITE)
                thumb:SetVertexColor(BRAND[1], BRAND[2], BRAND[3], S.palette.brandFillA)
                thumb:SetSize(10, 14)
            end

            local bd = PaintControl(S.Backdrop(sl))
            if bd then
                bd:ClearAllPoints()
                bd:SetPoint("TOPLEFT", sl, "TOPLEFT", 2, -3)
                bd:SetPoint("BOTTOMRIGHT", sl, "BOTTOMRIGHT", -2, 3)
                if thumb then
                    local step = CreateFrame("StatusBar", nil, sl)
                    step:SetFrameLevel(bd:GetFrameLevel() + 1)
                    step:SetStatusBarTexture(WHITE)
                    step:SetStatusBarColor(BRAND[1], BRAND[2], BRAND[3], 0.35)
                    step:SetPoint("TOPLEFT", bd, "TOPLEFT", 1, -1)
                    step:SetPoint("BOTTOMLEFT", bd, "BOTTOMLEFT", 1, 1)
                    step:SetPoint("RIGHT", thumb, "CENTER")
                    S.data(sl).stepBar = step
                end
            end
        end
        HookFontBump(widget.label, 13)
        if widget.editbox then
            SkinAceEditBox(widget.editbox)

            if widget.editbox.SetBackdrop then widget.editbox:SetBackdrop(nil) end
            widget.editbox:SetScript("OnEnter", nil)
            widget.editbox:SetScript("OnLeave", nil)

            widget.editbox:SetHeight(18)
            widget.editbox:ClearAllPoints()
            widget.editbox:SetPoint("TOP", sl, "BOTTOM", 0, -1)

            local eb = widget.editbox
            local function pinEB()
                if S.data(eb).aePinning then return end
                S.data(eb).aePinning = true
                S.SetFont(eb, 13, "OUTLINE")
                S.data(eb).aePinning = nil
            end
            if not S.data(eb).aeEBHook then
                S.data(eb).aeEBHook = true
                hooksecurefunc(eb, "SetFontObject", pinEB)
            end
            pinEB()
        end
        if widget.lowtext then
            widget.lowtext:ClearAllPoints()
            widget.lowtext:SetPoint("TOPLEFT", sl, "BOTTOMLEFT", 2, -2)
        end
        if widget.hightext then
            widget.hightext:ClearAllPoints()
            widget.hightext:SetPoint("TOPRIGHT", sl, "BOTTOMRIGHT", -2, -2)
        end

    elseif t == "Keybinding" then
        if widget.button then S.Button(widget.button) end
        if widget.msgframe then
            S.StripTextures(widget.msgframe)
            PaintControl(S.Backdrop(widget.msgframe))
        end

    elseif t == "ColorPicker" or t == "ColorPicker-ElvUI" then
        if frame then
            local bd = PaintControl(S.Backdrop(frame))
            if bd then
                bd:SetSize(24, 16)
                bd:ClearAllPoints()
                bd:SetPoint("LEFT", frame, "LEFT", 4, 0)
            end
            local sw = widget.colorSwatch
            if sw then
                sw:SetTexture("Interface\\Buttons\\WHITE8x8")
                sw:ClearAllPoints()
                if bd then sw:SetParent(bd); sw:SetPoint("TOPLEFT", bd, "TOPLEFT", 1, -1); sw:SetPoint("BOTTOMRIGHT", bd, "BOTTOMRIGHT", -1, 1) end
                if sw.background then sw.background:SetColorTexture(0, 0, 0, 0) end

                if sw.checkers then sw.checkers:Hide() end
            end
        end

    elseif t == "Label" or t == "InteractiveLabel" then

        local lbl = widget.label

        local w = widget.frame and widget.frame.width
        local fixedWidth = type(w) == "number"
        if lbl and not fixedWidth then
            HookFontBump(lbl, 13)
        end

        if lbl and widget.SetWidth and not S.data(widget).aeWidthHook then
            S.data(widget).aeWidthHook = true
            hooksecurefunc(widget, "SetWidth", function(wdg, width)
                if type(width) == "number" and wdg.label then
                    local fo = wdg.label.GetFontObject and wdg.label:GetFontObject()
                    local f, sz, fl = fo and fo:GetFont() -- luacheck: ignore 221/sz 221/fl
                    if f and sz then

                        local cf, cs, cfl = wdg.label:GetFont()
                        if cf ~= f or cs ~= sz or (cfl or "") ~= (fl or "") then
                            wdg.label:SetFont(f, sz, fl or "")
                        end
                    end
                end
            end)
        end

    elseif t == "Icon" then
        if frame then S.StripTextures(frame) end

    elseif t == "SharedDropdown" then

        local dd = widget.dropdown
        if dd and dd.GetName and not S.data(dd).aeSharedSkinned then
            S.data(dd).aeSharedSkinned = true
            local n = dd:GetName()
            for _, suffix in ipairs({ "Left", "Middle", "Right" }) do
                local tex = _G[n .. suffix]
                if tex then tex:SetAlpha(0) end
            end
            local bd = S.Template(dd, "Default")
            if bd then
                bd:ClearAllPoints()
                bd:SetPoint("TOPLEFT", dd, "TOPLEFT", 16, -2)
                bd:SetPoint("BOTTOMRIGHT", dd, "BOTTOMRIGHT", -18, 2)
            end
            local btn = _G[n .. "Button"]
            if btn then S.ArrowButton(btn, "down") end

            local seltext = _G[n .. "Text"]
            if seltext then S.SetFont(seltext, 13, "") end

            if widget.label then S.SetFont(widget.label, 12, "") end
        end

        if S.StyleSharedDropDownList then S.StyleSharedDropDownList() end

    elseif t == "Dropdown-Pullout" then

        if frame then
            local function reassert()
                if frame.SetBackdrop then frame:SetBackdrop(nil) end
                if not S.GetBackdrop(frame) then
                    S.StripTextures(frame)
                    S.Template(frame, "Default")
                else
                    local bd = S.GetBackdrop(frame)
                    if bd then bd:Show(); bd:SetBackdropColor(S.controlBg[1], S.controlBg[2], S.controlBg[3], S.controlBg[4]) end
                end
            end
            if not S.data(frame).aePulloutHook then
                S.data(frame).aePulloutHook = true
                if frame.HookScript then frame:HookScript("OnShow", reassert) end
            end
            reassert()
        end
        if widget.slider then
            S.StripTextures(widget.slider)
            S.ScrollBar(widget.slider)
        end

    elseif t and (t:find("Dropdown%-Item") == 1 or t:find("^DDI%-") == 1) then

        local itemFrame = widget.frame and widget.frame.GetParent and widget.frame:GetParent()
        local scrollFrame = itemFrame and itemFrame.GetParent and itemFrame:GetParent()
        local pulloutFrame = scrollFrame and scrollFrame.GetParent and scrollFrame:GetParent()
        if pulloutFrame and not S.data(pulloutFrame).aePulloutSkinned then
            S.data(pulloutFrame).aePulloutSkinned = true
            local function reassert()
                if pulloutFrame.SetBackdrop then pulloutFrame:SetBackdrop(nil) end
                S.StripTextures(pulloutFrame)
                local bd = S.GetBackdrop(pulloutFrame) or S.Template(pulloutFrame, "Default")
                if bd then
                    bd:Show()
                    bd:SetBackdropColor(S.controlBg[1], S.controlBg[2], S.controlBg[3], S.controlBg[4])
                    bd:SetFrameLevel(math.max(pulloutFrame:GetFrameLevel() - 1, 0))
                end

                for _, c in ipairs({ pulloutFrame:GetChildren() }) do
                    if c.GetObjectType and c:IsObjectType("Slider") then S.ScrollBar(c) end
                end
            end
            if pulloutFrame.HookScript then pulloutFrame:HookScript("OnShow", reassert) end
            reassert()
        end

        if widget.text then S.SetFont(widget.text, 13, "OUTLINE") end
        if widget.highlight and widget.highlight.SetTexture then
            widget.highlight:SetTexture("Interface\\Buttons\\WHITE8x8")
            widget.highlight:SetVertexColor(S.palette.hover[1], S.palette.hover[2], S.palette.hover[3], 0.15)
        end
    end
end

local GROUP = {
    InlineGroup = true, TreeGroup = true, TabGroup = true,
    Frame = true, DropdownGroup = true, Window = true,
}

local function SkinContainer(widget)
    if not widget or not widget.type then return end
    local t = widget.type

    if t == "ScrollFrame" then
        if widget.scrollbar then S.ScrollBar(widget.scrollbar) end
        return
    end

    if t == "DropdownGroup" then

        _G.C_Timer.After(0, function()
            if widget.exportInstanceBtn then S.Button(widget.exportInstanceBtn) end
        end)
    end

    if GROUP[t] then
        local frame = widget.content and widget.content.GetParent and widget.content:GetParent()
        frame = frame or widget.frame
        if not frame then return end

        local topLevelWindow = (t == "Frame" or t == "Window")
        if t == "Frame" then
            S.StripTextures(frame)
            for _, child in next, { frame:GetChildren() } do
                if child.IsObjectType and child:IsObjectType("Button") and child.GetText and child:GetText() then
                    S.Button(child)
                else

                    S.StripTextures(child)
                    if child.SetBackdrop then child:SetBackdrop(nil) end
                end
            end
            if widget.closebutton then S.CloseButton(widget.closebutton) end
        elseif t == "Window" then
            S.StripTextures(frame)
            if widget.closebutton then S.CloseButton(widget.closebutton) end
        end

        S.StripTextures(frame)

        local bd = S.Backdrop(frame, 0, t == "TabGroup")
        if bd then
            if topLevelWindow then
                bd:SetBackdropColor(S.bgColor[1], S.bgColor[2], S.bgColor[3], S.bgColor[4])
            elseif t == "InlineGroup" then

                local it = S.palette.inlineTint
                bd:SetBackdropColor(it[1], it[2], it[3], it[4])
            else

                local pc = S.palette.panel
                bd:SetBackdropColor(pc[1], pc[2], pc[3], pc[4])
            end
        end

        if widget.treeframe then
            S.StripTextures(widget.treeframe)

            local tf = S.Backdrop(widget.treeframe)
            if tf then
                local pc = S.palette.panel
                tf:SetBackdropColor(pc[1], pc[2], pc[3], pc[4])
            end
        end

        if t == "TabGroup" then
            S.AceSkinTabGroup(widget)
            if widget.tabs then
                for _, tab in next, widget.tabs do pcall(SkinTab, tab) end
            end
        end

        if t == "TreeGroup" and widget.RefreshTree and not widget.ae_oldRefreshTree then
            widget.ae_oldRefreshTree = widget.RefreshTree
            widget.RefreshTree = RefreshTree
        end

        if widget.scrollbar then S.ScrollBar(widget.scrollbar) end
    end

    if widget.sizer_se then
        for _, region in next, { widget.sizer_se:GetRegions() } do
            if region.IsObjectType and region:IsObjectType("Texture") then
                region:SetTexture(137057)
            end
        end
    end
end

local math_max = math.max

local SUB_BD_KEYS = { "editbox", "slider", "dropdown", "checkbg", "msgframe", "scrollBG" }
local function sinkOne(obj)
    if not obj then return end
    local bd = S.GetBackdrop(obj)
    if not bd then return end
    local ref = obj.GetFrameLevel and obj or (obj.GetParent and obj:GetParent())
    local lvl = (ref and ref.GetFrameLevel and ref:GetFrameLevel()) or 1
    local target = math_max(lvl - 1, 0)
    if bd:GetFrameLevel() ~= target then bd:SetFrameLevel(target) end
end

local function HasSinkTargets(f, widget)
    if S.GetBackdrop(f) then return true end
    if widget then
        for i = 1, #SUB_BD_KEYS do
            local o = widget[SUB_BD_KEYS[i]]
            if o and S.GetBackdrop(o) then return true end
        end
    end
    return false
end
function LevelLock(f, widget)
    if not f then return end
    if not S.data(f).aeLvlLock and not HasSinkTargets(f, widget) then return end
    local function sinkAll()
        sinkOne(f)
        if widget then
            for i = 1, #SUB_BD_KEYS do sinkOne(widget[SUB_BD_KEYS[i]]) end
        end
    end
    if S.data(f).aeLvlLock then sinkAll() return end
    S.data(f).aeLvlLock = true
    hooksecurefunc(f, "SetFrameLevel", sinkAll)
    hooksecurefunc(f, "SetParent", sinkAll)
    if f.HookScript then f:HookScript("OnShow", sinkAll) end
    sinkAll()
end

function S.AceSkinTabGroup(widget)
    if not widget then return end
    if not widget.ae_oldCreateTab and widget.CreateTab then
        widget.ae_oldCreateTab = widget.CreateTab
        widget.CreateTab = function(self, id)
            local tab = self.ae_oldCreateTab(self, id)
            pcall(SkinTab, tab)
            return tab
        end
    end

    if widget.tabs then
        for i = 1, #widget.tabs do pcall(SkinTab, widget.tabs[i]) end
    end

    local function AnchorRow(w)
        local t1 = w.tabs and w.tabs[1]
        if t1 and w.border then
            t1:ClearAllPoints()

            t1:SetPoint("BOTTOMLEFT", w.border, "TOPLEFT", -3, 1)
        end
    end
    if not S.data(widget).aeTabRowHook and widget.BuildTabs then
        S.data(widget).aeTabRowHook = true
        hooksecurefunc(widget, "BuildTabs", AnchorRow)
    end
    AnchorRow(widget)
end

function S.AceFixPullout(dropdown)
    local p = dropdown and dropdown.pullout
    if not p or S.data(p).aeLevelFix then return end
    S.data(p).aeLevelFix = true
    local math_max = math.max -- luacheck: ignore 431/math_max
    local function Relevel(pull)
        local f = pull.frame
        if not f then return end
        local base = f:GetFrameLevel() or 1

        if base >= 9998 then base = 9997; f:SetFrameLevel(base) end
        local bd = S.GetBackdrop(f)
        if bd then bd:SetFrameLevel(math_max(base - 1, 0)) end
        if pull.scrollFrame then pull.scrollFrame:SetFrameLevel(base + 1) end
        if pull.itemFrame then pull.itemFrame:SetFrameLevel(base + 2) end
    end
    if p.Open then hooksecurefunc(p, "Open", Relevel) end
    Relevel(p)
end

S.AceWidgetSkinners = S.AceWidgetSkinners or {}

local function SkinPulloutFrame(pf)
    if not pf or S.data(pf).aeBackdropLocked then return end
    S.data(pf).aeBackdropLocked = true
    S.StripTextures(pf)
    local abd = S.Template(pf, "Default")

    if abd then

        local sinkPending = false
        local function sink()
            sinkPending = false
            abd:SetFrameLevel(math.max(pf:GetFrameLevel() - 1, 0))
        end
        local function queueSink()
            if sinkPending or not _G.C_Timer then return end
            sinkPending = true
            _G.C_Timer.After(0, sink)
        end
        hooksecurefunc(pf, "SetFrameLevel", queueSink)
        if pf.HookScript then
            pf:HookScript("OnShow", queueSink)
        end
        sink()
    end
    local EMPTY_BD = { bgFile = nil, edgeFile = nil, tile = false, edgeSize = 0,
        insets = { left = 0, right = 0, top = 0, bottom = 0 } }
    hooksecurefunc(pf, "SetBackdrop", function(self, bkd)
        if bkd and bkd.bgFile and not S.data(self).aeClearing then
            S.data(self).aeClearing = true
            self:SetBackdrop(EMPTY_BD)
            S.data(self).aeClearing = nil
        end
    end)
    pf:SetBackdrop(EMPTY_BD)
    for _, c in ipairs({ pf:GetChildren() }) do
        if c.GetObjectType and c:IsObjectType("Slider") then S.ScrollBar(c) end
    end
end
S.SkinPulloutFrame = SkinPulloutFrame

-- BigWigs 419 "stock yellow config" regression. BigWigs_Options
-- (LoD) embeds its own AceGUI-3.0. Post-ElvUI it is often the FIRST -- or a
-- NEWER -- AceGUI-3.0 in the session: LibStub:NewLibrary succeeds and the
-- incoming lib file body reassigns RegisterAsWidget/RegisterAsContainer/
-- Create, wiping our wraps; then BigWigs builds the entire config window in
-- the SAME execution as LoadAddOn. The old C_Timer.After(0) rehook landed
-- one frame late, and AceGUI pools widgets so nothing ever re-registers.
-- Fix = ElvUI's exact idiom (Skins/Ace3.lua HookAce3/Ace3_MetaIndex): our
-- hooksecurefunc on LibStub.NewLibrary runs INSIDE NewLibrary, i.e. BEFORE
-- the incoming file assigns any methods -- so on a true minor upgrade we
-- nil the three fields and arm a metatable __newindex trap that re-wraps
-- each one synchronously AT ASSIGNMENT. Zero-frame gap, works whether an
-- AceGUI existed at login or the LoD copy is the first ever.

local function WrapRegisterAsWidget(orig)
    return function(self, widget)
        local r = orig(self, widget)
        pcall(SkinWidget, widget)
        for i = 1, #S.AceWidgetSkinners do pcall(S.AceWidgetSkinners[i], widget) end
        if widget and widget.frame then pcall(LevelLock, widget.frame, widget) end
        return r
    end
end

local function WrapRegisterAsContainer(orig)
    return function(self, widget)
        local r = orig(self, widget)
        pcall(SkinContainer, widget)
        if widget and widget.frame then pcall(LevelLock, widget.frame, widget) end
        return r
    end
end

local function WrapCreate(orig)
    return function(self, wtype)
        local w = orig(self, wtype)
        if wtype == "Dropdown-Pullout" and w and w.frame then
            pcall(SkinPulloutFrame, w.frame)
            -- Create fires per pool ACQUIRE, not per construction: guard so
            -- recycled pullouts don't accumulate duplicate OnShow hooks.
            if w.frame.HookScript and not S.data(w.frame).aeShowHooked then
                S.data(w.frame).aeShowHooked = true
                w.frame:HookScript("OnShow", function(f) pcall(SkinPulloutFrame, f) end)
            end
        end
        return w
    end
end

-- marker key ("did we wrap the current value?") per trapped method
local TRAP = {
    RegisterAsWidget    = { wrap = WrapRegisterAsWidget,    mark = "aeRAW" },
    RegisterAsContainer = { wrap = WrapRegisterAsContainer, mark = "aeRAC" },
    Create              = { wrap = WrapCreate,              mark = "aeCreate" },
}

local function AceGUIMetaNewIndex(lib, k, v)
    local t = TRAP[k]
    if t and type(v) == "function" then
        local wrapped = t.wrap(v)
        rawset(lib, k, wrapped)
        rawset(lib, t.mark, wrapped)
    else
        rawset(lib, k, v)
    end
end

local function ArmTrap(AceGUI)
    local mt = getmetatable(AceGUI)
    if mt then
        mt.__newindex = AceGUIMetaNewIndex
    else
        setmetatable(AceGUI, { __newindex = AceGUIMetaNewIndex })
    end
end

local lastGUIMinor = 0

local function HookAceGUI(AceGUI, minor, upgrading)
    if not AceGUI then return end
    if minor and minor > lastGUIMinor then lastGUIMinor = minor end

    if upgrading then
        -- Called from inside LibStub:NewLibrary on a real minor upgrade,
        -- BEFORE the incoming AceGUI-3.0.lua body runs. Clear the fields so
        -- its assignments fall through to __newindex and get wrapped in
        -- place. (Every AceGUI-3.0 defines all three at file scope -- same
        -- guarantee ElvUI's trap has relied on for years.)
        for k in pairs(TRAP) do rawset(AceGUI, k, nil) end
        ArmTrap(AceGUI)
        return
    end

    -- Direct path: wrap whatever is present right now.
    for k, t in pairs(TRAP) do
        local cur = AceGUI[k]
        if type(cur) == "function" and cur ~= AceGUI[t.mark] then
            local wrapped = t.wrap(cur)
            rawset(AceGUI, k, wrapped)
            rawset(AceGUI, t.mark, wrapped)
        end
    end
    ArmTrap(AceGUI)

    for n = 1, 20 do
        local pf = _G["AceGUI30Pullout" .. n]
        if pf then
            pcall(SkinPulloutFrame, pf)
            if pf.HookScript and not S.data(pf).aeShowHooked then
                S.data(pf).aeShowHooked = true
                pf:HookScript("OnShow", function(f) pcall(SkinPulloutFrame, f) end)
            end
        end
    end
end

local function StyleConfigDialog()
    local LibStub = _G.LibStub
    if not LibStub then return end
    local ok, ACD = pcall(LibStub, "AceConfigDialog-3.0", true)
    if not ok or not ACD then return end
    if ACD.tooltip and not S.data(ACD.tooltip).acdStyled then
        S.data(ACD.tooltip).acdStyled = true
        S.StripTextures(ACD.tooltip)
        S.Template(ACD.tooltip, "Transparent")
    end
    if ACD.popup and not S.data(ACD.popup).acdStyled then
        S.data(ACD.popup).acdStyled = true
        ACD.popup:HookScript("OnShow", function(pop)
            if S.data(pop).acdShown then return end
            S.data(pop).acdShown = true
            S.StripTextures(pop)
            S.Template(pop, "Window")
            local child = pop:GetChildren()
            if child then S.StripTextures(child) end
            if pop.accept then S.Button(pop.accept) end
            if pop.cancel then S.Button(pop.cancel) end
        end)
    end
end

local function SetupAce3()
    local LibStub = _G.LibStub
    if not LibStub then return end
    StyleConfigDialog()

    local ok, AceGUI = pcall(LibStub, "AceGUI-3.0", true)
    if ok and AceGUI then
        HookAceGUI(AceGUI, LibStub.minors and LibStub.minors["AceGUI-3.0"])
    end

    if not LibStub.aeNewLibHooked and type(LibStub.NewLibrary) == "function" then
        hooksecurefunc(LibStub, "NewLibrary", function(self, major)
            if type(major) ~= "string" then return end
            if major == "AceGUI-3.0" then
                -- We run inside NewLibrary: if minors[major] moved past our
                -- last-seen minor, the call SUCCEEDED and the incoming file
                -- body is about to reassign the lib's methods. Arm the trap
                -- NOW (synchronously) -- an After(0) here loses to BigWigs,
                -- which LoD-loads its Options addon and builds the whole
                -- config window in the same execution.
                local m = self.minors and self.minors[major]
                if m and m > lastGUIMinor then
                    HookAceGUI(self.libs and self.libs[major], m, true)
                end
            elseif major:find("AceConfigDialog", 1, true) and _G.C_Timer then
                -- tooltip/popup styling is hover/late-shown -- next frame is fine
                _G.C_Timer.After(0, StyleConfigDialog)
            end
        end)
        LibStub.aeNewLibHooked = true
    end
end

S:RegisterEarly(SetupAce3, "Ace3")

