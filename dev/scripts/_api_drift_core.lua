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

return C
