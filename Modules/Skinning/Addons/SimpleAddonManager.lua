local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local pairs = pairs
local hooksecurefunc = hooksecurefunc

local function ReskinItems(frame, template)
    if template ~= "SimpleAddonManagerAddonItem" and template ~= "SimpleAddonManagerCategoryItem" then return end
    if not frame.buttons then return end
    for _, btn in pairs(frame.buttons) do
        if not S.data(btn).skinned then
            S.data(btn).skinned = true
            if btn.Name then S.SetFont(btn.Name) end
            if btn.EnabledButton then S.CheckBox(btn.EnabledButton) end
            if btn.ExpandOrCollapseButton then S.StripTextures(btn.ExpandOrCollapseButton) end
        end
    end
end

local ARROW = "Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\collapse.png"
local function IconButton(btn)
    if not btn or S.data(btn).skinned then return end
    S.data(btn).skinned = true
    local icon = btn.icon
    S.ClearButtonArt(btn)
    if btn.GetRegions then
        for _, region in ipairs({ btn:GetRegions() }) do
            if region ~= icon and region.IsObjectType and region:IsObjectType("Texture") then
                S.KillTexture(region)
            end
        end
    end
    local bd = S.Backdrop(btn)
    if bd then bd:SetBackdropColor(S.controlBg[1], S.controlBg[2], S.controlBg[3], S.controlBg[4]) end
    S.Hover(btn)
    if icon then
        icon:SetAlpha(1)
        if icon.SetDrawLayer then icon:SetDrawLayer("ARTWORK") end
    end
end

local function SkinEDDMLists()
    for i = 1, (_G.UIDROPDOWNMENU_MAXLEVELS or 3) do
        local name = "ElioteDDM_DropDownList" .. i
        local list = _G[name]
        if list then
            if not S.data(list).skinned then
                S.data(list).skinned = true
                for _, suffix in ipairs({ "Backdrop", "MenuBackdrop" }) do
                    local bdf = _G[name .. suffix]
                    if bdf and bdf.SetBackdrop then bdf:SetBackdrop(nil) end
                end
                S.Backdrop(list)
            end

            local b = 1
            local button = _G[name .. "Button" .. b]
            while button do
                local fs = (button.GetFontString and button:GetFontString())
                    or _G[name .. "Button" .. b .. "NormalText"]
                if fs then S.SetFont(fs, 13, "") end
                b = b + 1
                button = _G[name .. "Button" .. b]
            end
        end
    end
end

local eddmHooked = false
local function HookEDDM()
    if eddmHooked then return end
    local LibStub = _G.LibStub
    local EDDM = LibStub and LibStub("ElioteDropDownMenu-1.0", true)
    if not EDDM then return end
    eddmHooked = true
    for _, fn in ipairs({ "EasyMenu", "ToggleEasyMenu" }) do
        if EDDM[fn] then hooksecurefunc(EDDM, fn, SkinEDDMLists) end
    end

    if EDDM.UIDropDownMenu_Initialize then hooksecurefunc(EDDM, "UIDropDownMenu_Initialize", SkinEDDMLists) end
end

local function ReskinModules(frame)
    for _, key in ipairs({ "OkButton", "CancelButton", "EnableAllButton", "DisableAllButton", "SetsButton" }) do
        if frame[key] then S.Button(frame[key]) end
    end

    IconButton(frame.ConfigButton)
    IconButton(frame.CategoryButton)
    if frame.CharacterDropDown then S.DropDown(frame.CharacterDropDown, true) end
    if frame.OkButton and frame.CancelButton then
        frame.OkButton:ClearAllPoints()
        frame.OkButton:SetPoint("RIGHT", frame.CancelButton, "LEFT", -2, 0)
    end
    if frame.DisableAllButton and frame.EnableAllButton then
        frame.DisableAllButton:ClearAllPoints()
        frame.DisableAllButton:SetPoint("LEFT", frame.EnableAllButton, "RIGHT", 2, 0)
    end
    if frame.Sizer then
        S.StripTextures(frame.Sizer)
        -- the strip killed the native grabber art and
        -- left the resize handle invisible. Reuse KE's own GUI
        -- resize-handle element (MainFrame footer) for an identical
        -- look: custom 23px grip texture, muted grey @ 0.6.
        local sizer = frame.Sizer
        if not S.data(sizer).aeGrip then
            S.data(sizer).aeGrip = true
            sizer:SetSize(16, 16)
            local tex = sizer:CreateTexture(nil, "OVERLAY")
            tex:SetAllPoints()
            tex:SetTexture("Interface\\AddOns\\KitnEssentials\\Media\\GUITextures\\KitnCustomResizeHandle23px.png")
            tex:SetVertexColor(KE.Theme.textMuted[1], KE.Theme.textMuted[2], KE.Theme.textMuted[3], 0.6)
            sizer:SetNormalTexture(tex)
        end
    end
    if frame.SearchBox then S.EditBox(frame.SearchBox) end

    if frame.ResultOptionsButton then
        IconButton(frame.ResultOptionsButton)
        local ic = frame.ResultOptionsButton.icon
        if ic then
            ic:SetTexture(ARROW)
            if ic.SetTexCoord then ic:SetTexCoord(0, 1, 0, 1) end
            if ic.SetRotation then ic:SetRotation(0) end
            ic:SetSize(13, 13)
            ic:SetVertexColor(S.palette.hover[1], S.palette.hover[2], S.palette.hover[3])
        end
    end
    if frame.AddonListFrame and frame.AddonListFrame.ScrollFrame then
        S.ScrollBar(frame.AddonListFrame.ScrollFrame.ScrollBar)
    end
    local cat = frame.CategoryFrame
    if cat then
        if cat.NewButton then S.Button(cat.NewButton) end
        if cat.SelectAllButton then S.Button(cat.SelectAllButton) end
        if cat.ClearSelectionButton then S.Button(cat.ClearSelectionButton) end
        if cat.ScrollFrame then S.ScrollBar(cat.ScrollFrame.ScrollBar) end
        if cat.NewButton and cat.SelectAllButton and cat.ClearSelectionButton then
            cat.NewButton:ClearAllPoints()
            cat.NewButton:SetHeight(20)
            cat.NewButton:SetPoint("BOTTOMLEFT", cat.SelectAllButton, "TOPLEFT", 0, 2)
            cat.NewButton:SetPoint("BOTTOMRIGHT", cat.ClearSelectionButton, "TOPRIGHT", 0, 2)
        end
    end
    if _G.HybridScrollFrame_CreateButtons then
        hooksecurefunc("HybridScrollFrame_CreateButtons", ReskinItems)
    end
    if frame.AddonListFrame and frame.AddonListFrame.ScrollFrame then
        ReskinItems(frame.AddonListFrame.ScrollFrame, "SimpleAddonManagerAddonItem")
    end
    if cat and cat.ScrollFrame then ReskinItems(cat.ScrollFrame, "SimpleAddonManagerCategoryItem") end
end

local function Skin()
    local f = _G.SimpleAddonManager
    if not f then return end
    if f.Initialize then hooksecurefunc(f, "Initialize", ReskinModules) end
    S.StripTextures(f, true)

    for _, key in ipairs({ "NineSlice", "Bg", "TopTileStreaks", "TitleContainer" }) do
        if f[key] then S.StripTextures(f[key], true) end
    end
    if f.Inset then
        S.StripTextures(f.Inset, true)
        if f.Inset.NineSlice then S.StripTextures(f.Inset.NineSlice, true) end
        S.Inset(f.Inset)
    end
    S.Backdrop(f)
    if f.CloseButton then S.CloseButton(f.CloseButton) end
    HookEDDM()
    SkinEDDMLists()
end

S:Register("SimpleAddonManager", Skin, "SimpleAddonManager")
