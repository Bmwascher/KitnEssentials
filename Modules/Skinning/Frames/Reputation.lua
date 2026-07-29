local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local hooksecurefunc = hooksecurefunc

local WHITE = "Interface\\Buttons\\WHITE8x8"
local REP_ROW_FONT = 12

local ourAtlas = {
    Soulbinds_Collection_CategoryHeader_Expand = true,
    Soulbinds_Collection_CategoryHeader_Collapse = true,
}
local function UpdateCollapse(texture, atlas)
    if not atlas or not ourAtlas[atlas] then
        local parent = texture:GetParent()
        if parent and parent.IsCollapsed and parent:IsCollapsed() then
            texture:SetAtlas("Soulbinds_Collection_CategoryHeader_Expand")
        else
            texture:SetAtlas("Soulbinds_Collection_CategoryHeader_Collapse")
        end
    end
end

local DAMPEN = 0.55
local function DampenBarColor(bar, r, g, b, a)
    if bar.aeDampening then return end
    bar.aeDampening = true
    bar:SetStatusBarColor(r * DAMPEN, g * DAMPEN, b * DAMPEN, a or 1)
    bar.aeDampening = false
end

local function UpdateToggleAtlas(button)
    local header = (button.GetHeader and button:GetHeader()) or button:GetParent()
    local collapsed = header and header.IsCollapsed and header:IsCollapsed()
    local atlas = collapsed and "Soulbinds_Collection_CategoryHeader_Expand"
        or "Soulbinds_Collection_CategoryHeader_Collapse"
    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }) do
        local t = button[getter] and button[getter](button)
        if t then t:SetAtlas(atlas) end
    end
end

local function FixCollapseChevron(child)
    if not child.Right then return end
    UpdateCollapse(child.Right)
    hooksecurefunc(child.Right, "SetAtlas", UpdateCollapse)

    child.Right:Show()
    if not child.Right.aeKeepShown then
        hooksecurefunc(child.Right, "Hide", function(t) t:Show() end)
        child.Right.aeKeepShown = true
    end
    if child.HighlightRight then
        UpdateCollapse(child.HighlightRight)
        hooksecurefunc(child.HighlightRight, "SetAtlas", UpdateCollapse)
    end
end

local function StyleEntry(child)
    if not child or child.aeRepRow then return end
    S.RowHover(child)
    S.StripTextures(child)
    FixCollapseChevron(child)

    if child.Right then
        local hbd = S.Backdrop(child)
        if hbd then
            hbd:ClearAllPoints()
            hbd:SetPoint("TOPLEFT", child, "TOPLEFT", 1, -1)
            hbd:SetPoint("BOTTOMRIGHT", child, "BOTTOMRIGHT", -1, 1)
        end
    end
    local tcb = child.ToggleCollapseButton
    if tcb then
        if tcb.RefreshIcon and not tcb.aeToggleHooked then
            hooksecurefunc(tcb, "RefreshIcon", UpdateToggleAtlas)
            tcb.aeToggleHooked = true
        end
        UpdateToggleAtlas(tcb)
    end
    local content = child.Content
    local bar = content and content.ReputationBar
    if bar then
        S.StripTextures(bar)
        if bar.SetStatusBarTexture then bar:SetStatusBarTexture(WHITE) end
        S.StatusBar(bar)

        if not bar.aeDampHooked then
            hooksecurefunc(bar, "SetStatusBarColor", DampenBarColor)
            bar.aeDampHooked = true
            local r, g, b, a = bar:GetStatusBarColor()
            if r then DampenBarColor(bar, r, g, b, a) end
        end

        S.FontStrings(content, REP_ROW_FONT, "")
        S.FontStrings(bar, REP_ROW_FONT, "")
    end
    child.aeRepRow = true
end

local function Skin()
    local frame = _G.ReputationFrame
    if not frame then return end
    S.StripTextures(frame)
    if frame.filterDropdown then S.DropDown(frame.filterDropdown) end
    if frame.ScrollBar then S.ScrollBar(frame.ScrollBar) end
    if frame.ScrollBox then S.HookScrollBox(frame.ScrollBox, StyleEntry) end

    local detail = frame.ReputationDetailFrame
    if detail then
        S.StripTextures(detail)
        S.Backdrop(detail)
        if detail.CloseButton then S.CloseButton(detail.CloseButton) end
        if detail.ScrollingDescriptionScrollBar then S.ScrollBar(detail.ScrollingDescriptionScrollBar) end
        for _, cb in ipairs({ "AtWarCheckBox", "InactiveCheckBox", "MainScreenCheckBox" }) do
            if detail[cb] then S.CheckBox(detail[cb]) end
        end
    end
end

S:Register("Blizzard_UIPanels_Game", Skin, "Reputation")
