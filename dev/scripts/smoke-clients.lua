-- smoke-clients.lua: say which game client loads each file a branch changed,
-- so a smoke handoff names the clients it must run on.
--
-- Run from the repo root with the local Lua interpreter:
--   lua dev/scripts/smoke-clients.lua [base]
--
-- base defaults to main. The changed set is `git diff --name-only base...HEAD`
-- plus uncommitted changes. Each path is looked up in the two load lists
-- (`load-list.lua --client standard` and `--client camelot`) and printed as
--   both | retail | forever | none | unlisted   <path>
-- none is a file that never ships. unlisted is a shipped file in neither load
-- list (an asset, a toc, a deleted file); it counts for both clients. The last
-- line, `Smoke on: ...`, is the answer. Always exits 0.

local _script = (arg[0] or ""):gsub("/", "\\")
local _dir = _script:match("^(.*\\)[^\\]+$") or ".\\dev\\scripts\\"
local S = dofile(_dir .. "_smoke_clients.lua")
local P = dofile(_dir .. "_apidocs_parser.lua")

local ROOT = P.resolveRepoRoot(arg[0])
local BASE = arg[1] or "main"

local function commandLines(cmd)
    local out = {}
    local p = io.popen(cmd)
    if p then
        for line in p:lines() do
            line = line:gsub("\r$", "")
            if line ~= "" then out[#out + 1] = line end
        end
        p:close()
    end
    return out
end

local function loadSet(client)
    local set, list = {}, P.loadList(ROOT, client, arg[-1])
    assert(#list >= 100,
        ("load-list.lua --client %s listed only %d files: run from the repo root"):format(client, #list))
    for _, path in ipairs(list) do set[path] = true end
    return set
end

local retail, forever = loadSet("standard"), loadSet("camelot")

local seen, changed = {}, {}
for _, cmd in ipairs({
    'git diff --name-only "' .. BASE .. '...HEAD"',
    "git diff --name-only HEAD",
    "git ls-files --others --exclude-standard",
}) do
    for _, path in ipairs(commandLines(cmd)) do
        if not seen[path] then
            seen[path] = true
            changed[#changed + 1] = path
        end
    end
end
table.sort(changed)

local classes = {}
for _, path in ipairs(changed) do
    local class = S.classify(path, retail, forever)
    classes[#classes + 1] = class
    print(("%-8s %s"):format(class, path))
end
print("Smoke on: " .. S.summary(classes))
