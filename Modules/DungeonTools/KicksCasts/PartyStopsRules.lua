-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/DungeonTools/KicksCasts/PartyStopsRules.lua     ║
-- ║  Purpose: Party Stops' pure rules. No WoW API, no        ║
-- ║           frames.                                        ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local ipairs, pairs, type = ipairs, pairs, type
local math_ceil, math_floor, math_max, math_min = math.ceil, math.floor, math.max, math.min

local Rules = {}
KE.PartyStopsRules = Rules

local EMPTY = {}

-- Per grow direction: the corner the first icon sits in, and the step along
-- a row. A new row starts below for Right and Left, to the right for Down
-- and Up.
local GROW = {
    RIGHT = { corner = "TOPLEFT",    dx = 1,  dy = 0 },
    LEFT  = { corner = "TOPRIGHT",   dx = -1, dy = 0 },
    DOWN  = { corner = "TOPLEFT",    dx = 0,  dy = -1 },
    UP    = { corner = "BOTTOMLEFT", dx = 0,  dy = 1 },
}

-- nil means the plate is watched. Only a plain false on the assist read
-- passes: on an assistable unit the game skips the spell-ID filter. strict
-- adds the combat test; any other unreadable read lets the plate through.
function Rules.Verdict(unit, api, strict)
    if api.exists(unit) ~= true then return "no unit" end
    if api.canAttack(unit) == false then return "not attackable" end
    if api.canAssist(unit) ~= false then return "assistable, or unreadable" end
    if api.isDead(unit) == true then return "dead" end
    if api.isBoss(unit) == true then return "boss" end
    if strict and api.inCombat(unit) == false then return "not in combat" end
    return nil
end

-- An unread need talent counts as taken, so a member is dropped only when
-- every one reads untaken. A spec, then a role, limits a stop only once known.
function Rules.Fits(stop, member, ranks)
    if member.class ~= stop.class then return false end
    local need = stop.need
    if need and #need > 0 and ranks then
        local taken = false
        for _, id in ipairs(need) do
            if ranks[id] ~= 0 then
                taken = true
                break
            end
        end
        if not taken then return false end
    end
    if stop.spec then
        if member.spec ~= nil then return member.spec == stop.spec end
        if member.role ~= nil then return member.role == stop.role end
    end
    return true
end

-- nil while a fact the answer needs is unknown.
function Rules.Live(facts, db)
    if facts.inRaid == nil or facts.inGroup == nil then return nil end
    if facts.inRaid then return false end
    if db.OnlyInParty ~= false and not facts.inGroup then return false end
    if db.OnlyInDungeons == true then
        if facts.inInstance == nil or (facts.inInstance and facts.instanceType == nil) then return nil end
        return facts.inInstance and facts.instanceType == "party"
    end
    return true
end

-- The saved order's known stops once each, then every shipped stop it lacks,
-- so a stop added in an update still shows.
function Rules.SpellList(db, data)
    local out, seen = {}, {}
    if type(db.Spells) == "table" then
        for _, id in ipairs(db.Spells) do
            if data.STOPS[id] and not seen[id] then
                seen[id] = true
                out[#out + 1] = id
            end
        end
    end
    for _, id in ipairs(data.ORDER) do
        if not seen[id] then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    return out
end

-- Per class, the talents its stops' need and mods name.
function Rules.WantByClass(data)
    local out = {}
    for _, stop in pairs(data.STOPS) do
        local set = out[stop.class] or {}
        out[stop.class] = set
        for _, id in ipairs(stop.need or EMPTY) do set[id] = true end
        for _, mod in ipairs(stop.mods or EMPTY) do set[mod[1]] = true end
    end
    return out
end

local function Clamp(value, low, high, default)
    if type(value) ~= "number" or value ~= value then return default end
    return math_max(low, math_min(high, math_floor(value)))
end

function Rules.Watched(value) return Clamp(value, 4, 20, 10) end

function Rules.PerRow(value) return Clamp(value, 1, 20, 8) end

-- Icon i's corner and its offset from it.
function Rules.GridPlace(i, perRow, grow, step)
    local g = GROW[grow] or GROW.RIGHT
    local along, line = (i - 1) % perRow, math_floor((i - 1) / perRow)
    if g.dy == 0 then return g.corner, g.dx * along * step, -line * step end
    return g.corner, line * step, g.dy * along * step
end

-- Width and height of n icons; one icon's size with none.
function Rules.GridSize(n, perRow, grow, size, step)
    if n < 1 then return size, size end
    local long = size + (math_min(n, perRow) - 1) * step
    local wide = size + (math_ceil(n / perRow) - 1) * step
    local g = GROW[grow] or GROW.RIGHT
    if g.dy == 0 then return long, wide end
    return wide, long
end

-- The first length characters of a name, counted in UTF-8.
function Rules.Short(name, length)
    if type(name) ~= "string" or type(length) ~= "number" or length <= 0 then return name end
    local i, count, len = 1, 0, #name
    while i <= len and count < length do
        local b = name:byte(i)
        i = i + ((b >= 240 and 4) or (b >= 224 and 3) or (b >= 192 and 2) or 1)
        count = count + 1
    end
    return name:sub(1, i - 1)
end
