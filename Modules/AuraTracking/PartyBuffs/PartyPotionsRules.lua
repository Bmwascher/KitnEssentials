-- ╔══════════════════════════════════════════════════════════╗
-- ║  PartyPotionsRules.lua                                   ║
-- ║  Purpose: pure rules for party potion bars.              ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local ipairs = ipairs
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local pairs = pairs
local table_insert = table.insert
local table_sort = table.sort
local type = type

local Rules = {}
KE.PartyPotionsRules = Rules

Rules.TOKENS = { "party1", "party2", "party3", "party4" }
Rules.FALLBACK_ICON = "Interface\\Icons\\Trade_Alchemy"
-- Every bar shows Light's Potential: the sensor sees that a listed potion was
-- drunk, never which one.
Rules.ICON_SPELL = 1236616
-- Combat potions share one 5-minute cooldown and a 30-second buff.
Rules.SECONDS = 300
Rules.BUFF_SECONDS = 30
-- A class-colored bar draws its fill and its drained part darker than the
-- class color, by these factors.
Rules.DIM = 0.75
Rules.BG = 0.15

local GRAY = { 0.5, 0.5, 0.5 }
local WHITE = { 1, 1, 1 }

-- The bars' one entry: the switched-on potions in spell ID order. listed is a
-- set of spell IDs. nil when none is switched on.
function Rules.Entry(listed)
    local buffs = {}
    for id, on in pairs(listed or {}) do
        if on and type(id) == "number" then buffs[#buffs + 1] = id end
    end
    if #buffs == 0 then return nil end
    table_sort(buffs)
    return { id = "potion", kind = "potion", buffs = buffs, cd = Rules.SECONDS }
end

-- The units to watch, in box order. Solo there are none, so nothing shows out
-- of a party.
function Rules.Tokens(includeSelf, exists)
    local out = {}
    for _, token in ipairs(Rules.TOKENS) do
        if exists(token) == true then out[#out + 1] = token end
    end
    if includeSelf and #out > 0 then table_insert(out, 1, "player") end
    return out
end

-- After a roster change a bar keeps its count only for the same member, known
-- by two plain, equal GUIDs.
function Rules.KeepOnRoster(old, new, isSecret)
    if isSecret(old) or isSecret(new) or old == nil or new == nil then return false end
    return old == new
end

-- A bar's fill, drained part and name: each fill color is returned with the
-- factor its RGB is drawn at, and last the drained part's opacity, which the
-- Background Color sets for class-colored bars too. color is the member's
-- class color, nil when the game hides the class; such a bar is gray and its
-- name white.
function Rules.Colors(style, color)
    local class = color or GRAY
    local fill, fillScale, bg, bgScale = class, Rules.DIM, class, Rules.BG
    if not style.classBars then
        fill, fillScale, bg, bgScale = style.barColor, 1, style.bgColor, 1
    end
    local bgAlpha = style.bgColor and style.bgColor[4] or 1
    return fill, fillScale, bg, bgScale, style.classNames and color or WHITE, bgAlpha
end

-- The timer window in whole pixels: its height, never above the line, how far
-- it sits above the bottom of the area, rounded down, so an odd difference
-- puts it half a pixel low, and how far its top sits below the area's top. A
-- measured line or margin a hair under a whole pixel counts as that pixel.
-- Last, how far the window may open below and above the line, so ink past the
-- line box is not cut: at most one strip margin, and never past the area. A
-- line taller than the area gets no opening and keeps its overflow.
function Rules.Window(areaPx, linePx, marginPx)
    local win = math_floor(linePx + 0.01)
    local area = math_floor(areaPx + 0.5)
    local raise = math_floor((area - win) / 2)
    local top = area - win - raise
    local margin = math_floor(marginPx + 0.01)
    return win, raise, top, math_max(0, math_min(margin, raise)), math_max(0, math_min(margin, top))
end

-- The offset from one bar to the next. At no spacing the bars overlap by a
-- pixel, so the two touching frame lines are one.
function Rules.Gap(spacing, px)
    if spacing == 0 then return -px end
    return spacing
end

-- A slot's cover range this second: the cover fills by one cd-th a second.
function Rules.CoverRange(sl, u, cd, n)
    local lo = (255 - (n - sl.epoch) / u) / 255
    return lo, lo + cd / (255 * u)
end
