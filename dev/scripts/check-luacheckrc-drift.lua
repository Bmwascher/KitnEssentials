-- check-luacheckrc-drift.lua — verify .luacheckrc globals against the
-- .wow-api-reference Blizzard UI reference (API docs + full UI source).
--
-- Run from the repo root with the local Lua interpreter (5.1 or 5.4):
--   lua dev/scripts/check-luacheckrc-drift.lua [--soft]
--
-- Two-tier verification:
--   tier 1: parse Blizzard_APIDocumentationGenerated via sandboxed load()
--           — C_* namespaces, non-namespaced Function names (globals),
--           event LiteralNames
--   tier 2: scan Interface/AddOns/**/*.lua|*.xml (EXCLUDING the
--           Blizzard_APIDocumentation* addons) for definition-grade hits
--           (XML name="X", line-start `X =`, `_G.X =`, `function X(`)
--           and loose identifier mentions — verifies frame globals and
--           FrameXML symbols the docs never cover
-- Usage axis: bare identifiers + _G.X forms across Core/ Modules/ GUI/.
--
-- Report groups (allowlist: dev/scripts/luacheckrc-drift-allow.lua):
--   [A] rc entries not in the reference   — non-allowlisted = failure
--   [B] rc entries unused in KE code      — ALWAYS advisory, never gates
--   [C] duplicate rc entries              — failure
--   [D] Register*Event literals not in documented events — failure
-- Exit 1 only on non-allowlisted [A] / [C] / [D]; --soft forces exit 0.
--
-- Degradation: docs dir missing (CI, broken symlink) — notice + exit 0.
-- Source tree not materialized (sparse checkout, < 50 addon dirs) —
-- tier-1-only mode with an "unverified" class + one-time fix hint.

local SOFT = false
for i = 1, #arg do
    if arg[i] == "--soft" then SOFT = true end
end

-- bootstrap: locate the lib next to this script, before root resolution
local _script = (arg[0] or ""):gsub("/", "\\")
local _dir = _script:match("^(.*\\)[^\\]+$") or ".\\dev\\scripts\\"
local P = dofile(_dir .. "_apidocs_parser.lua")

local openLong, readAll = P.openLong, P.readAll        -- luacheck: ignore 211
local listFiles, listDirs, count = P.listFiles, P.listDirs, P.count
local loadSandboxed, harvestLua = P.loadSandboxed, P.harvestLua
local ROOT = P.resolveRepoRoot(arg[0])

local REF = ROOT .. "\\.wow-api-reference"
local ADDONS = REF .. "\\Interface\\AddOns"
local DOCS = ADDONS .. "\\Blizzard_APIDocumentationGenerated"

-- ---- load .luacheckrc (sandboxed) --------------------------------------
local rcSrc = readAll(ROOT .. "\\.luacheckrc")
assert(rcSrc, "cannot read " .. ROOT .. "\\.luacheckrc — repo root resolution failed?")
local rcEnv = { files = {} }
assert(loadSandboxed(rcSrc, "@.luacheckrc", rcEnv))()
local rcGlobals = rcEnv.globals or {}
local rcRead = rcEnv.read_globals or {}

-- internal + cross-list duplicates
local seenWhere, dupes = {}, {}
local function noteDupes(list, kind)
    for _, sym in ipairs(list) do
        if seenWhere[sym] then
            dupes[#dupes + 1] = sym .. " (" .. seenWhere[sym] .. " + " .. kind .. ")"
        else
            seenWhere[sym] = kind
        end
    end
end
noteDupes(rcGlobals, "globals")
noteDupes(rcRead, "read_globals")

-- ---- load the allowlist -------------------------------------------------
local missingOk, unusedOk = {}, {}
local allowSrc = readAll(ROOT .. "\\dev\\scripts\\luacheckrc-drift-allow.lua")
if allowSrc then
    local allow = assert(loadSandboxed(allowSrc, "@luacheckrc-drift-allow.lua", {}))()
    if type(allow) == "table" then
        missingOk = allow.missing_ok or {}
        unusedOk = allow.unused_ok or {}
    end
end

-- ---- reference version + docs presence ----------------------------------
local version = (readAll(REF .. "\\version.txt") or "unknown"):match("[^\r\n]+") or "unknown"

local docFiles = listFiles(DOCS, "*.lua")
if #docFiles == 0 then
    print("luacheckrc drift check -- reference docs not found at")
    print("  " .. DOCS)
    print("(.wow-api-reference absent or broken symlink -- skipping, exit 0)")
    os.exit(0)
end

-- ---- tier 1: parse the API docs ------------------------------------------
local docRes = P.collectDocTables(DOCS)
local parseErrors, nDocsRead = docRes.errors, docRes.filesRead
local collected = docRes.tables
assert(nDocsRead >= 500, ("only %d API-docs files read (expected >= 500) -- docs checkout is damaged"):format(nDocsRead))

local namespaces, globalFns, docEvents = {}, {}, {}
for _, tbl in ipairs(collected) do
    local ns = rawget(tbl, "Namespace")
    if ns then namespaces[ns] = true end
    local fns = rawget(tbl, "Functions")
    if type(fns) == "table" then
        for _, fn in ipairs(fns) do
            local name = rawget(fn, "Name")
            -- systems WITHOUT a Namespace export their Functions as globals
            if name and not ns then globalFns[name] = true end
        end
    end
    local evs = rawget(tbl, "Events")
    if type(evs) == "table" then
        for _, ev in ipairs(evs) do
            local lit = rawget(ev, "LiteralName")
            if lit then docEvents[lit] = true end
        end
    end
end

-- ---- tier 2: scan the full Blizzard UI source ------------------------------
local addonDirs = listDirs(ADDONS)
local tier2 = #addonDirs >= 50

local blizzIds, blizzDefs = {}, {}
local nLua, nXml = 0, 0
if tier2 then
    for _, ext in ipairs({ "*.lua", "*.xml" }) do
        for _, f in ipairs(listFiles(ADDONS, ext)) do
            -- the API docs addons are tier 1 — do NOT let their Name="..."
            -- strings count as source mentions (would mask real removals)
            if not f:find("Blizzard_APIDocumentation", 1, true) then
                local src = readAll(f)
                if src then
                    if ext == "*.lua" then
                        nLua = nLua + 1
                        harvestLua(src, blizzIds)
                        -- definition-grade: line-start global assignment,
                        -- _G.X / _G["X"] assignment, global function decl
                        for id in src:gmatch("\n([A-Za-z_][A-Za-z0-9_]*)%s*=") do blizzDefs[id] = true end
                        for id in src:gmatch("^([A-Za-z_][A-Za-z0-9_]*)%s*=") do blizzDefs[id] = true end
                        for id in src:gmatch("_G%.([A-Za-z_][A-Za-z0-9_]*)%s*=") do blizzDefs[id] = true end
                        for id in src:gmatch("_G%[\"([A-Za-z_][A-Za-z0-9_]*)\"%]%s*=") do blizzDefs[id] = true end
                        for id in src:gmatch("function%s+([A-Za-z_][A-Za-z0-9_]*)%s*%(") do blizzDefs[id] = true end
                    else
                        nXml = nXml + 1
                        for id in src:gmatch("[A-Za-z_][A-Za-z0-9_]*") do blizzIds[id] = true end
                        -- definition-grade: exported XML names
                        for id in src:gmatch("name=\"([A-Za-z_][A-Za-z0-9_]*)\"") do blizzDefs[id] = true end
                    end
                end
            end
        end
    end
    assert(nLua + nXml >= 1000, ("only %d source files read (expected >= 1000) -- source checkout is damaged"):format(nLua + nXml))
end

-- ---- usage axis: KE code + event literals -----------------------------------
local usedIds, keEvents = {}, {}
local nKeFiles = 0
for _, sub in ipairs({ "Core", "Modules", "GUI" }) do
    for _, f in ipairs(listFiles(ROOT .. "\\" .. sub, "*.lua")) do
        local src = readAll(f)
        if src then
            nKeFiles = nKeFiles + 1
            harvestLua(src, usedIds)
            -- _G.X = / _G["X"] access also counts as usage of global X
            for id in src:gmatch("_G%.([A-Za-z_][A-Za-z0-9_]*)") do usedIds[id] = true end
            for id in src:gmatch("_G%[\"([A-Za-z_][A-Za-z0-9_]*)\"%]") do usedIds[id] = true end
            -- event literals passed to RegisterEvent-style calls
            for ev in src:gmatch("Register[%w]*Event%(%s*\"([A-Z][A-Z0-9_]+)\"") do keEvents[ev] = true end
        end
    end
end

-- ---- classification -----------------------------------------------------------
local thirdParty = {
    LibStub = true, ElvUI = true, ElvUI_SpellBookTooltip = true,
    BigWigs = true, BigWigsLoader = true, WeakAuras = true,
    Ayije_CastBar = true, BCDM_CastBar = true, UUF_Player_CastBar = true,
}
local function isKEOwn(sym)
    return sym:match("^Kitn") or sym:match("^KITN") or sym:match("^KE_")
        or sym:match("^SLASH_KITNESSENTIALS") or sym:match("^SLASH_KE_")
end

local CLS_UNVERIFIED = "unverified (source not materialized)"
local function classify(sym)
    if namespaces[sym] or globalFns[sym] then return "in API docs" end
    if isKEOwn(sym) then return "KE-own" end
    if thirdParty[sym] then return "third-party" end
    if not tier2 then return CLS_UNVERIFIED end
    if blizzDefs[sym] then return "source definition" end
    if blizzIds[sym] then return "source mention" end
    return "MISSING"
end

local rows, order = {}, {}
local function addRow(sym, kind)
    if rows[sym] then return end
    rows[sym] = { kind = kind, cls = classify(sym), used = usedIds[sym] and true or false }
    order[#order + 1] = sym
end
for _, sym in ipairs(rcGlobals) do addRow(sym, "globals") end
for _, sym in ipairs(rcRead) do addRow(sym, "read_globals") end
table.sort(order)

-- ---- report -----------------------------------------------------------------
print(("luacheckrc drift check -- reference %s"):format(version))
print(("  .luacheckrc: %d unique entries (%d raw, %d duplicate)"):format(
    #order, #rcGlobals + #rcRead, #dupes))
print(("  API docs: %d files parsed (%d namespaces, %d global functions, %d events)"):format(
    nDocsRead, count(namespaces), count(globalFns), count(docEvents)))
if tier2 then
    print(("  Blizzard source: %d addon dirs, %d lua + %d xml files scanned"):format(
        #addonDirs, nLua, nXml))
else
    print(("  Blizzard source: NOT materialized (%d addon dirs -- sparse checkout); tier-1-only mode"):format(#addonDirs))
    print('  fix once: git -C "' .. REF .. '" sparse-checkout set Interface/AddOns   (~26 MB)')
end
print(("  KE code: %d lua files (Core/ Modules/ GUI/)"):format(nKeFiles))
for _, e in ipairs(parseErrors) do
    print("  NOTE docs parse error: " .. e)
end

print("")
print("classification:")
local clsCounts = {}
for _, sym in ipairs(order) do
    clsCounts[rows[sym].cls] = (clsCounts[rows[sym].cls] or 0) + 1
end
for _, c in ipairs({ "in API docs", "source definition", "source mention",
                     "KE-own", "third-party", CLS_UNVERIFIED, "MISSING" }) do
    if clsCounts[c] then print(("  %-38s %d"):format(c, clsCounts[c])) end
end

-- [A] not in the reference
local missing, missingAllowed = {}, {}
for _, sym in ipairs(order) do
    if rows[sym].cls == "MISSING" then
        if missingOk[sym] then
            missingAllowed[#missingAllowed + 1] = sym
        else
            missing[#missing + 1] = sym
        end
    end
end
print("")
print(("[A] not in %s reference (%d: %d failing, %d allowlisted)"):format(
    version, #missing + #missingAllowed, #missing, #missingAllowed))
for _, sym in ipairs(missing) do
    print(("  FAIL %-32s (%s)%s"):format(sym, rows[sym].kind,
        rows[sym].used and "" or "  [also unused -- delete candidate]"))
end
for _, sym in ipairs(missingAllowed) do
    print(("  ok   %-32s allowlisted: %s"):format(sym, missingOk[sym]))
end

-- [B] unused in KE code (always advisory)
local unused, unusedAllowed = {}, {}
for _, sym in ipairs(order) do
    if not rows[sym].used then
        if unusedOk[sym] then
            unusedAllowed[#unusedAllowed + 1] = sym
        else
            unused[#unused + 1] = sym
        end
    end
end
print("")
print(("[B] unused in KE code (%d + %d allowlisted; advisory, never gates)"):format(
    #unused, #unusedAllowed))
for _, sym in ipairs(unused) do
    print(("  note %-32s (%s, %s)"):format(sym, rows[sym].kind, rows[sym].cls))
end
for _, sym in ipairs(unusedAllowed) do
    print(("  ok   %-32s allowlisted: %s"):format(sym, unusedOk[sym]))
end

-- [C] duplicate rc entries
print("")
print(("[C] duplicate .luacheckrc entries (%d)"):format(#dupes))
for _, d in ipairs(dupes) do
    print("  FAIL " .. d)
end

-- [D] event literals not in the documented events
local badEvents, nEvents = {}, 0
for ev in pairs(keEvents) do
    nEvents = nEvents + 1
    if not docEvents[ev] then badEvents[#badEvents + 1] = ev end
end
table.sort(badEvents)
print("")
print(("[D] Register*Event literals not in documented events (%d of %d distinct)"):format(
    #badEvents, nEvents))
for _, ev in ipairs(badEvents) do
    print("  FAIL " .. ev)
end

-- ---- exit policy --------------------------------------------------------------
local failures = #missing + #dupes + #badEvents
print("")
if failures == 0 then
    print("RESULT: clean -- exit 0")
    os.exit(0)
elseif SOFT then
    print(("RESULT: %d failure(s) -- --soft, exit 0"):format(failures))
    os.exit(0)
else
    print(("RESULT: %d failure(s) -- exit 1"):format(failures))
    os.exit(1)
end
