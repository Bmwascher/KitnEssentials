-- check-references-folders.lua — enforce the References/ folder rule.
--
-- Run from the repo root with the local Lua interpreter:
--   lua dev/scripts/check-references-folders.lua [--soft]
--
-- A reference is one addon family inside References/<Folder>/. Version folders
-- are grouped by family key: the folder name with a trailing `_old` and a
-- trailing version token stripped ("NorskenUI v8_old", "NorskenUI-v12.1.0.7"
-- and a bare "v2.2.0" all fold onto one key). Design-audit folders that hold
-- several unrelated addons therefore check per addon, not per folder.
--
-- Rules per family (canonical wording: reference-tracker skill, "References/
-- folder convention"):
--   [A] exactly one current (un-suffixed) copy   — two or more = FAIL
--   [B] at most two _old siblings                — more = FAIL
--   [C] no zip archives anywhere under References/ — FAIL
--   [D] _old copies with no current sibling      — note (orphan)
--   [E] addon files directly under References/<Folder>/ (no version folder)
--                                                — note (flat; wrap on refresh)
-- Exit 1 on any FAIL; --soft forces exit 0. References/ absent (CI, fresh
-- clone) — notice + exit 0.

local SOFT = false
for i = 1, #arg do
    if arg[i] == "--soft" then SOFT = true end
end

local _script = (arg[0] or ""):gsub("/", "\\")
local _dir = _script:match("^(.*\\)[^\\]+$") or ".\\dev\\scripts\\"
local P = dofile(_dir .. "_apidocs_parser.lua")

local root = P.resolveRepoRoot(arg[0])
local refs = root .. "\\References"

local function listFilesFlat(dir, pat)
    local out = {}
    local p = io.popen('dir /b /a-d "' .. dir .. '\\' .. pat .. '" 2>nul')
    if p then
        for line in p:lines() do out[#out + 1] = line end
        p:close()
    end
    return out
end

if #P.listDirs(refs) == 0 and #listFilesFlat(refs, "*") == 0 then
    print("[references] References/ not present — nothing to check")
    os.exit(0)
end

-- Family key: strip `_old`, then one trailing version token. A name that is
-- only a version ("v2.2.0", "2026-03-26") keys to "" — the folder itself.
local function familyKey(name)
    local n = name:gsub("_old$", "")
    if n:match("^v?%d[%w%.%-]*$") then return "" end
    n = n:gsub("%s*[%-_ ]v?%d[%w%.%-]*$", "")
    return n
end

local fails, notes = 0, 0
local function fail(msg) fails = fails + 1; print("[references] FAIL " .. msg) end
local function note(msg) notes = notes + 1; print("[references] note " .. msg) end

local folders = P.listDirs(refs)
table.sort(folders)
for _, folder in ipairs(folders) do
    local dir = refs .. "\\" .. folder
    if #listFilesFlat(dir, "*.toc") > 0 then
        note(folder .. ": addon files sit directly in the folder (flat copy) — wrap in a version folder on the next refresh")
    end
    local groups, order = {}, {}
    for _, child in ipairs(P.listDirs(dir)) do
        local key = familyKey(child)
        if not groups[key] then groups[key] = { current = {}, old = {} }; order[#order + 1] = key end
        if child:match("_old$") then
            table.insert(groups[key].old, child)
        else
            table.insert(groups[key].current, child)
        end
    end
    table.sort(order)
    for _, key in ipairs(order) do
        local g = groups[key]
        local label = folder .. (key ~= "" and ("/" .. key) or "")
        if #g.current > 1 then
            fail(label .. ": " .. #g.current .. " un-suffixed copies (" .. table.concat(g.current, ", ") .. ") — one current copy; rename the rest _old or delete them")
        end
        if #g.old > 2 then
            fail(label .. ": " .. #g.old .. " _old copies (" .. table.concat(g.old, ", ") .. ") — keep at most two")
        end
        if #g.current == 0 and #g.old > 0 then
            note(label .. ": only _old copies (" .. table.concat(g.old, ", ") .. ") — orphan; delete or restore a current copy")
        end
    end
end

local zips = P.listFiles(refs, "*.zip")
for _, z in ipairs(zips) do
    fail("zip archive present: " .. z:gsub("^" .. refs:gsub("%p", "%%%0") .. "\\", "") .. " — extract into a version folder and delete the zip")
end

if fails == 0 and notes == 0 then
    print("[references] OK — folder rule holds")
elseif fails == 0 then
    print("[references] OK with " .. notes .. " note(s)")
else
    print("[references] " .. fails .. " failure(s), " .. notes .. " note(s)")
end
os.exit((fails > 0 and not SOFT) and 1 or 0)
