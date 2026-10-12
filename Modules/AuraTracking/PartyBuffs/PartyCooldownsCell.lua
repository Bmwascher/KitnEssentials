-- ╔══════════════════════════════════════════════════════════╗
-- ║  PartyCooldownsCell.lua                                  ║
-- ║  Purpose: one cooldown icon: icon, border, the gray      ║
-- ║           cover and the strip of time labels.            ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- Each of the two timer slots has a position bar, whose fill edge carries the
-- strip of labels under a one-line window, and a gate bar, whose fill edge
-- carries the gray cover. Their values may be secret, so nothing here reads
-- a bar back or measures a region under them.

---@class KE
local KE = select(2, ...)

local CreateFrame = CreateFrame
local UIParent = UIParent
local math_min = math.min
local table_concat = table.concat
local tostring = tostring
local type = type

local Cell = {}
KE.PartyCooldownsCell = Cell

local WHITE = "Interface\\Buttons\\WHITE8X8"
local GRAY = 0.5
local BLACK = { 0, 0, 0, 1 }

local meter
local metrics = {}
local strips = {}

-- Every label from cd down to 1, one per line, top to bottom, in the core
-- countdown format.
local function StripText(cd)
    local text = strips[cd]
    if text then return text end
    local lines = {}
    for r = cd, 1, -1 do lines[#lines + 1] = KE:FormatCountdown(r) end
    text = table_concat(lines, "\n")
    strips[cd] = text
    return text
end

-- The distance between two strip lines and the height of one, per font.
-- Measured on a frame no secret ever reaches, and cached.
local function LineMetrics(fontName, size, outline)
    local key = tostring(fontName) .. "|" .. tostring(size) .. "|" .. tostring(outline)
    local known = metrics[key]
    if known then return known[1], known[2] end
    if not meter then
        local host = CreateFrame("Frame", nil, UIParent)
        host:SetSize(1, 1)
        host:SetPoint("CENTER")
        host:SetAlpha(0)
        meter = host:CreateFontString(nil, "OVERLAY")
        meter:SetPoint("CENTER")
    end
    KE:ApplyFontToText(meter, fontName, size, outline)
    meter:SetText("0")
    local one = meter:GetStringHeight()
    meter:SetText("0\n0\n0\n0\n0\n0\n0\n0\n0")
    local nine = meter:GetStringHeight()
    local step, line = size, size
    if not KE:IsSecretValue(one) and not KE:IsSecretValue(nine)
        and type(one) == "number" and type(nine) == "number" and one > 0 and nine > one then
        step, line = (nine - one) / 8, one
    end
    metrics[key] = { step, line }
    return step, line
end

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
    for k = 1, 2 do
        local pos, gate = NewBar(c), NewBar(c)
        local text = CreateFrame("Frame", nil, c.win)
        text:SetAllPoints(c.win)
        text:SetAlpha(0)
        local strip = text:CreateFontString(nil, "OVERLAY")
        strip:SetJustifyH("CENTER")
        strip:SetPoint("BOTTOM", pos:GetStatusBarTexture(), "TOP", 0, 0)
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

-- Colors, icon and text are applied every time; the bars move only when the
-- font, size or length changed.
function Cell.Dress(c, style, e)
    local size = style.size
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
    local step, line = LineMetrics(style.fontName, style.fontSize, style.outline)
    local sig = table_concat({ tostring(style.fontName), tostring(style.fontSize), tostring(style.outline),
        e.cd, size, px, step, line }, "|")
    if c.sig == sig then return end
    c.sig = sig
    local rules = KE.PartyCooldownsRules
    local cd = e.cd
    local bottom, height = rules.StripBar(cd, rules.Unit(cd))
    -- One step of the gray cover is more than the icon's height, so the
    -- cover is fully off the icon one second after zero.
    local jump = size + 2
    c.clip:ClearAllPoints()
    c.clip:SetPoint("TOPLEFT", c, "TOPLEFT", px, -px)
    c.clip:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -px, px)
    c.win:ClearAllPoints()
    c.win:SetPoint("CENTER", c, "CENTER", 0, 0)
    c.win:SetSize(size + 6, math_min(line, step))
    for k = 1, 2 do
        local pos, gate, strip, veil, edge = c.pos[k], c.gate[k], c.strip[k], c.veil[k], c.edge[k]
        pos:ClearAllPoints()
        pos:SetPoint("BOTTOM", c.win, "BOTTOM", 0, bottom * step)
        pos:SetSize(1, height * step)
        KE:ApplyFontToText(strip, style.fontName, style.fontSize, style.outline)
        strip:SetTextColor(1, 1, 1, 1)
        strip:SetText(StripText(cd))
        gate:ClearAllPoints()
        gate:SetPoint("BOTTOM", c.clip, "BOTTOM", 0, bottom * jump)
        gate:SetSize(1, height * jump)
        veil:ClearAllPoints()
        veil:SetPoint("BOTTOM", edge, "TOP", 0, -1)
        veil:SetPoint("TOP", edge, "TOP", 0, (cd - 1) * jump + size + 1)
        veil:SetWidth(size)
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
    Cell.Range(c, k, sl, u, n)
end

function Cell.Range(c, k, sl, u, n)
    local m = KE.PartyCooldownsRules.RangeMin(sl, u, n)
    c.pos[k]:SetMinMaxValues(m, m + 1)
    c.gate[k]:SetMinMaxValues(m, m + 1)
end

function Cell.Clear(c)
    c:Hide()
    for k = 1, 2 do
        c.text[k]:SetAlpha(0)
        c.veil[k]:SetAlpha(0)
    end
end
