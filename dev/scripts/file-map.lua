-- file-map.lua: map every shipped file to its sidebar section and row.
--
-- Run from the repo root with the local Lua interpreter:
--   lua dev/scripts/file-map.lua [--out <path>] [--retail <file>]
--
-- Rows come from GUIFrame.sidebarConfig in GUI/GUIMain/GUI-MainFrame.lua. A
-- row's content ids are its own id plus, transitively, the children of each
-- id in the set. A Register*("<parent>", ...) call gives <parent> as children:
--   - the ids of a literal tab table;
--   - for RegisterTabbedContent and RegisterNestedTabs, the ids inside a
--     function argument, or in a local table argument plus the local tables
--     an ipairs loop copies into it;
--   - for a RegisterContent builder that reads GUIFrame.registeredContent,
--     each registeredContent["<id>"] and each string of an ipairs({ ... })
--     list inside it.
-- Page files register one of those ids. A settings file that registers
-- through a variable, or registers nothing, is a page for each id it quotes.
-- Module files name an id in guiPath or guiTab. Files no row reaches are
-- listed by folder, then the manifests in load order (from load-list.lua),
-- then the retail-only list (dev/scripts/retail-only.lua unless --retail
-- names another).
--
-- Without --out the map prints to stdout; --out writes the bytes directly,
-- since a PowerShell 5.1 redirect would write UTF-16. Exit 1 when a
-- self-check fails: a row with no page file, a settings file no row reaches,
-- a tab strip the rules above cannot read, a retail-only entry that is not a
-- tracked file, a tracked .lua file that neither toc loads, or a load-list.lua
-- line that is not a toc header, an <inline> line or an existing file. The
-- map is written either way, failures first.

local SIDEBAR_FILE = "GUI/GUIMain/GUI-MainFrame.lua"
local PAGE_ROOTS = { "GUI/", "KitnEssentials_Options/" }
local MODULE_ROOTS = { "Modules/", "Core/" }
local OPTIONS_ROOT = "KitnEssentials_Options/"
local TOCS = { "KitnEssentials.toc", "KitnEssentials_Options/KitnEssentials_Options.toc" }
local STRIP_CALLS = { TabbedContent = true, NestedTabs = true }
local REFRESH = "lua dev/scripts/file-map.lua --out dev/docs/FILE-MAP.md"

local outPath
local retailPath = "dev/scripts/retail-only.lua"
local argi = 1
while argi <= #arg do
    local flag, value = arg[argi], arg[argi + 1]
    if flag == "--out" and value then
        outPath = value
    elseif flag == "--retail" and value then
        retailPath = value
    else
        io.stderr:write("usage: lua dev/scripts/file-map.lua [--out <path>] [--retail <file>]\n")
        os.exit(2)
    end
    argi = argi + 2
end

local function readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function fileExists(path)
    local f = io.open(path, "rb")
    if not f then return false end
    f:close()
    return true
end

local function commandLines(cmd)
    local out = {}
    local p = io.popen(cmd)
    if p then
        for line in p:lines() do
            out[#out + 1] = (line:gsub("\r$", ""))
        end
        p:close()
    end
    return out
end

local function underAny(path, roots)
    for _, root in ipairs(roots) do
        if path:sub(1, #root) == root then return true end
    end
    return false
end

local function escapePattern(s)
    return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1"))
end

local failures = {}
local function fail(msg) failures[#failures + 1] = msg end

local tracked, trackedSet = {}, {}
for _, path in ipairs(commandLines("git ls-files -- Core GUI Modules KitnEssentials_Options")) do
    tracked[#tracked + 1] = path
    trackedSet[path] = true
end

local sources = {}
for _, path in ipairs(tracked) do
    if path:match("%.lua$") then sources[path] = readFile(path) or "" end
end

-- Load list, through the same resolver the load-order proof uses. Lua 5.1's
-- popen close returns no exit status, so the output is checked instead: every
-- non-zero exit of load-list.lua prints a MISSING line or a Lua error.
local interpreter = arg[-1] or "lua"
local loadCmd = interpreter .. " dev/scripts/load-list.lua 2>&1"
if interpreter:find(" ", 1, true) then
    loadCmd = '"' .. interpreter .. '" dev/scripts/load-list.lua 2>&1'
    if package.config:sub(1, 1) == "\\" then loadCmd = '"' .. loadCmd .. '"' end
end
local loadLines = commandLines(loadCmd)

-- A missing file prints a MISSING line and its bare path; the MISSING line
-- reports it.
local missingSet = {}
for _, line in ipairs(loadLines) do
    local path = line:match("^MISSING: (.+)$")
    if path then missingSet[path] = true end
end

local loaded, manifests, tocSeen = {}, {}, {}
for _, line in ipairs(loadLines) do
    local toc = line:match("^# (.+)$")
    if toc then
        tocSeen[toc] = true
    elseif not (line:match("^<inline> ") or line:match("^%s*$") or missingSet[line]) then
        if fileExists(line) then
            loaded[line] = true
            if line:match("%.xml$") then manifests[#manifests + 1] = line end
        else
            fail("load-list.lua: " .. line)
        end
    end
end
for _, toc in ipairs(TOCS) do
    if not tocSeen[toc] then fail("load-list.lua printed no header for " .. toc) end
end
if next(loaded) == nil then fail("load-list.lua printed no files") end
for _, path in ipairs(tracked) do
    if path:match("%.lua$") and not loaded[path] then
        fail("tracked but loaded by neither toc: " .. path)
    end
end

local retail, retailSet = {}, {}
local okRetail, retailList = pcall(dofile, retailPath)
if okRetail and type(retailList) == "table" then
    for _, path in ipairs(retailList) do
        retail[#retail + 1] = path
        retailSet[path] = true
        if not trackedSet[path] then fail("retail-only entry is not a tracked file: " .. path) end
    end
else
    fail("could not read the retail-only list " .. retailPath .. ": " .. tostring(retailList))
end

-- Sidebar sections and rows, read as text.
local sections = {}
local sidebar = readFile(SIDEBAR_FILE) or ""
local config = sidebar:match("GUIFrame%.sidebarConfig%s*=%s*(%b{})")
if not config then fail("sidebarConfig not found in " .. SIDEBAR_FILE) end
for block in (config or "{}"):sub(2, -2):gmatch("%b{}") do
    local sectionId = block:match('id%s*=%s*"([^"]+_section)"')
    if sectionId then
        local title = (block:match('text%s*=%s*"([^"]+)"') or sectionId):gsub("\\226\\128\\162%s*", "")
        local section = { id = sectionId, text = title, rows = {} }
        local items = block:match("items%s*=%s*(%b{})") or "{}"
        for item in items:sub(2, -2):gmatch("%b{}") do
            local rowId = item:match('id%s*=%s*"([^"]+)"')
            if rowId then
                section.rows[#section.rows + 1] = { id = rowId, text = item:match('text%s*=%s*"([^"]+)"') or rowId }
            end
        end
        sections[#sections + 1] = section
    end
end

local function tableIds(tableText, kids)
    for child in tableText:gmatch('id%s*=%s*"([^"]+)"') do kids[#kids + 1] = child end
end

-- A local tab table, plus every local table an ipairs loop copies into it.
local function localTableIds(text, name, kids)
    local own = text:match("local%s+" .. name .. "%s*=%s*(%b{})")
    if own then tableIds(own, kids) end
    for source in text:gmatch("ipairs%(%s*([%a_][%w_]*)%s*%)%s*do%s*" .. name .. "%[") do
        local copied = text:match("local%s+" .. source .. "%s*=%s*(%b{})")
        if copied then tableIds(copied, kids) end
    end
end

-- The whole Register*( ... ) call, or the rest of the file when its
-- parentheses do not balance.
local function callSpan(text, open)
    return text:match("^%b()", open) or text:sub(open)
end

local children = {}
for path, text in pairs(sources) do
    if underAny(path, PAGE_ROOTS) then
        for kind, open, parent, argAt in text:gmatch('Register(%w*)()%(%s*"([^"]+)"%s*,%s*()') do
            local kids = {}
            local word = text:match("^([%a_][%w_]*)", argAt)
            if text:sub(argAt, argAt) == "{" then
                tableIds(text:match("^%b{}", argAt) or "", kids)
            elseif STRIP_CALLS[kind] then
                if word == "function" then
                    tableIds(callSpan(text, open), kids)
                elseif word then
                    localTableIds(text, word, kids)
                end
                if #kids == 0 then fail("tab strip not followed: " .. path .. ": " .. parent) end
            elseif kind == "Content" and word == "function" then
                local span = callSpan(text, open)
                if span:find("registeredContent%[") then
                    for id in span:gmatch('registeredContent%[%s*"([^"]+)"%s*%]') do kids[#kids + 1] = id end
                    for list in span:gmatch("ipairs%(%s*(%b{})%s*%)") do
                        for id in list:gmatch('"([^"]+)"') do kids[#kids + 1] = id end
                    end
                end
            end
            if #kids > 0 then
                local all = children[parent] or {}
                for _, id in ipairs(kids) do all[#all + 1] = id end
                children[parent] = all
            end
        end
    end
end

local function contentIds(rowId)
    local ids, seen, queue = {}, { [rowId] = true }, { rowId }
    while #queue > 0 do
        local id = table.remove(queue, 1)
        ids[#ids + 1] = id
        for _, child in ipairs(children[id] or {}) do
            if not seen[child] then
                seen[child] = true
                queue[#queue + 1] = child
            end
        end
    end
    return ids
end

-- Settings files that register through a variable, or register no id, are
-- pages for each id they quote.
local quotesIds = {}
for path, text in pairs(sources) do
    if path:sub(1, #OPTIONS_ROOT) == OPTIONS_ROOT
        and (text:find("RegisterContent%(%s*[%a_]")
            or not (text:find('RegisterContent%(%s*"') or text:find('RegisterTabbedContent%(%s*"'))) then
        quotesIds[path] = true
    end
end

local function isPageFor(path, text, id)
    if not underAny(path, PAGE_ROOTS) then return false end
    if text:find('Register%w*%(%s*"' .. escapePattern(id) .. '"') then return true end
    return quotesIds[path] == true and text:find('"' .. id .. '"', 1, true) ~= nil
end

local function isModuleFor(path, text, id)
    if not underAny(path, MODULE_ROOTS) then return false end
    local e = escapePattern(id)
    return text:find('guiPath%s*=%s*"' .. e .. '"') ~= nil or text:find('guiTab%s*=%s*"' .. e .. '"') ~= nil
end

local function sortedKeys(set)
    local list = {}
    for key in pairs(set) do list[#list + 1] = key end
    table.sort(list)
    return list
end

local reached = {}
local body = {}
local function add(line) body[#body + 1] = line end
local function fileLine(path)
    return "- `" .. path .. "`" .. (retailSet[path] and " (retail-only)" or "")
end

for _, section in ipairs(sections) do
    add("## " .. section.text .. " (`" .. section.id .. "`)")
    add("")
    for _, row in ipairs(section.rows) do
        local pages, modules = {}, {}
        for _, id in ipairs(contentIds(row.id)) do
            for path, text in pairs(sources) do
                if isPageFor(path, text, id) then pages[path] = true end
                if isModuleFor(path, text, id) then modules[path] = true end
            end
        end
        local pageList, moduleList = sortedKeys(pages), sortedKeys(modules)
        if #pageList == 0 then fail("sidebar row has no page file: " .. row.id) end
        add("### " .. row.text .. " (`" .. row.id .. "`)")
        add("")
        add("Pages:")
        if #pageList == 0 then add("- none") end
        for _, path in ipairs(pageList) do
            reached[path] = true
            add(fileLine(path))
        end
        add("")
        add("Modules:")
        if #moduleList == 0 then add("- none") end
        for _, path in ipairs(moduleList) do
            reached[path] = true
            add(fileLine(path))
        end
        add("")
    end
end

-- Every settings file belongs to a row, so one no row reaches is a linking
-- rule that missed its shape.
for _, path in ipairs(tracked) do
    if path:sub(1, #OPTIONS_ROOT) == OPTIONS_ROOT and path:match("%.lua$") and not reached[path] then
        fail("settings file reached by no row: " .. path)
    end
end

local byFolder = {}
for _, path in ipairs(tracked) do
    if (path:match("%.lua$") or path:match("%.xml$")) and not reached[path] then
        local folder = path:match("^(.*)/[^/]+$") or "."
        byFolder[folder] = byFolder[folder] or {}
        table.insert(byFolder[folder], path)
    end
end
add("## Not reached by a row")
add("")
for _, folder in ipairs(sortedKeys(byFolder)) do
    add("### `" .. folder .. "/`")
    add("")
    table.sort(byFolder[folder])
    for _, path in ipairs(byFolder[folder]) do add(fileLine(path)) end
    add("")
end

add("## Manifests in load order")
add("")
for _, path in ipairs(manifests) do add("- `" .. path .. "`") end
add("")

add("## Retail-only files")
add("")
add("Source: `" .. retailPath .. "`.")
add("")
for _, path in ipairs(retail) do add("- `" .. path .. "`") end

local sha = commandLines("git rev-parse --short HEAD")[1] or "unknown"
local doc = {
    "# KitnEssentials file map",
    "",
    "Generated by `" .. REFRESH .. "` at `" .. sha .. "`. Regenerate after any move.",
    "",
}
if #failures > 0 then
    doc[#doc + 1] = "## Self-check failures"
    doc[#doc + 1] = ""
    for _, msg in ipairs(failures) do doc[#doc + 1] = "- " .. msg end
    doc[#doc + 1] = ""
end
for _, line in ipairs(body) do doc[#doc + 1] = line end
local docText = table.concat(doc, "\n") .. "\n"

if outPath then
    local f = io.open(outPath, "wb")
    if not f then
        io.stderr:write("cannot write ", outPath, "\n")
        os.exit(2)
    end
    f:write(docText)
    f:close()
else
    io.write(docText)
end
for _, msg in ipairs(failures) do io.stderr:write("FAIL: ", msg, "\n") end
if #failures > 0 then os.exit(1) end
