-- ╔══════════════════════════════════════════════════════════╗
-- ║  PartyPotionsBar.lua                                     ║
-- ║  Purpose: one party member's potion bar.                 ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- Each of the two timer slots has a face: the bar's art in a clip frame that
-- hangs from a gate bar's fill edge, a cover that drains the fill, and a
-- strip of time labels. The slot's values may be secret: they reach only
-- SetValue and SetAlpha, no gate, cover or fill is read back, and every fill
-- texture an anchor uses is fetched in New. The one read is the bar's own
-- position and scale, to seat the time window and the names; the position is
-- secret only when the box hangs from a frame with secret anchoring, and then
-- the last seat stays.

---@class KE
local KE = select(2, ...)

local CreateFrame = CreateFrame
local GetPhysicalScreenSize = GetPhysicalScreenSize
local issecretvalue = issecretvalue
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
-- client draws one empty with the value above it. The gate spans two of the
-- pos bar's ranges at twice its height, so its edge sits where a one-range
-- gate's would but stays inside the range for the slot's whole life.
-- The gate hangs from the visibility bar's edge, which a hidden slot lifts
-- until the gate's bottom is above the row, so a hidden face is off the row by
-- position too, and the Ready clip below the gate's edge covers the row
-- exactly when no face does. Values 0 and 1 sit inside the bar's range, never
-- on its ends.
local function PlaceGate(c, f, ready, style, bottom, height)
    local cd, h = c.cd, style.height
    local jump = h + 2
    local lift = (cd + CDRules.Unit(cd) + 1) * jump + h
    f.vis:ClearAllPoints()
    f.vis:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 0, -lift)
    f.vis:SetSize(1, 3 * lift)
    f.gate:ClearAllPoints()
    f.gate:SetPoint("BOTTOMLEFT", f.visFill, "BOTTOMLEFT", 0, bottom * jump)
    f.gate:SetSize(1, 2 * height * jump)
    f.clip:ClearAllPoints()
    f.clip:SetPoint("BOTTOMLEFT", f.gateFill, "TOPLEFT", 0, -1)
    f.clip:SetPoint("TOPLEFT", f.gateFill, "TOPLEFT", 0, (cd - 1) * jump + h + 1)
    f.clip:SetWidth(style.width)
    ready:ClearAllPoints()
    ready:SetPoint("TOPLEFT", f.gateFill, "TOPLEFT", 0, -1)
    ready:SetSize(style.width, 3 * lift + height * jump)
end

local function NewArt(parent)
    local art = CreateFrame("Frame", nil, parent)
    art.icon = art:CreateTexture(nil, "ARTWORK")
    KE:ApplyIconZoom(art.icon)
    -- A frame, not a backing: the drained part shows what is behind the bar.
    art.edges = {}
    for i = 1, 4 do
        art.edges[i] = art:CreateTexture(nil, "BACKGROUND")
        art.edges[i]:SetColorTexture(0, 0, 0, 1)
    end
    art.area = art:CreateTexture(nil, "BACKGROUND")
    -- Under the fill only, so a fill below full opacity still sits on black.
    art.back = art:CreateTexture(nil, "BACKGROUND")
    art.back:SetColorTexture(0, 0, 0, 1)
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
    c.readyClip = {}
    local holder = c
    for k = 1, 2 do
        c.readyClip[k] = CreateFrame("Frame", nil, holder)
        c.readyClip[k]:SetClipsChildren(true)
        holder = c.readyClip[k]
    end
    c.ready = NewArt(holder)
    c.ready:SetAllPoints(c)
    c.ready:Hide()
    c.readyText = c.ready.top:CreateFontString(nil, "OVERLAY")
    c.readyText:SetJustifyH("RIGHT")
    c.face = {}
    for k = 1, 2 do
        local f = { gate = NewBar(c, "VERTICAL"), vis = NewBar(c, "VERTICAL") }
        f.gateFill = f.gate:GetStatusBarTexture()
        f.vis:SetReverseFill(true)
        f.vis:SetMinMaxValues(-1, 2)
        f.visFill = f.vis:GetStatusBarTexture()
        f.clip = CreateFrame("Frame", nil, c)
        f.clip:SetClipsChildren(true)
        f.clip:SetAlpha(0)
        f.art = NewArt(f.clip)
        f.art:SetAllPoints(c)
        f.cover = NewBar(f.art, "HORIZONTAL")
        f.cover:SetReverseFill(true)
        f.coverFill = f.cover:GetStatusBarTexture()
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

local function PlaceEdges(art, px)
    local edges = art.edges
    for i = 1, 4 do edges[i]:ClearAllPoints() end
    edges[1]:SetPoint("TOPLEFT", art, "TOPLEFT")
    edges[1]:SetPoint("BOTTOMRIGHT", art, "TOPRIGHT", 0, -px)
    edges[2]:SetPoint("TOPLEFT", art, "BOTTOMLEFT", 0, px)
    edges[2]:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT")
    edges[3]:SetPoint("TOPLEFT", art, "TOPLEFT")
    edges[3]:SetPoint("BOTTOMRIGHT", art, "BOTTOMLEFT", px, 0)
    edges[4]:SetPoint("TOPLEFT", art, "TOPRIGHT", -px, 0)
    edges[4]:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT")
end

-- Frame, icon, fill and name. The icon sits inside the frame at the left end,
-- right against the area the fill drains across. reserve keeps the name clear
-- of the text on the right. The name hangs top pixels below the area's top,
-- level with the timer window: centered in an odd-height area it starts on a
-- half pixel, and under the sliding clip it then jumps a pixel every second.
local function PlaceName(art, y)
    art.name:SetPoint("TOPLEFT", art.area, "TOPLEFT", TEXT_PAD, y)
    art.name:SetPoint("TOPRIGHT", art.area, "TOPRIGHT", art.nameRight, y)
end

local function Paint(art, style, e, fill, scale, nameColor, px, reserve, top)
    local inner = style.height - 2 * px
    PlaceEdges(art, px)
    art.icon:ClearAllPoints()
    art.icon:SetPoint("TOPLEFT", art, "TOPLEFT", px, -px)
    art.icon:SetSize(inner, inner)
    art.icon:SetTexture(e.texture)
    art.area:ClearAllPoints()
    art.area:SetPoint("TOPLEFT", art, "TOPLEFT", inner + px, -px)
    art.area:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", -px, px)
    art.fill:ClearAllPoints()
    art.fill:SetAllPoints(art.area)
    art.back:ClearAllPoints()
    art.back:SetAllPoints(art.fill)
    art.fill:SetColorTexture(fill[1] * scale, fill[2] * scale, fill[3] * scale, fill[4] or 1)
    KE:ApplyFontToText(art.name, style.fontName, style.textSize, style.outline)
    art.name:SetTextColor(nameColor[1], nameColor[2], nameColor[3], 1)
    art.nameRight = -(TEXT_PAD + reserve)
    art.name:ClearAllPoints()
    PlaceName(art, -top * px)
    art.name:SetText(e.name)
end

-- Look and text are applied every time; the strips move only when the font,
-- size or length changed. The cover is the drained part, drawn in the
-- background color. The fill ends at its edge, so nothing but the cover sits
-- behind the drained part.
function Bar.Dress(c, style, e)
    local px = KE:GetPixelSize()
    local fill, fillScale, bg, bgScale, nameColor, bgAlpha = Rules.Colors(style, e.color)
    local font, size, outline = style.fontName, style.textSize, style.outline
    c:SetSize(style.width, style.height)
    c.cd, c.placed = e.cd, true
    local bottom, height = CDRules.StripBar(e.cd, CDRules.Unit(e.cd))
    local timerWidth = Cell.TextWidth(font, size, outline, "00:00") + TIMER_PAD
    local step, line = Cell.LineMetrics(font, size, outline)
    local winPx, raise, top = Rules.Window((style.height - 2 * px) / px, math_min(line, step) / px)
    c.nameY, c.nameLift, c.nameSeat = -top * px, style.height - (top + 1) * px, nil
    Paint(c.ready, style, e, fill, fillScale, nameColor, px, Cell.TextWidth(font, size, outline, "Ready"), top)
    KE:ApplyFontToText(c.readyText, font, size, outline)
    c.readyText:SetText("Ready")
    c.readyText:SetTextColor(1, 1, 1, 1)
    c.readyText:ClearAllPoints()
    c.readyText:SetPoint("TOPRIGHT", c.ready.area, "TOPRIGHT", -TEXT_PAD, -top * px)
    local level = c:GetFrameLevel()
    for k = 1, 2 do c.readyClip[k]:SetFrameLevel(level + 1) end
    c.ready:SetFrameLevel(level + 1)
    c.ready.top:SetFrameLevel(level + 2)
    for k = 1, 2 do
        local f = c.face[k]
        Paint(f.art, style, e, fill, fillScale, nameColor, px, style.timer and timerWidth or 0, top)
        PlaceGate(c, f, c.readyClip[k], style, bottom, height)
        f.cover:ClearAllPoints()
        f.cover:SetAllPoints(f.art.area)
        f.cover:SetStatusBarColor(bg[1] * bgScale, bg[2] * bgScale, bg[3] * bgScale, bgAlpha)
        f.art.fill:ClearAllPoints()
        f.art.fill:SetPoint("TOPLEFT", f.art.area, "TOPLEFT")
        f.art.fill:SetPoint("BOTTOMRIGHT", f.coverFill, "BOTTOMLEFT")
        f.win:ClearAllPoints()
        f.win:SetPoint("BOTTOMRIGHT", f.art.area, "BOTTOMRIGHT", -TEXT_PAD / 2, raise * px)
        f.win:SetSize(timerWidth, winPx * px)
        f.winY, f.winLift, f.seat, f.timer = raise * px, (raise + 1) * px, nil, style.timer
        f.win:SetShown(style.timer)
        f.clip:SetFrameLevel(level + 3)
        f.art:SetFrameLevel(level + 4)
        f.cover:SetFrameLevel(level + 5)
        f.art.top:SetFrameLevel(level + 6)
        f.win:SetFrameLevel(level + 6)
        f.text:SetFrameLevel(level + 7)
    end
    local pitch, _, _, spacing = Cell.StripLayout(font, size, outline)
    local sig = table_concat({ tostring(font), tostring(size), tostring(outline), e.cd, step, line, pitch }, "|")
    if c.sig == sig then return end
    c.sig = sig
    local text = Cell.StripText(e.cd)
    for k = 1, 2 do
        local f = c.face[k]
        f.pos:ClearAllPoints()
        f.pos:SetPoint("BOTTOMRIGHT", f.win, "BOTTOMRIGHT", 0, bottom * pitch)
        f.pos:SetSize(1, height * pitch)
        KE:ApplyFontToText(f.strip, font, size, outline)
        f.strip:SetTextColor(1, 1, 1, 1)
        f.strip:SetSpacing(spacing)
        f.strip:SetText(text)
    end
end

-- The time window's bottom and the names' tops sit a quarter of a screen pixel
-- above the pixel grid. On the grid itself a text under the sliding clip
-- rounds up or down from second to second and jumps a pixel. Each is re-placed
-- only when the bar has moved off its seat.
local function Seat(c, f)
    local y = c:GetBottom()
    local scale = c:GetEffectiveScale()
    local _, height = GetPhysicalScreenSize()
    if f.timer then
        local seat = CDRules.Seat(y, -f.winLift, scale, height, f.seat, issecretvalue)
        if seat then
            f.win:SetPoint("BOTTOMRIGHT", f.art.area, "BOTTOMRIGHT", -TEXT_PAD / 2, f.winY + seat)
            f.seat = seat
        end
    end
    local seat = CDRules.Seat(y, -c.nameLift, scale, height, c.nameSeat, issecretvalue)
    if not seat then return end
    local nameY = c.nameY + seat
    for k = 1, 2 do PlaceName(c.face[k].art, nameY) end
    PlaceName(c.ready, nameY)
    c.readyText:SetPoint("TOPRIGHT", c.ready.area, "TOPRIGHT", -TEXT_PAD, nameY)
    c.nameSeat = seat
end

local function FaceRange(c, k, sl, u, n)
    local f = c.face[k]
    local m = CDRules.RangeMin(sl, u, n)
    f.pos:SetMinMaxValues(m, m + 1)
    f.cover:SetMinMaxValues(Rules.CoverRange(sl, u, c.cd, n))
    f.gate:SetMinMaxValues(m, m + 2)
    if f.winY then Seat(c, f) end
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
    f.vis:SetValue(sl.v)
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
    for k = 1, 2 do
        c.face[k].vis:SetValue(0)
        c.face[k].clip:SetAlpha(0)
    end
end

function Bar.SetReady(c, on)
    c.ready:SetShown(on == true)
end
