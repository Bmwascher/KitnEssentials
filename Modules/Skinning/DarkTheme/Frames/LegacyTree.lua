local KE = select(2, ...)
local S = KE.Skins
local _G = _G

local LINE_ALPHA = 0.15

-- Drawn on the divider's own frame, which sits beneath the tree cards. The
-- left edge sits on the frame's center: a 1 px line centered there would
-- straddle two pixels.
local function DividerLine(divider)
    if not divider or S.data(divider).keLine then return end
    if divider.VerticalDivider then divider.VerticalDivider:SetAlpha(0) end
    local line = divider:CreateTexture(nil, "OVERLAY")
    line:SetColorTexture(1, 1, 1, LINE_ALPHA)
    line:SetPoint("TOPLEFT", divider, "TOP")
    line:SetPoint("BOTTOMLEFT", divider, "BOTTOM")
    line:SetWidth(KE:GetPixelSize())
    S.data(divider).keLine = line
end

function S.LegacyTreePage()
    local page = _G.LegacySystemFrame and _G.LegacySystemFrame.TreePage
    if not page or S.data(page).skinned then return end
    S.FontStrings(page)
    if page.Background then page.Background:SetAlpha(0) end
    DividerLine(page.VerticalDivider)
    local traits = page.LegacyTreeTraitPanel
    if traits then
        S.Button(traits.ApplyButton)
        S.EditBox(traits.SearchBox)
    end
    S.data(page).skinned = true
end
