-- ╔══════════════════════════════════════════════════════════╗
-- ║  PartyCooldownsCell.lua                                  ║
-- ║  Purpose: one cooldown icon: icon, border, the gray      ║
-- ║           cover and the strip of time labels.            ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- Each of the two timer slots has a position bar, whose fill edge carries the
-- strip of labels under a one-line window, and a gate bar, whose fill edge
-- carries the gray cover; a summon cell adds a third bar for its glow window.
-- Their values may be secret, so nothing here reads a bar back or measures a
-- region under them.

---@class KE
local KE = select(2, ...)

local CreateFrame = CreateFrame
local GetPhysicalScreenSize = GetPhysicalScreenSize
local UIParent = UIParent
local issecretvalue = issecretvalue
local math_floor = math.floor
local table_concat = table.concat
local tostring = tostring
local type = type

local Cell = {}
KE.PartyCooldownsCell = Cell

local WHITE = "Interface\\Buttons\\WHITE8X8"
local GRAY = 0.5
local BLACK = { 0, 0, 0, 1 }
local GLOW_OFF = { GlowEnabled = false }

local meter
local metrics = {}
local layouts = {}
local widths = {}
local strips = {}

-- One label per line from cd down to 1, top to bottom. The first blank lines
-- are spaces, which keep the line pitch an empty line might not.
local function StripText(cd, blank)
    blank = blank or 0
    local key = cd .. "|" .. blank
    local text = strips[key]
    if text then return text end
    local lines = {}
    for r = cd, 1, -1 do
        lines[#lines + 1] = r > cd - blank and " " or KE:FormatCountdown(r)
    end
    text = table_concat(lines, "\n")
    strips[key] = text
    return text
end

-- A font string on a frame no secret ever reaches, made on first use.
local function Meter()
    if not meter then
        local host = CreateFrame("Frame", nil, UIParent)
        host:SetSize(1, 1)
        host:SetPoint("CENTER")
        host:SetAlpha(0)
        meter = host:CreateFontString(nil, "OVERLAY")
        meter:SetPoint("CENTER")
    end
    return meter
end

-- The distance between two lines and the height of one, measured on the meter
-- with the given line spacing; nil when the measure fails.
local function Measure(fontName, size, outline, spacing)
    local m = Meter()
    KE:ApplyFontToText(m, fontName, size, outline)
    m:SetSpacing(spacing)
    m:SetText("0")
    local one = m:GetStringHeight()
    m:SetText("0\n0\n0\n0\n0\n0\n0\n0\n0")
    local nine = m:GetStringHeight()
    m:SetSpacing(0)
    if not KE:IsSecretValue(one) and not KE:IsSecretValue(nine)
        and type(one) == "number" and type(nine) == "number" and one > 0 and nine > one then
        return (nine - one) / 8, one
    end
end

-- Screen pixels per unit on the meter, read live: the UI scale can change
-- during login after a measure, before the shared pixel size catches up.
local function MeterScale()
    local _, height = GetPhysicalScreenSize()
    local scale = Meter():GetEffectiveScale()
    if issecretvalue(scale) or type(scale) ~= "number" or scale <= 0 or type(height) ~= "number" or height <= 0 then
        return 1
    end
    return scale * height / 768
end

-- The client draws text in whole screen pixels, so a measure holds only for
-- the UI scale it was taken at.
local function FontKey(fontName, size, outline)
    return tostring(fontName) .. "|" .. tostring(size) .. "|" .. tostring(outline) .. "|" .. MeterScale()
end

-- The distance between two strip lines and the height of one, per font, and
-- cached.
local function LineMetrics(fontName, size, outline)
    local key = FontKey(fontName, size, outline)
    local known = metrics[key]
    if known then return known[1], known[2] end
    local step, line = Measure(fontName, size, outline, 0)
    if not step then step, line = size, size end
    metrics[key] = { step, line }
    return step, line
end

-- The width of text in a font, measured on the meter and cached.
function Cell.TextWidth(fontName, size, outline, text)
    local key = FontKey(fontName, size, outline) .. "|" .. text
    local known = widths[key]
    if known then return known end
    local m = Meter()
    KE:ApplyFontToText(m, fontName, size, outline)
    m:SetText(text)
    local width = m:GetStringWidth()
    if KE:IsSecretValue(width) or type(width) ~= "number" or width <= 0 then width = size * #text * 0.6 end
    widths[key] = width
    return width
end

-- A strip spaced so each label sits centered in its own line, with the margin
-- blank above and below: the line pitch, the line height, the margin and the
-- spacing to set on the strip. The pitch is measured with that spacing.
function Cell.StripLayout(fontName, size, outline)
    local key = FontKey(fontName, size, outline)
    local known = layouts[key]
    if known then return known[1], known[2], known[3], known[4] end
    local step, line = LineMetrics(fontName, size, outline)
    local margin = KE.PartyCooldownsRules.StripMargin(line)
    local spacing = 2 * margin
    -- The client draws the strip's lines a whole number of screen pixels
    -- apart; a bar stepping by a measure a fraction off that climbs against
    -- the drawn labels a little each second.
    local ppu = MeterScale()
    local pitch = math_floor((Measure(fontName, size, outline, spacing) or step + spacing) * ppu + 0.5) / ppu
    layouts[key] = { pitch, line, margin, spacing }
    return pitch, line, margin, spacing
end

Cell.StripText = StripText
Cell.LineMetrics = LineMetrics

local function NewBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(WHITE)
    bar:SetStatusBarColor(0, 0, 0, 0)
    bar:SetOrientation("VERTICAL")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    return bar
end

function Cell.New(parent)
    local c = CreateFrame("Frame", nil, parent)
    c:EnableMouse(false)
    c:Hide()
    c.border = c:CreateTexture(nil, "BACKGROUND")
    c.border:SetAllPoints(c)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    KE:ApplyIconZoom(c.icon)
    c.clip = CreateFrame("Frame", nil, c)
    c.clip:SetClipsChildren(true)
    c.win = CreateFrame("Frame", nil, c)
    c.win:SetClipsChildren(true)
    c.pos, c.gate, c.edge, c.text, c.strip, c.veil, c.gray = {}, {}, {}, {}, {}, {}, {}
    c.act = {}
    for k = 1, 2 do
        local pos, gate = NewBar(c), NewBar(c)
        local text = CreateFrame("Frame", nil, c.win)
        text:SetAllPoints(c.win)
        text:SetAlpha(0)
        local strip = text:CreateFontString(nil, "OVERLAY")
        strip:SetJustifyH("CENTER")
        strip:SetPoint("BOTTOM", pos:GetStatusBarTexture(), "TOP", 0, 0)
        local act = text:CreateFontString(nil, "OVERLAY")
        act:SetJustifyH("CENTER")
        c.act[k] = act
        local veil = CreateFrame("Frame", nil, c.clip)
        veil:SetClipsChildren(true)
        veil:SetAlpha(0)
        local gray = veil:CreateTexture(nil, "ARTWORK")
        gray:SetAllPoints(c.clip)
        gray:SetDesaturated(true)
        gray:SetVertexColor(GRAY, GRAY, GRAY)
        KE:ApplyIconZoom(gray)
        c.pos[k], c.gate[k], c.edge[k] = pos, gate, gate:GetStatusBarTexture()
        c.text[k], c.strip[k], c.veil[k], c.gray[k] = text, strip, veil, gray
    end
    return c
end

-- The hosts play only while the cell shows: a clipped or hidden animation
-- still costs.
local function PlayGlow(c)
    local glow = c:IsVisible() and c.glowOn and c.glowSettings or GLOW_OFF
    for k = 1, 2 do KE.AuraGlow.Configure(c.glowHost[k], glow) end
end

-- A summon's glow, made on first need: per slot a third bar whose edge carries
-- a clipping window, so the glow shows only during the active seconds.
local function GlowParts(c)
    c.glowBar, c.glowWin, c.glowHost = {}, {}, {}
    for k = 1, 2 do
        local win = CreateFrame("Frame", nil, c)
        win:SetClipsChildren(true)
        win:SetAlpha(0)
        local host = KE.AuraGlow.CreateHost(win, GLOW_OFF)
        host:ClearAllPoints()
        host:SetAllPoints(c)
        c.glowBar[k], c.glowWin[k], c.glowHost[k] = NewBar(c), win, host
    end
    c:SetScript("OnShow", PlayGlow)
    c:SetScript("OnHide", PlayGlow)
end

local function DressGlow(c, glow, active, level)
    local on = active > 0 and glow ~= nil and glow.GlowEnabled == true
    if on and not c.glowWin then
        GlowParts(c)
        c.sig = nil
    end
    if not (on or c.glowOn) then return end
    for k = 1, 2 do
        c.glowWin[k]:SetFrameLevel(level + 3)
        c.glowHost[k]:SetFrameLevel(level + 3)
        if not on then c.glowWin[k]:SetAlpha(0) end
    end
    c.glowOn, c.glowSettings = on, glow
    PlayGlow(c)
end

-- Colors, icon and text are applied every time; the bars move only when the
-- font, size or length changed.
function Cell.Dress(c, style, e)
    local size = style.size
    -- A login scale change can land after the shared pixel size was cached.
    KE:UpdatePixelCache()
    local px = KE:GetPixelSize()
    local color = style.colors[e.kind] or BLACK
    c:SetSize(size, size)
    c.border:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    c.icon:ClearAllPoints()
    c.icon:SetPoint("TOPLEFT", c, "TOPLEFT", px, -px)
    c.icon:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -px, px)
    c.icon:SetTexture(e.texture)
    local level = c:GetFrameLevel()
    c.clip:SetFrameLevel(level + 1)
    c.win:SetFrameLevel(level + 4)
    for k = 1, 2 do
        c.veil[k]:SetFrameLevel(level + 2)
        c.text[k]:SetFrameLevel(level + 5)
        c.gray[k]:SetTexture(e.texture)
        c.text[k]:SetShown(style.showText == true)
    end
    local pitch, line, _, spacing = Cell.StripLayout(style.fontName, style.fontSize, style.outline)
    local rules = KE.PartyCooldownsRules
    local cd = e.cd
    local active = rules.ActiveSeconds(e.active, cd)
    DressGlow(c, style.glow, active, level)
    local sig = table_concat({ tostring(style.fontName), tostring(style.fontSize), tostring(style.outline),
        cd, active, size, px, pitch, line }, "|")
    if c.sig == sig then return end
    c.sig = sig
    local bottom, height = rules.StripBar(cd, rules.Unit(cd))
    -- One step of the gray cover is more than the icon's height, so the
    -- cover is fully off the icon one second after zero.
    local jump = size + 2
    c.clip:ClearAllPoints()
    c.clip:SetPoint("TOPLEFT", c, "TOPLEFT", px, -px)
    c.clip:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -px, px)
    c.win:ClearAllPoints()
    c.win:SetPoint("CENTER", c, "CENTER", 0, 0)
    c.win:SetSize(size + 6, pitch)
    -- The label's line box sits centered in the window, whatever the measure.
    local center = math_floor((pitch - line) / 2 + 0.5)
    c.seat, c.seatBase = nil, pitch / 2 - center
    for k = 1, 2 do
        local pos, gate, strip, veil, edge = c.pos[k], c.gate[k], c.strip[k], c.veil[k], c.edge[k]
        local act = c.act[k]
        pos:ClearAllPoints()
        pos:SetPoint("BOTTOM", c.win, "BOTTOM", 0, bottom * pitch + center)
        pos:SetSize(1, height * pitch)
        KE:ApplyFontToText(strip, style.fontName, style.fontSize, style.outline)
        strip:SetTextColor(1, 1, 1, 1)
        strip:SetSpacing(spacing)
        strip:SetText(StripText(cd, active))
        -- The active labels sit where the cooldown strip's blank lines are, so
        -- the window shows them for the first active seconds.
        KE:ApplyFontToText(act, style.fontName, style.fontSize, style.outline)
        act:SetTextColor(1, 1, 1, 1)
        act:SetSpacing(spacing)
        act:ClearAllPoints()
        act:SetPoint("BOTTOM", pos:GetStatusBarTexture(), "TOP", 0, (cd - active) * pitch)
        act:SetText(active > 0 and StripText(active) or "")
        gate:ClearAllPoints()
        gate:SetPoint("BOTTOM", c.clip, "BOTTOM", 0, bottom * jump)
        gate:SetSize(1, height * jump)
        veil:ClearAllPoints()
        veil:SetPoint("BOTTOM", edge, "TOP", 0, -1)
        -- Lowered by the active seconds, so the cover starts once they end.
        veil:SetPoint("TOP", edge, "TOP", 0, (cd - 1 - active) * jump + size + 1)
        veil:SetWidth(size)
    end
    if not c.glowWin then return end
    local glowJump, low, high, width = rules.GlowWindow(size, px, cd, active)
    for k = 1, 2 do
        local bar, win = c.glowBar[k], c.glowWin[k]
        local glowEdge = bar:GetStatusBarTexture()
        bar:ClearAllPoints()
        bar:SetPoint("BOTTOM", c.clip, "BOTTOM", 0, bottom * glowJump)
        bar:SetSize(1, height * glowJump)
        win:ClearAllPoints()
        win:SetPoint("BOTTOM", glowEdge, "TOP", 0, low)
        win:SetPoint("TOP", glowEdge, "TOP", 0, high)
        win:SetWidth(width)
    end
end

-- The range is opened to 0..1 first, so the stamp is stored whole before the
-- bars are re-ranged to this second.
function Cell.Write(c, k, sl, u, n)
    local pos, gate = c.pos[k], c.gate[k]
    pos:SetMinMaxValues(0, 1)
    pos:SetValue(sl.c)
    gate:SetMinMaxValues(0, 1)
    gate:SetValue(sl.c)
    c.text[k]:SetAlpha(sl.v)
    c.veil[k]:SetAlpha(sl.v)
    if c.glowOn then
        local bar = c.glowBar[k]
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(sl.c)
        c.glowWin[k]:SetAlpha(sl.v)
    end
    Cell.Range(c, k, sl, u, n)
end

function Cell.Range(c, k, sl, u, n)
    local m = KE.PartyCooldownsRules.RangeMin(sl, u, n)
    c.pos[k]:SetMinMaxValues(m, m + 1)
    c.gate[k]:SetMinMaxValues(m, m + 1)
    if c.glowOn then c.glowBar[k]:SetMinMaxValues(m, m + 1) end
end

-- Run after a placement, a write and each second's re-range, so a moved cell
-- or a scale change is caught; while the seat holds it only reads. Reads the
-- cell, never a bar.
function Cell.Seat(c)
    local _, y = c:GetCenter()
    local _, height = GetPhysicalScreenSize()
    local seat = KE.PartyCooldownsRules.Seat(y, c.seatBase, c:GetEffectiveScale(), height, c.seat, issecretvalue)
    if not seat then return end
    c.win:SetPoint("CENTER", c, "CENTER", 0, seat)
    c.seat = seat
end

function Cell.Clear(c)
    c:Hide()
    for k = 1, 2 do
        c.text[k]:SetAlpha(0)
        c.veil[k]:SetAlpha(0)
        if c.glowWin then c.glowWin[k]:SetAlpha(0) end
    end
end
