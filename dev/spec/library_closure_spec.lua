-- Tier 1: the packaging invariant that every Ace mixin a module asks for is a
-- library the addon actually ships AND that the library is embed-capable.
-- AceAddon resolves mixins through LibStub and hard-errors when one is missing
-- or exposes no Embed, taking the whole module down with it -- but only on a
-- machine where no OTHER addon happened to register that library first. That
-- masking is why this needs a spec rather than a smoke: the failure is invisible
-- in any environment that has a second Ace addon installed, which is most.
--
-- The busted addon shim cannot catch this. installAddonShim defines NewModule as
-- function(_, name) and discards the mixin arguments entirely, so every spec in
-- this suite loads modules whose library requests are never resolved at all.
--
-- FAIL-CLOSED BY CONSTRUCTION. This does not parse Lua. It recognises ONE
-- declaration shape, the single shape all current declarations use, and reports
-- every other occurrence of NewAddon/NewModule as unreadable, which fails the
-- suite. A guard test that silently skips what it cannot read buys false
-- confidence, which is worse than no test -- so an unrecognised form must never
-- pass quietly. Widening the grammar is a deliberate edit with its own review;
-- an author who hits a false failure here extends CANONICAL below on purpose.
--
-- Scope: mixin arguments only. Direct LibStub lookups elsewhere are a related
-- failure class, but they mix required calls with deliberately optional ones,
-- so separating them needs a guard-aware parser and belongs in its own spec.
local lfs = require("lfs")

-- local NAME = expr:NewModule(<args>)  -- the whole grammar, anchored end to end
local CANONICAL = "^%s*local%s+[%w_]+%s*=%s*[%w_%.]+:(New%a+)%s*%((.*)%)%s*$"

-- A mixin argument is one double-quoted literal with no backslash in it. Escapes
-- are excluded rather than decoded: the scanner's idea of an escaped name and
-- Lua's would differ, and a name that only matches after decoding would resolve
-- here while failing in game. Library names never need an escape.
local LITERAL = '^%s*"([^"\\]*)"%s*$'

-- The first argument is the addon or module NAME, so it may also be a plain or
-- dotted name expression that this scanner does not need to resolve.
local NAME_EXPR = "^%s*[%w_][%w_%.]*%s*$"

-- A leading `--` does not make the line inert. `--[[ note ]] local M = ...` opens
-- and closes a comment before running the declaration, and inside an already-open
-- long comment the `--` of `--]] local M = ...` is content, so the `]]` closes the
-- block and the rest of the line runs. Either delimiter therefore disqualifies the
-- line from being skipped; it falls through to the grammar and is refused there.
local function isCommentLine(line)
    return line:match("^%s*%-%-") ~= nil
        and line:match("^%s*%-%-%[=*%[") == nil
        and line:match("%]=*%]") == nil
end

-- Mixins can also be requested away from a declaration: SetDefaultModuleLibraries
-- applies them to every later module, and the Embed entry points add them to an
-- existing object. Nothing here uses those, and a declaration site alone would
-- read as "no mixins" while resolving one, so any occurrence is refused.
local TRIGGERS = {
    "NewAddon", "NewModule",
    "SetDefaultModuleLibraries", "EmbedLibraries", "EmbedLibrary",
}

local function countTriggers(line)
    local n = 0
    for _, id in ipairs(TRIGGERS) do
        for _ in line:gmatch(id) do n = n + 1 end
    end
    return n
end

local function luaFilesUnder(dir, out)
    out = out or {}
    for entry in lfs.dir(dir) do
        if entry ~= "." and entry ~= ".." then
            local path = dir .. "/" .. entry
            local mode = lfs.attributes(path, "mode")
            if mode == "directory" then
                luaFilesUnder(path, out)
            elseif mode == "file" and path:match("%.lua$") then
                out[#out + 1] = path
            end
        end
    end
    return out
end

local function readLines(path)
    local lines = {}
    local f = assert(io.open(path, "r"), "cannot open " .. path)
    for line in f:lines() do lines[#lines + 1] = line end
    f:close()
    return lines
end

local function splitCommas(text)
    local parts, current = {}, ""
    for i = 1, #text do
        local c = text:sub(i, i)
        if c == "," then
            parts[#parts + 1] = current
            current = ""
        else
            current = current .. c
        end
    end
    parts[#parts + 1] = current
    return parts
end

-- Libraries the addon ships that AceAddon can actually embed. A directory in the
-- loader manifest is not enough: EmbedLibrary errors with "not Embed capable"
-- when the resolved library exposes no Embed, so a shipped library without one
-- kills the module exactly as a missing library does.
local function shippedEmbeddableLibraries()
    local f = assert(io.open("Libs/Init.xml", "r"))
    local xml = f:read("*a"):gsub("<!%-%-.-%-%->", "")
    f:close()

    local dirs = {}
    for path in xml:gmatch('file%s*=%s*"([^"]+)"') do
        local dir = path:match("^([^/]+)/")
        if dir then dirs[dir] = true end
    end

    local embeddable = {}
    for dir in pairs(dirs) do
        for _, path in ipairs(luaFilesUnder("Libs/" .. dir)) do
            for _, line in ipairs(readLines(path)) do
                -- Anchored to the line start so prose can never manufacture the
                -- capability: isCommentLine is deliberately conservative about
                -- what it calls a comment, and that judgement must not be what
                -- decides whether a vendored library is embeddable.
                if line:match("^%s*function%s+[%w_]+[:%.]Embed%s*%(")
                    or line:match("^%s*[%w_]+%.Embed%s*=%s*function") then
                    embeddable[dir] = true
                end
            end
        end
    end
    return embeddable, dirs
end

-- Every mixin argument of every declaration, plus every occurrence this scanner
-- refused to read. Whole-line comments are skipped; anything else containing the
-- identifiers must match CANONICAL exactly, once.
local function scanRequests()
    local requests, unreadable = {}, {}

    local function refuse(path, lineNo, why)
        unreadable[#unreadable + 1] = path .. ":" .. lineNo .. " " .. why
    end

    for _, root in ipairs({ "Core", "GUI", "Modules" }) do
        for _, path in ipairs(luaFilesUnder(root)) do
            for lineNo, line in ipairs(readLines(path)) do
                local occurrences = isCommentLine(line) and 0 or countTriggers(line)
                if occurrences > 0 then
                    local call, argText = line:match(CANONICAL)
                    if occurrences > 1 then
                        refuse(path, lineNo, "more than one declaration on the line")
                    elseif not call then
                        refuse(path, lineNo, "not a recognised declaration shape")
                    elseif call ~= "NewAddon" and call ~= "NewModule" then
                        refuse(path, lineNo, "unexpected constructor " .. call)
                    elseif argText:match("[%(%)]") then
                        refuse(path, lineNo, "arguments contain a nested call")
                    else
                        local args = splitCommas(argText)
                        if not (args[1]:match(LITERAL) or args[1]:match(NAME_EXPR)) then
                            refuse(path, lineNo, "first argument is neither a literal nor a name")
                        end
                        for i = 2, #args do
                            local lib = args[i]:match(LITERAL)
                            if lib then
                                requests[#requests + 1] = { file = path, lib = lib }
                            else
                                refuse(path, lineNo,
                                    "argument " .. i .. " is not a plain double-quoted literal")
                            end
                        end
                    end
                end
            end
        end
    end
    return requests, unreadable
end

describe("library closure (every requested mixin is shipped and embeddable)", function()
    local embeddable, manifestDirs = shippedEmbeddableLibraries()
    local requests, unreadable = scanRequests()

    it("reads library names out of the loader manifest", function()
        assert.is_true(manifestDirs["AceEvent-3.0"])
        assert.is_true(manifestDirs["LibStub"])
        assert.is_nil(manifestDirs["ThisLibraryIsNotShipped-1.0"])
    end)

    it("keeps only the manifest libraries AceAddon can embed", function()
        assert.is_true(embeddable["AceEvent-3.0"])
        assert.is_nil(embeddable["LibStub"])
    end)

    it("reads the known mixin request at the site this spec exists for", function()
        local found = false
        for _, r in ipairs(requests) do
            if r.file == "Modules/DamageMeter/Core.lua" and r.lib == "AceEvent-3.0" then
                found = true
            end
        end
        assert.is_true(found)
    end)

    it("reads a mixin request under every scanned root", function()
        local roots = {}
        for _, r in ipairs(requests) do
            roots[r.file:match("^([^/]+)/")] = true
        end
        assert.is_true(roots["Core"])
        assert.is_true(roots["Modules"])
    end)

    it("could read every declaration it found", function()
        assert.same({}, unreadable)
    end)

    it("ships an embeddable library for every requested mixin", function()
        local missing = {}
        for _, r in ipairs(requests) do
            if not embeddable[r.lib] then
                missing[#missing + 1] = r.file .. " requests " .. r.lib
            end
        end
        assert.same({}, missing)
    end)
end)
