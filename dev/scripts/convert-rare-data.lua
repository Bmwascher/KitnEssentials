-- convert-rare-data.lua: write KitnEssentials_Data/RareAlertTable.lua from a Lua
-- data file holding a rare table and a drop table. The rules are in
-- _rare_data_convert.lua beside it, and the stored form in _data_source.lua. Run
-- it again to refresh the table from a newer data file.
--
-- Run from the repo root with the local Lua 5.1 interpreter:
--   lua dev/scripts/convert-rare-data.lua <source> <out>
--   lua dev/scripts/convert-rare-data.lua <source> --check <file>
--
-- The data file sets its tables as fields of one table it reaches by a global
-- path; whatever that path names, it reaches the table this script fills. It
-- must set Rares, rows keyed by creature id, and Loot, drop lists keyed the same
-- way, and nothing else it sets is read. <out> is written with LF line ends.
-- --check exits 0 when the file, line ends aside, is the converted text;
-- otherwise it prints that text and exits 1. The counts go to stderr. An
-- unreadable data file or a refused row exits 1 naming its cause.

local _script = (arg[0] or ""):gsub("/", "\\")
local _dir = _script:match("^(.*\\)[^\\]+$") or ".\\dev\\scripts\\"
local Convert = dofile(_dir .. "_rare_data_convert.lua")
local Source = dofile(_dir .. "_data_source.lua")

local sourcePath, outPath, checkPath = arg[1], arg[2], nil
if outPath == "--check" then outPath, checkPath = nil, arg[3] end
if not sourcePath or not (outPath or checkPath) then
    io.stderr:write("usage: lua dev/scripts/convert-rare-data.lua <source> (<out> | --check <file>)\n")
    os.exit(2)
end

local function fail(msg)
    io.stderr:write("FAIL " .. msg .. "\n")
    os.exit(1)
end

local function readTables(path)
    local chunk, err = loadfile(path)
    if not chunk then fail(tostring(err)) end
    local filled = {}
    local anyName = setmetatable({}, { __index = function() return filled end })
    setfenv(chunk, { _G = setmetatable({}, { __index = function() return anyName end }) })
    local ok, runErr = pcall(chunk)
    if not ok then fail(tostring(runErr)) end
    if type(filled.Rares) ~= "table" then fail(path .. " sets no Rares table") end
    if type(filled.Loot) ~= "table" then fail(path .. " sets no Loot table") end
    return filled.Rares, filled.Loot
end

local rawRares, rawLoot = readTables(sourcePath)
local converted, rares, loot = pcall(Convert.Convert, rawRares, rawLoot)
if not converted then fail(tostring(rares)) end
local wrapped, lines = pcall(Convert.Lines, rares, loot, Source.Wrap)
if not wrapped then fail(tostring(lines)) end

local rareCount, lootCount = 0, 0
for _ in pairs(rares) do rareCount = rareCount + 1 end
for _ in pairs(loot) do lootCount = lootCount + 1 end
io.stderr:write(("rares %d, with drops %d\n"):format(rareCount, lootCount))

local out = table.concat(lines, "\n") .. "\n"
if checkPath then
    local f = io.open(checkPath, "rb")
    if not f then fail("cannot read " .. checkPath) end
    local text = f:read("*a")
    f:close()
    if Convert.FileMatches(text, lines) then
        print("OK " .. checkPath .. " is the converted table")
        os.exit(0)
    end
    io.write(out)
    fail(checkPath .. " is not the table above exactly")
end

local f = io.open(outPath, "wb")
if not f then fail("cannot write " .. outPath) end
f:write(out)
f:close()
