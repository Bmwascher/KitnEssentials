-- _forever_load.lua: which files of a Blizzard addon the Forever client loads,
-- read from the addon's manifest text. Pure string work, no file access; used
-- by check-forever-api.lua. Runs under Lua 5.1 and 5.4.
--
-- Forever is a mainline client whose game type is camelot, so a gate naming
-- either one admits it and an exclusion naming either one refuses it.

local L = {}

local FOREVER = { camelot = true, mainline = true }

local function namesForever(list)
    for word in list:gmatch("[%w_]+") do
        if FOREVER[word:lower()] then return true end
    end
    return false
end

-- text is a manifest line or a header value with its [bracket] conditions.
function L.gateAllows(text)
    local allow = text:match("%[AllowLoadGameType%s+([^%]]+)%]")
    local exclude = text:match("%[ExcludeLoadGameType%s+([^%]]+)%]")
    if allow and not namesForever(allow) then return false end
    if exclude and namesForever(exclude) then return false end
    return true
end

-- Whether the addon itself loads in game on Forever. A header line whose own
-- bracket condition refuses Forever does not apply.
function L.headerAllows(toc)
    for line in toc:gmatch("[^\r\n]+") do
        local key, value = line:match("^##%s*(%w+)%s*:%s*(.-)%s*$")
        if key and L.gateAllows(value) then
            local bare = value:gsub("%s*%[.*$", "")
            if key == "AllowLoadGameType" and not namesForever(bare) then return false end
            if key == "ExcludeLoadGameType" and namesForever(bare) then return false end
            if key == "AllowLoad" and bare:lower() == "glue" then return false end
        end
    end
    return true
end

-- The manifest's file lines Forever loads, in order, relative to the addon
-- folder, with [Family] and [Game] resolved to Forever's folders.
function L.tocFiles(toc)
    local out = {}
    for line in toc:gmatch("[^\r\n]+") do
        line = line:gsub("^%s+", "")
        if line ~= "" and line:sub(1, 1) ~= "#" and L.gateAllows(line) then
            -- the tokens can sit inside a file name; what is left in brackets
            -- after them is the line's conditions
            local file = line:gsub("%[Family%]", "Mainline"):gsub("%[Game%]", "Camelot")
            file = file:gsub("%s*%[.*$", ""):gsub("%s+$", "")
            if file ~= "" then out[#out + 1] = file end
        end
    end
    return out
end

-- Files an XML manifest pulls in, relative to that manifest's folder.
function L.xmlFiles(xml)
    local out = {}
    xml = xml:gsub("<!%-%-.-%-%->", "")
    for tag, attrs in xml:gmatch("<%s*(%a+)([^>]*)>") do
        if tag == "Script" or tag == "Include" then
            local file = attrs:match('file%s*=%s*"([^"]+)"')
            if file then out[#out + 1] = file end
        end
    end
    return out
end

-- Global names a source file defines: a line-start or _G assignment, a
-- line-start `function Name(`, a named XML object or an XML mixin. Adds them
-- to set. Line-start only, so a local function or a method never counts.
function L.definitions(src, isXml, set)
    if isXml then
        for id in src:gmatch('name="([A-Za-z_][A-Za-z0-9_]*)"') do set[id] = true end
        for id in src:gmatch('mixin="([A-Za-z_][A-Za-z0-9_]*)"') do set[id] = true end
        return
    end
    -- gmatch has no anchor, so the leading newline stands in for line 1
    src = "\n" .. src
    for id in src:gmatch("\n([A-Za-z_][A-Za-z0-9_]*)%s*=") do set[id] = true end
    for id in src:gmatch("\nfunction%s+([A-Za-z_][A-Za-z0-9_]*)%s*%(") do set[id] = true end
    for id in src:gmatch("_G%.([A-Za-z_][A-Za-z0-9_]*)%s*=") do set[id] = true end
    for id in src:gmatch("_G%[[\"']([A-Za-z_][A-Za-z0-9_]*)[\"']%]%s*=") do set[id] = true end
end

return L
