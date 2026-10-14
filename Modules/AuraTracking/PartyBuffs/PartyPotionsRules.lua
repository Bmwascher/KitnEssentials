-- ╔══════════════════════════════════════════════════════════╗
-- ║  PartyPotionsRules.lua                                   ║
-- ║  Purpose: pure rules for party potion bars.              ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local ipairs = ipairs
local pairs = pairs
local table_insert = table.insert
local table_sort = table.sort
local type = type

local Rules = {}
KE.PartyPotionsRules = Rules

Rules.TOKENS = { "party1", "party2", "party3", "party4" }
Rules.FALLBACK_ICON = "Interface\\Icons\\Trade_Alchemy"
-- Combat potions share one 5-minute cooldown.
Rules.SECONDS = 300
-- A class-colored bar draws its fill and its drained part darker than the
-- class color, by these factors.
Rules.DIM = 0.75
Rules.BG = 0.15

local GRAY = { 0.5, 0.5, 0.5 }
local WHITE = { 1, 1, 1 }

-- The bars' one entry: the switched-on potions in spell ID order and the icon
-- of the first of them that has one. listed is a set of spell IDs. nil when
-- none is switched on.
function Rules.Entry(listed, textureOf)
    local buffs = {}
    for id, on in pairs(listed or {}) do
        if on and type(id) == "number" then buffs[#buffs + 1] = id end
    end
    if #buffs == 0 then return nil end
    table_sort(buffs)
    local texture
    for _, id in ipairs(buffs) do
        texture = textureOf(id)
        if texture then break end
    end
    return {
        id = "potion", kind = "potion", buffs = buffs,
        cd = Rules.SECONDS,
        texture = texture or Rules.FALLBACK_ICON,
    }
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
-- factor its RGB is drawn at. color is the member's class color, nil when the
-- game hides the class; such a bar is gray and its name white.
function Rules.Colors(style, color)
    local class = color or GRAY
    local fill, fillScale, bg, bgScale = class, Rules.DIM, class, Rules.BG
    if not style.classBars then
        fill, fillScale, bg, bgScale = style.barColor, 1, style.bgColor, 1
    end
    return fill, fillScale, bg, bgScale, style.classNames and color or WHITE
end

-- A slot's cover range this second: the cover fills by one cd-th a second.
function Rules.CoverRange(sl, u, cd, n)
    local lo = (255 - (n - sl.epoch) / u) / 255
    return lo, lo + cd / (255 * u)
end
