-- _db2_csv.lua: read a wago.tools DB2 CSV export into rows keyed by column
-- name. Loaded by dofile from the derive scripts beside it:
--
--   local CSV = dofile(_dir .. "_db2_csv.lua")
--   local rows = CSV.read(dir .. "/SpellName.csv", { "ID", "Name_lang" })
--
-- Fields may be quoted ("a, b", with "" for a quote mark); a record never
-- spans lines. Every name in `need` must be a header column, so a renamed
-- column fails loudly instead of reading as empty. Values stay strings;
-- CSV.num turns one into a number, 0 when it is empty.

local M = {}

local function splitLine(line)
    local fields, i, n = {}, 1, #line
    while i <= n + 1 do
        if line:sub(i, i) == '"' then
            local buf, j = {}, i + 1
            while true do
                local c = line:sub(j, j)
                if c == "" then error("unterminated quoted field", 0) end
                if c == '"' then
                    if line:sub(j + 1, j + 1) == '"' then
                        buf[#buf + 1] = '"'
                        j = j + 2
                    else
                        j = j + 1
                        break
                    end
                else
                    buf[#buf + 1] = c
                    j = j + 1
                end
            end
            fields[#fields + 1] = table.concat(buf)
            i = j + 1
        else
            local comma = line:find(",", i, true)
            if comma then
                fields[#fields + 1] = line:sub(i, comma - 1)
                i = comma + 1
            else
                fields[#fields + 1] = line:sub(i)
                i = n + 2
            end
        end
    end
    return fields
end

function M.read(path, need)
    local f, err = io.open(path, "rb")
    if not f then error(path .. ": " .. tostring(err), 0) end
    local text = f:read("*a")
    f:close()
    text = text:gsub("^\239\187\191", "")
    local rows, index, lineNo = {}, nil, 0
    for line in text:gmatch("[^\r\n]+") do
        lineNo = lineNo + 1
        local ok, fields = pcall(splitLine, line)
        if not ok then error(("%s line %d: %s"):format(path, lineNo, fields), 0) end
        if not index then
            index = {}
            for i, name in ipairs(fields) do index[name] = i end
            for _, name in ipairs(need) do
                if not index[name] then error(("%s: no column %s"):format(path, name), 0) end
            end
        else
            local row = {}
            for _, name in ipairs(need) do row[name] = fields[index[name]] or "" end
            rows[#rows + 1] = row
        end
    end
    if not index then error(path .. ": empty file", 0) end
    return rows
end

function M.num(value)
    return tonumber(value) or 0
end

return M
