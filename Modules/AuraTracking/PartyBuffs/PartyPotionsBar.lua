-- ╔══════════════════════════════════════════════════════════╗
-- ║  PartyPotionsBar.lua                                     ║
-- ║  Purpose: one party member's potion bar.                 ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- Each of the two timer slots has a face: the bar's art in a clip frame that
-- hangs from a gate bar's fill edge, a cover that drains the class fill, and a
-- strip of time labels. The slot's values may be secret: they reach only
-- SetValue and SetAlpha, nothing here reads a bar back, and every fill texture
-- an anchor uses is fetched in New.

---@class KE
local KE = select(2, ...)

local CreateFrame = CreateFrame
local math_min = math.min
local table_concat = table.concat
local tostring = tostring

local Rules = KE.PartyPotionsRules
local CDRules = KE.PartyCooldownsRules
local Cell = KE.PartyCooldownsCell

local Bar = {}
KE.PartyPotionsBar = Bar
-- A bar shows no active state, so its slot takes no overlay.
Bar.overlay = false

local WHITE = "Interface\\Buttons\\WHITE8X8"
local GRAY = { 0.5, 0.5, 0.5 }
local DIM = 0.75
local BG = 0.15
local TEXT_PAD = 4
-- The timer window's width beyond its widest label, "00:00".
local TIMER_PAD = 6

local function NewBar(parent, orientation)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(WHITE)
    bar:SetStatusBarColor(0, 0, 0, 0)
    bar:SetOrientation(orientation)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    return bar
end

-- The face shows while its slot has time left: the clip hangs from the gate's
-- fill edge, which moves one row height and 2 more each second, so the clip is
-- off the row one second after zero. A narrow range cannot gate it: the
-- client draws one empty with the value above it.
local function PlaceGate(c, f, style, bottom, height)
    local cd, h = c.cd, style.height
    local jump = h + 2
    f.gate:ClearAllPoints()
    f.gate:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 0, bottom * jump)
    f.gate:SetSize(1, height * jump)
    f.clip:ClearAllPoints()
    f.clip:SetPoint("BOTTOMLEFT", f.gateFill, "TOPLEFT", 0, -1)
    f.clip:SetPoint("TOPLEFT", f.gateFill, "TOPLEFT", 0, (cd - 1) * jump + h + 1)
    f.clip:SetWidth(style.width)
end

local function NewArt(parent)
    local art = CreateFrame("Frame", nil, parent)
    art.icon = art:CreateTexture(nil, "ARTWORK")
    KE:ApplyIconZoom(art.icon)
    art.border = art:CreateTexture(nil, "BACKGROUND")
    art.border:SetColorTexture(0, 0, 0, 1)
    art.fill = art:CreateTexture(nil, "BORDER")
    -- Above the cover, so the drained part never hides the name.
    art.top = CreateFrame("Frame", nil, art)
    art.top:SetAllPoints(art)
    art.name = art.top:CreateFontString(nil, "OVERLAY")
    art.name:SetJustifyH("LEFT")
    art.name:SetWordWrap(false)
    return art
end

function Bar.New(parent)
    local c = CreateFrame("Frame", nil, parent)
    c:EnableMouse(false)
    c:Hide()
    c.ready = NewArt(c)
    c.ready:SetAllPoints(c)
    c.ready:Hide()
    c.readyText = c.ready.top:CreateFontString(nil, "OVERLAY")
    c.readyText:SetJustifyH("RIGHT")
    c.face = {}
    for k = 1, 2 do
        local f = { gate = NewBar(c, "VERTICAL") }
        f.gateFill = f.gate:GetStatusBarTexture()
        f.clip = CreateFrame("Frame", nil, c)
        f.clip:SetClipsChildren(true)
        f.clip:SetAlpha(0)
        f.art = NewArt(f.clip)
        f.art:SetAllPoints(c)
        f.cover = NewBar(f.art, "HORIZONTAL")
        f.cover:SetReverseFill(true)
        f.win = CreateFrame("Frame", nil, f.art)
        f.win:SetClipsChildren(true)
        f.pos = NewBar(f.art, "VERTICAL")
        f.text = CreateFrame("Frame", nil, f.win)
        f.text:SetAllPoints(f.win)
        f.strip = f.text:CreateFontString(nil, "OVERLAY")
        f.strip:SetJustifyH("RIGHT")
        f.strip:SetPoint("BOTTOMRIGHT", f.pos:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
        c.face[k] = f
    end
    c.placed = false
    return c
end

-- Border, icon, class fill and name. The icon sits inside the border at the
-- left end, a border line between it and the fill. reserve keeps the name
-- clear of the text on the right.
local function Paint(art, style, e, color, px, reserve)
    local inner = style.height - 2 * px
    local left = px
    art.border:ClearAllPoints()
    art.border:SetAllPoints(art)
    art.icon:SetShown(style.icon)
    if style.icon then
        art.icon:ClearAllPoints()
        art.icon:SetPoint("TOPLEFT", art.border, "TOPLEFT", px, -px)
        art.icon:SetSize(inner, inner)
        art.icon:SetTexture(e.texture)
        left = inner + 2 * px
    end
    art.fill:ClearAllPoints()
    art.fill:SetPoint("TOPLEFT", art.border, "TOPLEFT", left, -px)
    art.fill:SetPoint("BOTTOMRIGHT", art.border, "BOTTOMRIGHT", -px, px)
    art.fill:SetColorTexture(color[1] * DIM, color[2] * DIM, color[3] * DIM, 1)
    KE:ApplyFontToText(art.name, style.fontName, style.textSize, style.outline)
    art.name:SetTextColor(1, 1, 1, 1)
    art.name:ClearAllPoints()
    art.name:SetPoint("LEFT", art.fill, "LEFT", TEXT_PAD, 0)
    art.name:SetPoint("RIGHT", art.fill, "RIGHT", -(TEXT_PAD + reserve), 0)
    art.name:SetText(e.name)
end

-- Look and text are applied every time; the strips move only when the font,
-- size or length changed. The cover is drawn in the background color, so the
-- drained part of the bar shows the background.
function Bar.Dress(c, style, e)
    local px = KE:GetPixelSize()
    local color = e.color or GRAY
    local font, size, outline = style.fontName, style.textSize, style.outline
    c:SetSize(style.width, style.height)
    c.cd, c.placed = e.cd, true
    local bottom, height = CDRules.StripBar(e.cd, CDRules.Unit(e.cd))
    local timerWidth = Cell.TextWidth(font, size, outline, "00:00") + TIMER_PAD
    Paint(c.ready, style, e, color, px, Cell.TextWidth(font, size, outline, "Ready"))
    KE:ApplyFontToText(c.readyText, font, size, outline)
    c.readyText:SetText("Ready")
    c.readyText:SetTextColor(1, 1, 1, 1)
    c.readyText:ClearAllPoints()
    c.readyText:SetPoint("RIGHT", c.ready.fill, "RIGHT", -TEXT_PAD, 0)
    local level = c:GetFrameLevel()
    c.ready:SetFrameLevel(level + 1)
    c.ready.top:SetFrameLevel(level + 2)
    for k = 1, 2 do
        local f = c.face[k]
        Paint(f.art, style, e, color, px, style.timer and timerWidth or 0)
        PlaceGate(c, f, style, bottom, height)
        f.cover:ClearAllPoints()
        f.cover:SetAllPoints(f.art.fill)
        f.cover:SetStatusBarColor(color[1] * BG, color[2] * BG, color[3] * BG, 1)
        f.win:ClearAllPoints()
        f.win:SetPoint("RIGHT", f.art.fill, "RIGHT", -TEXT_PAD / 2, 0)
        f.win:SetShown(style.timer)
        f.clip:SetFrameLevel(level + 3)
        f.art:SetFrameLevel(level + 4)
        f.cover:SetFrameLevel(level + 5)
        f.art.top:SetFrameLevel(level + 6)
        f.win:SetFrameLevel(level + 6)
        f.text:SetFrameLevel(level + 7)
    end
    local step, line = Cell.LineMetrics(font, size, outline)
    local sig = table_concat({ tostring(font), tostring(size), tostring(outline), e.cd, step, line }, "|")
    if c.sig == sig then return end
    c.sig = sig
    local text = Cell.StripText(e.cd)
    for k = 1, 2 do
        local f = c.face[k]
        f.win:SetSize(timerWidth, math_min(line, step))
        f.pos:ClearAllPoints()
        f.pos:SetPoint("BOTTOMRIGHT", f.win, "BOTTOMRIGHT", 0, bottom * step)
        f.pos:SetSize(1, height * step)
        KE:ApplyFontToText(f.strip, font, size, outline)
        f.strip:SetTextColor(1, 1, 1, 1)
        f.strip:SetText(text)
    end
end

local function FaceRange(c, k, sl, u, n)
    local f = c.face[k]
    local m = CDRules.RangeMin(sl, u, n)
    f.pos:SetMinMaxValues(m, m + 1)
    f.cover:SetMinMaxValues(Rules.CoverRange(sl, u, c.cd, n))
    f.gate:SetMinMaxValues(m, m + 1)
end

-- Each range is opened to 0..1 first, so the stamp is stored whole before it
-- is re-ranged to this second.
function Bar.Write(c, k, sl, u, n)
    local f = c.face[k]
    f.pos:SetMinMaxValues(0, 1)
    f.pos:SetValue(sl.c)
    f.cover:SetMinMaxValues(0, 1)
    f.cover:SetValue(sl.c)
    f.gate:SetMinMaxValues(0, 1)
    f.gate:SetValue(sl.c)
    f.clip:SetAlpha(sl.v)
    FaceRange(c, k, sl, u, n)
end

function Bar.Range(c, k, sl, u, n)
    FaceRange(c, k, sl, u, n)
end

-- A cleared row is hidden, and Stack gives it no place.
function Bar.Clear(c)
    c:Hide()
    c.placed = false
    for k = 1, 2 do c.face[k].clip:SetAlpha(0) end
end

function Bar.SetReady(c, on)
    c.ready:SetShown(on == true)
end
