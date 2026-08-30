-- Tier 1: the packaging invariant that every Ace mixin a module asks for is a
-- library the addon actually ships. AceAddon resolves mixins through LibStub and
-- errors when one is missing, taking the whole module down with it, so a request
-- for an unshipped library is a hard load failure -- but only on a machine where
-- no OTHER addon happened to register that library first. That masking is why
-- this needs a spec rather than a smoke: the failure is invisible in any
-- environment that has a second Ace addon installed, which is most of them.
--
-- The busted addon shim cannot catch this. installAddonShim defines NewModule as
-- function(_, name) and discards the mixin arguments entirely, so every spec in
-- this suite loads modules whose library requests are never resolved at all.
local lfs = require("lfs")

-- Library names the addon ships, taken from the loader manifest. Ace libraries
-- live in a directory named exactly like the mixin they register, so the
-- directory component IS the name a NewModule call would ask for.
local function shippedLibraries()
    local f = assert(io.open("Libs/Init.xml", "r"))
    local xml = f:read("*a")
    f:close()

    local shipped = {}
    for path in xml:gmatch('file%s*=%s*"([^"]+)"') do
        local dir = path:match("^([^/]+)/")
        if dir then shipped[dir] = true end
    end
    return shipped
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

-- Splits a call's argument text on top-level commas. Mixin arguments are always
-- plain string literals, so anything that is not one is a name expression
-- (config.moduleName and friends) and carries no library to check.
local function splitArgs(argText)
    local args, depth, current = {}, 0, ""
    for i = 1, #argText do
        local c = argText:sub(i, i)
        if c == "(" then depth = depth + 1 end
        if c == ")" then depth = depth - 1 end
        if c == "," and depth == 0 then
            args[#args + 1] = current
            current = ""
        else
            current = current .. c
        end
    end
    args[#args + 1] = current
    return args
end

-- Every (file, library) pair requested as a mixin. The first argument is the
-- addon or module NAME, never a library, so it is dropped.
local function requestedMixins()
    local requests = {}
    local roots = { "Core", "GUI", "Modules" }
    for _, root in ipairs(roots) do
        for _, path in ipairs(luaFilesUnder(root)) do
            local f = assert(io.open(path, "r"))
            local src = f:read("*a")
            f:close()
            for call, argText in src:gmatch(":(New%a+)%s*%(([^)]*)%)") do
                if call == "NewAddon" or call == "NewModule" then
                    local args = splitArgs(argText)
                    for i = 2, #args do
                        local lib = args[i]:match('^%s*"([^"]+)"%s*$')
                        if lib then
                            requests[#requests + 1] = { file = path, lib = lib }
                        end
                    end
                end
            end
        end
    end
    return requests
end

describe("library closure (every requested mixin is shipped)", function()
    local shipped = shippedLibraries()
    local requests = requestedMixins()

    it("finds the loader manifest and reads library names from it", function()
        assert.is_true(shipped["AceAddon-3.0"])
        assert.is_true(shipped["AceEvent-3.0"])
        assert.is_nil(shipped["AceConsole-3.0"])
    end)

    it("finds mixin requests to check", function()
        assert.is_true(#requests > 0)
    end)

    it("ships every library a NewAddon or NewModule call requests", function()
        local missing = {}
        for _, r in ipairs(requests) do
            if not shipped[r.lib] then
                missing[#missing + 1] = r.file .. " requests " .. r.lib
            end
        end
        assert.same({}, missing)
    end)
end)
