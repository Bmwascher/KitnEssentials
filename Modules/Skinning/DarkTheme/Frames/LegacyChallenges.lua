local KE = select(2, ...)
local S = KE.Skins
local _G = _G

local FLAT_TEX = "Interface\\Buttons\\WHITE8x8"
local BAR_ART = { "ProgressBarFrame" }
local BAR_BACKGROUND_ART = { "ProgressBarBackground" }
local PAGE_ART = { "Background" }

-- Written onto the existing fill region: the Rewards page holds that region
-- in its mask list.
local function FlatBar(bar)
    if not bar or S.data(bar).keLegacyBar then return end
    S.data(bar).keLegacyBar = true
    S.Vanish(bar, BAR_ART)
    local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if fill then fill:SetTexture(FLAT_TEX) end
    if bar.SetStatusBarColor then
        local c = S.palette.progress
        bar:SetStatusBarColor(c[1], c[2], c[3], c[4])
    end
    S.StatusBar(bar)
    S.SetFont(bar.Text)
end

-- The one place a Legacy points shield is treated; the Tree page's shield
-- goes through it too, so a new crown look is an edit here.
function S.LegacyPointShield(shield)
    if not shield or S.data(shield).keLegacyShield then return end
    S.data(shield).keLegacyShield = true
    S.SetFont(shield.Points)
end

local function SkinPointSummary(summary)
    if not summary then return end
    S.Vanish(summary, BAR_BACKGROUND_ART)
    FlatBar(summary.PointsBar)
    S.LegacyPointShield(summary.Shield)
end

-- The divider's only region is an unnamed atlas texture.
local function FlattenDivider(divider)
    if not divider or S.data(divider).keLegacyLine then return end
    local art = divider:GetRegions()
    if art and art.SetAlpha then art:SetAlpha(0) end
    local line = divider:CreateTexture(nil, "OVERLAY")
    local b = S.borderColor
    line:SetColorTexture(b[1], b[2], b[3], b[4])
    line:SetPoint("TOP")
    line:SetPoint("BOTTOM")
    line:SetWidth(KE:GetPixelSize())
    S.data(divider).keLegacyLine = line
end

local EXPAND_ATLAS = "Soulbinds_Collection_CategoryHeader_Expand"
local COLLAPSE_ATLAS = "Soulbinds_Collection_CategoryHeader_Collapse"

-- The engine shows a HIGHLIGHT-layer texture on mouseover, so no scripts.
local function AddHover(button, plate)
    if not plate or S.data(button).keLegacyHover then return end
    local hl = button:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture(FLAT_TEX)
    local c = S.palette.hover
    hl:SetVertexColor(c[1], c[2], c[3])
    hl:SetAlpha(c[4])
    S.InsetToEdge(hl, plate)
    S.data(button).keLegacyHover = hl
end

local function PaintCollapseIcon(button, collapsed)
    local atlas = collapsed and EXPAND_ATLAS or COLLAPSE_ATLAS
    if button.Icon then button.Icon:SetAtlas(atlas, true) end
    button:SetHighlightAtlas(atlas)
end

-- A white wash over the plate, not a second plate color: it keeps expansion
-- rows lighter than leaf rows whatever backdrop color the player picks.
local PARENT_LIFT_A = 0.05

-- A pooled row can come back as the other kind, so the lift is set on every
-- refresh along with the selection fill.
local function PaintCategoryRow(row)
    local d = S.data(row)
    local fill, lift = d.keLegacyFill, d.keLegacyLift
    if not (fill and lift) then return end
    fill:SetShown(row.selected and true or false)
    lift:SetShown(row.collapsable and true or false)
end

-- Alpha, not a strip: RefreshCardArt re-sets both atlases on every refresh.
local function StyleCategoryRow(row)
    local d = S.data(row)
    if d.keLegacyRow then return end
    d.keLegacyRow = true
    local normal = row.GetNormalTexture and row:GetNormalTexture()
    if normal then normal:SetAlpha(0) end
    local highlight = row.GetHighlightTexture and row:GetHighlightTexture()
    if highlight then highlight:SetAlpha(0) end
    local plate = S.Backdrop(row)
    if not plate then return end
    AddHover(row, plate)
    local lift = row:CreateTexture(nil, "BACKGROUND", nil, 0)
    lift:SetColorTexture(1, 1, 1)
    lift:SetAlpha(PARENT_LIFT_A)
    S.InsetToEdge(lift, plate)
    local fill = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    fill:SetTexture(FLAT_TEX)
    S.InsetToEdge(fill, plate)
    S.PaintBrand(fill, "SetVertexColor", S.palette.selectedA)
    d.keLegacyFill, d.keLegacyLift = fill, lift
    if row.RefreshCardArt then hooksecurefunc(row, "RefreshCardArt", PaintCategoryRow) end
    local toggle = row.CollapseButton
    if toggle and toggle.UpdateCollapsedState then
        hooksecurefunc(toggle, "UpdateCollapsedState", PaintCollapseIcon)
        PaintCollapseIcon(toggle, toggle.collapsed)
    end
    PaintCategoryRow(row)
end

local CARD_ART = {
    "Background", "BackgroundTop", "BackgroundMiddle", "BackgroundBottom",
    "SelectedOverlay", "TitleBar",
}
local TITLE_COLORS = {
    account = { 0, 0.6, 1 },
    accountDimmed = { 0, 0.3, 0.5 },
}
local TRACKED_SIZE = 20

-- Dimmed is RefreshStateArt's own rule: not completed and not selected.
function S._LegacyCardLook(selected, completed, accountWide)
    local titleKey
    if accountWide then
        titleKey = (not completed and not selected) and "accountDimmed" or "account"
    end
    return selected and true or false, titleKey
end

-- RefreshStateArt is the last call of Init, so this runs after every state
-- change; UpdatePlusMinusArt would otherwise put the red button back.
local function PaintCard(card)
    if not card.id then return end
    local plate = S.data(card).keLegacyPlate
    if not plate then return end
    local selected = card.IsSelected and card:IsSelected()
    local brandBorder, titleKey = S._LegacyCardLook(selected, card.completed, card.accountWide)
    if brandBorder then
        S.PaintBrand(plate, "SetBackdropBorderColor", 1)
    else
        S.ForgetBrand(plate)
        local b = S.borderColor
        plate:SetBackdropBorderColor(b[1], b[2], b[3], b[4])
    end
    local title = titleKey and TITLE_COLORS[titleKey]
    if title and card.Label then card.Label:SetTextColor(title[1], title[2], title[3]) end
    if card.PlusMinus then
        card.PlusMinus:SetAtlas(card.collapsed and EXPAND_ATLAS or COLLAPSE_ATLAS)
    end
end

local function StyleCard(card)
    local d = S.data(card)
    if d.keLegacyCard then return end
    d.keLegacyCard = true
    S.Vanish(card, CARD_ART)
    local icon = card.Icon
    if icon then
        if icon.frame then icon.frame:SetAlpha(0) end
        S.Icon(icon.texture, true)
    end
    local shield = card.Shield
    if shield and shield.CheckBackground then shield.CheckBackground:SetAlpha(0) end
    -- The template's box is 15px; S.CheckBox insets its plate by 4 on each side.
    if card.Tracked then
        S.CheckBox(card.Tracked)
        card.Tracked:SetSize(TRACKED_SIZE, TRACKED_SIZE)
    end
    local plate = S.Backdrop(card)
    if not plate then return end
    d.keLegacyPlate = plate
    AddHover(card, plate)
    if card.RefreshStateArt then hooksecurefunc(card, "RefreshStateArt", PaintCard) end
    if card.UpdatePlusMinusArt then hooksecurefunc(card, "UpdatePlusMinusArt", PaintCard) end
    PaintCard(card)
end

function S.LegacyRewardTrackPage()
    local page = _G.LegacySystemFrame and _G.LegacySystemFrame.RewardTrackPage
    if not page or S.data(page).skinned then return end
    S.FontStrings(page)
    local bar = page.LegacyRewardProgressBar
    if bar then S.SetFont(bar.Text) end
    S.data(page).skinned = true
end

function S.LegacyChallengesPage()
    local page = _G.LegacySystemFrame and _G.LegacySystemFrame.ChallengesPage
    if not page or S.data(page).skinned then return end
    S.FontStrings(page)
    local list = page.CategoryList
    if list then
        S.Button(list.FilterDropdown)
        if list.FilterDropdown then S.CloseButton(list.FilterDropdown.ResetButton) end
        S.EditBox(list.SearchBox)
        S.ScrollBar(list.ScrollBar)
        S.HookScrollBox(list.ScrollBox, StyleCategoryRow)
        S.SetFont(list.NoResultsText)
    end
    if page.DetailPane then
        S.ScrollBar(page.DetailPane.ScrollBar)
        S.HookScrollBox(page.DetailPane.ScrollBox, StyleCard)
    end
    S.Vanish(page, PAGE_ART)
    SkinPointSummary(page.LegacyChallengePointSummary)
    FlattenDivider(page.VerticalDivider)
    S.data(page).skinned = true
end
