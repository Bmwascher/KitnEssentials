-- file-map.lua: map every shipped file to its sidebar section and row, and
-- every row to its tabs and cards.
--
-- Run from the repo root with the local Lua interpreter:
--   lua dev/scripts/file-map.lua [--refresh] [--out <path>] [--retail <file>]
--
-- --refresh keeps a map current: it rebuilds when the map is missing, git
-- cannot give a stamp, or the commit or the uncommitted content of the map's
-- inputs (REFRESH_INPUTS) differs from the stamp at the end of the map. Map
-- and stamp are one file replaced in one step, so runs started together each
-- leave a map that matches its own stamp. It publishes only a map whose
-- self-checks pass (else it keeps the previous one and prints the failures),
-- prints one `[file-map]` line naming the map, and takes no custom --retail
-- list. Its default output is dev/docs/FILE-MAP.md in the primary checkout
-- and FILE-MAP.md in the git dir of a linked worktree, whose dev/docs may be
-- a junction to the primary's. The SessionStart hook file-map-check.ps1 runs
-- it.
--
-- Rows come from GUIFrame.sidebarConfig in GUI/GUIMain/GUI-MainFrame.lua. A
-- row's content ids are its own id plus, transitively, the children of each
-- id in the set. A Register*("<parent>", ...) call gives <parent> as children:
--   - the ids of a literal tab table;
--   - for RegisterTabbedContent and RegisterNestedTabs, the ids inside a
--     function argument, or in a local table argument plus the local tables
--     an ipairs loop copies into it;
--   - for a RegisterContent builder that reads GUIFrame.registeredContent,
--     each registeredContent["<id>"], and each string of a plain string list
--     looped by `for _, <var> in ipairs({ ... })` when the builder reads
--     registeredContent[<var>].
-- A parent or tab id may be a string or a file-level string constant. Page
-- files register one of those ids. A settings file that registers through a
-- variable, or registers nothing, is a page for each id it quotes. Module
-- files name an id in guiPath or guiTab.
--
-- Under each row, "Tabs and cards" lists the row's own cards (its header,
-- above every tab, or the whole page when it has no tabs), then each tab with
-- its label and cards, nested tabs indented. A child read from
-- registeredContent has no label and prints as Chained: a page drawn inside
-- its parent's. The cards of a content id are the CreateCard calls and the
-- GUI/GUIWidgets card builders inside its RegisterContent or
-- RegisterTabbedContent call, in source order, with every function of the
-- same file named there expanded where it is named, and every settings
-- file's column-0 `function X.Name(` or `X:Name(` definition, or
-- `X.Name = <local function>` alias, expanded where `.Name(` or `:Name(` is
-- called. Cards on every run-time branch are listed. A strip a page draws with
-- CreateSubTabs prints among its cards as `in-page tabs (A / B)`; the cards
-- after it are not split by view. A Register call whose id is a parameter of
-- its function is read once per call of that function; one whose id is a
-- field of an ipairs loop variable, once per entry of the looped local table.
-- A title that is a string literal with no escapes, a file-level string
-- constant, a bound parameter, `<param>.<field>` or `<param>.<field> or
-- "<default>"` prints as text; any other prints as dynamic. The "Error"
-- placeholder card is left out.
--
-- A tab marked retail only is absent on WoW Forever, for one of two reasons:
-- its page file is not in `load-list.lua --client camelot`, or its id is not
-- in FOREVER_ALLOWED in Core/Availability.lua. A page file only the camelot
-- list loads is marked Forever only, or on neither client when its id is
-- withheld. Code inside a page that hides a card on either client is not read
-- (see foreverNote).
--
-- Files no row reaches are listed by folder, then the manifests in load order
-- (from load-list.lua, both clients), then the retail-only list
-- (dev/scripts/retail-only.lua unless --retail names another).
--
-- Without --out or --refresh the map prints to stdout; --out writes the
-- bytes directly, since a PowerShell 5.1 redirect would write UTF-16.
-- Exit 1 when a self-check fails: a row with no page file, a settings file no row reaches,
-- a registered tab strip the rules above cannot read, a tab function with a
-- `return` that is not a literal list, or a tab list with an element that
-- is not an inline or local table, an id that is not a string literal or
-- constant, or a label that is not a string literal (an in-page strip prints
-- as dynamic instead), a Register call whose content id cannot be read, no
-- FOREVER_ALLOWED table in Core/Availability.lua, a retail-only entry that is
-- not a tracked file, a tracked .lua file that neither client loads, or a
-- load-list.lua line that is not a toc header, an <inline> line or an
-- existing file. Without --refresh the map is written either way, failures
-- first.

local SIDEBAR_FILE = "GUI/GUIMain/GUI-MainFrame.lua"
local AVAILABILITY_FILE = "Core/Availability.lua"
local PAGE_ROOTS = { "GUI/", "KitnEssentials_Options/" }
local MODULE_ROOTS = { "Modules/", "Core/" }
local OPTIONS_ROOT = "KitnEssentials_Options/"
local TOCS = { "KitnEssentials.toc", "KitnEssentials_Options/KitnEssentials_Options.toc" }
local STRIP_CALLS = { TabbedContent = true, NestedTabs = true }
-- The files that define the Register methods: their calls take the id as a
-- parameter of the method and register nothing themselves.
local REGISTRY_FILES = { ["GUI/GUIMain/GUI-Core.lua"] = true, ["GUI/GUIMain/GUI-TabbedContent.lua"] = true }
-- Card builders that take (scrollChild, yOffset, config), and the title each
-- prints when config has none; false when it has no default.
local BUILDER_DEFAULTS = {
    CreatePositionCard = "Position Settings",
    CreateFontSettingsCard = "Font Settings",
    CreateColorsCard = "Colors",
    CreateAuraGlowCard = "Glow",
    CreateGlowSettingsCard = "Glow",
    CreateAuraApplicationSoundCard = "Sound",
    CreateSpecEnableCard = "Enable per Specialization",
    CreateAuraCasterNameCard = "Caster Name",
    CreateTauntCursorCard = "Taunt Countdown",
    CreateDispelTypeColorsCard = "Dispel Type Colors",
    CreateDispelCursorCard = "Dispel Countdown",
    CreateAuraAllowlistCard = false,
}
local EXPAND_DEPTH = 8
local CARD_SEP = " \194\183 "
local REFRESH = "lua dev/scripts/file-map.lua --refresh"
local REFRESH_INPUTS = "GUI Core Modules KitnEssentials_Options Libs KitnEssentials.toc "
    .. "dev/scripts/file-map.lua dev/scripts/load-list.lua dev/scripts/retail-only.lua"
local STAMP_OPEN, STAMP_CLOSE = "<!-- file-map stamp\n", "-->\n"

local outPath, refresh
local retailPath = "dev/scripts/retail-only.lua"
local argi = 1
while argi <= #arg do
    local flag, value = arg[argi], arg[argi + 1]
    if flag == "--refresh" then
        refresh = true
        argi = argi + 1
    elseif flag == "--out" and value then
        outPath = value
        argi = argi + 2
    elseif flag == "--retail" and value then
        retailPath = value
        argi = argi + 2
    else
        io.stderr:write("usage: lua dev/scripts/file-map.lua [--refresh] [--out <path>] [--retail <file>]\n")
        os.exit(2)
    end
end
-- The stamp covers the default retail-only list only.
if refresh and retailPath ~= "dev/scripts/retail-only.lua" then
    io.stderr:write("--refresh reads the default retail-only list; drop --retail\n")
    os.exit(2)
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

local function writeFile(path, text)
    local f, err = io.open(path, "wb")
    if not f then return false, err end
    local wrote, werr = f:write(text)
    local closed, cerr = f:close()
    if wrote and closed then return true end
    os.remove(path)
    return false, werr or cerr or ("cannot write " .. path)
end

-- Lua 5.1's popen gives no exit status, so the command must print OK_MARK
-- last for its lines to count; nil otherwise.
local OK_MARK = "::file-map-ok"
local function commandOk(cmd)
    local lines = commandLines(cmd .. " && echo " .. OK_MARK)
    if lines[#lines] ~= OK_MARK then return nil end
    lines[#lines] = nil
    return lines
end

local function winPath(path) return (path:gsub("/", "\\")) end

-- A --refresh run keeps its scratch files in a folder of its own beside the
-- map; it is removed on every exit after it exists.
local runDir
local function refreshExit(code, msg)
    if msg then print("[file-map] " .. msg) end
    if runDir then
        commandLines("rmdir /s /q \"" .. winPath(runDir) .. "\" 2>nul")
        if commandLines("if exist \"" .. winPath(runDir) .. "\" echo left")[1] == "left" then
            print("[file-map] note: could not remove " .. runDir)
        end
    end
    os.exit(code)
end

-- --refresh: the output path, the stamp, and an exit when the map is current.
-- The stamp the inputs give now: nil when git cannot say, which never
-- matches. The hashes cover content, so a second edit to an already modified
-- file still changes it.
local function inputStamp()
    local scratch = runDir .. "/scratch"
    local head = commandOk("git rev-parse HEAD")
    local edits = commandOk("git diff HEAD --binary -- " .. REFRESH_INPUTS .. " > \"" .. scratch
        .. "\" && git hash-object \"" .. scratch .. "\"")
    local new = commandOk("git -c core.quotePath=false ls-files --others --exclude-standard -- " .. REFRESH_INPUTS)
    local newHashes = new and #new == 0 and {}
    if new and #new > 0 and writeFile(scratch, table.concat(new, "\n") .. "\n") then
        newHashes = commandOk("git hash-object --stdin-paths < \"" .. scratch .. "\"")
    end
    os.remove(scratch)
    if not (head and head[1] and head[1]:match("^%x+$") and edits and edits[1] and edits[1]:match("^%x+$")
        and newHashes and #newHashes == #new) then
        return nil
    end
    return table.concat({ head[1], edits[1], table.concat(new, "\n"), table.concat(newHashes, "\n") }, "\n")
        .. "\n"
end
local stamp
if refresh then
    if not outPath then
        local gitDir = commandOk("git rev-parse --path-format=absolute --git-dir")
        local commonDir = commandOk("git rev-parse --path-format=absolute --git-common-dir")
        if not (gitDir and gitDir[1] and commonDir and commonDir[1]) then
            refreshExit(1, "git could not name this checkout's git dir, so the map's place is unknown")
        end
        outPath = gitDir[1] ~= commonDir[1] and (gitDir[1] .. "/FILE-MAP.md") or "dev/docs/FILE-MAP.md"
    end
    -- move /Y would put the map inside a folder named as the destination.
    if commandLines("if exist \"" .. winPath(outPath) .. "\\*\" echo folder")[1] == "folder" then
        refreshExit(1, outPath .. " is a folder; give --out a file path")
    end
    -- mkdir fails on an existing folder, so no two runs share one. It also
    -- makes missing parents, such as the gitignored dev/docs of a fresh clone.
    for n = 1, 20 do
        local dir = outPath .. ".run" .. os.time() .. "-" .. n
        if commandOk("mkdir \"" .. winPath(dir) .. "\" 2>nul") then
            runDir = dir
            break
        end
    end
    if not runDir then refreshExit(1, "cannot make a folder beside " .. outPath) end
    stamp = inputStamp()
    local current, tail = readFile(outPath), stamp and (STAMP_OPEN .. stamp .. STAMP_CLOSE)
    if tail and current and current:sub(-#tail) == tail then
        refreshExit(0, "current: " .. outPath)
    end
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

local function trim(s)
    return s:match("^%s*(.-)%s*$")
end

-- The token starting at i: "name", "string", "comment" or "other", and its
-- last position.
local function token(text, i)
    local c = text:sub(i, i)
    if c == "-" and text:sub(i + 1, i + 1) == "-" then
        local eq = text:match("^%-%-%[(=*)%[", i)
        if eq then
            local _, e = text:find("]" .. eq .. "]", i, true)
            return "comment", e or #text
        end
        local e = text:find("\n", i, true)
        return "comment", e and e - 1 or #text
    end
    if c == "[" then
        local eq = text:match("^%[(=*)%[", i)
        if eq then
            local _, e = text:find("]" .. eq .. "]", i, true)
            return "string", e or #text
        end
    end
    if c == '"' or c == "'" then
        local j = i + 1
        while j <= #text do
            local d = text:sub(j, j)
            if d == "\\" then
                j = j + 2
            elseif d == c or d == "\n" then
                return "string", j
            else
                j = j + 1
            end
        end
        return "string", #text
    end
    local _, e = text:find("^[%a_][%w_]*", i)
    if e then return "name", e end
    _, e = text:find("^%d[%w%.]*", i)
    return "other", e or i
end

-- Calls fn(kind, first, last) for each token from `from` on until fn returns
-- true. Punctuation other than "-" and "[" is skipped.
local function eachToken(text, from, fn)
    local i = from
    while true do
        i = text:find("[%-%[\"'%w_]", i)
        if not i then return end
        local kind, e = token(text, i)
        if fn(kind, i, e) then return end
        i = e + 1
    end
end

-- Comments blanked to spaces, newlines and positions kept, so a pattern never
-- matches inside one.
local function stripComments(text)
    local parts, last = {}, 1
    eachToken(text, 1, function(kind, s, e)
        if kind == "comment" then
            parts[#parts + 1] = text:sub(last, s - 1)
            parts[#parts + 1] = (text:sub(s, e):gsub("[^\n]", " "))
            last = e + 1
        end
    end)
    parts[#parts + 1] = text:sub(last)
    return table.concat(parts)
end

local OPENS = { ["function"] = true, ["if"] = true, ["do"] = true, ["repeat"] = true }
local CLOSES = { ["end"] = true, ["until"] = true }

-- The last position of the function whose keyword starts at `start`.
local function blockEnd(code, start)
    local depth, stop = 0, #code
    eachToken(code, start, function(kind, s, e)
        if kind ~= "name" then return end
        local word = code:sub(s, e)
        if OPENS[word] then
            depth = depth + 1
        elseif CLOSES[word] then
            depth = depth - 1
            if depth == 0 then
                stop = e
                return true
            end
        end
    end)
    return stop
end

-- The bracket closing the one at `open`, skipping strings; the end of the
-- text when it does not balance.
local function matchClose(code, open)
    local depth, i = 0, open
    while true do
        i = code:find("[(){}%[%]\"']", i)
        if not i then return #code end
        local c = code:sub(i, i)
        if c == '"' or c == "'" or (c == "[" and code:find("^%[=*%[", i)) then
            local _, e = token(code, i)
            i = e
        elseif c == "(" or c == "{" or c == "[" then
            depth = depth + 1
        else
            depth = depth - 1
            if depth == 0 then return i end
        end
        i = i + 1
    end
end

-- The comma-separated pieces of an argument list or table body, trimmed. A
-- function body inside is one unit, so its own commas do not split.
local function splitTop(inner)
    local pieces, depth, last, i = {}, 0, 1, 1
    local fn = 0
    while true do
        if fn and fn < i then fn = inner:find("%f[%w_]function%f[^%w_]", i) end
        i = inner:find("[(){}%[%],\"']", i)
        if not i then break end
        local c = inner:sub(i, i)
        if fn and fn < i then
            i = blockEnd(inner, fn)
        elseif c == '"' or c == "'" or (c == "[" and inner:find("^%[=*%[", i)) then
            local _, e = token(inner, i)
            i = e
        elseif c == "(" or c == "{" or c == "[" then
            depth = depth + 1
        elseif c == ")" or c == "}" or c == "]" then
            depth = depth - 1
        elseif depth == 0 then
            pieces[#pieces + 1] = trim(inner:sub(last, i - 1))
            last = i + 1
        end
        i = i + 1
    end
    local tail = trim(inner:sub(last))
    if tail ~= "" then pieces[#pieces + 1] = tail end
    return pieces
end

local function callArgs(code, open)
    local close = matchClose(code, open)
    return splitTop(code:sub(open + 1, close - 1)), close
end

local function tableAt(text, at)
    return text:sub(at, matchClose(text, at))
end

local function localTable(text, name)
    local at = text:match("local%s+" .. name .. "%s*=%s*(){")
    return at and tableAt(text, at) or nil
end

-- A list element as table text: an inline table, or a name for a local table
-- in `scope` or else the file; nil when it is neither.
local function entryText(code, scope, element)
    if element:sub(1, 1) == "{" then return element end
    if element:match("^[%a_][%w_]*$") then return localTable(scope, element) or localTable(code, element) end
    return nil
end

local function prevChar(code, at)
    local b = at - 1
    while b > 0 and code:find("^%s", b) do b = b - 1 end
    return code:sub(b, b), b
end

local function nextCharAt(code, at)
    return code:match("^%s*()", at)
end

local failures = {}
local function fail(msg) failures[#failures + 1] = msg end

local tracked, trackedSet = {}, {}
for _, path in ipairs(commandLines("git ls-files -- Core GUI Modules KitnEssentials_Options")) do
    tracked[#tracked + 1] = path
    trackedSet[path] = true
end

local sources, codeOf = {}, {}
for _, path in ipairs(tracked) do
    if path:match("%.lua$") then
        sources[path] = readFile(path) or ""
        codeOf[path] = stripComments(sources[path])
    end
end

-- Load lists, through the same resolver the load-order proof uses. Lua 5.1's
-- popen close returns no exit status, so the output is checked instead: every
-- non-zero exit of load-list.lua prints a MISSING line or a Lua error.
local interpreter = arg[-1] or "lua"
local function loadListCommand(client)
    local script = " dev/scripts/load-list.lua --client " .. client .. " 2>&1"
    if not interpreter:find(" ", 1, true) then return interpreter .. script end
    local cmd = '"' .. interpreter .. '"' .. script
    if package.config:sub(1, 1) == "\\" then cmd = '"' .. cmd .. '"' end
    return cmd
end

-- A missing file prints a MISSING line and its bare path; the MISSING line
-- reports it.
local function readLoadList(client)
    local lines = commandLines(loadListCommand(client))
    local label = "load-list.lua --client " .. client
    local missingSet = {}
    for _, line in ipairs(lines) do
        local path = line:match("^MISSING: (.+)$")
        if path then missingSet[path] = true end
    end
    local loadedSet, manifestList, tocSeen = {}, {}, {}
    for _, line in ipairs(lines) do
        local toc = line:match("^# (.+)$")
        if toc then
            tocSeen[toc] = true
        elseif not (line:match("^<inline> ") or line:match("^%s*$") or missingSet[line]) then
            if fileExists(line) then
                loadedSet[line] = true
                if line:match("%.xml$") then manifestList[#manifestList + 1] = line end
            else
                fail(label .. ": " .. line)
            end
        end
    end
    for _, toc in ipairs(TOCS) do
        if not tocSeen[toc] then fail(label .. " printed no header for " .. toc) end
    end
    if next(loadedSet) == nil then fail(label .. " printed no files") end
    return loadedSet, manifestList
end

local loaded, manifests = readLoadList("standard")
local foreverLoaded, foreverManifests = readLoadList("camelot")
for _, path in ipairs(tracked) do
    if path:match("%.lua$") and not (loaded[path] or foreverLoaded[path]) then
        fail("tracked but loaded by neither client: " .. path)
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

local foreverAllowed = {}
local allowedTable = (codeOf[AVAILABILITY_FILE] or ""):match("local%s+FOREVER_ALLOWED%s*=%s*(%b{})")
if allowedTable then
    for id in allowedTable:gmatch("([%a_][%w_]*)%s*=%s*true") do foreverAllowed[id] = true end
else
    fail("FOREVER_ALLOWED not found in " .. AVAILABILITY_FILE)
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

-- Whether the code at `at` continues an expression: `or`, `and`, or any
-- operator or bracket. A new statement starts with a name.
local function continues(code, at)
    local word = code:match("^%s*([%a_][%w_]*)", at)
    if word then return word == "or" or word == "and" end
    local mark = code:match("^%s*(%p)", at)
    return mark ~= nil and mark ~= ";"
end

-- File-level (column-0) string constants, by name: a whole line that the next
-- code does not continue. A name given two values is dropped.
local constsOf = {}
for path, code in pairs(codeOf) do
    local consts = {}
    for lineAt, line in ("\n" .. code):gmatch("\n()([^\n]*)") do
        local name, value = line:match('^local%s+([%a_][%w_]*)%s*=%s*"([^"\\]*)"%s*$')
        if name and continues(code, lineAt + #line) then name = nil end
        if name and consts[name] == nil then
            consts[name] = value
        elseif name and consts[name] ~= value then
            consts[name] = false
        end
    end
    constsOf[path] = consts
end

local function constant(path, name)
    local value = constsOf[path] and constsOf[path][name]
    return value or nil
end

-- A string literal's text; nil for one with escapes, which is not decoded.
local function literal(expr)
    return expr:match('^"([^"\\]*)"$') or expr:match("^'([^'\\]*)'$")
end

local function idValue(path, expr)
    return literal(expr) or (expr:match("^[%a_][%w_]*$") and constant(path, expr))
end

local function tableFieldsRaw(tableText)
    local raw = {}
    local inner = tableText:sub(2, -2)
    for _, piece in ipairs(splitTop(inner)) do
        local key, value = piece:match("^([%a_][%w_]*)%s*=%s*(.-)$")
        if key and value:sub(1, 1) ~= "=" then raw[key] = value end
    end
    return raw
end

-- Each element of a tab list; one that is not a readable
-- { id = ..., label = ... } entry comes back as `unread`.
local function listIds(path, code, scope, listText, kids)
    for _, element in ipairs(splitTop(listText:sub(2, -2))) do
        local entry = entryText(code, scope, element)
        local raw = entry and tableFieldsRaw(entry) or {}
        local id = raw.id and idValue(path, raw.id)
        if id then
            kids[#kids + 1] = { id = id, label = raw.label and literal(raw.label) or nil, labeled = true }
        else
            kids[#kids + 1] = { unread = (element:gsub("%s+", " ")) }
        end
    end
end

-- A local tab table, plus every local table an ipairs loop copies into it.
local function localTableIds(path, code, name, kids)
    local own = localTable(code, name)
    if own then listIds(path, code, code, own, kids) end
    for source in code:gmatch("ipairs%(%s*([%a_][%w_]*)%s*%)%s*do%s*" .. name .. "%[") do
        local copied = localTable(code, source)
        if copied then listIds(path, code, code, copied, kids) end
    end
end

-- The whole Register*( ... ) call, or the rest of the file when its
-- parentheses do not balance.
local function callSpan(code, open)
    return code:sub(open, matchClose(code, open))
end

local BLOCK_ENDS = { ["end"] = true, ["else"] = true, ["elseif"] = true, ["until"] = true }

-- A function tab list: the lists its `return` statements give, outside nested
-- functions, read longest first, since the longest shows the on-screen order
-- and a shorter one is a subset. False when a return is not a literal list,
-- which the map cannot follow.
local function returnedIds(path, code, fnText, kids)
    local lists, literalOnly, skipTo = {}, true, 0
    eachToken(fnText, 1, function(kind, ts, te)
        if kind ~= "name" or ts <= skipTo then return end
        local word = fnText:sub(ts, te)
        if word == "function" and ts > 1 then
            skipTo = blockEnd(fnText, ts)
        elseif word == "return" then
            -- A return ends its block, so a literal list is followed by the
            -- block's end; anything else extends the returned expression.
            local at = nextCharAt(fnText, te + 1)
            local close = fnText:sub(at, at) == "{" and matchClose(fnText, at)
            local after = close and nextCharAt(fnText, close + 1)
            local follows = after and (fnText:match("^([%a_][%w_]*)", after) or fnText:sub(after, after))
            if follows and (BLOCK_ENDS[follows] or follows == "" or follows == ";") then
                lists[#lists + 1] = fnText:sub(at, close)
            else
                literalOnly = false
            end
        end
    end)
    for i, list in ipairs(lists) do lists[i] = { text = list, size = #splitTop(list:sub(2, -2)), order = i } end
    table.sort(lists, function(a, b)
        if a.size ~= b.size then return a.size > b.size end
        return a.order < b.order
    end)
    for _, list in ipairs(lists) do listIds(path, code, fnText, list.text, kids) end
    return literalOnly
end

local children, labels = {}, {}
for _, path in ipairs(tracked) do
    local code = codeOf[path]
    if code and underAny(path, PAGE_ROOTS) then
        for kind, open, first, argAt in code:gmatch('Register(%w*)()%(%s*("?[%w_]+"?)%s*,%s*()') do
            local parent = idValue(path, first)
            if parent then
                local kids = {}
                local word = code:match("^([%a_][%w_]*)", argAt)
                if code:sub(argAt, argAt) == "{" then
                    listIds(path, code, code, tableAt(code, argAt), kids)
                elseif STRIP_CALLS[kind] then
                    if word == "function" then
                        if not returnedIds(path, code, code:sub(argAt, blockEnd(code, argAt)), kids) then
                            fail("tab function returns a list that is not a literal: " .. path .. ": " .. parent)
                        end
                    elseif word then
                        localTableIds(path, code, word, kids)
                    end
                    if #kids == 0 then fail("tab strip not followed: " .. path .. ": " .. parent) end
                elseif kind == "Content" and word == "function" then
                    local span = callSpan(code, open)
                    if span:find("registeredContent%[") then
                        for id in span:gmatch('registeredContent%[%s*"([^"]+)"%s*%]') do kids[#kids + 1] = { id = id } end
                        for var, list in span:gmatch("for%s+[%w_]+%s*,%s*([%a_][%w_]*)%s+in%s+ipairs%(%s*(%b{})%s*%)") do
                            if not list:find("[={]", 2) and span:find("registeredContent%[%s*" .. var .. "%s*%]") then
                                for id in list:gmatch('"([^"]+)"') do kids[#kids + 1] = { id = id } end
                            end
                        end
                    end
                end
                local all = children[parent] or {}
                local named = labels[parent] or {}
                for _, kid in ipairs(kids) do
                    if kid.unread then
                        fail("tab id not read: " .. path .. ": " .. parent .. ": " .. kid.unread)
                    else
                        if kid.labeled and not kid.label then
                            fail("tab label not read: " .. path .. ": " .. parent .. ": " .. kid.id)
                        end
                        local known = false
                        for _, id in ipairs(all) do
                            if id == kid.id then known = true break end
                        end
                        if not known then all[#all + 1] = kid.id end
                        named[kid.id] = named[kid.id] or kid.label
                    end
                end
                if #all > 0 then
                    children[parent] = all
                    labels[parent] = named
                end
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

local function paramList(text)
    local params = {}
    for _, p in ipairs(splitTop(text)) do
        if p:match("^[%a_][%w_]*$") then params[#params + 1] = p end
    end
    return params
end

-- Functions a page can reach by name: `local function N(`, `function N(`,
-- `N = function(` and `local N = function(` for a declared local N. Exports
-- are column-0 `function X.Name(` or `X:Name(` definitions and
-- `X.Name = <local function>` aliases in settings files, by last name.
local defsOf, exports, defAt = {}, {}, {}
local function addDef(path, list, name, start, params)
    local def = { path = path, name = name, start = start, stop = blockEnd(codeOf[path], start), params = paramList(params) }
    list[name] = list[name] or {}
    table.insert(list[name], def)
    defAt[path] = defAt[path] or {}
    defAt[path][start] = def
    return def
end

for _, path in ipairs(tracked) do
    local code = codeOf[path]
    if code and underAny(path, PAGE_ROOTS) then
        local localNames = {}
        for at in code:gmatch("%f[%w_]local%s+()") do
            local i = at
            while true do
                local name, after = code:match("^([%a_][%w_]*)%s*()", i)
                if not name or name == "function" then break end
                localNames[name] = true
                if code:sub(after, after) ~= "," then break end
                i = nextCharAt(code, after + 1)
            end
        end
        local defs, seenStart = {}, {}
        for start, name, params in code:gmatch("%f[%w_]()function%s+([%a_][%w_]*)%s*%(([^)]*)%)") do
            seenStart[start] = true
            addDef(path, defs, name, start, params)
        end
        for nameAt, name, start, params in code:gmatch("%f[%w_]()([%a_][%w_]*)%s*=%s*()function%s*%(([^)]*)%)") do
            local before = prevChar(code, nameAt)
            if localNames[name] and not seenStart[start] and before ~= "." and before ~= ":" then
                addDef(path, defs, name, start, params)
            end
        end
        for _, list in pairs(defs) do
            table.sort(list, function(a, b) return a.start < b.start end)
        end
        defsOf[path] = defs
        if path:sub(1, #OPTIONS_ROOT) == OPTIONS_ROOT then
            for lineAt, line in ("\n" .. code):gmatch("\n()([^\n]*)") do
                local name, params = line:match("^function%s+[%a_][%w_]*[%.:][%w_%.:]-([%a_][%w_]*)%s*%(([^)]*)%)")
                if name then addDef(path, exports, name, lineAt - 1, params) end
                local alias, target = line:match("^[%a_][%w_%.]*%.([%a_][%w_]*)%s*=%s*([%a_][%w_]*)%s*$")
                local def = alias and defs[target] and defs[target][#defs[target]]
                if def then
                    exports[alias] = exports[alias] or {}
                    table.insert(exports[alias], def)
                end
            end
        end
    end
end

-- The definition a use at `at` refers to: the last one before it, else the
-- first after it (a forward-declared local).
local function pickDef(list, at)
    local before, after
    for _, def in ipairs(list or {}) do
        if def.start < at then
            before = def
        elseif not after then
            after = def
        end
    end
    return before or after
end

local function enclosingDef(path, at)
    local best
    for _, list in pairs(defsOf[path] or {}) do
        for _, def in ipairs(list) do
            if def.start < at and def.stop > at and (not best or def.start > best.start) then best = def end
        end
    end
    return best
end

-- A string from a literal, a bound parameter, `<param>.<field>` or
-- `<param>.<field> or "<default>"`; nil when the value is only known at run
-- time. The default applies only when the bound table lacks the field; a
-- field it holds but could not read is false there.
local function resolveExpr(path, expr, binding)
    local text = literal(expr)
    if text then return text end
    local var, field, default = expr:match("^([%a_][%w_]*)%.([%a_][%w_]*)%s+or%s+(.+)$")
    if var then default = literal(default) end
    if not var then var, field = expr:match("^([%a_][%w_]*)%.([%a_][%w_]*)$") end
    if var then
        local bound = binding and binding[var]
        if type(bound) ~= "table" then return nil end
        local value = bound[field]
        if type(value) == "string" then return value end
        if value == nil then return default end
        return nil
    end
    if expr:match("^[%a_][%w_]*$") then
        local bound = binding and binding[expr]
        if type(bound) == "string" then return bound end
        return constant(path, expr)
    end
    return nil
end

local function tableFields(path, tableText, binding)
    local fields = {}
    for key, value in pairs(tableFieldsRaw(tableText)) do
        fields[key] = resolveExpr(path, value, binding) or false
    end
    return fields
end

local function bindArgs(path, params, args, binding)
    local bound = {}
    for i, param in ipairs(params) do
        local arg = args[i]
        if arg then
            if arg:sub(1, 1) == "{" then
                bound[param] = tableFields(path, arg, binding)
            elseif arg:match("^[%a_][%w_]*$") and binding and type(binding[arg]) == "table" then
                bound[param] = binding[arg]
            else
                bound[param] = resolveExpr(path, arg, binding)
            end
        end
    end
    return bound
end

-- A strip a page draws with CreateSubTabs inside its own content; its views
-- are code branches, not registered ids, so the cards after it are not split
-- by view.
local UNREAD_STRIP = "in-page tabs (dynamic)"

-- The labels of a CreateSubTabs `tabs` value: a literal table, a local table
-- of the same file, or a GUIFrame.NAME table a GUI file defines.
local function stripLabels(path, expr)
    local list
    if expr:sub(1, 1) == "{" then
        list = expr
    elseif expr:match("^[%a_][%w_]*$") then
        list = localTable(codeOf[path], expr)
    else
        local shared = expr:match("^GUIFrame%.([%a_][%w_]*)$")
        for _, guiPath in ipairs(shared and tracked or {}) do
            local code = guiPath:sub(1, 4) == "GUI/" and codeOf[guiPath]
            local at = code and code:match("GUIFrame%." .. shared .. "%s*=%s*(){")
            if at then list = tableAt(code, at) end
        end
    end
    if not list then return nil end
    local names = {}
    for _, element in ipairs(splitTop(list:sub(2, -2))) do
        local entry = entryText(codeOf[path], codeOf[path], element)
        local label = entry and tableFieldsRaw(entry).label
        label = label and literal(label)
        if not label then return nil end
        names[#names + 1] = label
    end
    return #names > 0 and table.concat(names, " / ") or nil
end

local function dynamic(expr)
    return "dynamic `" .. expr:gsub("%s+", " ") .. "`"
end

-- Appends to `out` the card titles of code[s..e], expanding the functions it
-- names, in source order. A named function defined inside the span is
-- skipped where it is defined and walked where it is called, with that
-- call's arguments.
local function walk(path, s, e, binding, depth, onPath, out)
    local code = codeOf[path]
    local skipTo = 0
    eachToken(code, s, function(kind, ts, te)
        if ts > e then return true end
        if kind ~= "name" or ts <= skipTo then return end
        local nested = ts > s and defAt[path] and defAt[path][ts]
        if nested then
            skipTo = nested.stop
            return
        end
        local word = code:sub(ts, te)
        local prev, prevAt = prevChar(code, ts)
        local nextAt = nextCharAt(code, te + 1)
        local nextC = code:sub(nextAt, nextAt)
        local member = prev == ":" or (prev == "." and code:sub(prevAt - 1, prevAt - 1) ~= ".")
        if member and nextC == "(" and word == "CreateCard" then
            local args = callArgs(code, nextAt)
            local title = args[2] or ""
            local text = resolveExpr(path, title, binding)
            if text ~= "Error" then out[#out + 1] = text or dynamic(title) end
            return
        end
        if member and nextC == "(" and BUILDER_DEFAULTS[word] ~= nil then
            local args = callArgs(code, nextAt)
            local configText = args[3] or ""
            local raw = configText:sub(1, 1) == "{" and tableFieldsRaw(configText) or {}
            if raw.title then
                out[#out + 1] = resolveExpr(path, raw.title, binding) or dynamic(raw.title)
            elseif configText:sub(1, 1) == "{" or configText == "" then
                out[#out + 1] = BUILDER_DEFAULTS[word] or dynamic("config.title")
            else
                out[#out + 1] = dynamic(configText .. ".title")
            end
            return
        end
        if member and nextC == "(" and word == "CreateSubTabs" then
            local configText = callArgs(code, nextAt)[3] or ""
            local raw = configText:sub(1, 1) == "{" and tableFieldsRaw(configText) or {}
            local labelsText = raw.tabs and stripLabels(path, raw.tabs)
            out[#out + 1] = labelsText and ("in-page tabs (" .. labelsText .. ")") or UNREAD_STRIP
            return
        end
        if nextC == "=" and code:sub(nextAt + 1, nextAt + 1) ~= "=" then return end
        local def
        if member then
            local list = exports[word]
            if nextC == "(" and list and #list == 1 then def = list[1] end
        else
            def = pickDef(defsOf[path] and defsOf[path][word], ts)
        end
        if not def or onPath[def] or depth >= EXPAND_DEPTH then return end
        local bound = {}
        if nextC == "(" then bound = bindArgs(path, def.params, callArgs(code, nextAt), binding) end
        onPath[def] = true
        walk(def.path, def.start, def.stop, bound, depth + 1, onPath, out)
        onPath[def] = nil
    end)
end

-- The ids a Register call at `at` registers, each with the parameter values
-- of its call: a string, a constant, a parameter of the enclosing function
-- (once per call of it in the file), or a field of an ipairs loop variable
-- (once per entry of the looped local table).
local function registrations(path, at, first)
    local id = idValue(path, first)
    if id then return { { id = id } } end
    local var, field = first:match("^([%a_][%w_]*)%.([%a_][%w_]*)$")
    var = var or first:match("^([%a_][%w_]*)$")
    if not var then return {} end
    local code = codeOf[path]
    local found = {}
    local owner = enclosingDef(path, at)
    local isParam = false
    for _, p in ipairs(owner and owner.params or {}) do
        if p == var then isParam = true end
    end
    if isParam then
        eachToken(code, 1, function(kind, ts, te)
            if kind ~= "name" or code:sub(ts, te) ~= owner.name then return end
            local prev, b = prevChar(code, ts)
            if prev == "." or prev == ":" or code:sub(b - 7, b) == "function" then return end
            local nextAt = nextCharAt(code, te + 1)
            if code:sub(nextAt, nextAt) ~= "(" then return end
            local bound = bindArgs(path, owner.params, callArgs(code, nextAt), nil)
            local value = bound[var]
            if field then value = type(value) == "table" and value[field] or nil end
            if type(value) == "string" then found[#found + 1] = { id = value, binding = bound } end
        end)
        return found
    end
    if not field then return found end
    local listName
    for loopAt, name in code:gmatch("()for%s+[%w_]+%s*,%s*" .. var .. "%s+in%s+ipairs%(%s*([%a_][%w_]*)%s*%)") do
        if loopAt < at then listName = name end
    end
    local list = listName and localTable(code, listName)
    if not list then return found end
    for _, entry in ipairs(splitTop(list:sub(2, -2))) do
        if entry:sub(1, 1) == "{" then
            local fields = tableFields(path, entry, nil)
            if fields[field] then found[#found + 1] = { id = fields[field], binding = { [var] = fields } } end
        end
    end
    return found
end

local cardsOf, registeredIn = {}, {}
for _, path in ipairs(tracked) do
    local code = codeOf[path]
    if code and underAny(path, PAGE_ROOTS) then
        for kind, open in code:gmatch("[:.]Register(%w+)%s*()%(") do
            if kind == "Content" or kind == "TabbedContent" then
                local args, close = callArgs(code, open)
                local regs = registrations(path, open, args[1] or "")
                if #regs == 0 and not REGISTRY_FILES[path] then
                    fail("content id not read: " .. path .. ": " .. (args[1] or ""))
                end
                for _, reg in ipairs(regs) do
                    local cards = cardsOf[reg.id] or {}
                    walk(path, open, close, reg.binding, 0, {}, cards)
                    cardsOf[reg.id] = cards
                    registeredIn[reg.id] = registeredIn[reg.id] or {}
                    registeredIn[reg.id][path] = true
                end
            end
        end
    end
end

-- Whether a content id exists on WoW Forever, from the files that register
-- it and the client policy. Card-level hiding inside a page is not read; a
-- reader for it would mark the card titles walk() collects.
local function foreverNote(id)
    local onRetail, onForever = false, false
    for path in pairs(registeredIn[id] or {}) do
        onRetail = onRetail or loaded[path] == true
        onForever = onForever or foreverLoaded[path] == true
    end
    if onRetail and not onForever then return "retail only: page not loaded on Forever" end
    if not foreverAllowed[id] then
        if onForever and not onRetail then return "on neither client: Forever-only page, id withheld on Forever" end
        return "retail only: id withheld on Forever"
    end
    if onForever and not onRetail then return "Forever only" end
    return nil
end

-- A strip whose labels cannot be read is left out on an id that registers
-- its tabs as children, since those print as nested tabs.
local function cardText(id)
    local cards = {}
    for _, card in ipairs(cardsOf[id] or {}) do
        if card ~= UNREAD_STRIP or not children[id] then cards[#cards + 1] = card end
    end
    if #cards == 0 then return "no cards" end
    return table.concat(cards, CARD_SEP)
end

local function idText(id)
    local note = foreverNote(id)
    return "(`" .. id .. "`" .. (note and "; " .. note or "") .. ")"
end

local function tabLines(add, parent, indent, seen)
    for _, id in ipairs(children[parent] or {}) do
        if not seen[id] then
            seen[id] = true
            local label = labels[parent] and labels[parent][id]
            local head = label and ('Tab "' .. label .. '" ') or "Chained "
            add(indent .. "- " .. head .. idText(id) .. ": " .. cardText(id))
            tabLines(add, id, indent .. "  ", seen)
        end
    end
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
        add("Tabs and cards:")
        add("- " .. (children[row.id] and "Header " or "Page ") .. idText(row.id) .. ": " .. cardText(row.id))
        tabLines(add, row.id, "", { [row.id] = true })
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
add("Forever (`--client camelot`) loads these in their place:")
add("")
for _, path in ipairs(foreverManifests) do
    if not loaded[path] then add("- `" .. path .. "`") end
end
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
    "Tabs and cards: each row's own cards (Header: shown above every tab; Page: a row with no tabs), " ..
        "then each tab and its cards in source order, nested tabs indented. Chained: a page drawn inside its parent's. " ..
        "Dynamic: a title set at run time. In-page tabs: a strip a page draws inside itself, " ..
        "printed where it is drawn; the cards after it are not split by view. " ..
        "Cards on every run-time branch are listed, so a tab can show fewer cards than listed on either client.",
    "",
    "Forever: `retail only: page not loaded on Forever` means the camelot load list skips the page file; " ..
        "`retail only: id withheld on Forever` means Core/Availability.lua does not admit the id. " ..
        "A card a page hides or adds on one client by its own check is not marked.",
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

if refresh then
    -- An input that changed during the scan leaves the map unstamped, so the
    -- next run rebuilds.
    local tmp = runDir .. "/map"
    local published, why, note = false, "self-check failed", ""
    if #failures == 0 then
        local text = docText
        if not stamp then
            note = "; git gave no stamp, so the next run rebuilds"
        elseif inputStamp() ~= stamp then
            note = "; inputs changed during the run, so the next run rebuilds"
        else
            text = docText .. STAMP_OPEN .. stamp .. STAMP_CLOSE
        end
        local ok, err = writeFile(tmp, text)
        if ok then
            -- move /Y replaces the map in one step and leaves it in place when
            -- the move fails; os.rename refuses an existing target on Windows.
            local moved = commandLines("move /Y \"" .. winPath(tmp) .. "\" \"" .. winPath(outPath)
                .. "\" 2>&1 && echo " .. OK_MARK)
            ok = moved[#moved] == OK_MARK
            err = moved[1]
        end
        published, why = ok, err
    end
    if published then
        print("[file-map] regenerated at " .. sha .. ": " .. outPath .. note)
    else
        local kept = fileExists(outPath) and "kept the previous map at " or "no map at "
        print("[file-map] " .. kept .. outPath .. "; this run did not publish: " .. tostring(why))
        for _, msg in ipairs(failures) do print("FAIL: " .. msg) end
    end
    refreshExit(published and 0 or 1)
elseif outPath then
    if not writeFile(outPath, docText) then
        io.stderr:write("cannot write ", outPath, "\n")
        os.exit(2)
    end
else
    io.write(docText)
end
for _, msg in ipairs(failures) do io.stderr:write("FAIL: ", msg, "\n") end
if #failures > 0 then os.exit(1) end
