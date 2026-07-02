-- _apidocs_parser.lua — shared Windows-hardened io + Blizzard API-docs
-- parsing for dev/scripts tools (drift check, api-drift watch).
-- Runs under Lua 5.1 and 5.4. Load via dofile from the resolved script dir.

local P = {}

-- ---- Windows-hardened file access -------------------------------------
-- io.open wrapper: the \\?\ extended-length prefix defeats the MAX_PATH
-- (260) limit, under which io.open fails SILENTLY (masked 30% of the
-- source scan in the prototype)
function P.openLong(path)
    if path:match("^%a:\\") then
        return io.open("\\\\?\\" .. path, "r")
    end
    return io.open(path, "r")
end

function P.readAll(path)
    local fh = P.openLong(path)
    if not fh then return nil end
    local src = fh:read("*a")
    fh:close()
    return src
end

-- recursive file listing via cmd.exe; returns absolute paths
function P.listFiles(dir, pat)
    local out = {}
    local p = io.popen('dir /b /s "' .. dir .. '\\' .. pat .. '" 2>nul')
    if p then
        for line in p:lines() do out[#out + 1] = line end
        p:close()
    end
    return out
end

function P.listDirs(dir)
    local out = {}
    local p = io.popen('dir /b /ad "' .. dir .. '" 2>nul')
    if p then
        for line in p:lines() do out[#out + 1] = line end
        p:close()
    end
    return out
end

function P.count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- Lua 5.1/5.4 compat: sandboxed chunk loader. 5.2+ load() takes the env
-- as its 4th argument; 5.1 needs loadstring + setfenv instead.
function P.loadSandboxed(src, name, env)
    if setfenv then
        local chunk, err = loadstring(src, name)
        if chunk then setfenv(chunk, env) end
        return chunk, err
    end
    return load(src, name, "t", env)
end

-- resolve repo root from a script's arg[0] (was inline in the drift check)
function P.resolveRepoRoot(arg0)
    local function getCwd()
        local p = io.popen("cd")
        local d = p and p:read("*l")
        if p then p:close() end
        return d
    end
    local scriptPath = (arg0 or ""):gsub("/", "\\")
    local prefix = scriptPath:match("^(.-)dev\\scripts\\[^\\]+$")
    local root
    if not prefix or prefix == "" or prefix == ".\\" then
        root = getCwd()
    elseif prefix:match("^%a:\\") or prefix:match("^\\\\") then
        root = (prefix:gsub("\\+$", ""))
    else
        root = getCwd() .. "\\" .. (prefix:gsub("\\+$", ""))
    end
    assert(root and #root > 0, "could not resolve repo root from arg[0]")
    return root
end

-- PURE docs collector: sources = { {name=..., src=...}, ... }.
-- Same permissive sandbox as before (stub with arithmetic metamethods).
function P.collectDocTablesFromSources(sources)
    local collected, errors = {}, {}
    -- permissive sandbox: any unknown global resolves to a stub that can be
    -- indexed/called; APIDocumentation:AddDocumentationTable collects the
    -- tables. The stub needs arithmetic metamethods because 3 constants files
    -- compute values from other constants (e.g. PetConstants MAX_STABLE_SLOTS + 1).
    local stub
    stub = setmetatable({}, {
        __index = function() return stub end,
        __call = function() return stub end,
        __add = function() return 0 end, __sub = function() return 0 end,
        __mul = function() return 0 end, __div = function() return 0 end,
        __unm = function() return 0 end, __concat = function() return "" end,
    })
    local docsEnv = setmetatable({
        APIDocumentation = {
            AddDocumentationTable = function(_, tbl) collected[#collected + 1] = tbl end,
        },
    }, { __index = function() return stub end })

    for _, s in ipairs(sources) do
        local chunk, err = P.loadSandboxed(s.src, "@" .. s.name, docsEnv)
        if not chunk then
            errors[#errors + 1] = s.name .. ": " .. tostring(err)
        else
            local ok, runErr = pcall(chunk)
            if not ok then errors[#errors + 1] = s.name .. ": " .. tostring(runErr) end
        end
    end
    return { tables = collected, errors = errors }
end

-- io wrapper: read every *.lua in docsDir, delegate to the pure collector
function P.collectDocTables(docsDir)
    local sources, filesRead = {}, 0
    for _, path in ipairs(P.listFiles(docsDir, "*.lua")) do
        local src = P.readAll(path)
        if src then
            filesRead = filesRead + 1
            sources[#sources + 1] = { name = path, src = src }
        end
    end
    local res = P.collectDocTablesFromSources(sources)
    res.filesRead = filesRead
    return res
end

-- ---- shared identifier harvest --------------------------------------------
-- bare identifiers: not preceded by '.' or ':' (field/method accesses don't
-- count). Comments and strings DO count — known over-approximation.
function P.harvestLua(src, set)
    for pos, id in src:gmatch("()([A-Za-z_][A-Za-z0-9_]*)") do
        local prev = pos > 1 and src:sub(pos - 1, pos - 1) or ""
        if prev ~= "." and prev ~= ":" then set[id] = true end
    end
end

return P
