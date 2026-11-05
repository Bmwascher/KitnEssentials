-- ╔══════════════════════════════════════════════════════════╗
-- ║  RareAlertCard.lua                                       ║
-- ║  Module: Rare Alert                                      ║
-- ║  Purpose: Builds and paints the alert card from values   ║
-- ║           it is given. Reads no unit or vignette.        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)
if not KitnEssentials then return end

---@type RareAlert
local RA = KitnEssentials:GetModule("RareAlert")

local floor = math.floor
local min = math.min
local format = string.format

local CARD_WIDTH, CARD_HEIGHT = 360, 76
local TEXT_LEFT, TEXT_RIGHT = 80, 68
local COLUMN_WIDTH, COLUMN_INSET = 64, 4
local TEXT_WIDTH = CARD_WIDTH - TEXT_LEFT - TEXT_RIGHT
local NEW_TAG_ROOM = 30

local WHITE = "Interface\\Buttons\\WHITE8X8"
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local CHIP_RING = "Interface\\AddOns\\KitnEssentials\\Media\\Cursor\\circle_thin.tga"
local ARROW_ATLAS = "Navigation-Tracked-Arrow"
local PIN_ATLAS = "Waypoint-MapPin-Tracked"
local STAR_ATLAS = "VignetteKill"
local STAR_ELITE_ATLAS = "VignetteKillElite"

local SLIDE_DISTANCE = 10
local SLIDE_TIME = 0.32
local PULSE_TIME = 0.55

local RING_RARE = { 0.784, 0.808, 0.839 }
local RING_ELITE = { 1, 0.82, 0 }
local TAPPED_STRIP = { 0.902, 0.302, 0.302 }
local TAPPED_BORDER = { 0.478, 0.122, 0.122 }
local MUTED = 0.604
local DIM_TIME_BAR = 0.333
local DIM_CHIP = 0.45
local DEAD_ALPHA = 0.8

local THIRD_TEXT = {
    targeted = "Targeted: closing",
    tapped = "You would get no loot",
    dead = "Closing",
    left = "Left your minimap",
    combat = "In combat: click works when it ends",
    far = "Too far to target: follow the arrow",
    click = "Click to target",
}
local THIRD_DEFAULT = { 0.71, 0.71, 0.71 }
local THIRD_COLORS = {
    targeted = { 0.498, 0.851, 0.561 },
    tapped = { 1, 0.42, 0.42 },
    dead = { MUTED, MUTED, MUTED },
    combat = { 1, 0.702, 0.278 },
}

local DOT = " |cff777777\194\183|r "

---------------------------------------------------------------------------------
-- Holder
---------------------------------------------------------------------------------
function RA:ApplyHolder()
    local scale = self.db.Size / 100
    self.holder:SetSize(CARD_WIDTH * scale, CARD_HEIGHT * scale)
    KE:ApplyFramePosition(self.holder, self.db.Position, self.db)
end

function RA:CreateHolder()
    if self.holder then return end
    self.holder = CreateFrame("Frame", "KE_RareAlertHolder", UIParent)
    self:ApplyHolder()
end

---------------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------------
local function NewEdge(parent, size)
    local edge = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    edge:SetAllPoints(parent)
    edge:SetBackdrop({ edgeFile = WHITE, edgeSize = size })
    edge:Hide()
    return edge
end

local function NewBar(parent, maxValue)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(WHITE)
    bar:SetMinMaxValues(0, maxValue)
    bar:SetValue(maxValue)
    return bar
end

local function NewText(card, justify)
    local text = card:CreateFontString(nil, "OVERLAY")
    text:SetJustifyH(justify)
    text:SetWordWrap(false)
    return text
end

local function NewRightColumnText(card, top)
    local text = NewText(card, "CENTER")
    text:SetWidth(COLUMN_WIDTH)
    text:SetPoint("TOPRIGHT", card, "TOPRIGHT", -COLUMN_INSET, top)
    return text
end

local function ZoomModel(model)
    model:SetPortraitZoom(1)
end

local function BuildPortrait(card, parts)
    local portrait = CreateFrame("Frame", nil, card, "BackdropTemplate")
    portrait:SetSize(68, 68)
    portrait:SetPoint("TOPLEFT", card, "TOPLEFT", 4, -4)
    portrait:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    portrait:SetBackdropColor(0.063, 0.071, 0.078, 1)
    parts.portrait = portrait

    local model = CreateFrame("PlayerModel", nil, portrait)
    model:SetPoint("TOPLEFT", portrait, "TOPLEFT", 1, -1)
    model:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", -1, 1)
    model:SetScript("OnModelLoaded", ZoomModel)
    model:Hide()
    parts.model = model

    local badge = CreateFrame("Frame", nil, portrait)
    badge:SetAllPoints(portrait)
    badge:SetFrameLevel(model:GetFrameLevel() + 1)
    local star = badge:CreateTexture(nil, "OVERLAY")
    star:SetSize(18, 18)
    star:SetPoint("BOTTOMLEFT", badge, "BOTTOMLEFT", 2, 2)
    parts.star = star
end

local function BuildChip(card, parts)
    local chip = CreateFrame("Frame", nil, card)
    chip:SetSize(40, 40)
    -- Its right edge is the pin's left edge, so the secure button covers all of it.
    chip:SetPoint("TOPRIGHT", card, "TOPRIGHT", -16, -5)
    chip:Hide()
    parts.chip = chip

    local fill = chip:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(chip)
    fill:SetColorTexture(0, 0, 0, 0.85)
    local mask = chip:CreateMaskTexture()
    mask:SetAllPoints(chip)
    mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    fill:AddMaskTexture(mask)

    local ring = chip:CreateTexture(nil, "BORDER")
    ring:SetAllPoints(chip)
    ring:SetTexture(CHIP_RING)
    ring:SetVertexColor(0.227, 0.227, 0.227, 1)

    local arrow = chip:CreateTexture(nil, "ARTWORK")
    arrow:SetSize(30, 30)
    arrow:SetPoint("CENTER", chip, "CENTER", 0, 0)
    arrow:SetAtlas(ARROW_ATLAS)
    parts.arrow = arrow
end

local function BuildAnimations(card, parts)
    local slide = card:CreateAnimationGroup()
    local lift = slide:CreateAnimation("Translation")
    lift:SetOffset(0, SLIDE_DISTANCE)
    lift:SetDuration(0)
    lift:SetOrder(1)
    local drop = slide:CreateAnimation("Translation")
    drop:SetOffset(0, -SLIDE_DISTANCE)
    drop:SetDuration(SLIDE_TIME)
    drop:SetSmoothing("OUT")
    drop:SetOrder(2)
    parts.slide = slide

    local pulse = NewEdge(card, 2)
    local glow = pulse:CreateAnimationGroup()
    for order = 1, 4 do
        local fade = glow:CreateAnimation("Alpha")
        local rising = order % 2 == 1
        fade:SetFromAlpha(rising and 0 or 1)
        fade:SetToAlpha(rising and 1 or 0)
        fade:SetDuration(PULSE_TIME / 2)
        fade:SetOrder(order)
    end
    glow:SetScript("OnFinished", function() pulse:Hide() end)
    parts.pulse = pulse
    parts.glow = glow
end

function RA:BuildCard()
    if self.card then return end

    local card = CreateFrame("Frame", nil, self.holder, "BackdropTemplate")
    card:SetSize(CARD_WIDTH, CARD_HEIGHT)
    card:SetPoint("CENTER", self.holder, "CENTER", 0, 0)
    card:EnableMouse(true)
    card:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and RA.rare then RA:CloseCard() end
    end)
    card:Hide()
    self.card = card

    local parts = {}
    self.parts = parts

    BuildPortrait(card, parts)
    BuildChip(card, parts)

    local strip = card:CreateTexture(nil, "ARTWORK")
    strip:SetWidth(3)
    strip:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
    strip:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 0, 0)
    strip:SetColorTexture(TAPPED_STRIP[1], TAPPED_STRIP[2], TAPPED_STRIP[3], 1)
    strip:Hide()
    parts.strip = strip

    local tapBorder = NewEdge(card, 1)
    tapBorder:SetBackdropBorderColor(TAPPED_BORDER[1], TAPPED_BORDER[2], TAPPED_BORDER[3], 1)
    parts.tapBorder = tapBorder

    local name = NewText(card, "LEFT")
    name:SetPoint("TOPLEFT", card, "TOPLEFT", TEXT_LEFT, -5)
    name:SetPoint("TOPRIGHT", card, "TOPRIGHT", -TEXT_RIGHT, -5)
    parts.name = name

    local sub = NewText(card, "LEFT")
    sub:SetPoint("TOPLEFT", card, "TOPLEFT", TEXT_LEFT, -28)
    sub:SetPoint("TOPRIGHT", card, "TOPRIGHT", -TEXT_RIGHT, -28)
    sub:SetTextColor(0.812, 0.812, 0.812)
    parts.sub = sub

    parts.third = NewText(card, "LEFT")

    local newTag = NewText(card, "LEFT")
    newTag:SetTextColor(1, 0.82, 0)
    newTag:Hide()
    parts.newTag = newTag

    local health = NewBar(card, 100)
    health:SetHeight(5)
    health:SetPoint("TOPLEFT", card, "TOPLEFT", TEXT_LEFT, -64)
    health:SetPoint("TOPRIGHT", card, "TOPRIGHT", -TEXT_RIGHT, -64)
    health:SetStatusBarColor(0.788, 0.208, 0.184)
    local healthBack = health:CreateTexture(nil, "BACKGROUND")
    healthBack:SetAllPoints(health)
    healthBack:SetColorTexture(0.165, 0.063, 0.063, 1)
    health:Hide()
    parts.health = health

    parts.yards = NewRightColumnText(card, -46)
    local percent = NewRightColumnText(card, -60)
    percent:SetTextColor(0.816, 0.816, 0.816)
    percent:Hide()
    parts.percent = percent

    local pin = CreateFrame("Button", nil, card)
    pin:SetSize(16, 16)
    pin:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, -1)
    pin:SetNormalAtlas(PIN_ATLAS)
    pin:SetScript("OnClick", function() RA:PlacePin() end)
    pin:Hide()
    parts.pin = pin

    local timeBar = NewBar(card, 1)
    timeBar:SetHeight(2)
    timeBar:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 1, 1)
    timeBar:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -1, 1)
    parts.timeBar = timeBar

    BuildAnimations(card, parts)
    self:ApplyCardLook()
    -- SetText raises an error on a font string with no font yet.
    newTag:SetText("NEW")
end

---------------------------------------------------------------------------------
-- Look
---------------------------------------------------------------------------------
function RA:ApplyCardLook()
    local db, parts = self.db, self.parts
    self.card:SetScale(db.Size / 100)
    KE:ApplyBackdrop(self.card, db.Backdrop)

    local face, size, outline = db.FontFace, db.FontSize, db.FontOutline
    KE:ApplyFontToText(parts.name, face, size, outline)
    KE:ApplyFontToText(parts.sub, face, size - 4, outline)
    KE:ApplyFontToText(parts.third, face, size - 5, outline)
    KE:ApplyFontToText(parts.newTag, face, 11, outline)
    KE:ApplyFontToText(parts.yards, face, size - 4, outline)
    KE:ApplyFontToText(parts.percent, face, size - 6, outline)

    self:PaintAccent(self.rare)
end

-- Level and quality colors are semantic and do not follow the accent.
function RA:PaintAccent(view)
    local parts = self.parts
    local r, g, b = KE:GetAccentColor("theme")
    parts.pulse:SetBackdropBorderColor(r, g, b, 1)
    if view and (view.dead or view.left) then
        parts.timeBar:SetStatusBarColor(DIM_TIME_BAR, DIM_TIME_BAR, DIM_TIME_BAR)
    else
        parts.timeBar:SetStatusBarColor(r, g, b)
    end
end

function RA:OnThemeChanged()
    if self.parts then self:PaintAccent(self.rare) end
end

---------------------------------------------------------------------------------
-- Paint
---------------------------------------------------------------------------------
function RA:PaintIdentity(view)
    local parts = self.parts
    parts.name:SetText(view.name)
    parts.star:SetAtlas(view.elite and STAR_ELITE_ATLAS or STAR_ATLAS)
    local ring = view.elite and RING_ELITE or RING_RARE
    parts.portrait:SetBackdropBorderColor(ring[1], ring[2], ring[3], 1)
end

local function SubLine(view)
    local line = view.elite and "Rare Elite" or "Rare"
    if view.levelText then
        local color = view.levelColor
        local level = color and (KE:ColorCode(color.r, color.g, color.b) .. view.levelText .. "|r")
            or view.levelText
        line = level .. " " .. line
    end
    if view.dead then
        line = line .. DOT .. "|cff9a9a9aDead|r"
    elseif view.tapped then
        line = line .. DOT .. "|cffff6b6bTapped by someone else|r"
    end
    return line
end

local function PaintThirdLine(card, parts, view)
    local key = RA.ThirdLine(view)
    local third, newTag = parts.third, parts.newTag
    local isNew = key == "drop" and view.drop.new and true or false

    third:ClearAllPoints()
    third:SetPoint("TOPLEFT", card, "TOPLEFT", TEXT_LEFT, -45)
    third:SetPoint("TOPRIGHT", card, "TOPRIGHT", -(TEXT_RIGHT + (isNew and NEW_TAG_ROOM or 0)), -45)

    if key == "drop" then
        local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[view.drop.quality]
        third:SetText(view.drop.name)
        if color then
            third:SetTextColor(color.r, color.g, color.b)
        else
            third:SetTextColor(1, 1, 1)
        end
    else
        local color = THIRD_COLORS[key] or THIRD_DEFAULT
        third:SetText(THIRD_TEXT[key])
        third:SetTextColor(color[1], color[2], color[3])
    end

    newTag:ClearAllPoints()
    if isNew then
        local width = min(third:GetStringWidth(), TEXT_WIDTH - NEW_TAG_ROOM)
        newTag:SetPoint("LEFT", third, "LEFT", width + 4, 0)
    end
    newTag:SetShown(isNew)
end

function RA:PaintState(view)
    local card, parts = self.card, self.parts
    if view.dead or view.left then
        parts.name:SetTextColor(MUTED, MUTED, MUTED)
    else
        parts.name:SetTextColor(1, 1, 1)
    end
    parts.sub:SetText(SubLine(view))
    PaintThirdLine(card, parts, view)

    local redEdge = view.tapped and not view.dead and true or false
    parts.strip:SetShown(redEdge)
    parts.tapBorder:SetShown(redEdge)

    card:SetAlpha(view.dead and DEAD_ALPHA or 1)
    parts.model:SetDesaturation(view.dead and 1 or 0)
    parts.chip:SetAlpha(view.left and DIM_CHIP or 1)
    self:PaintAccent(view)
end

-- A nil rotation means no position: no chip, and "Nearby" where the yards go.
function RA:PaintBearing(rotation, yards)
    local parts = self.parts
    local chip, label = parts.chip, parts.yards
    if not self.db.ShowDirection then
        chip:Hide()
        label:Hide()
        self.lastYards = nil
        return
    end
    if not rotation then
        chip:Hide()
        label:ClearAllPoints()
        label:SetPoint("TOPRIGHT", self.card, "TOPRIGHT", -COLUMN_INSET, -22)
        label:SetText("Nearby")
        label:Show()
        self.lastYards = nil
        return
    end
    if not chip:IsShown() then
        chip:Show()
        label:ClearAllPoints()
        label:SetPoint("TOPRIGHT", self.card, "TOPRIGHT", -COLUMN_INSET, -46)
        label:Show()
    end
    parts.arrow:SetRotation(rotation)
    local whole = floor(yards + 0.5)
    if whole ~= self.lastYards then
        self.lastYards = whole
        label:SetText(format("%d yd", whole))
    end
end

-- The value may be secret: the bar takes it as it is, and the percent shows
-- only when it reads plain.
function RA:PaintHealth(value)
    local parts = self.parts
    local bar, percent = parts.health, parts.percent
    if not self.db.ShowHealth then
        bar:Hide()
        percent:Hide()
        return
    end
    if KE:IsSecretValue(value) then
        bar:SetValue(value)
        bar:Show()
        percent:Hide()
        return
    end
    if not value then
        bar:Hide()
        percent:Hide()
        return
    end
    bar:SetValue(value)
    bar:Show()
    percent:SetText(format("%d%%", floor(value + 0.5)))
    percent:Show()
end

function RA:PaintTimeBar(fraction)
    self.parts.timeBar:SetValue(fraction)
end

function RA:PaintPin(shown)
    self.parts.pin:SetShown(shown)
end

-- A unit token draws the live creature, an npc id draws it by id, and the star
-- stands alone when neither draws.
function RA:SetPortrait(unit, npc)
    local model = self.parts.model
    model:ClearModel()
    if unit then
        model:Show()
        model:SetUnit(unit)
    elseif npc then
        model:Show()
        model:SetCreature(npc)
    else
        model:Hide()
    end
end

function RA:PlayArrival()
    local parts = self.parts
    parts.slide:Stop()
    parts.slide:Play()
    parts.glow:Stop()
    parts.pulse:Show()
    parts.glow:Play()
end

function RA:HideCard()
    local parts = self.parts
    if not parts then return end
    parts.slide:Stop()
    parts.glow:Stop()
    parts.pulse:Hide()
    parts.model:ClearModel()
    parts.model:Hide()
    self.card:Hide()
end
