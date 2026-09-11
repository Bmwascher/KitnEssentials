local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local next = next
local hooksecurefunc = hooksecurefunc

local function HandleHeader(header)
    if S.data(header).skinned then return end
    S.data(header).skinned = true
    if header.HighlightMiddle then header.HighlightMiddle:SetAlpha(0) end
    if header.HighlightLeft then header.HighlightLeft:SetAlpha(0) end
    if header.HighlightRight then header.HighlightRight:SetAlpha(0) end
    if header.Middle then header.Middle:Hide() end
    if header.Left then header.Left:Hide() end
    if header.Right then header.Right:Hide() end
    S.Button(header)
end

local function HandleSettingItem(item)
    if S.data(item).skinned then return end
    S.data(item).skinned = true

    if item.Bar then
        S.StripTextures(item.Bar)

        S.StatusBar(item.Bar)
        if item.Bar.SetStatusBarTexture then
            item.Bar:SetStatusBarTexture("Interface\\AddOns\\KitnEssentials\\Media\\Statusbars\\KitnEssentials")
        end
    end
    local icon = item.Icon
    if icon then
        local highlight = item.Highlight
        if highlight then
            highlight:SetColorTexture(1, 1, 1, 0.25)
            highlight:SetAllPoints(icon)
        elseif item.CreateTexture then

            local hl = item:CreateTexture(nil, "HIGHLIGHT")
            hl:SetColorTexture(1, 1, 1, 0.25)
            hl:SetAllPoints(icon)
        end
        S.Icon(icon, true)
    end
end

local function HandleSettingItemPool(pool)
    for frame in pool:EnumerateActive() do
        HandleSettingItem(frame)
    end
end

local hookedItemPools = {}
local function RefreshLayout()
    local viewer = _G.CooldownViewerSettings
    local content = viewer and viewer.CooldownScroll and viewer.CooldownScroll.Content
    if not content then return end
    for _, child in next, { content:GetChildren() } do
        if child.Header then HandleHeader(child.Header) end
        local itemPool = child.itemPool
        if itemPool and not hookedItemPools[itemPool] then
            hookedItemPools[itemPool] = true
            HandleSettingItemPool(itemPool)
            hooksecurefunc(itemPool, "Acquire", HandleSettingItemPool)
        end
    end
end

local function KeepTabAnchored(tab, _, _, _, x, y)
    local a = S.data(tab).tabAnchor
    if not a then return end
    if x == a.x and y == a.y then return end
    tab:ClearAllPoints()
    tab:SetPoint(a.point, a.rel, a.relPoint, a.x, a.y)
end

local function PositionTabIcon(icon, point)
    if point == "CENTER" then return end
    icon:ClearAllPoints()
    icon:SetPoint("CENTER")
end

-- Fallback for a build without the parentArray.
local function TabList(viewer)
    local tabs = viewer.TabButtons
    if type(tabs) == "table" and #tabs > 0 then return tabs end
    return { viewer.SpellsTab, viewer.AurasTab, viewer.GroupBuffsTab }
end

local function HandleAbilityTabs(viewer)
    local prev
    for i, tab in ipairs(TabList(viewer)) do
        local d = S.data(tab)

        local a
        if i == 1 or not prev then
            a = { point = "TOPLEFT", rel = viewer, relPoint = "TOPRIGHT", x = 1, y = 0 }
        else
            a = { point = "TOP", rel = prev, relPoint = "BOTTOM", x = 0, y = -1 }
        end
        d.tabAnchor = a
        tab:SetSize(30, 40)
        tab:ClearAllPoints()
        tab:SetPoint(a.point, a.rel, a.relPoint, a.x, a.y)

        if not d.tabSkinned then
            d.tabSkinned = true
            S.Backdrop(tab)
            hooksecurefunc(tab, "SetPoint", KeepTabAnchored)
            if tab.Icon then
                hooksecurefunc(tab.Icon, "SetPoint", PositionTabIcon)
                hooksecurefunc(tab.Icon, "SetSize", function(ic, w, h)
                    if (w ~= 20 or h ~= 20) and not S.data(ic).sizing then
                        S.data(ic).sizing = true
                        ic:SetSize(20, 20)
                        S.data(ic).sizing = nil
                    end
                end)
                S.Icon(tab.Icon)
            end
            S.HoverWash(tab)
        end

        if tab.Icon then
            tab.Icon:ClearAllPoints()
            tab.Icon:SetPoint("CENTER")
            tab.Icon:SetSize(20, 20)
        end
        if tab.Background then tab.Background:SetAlpha(0) end
        if tab.SelectedTexture then
            tab.SelectedTexture:SetDrawLayer("BACKGROUND", 1)
            tab.SelectedTexture:SetColorTexture(S.palette.brand[1], S.palette.brand[2], S.palette.brand[3], 0.18)
            local tbd = S.GetBackdrop(tab)
            tab.SelectedTexture:ClearAllPoints()
            tab.SelectedTexture:SetPoint("TOPLEFT", tbd or tab, "TOPLEFT", 1, -1)
            tab.SelectedTexture:SetPoint("BOTTOMRIGHT", tbd or tab, "BOTTOMRIGHT", -1, 1)
        end

        S.KillSideTabArt(tab)
        prev = tab
    end
end

local function Skin()
    local viewer = _G.CooldownViewerSettings
    if viewer then
        S.Frame(viewer)
        if viewer.SearchBox then
            S.EditBox(viewer.SearchBox)

            viewer.SearchBox:SetHeight(20)
        end
        if viewer.CooldownScroll then S.ScrollBar(viewer.CooldownScroll.ScrollBar) end
        S.Button(viewer.UndoButton)
        if viewer.LayoutDropdown then pcall(S.DropDown, viewer.LayoutDropdown) end
        HandleAbilityTabs(viewer)
        RefreshLayout()
        hooksecurefunc(viewer, "RefreshLayout", RefreshLayout)
    end

    local import = _G.CooldownViewerImportLayoutDialog
    if import then
        if import.Border then import.Border:Hide() end
        S.Template(import, "Window")
        S.Button(import.AcceptButton)
        S.Button(import.CancelButton)
        if import.ImportBox then S.EditBox(import.ImportBox) end
        if import.LayoutNameEditBox then S.EditBox(import.LayoutNameEditBox) end
    end

    local layout = _G.CooldownViewerLayoutDialog
    if layout then
        if layout.Border then layout.Border:Hide() end
        S.Template(layout, "Window")
        S.Button(layout.AcceptButton)
        S.Button(layout.CancelButton)
        if layout.LayoutNameEditBox then S.EditBox(layout.LayoutNameEditBox) end
    end
end

S:Register("Blizzard_CooldownViewer", Skin, "CooldownManager")
