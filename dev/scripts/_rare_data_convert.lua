-- _rare_data_convert.lua: the rules of convert-rare-data.lua, apart from file
-- reading, so dev/spec/rare_data_convert_spec.lua can run them on rows it
-- builds. Loaded by dofile:
--
--   local Convert = dofile(_dir .. "_rare_data_convert.lua")
--   local rares, loot = Convert.Convert(rawRares, rawLoot)
--   local lines = Convert.Lines(rares, loot, Source.Wrap)
--
-- A raw rare is { name, low, high, elite, reactA, reactH, map, spots, trail },
-- keyed by creature id. A raw drop list is { { id, quality, chance, name, new },
-- ... }, keyed the same way, and may carry a count under `more`. Rules:
--   1. A low or high at or below 0 stores both levels as absent.
--   2. Items 286749 and 286746 store quality 2.
--   3. A chance above 100 stores 100; 0 stays.
--   4. An elite or new of 1 stores true; any other value stores nothing.
--   5. Every other field stands as it is. The trail and the `more` count are
--      not stored.
-- A row the stored form cannot hold, or the module cannot read, raises
-- error(msg, 0) naming its creature: a field of the wrong type, a number that
-- is not finite, spots that are not x, y pairs of numbers, a list with a named
-- key or a gap, or a row or drop with a field past its last known position.
-- Lines returns the data file's lines in the stored form `wrap` gives them, one
-- creature per line in id order, each field in a fixed order and an absent one
-- not written. FileMatches says whether a file's text is exactly those lines.

local M = {}

local NAME = "RareAlertTable"
local GENERATED_BY = "dev/scripts/convert-rare-data.lua"
local CHANCE_MAX = 100
local QUALITY_OF = { [286749] = 2, [286746] = 2 }
local RARE_FIELDS = 9
local DROP_FIELDS = 5
local RARE_ORDER = { "name", "low", "high", "elite", "reactA", "reactH", "map" }
local DROP_ORDER = { "id", "quality", "chance", "name", "new" }

local function refuse(npc, what)
    error(("rare %s: %s"):format(tostring(npc), what), 0)
end

-- value() writes NaN and infinity as names, which build back as nil.
local function isNumber(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function checkNumber(npc, v, what)
    if v ~= nil and not isNumber(v) then refuse(npc, what .. " that is not a number") end
end

local function checkTable(npc, v, what)
    if type(v) ~= "table" then refuse(npc, what .. " that is not a table") end
end

-- Lines writes the id with %d, which would cut a fraction and join two rows.
local function checkId(npc)
    if not isNumber(npc) or npc % 1 ~= 0 then refuse(npc, "a creature id that is not a whole number") end
end

local function isPosition(key)
    return type(key) == "number" and key >= 1 and key % 1 == 0
end

-- The entry count of a list read by #, or nil for a named key or a gap, which
-- # would skip. `allowed` is the one other key the list may carry.
local function listLength(list, allowed)
    local count, last = 0, 0
    for key in pairs(list) do
        if key ~= allowed then
            if not isPosition(key) then return nil end
            count = count + 1
            if key > last then last = key end
        end
    end
    if count ~= last then return nil end
    return last
end

-- A row read at fixed positions would drop any other field unseen.
local function checkFields(npc, row, fields, what)
    for key in pairs(row) do
        if not isPosition(key) or key > fields then
            refuse(npc, what .. " with a field the converter does not know")
        end
    end
end

local function checkName(npc, name)
    if type(name) ~= "string" then refuse(npc, "no name") end
    if name:find("%c") then refuse(npc, "a name holding a control character") end
end

-- The module reads spots two numbers at a time.
local function convertSpots(npc, spots)
    if spots == nil then return nil end
    local count = type(spots) == "table" and listLength(spots)
    if not count then refuse(npc, "spots that are not a list") end
    if count % 2 ~= 0 then refuse(npc, "spots that are not x, y pairs") end
    local copy = {}
    for i = 1, count do
        if not isNumber(spots[i]) then refuse(npc, "a spot that is not a number") end
        copy[i] = spots[i]
    end
    return copy
end

local function convertRare(npc, row)
    checkTable(npc, row, "a rare row")
    checkFields(npc, row, RARE_FIELDS, "a rare row")
    checkName(npc, row[1])
    checkNumber(npc, row[2], "a level")
    checkNumber(npc, row[3], "a level")
    checkNumber(npc, row[5], "a reaction")
    checkNumber(npc, row[6], "a reaction")
    if not isNumber(row[7]) then refuse(npc, "no map") end
    local spots = convertSpots(npc, row[8])
    local low, high = row[2], row[3]
    if (low and low <= 0) or (high and high <= 0) then low, high = nil, nil end
    return {
        name = row[1],
        low = low,
        high = high,
        elite = row[4] == 1 or nil,
        reactA = row[5],
        reactH = row[6],
        map = row[7],
        spots = spots,
    }
end

local function convertDrop(npc, item)
    checkTable(npc, item, "a drop")
    checkFields(npc, item, DROP_FIELDS, "a drop")
    if not isNumber(item[1]) then refuse(npc, "a drop with no id") end
    checkNumber(npc, item[2], "a drop quality")
    checkNumber(npc, item[3], "a drop chance")
    checkName(npc, item[4])
    local chance = item[3]
    if chance and chance > CHANCE_MAX then chance = CHANCE_MAX end
    return {
        id = item[1],
        quality = QUALITY_OF[item[1]] or item[2],
        chance = chance,
        name = item[4],
        new = item[5] == 1 or nil,
    }
end

function M.Convert(rawRares, rawLoot)
    local rares, loot = {}, {}
    for npc, row in pairs(rawRares) do
        checkId(npc)
        rares[npc] = convertRare(npc, row)
    end
    for npc, items in pairs(rawLoot) do
        checkId(npc)
        checkTable(npc, items, "a drop list")
        -- A `more` count is allowed and not stored.
        local count = listLength(items, "more")
        if not count then refuse(npc, "a drop list with a named key or a gap") end
        local list = {}
        for i = 1, count do list[i] = convertDrop(npc, items[i]) end
        loot[npc] = list
    end
    return rares, loot
end

local function value(v)
    if type(v) == "string" then return ("%q"):format(v) end
    return tostring(v)
end

local function fields(record, order)
    local parts = {}
    for _, key in ipairs(order) do
        if record[key] ~= nil then parts[#parts + 1] = key .. "=" .. value(record[key]) end
    end
    return parts
end

local function list(values)
    local parts = {}
    for i = 1, #values do parts[i] = value(values[i]) end
    return "{" .. table.concat(parts, ",") .. "}"
end

local function sortedKeys(map)
    local keys = {}
    for key in pairs(map) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

function M.Lines(rares, loot, wrap)
    local source = { "return {", "rares={" }
    for _, npc in ipairs(sortedKeys(rares)) do
        local record = rares[npc]
        local parts = fields(record, RARE_ORDER)
        if record.spots then parts[#parts + 1] = "spots=" .. list(record.spots) end
        source[#source + 1] = ("[%d]={%s},"):format(npc, table.concat(parts, ","))
    end
    source[#source + 1] = "},"
    source[#source + 1] = "loot={"
    for _, npc in ipairs(sortedKeys(loot)) do
        local drops = {}
        for i, drop in ipairs(loot[npc]) do
            drops[i] = "{" .. table.concat(fields(drop, DROP_ORDER), ",") .. "}"
        end
        source[#source + 1] = ("[%d]={%s},"):format(npc, table.concat(drops, ","))
    end
    source[#source + 1] = "},"
    source[#source + 1] = "}"
    return wrap(NAME, GENERATED_BY, source)
end

function M.FileMatches(text, lines)
    return (text:gsub("\r\n", "\n")) == table.concat(lines, "\n") .. "\n"
end

return M
