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
-- The scanner below fails LOUD on any call shape it cannot read with certainty.
-- A guard test that silently skips what it does not understand buys false
-- confidence, which is worse than no test: every unreadable form is reported as
-- a failure asking for the scanner to be extended, never quietly dropped.
--
-- Scope: mixin arguments only. Direct LibStub lookups elsewhere are a related
-- failure class, but they mix required calls with deliberately optional ones,
-- so separating them needs a guard-aware parser and belongs in its own spec.
local lfs = require("lfs")

-- Marks every byte as code or not, so a call site inside a comment or a string
-- is never mistaken for a real declaration, and records the span and value of
-- each quoted string so arguments can be read back.
local function lexLua(src)
    local isCode, strings = {}, {}
    local i, n = 1, #src
    while i <= n do
        local c = src:sub(i, i)
        local commentLevel = src:match("^%-%-%[(=*)%[", i)
        local longLevel = src:match("^%[(=*)%[", i)
        if commentLevel then
            local close = src:find("]" .. commentLevel .. "]", i, true)
            local finish = close and (close + #commentLevel + 1) or n
            for j = i, finish do isCode[j] = false end
            i = finish + 1
        elseif c == "-" and src:sub(i + 1, i + 1) == "-" then
            local finish = src:find("\n", i, true) or (n + 1)
            for j = i, finish - 1 do isCode[j] = false end
            i = finish
        elseif c == '"' or c == "'" then
            local j, value = i + 1, {}
            while j <= n do
                local d = src:sub(j, j)
                if d == "\\" then
                    value[#value + 1] = src:sub(j + 1, j + 1)
                    j = j + 2
                elseif d == c or d == "\n" then
                    break
                else
                    value[#value + 1] = d
                    j = j + 1
                end
            end
            strings[i] = { finish = j, value = table.concat(value), quote = c }
            for k = i, j do isCode[k] = false end
            i = j + 1
        elseif longLevel then
            local close = src:find("]" .. longLevel .. "]", i, true)
            local finish = close and (close + #longLevel + 1) or n
            for j = i, finish do isCode[j] = false end
            i = finish + 1
        else
            isCode[i] = true
            i = i + 1
        end
    end
    return isCode, strings
end

-- Splits one call's arguments at top-level commas, stepping over nested calls
-- and over strings. Returns nil when the closing parenthesis is absent.
local function splitArgs(src, openPos, isCode, strings)
    local args, current, depth = {}, {}, 0
    local i, n = openPos + 1, #src
    while i <= n do
        local str = strings[i]
        if str then
            current[#current + 1] = { kind = "string", value = str.value, quote = str.quote }
            i = str.finish + 1
        elseif not isCode[i] then
            i = i + 1
        else
            local c = src:sub(i, i)
            if c == "(" then
                depth = depth + 1
                current[#current + 1] = { kind = "other" }
            elseif c == ")" then
                if depth == 0 then
                    args[#args + 1] = current
                    return args
                end
                depth = depth - 1
            elseif c == "," and depth == 0 then
                args[#args + 1] = current
                current = {}
            elseif c:match("[%w_%.:%[%]{}]") then
                current[#current + 1] = { kind = "other" }
            end
            i = i + 1
        end
    end
    return nil
end

-- An argument yields a library name only when it is one lone double-quoted
-- literal. Anything else in a mixin position is unreadable and must fail loud.
local function classify(tokens)
    if #tokens == 0 then return "empty" end
    if #tokens == 1 and tokens[1].kind == "string" and tokens[1].quote == '"' then
        return "literal", tokens[1].value
    end
    return "unreadable"
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

local function readFile(path)
    local f = assert(io.open(path, "r"), "cannot open " .. path)
    local src = f:read("*a")
    f:close()
    return src
end

-- Libraries the addon ships that AceAddon can actually embed. A directory in the
-- loader manifest is not enough: EmbedLibrary errors with "not Embed capable"
-- when the resolved library exposes no Embed, so a shipped library without one
-- kills the module exactly as a missing library does.
local function shippedEmbeddableLibraries()
    local xml = readFile("Libs/Init.xml"):gsub("<!%-%-.-%-%->", "")

    local dirs = {}
    for path in xml:gmatch('file%s*=%s*"([^"]+)"') do
        local dir = path:match("^([^/]+)/")
        if dir then dirs[dir] = true end
    end

    local embeddable = {}
    for dir in pairs(dirs) do
        for _, path in ipairs(luaFilesUnder("Libs/" .. dir)) do
            if readFile(path):match("function%s+[%w_]+:Embed%s*%(") then
                embeddable[dir] = true
            end
        end
    end
    return embeddable, dirs
end

-- Every mixin argument of every NewAddon/NewModule call, plus every call this
-- scanner could not read. The first argument is the addon or module NAME.
local function scanRequests()
    local requests, unreadable = {}, {}
    for _, root in ipairs({ "Core", "GUI", "Modules" }) do
        for _, path in ipairs(luaFilesUnder(root)) do
            local src = readFile(path)
            local isCode, strings = lexLua(src)
            local pos = 1
            while true do
                local s, e, call = src:find(":(New%a+)%s*%(", pos)
                if not s then break end
                pos = e + 1
                if isCode[s] and (call == "NewAddon" or call == "NewModule") then
                    local args = splitArgs(src, e, isCode, strings)
                    if not args then
                        unreadable[#unreadable + 1] = path .. ": unterminated " .. call .. " call"
                    else
                        for i = 2, #args do
                            local kind, value = classify(args[i])
                            if kind == "literal" then
                                requests[#requests + 1] = { file = path, lib = value }
                            elseif kind ~= "empty" then
                                unreadable[#unreadable + 1] =
                                    path .. ": " .. call .. " argument " .. i .. " is not a plain string literal"
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

    it("can read every NewAddon and NewModule call it found", function()
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
