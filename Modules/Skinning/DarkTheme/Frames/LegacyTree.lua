local KE = select(2, ...)
local S = KE.Skins
local _G = _G
local ipairs = ipairs
local hooksecurefunc = hooksecurefunc

local LINE_ALPHA = 0.15
-- The tree icons are painted discs: this inset keeps the square inscribed in
-- the disc, so no round edge shows inside the border.
local ICON_CROP = 0.146

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

-- Atlas space: the three icons share one sheet. A new atlas resets the crop.
local function CropIcon(button)
    S.CropAtlasEdges(button.NormalTexture, ICON_CROP, ICON_CROP)
    S.CropAtlasEdges(button.PushedTexture, ICON_CROP, ICON_CROP)
end

local function SquareIcon(button)
    if not button or S.data(button).keSquareIcon then return end
    S.data(button).keSquareIcon = true
    local normal, pushed, mask = button.NormalTexture, button.PushedTexture, button.CircleMask
    -- A mask left on would clip the square's corners.
    if mask then
        if normal then normal:RemoveMaskTexture(mask) end
        if pushed then pushed:RemoveMaskTexture(mask) end
    end
    if button.Ring then button.Ring:SetAlpha(0) end
    -- Re-atlased on every selection refresh; the alpha survives it.
    if button.HighlightTexture then button.HighlightTexture:SetAlpha(0) end
    CropIcon(button)
    if normal then
        S.PixelSnap(normal)
        local border = S.Backdrop(normal, -1, true)
        if border then border:SetFrameLevel(button:GetFrameLevel() + 1) end
    end
    if button.SetIconAtlas then hooksecurefunc(button, "SetIconAtlas", CropIcon) end
end

local function SkinSelectedIcon(icon)
    if not icon then return end
    SquareIcon(icon)
    -- A click toggles the checked state, which would draw a round ring.
    if icon.CheckedTexture then icon.CheckedTexture:SetAlpha(0) end
end

function S.LegacyTreePage()
    local page = _G.LegacySystemFrame and _G.LegacySystemFrame.TreePage
    if not page or S.data(page).skinned then return end
    S.FontStrings(page)
    if page.Background then page.Background:SetAlpha(0) end
    DividerLine(page.VerticalDivider)
    local selection = page.LegacyTreeSelectionPanel
    if selection and selection.treeButtons then
        for _, button in ipairs(selection.treeButtons) do SquareIcon(button) end
    end
    local traits = page.LegacyTreeTraitPanel
    if traits then
        S.Button(traits.ApplyButton)
        S.EditBox(traits.SearchBox)
        SkinSelectedIcon(traits.SelectedTreeIcon)
    end
    S.data(page).skinned = true
end
