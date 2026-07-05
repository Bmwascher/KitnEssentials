-- _api_drift_core.lua — PURE functions for the api-drift watch. No io, no
-- git, no os.* except os.date in callers — this file must stay testable on
-- Linux CI. Consumed by update-api-reference.lua and api_drift_spec.lua.
local C = {}

-- Stable serialization: sorted keys, scalars as k=v, nested tables
-- recursed with a path prefix. Any doc-table shape change (including
-- unknown future secret-flag fields) therefore changes the string.
function C.serializeRecord(tbl)
    local parts = {}
    local function walk(t, prefix)
        local keys = {}
        for k in pairs(t) do keys[#keys + 1] = k end
        -- sort by tostring so numeric (array) and string keys coexist stably;
        -- keys keep their original type so the lookup below actually hits
        table.sort(keys, function(x, y) return tostring(x) < tostring(y) end)
        for _, k in ipairs(keys) do
            local v = t[k]
            local p = prefix == "" and tostring(k) or (prefix .. "." .. tostring(k))
            if type(v) == "table" then
                walk(v, p)
            else
                parts[#parts + 1] = p .. "=" .. tostring(v)
            end
        end
    end
    walk(tbl, "")
    return table.concat(parts, ";")
end

function C.flattenDocs(tables)
    local flat = { functions = {}, events = {}, enums = {} }
    for _, tbl in ipairs(tables) do
        local ns = rawget(tbl, "Namespace")
        local fns = rawget(tbl, "Functions")
        if type(fns) == "table" then
            for _, fn in ipairs(fns) do
                local name = rawget(fn, "Name")
                if name then
                    local key = ns and (ns .. "." .. name) or name
                    flat.functions[key] = C.serializeRecord(fn)
                end
            end
        end
        local evs = rawget(tbl, "Events")
        if type(evs) == "table" then
            for _, ev in ipairs(evs) do
                local lit = rawget(ev, "LiteralName")
                if lit then flat.events[lit] = C.serializeRecord(ev) end
            end
        end
        -- enums nest under Tables in the real doc files
        -- (e.g. AddOnProfilerConstantsDocumentation.lua)
        local subTables = rawget(tbl, "Tables")
        if type(subTables) == "table" then
            for _, sub in ipairs(subTables) do
                if rawget(sub, "Type") == "Enumeration" and rawget(sub, "Name") then
                    local fields = rawget(sub, "Fields")
                    if type(fields) == "table" then
                        for _, f in ipairs(fields) do
                            local fname = rawget(f, "Name")
                            local val = rawget(f, "EnumValue")
                            if fname and val ~= nil then
                                flat.enums["Enum." .. rawget(sub, "Name") .. "." .. fname] = val
                            end
                        end
                    end
                end
            end
        end
    end
    return flat
end

function C.diffMaps(old, new)
    local added, removed, changed = {}, {}, {}
    for k, v in pairs(new) do
        if old[k] == nil then added[#added + 1] = k
        elseif old[k] ~= v then changed[#changed + 1] = k end
    end
    for k in pairs(old) do
        if new[k] == nil then removed[#removed + 1] = k end
    end
    table.sort(added); table.sort(removed); table.sort(changed)
    return { added = added, removed = removed, changed = changed }
end

function C.usedPredicates(used)
    local p = {}
    function p.fn(key)
        if used.nsCalls[key] then return true end
        if not key:find(".", 1, true) and used.names[key] then return true end
        return false
    end
    function p.fnNsAddition(key)
        local ns = key:match("^(C_[%w_]+)%.")
        return (ns and used.nsAll[ns]) and true or false
    end
    function p.event(key) return used.events[key] == true end
    function p.enum(key) return used.enums[key] == true end
    function p.name(key) return used.names[key] == true end
    function p.cvar(key) return used.cvars[key] == true end
    return p
end

function C.filterUsed(keys, pred)
    local hit, miss = {}, 0
    for _, k in ipairs(keys) do
        if pred(k) then hit[#hit + 1] = k else miss = miss + 1 end
    end
    return { hit = hit, miss = miss }
end

function C.newUsedSurface()
    return { names = {}, nsCalls = {}, nsAll = {}, events = {}, enums = {}, cvars = {} }
end

function C.harvestUsedFromSource(src, used)
    -- bare identifiers (not preceded by . or :) — same rule as the drift check
    for pos, id in src:gmatch("()([A-Za-z_][A-Za-z0-9_]*)") do
        local prev = pos > 1 and src:sub(pos - 1, pos - 1) or ""
        if prev ~= "." and prev ~= ":" then used.names[id] = true end
    end
    for id in src:gmatch("_G%.([A-Za-z_][A-Za-z0-9_]*)") do used.names[id] = true end
    for id in src:gmatch("_G%[\"([A-Za-z_][A-Za-z0-9_]*)\"%]") do used.names[id] = true end
    for ns, member in src:gmatch("(C_[%w_]+)[%.:]([A-Za-z_][A-Za-z0-9_]*)") do
        used.nsCalls[ns .. "." .. member] = true
        used.nsAll[ns] = true
    end
    for name, member in src:gmatch("Enum%.([%w_]+)%.([%w_]+)") do
        used.enums["Enum." .. name .. "." .. member] = true
    end
    for ev in src:gmatch("Register[%w]*Event%(%s*[\"']([A-Z][A-Z0-9_]+)[\"']") do
        used.events[ev] = true
    end
    for cv in src:gmatch("[GS]etCVar%(%s*[\"']([%w_%.]+)[\"']") do used.cvars[cv] = true end
    for cv in src:gmatch("C_CVar%.[%w_]+%(%s*[\"']([%w_%.]+)[\"']") do used.cvars[cv] = true end
end

function C.addLuacheckrcNames(rcGlobals, rcRead, used)
    for _, sym in ipairs(rcGlobals or {}) do used.names[sym] = true end
    for _, sym in ipairs(rcRead or {}) do used.names[sym] = true end
end

function C.parseBIRSource(src, loadSandboxed)
    local set = {}
    local function walk(t, seen)
        if seen[t] then return end
        seen[t] = true
        for k, v in pairs(t) do
            if type(v) == "string" then set[v] = true
            elseif type(v) == "table" then walk(v, seen) end
            if type(k) == "string" and type(v) ~= "table" then set[k] = true end
        end
    end
    local env = {}
    local chunk = loadSandboxed(src, "@bir", env)
    local ok, ret
    if chunk then ok, ret = pcall(chunk) end
    if ok then
        if type(ret) == "table" then walk(ret, {}) end
        walk(env, {})
    else
        for name in src:gmatch("[\"']([A-Za-z_][A-Za-z0-9_%.]*)[\"']") do set[name] = true end
    end
    return set
end

local function quoteKey(k)
    if type(k) == "string" and k:match("^[A-Za-z_][A-Za-z0-9_]*$") then return k end
    return "[" .. string.format("%q", k) .. "]"
end

local function serializeValue(v, indent)
    if type(v) ~= "table" then
        if type(v) == "string" then return string.format("%q", v) end
        return tostring(v)
    end
    local pad = string.rep("    ", indent)
    local parts = { "{" }
    local isArray = #v > 0
    if isArray then
        for _, item in ipairs(v) do
            parts[#parts + 1] = pad .. "    " .. serializeValue(item, indent + 1) .. ","
        end
    else
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            parts[#parts + 1] = pad .. "    " .. quoteKey(k) .. " = "
                .. serializeValue(v[k], indent + 1) .. ","
        end
    end
    parts[#parts + 1] = pad .. "}"
    return table.concat(parts, "\n")
end

function C.serializeSnapshot(snap)
    return "-- api-drift snapshot (generated; do not edit)\nreturn "
        .. serializeValue(snap, 0) .. "\n"
end

function C.loadSnapshotFromString(src, loadSandboxed)
    local chunk = loadSandboxed(src, "@snapshot", {})
    if not chunk then return nil end
    local ok, snap = pcall(chunk)
    if not ok or type(snap) ~= "table" then return nil end
    return snap
end

function C.renderReport(ctx)
    local L = {}
    local function add(s) L[#L + 1] = s end
    add(("api-drift: %s -> %s   [snapshot %s -> %s]")
        :format(ctx.oldBuild, ctx.newBuild, ctx.oldDate, ctx.date))
    add("")
    add(("[BREAKING-USED] (%d)"):format(#ctx.sections.breaking))
    for _, s in ipairs(ctx.sections.breaking) do add("  " .. s) end
    add("")
    add(("[C-SIDE] (%d)"):format(#ctx.sections.cside))
    for _, s in ipairs(ctx.sections.cside) do add("  " .. s) end
    add("")
    add(("[ADDITIONS] (%d)"):format(#ctx.sections.additions))
    for _, s in ipairs(ctx.sections.additions) do add("  " .. s) end
    add("")
    add(("[FYI] %d total doc changes this update; %d intersect the used surface.")
        :format(ctx.fyiTotal, ctx.fyiUsed))
    for _, s in ipairs(ctx.links) do add("links: " .. s) end
    return L, ((#ctx.sections.breaking > 0 or (ctx.csideGating or 0) > 0) and 1) or 0
end

return C
