-- load-list.lua: print the ordered list of files a toc loads.
--
-- Run from the repo root with the local Lua interpreter:
--   lua dev/scripts/load-list.lua [--client standard|camelot] [toc ...]
--
-- With no toc arguments it walks KitnEssentials.toc, then
-- KitnEssentials_Options/KitnEssentials_Options.toc. Every toc line, then
-- every <Script file> and <Include file> inside each manifest, is expanded in
-- load order. A toc line tagged [AllowLoadGameType a, b] is kept only when
-- --client (default standard) is in its list. Output: one repo-relative path
-- per line, forward slashes; a manifest prints before the files it includes.
-- A <Script> with no file attribute prints as "<inline> <manifest>".
--
-- Exit 1 when a listed file does not exist.

local CLIENT = "standard"
local tocs = {}
local i = 1
while i <= #arg do
    if arg[i] == "--client" then
        CLIENT = arg[i + 1] or CLIENT
        i = i + 1
    else
        tocs[#tocs + 1] = arg[i]
    end
    i = i + 1
end
if #tocs == 0 then
    tocs = { "KitnEssentials.toc", "KitnEssentials_Options/KitnEssentials_Options.toc" }
end

local missing = 0

local function normalize(path)
    path = path:gsub("\\", "/")
    local parts = {}
    for part in path:gmatch("[^/]+") do
        if part == ".." then
            parts[#parts] = nil
        elseif part ~= "." then
            parts[#parts + 1] = part
        end
    end
    return table.concat(parts, "/")
end

local function dirOf(path)
    return path:match("^(.*)/[^/]*$") or ""
end

local function join(dir, rel)
    if dir == "" then return normalize(rel) end
    return normalize(dir .. "/" .. rel)
end

local function readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function emit(path)
    io.write(path, "\n")
end

local expandXml

local function loadPath(path)
    local text = readFile(path)
    if not text then
        missing = missing + 1
        io.stderr:write("MISSING: ", path, "\n")
        emit(path)
        return
    end
    emit(path)
    if path:lower():match("%.xml$") then
        expandXml(path, text)
    end
end

expandXml = function(path, text)
    text = text:gsub("<!%-%-.-%-%->", "")
    local dir = dirOf(path)
    for tag, attrs in text:gmatch("<%s*(%a+)([^>]*)>") do
        if tag == "Script" or tag == "Include" then
            local file = attrs:match('file%s*=%s*"([^"]+)"')
            if file then
                loadPath(join(dir, file))
            elseif tag == "Script" then
                emit("<inline> " .. path)
            end
        end
    end
end

local function tagAllows(tagText)
    local list = tagText:match("AllowLoadGameType%s+([^%]]+)")
    if not list then return true end
    for name in list:gmatch("[%w_]+") do
        if name == CLIENT then return true end
    end
    return false
end

for _, toc in ipairs(tocs) do
    toc = normalize(toc)
    local text = readFile(toc)
    if not text then
        io.stderr:write("MISSING TOC: ", toc, "\n")
        os.exit(1)
    end
    emit("# " .. toc)
    local dir = dirOf(toc)
    for line in text:gmatch("[^\r\n]+") do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and not line:match("^#") then
            local file, tags = line:match("^(.-)%s*(%[.*%])$")
            file = file or line
            if not tags or tagAllows(tags) then
                loadPath(join(dir, file))
            end
        end
    end
end

if missing > 0 then os.exit(1) end
