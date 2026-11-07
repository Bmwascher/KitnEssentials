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
        S.SetFont(list.NoResultsText)
    end
    if page.DetailPane then S.ScrollBar(page.DetailPane.ScrollBar) end
    S.Vanish(page, PAGE_ART)
    SkinPointSummary(page.LegacyChallengePointSummary)
    FlattenDivider(page.VerticalDivider)
    S.data(page).skinned = true
end
