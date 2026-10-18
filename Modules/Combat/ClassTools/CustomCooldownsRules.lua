-- ╔══════════════════════════════════════════════════════════╗
-- ║  Modules/Combat/ClassTools/CustomCooldownsRules.lua      ║
-- ║  Purpose: Custom Cooldowns' saved keys, its add and      ║
-- ║         remove refusals and the resolved list.         ║
-- ║         No WoW API, no frames.                         ║
-- ╚══════════════════════════════════════════════════════════╝

---@class KE
local KE = select(2, ...)

local floor = math.floor
local pairs, tonumber, tostring, type = pairs, tonumber, tostring, type
local table_sort = table.sort

local Rules = {}
KE.CustomCooldownsRules = Rules

local MSG_NOT_ID = "Enter a spell id (a whole number)."

-- scope is a class token (every spec of the class) or a spec id (that spec).
function Rules.SpellKey(scope, spellID)
    return tostring(scope) .. ":" .. tostring(spellID)
end

local function ParseId(text)
    local n = tonumber(text)
    if not n or n <= 0 or n ~= floor(n) then return nil end
    return n
end

-- Canonical keys only, the two forms SpellKey writes: an entry under "WARRIOR:04"
-- or "071:23920" could never be found again by its ids.
local function ParseKey(key)
    if type(key) ~= "string" then return nil end
    local class, spell = key:match("^([A-Z]+):([1-9]%d*)$")
    if class then return class, tonumber(spell) end
    local spec
    spec, spell = key:match("^([1-9]%d*):([1-9]%d*)$")
    if spec then return tonumber(spec), tonumber(spell) end
    return nil
end

local function Listed(spells, key)
    return type(spells) == "table" and type(spells[key]) == "table"
end

-- A class token never equals a spec id, so one scope never reads the other's keys.
function Rules.ScopeIds(spells, scope)
    local ids = {}
    if type(spells) ~= "table" or scope == nil then return ids end
    for key, entry in pairs(spells) do
        local owner, id = ParseKey(key)
        if owner ~= nil and owner == scope and type(entry) == "table" then
            ids[#ids + 1] = id
        end
    end
    table_sort(ids)
    return ids
end

-- specOrNil nil adds to All Specs. A spec entry beside an All Specs one would
-- only repeat it, so that add is refused; the reverse is allowed and the
-- resolved list shows the id once.
function Rules.CanAdd(spells, class, specOrNil, text, nameOf)
    local id = ParseId(text)
    if not id then return nil, MSG_NOT_ID end
    if not nameOf(id) then return nil, "No spell has the id " .. id .. "." end
    if Listed(spells, Rules.SpellKey(specOrNil or class, id)) then
        return nil, "That spell is already listed there."
    end
    if specOrNil and Listed(spells, Rules.SpellKey(class, id)) then
        return nil, "That spell is already listed for all specs."
    end
    return id
end

function Rules.CanRemove(spells, class, specOrNil, text)
    local id = ParseId(text)
    if not id then return nil, MSG_NOT_ID end
    local key = Rules.SpellKey(specOrNil or class, id)
    if not Listed(spells, key) then return nil, "That id is not listed there." end
    return key
end

-- The current spec's spells: the class's All Specs entries and the spec's own,
-- each id once, kept while either entry is ticked and the spell is known.
function Rules.ResolveList(spells, class, specId, isKnown)
    local wanted, out = {}, {}
    local function Collect(scope)
        local ids = Rules.ScopeIds(spells, scope)
        for i = 1, #ids do
            local id = ids[i]
            if spells[Rules.SpellKey(scope, id)].enabled ~= false then wanted[id] = true end
        end
    end
    Collect(class)
    if specId then Collect(specId) end
    for id in pairs(wanted) do
        if isKnown(id) == true then out[#out + 1] = id end
    end
    table_sort(out)
    return out
end
