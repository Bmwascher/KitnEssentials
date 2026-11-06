-- _lua_text.lua: read a Lua table literal out of a file's text, running nothing.
--
--   local data = Text.ReadTable(fileText, "some.marker")
--
-- Finds the first occurrence of the marker, then reads the table constructor
-- that follows it into a plain table. Numbers, strings, true, false, nil and
-- nested tables read as themselves, and a bare name reads as a string. A
-- function body or a call in a value raises error(msg, 0), as does anything
-- else the constructor cannot hold.

local M = {}

local ESCAPES = { n = "\n", t = "\t", r = "\r" }

local function SkipSpace(text, pos)
    while true do
        pos = text:find("%S", pos) or #text + 1
        if text:sub(pos, pos + 3) == "--[[" then
            local close = text:find("]]", pos + 4, true)
            if not close then error("unterminated comment", 0) end
            pos = close + 2
        elseif text:sub(pos, pos + 1) == "--" then
            pos = text:find("\n", pos, true) or #text + 1
        else
            return pos
        end
    end
end

local function ReadString(text, pos)
    local quote = text:sub(pos, pos)
    local parts, i = {}, pos + 1
    while true do
        local c = text:sub(i, i)
        if c == "" then error("unterminated string", 0) end
        if c == quote then return table.concat(parts), i + 1 end
        if c == "\\" then
            local escaped = text:sub(i + 1, i + 1)
            parts[#parts + 1] = ESCAPES[escaped] or escaped
            i = i + 2
        else
            parts[#parts + 1] = c
            i = i + 1
        end
    end
end

local ReadTable

local function ReadValue(text, pos)
    pos = SkipSpace(text, pos)
    local c = text:sub(pos, pos)
    if c == "{" then return ReadTable(text, pos) end
    if c == '"' or c == "'" then return ReadString(text, pos) end
    local number = text:match("^-?%d+%.?%d*", pos)
    if number then return tonumber(number), pos + #number end
    local name = text:match("^[%a_][%w_%.]*", pos)
    if not name then error(("unexpected '%s' at %d"):format(c, pos), 0) end
    if name == "function" then error(("a function at %d"):format(pos), 0) end
    local after = SkipSpace(text, pos + #name)
    if text:sub(after, after) == "(" then error(("a call to %s at %d"):format(name, pos), 0) end
    if name == "true" then return true, after end
    if name == "false" then return false, after end
    if name == "nil" then return nil, after end
    return name, after
end

ReadTable = function(text, pos)
    local out, count = {}, 0
    pos = SkipSpace(text, pos + 1)
    while text:sub(pos, pos) ~= "}" do
        if pos > #text then error("unterminated table", 0) end
        local key, value
        if text:sub(pos, pos) == "[" then
            key, pos = ReadValue(text, pos + 1)
            pos = SkipSpace(text, pos)
            if text:sub(pos, pos) ~= "]" then error(("expected ] at %d"):format(pos), 0) end
            pos = SkipSpace(text, pos + 1)
            if text:sub(pos, pos) ~= "=" then error(("expected = at %d"):format(pos), 0) end
            value, pos = ReadValue(text, pos + 1)
        else
            local name = text:match("^[%a_][%w_]*", pos)
            local after = name and SkipSpace(text, pos + #name)
            if name and text:sub(after, after) == "=" then
                key = name
                value, pos = ReadValue(text, after + 1)
            else
                count = count + 1
                key = count
                value, pos = ReadValue(text, pos)
            end
        end
        out[key] = value
        pos = SkipSpace(text, pos)
        local separator = text:sub(pos, pos)
        if separator == "," or separator == ";" then
            pos = SkipSpace(text, pos + 1)
        elseif separator ~= "}" then
            error(("expected a separator at %d"):format(pos), 0)
        end
    end
    return out, pos + 1
end

function M.ReadTable(text, marker)
    local at = text:find(marker, 1, true)
    if not at then error("no " .. marker, 0) end
    local brace = text:find("{", at, true)
    if not brace then error("no table after " .. marker, 0) end
    return (ReadTable(text, brace))
end

return M
