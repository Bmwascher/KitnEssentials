-- check-forever-api.lua: find Retail-only API and Blizzard globals in files
-- the Forever client loads. .luacheckrc and the drift check validate against
-- the Retail reference alone, so such a use passes them and fails only in game.
--
-- Run from the repo root with the local Lua interpreter (5.1 or 5.4):
--   lua dev/scripts/check-forever-api.lua [--soft] [--verbose]
--
-- Subjects: every .lua in `load-list.lua --client camelot`, embedded libraries
-- excluded. Two tiers, both against the Forever reference clone:
--   tier 1: a C_Namespace.Function call, Enum member or Register*Event
--           literal that the Retail API docs have and the Forever API docs
--           lack. The two doc sets differ little.
--   tier 2: a .luacheckrc global that no file Forever loads defines, and
--           that either the Forever clone defines in a file it does not load
--           (its addon is refused, or its manifest line is) or the Retail
--           docs alone list as a function. _forever_load.lua holds the load
--           rules.
-- A finding prints as `<file>  <symbol>`; --verbose adds where tier 2 found
-- the definition, and the manifest files that did not resolve.
--
-- Limits: a global the clone never defines by name (created in C, or built
-- from $parent) is never reported, and the harvest reads comments and strings
-- too. A Lua definition counts only at the start of a line, because text
-- matching cannot tell an indented global from a local; a global that a
-- loaded file defines indented, and an unloaded file defines at line start,
-- is therefore reported. A use guarded at run time (a nil check, a
-- KE.IS_FOREVER branch) is reported too. Record either kind in
-- dev/scripts/forever-api-allow.lua with the reason.
--
-- Exit 1 on a finding the allowlist does not cover, or on an allowlist entry
-- that no longer matches anything; --soft turns that into exit 0. Exit 2 when
-- the check could not run (an unreadable .luacheckrc, a missing or malformed
-- allowlist, no load list). A missing clone is a notice and exit 0 (CI has no
-- reference clones).

local SOFT, VERBOSE = false, false
for i = 1, #arg do
    if arg[i] == "--soft" then SOFT = true end
    if arg[i] == "--verbose" then VERBOSE = true end
end

local _script = (arg[0] or ""):gsub("/", "\\")
local _dir = _script:match("^(.*\\)[^\\]+$") or ".\\dev\\scripts\\"
local P = dofile(_dir .. "_apidocs_parser.lua")
local C = dofile(_dir .. "_api_drift_core.lua")
local L = dofile(_dir .. "_forever_load.lua")

-- The check could not run. Exit 2 keeps this apart from a finding.
local function fail(message)
    print("forever-api: " .. message)
    os.exit(2)
end

local ROOT = P.resolveRepoRoot(arg[0])
local ADDONS_SUB = "\\Interface\\AddOns"
local DOCS_SUB = ADDONS_SUB .. "\\Blizzard_APIDocumentationGenerated"

local clones = P.referenceClones(ROOT)
if not clones then
    print("forever-api: .wow-api-reference is not a git checkout; skipped")
    os.exit(0)
end

-- ---- tier 1: the two API doc sets -------------------------------------------
local function flatDocs(clone)
    local res = P.collectDocTables(clone .. DOCS_SUB)
    if res.filesRead < 500 then return nil, res.filesRead end
    return C.flattenDocs(res.tables)
end

local retail, retailRead = flatDocs(clones.retail)
local forever, foreverRead = flatDocs(clones.forever)
if not retail or not forever then
    print(("forever-api: API docs not readable (Retail %s, Forever %s files); skipped")
        :format(tostring(retail and "ok" or retailRead), tostring(forever and "ok" or foreverRead)))
    os.exit(0)
end

local function retailOnly(kind, key)
    return retail[kind][key] ~= nil and forever[kind][key] == nil
end

-- ---- tier 2: what the Forever client loads ---------------------------------
local ADDONS = clones.forever .. ADDONS_SUB

local function normalize(path)
    local parts = {}
    for part in path:gsub("/", "\\"):gmatch("[^\\]+") do
        if part == ".." then parts[#parts] = nil elseif part ~= "." then parts[#parts + 1] = part end
    end
    return table.concat(parts, "\\")
end

local loaded, unresolved = {}, {}
local function loadFile(path)
    path = normalize(path)
    local key = path:lower()
    if loaded[key] then return end
    local src = P.readAll(path)
    if not src then
        unresolved[#unresolved + 1] = path:sub(#ADDONS + 2)
        return
    end
    loaded[key] = true
    if key:match("%.xml$") then
        local dir = path:match("^(.*)\\[^\\]+$")
        for _, file in ipairs(L.xmlFiles(src)) do loadFile(dir .. "\\" .. file) end
    end
end

for _, addon in ipairs(P.listDirs(ADDONS)) do
    if not addon:find("Blizzard_APIDocumentation", 1, true) then
        local dir = ADDONS .. "\\" .. addon
        -- one manifest per addon: the plain one, or the mainline one where
        -- the folder has no plain one
        local toc = P.readAll(dir .. "\\" .. addon .. ".toc")
            or P.readAll(dir .. "\\" .. addon .. "_Mainline.toc")
        if toc and L.headerAllows(toc) then
            for _, file in ipairs(L.tocFiles(toc)) do loadFile(dir .. "\\" .. file) end
        end
    end
end

local defined, definedLoaded, definedIn, nSource = {}, {}, {}, 0
for _, ext in ipairs({ "*.lua", "*.xml" }) do
    for _, path in ipairs(P.listFiles(ADDONS, ext)) do
        if not path:find("Blizzard_APIDocumentation", 1, true) then
            local src = P.readAll(path)
            if src then
                nSource = nSource + 1
                local own = {}
                L.definitions(src, ext == "*.xml", own)
                local isLoaded = loaded[normalize(path):lower()]
                for id in pairs(own) do
                    defined[id] = true
                    if isLoaded then
                        definedLoaded[id] = true
                    else
                        definedIn[id] = definedIn[id] or path:sub(#ADDONS + 2)
                    end
                end
            end
        end
    end
end
if nSource < 1000 then
    print(("forever-api: only %d Forever source files read (sparse clone?); skipped"):format(nSource))
    os.exit(0)
end

local rcEnv = { files = {} }
local rcSrc = P.readAll(ROOT .. "\\.luacheckrc")
local rcChunk = rcSrc and P.loadSandboxed(rcSrc, "@.luacheckrc", rcEnv)
if not (rcChunk and pcall(rcChunk)) then fail("cannot read or load .luacheckrc") end
local rcNames = {}
for _, sym in ipairs(P.rcSymbols(rcEnv.globals)) do rcNames[sym] = true end
for _, sym in ipairs(P.rcSymbols(rcEnv.read_globals)) do rcNames[sym] = true end

-- ---- the Forever-loaded KE files --------------------------------------------
local allowOk, allow = pcall(dofile, _dir .. "forever-api-allow.lua")
if not allowOk or type(allow) ~= "table" then
    fail("forever-api-allow.lua does not load as a table: " .. tostring(allow))
end
for path, syms in pairs(allow) do
    if type(path) ~= "string" or type(syms) ~= "table" then
        fail("forever-api-allow.lua: each entry is [\"file\"] = { symbol = \"reason\" }")
    end
    for sym, reason in pairs(syms) do
        if type(sym) ~= "string" or type(reason) ~= "string" then
            fail("forever-api-allow.lua: " .. path .. " needs symbol = \"reason\" pairs")
        end
    end
end

local files = P.loadedLuaFiles(ROOT, "camelot", arg[-1])
if #files < 100 then
    fail(("only %d Forever-loaded files listed: run from the repo root"):format(#files))
end

local findings, allowed, usedAllow = {}, 0, {}
for _, path in ipairs(files) do
    local src = P.readAll(ROOT .. "\\" .. path:gsub("/", "\\"))
    if src then
        local used = C.newUsedSurface()
        C.harvestUsedFromSource(src, used)
        local hits, seen = {}, {}
        local function hit(sym)
            if not seen[sym] then
                seen[sym] = true
                hits[#hits + 1] = sym
            end
        end
        for key in pairs(used.nsCalls) do
            if retailOnly("functions", key) then hit(key) end
        end
        for key in pairs(used.enums) do
            if retailOnly("enums", key) then hit(key) end
        end
        for ev in pairs(used.events) do
            if retailOnly("events", ev) then hit("event " .. ev) end
        end
        -- a bare name is harvested from locals, comments and strings too, so
        -- it counts only as a declared global that no loaded file defines
        for name in pairs(used.names) do
            if rcNames[name] and not definedLoaded[name]
                and (retailOnly("functions", name) or defined[name]) then
                hit(name)
            end
        end
        table.sort(hits)
        local fileAllow = allow[path] or {}
        for _, sym in ipairs(hits) do
            if fileAllow[sym] then
                allowed = allowed + 1
                usedAllow[path .. "\0" .. sym] = true
            elseif VERBOSE and definedIn[sym] then
                findings[#findings + 1] = path .. "  " .. sym .. "  (defined in " .. definedIn[sym] .. ")"
            else
                findings[#findings + 1] = path .. "  " .. sym
            end
        end
    end
end

local stale = {}
for path, syms in pairs(allow) do
    for sym in pairs(syms) do
        if not usedAllow[path .. "\0" .. sym] then stale[#stale + 1] = path .. "  " .. sym end
    end
end
table.sort(stale)

print(("forever-api: %d Forever-loaded files, Retail %s vs Forever %s")
    :format(#files, P.readBuild(clones.retail), P.readBuild(clones.forever)))
print(("[RETAIL-ONLY] (%d)"):format(#findings))
for _, line in ipairs(findings) do print("  " .. line) end
print(("[STALE-ALLOW] (%d)"):format(#stale))
for _, line in ipairs(stale) do print("  " .. line) end
print(("allowlisted: %d"):format(allowed))
if VERBOSE then
    print(("[UNRESOLVED] (%d) manifest entries with no file in the Forever clone"):format(#unresolved))
    for _, line in ipairs(unresolved) do print("  " .. line) end
end

if (#findings > 0 or #stale > 0) and not SOFT then os.exit(1) end
os.exit(0)
