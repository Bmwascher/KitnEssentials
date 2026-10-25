-- derive-forever-transforms.lua: print the Forever Hide Transforms table of
-- Modules/QoL/Automation/Automation.lua from game-data (DB2) tables saved by
-- fetch-db2.ps1.
--
-- Run from the repo root with the local Lua 5.1 interpreter:
--   lua dev/scripts/derive-forever-transforms.lua <dir>
--   lua dev/scripts/derive-forever-transforms.lua <dir> --check Modules/QoL/Automation/Automation.lua
--
-- <dir> holds SpellName, SpellEffect and SpellMisc as <Table>.csv. The first
-- form prints FOREVER_TRANSFORMS, to be pasted into Automation.lua as printed.
-- --check exits 0 when the file holds that text exactly; otherwise it prints
-- the text and exits 1. A candidate that breaks a rule, a missing table or a
-- missing column exits 1 naming its cause: the rows are a ruled list, so a
-- failing id is a question, never a silent drop.
--
-- Rules, for every candidate id:
--   1. It has a SpellName row.
--   2. It has a DifficultyID 0 SpellEffect row with Effect 6 (apply aura).
--   3. Its DifficultyID 0 SpellMisc row has Attributes_0 bit 31 (cannot
--      cancel) clear. A negative stored value is read as unsigned 32-bit.

local _script = (arg[0] or ""):gsub("/", "\\")
local _dir = _script:match("^(.*\\)[^\\]+$") or ".\\dev\\scripts\\"
local CSV = dofile(_dir .. "_db2_csv.lua")

local dir, checkPath = arg[1], nil
if arg[2] == "--check" then checkPath = arg[3] end
if not dir or (arg[2] and not checkPath) then
    io.stderr:write("usage: lua dev/scripts/derive-forever-transforms.lua <dir> [--check <file>]\n")
    os.exit(2)
end

local function fail(msg)
    io.stderr:write("FAIL " .. msg .. "\n")
    os.exit(1)
end

-- The ruled rows, in page order.
local ROWS = {
    { key = "hallowed", cat = "holiday", label = "Hallowed Wand",
      ids = { 24708, 24709, 24710, 24711, 24712, 24713, 24723, 24732, 24735, 24736, 24740 } },
    { key = "noggenfogger", cat = "items", label = "Noggenfogger Elixir", ids = { 16593, 16595 } },
    { key = "deviate", cat = "items", label = "Savory Deviate Delight", ids = { 8213, 8219, 8221 } },
    { key = "whimsyfin", cat = "items", label = "Savory Whimsyfin Delight", ids = { 1252576 } },
    { key = "deception", cat = "items", label = "Orb of Deception", ids = { 16739 } },
}

local num = CSV.num

local function loadTable(name, columns)
    local ok, rows = pcall(CSV.read, dir .. "/" .. name .. ".csv", columns)
    if not ok then fail(tostring(rows)) end
    return rows
end

local wanted = {}
for _, row in ipairs(ROWS) do
    for _, id in ipairs(row.ids) do wanted[id] = true end
end

local named = {}
for _, r in ipairs(loadTable("SpellName", { "ID", "Name_lang" })) do
    local id = num(r.ID)
    if wanted[id] then named[id] = true end
end

local appliesAura = {}
for _, r in ipairs(loadTable("SpellEffect", { "SpellID", "DifficultyID", "Effect" })) do
    local id = num(r.SpellID)
    if wanted[id] and num(r.DifficultyID) == 0 and num(r.Effect) == 6 then appliesAura[id] = true end
end

local attributes = {}
for _, r in ipairs(loadTable("SpellMisc", { "SpellID", "DifficultyID", "Attributes_0" })) do
    local id = num(r.SpellID)
    if wanted[id] and num(r.DifficultyID) == 0 then attributes[id] = num(r.Attributes_0) end
end

-- Lua 5.1 has no bit operators.
local function cannotCancel(value)
    if value < 0 then value = value + 2 ^ 32 end
    return math.floor(value / 2 ^ 31) % 2 == 1
end

for _, row in ipairs(ROWS) do
    for _, id in ipairs(row.ids) do
        if not named[id] then fail(("%d (%s): no SpellName row"):format(id, row.key)) end
        if not appliesAura[id] then fail(("%d (%s): no Effect 6 SpellEffect row"):format(id, row.key)) end
        local value = attributes[id]
        if not value then fail(("%d (%s): no SpellMisc row"):format(id, row.key)) end
        if cannotCancel(value) then fail(("%d (%s): cannot be canceled"):format(id, row.key)) end
    end
end

local lines = { "    local FOREVER_TRANSFORMS = {" }
for _, row in ipairs(ROWS) do
    local ids = {}
    for i, id in ipairs(row.ids) do ids[i] = tostring(id) end
    lines[#lines + 1] = ('        { key = "%s", cat = "%s", label = "%s", ids = { %s } },'):format(
        row.key, row.cat, row.label, table.concat(ids, ", "))
end
lines[#lines + 1] = "    }"

local out = table.concat(lines, "\n") .. "\n"
if checkPath then
    local f = io.open(checkPath, "rb")
    if not f then fail("cannot read " .. checkPath) end
    local text = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    if text:find(out, 1, true) then
        print("OK " .. checkPath .. " holds the derived rows")
        os.exit(0)
    end
    io.write(out)
    fail(checkPath .. " does not hold the rows above exactly")
end
io.write(out)
